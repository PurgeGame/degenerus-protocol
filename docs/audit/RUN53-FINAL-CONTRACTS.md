# Ticket-drain charge derivation

Backs `UNIT_GAS_BOUND`, `WRITES_BUDGET_SAFE`, `ROUND_UNITS` and `ROUND_SPLIT_UNITS` in
`contracts/storage/DegenerusGameStorage.sol`. Storage operations are priced by the analytical
model in that file's comment table; the reveal emitter is bounded separately below.

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

## Charges against re-derived worst cases

| Step | Charge gas | Re-derived worst gas | Headroom |
|---|---:|---:|---:|
| Seated round, no split | 380,000 | 282,000 + 56,800 + 32,851 = **371,651** | **8,349** |
| Split quadrant, extra | 320,000 | 8 × 48,400 − 70,500 = **316,700** | **3,300** |
| Seat join | 20,000 | 14,200 | 5,800 |
| Dust skip | 10,000 | 9,200 | 800 |
| Seats word write | 30,000 | 22,100 | 7,900 |
| Per-entry occurrence, first 256 | 60,000 | 51,600 | 8,400 |
| Per-entry occurrence, beyond 256 | 10,000 | 3,200 | 6,800 |
| Foil pack | 830,000 | 814,400 | 15,600 |
| Fully split round | 1,660,000 | **1,638,451** | **21,549** |

With `UNIT_GAS_BOUND = 10,000` and `WRITES_BUDGET_SAFE = 1000`, the analytical ceiling for a
drain call is **11,000,000 gas**, 5,777,216 below 16,777,216. Block metadata is written in the
constructor/request transaction, not in this drain envelope. Transition housekeeping is
separate from charged steps and runs only before the cold first future chunk; the 35%
first-chunk derate leaves 3.5M of unused budget for that leg.

`test/gas/TicketDrainWorstCaseBound.t.sol` checks this model's arithmetic; it is not an
independent measurement of the model.
