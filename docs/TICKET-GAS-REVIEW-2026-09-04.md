# Ticket gas review — 2026-09-04

Reviewed purchase-time owner registration, queued balances, current/future ticket drains,
seated rounds, and packed bucket writes. This is a focused gas review, not a new full audit.

## Applied optimization

`DegenerusGameStorage._bucketAppendRun` now fills a partial eight-lane word with one
masked write instead of iterating over each appended lane. It retains the existing
storage format, owner ordering, fresh/dirty budget charges, and round/trait generation.
The change affects both the normal-ticket and shared foil/round helper paths.

## Measured results

A/B builds used Solidity 0.8.34, via IR, optimizer 1,000 runs, Osaka, with identical
Foundry addresses and harness inputs. Only the packed-tail helper changed between builds.

| Complete queue | Original gas | Updated gas | Saved | Reduction |
| --- | ---: | ---: | ---: | ---: |
| 600 buyers, 8 entries each | 36,479,194 | 36,226,170 | 253,024 | 0.694% |
| 8 buyers, 2,000 entries each | 80,878,521 | 80,026,812 | 851,709 | 1.053% |
| 1 buyer, 5,000 entries | 51,748,656 | 51,574,376 | 174,280 | 0.337% |

Four entries constitute a whole ticket. Batch counts remained 7, 14, and 18 respectively;
the complete emitted-event digests matched for each A/B pair. All final owed balances
were zero. The existing 12 single-chunk benchmarks saved 3,948–42,647 gas each.
Foundry mint runtime shrank 28 bytes (24,406 → 24,378), and foil runtime shrank 26 bytes
(18,192 → 18,166). Deployment-specific addresses can change these absolute sizes.

These are synthetic execution comparisons, not live transaction fee estimates.
The complete-drain harness resets access warmth between calls with `vm.cool`, but it
runs them in one test transaction: original storage values and refund accounting do
not reset as they would between real transactions. Intrinsic transaction gas is excluded.
The existing benchmark names “cold” and “warm” select initial/resumed cursor behavior;
they should not be read as a guarantee that all storage access is transaction-cold.

## Remaining opportunities

The major storage savings already exist: eight indices per word, whole-word writes for
rounds, histogrammed runs for individual buyers, and constant-time queue release.
Purchase-time owner registration moves registration work to the purchase; it does not
eliminate that storage cost. Raising the batch budget alone would not lower cost per entry.

There is no evidence from this pass for a further large drop-in saving in the storage path.

## Applied optimization 2: seats by registry position

`RoundTraitsGenerated` now carries `uint256 seatOwners` in place of `address[] players`:
lane j holds seat j's registry position plus one, so a zero lane is an empty seat. The
position resolves through the new `EntryOwnerRegistered(lvl, idx, owner)` event, emitted
once per owner per level at both registration sites (the shared sink helper and the foil
buy path). The indexer is log-only, so this is the resolution rule: keep a per-level
position map from `EntryOwnerRegistered`, then map each round's lanes through it.

Same harness, same inputs, measured against the build above (tail-word optimization in):

| Complete queue | Before | After | Saved | Reduction |
| --- | ---: | ---: | ---: | ---: |
| 600 buyers, 8 entries each | 36,226,170 | 35,592,946 | 633,224 | 1.748% |
| 8 buyers, 2,000 entries each | 80,026,812 | 77,824,022 | 2,202,790 | 2.753% |
| 1 buyer, 5,000 entries | 51,574,376 | 51,574,376 | 0 | 0% |

The single-buyer queue drains through the per-entry path and never seats a round, so it
is unchanged by construction. Round chunks dropped 70k–110k each; per-entry chunks are
unchanged. Event digests changed by design (the schema changed). The cost that moved:
one `EntryOwnerRegistered` log (about 1,650 gas) on the transaction that first queues an
owner at a level, paid by that owner rather than by the drain crank.

Sizes (Foundry addresses): foil module 18,166 → 17,996 (−170). The registration emit
inlines into every module that queues entries: mint 24,378 → 24,444 (+66, 132 headroom),
advance +67, jackpot +74, lootbox +75. `DegenerusGame` unchanged.

Consumers updated: `test/fuzz/RoundDrain.t.sol`, `test/fuzz/SnapValve.t.sol` (signature
and decode). No script or indexer artifact in this repo referenced the old signature.

## Reproduction

`test/gas/TicketOptimizationGas.t.sol` retains the complete-drain benchmarks and event
digests. `test/fuzz/BucketAppendRun.t.sol` compares packed words against logical owner
sequences, including zero and maximum indices, empty runs, every tail alignment, and
fresh/dirty accounting. Local A/B logs are under `audit/ticket-gas-2026-09-04/` (ignored).

Final regression run against current working-tree contracts: **113 passed, zero failed or
skipped**, across ten suites covering packed lanes, 1,000-case fuzz tests, round conservation,
ticket lifecycle, future queues, constant-time release, golden foil tickets, midday foil
swaps, gas budgets, and the benchmarks. Both source gates for caller-independent drains
and bounded queue release passed; `git diff --check` passed.
