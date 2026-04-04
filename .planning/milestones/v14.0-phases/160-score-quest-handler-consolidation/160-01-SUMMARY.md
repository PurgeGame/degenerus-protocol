---
phase: 160-score-quest-handler-consolidation
plan: 01
subsystem: contracts
tags: [solidity, bit-packing, gas-optimization, activity-score, deityPassCount]

# Dependency graph
requires:
  - phase: 159-storage-analysis-architecture-design
    provides: Architecture spec with packed struct layout and score consolidation design
provides:
  - "Shared 3-arg _playerActivityScore(address, uint32 questStreak, uint24 streakBaseLevel) in MintStreakUtils"
  - "2-arg convenience wrapper _playerActivityScore(address, uint32 questStreak) using _activeTicketLevel()"
  - "DEITY_PASS_COUNT_SHIFT = 184 in BitPackingLib (bits 184-199 of mintPacked_)"
  - "affiliate constant and score constants consolidated in DegenerusGameStorage"
  - "_mintCountBonusPoints moved to DegenerusGameStorage as internal pure"
  - "_activeTicketLevel moved to MintStreakUtils as internal"
  - "DegeneretteModule duplicate _playerActivityScoreInternal fully eliminated"
affects: [160-02, 160-03, purchase-path-optimization, quest-handler-consolidation]

# Tech tracking
tech-stack:
  added: []
  patterns: ["Shared score function with streakBaseLevel parameter for DegeneretteModule semantic difference", "deityPassCount packed into mintPacked_ eliminating cold mapping SLOAD"]

key-files:
  created: []
  modified:
    - contracts/libraries/BitPackingLib.sol
    - contracts/modules/DegenerusGameMintStreakUtils.sol
    - contracts/storage/DegenerusGameStorage.sol
    - contracts/DegenerusGame.sol
    - contracts/modules/DegenerusGameDegeneretteModule.sol
    - contracts/modules/DegenerusGameWhaleModule.sol
    - contracts/modules/DegenerusGameLootboxModule.sol
    - contracts/modules/DegenerusGameAdvanceModule.sol
    - contracts/modules/DegenerusGameMintModule.sol
    - contracts/modules/DegenerusGameEndgameModule.sol

key-decisions:
  - "Shared _playerActivityScore placed in MintStreakUtils (not DegenerusGameStorage) because it needs _mintStreakEffective which is defined in MintStreakUtils"
  - "affiliate constant moved from per-module declarations to DegenerusGameStorage (shared base), removing 5 duplicate declarations"
  - "DegeneretteModule fetches questStreak via questView.playerQuestStates (non-purchase path, acceptable STATICCALL cost) since quest notification happens after score computation"
  - "deityPassCount mapping declaration retained with DEPRECATED comment to prevent storage slot key reuse"

patterns-established:
  - "3-arg _playerActivityScore with streakBaseLevel: DegeneretteModule passes level + 1, all others use _activeTicketLevel() via 2-arg wrapper"
  - "Score constants (DEITY_PASS_ACTIVITY_BONUS_BPS, PASS_STREAK_FLOOR_POINTS, PASS_MINT_COUNT_FLOOR_POINTS) live in DegenerusGameStorage for all inheritors"

requirements-completed: [SCORE-04, SCORE-05]

# Metrics
duration: 20min
completed: 2026-04-01
---

# Phase 160 Plan 01: Score & Deity Pass Packing Summary

**deityPassCount packed into mintPacked_ bits 184-199 eliminating 1 cold SLOAD per score call, shared 3-arg _playerActivityScore in MintStreakUtils replacing DegeneretteModule's 80-line duplicate**

## Performance

- **Duration:** 20 min
- **Started:** 2026-04-01T22:38:36Z
- **Completed:** 2026-04-01T22:58:36Z
- **Tasks:** 2
- **Files modified:** 10

## Accomplishments
- Packed deityPassCount into mintPacked_ bits 184-199, migrating all 12 read/write sites across 6 contracts
- Created shared 3-arg _playerActivityScore in MintStreakUtils with streakBaseLevel parameter (DegeneretteModule passes level + 1)
- Deleted 80-line _playerActivityScoreInternal duplicate from DegeneretteModule plus duplicate _mintCountBonusPoints
- Consolidated affiliate constant from 5 per-module declarations to single DegenerusGameStorage declaration
- Moved _activeTicketLevel from private in DegenerusGame to internal in MintStreakUtils

## Task Commits

Each task was committed atomically:

1. **Task 1: Pack deityPassCount into mintPacked_ + add shared _playerActivityScore** - `c98287e0` (feat)
2. **Task 2: Delete DegeneretteModule duplicate + wire to shared implementation** - `bf4f470c` (feat)

## Files Created/Modified
- `contracts/libraries/BitPackingLib.sol` - Added DEITY_PASS_COUNT_SHIFT = 184 constant, updated bit layout comment
- `contracts/modules/DegenerusGameMintStreakUtils.sol` - New shared _playerActivityScore (3-arg + 2-arg) and _activeTicketLevel
- `contracts/storage/DegenerusGameStorage.sol` - Added affiliate constant, score constants, _mintCountBonusPoints, deprecated deityPassCount mapping
- `contracts/DegenerusGame.sol` - Rewired 1-arg _playerActivityScore to delegate to 2-arg, migrated constructor + 4 read sites from deityPassCount to mintPacked_, removed duplicate private functions and constants
- `contracts/modules/DegenerusGameDegeneretteModule.sol` - Deleted _playerActivityScoreInternal + _mintCountBonusPoints + duplicate constants, wired to shared 3-arg with level + 1
- `contracts/modules/DegenerusGameWhaleModule.sol` - Migrated 2 read sites + 1 write site from deityPassCount to mintPacked_
- `contracts/modules/DegenerusGameLootboxModule.sol` - Migrated 1 read site, added BitPackingLib import
- `contracts/modules/DegenerusGameAdvanceModule.sol` - Migrated 1 read site using already-loaded mintData
- `contracts/modules/DegenerusGameMintModule.sol` - Removed duplicate affiliate constant
- `contracts/modules/DegenerusGameEndgameModule.sol` - Removed duplicate affiliate constant

## Decisions Made
- **Shared function location:** MintStreakUtils instead of DegenerusGameStorage because _playerActivityScore needs _mintStreakEffective which is defined in MintStreakUtils. Both DegenerusGame and DegeneretteModule inherit MintStreakUtils.
- **affiliate constant consolidation:** Moved from 5 separate module declarations to DegenerusGameStorage (shared base). All modules inherit it through the Storage chain.
- **DegeneretteModule streak fetch:** Uses questView.playerQuestStates STATICCALL since quest notification (coin.notifyQuestDegenerette) happens AFTER score computation in the execution flow. Non-purchase path, so extra call acceptable.
- **deityPassCount mapping retained:** Declaration kept with DEPRECATED comment since removing a mapping declaration is safe (hashed slots) but documentation is cleaner for audit trail.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] affiliate constant conflict across 5 modules**
- **Found during:** Task 1 (compilation)
- **Issue:** Moving affiliate to DegenerusGameStorage caused identifier conflicts with identical declarations in WhaleModule, MintModule, EndgameModule, and DegeneretteModule
- **Fix:** Removed duplicate affiliate declarations from all 4 downstream modules, replaced with comment referencing DegenerusGameStorage
- **Files modified:** WhaleModule, MintModule, EndgameModule, DegeneretteModule
- **Verification:** forge build succeeds

**2. [Rule 3 - Blocking] _mintCountBonusPoints visibility conflict with DegeneretteModule**
- **Found during:** Task 1 (compilation)
- **Issue:** DegeneretteModule's private _mintCountBonusPoints conflicted with the new internal version in DegenerusGameStorage (Solidity disallows overriding internal with private of same name)
- **Fix:** Deleted DegeneretteModule's private _mintCountBonusPoints early (it would be deleted in Task 2 anyway)
- **Files modified:** DegeneretteModule
- **Verification:** forge build succeeds

**3. [Rule 3 - Blocking] DEITY_PASS_ACTIVITY_BONUS_BPS constant conflict**
- **Found during:** Task 1 (pre-compilation analysis)
- **Issue:** DegeneretteModule declared private DEITY_PASS_ACTIVITY_BONUS_BPS which conflicted with the new internal version in DegenerusGameStorage
- **Fix:** Removed from DegeneretteModule, kept WHALE_PASS_ prefixed constants temporarily (deleted in Task 2)
- **Files modified:** DegeneretteModule
- **Verification:** forge build succeeds

**4. [Rule 3 - Blocking] BitPackingLib not imported in LootboxModule**
- **Found during:** Task 1 (compilation)
- **Issue:** LootboxModule used BitPackingLib.DEITY_PASS_COUNT_SHIFT but didn't import the library (library imports are file-local in Solidity)
- **Fix:** Added BitPackingLib import to LootboxModule
- **Files modified:** LootboxModule
- **Verification:** forge build succeeds

**5. [Rule 3 - Blocking] _playerActivityScore needs _mintStreakEffective from MintStreakUtils**
- **Found during:** Task 1 (inheritance analysis)
- **Issue:** Plan specified placing shared function in DegenerusGameStorage, but it needs _mintStreakEffective defined in child contract MintStreakUtils
- **Fix:** Placed shared function in MintStreakUtils instead (both DegenerusGame and DegeneretteModule inherit it)
- **Files modified:** MintStreakUtils (added), DegenerusGameStorage (kept helpers only)
- **Verification:** forge build succeeds, both contracts access shared function

---

**Total deviations:** 5 auto-fixed (all Rule 3 - blocking issues during compilation)
**Impact on plan:** All auto-fixes were necessary for compilation. No scope creep -- all changes serve the original plan objectives.

## Issues Encountered
None beyond the compilation issues documented as deviations.

## Known Stubs
None -- all code paths are fully wired with no placeholders.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Shared _playerActivityScore ready for Plan 02 to wire quest streak forwarding on the purchase path
- _activeTicketLevel now internal, ready for Plan 02/03 to call from MintModule for cached score computation
- All contracts compile clean with zero errors

---
*Phase: 160-score-quest-handler-consolidation*
*Completed: 2026-04-01*
