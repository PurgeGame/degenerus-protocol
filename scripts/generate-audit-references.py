#!/usr/bin/env python3
"""Generate the EIP-170 dispatch map and compiler layout appendix without bytecode compilation."""
import argparse
from collections import defaultdict
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts/lib'))
from audit_scope import inventory


def walk(node):
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from walk(value)
    elif isinstance(node, list):
        for value in node:
            yield from walk(value)


def compile_sources(output):
    sources = {p.relative_to(ROOT).as_posix(): {'content': p.read_text()}
               for p in (ROOT / 'contracts').rglob('*.sol')}
    sources['AuditNamespaceLayouts.sol'] = {'content': '''pragma solidity 0.8.38;
import {DegenerusQuests} from "contracts/DegenerusQuests.sol";
import {DegenerusAffiliate} from "contracts/DegenerusAffiliate.sol";
contract AuditNamespaceLayouts {
    DegenerusQuests.DegenerusQuestsStorage quests;
    DegenerusAffiliate.DegenerusAffiliateStorage affiliate;
}
'''}
    request = {'language': 'Solidity', 'sources': sources, 'settings': {
        'outputSelection': {'*': {'': ['ast'], '*': ['storageLayout', 'evm.methodIdentifiers']}}}}
    compiler = os.environ.get('SOLC', str(Path.home() / '.svm/0.8.38/solc-0.8.38'))
    result = subprocess.run([compiler, '--base-path', str(ROOT), '--include-path', str(ROOT / 'node_modules'),
                             '--standard-json'], input=json.dumps(request), text=True, capture_output=True, check=True)
    compiled = json.loads(result.stdout)
    errors = [e['formattedMessage'] for e in compiled.get('errors', []) if e['severity'] == 'error']
    if errors:
        raise ValueError('\n'.join(errors))
    output.write_text(result.stdout)
    return compiled


class Reference:
    def __init__(self, compiled):
        self.compiled = compiled
        self.nodes, self.paths, self.owners, self.contracts = {}, {}, {}, {}
        for path, unit in compiled['sources'].items():
            for node in walk(unit['ast']):
                if 'id' in node:
                    self.nodes[node['id']] = node
                    self.paths[node['id']] = path
                if node.get('nodeType') == 'ContractDefinition':
                    self.contracts[node['name']] = node
                    for child in node['nodes']:
                        self.owners[child['id']] = node['name']
        self.rows = json.loads((ROOT / 'deployments/eip170.json').read_text())['deployments']
        self.hosts = {alias: row['contract'] for row in self.rows for alias in row['aliases']}
        self.methods = {name: item['evm']['methodIdentifiers'] for cs in compiled['contracts'].values()
                        for name, item in cs.items()}
        self.source = {path: (ROOT / path).read_text() for path in compiled['sources'] if (ROOT / path).is_file()}
        self.active = {}
        for name, contract in self.contracts.items():
            functions = {}
            for base_id in contract['linearizedBaseContracts']:
                for node in self.nodes[base_id]['nodes']:
                    if node['nodeType'] == 'FunctionDefinition' and node.get('implemented'):
                        key = self.key(node)
                        functions.setdefault(key, node)
            self.active[name] = functions

    @staticmethod
    def key(fn):
        return (fn['name'], tuple(p['typeDescriptions']['typeString'] for p in fn['parameters']['parameters']))

    def text(self, node):
        start, length, _ = map(int, node['src'].split(':'))
        # solc source spans count UTF-8 bytes, not Python characters.
        return self.source[self.paths[node['id']]].encode()[start:start + length].decode()

    def link(self, node):
        return f"[{self.owners.get(node['id'], '')}.{node.get('name', '')}](../{self.paths[node['id']]})"

    def function(self, host, selector):
        return next((f for f in self.active[host].values() if f.get('functionSelector') == selector), None)

    def routes(self, host, fn, selector, seen=None, arguments=None):
        seen = set() if seen is None else seen
        stamp = (host, fn['id'], selector, repr(arguments))
        if stamp in seen:
            return set()
        seen.add(stamp)
        body = fn.get('body') or {}
        values = dict(arguments or {})
        assignments = defaultdict(list)
        for n in walk(body):
            if n.get('nodeType') == 'VariableDeclarationStatement' and n.get('initialValue'):
                for decl in n['declarations']:
                    if decl:
                        assignments[decl['id']].append(n['initialValue'])
            if n.get('nodeType') == 'Assignment':
                ref = n['leftHandSide'].get('referencedDeclaration')
                if ref:
                    assignments[ref].append(n['rightHandSide'])

        def value(expr, visiting=None):
            visiting = set() if visiting is None else visiting
            if not isinstance(expr, dict):
                return set()
            ref = expr.get('referencedDeclaration')
            if expr.get('memberName') == 'data' and expr.get('expression', {}).get('name') == 'msg':
                return {selector}
            if expr.get('memberName') == 'selector':
                target = self.nodes.get(expr.get('expression', {}).get('referencedDeclaration'), {})
                return {target['functionSelector']} if 'functionSelector' in target else set()
            if expr.get('expression', {}).get('name') == 'ContractAddresses':
                return {expr['memberName']}
            if ref in values:
                return values[ref]
            if ref in assignments and ref not in visiting:
                return set().union(*(value(e, visiting | {ref}) for e in assignments[ref]))
            if expr.get('nodeType') == 'FunctionCall' and expr['expression'].get('memberName') == 'encodeWithSelector':
                return value(expr['arguments'][0], visiting)
            if expr.get('nodeType') == 'Conditional':
                return value(expr['trueExpression'], visiting) | value(expr['falseExpression'], visiting)
            return set()

        result = set()
        for n in walk(body):
            if n.get('nodeType') != 'FunctionCall':
                continue
            expr = n['expression']
            if expr.get('nodeType') == 'FunctionCallOptions':
                expr = expr['expression']
            args = n['arguments']
            target, selectors = set(), set()
            if expr.get('name') == '_componentDelegate':
                target, selectors = value(args[0]), value(args[1])
            elif expr.get('memberName') == 'delegatecall':
                target, selectors = value(expr['expression']), value(args[0])
            elif expr.get('name') == '_delegateLifecycle':
                target, selectors = {'CRAPS_LIFECYCLE_MODULE'}, {selector}
            else:
                ref = self.nodes.get(expr.get('referencedDeclaration'), {})
                if ref.get('nodeType') == 'FunctionDefinition' and expr.get('nodeType') == 'Identifier':
                    actual = self.active[host].get(self.key(ref), ref)
                    params = {p['id']: value(a) for p, a in zip(actual['parameters']['parameters'], args)}
                    result |= self.routes(host, actual, selector, seen, params)
                continue
            if not target or not selectors:
                raise ValueError(f"Unresolved delegate route: {host}.{fn['name']}: {self.text(n)}")
            for sel in selectors:
                matches = [alias for alias in target if alias in self.hosts
                           and (fn['name'] != '_mineFlip' or alias.startswith('GAME_'))
                           and self.function(self.hosts[alias], sel)]
                if not matches:
                    # The miner also dispatches external workers via the same local calldata variable.
                    if fn['name'] == '_mineFlip':
                        continue
                    raise ValueError(f"Missing target selector: {host}.{fn['name']} {target} {sel}")
                for alias in matches:
                    result.add((self.hosts[alias], sel))
        return result

    def module_map(self):
        lines = ['# EIP-170 module map', '',
                 'Generated from the compiler AST, inheritance order, ABI selectors and deployment aliases by',
                 '[generate-audit-references.py](../scripts/generate-audit-references.py). The tables enumerate',
                 'external/public entries, including generated getters. A route is a possible edge, not a promise',
                 'that every branch executes. Follow the destination host table for nested delegatecalls.', '',
                 'Game delegates retain Game storage; Craps lifecycle delegates retain CrapsBattle storage.',
                 'Ordinary external calls (including the stateless Craps engine) are separate call contexts.',
                 'An exposed worker selector does not imply permission to call that worker directly; inspect guards.', '',
                 '```sh', 'python3 scripts/generate-audit-references.py --output-dir "$AUDIT_SCRATCH/references"',
                 'python3 scripts/generate-audit-references.py --output-dir "$AUDIT_SCRATCH/references" --check',
                 '```', '',
                 'Set `AUDIT_SCRATCH` as in [Testing](TESTING.md). The compiler output stays in that directory.', '']
        game_modules = [r['contract'] for r in self.rows if r['key'].startswith('GAME_')]
        groups = [
            ('Game facade', ['DegenerusGame']),
            ('Game delegates', game_modules),
            ('Craps table, lifecycle and engine', ['CrapsBattle', 'Eip170JackpotBattle', 'Eip170CrapsEngine']),
            ('Credits and side games', ['Coinflip', 'Eip170Quests', 'Eip170Affiliate',
                                       'DegenerusJackpots', 'DegenerusParimutuel', 'DegenerusRecordBounty']),
            ('Custody, governance and tokens', ['DegenerusVault', 'DegenerusVaultShare',
                'sDGNRS', 'DGNRS', 'DegenerusAdmin', 'GNRUS', 'FLIP', 'WWXRP',
                'DegenerusOwnerGovernance', 'DegenerusDeityPass', 'AFKingSubscriptionToken']),
            ('Readers and display dependencies', ['DegenerusGameLens', 'CrapsLens', 'DeityBoonViewer',
                                                  'Icons32Data', 'DeityPassCustomizationRenderer']),
        ]
        listed = [host for _, hosts in groups for host in hosts]
        assert len(listed) == len(set(listed)), 'duplicate host'
        assert set(self.hosts.values()) <= set(listed), 'unmapped deployment host'
        area_of = {hosts[0]: area for area, hosts in groups}
        for host in listed:
            if host in area_of:
                lines += [f'## {area_of[host]}', '']
            aliases = ', '.join(a for a, h in self.hosts.items() if h == host)
            if not aliases:
                aliases = ('created by Vault constructor (DGVE and DGVF)' if host == 'DegenerusVaultShare'
                           else 'optional reader/renderer')
            lines += [f'### {host}', '', f'Deployment aliases: `{aliases}`.', '',
                      '| External entry (selector) | Implementing function | Direct delegate destinations |',
                      '| --- | --- | --- |']
            for signature, selector in sorted(self.methods[host].items()):
                fn = self.function(host, selector)
                if fn:
                    routes = self.routes(host, fn, selector)
                    destinations = []
                    for target, sel in sorted(routes):
                        tf = self.function(target, sel)
                        destinations.append(f'[{target}](#{target.lower()}).`{tf["name"]}`')
                    impl = self.link(fn)
                else:
                    destinations = []
                    impl = 'Compiler-generated getter'
                lines.append(f'| `{signature}` (`0x{selector}`) | {impl} | '+('; '.join(destinations) or 'None')+' |')
            for fn in self.active[host].values():
                if fn.get('kind') in ('receive', 'fallback'):
                    routes = self.routes(host, fn, '')
                    if routes:
                        raise ValueError(f'Unnamed entry needs explicit dispatch rendering: {host}')
                    impl = f"[{self.owners[fn['id']]}.{fn['kind']}](../{self.paths[fn['id']]})"
                    lines.append(f"| `{fn['kind']}()` (no selector) | {impl} | None |")
            lines += ['']
        return '\n'.join(lines)

    def layouts(self):
        lines = ['## Compiler storage layouts', '',
                 'Slots and offsets below come from solc 0.8.38 `storageLayout`. Bits count from the',
                 'least significant bit of each 256-bit slot. Mapping/array rows identify their root slots;',
                 'their elements use Solidity hashed/indexed addressing. Struct slots are relative to the',
                 'struct base. Only structs used in storage appear here; memory-only work structs do not pack',
                 'their fields into storage. Namespaced Quests/Affiliate layouts use a temporary compiler',
                 'harness declaring the production struct types, without changing production sources.', '']
        names = ['DegenerusGame', 'CrapsBattle', 'Coinflip', 'sDGNRS']
        names += [r['contract'] for r in self.rows if not r['key'].startswith('GAME_') and r['contract'] not in names]
        names += ['DeityPassCustomizationRenderer', 'DegenerusVaultShare', 'AuditNamespaceLayouts']
        struct_seen = set()
        for name in names:
            artifact = next(cs[name] for cs in self.compiled['contracts'].values() if name in cs)
            layout = artifact['storageLayout']
            if not layout['storage']:
                continue
            if name != 'AuditNamespaceLayouts':
                lines += [f'### {name}', '', '| Slot | Bits | Field | Type |', '| --- | --- | --- | --- |']
            else:
                lines += ['### Namespaced storage types', '']
            types = layout['types']
            for row in (layout['storage'] if name != 'AuditNamespaceLayouts' else []):
                t = types[row['type']];start = row['offset'] * 8;size = int(t['numberOfBytes']) * 8
                bits = f'{start}–{start+size-1}' if size <= 256 else 'root / multiple slots'
                lines.append(f'| {row["slot"]} | {bits} | `{row["label"]}` | `{t["label"]}` |')
            lines += ['']
            for t in types.values():
                if 'members' not in t or t['label'] in struct_seen:
                    continue
                struct_seen.add(t['label'])
                lines += [f'#### {t["label"]}', '', '| Relative slot | Bits | Member | Type |', '| --- | --- | --- | --- |']
                for row in t['members']:
                    mt=types[row['type']]; start=row['offset']*8;size=int(mt['numberOfBytes'])*8
                    bits=f'{start}–{start+size-1}' if size<=256 else 'root / multiple slots'
                    lines.append(f'| {row["slot"]} | {bits} | `{row["label"]}` | `{mt["label"]}` |')
                lines+=['']
        return '\n'.join(lines)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--check', action='store_true')
    args=parser.parse_args()
    os.chdir(ROOT)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    ref=Reference(compile_sources(args.output_dir/'compiler.json'))
    module=ref.module_map()
    packing=ROOT/'docs/STORAGE-PACKING.md'
    marker='<!-- compiler-layouts -->'
    intro=packing.read_text().split(marker)[0] if packing.exists() else '# Storage packing\n\n'
    outputs={ROOT/'docs/MODULE-MAP.md':module,packing:intro+marker+'\n\n'+ref.layouts()}
    for path, content in outputs.items():
        content=content.rstrip()+'\n'
        if args.check:
            if not path.exists() or path.read_text()!=content:
                raise ValueError(f'Stale generated reference: {path.relative_to(ROOT)}')
        else:
            path.write_text(content)
    print('Dispatch and compiler storage references '+('match.' if args.check else 'generated.'))


if __name__=='__main__':
    main()
