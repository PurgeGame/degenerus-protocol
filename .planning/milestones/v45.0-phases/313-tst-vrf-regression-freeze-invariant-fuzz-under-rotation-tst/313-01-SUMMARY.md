---
phase: 313-tst-vrf-regression-freeze-invariant-fuzz-under-rotation-tst
plan: 01
subsystem: testing
tags: [solidity, foundry, chainlink-vrf, vrf-rotation, rng-lock, orphan-index, degenerus]

# Dependency graph
requires:
  - phase: 312-impl-vrf-rotation-fix-single-batched-user-approved-diff-impl
    provides: "Patched updateVrfCoordinatorAndSub (a303ae18) — mid-day rotation preserves LR_INDEX and re-issues the in-flight request on the new coordinator; the contract surface this test asserts against"
provides:
  - "test/fuzz/VrfRotationOrphanIndex.t.sol — VTST-01 orphan-index reproduction (proves VRF-01) as a single-invocation contrast"
  - "Post-fix arm: a real mid-flight emergency rotation lands a contract-derived VRF word in the preserved lootboxRngWordByIndex[N]"
  - "Pre-fix arm: the Scenario-A entropy-0 consequence asserted at the consumed index (LR_INDEX-1)"
affects: [313-06 suite-verify, 314 SWEEP, 315 TERMINAL]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "In-repo contrast (single forge-test invocation): pre-fix arm asserts the defect consequence via vm.store, post-fix arm asserts the fixed invariant via a real contract path"
    - "Authoritative storage slots from `forge inspect DegenerusGame storage-layout` (37 lootboxRngPacked, 38 lootboxRngWordByIndex), NOT the analog file's drifted 38/39"

key-files:
  created:
    - test/fuzz/VrfRotationOrphanIndex.t.sol
  modified: []

key-decisions:
  - "Used authoritative storage slots 37 (lootboxRngPacked) / 38 (lootboxRngWordByIndex) from forge inspect; the analog LootboxRngLifecycle.t.sol uses drifted slots 38/39 and its mid-day test currently FAILS as a result (pre-existing, out of scope — Plan 05 regression-migration territory)"
  - "Post-fix arm asserts a contract-WRITTEN word (delivered to the new coordinator, written by rawFulfillRandomWords:1804), never a vm.stored value — no tautology"
  - "Asserted LR_MID_DAY==1 after requestLootboxRng so the rotation's mid-day re-issue branch (AdvanceModule:1726) is the path under test"

patterns-established:
  - "Pre-fix/post-fix contrast in one contract for an already-merged fix, avoiding a git pre-fix checkout / separate CI profile"

requirements-completed: [VTST-01]

# Metrics
duration: 22min
completed: 2026-05-23
---

# Phase 313 Plan 01: VTST-01 Orphan-Index Reproduction Summary

**Single-invocation Foundry contrast proving VRF-01: a real mid-flight `updateVrfCoordinatorAndSub` rotation re-issues on a 2nd MockVRFCoordinator and lands a contract-derived VRF word in the preserved `lootboxRngWordByIndex[N]`, contrasted against the pre-fix entropy-0 consequence at the consumed index.**

## Performance

- **Duration:** ~22 min
- **Started:** 2026-05-23 (Phase 313 execution start)
- **Completed:** 2026-05-23
- **Tasks:** 2
- **Files modified:** 1 (created)

## Accomplishments
- `test/fuzz/VrfRotationOrphanIndex.t.sol` created — `contract VrfRotationOrphanIndex is DeployProtocol` with both contrast arms in one file.
- **Post-fix arm** (`test_postFix_midDayRotation_landsRealWordInOrphanedIndex`, 1000 fuzz runs): mid-day `requestLootboxRng` → real rotation to a freshly-deployed 2nd `MockVRFCoordinator` while `LR_MID_DAY==1` → `fulfillRandomWords` on the NEW coordinator → `lootboxRngWordByIndex[reservedIndex] == vrfWord`. Asserts the slot is 0 before fulfilment (no tautology), index preserved across rotation, and `newVRF.lastRequestId() != 0` (re-issue fired).
- **Pre-fix arm** (`test_preFix_orphanedZeroIndex_yieldsEntropyZero`): forces the orphaned-at-zero state via `vm.store` on the slot-38 mapping at `LR_INDEX-1` and asserts the consumed index reads `entropy == 0` — the Scenario-A defect consequence.
- Both arms PASS in a single `forge test --match-contract VrfRotationOrphanIndex` invocation; `forge build` exits 0; ZERO `contracts/` mutation.

## Task Commits

1. **Task 1: Post-fix arm — real mid-flight rotation lands a real VRF word in the orphaned index** — `f6cc92c9` (test)
2. **Task 2: Pre-fix arm — entropy-0 consequence at the consumed orphaned index** — `611deb20` (test)

_TDD plan: Task 1 was authored test-first against the already-merged patched contract; the post-fix sequence was validated by a throwaway probe before the assertions were committed._

## Files Created/Modified
- `test/fuzz/VrfRotationOrphanIndex.t.sol` — VTST-01 reproduction: pre-fix entropy-0 consequence arm + post-fix real-VRF-word-in-[N]-after-rotation arm, single forge-test invocation.

## Decisions Made
- **Authoritative storage slots over the analog's drifted constants.** `forge inspect DegenerusGame storage-layout` confirms `lootboxRngPacked` at slot 37 and `lootboxRngWordByIndex` at slot 38, matching the PLAN `<interfaces>` block. The analog `test/fuzz/LootboxRngLifecycle.t.sol` reads slots 38/39 (a pre-drift layout) and its `test_wordWriteMidDay` consequently FAILS (`0 != <word>`). The new file uses 37/38 and passes; the analog's failure is a pre-existing, unrelated regression (Plan 05 territory) — not caused by this plan.
- **Contract-derived assertion in the post-fix arm.** The asserted word is delivered to the new coordinator and written by the contract's `rawFulfillRandomWords` (mid-day branch, AdvanceModule:1804); the test never `vm.store`s the word into `[N]` in that arm.
- **`LR_MID_DAY==1` precondition asserted.** `_setupForMidDayRng`'s lootbox purchase creates a ticket-queue entry so `requestLootboxRng`'s buffer swap sets `LR_MID_DAY=1`, ensuring the rotation's mid-day re-issue branch (AdvanceModule:1726-1730) is the path exercised.

## Deviations from Plan

None — plan executed exactly as written. The PLAN explicitly warned line numbers may have drifted post-patch and instructed grep-verification before relying on cited anchors; verified anchors: `updateVrfCoordinatorAndSub`:1712, `rawFulfillRandomWords`:1788 (mid-day write :1803-1804), `requestLootboxRng`:1042, MintModule consumer :686. Storage slots taken from the authoritative `forge inspect` per the PLAN's interface note.

## Issues Encountered
- The analog `test_wordWriteMidDay` fails against the current contract due to drifted slot constants (38/39 vs authoritative 38). This was diagnosed (not fixed — out of scope, test-tree slot drift belongs to Plan 05's regression-migration) and informed the decision to hardcode authoritative slots 37/38 in the new file.

## User Setup Required
None — no external service configuration required.

## Next Phase Readiness
- VTST-01 / VRF-01 reproduction is green and committed (test-tree only, AGENT-COMMITTED).
- Ready for sibling Wave-1 plans (313-02..05) and Wave-2 suite-verify (313-06).
- Note for Plan 05/06: `LootboxRngLifecycle.t.sol` mid-day-write slot drift (38/39 → 38) is a live failing baseline test to migrate.

## Self-Check: PASSED

- FOUND: `test/fuzz/VrfRotationOrphanIndex.t.sol`
- FOUND: commit `f6cc92c9` (Task 1 post-fix arm)
- FOUND: commit `611deb20` (Task 2 pre-fix arm)
- `forge test --match-contract VrfRotationOrphanIndex`: 2 passed, 0 failed (post-fix 1000 fuzz runs)
- `forge build`: exit 0
- `git diff --name-only -- contracts/`: empty (ZERO mainnet contract mutation)

---
*Phase: 313-tst-vrf-regression-freeze-invariant-fuzz-under-rotation-tst*
*Completed: 2026-05-23*
