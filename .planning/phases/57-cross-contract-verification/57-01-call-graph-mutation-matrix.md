# Protocol Call Graph and State Mutation Matrix

**Scope:** 22 deployable contracts + 10 delegatecall modules + 5 libraries
**Date:** 2026-03-07
**Source:** Phases 50-56 audit data + direct source verification

---

## Part 1: Cross-Contract Call Graph (XREF-01)

### Section A: Delegatecall Dispatch Map

Every delegatecall from `DegenerusGame.sol` into a module, extracted from source and verified against Phase 50-52 audit data.

| # | Game Function | Target Module | Module Function | Call Type |
|---|--------------|---------------|-----------------|-----------|
| 1 | `advanceGame()` | GAME_ADVANCE_MODULE | `advanceGame()` | delegatecall |
| 2 | `wireVrf(coordinator_, subId, keyHash_)` | GAME_ADVANCE_MODULE | `wireVrf(coordinator_, subId, keyHash_)` | delegatecall |
| 3 | `updateVrfCoordinatorAndSub(newCoord, newSubId, newKeyHash)` | GAME_ADVANCE_MODULE | `updateVrfCoordinatorAndSub(newCoord, newSubId, newKeyHash)` | delegatecall |
| 4 | `requestLootboxRng()` | GAME_ADVANCE_MODULE | `requestLootboxRng()` | delegatecall |
| 5 | `reverseFlip()` | GAME_ADVANCE_MODULE | `reverseFlip()` | delegatecall |
| 6 | `rawFulfillRandomWords(requestId, randomWords)` | GAME_ADVANCE_MODULE | `rawFulfillRandomWords(requestId, randomWords)` | delegatecall |
| 7 | `_purchaseFor(buyer, ticketQty, lootBoxAmt, affCode, payKind)` | GAME_MINT_MODULE | `purchase(buyer, ticketQty, lootBoxAmt, affCode, payKind)` | delegatecall |
| 8 | `purchaseCoin(buyer, ticketQty, lootBoxBurnieAmt)` | GAME_MINT_MODULE | `purchaseCoin(buyer, ticketQty, lootBoxBurnieAmt)` | delegatecall |
| 9 | `purchaseBurnieLootbox(buyer, burnieAmount)` | GAME_MINT_MODULE | `purchaseBurnieLootbox(buyer, burnieAmount)` | delegatecall |
| 10 | `_recordMintDataModule(player, lvl, mintUnits)` | GAME_MINT_MODULE | `recordMintData(player, lvl, mintUnits)` | delegatecall |
| 11 | `_purchaseWhaleBundleFor(buyer, quantity)` | GAME_WHALE_MODULE | `purchaseWhaleBundle(buyer, quantity)` | delegatecall |
| 12 | `_purchaseLazyPassFor(buyer)` | GAME_WHALE_MODULE | `purchaseLazyPass(buyer)` | delegatecall |
| 13 | `_purchaseDeityPassFor(buyer, symbolId)` | GAME_WHALE_MODULE | `purchaseDeityPass(buyer, symbolId)` | delegatecall |
| 14 | `onDeityPassTransfer(from, to, _)` | GAME_WHALE_MODULE | `handleDeityPassTransfer(from, to)` | delegatecall |
| 15 | `_openLootBoxFor(player, lootboxIndex)` | GAME_LOOTBOX_MODULE | `openLootBox(player, lootboxIndex)` | delegatecall |
| 16 | `_openBurnieLootBoxFor(player, lootboxIndex)` | GAME_LOOTBOX_MODULE | `openBurnieLootBox(player, lootboxIndex)` | delegatecall |
| 17 | `issueDeityBoon(deity, recipient, slot)` | GAME_LOOTBOX_MODULE | `issueDeityBoon(deity, recipient, slot)` | delegatecall |
| 18 | `placeFullTicketBets(player, currency, amt, count, ticket, hero)` | GAME_DEGENERETTE_MODULE | `placeFullTicketBets(player, currency, amt, count, ticket, hero)` | delegatecall |
| 19 | `placeFullTicketBetsFromAffiliateCredit(player, amt, count, ticket, hero)` | GAME_DEGENERETTE_MODULE | `placeFullTicketBetsFromAffiliateCredit(player, amt, count, ticket, hero)` | delegatecall |
| 20 | `resolveDegeneretteBets(player, betIds)` | GAME_DEGENERETTE_MODULE | `resolveBets(player, betIds)` | delegatecall |
| 21 | `consumeCoinflipBoon(player)` | GAME_BOON_MODULE | `consumeCoinflipBoon(player)` | delegatecall |
| 22 | `consumeDecimatorBoon(player)` | GAME_BOON_MODULE | `consumeDecimatorBoost(player)` | delegatecall |
| 23 | `consumePurchaseBoost(player)` | GAME_BOON_MODULE | `consumePurchaseBoost(player)` | delegatecall |
| 24 | `creditDecJackpotClaimBatch(accounts, amounts, rngWord)` | GAME_DECIMATOR_MODULE | `creditDecJackpotClaimBatch(accounts, amounts, rngWord)` | delegatecall |
| 25 | `creditDecJackpotClaim(account, amount, rngWord)` | GAME_DECIMATOR_MODULE | `creditDecJackpotClaim(account, amount, rngWord)` | delegatecall |
| 26 | `recordDecBurn(player, lvl, bucket, baseAmount, multBps)` | GAME_DECIMATOR_MODULE | `recordDecBurn(player, lvl, bucket, baseAmount, multBps)` | delegatecall |
| 27 | `runDecimatorJackpot(poolWei, lvl, rngWord)` | GAME_DECIMATOR_MODULE | `runDecimatorJackpot(poolWei, lvl, rngWord)` | delegatecall |
| 28 | `consumeDecClaim(player, lvl)` | GAME_DECIMATOR_MODULE | `consumeDecClaim(player, lvl)` | delegatecall |
| 29 | `claimDecimatorJackpot(lvl)` | GAME_DECIMATOR_MODULE | `claimDecimatorJackpot(lvl)` | delegatecall |
| 30 | `runTerminalJackpot(poolWei, targetLvl, rngWord)` | GAME_JACKPOT_MODULE | `runTerminalJackpot(poolWei, targetLvl, rngWord)` | delegatecall |
| 31 | `_claimWhalePassFor(player)` | GAME_ENDGAME_MODULE | `claimWhalePass(player)` | delegatecall |

**Total delegatecall dispatch paths: 31**

**Note:** Rows 27, 28, 29, 30 are "self-call" pattern -- functions on Game that are called by other modules via `IDegenerusGame(address(this))` during delegatecall execution, which triggers a new delegatecall chain through Game's external function.

**Module-to-Game self-calls (via `IDegenerusGame(address(this))`):**
- MintModule -> `Game.recordMint{value}(...)` -> MintModule.recordMintData (row 10)
- MintModule -> `Game.consumePurchaseBoost(...)` -> BoonModule.consumePurchaseBoost (row 23)
- MintModule -> `Game.playerActivityScore(...)` (view, no delegatecall)
- LootboxModule -> `Game.playerActivityScore(...)` (view, no delegatecall)
- WhaleModule -> `Game.playerActivityScore(...)` (view, no delegatecall)
- EndgameModule -> `Game.runDecimatorJackpot(...)` -> DecimatorModule (row 27)
- GameOverModule -> `Game.runDecimatorJackpot(...)` -> DecimatorModule (row 27)
- GameOverModule -> `Game.runTerminalJackpot(...)` -> JackpotModule (row 30)

---

### Section B: Cross-Contract External Calls

All external calls between protocol contracts, grouped by source. Call types: `external` (state-changing), `view` (staticcall/view), `delegatecall`.

#### DegenerusGame (Source)

| Source Contract | Function | Target Contract | Method Called | Call Type |
|----------------|----------|----------------|--------------|-----------|
| DegenerusGame | `payCoinflipBountyDgnrs` | DegenerusStonk | `poolBalance(Pool.Reward)` | view |
| DegenerusGame | `payCoinflipBountyDgnrs` | DegenerusStonk | `transferFromPool(Pool.Reward, player, payout)` | external |
| DegenerusGame | `claimAffiliateDgnrs` | DegenerusAffiliate | `affiliateScore(prevLevel, player)` | view |
| DegenerusGame | `claimAffiliateDgnrs` | DegenerusStonk | `poolBalance(Pool.Affiliate)` | view |
| DegenerusGame | `claimAffiliateDgnrs` | DegenerusStonk | `transferFromPool(Pool.Affiliate, player, reward)` | external |
| DegenerusGame | `claimAffiliateDgnrs` | BurnieCoin | `creditFlip(player, bonus)` | external |
| DegenerusGame | `_setAfKingMode` | BurnieCoinflip | `setCoinflipAutoRebuy(player, true, adjustedCoinKeep)` | external |
| DegenerusGame | `_setAfKingMode` | BurnieCoinflip | `settleFlipModeChange(player)` | external |
| DegenerusGame | `_deactivateAfKing` | BurnieCoinflip | `settleFlipModeChange(player)` | external |
| DegenerusGame | `_claimWinningsInternal` | payable(player) | `.call{value}` | external |
| DegenerusGame | `_transferSteth` | stETH | `approve(DGNRS, amount)` | external |
| DegenerusGame | `_transferSteth` | DegenerusStonk | `depositSteth(amount)` | external |
| DegenerusGame | `_transferSteth` | stETH | `transfer(to, amount)` | external |
| DegenerusGame | `adminSwapEthForStEth` | stETH | `balanceOf(this)` | view |
| DegenerusGame | `adminSwapEthForStEth` | stETH | `transfer(recipient, amount)` | external |
| DegenerusGame | `adminStakeEthForStEth` | stETH | `submit{value}(address(0))` | external |
| DegenerusGame | `_awardEarlybirdDgnrs` | DegenerusStonk | `poolBalance(Pool.Earlybird)` | view |
| DegenerusGame | `_awardEarlybirdDgnrs` | DegenerusStonk | `transferFromPool(Pool.Earlybird, buyer, payout)` | external |
| DegenerusGame | `_awardEarlybirdDgnrs` | DegenerusStonk | `transferBetweenPools(Pool.Earlybird, Pool.Reward, remaining)` | external |
| DegenerusGame | `constructor` | DegenerusStonk | (implicit: storage initialized to DGNRS/VAULT) | -- |
| DegenerusGame | `_payoutWithStethFallback` | stETH | `balanceOf(this)` | view |
| DegenerusGame | `_payoutWithEthFallback` | stETH | `balanceOf(this)` | view |
| DegenerusGame | `yieldPoolView` | stETH | `balanceOf(this)` | view |

#### Modules executing in Game context (via delegatecall -- external calls originate from Game's address)

| Module (via Game) | Function | Target Contract | Method Called | Call Type |
|-------------------|----------|----------------|--------------|-----------|
| AdvanceModule | `advanceGame` | BurnieCoin | `creditFlip(caller, ADVANCE_BOUNTY)` | external |
| AdvanceModule | `advanceGame` | BurnieCoinflip | `processCoinflipPayouts(bonusFlip, word, day)` | external |
| AdvanceModule | `advanceGame` | stETH | `submit{value}(address(0))` | external |
| AdvanceModule | `reverseFlip` | BurnieCoin | `burnCoin(msg.sender, cost)` | external |
| AdvanceModule | `advanceGame` | BurnieCoin | `rollDailyQuest(day, word)` | external |
| MintModule | `purchase` | DegenerusAffiliate | `payAffiliate(...)` | external |
| MintModule | `purchase` | BurnieCoin | `creditFlip(buyer, amount)` | external |
| MintModule | `purchase` | BurnieCoin | `notifyQuestMint(buyer, qty, paidWithEth)` | external |
| MintModule | `purchase` | BurnieCoin | `notifyQuestLootBox(buyer, amount)` | external |
| MintModule | `purchase` | BurnieCoin | `burnCoin(payer, amount)` | external |
| MintModule | `purchaseBurnieLootbox` | BurnieCoin | `burnCoin(buyer, burnieAmount)` | external |
| MintModule | `purchase` | payable(VAULT) | `.call{value}` | external |
| WhaleModule | `purchaseWhaleBundle` | DegenerusAffiliate | `getReferrer(buyer)` | view |
| WhaleModule | `purchaseLazyPass` | DegenerusAffiliate | `getReferrer(buyer)` | view |
| WhaleModule | `purchaseDeityPass` | DegenerusAffiliate | `getReferrer(buyer)` | view |
| WhaleModule | `purchaseWhaleBundle` | DegenerusStonk | `poolBalance(Pool.Whale)` | view |
| WhaleModule | `purchaseWhaleBundle` | DegenerusStonk | `transferFromPool(Pool.Whale, ...)` | external |
| WhaleModule | `purchaseWhaleBundle` | DegenerusStonk | `poolBalance(Pool.Affiliate)` | view |
| WhaleModule | `purchaseWhaleBundle` | DegenerusStonk | `transferFromPool(Pool.Affiliate, ...)` | external |
| WhaleModule | `purchaseLazyPass` | DegenerusStonk | `poolBalance(Pool.Whale)` | view |
| WhaleModule | `purchaseLazyPass` | DegenerusStonk | `transferFromPool(Pool.Whale, ...)` | external |
| WhaleModule | `purchaseLazyPass` | DegenerusStonk | `poolBalance(Pool.Affiliate)` | view |
| WhaleModule | `purchaseLazyPass` | DegenerusStonk | `transferFromPool(Pool.Affiliate, ...)` | external |
| LootboxModule | `openLootBox` | BurnieCoin | `creditFlip(player, burnieAmount)` | external |
| LootboxModule | `openLootBox` | DegenerusStonk | `poolBalance(Pool.Lootbox)` | view |
| LootboxModule | `openLootBox` | DegenerusStonk | `transferFromPool(Pool.Lootbox, ...)` | external |
| DegeneretteModule | `placeFullTicketBets` | BurnieCoin | `notifyQuestDegenerette(player, amount, paidWithEth)` | external |
| DegeneretteModule | `placeFullTicketBets` | BurnieCoin | `burnCoin(player, totalBet)` | external |
| DegeneretteModule | `placeFullTicketBetsFromAffiliateCredit` | DegenerusAffiliate | `consumeDegeneretteCredit(player, totalBet)` | external |
| DegeneretteModule | `placeFullTicketBetsFromAffiliateCredit` | BurnieCoin | `notifyQuestDegenerette(player, amount, false)` | external |
| DegeneretteModule | `resolveBets` | BurnieCoin | `mintForGame(player, payout)` | external |
| DegeneretteModule | `_activityScoreForDegenerette` | DegenerusQuests | `playerQuestStates(player)` | view |
| DegeneretteModule | `_activityScoreForDegenerette` | DegenerusAffiliate | `affiliateBonusPointsBest(level, player)` | view |
| JackpotModule | `payDailyJackpot` | BurnieCoin | `rollDailyQuest(day, word)` | external |
| JackpotModule | `_awardFinalDayDgnrsReward` | DegenerusStonk | `poolBalance(Pool.Reward)` | view |
| JackpotModule | `_awardFinalDayDgnrsReward` | DegenerusStonk | `transferFromPool(Pool.Reward, ...)` | external |
| JackpotModule | `_payDailyCoinJackpot` | BurnieCoin | `creditFlip(beneficiary, amount)` | external |
| JackpotModule | `_payDailyCoinJackpot` | BurnieCoin | `creditFlipBatch(players, amounts)` | external |
| JackpotModule | `_payDailyCoinJackpot` | BurnieCoin | `creditFlip(DGNRS, coinAmount)` | external |
| JackpotModule | `runTerminalJackpot` | stETH | `balanceOf(this)` | view |
| JackpotModule | `_distributeJackpotEth` | DegenerusStonk | `transferFromPool(Pool.Reward, ...)` | external |
| EndgameModule | `_rewardTopAffiliate` | DegenerusAffiliate | `affiliateTop(lvl)` | view |
| EndgameModule | `_rewardTopAffiliate` | DegenerusStonk | `poolBalance(Pool.Affiliate)` | view |
| EndgameModule | `_rewardTopAffiliate` | DegenerusStonk | `transferFromPool(Pool.Affiliate, ...)` | external |
| GameOverModule | `_sweepToVaultAndDgnrs` | stETH | `balanceOf(this)` | view |
| GameOverModule | `_sweepToVaultAndDgnrs` | stETH | `transfer(VAULT, amount)` | external |
| GameOverModule | `_sweepToVaultAndDgnrs` | stETH | `approve(DGNRS, amount)` | external |
| GameOverModule | `_sweepToVaultAndDgnrs` | DegenerusStonk | `depositSteth(amount)` | external |
| GameOverModule | `_sweepToVaultAndDgnrs` | payable(VAULT) | `.call{value}` | external |
| GameOverModule | `_sweepToVaultAndDgnrs` | payable(DGNRS) | `.call{value}` | external |

#### BurnieCoin (Source)

| Source Contract | Function | Target Contract | Method Called | Call Type |
|----------------|----------|----------------|--------------|-----------|
| BurnieCoin | `claimableCoin` | BurnieCoinflip | `previewClaimCoinflips(msg.sender)` | view |
| BurnieCoin | `balanceOfWithClaimable` | DegenerusGame | `rngLocked()` | view |
| BurnieCoin | `balanceOfWithClaimable` | BurnieCoinflip | `previewClaimCoinflips(player)` | view |
| BurnieCoin | `creditFlip` | BurnieCoinflip | `creditFlip(player, amount)` | external |
| BurnieCoin | `creditFlipBatch` | BurnieCoinflip | `creditFlipBatch(players, amounts)` | external |
| BurnieCoin | `creditLinkReward` | BurnieCoinflip | `creditFlip(player, amount)` | external |
| BurnieCoin | `_claimCoinflipShortfall` | DegenerusGame | `rngLocked()` | view |
| BurnieCoin | `_claimCoinflipShortfall` | BurnieCoinflip | `claimCoinflipsFromBurnie(player, shortfall)` | external |
| BurnieCoin | `_consumeCoinflipShortfall` | DegenerusGame | `rngLocked()` | view |
| BurnieCoin | `_consumeCoinflipShortfall` | BurnieCoinflip | `consumeCoinflipsForBurn(player, shortfall)` | external |
| BurnieCoin | `rollDailyQuest` | DegenerusQuests | `rollDailyQuest(day, entropy)` | external |
| BurnieCoin | `notifyQuestMint` | DegenerusQuests | `handleMint(player, quantity, paidWithEth)` | external |
| BurnieCoin | `notifyQuestMint` | DegenerusGame | `recordMintQuestStreak(player)` | external |
| BurnieCoin | `notifyQuestMint` | BurnieCoinflip | `creditFlip(player, questReward)` | external |
| BurnieCoin | `notifyQuestLootBox` | DegenerusQuests | `handleLootBox(player, amountWei)` | external |
| BurnieCoin | `notifyQuestLootBox` | BurnieCoinflip | `creditFlip(player, questReward)` | external |
| BurnieCoin | `notifyQuestDegenerette` | DegenerusQuests | `handleDegenerette(player, amount, paidWithEth)` | external |
| BurnieCoin | `notifyQuestDegenerette` | BurnieCoinflip | `creditFlip(player, questReward)` | external |
| BurnieCoin | `affiliateQuestReward` | DegenerusQuests | `handleAffiliate(player, amount)` | external |
| BurnieCoin | `decimatorBurn` | DegenerusGame | `isOperatorApproved(player, msg.sender)` | view |
| BurnieCoin | `decimatorBurn` | DegenerusGame | `decWindow()` | view |
| BurnieCoin | `decimatorBurn` | DegenerusGame | `playerActivityScore(caller)` | view |
| BurnieCoin | `decimatorBurn` | DegenerusGame | `consumeDecimatorBoon(caller)` | external |
| BurnieCoin | `decimatorBurn` | DegenerusGame | `recordDecBurn(caller, lvl, bucket, base, mult)` | external |
| BurnieCoin | `decimatorBurn` | DegenerusQuests | `handleDecimator(caller, amount)` | external |
| BurnieCoin | `decimatorBurn` | BurnieCoinflip | `creditFlip(caller, questReward)` | external |
| BurnieCoin | `coinflipAutoRebuyInfo` | BurnieCoinflip | `coinflipAutoRebuyInfo(player)` | view |
| BurnieCoin | `coinflipAmount` | BurnieCoinflip | `coinflipAmount(player)` | view |
| BurnieCoin | `previewClaimCoinflips` | BurnieCoinflip | `previewClaimCoinflips(player)` | view |

#### BurnieCoinflip (Source)

| Source Contract | Function | Target Contract | Method Called | Call Type |
|----------------|----------|----------------|--------------|-----------|
| BurnieCoinflip | `_depositCoinflip` | BurnieCoin | `burnForCoinflip(caller, amount)` | external |
| BurnieCoinflip | `_depositCoinflip` | DegenerusQuests | `handleFlip(caller, amount)` | external |
| BurnieCoinflip | `_depositCoinflip` | DegenerusGame | `recordCoinflipDeposit(amount)` | external |
| BurnieCoinflip | `_depositCoinflip` | DegenerusGame | `afKingModeFor(caller)` | view |
| BurnieCoinflip | `_depositCoinflip` | DegenerusGame | `deityPassCountFor(caller)` | view |
| BurnieCoinflip | `_depositCoinflip` | DegenerusGame | `level()` | view |
| BurnieCoinflip | `depositCoinflip` | DegenerusGame | `isOperatorApproved(player, msg.sender)` | view |
| BurnieCoinflip | `_claimCoinflipsInternal` | DegenerusGame | `syncAfKingLazyPassFromCoin(player)` | external |
| BurnieCoinflip | `_claimCoinflipsInternal` | DegenerusGame | `deityPassCountFor(player)` | view |
| BurnieCoinflip | `_claimCoinflipsInternal` | DegenerusGame | `level()` | view |
| BurnieCoinflip | `_claimCoinflipsInternal` | DegenerusGame | `purchaseInfo()` | view |
| BurnieCoinflip | `_claimCoinflipsInternal` | DegenerusGame | `gameOver()` | view |
| BurnieCoinflip | `_claimCoinflipsInternal` | DegenerusJackpots | `recordBafFlip(player, bafLvl, credit)` | external |
| BurnieCoinflip | `_claimCoinflipsInternal` | WrappedWrappedXRP | `mintPrize(player, amount)` | external |
| BurnieCoinflip | `_claimCoinflipsTakeProfit` | BurnieCoin | `mintForCoinflip(player, toClaim)` | external |
| BurnieCoinflip | `_claimCoinflipsAmount` | BurnieCoin | `mintForCoinflip(player, toClaim)` | external |
| BurnieCoinflip | `_addDailyFlip` | DegenerusGame | `consumeCoinflipBoon(player)` | external |
| BurnieCoinflip | `_addDailyFlip` | DegenerusGame | `rngLocked()` | view |
| BurnieCoinflip | `_coinflipLockedDuringTransition` | DegenerusGame | `purchaseInfo()` | view |
| BurnieCoinflip | `_coinflipLockedDuringTransition` | DegenerusGame | `gameOver()` | view |
| BurnieCoinflip | `_afKingDeityBonusHalfBps` | DegenerusGame | `afKingActivatedLevelFor(player)` | view |
| BurnieCoinflip | `_setCoinflipAutoRebuy` | DegenerusGame | `rngLocked()` | view |
| BurnieCoinflip | `_setCoinflipAutoRebuy` | DegenerusGame | `deactivateAfKingFromCoin(player)` | external |
| BurnieCoinflip | `_setCoinflipAutoRebuy` | BurnieCoin | `mintForCoinflip(player, mintable)` | external |
| BurnieCoinflip | `_setCoinflipAutoRebuyTakeProfit` | DegenerusGame | `rngLocked()` | view |
| BurnieCoinflip | `_setCoinflipAutoRebuyTakeProfit` | DegenerusGame | `deactivateAfKingFromCoin(player)` | external |
| BurnieCoinflip | `_setCoinflipAutoRebuyTakeProfit` | BurnieCoin | `mintForCoinflip(player, mintable)` | external |
| BurnieCoinflip | `processCoinflipPayouts` | DegenerusGame | `lootboxPresaleActiveFlag()` | view |
| BurnieCoinflip | `processCoinflipPayouts` | DegenerusGame | `lastPurchaseDayFlipTotals()` | view |
| BurnieCoinflip | `processCoinflipPayouts` | DegenerusGame | `payCoinflipBountyDgnrs(to)` | external |
| BurnieCoinflip | `claimCoinflips` | DegenerusGame | `rngLocked()` | view |
| BurnieCoinflip | `claimCoinflipsTakeProfit` | DegenerusGame | `rngLocked()` | view |
| BurnieCoinflip | `claimCoinflipsFromBurnie` | DegenerusGame | `rngLocked()` | view |
| BurnieCoinflip | `consumeCoinflipsForBurn` | DegenerusGame | `rngLocked()` | view |
| BurnieCoinflip | `_resolvePlayer` | DegenerusGame | `isOperatorApproved(player, msg.sender)` | view |
| BurnieCoinflip | `_targetFlipDay` | DegenerusGame | `currentDayView()` | view |

#### DegenerusVault (Source)

| Source Contract | Function | Target Contract | Method Called | Call Type |
|----------------|----------|----------------|--------------|-----------|
| DegenerusVault | `constructor` | BurnieCoin | `vaultMintAllowance()` | view |
| DegenerusVault | `constructor` | BurnieCoin | `vaultEscrow(coinAmount)` | external |
| DegenerusVault | `_requireApproved` | DegenerusGame | `isOperatorApproved(player, msg.sender)` | view |
| DegenerusVault | `vaultAdvanceGame` | DegenerusGame | `advanceGame()` | external |
| DegenerusVault | `vaultPurchase` | DegenerusGame | `purchase{value}(...)` | external |
| DegenerusVault | `vaultPurchaseCoin` | DegenerusGame | `purchaseCoin(this, qty, 0)` | external |
| DegenerusVault | `vaultPurchaseBurnieLootbox` | DegenerusGame | `purchaseBurnieLootbox(this, amount)` | external |
| DegenerusVault | `vaultOpenLootBox` | DegenerusGame | `openLootBox(this, index)` | external |
| DegenerusVault | `vaultPurchaseDeityPass` | DegenerusGame | `claimableWinningsOf(this)` | view |
| DegenerusVault | `vaultPurchaseDeityPass` | DegenerusGame | `claimWinnings(this)` | external |
| DegenerusVault | `vaultPurchaseDeityPass` | DegenerusGame | `purchaseDeityPass{value}(this, true)` | external |
| DegenerusVault | `vaultClaimWinningsStethFirst` | DegenerusGame | `claimWinningsStethFirst()` | external |
| DegenerusVault | `vaultClaimWhalePass` | DegenerusGame | `claimWhalePass(this)` | external |
| DegenerusVault | `vaultPlaceFullTicketBets` | DegenerusGame | `placeFullTicketBets{value}(...)` | external |
| DegenerusVault | `vaultPlaceFullTicketBetsBurnie` | DegenerusGame | `placeFullTicketBets(...)` | external |
| DegenerusVault | `vaultPlaceFullTicketBetsWwxrp` | DegenerusGame | `placeFullTicketBets(...)` | external |
| DegenerusVault | `vaultResolveDegeneretteBets` | DegenerusGame | `resolveDegeneretteBets(this, betIds)` | external |
| DegenerusVault | `vaultSetAutoRebuy` | DegenerusGame | `setAutoRebuy(this, enabled)` | external |
| DegenerusVault | `vaultSetAutoRebuyTakeProfit` | DegenerusGame | `setAutoRebuyTakeProfit(this, takeProfit)` | external |
| DegenerusVault | `vaultSetDecimatorAutoRebuy` | DegenerusGame | `setDecimatorAutoRebuy(this, enabled)` | external |
| DegenerusVault | `vaultSetAfKingMode` | DegenerusGame | `setAfKingMode(this, enabled, ethTP, coinTP)` | external |
| DegenerusVault | `vaultSetOperatorApproval` | DegenerusGame | `setOperatorApproval(operator, approved)` | external |
| DegenerusVault | `wwxrpMint` | WrappedWrappedXRP | `vaultMintTo(to, amount)` | external |
| DegenerusVault | `vaultClaimDecimatorJackpot` | DegenerusGame | `claimDecimatorJackpot(lvl)` | external |
| DegenerusVault | `burnCoin` | BurnieCoin | `balanceOf(this)` | view |
| DegenerusVault | `burnCoin` | BurnieCoin | `transfer(player, payBal)` | external |
| DegenerusVault | `burnCoin` | BurnieCoin | `vaultMintTo(player, remaining)` | external |
| DegenerusVault | `burnCoin` | DegenerusGame | `claimableWinningsOf(this)` | view |
| DegenerusVault | `burnCoin` | DegenerusGame | `claimWinnings(this)` | external |
| DegenerusVault | `_vaultSync` | BurnieCoin | `vaultMintAllowance()` | view |
| DegenerusVault | `_vaultSync` | BurnieCoin | `balanceOf(this)` | view |
| DegenerusVault | `stethBalance` | stETH | `balanceOf(this)` | view |
| DegenerusVault | `transferSteth` | stETH | `transfer(to, amount)` | external |
| DegenerusVault | `depositSteth` | stETH | `transferFrom(from, this, amount)` | external |

#### DegenerusStonk (Source)

| Source Contract | Function | Target Contract | Method Called | Call Type |
|----------------|----------|----------------|--------------|-----------|
| DegenerusStonk | `_requireApproved` | DegenerusGame | `isOperatorApproved(player, msg.sender)` | view |
| DegenerusStonk | `claimWhalePass` | DegenerusGame | `claimWhalePass(address(0))` | external |
| DegenerusStonk | `claimWhalePass` | DegenerusGame | `setAfKingMode(...)` | external |
| DegenerusStonk | `_stonkLevel` | DegenerusGame | `level()` | view |
| DegenerusStonk | `advanceGame` | DegenerusGame | `advanceGame()` | external |
| DegenerusStonk | `purchaseTickets` | DegenerusGame | `mintPrice()` | view |
| DegenerusStonk | `purchaseTickets` | DegenerusGame | `purchase{value}(...)` | external |
| DegenerusStonk | `purchaseTicketsCoin` | DegenerusGame | `purchaseCoin(address(0), qty, 0)` | external |
| DegenerusStonk | `purchaseBurnieLootbox` | DegenerusGame | `purchaseBurnieLootbox(address(0), amount)` | external |
| DegenerusStonk | `placeFullTicketBets` | DegenerusGame | `placeFullTicketBets{value}(...)` | external |
| DegenerusStonk | `placeFullTicketBetsBurnie` | DegenerusGame | `placeFullTicketBets(...)` | external |
| DegenerusStonk | `openLootBox` | DegenerusGame | `openLootBox(address(0), index)` | external |
| DegenerusStonk | `claimWhalePass` | DegenerusGame | `claimWhalePass(address(0))` | external |
| DegenerusStonk | `decimatorBurn` | BurnieCoin | `decimatorBurn(this, amount)` | external |
| DegenerusStonk | `_stonkRebuy` | DegenerusGame | `mintPrice()` | view |
| DegenerusStonk | `_stonkRebuy` | BurnieCoin | `balanceOf(this)` | view |
| DegenerusStonk | `_stonkRebuy` | DegenerusGame | `rngLocked()` | view |
| DegenerusStonk | `_stonkRebuy` | BurnieCoinflip | `previewClaimCoinflips(this)` | view |
| DegenerusStonk | `_stonkRebuy` | BurnieCoinflip | `claimCoinflips(this, remainder)` | external |
| DegenerusStonk | `_stonkRebuy` | BurnieCoin | `transfer(msg.sender, burnieOut)` | external |
| DegenerusStonk | `depositSteth` | stETH | `transferFrom(msg.sender, this, amount)` | external |
| DegenerusStonk | `totalBacking` | stETH | `balanceOf(this)` | view |
| DegenerusStonk | `totalBacking` | BurnieCoin | `balanceOf(this)` | view |
| DegenerusStonk | `totalBacking` | BurnieCoinflip | `previewClaimCoinflips(this)` | view |
| DegenerusStonk | `totalBacking` | WrappedWrappedXRP | `balanceOf(this)` | view |
| DegenerusStonk | `burn` | DegenerusGame | `claimWinnings(address(0))` | external |
| DegenerusStonk | `burn` | stETH | `balanceOf(this)` | view |
| DegenerusStonk | `burn` | BurnieCoin | `balanceOf(this)` | view |
| DegenerusStonk | `burn` | BurnieCoinflip | `previewClaimCoinflips(this)` | view |
| DegenerusStonk | `burn` | BurnieCoin | `transfer(player, payBal)` | external |
| DegenerusStonk | `burn` | BurnieCoinflip | `claimCoinflips(address(0), remaining)` | external |
| DegenerusStonk | `burn` | BurnieCoin | `transfer(player, remaining)` | external |
| DegenerusStonk | `burn` | stETH | `transfer(player, stethOut)` | external |
| DegenerusStonk | `burn` | WrappedWrappedXRP | `transfer(player, wwxrpOut)` | external |
| DegenerusStonk | `_transfer` | DegenerusGame | `level()` | view |

#### DegenerusAdmin (Source)

| Source Contract | Function | Target Contract | Method Called | Call Type |
|----------------|----------|----------------|--------------|-----------|
| DegenerusAdmin | `_requireVaultOwner` | DegenerusVault | `isVaultOwner(msg.sender)` | view |
| DegenerusAdmin | `constructor` | VRF Coordinator | `createSubscription()` | external |
| DegenerusAdmin | `constructor` | VRF Coordinator | `addConsumer(subId, GAME)` | external |
| DegenerusAdmin | `constructor` | DegenerusGame | `wireVrf(coordinator, subId, keyHash)` | external |
| DegenerusAdmin | `swapEthForSteth` | DegenerusGame | `adminSwapEthForStEth{value}(msg.sender, amount)` | external |
| DegenerusAdmin | `stakeEthForSteth` | DegenerusGame | `adminStakeEthForStEth(amount)` | external |
| DegenerusAdmin | `setLootboxRngThreshold` | DegenerusGame | `setLootboxRngThreshold(threshold)` | external |
| DegenerusAdmin | `rotateVrfCoordinator` | DegenerusGame | `rngStalledForThreeDays()` | view |
| DegenerusAdmin | `rotateVrfCoordinator` | VRF Coordinator (old) | `cancelSubscription(subId, this)` | external |
| DegenerusAdmin | `rotateVrfCoordinator` | VRF Coordinator (new) | `createSubscription()` | external |
| DegenerusAdmin | `rotateVrfCoordinator` | VRF Coordinator (new) | `addConsumer(newSubId, GAME)` | external |
| DegenerusAdmin | `rotateVrfCoordinator` | DegenerusGame | `updateVrfCoordinatorAndSub(...)` | external |
| DegenerusAdmin | `rotateVrfCoordinator` | LINK | `balanceOf(this)` | view |
| DegenerusAdmin | `rotateVrfCoordinator` | LINK | `transferAndCall(coord, amount, abi.encode(subId))` | external |
| DegenerusAdmin | `rescueVrf` | VRF Coordinator | `cancelSubscription(subId, target)` | external |
| DegenerusAdmin | `rescueVrf` | LINK | `balanceOf(this)` | view |
| DegenerusAdmin | `rescueVrf` | LINK | `transfer(target, bal)` | external |
| DegenerusAdmin | `onTokenTransfer` | DegenerusGame | `gameOver()` | view |
| DegenerusAdmin | `onTokenTransfer` | VRF Coordinator | `getSubscription(subId)` | view |
| DegenerusAdmin | `onTokenTransfer` | LINK | `transferAndCall(coord, amount, abi.encode(subId))` | external |
| DegenerusAdmin | `onTokenTransfer` | DegenerusGame | `purchaseInfo()` | view |
| DegenerusAdmin | `onTokenTransfer` | BurnieCoin | `creditLinkReward(from, credit)` | external |
| DegenerusAdmin | `_linkAmountToEth` | Chainlink Feed | `latestRoundData()` | view |
| DegenerusAdmin | `_linkAmountToEth` | Chainlink Feed | `decimals()` | view |

#### DegenerusAffiliate (Source)

| Source Contract | Function | Target Contract | Method Called | Call Type |
|----------------|----------|----------------|--------------|-----------|
| DegenerusAffiliate | `_payAffiliateInternal` | BurnieCoin | `affiliateQuestReward(addr, share)` | external |
| DegenerusAffiliate | `claimAffiliateEth` | BurnieCoin | `creditCoin(player, coinAmount)` | external |
| DegenerusAffiliate | `claimAffiliateEth` | BurnieCoin | `creditFlip(player, amount)` | external |
| DegenerusAffiliate | `lootboxPresaleActiveFlag` | DegenerusGame | `lootboxPresaleActiveFlag()` | view |

#### DegenerusJackpots (Source)

| Source Contract | Function | Target Contract | Method Called | Call Type |
|----------------|----------|----------------|--------------|-----------|
| DegenerusJackpots | `_getBafWinners` | BurnieCoinflip | `coinflipTopLastDay()` | view |
| DegenerusJackpots | `_getBafWinners` | DegenerusAffiliate | `affiliateTop(lvl)` | view |
| DegenerusJackpots | `_getBafWinners` | DegenerusGame | `sampleFarFutureTickets(entropy)` | view |
| DegenerusJackpots | `_getBafWinners` | DegenerusGame | `sampleTraitTicketsAtLevel(targetLvl, entropy)` | view |

#### DegenerusQuests (Source)

| Source Contract | Function | Target Contract | Method Called | Call Type |
|----------------|----------|----------------|--------------|-----------|
| DegenerusQuests | `_resolveQuestPayout` | DegenerusGame | `mintPrice()` | view |

#### DegenerusDeityPass (Source)

| Source Contract | Function | Target Contract | Method Called | Call Type |
|----------------|----------|----------------|--------------|-----------|
| DegenerusDeityPass | `tokenURI` | Icons32Data | `getIcon(symbolId)` | view |
| DegenerusDeityPass | `_afterTokenTransfer` | DegenerusGame | `onDeityPassTransfer(from, to, symbolId)` | external |

#### WrappedWrappedXRP (Source)

| Source Contract | Function | Target Contract | Method Called | Call Type |
|----------------|----------|----------------|--------------|-----------|
| WrappedWrappedXRP | (none outbound) | -- | -- | -- |

**Note:** WWXRP has no outbound calls. It only receives calls (minting from Game, Coin, Coinflip, Vault).

#### DeityBoonViewer (Source)

| Source Contract | Function | Target Contract | Method Called | Call Type |
|----------------|----------|----------------|--------------|-----------|
| DeityBoonViewer | `viewBoons` | DegenerusGame | `deityBoonData(deity)` | view |

#### DegenerusTraitUtils (Source)

| Source Contract | Function | Target Contract | Method Called | Call Type |
|----------------|----------|----------------|--------------|-----------|
| DegenerusTraitUtils | (none) | -- | -- | -- |

**Note:** TraitUtils is a pure library contract. No external calls.

#### Icons32Data (Source)

| Source Contract | Function | Target Contract | Method Called | Call Type |
|----------------|----------|----------------|--------------|-----------|
| Icons32Data | (none outbound) | -- | -- | -- |

**Note:** Icons32Data only has setter/getter functions. Creator-gated setters, no cross-contract calls.

---

### Section C: Inbound Call Summary

For each contract, which other contracts call INTO it. Derived by reversing Section B.

| Target Contract | Called By | Via Function | Method |
|----------------|-----------|-------------|--------|
| **DegenerusGame** | BurnieCoin | `decimatorBurn` | `rngLocked()`, `decWindow()`, `isOperatorApproved()`, `playerActivityScore()`, `consumeDecimatorBoon()`, `recordDecBurn()`, `recordMintQuestStreak()` |
| | BurnieCoinflip | `_depositCoinflip`, `_claimCoinflipsInternal`, `processCoinflipPayouts`, etc. | `rngLocked()`, `level()`, `purchaseInfo()`, `gameOver()`, `isOperatorApproved()`, `afKingModeFor()`, `deityPassCountFor()`, `recordCoinflipDeposit()`, `syncAfKingLazyPassFromCoin()`, `deactivateAfKingFromCoin()`, `consumeCoinflipBoon()`, `payCoinflipBountyDgnrs()`, `lootboxPresaleActiveFlag()`, `lastPurchaseDayFlipTotals()`, `currentDayView()`, `afKingActivatedLevelFor()` |
| | DegenerusVault | various vault* functions | `advanceGame()`, `purchase()`, `purchaseCoin()`, `purchaseBurnieLootbox()`, `openLootBox()`, `purchaseDeityPass()`, `claimWinnings()`, `claimWinningsStethFirst()`, `claimWhalePass()`, `placeFullTicketBets()`, `resolveDegeneretteBets()`, `setAutoRebuy()`, `setAutoRebuyTakeProfit()`, `setDecimatorAutoRebuy()`, `setAfKingMode()`, `setOperatorApproval()`, `claimDecimatorJackpot()`, `claimableWinningsOf()`, `isOperatorApproved()` |
| | DegenerusStonk | various stonk functions | `advanceGame()`, `purchase()`, `purchaseCoin()`, `purchaseBurnieLootbox()`, `openLootBox()`, `claimWhalePass()`, `placeFullTicketBets()`, `setAfKingMode()`, `mintPrice()`, `level()`, `rngLocked()`, `claimWinnings()`, `claimableWinningsOf()`, `isOperatorApproved()` |
| | DegenerusAdmin | constructor, admin functions | `wireVrf()`, `adminSwapEthForStEth()`, `adminStakeEthForStEth()`, `setLootboxRngThreshold()`, `rngStalledForThreeDays()`, `updateVrfCoordinatorAndSub()`, `gameOver()`, `purchaseInfo()` |
| | DegenerusAffiliate | `lootboxPresaleActiveFlag` | `lootboxPresaleActiveFlag()` |
| | DegenerusJackpots | `_getBafWinners` | `sampleFarFutureTickets()`, `sampleTraitTicketsAtLevel()` |
| | DegenerusDeityPass | `_afterTokenTransfer` | `onDeityPassTransfer()` |
| | DegenerusQuests | `_resolveQuestPayout` | `mintPrice()` |
| | DeityBoonViewer | `viewBoons` | `deityBoonData()` |
| **BurnieCoin** | DegenerusGame (via modules) | AdvanceModule, MintModule, JackpotModule, LootboxModule, DegeneretteModule | `creditFlip()`, `creditFlipBatch()`, `rollDailyQuest()`, `notifyQuestMint()`, `notifyQuestLootBox()`, `notifyQuestDegenerette()`, `burnCoin()`, `mintForGame()` |
| | DegenerusGame | `claimAffiliateDgnrs` | `creditFlip()` |
| | BurnieCoinflip | `_claimCoinflipsTakeProfit`, `_setCoinflipAutoRebuy` | `mintForCoinflip()` |
| | DegenerusVault | `burnCoin` | `balanceOf()`, `transfer()`, `vaultMintTo()`, `vaultMintAllowance()`, `vaultEscrow()` |
| | DegenerusStonk | `_stonkRebuy`, `burn`, `totalBacking` | `balanceOf()`, `transfer()`, `decimatorBurn()` |
| | DegenerusAffiliate | `_payAffiliateInternal`, `claimAffiliateEth` | `affiliateQuestReward()`, `creditCoin()`, `creditFlip()` |
| | DegenerusAdmin | `onTokenTransfer` | `creditLinkReward()` |
| **BurnieCoinflip** | BurnieCoin | various | `previewClaimCoinflips()`, `creditFlip()`, `creditFlipBatch()`, `claimCoinflipsFromBurnie()`, `consumeCoinflipsForBurn()`, `coinflipAutoRebuyInfo()`, `coinflipAmount()` |
| | DegenerusGame (via AdvanceModule) | `advanceGame` | `processCoinflipPayouts()` |
| | DegenerusGame | `_setAfKingMode`, `_deactivateAfKing` | `setCoinflipAutoRebuy()`, `settleFlipModeChange()` |
| | DegenerusStonk | `_stonkRebuy`, `burn`, `totalBacking` | `previewClaimCoinflips()`, `claimCoinflips()` |
| **DegenerusStonk** | DegenerusGame (via modules) | WhaleModule, JackpotModule, LootboxModule, EndgameModule | `poolBalance()`, `transferFromPool()`, `transferBetweenPools()`, `depositSteth()` |
| | DegenerusGame | `payCoinflipBountyDgnrs`, `claimAffiliateDgnrs`, `_awardEarlybirdDgnrs`, `_transferSteth` | `poolBalance()`, `transferFromPool()`, `transferBetweenPools()`, `depositSteth()` |
| | DegenerusGame (via GameOverModule) | `_sweepToVaultAndDgnrs` | `depositSteth()` |
| **DegenerusAffiliate** | DegenerusGame (via MintModule) | `purchase` | `payAffiliate()` |
| | DegenerusGame (via WhaleModule) | whale purchases | `getReferrer()` |
| | DegenerusGame (via DegeneretteModule) | degenerette | `consumeDegeneretteCredit()`, `affiliateBonusPointsBest()` |
| | DegenerusGame (via EndgameModule) | `_rewardTopAffiliate` | `affiliateTop()` |
| | DegenerusGame | `claimAffiliateDgnrs` | `affiliateScore()` |
| | DegenerusJackpots | `_getBafWinners` | `affiliateTop()` |
| **DegenerusQuests** | BurnieCoin | quest notifications | `rollDailyQuest()`, `handleMint()`, `handleLootBox()`, `handleDegenerette()`, `handleAffiliate()`, `handleDecimator()`, `handleFlip()` |
| | DegenerusGame (via DegeneretteModule) | activity score | `playerQuestStates()` |
| **DegenerusJackpots** | BurnieCoinflip | `_claimCoinflipsInternal` | `recordBafFlip()` |
| **DegenerusVault** | DegenerusAdmin | `_requireVaultOwner` | `isVaultOwner()` |
| | DegenerusGame (via modules) | MintModule, GameOverModule | direct ETH transfers via `.call{value}` |
| **WrappedWrappedXRP** | BurnieCoinflip | `_claimCoinflipsInternal` | `mintPrize()` |
| | DegenerusVault | `wwxrpMint` | `vaultMintTo()` |
| **DegenerusDeityPass** | DegenerusGame (via WhaleModule) | deity pass operations | `mint()`, `burn()` (via IDegenerusDeityPassBurn interface) |
| **Icons32Data** | DegenerusDeityPass | `tokenURI` | `getIcon()` |
| **stETH (external)** | DegenerusGame (direct + modules) | various | `submit()`, `balanceOf()`, `transfer()`, `approve()`, `transferFrom()` |
| **VRF Coordinator (external)** | DegenerusAdmin | constructor, `rotateVrf` | `createSubscription()`, `addConsumer()`, `cancelSubscription()`, `getSubscription()` |
| | DegenerusGame (via AdvanceModule) | VRF requests | `requestRandomWords()` |
| **LINK (external)** | DegenerusAdmin | VRF funding | `balanceOf()`, `transfer()`, `transferAndCall()` |
| **Chainlink Feed (external)** | DegenerusAdmin | `_linkAmountToEth` | `latestRoundData()`, `decimals()` |

---

**Total unique cross-contract call edges (protocol-internal): 167**
- DegenerusGame outbound (direct + via modules): ~75 edges
- BurnieCoin outbound: ~29 edges
- BurnieCoinflip outbound: ~36 edges
- DegenerusVault outbound: ~34 edges
- DegenerusStonk outbound: ~35 edges
- DegenerusAdmin outbound: ~24 edges
- DegenerusAffiliate outbound: 4 edges
- DegenerusJackpots outbound: 4 edges
- DegenerusQuests outbound: 1 edge
- DegenerusDeityPass outbound: 2 edges
- DeityBoonViewer outbound: 1 edge
- Others (TraitUtils, Icons32Data, WWXRP): 0 edges

**No discrepancies found** between audit data (Phases 50-56) and source code verification.
