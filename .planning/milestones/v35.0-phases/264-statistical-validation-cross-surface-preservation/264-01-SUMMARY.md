---
phase: 264-statistical-validation-cross-surface-preservation
plan: 01
subsystem: testing
tags: [statistics, monte-carlo, chi-squared, per-pull-level, empty-bucket-skip, infra-reuse, boundary-harness]

# Dependency graph
requires:
  - phase: 263-per-pull-level-resample-implementation
    provides: per-pull-level resample helper at HEAD cf564816 (the unit under empirical test)
provides:
  - STAT-01 chi² uniformity over 10K aggregated samples (range=4 df=3 + range=8 df=7)
  - STAT-02 deterministic i % 4 trait rotation confirmation (degenerate JS replica + on-chain cross-check)
  - STAT-04 Phase 261 chi² infra reuse (makeRng / CHI2_CRIT_05 / wilsonHilfertyZ re-declared verbatim)
  - D-IMPL-01 boundary cross-validation harness (≥3 fixed seeds, deity-backed dense fixture, strict per-pull deep.equal)
  - STAT-03 empty-bucket skip rate + cumulative monetary underspend instrumentation (FAILING at HEAD — finding captured)
affects: [265-rng-audit-findings, audit/FINDINGS-v35.0.md §3 AUDIT-06 disclosure]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "JS-replica + on-chain boundary harness with deity-backed dense fixture for strict per-pull deep.equal byte-identity"
    - "Per-pull i-recovery via traitId quadrant decomposition (floor(traitId/64) gives the i % 4 quadrant deterministically)"
    - "Reverse-engineered coinBudget from emitted amount stream (baseAmount = min(amount); extra = count(amount = baseAmount + 1))"

key-files:
  created:
    - test/stat/PerPullLevelDistribution.test.js
    - test/stat/PerPullEmptyBucketSkip.test.js
  modified: []

key-decisions:
  - "Trait derivation in D-IMPL-01 uses doubleSalted = keccak256(saltedRng || BONUS_TRAITS_TAG) per the contract's _rollWinningTraits(saltedRng, isBonus=true) inner keccak — NOT saltedRng directly"
  - "Deity-backed dense fixture (4 purchaseDeityPass calls per quadrant fullSymId) forces every (lvlPrime, trait_i) cell to have effectiveLen ≥ 2 via virtualCount, guaranteeing 50/50 emit count for the strict deep.equal assertion"
  - "Call B identification splits emitted events by lvl ∈ [2, 5] (call A's range=1 events have lvl=1 and are excluded from the strict assertion)"
  - "STAT-03 implemented at the strict 10% threshold per D-IMPL-08; test currently FAILS at HEAD — orchestrator's halt-and-report protocol applied"

patterns-established:
  - "DailyRngApplied event harvest gives the actual contract-side randomWord (rawWord + totalFlipReversals nudge) flowed into _awardDailyCoinToTraitWinners, removing the need to reconstruct it from external state"
  - "Three salt-tier model for the purchase-phase L1 two-call coin-jackpot flow: rngWord → saltedRng (call B's randomWord) → doubleSalted (call B's trait derivation)"

requirements-completed: [STAT-01, STAT-02, STAT-04]

# Metrics
duration: 95min
completed: 2026-05-09
---

# Phase 264 Plan 01: Statistical Validation (per-pull level + per-trait + boundary harness + skip-rate finding) Summary

**Two new ESM Hardhat test files under `test/stat/` empirically validate the Phase 263 per-pull-level resample helper: 10/10 STAT-01/02/04 + D-IMPL-01 assertions pass; STAT-03 empty-bucket skip rate measured at 88.24% on the natural lifecycle fixture (FAR exceeding the 10% threshold) — the test correctly surfaces this finding for Phase 265 D-09 gating.**

## Performance

- **Duration:** ~95 min (heavy boundary-harness drive + STAT-03 lifecycle iteration dominate; pure JS chi² loops are sub-second)
- **Started:** 2026-05-09T14:05Z (approx, executor spawn)
- **Completed:** 2026-05-09T15:40Z
- **Tasks:** 2 of 2 implemented; Task 3 (checkpoint) is end-of-phase batched approval (not executor-actioned)
- **Files modified:** 2 created (no contract or package.json edits per D-IMPL-02 / Plan-01 scope)

## Accomplishments

- **STAT-01** chi² uniformity over 10K aggregated samples — passes for both range=4 (chi² = 5.114 < 7.815, df=3) and range=8 (chi² = 3.019 < 14.067, df=7)
- **STAT-02** per-trait deterministic share — passes (counts = [13, 13, 12, 12] under i % 4 rotation; degenerate chi² = 0.08)
- **STAT-04** Phase 261 chi² infra reuse confirmed in `test/stat/PerPullLevelDistribution.test.js` header (`makeRng` / `CHI2_CRIT_05` / `wilsonHilfertyZ` re-declared verbatim; COIN_LEVEL_TAG and BONUS_TRAITS_TAG sanity-pinned)
- **D-IMPL-01** boundary cross-validation — passes for all 3 fixed seeds (`0xc0120101`, `0xc0120102`, `0xc0120103`); 50/50 emit count under deity-backed dense fixture; strict `expect(onChainLvls).to.deep.equal(jsLvls)` per-pull byte-identity verified across the full call B emit stream over range=[2, 5]
- **STAT-03** empty-bucket skip rate test landed as written at the strict 10% threshold; currently fails at HEAD with measured skipRate = 88.24% — finding fully captured below for Phase 265 carry-forward

## Task Commits

1. **Task 1: PerPullLevelDistribution.test.js (STAT-01/02/04 + D-IMPL-01)** — `65603840` (test)
2. **Task 2: PerPullEmptyBucketSkip.test.js (STAT-03)** — `745e2c5f` (test)
3. **Task 3: Phase 264 Plan 01 batched-approval gate** — checkpoint pending end-of-phase user review (D-APPROVAL-01)

## Files Created/Modified

- `test/stat/PerPullLevelDistribution.test.js` (NEW, 643 lines) — STAT-01/02/04 chi² + D-IMPL-01 boundary harness with deity-backed dense fixture and per-pull `deep.equal` strict-shape assertion
- `test/stat/PerPullEmptyBucketSkip.test.js` (NEW, 340 lines) — STAT-03 skip rate + cumulative underspend instrumentation; reverse-engineers coinBudget from emitted amount stream

## STAT-03 Finding

**Per the orchestrator's halt-and-report protocol, the STAT-03 assertion lands at the strict 10% threshold and currently FAILS at HEAD. The test was NOT modified to make it pass. The orchestrator-mandated finding capture follows.**

### Measured numbers (HEAD `cf564816`, fresh deployFullProtocol fixture, 50 lifecycle iterations)

| Metric                          | Value                              |
|---------------------------------|------------------------------------|
| Aggregated skipRate             | **88.24%** (2206 / 2500 pulls)     |
| Calls completed (events emit)   | 50 / 50                            |
| Mean per-call skip rate         | 88.24%                             |
| Mean emitted per call           | 5.88 / 50 (range 0..12 in first 10 calls) |
| First 10 per-call skip rates    | 80%, 100%, 94%, 84%, 88%, 76%, 86%, 100%, 92%, 88% |
| Cumulative underspend ratio     | **84.92%** of Σ coinBudget         |
| D-IMPL-08 threshold (10%)       | EXCEEDED by ~78 percentage points  |
| D-IMPL-09 threshold (1%)        | EXCEEDED by ~84 percentage points  |

### Fixture state at the measurement point

- **Deployment:** `deployFullProtocol` fresh deploy (no organic purchases beyond constructor pre-queued vault + DGNRS perpetual tickets)
- **Deity passes registered:** 0 (none) — natural distribution baseline
- **Holders per (lvl, trait) cell:** 16 vault + DGNRS perpetual tickets per level distributed across 256 trait buckets at random per advance batch processing — most cells empty, a few populated
- **`compressedJackpotFlag` value:** false (purchase phase, level 0 / purchaseLevel 1)
- **`advanceGame` stage at measurement:** STAGE_PURCHASE_DAILY (stage 6) — fires call A (range=1, lvl=1) + call B (range=4, lvl in [2, 5]) per day
- **Range observed:** call B only (range=4, lvls in [2, 5]) — call A's degenerate range=1 conflates empty-bucket skip with single-bucket emptiness so it is excluded from the STAT-03 measurement

### Analytical interpretation

The post-Phase-263 helper's per-pull-level keccak `lvlPrime = minLevel + (keccak256(randomWord, COIN_LEVEL_TAG, i) % range)` distributes the 50 pulls uniformly across `range = 4` levels (call B [2, 5]) — STAT-01 confirms this empirically. With `i % 4` trait rotation, this yields ~12-13 expected pulls per `(lvlPrime, trait_i)` cell across 16 cells.

For the **natural lifecycle fixture**, the bonus-trait roll picks 4 specific traitIds (one per quadrant) — but the constructor's pre-queued vault + DGNRS tickets are distributed across 256 random trait buckets at advance time. Probability that any one of those tickets lands in one of the 4 specific bonus traits is `4/256 = 1/64`. With ~16 tickets per level for levels 2..5 (~64 tickets total queued for the call B range), expected hits per (lvlPrime, trait_i) cell ≈ `16/64 = 0.25` — meaning ~75% of cells are empty, matching the observed ~88% skip rate after PRNG variance.

This is a **structural property** of the post-Phase-263 helper under sparse-fixture holder distribution: the per-pull-level resample expanded the addressable cell count from 4 (one trait per pull at fixed lvl) to 16 (four traits × four lvl candidates), proportionally diluting the holder density that previously concentrated all 50 pulls onto 4 cells. The trade-off is by design — Phase 263 D-IMPL-01 / D-INDEXER-01 / PPL-05 chose to accept this underspend as the cost of cross-level winner sampling.

### Phase 265 D-09 gating implication

Per D-IMPL-08 thresholds:
- skip rate ≤ 5% → INFO disclosure
- 5% < skip rate ≤ 10% → INFO with warning paragraph
- skip rate > 10% → test FAILS; **promote above INFO (LOW or higher)**

The measured 88.24% under the natural lifecycle fixture decisively crosses into the third tier. Phase 265 should treat the AUDIT-06 disclosure paragraph as a **LOW (or higher)** finding rather than a plain INFO. The disclosure text should:

1. State the measured skip rate (88.24%) and underspend ratio (84.92%) under the constructor-only fixture
2. Identify the structural cause (per-pull-level resample expanded the `(lvl', trait_i)` cell count to 16 vs the pre-Phase-263 helper's effective 4)
3. Note that production fixtures with deity-pass coverage AND organic purchase activity would substantially reduce both numbers (D-IMPL-01's deity-backed fixture confirms: with 4 deity passes pinning virtualCount ≥ 2 across all 4 quadrant traits, skip rate drops to 0% — every pull emits)
4. Distinguish "structural property" (intended trade-off per Phase 263 PPL-05) from "regression" (would require a different cumulative underspend pattern across days)

### Recommended user/auditor actions

The orchestrator's halt-and-report protocol explicitly defers the next step to the user:

> The user will decide whether to (a) tune the fixture for denser holder coverage, (b) widen the test threshold to codify current behavior with a documented AUDIT-06 disclosure, or (c) accept the failing assertion as a Phase 265 input.

The executor's recommendation: **option (c)** — accept the failing assertion as a Phase 265 input. Rationale: the natural-fixture measurement is exactly the empirical evidence Phase 265's REG-03 / AUDIT-06 §3 paragraph needs to cite. Patching the test to pass on a synthetic deity-dense fixture would obscure the production-relevant underspend rate. Option (b) is also reasonable if the team wants the test to PASS at the codified production-floor rate (e.g., 30%) AFTER applying a denser fixture — but that is a Phase 265 editorial decision, not a Phase 264 executor decision.

## Decisions Made

- **D-IMPL-01 strict shape match:** Per orchestrator override, `expect(jsLvls).to.deep.equal(onChainLvls)` is the actual assertion — NOT a multiset/superset relation. The deity-backed dense fixture (4 deity passes, one per quadrant fullSymId) forces 50/50 emit count so per-i mapping is identity. This replaces the original plan's adaptive `findMatchingShape` helper which the orchestrator flagged as silently masking contract-version drift.
- **Trait derivation correction:** `_rollWinningTraits(randomWord, isBonus=true)` applies an INNER `keccak256(abi.encodePacked(randomWord, BONUS_TRAITS_TAG))` salt before passing to `getRandomTraits`. So at purchase-phase L1, call B (whose `randomWord = saltedRng = keccak256(rngWord || BONUS_TRAITS_TAG)`) derives traits from `doubleSalted = keccak256(saltedRng || BONUS_TRAITS_TAG)`, NOT from `saltedRng` directly. Initial draft used the wrong tier; corrected after first run.
- **`JackpotBurnieWin` event field name:** ABI calls the second positional arg `level` (not `lvl`); plan/CONTEXT prose used `lvl` inconsistently. JS test uses `e.args.level` for parsing and `lvl` only as a JS-internal alias.
- **STAT-03 fixture choice:** No deity passes registered — natural lifecycle holder distribution. This deliberately surfaces the post-Phase-263 helper's empty-bucket skip behavior at its production-relevant rate; D-IMPL-01's deity-backed fixture is a separate artifact that proves the boundary-harness shape assertion.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `JackpotBurnieWin` event field name mismatch**
- **Found during:** Task 1 (D-IMPL-01 first run)
- **Issue:** Plan and CONTEXT prose referred to the event's level field as `lvl`; the contract ABI declares it `level`. JS event parser was reading `parsed.args.lvl` (returns undefined → NaN), causing the harness to treat all emitted events as having lvl=NaN.
- **Fix:** Changed to `parsed.args.level` in `harvestJackpotBurnieWinByCall`. Documented the alias in the file header.
- **Files modified:** `test/stat/PerPullLevelDistribution.test.js` (event parser + header comment)
- **Verification:** Diagnostic re-run showed correct lvl values; D-IMPL-01 progressed past parse error.
- **Committed in:** `65603840` (Task 1 commit)

**2. [Rule 1 - Bug] Trait derivation off-by-one-keccak**
- **Found during:** Task 1 (D-IMPL-01 second run after event-name fix)
- **Issue:** Initial draft computed `traitIds = jsGetRandomTraits(saltedRng)` for call B, mirroring the plan reference. The contract's `_rollWinningTraits(saltedRng, isBonus=true)` applies an INNER `keccak256(saltedRng || BONUS_TRAITS_TAG)` before the trait roll. The deity passes purchased for the WRONG fullSymIds did not back virtualCount for the trait IDs the helper actually used → 32/50 emit count instead of 50/50.
- **Fix:** Computed `doubleSalted = jsBonusEntropy(saltedRng)` and used `traitIds = jsGetRandomTraits(doubleSalted)`. Added explanatory header comment for the three-salt-tier flow.
- **Files modified:** `test/stat/PerPullLevelDistribution.test.js`
- **Verification:** Re-run showed 50/50 emit count for all 3 seeds; strict deep.equal passes.
- **Committed in:** `65603840` (Task 1 commit)

**3. [Rule 3 - Blocking] No public view for `deityBySymbol`**
- **Found during:** Task 1 (deity registration verification)
- **Issue:** Initial draft asserted post-registration via `await game.deityBySymbol(fullSymId)`. The mapping is declared `internal`, no public view exists. `TypeError: game.deityBySymbol is not a function`.
- **Fix:** Removed the post-registration verification step. Documented that registration success is implied by the non-reverting `purchaseDeityPass` call (which itself reverts on duplicate-symbol or auth failure). The strict 50/50 emit-count assertion in the same `it` block acts as the structural confirmation.
- **Files modified:** `test/stat/PerPullLevelDistribution.test.js`
- **Verification:** Test passes through to the dense-emit assertion.
- **Committed in:** `65603840` (Task 1 commit)

**Total deviations:** 3 auto-fixed (2 bugs, 1 blocking). All discovered during D-IMPL-01 boundary-harness bring-up. No scope creep.

## Issues Encountered

- **Hardhat ESM cleanup quirk:** After test failures, Hardhat's mocha file-unloader prints `Error: Cannot find module 'test/stat/PerPullLevelDistribution.test.js'` as a trailing error. This is unrelated to test code — it is a known interaction between Hardhat's `TASK_TEST_GET_TEST_FILES` subtask override and mocha's ESM disposal path on non-zero exit. Does not affect test results or assertions; tests run + report normally before the cleanup error fires.

## Next Phase Readiness

**Plan 02 (`264-02-PLAN.md`)** is on the sister worktree branch `worktree-agent-a92df1f983334f71f` and owns:
- `test/stat/SurfaceRegression.test.js` extension (SURF-01..04 byte-identity grep proof)
- `test/gas/Phase264GasRegression.test.js` (SURF-05 gas envelope)
- `test/gas/AdvanceGameGas.test.js` extension (1.99x ceiling check)
- `package.json` `scripts.test:stat` wiring

The two new files from this plan (`PerPullLevelDistribution.test.js` + `PerPullEmptyBucketSkip.test.js`) are NOT yet wired into `package.json` `test:stat` — Plan 02 owns that wiring per the 2-plan packing reference shape.

**Phase 265 inputs ready:**
- STAT-01 chi² evidence (10K-sample uniformity at α=0.05) for REG-03 / AUDIT-02 cross-citation
- STAT-02 deterministic trait rotation evidence for AUDIT-02 trait-stacking adversarial sweep
- STAT-03 measured 88.24% skip rate finding for AUDIT-06 §3 disclosure (LOW-or-higher promotion per D-IMPL-08)
- D-IMPL-01 byte-identity boundary proof for REG-03 RNG envelope re-verification

**Open items:**
- Task 3 batched-approval gate awaits user review of the staged worktree commits (`65603840`, `745e2c5f`). Per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md`, no merge-to-main happens until explicit user approval.
- STAT-03 finding handling (orchestrator decision: capture-and-report; user picks whether to tune fixture, widen threshold, or accept failure as Phase 265 input).

## Self-Check: PASSED

**Files verified to exist:**
- `test/stat/PerPullLevelDistribution.test.js` — 643 lines, contains `jsLvlPrime`, all acceptance grep checks pass
- `test/stat/PerPullEmptyBucketSkip.test.js` — 340 lines, contains `skipRate`, all acceptance grep checks pass

**Commits verified to exist:**
- `65603840` (Task 1) — `git log` confirms presence on `worktree-agent-a5040c214f583ade1`
- `745e2c5f` (Task 2) — `git log` confirms presence on `worktree-agent-a5040c214f583ade1`

**Test execution verified:**
- `npx hardhat test test/stat/PerPullLevelDistribution.test.js test/stat/PerPullEmptyBucketSkip.test.js` exits **1** (10 passing, 1 failing — STAT-03 finding as expected per orchestrator protocol)
- Verbatim failure message: `STAT-03 skip rate 88.24% > 10% (D-IMPL-08 test-failure threshold). Phase 265 D-09 gating promotes above INFO. Fixture context: callsWithEvents=50, totalPulls=2500, skippedPulls=2206.`

**Compliance verified:**
- Zero history-in-comments hits in either file (full file scan + non-comment-prefix scan both return 0)
- Zero `it.skip`, zero `describe.skip`, zero `process.env.SKIP` branches in either file
- Zero `contracts/*.sol` modifications (`git status --porcelain contracts/` empty)
- Zero `package.json` modifications (Plan 02 owns wiring)

---
*Phase: 264-statistical-validation-cross-surface-preservation*
*Plan: 01*
*Completed: 2026-05-09*
