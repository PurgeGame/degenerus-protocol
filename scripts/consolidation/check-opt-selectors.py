#!/usr/bin/env python3
"""Verify the reviewed selector removals, unchanged guards/bodies and runtime dispatch order."""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import re

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--before', type=Path, required=True)
p.add_argument('--after', type=Path, required=True)
p.add_argument('--manifest', type=Path, required=True)
p.add_argument('--report', type=Path, required=True)
a = p.parse_args()
manifest = json.loads(a.manifest.read_text())
artifacts = {s: json.loads((d / 'abis.json').read_text()) for s, d in [('before', a.before), ('after', a.after)]}
sources = {s: json.loads((d / 'input.json').read_text())['sources'] for s, d in [('before', a.before), ('after', a.after)]}
outputs = {s: json.loads((d / 'output.json').read_text()) for s, d in [('before', a.before), ('after', a.after)]}

def walk(n):
    if isinstance(n, dict):
        yield n
        for v in n.values():
            yield from walk(v)
    elif isinstance(n, list):
        for v in n:
            yield from walk(v)

contracts = {}
by_id = {}
for side, output in outputs.items():
    contracts[side] = {}
    by_id[side] = {}
    for filename, unit in output['sources'].items():
        for node in walk(unit['ast']):
            if node.get('nodeType') == 'ContractDefinition':
                contracts[side][(filename, node['name'])] = node
                by_id[side][node['id']] = (filename, node)

def text(side, filename, node):
    start, length, _ = map(int, node['src'].split(':'))
    return sources[side][filename]['content'].encode()[start:start + length].decode()

def compact(value):
    value = re.sub(r'/\*[\s\S]*?\*/|//[^\n]*', '', value)
    return re.sub(r'\s+', '', value)

renames = {r['original']: r['alias'] for r in manifest['definitions'] if r['mode'] == 'rename'}
renames.update({r['alias']: r['original'] for r in manifest['definitions'] if r['mode'] == 'drop-alias'})
def renamed(value):
    return re.sub(r'\b(' + '|'.join(map(re.escape, renames)) + r')\b', lambda m: renames[m[0]], value)

proofs = []
for row in manifest['definitions']:
    filename, name = row['path'], row['contract']
    left = contracts['before'][(filename, name)]
    right = contracts['after'][(filename, name)]
    old = next(n for n in left['nodes'] if n.get('nodeType') == 'FunctionDefinition'
               and n.get('functionSelector') == row['selector'])
    funcs = {n.get('functionSelector'): n for n in right['nodes'] if n.get('nodeType') == 'FunctionDefinition'}
    new = funcs[row['aliasSelector'] if row['mode'] == 'rename' else row['selector']]
    if row['mode'] == 'rename':
        assert row['selector'] not in funcs, row
        assert new['functionSelector'] == row['aliasSelector'], row
    elif row['mode'] == 'drop-alias':
        assert row['aliasSelector'] not in funcs, row
    else:
        alias = funcs[row['aliasSelector']]
        assert alias['functionSelector'] == row['aliasSelector'], row
        if alias.get('body'):
            args = ','.join(n['name'] for n in alias['parameters']['parameters'])
            expected = '{' + ('return ' if alias['returnParameters']['parameters'] else '') + row['original'] + '(' + args + ');}'
            assert compact(text('after', filename, alias['body'])) == compact(expected), row
            assert not alias['modifiers'], row
    assert new['stateMutability'] == old['stateMutability'], row
    assert new['visibility'] == (old['visibility'] if row['mode'] == 'retain' else row['originalVisibility']), row
    for field in ['parameters', 'returnParameters']:
        types = lambda n: [(x['typeDescriptions']['typeString'], x['storageLocation']) for x in n[field]['parameters']]
        assert types(old) == types(new), (row, field)
    old_mods = [text('before', filename, n) for n in old['modifiers']]
    new_mods = [text('after', filename, n) for n in new['modifiers']]
    assert list(map(compact, old_mods)) == list(map(compact, new_mods)), row
    if old.get('body'):
        before = compact(text('before', filename, old['body']))
        after = compact(text('after', filename, new['body']))
        assert after in (before, compact(renamed(text('before', filename, old['body'])))), ('Body/guard drift', row)
        assert 'msg.sig' not in after, ('Selector-dependent body needs a separate proof', row)
    proofs.append(dict(row, bodyAndAuthorizationUnchanged=True))

abis = []
for host in json.loads((a.after / 'sizes.json').read_text()):
    if host == 'CrapsViews':
        continue
    node = next(n for (_, name), n in contracts['before'].items() if name == host)
    owners = {(by_id['before'][i][0], by_id['before'][i][1]['name']) for i in node['linearizedBaseContracts']}
    rules = list({(r['selector'], r['mode']): r for r in manifest['definitions']
                  if (r['path'], r['contract']) in owners}.values())
    expected = deepcopy(artifacts['before'][host]['abi'])
    for row in rules:
        if row['mode'] == 'retain':
            continue
        expected = [e for e in expected if e.get('name') != row['alias']]
        if row['mode'] == 'rename':
            for entry in expected:
                if entry.get('name') == row['original']:
                    entry['name'] = row['alias']
    canonical = lambda entries: {json.dumps(e, sort_keys=True) for e in entries}
    assert canonical(expected) == canonical(artifacts['after'][host]['abi']), ('Unexpected ABI drift', host,
        canonical(expected) - canonical(artifacts['after'][host]['abi']), canonical(artifacts['after'][host]['abi']) - canonical(expected))
    methods = artifacts['after'][host]['evm']['methodIdentifiers']
    assert len(methods) == len(set(methods.values())), ('Selector collision', host)
    abis.append(dict(contract=host, reviewedRemovalsOnly=True))

orders = []
for host in ['DegenerusGame', 'Coinflip', 'DegenerusGameBoxModule', 'DegenerusGameDailyModule',
             'DegenerusGameEndgameModule', 'DegenerusGamePassModule', 'CrapsBattle']:
    artifact = artifacts['after'][host]
    code = bytes.fromhex(artifact['evm']['deployedBytecode']['object'])
    ops = []
    pc = 0
    while pc < min(len(code), 6000):
        op = code[pc]
        pc += 1
        size = op - 0x5f if 0x60 <= op <= 0x7f else 0
        value = code[pc:pc + size]
        pc += size
        ops.append((op, value))
    selected = []
    for i in range(len(ops) - 4):
        aa, b, c, d, e = ops[i:i + 5]
        if 0x80 <= aa[0] <= 0x8f and 0x60 <= b[0] <= 0x63 and c[0] == 0x14 and 0x60 <= d[0] <= 0x63 and e[0] == 0x57:
            selected.append(b[1].hex().zfill(8))
        elif selected and aa[0] == 0x5b:
            break
    expected = set(artifact['evm']['methodIdentifiers'].values()) & {r['aliasSelector'] for r in manifest['aliases']}
    assert set(selected[:len(expected)]) == expected, ('Dispatcher order', host)
    orders.append(dict(contract=host, firstSelectors=selected[:len(expected)]))
a.report.write_text(json.dumps(dict(definitions=proofs, abis=abis, dispatcherOrder=orders), indent=2) + '\n')
print(f'{len(proofs)} definition/body/authorization proofs; {len(abis)} exact ABI comparisons; {len(orders)} dispatcher orders')
