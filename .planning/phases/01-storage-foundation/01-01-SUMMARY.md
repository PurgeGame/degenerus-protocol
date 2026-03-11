---
phase: 01-storage-foundation
plan: 01
subsystem: database
tags: [solidity, storage-layout, evm-packing, delegatecall, foundry]

# Dependency graph
requires: []
provides:
  - "ticketWriteSlot, ticketsFullyProcessed, prizePoolFrozen fields in EVM Slot 1"
  - "prizePoolsPacked (Slot 3) replacing nextPrizePool"
  - "prizePoolPendingPacked (Slot 16) replacing futurePrizePool"
  - "_getPrizePools/_setPrizePools packed pool accessors"
  - "_getPendingPools/_setPendingPools pending accumulator accessors"
  - "_tqWriteKey/_tqReadKey ticket queue key encoding"
  - "_swapTicketSlot/_swapAndFreeze/_unfreezePool queue swap and freeze primitives"
  - "_legacyGet/SetNextPrizePool/_legacyGet/SetFuturePrizePool compatibility shims"
  - "TICKET_SLOT_BIT constant for double-buffer key encoding"
  - "error E() declaration in storage contract"
affects: [01-02, phase-02, phase-03, phase-04, phase-05]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "uint128 packing for dual prize pools in single uint256 slot"
    - "XOR-based double-buffer toggle (ticketWriteSlot ^= 1)"
    - "Bit-23 key encoding for ticket queue read/write slot separation"
    - "Freeze/unfreeze pattern for prize pool isolation during jackpot phase"

key-files:
  created: []
  modified:
    - "contracts/storage/DegenerusGameStorage.sol"

key-decisions:
  - "prizePoolPendingPacked placed at Slot 16 (futurePrizePool's position) instead of adjacent to prizePoolsPacked, to avoid shifting all subsequent storage slots"
  - "Compatibility shims (_legacyGet/Set*) provide uint256 interface over packed uint128 storage for gradual migration"

patterns-established:
  - "Packed pool access: always use _getPrizePools/_setPrizePools, never read prizePoolsPacked directly"
  - "Key encoding: _tqWriteKey/_tqReadKey derive mapping keys from level + ticketWriteSlot"
  - "Freeze lifecycle: _swapAndFreeze at daily RNG -> accumulate in pending -> _unfreezePool after final payout"

requirements-completed: [STOR-01, STOR-02, STOR-03, STOR-04]

# Metrics
duration: 5min
completed: 2026-03-11
---

# Phase 1 Plan 01: Storage Foundation Summary

**Double-buffer fields, packed prize pools, key encoding, swap/freeze primitives, and legacy shims added to DegenerusGameStorage.sol with zero storage slot shifts**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-11T20:26:48Z
- **Completed:** 2026-03-11T20:31:58Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Three new Slot 1 fields (ticketWriteSlot, ticketsFullyProcessed, prizePoolFrozen) at offsets 24-26 with TICKET_SLOT_BIT constant and error E() declaration
- Replaced nextPrizePool (Slot 3) with prizePoolsPacked and futurePrizePool (Slot 16) with prizePoolPendingPacked -- zero slot shifts verified via forge inspect before/after comparison
- Added all 9 helper functions (4 packed pool, 2 key encoding, 3 swap/freeze) and 4 compatibility shims
- ASCII storage layout diagrams corrected to match actual EVM slot boundaries

## Task Commits

Each task was committed atomically:

1. **Task 1: Add Slot 1 fields, TICKET_SLOT_BIT, error E(), fix ASCII diagrams** - `dca6cb33` (feat) -- pre-existing commit
2. **Task 2: Add packed pool variables, all helper functions, and compatibility shims** - `5a59a785` (feat)

**Plan metadata:** [pending] (docs: complete plan)

## Files Created/Modified
- `contracts/storage/DegenerusGameStorage.sol` - All new storage fields, packed pool helpers, key encoding, swap/freeze/unfreeze, compatibility shims

## Decisions Made
- prizePoolPendingPacked placed at Slot 16 (futurePrizePool's exact position) rather than adjacent to prizePoolsPacked at Slot 4, because adjacency would shift rngWordCurrent (Slot 4), vrfRequestId (Slot 5), and all subsequent slots, corrupting storage for all delegatecall modules
- Compatibility shims provide uint256 interface to ease gradual migration of 96 consumer references in Plan 02

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed duplicate helper function insertion**
- **Found during:** Task 2 (helper function addition)
- **Issue:** Task 1 had already been executed in a prior session, which also partially completed Task 2's helper functions. Inserting the full block again created duplicate function definitions causing compilation failure.
- **Fix:** Removed the duplicate insertion, keeping the original block already present in the file.
- **Files modified:** contracts/storage/DegenerusGameStorage.sol
- **Verification:** forge inspect compiles successfully, all function signatures present exactly once
- **Committed in:** 5a59a785 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Auto-fix necessary due to partial prior execution. No scope creep.

## Issues Encountered
- Task 1 was already fully committed from a prior session (commit dca6cb33). Task 2 variable replacements and some helpers were also partially applied but uncommitted. Resolved by verifying existing state, removing duplicates, and committing only the remaining changes.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Storage primitives are in place for Plan 02 (consumer reference migration)
- Full `forge build` will fail until Plan 02 migrates the 96 references to nextPrizePool/futurePrizePool in 10 consumer files
- All helper functions compile in isolation via `forge inspect`

---
*Phase: 01-storage-foundation*
*Completed: 2026-03-11*

## Self-Check: PASSED
- contracts/storage/DegenerusGameStorage.sol: FOUND
- 01-01-SUMMARY.md: FOUND
- Commit dca6cb33: FOUND
- Commit 5a59a785: FOUND
