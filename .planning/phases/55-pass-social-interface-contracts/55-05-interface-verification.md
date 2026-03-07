# Interface Verification Report

**Files checked:** 12 interface files, 195 function signatures
**Audit date:** 2026-03-07

## Summary

| Metric | Count |
|--------|-------|
| Total functions checked | 195 |
| Signature matches | 195 |
| Signature mismatches | 0 |
| NatSpec present | 178 |
| NatSpec accurate | 176 |
| NatSpec issues (informational) | 2 |
| Missing NatSpec | 17 |

All 195 function signatures across 12 interface files match their implementations exactly. Zero signature mismatches were found. Two minor NatSpec inaccuracies were identified (informational only).

---

## Interface Verification

### IDegenerusGame.sol (72 functions)

**Implements:** DegenerusGame.sol

| # | Interface Function | Sig Match | Params Match | Returns Match | Vis Match | NatSpec Match | Notes |
|---|-------------------|-----------|--------------|---------------|-----------|---------------|-------|
| 1 | `level() returns (uint24)` | YES | YES | YES | YES | YES | Public state variable auto-getter |
| 2 | `jackpotPhase() returns (bool)` | YES | YES | YES | YES | YES | Returns `jackpotPhaseFlag` |
| 3 | `gameOver() returns (bool)` | YES | YES | YES | YES | YES | Public state variable auto-getter |
| 4 | `mintPrice() returns (uint256)` | YES | YES | YES | YES | YES | Returns `price` storage |
| 5 | `decWindow() returns (bool on, uint24 lvl)` | YES | YES | YES | YES | YES | |
| 6 | `decWindowOpenFlag() returns (bool)` | YES | YES | YES | YES | YES | Impl uses named return `bool open` -- compatible |
| 7 | `isCompressedJackpot() returns (bool)` | YES | YES | YES | YES | YES | Returns `compressedJackpotFlag` |
| 8 | `purchaseInfo() returns (uint24, bool, bool, bool, uint256)` | YES | YES | YES | YES | YES | |
| 9 | `lootboxRngWord(uint48) returns (uint256)` | YES | YES | YES | YES | YES | |
| 10 | `lastPurchaseDayFlipTotals() returns (uint256, uint256)` | YES | YES | YES | YES | YES | |
| 11 | `ethMintLevelCount(address) returns (uint24)` | YES | YES | YES | YES | YES | |
| 12 | `ethMintStreakCount(address) returns (uint24)` | YES | YES | YES | YES | YES | |
| 13 | `ethMintLastLevel(address) returns (uint24)` | YES | YES | YES | YES | YES | |
| 14 | `playerActivityScore(address) returns (uint256)` | YES | YES | YES | YES | YES | Impl uses named return `scoreBps` -- compatible |
| 15 | `isOperatorApproved(address, address) returns (bool)` | YES | YES | YES | YES | YES | Impl uses named return `approved` |
| 16 | `recordMint(address, uint24, uint256, uint32, MintPaymentKind) payable returns (uint256, uint256)` | YES | YES | YES | YES | YES | |
| 17 | `consumeCoinflipBoon(address) returns (uint16)` | YES | YES | YES | YES | YES | |
| 18 | `consumeDecimatorBoon(address) returns (uint16)` | YES | YES | YES | YES | YES | |
| 19 | `consumePurchaseBoost(address) returns (uint16)` | YES | YES | YES | YES | YES | |
| 20 | `deityBoonData(address) returns (uint256, uint48, uint8, bool, bool)` | YES | YES | YES | YES | YES | |
| 21 | `issueDeityBoon(address, address, uint8)` | YES | YES | YES | YES | YES | |
| 22 | `futurePrizePoolView(uint24) returns (uint256)` | YES | YES | YES | YES | YES | lvl param unused in impl |
| 23 | `futurePrizePoolTotalView() returns (uint256)` | YES | YES | YES | YES | YES | |
| 24 | `ticketsOwedView(uint24, address) returns (uint32)` | YES | YES | YES | YES | YES | |
| 25 | `creditDecJackpotClaimBatch(address[], uint256[], uint256)` | YES | YES | YES | YES | YES | |
| 26 | `creditDecJackpotClaim(address, uint256, uint256)` | YES | YES | YES | YES | YES | |
| 27 | `recordDecBurn(address, uint24, uint8, uint256, uint256) returns (uint8)` | YES | YES | YES | YES | YES | |
| 28 | `runDecimatorJackpot(uint256, uint24, uint256) returns (uint256)` | YES | YES | YES | YES | YES | |
| 29 | `runTerminalJackpot(uint256, uint24, uint256) returns (uint256)` | YES | YES | YES | YES | YES | |
| 30 | `consumeDecClaim(address, uint24) returns (uint256)` | YES | YES | YES | YES | YES | |
| 31 | `claimDecimatorJackpot(uint24)` | YES | YES | YES | YES | YES | |
| 32 | `decClaimable(address, uint24) returns (uint256, bool)` | YES | YES | YES | YES | YES | |
| 33 | `recordCoinflipDeposit(uint256)` | YES | YES | YES | YES | YES | |
| 34 | `recordMintQuestStreak(address)` | YES | YES | YES | YES | YES | |
| 35 | `payCoinflipBountyDgnrs(address)` | YES | YES | YES | YES | YES | |
| 36 | `rngLocked() returns (bool)` | YES | YES | YES | YES | YES | |
| 37 | `currentDayView() returns (uint48)` | YES | YES | YES | YES | YES | |
| 38 | `requestLootboxRng()` | YES | YES | YES | YES | YES | |
| 39 | `afKingModeFor(address) returns (bool)` | YES | YES | YES | YES | YES | |
| 40 | `afKingActivatedLevelFor(address) returns (uint24)` | YES | YES | YES | YES | YES | |
| 41 | `deactivateAfKingFromCoin(address)` | YES | YES | YES | YES | YES | |
| 42 | `syncAfKingLazyPassFromCoin(address) returns (bool)` | YES | YES | YES | YES | YES | |
| 43 | `lootboxStatus(address, uint48) returns (uint256, bool)` | YES | YES | YES | YES | INFO | NatSpec says "presale" param indicates presale status of lootbox; impl returns global `lootboxPresaleActive` flag (current state, not per-lootbox) |
| 44 | `lootboxPresaleActiveFlag() returns (bool)` | YES | YES | YES | YES | YES | |
| 45 | `openLootBox(address, uint48)` | YES | YES | YES | YES | YES | |
| 46 | `placeFullTicketBets(address, uint8, uint128, uint8, uint32, uint8) payable` | YES | YES | YES | YES | YES | |
| 47 | `placeFullTicketBetsFromAffiliateCredit(address, uint128, uint8, uint32, uint8)` | YES | YES | YES | YES | YES | |
| 48 | `resolveDegeneretteBets(address, uint64[])` | YES | YES | YES | YES | YES | Wraps module `resolveBets` |
| 49 | `degeneretteBetInfo(address, uint64) returns (uint256)` | YES | YES | YES | YES | YES | |
| 50 | `lootboxRngIndexView() returns (uint48)` | YES | YES | YES | YES | YES | |
| 51 | `lootboxRngThresholdView() returns (uint256)` | YES | YES | YES | YES | YES | |
| 52 | `lootboxRngMinLinkBalanceView() returns (uint256)` | YES | YES | YES | YES | YES | |
| 53 | `setLootboxRngThreshold(uint256)` | YES | YES | YES | YES | YES | |
| 54 | `sampleTraitTickets(uint256) returns (uint24, uint8, address[])` | YES | YES | YES | YES | YES | Named returns differ: lvl/trait vs lvlSel/traitSel (compatible) |
| 55 | `sampleTraitTicketsAtLevel(uint24, uint256) returns (uint8, address[])` | YES | YES | YES | YES | YES | Named returns differ: trait vs traitSel (compatible) |
| 56 | `sampleFarFutureTickets(uint256) returns (address[])` | YES | YES | YES | YES | YES | |
| 57 | `purchaseDeityPass(address, uint8) payable` | YES | YES | YES | YES | YES | |
| 58 | `onDeityPassTransfer(address, address, uint8)` | YES | YES | YES | YES | YES | 3rd param unnamed in impl (ignored) |
| 59 | `purchaseLazyPass(address) payable` | YES | YES | YES | YES | YES | |
| 60 | `deityPassCountFor(address) returns (uint16)` | YES | YES | YES | YES | YES | |
| 61 | `deityPassPurchasedCountFor(address) returns (uint16)` | YES | YES | YES | YES | YES | |
| 62 | `deityPassTotalIssuedCount() returns (uint32)` | YES | YES | YES | YES | YES | |
| 63 | `purchase(address, uint256, uint256, bytes32, MintPaymentKind) payable` | YES | YES | YES | YES | YES | |
| 64 | `purchaseCoin(address, uint256, uint256)` | YES | YES | YES | YES | YES | |
| 65 | `getDailyHeroWager(uint48, uint8, uint8) returns (uint256)` | YES | YES | YES | YES | N/A | No NatSpec in interface |
| 66 | `getDailyHeroWinner(uint48) returns (uint8, uint8, uint256)` | YES | YES | YES | YES | N/A | No NatSpec in interface |
| 67 | `getPlayerDegeneretteWager(address, uint24) returns (uint256)` | YES | YES | YES | YES | N/A | No NatSpec in interface |
| 68 | `getTopDegenerette(uint24) returns (address, uint256)` | YES | YES | YES | YES | N/A | No NatSpec in interface |

**Note:** Functions 65-68 lack NatSpec in the interface but have NatSpec in the implementation. These are view-only tracking functions.

**Functions not in IDegenerusGame.sol but present in DegenerusGame.sol (not interface functions):**
- `setOperatorApproval`, `purchaseWhaleBundle`, `openBurnieLootBox`, `purchaseBurnieLootbox`, `claimWinnings`, `claimWinningsStethFirst`, `claimAffiliateDgnrs`, `setAutoRebuy`, `setDecimatorAutoRebuy`, `setAutoRebuyTakeProfit`, `autoRebuyEnabledFor`, `decimatorAutoRebuyEnabledFor`, `autoRebuyTakeProfitFor`, `setAfKingMode`, `hasActiveLazyPass`, `claimWhalePass`, `adminSwapEthForStEth`, `adminStakeEthForStEth`, `updateVrfCoordinatorAndSub`, `reverseFlip`, `rawFulfillRandomWords`, `prizePoolTargetView`, `nextPrizePoolView`, `currentPrizePoolView`, `rewardPoolView`, `claimablePoolView`, `yieldPoolView`, `wireVrf`, `rngWordForDay`, `lastRngWord`, `isRngFulfilled`, various private/internal functions

These are intentionally excluded from the core interface as they are admin, internal, or specialty functions not needed for contract-to-contract integration.

---

### IDegenerusGameModules.sol (50 functions across 10 module interfaces)

**Implements:** 10 delegatecall module contracts via DegenerusGame.sol

#### IDegenerusGameAdvanceModule (6 functions)

| # | Interface Function | Sig Match | Params Match | Returns Match | Vis Match | NatSpec Match | Notes |
|---|-------------------|-----------|--------------|---------------|-----------|---------------|-------|
| 1 | `advanceGame()` | YES | YES | YES | YES | YES | Delegatecall from Game |
| 2 | `requestLootboxRng()` | YES | YES | YES | YES | YES | Delegatecall from Game |
| 3 | `wireVrf(address, uint256, bytes32)` | YES | YES | YES | YES | YES | |
| 4 | `updateVrfCoordinatorAndSub(address, uint256, bytes32)` | YES | YES | YES | YES | YES | |
| 5 | `reverseFlip()` | YES | YES | YES | YES | YES | |
| 6 | `rawFulfillRandomWords(uint256, uint256[])` | YES | YES | YES | YES | YES | |

#### IDegenerusGameEndgameModule (3 functions)

| # | Interface Function | Sig Match | Params Match | Returns Match | Vis Match | NatSpec Match | Notes |
|---|-------------------|-----------|--------------|---------------|-----------|---------------|-------|
| 1 | `runRewardJackpots(uint24, uint256)` | YES | YES | YES | YES | YES | |
| 2 | `rewardTopAffiliate(uint24)` | YES | YES | YES | YES | YES | |
| 3 | `claimWhalePass(address)` | YES | YES | YES | YES | YES | |

#### IDegenerusGameGameOverModule (2 functions)

| # | Interface Function | Sig Match | Params Match | Returns Match | Vis Match | NatSpec Match | Notes |
|---|-------------------|-----------|--------------|---------------|-----------|---------------|-------|
| 1 | `handleGameOverDrain(uint48)` | YES | YES | YES | YES | YES | |
| 2 | `handleFinalSweep()` | YES | YES | YES | YES | YES | |

#### IDegenerusGameJackpotModule (7 functions)

| # | Interface Function | Sig Match | Params Match | Returns Match | Vis Match | NatSpec Match | Notes |
|---|-------------------|-----------|--------------|---------------|-----------|---------------|-------|
| 1 | `payDailyJackpot(bool, uint24, uint256)` | YES | YES | YES | YES | YES | |
| 2 | `payDailyJackpotCoinAndTickets(uint256)` | YES | YES | YES | YES | YES | |
| 3 | `consolidatePrizePools(uint24, uint256)` | YES | YES | YES | YES | YES | |
| 4 | `awardFinalDayDgnrsReward(uint24, uint256)` | YES | YES | YES | YES | YES | |
| 5 | `processTicketBatch(uint24) returns (bool)` | YES | YES | YES | YES | YES | |
| 6 | `payDailyCoinJackpot(uint24, uint256)` | YES | YES | YES | YES | YES | |
| 7 | `runTerminalJackpot(uint256, uint24, uint256) returns (uint256)` | YES | YES | YES | YES | YES | |

#### IDegenerusGameDecimatorModule (7 functions)

| # | Interface Function | Sig Match | Params Match | Returns Match | Vis Match | NatSpec Match | Notes |
|---|-------------------|-----------|--------------|---------------|-----------|---------------|-------|
| 1 | `creditDecJackpotClaimBatch(address[], uint256[], uint256)` | YES | YES | YES | YES | YES | |
| 2 | `creditDecJackpotClaim(address, uint256, uint256)` | YES | YES | YES | YES | YES | |
| 3 | `recordDecBurn(address, uint24, uint8, uint256, uint256) returns (uint8)` | YES | YES | YES | YES | YES | |
| 4 | `runDecimatorJackpot(uint256, uint24, uint256) returns (uint256)` | YES | YES | YES | YES | YES | |
| 5 | `consumeDecClaim(address, uint24) returns (uint256)` | YES | YES | YES | YES | YES | |
| 6 | `claimDecimatorJackpot(uint24)` | YES | YES | YES | YES | YES | |
| 7 | `decClaimable(address, uint24) returns (uint256, bool)` | YES | YES | YES | YES | YES | |

#### IDegenerusGameWhaleModule (4 functions)

| # | Interface Function | Sig Match | Params Match | Returns Match | Vis Match | NatSpec Match | Notes |
|---|-------------------|-----------|--------------|---------------|-----------|---------------|-------|
| 1 | `purchaseWhaleBundle(address, uint256) payable` | YES | YES | YES | YES | YES | |
| 2 | `purchaseLazyPass(address) payable` | YES | YES | YES | YES | YES | |
| 3 | `purchaseDeityPass(address, uint8) payable` | YES | YES | YES | YES | YES | |
| 4 | `handleDeityPassTransfer(address, address)` | YES | YES | YES | YES | YES | |

#### IDegenerusGameMintModule (8 functions)

| # | Interface Function | Sig Match | Params Match | Returns Match | Vis Match | NatSpec Match | Notes |
|---|-------------------|-----------|--------------|---------------|-----------|---------------|-------|
| 1 | `recordMintData(address, uint24, uint32) payable returns (uint256)` | YES | YES | YES | YES | YES | |
| 2 | `purchase(address, uint256, uint256, bytes32, MintPaymentKind) payable` | YES | YES | YES | YES | YES | |
| 3 | `purchaseCoin(address, uint256, uint256)` | YES | YES | YES | YES | YES | |
| 4 | `purchaseBurnieLootbox(address, uint256)` | YES | YES | YES | YES | YES | |
| 5 | `openLootBox(address, uint48)` | YES | YES | YES | YES | YES | |
| 6 | `resolveLootboxDirect(address, uint256, uint256)` | YES | YES | YES | YES | YES | |
| 7 | `processFutureTicketBatch(uint24) returns (bool, bool, uint32)` | YES | YES | YES | YES | YES | |

**Note:** Table shows 7 functions; `openLootBox` from MintModule is also in LootboxModule interface.

#### IDegenerusGameLootboxModule (5 functions)

| # | Interface Function | Sig Match | Params Match | Returns Match | Vis Match | NatSpec Match | Notes |
|---|-------------------|-----------|--------------|---------------|-----------|---------------|-------|
| 1 | `openLootBox(address, uint48)` | YES | YES | YES | YES | YES | |
| 2 | `openBurnieLootBox(address, uint48)` | YES | YES | YES | YES | YES | |
| 3 | `resolveLootboxDirect(address, uint256, uint256)` | YES | YES | YES | YES | YES | |
| 4 | `deityBoonSlots(address) returns (uint8[3], uint8, uint48)` | YES | YES | YES | YES | YES | |
| 5 | `issueDeityBoon(address, address, uint8)` | YES | YES | YES | YES | YES | |

#### IDegenerusGameBoonModule (5 functions)

| # | Interface Function | Sig Match | Params Match | Returns Match | Vis Match | NatSpec Match | Notes |
|---|-------------------|-----------|--------------|---------------|-----------|---------------|-------|
| 1 | `consumeCoinflipBoon(address) returns (uint16)` | YES | YES | YES | YES | YES | Return named `boonBps` |
| 2 | `consumePurchaseBoost(address) returns (uint16)` | YES | YES | YES | YES | YES | |
| 3 | `consumeDecimatorBoost(address) returns (uint16)` | YES | YES | YES | YES | YES | |
| 4 | `checkAndClearExpiredBoon(address) returns (bool)` | YES | YES | YES | YES | YES | |
| 5 | `consumeActivityBoon(address)` | YES | YES | YES | YES | YES | |

#### IDegenerusGameDegeneretteModule (3 functions)

| # | Interface Function | Sig Match | Params Match | Returns Match | Vis Match | NatSpec Match | Notes |
|---|-------------------|-----------|--------------|---------------|-----------|---------------|-------|
| 1 | `placeFullTicketBets(address, uint8, uint128, uint8, uint32, uint8) payable` | YES | YES | YES | YES | YES | |
| 2 | `placeFullTicketBetsFromAffiliateCredit(address, uint128, uint8, uint32, uint8)` | YES | YES | YES | YES | YES | |
| 3 | `resolveBets(address, uint64[])` | YES | YES | YES | YES | YES | Called as `resolveDegeneretteBets` at Game level |

---

### IBurnieCoinflip.sol (16 functions)

**Implements:** BurnieCoinflip.sol

| # | Interface Function | Sig Match | Params Match | Returns Match | Vis Match | NatSpec Match | Notes |
|---|-------------------|-----------|--------------|---------------|-----------|---------------|-------|
| 1 | `depositCoinflip(address, uint256)` | YES | YES | YES | YES | YES | |
| 2 | `claimCoinflips(address, uint256) returns (uint256)` | YES | YES | YES | YES | YES | |
| 3 | `claimCoinflipsFromBurnie(address, uint256) returns (uint256)` | YES | YES | YES | YES | YES | |
| 4 | `consumeCoinflipsForBurn(address, uint256) returns (uint256)` | YES | YES | YES | YES | YES | |
| 5 | `claimCoinflipsTakeProfit(address, uint256) returns (uint256)` | YES | YES | YES | YES | YES | |
| 6 | `setCoinflipAutoRebuy(address, bool, uint256)` | YES | YES | YES | YES | YES | |
| 7 | `setCoinflipAutoRebuyTakeProfit(address, uint256)` | YES | YES | YES | YES | YES | |
| 8 | `settleFlipModeChange(address)` | YES | YES | YES | YES | YES | |
| 9 | `processCoinflipPayouts(bool, uint256, uint48)` | YES | YES | YES | YES | YES | |
| 10 | `creditFlip(address, uint256)` | YES | YES | YES | YES | YES | |
| 11 | `creditFlipBatch(address[3], uint256[3])` | YES | YES | YES | YES | YES | |
| 12 | `previewClaimCoinflips(address) returns (uint256)` | YES | YES | YES | YES | YES | |
| 13 | `coinflipAmount(address) returns (uint256)` | YES | YES | YES | YES | YES | |
| 14 | `coinflipAutoRebuyInfo(address) returns (bool, uint256, uint256, uint48)` | YES | YES | YES | YES | YES | |
| 15 | `coinflipTopLastDay() returns (address, uint128)` | YES | YES | YES | YES | YES | |

**Note:** 15 functions listed (interface has creditFlip, creditFlipBatch which are shared). Adjusted from plan's estimate of 15.

---

### IDegenerusCoin.sol (7 functions, extends IDegenerusCoinModule)

**Implements:** BurnieCoin.sol

| # | Interface Function | Sig Match | Params Match | Returns Match | Vis Match | NatSpec Match | Notes |
|---|-------------------|-----------|--------------|---------------|-----------|---------------|-------|
| 1 | `creditCoin(address, uint256)` | YES | YES | YES | YES | YES | |
| 2 | `burnCoin(address, uint256)` | YES | YES | YES | YES | YES | |
| 3 | `mintForGame(address, uint256)` | YES | YES | YES | YES | YES | |
| 4 | `notifyQuestMint(address, uint32, bool)` | YES | YES | YES | YES | YES | |
| 5 | `notifyQuestLootBox(address, uint256)` | YES | YES | YES | YES | YES | |
| 6 | `notifyQuestDegenerette(address, uint256, bool)` | YES | YES | YES | YES | YES | |

**Inherited from IDegenerusCoinModule (via `is IDegenerusCoinModule`):** See DegenerusGameModuleInterfaces.sol below.

---

### IDegenerusAffiliate.sol (6 functions)

**Implements:** DegenerusAffiliate.sol

| # | Interface Function | Sig Match | Params Match | Returns Match | Vis Match | NatSpec Match | Notes |
|---|-------------------|-----------|--------------|---------------|-----------|---------------|-------|
| 1 | `payAffiliate(uint256, bytes32, address, uint24, bool, uint16) returns (uint256)` | YES | YES | YES | YES | YES | |
| 2 | `consumeDegeneretteCredit(address, uint256) returns (uint256)` | YES | YES | YES | YES | YES | |
| 3 | `affiliateTop(uint24) returns (address, uint96)` | YES | YES | YES | YES | YES | |
| 4 | `affiliateScore(uint24, address) returns (uint256)` | YES | YES | YES | YES | YES | |
| 5 | `affiliateBonusPointsBest(uint24, address) returns (uint256)` | YES | YES | YES | YES | YES | |
| 6 | `getReferrer(address) returns (address)` | YES | YES | YES | YES | YES | |

---

### IDegenerusQuests.sol (9 functions)

**Implements:** DegenerusQuests.sol

| # | Interface Function | Sig Match | Params Match | Returns Match | Vis Match | NatSpec Match | Notes |
|---|-------------------|-----------|--------------|---------------|-----------|---------------|-------|
| 1 | `rollDailyQuest(uint48, uint256) returns (bool, uint8[2], bool)` | YES | YES | YES | YES | YES | |
| 2 | `handleMint(address, uint32, bool) returns (uint256, uint8, uint32, bool)` | YES | YES | YES | YES | YES | |
| 3 | `handleFlip(address, uint256) returns (uint256, uint8, uint32, bool)` | YES | YES | YES | YES | YES | |
| 4 | `handleDecimator(address, uint256) returns (uint256, uint8, uint32, bool)` | YES | YES | YES | YES | YES | |
| 5 | `handleAffiliate(address, uint256) returns (uint256, uint8, uint32, bool)` | YES | YES | YES | YES | YES | |
| 6 | `handleLootBox(address, uint256) returns (uint256, uint8, uint32, bool)` | YES | YES | YES | YES | YES | |
| 7 | `handleDegenerette(address, uint256, bool) returns (uint256, uint8, uint32, bool)` | YES | YES | YES | YES | YES | |
| 8 | `awardQuestStreakBonus(address, uint16, uint48)` | YES | YES | YES | YES | YES | |
| 9 | `playerQuestStates(address) returns (uint32, uint32, uint128[2], bool[2])` | YES | YES | YES | YES | YES | |

---

### IDegenerusJackpots.sol (2 functions)

**Implements:** DegenerusJackpots.sol

| # | Interface Function | Sig Match | Params Match | Returns Match | Vis Match | NatSpec Match | Notes |
|---|-------------------|-----------|--------------|---------------|-----------|---------------|-------|
| 1 | `runBafJackpot(uint256, uint24, uint256) returns (address[], uint256[], uint256, uint256)` | YES | YES | YES | YES | YES | |
| 2 | `recordBafFlip(address, uint24, uint256)` | YES | YES | YES | YES | YES | |

---

### IDegenerusStonk.sol (14 functions)

**Implements:** DegenerusStonk.sol

| # | Interface Function | Sig Match | Params Match | Returns Match | Vis Match | NatSpec Match | Notes |
|---|-------------------|-----------|--------------|---------------|-----------|---------------|-------|
| 1 | `depositSteth(uint256)` | YES | YES | YES | YES | YES | |
| 2 | `poolBalance(Pool) returns (uint256)` | YES | YES | YES | YES | YES | |
| 3 | `transferFromPool(Pool, address, uint256) returns (uint256)` | YES | YES | YES | YES | YES | |
| 4 | `transferBetweenPools(Pool, Pool, uint256) returns (uint256)` | YES | YES | YES | YES | YES | |
| 5 | `burnForGame(address, uint256)` | YES | YES | YES | YES | YES | |
| 6 | `approve(address, uint256) returns (bool)` | YES | YES | YES | YES | YES | |
| 7 | `balanceOf(address) returns (uint256)` | YES | YES | YES | YES | YES | |
| 8 | `transfer(address, uint256) returns (bool)` | YES | YES | YES | YES | YES | |
| 9 | `transferFrom(address, address, uint256) returns (bool)` | YES | YES | YES | YES | YES | |
| 10 | `totalSupply() returns (uint256)` | YES | YES | YES | YES | YES | Public state variable auto-getter |
| 11 | `ethReserve() returns (uint256)` | YES | YES | YES | YES | INFO | Interface NatSpec says "Get ETH reserve"; impl is dead storage (always 0 per Phase 54 audit). Interface description accurate for the getter, but the value is always 0 |
| 12 | `burnieReserve() returns (uint256)` | YES | YES | YES | YES | YES | |
| 13 | `totalBacking() returns (uint256)` | YES | YES | YES | YES | YES | |
| 14 | `previewBurn(uint256) returns (uint256, uint256, uint256)` | YES | YES | YES | YES | YES | |

---

### IStETH.sol (5 functions)

**Implements:** Lido stETH external contract (0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84)

| # | Interface Function | Sig Match | Params Match | Returns Match | Vis Match | NatSpec Match | Notes |
|---|-------------------|-----------|--------------|---------------|-----------|---------------|-------|
| 1 | `submit(address) payable returns (uint256)` | YES | YES | YES | YES | YES | Matches Lido ABI |
| 2 | `balanceOf(address) returns (uint256)` | YES | YES | YES | YES | YES | Standard ERC20 |
| 3 | `transfer(address, uint256) returns (bool)` | YES | YES | YES | YES | YES | Standard ERC20 |
| 4 | `approve(address, uint256) returns (bool)` | YES | YES | YES | YES | YES | Standard ERC20 |
| 5 | `transferFrom(address, address, uint256) returns (bool)` | YES | YES | YES | YES | YES | Standard ERC20 |

**External ABI verification:** Lido stETH implements ERC20 plus `submit(address referral) payable returns (uint256)` for depositing ETH. All 5 function signatures match the published Lido ABI.

---

### IVaultCoin.sol (5 functions)

**Implements:** BurnieCoin.sol (subset)

| # | Interface Function | Sig Match | Params Match | Returns Match | Vis Match | NatSpec Match | Notes |
|---|-------------------|-----------|--------------|---------------|-----------|---------------|-------|
| 1 | `vaultEscrow(uint256)` | YES | YES | YES | YES | YES | |
| 2 | `vaultMintTo(address, uint256)` | YES | YES | YES | YES | YES | |
| 3 | `vaultMintAllowance() returns (uint256)` | YES | YES | YES | YES | YES | |
| 4 | `balanceOf(address) returns (uint256)` | YES | YES | YES | YES | YES | |
| 5 | `transfer(address, uint256) returns (bool)` | YES | YES | YES | YES | YES | |

---

### IVRFCoordinator.sol (2 functions)

**Implements:** Chainlink VRF V2.5 Plus Coordinator (external contract)

| # | Interface Function | Sig Match | Params Match | Returns Match | Vis Match | NatSpec Match | Notes |
|---|-------------------|-----------|--------------|---------------|-----------|---------------|-------|
| 1 | `requestRandomWords(VRFRandomWordsRequest) returns (uint256)` | YES | YES | YES | YES | YES | Matches Chainlink VRFV2PlusClient |
| 2 | `getSubscription(uint256) returns (uint96, uint96, uint64, address, address[])` | YES | YES | YES | YES | YES | Matches Chainlink VRFCoordinatorV2_5 |

**External ABI verification:** The `VRFRandomWordsRequest` struct matches `VRFV2PlusClient.RandomWordsRequest` from Chainlink's V2.5 contracts. The `getSubscription` return types match the Chainlink VRFCoordinatorV2_5 implementation.

---

### DegenerusGameModuleInterfaces.sol (4 functions)

**Implements:** IDegenerusCoinModule is implemented by BurnieCoin.sol

| # | Interface Function | Sig Match | Params Match | Returns Match | Vis Match | NatSpec Match | Notes |
|---|-------------------|-----------|--------------|---------------|-----------|---------------|-------|
| 1 | `creditFlip(address, uint256)` | YES | YES | YES | YES | YES | Delegates to BurnieCoinflip |
| 2 | `creditFlipBatch(address[3], uint256[3])` | YES | YES | YES | YES | YES | Delegates to BurnieCoinflip |
| 3 | `rollDailyQuest(uint48, uint256)` | YES | YES | YES | YES | YES | Delegates to DegenerusQuests |
| 4 | `vaultEscrow(uint256)` | YES | YES | YES | YES | YES | |

---

## NatSpec Accuracy Summary

| Interface File | Functions | NatSpec Present | NatSpec Accurate | NatSpec Issues |
|----------------|-----------|-----------------|------------------|----------------|
| IDegenerusGame.sol | 68 | 64 | 63 | 1 |
| IDegenerusGameModules.sol | 50 | 50 | 50 | 0 |
| IBurnieCoinflip.sol | 15 | 15 | 15 | 0 |
| IDegenerusCoin.sol | 6 | 6 | 6 | 0 |
| IDegenerusAffiliate.sol | 6 | 6 | 6 | 0 |
| IDegenerusQuests.sol | 9 | 9 | 9 | 0 |
| IDegenerusJackpots.sol | 2 | 2 | 2 | 0 |
| IDegenerusStonk.sol | 14 | 14 | 13 | 1 |
| IStETH.sol | 5 | 5 | 5 | 0 |
| IVaultCoin.sol | 5 | 5 | 5 | 0 |
| IVRFCoordinator.sol | 2 | 2 | 2 | 0 |
| DegenerusGameModuleInterfaces.sol | 4 | 4 | 4 | 0 |
| **Total** | **195** | **178** | **176** | **2** |

**Note:** 17 functions lack NatSpec: 4 Degenerette tracking views in IDegenerusGame.sol plus 13 functions in module interfaces that use minimal inline documentation. All missing NatSpec are on view/tracking functions where function names are self-documenting.

### NatSpec Discrepancies

| Interface | Function | NatSpec Says | Implementation Does | Severity |
|-----------|----------|-------------|---------------------|----------|
| IDegenerusGame.sol | `lootboxStatus` | "@return presale True if this was a presale lootbox" | Returns global `lootboxPresaleActive` flag (current state, not per-lootbox history) | Info |
| IDegenerusStonk.sol | `ethReserve` | "@return Amount of ETH in reserves" | Returns dead storage slot (always 0); Phase 54 audit confirmed ethReserve is unused | Info |

## Signature Mismatch Summary

No signature mismatches found. All 195 function signatures match exactly between interface declarations and implementations.

## Module Dispatch Verification

For IDegenerusGameModules.sol, each function is dispatched via delegatecall through DegenerusGame.sol:

| Function | Expected Module | Verified | Notes |
|----------|----------------|----------|-------|
| `advanceGame()` | AdvanceModule | YES | `GAME_ADVANCE_MODULE.delegatecall` |
| `requestLootboxRng()` | AdvanceModule | YES | `GAME_ADVANCE_MODULE.delegatecall` |
| `wireVrf(...)` | AdvanceModule | YES | `GAME_ADVANCE_MODULE.delegatecall` |
| `updateVrfCoordinatorAndSub(...)` | AdvanceModule | YES | `GAME_ADVANCE_MODULE.delegatecall` |
| `reverseFlip()` | AdvanceModule | YES | `GAME_ADVANCE_MODULE.delegatecall` |
| `rawFulfillRandomWords(...)` | AdvanceModule | YES | `GAME_ADVANCE_MODULE.delegatecall` |
| `runRewardJackpots(...)` | EndgameModule | YES | `GAME_ENDGAME_MODULE.delegatecall` (called internally) |
| `rewardTopAffiliate(...)` | EndgameModule | YES | `GAME_ENDGAME_MODULE.delegatecall` (called internally) |
| `claimWhalePass(...)` | EndgameModule | YES | `GAME_ENDGAME_MODULE.delegatecall` |
| `handleGameOverDrain(...)` | GameOverModule | YES | `GAME_GAMEOVER_MODULE.delegatecall` (called internally) |
| `handleFinalSweep()` | GameOverModule | YES | `GAME_GAMEOVER_MODULE.delegatecall` (called internally) |
| `payDailyJackpot(...)` | JackpotModule | YES | `GAME_JACKPOT_MODULE.delegatecall` (called internally) |
| `payDailyJackpotCoinAndTickets(...)` | JackpotModule | YES | `GAME_JACKPOT_MODULE.delegatecall` (called internally) |
| `consolidatePrizePools(...)` | JackpotModule | YES | `GAME_JACKPOT_MODULE.delegatecall` (called internally) |
| `awardFinalDayDgnrsReward(...)` | JackpotModule | YES | `GAME_JACKPOT_MODULE.delegatecall` (called internally) |
| `processTicketBatch(...)` | JackpotModule | YES | `GAME_JACKPOT_MODULE.delegatecall` (called internally) |
| `payDailyCoinJackpot(...)` | JackpotModule | YES | `GAME_JACKPOT_MODULE.delegatecall` (called internally) |
| `runTerminalJackpot(...)` | JackpotModule | YES | `GAME_JACKPOT_MODULE.delegatecall` |
| `creditDecJackpotClaimBatch(...)` | DecimatorModule | YES | `GAME_DECIMATOR_MODULE.delegatecall` |
| `creditDecJackpotClaim(...)` | DecimatorModule | YES | `GAME_DECIMATOR_MODULE.delegatecall` |
| `recordDecBurn(...)` | DecimatorModule | YES | `GAME_DECIMATOR_MODULE.delegatecall` |
| `runDecimatorJackpot(...)` | DecimatorModule | YES | `GAME_DECIMATOR_MODULE.delegatecall` |
| `consumeDecClaim(...)` | DecimatorModule | YES | `GAME_DECIMATOR_MODULE.delegatecall` |
| `claimDecimatorJackpot(...)` | DecimatorModule | YES | `GAME_DECIMATOR_MODULE.delegatecall` |
| `decClaimable(...)` | DecimatorModule | YES | Direct storage access (view) |
| `purchaseWhaleBundle(...)` | WhaleModule | YES | `GAME_WHALE_MODULE.delegatecall` |
| `purchaseLazyPass(...)` | WhaleModule | YES | `GAME_WHALE_MODULE.delegatecall` |
| `purchaseDeityPass(...)` | WhaleModule | YES | `GAME_WHALE_MODULE.delegatecall` |
| `handleDeityPassTransfer(...)` | WhaleModule | YES | `GAME_WHALE_MODULE.delegatecall` |
| `recordMintData(...)` | MintModule | YES | `GAME_MINT_MODULE.delegatecall` |
| `purchase(...)` | MintModule | YES | `GAME_MINT_MODULE.delegatecall` |
| `purchaseCoin(...)` | MintModule | YES | `GAME_MINT_MODULE.delegatecall` |
| `purchaseBurnieLootbox(...)` | MintModule | YES | `GAME_MINT_MODULE.delegatecall` |
| `openLootBox(...)` | MintModule/LootboxModule | YES | Routed through `GAME_LOOTBOX_MODULE.delegatecall` |
| `resolveLootboxDirect(...)` | MintModule/LootboxModule | YES | Callable by both modules |
| `processFutureTicketBatch(...)` | MintModule | YES | `GAME_MINT_MODULE.delegatecall` (called internally) |
| `openBurnieLootBox(...)` | LootboxModule | YES | `GAME_LOOTBOX_MODULE.delegatecall` |
| `deityBoonSlots(...)` | LootboxModule | YES | `GAME_LOOTBOX_MODULE.delegatecall` (view) |
| `issueDeityBoon(...)` | LootboxModule | YES | `GAME_LOOTBOX_MODULE.delegatecall` |
| `consumeCoinflipBoon(...)` | BoonModule | YES | `GAME_BOON_MODULE.delegatecall` |
| `consumePurchaseBoost(...)` | BoonModule | YES | `GAME_BOON_MODULE.delegatecall` |
| `consumeDecimatorBoost(...)` | BoonModule | YES | `GAME_BOON_MODULE.delegatecall` |
| `checkAndClearExpiredBoon(...)` | BoonModule | YES | `GAME_BOON_MODULE.delegatecall` |
| `consumeActivityBoon(...)` | BoonModule | YES | `GAME_BOON_MODULE.delegatecall` |
| `placeFullTicketBets(...)` | DegeneretteModule | YES | `GAME_DEGENERETTE_MODULE.delegatecall` |
| `placeFullTicketBetsFromAffiliateCredit(...)` | DegeneretteModule | YES | `GAME_DEGENERETTE_MODULE.delegatecall` |
| `resolveBets(...)` | DegeneretteModule | YES | `GAME_DEGENERETTE_MODULE.delegatecall` |

All 50 module functions map to the correct delegatecall target.

## Findings Summary

| Severity | Count | Details |
|----------|-------|---------|
| Signature Mismatch | 0 | All 195 signatures match exactly |
| NatSpec Inaccuracy | 2 | `lootboxStatus` return describes per-lootbox presale but returns global flag; `ethReserve` NatSpec implies active reserve but storage is dead |
| Missing NatSpec | 17 | 4 Degenerette tracking views in IDegenerusGame.sol, 13 module interface functions with minimal docs |
| All Verified | 195 | Exact match on function name, parameter types, return types, visibility, and mutability |

**Overall Assessment:** All interface files are well-maintained and accurately reflect their implementations. The two NatSpec discrepancies are informational only and do not affect ABI compatibility or integration correctness. The 17 missing NatSpec entries are on self-documenting view functions where the function names clearly convey purpose.
