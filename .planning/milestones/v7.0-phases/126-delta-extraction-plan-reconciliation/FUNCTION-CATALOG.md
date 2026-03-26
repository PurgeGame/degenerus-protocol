# Per-Contract Function Catalog: v5.0 to HEAD

**Purpose:** Taskmaster coverage target for Phases 127 and 128.
**Method:** Every function touched in `git diff v5.0..HEAD` is classified by change type and originating phase.

---

## 1. DegenerusCharity.sol

**Entire contract is new -- full adversarial review in Phase 127.**

538 new lines, Phase 123. New contract deployed at nonce N+23 with soulbound GNRUS token, proportional burn redemption, and sDGNRS governance.

| Function | Visibility | Change Type | Phase | Review Flag |
|----------|-----------|-------------|-------|-------------|
| `totalSupply()` | external | new | 123 | NEEDS_ADVERSARIAL_REVIEW |
| `balanceOf(address)` | external | new | 123 | NEEDS_ADVERSARIAL_REVIEW |
| `claimWinnings(address)` | external | new | 123 | NEEDS_ADVERSARIAL_REVIEW |
| `claimableWinningsOf(address)` | external | new | 123 | NEEDS_ADVERSARIAL_REVIEW |
| `gameOver()` | external | new | 123 | NEEDS_ADVERSARIAL_REVIEW |
| `isVaultOwner(address)` | external | new | 123 | NEEDS_ADVERSARIAL_REVIEW |
| `transfer(address, uint256)` | external | new | 123 | NEEDS_ADVERSARIAL_REVIEW |
| `transferFrom(address, address, uint256)` | external | new | 123 | NEEDS_ADVERSARIAL_REVIEW |
| `approve(address, uint256)` | external | new | 123 | NEEDS_ADVERSARIAL_REVIEW |
| `burn(uint256)` | external | new | 123 | NEEDS_ADVERSARIAL_REVIEW |
| `handleGameOver()` | external | new | 123 | NEEDS_ADVERSARIAL_REVIEW |
| `propose(address)` | external | new | 123 | NEEDS_ADVERSARIAL_REVIEW |
| `vote(uint48, bool)` | external | new | 123 | NEEDS_ADVERSARIAL_REVIEW |
| `resolveLevel(uint24)` | external | new | 123 | NEEDS_ADVERSARIAL_REVIEW |
| `getProposal(uint48)` | external | new | 123 | NEEDS_ADVERSARIAL_REVIEW |
| `getLevelProposals(uint24)` | external | new | 123 | NEEDS_ADVERSARIAL_REVIEW |
| `_mint(address, uint256)` | private | new | 123 | NEEDS_ADVERSARIAL_REVIEW |

## 2. DegenerusGameDegeneretteModule.sol

296 lines changed (208 insertions, 88 deletions). Phase 122: degenerette freeze fix -- allows ETH resolution during prizePoolFrozen by routing through pending pool side-channel. Many functions have both logic changes and formatting/line-wrapping adjustments.

| Function | Visibility | Change Type | Phase | Review Flag |
|----------|-----------|-------------|-------|-------------|
| `_resolvePlayer(address)` | private | modified | 122 | NEEDS_ADVERSARIAL_REVIEW |
| `placeFullTicketBets(...)` | external | modified | 122 | NEEDS_ADVERSARIAL_REVIEW |
| `resolveBets(address, uint64[])` | external | modified | 122 | NEEDS_ADVERSARIAL_REVIEW |
| `_placeFullTicketBets(...)` | private | modified | 122 | NEEDS_ADVERSARIAL_REVIEW |
| `_placeFullTicketBetsCore(...)` | private | modified | 122 | NEEDS_ADVERSARIAL_REVIEW |
| `_collectBetFunds(...)` | private | modified | 122 | NEEDS_ADVERSARIAL_REVIEW |
| `_resolveBet(address, uint64)` | private | modified | 122 | NEEDS_ADVERSARIAL_REVIEW |
| `_resolveFullTicketBet(address, uint64, uint256)` | private | modified | 122 | NEEDS_ADVERSARIAL_REVIEW |
| `_distributePayout(address, uint8, uint256, uint256)` | private | modified | 122 | NEEDS_ADVERSARIAL_REVIEW |
| `_maybeAwardConsolation(address, uint8, uint128)` | private | modified | 122 | NEEDS_ADVERSARIAL_REVIEW |
| `_packFullTicketBet(...)` | private | modified | 122 | NEEDS_ADVERSARIAL_REVIEW |
| `_countMatches(...)` | private | modified | 122 | NEEDS_ADVERSARIAL_REVIEW |
| `_fullTicketPayout(...)` | private | modified | 122 | NEEDS_ADVERSARIAL_REVIEW |
| `_applyHeroMultiplier(...)` | private | modified | 122 | NEEDS_ADVERSARIAL_REVIEW |
| `_roiBpsFromScore(...)` | private | modified | 122 | NEEDS_ADVERSARIAL_REVIEW |
| `_wwxrpHighValueRoi(uint256)` | private | modified | 122 | NEEDS_ADVERSARIAL_REVIEW |
| `_addClaimableEth(address, uint256)` | private | modified | 122 | NEEDS_ADVERSARIAL_REVIEW |
| `_awardDegeneretteDgnrs(address, uint256, uint8)` | private | modified | 122 | NEEDS_ADVERSARIAL_REVIEW |

## 3. DegenerusAffiliate.sol

76 lines changed (58 insertions, 18 deletions). **Unplanned** -- adds default referral codes so every address is an affiliate without on-chain registration.

| Function | Visibility | Change Type | Phase | Review Flag |
|----------|-----------|-------------|-------|-------------|
| `defaultCode(address)` | external | new | unplanned | NEEDS_ADVERSARIAL_REVIEW |
| `_resolveCodeOwner(bytes32)` | private | new | unplanned | NEEDS_ADVERSARIAL_REVIEW |
| `createAffiliateCode(bytes32, uint8)` | external | modified | unplanned | NEEDS_ADVERSARIAL_REVIEW |
| `referPlayer(bytes32)` | external | modified | unplanned | NEEDS_ADVERSARIAL_REVIEW |
| `payAffiliate(...)` | external | modified | unplanned | NEEDS_ADVERSARIAL_REVIEW |
| `_setReferralCode(address, bytes32)` | private | modified | unplanned | NEEDS_ADVERSARIAL_REVIEW |
| `_referrerAddress(address)` | private | modified | unplanned | NEEDS_ADVERSARIAL_REVIEW |
| `_createAffiliateCode(...)` | private | modified | unplanned | NEEDS_ADVERSARIAL_REVIEW |

## 4. DegenerusGameGameOverModule.sol

74 lines changed (37 insertions, 37 deletions). Phase 124: charity game-over hooks. Fund split changed from 50/50 (DGNRS/vault) to 33/33/34 (DGNRS/vault/GNRUS). New `_sendStethFirst` helper extracted.

| Function | Visibility | Change Type | Phase | Review Flag |
|----------|-----------|-------------|-------|-------------|
| `_sendStethFirst(address, uint256, uint256)` | private | new | 124 | NEEDS_ADVERSARIAL_REVIEW |
| `handleGameOverDrain()` | external | modified | 124 | NEEDS_ADVERSARIAL_REVIEW |
| `handleFinalSweep()` | external | modified | 124 | NEEDS_ADVERSARIAL_REVIEW |
| `_sendToVault(uint256, uint256)` | private | modified | 124 | NEEDS_ADVERSARIAL_REVIEW |

## 5. DegenerusStonk.sol

54 insertions, 0 deletions. Phases 123/124: charity integration -- 1-year post-gameover sweep and gameOverTimestamp getter.

| Function | Visibility | Change Type | Phase | Review Flag |
|----------|-----------|-------------|-------|-------------|
| `yearSweep()` | external | new | 123/124 | NEEDS_ADVERSARIAL_REVIEW |
| `gameOverTimestamp()` | external | new | 124 | NEEDS_ADVERSARIAL_REVIEW |

Note: `gameOverTimestamp()` is added to the `IDegenerusGame` interface used by DegenerusStonk.

## 6. DegenerusGameAdvanceModule.sol

35 lines changed (23 insertions, 12 deletions). Phases 121/124: storage/gas fixes (advanceBounty rewrite, lastLootboxRngWord removal) + charity level-transition hook.

| Function | Visibility | Change Type | Phase | Review Flag |
|----------|-----------|-------------|-------|-------------|
| `advanceGame()` | external | modified | 121/124 | NEEDS_ADVERSARIAL_REVIEW |
| `_finalizeLootboxRng(...)` | private | modified | 121 | NEEDS_ADVERSARIAL_REVIEW |
| `_finalizeRngRequest(...)` | private | modified | 124 | NEEDS_ADVERSARIAL_REVIEW |
| `_backfillOrphanedLootboxIndices(...)` | private | modified | 121 | NEEDS_ADVERSARIAL_REVIEW |

Changes in `advanceGame()`:
- Removed upfront `advanceBounty` computation, moved to payout-time (FIX-07, Phase 121)
- Removed `lastLootboxRngWord = word` assignment (FIX-01, Phase 121)
- Added `charityResolve.resolveLevel(lvl - 1)` call at level transition (Phase 124)
- Bounty now uses inline `(ADVANCE_BOUNTY_ETH * PRICE_COIN_UNIT * bountyMultiplier) / price`

## 7. DegenerusGameJackpotModule.sol

30 lines changed (18 insertions, 12 deletions). Phase 121: storage/gas fixes (double SLOAD caching, yield surplus charity share, lastLootboxRngWord replacement).

| Function | Visibility | Change Type | Phase | Review Flag |
|----------|-----------|-------------|-------|-------------|
| `payDailyJackpot(...)` | external | modified | 121 | NEEDS_ADVERSARIAL_REVIEW |
| `_runEarlyBirdLootboxJackpot(...)` | private | modified | 121 | NEEDS_ADVERSARIAL_REVIEW |
| `_distributeYieldSurplus(uint256)` | private | modified | 121/124 | NEEDS_ADVERSARIAL_REVIEW |
| `processTicketBatch(...)` | external | modified | 121 | NEEDS_ADVERSARIAL_REVIEW |

Changes:
- `payDailyJackpot`: cache `_getFuturePrizePool()` to avoid double SLOAD (FIX-02)
- `_runEarlyBirdLootboxJackpot`: cache `_getFuturePrizePool()` to avoid double SLOAD (FIX-02)
- `_distributeYieldSurplus`: 46% accumulator split into 23% charity + 23% accumulator (Phase 124)
- `processTicketBatch`: replaced `lastLootboxRngWord` with `lootboxRngWordByIndex[lootboxRngIndex - 1]` (FIX-01)

## 8. DegenerusGameLootboxModule.sol

29 lines changed (12 insertions, 17 deletions). Phase 121: deity boon downgrade prevention (FIX-06).

| Function | Visibility | Change Type | Phase | Review Flag |
|----------|-----------|-------------|-------|-------------|
| `_boonCategory(...)` | private | modified | 121 | NEEDS_ADVERSARIAL_REVIEW |
| `_applyBoon(...)` | private | modified | 121 | NEEDS_ADVERSARIAL_REVIEW |

Changes in `_applyBoon`:
- Removed `isDeity ||` override from 8 boon type branches (coinflip, lootbox, purchase, decimator, whale, activity, deity pass, lazy pass)
- Both deity and lootbox boons now use uniform upgrade semantics (only if higher tier/amount)
- NatSpec updated to reflect unified behavior

## 9. DegenerusGame.sol

13 lines changed (7 insertions, 6 deletions). Phase 124: game router changes for charity integration.

| Function | Visibility | Change Type | Phase | Review Flag |
|----------|-----------|-------------|-------|-------------|
| `gameOverTimestamp()` | external | new | 124 | NEEDS_ADVERSARIAL_REVIEW |
| `claimWinningsStethFirst()` | external | modified | 124 | NEEDS_ADVERSARIAL_REVIEW |

Changes:
- `gameOverTimestamp()`: new view function exposing `gameOverTime` storage variable
- `claimWinningsStethFirst()`: restricted from VAULT+SDGNRS to VAULT-only (SDGNRS no longer needs stETH-first claims after charity integration)

## 10. DegenerusGameEndgameModule.sol

5 lines changed (3 insertions, 2 deletions). Phase 121: event emission fix (FIX-03).

| Function | Visibility | Change Type | Phase | Review Flag |
|----------|-----------|-------------|-------|-------------|
| `runRewardJackpots(...)` | external | modified | 121 | NEEDS_ADVERSARIAL_REVIEW |

Changes:
- `rebuyDelta` variable hoisted to emit post-reconciliation value in `RewardJackpotsSettled` event
- Before: event emitted `futurePoolLocal` (missing rebuy delta)
- After: event emits `futurePoolLocal + rebuyDelta` (correct post-reconciliation value)

## 11. DegenerusGameStorage.sol

5 deletions, 0 insertions. Phase 121: deleted redundant storage variable (FIX-01).

| Function | Visibility | Change Type | Phase | Review Flag |
|----------|-----------|-------------|-------|-------------|
| `lastLootboxRngWord` (variable) | internal | deleted | 121 | NEEDS_ADVERSARIAL_REVIEW |

Note: This is a storage variable, not a function. Deleted because all consumers now read `lootboxRngWordByIndex[lootboxRngIndex - 1]` directly, eliminating redundant storage.

## 12. BitPackingLib.sol

2 lines changed (1 insertion, 1 deletion). Phase 121: NatSpec correction (FIX-05).

| Function | Visibility | Change Type | Phase | Review Flag |
|----------|-----------|-------------|-------|-------------|
| `WHALE_BUNDLE_TYPE_SHIFT` (constant) | internal | natspec-only | 121 | |

Change: NatSpec comment corrected from "bits 152-154" to "bits 152-153". No logic change.

---

## Summary

| Category | Count |
|----------|-------|
| New functions (Phase 123 Charity) | 17 |
| New functions (Phase 124 integration) | 3 |
| New functions (unplanned affiliate) | 2 |
| Modified functions (Phase 121 storage/gas) | 10 |
| Modified functions (Phase 122 freeze fix) | 18 |
| Modified functions (Phase 124 integration) | 7 |
| Modified functions (unplanned affiliate) | 6 |
| Deleted variables (Phase 121) | 1 |
| NatSpec-only changes (Phase 121) | 1 |
| **Total entries** | **65** |
| **Total requiring adversarial review** | **64** |

### By Originating Phase

| Phase | Functions | Nature |
|-------|-----------|--------|
| 121 (storage/gas fixes) | 11 | Modified functions + 1 deleted variable + 1 natspec |
| 122 (degenerette freeze fix) | 18 | Modified functions (ETH resolution during freeze) |
| 123 (DegenerusCharity) | 17 | All new (entire contract) |
| 124 (game integration) | 10 | New + modified (charity hooks wired into game modules) |
| unplanned (affiliate) | 8 | New + modified (default referral codes) |

### Audit Scope Priority

1. **DegenerusCharity.sol** (17 new functions) -- entire new contract, highest priority
2. **DegenerusAffiliate.sol** (8 functions) -- unplanned change, no prior review
3. **DegenerusGameDegeneretteModule.sol** (18 functions) -- significant freeze fix, ETH flow change
4. **DegenerusGameGameOverModule.sol** (4 functions) -- fund split ratio changed, new helper
5. **DegenerusGameAdvanceModule.sol** (4 functions) -- multiple change sources (121 + 124)
6. **DegenerusGameJackpotModule.sol** (4 functions) -- yield surplus redistribution
7. **DegenerusStonk.sol** (2 functions) -- new yearSweep, new view
8. **DegenerusGame.sol** (2 functions) -- access control change + new view
9. **DegenerusGameLootboxModule.sol** (2 functions) -- boon downgrade prevention
10. **DegenerusGameEndgameModule.sol** (1 function) -- event emission fix
11. **DegenerusGameStorage.sol** (1 variable) -- deletion only
12. **BitPackingLib.sol** (1 constant) -- natspec-only, no review needed
