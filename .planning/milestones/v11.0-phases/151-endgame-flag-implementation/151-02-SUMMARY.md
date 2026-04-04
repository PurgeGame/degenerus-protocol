---
phase: 151-endgame-flag-implementation
plan: 02
subsystem: contracts
tags: [solidity, endgame, mint-enforcement, lootbox-redirect, ban-removal]

requires:
  - phase: 151-01
    provides: gameOverPossible flag in GameStorage, set by AdvanceModule
provides:
  - GameOverPossible error + enforcement in MintModule
  - Far-future redirect in LootboxModule when flag active
  - Full removal of 30-day BURNIE ban constants and errors
affects: [testing, deployment]

tech-stack:
  added: []
  patterns: [flag-based enforcement replacing time-based ban]

key-files:
  created: []
  modified:
    - contracts/modules/DegenerusGameMintModule.sol
    - contracts/modules/DegenerusGameLootboxModule.sol

key-decisions:
  - "Error named GameOverPossible (matching flag name, not EndgameFlagActive from plan)"
  - "Lootbox redirect uses _tqFarFutureKey(currentLevel) with bit 22 for far-future key space"
  - "Only current-level BURNIE lootbox tickets redirect; near-future rolls (currentLevel+1..+6) unaffected"

patterns-established:
  - "Flag-gated enforcement: single bool read replaces elapsed-time computation"

requirements-completed: [REM-01, ENF-01, ENF-02, ENF-03]

duration: 12min
completed: 2026-03-31
---

# Plan 151-02: Remove BURNIE Ban + Wire Enforcement Summary

**30-day BURNIE ban fully removed, MintModule reverts with GameOverPossible when flag active, LootboxModule redirects current-level tickets to far-future key space via bit 22**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-03-31T21:40:00Z
- **Completed:** 2026-03-31T21:44:32Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Deleted COIN_PURCHASE_CUTOFF, COIN_PURCHASE_CUTOFF_LVL0, CoinPurchaseCutoff error from MintModule
- BURNIE ticket purchases revert with GameOverPossible() when flag active
- Deleted BURNIE_LOOT_CUTOFF, BURNIE_LOOT_CUTOFF_LVL0 from LootboxModule
- Current-level BURNIE lootbox tickets redirect to far-future (bit 22) when flag active
- ETH paths completely unaffected
- Audited all "30 days" references — only GameOverModule final sweep timer remains (unrelated)

## Task Commits

1. **Task 1: Remove 30-day ban + wire enforcement in MintModule** - `fe146106` (feat)
2. **Task 2: Remove 30-day ban + wire redirect in LootboxModule** - `fe146106` (feat, combined commit)

## Files Created/Modified
- `contracts/modules/DegenerusGameMintModule.sol` - Removed CoinPurchaseCutoff error + constants, added GameOverPossible error + endgameFlag check
- `contracts/modules/DegenerusGameLootboxModule.sol` - Removed BURNIE_LOOT_CUTOFF constants, replaced elapsed-time redirect with gameOverPossible + _tqFarFutureKey

## Decisions Made
- Error named `GameOverPossible()` matching flag variable name
- Far-future redirect uses `_tqFarFutureKey(currentLevel)` (bit 22) instead of old `currentLevel + 2`
- Near-future rolls (currentLevel+1..+6) intentionally not redirected

## Deviations from Plan

- Error named `GameOverPossible` instead of `EndgameFlagActive` — follows variable naming convention
- Flag variable named `gameOverPossible` instead of `endgameFlag` (decided in Plan 01)

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Endgame flag implementation complete across all four contracts
- Ready for testing and verification

---
*Phase: 151-endgame-flag-implementation*
*Completed: 2026-03-31*
