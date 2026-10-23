#!/usr/bin/env python3
"""Manage an IAP config without executing configuration text."""
import argparse
import copy
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile

RESERVED = set('export help setup new remove reset uninstall ls list show edit import to-yaml version update self-update names'.split())


def confirm(message):
    print(message + ' [y/N]: ', end='', file=sys.stderr, flush=True)
    answer = sys.stdin.readline()
    return answer.strip().lower() in ('y', 'yes')


def read_data(path):
    text = path.read_bytes().decode('utf-8-sig')
    if path.suffix in ('.json', '.yaml', '.yml'):
        try:
            data = json.loads(text)
        except ValueError:
            if path.suffix == '.json':
                raise
            try:
                import yaml
                data = yaml.safe_load(text)
            except ImportError:
                data = json.loads(subprocess.check_output(['yq', '-o=json', '.', str(path)], text=True))
        if not isinstance(data, dict) or not isinstance(data.get('hosts'), dict):
            raise ValueError('設定必須包含 hosts map。')
        return data
    return text


def blocks(text):
    lines = text.splitlines(keepends=True)
    starts = [(i, line.split()[0]) for i, line in enumerate(lines)
              if line.strip() and not line.lstrip().startswith(('#', '>'))]
    return lines, [(name, start, starts[i + 1][0] if i + 1 < len(starts) else len(lines))
                   for i, (start, name) in enumerate(starts)]


def validate(data):
    if isinstance(data, dict):
        entries = data['hosts'].items()
    else:
        parsed = []
        for line in data.splitlines():
            if not line.strip() or line.lstrip().startswith(('#', '>')):
                continue
            fields = line.split()
            if not 5 <= len(fields) <= 7:
                raise ValueError('每組設定必須包含 name type project zone instance [remote_port] [local_port]。')
            name, kind, project, zone, instance, *ports = fields
            host = dict(type=kind, project=project, zone=zone, instance=instance)
            if ports:
                host.update(remote_port=ports[0], local_port=ports[-1])
            parsed.append((name, host))
        entries = parsed
    seen = set()
    for name, host in entries:
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', name) or name in RESERVED or name in seen:
            raise ValueError('連線名稱無效、重複或為保留指令：' + name)
        seen.add(name)
        host = host or {}
        if not isinstance(host, dict) or host.get('type', 'ssh') not in ('ssh', 'tunnel'):
            raise ValueError('type 只支援 ssh / tunnel。')
        for key in ('project', 'zone'):
            value = host.get(key, '-')
            if not isinstance(value, str) or not re.fullmatch(r'-|[A-Za-z0-9][A-Za-z0-9._-]*', value):
                raise ValueError('無效欄位：' + key)
        instance = host.get('instance', name)
        if not isinstance(instance, str) or not re.fullmatch(r'([A-Za-z0-9._-]+@)?[A-Za-z0-9][A-Za-z0-9._-]*', instance):
            raise ValueError('無效 instance。')
        if host.get('type', 'ssh') == 'tunnel':
            if '@' in instance:
                raise ValueError('Tunnel instance 不可包含使用者。')
            for value in (host.get('remote_port'), host.get('local_port', host.get('remote_port'))):
                if not re.fullmatch(r'[1-9][0-9]{0,4}', str(value)) or int(value) > 65535:
                    raise ValueError('Tunnel port 必須為 1–65535。')
    return seen


def publish(path, original, content):
    if path.is_symlink() or path.read_bytes() != original:
        raise ValueError('設定在操作期間已變更，未寫入，請重試。')
    fd, backup = tempfile.mkstemp(prefix=path.name + '.backup-', dir=path.parent)
    with os.fdopen(fd, 'wb') as stream:
        stream.write(original)
    fd, staged = tempfile.mkstemp(prefix=path.name + '.tmp-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(content)
        os.replace(staged, path)
    finally:
        if os.path.exists(staged):
            os.unlink(staged)
    print('原檔備份：' + backup)
    print('已更新：' + str(path))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=('remove', 'edit', 'reset', 'uninstall'))
    parser.add_argument('name', nargs='?')
    parser.add_argument('--config', required=True, type=Path)
    parser.add_argument('--bin-dir', required=True, type=Path)
    args = parser.parse_args()
    if args.action in ('remove', 'edit') and not args.name:
        parser.error(args.action + ' 需要指定連線名稱。')
    if args.action in ('reset', 'uninstall') and args.name:
        parser.error(args.action + ' 不接受連線名稱。')
    if args.action == 'uninstall':
        root = args.bin_dir
        if not (root / '.iap/scripts/manage.py').is_file():
            raise ValueError('只能從複製安裝的 iap 執行 uninstall；不會刪除原始碼。')
        if not confirm(f'移除 {root / "iap"} 與 Bash 配套檔案；保留連線設定 {args.config}，是否繼續？'):
            return
        for relative in ('iap', '.iap/scripts/setup.sh', '.iap/scripts/manage.py', '.iap/completions/iap.bash', '.iap/bash-source'):
            path = root / relative
            if path.is_file() or path.is_symlink():
                path.unlink()
        for relative in ('.iap/scripts', '.iap/completions', '.iap'):
            try:
                (root / relative).rmdir()
            except OSError:
                pass
        print('已解除安裝 Bash iap，連線設定已保留。請自行移除 shell rc 中的補全設定。')
        return
    path = args.config
    if path.is_symlink() or not path.is_file():
        raise ValueError('找不到設定檔或目標不是一般檔案：' + str(path))
    original = path.read_bytes()
    data = read_data(path)
    if isinstance(data, dict):
        names = list(data['hosts'])
    else:
        lines, groups = blocks(data)
        names = [name for name, _, _ in groups]
    if args.action in ('edit', 'remove') and names.count(args.name) != 1:
        raise ValueError('找不到唯一連線：' + args.name)
    if args.action == 'reset':
        if not confirm(f'清空 {path} 的全部 {len(names)} 組連線，先備份並保留 defaults，是否繼續？'):
            return
        if isinstance(data, dict):
            data['hosts'] = {}
        else:
            data = '# IAP hosts — reset\n'
    elif args.action == 'remove':
        if not confirm(f'從 {path} 移除連線 {args.name} 與其入口，是否繼續？'):
            return
        if isinstance(data, dict):
            del data['hosts'][args.name]
        else:
            _, start, end = next(group for group in groups if group[0] == args.name)
            # Keep comments and blank lines attached to the following entry.
            kept = [line for line in lines[start + 1:end] if not line.lstrip().startswith('>')]
            data = ''.join(lines[:start] + kept + lines[end:])
    else:
        if isinstance(data, dict):
            isolated = {'hosts': {args.name: copy.deepcopy(data['hosts'][args.name])}}
            if 'defaults' in data:
                isolated['defaults'] = data['defaults']
            payload = json.dumps(isolated, ensure_ascii=False, indent=2) + '\n'
            suffix = '.json'
        else:
            _, start, end = next(group for group in groups if group[0] == args.name)
            payload = ''.join(lines[start:end])
            suffix = '.hosts'
        with tempfile.TemporaryDirectory(prefix='iap-edit-') as work:
            edited = Path(work) / ('connection' + suffix)
            edited.write_text(payload, encoding='utf-8')
            edited.chmod(0o600)
            editor = shlex.split(os.environ.get('EDITOR', 'vi'))
            subprocess.run(editor + [str(edited)], check=True)
            changed = read_data(edited)
            changed_names = validate(changed)
            if changed_names != {args.name}:
                raise ValueError('只能修改指定連線，請保留原本的連線名稱。')
            if isinstance(data, dict):
                if changed.get('defaults', {}) != data.get('defaults', {}):
                    raise ValueError('修改特定連線時不可變更 defaults。')
                if changed['hosts'][args.name] == data['hosts'][args.name]:
                    print('沒有變更。'); return
                data['hosts'][args.name] = changed['hosts'][args.name]
            else:
                text = edited.read_text(encoding='utf-8')
                if text == payload:
                    print('沒有變更。'); return
                data = ''.join(lines[:start]) + text.rstrip('\n') + '\n' + ''.join(lines[end:])
        if not confirm(f'儲存 {args.name} 的修改到 {path}（先備份），是否繼續？'):
            return
    content = (json.dumps(data, ensure_ascii=False, indent=2) + '\n') if isinstance(data, dict) else data
    publish(path, original, content.encode('utf-8'))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print('iap: ' + str(error), file=sys.stderr)
        sys.exit(1)
