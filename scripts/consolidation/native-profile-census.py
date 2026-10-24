#!/usr/bin/env python3
"""Replay every cold census call with native production runtimes and strict effects.

The high Osaka debug-call budget compares identical amounts of work, including
Foundry batches larger than the transaction cap. The separate multiplier replay
must repartition those batches at the real cap; this is not a deployment test.
"""
import argparse
from collections import defaultdict
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import time
from urllib.parse import urlparse

spec = importlib.util.spec_from_file_location('calibration', Path(__file__).with_name('native-calibration.py'))
n = importlib.util.module_from_spec(spec)
spec.loader.exec_module(n)


def load_dataset(directory, artifacts):
    codes = json.loads((directory / 'codes.json').read_text())
    names = json.loads((directory / 'names.json').read_text())
    inverse = {name: address for address, name in names.items()}
    pins = dict(re.findall(r'address internal constant (\w+)\s*=\s*address\((0x[0-9a-fA-F]+)\)',
        (artifacts.parent / 'contracts/ContractAddresses.sol').read_text()))
    # The recorder uses common EIP-170 state-owner nonces in both profiles.
    # The wrapper restores source pins after testing, so that restored file is
    # not an authority for deployed protocol addresses. Derive them anew.
    common = json.loads(subprocess.check_output(['node', '--input-type=module', '-e', '''
import {getCreateAddress} from 'ethers';
import {PROFILES} from './scripts/lib/deploymentProfiles.js';
const pins = {};
PROFILES.eip170.forEach((row, index) => {
  const address = getCreateAddress({from: '0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496', nonce: 5 + index});
  for (const key of row.aliases) pins[key] = address;
});
console.log(JSON.stringify(pins));'''], text=True))
    pins.update(common)
    for name, key in dict(AFKingToken='AFKING_SUB_TOKEN', DeityPass='DEITY_PASS', Parimutuel='PARIMUTUEL',
        RecordBounty='RECORD_BOUNTY', OwnerGovernance='OWNER_GOVERNANCE', Admin='ADMIN',
        Icons32='ICONS_32', MockStETH='STETH_TOKEN', MockVRF='VRF_COORDINATOR',
        MockLINK='LINK_TOKEN', MockFeed='LINK_ETH_FEED').items():
        if key in pins:
            inverse.setdefault(name, pins[key].lower())
    # Remove only the fixture's extra table getters. Pins and constructor-bound
    # immutable code in every other exported runtime are retained verbatim.
    artifact = json.loads((artifacts / 'CrapsBattle.sol/CrapsBattle.json').read_text())
    assert not artifact['deployedBytecode'].get('immutableReferences')
    code = artifact['deployedBytecode']['object']
    codes[inverse['CRAPS']] = '0x' + code.removeprefix('0x')
    return codes, names, inverse


def state_for(row, codes):
    return {address: dict(code=codes[address], **{k: v for k, v in account.items() if k != 'codeHash'})
            for address, account in row['state'].items()}


def expected_logs(row, inverse):
    # Foundry recordLogs retains attempted LOGs inside a reverted root call.
    # A native reverted transaction commits no logs; its status/revert bytes and
    # unchanged poststate remain mandatory oracle checks.
    if not row['success']:
        return []
    return n.events([dict(address=inverse.get(log['name'], log['name']),
                          topics=log['topics'], data=log['data']) for log in row['logs']])


def update_world(world, patch):
    for address, account in patch.items():
        known = world.setdefault(address, dict(code='0x', balance='0x0', nonce='0x0', state={}))
        known.update({k: v for k, v in account.items() if k in ('balance', 'nonce', 'code')})
        known['state'].update(account.get('state', {}))


def remap_state(state, mapping, codes):
    """Move only disjoint namespaced state for a grouping counterfactual."""
    out = {address: dict(account, state=dict(account.get('state', {})))
           for address, account in state.items() if address not in mapping}
    for address, target in mapping.items():
        if address not in state:
            continue
        source = state[address]
        assert int(source.get('balance', '0x0'), 16) == 0, 'Grouping study expects unfunded QA roots'
        dest = out.setdefault(target, dict(code=codes[target], balance='0x0', nonce='0x1', state={}))
        for slot, value in source.get('state', {}).items():
            assert slot not in dest['state'] or int(dest['state'][slot], 16) == int(value, 16), ('Namespace collision', slot)
            dest['state'][slot] = value
        # The old address remains the delegate implementation, without user state.
        out[address] = dict(code=codes[address], balance='0x0', nonce='0x1', state={})
    return out


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--dataset', type=Path, required=True)
    p.add_argument('--artifacts', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--rpc', required=True)
    p.add_argument('--limit', type=int, default=500_000_000)
    p.add_argument('--max-calls', type=int, default=0)
    p.add_argument('--resume', action='store_true')
    p.add_argument('--runtime-overrides', type=Path)
    p.add_argument('--address-map', type=Path, help='Counterfactual disjoint namespace roots')
    a = p.parse_args()
    assert urlparse(a.rpc).hostname in ('127.0.0.1', 'localhost')
    assert int(n.b.rpc(a.rpc, 'eth_chainId', []), 16) == 31337
    codes, names, inverse = load_dataset(a.dataset, a.artifacts)
    if a.runtime_overrides:
        for address, code in json.loads(a.runtime_overrides.read_text()).items():
            assert address in codes and codes[address] != '0x', ('Unknown runtime override', address)
            codes[address] = code
    mapping = json.loads(a.address_map.read_text()) if a.address_map else {}
    world = json.loads((a.dataset / 'initial.json').read_text())
    a.out.mkdir(parents=True, exist_ok=True)
    code_hash = hashlib.sha256(json.dumps(codes, sort_keys=True).encode()).hexdigest()
    meta = dict(dataset=str(a.dataset), runtimeSetSha256=code_hash, gasLimit=a.limit,
                completePrestateSource='Initial full world plus every recorded write and explicit fixture patch',
                client=n.b.rpc(a.rpc, 'web3_clientVersion', []), method=__doc__)
    if mapping:
        meta['counterfactualAddressMap'] = mapping
    meta_path = a.out / 'metadata.json'
    if a.resume and meta_path.exists():
        assert json.loads(meta_path.read_text()) == meta, 'Cannot resume different runtime/input set'
    meta_path.write_text(json.dumps(meta, indent=2))
    done = {}
    results_file = a.out / 'calls.jsonl'
    if a.resume and results_file.exists():
        done = {r['seq']: r for r in map(json.loads, results_file.read_text().splitlines())}
    results = []
    start = time.monotonic()
    with results_file.open('w') as output:
        for line in gzip.open(a.dataset / 'calls.jsonl.gz', 'rt'):
            row = json.loads(line)
            if a.max_calls and len(results) >= a.max_calls:
                break
            update_world(world, row['fixturePatch'])
            if row['seq'] in done and done[row['seq']]['pass_']:
                results.append(done[row['seq']])
                output.write(json.dumps(done[row['seq']], separators=(',', ':')) + '\n')
                update_world(world, row['post'])
                continue
            state = state_for(row, codes)
            expected_post = row['post']
            known_world = world
            if mapping:
                state = remap_state(state, mapping, codes)
                expected_post = remap_state(expected_post, mapping, codes)
                known_world = remap_state(world, mapping, codes)
            bo = dict(number=hex(row['number']), time=hex(row['timestamp']), baseFeePerGas='0x0')
            tx = dict(from_=row['from_'], to=mapping.get(row['to'], row['to']), data=row['data'], value=row['value'],
                      gas=hex(a.limit), gasPrice='0x0')
            tx['from'] = tx.pop('from_')
            opts = dict(blockOverrides=bo, stateOverrides=state, tracer='prestateTracer', timeout='60s')
            observed = n.b.rpc(a.rpc, 'debug_traceCall', [tx, '0x0', opts])
            missing = n.missing_prestate(observed, state)
            if missing:
                # Optional gas-dependent lookahead can read keys absent from the
                # original access set. Resolve them from the complete recorded
                # world; only that full dump/history proves absent keys are zero.
                for address, key in missing:
                    assert key.startswith('0x'), ('Unexpected code change', address, key)
                    known = known_world.get(address, dict(code=codes.get(address, '0x'), balance='0x0', nonce='0x0', state={}))
                    account = state.setdefault(address, dict(code=codes.get(address, '0x'),
                        balance=known['balance'], nonce=known['nonce'], state={}))
                    account['state'][key] = known['state'].get(key, n.b.word(0))
                observed = n.b.rpc(a.rpc, 'debug_traceCall', [tx, '0x0', opts])
                missing = n.missing_prestate(observed, state)
            block = n.b.rpc(a.rpc, 'eth_simulateV1', [dict(blockStateCalls=[dict(
                blockOverrides=bo, stateOverrides=state, calls=[tx])], validation=False), '0x0'])[0]
            result = block['calls'][0]
            delta = n.b.rpc(a.rpc, 'debug_traceCall', [tx, '0x0', dict(opts, tracerConfig=dict(diffMode=True))])
            storage = n.check_storage({address: account.get('state', {}) for address, account in expected_post.items()}, state, delta)
            actual = n.apply_delta(state, delta)
            balances = [[address, account['balance'], actual.get(address, {}).get('balance', '0x0')]
                        for address, account in expected_post.items() if 'balance' in account
                        and int(account['balance'], 16) != int(actual.get(address, {}).get('balance', '0x0'), 16)]
            status = (result['status'] == '0x1') == row['success']
            return_data = result.get('error', {}).get('data', result.get('returnData', '0x'))
            returned = return_data == row['expected']
            actual_logs = n.events(result.get('logs', []))
            wanted_logs = expected_logs(row, inverse)
            if mapping:
                wanted_logs = [(mapping.get(address, address), topics, data) for address, topics, data in wanted_logs]
            equal_logs = actual_logs == wanted_logs
            record = dict(seq=row['seq'], label=row['label'], payer=row['payer'],
                receiptGas=int(result['gasUsed'], 16), grossGas=int(result['maxUsedGas'], 16),
                statusMatches=status, returnMatches=returned, orderedLogsMatch=equal_logs,
                missingPrestate=missing, storageMismatches=storage, balanceMismatches=balances,
                pass_=status and returned and equal_logs and not missing and not storage and not balances)
            if not record['pass_']:
                record['diagnostic'] = dict(result=result, expectedLogs=wanted_logs,
                    expectedReturn=row['expected'], expectedSuccess=row['success'])
            results.append(record)
            output.write(json.dumps(record, separators=(',', ':')) + '\n')
            output.flush()
            update_world(world, row['post'])
            if len(results) % 100 == 0:
                print(json.dumps(dict(calls=len(results), failures=sum(not r['pass_'] for r in results),
                                      seconds=round(time.monotonic()-start, 1))), flush=True)
    groups = defaultdict(list)
    for record in results:
        groups[record['label']].append(record)
    summary = dict(meta, calls=len(results), failures=sum(not r['pass_'] for r in results),
        flows=[dict(label=label, payer=group[0]['payer'], count=len(group),
            totalGas=sum(r['receiptGas'] for r in group), totalGrossGas=sum(r['grossGas'] for r in group),
            maxGas=max(r['grossGas'] for r in group), meanGas=sum(r['receiptGas'] for r in group)/len(group))
            for label, group in sorted(groups.items())])
    (a.out / 'summary.json').write_text(json.dumps(summary, indent=2))
    print(json.dumps(dict(calls=summary['calls'], failures=summary['failures'])), flush=True)
    assert results and not summary['failures'], 'Native census differs from recorded effects'


if __name__ == '__main__':
    main()
