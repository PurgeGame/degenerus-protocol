---
phase: quick
plan: 260327-q8y
subsystem: game-boons
tags: [test, boon, multi-category, deity-boon]
dependency_graph:
  requires: []
  provides: [multi-boon-coexistence-tests]
  affects: [test/edge/MultiBoon.test.js]
tech_stack:
  added: []
  patterns: [deity-boon-scanning-loop, DeityBoonViewer-for-slot-lookup]
key_files:
  created:
    - test/edge/MultiBoon.test.js
  modified: []
decisions:
  - Used settleRngDay pattern (not lockRngWithFulfilledWord) for deity boon issuance -- simpler and matches issueLazyBoonForRecipient in WhaleBundle.test.js
  - Tested cross-day deity boon issuance instead of same-day dual issuance (deityBoonRecipientDay limits one deity boon per recipient per day)
  - Used lootboxModule ABI for DeityBoonIssued event decoding (emitted via delegatecall from game proxy)
metrics:
  duration: 6min
  completed: 2026-03-28T00:07:00Z
  tasks: 1
  files: 1
---

# Quick Task 260327-q8y: Multi-Category Boon Coexistence Tests Summary

Test coverage for commit 004a9065 which removed the single-category exclusivity gate from _rollLootboxBoons, allowing players to hold boons in multiple categories simultaneously.

## What Was Done

Created `test/edge/MultiBoon.test.js` (372 lines) with 5 tests covering:

1. **Cross-category coexistence (coinflip + purchase)** -- Issues a coinflip deity boon then a purchase deity boon to the same player on consecutive days. Both _applyBoon calls succeed, writing to independent bit fields in boonPacked.slot0.

2. **Cross-slot coexistence (slot0 + slot1)** -- Issues a coinflip boon (slot0) and an activity boon (slot1) to the same player. Proves completely separate storage slots coexist.

3. **Upgrade semantics** -- Issues two coinflip boons on different days. The second _applyBoon overwrites the tier field if higher, preserving upgrade-within-category behavior.

4. **Lootbox resolution with existing deity boon** -- Issues a deity boon then performs whale bundle purchases (which trigger _rollLootboxBoons). Before the exclusivity removal, a cross-category lootbox boon would have been silently dropped. The test proves purchases succeed without the old activeCategory check.

5. **Event verification** -- Scans DeityBoonIssued events across multiple days and confirms boons from 2+ distinct categories are applied to the same player.

## Key Testing Constraints

- **deityBoonRecipientDay**: A recipient can receive at most one deity boon per day regardless of which deity issues it. Tests use consecutive days for multi-category issuance.
- **Deity boon expiry**: Deity boons expire on day change (deityDay != currentDay clears them on consume). The raw boonPacked storage still holds both categories' fields between days -- the test verifies the write path, not consume-time liveness.
- **Consume function access control**: consumeCoinflipBoon, consumePurchaseBoost, consumeDecimatorBoost are restricted to specific caller contracts (COIN, COINFLIP, self-call). Tests verify coexistence via successful _applyBoon writes and event emission rather than direct consume calls.

## Deviations from Plan

None -- plan executed as written. The plan anticipated the deityBoonRecipientDay constraint and suggested same-day issuance from two deities, but this was not needed since the settleRngDay loop naturally advances to different days.

## Known Stubs

None.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | e56be217 | Multi-category boon coexistence tests |

## Self-Check: PASSED

- test/edge/MultiBoon.test.js: FOUND (372 lines)
- Commit e56be217: FOUND
