#!/usr/bin/env python3
"""Replace protocol-only alias pairs with their existing low-selector implementation.

Uses compiler declaration identities. The retained public names come from the
website/simulator caller review; generated ABI listings alone are not callers.
The report pins every edited definition and compatibility decision for review.
"""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import re

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--before', type=Path, required=True)
p.add_argument('--manifest', type=Path, required=True)
p.add_argument('--original', type=Path, required=True, help='Build before aliases widened visibility')
p.add_argument('--out', type=Path, required=True)
p.add_argument('--apply', action='store_true')
a = p.parse_args()
source = json.loads((a.before / 'input.json').read_text())['sources']
compiled = json.loads((a.before / 'output.json').read_text())
aliases = json.loads(a.manifest.read_text())['aliases']
by_selector = {r['selector']: r for r in aliases}
retained = {
    'extsload': 'Website read-provider/polling and simulator raw readers.',
    'registerWallet': 'Simulator onchain integration calls the original authorized hook.',
    'mintPackedOfId': 'Simulator craps/runtime.ts reads the original entry.',
    'resolveAccount': 'Website passes.js and account-loans.js.',
    'walletIdOf': 'Website wallet readers and simulator game/executeDecision.ts.',
    'effectiveBaseStreakAndAfking': 'Website app/quests.js reads the original entry.',
    'minerMaintenancePending': 'Simulator runLifecycle/crapsSettlement.ts and craps/keeper.ts.',
    'runCrapsMaintenance': 'Simulator craps/chaos.ts probes original authorization.',
    'resolveRngSlot': 'Simulator craps/chaos.ts probes original authorization.',
}

def walk(n):
    if isinstance(n, dict):
        yield n
        for v in n.values():
            yield from walk(v)
    elif isinstance(n, list):
        for v in n:
            yield from walk(v)

def span(n):
    s, length, _ = map(int, n['src'].split(':'))
    return s, s + length

visibility = {}
for filename, unit in json.loads((a.original / 'output.json').read_text())['sources'].items():
    for contract in (n for n in walk(unit['ast']) if n.get('nodeType') == 'ContractDefinition'):
        for node in contract['nodes']:
            if node.get('nodeType') == 'FunctionDefinition' and node.get('functionSelector'):
                visibility[(filename, contract['name'], node['functionSelector'])] = node['visibility']

units = {}
definitions = {}
changes = defaultdict(list)
removed = defaultdict(list)
records = []
for filename, unit in compiled['sources'].items():
    if not filename.startswith('contracts/') or filename == 'contracts/XaLayout.sol':
        continue
    text = source[filename]['content'].encode()
    # Foundry may temporarily replace address pins while compiling another batch.
    if filename != 'contracts/ContractAddresses.sol':
        assert Path(filename).read_bytes() == text, ('Source drift', filename)
    units[filename] = (text, list(walk(unit['ast'])))
    for contract in (n for n in walk(unit['ast']) if n.get('nodeType') == 'ContractDefinition'):
        functions = [n for n in contract['nodes'] if n.get('nodeType') == 'FunctionDefinition']
        for original in functions:
            row = by_selector.get(original.get('functionSelector'))
            if row is None:
                continue
            alias = next(n for n in functions if n.get('functionSelector') == row['aliasSelector'])
            name = original['name']
            public_buy = name == 'buyDegenesisBox' and filename in (
                'contracts/DegenerusGame.sol', 'contracts/interfaces/IDegenerusGame.sol')
            minor_saving = name == 'runCrapsReadWork'
            mode = 'drop-alias' if public_buy or minor_saving else 'retain' if name in retained else 'rename'
            reason = ('Simulator authorization probe; alias saves only 40 native gas, so keep one original selector.' if minor_saving else
                      'Player entry; no production caller uses the facade alias.' if public_buy else
                      retained.get(name, 'Only protocol calls; preserve the guarded body at the low selector.'))
            original_visibility = visibility[(filename, contract['name'], row['selector'])]
            records.append(dict(path=filename, contract=contract['name'], original=name,
                selector=row['selector'], alias=row['alias'], aliasSelector=row['aliasSelector'],
                mode=mode, reason=reason, implemented=bool(original.get('body')),
                originalVisibility=original_visibility))
            if mode == 'retain':
                continue
            start, end = span(alias)
            line = text.rfind(b'\n', 0, start) + 1
            previous = text.rfind(b'\n', 0, max(0, line - 1)) + 1
            if b'// Low-selector protocol entry;' in text[previous:line]:
                start = previous
            else:
                start = line
            changes[filename].append((start, end, b''))
            removed[filename].append((start, end))
            if mode == 'rename':
                start, length, _ = map(int, original['nameLocation'].split(':'))
                assert text[start:start + length].decode() == name
                changes[filename].append((start, start + length, row['alias'].encode()))
                definitions[original['id']] = row['alias']
            else:
                definitions[alias['id']] = name
            # Undo only the widening introduced by the removed wrapper.
            if original.get('body') and original['visibility'] == 'public' and original_visibility == 'external':
                _, params_end = span(original['parameters'])
                body_start, _ = span(original['body'])
                match = re.search(rb'\bpublic\b', text[params_end:body_start])
                assert match
                changes[filename].append((params_end + match.start(), params_end + match.end(), b'external'))

for filename, (text, nodes) in units.items():
    for node in nodes:
        target = definitions.get(node.get('referencedDeclaration'))
        if not target or node.get('nodeType') not in ('MemberAccess', 'Identifier'):
            continue
        start, end = span(node)
        if any(low <= start < high for low, high in removed[filename]):
            continue
        name = node.get('memberName', node.get('name'))
        start = end - len(name)
        assert text[start:end].decode() == name
        changes[filename].append((start, end, target.encode()))

for filename, edits in changes.items():
    text = units[filename][0]
    last = len(text) + 1
    for start, end, replacement in sorted(set(edits), reverse=True):
        assert end <= last, ('Overlapping edits', filename, start, end, last)
        text = text[:start] + replacement + text[end:]
        last = start
    if a.apply:
        Path(filename).write_bytes(text)

a.out.parent.mkdir(parents=True, exist_ok=True)
a.out.write_text(json.dumps(dict(aliases=aliases, definitions=records,
    files=sorted(changes), retainedPublicNames=retained), indent=2) + '\n')
print(json.dumps(dict(definitions=len(records), decisions={mode: sum(r['mode'] == mode for r in records)
    for mode in ('rename', 'retain', 'drop-alias')}, files=len(changes), applied=a.apply)))
