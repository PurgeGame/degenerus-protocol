# Phase 145: Candidate Review Decisions

**Reviewed:** 2026-03-30
**Total candidates:** 60+ scanned, 25 approved for removal

## Approved Removals

### Forwarding Wrappers (9)

| # | Contract | Function | Fix Required |
|---|----------|----------|--------------|
| 1 | BurnieCoin | `creditFlip(address,uint256)` | Add AFFILIATE+ADMIN to BurnieCoinflip.onlyFlipCreditors, rewire all callers to call BurnieCoinflip directly |
| 2 | BurnieCoin | `creditFlipBatch(address[3],uint256[3])` | Same as #1 |
| 3 | BurnieCoin | `creditLinkReward(address,uint256)` | Add ADMIN to BurnieCoinflip creditors, DegenerusAdmin calls BurnieCoinflip.creditFlip directly, remove duplicate LinkCreditRecorded event from BurnieCoin |
| 4 | BurnieCoin | `previewClaimCoinflips(address)` | Callers use BurnieCoinflip.previewClaimCoinflips directly |
| 5 | BurnieCoin | `coinflipAmount(address)` | Callers use BurnieCoinflip.coinflipAmount directly |
| 6 | BurnieCoin | `claimableCoin()` | Remove; callers use BurnieCoinflip.previewClaimCoinflips(player) |
| 7 | BurnieCoin | `coinflipAutoRebuyInfo(address)` | Remove; callers use BurnieCoinflip.coinflipAutoRebuyInfo (full return) |
| 8 | DegenerusAdmin | `stakeGameEthToStEth(uint256)` | Game.adminStakeEthForStEth checks vault owner directly |
| 9 | DegenerusAdmin | `setLootboxRngThreshold(uint256)` | Game.setLootboxRngThreshold checks vault owner directly |

### Unused Views (14 + 2 duplicates = 16)

| # | Contract | Function | Reason |
|---|----------|----------|--------|
| 10 | DegenerusGame | `futurePrizePoolTotalView()` | Duplicate of futurePrizePoolView |
| 11 | DegenerusGame | `rewardPoolView()` | Duplicate of futurePrizePoolView, confusing name |
| 12 | DegenerusGame | `lastRngWord()` | Dead; UI doesn't need it |
| 13 | DegenerusGame | `rngStalledForThreeDays()` | Dead; zero callers, governance uses lastVrfProcessed |
| 14 | DegenerusGame | `hasActiveLazyPass(address)` | UI doesn't need it |
| 15 | DegenerusGame | `autoRebuyEnabledFor(address)` | UI doesn't need it |
| 16 | DegenerusGame | `decimatorAutoRebuyEnabledFor(address)` | UI doesn't need it |
| 17 | DegenerusGame | `ethMintLastLevel(address)` | Redundant with ethMintStats |
| 18 | DegenerusGame | `ethMintLevelCount(address)` | Redundant with ethMintStats |
| 19 | DegenerusGame | `ethMintStreakCount(address)` | Redundant with ethMintStats |
| 20 | DegenerusGame | `deityPassPurchasedCountFor(address)` | UI doesn't need it |
| 21 | DegenerusGame | `deityPassTotalIssuedCount()` | UI doesn't need it |
| 22 | DegenerusGame | `lootboxRngIndexView()` | UI doesn't need it |
| 23 | DegenerusGame | `lootboxRngWord(uint48)` | UI doesn't need it |
| 24 | DegenerusGame | `lootboxRngThresholdView()` | UI doesn't need it |
| 25 | DegenerusGame | `lootboxRngMinLinkBalanceView()` | UI doesn't need it |

## Explicitly Kept

### Forwarding Wrappers Kept
- sDGNRS.gameAdvance() — reward routing, sDGNRS receives advance bounty
- sDGNRS.gameClaimWhalePass() — reward routing for sDGNRS
- DegenerusStonk.previewBurn(uint256) — convenience wrapper

### Views Kept (UI needs)
- DegenerusGame: futurePrizePoolView, nextPrizePoolView, currentPrizePoolView, claimablePoolView, prizePoolTargetView, yieldPoolView, yieldAccumulatorView
- DegenerusGame: isRngFulfilled
- DegenerusGame: getWinnings, afKingActivatedLevelFor, autoRebuyTakeProfitFor, ethMintStats, whalePassClaimAmount
- DegenerusGame: jackpotCompressionTier, jackpotPhase, isFinalSwept
- DegenerusGame: lootboxStatus, degeneretteBetInfo, ticketsOwedView, decClaimable
- BurnieCoin: totalSupply, supplyIncUncirculated
- DegenerusAffiliate: defaultCode
- DegenerusQuests: getActiveQuests, getPlayerQuestView
- GNRUS: getProposal, getLevelProposals
- DegenerusAdmin: canExecute, canExecuteFeedSwap
- sDGNRS: burnieReserve
- wXRP: supplyIncUncirculated
- DegenerusDeityPass: renderColors

## Key Implementation Notes

- BurnieCoinflip.onlyFlipCreditors must add AFFILIATE and ADMIN addresses
- Game.adminStakeEthForStEth and Game.setLootboxRngThreshold need vault-owner access control check (replacing Admin middleman)
- Access control between own contracts is not a security concern — all contracts are owned by the same deployer
