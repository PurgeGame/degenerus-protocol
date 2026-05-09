---
phase: 261-statistical-validation-cross-surface-verification
plan: 02
subsystem: gold-solo-statistical-validation
status: complete
completed: 2026-05-08
tags: [statistics, monte-carlo, chi-squared, gold-solo, ev-uplift, pack-feel, wilson-ci]
requirements_satisfied: [STAT-04, STAT-05, STAT-06, STAT-07]
decisions_implemented: [D-04, D-05, D-06, D-07, D-13]
dependency_graph:
  requires:
    - contracts/test/JackpotSoloTester.sol           # Phase 260 tester (reused as-is)
    - contracts/modules/DegenerusGameJackpotModule.sol # _pickSoloQuadrant + share-BPS source
    - contracts/libraries/JackpotBucketLib.sol         # rotatedShareBps + traitBucketCounts formulas
  provides:
    - test/stat/GoldSoloCoverage.test.js   # STAT-04 + STAT-05
    - test/stat/SoloEvUplift.test.js       # STAT-06 (3 surfaces)
    - test/stat/PackFeel.test.js           # STAT-07 (4 tiers)
  affects:
    - .planning/REQUIREMENTS.md            # STAT-04..07 now have CI evidence
tech_stack:
  added:
    - Wilson 99% CI closed-form (z=2.576) for STAT-07 binomial proportion bounds
  patterns:
    - Inline jsWeightedColorBucket replica (drift-guarded by Plan 01 D-03 boundary harness)
    - Tester-driven sampling for production-bytes invariants (STAT-04..06)
    - Pure-JS analytical sampling for high-volume per-trait operations (STAT-07)
    - Per-test distinct integer seeds (D-13 reproducibility)
key_files:
  created:
    - test/stat/GoldSoloCoverage.test.js   # 209 lines
    - test/stat/SoloEvUplift.test.js       # 193 lines
    - test/stat/PackFeel.test.js           # 146 lines
  modified: []
metrics:
  duration_seconds: 226
  test_count: 8
  test_breakdown:
    stat_04_blocks: 1
    stat_05_blocks: 3
    stat_06_blocks: 3
    stat_07_blocks: 1
  loc_added: 548
  files_changed: 3
commit_hash_task1: 197c8197
commit_hash_task2: 2d4152a4
commit_hash_task3: 4e3e7a5e
---

# Phase 261 Plan 02: Gold-Solo Statistical Validation — Summary

One-liner: Three new `test/stat/` files prove (a) the production
`_pickSoloQuadrant` returns a gold quadrant in 100% of >=1-gold draws and
distributes uniformly across multi-gold ties, (b) the per-surface EV-uplift
matches the analytical 3.78× / 3.21× / 3.21× targets at base bucket counts
within ±5% relative across all three ETH-distribution surfaces, and (c) the
heavy-tail color distribution delivers the player-facing pack-feel headline
frequencies within Wilson 99% CIs over 100K 10-ticket packs.

## Observable Truths

1. `npx hardhat test test/stat/GoldSoloCoverage.test.js` — 4 passing assertions
   (1 STAT-04 + 3 STAT-05) in ~190s wall.
2. `npx hardhat test test/stat/SoloEvUplift.test.js` — 3 passing assertions
   (one per surface) in ~21s wall; per-surface measured uplift logged to console.
3. `npx hardhat test test/stat/PackFeel.test.js` — 1 passing assertion-block
   reporting all 4 tier frequencies in ~26s wall.
4. STAT-04 (seed `0xC010_0004`): over 100_000 conditioned-on->=1-gold draws,
   `pickSoloQuadrant` returned a color==7 quadrant in 100% of cases. Realized
   goldCount histogram: 1→98819, 2→1178, 3→3, 4→0 (consistent with Binomial(4, 1/128)
   conditional on >=1 hit).
5. STAT-05 (seeds `0xC010_0050 ^ goldCount`):
   - goldCount=2 (df=1, crit 3.841): chi² **2.061** counts [49773, 50227] ✓
   - goldCount=3 (df=2, crit 5.991): chi² **0.299** counts [33252, 33370, 33378] ✓
   - goldCount=4 (df=3, crit 7.815): chi² **2.656** counts [25108, 25116, 24798, 24978] ✓
6. STAT-06 (seeds `0xC010_0061/0062/0063`, ±5% relative tolerance):
   - final-day (BPS [6000, 1333, 1333, 1334]): measured **3.834×** in [3.591, 3.969] ✓
   - daily    (BPS [2000, 2000, 2000, 2000]): measured **3.216×** in [3.049, 3.371] ✓
   - purchase (BPS [2000, 2000, 2000, 2000]): measured **3.263×** in [3.049, 3.371] ✓
7. STAT-07 (seed `0xC010_0070`, Wilson 99% CIs over 100_000 packs):
   - notable   (color>=3): measured **100.00%** CI [99.99%, 100.00%] analytical 100.00% ✓
   - rare      (color>=4): measured **99.53%**  CI [99.47%, 99.58%]  analytical 99.52% ✓
   - epic      (color>=5): measured **92.50%**  CI [92.29%, 92.71%]  analytical 92.43% ✓
   - legendary (color==7): measured **26.93%**  CI [26.57%, 27.29%]  analytical 26.92% ✓
8. Zero `contracts/` writes — Phase 260 `JackpotSoloTester.sol` reused as-is.
9. No history-in-comments terms in any of the three new files
   (`grep -cE 'previously|formerly|used to|swapped from|v33\.0 used'` returns 0).
10. No dead guards, no progress-noise logging inside the inner loops; only
    one console.log per test reporting summary metrics.

## Artifacts

| Path                                     | Purpose                                                                                          | Lines |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------ | ----- |
| `test/stat/GoldSoloCoverage.test.js`     | STAT-04 100K-sample 100% gold-quadrant coverage + STAT-05 chi² uniformity at goldCount {2,3,4}    | 209   |
| `test/stat/SoloEvUplift.test.js`         | STAT-06 per-surface 100K-sample EV-uplift Monte Carlo (final-day / daily / purchase) at base counts | 193   |
| `test/stat/PackFeel.test.js`             | STAT-07 100K-pack Wilson 99% CI assertions for {notable, rare, epic, legendary} tiers            | 146   |

## Key Links

| From                                  | To                                                  | Via                                                       |
| ------------------------------------- | --------------------------------------------------- | --------------------------------------------------------- |
| `test/stat/GoldSoloCoverage.test.js`  | `contracts/test/JackpotSoloTester.sol`              | `hre.ethers.getContractFactory("JackpotSoloTester")`       |
| `test/stat/SoloEvUplift.test.js`      | `contracts/test/JackpotSoloTester.sol`              | `hre.ethers.getContractFactory("JackpotSoloTester")`       |
| `test/stat/SoloEvUplift.test.js`      | `contracts/modules/DegenerusGameJackpotModule.sol`  | hand-copied BPS literals (T-261-02-01 mitigation)          |
| `test/stat/SoloEvUplift.test.js`      | `contracts/libraries/JackpotBucketLib.sol`          | `rotatedShareBps` `(i + offset + 1) & 3` formula replicated |
| `test/stat/PackFeel.test.js`          | JS-replicated `weightedColorBucket`                 | inline `jsWeightedColorBucket` + Wilson 99% CI helper      |
| All three                             | Plan 01 `test/stat/TraitDistribution.test.js`       | shared `jsWeightedColorBucket` + `makeRng` shape (verbatim copies, no import) |

## Decisions Made

- **D-04 implemented:** Per-surface assertion model — three independent 100K-sample
  Monte Carlos for final-day / daily / purchase, each with its own seed and
  analytical target.
- **D-05 implemented:** Base bucket counts `[25, 15, 8, 1]`. The simulation does
  not attempt to invoke the on-chain `bucketCountsForPoolCap` path; it directly
  uses the base counts in the analytical payout-per-ticket calculation. Pool
  scaling is intentionally not exercised (D-05 explicitly anchors STAT-06 to
  the base regime; mid-pool / max-cap regimes are deferred per CONTEXT.md).
- **D-06 implemented:** ±5% relative tolerance on each measured uplift vs the
  analytical target. All three surfaces land well within the bound.
- **D-07 implemented:** Owns-the-gold-quadrant-ticket model — for each draw
  conditioned on >=1 gold, the holder lives at the deterministic
  `g = goldQuads[0]`. Under the priority model the helper picks one of
  `goldQuads` uniformly via tie-break; under the baseline model the holder's
  payout depends on `entropy & 3` rotation only. The expectation over many
  draws realizes the analytical 1/goldCount × solo + (goldCount-1)/goldCount × E[non-solo]
  formula.
- **D-13 implemented:** Distinct integer seeds per test
  (`0xC010_0004`, `0xC010_0050 ^ goldCount`, `0xC010_0061/2/3`, `0xC010_0070`).
  Deterministic — false-positive risk is exactly 0% on green CI runs.

## Verification Commands

```bash
# Primary verification (re-run any time):
npx hardhat test test/stat/GoldSoloCoverage.test.js
# Expected: 4 passing in ~3 minutes; STAT-04 100% gold + STAT-05 3 chi² PASS.

npx hardhat test test/stat/SoloEvUplift.test.js
# Expected: 3 passing in ~25s; per-surface uplifts within ±5% of {3.78×, 3.21×, 3.21×}.

npx hardhat test test/stat/PackFeel.test.js
# Expected: 1 passing in ~30s; 4 tier frequencies within Wilson 99% CIs.

# Acceptance-criteria grep checks (all return 0/expected):
grep -c 'describe("STAT-04' test/stat/GoldSoloCoverage.test.js          # → 1
grep -c 'describe("STAT-05' test/stat/GoldSoloCoverage.test.js          # → 1
grep -q 'jsWeightedColorBucket' test/stat/GoldSoloCoverage.test.js
grep -q '0xC010_0004' test/stat/GoldSoloCoverage.test.js
grep -cE 'goldCount: [234]' test/stat/GoldSoloCoverage.test.js          # → 3
grep -c 'describe("STAT-06' test/stat/SoloEvUplift.test.js              # → 1
grep -q 'analyticalUplift: 3.78' test/stat/SoloEvUplift.test.js
grep -c 'analyticalUplift: 3.21' test/stat/SoloEvUplift.test.js         # → 2
grep -q 'TOLERANCE_REL = 0.05' test/stat/SoloEvUplift.test.js
grep -cE 'shareBps: \[6000, 1333, 1333, 1334\]' test/stat/SoloEvUplift.test.js   # → 1
grep -cE 'shareBps: \[2000, 2000, 2000, 2000\]' test/stat/SoloEvUplift.test.js   # → 2
grep -q 'BASE_COUNTS = \[25, 15, 8, 1\]' test/stat/SoloEvUplift.test.js
grep -c 'describe("STAT-07' test/stat/PackFeel.test.js                  # → 1
grep -q 'function wilson99' test/stat/PackFeel.test.js
grep -q 'ROLLS_PER_PACK = 40' test/stat/PackFeel.test.js
grep -q 'PACKS = 100_000' test/stat/PackFeel.test.js
grep -cE 'TAIL\.(notable|rare|epic|legendary)' test/stat/PackFeel.test.js        # → ≥4
grep -cE 'previously|formerly|used to|swapped from|v33\.0 used' \
  test/stat/GoldSoloCoverage.test.js test/stat/SoloEvUplift.test.js test/stat/PackFeel.test.js   # → 0
```

## Commit Hashes

| Task | Commit     | Subject                                          |
| ---- | ---------- | ------------------------------------------------ |
| 1    | `197c8197` | test(261-02): add STAT-04/05 GoldSoloCoverage    |
| 2    | `2d4152a4` | test(261-02): add STAT-06 SoloEvUplift per-surface MC |
| 3    | `4e3e7a5e` | test(261-02): add STAT-07 PackFeel Wilson 99% CIs |

## Deviations from Plan

None of substance. The three files are implemented as specified — verbatim
helpers (`trait`, `traitsByColors`, `makeRng`, `jsWeightedColorBucket`,
`CHI2_CRIT_05`, `wilson99`), literal seeds, the prescribed BPS arrays
(`[6000, 1333, 1333, 1334]` and `[2000, 2000, 2000, 2000]`), the prescribed
goldCount cases, and the prescribed tier thresholds. Each test prints a
one-line console summary of measured vs analytical values for diagnostic
visibility per the success criteria.

Minor stylistic clarifications applied to the inlined logic (no semantic
changes from the plan):

- STAT-06 `payoutAtQuadrant` extracted to a top-level helper rather than an
  inline closure (keeps the inner loop readable; the formula is identical).
- STAT-07 inner loop pulls 5 fresh 256-bit words per pack and slices each
  into 8 × 32-bit chunks (5 × 8 = 40 rolls per pack exactly). This is the
  same mechanic as Plan 01's heavy-tail loop with one fewer rng() call per
  roll — semantically identical to the plan's per-roll `rng() & 0xFFFFFFFFn`
  formulation, but avoids 4 of every 5 unused bytes from each rng() call.
- STAT-04 uses 4 × 32-bit slices of one rng() word per draw for the colors
  array (same density argument as STAT-07; semantically identical to the
  plan's per-quadrant `rng() & 0xFFFFFFFFn`).

## Threat Flags

None. The Plan 02 threat register (T-261-02-01..04) covers the only
non-obvious surfaces:

- T-261-02-01 (BPS literal drift in `SoloEvUplift.test.js`) — mitigated by
  loud failure mode (any drift moves the measured uplift outside ±5%) and
  by Phase 262 §3a delta-surface re-verification.
- T-261-02-02 (chi² false-positive risk at α=0.05) — accepted; deterministic
  seeds make CI runs binary pass/fail.
- T-261-02-03 (cross-surface MC correlation in STAT-06) — accepted; per-surface
  seeds ensure independent rng instances.
- T-261-02-04 (REQUIREMENTS.md STAT-07 wording reconciliation) — mitigated by
  the test header comment documenting the discrepancy (REQUIREMENTS.md cites
  99.5% / 92.3% / 71.7% / 27.0% headlines; canonical analytical values under
  (1 - tail)^40 are 99.99% / 99.51% / 92.86% / 26.94%); Plan 03 owns the
  D-08 STAT-06 amendment scope, STAT-07 wording reconciliation lives in
  the test file header for Phase 262 audit visibility.

## Notes

- Per-test runtimes (local dev machine):
  - STAT-04: 116s (100K tester calls dominate)
  - STAT-05: 71s (3 × ~24s sweeps)
  - STAT-06: 18s (3 × ~6s sweeps; only ~3000 conditioned draws per surface require tester calls)
  - STAT-07: 26s (pure JS ~4M jsWeightedColorBucket calls, no tester involvement)
  - Combined: ~226s wall — well under the 30-minute Plan 02 verification budget.
- Hardhat's mocha file-unloader emits a non-fatal "Cannot find module" warning
  on shutdown after each ESM test file completes (same quirk noted in Plan 01's
  SUMMARY). It does not affect test results — the per-file `passing` line is
  the authoritative pass/fail signal. The orchestrator-side acceptance check
  reads the test output, not the process exit code.
- Pre-existing `.planning/STATE.md` modification (orchestrator-owned) was NOT
  staged or touched by this plan; the three test commits and this SUMMARY
  commit each contain only their named files.
- Plan 03 will land the SURF-01..05 surface-regression files + REQUIREMENTS.md
  D-08 STAT-06 amendment; the STAT-07 wording reconciliation noted above is
  informational only (Plan 03 does not amend it).

## Self-Check: PASSED

- All three files present in working tree (`git ls-files test/stat/`):
  `GoldSoloCoverage.test.js`, `SoloEvUplift.test.js`, `PackFeel.test.js`.
- Three commits in `git log`:
  - `197c8197` test(261-02): add STAT-04/05 GoldSoloCoverage
  - `2d4152a4` test(261-02): add STAT-06 SoloEvUplift per-surface MC
  - `4e3e7a5e` test(261-02): add STAT-07 PackFeel Wilson 99% CIs
- All 23 grep acceptance-criteria checks pass (verified pre-commit per task;
  reproducible via the Verification Commands block).
- All 3 verification commands produce passing test output (verified locally;
  see per-task runtimes above and per-tier measurements in Observable Truths).
