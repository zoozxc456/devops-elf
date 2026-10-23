#!/usr/bin/env python3
"""Check local Markdown link targets in tracked and unignored source files.

External URLs and heading fragments are intentionally outside this check.
"""
from pathlib import Path
import re
import subprocess
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[2]
FENCES = re.compile(r'^\s*(`{3,}|~{3,})')
INLINE_LINK = re.compile(r'!?\[[^\]\n]*\]\(\s*(<[^>]+>|[^\s)]+)(?:\s+[^)]*)?\)')
REFERENCE = re.compile(r'^\s{0,3}\[[^\]]+\]:\s*(<[^>]+>|\S+)', re.MULTILINE)


def prose(text):
    """Exclude fenced code examples from link checks."""
    marker = None
    result = []
    for line in text.splitlines():
        fence = FENCES.match(line)
        if fence:
            value = fence.group(1)
            if marker is None:
                marker = value
            elif value[0] == marker[0] and len(value) >= len(marker):
                marker = None
            continue
        if marker is None:
            result.append(line)
    return '\n'.join(result)


def main():
    output = subprocess.check_output(
        ['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'],
        cwd=ROOT,
    )
    documents = sorted({ROOT / name for name in output.decode().split('\0')
                        if name.endswith('.md')})
    errors = []
    links = 0
    for document in documents:
        text = prose(document.read_text(encoding='utf-8'))
        targets = [m.group(1) for pattern in (INLINE_LINK, REFERENCE)
                   for m in pattern.finditer(text)]
        for target in targets:
            url = urlsplit(target.strip('<>'))
            if url.scheme or url.netloc or not url.path:
                continue
            links += 1
            path = unquote(url.path)
            destination = ROOT / path.lstrip('/') if path.startswith('/') else document.parent / path
            if not destination.exists():
                errors.append(f'{document.relative_to(ROOT)}: missing target {target}')
    for error in errors:
        print(error)
    print(f'Checked {links} local links in {len(documents)} Markdown files; {len(errors)} errors.')
    return bool(errors)


if __name__ == '__main__':
    raise SystemExit(main())
