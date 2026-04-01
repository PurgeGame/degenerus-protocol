---
phase: 146
plan: 04
subsystem: test-suite
tags: [test-fix, abi-cleanup, phase-146]
dependency_graph:
  requires: [146-01, 146-02, 146-03]
  provides: [green-test-suite]
  affects: [test/]
tech_stack:
  patterns: [event-based-assertions, hardcoded-index-for-removed-views]
key_files:
  modified:
    - test/access/AccessControl.test.js
    - test/edge/RngStall.test.js
    - test/integration/GameLifecycle.test.js
    - test/unit/BurnieCoin.test.js
    - test/unit/DegenerusAdmin.test.js
    - test/unit/DegenerusGame.test.js
    - test/unit/DistressLootbox.test.js
    - test/unit/EthInvariant.test.js
    - test/unit/GovernanceGating.test.js
    - test/unit/SecurityEconHardening.test.js
decisions:
  - Used event-based assertions where view functions were removed (autoRebuyEnabledFor, decimatorAutoRebuyEnabledFor)
  - Replaced deityPassPurchasedCountFor with deityPassCountFor (both track pass ownership; purchased variant was view-only sugar)
  - Used hardcoded lootboxRngIndex=1n in DistressLootbox tests since presale starts at index 1
  - Replaced rewardPoolView with futurePrizePoolView (rewardPoolView was a duplicate alias)
metrics:
  duration: 12min
  completed: "2026-03-30T05:03:00Z"
  tasks: 1
  files: 10
---

# Phase 146 Plan 04: Fix Test Suite for ABI Cleanup Summary

Fixed all 62 failing Hardhat tests caused by Phase 146 ABI cleanup. Test suite now passes with 0 failures (1319 passing).

## One-liner

Removed/rewrote 62 failing tests referencing deleted BurnieCoin forwarding wrappers, Admin proxy functions, and Game unused views.

## Changes by Category

### 1. Tests for Removed BurnieCoin Functions (deleted)
- `creditFlip`, `creditFlipBatch`, `creditCoin` -- forwarding wrappers removed
- `claimableCoin`, `previewClaimCoinflips`, `coinflipAmount`, `coinflipAutoRebuyInfo` -- forwarding views removed
- `mintForCoinflip` -- merged into `mintForGame`

### 2. Tests for Removed Admin Functions (deleted/rewritten)
- `stakeGameEthToStEth` -- now `game.adminStakeEthForStEth` with vault-owner gating
- `setLootboxRngThreshold` -- now `game.setLootboxRngThreshold` with vault-owner gating

### 3. Tests for Removed Game Views (deleted)
- `rngStalledForThreeDays`, `lootboxRngIndexView`, `lootboxRngThresholdView`, `lootboxRngWord`
- `ethMintLastLevel`, `ethMintLevelCount`, `ethMintStreakCount`
- `hasActiveLazyPass`, `autoRebuyEnabledFor`, `decimatorAutoRebuyEnabledFor`
- `deityPassPurchasedCountFor`

### 4. Tests Rewritten for New Access Patterns
- GovernanceGating: 7 tests rewritten to call `game.setLootboxRngThreshold` as vault owner instead of `admin.setLootboxRngThreshold`
- EthInvariant: `admin.stakeGameEthToStEth` rewritten to `game.adminStakeEthForStEth`
- SecurityEconHardening: `rewardPoolView` replaced with `futurePrizePoolView`; `deityPassPurchasedCountFor` replaced with `deityPassCountFor`
- DegenerusGame: `autoRebuyEnabledFor`/`decimatorAutoRebuyEnabledFor` assertions replaced with event-based verification

## Test Count Reconciliation

| Metric | Before | After |
|--------|--------|-------|
| Passing | 1298 | 1319 |
| Failing | 62 | 0 |
| Total | 1360 | 1319 |
| Tests removed | - | 41 |
| Tests rewritten | - | 21 |

41 tests deleted (for permanently removed functions). 21 of the 62 failures were tests that could be rewritten to use the new APIs.

## Deviations from Plan

None -- plan executed exactly as written.

## Commits

| Hash | Description |
|------|-------------|
| edeb1cef | fix(146-04): update test suite for Phase 146 ABI cleanup -- 0 failures |

## Known Stubs

None.
