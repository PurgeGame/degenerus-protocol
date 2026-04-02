---
phase: 168-storage-repack
plan: 01
subsystem: storage
tags: [solidity, evm-storage, slot-packing, gas-optimization, delegatecall]

requires:
  - phase: 167-integration-test-baseline
    provides: stable codebase with v15.0 complete
provides:
  - repacked EVM slot 0 (32/32 bytes, zero padding)
  - currentPrizePool downsized to uint128 packed in slot 1
  - _getCurrentPrizePool()/_setCurrentPrizePool() helper API
  - eliminated old slot 2 (all subsequent slots shift down by 1)
affects: [168-storage-repack plan 02 (test offset updates), 168-storage-repack plan 03 (verification), 169-inline-rewardTopAffiliate, 170-migrate-runRewardJackpots]

tech-stack:
  added: []
  patterns: [uint128 packed storage with uint256 helper API for ABI compatibility]

key-files:
  created: []
  modified:
    - contracts/storage/DegenerusGameStorage.sol
    - contracts/modules/DegenerusGameJackpotModule.sol
    - contracts/modules/DegenerusGameGameOverModule.sol
    - contracts/DegenerusGame.sol
    - contracts/modules/DegenerusGameAdvanceModule.sol

key-decisions:
  - "currentPrizePool helpers read/write Solidity variable directly (no assembly), matching Pitfall 8 guidance"
  - "Helpers return/accept uint256 for ABI compatibility, narrowing to uint128 only at storage boundary"
  - "poolConsolidationDone removal and _runRewardJackpots reorder applied as prerequisites (user's uncommitted changes)"

patterns-established:
  - "Packed storage helper pattern: _getX()/_setX() with uint256 interface over narrower packed types"

requirements-completed: [STOR-01, STOR-02, STOR-03, STOR-04]

duration: 9min
completed: 2026-04-02
---

# Phase 168 Plan 01: Storage Repack Summary

**EVM slots 0-2 repacked: slot 0 filled to 32/32 bytes, currentPrizePool downsized to uint128 in slot 1, old slot 2 eliminated, all 11 consumer sites migrated to helper API**

## Performance

- **Duration:** 9 min
- **Started:** 2026-04-02T19:29:15Z
- **Completed:** 2026-04-02T19:38:42Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Repacked slot 0 to 32/32 bytes by moving ticketsFullyProcessed and gameOverPossible from slot 1
- Downsized currentPrizePool from uint256 (full slot 2) to uint128 packed into slot 1, eliminating one storage slot
- Created _getCurrentPrizePool()/_setCurrentPrizePool() helpers returning/accepting uint256 for seamless integration
- Replaced all 11 direct currentPrizePool access sites across 3 consuming contracts
- Updated all slot header comments and architecture overview NatSpec to match actual layout
- Verified via forge inspect: slot 0 = 32 bytes (15 vars), slot 1 = 24 bytes (4 vars), prizePoolsPacked shifted to slot 2

## Task Commits

Each task was committed atomically:

1. **Task 1: Repack storage variables + add currentPrizePool helpers + update slot comments** - `ed057810` (feat)
2. **Task 2: Replace all direct currentPrizePool access with helpers in consuming contracts** - `622cc1ae` (feat)

## Files Created/Modified
- `contracts/storage/DegenerusGameStorage.sol` - Repacked storage layout, new helpers, updated comments
- `contracts/modules/DegenerusGameJackpotModule.sol` - 7 reads + 4 writes via helpers (11 total replacements)
- `contracts/modules/DegenerusGameGameOverModule.sol` - 2 zeroing sites via _setCurrentPrizePool(0)
- `contracts/DegenerusGame.sol` - 2 reads via _getCurrentPrizePool() (view function + obligations)
- `contracts/modules/DegenerusGameAdvanceModule.sol` - poolConsolidationDone removal + _runRewardJackpots reorder (user prereq)

## Decisions Made
- Applied user's uncommitted prerequisite changes (poolConsolidationDone removal, _runRewardJackpots reorder) as part of Task 1 since the plan assumed this state
- Used Solidity-managed variable access in helpers (not assembly) per Pitfall 8 guidance
- Helper functions return/accept uint256 to avoid intermediate arithmetic issues (Pitfall 4) -- narrowing only at storage write boundary

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Applied user's uncommitted prerequisite changes**
- **Found during:** Task 1 (storage repack)
- **Issue:** Plan assumed poolConsolidationDone was already removed (present in main repo's unstaged changes but not in worktree)
- **Fix:** Applied the user's uncommitted diff (poolConsolidationDone removal from storage + AdvanceModule) before proceeding with repack
- **Files modified:** contracts/storage/DegenerusGameStorage.sol, contracts/modules/DegenerusGameAdvanceModule.sol
- **Verification:** forge inspect confirms slot layout matches plan's expected baseline
- **Committed in:** ed057810 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking prerequisite)
**Impact on plan:** Prerequisite change was already prepared by user in main repo; mechanical application only. No scope creep.

## Storage Layout Verification

```
Slot 0 (32/32 bytes):
  offset  0: levelStartTime (uint48)
  offset  6: dailyIdx (uint48)
  offset 12: rngRequestTime (uint48)
  offset 18: level (uint24)
  offset 21: jackpotPhaseFlag (bool)
  offset 22: jackpotCounter (uint8)
  offset 23: lastPurchaseDay (bool)
  offset 24: decWindowOpen (bool)
  offset 25: rngLockedFlag (bool)
  offset 26: phaseTransitionActive (bool)
  offset 27: gameOver (bool)
  offset 28: dailyJackpotCoinTicketsPending (bool)
  offset 29: compressedJackpotFlag (uint8)
  offset 30: ticketsFullyProcessed (bool)    <-- moved from slot 1
  offset 31: gameOverPossible (bool)         <-- moved from slot 1

Slot 1 (24/32 bytes):
  offset  0: purchaseStartDay (uint48)
  offset  6: ticketWriteSlot (uint8)
  offset  7: prizePoolFrozen (bool)
  offset  8: currentPrizePool (uint128)      <-- downsized from uint256 slot 2

Slot 2: prizePoolsPacked (was slot 3)
Slot 3: rngWordCurrent (was slot 4)
...all subsequent slots shifted down by 1
```

## Known Stubs

None -- all code is fully wired with no placeholder data.

## Issues Encountered
- Worktree lacked node_modules and forge-std symlinks for forge build; used main repo for compilation verification
- GameOverModule had two identical `currentPrizePool = 0;` lines at different indentation levels; replace_all only matched one due to whitespace differences; second was caught by post-replacement grep and fixed manually

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Storage repack complete, all contracts compile cleanly
- Plan 168-02 (test offset updates) can proceed to update Foundry test hardcoded slot offsets
- Plan 168-03 (forge inspect verification across all inheriting contracts) should confirm layout consistency

## Self-Check: PASSED

- All 5 key files exist on disk
- Commit ed057810 (Task 1) verified in git log
- Commit 622cc1ae (Task 2) verified in git log

---
*Phase: 168-storage-repack*
*Completed: 2026-04-02*
