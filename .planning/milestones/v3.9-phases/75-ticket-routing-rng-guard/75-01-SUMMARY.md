---
phase: 75-ticket-routing-rng-guard
plan: 01
subsystem: storage
tags: [solidity, ticket-queue, routing, rng-guard, foundry, tdd]

# Dependency graph
requires:
  - phase: 74-storage-foundation
    provides: "_tqFarFutureKey helper and TICKET_FAR_FUTURE_BIT constant"
provides:
  - "Far-future ticket routing in _queueTickets, _queueTicketsScaled, _queueTicketRange"
  - "RngLocked guard preventing permissionless FF writes during VRF commitment window"
  - "phaseTransitionActive exemption for advanceGame-origin FF writes"
  - "Foundry test harness and 12 tests proving routing + guard behaviors"
affects: [76-ticket-drain, 80-integration-tests]

# Tech tracking
tech-stack:
  added: []
  patterns: ["conditional key selection: isFarFuture ? _tqFarFutureKey : _tqWriteKey", "rngLocked + phaseTransitionActive guard pattern"]

key-files:
  created: ["test/fuzz/TicketRouting.t.sol"]
  modified: ["contracts/storage/DegenerusGameStorage.sol", "contracts/DegenerusGame.sol", "contracts/modules/DegenerusGameWhaleModule.sol", "contracts/modules/DegenerusGameAdvanceModule.sol"]

key-decisions:
  - "Consolidate error RngLocked() in DegenerusGameStorage base contract, remove from inheriting contracts"
  - "Level cached outside _queueTicketRange loop to avoid per-iteration SLOAD (100 gas savings per level)"

patterns-established:
  - "Central fix pattern: routing logic inside queue functions, not at caller sites"
  - "Storage sentinel exemption: phaseTransitionActive for advanceGame-origin writes"

requirements-completed: [ROUTE-01, ROUTE-02, ROUTE-03, RNG-02]

# Metrics
duration: 5min
completed: 2026-03-23
---

# Phase 75 Plan 01: Ticket Routing + RNG Guard Summary

**Far-future ticket routing via conditional _tqFarFutureKey selection with rngLocked guard and phaseTransitionActive exemption in all three queue functions**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-23T01:46:23Z
- **Completed:** 2026-03-23T01:51:37Z
- **Tasks:** 2 (TDD RED + GREEN)
- **Files modified:** 5

## Accomplishments
- All 3 queue functions (_queueTickets, _queueTicketsScaled, _queueTicketRange) route far-future tickets (targetLevel > level+6) to _tqFarFutureKey
- RngLocked guard blocks permissionless FF key writes during VRF commitment window
- phaseTransitionActive exemption allows advanceGame-origin vault perpetual tickets through
- 12 Foundry tests pass covering routing, boundary, scaled, range, and guard behaviors
- Phase 74 collision tests pass (no regression)
- Clean compilation across all 58 Solidity files

## Task Commits

Each task was committed atomically:

1. **Task 1: RED -- Create Foundry test harness and failing tests** - `f26ae838` (test)
2. **Task 2: GREEN -- Implement routing + RNG guard** - `55e2e6ea` (feat)

## Files Created/Modified
- `test/fuzz/TicketRouting.t.sol` - Harness + 12 tests proving ROUTE-01/02/03 and RNG-02
- `contracts/storage/DegenerusGameStorage.sol` - Routing logic + RngLocked error + guard in 3 queue functions
- `contracts/DegenerusGame.sol` - Removed duplicate RngLocked error (now inherited from base)
- `contracts/modules/DegenerusGameWhaleModule.sol` - Removed duplicate RngLocked error (now inherited from base)
- `contracts/modules/DegenerusGameAdvanceModule.sol` - Removed duplicate RngLocked error (now inherited from base)

## Decisions Made
- Consolidated `error RngLocked()` declaration in DegenerusGameStorage base contract rather than duplicating across inheriting contracts. This is cleaner since all modules inherit from the storage contract and the error is now used at the storage level.
- Cached `level` outside _queueTicketRange loop as `currentLevel` to avoid repeated SLOAD (100 gas per iteration, up to 100 iterations for whale pass claims).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Removed duplicate RngLocked error declarations from inheriting contracts**
- **Found during:** Task 2 (Compilation of error declaration)
- **Issue:** Adding `error RngLocked()` to DegenerusGameStorage caused Solidity DeclarationError because DegenerusGame, WhaleModule, and AdvanceModule already declared the same error and inherit from DegenerusGameStorage
- **Fix:** Removed `error RngLocked()` from DegenerusGame.sol, DegenerusGameWhaleModule.sol, and DegenerusGameAdvanceModule.sol; replaced with inheritance comments
- **Files modified:** contracts/DegenerusGame.sol, contracts/modules/DegenerusGameWhaleModule.sol, contracts/modules/DegenerusGameAdvanceModule.sol
- **Verification:** `npx hardhat compile` succeeds with 58 files, all existing error references resolve correctly
- **Committed in:** 55e2e6ea (Task 2 commit)

**2. [Rule 3 - Blocking] Updated test harness error selector reference**
- **Found during:** Task 2 (Test compilation after removing harness-local error)
- **Issue:** Test harness declared local `error RngLocked()` which conflicted with inherited version; after removal, `TicketRoutingHarness.RngLocked.selector` was not accessible since Solidity requires referencing inherited errors via the declaring contract
- **Fix:** Changed `TicketRoutingHarness.RngLocked.selector` to `DegenerusGameStorage.RngLocked.selector` in all test assertions
- **Files modified:** test/fuzz/TicketRouting.t.sol
- **Verification:** All 12 tests compile and pass
- **Committed in:** 55e2e6ea (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 3 - blocking)
**Impact on plan:** Both fixes necessary for compilation. No scope creep; the consolidated error location is actually better practice.

## Issues Encountered
None beyond the deviations documented above.

## User Setup Required
None - no external service configuration required.

## Known Stubs
None - all routing and guard logic is fully wired.

## Next Phase Readiness
- Far-future routing is active in all 3 queue functions
- Ready for Phase 76+ to implement the drain mechanism (processFutureTicketBatch)
- Integration tests (Phase 80) can exercise the full ticket lifecycle

---
*Phase: 75-ticket-routing-rng-guard*
*Completed: 2026-03-23*
