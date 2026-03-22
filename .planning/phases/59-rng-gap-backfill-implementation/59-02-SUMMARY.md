---
phase: 59-rng-gap-backfill-implementation
plan: 02
subsystem: rng
tags: [solidity, vrf, lootbox, coordinator-swap, orphaned-index, keccak256]

# Dependency graph
requires:
  - phase: 59-01
    provides: "Gap day RNG backfill in rngGate (keccak256 derivation pattern)"
provides:
  - "Orphaned lootbox index recovery in updateVrfCoordinatorAndSub"
  - "midDayTicketRngPending clearing during coordinator swap"
  - "Deterministic fallback RNG word via keccak256(lastLootboxRngWord, orphanedIndex)"
affects: [61-stall-resume-tests]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Orphaned index detection: capture outgoingRequestId before vrfRequestId=0, lookup via lootboxRngRequestIndexById"
    - "Fallback RNG derivation: keccak256(lastLootboxRngWord, orphanedIndex) with zero-guard"
    - "State flag clearing: midDayTicketRngPending=false prevents post-swap deadlock"

key-files:
  created: []
  modified:
    - contracts/modules/DegenerusGameAdvanceModule.sol

key-decisions:
  - "Orphaned index handled in updateVrfCoordinatorAndSub (not rngGate) -- resolves at exact moment of orphaning"
  - "Fallback word derived from lastLootboxRngWord + orphanedIndex for unique entropy"
  - "fallbackWord==0 guard matches rawFulfillRandomWords pattern for consistency"
  - "No loop needed -- at most one lootbox index can be orphaned (requestLootboxRng reverts if rngRequestTime != 0)"

patterns-established:
  - "VRF coordinator swap: backfill orphaned lootbox index before clearing VRF state"

requirements-completed: [GAP-02, GAP-03, GAP-05]

# Metrics
duration: 3min
completed: 2026-03-22
---

# Phase 59 Plan 02: Orphaned Lootbox Recovery Summary

**Orphaned lootbox index backfill via keccak256(lastLootboxRngWord, orphanedIndex) + midDayTicketRngPending clearing in coordinator swap**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-22T12:20:31Z
- **Completed:** 2026-03-22T12:23:29Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Orphaned lootbox indices from stalled VRF requests now receive a valid fallback RNG word during coordinator swap
- midDayTicketRngPending cleared during swap to prevent post-swap advanceGame deadlock
- Outgoing requestId captured before vrfRequestId=0 to enable orphaned index lookup
- Zero-guard on fallbackWord matches rawFulfillRandomWords safety pattern

## Task Commits

Each task was committed atomically:

1. **Task 1: Add orphaned lootbox index recovery and midDayTicketRngPending clearing** - `6a7bd5ca` (fix)

## Files Created/Modified
- `contracts/modules/DegenerusGameAdvanceModule.sol` - Added orphaned index backfill block (lines 1346-1359) and midDayTicketRngPending=false (line 1370) to updateVrfCoordinatorAndSub

## Decisions Made
- Orphaned index handled in updateVrfCoordinatorAndSub rather than rngGate -- cleaner because it resolves the orphan at the exact moment we know it is orphaned (coordinator swap time)
- Fallback word derived from lastLootboxRngWord + orphanedIndex -- deterministic, unique per index, uses existing entropy chain
- No loop needed: Research Pitfall 5 confirms at most one lootbox index can be orphaned since requestLootboxRng reverts if rngRequestTime != 0
- fallbackWord==0 guard follows the same safety pattern used in rawFulfillRandomWords

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All RNG gap backfill implementation complete (59-01 gap days + 59-02 orphaned lootbox + midDayTicketRngPending)
- Ready for Phase 60+ test coverage of the full stall-swap-resume flow
- Key verification: lootboxes assigned to orphaned indices should open successfully after coordinator swap

## Self-Check: PASSED

- FOUND: 59-02-SUMMARY.md
- FOUND: commit 6a7bd5ca
- FOUND: DegenerusGameAdvanceModule.sol

---
*Phase: 59-rng-gap-backfill-implementation*
*Completed: 2026-03-22*
