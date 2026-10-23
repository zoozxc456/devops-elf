#!/usr/bin/env python3
"""Check and advance the Lookout version and release notes; never commits or tags."""
import argparse
from datetime import date, datetime, timedelta, timezone
import difflib
import os
from pathlib import Path
import re
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SEMVER = r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
HEADING = re.compile(r'^## \[([^\]]+)\](?: - (\d{4}-\d{2}-\d{2}))?\s*$', re.MULTILINE)


def inspect(root):
    version = (root / 'VERSION').read_text().strip()
    if not re.fullmatch(SEMVER, version):
        raise ValueError('VERSION 必須為 major.minor.patch，不能包含 v 前綴或前導零')
    changelog = (root / 'CHANGELOG.md').read_text()
    headings = list(HEADING.finditer(changelog))
    if len(headings) < 2 or headings[0].group(1) != 'Unreleased' or headings[0].group(2):
        raise ValueError('CHANGELOG.md 第一筆必須是 ## [Unreleased]，且至少有一筆正式版本')
    versions = []
    for heading in headings[1:]:
        value, released = heading.groups()
        if not re.fullmatch(SEMVER, value) or not released:
            raise ValueError('正式版本標題必須為 ## [major.minor.patch] - YYYY-MM-DD')
        date.fromisoformat(released)
        versions.append(tuple(map(int, value.split('.'))))
    if versions != sorted(set(versions), reverse=True):
        raise ValueError('CHANGELOG.md 版本必須由新至舊排列，且不可重複')
    if headings[1].group(1) != version:
        raise ValueError('VERSION 與 CHANGELOG.md 最新正式版本不一致')
    return version, changelog, headings


def bump(root, part, released, dry_run=False):
    version, changelog, headings = inspect(root)
    notes = changelog[headings[0].end():headings[1].start()].strip()
    if not notes:
        raise ValueError('請先在 CHANGELOG.md 的 [Unreleased] 填寫本次變更，再更新版本')
    if released < date.fromisoformat(headings[1].group(2)):
        raise ValueError('新版本日期不能早於上一版')
    numbers = list(map(int, version.split('.')))
    index = {'major': 0, 'minor': 1, 'patch': 2}[part]
    numbers[index] += 1
    for following in range(index + 1, 3):
        numbers[following] = 0
    updated = '.'.join(map(str, numbers))
    new_changelog = (changelog[:headings[0].start()] + '## [Unreleased]\n\n'
                     + f'## [{updated}] - {released.isoformat()}\n\n' + notes + '\n\n'
                     + changelog[headings[1].start():])
    changes = [(root / 'VERSION', updated + '\n'), (root / 'CHANGELOG.md', new_changelog)]
    if dry_run:
        for path, content in changes:
            print(''.join(difflib.unified_diff(path.read_text().splitlines(True), content.splitlines(True),
                                             fromfile=path.name, tofile=path.name)), end='')
        return updated
    # Stage both documents before replacing either. A later check detects interrupted updates.
    staged = []
    try:
        for path, content in changes:
            with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', newline='\n', dir=root,
                                             prefix='.version-', delete=False) as temporary:
                staged.append((Path(temporary.name), path))
                temporary.write(content)
            os.chmod(temporary.name, path.stat().st_mode & 0o777)
        for temporary, path in staged:
            os.replace(temporary, path)
    finally:
        for temporary, _ in staged:
            if temporary.exists():
                temporary.unlink()
    return updated


def main():
    parser = argparse.ArgumentParser(description='Lookout 版本管理，只修改 VERSION 與 CHANGELOG.md，不執行 Git 操作。')
    commands = parser.add_subparsers(dest='command')
    commands.add_parser('show', help='顯示目前版本')
    commands.add_parser('check', help='檢查版本與變更紀錄是否一致')
    release = commands.add_parser('bump', help='將 Unreleased 移入下一個版本')
    release.add_argument('part', choices=['major', 'minor', 'patch'])
    release.add_argument('--date', type=date.fromisoformat,
                         default=datetime.now(timezone(timedelta(hours=8))).date(), help='發版日期，預設 UTC+8 當天日期')
    release.add_argument('--dry-run', action='store_true', help='只顯示預計變更，不寫入檔案')
    args = parser.parse_args()
    try:
        if args.command == 'bump':
            version = bump(ROOT, args.part, args.date, args.dry_run)
            if not args.dry_run:
                print(f'Lookout {version}（已更新 VERSION 與 CHANGELOG.md；尚未建立 Git tag）')
        else:
            version, _, _ = inspect(ROOT)
            print(f'Lookout {version}' + ('：版本與變更紀錄一致' if args.command == 'check' else ''))
    except (OSError, ValueError) as error:
        parser.exit(1, f'{error}\n')


if __name__ == '__main__':
    main()
