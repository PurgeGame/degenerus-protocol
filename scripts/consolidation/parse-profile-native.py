#!/usr/bin/env python3
"""Compact the profile replay's cold prestates and final observations.

The recorder emits first-access values and final values, including reverted
accesses. No slot value is invented. Explicit fixture changes between calls are
derived against the preceding recorded world, not against a candidate replay.
"""
import argparse
from collections import Counter
import gzip
import hashlib
import json
from pathlib import Path


def word(value):
    return '0x' + f'{int(value, 16):064x}'


def parse(log, initial, out):
    out.mkdir(parents=True, exist_ok=True)
    dump = json.loads(initial.read_text())
    dump = dump.get('accounts', dump.get('alloc', dump))
    world = {}
    codes = {}
    for address, account in dump.items():
        address = ('0x' + address.removeprefix('0x')).lower()
        nonce = account.get('nonce', 0)
        world[address] = dict(balance=hex(int(account.get('balance', '0x0'), 16)),
            nonce=hex(int(nonce, 16) if isinstance(nonce, str) else nonce),
            state={word(k): word(v) for k, v in account.get('storage', {}).items()})
        codes[address] = account.get('code', '0x').lower()
    initial_state = {address: dict(value, code=codes[address]) for address, value in world.items()}
    (out / 'initial.json').write_text(json.dumps(initial_state, separators=(',', ':')))
    names, counts, patches = {}, Counter(), Counter()
    row = None
    count, crank, success = 0, None, False
    census_meta, mine_reverts = None, None

    def finish(stream):
        nonlocal count
        if row is None:
            return
        assert 'expected' in row, f'Incomplete call {row["seq"]}'
        patch = {}
        for address, account in row['state'].items():
            assert address in codes, address
            account['codeHash'] = hashlib.sha256(bytes.fromhex(codes[address][2:])).hexdigest()
            known = world.setdefault(address, dict(balance='0x0', nonce='0x0', state={}))
            for field in ('balance', 'nonce'):
                if int(account[field], 16) != int(known[field], 16):
                    patch.setdefault(address, {})[field] = account[field]
                    patches[field] += 1
            for slot, value in account['state'].items():
                if int(value, 16) != int(known['state'].get(slot, '0x0'), 16):
                    patch.setdefault(address, {}).setdefault('state', {})[slot] = value
                    patches['storage'] += 1
            known.update({k: account[k] for k in ('balance', 'nonce')})
            known['state'].update(account['state'])
        row['fixturePatch'] = patch
        # The initiating account is outside the callee's recorded account access.
        # Foundry's CALL does not increment its nonce or charge transaction gas.
        if row['success'] and int(row['value'], 16):
            sender = row['from_']
            row['post'].setdefault(sender, {}).setdefault('balance',
                hex(int(row['state'][sender]['balance'], 16) - int(row['value'], 16)))
        for address, account in row['post'].items():
            known = world.setdefault(address, dict(balance='0x0', nonce='0x0', state={}))
            for field in ('balance', 'nonce'):
                if field in account:
                    known[field] = account[field]
            known['state'].update(account.get('state', {}))
        stream.write(json.dumps(row, separators=(',', ':')) + '\n')
        count += 1
        assert row["seq"] == count, ("Non-contiguous export", row["seq"], count)
        counts[row['label']] += 1

    with log.open() as source, gzip.open(out / 'calls.jsonl.gz', 'wt', compresslevel=3) as stream:
        for line in source:
            line = line.strip()
            if line.startswith('[PASS] testLongRunCensus'):
                success = True
            if line.startswith('CENSUSMETA|longrun|'):
                fields = line.split('|')
                census_meta = dict(startDay=int(fields[2]), endDay=int(fields[3]),
                    startLevel=int(fields[4]), endLevel=int(fields[5]), successfulCalls=int(fields[6]))
            elif line.startswith('CENSUSNOTE|longrun|mineReverts|'):
                mine_reverts = int(line.rsplit('|', 1)[1])
            if line.startswith('DIFFNAME|'):
                _, address, name = line.split('|')
                names[address.lower()] = name
            elif line.startswith('NATCRANK|'):
                _, tag, timestamp, number, seq = line.split('|')
                crank = dict(tag=int(tag), timestamp=int(timestamp), number=int(number), seq=int(seq))
            elif line.startswith('NATCALL|'):
                finish(stream)
                _, seq, timestamp, number, sender, target, value, data = line.split('|')
                row = dict(seq=int(seq), timestamp=int(timestamp), number=int(number),
                    from_=sender.lower(), to=target.lower(), value=hex(int(value)), data=data.lower(),
                    state={}, post={}, logs=[], crank=crank)
                crank = None
            elif line.startswith('DIFFTX|'):
                _, seq, label, payer, status, returned, gas, sender, target = line.split('|')
                assert int(seq) == row['seq']
                row.update(label=label, payer=payer, expected=returned.lower(),
                           success=status == 'ok', foundryGas=int(gas))
            elif line.startswith('DIFFEVENT|'):
                _, name, encoded = line.split('|')
                data = bytes.fromhex(encoded[2:])
                o1, o2 = int.from_bytes(data[:32]), int.from_bytes(data[32:64])
                n, length = int.from_bytes(data[o1:o1+32]), int.from_bytes(data[o2:o2+32])
                row['logs'].append(dict(name=name, topics=[
                    '0x' + data[o1 + 32*(i+1):o1 + 32*(i+2)].hex() for i in range(n)],
                    data='0x' + data[o2+32:o2+32+length].hex()))
            elif line.startswith('NATACCOUNT|'):
                _, address, balance, nonce = line.split('|')
                row['state'].setdefault(address.lower(), dict(balance=hex(int(balance)),
                    nonce=hex(int(nonce)), state={}))
            elif line.startswith('NATCODE|'):
                _, address, code = line.split('|')
                address, code = address.lower(), code.lower()
                assert address not in codes or codes[address] == code, ('Code changed', address)
                codes[address] = code
            elif line.startswith('NATBALANCE|'):
                _, address, balance, nonce = line.split('|')
                row['post'].setdefault(address.lower(), {}).update(balance=hex(int(balance)), nonce=hex(int(nonce)))
            elif line.startswith('NATSLOT|'):
                _, address, slot, before, after = line.split('|')
                address, slot = address.lower(), word(slot)
                assert address in row['state'], address
                row['state'][address]['state'].setdefault(slot, word(before))
                row['post'].setdefault(address, {}).setdefault('state', {})[slot] = word(after)
        finish(stream)
    # Call count changes when valid gameplay reaches the target sooner. Pin the
    # completed scenario and contiguous recorded sequence, not a stale gas-era count.
    assert success and census_meta and census_meta['endLevel'] >= 31 and mine_reverts == 0, (
        'Full level-31 long-run export required', success, census_meta, mine_reverts)
    assert count >= census_meta['successfulCalls'] > 0
    (out / 'codes.json').write_text(json.dumps(codes))
    (out / 'names.json').write_text(json.dumps(names, indent=2))
    summary = dict(calls=count, counts=counts, accounts=len(codes), fixturePatches=patches,
                   census=census_meta, mineReverts=mine_reverts,
                   log=str(log), initialSha256=hashlib.sha256(initial.read_bytes()).hexdigest())
    (out / 'export-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary))


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--log', type=Path, required=True)
    p.add_argument('--initial', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    a = p.parse_args()
    parse(a.log, a.initial, a.out)
