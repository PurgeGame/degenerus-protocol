---
phase: 313-tst-vrf-regression-freeze-invariant-fuzz-under-rotation-tst
plan: 05
subsystem: testing
tags: [solidity, foundry, chainlink-vrf, vrf-rotation, rng-lock, regression-migration, degenerus]

# Dependency graph
requires:
  - phase: 312-impl-vrf-rotation-fix-single-batched-user-approved-diff-impl
    provides: "updateVrfCoordinatorAndSub preserve+re-issue rework (blanket-reset removed)"
provides:
  - "Migrated coordinator-swap regression tests asserting preserve+re-issue (no blanket-reset)"
  - "Shared _resumeAfterSwap helpers (VRFStallEdgeCases / StallResilience / VRFPathCoverage) that fulfil the already-re-issued request on the new coordinator before draining"
  - "StallResilience lootbox slot reads corrected to authoritative 37/38"
affects: [313-06-suite-verify, vrf-rotation-regression-baseline]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Resume-after-rotation: fulfil the existing re-issued request (newVRF.lastRequestId()) before advanceGame; fall back to fresh-request flow only when nothing was in flight"

key-files:
  created: []
  modified:
    - test/fuzz/VRFStallEdgeCases.t.sol
    - test/fuzz/VRFCore.t.sol
    - test/fuzz/StallResilience.t.sol
    - test/fuzz/VRFPathCoverage.t.sol

key-decisions:
  - "Class A assertions flipped to PRESERVE+RE-ISSUE (rngLocked stays true / LR_MID_DAY stays 1 / re-issued request exists on the new coordinator + day completes after fulfilment), not weakened to trivial passes."
  - "Class B shared _resumeAfterSwap migrated to fulfil the already-re-issued request first (the swap re-issues it, so newVRF.lastRequestId() is non-zero immediately post-swap); RngNotReady was the old advanceGame-first flow."
  - "StallResilience lootbox-index/word slot drift (38/39) corrected to authoritative 37/38 (lootboxRngPacked / lootboxRngWordByIndex) — a Rule-3 blocker for the enumerated test_lootboxOpenAfterOrphanedIndexBackfill in the same file/helper being migrated."
  - "VRFPathCoverage slot drift (38/39) left UNCORRECTED: the only two tests it would affect (test_gapBackfillWithMidDayPending_fuzz, test_indexLifecycleAcrossStall_fuzz) are PRE-EXISTING baseline failures (fail at 41546f16) and NOT in the enumerated fix-induced set — out of scope per the strict scope guard."

requirements-completed: [VTST-02]

# Metrics
duration: ~22min
completed: 2026-05-23
---

# Phase 313 Plan 05: VRF-Rotation Regression Migration Summary

**Migrated the Foundry tests that the Phase 312 VRF-rotation preserve+re-issue fix regressed — flipping the Class A coordinator-swap assertions from the deleted blanket-reset to PRESERVE+RE-ISSUE, and updating the Class B shared swap+resume helpers to fulfil the already-re-issued request on the new coordinator before draining — so the suite returns to its pre-fix pass/fail baseline (no NEW fix-induced failures). ZERO contracts/ mutation.**

## Performance
- **Duration:** ~22 min
- **Completed:** 2026-05-23T11:05:57Z
- **Tasks:** 2 (both auto)
- **Files modified:** 4 test files (test-tree only; AGENT-COMMITTED)

## Accomplishments

### Task 1 — Class A assertion migration (commit `ced272e7`)
Flipped the four assertion-class regressions from the deleted blanket-reset to the new preserve+re-issue behavior, keeping the PRESERVE-side checks:
- `test_coordinatorSwapResetsAllVrfState` (VRFStallEdgeCases): asserts rngLocked STAYS true, vrfRequestId re-issued fresh (non-zero) with a request on the new coordinator, rngRequestTime refreshed, rngWordCurrent stays 0 (not yet delivered); retains lootboxRngIndex + historical rngWordForDay(2) PRESERVE checks; then fulfils the re-issued request + drains, asserting the day completes (liveness).
- `test_tryRequestRngGuardBranches` (VRFStallEdgeCases): asserts rngLocked PRESERVED after swap, the new coordinator received the re-issued request, then fulfils + drains.
- `test_coordinatorSwapClearsMidDayPending` (VRFStallEdgeCases): asserts LR_MID_DAY STAYS 1 (preserved), the reserved lootbox index is preserved, a re-issued mid-day request exists on the new coordinator, and fulfilling it lands the genuine word in the SAME reserved index (the orphan-0 path is eliminated); request-state (vrfRequestId / rngRequestTime) cleared by the mid-day callback.
- `test_coordinatorSwap_clearsRngLocked` (VRFCore): asserts rngLocked STAYS true, vrfRequestId re-issued, re-issued request exists on the new coordinator; fulfils + drains to confirm the day completes.
Also migrated the VRFStallEdgeCases shared `_resumeAfterSwap` helper (fulfil the existing re-issued request before draining) and the inline swap+fulfil in `test_manipulationWindowIdenticalToDaily`.

### Task 2 — Class B swap+resume helper migration (commit `6ad8338a`)
- Updated `_resumeAfterSwap` in StallResilience + VRFPathCoverage to the preserve+re-issue resume shape: fulfil `newVRF.lastRequestId()` first (the re-issued request exists immediately post-swap), then drain; fall back to advanceGame-then-fulfil only when nothing was in flight.
- Corrected StallResilience `_lootboxRngIndex` / `_lootboxRngWord` slot reads from drifted 38/39 to authoritative 37/38.
- Restores liveness for `test_stallSwapResume`, `test_coinflipClaimsAcrossGapDays`, `test_lootboxOpenAfterOrphanedIndexBackfill` (StallResilience); the eight gap-backfill / zero-seed Class-B tests in VRFStallEdgeCases; and the VRFPathCoverage gap-backfill fuzz tests. Gap-day `keccak256(vrfWord, gapDay)` assertions retained — the re-issued resume word IS the same backfill seed.

## Fix-Induced Regression Migration — Final Result

All enumerated fix-induced regressions PASS post-migration (verified via `forge test`):

| File | Tests migrated (fix-induced) | Result |
|------|------------------------------|--------|
| VRFStallEdgeCases.t.sol | test_coordinatorSwapResetsAllVrfState, test_tryRequestRngGuardBranches, test_coordinatorSwapClearsMidDayPending, test_zeroSeedAtGameStart, test_zeroSeedUnreachableAfterSwap, test_manipulationWindowIdenticalToDaily, test_gapDayPositionsPreCommitted, test_gapDaysSkipResolveRedemptionPeriod, test_gapBackfillSingleDayGap, test_gapBackfillZeroGuard, test_gapBackfillGas30Days, test_gapBackfillGas120Days, test_gapBackfillEntropyUnique_fuzz | 18/18 suite PASS |
| VRFCore.t.sol | test_coordinatorSwap_clearsRngLocked | migrated test PASS (suite 20/22; 2 pre-existing fails) |
| StallResilience.t.sol | test_stallSwapResume, test_coinflipClaimsAcrossGapDays, test_lootboxOpenAfterOrphanedIndexBackfill | 3/3 suite PASS |
| VRFPathCoverage.t.sol | test_gapBackfillEntropyUnique_fuzz (+ MaxGap/MultiDay/SingleDay, see Deviation 1) | 4 fix-induced PASS (suite 4/6; 2 pre-existing fails) |

`forge build` → exit 0.

## Baseline Classification (pre-fix `41546f16` vs post-fix HEAD)

The classification was empirically established by running each test file against the pre-fix contract (temporary contract swap, restored byte-identical; ZERO committed contract change):

**Fix-induced (PASS pre-fix, migrated to PASS post-fix):** the 4 Class A assertion tests; the 8 VRFStallEdgeCases gap/zero-seed Class-B tests (all except test_zeroSeedAtGameStart, see below); test_stallSwapResume + test_coinflipClaimsAcrossGapDays (StallResilience); test_gapBackfillEntropyUnique_fuzz + test_gapBackfillMaxGap_fuzz + test_gapBackfillMultiDay_fuzz + test_gapBackfillSingleDay_fuzz (VRFPathCoverage).

**Pre-existing-AND-fix-blocked (FAIL pre-fix for a separate reason, listed in plan, now PASS post-migration):** test_coordinatorSwapClearsMidDayPending + test_zeroSeedAtGameStart (VRFStallEdgeCases) and test_lootboxOpenAfterOrphanedIndexBackfill (StallResilience) all failed pre-fix with RngNotReady (the old resume helper) AND the fix; the helper migration (plus the StallResilience slot-drift correction) makes them pass with assertions matching actual contract behavior — not weakened.

**Pre-existing baseline failures (FAIL at 41546f16, left UNTOUCHED, documented):**
- VRFCore: `test_retryDetection_fresh` ("index should increment by 1: 0 != 1" — slot-38 drift) and `test_midDayRequest_doesNotBlockDaily` (RngNotReady). Both confirmed FAIL at 41546f16 with identical errors.
- VRFPathCoverage: `test_gapBackfillWithMidDayPending_fuzz` (RngNotReady) and `test_indexLifecycleAcrossStall_fuzz` ("index should increment by 1: 0 != 1" — slot-38 drift). Both confirmed FAIL at 41546f16. NOT in the enumerated set; left failing so 313-06 sees the same pre-fix baseline.

## Deviations from Plan

### 1. [Rule 3 — Blocking issue + plan under-enumeration] 3 additional VRFPathCoverage fuzz tests were fix-induced
- **Found during:** baseline classification (Task 2).
- **Issue:** The plan enumerated only `test_gapBackfillEntropyUnique_fuzz` from VRFPathCoverage as fix-induced. Empirically, `test_gapBackfillMaxGap_fuzz`, `test_gapBackfillMultiDay_fuzz`, and `test_gapBackfillSingleDay_fuzz` ALSO passed at the pre-fix baseline `41546f16` and failed post-fix with `RngNotReady()` — i.e. they are fix-induced too (the plan under-enumerated them).
- **Fix:** No extra work — all four route through the single shared `_resumeAfterSwap` helper, so migrating that one helper restored all four. Documented for completeness.
- **Files modified:** test/fuzz/VRFPathCoverage.t.sol (shared helper only).
- **Commit:** `6ad8338a`.

### 2. [Rule 3 — Blocking issue] StallResilience slot-drift correction (38/39 → 37/38)
- **Found during:** Task 2 (after the helper fix, `test_lootboxOpenAfterOrphanedIndexBackfill` failed on its orphaned-index assertion rather than RngNotReady).
- **Issue:** StallResilience read lootboxRngIndex from slot 38 and lootboxRngWordByIndex from slot 39; `forge inspect DegenerusGame storage-layout` confirms the authoritative slots are 37 (lootboxRngPacked, low-bit LR_INDEX) and 38 (lootboxRngWordByIndex). The drift made the enumerated `test_lootboxOpenAfterOrphanedIndexBackfill` read the wrong slot, so it could not pass even with correct contract behavior.
- **Fix:** Corrected the two read helpers to 37/38 (proven sufficient: a scoped slot-correction trial flipped the test to PASS). This is a Rule-3 blocker for an enumerated test in the file/helpers already being migrated. Only `test_lootboxOpenAfterOrphanedIndexBackfill` uses these two helpers in StallResilience, so no other test is affected.
- **Files modified:** test/fuzz/StallResilience.t.sol.
- **Commit:** `6ad8338a`.

### 3. [Scope discipline] VRFPathCoverage / VRFCore slot drift left uncorrected
- VRFPathCoverage and VRFCore also use the same drifted slots (38/39 and 38), but the only tests they would affect (`test_gapBackfillWithMidDayPending_fuzz`, `test_indexLifecycleAcrossStall_fuzz`, `test_retryDetection_fresh`, `test_midDayRequest_doesNotBlockDaily`) are PRE-EXISTING baseline failures (fail at 41546f16) and NOT in the enumerated fix-induced set. Per the strict scope guard, they are left untouched and documented in the baseline allow-list for 313-06. The 4 fix-induced VRFPathCoverage tests pass without needing the slot correction.

## LootboxRngLifecycle.t.sol Classification (per phase-critical-context informational note)
`test/fuzz/LootboxRngLifecycle.t.sol::test_wordWriteMidDay` is NOT in this plan's files_modified and was not edited. It uses drifted slots 38/39 (the 313-01 executor note). Its failure is a slot-drift PRE-EXISTING baseline issue (not one of the enumerated Phase-312 fix-induced regressions in the 4 named files), so it belongs to the documented pre-existing baseline; flagged here for 313-06's baseline allow-list. No action taken (out of file scope).

## Build / Scope / Self-Review Attestation
- `forge build` → exit 0.
- ZERO contracts/ mutation across the plan: `git diff HEAD~2 HEAD -- contracts/` is empty.
- Files touched across the plan: exactly the 4 named test files (test/fuzz/VRFStallEdgeCases.t.sol, VRFCore.t.sol, StallResilience.t.sol, VRFPathCoverage.t.sol).
- All baseline classification used a temporary contract swap that was restored byte-identical (verified `git diff --quiet -- contracts/` clean before each commit). No `CONTRACTS_COMMIT_APPROVED` flag set; the contract-commit guard did not fire (test-tree only).

## Known Stubs
None. All migrated assertions are positive PRESERVE+RE-ISSUE claims wired to actual contract state/views; no placeholder data or weakened assertions.

## Threat Flags
None. Zero contracts/ mutation; no production attack surface introduced (D-43N-AUDIT-ONLY-01).

## Task Commits
1. `ced272e7` — test(313-05): migrate Class A coordinator-swap assertions to preserve+re-issue
2. `6ad8338a` — test(313-05): migrate Class B swap+resume helpers to fulfil re-issued request

## Next Phase Readiness
- Plan 313-06 (suite-verify + AGENT-COMMIT) can now assert no NEW failures beyond the pre-fix baseline. The documented pre-existing baseline failures it should expect (allow-list): VRFCore test_retryDetection_fresh + test_midDayRequest_doesNotBlockDaily; VRFPathCoverage test_gapBackfillWithMidDayPending_fuzz + test_indexLifecycleAcrossStall_fuzz; plus the broader suite-wide pre-existing debt (affiliate E(), solvency, arithmetic panics, InvalidBet, etc.) and LootboxRngLifecycle slot-drift failures, all unrelated to the VRF fix.

---
*Phase: 313-tst-vrf-regression-freeze-invariant-fuzz-under-rotation-tst*
*Completed: 2026-05-23*
