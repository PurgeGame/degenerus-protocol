---
phase: 124-game-integration
plan: 01
subsystem: contracts
tags: [solidity, delegatecall, hooks, charity, GNRUS, game-integration]

# Dependency graph
requires:
  - phase: 123-degeneruscharity-contract
    provides: DegenerusCharity.sol with resolveLevel and handleGameOver functions
provides:
  - resolveLevel hook in AdvanceModule at level transitions
  - handleGameOver hook in GameOverModule at gameover drain (both terminal paths)
  - Integration tests proving hooks fire via full-protocol VRF cycles
affects: [104-day-advancement-vrf, 106-endgame-game-over]

# Tech tracking
tech-stack:
  added: []
  patterns: [minimal-interface-above-contract, constant-at-ContractAddresses, direct-call-no-try-catch]

key-files:
  created:
    - test/integration/CharityGameHooks.test.js
  modified:
    - contracts/modules/DegenerusGameAdvanceModule.sol
    - contracts/modules/DegenerusGameGameOverModule.sol

key-decisions:
  - "Direct calls (no try/catch) for both hooks per D-01 through D-06 -- reverts are bugs to surface"
  - "resolveLevel(lvl - 1) passes the COMPLETED level, not the NEW level"
  - "handleGameOver in both terminal paths (no-funds early return and main drain)"
  - "Two-day VRF cycle needed for level transition tests (day 1 drains pre-queued tickets, day 2 triggers transition)"

patterns-established:
  - "Charity hook pattern: minimal interface above contract, private constant at ContractAddresses, direct external call"
  - "Level transition integration test pattern: fill prize pool > 50 ETH, drive two VRF cycles"

requirements-completed: [INTG-02]

# Metrics
duration: 20min
completed: 2026-03-26
---

# Phase 124 Plan 01: Game Integration Hooks Summary

**resolveLevel hook at level transitions and handleGameOver hook at gameover drain wired into game modules with 5 passing integration tests**

## Performance

- **Duration:** 20 min
- **Started:** 2026-03-26T14:06:26Z
- **Completed:** 2026-03-26T14:26:32Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- resolveLevel(lvl-1) fires at every level transition inside _finalizeRngRequest's isTicketJackpotDay block
- handleGameOver() fires in both terminal paths of handleGameOverDrain (no-funds path and main drain path)
- Both hooks are direct calls with no try/catch -- reverts surface as bugs per D-01 through D-06
- 5 integration tests pass: currentLevel increment, levelResolved flag, LevelSkipped event, finalized flag, GNRUS burn

## Task Commits

Each task was committed atomically:

1. **Task 1: Add resolveLevel and handleGameOver hooks to game modules** - `692dbe0c` (feat)
2. **Task 2: Integration tests for charity game hooks** - `a5aa67f8` (test)

## Files Created/Modified
- `contracts/modules/DegenerusGameAdvanceModule.sol` - Added IDegenerusCharityResolve interface, charityResolve constant, resolveLevel(lvl-1) call after level=lvl
- `contracts/modules/DegenerusGameGameOverModule.sol` - Added IDegenerusCharityGameOver interface, charityGameOver constant, handleGameOver() in both terminal paths
- `test/integration/CharityGameHooks.test.js` - 252-line integration test with 5 tests covering resolveLevel at level transition and handleGameOver at gameover drain

## Decisions Made
- Direct calls (no try/catch) for both hooks -- these are our contracts, reverts are bugs to surface
- resolveLevel receives `lvl - 1` (the completed level) since the game increments level to `lvl` (purchaseLevel = level + 1) before the call, and DegenerusCharity.currentLevel tracks the current governance level starting at 0
- handleGameOver placed in both terminal paths of handleGameOverDrain: the no-funds early return path (available == 0) and the main drain path (before burnRemainingPools)
- gameOverFinalJackpotPaid guard at function entry prevents double invocation
- Two-day VRF cycle required for level transition tests: day 1 processes ~109 pre-queued tickets, day 2 triggers the actual level transition

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- Prize pool fill calculation required understanding the ticketCost formula: `(price * ticketQuantity) / (4 * TICKET_SCALE)`, meaning each 100 ticket units at 0.01 ETH costs 0.0025 ETH, not 0.01 ETH. Adjusted purchase amounts to ensure >50 ETH reaches the next prize pool.
- Level transition requires two full VRF cycles: first day processes ~1600 pre-queued vault/DGNRS perpetual tickets (109 advanceGame iterations), second day triggers the actual level increment. Test flow adjusted accordingly.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- INTG-02 requirement satisfied: game calls DegenerusCharity.resolveLevel(level) at level transitions and DegenerusCharity.handleGameOver() at gameover drain
- Both hooks verified via full-protocol integration tests with real VRF cycles

## Self-Check: PASSED

- FOUND: contracts/modules/DegenerusGameAdvanceModule.sol
- FOUND: contracts/modules/DegenerusGameGameOverModule.sol
- FOUND: test/integration/CharityGameHooks.test.js
- FOUND: .planning/phases/124-game-integration/124-01-SUMMARY.md
- FOUND: commit 692dbe0c
- FOUND: commit a5aa67f8

---
*Phase: 124-game-integration*
*Completed: 2026-03-26*
