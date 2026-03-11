---
phase: 04-advancegame-rewrite
plan: 01
subsystem: contracts
tags: [solidity, foundry, advance-game, drain-gate, ticket-processing, freeze-state]

# Dependency graph
requires:
  - phase: 03-prize-pool-freeze
    provides: "_swapAndFreeze, _unfreezePool, prizePoolFrozen flag, pending pool accumulators"
  - phase: 02-double-buffer-queue
    provides: "ticketQueue double buffer, _swapTicketSlot, ticketsFullyProcessed flag, mid-day path"
provides:
  - "Pre-RNG drain gate ensuring read slot is fully drained before daily RNG request"
  - "ticketsFullyProcessed flag set at both drain points (pre-do{} and inside-do{})"
  - "AdvanceHarness + 9 unit tests covering ADV-01/02/03 and SC-4 break-path freeze audit"
affects: [05-integration-testing]

# Tech tracking
tech-stack:
  added: []
  patterns: ["Pre-RNG drain gate pattern: guard RNG request behind ticket completion flag"]

key-files:
  created:
    - test/fuzz/AdvanceGameRewrite.t.sol
  modified:
    - contracts/modules/DegenerusGameAdvanceModule.sol

key-decisions:
  - "Defensive read-slot-length check before _runProcessTicketBatch in drain gate (handles Pitfall 1: empty read slot on first daily call)"
  - "Line 216 in-do{} ticket processing kept as defensive code with ADV-03 flag set after it"

patterns-established:
  - "AdvanceHarness with simulateDrainGate for testing pre-RNG gate logic without delegatecall dependencies"

requirements-completed: [ADV-01, ADV-02, ADV-03]

# Metrics
duration: 4min
completed: 2026-03-11
---

# Phase 4 Plan 01: AdvanceGame Rewrite Summary

**Pre-RNG drain gate gating daily RNG behind ticketsFullyProcessed, with 9-test AdvanceHarness covering drain, freeze, and break-path invariants**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-11T22:08:19Z
- **Completed:** 2026-03-11T22:12:25Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Pre-RNG drain gate inserted: daily path bounces caller while read slot has unprocessed entries, proceeds only when ticketsFullyProcessed == true
- ticketsFullyProcessed = true set at both drain points (pre-do{} gate at line 184 and inside-do{} after ticket batch at line 237)
- 9 unit tests covering ADV-01 (mid-day no freeze), ADV-02 (drain gate blocks/proceeds/skips), ADV-03 (flag set before jackpot logic), and SC-4 (break-path freeze audit for 4 exit paths)
- grep verification: exactly 3 _unfreezePool() call sites, 1 _swapAndFreeze() call site (unchanged from Phase 3)

## Task Commits

Each task was committed atomically:

1. **Task 1: Insert pre-RNG drain gate and ticketsFullyProcessed flag** - `9a9f3963` (feat)
2. **Task 2: Create AdvanceHarness and all ADV requirement tests** - `e0545607` (test)

## Files Created/Modified
- `contracts/modules/DegenerusGameAdvanceModule.sol` - Pre-RNG drain gate (lines 173-185) + ADV-03 flag set (line 237)
- `test/fuzz/AdvanceGameRewrite.t.sol` - AdvanceHarness + 9 unit tests for ADV-01/02/03 and SC-4

## Decisions Made
- Used defensive read-slot-length check (`ticketQueue[rk].length > 0`) before calling `_runProcessTicketBatch` in the drain gate, matching the mid-day path pattern and handling Pitfall 1 (empty read slot on first daily call)
- Kept line 216 in-do{} ticket processing as defensive code (effectively a no-op in the new flow but harmless), added `ticketsFullyProcessed = true` after it for ADV-03

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Added read-slot-length guard to drain gate**
- **Found during:** Task 1
- **Issue:** Plan's action block omitted the `ticketQueue[rk].length > 0` check, but the research (Pitfall 1) and code example both include it to handle empty read slot edge case
- **Fix:** Used the research pattern with the length check, preventing unnecessary `_runProcessTicketBatch` call on empty read slot
- **Files modified:** contracts/modules/DegenerusGameAdvanceModule.sol
- **Verification:** All tests pass, drain gate correctly handles empty read slot case
- **Committed in:** 9a9f3963

---

**Total deviations:** 1 auto-fixed (1 bug prevention)
**Impact on plan:** Essential for correctness. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- advanceGame daily path fully restructured with drain gate and freeze-state correctness at all break paths
- Ready for Phase 5 integration testing or further AdvanceModule work
- Pre-existing 12 invariant test failures remain deploy-dependent (not caused by Phase 4 changes)

---
*Phase: 04-advancegame-rewrite*
*Completed: 2026-03-11*
