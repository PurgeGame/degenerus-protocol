---
phase: 207-storage-foundation
plan: 01
subsystem: storage
tags: [type-narrowing, slot-packing, gas-optimization]
dependency_graph:
  requires: []
  provides: [uint32-day-indices, bool-ticketWriteSlot, packed-slots-0-1]
  affects: [all-game-modules-using-uint48-day-indices]
tech_stack:
  added: []
  patterns: [bool-toggle-negation, uint128-pool-packing]
key_files:
  created: []
  modified:
    - contracts/storage/DegenerusGameStorage.sol
    - contracts/libraries/GameTimeLib.sol
decisions:
  - "uint32 for all day-index types (4.2B days = ~11.5M years headroom)"
  - "bool for ticketWriteSlot with negation toggle (cleaner than uint8 XOR)"
  - "uint128 for claimablePool (3.4e20 ETH max, packed with currentPrizePool)"
  - "Slot 0: 30/32 bytes after absorbing ticketWriteSlot + prizePoolFrozen"
  - "Slot 1: 32/32 bytes with two uint128 prize pools (was 18/32 with padding)"
metrics:
  duration: 265s
  completed: "2026-04-10T03:43:31Z"
  tasks_completed: 2
  tasks_total: 2
  files_modified: 2
requirements_completed: [TYPE-01, TYPE-02, TYPE-06, SLOT-01, SLOT-02, SLOT-03]
---

# Phase 207 Plan 01: Storage Foundation - Type Narrowing and Slot Repacking Summary

Narrowed all day-index types from uint48 to uint32, converted ticketWriteSlot from uint8 to bool with negation toggle, and repacked EVM slots 0 and 1 to eliminate 14 bytes of wasted padding in slot 1.

## What Changed

### Task 1: Type Narrowing (f5c86549)

**GameTimeLib.sol:**
- `JACKPOT_RESET_TIME`: uint48 -> uint32 (value 82620 fits fine)
- `currentDayIndex()`: returns uint32 instead of uint48
- `currentDayIndexAt(uint48 ts)`: returns uint32, local `currentDayBoundary` now uint32. Parameter `ts` stays uint48 (it is a timestamp).

**DegenerusGameStorage.sol storage variables:**
- `purchaseStartDay`: uint48 -> uint32
- `dailyIdx`: uint48 -> uint32
- `lastDailyJackpotDay`: uint48 -> uint32

**Mapping key narrowing (12 mappings):**
- `rngWordByDay`, `lootboxRngWordByIndex`, `lootboxDay` (outer + inner value), `lootboxEth`, `lootboxEthBase`, `lootboxBaseLevelPacked`, `lootboxEvScorePacked`, `lootboxBurnie`, `deityBoonDay`, `deityBoonRecipientDay`, `dailyHeroWagers`, `lootboxDistressEth`: all uint48 keys -> uint32

**ticketWriteSlot conversion:**
- Declaration: uint8 -> bool
- `_swapTicketSlot`: `ticketWriteSlot ^= 1` -> `ticketWriteSlot = !ticketWriteSlot`
- `_tqWriteKey`: `ticketWriteSlot != 0 ?` -> `ticketWriteSlot ?`
- `_tqReadKey`: `ticketWriteSlot == 0 ?` -> `!ticketWriteSlot ?`

**Helper return types:**
- `_simulatedDayIndex()`: returns uint32
- `_simulatedDayIndexAt(uint48 ts)`: returns uint32 (param stays uint48)
- `_currentMintDay()`: local `uint48 day` -> `uint32 day`, removed unnecessary cast
- `_isDistressMode()`: locals `uint48 psd` -> `uint32 psd`, `uint48 currentDay` -> `uint32 currentDay`

### Task 2: Slot Repacking (c46aa4b0)

**Slot 0 (30/32 bytes):**
- Moved `ticketWriteSlot` (bool, 1 byte) from slot 1 to slot 0 after `gameOverPossible`
- Moved `prizePoolFrozen` (bool, 1 byte) from slot 1 to slot 0 after `ticketWriteSlot`
- Net result: 4 bytes freed by uint48->uint32 narrowing, 2 bytes added from slot 1 moves = 2 bytes padding

**Slot 1 (32/32 bytes):**
- `currentPrizePool` (uint128, 16 bytes) stays
- `claimablePool` narrowed from uint256 to uint128 and moved here (16 bytes)
- Full slot: zero padding (was 14 bytes wasted)

**Comment block:** Updated to reflect new slot layout with correct byte offsets and types.

## What Did NOT Change (Verified)

- `rngRequestTime` (uint48 timestamp)
- `gameOverTime` (uint48 timestamp)
- `lastVrfProcessedTimestamp` (uint48 timestamp)
- `_DEPLOY_IDLE_TIMEOUT_DAYS` (uint48 constant)
- `lootboxRngIndex` (uint48 -- deferred to Plan 02 SLOT-05)
- `uint48(block.timestamp)` casts
- `_simulatedDayIndexAt` parameter type (uint48 ts)

## Deviations from Plan

None -- plan executed exactly as written.

## Known Stubs

None.

## Commits

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Narrow day-index types, convert ticketWriteSlot to bool | f5c86549 | DegenerusGameStorage.sol, GameTimeLib.sol |
| 2 | Repack EVM slots 0-1, update slot layout comment | c46aa4b0 | DegenerusGameStorage.sol |

## Compilation Note

This will NOT compile because module callers still reference uint48 for day-index types. Phase 208 fixes all callers.

## Self-Check: PASSED
