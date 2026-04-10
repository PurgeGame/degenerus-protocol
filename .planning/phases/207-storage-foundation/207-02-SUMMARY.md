---
phase: 207-storage-foundation
plan: 02
subsystem: storage
tags: [slot-packing, gas-optimization, packed-uint256]
dependency_graph:
  requires: [207-01]
  provides: [lootboxRngPacked, gameOverStatePacked, dailyJackpotTraitsPacked, presaleStatePacked]
  affects: [all-modules-referencing-packed-variables]
tech_stack:
  added: []
  patterns: [shift-mask-packing, scaled-storage, read-write-helpers]
key_files:
  created: []
  modified:
    - contracts/storage/DegenerusGameStorage.sol
decisions:
  - "ETH/LINK scaled by 1e15 (0.001 resolution) for lootboxRng packed fields"
  - "BURNIE scaled by 1e18 (1 token resolution) for lootboxRng packed fields"
  - "presaleStatePacked uses uint128 for mint ETH (200 ETH cap, enormous headroom)"
  - "gameOverStatePacked uses only 64/256 bits (compact, room for future fields)"
  - "dailyJackpotTraitsPacked uses 88/256 bits (trait+level+day)"
metrics:
  duration: 117s
  completed: "2026-04-10T03:47:30Z"
  tasks_completed: 2
  tasks_total: 2
  files_modified: 1
requirements_completed: [SLOT-05, SLOT-06, SLOT-07, SLOT-08]
---

# Phase 207 Plan 02: Packed uint256 Variables Summary

Four groups of related storage variables packed into single uint256 slots with shift/mask read/write helpers, reducing 14 separate slots to 4.

## What Changed

### Task 1: Pack lootboxRng variables (f2bef1b0)

Replaced 6 separate lootboxRng variables with `lootboxRngPacked` (232/256 bits used, 24 bits free):

| Field | Bits | Type | Scaling | Range |
|-------|------|------|---------|-------|
| lootboxRngIndex | 0:47 | uint48 | none | 281T indices |
| lootboxRngPendingEth | 48:111 | uint64 | /1e15 | ~18,446 ETH |
| lootboxRngThreshold | 112:175 | uint64 | /1e15 | ~18,446 ETH |
| lootboxRngMinLinkBalance | 176:183 | uint8 | whole LINK | 255 LINK |
| lootboxRngPendingBurnie | 184:223 | uint40 | /1e18 | ~1.1T BURNIE |
| midDayTicketRngPending | 224:231 | uint8 | bool | 0/1 |

Default initializer encodes: index=1, threshold=1000 (1 ETH / 1e15), minLink=14000 (14 ETH / 1e15).

Added helpers:
- `_lrRead` / `_lrWrite` for field access
- `_packEthToMilliEth` / `_unpackMilliEthToWei` (0.001 ETH resolution)
- `_packBurnieToWhole` / `_unpackWholeBurnieToWei` (1 BURNIE resolution)
- 12 shift/mask constants (LR_*)

### Task 2: Pack gameover, daily-jackpot-traits, presale (c72b1d5e)

**gameOverStatePacked** (64/256 bits):
- gameOverTime (uint48, bits 0:47) + gameOverFinalJackpotPaid (uint8, bits 48:55) + finalSwept (uint8, bits 56:63)
- Helpers: `_goRead` / `_goWrite`, GO_* constants

**dailyJackpotTraitsPacked** (88/256 bits):
- lastDailyJackpotWinningTraits (uint32, bits 0:31) + lastDailyJackpotLevel (uint24, bits 32:55) + lastDailyJackpotDay (uint32, bits 56:87)
- Helpers: `_djtRead` / `_djtWrite`, DJT_* constants

**presaleStatePacked** (136/256 bits):
- lootboxPresaleActive (uint8, bits 0:7) + lootboxPresaleMintEth (uint128, bits 8:135)
- Initialized with active=1
- Helpers: `_psRead` / `_psWrite`, PS_* constants

All 8 individual variable declarations deleted.

## What Did NOT Change (Verified)

- `lootboxEth` mapping (separate concern, stays as-is)
- Day-index mapping keys (uint32 from Plan 01); lootbox-index-keyed mapping keys remain uint48 (keyed by lootboxRngIndex)
- Slot 0 and Slot 1 layouts (from Plan 01)
- All other storage variables

## Deviations from Plan

None -- plan executed exactly as written.

## Known Stubs

None.

## Orphaned Constants

`LR_MIN_LINK_SHIFT` (176) and `LR_MIN_LINK_MASK` (0xFF) are defined in DegenerusGameStorage.sol but never consumed by any runtime read/write path. The `lootboxRngMinLinkBalance` field occupies bits 176:183 of `lootboxRngPacked` and is initialized to 14 (whole LINK) in the default initializer, but no module reads or writes this field at runtime. The constants are retained for off-chain tooling that may need to decode the packed slot.

## Compilation Note

This will NOT compile because module callers still reference old variable names (e.g., `lootboxRngIndex`, `gameOverTime`, `lootboxPresaleActive`). Phase 208 fixes all callers to use the packed helpers.

## Commits

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Pack 6 lootboxRng variables into single uint256 | f2bef1b0 | DegenerusGameStorage.sol |
| 2 | Pack gameover, daily-jackpot-traits, presale into uint256 slots | c72b1d5e | DegenerusGameStorage.sol |

## Self-Check: PASSED
