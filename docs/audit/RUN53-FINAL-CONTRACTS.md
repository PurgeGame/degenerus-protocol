# Historical ticket-drain unit model — retired

This document records the retired fixed-unit implementation. Its constants,
900-unit budget, transaction envelope and measurements do not describe the current
engine. Current admission uses `MineFlipGas` and `MineFlipGasBounds`: conservative
cold operation bounds and complete return tails must fit actual available gas and
the remaining worker allowance. See [the current audit handoff](../AUDIT.md) and
[verification instructions](../VERIFICATION.md).

The derivation below backed `UNIT_GAS_BOUND`, `WRITES_BUDGET_SAFE`, `ROUND_UNITS` and
`ROUND_SPLIT_UNITS` in the former `DegenerusGameStorage.sol`. Those constants have
been removed. The historical model priced storage operations analytically and
bounded the reveal emitter separately.

## Reveal emitter

The emitter has no input-dependent loops. Its only successful-path choices are the seated
count (4–8), the second-log condition and the three optional trailing topics. Offsets are
fixed at 0 and 4; topic values and traits do not change the instruction path. All five cases
were traced in the compiled Solidity 0.8.34 / via-IR / optimizer-1000 / Osaka runtime. The
measured region starts after the final bucket SSTORE and includes the tail of quadrant
bookkeeping through the last LOG4, so it overcounts the emitter itself:

| Seats | LOG4s | Instructions in measured region | Region gas |
|---:|---:|---:|---:|
| 4 | 1 | 314 | 3,171 |
| 5 | 2 | 433 | 5,696 |
| 6 | 2 | 457 | 5,764 |
| 7 | 2 | 481 | 5,832 |
| 8 | 2 | 500 | 5,886 |

At most `1000/4 = 250` rounds can execute in one call even if all other charges were free.
Round seeds allocate 128 bytes each; the fixed seat/frame allocation plus these seeds stays
below 64 KiB. The emitter uses one scratch ABI word without advancing the free-memory pointer,
so a one-word memory expansion costs at most 12 gas; a 64-gas memory allowance is
conservative. The 10,000-gas emitter allowance therefore covers all five paths with slack.

Reveal and seat-loop bound: `25,000 - 2,149 + 10,000 = 32,851` (the 25,000 loop allowance,
less the 2,149 gas of a 128-byte LOG2 the emitter does not perform, plus the emitter
allowance). `_runRound` charges 4 compute/event units, giving `ROUND_UNITS = 38`; a fully
split round reserves 166 units.

## Header-tail drain pricing (2026-10-01)

The user authorized removing the first-call 35% derate and requires at least 99%
of normal calls at 10M gas or less. After measuring uniform pricing, the final
choice prices every physical slot from its prior value: three units if zero and
one if nonzero. Header tails eliminate separate partial-data writes. Completed
words and bitmap initialization use the same classification; stale headers are
classified before their payload is logically reset.

`UNIT_GAS_BOUND = 10,000`, `WRITES_BUDGET_SAFE = 900`. A cold SLOAD followed by
a warm zero-to-nonzero SSTORE costs 22,100 gas, covered by three units. A cold
nonzero read plus rewrite costs 5,000, covered by one. Classification adds small
opcode costs but no additional cold-access charge. Slot contents alone decide
pricing: no transient tracking, caller-supplied gas or warmth enters work sizing.

| Item | Worst / reserve |
| --- | ---: |
| Zero-valued slot write | 3 units / 30,000 gas |
| Nonzero-valued slot write | 1 unit / 10,000 gas |
| Singleton append (at most two writes), including reads allowance | 48,400 gas |
| Eight-lane append (bitmap, header, completed word), including reads allowance | 70,500 gas |
| Fully split round | 1,638,451 gas / 166 units |
| First 256 per-entry occurrences | 6 units each |
| Additional per-entry occurrences | 1 unit each |
| Foil pack | 83 units |
| Drain budget | 900 units |
| Fixed entry/exit/keeper overhead allowance | 1,000,000 gas |
| Analytical drain envelope | **10,000,000 gas** |

A singleton can initialize a bucket (header plus bitmap), or complete an already
live tail (header plus word); it cannot do all three. Admission reserves bound
actual step gas even if conservatively charged units exceed a reserve on the
last step. The outer drain does not begin another step without sufficient room.
The fixed allowance covers keeper/entry/exit work; it is an explicit assumption
of this analytical envelope, checked separately in complete transaction fixtures.

Normal chunk fixtures include startup, full recycling, tail flushes, growth
beyond the previous parity backing and later record-volume chunks after 32 real
earlier drain calls. The named 16-day lifecycle enforces at most 1% of keeper
transactions above 10M and none above 16.7M. This fixture gate is evidence for
exercised workloads, not a statistical claim about the entire future game.

The original arithmetic checks were not independent runtime measurements. The
current `test/gas/TicketDrainWorstCaseBound.t.sol` checks cold checkpoint reserves
and sizing targets for the replacement implementation, not this retired unit model.
