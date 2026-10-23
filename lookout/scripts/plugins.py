#!/usr/bin/env python3
"""Build the enabled plugins into disposable Agent / Server configuration trees."""
import argparse
import json
from pathlib import Path
import re
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MARKER = '.lookout-generated'


def copy_tree(source, destination):
    if source.is_dir():
        shutil.copytree(source, destination, dirs_exist_ok=True)


def build(names, output):
    if not all(isinstance(name, str) for name in names):
        raise ValueError('插件名稱須為字串')
    if len(set(names)) != len(names):
        raise ValueError('插件名稱不能重複')
    for name in names:
        if not re.fullmatch(r'[a-z][a-z0-9-]*', name) or not (ROOT / 'plugins' / name / 'agent/log-stages.alloy.inc').is_file():
            raise ValueError(f'未知插件：{name}')
    # Only replace our own generated directories. User configuration is never copied or deleted.
    destinations = [output / 'agent/generated', output / 'server/generated']
    for destination in destinations:
        if destination.exists() and (destination.is_symlink() or not (destination / MARKER).is_file()):
            raise ValueError(f'拒絕覆寫非工具管理的目錄：{destination}')
    with tempfile.TemporaryDirectory(prefix='lookout-plugins-') as temporary:
        stage = Path(temporary)
        agent, server = stage / 'agent/generated', stage / 'server/generated'
        agent.mkdir(parents=True)
        server.mkdir(parents=True)
        copy_tree(ROOT / 'server/grafana/dashboards', server / 'dashboards')
        copy_tree(ROOT / 'server/loki/rules', server / 'loki-rules')
        allowed_formats = '|'.join(['raw', 'json', 'logfmt', 'postgres'] + names)
        fragments = ['  stage.match {\n    selector = "{format!~\\\"' + allowed_formats + '\\\"}"\n    action = "drop"\n  }\n']
        for name in names:
            plugin = ROOT / 'plugins' / name
            fragments.append(f'  // Plugin: {name}\n' + (plugin / 'agent/log-stages.alloy.inc').read_text())
            for source, destination in [(plugin / 'grafana/dashboards', server / 'dashboards'), (plugin / 'loki/rules', server / 'loki-rules')]:
                if source.is_dir():
                    for path in source.rglob('*'):
                        if path.is_file() and (destination / path.relative_to(source)).exists():
                            raise ValueError(f'插件檔案名稱衝突：{name}/{path.relative_to(plugin)}')
                    copy_tree(source, destination)
        pipeline = (ROOT / 'agent/alloy/log-pipeline.alloy.tmpl').read_text()
        token = '  // LOOKOUT_PLUGIN_STAGES'
        if pipeline.count(token) != 1:
            raise ValueError('Log pipeline 必須有且只有一個插件插入點')
        (agent / 'log-pipeline.alloy').write_text(pipeline.replace(token, '\n'.join(fragments)))
        # Check dashboard UID conflicts before replacing any output.
        uids = set()
        for path in (server / 'dashboards').glob('*.json'):
            uid = json.loads(path.read_text())['uid']
            if uid in uids:
                raise ValueError(f'Dashboard UID 衝突：{uid}')
            uids.add(uid)
        for directory in (agent, server):
            (directory / MARKER).write_text(json.dumps({'version': (ROOT / 'VERSION').read_text().strip(), 'plugins': names}, indent=2) + '\n')
        changed = False
        for source, destination in zip((agent, server), destinations):
            def contents(directory):
                return {str(path.relative_to(directory)): path.read_bytes() for path in directory.rglob('*') if path.is_file()}
            if destination.exists() and contents(source) == contents(destination):
                continue
            changed = True
            destination.parent.mkdir(parents=True, exist_ok=True)
            if destination.exists():
                shutil.rmtree(destination)
            shutil.copytree(source, destination)
        return changed


def main():
    parser = argparse.ArgumentParser(description='組合核心與選用插件；apply 後的清單即為完整啟用清單，空清單代表停用所有插件。')
    parser.add_argument('command', choices=['apply', 'list'])
    parser.add_argument('plugins', nargs='*')
    parser.add_argument('--output', type=Path, default=ROOT, help='產物根目錄，預設為 lookout/')
    args = parser.parse_args()
    if args.command == 'list':
        print('\n'.join(sorted(path.parent.parent.name for path in (ROOT / 'plugins').glob('*/agent/log-stages.alloy.inc'))))
        return
    try:
        changed = build(args.plugins, args.output.resolve())
    except (ValueError, OSError, KeyError, json.JSONDecodeError) as error:
        parser.exit(1, f'{error}\n')
    print(json.dumps({'changed': changed, 'plugins': args.plugins, 'output': str(args.output.resolve())}, ensure_ascii=False))


if __name__ == '__main__':
    main()
