#!/usr/bin/env python3
"""Sweep real native gas boundaries: atomic shutdown or preserved request prefix.

Every storage read must be exported. Successful states must match a funded native
control; refusals must match the unchanged state or the certified-prefix control.
No value is supplied for an unobserved slot, and no failed attempt is called success.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import urllib.request
from urllib.parse import urlparse

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('fixtures', type=Path)
p.add_argument('build', type=Path)
p.add_argument('report', type=Path)
p.add_argument('--rpc', default='http://127.0.0.1:19653')
a = p.parse_args()
assert urlparse(a.rpc).hostname in ('127.0.0.1', 'localhost')

def rpc(method, params):
    req = urllib.request.Request(a.rpc, json.dumps(dict(jsonrpc='2.0', id=1, method=method, params=params)).encode(),
                                 {'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=90) as response:
        result = json.load(response)
    assert 'error' not in result, result
    return result['result']

assert int(rpc('eth_chainId', []), 16) == 31337
source = json.loads((a.build / 'input.json').read_text())['sources']
pins = dict(re.findall(r'address internal constant (\w+)\s*=\s*address\((0x[0-9a-fA-F]+)\)',
                     source['contracts/ContractAddresses.sol']['content']))
artifacts = json.loads((a.build / 'abis.json').read_text())
def slot(contract, field):
    row = next(r for r in artifacts[contract]['storageLayout']['storage'] if r['label'] == field)
    return '0x' + hex(int(row['slot']))[2:].zfill(64), int(row['offset']) * 8

sub_slot, _ = slot('DegenerusAdmin', 'subscriptionId')
go_slot, go_offset = slot('DegenerusGame', 'gameOverStatePacked')
flags_slot, flags_offset = slot('DegenerusGame', 'rngFlagsAndNudges')
sweep_shift = int(re.search(r'GO_SWEPT_SHIFT\s*=\s*(\d+)',
                           source['contracts/storage/DegenerusGameStorage.sol']['content'])[1]) + go_offset
game, admin = pins['GAME'].lower(), pins['ADMIN'].lower()
daily = pins['GAME_ADVANCE_MODULE'].lower() if 'GAME_ADVANCE_MODULE' in pins else pins['GAME_DAILY_MODULE'].lower()
request_selectors = {'0x' + selector for signature, selector in
                     artifacts['DegenerusGameDailyModule']['evm']['methodIdentifiers'].items()
                     if signature.startswith(('requestDailyRng', 'requestMinerRng'))}
miner_topic = rpc('web3_sha3', ['0x' + b'MinerWork(address,uint8,uint256,uint256)'.hex()])
rows = []

def log_effects(logs):
    out = []
    for log in logs:
        if log['address'].lower() == '0xfffffffffffffffffffffffffffffffffffffffe':
            continue
        data = log['data'].lower()
        if log['topics'] and log['topics'][0].lower() == miner_topic:
            assert int(data[-64:], 16) == 0
            data = data[:66] + '<gas>' + data[-64:]
        out.append([log['address'].lower(), log['topics'], data])
    return out

for kind in ['sweep', 'daily', 'midday']:
    path = a.fixtures / ('optfix-' + kind + '.call.json')
    call = json.loads(path.read_text())
    exported = json.loads(path.with_name(path.name.replace('.call.json', '.state.json')).read_text())
    state = {address.lower(): dict(code=entry['code'], balance=hex(int(entry['balance'], 16)),
             nonce=hex(entry['nonce']), state={k.lower(): v.lower() for k, v in entry['storage'].items()})
             for address, entry in exported.items()}
    raw = bytes.fromhex(call['input'][2:])
    assert raw[4:36][-20:].hex() == game[2:]
    block = {'number': '0x1', 'time': hex(call['timestamp']), 'baseFeePerGas': '0x0'}

    def run(supplied, multiplier, limit):
        data = bytearray(raw)
        data[68:100] = supplied.to_bytes(32, 'big')
        # invoke(address,bytes,uint256), bytes payload = mineFlip(uint32).
        assert int.from_bytes(data[36:68], 'big') == 96
        assert int.from_bytes(data[100:132], 'big') == 36
        data[136:168] = multiplier.to_bytes(32, 'big')
        tx = dict(from_=call['from'], to=call['to'], data='0x' + data.hex(), gas=hex(limit), gasPrice='0x0')
        tx['from'] = tx.pop('from_')
        options = dict(blockOverrides=block, stateOverrides=state, tracer='prestateTracer', timeout='60s')
        reads = rpc('debug_traceCall', [tx, '0x0', options])
        missing = [(address, key) for address, entry in reads.items() for key in entry.get('storage', {})
                   if key not in state.get(address, {}).get('state', {})]
        assert not missing, (kind, supplied, multiplier, 'Unexported reads', missing)
        delta = rpc('debug_traceCall', [tx, '0x0', dict(options, tracerConfig={'diffMode': True})])
        result = rpc('eth_simulateV1', [dict(blockStateCalls=[dict(blockOverrides=block,
                     stateOverrides=state, calls=[tx])], validation=False), '0x0'])[0]['calls'][0]
        assert result['status'] == '0x1', (kind, supplied, result)
        output = bytes.fromhex(result.get('returnData', '0x')[2:])
        assert len(output) == 64 and int.from_bytes(output[:32], 'big') in (0, 1)
        ok = bool(int.from_bytes(output[:32], 'big'))
        request_frames = []
        if kind != 'sweep':
            trace = rpc('debug_traceCall', [tx, '0x0', dict(options, tracer='callTracer')])
            def visit(frame):
                if frame.get('to', '').lower() == daily and frame.get('input', '')[:10] in request_selectors:
                    request_frames.append(frame)
                for child in frame.get('calls', []):
                    visit(child)
            visit(trace)
            # At 1x, a request admitted by canRun must also clear its forwarding
            # minimum. A lower multiplier may refuse while preserving the prefix.
            if multiplier == 10_000:
                assert all('error' not in frame for frame in request_frames), (kind, supplied, 'Admitted worker reverted')
        changes = []
        final = {}
        for address in delta['pre'].keys() | delta['post'].keys():
            before = delta['pre'].get(address, {})
            after = delta['post'].get(address, {})
            if address not in state:
                # Amsterdam reports the zero-fee coinbase's empty code hash even
                # when no account value changed. Do not invent a missing account.
                assert address == '0x' + '00' * 20 and not before
                assert after == {'codeHash': '0x' + '00' * 32}, (address, after)
                continue
            assert before.get('code', state[address]['code']) == after.get('code', state[address]['code'])
            if 'balance' in after:
                old = int(state[address]['balance'], 16)
                new = int(after['balance'], 16)
                if old != new:
                    changes.append((address, 'balance', new))
            for key in before.get('storage', {}).keys() | after.get('storage', {}).keys():
                old = int(state[address]['state'][key], 16)
                new = int(after.get('storage', {}).get(key, '0x0'), 16)
                final[address, key] = new
                if old != new:
                    changes.append((address, key, new))
        effects = [sorted(changes), log_effects(result.get('logs', []))]
        def word(address, key):
            return final.get((address, key), int(state[address]['state'][key], 16))
        return dict(ok=ok, effects=effects, gas=int(result['gasUsed'], 16),
                    requestWorkerEntered=bool(request_frames),
                    sub=word(admin, sub_slot) if kind == 'sweep' else None,
                    swept=bool((word(game, go_slot) >> sweep_shift) & 1) if kind == 'sweep' else None,
                    flags=word(game, flags_slot) >> flags_offset)

    for profile, limit in [('no-reservoir', 16_777_216), ('reservoir', 500_000_000)]:
        complete = run(6_000_000, 10_000, limit)
        assert complete['ok']
        if kind == 'sweep':
            assert complete['swept'] and complete['sub'] == 0
            budgets = range(750_000, 2_800_001, 5_000)
            multipliers = [10_000]
            prefix = None
        else:
            assert complete['flags'] & (1 << 14)
            assert complete['requestWorkerEntered'], 'Funded control missed the request worker'
            prefix = run(450_000, 10_000, limit)
            assert prefix['ok'] and prefix['flags'] & (1 << 8) and not prefix['flags'] & (1 << 14)
            assert prefix['effects'] != complete['effects']
            # Cross daily's 4.4M estimate plus its Degenesis surcharge, both
            # engine reserves and the preceding certification cost.
            budgets = range(450_000, 6_500_001 if kind == 'daily' else 3_000_001, 25_000)
            multipliers = [2_500, 10_000]
        for multiplier in multipliers:
            completed = 0
            for supplied in budgets:
                result = run(supplied, multiplier, limit)
                if kind == 'sweep':
                    if result['ok']:
                        assert result['swept'] and result['sub'] == 0
                        assert result['effects'] == complete['effects'], (kind, profile, supplied, result)
                        outcome = 'completed'
                        completed += 1
                    else:
                        assert not result['swept'] and result['sub'] != 0
                        assert result['effects'] == [[], []], (kind, profile, supplied, result)
                        outcome = 'atomic-refusal'
                else:
                    assert result['ok'], (kind, profile, supplied, multiplier, result)
                    if result['effects'] == complete['effects']:
                        outcome = 'requested'
                        completed += 1
                    else:
                        assert result['effects'] == prefix['effects'], (kind, profile, supplied, multiplier, result)
                        outcome = 'certified-prefix'
                rows.append(dict(kind=kind, profile=profile, supplied=supplied, multiplier=multiplier,
                                 requestWorkerEntered=result['requestWorkerEntered'],
                                 outcome=outcome, gas=result['gas'], effectSha256=hashlib.sha256(
                                     json.dumps(result['effects'], sort_keys=True).encode()).hexdigest()))
            assert completed, (kind, profile, multiplier, 'Range never reached successful admission')
        print(kind, profile, 'passed', flush=True)
a.report.write_text(json.dumps(dict(client=rpc('web3_clientVersion', []),
    cases=len(rows), allPassed=True, rows=rows), indent=2) + '\n')
print(f'{len(rows)} native gas-boundary cases passed', flush=True)
