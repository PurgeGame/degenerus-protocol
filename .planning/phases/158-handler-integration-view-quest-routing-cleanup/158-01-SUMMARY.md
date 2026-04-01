---
phase: 158-handler-integration-view-quest-routing-cleanup
plan: 01
subsystem: quests
tags: [solidity, level-quests, handler-integration, access-control]

requires:
  - phase: 157-quest-logic-roll-chain
    provides: "_handleLevelQuestProgress internal function, levelQuestGlobal storage, MINT_BURNIE=9, IBurnieCoinflip import"
provides:
  - "Level quest progress tracking in all 6 quest handlers"
  - "GAME and AFFILIATE addresses accepted by onlyCoin modifier"
affects: [158-02, delta-audit, gas-analysis]

tech-stack:
  added: []
  patterns: ["level quest progress call before every handler return path"]

key-files:
  created: []
  modified:
    - "contracts/DegenerusQuests.sol"
    - "contracts/interfaces/IDegenerusQuests.sol"

key-decisions:
  - "Placed level quest call AFTER daily quest loop in handleMint (single call covers both returns)"
  - "Placed level quest call BEFORE every return in other 5 handlers (4 paths each)"
  - "Moved mintPrice load before no-slot early return in handleLootBox and handleDegenerette"
  - "Kept onlyCoin modifier name unchanged -- added GAME + AFFILIATE to accepted callers"

patterns-established:
  - "Level quest progress: every handler path calls _handleLevelQuestProgress before return"
  - "handleMint uses single post-loop call with paidWithEth branch (avoids per-return duplication)"

requirements-completed: [QUEST-05, QUEST-07]

duration: 4min
completed: 2026-04-01
---

# Phase 158 Plan 01: Handler Integration Summary

**Level quest progress wired into all 6 handlers with per-return-path coverage, onlyCoin expanded for GAME + AFFILIATE callers**

## Performance

- **Duration:** 4 min
- **Started:** 2026-04-01T17:47:12Z
- **Completed:** 2026-04-01T17:51:30Z
- **Tasks:** 1
- **Files modified:** 2

## Accomplishments
- All 6 handlers (handleMint, handleFlip, handleDecimator, handleAffiliate, handleLootBox, handleDegenerette) call `_handleLevelQuestProgress` on every code path
- handleMint branches on `paidWithEth` to pass correct quest type (MINT_ETH vs MINT_BURNIE) and delta
- handleDegenerette uses existing `targetType` variable for DEGENERETTE_ETH vs DEGENERETTE_BURNIE
- onlyCoin modifier expanded to accept GAME and AFFILIATE addresses (prep for Plan 02 routing cleanup)
- `npx hardhat compile --force` passes cleanly (62 files)
- 21 total occurrences of `_handleLevelQuestProgress` (function definition + 20 call sites across 6 handlers)

## Task Commits

Each task was committed atomically:

1. **Task 1: Expand onlyCoin modifier and add _handleLevelQuestProgress to all 6 handlers** - `1c7abbb5` (feat)

## Files Created/Modified
- `contracts/DegenerusQuests.sol` - onlyCoin modifier expanded (GAME + AFFILIATE), level quest progress calls in all 6 handlers, includes Phase 157 prerequisite base
- `contracts/interfaces/IDegenerusQuests.sol` - Phase 157 prerequisite (LevelQuestCompleted event, rollLevelQuest, getPlayerLevelQuestView)

## Decisions Made
- **handleMint level quest placement:** Single call after the daily quest for-loop rather than before each return inside the loop. The loop doesn't return early (it uses `continue`), so one post-loop call covers all paths.
- **mintPrice hoisting in handleLootBox:** Moved `questGame.mintPrice()` call from after the no-slot check to before it. This adds one external call on the no-slot-match path (previously skipped), but is necessary for the level quest target computation. The call is a view on an immutable field (gas-cheap).
- **mintPrice hoisting in handleDegenerette:** Same pattern -- moved before no-slot check so level quest call has mintPrice available on all paths.
- **Modifier name unchanged:** Kept `onlyCoin` rather than renaming to `onlyAuthorized` to minimize diff and avoid renaming across NatSpec/reverts.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Copied Phase 157 prerequisite contract changes to worktree**
- **Found during:** Task 1 (compilation)
- **Issue:** Worktree branched from HEAD before Phase 157 uncommitted changes. DegenerusQuests.sol was 1598 lines (missing _handleLevelQuestProgress, levelQuestGlobal, etc.)
- **Fix:** Copied working-tree files from main repo for all Phase 157 modified contracts (DegenerusQuests.sol, IDegenerusQuests.sol, BurnieCoin.sol, BurnieCoinflip.sol, DegenerusGame.sol, IDegenerusGame.sol, DegenerusGameModuleInterfaces.sol, DegenerusGameAdvanceModule.sol, DegenerusGameJackpotModule.sol)
- **Files modified:** 9 contract files in worktree
- **Verification:** `npx hardhat compile --force` passes cleanly
- **Committed in:** 1c7abbb5 (only DegenerusQuests.sol and IDegenerusQuests.sol committed; other files are Phase 157 dependencies not part of this plan)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Prerequisite sync necessary for worktree compilation. No scope creep.

## Issues Encountered
None beyond the prerequisite sync described above.

## User Setup Required
None - no external service configuration required.

## Known Stubs
None - all handler integrations are fully wired with correct quest types, deltas, and mintPrice arguments.

## Next Phase Readiness
- All 6 handlers track level quest progress on every code path
- onlyCoin accepts GAME + AFFILIATE, ready for Plan 02 routing cleanup (BurnieCoin middleman removal)
- getPlayerLevelQuestView already implemented in Phase 157 (QUEST-07 satisfied, no changes needed per D-12)

## Self-Check: PASSED

- FOUND: contracts/DegenerusQuests.sol
- FOUND: contracts/interfaces/IDegenerusQuests.sol
- FOUND: 158-01-SUMMARY.md
- FOUND: commit 1c7abbb5

---
*Phase: 158-handler-integration-view-quest-routing-cleanup*
*Completed: 2026-04-01*
