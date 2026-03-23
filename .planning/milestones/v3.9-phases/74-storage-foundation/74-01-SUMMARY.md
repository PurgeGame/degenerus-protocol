---
phase: 74-storage-foundation
plan: 01
subsystem: storage
tags: [solidity, bitwise, uint24, key-encoding, foundry-fuzz]

# Dependency graph
requires: []
provides:
  - "TICKET_FAR_FUTURE_BIT constant (1 << 22) in DegenerusGameStorage"
  - "_tqFarFutureKey(lvl) pure helper for far-future key space"
  - "Foundry fuzz proof: three key spaces collision-free for all lvl < 2^22"
affects: [75-routing, 76-processing, 77-jackpot, 78-drain, 79-integration, 80-tests]

# Tech tracking
tech-stack:
  added: []
  patterns: [third-key-space-via-bit22, pure-helper-for-slot-independent-keys]

key-files:
  created: [test/fuzz/TqFarFutureKey.t.sol]
  modified: [contracts/storage/DegenerusGameStorage.sol]

key-decisions:
  - "Bit 22 reserved for far-future key space, reducing theoretical max level from 2^23-1 to 2^22-1 (still millennia of gameplay)"
  - "_tqFarFutureKey is pure (not view) since it does not read ticketWriteSlot"

patterns-established:
  - "Third key space pattern: bit 22 for far-future, bit 23 for double-buffer slot"
  - "Far-future keys are not double-buffered; single persistent key space"

requirements-completed: [STORE-01, STORE-02]

# Metrics
duration: 6min
completed: 2026-03-22
---

# Phase 74 Plan 01: Storage Foundation Summary

**TICKET_FAR_FUTURE_BIT constant (1 << 22) and _tqFarFutureKey pure helper with Foundry fuzz proof of three-way key space collision-freedom**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-23T01:14:52Z
- **Completed:** 2026-03-23T01:20:48Z
- **Tasks:** 2 (TDD: RED + GREEN)
- **Files modified:** 2

## Accomplishments
- Added TICKET_FAR_FUTURE_BIT = 1 << 22 constant to DegenerusGameStorage.sol
- Added _tqFarFutureKey(lvl) internal pure helper returning lvl | TICKET_FAR_FUTURE_BIT
- Updated TICKET_SLOT_BIT comment to reflect reduced max level (2^22-1 = 4,194,303)
- 5 Foundry fuzz/unit tests prove collision-freedom across all three key spaces under both ticketWriteSlot states

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Foundry test for far-future key space (RED)** - `aaa99978` (test)
2. **Task 2: Add TICKET_FAR_FUTURE_BIT constant and _tqFarFutureKey helper (GREEN)** - `2b2373c4` (feat)

## Files Created/Modified
- `test/fuzz/TqFarFutureKey.t.sol` - Harness contract exposing internal key functions + 5 fuzz/unit tests proving key space collision-freedom
- `contracts/storage/DegenerusGameStorage.sol` - TICKET_FAR_FUTURE_BIT constant, _tqFarFutureKey helper, updated max level comment

## Decisions Made
- Bit 22 chosen as the far-future discriminator (next-highest available bit below existing bit 23), maximizing level address space at 2^22-1
- _tqFarFutureKey is pure (not view) because it does not read ticketWriteSlot -- far-future tickets are not double-buffered

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Storage foundation complete: TICKET_FAR_FUTURE_BIT and _tqFarFutureKey are available to all contracts inheriting DegenerusGameStorage
- Phase 75+ can use _tqFarFutureKey in routing, processing, jackpot, and drain logic
- Full compilation succeeds with zero regressions across all 11 inheriting contracts

## Self-Check: PASSED

- FOUND: test/fuzz/TqFarFutureKey.t.sol
- FOUND: contracts/storage/DegenerusGameStorage.sol
- FOUND: .planning/phases/74-storage-foundation/74-01-SUMMARY.md
- FOUND: aaa99978 (Task 1 commit)
- FOUND: 2b2373c4 (Task 2 commit)
- No stubs detected

---
*Phase: 74-storage-foundation*
*Completed: 2026-03-22*
