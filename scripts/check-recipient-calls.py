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


def pointer_key(type_identifier):
    # A view or pure helper can be assigned to a less restricted internal pointer.
    return re.sub(r'(_internal)_(pure|view|nonpayable|payable)(?=\$)', r'\1', type_identifier)


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
    # Imported library bodies participate in the same graph as local code. Solc's
    # referencedDeclaration IDs survive aliases, using-for syntax and inheritance.
    units = {}
    for path, unit in output['sources'].items():
        if path in sources:
            content = sources[path]['content']
        else:
            candidates = (root / path, root / 'node_modules' / path)
            resolved = next((p for p in candidates if p.is_file()), None)
            if resolved is None:
                raise RuntimeError('cannot read imported recipient-call source: ' + path)
            content = resolved.read_text()
        units[path] = (unit['ast'], content.encode())

    nodes = []
    declarations = {}
    references_by_type = {}
    for path, (ast, source) in units.items():
        def visit(node, scope='', owner=None):
            if not isinstance(node, dict):
                return
            kind = node.get('nodeType')
            if kind == 'ContractDefinition':
                scope = node['name']
            if kind in ('FunctionDefinition', 'ModifierDefinition'):
                scope += '.' + (node.get('name') or node.get('kind', 'anonymous'))
                owner = node['id']
                declarations[owner] = (path, node)
            nodes.append((path, source, scope, owner, node))
            for value in node.values():
                if isinstance(value, dict):
                    visit(value, scope, owner)
                elif isinstance(value, list):
                    for child in value:
                        visit(child, scope, owner)
        visit(ast)

    def targets(expression):
        ref = expression.get('referencedDeclaration')
        if ref in declarations:
            return {ref}
        # Internal function values may be assigned, passed or returned. Use a
        # conservative type-compatible set so indirect payout calls cannot escape.
        typ = pointer_key(expression.get('typeDescriptions', {}).get('typeIdentifier', ''))
        return references_by_type.get(typ, set()) if '_internal' in typ else set()

    for _, _, _, _, node in nodes:
        ref = node.get('referencedDeclaration')
        typ = pointer_key(node.get('typeDescriptions', {}).get('typeIdentifier', ''))
        if ref in declarations and typ:
            references_by_type.setdefault(typ, set()).add(ref)

    # Keep overloaded callers distinct: moving a payout into another overload
    # must change the inventory even if its source expression is identical.
    scope_counts = Counter((path, scope) for path, _, scope, owner, node in nodes
                           if node.get('nodeType') in ('FunctionDefinition', 'ModifierDefinition'))
    calls = []
    edges = {fn: set() for fn in declarations}
    # Internal virtual dispatch can resolve to a recipient-bearing override even
    # when the call expression references the harmless base declaration.
    for fn, (_, declaration) in declarations.items():
        for base in declaration.get('baseFunctions', []):
            if base in edges:
                edges[base].add(fn)
    dangerous = set()
    for path, source, scope, owner, node in nodes:
        kind = node.get('nodeType')
        category = None
        destinations = set()
        if kind == 'FunctionCall' and node.get('kind') != 'typeConversion':
            expression = node['expression']
            if expression['nodeType'] == 'FunctionCallOptions':
                expression = expression['expression']
            typ = expression.get('typeDescriptions', {}).get('typeIdentifier', '')
            destinations = targets(expression)
            if re.search(r't_function_(barecall|baredelegatecall|barestaticcall|send|transfer|selfdestruct|creation)', typ):
                category = 'opcode-or-value'
            elif '_external' in typ and typ.startswith('t_function_'):
                category = 'external'
            elif any(declarations[ref][0].endswith('/BoundedCall.sol') for ref in destinations):
                category = 'bounded-wrapper'
        elif kind == 'ModifierInvocation':
            destinations = targets(node['modifierName'])
        elif kind == 'YulFunctionCall' and node.get('functionName', {}).get('name') in (
                'call', 'callcode', 'delegatecall', 'staticcall', 'selfdestruct', 'create', 'create2'):
            category = 'assembly'
        if owner is not None:
            edges[owner].update(destinations)
            if category:
                dangerous.add(owner)
        if category or destinations:
            start, length, _ = map(int, node['src'].split(':'))
            code = normalize_expression(source[start:start+length].decode())
            if owner is not None and scope_counts[(path, scope)] > 1:
                declaration = declarations[owner][1]
                params = declaration.get('parameters', {}).get('parameters', [])
                scope += '(' + ','.join(p.get('typeDescriptions', {}).get('typeString', '')
                                       + ':' + p.get('storageLocation', 'default') for p in params) + ')'
            calls.append((path, scope, category, code, destinations))

    while True:
        expanded = dangerous | {fn for fn, dest in edges.items() if dest & dangerous}
        if expanded == dangerous:
            break
        dangerous = expanded
    return Counter((path, scope, category or 'recipient-helper', code)
                   for path, scope, category, code, destinations in calls
                   if category or destinations & dangerous)


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
    print(f'Recipient-call gate: {sum(current.values())} reviewed expressions; external, value, hook, pointer, assembly and transitive helper calls covered.')
    return 0

if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, OSError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
