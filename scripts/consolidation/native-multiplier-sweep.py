#!/usr/bin/env python3
"""Chain native transactions at the real cap, repartitioning every mining crank.

Only independently recorded fixture changes are applied. Candidate poststates
are never replaced by expected state. Every completed crank and player action
must match the reference world, including ETH and all protocol storage. Expected
rejected player attempts are omitted; their fixture setup is still applied.
"""
import argparse
from collections import Counter
import copy
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import time
from urllib.parse import urlparse

spec = importlib.util.spec_from_file_location('census', Path(__file__).with_name('native-profile-census.py'))
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)
n = c.n


def quantity(value):
    return int(value, 16) if isinstance(value, str) else value


def canonical(world, senders, fixture):
    out = {}
    for address, account in world.items():
        if address == fixture:
            continue
        state = {k: v for k, v in account.get('state', {}).items() if int(v, 16)}
        value = dict(balance=hex(quantity(account.get('balance', '0x0'))), state=state)
        if address not in senders:
            value['nonce'] = hex(quantity(account.get('nonce', '0x0')))
        if state or int(value['balance'], 16) or int(value.get('nonce', '0x0'), 16):
            out[address] = value
    return out


def differences(actual, expected, senders, fixture):
    actual, expected = canonical(actual, senders, fixture), canonical(expected, senders, fixture)
    errors = []
    for address in actual.keys() | expected.keys():
        left, right = actual.get(address, {}), expected.get(address, {})
        for field in ('balance', 'nonce'):
            if quantity(left.get(field, '0x0')) != quantity(right.get(field, '0x0')):
                errors.append([address, field, right.get(field), left.get(field)])
        lslots, rslots = left.get('state', {}), right.get('state', {})
        for key in lslots.keys() | rslots.keys():
            if quantity(lslots.get(key, '0x0')) != quantity(rslots.get(key, '0x0')):
                errors.append([address, key, rslots.get(key), lslots.get(key)])
    return errors


def protocol(row):
    return row['label'].startswith('mineFlip:') or row['label'] == 'vrfFulfill'


def groups(rows):
    current = []
    for row in rows:
        if current and (not protocol(row) or not protocol(current[-1]) or
                        row['timestamp'] != current[-1]['timestamp'] or row['crank'] is not None):
            yield current
            current = []
        current.append(row)
    if current:
        yield current


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--dataset', type=Path, required=True)
    p.add_argument('--artifacts', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--rpc', required=True)
    p.add_argument('--schedule', choices=('osaka', 'amsterdam'), required=True)
    p.add_argument('--multiplier', type=int, required=True)
    p.add_argument('--limit', type=int, default=16_777_216)
    p.add_argument('--through-level', type=int, default=6)
    p.add_argument('--max-groups', type=int, default=0, help='Short oracle smoke check only')
    a = p.parse_args()
    assert urlparse(a.rpc).hostname in ('127.0.0.1', 'localhost')
    assert int(n.b.rpc(a.rpc, 'eth_chainId', []), 16) == 31337
    codes, names, inverse = c.load_dataset(a.dataset, a.artifacts)
    rows = [json.loads(line) for line in gzip.open(a.dataset / 'calls.jsonl.gz', 'rt')]
    expected = json.loads((a.dataset / 'initial.json').read_text())
    actual = copy.deepcopy(expected)
    for address, code in codes.items():
        actual.setdefault(address, dict(balance='0x0', nonce='0x0', state={}))['code'] = code
    senders = {row['from_'] for row in rows}
    fixture, game, keeper = inverse['fixture'], inverse['Game'], inverse['keeper']
    vrf = next(row['to'] for row in rows if row['label'] == 'vrfFulfill')
    fulfilled = {int(row['data'][10:74], 16): row['data'] for row in rows if row['label'] == 'vrfFulfill'}
    selector = lambda signature: n.b.topic(signature)[:10]
    mine_selector = selector('mineFlip(uint32)')
    next_selector = selector('nextMinerAction()')
    request_selector = selector('lastRequestId()')
    pending_selector = selector('pendingRequests(uint256)')
    mine_data = mine_selector + f'{a.multiplier:064x}'
    miner_addresses = {address for address, code in codes.items() if code != '0x' and address != game}
    calls, failures, rollbacks, omitted, worker_units = [], [], [], 0, Counter()
    patches = []
    a.out.mkdir(parents=True, exist_ok=True)
    start = time.monotonic()
    bo = {}

    def read(target, data):
        result = n.b.rpc(a.rpc, 'eth_simulateV1', [dict(blockStateCalls=[dict(
            blockOverrides=bo, stateOverrides=actual, calls=[dict(to=target, data=data, gas=hex(a.limit))])],
            validation=False), '0x0'])[0]['calls'][0]
        assert result['status'] == '0x1', ('View reverted', target, data, result)
        return result['returnData']

    def execute(sender, target, data, value, label):
        nonlocal actual
        tx = dict(to=target, data=data, value=value, gas=hex(a.limit), gasPrice='0x0')
        tx['from'] = sender
        opts = dict(blockOverrides=bo, stateOverrides=actual, tracer='prestateTracer', timeout='60s')
        block = n.b.rpc(a.rpc, 'eth_simulateV1', [dict(blockStateCalls=[dict(
            blockOverrides=bo, stateOverrides=actual, calls=[tx])], validation=False), '0x0'])[0]
        result = block['calls'][0]
        delta = n.b.rpc(a.rpc, 'debug_traceCall', [tx, '0x0', dict(opts, tracerConfig=dict(diffMode=True))])
        record = dict(label=label, gas=int(result['gasUsed'], 16), grossGas=int(result['maxUsedGas'], 16),
                      success=result['status'] == '0x1')
        if label == 'mineFlip':
            trace = n.b.rpc(a.rpc, 'debug_traceCall', [tx, '0x0', dict(opts, tracer='callTracer')])
            def walk(frame, in_miner=False):
                entering = frame.get('input', '').startswith(mine_selector) and frame.get('to') in miner_addresses
                for child in frame.get('calls', []):
                    if in_miner or entering:
                        output = child.get('output', '0x')
                        if child.get('error'):
                            rollbacks.append(dict(call=len(calls), to=child.get('to'),
                                selector=child.get('input', '')[:10], error=child['error']))
                        elif child['type'] != 'STATICCALL' and len(output) == 194:
                            words = [int(output[2+i:66+i], 16) for i in (0, 64, 128)]
                            if words[0] in (0, 1) and words[1] in (0, 1):
                                worker_units[child['input'][:10]] += words[2]
                    walk(child, False)
            walk(trace)
        calls.append(record)
        if not record['success']:
            failures.append(dict(record, error=result.get('error'), input=data))
            raise AssertionError(('Native transaction reverted', label, result.get('error')))
        actual = n.apply_delta(actual, delta)
        return result

    completed = 0
    last_seq = 0
    mismatch = []
    try:
        for group in groups(rows):
            if a.max_groups and completed >= a.max_groups:
                break
            first, last = group[0], group[-1]
            bo = dict(number=hex(first['number']), time=hex(first['timestamp']), baseFeePerGas='0x0')
            patch, written = {}, set()
            for row in group:
                for address, fields in row['fixturePatch'].items():
                    for field, value in fields.items():
                        if field == 'state':
                            for key, val in value.items():
                                assert (address, key) not in written, ('Late fixture patch overlaps protocol write', row['seq'], address, key)
                                patch.setdefault(address, {}).setdefault('state', {})[key] = val
                        else:
                            assert (address, field) not in written, ('Late fixture patch overlaps protocol account change', row['seq'])
                            patch.setdefault(address, {})[field] = value
                c.update_world(expected, row['fixturePatch'])
                for address, account in row['post'].items():
                    known = expected.get(address, dict(balance='0x0', nonce='0x0', state={}))
                    for field in ('balance', 'nonce'):
                        if field in account and quantity(account[field]) != quantity(known[field]):
                            written.add((address, field))
                    for key, value in account.get('state', {}).items():
                        if quantity(value) != quantity(known['state'].get(key, '0x0')):
                            written.add((address, key))
                c.update_world(expected, row['post'])
            c.update_world(actual, patch)
            if patch:
                patches.append(dict(before=first['seq'], discoveredThrough=last['seq'], patch=patch))
            if protocol(first):
                for attempt in range(3000):
                    request = int(read(vrf, request_selector), 16)
                    if request:
                        pending = read(vrf, pending_selector + f'{request:064x}')
                        if int(pending[-64:], 16) == 0:
                            assert request in fulfilled, ('Unexpected request', request)
                            execute(keeper, vrf, fulfilled[request], '0x0', 'vrfFulfill')
                    action = int(read(game, next_selector), 16)
                    if action == 0:
                        break
                    assert action != 2, ('RNG waits after fulfillment', request)
                    execute(keeper, game, mine_data, '0x0', 'mineFlip')
                else:
                    raise AssertionError('Miner did not drain within 3000 calls')
            elif first['success']:
                result = execute(first['from_'], first['to'], first['data'], first['value'], first['label'])
                assert result['returnData'] == first['expected'], ('Player return differs', first['seq'])
                assert n.events(result['logs']) == c.expected_logs(first, inverse), ('Player events differ', first['seq'])
            else:
                omitted += 1
            mismatch = differences(actual, expected, senders, fixture)
            assert not mismatch, ('Native state diverged', first['seq'], last['seq'], mismatch[:4])
            completed += 1
            last_seq = last['seq']
            level = (int(actual[game]['state'].get(n.b.word(0), '0x0'), 16) >> 96) & ((1 << 24)-1)
            if completed % 100 == 0:
                print(json.dumps(dict(groups=completed, through=last_seq, level=level, calls=len(calls),
                    minerCalls=sum(r['label']=='mineFlip' for r in calls), rollbacks=len(rollbacks),
                    seconds=round(time.monotonic()-start, 1))), flush=True)
            if level >= a.through_level and protocol(first):
                break
    except Exception as error:
        failures.append(dict(oracleError=str(error)))
    final = canonical(actual, senders, fixture)
    digest = hashlib.sha256(json.dumps(final, sort_keys=True).encode()).hexdigest()
    total_gas = sum(row['gas'] for row in calls)
    total_units = sum(worker_units.values())
    report = dict(schedule=a.schedule, multiplier=a.multiplier, txGasCap=a.limit, throughSequence=last_seq,
        groups=completed, calls=len(calls), minerCalls=sum(r['label']=='mineFlip' for r in calls),
        totalGas=total_gas, workerUnits=dict(worker_units), totalWorkerUnits=total_units,
        minerGasPerWorkerUnit=(sum(r['gas'] for r in calls if r['label']=='mineFlip') / total_units if total_units else None),
        omittedExpectedRejectedPlayerAttempts=omitted, failures=failures, workerRollbacks=rollbacks,
        finalStateSha256=digest, finalStateMatchesReference=not mismatch and not failures,
        seconds=round(time.monotonic()-start, 1), checkpointComparisons=completed,
        note='EOA/caller transaction nonces are excluded; protocol storage, ETH balances and non-sender contract nonces are exact. Work units are the rewardBasis returned by successful immediate miner worker calls.')
    (a.out / 'result.json').write_text(json.dumps(report, indent=2))
    (a.out / 'calls.json').write_text(json.dumps(calls))
    (a.out / 'fixture-patches.json').write_text(json.dumps(patches, indent=2))
    (a.out / 'final-state.json').write_text(json.dumps(final, sort_keys=True))
    print(json.dumps({key: value for key, value in report.items() if key not in ('workerUnits', 'note')}), flush=True)
    assert not failures and not mismatch, 'Native chained replay needs review'


if __name__ == '__main__':
    main()
