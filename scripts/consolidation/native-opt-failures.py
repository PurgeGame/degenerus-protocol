#!/usr/bin/env python3
"""Verify exported forced failures on a local native Amsterdam node, including storage rollback."""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request
from urllib.parse import urlparse

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('fixtures', type=Path)
p.add_argument('report', type=Path)
p.add_argument('--rpc', default='http://127.0.0.1:19653')
p.add_argument('--pattern', default='*.call.json')
p.add_argument('--boundaries', type=Path, help='Required child target/selector and optional minimum observed frame gas per fixture')
a = p.parse_args()
assert urlparse(a.rpc).hostname in ('localhost', '127.0.0.1')

def rpc(method, params):
    request = urllib.request.Request(a.rpc, json.dumps(dict(jsonrpc='2.0', id=1, method=method, params=params)).encode(),
                                     {'Content-Type': 'application/json'})
    with urllib.request.urlopen(request, timeout=90) as response:
        value = json.load(response)
    if 'error' in value:
        raise RuntimeError((method, value['error']))
    return value['result']

assert int(rpc('eth_chainId', []), 16) == 31337
boundaries = json.loads(a.boundaries.read_text()) if a.boundaries else {}
miner = rpc('web3_sha3', ['0x' + b'MinerWork(address,uint8,uint256,uint256)'.hex()])

def logs_normalized(logs):
    result = []
    for log in logs:
        if log['address'].lower() == '0xfffffffffffffffffffffffffffffffffffffffe':
            continue
        data = log['data'].lower()
        if log['topics'] and log['topics'][0].lower() == miner:
            assert int(data[-64:], 16) == 0, 'Cannot normalize paid mining work'
            data = data[:66] + '<gas>' + data[-64:]
        result.append([log['address'].lower(), [v.lower() for v in log['topics']], data])
    return result

rows = []
for path in sorted(a.fixtures.glob(a.pattern)):
    call = json.loads(path.read_text())
    state_path = path.with_name(path.name.replace('.call.json', '.state.json'))
    post_path = path.with_name(path.name.replace('.call.json', '.post.json'))
    assert post_path.exists(), post_path
    state = {address.lower(): {'code': value['code'], 'balance': hex(int(value['balance'], 16)),
             'nonce': hex(value['nonce']), 'state': {k.lower(): v.lower() for k, v in value['storage'].items()}}
             for address, value in json.loads(state_path.read_text()).items()}
    expected = {address.lower(): {k.lower(): v.lower() for k, v in slots.items()}
                for address, slots in json.loads(post_path.read_text()).items()}
    overrides = {'number': '0x1', 'time': hex(call['timestamp']), 'baseFeePerGas': '0x0'}
    for profile, limit in [('no-reservoir', 16_777_216), ('reservoir', 500_000_000)]:
        tx = {'from': call['from'], 'to': call['to'], 'data': call['input'], 'gas': hex(limit), 'gasPrice': '0x0'}
        options = {'blockOverrides': overrides, 'stateOverrides': state, 'tracer': 'prestateTracer', 'timeout': '60s'}
        before = rpc('debug_traceCall', [tx, '0x0', options])
        missing = [[address, slot] for address, value in before.items() for slot in value.get('storage', {})
                   if slot not in state.get(address, {}).get('state', {})]
        delta = rpc('debug_traceCall', [tx, '0x0', dict(options, tracerConfig={'diffMode': True})])
        mismatches = []
        for address, slots in expected.items():
            pre = delta['pre'].get(address, {}).get('storage', {})
            post = delta['post'].get(address, {}).get('storage', {})
            for slot, value in slots.items():
                actual = post.get(slot, '0x0' if slot in pre else state.get(address, {}).get('state', {}).get(slot, '0x0'))
                if int(actual, 16) != int(value, 16):
                    mismatches.append([address, slot, value, actual])
        block = rpc('eth_simulateV1', [{'blockStateCalls': [{'blockOverrides': overrides, 'stateOverrides': state,
                      'calls': [tx]}], 'validation': False}, '0x0'])[0]
        result = block['calls'][0]
        required = boundaries.get(path.stem)
        if a.boundaries:
            assert required is not None, ('Unreviewed fixture boundary', path.stem)
        boundary = None
        expected_logs = json.loads(call['expectedLogs'])
        if required:
            trace = rpc('debug_traceCall', [tx, '0x0', dict(options, tracer='callTracer')])
            matches = []
            rollbacks = []
            def visit(frame):
                if (frame.get('to', '').lower() == required['target'].lower()
                        and frame.get('input', '')[:10].lower() == required['selector'].lower()):
                    matches.append(int(frame.get('gasUsed', '0x0'), 16))
                rollback = required.get('revertedWorker')
                if (rollback and frame.get('to', '').lower() == rollback['target'].lower()
                        and frame.get('input', '')[:10].lower() == rollback['selector'].lower()):
                    rollbacks.append(frame.get('error') == 'execution reverted'
                                     and frame.get('output', '').lower() == rollback['output'].lower())
                for child in frame.get('calls', []):
                    visit(child)
            visit(trace)
            boundary = dict(frames=len(matches), maximumFrameGas=max(matches, default=0))
            boundary['passed'] = (bool(matches) == required.get('entered', True)
                and boundary['maximumFrameGas'] >= required.get('minimumFrameGas', 0))
            if 'revertedWorker' in required:
                # Foundry recordLogs includes attempted logs from reverted children.
                # This explicit fixture expectation names the trusted rolled-back
                # request worker and its exact refusal selector. Its caller's only
                # committed event is the pinned MinerWork prefix, checked in full.
                if required.get('wholeStepRollback'):
                    # The exact trusted Game frame reverted. The test probe only
                    # returns its failure tuple and emits nothing outside that frame.
                    assert required['committedLogs'] == []
                    returned = bytes.fromhex(call['expectedReturn'][2:])
                    assert len(returned) == 64 and returned[:32] == bytes(32)
                    assert returned[32:36].hex() == required['revertedWorker']['output'][2:]
                else:
                    assert len(required['committedLogs']) == 1
                    assert required['committedLogs'][0]['topics'][0].lower() == miner
                    assert required['committedLogs'][0] == expected_logs[-1]
                expected_logs = required['committedLogs']
                boundary['workerRollbackVerified'] = bool(rollbacks) and all(rollbacks)
                boundary['passed'] = boundary['passed'] and boundary['workerRollbackVerified']
        row = dict(fixture=path.stem, profile=profile, status=result['status'],
                   gas=int(result['gasUsed'], 16), maxUsedGas=int(result['maxUsedGas'], 16),
                   executionGas=int(block['gasUsed'], 16), missingSlots=missing, storageMismatches=mismatches,
                   returnMatches=result.get('returnData', '0x').lower() == call['expectedReturn'].lower(),
                   logsMatch=logs_normalized(result.get('logs', [])) == logs_normalized(expected_logs),
                   boundary=boundary,
                   fixtureSha256=hashlib.sha256(path.read_bytes() + state_path.read_bytes() + post_path.read_bytes()).hexdigest())
        row['passed'] = row['status'] == '0x1' and row['returnMatches'] and row['logsMatch'] and not missing and not mismatches
        if boundary is not None:
            row['passed'] = row['passed'] and boundary['passed']
        rows.append(row)
        if not row['passed']:
            print(json.dumps(row), flush=True)
    print(path.stem, 'checked', flush=True)
a.report.parent.mkdir(parents=True, exist_ok=True)
a.report.write_text(json.dumps(dict(client=rpc('web3_clientVersion', []), samples=rows,
    passed=sum(r['passed'] for r in rows), total=len(rows)), indent=2) + '\n')
assert rows and all(r['passed'] for r in rows), 'Native forced-failure verification failed; inspect report'
print(f'{len(rows)}/{len(rows)} profiles pass status, returns, logs, covered prestate and final storage')
