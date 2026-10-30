#!/usr/bin/env python3
"""Check Markdown links, repository path references, formatting and build entry-point files.

Generated output paths and shell variables are not input files. The temporary audit-prep
report is a deletion inventory, so only its formatting is checked. External URLs are not fetched.
"""
import glob
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
PATH = re.compile(r'(?<![\w/])(?:contracts|scripts|test|docs|deployments|\.github)/[\w.*?{}+/@-]+(?:\.[\w.-]+)?')


def anchors(text):
    result = set()
    counts = {}
    fence = False
    for line in text.splitlines():
        if line.startswith('```'):
            fence = not fence
        elif not fence and re.match(r'^#{1,6} ', line):
            title = re.sub(r'^#+\s+', '', line).strip().lower()
            title = re.sub(r'[^\w\- ]', '', title).replace(' ', '-')
            count = counts.get(title, 0)
            counts[title] = count + 1
            result.add(title + (f'-{count}' if count else ''))
    result.update(re.findall(r'<a\s+(?:id|name)=["\']([^"\']+)', text))
    return result


def check_path(raw, source, errors):
    raw = raw.rstrip('.,;:')
    if any(x in raw for x in ('<', '>', '$', '{', '}')):
        return
    # A trailing slash and globs are valid only if they resolve in the checkout.
    if not glob.glob(str(ROOT / raw)):
        errors.append(f'{source}: missing repository path {raw}')


def main():
    # Tracked plus untracked-but-not-ignored: what a commit would publish, never local ignored notes.
    listed = subprocess.check_output(
        ['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], cwd=ROOT
    ).decode().split('\0')
    files = {ROOT / p for p in listed if p.endswith('.md') and (ROOT / p).is_file()}
    errors = []
    for path in sorted(files):
        name = path.relative_to(ROOT).as_posix()
        content = path.read_text()
        fence = False
        h1 = 0
        previous = 0
        for i, line in enumerate(content.splitlines(), 1):
            if line != line.rstrip():
                errors.append(f'{name}:{i}: trailing whitespace')
            if line.startswith('```'):
                if not fence and line == '```':
                    errors.append(f'{name}:{i}: fence needs a language')
                fence = not fence
                continue
            if not fence and not line.startswith('|') and len(line) > 120:
                if max(map(len, line.split()), default=0) <= 100:
                    errors.append(f'{name}:{i}: wrap prose near 100 columns')
            if not fence and (m := re.match(r'^(#{1,6}) ', line)):
                level = len(m[1]); h1 += level == 1
                if previous and level > previous + 1:
                    errors.append(f'{name}:{i}: heading skips a level')
                previous = level
        if fence:
            errors.append(f'{name}: unclosed code fence')
        if h1 != 1:
            errors.append(f'{name}: expected one H1, got {h1}')
        if name == 'AUDITPREP-REPORT.md':
            continue
        for match in re.finditer(r'\[[^\]]*\]\(([^)\n]+)\)', content):
            target = match[1].strip().strip('<>')
            if urlsplit(target).scheme or target.startswith('//'):
                continue
            local, _, fragment = unquote(target).partition('#')
            dest = (path.parent / local).resolve() if local else path
            if not dest.exists():
                errors.append(f'{name}: broken link {target}')
            elif fragment and dest.suffix == '.md' and fragment not in anchors(dest.read_text()):
                errors.append(f'{name}: missing anchor {target}')
        for match in PATH.finditer(content):
            # Markdown link destinations relative to the document are checked above.
            if match.start() and content[match.start()-1] in '/.':
                continue
            check_path(match[0], name, errors)
        # Inline source basenames are valid navigation hints when present in the source tree.
        for basename in re.findall(r'`([\w-]+\.(?:sol|py|js|sh))`', content):
            if not any(next((ROOT / d).rglob(basename), None) for d in ('contracts', 'scripts', 'test')):
                errors.append(f'{name}: missing source basename {basename}')
    consumers = [ROOT / 'Makefile', ROOT / 'package.json', *sorted((ROOT / '.github/workflows').glob('*'))]
    for path in consumers:
        text = path.read_text()
        for match in PATH.finditer(text):
            raw = match[0]
            # A literal prefix before a variable/template is a directory, not a full filename.
            if match.end() < len(text) and text[match.end()] in '${':
                continue
            check_path(raw, path.relative_to(ROOT), errors)
    for error in sorted(set(errors)):
        print(error, file=sys.stderr)
    if errors:
        print(f'{len(set(errors))} documentation/build-reference errors.', file=sys.stderr)
        return 1
    print(f'Checked {len(files)} Markdown files and {len(consumers)} build/CI entry points.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
