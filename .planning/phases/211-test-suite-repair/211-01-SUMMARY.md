---
phase: 211-test-suite-repair
plan: 01
subsystem: testing
tags: [foundry, vm.load, storage-layout, fuzz-tests, vrf]

requires:
  - phase: 210-test-compilation-repair
    provides: "Type-narrowed test files that compile against v24.1 contracts"
provides:
  - "All 6 VRF fuzz test files read correct v24.1 storage slots and bit offsets"
affects: [211-02, 211-03, 211-04]

tech-stack:
  added: []
  patterns: ["vm.load with hardcoded slot numbers verified via forge inspect"]

key-files:
  created: []
  modified:
    - test/fuzz/VRFCore.t.sol
    - test/fuzz/VRFStallEdgeCases.t.sol
    - test/fuzz/VRFPathCoverage.t.sol
    - test/fuzz/LootboxRngLifecycle.t.sol
    - test/fuzz/StallResilience.t.sol
    - test/fuzz/handlers/VRFPathHandler.sol

key-decisions:
  - "No changes needed to lootboxRngIndex extraction logic (low 48 bits unchanged after repack)"

patterns-established:
  - "v24.1 slot references: lootboxRngPacked=38, lootboxRngWordByIndex=39"
  - "v24.1 bit offsets in slot 0: dailyIdx at >>32 (uint32), rngRequestTime at >>64 (uint48)"

requirements-completed: [VER-02]

duration: 6min
completed: 2026-04-10
---

# Phase 211 Plan 01: Storage Slot and Bit Offset Repair Summary

**Fixed vm.load() storage reads in 6 Foundry fuzz test files to match v24.1 slot layout (38/39) and bit offsets (>>64/>>32)**

## Performance

- **Duration:** 6 min
- **Started:** 2026-04-10T16:59:45Z
- **Completed:** 2026-04-10T17:05:40Z
- **Tasks:** 1
- **Files modified:** 6

## Accomplishments
- Updated lootboxRngPacked reads from slot 40 to slot 38 across all 6 files
- Updated lootboxRngWordByIndex mapping reads from slot 44 to slot 39 in 5 files
- Fixed rngRequestTime bit shift from >>96 to >>64 in 3 files
- Fixed dailyIdx bit shift from >>48 to >>32 in VRFStallEdgeCases and VRFPathHandler
- Updated all NatSpec comments to reflect v24.1 positions
- Verified compilation succeeds with forge build

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix lootboxRngPacked slot reads and bit offsets** - `266ce5b3` (fix)

## Files Created/Modified
- `test/fuzz/VRFCore.t.sol` - Fixed _lootboxRngIndex (slot 38), _readRngRequestTime (>>64)
- `test/fuzz/VRFStallEdgeCases.t.sol` - Fixed _lootboxRngIndex (slot 38), _lootboxRngWord (slot 39), _readRngRequestTime (>>64), _readDailyIdx (>>32)
- `test/fuzz/VRFPathCoverage.t.sol` - Fixed _lootboxRngIndex (slot 38), _lootboxRngWord (slot 39)
- `test/fuzz/LootboxRngLifecycle.t.sol` - Fixed _readLootboxRngIndex (slot 38), _lootboxRngWord (slot 39), _readRngRequestTime (>>64)
- `test/fuzz/StallResilience.t.sol` - Fixed _lootboxRngIndex (slot 38), _lootboxRngWord (slot 39)
- `test/fuzz/handlers/VRFPathHandler.sol` - Fixed _lootboxRngIndex (slot 38), _dailyIdx (>>32 with uint32 mask), _lootboxRngWord (slot 39)

## Decisions Made
- No changes needed to lootboxRngIndex extraction logic -- the low 48 bits mask is correct for LR_INDEX_SHIFT=0 in the new layout
- VRFPathHandler _dailyIdx uses uint32 intermediate cast to properly mask 32-bit field before widening to uint48 return type

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All 6 files compile cleanly against v24.1 contracts
- Ready for plan 02 (Hardhat test helper repairs) and subsequent plans
- TicketLifecycle.t.sol still has stale slot 40/44 references (separate plan scope)

---
*Phase: 211-test-suite-repair*
*Completed: 2026-04-10*
