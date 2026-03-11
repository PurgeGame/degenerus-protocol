---
phase: 05-lock-removal
plan: 01
subsystem: contracts
tags: [solidity, rngLockedFlag, guard-removal, foundry, fuzz-testing]

# Dependency graph
requires:
  - phase: 01-prize-pool-packing
    provides: Packed prize pool helpers with freeze-aware routing
  - phase: 02-ticket-queue-double-buffer
    provides: Double-buffered ticket queue with read/write slot isolation
  - phase: 03-freeze-unfreeze
    provides: Prize pool freeze/unfreeze lifecycle and pending accumulators
  - phase: 04-advancegame-rewrite
    provides: Drain gate and freeze-state management in advanceGame
provides:
  - Six rngLockedFlag purchase-path guards removed from four contract modules
  - Players can buy tickets and open lootboxes at any time, even during RNG processing
  - LockRemoval test suite validating all six LOCK requirements with unit + fuzz tests
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns: [delete-and-verify guard removal with grep confirmation]

key-files:
  created:
    - test/fuzz/LockRemoval.t.sol
  modified:
    - contracts/modules/DegenerusGameMintModule.sol
    - contracts/modules/DegenerusGameLootboxModule.sol
    - contracts/modules/DegenerusGameDegeneretteModule.sol
    - contracts/modules/DegenerusGameAdvanceModule.sol

key-decisions:
  - "Bounded fuzz level to uint24.max-1 to avoid arithmetic overflow on level+1 (contract never reaches max level)"

patterns-established:
  - "Delete-and-verify: remove guard lines, update NatSpec, confirm via grep counts, run full suite"

requirements-completed: [LOCK-01, LOCK-02, LOCK-03, LOCK-04, LOCK-05, LOCK-06]

# Metrics
duration: 4min
completed: 2026-03-11
---

# Phase 5 Plan 1: Lock Removal Summary

**Removed six rngLockedFlag purchase-path guards across MintModule, LootboxModule, DegeneretteModule, and AdvanceModule -- players can now buy tickets and open lootboxes during RNG processing**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-11T22:31:57Z
- **Completed:** 2026-03-11T22:36:00Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- LockRemovalHarness + 13 tests (12 unit + 1 fuzz) covering all six LOCK requirements
- Six rngLockedFlag guards removed: two line deletions in MintModule, two in LootboxModule, one compound-condition strip in DegeneretteModule, one line deletion in AdvanceModule
- error RngLocked() declaration removed from LootboxModule (zero remaining usage)
- NatSpec updated at all modified function sites
- Grep verification confirms zero rngLockedFlag references in MintModule, LootboxModule, DegeneretteModule; exactly 6 in AdvanceModule (all out-of-scope)
- Full Foundry suite: 109 tests pass, 12 pre-existing deploy-dependent failures unchanged

## Task Commits

Each task was committed atomically:

1. **Task 1: Create LockRemovalHarness and guard-logic tests** - `13326bdb` (test)
2. **Task 2: Remove six rngLockedFlag guards, update NatSpec, clean up error declarations** - `f4a6596e` (feat)

## Files Created/Modified
- `test/fuzz/LockRemoval.t.sol` - LockRemovalHarness extending DegenerusGameStorage + 13 tests for LOCK-01 through LOCK-06
- `contracts/modules/DegenerusGameMintModule.sol` - LOCK-01 (line 840 deleted) and LOCK-02 (rngLockedFlag stripped from compound condition at line 627)
- `contracts/modules/DegenerusGameLootboxModule.sol` - LOCK-03 (line 557 deleted), LOCK-04 (line 640 deleted), error RngLocked() removed, NatSpec updated
- `contracts/modules/DegenerusGameDegeneretteModule.sol` - LOCK-05 (rngLockedFlag stripped from jackpotResolutionActive at line 503)
- `contracts/modules/DegenerusGameAdvanceModule.sol` - LOCK-06 (line 643 deleted)

## Decisions Made
- Bounded fuzz level to uint24.max-1 to avoid arithmetic overflow on level+1 (contract never reaches max level in practice)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fuzz test uint24 overflow on level+1**
- **Found during:** Task 1 (LockRemoval tests)
- **Issue:** When fuzz generates lvl=type(uint24).max, lvl+1 overflows causing panic revert
- **Fix:** Added `bound(lvl, 0, type(uint24).max - 1)` in fuzz test
- **Files modified:** test/fuzz/LockRemoval.t.sol
- **Verification:** All 13 tests pass including 1001 fuzz runs
- **Committed in:** 13326bdb (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Trivial fuzz boundary fix. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Always-open-purchases milestone is complete
- All five phases delivered: packed pools, double-buffered queue, freeze/unfreeze, drain gates, lock removal
- Players can purchase tickets at any time without downtime during RNG processing

## Self-Check: PASSED

- [x] test/fuzz/LockRemoval.t.sol exists (213 lines, >= 80 min)
- [x] Commit 13326bdb exists (Task 1)
- [x] Commit f4a6596e exists (Task 2)
- [x] MintModule: 0 rngLockedFlag references
- [x] LootboxModule: 0 rngLockedFlag references, 0 RngLocked references
- [x] DegeneretteModule: 0 rngLockedFlag references
- [x] AdvanceModule: 6 rngLockedFlag references (all out-of-scope)
- [x] 13/13 LockRemoval tests pass
- [x] 109/109 non-invariant tests pass (12 pre-existing invariant failures unchanged)

---
*Phase: 05-lock-removal*
*Completed: 2026-03-11*
