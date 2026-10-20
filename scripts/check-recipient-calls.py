#!/usr/bin/env python3
"""Fail on unreviewed external-call expressions anywhere under contracts/.

Uses a fresh compiler AST (no bytecode build). This deliberately includes protocol
calls, constructors, mocks and views so a type alias, function pointer, new wrapper,
receiver hook or assembly call cannot bypass a receiver-name heuristic. The manifest
pins multiplicity and the complete expression, including recipient and calldata.
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tomllib

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'scripts/recipient-call-manifest.json'


def normalize_expression(code):
    # Preserve literal bytes while ignoring comments and formatting outside literals.
    literals = r"\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'"
    code = re.sub(literals + r'|/\*[\s\S]*?\*/|//[^\n]*',
                  lambda m: m[0] if m[0][0] in ('"', "'") else ' ', code)
    return re.sub(literals + r'|\s+',
                  lambda m: m[0] if m[0][0] in ('"', "'") else ' ', code).strip()


def discover(root=ROOT):
    sources = {p.relative_to(root).as_posix(): {'content': p.read_text()}
               for p in sorted((root / 'contracts').rglob('*.sol'))}
    config = root / 'foundry.toml'
    version = tomllib.loads(config.read_text()).get('profile', {}).get('default', {}).get('solc_version') if config.exists() else None
    installed = Path.home() / '.svm' / str(version) / f'solc-{version}'
    compiler = str(installed) if installed.is_file() else shutil.which('solc')
    if not compiler:
        raise RuntimeError('solc is required for the recipient-call source gate')
    request = {'language': 'Solidity', 'sources': sources,
               'settings': {'outputSelection': {'*': {'': ['ast']}}}}
    result = subprocess.run([compiler, '--base-path', str(root), '--include-path', str(root / 'node_modules'),
                             '--standard-json'], input=json.dumps(request), text=True, capture_output=True, cwd=root)
    output = json.loads(result.stdout)
    errors = [e['formattedMessage'] for e in output.get('errors', []) if e['severity'] == 'error']
    if result.returncode or errors:
        raise RuntimeError('\n'.join(errors) or result.stderr)
    sites = []
    for path, unit in output['sources'].items():
        if path not in sources:
            continue
        source = sources[path]['content'].encode()
        def visit(node, scope=''):
            if not isinstance(node, dict):
                return
            kind = node.get('nodeType')
            if kind == 'ContractDefinition':
                scope = node['name']
            if kind in ('FunctionDefinition', 'ModifierDefinition'):
                scope += '.' + (node.get('name') or node.get('kind', 'anonymous'))
            category = None
            if kind == 'FunctionCall' and node.get('kind') != 'typeConversion':
                expression = node['expression']
                if expression['nodeType'] == 'FunctionCallOptions':
                    expression = expression['expression']
                typ = expression.get('typeDescriptions', {}).get('typeIdentifier', '')
                if re.search(r't_function_(barecall|baredelegatecall|barestaticcall|send|transfer|selfdestruct|creation)', typ):
                    category = 'opcode-or-value'
                elif '_external' in typ and typ.startswith('t_function_'):
                    category = 'external'
                elif expression.get('nodeType') == 'MemberAccess' and expression.get('expression', {}).get('name') == 'BoundedCall':
                    category = 'bounded-wrapper'
            elif kind == 'YulFunctionCall' and node.get('functionName', {}).get('name') in ('call', 'callcode', 'delegatecall', 'staticcall', 'selfdestruct', 'create', 'create2'):
                category = 'assembly'
            if category:
                start, length, _ = map(int, node['src'].split(':'))
                code = source[start:start+length].decode()
                code = normalize_expression(code)
                sites.append((path, scope, category, code))
            for value in node.values():
                if isinstance(value, dict):
                    visit(value, scope)
                elif isinstance(value, list):
                    for child in value:
                        visit(child, scope)
        visit(unit['ast'])
    return Counter(sites)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--dump', action='store_true', help='print discovered sites for review; never updates the manifest')
    args = p.parse_args()
    current = discover()
    if args.dump:
        print(json.dumps([{'path': a, 'scope': b, 'kind': c, 'expression': d, 'count': count}
                          for (a, b, c, d), count in sorted(current.items())], indent=2))
        return 0
    rows = json.loads(MANIFEST.read_text())
    expected = Counter()
    for row in rows:
        if not row.get('review', '').strip():
            raise RuntimeError('manifest entry has no reachability review: ' + row['scope'])
        key = tuple(row[k] for k in ('path', 'scope', 'kind', 'expression'))
        if key in expected:
            raise RuntimeError('duplicate manifest entry: ' + row['scope'])
        expected[key] = row['count']
    for label, delta in [('UNREVIEWED', current-expected), ('STALE', expected-current)]:
        for (path, scope, kind, code), count in sorted(delta.items()):
            print(f'{label} x{count}: {path} {scope} [{kind}] {code}')
    if current != expected:
        return 1
    print(f'Recipient-call gate: {sum(current.values())} reviewed expressions; external, value, hook, pointer and assembly calls covered.')
    return 0

if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, OSError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
