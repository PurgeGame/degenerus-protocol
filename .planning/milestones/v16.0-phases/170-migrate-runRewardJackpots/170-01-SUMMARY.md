---
phase: 170-migrate-runRewardJackpots
plan: 01
subsystem: contracts
tags: [solidity, delegatecall, module-migration, jackpot, endgame-elimination]

# Dependency graph
requires:
  - phase: 169-inline-rewardTopAffiliate
    provides: "rewardTopAffiliate inlined into AdvanceModule, first EndgameModule function removed"
provides:
  - "JackpotModule contains runRewardJackpots + _runBafJackpot + _awardJackpotTickets + _jackpotTicketRoll"
  - "AdvanceModule _runRewardJackpots wrapper targets GAME_JACKPOT_MODULE"
  - "IDegenerusGameJackpotModule interface includes runRewardJackpots(uint24,uint256)"
affects: [171-delete-endgame-module, endgame-elimination]

# Tech tracking
tech-stack:
  added: []
  patterns: [module-migration-with-existing-helper-reuse]

key-files:
  created: []
  modified:
    - contracts/modules/DegenerusGameJackpotModule.sol
    - contracts/interfaces/IDegenerusGameModules.sol
    - contracts/modules/DegenerusGameAdvanceModule.sol

key-decisions:
  - "Reused existing _addClaimableEth in JackpotModule instead of copying EndgameModule version (compatible return semantics, avoids duplicate)"
  - "Dropped AutoRebuyExecuted event (existing _addClaimableEth emits AutoRebuyProcessed via _processAutoRebuy)"

patterns-established:
  - "Module migration: reuse existing helpers when signatures and semantics match rather than duplicating"

requirements-completed: [MOD-02]

# Metrics
duration: 12min
completed: 2026-04-03
---

# Phase 170 Plan 01: Migrate runRewardJackpots Summary

**Moved ~265 lines of reward jackpot logic (runRewardJackpots + BAF/Decimator helpers) from EndgameModule to JackpotModule, rewired AdvanceModule delegatecall**

## Performance

- **Duration:** 12 min
- **Started:** 2026-04-03T00:49:16Z
- **Completed:** 2026-04-03T01:02:02Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Migrated runRewardJackpots, _runBafJackpot, _awardJackpotTickets, _jackpotTicketRoll to JackpotModule
- Added IDegenerusJackpots/IDegenerusGame imports, jackpots constant, SMALL_LOOTBOX_THRESHOLD, and RewardJackpotsSettled event
- Rewired AdvanceModule _runRewardJackpots wrapper from GAME_ENDGAME_MODULE to GAME_JACKPOT_MODULE
- Updated IDegenerusGameJackpotModule interface with runRewardJackpots signature
- All contracts compile successfully

## Task Commits

Each task was committed atomically:

1. **Task 1: Move runRewardJackpots + helpers to JackpotModule and update interface** - `7e89a1f4` (feat)
2. **Task 2: Rewire AdvanceModule wrapper and update comments** - `b13fb054` (feat)

## Files Created/Modified
- `contracts/modules/DegenerusGameJackpotModule.sol` - Added imports, constants, event, and 4 functions (runRewardJackpots, _runBafJackpot, _awardJackpotTickets, _jackpotTicketRoll)
- `contracts/interfaces/IDegenerusGameModules.sol` - Added runRewardJackpots to IDegenerusGameJackpotModule interface
- `contracts/modules/DegenerusGameAdvanceModule.sol` - Rewired _runRewardJackpots to GAME_JACKPOT_MODULE, updated module comment

## Decisions Made
- **Reused existing _addClaimableEth:** JackpotModule already had a compatible _addClaimableEth (via _processAutoRebuy). The EndgameModule version inlines auto-rebuy logic and emits AutoRebuyExecuted, while the existing one delegates to _processAutoRebuy and emits AutoRebuyProcessed. Both have identical signatures and compatible claimablePool accounting (EndgameModule version returns 0 and increments claimablePool internally; existing version returns calc.reserved for caller to track). The existing version also has a gameOver guard that prevents pointless auto-rebuy after game end.
- **Dropped AutoRebuyExecuted event:** Since the existing _addClaimableEth emits AutoRebuyProcessed (not AutoRebuyExecuted), the event declaration was unnecessary.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Resolved _addClaimableEth naming conflict**
- **Found during:** Task 1 (moving functions to JackpotModule)
- **Issue:** JackpotModule already contains a private `_addClaimableEth` function (line 823). Copying the EndgameModule version verbatim created a duplicate function error.
- **Fix:** Removed the EndgameModule copy of _addClaimableEth and the unused AutoRebuyExecuted event. The existing JackpotModule _addClaimableEth has compatible signature and return semantics -- verified that claimablePool accounting is correct for both auto-rebuy and normal paths.
- **Files modified:** contracts/modules/DegenerusGameJackpotModule.sol
- **Verification:** forge build succeeds, all 5 required functions present
- **Committed in:** 7e89a1f4 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Necessary to resolve compile-time duplicate. The existing helper is functionally equivalent with better gameOver protection. No scope creep.

## Issues Encountered
None beyond the _addClaimableEth duplicate addressed as a deviation.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Only claimWhalePass remains in EndgameModule (Phase 171 target)
- AdvanceModule's GAME_ENDGAME_MODULE reference is comment-only (no delegatecall)
- IDegenerusGameEndgameModule import retained in AdvanceModule for claimWhalePass path (DegenerusGame.sol)

## Self-Check: PASSED

All artifacts verified:
- SUMMARY.md exists
- Task 1 commit 7e89a1f4 exists
- Task 2 commit b13fb054 exists
- All 3 modified contract files exist

---
*Phase: 170-migrate-runRewardJackpots*
*Completed: 2026-04-03*
