#!/usr/bin/env python3
"""Compare retained public and low selectors on identical, fully exported native prestates.

Candidates come from real census call frames, retaining caller, arguments, value
and timestamp. Both entries must succeed with identical returns, logs and state.
Every storage read must be present in the fixture; unknown reads are rejected.
"""
import argparse
import gzip
import json
from pathlib import Path
import re
import subprocess
import urllib.request
from urllib.parse import urlparse

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--build', type=Path, required=True)
p.add_argument('--dataset', type=Path, required=True)
p.add_argument('--manifest', type=Path, required=True)
p.add_argument('--report', type=Path, required=True)
p.add_argument('--rpc', default='http://127.0.0.1:19653')
a = p.parse_args()
assert urlparse(a.rpc).hostname in ('127.0.0.1', 'localhost')

def rpc(method, params):
    request = urllib.request.Request(a.rpc, json.dumps(dict(jsonrpc='2.0', id=1, method=method,
                                    params=params)).encode(), {'Content-Type': 'application/json'})
    with urllib.request.urlopen(request, timeout=90) as response:
        result = json.load(response)
    assert 'error' not in result, result
    return result['result']

assert int(rpc('eth_chainId', []), 16) == 31337
source = json.loads((a.build / 'input.json').read_text())['sources']
pins = dict(re.findall(r'address internal constant (\w+)\s*=\s*address\((0x[0-9a-fA-F]+)\)',
                     source['contracts/ContractAddresses.sol']['content']))
deployments = json.loads(subprocess.check_output(['node', '--input-type=module', '-e',
    'import {DEPLOYMENTS} from "./scripts/lib/deploymentManifest.js"; console.log(JSON.stringify(DEPLOYMENTS))'], text=True))
addresses = {r['contract']: pins[r['key']].lower() for r in deployments}
artifacts = json.loads((a.build / 'abis.json').read_text())
codes = json.loads((a.dataset / 'codes.json').read_text())
manifest = json.loads(a.manifest.read_text())
wanted = {(address, r['aliasSelector']): dict(r, contract=name)
          for name, address in addresses.items() for r in manifest['aliases']
          if r['signature'].split('(')[0] in manifest['retainedPublicNames']
          and r['aliasSelector'] in artifacts[name]['evm']['methodIdentifiers'].values()}
wallet_slot = int(next(r['slot'] for r in artifacts['DegenerusGame']['storageLayout']['storage']
                       if r['label'] == 'wallets'))
wallet_base = int(rpc('web3_sha3', ['0x' + wallet_slot.to_bytes(32, 'big').hex()]), 16)
results = {}
attempts = {}

def walk(frame):
    yield frame
    for child in frame.get('calls', []):
        yield from walk(child)

for line in gzip.open(a.dataset / 'calls.jsonl.gz', 'rt'):
    fixture = json.loads(line)
    state = {address: dict(code=codes[address], **{k: v for k, v in entry.items() if k != 'codeHash'})
             for address, entry in fixture['state'].items()}
    for name, address in addresses.items():
        runtime = artifacts[name]['evm']['deployedBytecode']
        if not runtime.get('immutableReferences'):
            state[address] = dict(state.get(address, {}), code='0x' + runtime['object'])
    block = dict(number=hex(fixture['number']), time=hex(fixture['timestamp']), baseFeePerGas='0x0')
    options = dict(blockOverrides=block, stateOverrides=state, tracer='callTracer', timeout='60s')
    outer = dict(to=fixture['to'], data=fixture['data'], value=fixture['value'],
                 gas=hex(16_777_216), gasPrice='0x0')
    outer['from'] = fixture['from_']
    trace = rpc('debug_traceCall', [outer, '0x0', options])
    candidates = list(walk(trace))
    # For view entries absent from the sampled transaction trace, query an already
    # exported concrete slot/account. This supplies no missing prestate values.
    for key, row in wanted.items():
        if key in results:
            continue
        slots = state.get(key[0], {}).get('state', {})
        if row['signature'] == 'extsload(bytes32)' and slots:
            candidates.append(dict(to=key[0], input='0x' + row['aliasSelector'] + next(iter(slots))[2:],
                                   **{'from': fixture['from_'], 'derivedView': True}))
        elif row['signature'] == 'resolveAccount(uint32,address)':
            length = int(slots.get('0x' + wallet_slot.to_bytes(32, 'big').hex(), '0x0'), 16)
            for slot, value in slots.items():
                account_id = int(slot, 16) - wallet_base
                owner = int(value, 16)
                if 0 < account_id < length and 0 < owner < (1 << 160):
                    data = '0x' + row['aliasSelector'] + account_id.to_bytes(32, 'big').hex() + owner.to_bytes(32, 'big').hex()
                    candidates.append(dict(to=key[0], input=data, **{'from': fixture['from_'], 'derivedView': True}))
                    break
    for frame in candidates:
        key = (frame.get('to', '').lower(), frame.get('input', '')[2:10])
        if key not in wanted or key in results or 'error' in frame:
            continue
        attempts[key] = attempts.get(key, 0) + 1
        row = wanted[key]
        pair = {}
        for label, selector in [('original', row['selector']), ('alias', row['aliasSelector'])]:
            call = dict(to=key[0], data='0x' + selector + frame['input'][10:],
                        value=frame.get('value', '0x0'), gas=hex(16_777_216), gasPrice='0x0')
            call['from'] = frame['from']
            reads = rpc('debug_traceCall', [call, '0x0', dict(options, tracer='prestateTracer')])
            missing = [(address, slot) for address, entry in reads.items() for slot in entry.get('storage', {})
                       if slot not in state.get(address, {}).get('state', {})]
            if missing:
                break
            delta = rpc('debug_traceCall', [call, '0x0', dict(options, tracer='prestateTracer',
                         tracerConfig={'diffMode': True})])
            result = rpc('eth_simulateV1', [dict(blockStateCalls=[dict(blockOverrides=block,
                         stateOverrides=state, calls=[call])], validation=False), '0x0'])[0]['calls'][0]
            if result['status'] != '0x1':
                break
            direct = rpc('debug_traceCall', [call, '0x0', options])
            pair[label] = dict(gas=int(result['gasUsed'], 16), executionGas=int(direct['gasUsed'], 16),
                effects=[result.get('returnData', '0x'),
                         [[log['address'], log['topics'], log['data']] for log in result.get('logs', [])], delta])
        if len(pair) != 2:
            continue
        assert pair['original']['effects'] == pair['alias']['effects'], ('Effect mismatch', row, fixture['seq'])
        results[key] = dict(row, fixture=fixture['seq'], label=fixture['label'], caller=frame['from'],
            argumentSource='exported account/slot view' if frame.get('derivedView') else 'census call frame',
            calldata=frame['input'], originalGas=pair['original']['gas'], aliasGas=pair['alias']['gas'],
            saving=pair['original']['gas'] - pair['alias']['gas'],
            executionSaving=pair['original']['executionGas'] - pair['alias']['executionGas'],
            covered=True, authorizedSuccess=True, effectsEqual=True)
        print(row['contract'], row['signature'], results[key]['saving'], flush=True)
    if len(results) == len(wanted):
        break
missing = [row for key, row in wanted.items() if key not in results]
a.report.write_text(json.dumps(dict(client=rpc('web3_clientVersion', []), aliases=list(results.values()),
    missing=missing, method=__doc__), indent=2) + '\n')
assert not missing, missing
assert all(row['saving'] > 0 for row in results.values())
