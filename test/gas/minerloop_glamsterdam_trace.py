#!/usr/bin/env python3
"""Check conservative checkpoint-gap envelopes from a -vvvv Foundry run.

Supply a log containing the permanent ample 101-seat test and/or 3-field FIFO test.
The cold mineRun frame is authoritative. Count each resolver frame once, and
conservatively assign ALL remaining frame gas to the largest interval. Then add
an upper bound on every positive repricing delta in the entire transaction.
This proves a ceiling on the largest observed gap, not its exact opcode boundary.
"""
import argparse
import json
import re
from pathlib import Path


def check(text, name):
    match = re.search(r'\[PASS\] ' + re.escape(name) + r'\(\).*?(?=\n\[(?:PASS|FAIL)|\nSuite result:|\Z)', text, re.S)
    if not match:
        raise ValueError(f'missing passing test: {name}')
    section = match.group()
    def metric(key):
        m = re.search(r'^  ' + key + r': (\d+)$', section, re.M)
        if not m:
            raise ValueError(f'{name}: missing {key}')
        return int(m[1])
    # Setup seals with UINT32_MAX. The first mineRun(0) is the cold measurement;
    # the second is the recorded replay, which must not be used for cold gas.
    call = re.search(r'\[(\d+)\] DegenerusGame::mineRun\(0\)', section)
    if not call:
        raise ValueError(f'{name}: missing cold mineRun trace (-vvvv required)')
    end = section.find('VM::lastCallGas()', call.end())
    if end < 0:
        raise ValueError('missing measurement boundary')
    fragment = section[call.end():end]
    batches = [int(n) for n in re.findall(r'\[(\d+)\] \w+::resolveRngSlot_g1079\(', fragment)]
    if len(batches) < 4:
        raise ValueError(f'{name}: expected at least four resolver frames, got {len(batches)}')
    osaka = metric('osaka_exec')
    assert int(call[1]) == osaka, (call[1], osaka)
    overhead = osaka - sum(batches)
    assert overhead >= 0, 'double-counted resolver frames'
    osaka_gap = max(batches) + overhead
    # GlamsterdamReprice adds at most 7200 per first-changing SSTORE and 400
    # per cold account. Ignore all negative deltas, and charge every positive
    # delta to this one interval; shared/dirty slots can only make it cheaper.
    positive_delta_ceiling = metric('first_changes') * 7200 + metric('cold_accounts') * 400
    glam_gap = osaka_gap + positive_delta_ceiling
    assert osaka_gap < 10_000_000, f'Osaka checkpoint envelope exceeded: {osaka_gap}'
    assert glam_gap < 10_000_000, f'Glamsterdam checkpoint envelope exceeded: {glam_gap}'
    return dict(test=name, resolver_frames=batches, all_other_frame_gas=overhead,
                largest_osaka_gap_upper_bound=osaka_gap,
                whole_tx_positive_reprice_delta_upper_bound=positive_delta_ceiling,
                largest_glamsterdam_exec_gap_upper_bound=glam_gap,
                osaka_exec=osaka, glamsterdam_exec=metric('glamsterdam_exec'),
                glamsterdam_state=metric('glamsterdam_state'),
                glamsterdam_total=metric('glamsterdam_total'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log', type=Path)
    parser.add_argument('--test', action='append', required=True)
    args = parser.parse_args()
    source = args.log.read_text()
    print(json.dumps([check(source, name) for name in args.test], indent=2))


if __name__ == '__main__':
    main()
