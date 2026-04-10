---
phase: 211-test-suite-repair
plan: 05
subsystem: testing
tags: [foundry, solidity, storage-layout, game-loop, vrf, level-advancement]

# Dependency graph
requires:
  - phase: 211-test-suite-repair/04
    provides: "Foundry test suite baseline with 312 pass / 46 fail after patchForFoundry.js workflow"
provides:
  - "All 53 level-advancement integration tests passing (was 16/53)"
  - "Fixed _driveToLevel helper with warm-up to prevent turbo-mode underflow"
  - "Fixed AffiliateDgnrsClaim storage slot constants for v24.1 layout"
  - "Fixed FarFutureIntegration TICKET_QUEUE_SLOT for v24.1 layout"
affects: [211-test-suite-repair/06, 211-test-suite-repair/07]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Warm-up pattern: drain pending advanceGame work on current day before starting seeded level-advancement loop to prevent multi-day gap backfill"
    - "VRF-before-advance: fulfill pending VRF requests before calling advanceGame, not after"

key-files:
  created: []
  modified:
    - test/fuzz/TicketLifecycle.t.sol
    - test/fuzz/VRFLifecycle.t.sol
    - test/fuzz/AffiliateDgnrsClaim.t.sol
    - test/fuzz/FarFutureIntegration.t.sol

key-decisions:
  - "Root cause of 27 TicketLifecycle failures: multi-day gap backfill adjusted purchaseStartDay making turbo check trigger at level 0, causing purchaseLevel=0 underflow in _consolidatePoolsAndRewardJackpots"
  - "Fix: warm-up phase in _driveToLevel drains pending work on current day before entering seeded loop, preventing gap backfill from corrupting purchaseStartDay"
  - "AffiliateDgnrsClaim slot constants updated: SLOT_LEVEL_DGNRS_ALLOCATION 28->25, SLOT_LEVEL_DGNRS_CLAIMED 29->26 (not just the bit shift from the plan)"

patterns-established:
  - "Level-advancement test warm-up: always call advanceGame+VRF on current day before the seeded daily loop to establish dailyIdx"

requirements-completed: [VER-02]

# Metrics
duration: 38min
completed: 2026-04-10
---

# Phase 211 Plan 05: Level-Advancement Test Repair Summary

**Fixed 37 Foundry test failures across 4 test contracts by correcting v24.1 storage slot constants and adding warm-up phase to _driveToLevel to prevent turbo-mode underflow at level 0**

## Performance

- **Duration:** 38 min
- **Started:** 2026-04-10T18:34:55Z
- **Completed:** 2026-04-10T19:13:09Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- All 53 tests pass across TicketLifecycle (34), VRFLifecycle (4), AffiliateDgnrsClaim (14), and FarFutureIntegration (1)
- Root-caused the _driveToLevel overflow: multi-day gap backfill adjusted purchaseStartDay, triggering turbo path at level 0 where purchaseLevel-1 underflows
- Fixed 3 stale storage slot constants in AffiliateDgnrsClaim (bit shift + 2 mapping slots) and 1 in FarFutureIntegration

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix AffiliateDgnrsClaim _setLevel and FarFutureIntegration slot constant** - `f28164cc` (fix)
2. **Task 2: Fix _driveToLevel helper and VRFLifecycle level advancement** - `e284da33` (fix)

## Files Created/Modified
- `test/fuzz/AffiliateDgnrsClaim.t.sol` - Fixed _setLevel bit shift 144->112, SLOT_LEVEL_DGNRS_ALLOCATION 28->25, SLOT_LEVEL_DGNRS_CLAIMED 29->26
- `test/fuzz/FarFutureIntegration.t.sol` - Fixed TICKET_QUEUE_SLOT 13->12
- `test/fuzz/TicketLifecycle.t.sol` - Added warm-up phase to _driveToLevel, VRF-before-advance and retry-after-fulfill in inner loop
- `test/fuzz/VRFLifecycle.t.sol` - Added warm-up phase and VRF-before-advance pattern to test_vrfLifecycle_levelAdvancement

## Decisions Made
- Root cause of TicketLifecycle failures was NOT just VRF ordering (as plan hypothesized) but a turbo-mode underflow triggered by gap backfill adjusting purchaseStartDay
- AffiliateDgnrsClaim had 2 additional stale slot constants beyond the bit shift identified in the plan (SLOT_LEVEL_DGNRS_ALLOCATION and SLOT_LEVEL_DGNRS_CLAIMED)
- Warm-up pattern (drain current day before seeded loop) chosen over alternative approaches (skip first iteration seeding, increase ETH balance, etc.) because it addresses all call sites

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed stale SLOT_LEVEL_DGNRS_ALLOCATION and SLOT_LEVEL_DGNRS_CLAIMED constants**
- **Found during:** Task 1 (AffiliateDgnrsClaim slot fixes)
- **Issue:** Plan only identified _setLevel bit shift (144->112) and SLOT_LEVEL comment. The SLOT_LEVEL_DGNRS_ALLOCATION (28) and SLOT_LEVEL_DGNRS_CLAIMED (29) constants were also stale from v24.1 layout shift (actual slots are 25 and 26). This caused _setAllocation to write to wrong storage and claimAffiliateDgnrs to read zero allocation, reverting with E().
- **Fix:** Updated SLOT_LEVEL_DGNRS_ALLOCATION 28->25, SLOT_LEVEL_DGNRS_CLAIMED 29->26 (confirmed via forge inspect)
- **Files modified:** test/fuzz/AffiliateDgnrsClaim.t.sol
- **Verification:** All 14 AffiliateDgnrsClaim tests pass
- **Committed in:** f28164cc (Task 1 commit)

**2. [Rule 1 - Bug] Root-caused and fixed _driveToLevel turbo-mode underflow**
- **Found during:** Task 2 (_driveToLevel repair)
- **Issue:** Plan's proposed fix (VRF-before-advance ordering) did not address the actual failure. The real bug: when _driveToLevel runs its first iteration, advanceGame's rngGate performs multi-day gap backfill (dailyIdx was stale), adjusting purchaseStartDay. This makes day-purchaseStartDay<=1, triggering turbo mode (compressedJackpotFlag=2) while rngLockedFlag is still true. With lastPurchase=true and rngLockedFlag=true, purchaseLevel becomes lvl (=0 at start). _consolidatePoolsAndRewardJackpots then computes purchaseLevel-1 which underflows uint24.
- **Fix:** Added warm-up phase that drains pending advanceGame work on the current day (no warp) before starting the seeded loop. This establishes dailyIdx at the current day, preventing gap backfill.
- **Files modified:** test/fuzz/TicketLifecycle.t.sol, test/fuzz/VRFLifecycle.t.sol
- **Verification:** All 34 TicketLifecycle + 4 VRFLifecycle tests pass
- **Committed in:** e284da33 (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (2 bugs)
**Impact on plan:** Both auto-fixes were necessary for correctness. The plan's proposed VRF-ordering fix was also applied but was insufficient alone. No scope creep.

## Issues Encountered
- Plan's root cause analysis for _driveToLevel was incomplete. The plan identified VRF ordering and multi-day processing as causes, but the actual root cause was a turbo-mode underflow triggered by gap backfill adjusting purchaseStartDay. Extensive contract code tracing was required to identify the exact overflow location (purchaseLevel-1 when purchaseLevel=0 in _consolidatePoolsAndRewardJackpots).

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- 37 previously-failing tests now pass (27 TicketLifecycle + 1 VRFLifecycle + 8 AffiliateDgnrsClaim + 1 FarFutureIntegration)
- Remaining Foundry failures from the 46-failure baseline should be addressed in plans 06 and 07
- No regressions in previously-passing tests

## Self-Check: PASSED

All files exist, all commits verified.

---
*Phase: 211-test-suite-repair*
*Completed: 2026-04-10*
