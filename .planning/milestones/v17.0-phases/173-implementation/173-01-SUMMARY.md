---
phase: 173-implementation
plan: 01
status: complete
started: 2026-04-03
completed: 2026-04-03
---

# Plan 173-01 Summary

## What Was Built

Added affiliate bonus cache constants to BitPackingLib and changed the affiliate bonus rate from 1 point per 1 ETH to 1 point per 0.5 ETH.

## Key Changes

### BitPackingLib.sol
- Added `MASK_6 = (uint256(1) << 6) - 1` (6-bit mask for bonus points)
- Added `AFFILIATE_BONUS_LEVEL_SHIFT = 185` (bits 185-208, 24 bits)
- Added `AFFILIATE_BONUS_POINTS_SHIFT = 209` (bits 209-214, 6 bits)
- Updated layout comment: `[185-227] (unused)` → granular breakdown

### DegenerusAffiliate.sol
- `affiliateBonusPointsBest`: `sum / ethUnit` → `sum / (ethUnit / 2)`
- NatSpec updated to reflect "per 0.5 ETH"
- `AFFILIATE_BONUS_MAX = 50` unchanged

## Commits

- `f730bc0c` — feat(v17.0): add affiliate bonus cache constants + 0.5 ETH rate change

## Requirements

- IMPL-01: ✓ BitPackingLib declares cache field constants
- IMPL-04: ✓ Affiliate bonus awards 1 point per 0.5 ETH

## Self-Check: PASSED
