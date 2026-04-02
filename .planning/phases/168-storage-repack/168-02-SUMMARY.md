---
phase: 168-storage-repack
plan: 02
subsystem: test-infrastructure
tags: [foundry, evm-storage, vm-load, vm-store, slot-offsets]

requires:
  - phase: 168-storage-repack
    plan: 01
    provides: repacked storage layout with slot 2 eliminated
provides:
  - all 15 Foundry test files updated for new storage layout
  - StorageFoundation.t.sol byte offset assertions match forge inspect
affects: [168-storage-repack plan 03 (full test suite verification)]

tech-stack:
  added: []
  patterns: []

key-files:
  created: []
  modified:
    - test/fuzz/StorageFoundation.t.sol
    - test/fuzz/TicketLifecycle.t.sol
    - test/fuzz/DegeneretteFreezeResolution.t.sol
    - test/fuzz/VRFStallEdgeCases.t.sol
    - test/fuzz/VRFCore.t.sol
    - test/fuzz/LootboxRngLifecycle.t.sol
    - test/fuzz/LootboxBoonCoexistence.t.sol
    - test/fuzz/BafRebuyReconciliation.t.sol
    - test/fuzz/FarFutureIntegration.t.sol
    - test/fuzz/AffiliateDgnrsClaim.t.sol
    - test/fuzz/StallResilience.t.sol
    - test/fuzz/VRFPathCoverage.t.sol
    - test/fuzz/RedemptionGas.t.sol
    - test/fuzz/handlers/CompositionHandler.sol
    - test/fuzz/handlers/VRFPathHandler.sol

key-decisions:
  - "RedemptionHandler.sol and RedemptionInvariants.inv.t.sol unchanged -- their SLOT_ constants reference StakedDegenerusStonk storage, not DegenerusGameStorage"
  - "Several pre-existing slot number errors corrected (e.g., claimableWinnings was slot 9 in test, actually slot 8 pre-repack / slot 7 post-repack)"
  - "Slot 0 bit shifts updated for poolConsolidationDone removal: rngLockedFlag 208->200, compressedJackpotFlag 248->232"

patterns-established: []

requirements-completed: [STOR-05]

duration: 20min
completed: 2026-04-02
---

# Phase 168 Plan 02: Test Slot Offset Updates Summary

**All 15 Foundry test files updated with correct slot constants and byte offsets matching forge inspect output for repacked DegenerusGameStorage layout**

## Performance

- **Duration:** 20 min
- **Started:** 2026-04-02T20:04:23Z
- **Completed:** 2026-04-02T20:24:35Z
- **Tasks:** 1
- **Files modified:** 15

## Accomplishments

- Updated slot constants in 15 test files to match the authoritative `forge inspect DegenerusGameStorage storage-layout` output
- Rewrote StorageFoundation.t.sol `testSlot1FieldOffsets()` for new layout: ticketWriteSlot at offset 6, prizePoolFrozen at offset 7, ticketsFullyProcessed verified in slot 0 offset 30
- Updated `testPackedPoolSlotsUnshifted()`: prizePoolsPacked slot 3->2, prizePoolPendingPacked slot 14->12
- Fixed slot 0 bit shift constants: rngLockedFlag 208->200, compressedJackpotFlag 248->232 (shifted by poolConsolidationDone removal)
- Fixed slot 1 bit shift: ticketWriteSlot WRITE_SLOT_SHIFT 176->48 (offset 22->6)
- Updated all 7 lootboxRngIndex inline references from slot 45 to 40
- Updated all lootboxRngWordByIndex mapping references from slot 49 to 44
- Corrected pre-existing off-by-N errors in multiple test files (claimableWinnings, claimablePool, levelDgnrsAllocation, etc.)
- StorageFoundation: all 24 tests passing

## Task Commits

Each task was committed atomically:

1. **Task 1: Update all test slot constants and byte offsets** - `64b6915f` (feat)

## Slot Update Summary

| Variable | Old Slot | New Slot | Files Updated |
|----------|----------|----------|---------------|
| prizePoolsPacked | 3 | 2 | TicketLifecycle, DegeneretteFreezeResolution, BafRebuyReconciliation, FarFutureIntegration, StorageFoundation |
| rngWordCurrent | 4 | 3 | VRFStallEdgeCases, VRFCore, LootboxRngLifecycle |
| vrfRequestId | 5 | 4 | VRFStallEdgeCases, VRFCore, LootboxRngLifecycle |
| totalFlipReversals | 6 | 5 | VRFStallEdgeCases |
| claimableWinnings | 9 | 7 | RedemptionGas |
| claimablePool | 10 | 8 | RedemptionGas |
| mintPacked_ | 12 | 10 | handlers/CompositionHandler |
| prizePoolPendingPacked | 14 | 12 | DegeneretteFreezeResolution, StorageFoundation |
| ticketQueue | 15 | 13 | TicketLifecycle, FarFutureIntegration |
| ticketsOwedPacked | 16 | 14 | TicketLifecycle |
| lootboxEth | 20 | 16 | LootboxBoonCoexistence |
| lootboxEthBase | 28 | 24 | LootboxBoonCoexistence |
| levelDgnrsAllocation | 32 | 28 | AffiliateDgnrsClaim |
| levelDgnrsClaimed | 33 | 29 | AffiliateDgnrsClaim |
| lootboxRngIndex | 45 | 40 | 7 files (all inline refs) |
| lootboxRngWordByIndex | 49 | 44 | 7 files (all mapping refs) |
| lootboxDay | 50 | 45 | LootboxBoonCoexistence |
| lootboxEvScorePacked | 52 | 47 | LootboxBoonCoexistence |
| midDayTicketRngPending | 55 | 50 | VRFStallEdgeCases |
| boonPacked | 77 | 72 | LootboxBoonCoexistence |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Pre-existing slot number errors in tests corrected**
- **Found during:** Task 1 (slot constant audit)
- **Issue:** Multiple test files had slot numbers that were already wrong before the repack (e.g., claimableWinnings at slot 9 instead of 8, levelDgnrsAllocation at 32 instead of 29). These tests had been "passing" because the wrong slot reads returned 0, which matched default state.
- **Fix:** All values set to match current forge inspect output. The plan specified only -1 shifts, but actual deltas varied from -2 to -5 due to accumulated prior variable removals.
- **Files modified:** RedemptionGas.t.sol, AffiliateDgnrsClaim.t.sol, LootboxBoonCoexistence.t.sol, handlers/CompositionHandler.sol

**2. [Rule 1 - Bug] Slot 0 bit shift constants wrong for post-poolConsolidationDone layout**
- **Found during:** Task 1 (forge inspect comparison)
- **Issue:** rngLockedFlag shift was 208 (offset 26) but poolConsolidationDone removal shifted it to offset 25 (shift 200). compressedJackpotFlag shift was 248 (offset 31) but is actually at offset 29 (shift 232).
- **Fix:** Updated to forge inspect-verified values.
- **Files modified:** TicketLifecycle.t.sol

**3. [Rule 1 - Bug] WRITE_SLOT_SHIFT was 176 but ticketWriteSlot is at offset 6 (shift 48)**
- **Found during:** Task 1 (forge inspect comparison)
- **Issue:** The test used WRITE_SLOT_SHIFT = 176 (offset 22) but forge inspect confirms ticketWriteSlot at offset 6 in slot 1. This was wrong even pre-repack.
- **Fix:** Updated to 48.
- **Files modified:** TicketLifecycle.t.sol

## Known Stubs

None.

## Self-Check: PASSED

- All 15 modified test files exist
- Task commit 64b6915f verified in git log
- StorageFoundation: 24/24 tests passing
- SUMMARY.md created at .planning/phases/168-storage-repack/168-02-SUMMARY.md
