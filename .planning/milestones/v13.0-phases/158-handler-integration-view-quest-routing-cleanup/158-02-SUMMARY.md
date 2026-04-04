---
phase: 158-handler-integration-view-quest-routing-cleanup
plan: 02
subsystem: quests
tags: [solidity, quest-routing, burnie-coin-cleanup, middleman-removal, direct-handler-calls]

requires:
  - phase: 158-handler-integration-view-quest-routing-cleanup
    plan: 01
    provides: "onlyCoin expanded to accept GAME + AFFILIATE, all 6 handlers with _handleLevelQuestProgress"
provides:
  - "MintModule calls DegenerusQuests.handleMint directly with creditFlip and recordMintQuestStreak"
  - "DegeneretteModule calls DegenerusQuests.handleDegenerette directly with creditFlip"
  - "DegenerusAffiliate calls DegenerusQuests.handleAffiliate directly"
  - "BurnieCoin cleaned of notify* wrappers, _questApplyReward, QuestCompleted event, affiliateQuestReward"
  - "BurnieCoin.decimatorBurn retains questModule.handleDecimator with inlined reward logic"
  - "DegenerusGame.recordMintQuestStreak accepts COIN or GAME"
  - "IDegenerusCoin cleaned of removed function signatures"
affects: [delta-audit, gas-analysis]

tech-stack:
  added: []
  patterns: ["direct quest handler calls from game modules (no BurnieCoin hop)", "_questMint helper for 4-site deduplication in MintModule", "inline IDegenerusQuestsAffiliate interface in DegenerusAffiliate"]

key-files:
  created: []
  modified:
    - "contracts/modules/DegenerusGameMintModule.sol"
    - "contracts/modules/DegenerusGameDegeneretteModule.sol"
    - "contracts/BurnieCoin.sol"
    - "contracts/interfaces/IDegenerusCoin.sol"
    - "contracts/DegenerusGame.sol"
    - "contracts/interfaces/IDegenerusGame.sol"
    - "contracts/DegenerusAffiliate.sol"

key-decisions:
  - "MintModule _questMint helper: private function deduplicates quests.handleMint + creditFlip + recordMintQuestStreak across 4 call sites"
  - "DegeneretteModule: merged two separate notifyQuestDegenerette calls (ETH/BURNIE branches) into single quests.handleDegenerette with ethBet bool"
  - "DegenerusAffiliate uses inline IDegenerusQuestsAffiliate interface rather than importing full IDegenerusQuests (minimizes import surface)"
  - "decimatorBurn inlined reward: completed ? reward : 0 (no event, DegenerusQuests already emits)"
  - "recordMintQuestStreak expanded to accept GAME (delegatecall from MintModule) in addition to COIN"

patterns-established:
  - "Direct handler calls: game modules call DegenerusQuests handlers directly, handle creditFlip locally"
  - "No BurnieCoin middleman: quest notification wrappers eliminated, reducing cross-contract hops"

requirements-completed: [CLEANUP-01]

duration: 2min
completed: 2026-04-01
---

# Phase 158 Plan 02: Quest Routing Cleanup Summary

**Removed BurnieCoin quest notification middleman (5 functions + event), rewired MintModule/DegeneretteModule/Affiliate to call DegenerusQuests handlers directly with local creditFlip**

## Performance

- **Duration:** 2 min
- **Started:** 2026-04-01T18:22:09Z
- **Completed:** 2026-04-01T18:24:46Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments
- MintModule calls quests.handleMint directly via _questMint helper at 4 sites, plus quests.handleLootBox at 1 site, with local creditFlip and recordMintQuestStreak
- DegeneretteModule calls quests.handleDegenerette directly with local creditFlip, merging two coin.notifyQuestDegenerette branches into one
- DegenerusAffiliate calls quests.handleAffiliate directly (removed coin.affiliateQuestReward hop)
- BurnieCoin stripped of notifyQuestMint, notifyQuestLootBox, notifyQuestDegenerette, affiliateQuestReward, _questApplyReward, QuestCompleted event, and all QUEST_TYPE_ constants
- BurnieCoin.decimatorBurn retains questModule.handleDecimator with inlined reward logic (completed ? reward : 0)
- DegenerusGame.recordMintQuestStreak access expanded to COIN or GAME
- IDegenerusCoin cleaned of all removed function signatures
- All 62 Solidity files compile cleanly (npx hardhat compile --force)
- Zero notifyQuest* references remain anywhere in contracts/

## Task Commits

Contract changes are unstaged working-tree modifications per project convention (user reviews before commit). No per-task commits for contract files.

## Files Created/Modified
- `contracts/modules/DegenerusGameMintModule.sol` - Added IDegenerusQuests import, quests constant, _questMint helper; replaced 4x coin.notifyQuestMint + 1x coin.notifyQuestLootBox with direct handler calls
- `contracts/modules/DegenerusGameDegeneretteModule.sol` - Added IDegenerusQuests/IBurnieCoinflip imports, quests/coinflip constants; replaced 2x coin.notifyQuestDegenerette with direct quests.handleDegenerette
- `contracts/BurnieCoin.sol` - Removed notifyQuestMint, notifyQuestLootBox, notifyQuestDegenerette, affiliateQuestReward, _questApplyReward, QuestCompleted event, QUEST_TYPE_ constants; inlined decimatorBurn reward logic
- `contracts/interfaces/IDegenerusCoin.sol` - Removed notifyQuestMint, notifyQuestLootBox, notifyQuestDegenerette, affiliateQuestReward signatures
- `contracts/DegenerusGame.sol` - recordMintQuestStreak access: added GAME alongside COIN
- `contracts/interfaces/IDegenerusGame.sol` - Updated NatSpec for recordMintQuestStreak (COIN or GAME)
- `contracts/DegenerusAffiliate.sol` - Added inline IDegenerusQuestsAffiliate interface and quests constant; replaced coin.affiliateQuestReward with quests.handleAffiliate

## Decisions Made
- **_questMint helper pattern:** Created private _questMint(player, quantity, paidWithEth) in MintModule to deduplicate quests.handleMint + creditFlip + recordMintQuestStreak across 4 call sites.
- **Merged degenerette branches:** Two separate `if (currency == CURRENCY_ETH) / else if (currency == CURRENCY_BURNIE)` calls collapsed into single `if (currency == CURRENCY_ETH || currency == CURRENCY_BURNIE)` with `ethBet` bool.
- **Affiliate inline interface:** DegenerusAffiliate defines a local IDegenerusQuestsAffiliate interface rather than importing the full IDegenerusQuests. Minimizes import surface for a contract that only needs handleAffiliate.
- **Inlined reward in decimatorBurn:** Replaced `_questApplyReward(...)` with `uint256 questReward = completed ? reward : 0`. No event emission needed (DegenerusQuests._questComplete already emits).
- **No BurnieCoinflip changes:** handleFlip call in BurnieCoinflip already calls DegenerusQuests directly (per D-09). Confirmed unchanged.

## Deviations from Plan

None - plan executed exactly as written. All contract changes were already present in the working tree from prior plan execution; verification confirmed correctness.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Known Stubs
None - all handler rewiring is complete with correct quest types, deltas, and creditFlip handling.

## Next Phase Readiness
- All BurnieCoin quest middleman functions removed
- Game modules (MintModule, DegeneretteModule) call DegenerusQuests directly
- DegenerusAffiliate calls quests.handleAffiliate directly
- BurnieCoinflip unchanged (already direct)
- Ready for delta audit of all routing changes

## Self-Check: PASSED

- FOUND: contracts/modules/DegenerusGameMintModule.sol
- FOUND: contracts/modules/DegenerusGameDegeneretteModule.sol
- FOUND: contracts/BurnieCoin.sol
- FOUND: contracts/interfaces/IDegenerusCoin.sol
- FOUND: contracts/DegenerusGame.sol
- FOUND: contracts/interfaces/IDegenerusGame.sol
- FOUND: contracts/DegenerusAffiliate.sol
- FOUND: 158-02-SUMMARY.md
- Compilation: 62 files, 0 errors
- notifyQuest* sweep: 0 matches across contracts/

---
*Phase: 158-handler-integration-view-quest-routing-cleanup*
*Completed: 2026-04-01*
