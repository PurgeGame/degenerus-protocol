# Weekly gas review — 2026-09-24

## Scope and method

Compared `8330d94d` (September 17, before the week's changes) with `f3c8839a`
(September 24): 88 commits, including merges, touching 60 files under `contracts/`.
The concurrent ticket fix `20a0e892` also passed an 82-test follow-up on the affected
purchase-day, century-transition, early-ticket and terminal scenarios. The new gas
optimizations below are measured against that commit with identical inputs and
production compiler settings.

Both revisions use Solidity 0.8.34, via IR, optimizer runs 1,000, Osaka, and
Foundry `1.6.0-nightly` / `c07d504b4ae67754584f4e05ff0c547a43c50f7b`.
The baseline and follow-up use isolated worktrees and the repository's predicted
Foundry addresses. The initial run's 100 test artifacts were checked against the
committed advance/storage source hashes; none incorporated concurrent workspace edits.

Measurements below are the tests' instrumented production calls, not Forge's gas
total for the entire test function. Cold-transaction fixtures finish setup before
measurement. Tables identify when transaction intrinsic gas is included. Synthetic
multi-call drain totals and same-transaction warm measurements are comparisons,
not transaction fee estimates. Changed economics and RNG outcomes can change the
work performed by an otherwise identically named scenario.

## Avoidable costs found and optimized

The review found three concrete sources of wasted work in the week's additions.
The production patch touches only `CoinDrawBattle.sol` and
`DegenerusGameGameOverModule.sol`; interfaces and storage layout are unchanged.

| Identical workload, before → optimized | Before | Optimized | Saved |
|---|---:|---:|---:|
| Coin battle, mean over 150 sampled fields | 2,652,622 | 2,411,195 | 241,427 (9.10%) |
| Coin battle, largest sampled call | 3,024,052 | 2,792,765 | 231,287 (7.65%) |
| Coin battle, 50 distinct address low bytes | 2,412,866 | 2,137,337 | 275,529 (11.42%) |
| Dead-VRF tally, 3,000 unsnapped registry records | 9,042,696 | 7,687,021 | 1,355,675 (14.99%) |
| Dead-VRF tally, 3,000 foil records | 7,687,910 | 7,073,007 | 614,903 (8.00%) |
| Dead-VRF finishing batch, 2,744 records + traits + refunds | 9,959,803 | 8,719,869 | 1,239,934 (12.45%) |

The dead-VRF rows include intrinsic gas and use cold production storage. Battle
rows measure the call without intrinsic. The 150-field sampler includes three
budget-truncated fields; its others seat all 50 entrants. Its sampled maximum is
not the theoretical maximum: the existing 7.31M bound remains in force.

### GAS-01 — Repacking a balance solely to unpack it again

**Location:** [GameOverModule._deadWeight](../../contracts/modules/DegenerusGameGameOverModule.sol).
**Severity:** Low, gas inefficiency. **Status:** Optimized.

The new deterministic ending used `_snapOwedPacked` to divide a queued balance,
divide/modulo it into whole entries and a fractional remainder, combine those with
owner and snap metadata, then immediately unpack and recombine it into a scaled
weight. The ending needs only the weight. Calculate it once and shift directly
when the record is not already snapped.

This change alone saved **788,743 gas** on 3,000 unsnapped records. For nonzero
shifts, recombining the snap helper's quotient and remainder equals the original
scaled weight shifted right. For zero shifts or already-snapped records, the
original weight is retained. A zero weight remains zero. The parity suite feeds
the actual production tally arbitrary `uint80` records and all `uint8` shifts,
comparing its writes against the original packing implementation.

### GAS-02 — Recomputing storage addresses inside a frozen batch

**Location:** [GameOverModule.tallyDeadVrf](../../contracts/modules/DegenerusGameGameOverModule.sol).
**Severity:** Low, gas inefficiency. **Status:** Optimized.

The registry loop called the general single-record accessor for every owner,
repeating mapping/array address calculations and its nonzero-position guard.
The foil loop repeated array indexing work for every record. Both arrays remain
unchanged throughout this tally, and both loops already enforce their bounds.
Cache each array's data base and load its bounded record directly. The foil base
is calculated only for a nonempty remainder of the day's bucket.

The registry cache adds **566,932 gas** of savings beyond GAS-01. The foil walk
saves **614,903 gas** per 3,000 records. Exact storage-write parity covers mixed
levels, empty days, partially processed buckets, all tally stages, and pause/
resume boundaries at the 3,000-unit limit. No external call occurs during either
walk; scratch-memory hashing uses only the EVM's designated scratch region.

Tradeoff: the all-empty 3,000-day scan costs **7,087,903**, up **9,003 gas (0.13%)**.
The conditional cache avoids the much larger empty-day overhead of an unconditional
hash. The separate 256-trait claim remains **7,164,936 gas**, unchanged.

### GAS-03 — Scanning the whole drawn field for every new wallet

**Location:** [CoinDrawBattle.resolve](../../contracts/CoinDrawBattle.sol).
**Severity:** Low, gas inefficiency. **Status:** Optimized.

The new battle folded repeated wallets into units by scanning its growing list
for every entrant. Fifty distinct wallets require 1,225 address comparisons.
Track the low byte of each encountered address in a 256-bit memory mask: an
unused bit proves a wallet is new, so it can append immediately. A set bit still
runs the original exact-address scan. This is a filter, never a uniqueness test;
collisions cannot merge wallets or alter first-drawn order or tie resolution.

Measured mean saving: **241,427 gas** per sampled battle. Even a 50-wallet field
with identical low bytes measured **2,367,316**, down from **2,381,038**; it retains
the original bounded scan. The fixed 50-copy single-wallet case increases from
**62,165 to 64,466 gas** (+2,301); one entrant remains essentially flat
(**27,620 → 27,618**). This small repeat-heavy cost buys the much larger saving
on distinct fields. No additional storage or external calls are introduced.

The independent payout-rule test now also fuzzes deliberately colliding wallet
addresses, repetitions, and address zero. Both random and colliding fields check
the original gas model as well as exact player order, unit-weighted payouts,
rounding and the pot winner. Dedicated gas regressions retain the distinct-field
saving and cap collision/repeat costs.

## Follow-up: merging repeats versus separate bets (2026-09-25)

**Decision: retain the current merge for its gas savings on repeated wallets.**
Separate entries are valid; per-entry rounding differences were explicitly accepted
for this comparison. The simpler alternative removes the duplicate scan and held-unit
array, copies the funded entrants directly, and resolves/rounds/emits once per entry.
It preserves the wallet-keyed board and dice and awards the pot only once.

Compared with committed `0faee98e`, using 100 deterministic words and wallet fields
per row, a fixed 150,000-FLIP budget, and the same production compiler settings:

| Entries | Distinct wallets | Current merge | Separate bets | Cheaper approach |
|---:|---:|---:|---:|---|
| 50 | 50 | 2,367,732 | 2,320,022 | Separate by 47,710 (2.0%) |
| 50 | 49 | 2,320,052 | 2,320,884 | Approximately equal |
| 50 | 48 | 2,275,288 | 2,323,393 | Merge by 48,105 |
| 50 | 45 | 2,126,991 | 2,318,521 | Merge by 191,530 |
| 50 | 40 | 1,895,874 | 2,308,300 | Merge by 412,426 |
| 50 | 25 | 1,244,723 | 2,296,438 | Merge by 1,051,715 |
| 16 | 16 | 735,556 | 728,308 | Separate by 7,248 |
| 16 | 8 | 384,878 | 735,007 | Merge by 350,129 |
| 16 | 1 | 62,797 | 760,282 | Merge by 697,485 |

These are mean **resolve-call** measurements, excluding intrinsic gas and the
subsequent Coinflip credits. Every sample uses a fresh caller frame to avoid
accumulated caller-memory expansion. Account warmth is symmetric between the two
alternatives. The absolute figures differ from the earlier 150-field benchmark,
which used a different field/word/budget distribution; only paired rows here are
comparable. Duplicate payout credits would add more work to the separate version.

One repeat is approximately the break-even point in this sample. At two repeats,
merging was cheaper in 99 of 100 fields; at five or more, it won every sampled
field. This is a scenario comparison, not an assumed live repeat frequency.
The draw can encounter the same wallet across different future levels, so repeat
fields matter even though each level is walked without revisiting its lanes.

Separate bets use less code: runtime shrinks from **5,878 to 5,610 bytes**. The
small all-distinct saving does not justify losing the large repeated-wallet saving
for the gas-focused objective. Production code remains unchanged in this follow-up.

**Verification:** 12 comparison tests passed, including 1,000 fuzz cases checking
identical per-wallet run results, roll counts, pot recipient, and pot amount.
All-distinct fields also match exact returned payouts. No aggregate-payout equality
was required for repeats, because per-bet rounding was allowed to differ.

The experiment and measured results are preserved locally under
`.audit-test-logs/gas-merge-comparison-2026-09-25/`: `results.json`,
`final/focused.log`, and `experiment/test/{gas,helpers}/`. To reproduce in a
throwaway checkout of `0faee98e`, copy the two experimental Solidity files into
the same `test/` paths, then run:

```sh
python3 scripts/test-foundry-groups.py \
  --file test/gas/CoinDrawMergeComparison.t.sol \
  --log-dir .audit-test-logs/gas-merge-comparison
```

## Validation of the optimization patch

- Initial arithmetic-only change: **33 tests passed**.
- Final optimization microbenchmarks and parity checks: **30 tests passed**,
  including 1,000-run properties for arbitrary snap words, mixed tally stages,
  random battle fields, colliding battle fields, and roll-budget behavior.
- Final production advance/ending follow-up: **68 passed, 0 failed, 0 skipped**
  across eight test sources. This includes the payout and gas-model fuzz checks,
  cold terminal paths, purchase-day payouts, and the full nested battle composition.
- All ten source-gate targets passed. Compiled ABIs and normalized storage layouts
  match the pre-optimization artifacts exactly for both changed contracts.
- Compiled test metadata was checked against the exact two production files copied
  into the working tree; every referenced source hash matched.
- Foundry runtime size: GameOverModule **10,169 → 10,055 bytes**; CoinDrawBattle
  **5,845 → 5,878 bytes**. Both remain far below the deployment limit.

The tally reference is preserved as independent source in
[DeadVrfTallyParity.t.sol](../../test/fuzz/DeadVrfTallyParity.t.sol), copied from
`20a0e892`. It compares ordered storage writes and completion status from the
same snapshot, including consecutive resumed calls. Baseline/candidate benchmarks
use isolated checkouts, not a modified compiler configuration.

Reproduce the optimization checks:

```sh
python3 scripts/test-foundry-groups.py \
  --file test/fuzz/DeadVrfTallyParity.t.sol \
  --file test/gas/DeadVrfEndingGas.t.sol \
  --file test/craps/CoinDrawBattle.t.sol \
  --file test/gas/CoinDrawDedupGas.t.sol \
  --file test/gas/PurchaseDailyWorstCase.t.sol \
  --file test/gas/AdvanceNestedFullCompositionGas.t.sol \
  --log-dir .audit-test-logs/gas-optimization-rerun
```

The broader weekly measurements below describe changes that were already
committed before this optimization patch; they are separate from the savings above.

## Week-over-week costs

Gas excludes intrinsic unless the underlying test explicitly includes it. These
are reproducible scenario comparisons, not a claim that every workload changes
by the same percentage.

| Scenario | Before | Reviewed revision | Change |
|---|---:|---:|---:|
| Open 100 small boxes | 2,091,245 | 1,609,420 | −23.04% |
| Open 100 mixed-tier boxes | 2,586,431 | 2,069,395 | −19.99% |
| Open 100 saturated custom boxes | 2,865,308 | 2,236,460 | −21.95% |
| 305-recipient ETH jackpot, module fixture | 7,202,627 | 6,928,945 | −3.80% |
| Level-100 phase-ending advance | 9,141,117 | 7,178,549 | −21.47% |
| Drain 600 buyers × 8 entries, sum of batches | 35,592,946 | 34,727,022 | −2.43% |
| Drain eight whales × 2,000 entries, sum of batches | 77,824,022 | 79,013,162 | +1.53% |
| Level-100 transition completion | 982,546 | 2,482,134 | +152.62% |

The transition completion now includes additional protocol work, including deity
ticket grants and century recycling. Its dedicated cold fixtures measured
2,524,503–2,575,803 gas including intrinsic. This increase remains well inside the
transaction budget, while the preceding phase-ending and carryover calls became cheaper.

The direct entry-reveal A/B test measures **242,684 additional gas for 4,096
entries**, or **59.25 gas per entry**, with identical ordered storage writes and
owner/trait inventory. That is a measured feature cost to retain in future budgets.

Existing batching is effective: an automatic five-pass sDGNRS purchase costs
1,905,259 gas for the subscriber-stage call, while 100 passes cost 1,913,266—only
8,007 more. The queue-cache parity test also confirms one queue-word read instead
of eight for an aligned group of eight owners.

## Cold transaction measurements

These figures include intrinsic gas. The recurring advance review target is
15,000,000; the transaction ceiling asserted by the tests is 16,777,216.

| Scenario at `f3c8839a` | Gas |
|---|---:|
| Century consolidation with failed 365-day vault settlement | 12,868,818 |
| Cold subscriber eviction chunk | 10,338,751 |
| Normal terminal payout, 305 awards and 30 refunds | 10,309,247 |
| Jackpot coin/ticket stage, 25 opener seats and 96 ticket awards | 8,972,214 |
| RNG settlement plus six maximum-depth protocol boon draws | 1,822,108 |
| Genesis initialization, both protocol deities over 100 levels | 16,377,397 |

**Genesis is the tightest measured call:** 399,819 gas (2.38%) remains below the
transaction ceiling. It is a one-time initialization, outside the recurring
advance target. Its existing regression verifies one write per queue word and
registry length, and one complete owner/owed-record write per owner. Preserve
that batching and its explicit transaction-cap test when changing initialization.

The composed full-battle fixture measures all 50 entrants reaching 200 rolls and
adds 1,210,000 gas for the complete shooter allowance. Its maximum-roll variant
changes fixture records in the test body; treat that result as a synthetic work
envelope, not a fully cold transaction receipt. The ordinary composition and
century fixtures separately use cold transaction setup.

## Added coverage and repaired benchmark

Added [DeadVrfEndingGas.t.sol](../../test/gas/DeadVrfEndingGas.t.sol) to measure the
real Game → Advance → GameOver call chain with cold storage, asserted progress,
actual payouts, and a 15M ceiling:

| New scenario at `f3c8839a`, including intrinsic | Gas |
|---|---:|
| 3,000 registry positions, with unsnapped weight adjustment | 9,042,696 |
| 3,000 undrained foil records | 7,687,910 |
| 3,000 empty foil-day steps | 7,078,900 |
| Final 2,744 registry positions + 256 trait buckets + 30 refunds + pot fixation | 9,959,803 |
| Claim across all 256 traits, distinct cold bitmap writes | 7,164,936 |

The claim case verifies the credited amount and rejects a repeated claim. The
finishing case verifies all 256 populated traits, the exact uncreated weight,
the 600 ETH of refunds, and the resulting 4,400 ETH pot. The fixtures restore
production runtime before every measured operation.

The Hardhat picker benchmark initially failed because `JackpotSoloTester`, which
inherits the entire jackpot module and adds a wrapper, was 24,604 bytes. The
production module was 24,481 bytes under Hardhat's local wiring. Added a shared
[test fixture](../../test/helpers/jackpotSoloFixture.js) that installs the test
runtime at a synthetic address, preserving production deployment-size enforcement.
All five consumers use it. The measured picker delta is **1,236 gas**, under
the unchanged 1,500-gas bound. Its gas, unit and integration checks pass.

Local Hardhat runtime-size margins are narrow: CrapsBattle has 89 bytes remaining,
and JackpotModule has 95. Address-dependent compilation matters: the Foundry
CrapsBattle fixture measured 24,419 bytes. Validate final deployment pins before
using these local byte sizes as deployment evidence.

## Verification and reproduction

The initial Foundry gas run reported 196 passes, 10 failures and 13 existing
skips. All ten failures expected the purchase payout while the new early-ticket
activation took its preceding ticket stage. Their small measured gas values do
not represent payout costs. The `20a0e892` follow-up retains the original stage,
winner-count and gas-ceiling assertions. All **82 follow-up tests passed**, including
every previously failing scenario; no assertion was weakened.

- Pre-week Foundry gas baseline: **127 passed, 13 skipped**.
- Focused changed-path checks at `f3c8839a`: **159 passed**, including 1,000-run
  fuzz properties for the changed ticket, whale-award and battle paths.
- New dead-VRF gas cases at `f3c8839a`: **5 passed**.
- Hardhat gas suite after the fixture repair: **23 passed, 11 pending**.
- Picker gas/unit/integration check: **22 passed, 2 pending**.

Existing skipped/pending tests are not counted as evidence. Some older Hardhat
stage descriptions and reference-only tests are stale; the explicit-work Foundry
fixtures provide the principal transaction-ceiling evidence.

Raw logs, test-source lists, extracted metrics and artifact-source checks are
under `.audit-test-logs/gas-week-2026-09-24/` (local, git-ignored). The baseline is
in `baseline/`, the initial gas run in `head/`, changed-path checks in
`changed-paths/`, new terminal cases in `dead-vrf/`, and the latest-commit follow-up
in `latest/`. Hardhat's completed repaired run is `hardhat/gas-fixed.log`.
Optimization A/B runs are in `optimization-weight/`, `optimization-cache/`,
`optimization-final/`, and `optimization-integration/`.

To rerun all current Foundry gas sources with production compiler settings:

```sh
python3 - <<'PY'
from pathlib import Path
import subprocess
files = sorted(set(Path('test/gas').glob('*.t.sol'))
               | set(Path('test/craps').glob('*Gas.t.sol'))
               | set(Path('test/fuzz').glob('*Gas.t.sol')))
command = ['python3', 'scripts/test-foundry-groups.py',
           '--log-dir', '.audit-test-logs/gas-review-rerun']
for path in files:
    command += ['--file', str(path)]
subprocess.run(command, check=True)
PY
```

Run `npx hardhat test test/gas/*.test.js` in a separate checkout: its deployment
fixture rewrites address pins. Do not run both harnesses against the same source
tree concurrently.
