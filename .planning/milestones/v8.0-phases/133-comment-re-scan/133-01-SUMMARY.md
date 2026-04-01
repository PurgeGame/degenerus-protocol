---
phase: 133-comment-re-scan
plan: 01
subsystem: contracts
tags: [natspec, solidity, comments, audit-prep]

# Dependency graph
requires:
  - phase: 130-bot-race-slither-4naly3er
    provides: "NC-18/19/20 bot findings routed to Phase 133 for comment fixes"
provides:
  - "Fixed NatSpec in DegenerusGame.sol (missing @param/@return tags)"
  - "Fixed misplaced NatSpec in DegenerusGameJackpotModule.sol"
  - "Verified DegenerusGameStorage.sol and AdvanceModule already fully documented"
affects: [134-consolidation]

# Tech tracking
tech-stack:
  added: []
  patterns: []

key-files:
  created: []
  modified:
    - contracts/DegenerusGame.sol
    - contracts/modules/DegenerusGameJackpotModule.sol

key-decisions:
  - "DegenerusGameStorage.sol NatSpec already complete -- no changes needed"
  - "DegenerusGameAdvanceModule.sol NatSpec already complete -- no changes needed"
  - "JackpotModule had payDailyJackpot NatSpec misplaced above runTerminalJackpot -- relocated to correct position"

patterns-established: []

requirements-completed: [CMT-01, CMT-02]

# Metrics
duration: 11min
completed: 2026-03-27
---

# Phase 133 Plan 01: Game Core Comment Fix Summary

**Fixed 4 missing NatSpec tags in DegenerusGame.sol and relocated misplaced payDailyJackpot documentation block in JackpotModule**

## Performance

- **Duration:** 11 min
- **Started:** 2026-03-27T04:28:58Z
- **Completed:** 2026-03-27T04:40:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Added missing @param tags for payCoinflipBountyDgnrs (winningBet, bountyPool) in DegenerusGame.sol
- Added missing @param/@return tags for recordTerminalDecBurn and runTerminalDecimatorJackpot in DegenerusGame.sol
- Fixed misplaced payDailyJackpot NatSpec block that was attached to runTerminalJackpot in JackpotModule
- Verified DegenerusGameStorage.sol and DegenerusGameAdvanceModule.sol already have complete NatSpec

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix NatSpec in DegenerusGame + GameStorage** - `7d42914a` (docs)
2. **Task 2: Fix NatSpec in AdvanceModule + JackpotModule** - `dd68a019` (docs)

## Files Created/Modified
- `contracts/DegenerusGame.sol` - Added 3 missing @param tags and 1 @return tag across 3 functions
- `contracts/modules/DegenerusGameJackpotModule.sol` - Relocated payDailyJackpot NatSpec from above runTerminalJackpot to its correct position

## Decisions Made
- DegenerusGameStorage.sol was already fully documented with detailed NatSpec on all storage variables, structs, and functions -- no changes needed
- DegenerusGameAdvanceModule.sol had complete NatSpec on all external functions (advanceGame, wireVrf, requestLootboxRng, reverseFlip, rawFulfillRandomWords, updateVrfCoordinatorAndSub) -- no changes needed
- The JackpotModule payDailyJackpot NatSpec block (22 lines) was placed above runTerminalJackpot instead of its own function -- relocated to correct position

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] payDailyJackpot NatSpec attached to wrong function**
- **Found during:** Task 2 (AdvanceModule + JackpotModule scan)
- **Issue:** The payDailyJackpot NatSpec block (lines 242-262) was placed directly before runTerminalJackpot, meaning Solidity would attach it to the wrong function
- **Fix:** Moved the payDailyJackpot documentation block to directly above the payDailyJackpot function declaration
- **Files modified:** contracts/modules/DegenerusGameJackpotModule.sol
- **Verification:** forge build succeeds, NatSpec now attached to correct functions
- **Committed in:** dd68a019 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Fix was within plan scope (NatSpec accuracy). No scope creep.

## Issues Encountered
None

## Known Stubs
None

## Next Phase Readiness
- Game core contracts (DegenerusGame, GameStorage, AdvanceModule, JackpotModule) now have accurate NatSpec
- Ready for Plans 02-05 to scan remaining contracts

---
*Phase: 133-comment-re-scan*
*Completed: 2026-03-27*
