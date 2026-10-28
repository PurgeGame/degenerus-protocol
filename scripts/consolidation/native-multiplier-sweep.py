#!/usr/bin/env python3
"""Chain native transactions at the real cap, repartitioning every mining crank.

Only independently recorded fixture changes are applied. Candidate poststates
are never replaced by expected state. Every completed crank and player action
must match the reference world, including ETH and protocol storage (with one
source-pinned inactive redemption cache exception, reported explicitly). Rejected
player attempts must still reject with the recorded reason and unchanged state.
The default consumes the entire captured lifecycle; partial runs are labelled.
"""
import argparse
from collections import Counter
import copy
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import time
from urllib.parse import urlparse
import urllib.request

def load_runtime():
    # Parser/oracle unit tests need only the standard library. The actual native
    # replay additionally requires the documented pycryptodome dependency.
    spec = importlib.util.spec_from_file_location('census', Path(__file__).with_name('native-profile-census.py'))
    census = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(census)
    return census, census.n


def quantity(value):
    return int(value, 16) if isinstance(value, str) else value


def canonical(world, senders, fixture):
    out = {}
    for address, account in world.items():
        # Recorder bookkeeping is not protocol storage, but the fixture can also be
        # the deployment creator. Its ETH balance remains economically relevant.
        state = {} if address == fixture else {k: v for k, v in account.get('state', {}).items() if int(v, 16)}
        value = dict(balance=hex(quantity(account.get('balance', '0x0'))), state=state)
        if address not in senders and address != fixture:
            value['nonce'] = hex(quantity(account.get('nonce', '0x0')))
        if state or int(value['balance'], 16) or int(value.get('nonce', '0x0'), 16):
            out[address] = value
    return out


def inactive_cache_spec(artifacts, inverse, source_hashes):
    # Reviewed on the frozen source: only an active, already resolved batch reads
    # this cache. Fresh resolution bypasses its old value; a resumable batch stores
    # fresh residue before a later read. A one-call batch need not write it at all.
    # Source changes require a new review before permitting this equivalence.
    reviewed = '7bac41205f7871f84d3f2a3e26e12d98a7a469b830c0965274391b5afe159137'
    if source_hashes.get('contracts/sDGNRS.sol') != reviewed:
        raise ValueError('Inactive redemption-cache equivalence needs source review')
    layout = json.loads((artifacts / 'sDGNRS.sol/sDGNRS.json').read_text())['storageLayout']['storage']
    fields = {f['label']: f for f in layout}
    batch, cache = fields['_settlingBatch'], fields['_settlingReserveLeft']
    assert (int(batch['slot']), batch['offset'], batch['type']) == (6, 16, 't_uint32'), 'Reviewed batch layout changed'
    assert (int(cache['slot']), cache['offset'], cache['type']) == (7, 20, 't_uint96'), 'Reviewed cache layout changed'
    return dict(address=inverse['sDGNRS'], batchSlot=f"0x{int(batch['slot']):064x}", batchShift=batch['offset'] * 8,
                cacheSlot=f"0x{int(cache['slot']):064x}", cacheShift=cache['offset'] * 8)


def differences(actual, expected, senders, fixture, inactive_cache=None):
    actual, expected = canonical(actual, senders, fixture), canonical(expected, senders, fixture)
    if inactive_cache:
        spec = inactive_cache
        left = actual.get(spec['address'], {}).get('state', {})
        right = expected.get(spec['address'], {}).get('state', {})
        active = lambda state: (quantity(state.get(spec['batchSlot'], '0x0')) >> spec['batchShift']) & (2**32 - 1)
        if not active(left) and not active(right):
            mask = ((2**96 - 1) << spec['cacheShift'])
            for state in (left, right):
                key = spec['cacheSlot']
                if key in state:
                    state[key] = hex(quantity(state[key]) & ~mask)
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
                        row['timestamp'] != current[-1]['timestamp'] or
                        row['number'] != current[-1]['number'] or row['crank'] is not None):
            yield current
            current = []
        current.append(row)
    if current:
        yield current


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--dataset', type=Path, required=True)
    p.add_argument('--artifacts', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--rpc', required=True)
    p.add_argument('--schedule', choices=('osaka', 'amsterdam'), required=True)
    p.add_argument('--profile', choices=('eip170', 'glamsterdam'), required=True)
    p.add_argument('--multiplier', type=int, required=True)
    p.add_argument('--limit', type=int, default=16_777_216)
    p.add_argument('--through-level', type=int, help='Explicit partial campaign; default consumes the full dataset')
    p.add_argument('--max-groups', type=int, default=0, help='Short oracle smoke check only')
    return p


def validate_args(a):
    if urlparse(a.rpc).hostname not in ('127.0.0.1', 'localhost'):
        raise ValueError('Only a loopback simulation endpoint is allowed')
    if not 21_000 <= a.limit <= 16_777_216:
        raise ValueError('Transaction cap must be between 21,000 and 16,777,216')
    if a.multiplier != 0 and not 2_500 <= a.multiplier <= 2**32 - 1:
        raise ValueError('Multiplier must be zero or a supported uint32 calibration >= 2,500')
    if a.max_groups < 0 or (a.through_level is not None and a.through_level < 1):
        raise ValueError('Partial campaign bounds must be positive')


def validate_rows(rows, summary=None):
    if not rows or [row['seq'] for row in rows] != list(range(1, len(rows) + 1)):
        raise ValueError('Dataset must contain every contiguous call starting at sequence 1')
    if summary is not None:
        if len(rows) != summary['calls']:
            raise ValueError('Dataset call count differs from the capture export summary')
        if dict(Counter(row['label'] for row in rows)) != summary['counts']:
            raise ValueError('Dataset action counts differ from the capture export summary')
        if sum(bool(row['success']) for row in rows) != summary['census']['successfulCalls']:
            raise ValueError('Dataset success counts differ from the capture export summary')


def source_identity(dataset, artifacts, profile, root=None):
    """Bind a retained capture to this checkout, allowing only explicit profile generation."""
    root = root or Path(__file__).resolve().parents[2]
    source_root = artifacts.parent
    manifest = source_root.parent / 'capture-evidence/focused-01-inputs.json'
    recorded = json.loads(manifest.read_text())
    allowed = {'contracts/Coinflip.sol', 'contracts/CrapsBattle.sol', 'contracts/DegenerusGame.sol',
               'contracts/profiles/Selected.sol', 'contracts/ContractAddresses.sol'} if profile == 'glamsterdam' else set()
    differences = []
    hashes = {}
    for name in (root / 'scope.txt').read_text().splitlines():
        name = name.strip()
        if not name or name.startswith('#'):
            continue
        captured = hashlib.sha256((source_root / name).read_bytes()).hexdigest()
        current = hashlib.sha256((root / name).read_bytes()).hexdigest()
        if recorded.get(name) != captured:
            raise ValueError('Capture does not match recorded compiler input: ' + name)
        if current != captured:
            if name not in allowed:
                raise ValueError('Capture production source differs from checkout: ' + name)
            differences.append(dict(path=name, captured=captured, current=current))
        hashes[name] = current
    selected = (source_root / 'contracts/profiles/Selected.sol').read_text()
    if ('/glamsterdam/' in selected) != (profile == 'glamsterdam'):
        raise ValueError('Declared profile does not match captured profile selection')
    # The public handoff is delivered as an independently checksummed evidence
    # archive. Its member manifest prevents a contiguous truncated prefix (or a
    # rewritten export summary) from silently becoming a new "complete" dataset.
    bundle = dataset.parents[2]
    members_file = bundle / 'SHA256SUMS'
    members = {}
    for line in members_file.read_text().splitlines():
        digest, name = line.split(None, 1)
        members[name.strip().removeprefix('./')] = digest
    dataset_hashes = {}
    for path in sorted(dataset.iterdir()):
        if not path.is_file():
            continue
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        relative = path.relative_to(bundle).as_posix()
        if members.get(relative) != digest:
            raise ValueError('Dataset does not match packaged member checksum: ' + relative)
        dataset_hashes[path.name] = digest
    return dict(profile=profile, currentSourceSha256=hashes, generatedSourceDifferences=differences,
                captureManifestSha256=hashlib.sha256(manifest.read_bytes()).hexdigest(),
                packagedMemberManifestSha256=hashlib.sha256(members_file.read_bytes()).hexdigest(),
                datasetSha256=dataset_hashes,
                runnerSha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                gitCommit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=Path(__file__).resolve().parents[2], text=True).strip())


def node_config(url):
    request = urllib.request.Request(url, data=json.dumps(dict(
        jsonrpc='2.0', id=1, method='admin_nodeInfo', params=[])).encode(),
        headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(request, timeout=30) as response:
        result = json.load(response)
    if 'error' in result:
        raise ValueError('Private simulation node must expose read-only admin_nodeInfo: ' + str(result['error']))
    return result['result']['protocols']['eth']['config']


def main():
    a = parser().parse_args()
    validate_args(a)
    c, n = load_runtime()
    assert int(n.b.rpc(a.rpc, 'eth_chainId', []), 16) == 31337
    identity = source_identity(a.dataset, a.artifacts, a.profile)
    # A free-form --schedule label is not execution evidence. Require the local node's
    # actual config; enable admin RPC only on the private loopback simulation node.
    config = node_config(a.rpc)
    assert config.get('osakaTime') == 0, 'Node must activate Osaka at genesis'
    assert (config.get('amsterdamTime') == 0) == (a.schedule == 'amsterdam'), 'Schedule/config mismatch'
    codes, names, inverse = c.load_dataset(a.dataset, a.artifacts)
    inactive_cache = inactive_cache_spec(a.artifacts, inverse, identity['currentSourceSha256'])
    rows = [json.loads(line) for line in gzip.open(a.dataset / 'calls.jsonl.gz', 'rt')]
    export_summary = json.loads((a.dataset / 'export-summary.json').read_text())
    validate_rows(rows, export_summary)
    expected = json.loads((a.dataset / 'initial.json').read_text())
    actual = copy.deepcopy(expected)
    for address, code in codes.items():
        actual.setdefault(address, dict(balance='0x0', nonce='0x0', state={}))['code'] = code
    senders = {row['from_'] for row in rows}
    fixture, game, keeper = inverse['fixture'], inverse['Game'], inverse['keeper']
    vrf = next(row['to'] for row in rows if row['label'] == 'vrfFulfill')
    fulfilled = {int(row['data'][10:74], 16): row['data'] for row in rows if row['label'] == 'vrfFulfill'}
    selector = lambda signature: n.b.topic(signature)[:10]
    mine_selector = selector('mineRun(uint32)')
    next_selector = selector('nextMinerAction()')
    request_selector = selector('lastRequestId()')
    pending_selector = selector('pendingRequests(uint256)')
    mine_data = mine_selector + f'{a.multiplier:064x}'
    miner_addresses = {address for address, code in codes.items() if code != '0x' and address != game}
    calls, failures, rollbacks, omitted, worker_units = [], [], [], 0, Counter()
    patches = []
    cache_differences = {}
    a.out.mkdir(parents=True, exist_ok=True)
    identity.update(client=n.b.rpc(a.rpc, 'web3_clientVersion', []), chainConfig=config,
                    runtimeSetSha256=hashlib.sha256(json.dumps(codes, sort_keys=True).encode()).hexdigest())
    retained = a.artifacts.parent.parent / 'replay/metadata.json'
    if retained.is_file():
        assert json.loads(retained.read_text())['runtimeSetSha256'] == identity['runtimeSetSha256'], 'Captured runtime set differs'
    (a.out / 'inputs.json').write_text(json.dumps(identity, indent=2) + '\n')
    (a.out / 'runner-source.py').write_bytes(Path(__file__).read_bytes())
    start = time.monotonic()
    bo = {}

    def read(target, data):
        result = n.b.rpc(a.rpc, 'eth_simulateV1', [dict(blockStateCalls=[dict(
            blockOverrides=bo, stateOverrides=actual, calls=[dict(to=target, data=data, gas=hex(a.limit))])],
            validation=False), '0x0'])[0]['calls'][0]
        assert result['status'] == '0x1', ('View reverted', target, data, result)
        return result['returnData']

    def execute(sender, target, data, value, label, expected_success=True):
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
        assert record['gas'] <= record['grossGas'] <= a.limit, ('Native receipt exceeds gas cap', record)
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
        if record['success'] != expected_success:
            failures.append(dict(record, error=result.get('error'), input=data))
            raise AssertionError(('Native status differs', label, expected_success, result.get('error')))
        actual = n.apply_delta(actual, delta)
        return result

    completed = 0
    last_seq = 0
    mismatch = []
    level = 0
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
                result = execute(first['from_'], first['to'], first['data'], first['value'], first['label'], False)
                returned = result.get('error', {}).get('data', result.get('returnData', '0x'))
                assert returned == first['expected'], ('Player revert differs', first['seq'], returned, first['expected'])
                assert not n.events(result.get('logs', [])), ('Reverted player call committed logs', first['seq'])
                omitted += 1
            raw = differences(actual, expected, senders, fixture)
            mismatch = differences(actual, expected, senders, fixture, inactive_cache)
            if raw and not mismatch:
                for difference in raw:
                    cache_differences.setdefault(tuple(difference), dict(firstSequence=first['seq'], difference=difference))
            assert not mismatch, ('Native state diverged', first['seq'], last['seq'], mismatch[:4])
            completed += 1
            last_seq = last['seq']
            level = (int(actual[game]['state'].get(n.b.word(0), '0x0'), 16) >> 96) & ((1 << 24)-1)
            if completed % 100 == 0:
                print(json.dumps(dict(groups=completed, through=last_seq, level=level, calls=len(calls),
                    minerCalls=sum(r['label']=='mineFlip' for r in calls), rollbacks=len(rollbacks),
                    seconds=round(time.monotonic()-start, 1))), flush=True)
            if a.through_level is not None and level >= a.through_level and protocol(first):
                break
    except Exception as error:
        failures.append(dict(oracleError=str(error)))
    final = canonical(actual, senders, fixture)
    digest = hashlib.sha256(json.dumps(final, sort_keys=True).encode()).hexdigest()
    total_gas = sum(row['gas'] for row in calls)
    total_units = sum(worker_units.values())
    full = last_seq == rows[-1]['seq'] and not failures and not mismatch
    if full and level != export_summary['census']['endLevel']:
        failures.append(dict(oracleError='Completed world differs from recorded final level'))
        full = False
    if a.through_level is None and not a.max_groups and not full:
        failures.append(dict(oracleError='Full campaign did not consume the complete dataset'))
    if a.through_level is not None and not a.max_groups and level < a.through_level:
        failures.append(dict(oracleError='Requested level was not reached'))
    report = dict(schedule=a.schedule, profile=a.profile, multiplier=a.multiplier, txGasCap=a.limit, throughSequence=last_seq,
        datasetCalls=len(rows), fullDatasetCompleted=full, finalLevel=level,
        requestedThroughLevel=a.through_level, requestedMaxGroups=a.max_groups,
        groups=completed, calls=len(calls), minerCalls=sum(r['label']=='mineFlip' for r in calls),
        totalGas=total_gas, workerUnits=dict(worker_units), totalWorkerUnits=total_units,
        minerGasPerWorkerUnit=(sum(r['gas'] for r in calls if r['label']=='mineFlip') / total_units if total_units else None),
        checkedExpectedRejectedPlayerAttempts=omitted, omittedExpectedRejectedPlayerAttempts=0,
        inactiveRedemptionCacheDifferences=list(cache_differences.values()),
        failures=failures, workerRollbacks=rollbacks,
        finalStateSha256=digest, finalStateMatchesReference=not mismatch and not failures,
        seconds=round(time.monotonic()-start, 1), checkpointComparisons=completed,
        note='EOA/caller transaction nonces and recorder-only fixture storage/nonce are excluded. The source-pinned _settlingReserveLeft cache is compared only while either settlingBatch is active; all omitted cache differences are retained. Fixture ETH, remaining protocol storage, ETH balances and non-sender contract nonces are exact. Work units are the rewardBasis returned by successful immediate miner worker calls.')
    (a.out / 'result.json').write_text(json.dumps(report, indent=2))
    (a.out / 'calls.json').write_text(json.dumps(calls))
    (a.out / 'fixture-patches.json').write_text(json.dumps(patches, indent=2))
    (a.out / 'final-state.json').write_text(json.dumps(final, sort_keys=True))
    print(json.dumps({key: value for key, value in report.items() if key not in ('workerUnits', 'note')}), flush=True)
    assert completed and not failures and not mismatch, 'Native chained replay needs review'


if __name__ == '__main__':
    main()
