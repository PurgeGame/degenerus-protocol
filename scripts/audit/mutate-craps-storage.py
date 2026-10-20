#!/usr/bin/env python3
"""Mutation campaign for the Craps tagged rings; always restore exact source bytes."""
from pathlib import Path
import argparse
import json
import os
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
STORAGE = Path('contracts/storage/CrapsBattleStorage.sol')
JACKPOT = Path('contracts/JackpotBattle.sol')
MATCH = 'test_MutationFamily_|testFuzz_FourSeatLanes|test_JackpotWrap'
EXPECTED = ['Scoreboard','SlotStateAndHighDraw','HighField','DayTickets','DayAction','MergedBudgets',
            'FourSeatLanesPreserveNeighborsAndReplaceWholeStaleLane','JackpotWrapReplacesPoisonedCountsButHidesRetainedEntropyUntilPrepare']

def replace(text, old, new):
    if old not in text:
        raise ValueError(f'mutation source drift: {old}')
    return text.replace(old, new)

def mutant(name, storage, jackpot):
    if name == 'skip-tag-checks':
        storage = replace(storage, 'word >> 232 == day ? word & _RING_VALUE_MASK : 0', 'word & _RING_VALUE_MASK')
        storage = replace(storage, 'word >> 232 == slot >> 3 ? word & _RING_VALUE_MASK : 0', 'word & _RING_VALUE_MASK')
        storage = replace(storage, 'word >> 232 == daySlot >> 3 ? word & _RING_VALUE_MASK : 0', 'word & _RING_VALUE_MASK')
        storage = replace(storage, '        if (word >> 40 != day) return 0;', '')
        storage = replace(storage, 'return r.day == slot >> 3 && r.requestDay != 0;', 'return r.requestDay != 0;')
    elif name == 'stale-physical-overwrite':
        storage = replace(storage, 'book[uint24(day & 63)] = value', 'book[uint24(day)] = value')
        storage = replace(storage, 'key = bytes32(slot & 511);', 'key = bytes32(slot);')
        storage = replace(storage, '            slot &= 511;', '')
        storage = replace(storage, '_dayTickets[(daySlot >> 3) & 63] = value', '_dayTickets[daySlot >> 3] = value')
        storage = replace(storage, 'uint256 key = (day & 63) >> 2;', 'uint256 key = day >> 2;')
        jackpot = replace(jackpot, 'JackpotRound storage r = _jackpotRounds[slot & 511];', 'JackpotRound storage r = _jackpotRounds[slot];')
    elif name == 'missing-whole-word-reset':
        for old in ['book[uint24(day & 63)] = value', '_battles[key] = value', '_slotState[slot] = value',
                    '_highField[key] = value', '_dayTickets[(daySlot >> 3) & 63] = value']:
            storage = replace(storage, old, old.replace(' = ', ' |= '))
        storage = replace(storage, '(_daySeated[key][id] & ~(uint256(type(uint64).max) << shift)) | (lane << shift)',
                          '_daySeated[key][id] | (lane << shift)')
        # Carry old packed counts/flags/padding into the new round's final state word.
        jackpot = replace(jackpot, 'sstore(add(r.slot, 4), or(or(shl(32, paidCount), shl(128, awardTarget)),\n                or(shl(160, entryPrice), shl(232, shr(3, slot)))))',
                          'sstore(add(r.slot, 4), or(sload(add(r.slot, 4)), or(or(shl(32, paidCount), shl(128, awardTarget)),\n                or(shl(160, entryPrice), shl(232, shr(3, slot))))))')
    else:
        raise ValueError(name)
    return storage, jackpot

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--log-dir',type=Path,required=True)
    args=parser.parse_args()
    os.chdir(ROOT)
    args.log_dir.mkdir(parents=True,exist_ok=True)
    originals={p:p.read_bytes() for p in (STORAGE,JACKPOT)}
    report=[]
    try:
        for name in ['skip-tag-checks','stale-physical-overwrite','missing-whole-word-reset']:
            s,j=mutant(name,originals[STORAGE].decode(),originals[JACKPOT].decode())
            STORAGE.write_text(s);JACKPOT.write_text(j)
            destination=args.log_dir/name
            command=['python3','scripts/audit/storage-census/run.py','--file','test/craps/CrapsStorageReuse.t.sol',
                     '--log-dir',str(destination),'--match-test',MATCH,'--fuzz-runs','64']
            with (args.log_dir/(name+'-driver.log')).open('w') as out:
                result=subprocess.run(command,stdout=out,stderr=subprocess.STDOUT)
            logs=sorted(destination.glob('*/focused-*.log'))
            text='\n'.join(p.read_text() for p in logs)
            failed=[label for label in EXPECTED if re.search(r'\[FAIL[^\n]*'+label,text)]
            killed=result.returncode != 0 and len(failed)==len(EXPECTED)
            report.append({'mutation':name,'exit_code':result.returncode,'killed':killed,'failed_families':failed,'logs':[str(p) for p in logs]})
            print(json.dumps(report[-1]),flush=True)
            if not killed:
                raise RuntimeError(f'{name}: every ring family must detect the mutation')
    finally:
        for p,contents in originals.items():p.write_bytes(contents)
        (args.log_dir/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    return 0

if __name__=='__main__':raise SystemExit(main())
