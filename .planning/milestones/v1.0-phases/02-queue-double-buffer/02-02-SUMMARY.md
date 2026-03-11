---
phase: 02-queue-double-buffer
plan: 02
subsystem: game-logic
tags: [solidity, double-buffer, ticket-queue, advanceGame, mid-day-swap]

requires:
  - phase: 02-queue-double-buffer
    plan: 01
    provides: "_tqWriteKey/_tqReadKey helpers, _swapTicketSlot, buffer isolation"
provides:
  - "Mid-day swap path in advanceGame replacing unconditional revert"
  - "MID_DAY_SWAP_THRESHOLD = 440 constant for throughput-driven swaps"
  - "Jackpot-phase mid-day swap for any non-empty write queue"
  - "5 unit tests proving threshold, jackpot, revert, and read-slot-first conditions"
affects: [03-freeze-orchestration, 04-advance-game-rewrite]

tech-stack:
  added: []
  patterns: ["mid-day path: drain read slot -> check write threshold -> swap or revert"]

key-files:
  created: []
  modified:
    - contracts/modules/DegenerusGameAdvanceModule.sol
    - contracts/storage/DegenerusGameStorage.sol
    - test/fuzz/QueueDoubleBuffer.t.sol

key-decisions:
  - "Option C testing approach: building-block tests via QueueHarness rather than full AdvanceModule harness (delegatecall + coin + VRF dependencies too complex)"
  - "Mid-day swap uses _swapTicketSlot only (not _swapAndFreeze) -- mid-day processing does not touch jackpots/payouts"

patterns-established:
  - "Mid-day path pattern: process read slot first, then check write threshold, then swap or revert"
  - "Threshold gating: MID_DAY_SWAP_THRESHOLD (uint32) checked against ticketQueue[wk].length"

requirements-completed: [QUEUE-04]

duration: 3min
completed: 2026-03-11
---

# Phase 2 Plan 2: Mid-Day Swap Trigger Summary

**Mid-day advanceGame path with 440-ticket threshold swap trigger and jackpot-phase bypass, replacing unconditional revert NotTimeYet()**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-11T21:18:31Z
- **Completed:** 2026-03-11T21:21:54Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Replaced unconditional `revert NotTimeYet()` on same-day advanceGame with conditional mid-day swap logic
- Added MID_DAY_SWAP_THRESHOLD = 440 constant to DegenerusGameStorage for throughput-driven queue draining
- Mid-day path drains read slot first via _runProcessTicketBatch, then triggers _swapTicketSlot when write queue qualifies
- Jackpot phase triggers swap for any non-empty write queue (bypasses 440 threshold)
- 5 new unit tests covering threshold, jackpot, revert condition, and read-slot-first guard

## Task Commits

Each task was committed atomically:

1. **Task 1: Add MID_DAY_SWAP_THRESHOLD constant and mid-day swap path** - `8fcfd032` (feat)
2. **Task 2: Mid-day swap trigger unit tests** - `485a5ad0` (test)

## Files Created/Modified
- `contracts/storage/DegenerusGameStorage.sol` - Added MID_DAY_SWAP_THRESHOLD = 440 constant
- `contracts/modules/DegenerusGameAdvanceModule.sol` - Replaced revert NotTimeYet() with conditional mid-day swap path
- `test/fuzz/QueueDoubleBuffer.t.sol` - Added MidDaySwapTest contract with 5 tests + QueueHarness extensions

## Decisions Made
- Used Option C (building-block tests) instead of Option A (full AdvanceModule harness) because AdvanceModule has too many delegatecall + interface dependencies (coin, VRF, coinflip) for isolated unit testing
- Mid-day swap uses _swapTicketSlot only, not _swapAndFreeze, consistent with research recommendation that mid-day processing does not touch jackpots/payouts

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 2 (Queue Double Buffer) fully complete: all QUEUE-01 through QUEUE-04 requirements implemented
- Ready for Phase 3 (Freeze Orchestration) which will add _swapAndFreeze for end-of-day paths
- Mid-day path explicitly uses _swapTicketSlot (no freeze), so Phase 3 freeze logic won't conflict

## Self-Check: PASSED

- Commit 8fcfd032 (feat): FOUND
- Commit 485a5ad0 (test): FOUND
- contracts/storage/DegenerusGameStorage.sol: FOUND
- contracts/modules/DegenerusGameAdvanceModule.sol: FOUND
- test/fuzz/QueueDoubleBuffer.t.sol: FOUND
- 02-02-SUMMARY.md: FOUND
- MID_DAY_SWAP_THRESHOLD = 440: VERIFIED
- NotTimeYet as fallthrough only (line 170): VERIFIED
- All 11 QueueDoubleBuffer tests: PASSED

---
*Phase: 02-queue-double-buffer*
*Completed: 2026-03-11*
