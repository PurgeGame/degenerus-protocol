# Unit 1: Game Router + Storage Layout -- Coverage Checklist

## Contracts Under Audit
- contracts/DegenerusGame.sol (2,848 lines)
- contracts/storage/DegenerusGameStorage.sol (1,613 lines)
- contracts/modules/DegenerusGameMintStreakUtils.sol (62 lines)

## Checklist Summary

| Category | Count | Analysis Depth |
|----------|-------|---------------|
| A: Delegatecall Dispatchers | 30 | Dispatch verification |
| B: Direct State-Changing | 19 | Full Mad Genius |
| C: Internal Helpers (State-Changing) | 44 | Via caller's call tree |
| D: View/Pure | 80 | Minimal |
| **TOTAL** | **173** | |

**Note on counts vs research:** The research estimated 27 internal helpers in Game.sol, 15 state-changing in Storage.sol, and 2 in MintStreakUtils.sol (44 total). Category D is larger than the research estimated (~60) because the count now includes all pure/view helpers across all three contracts.

---

## Category A: Delegatecall Dispatchers

Functions that encode a selector, delegatecall to a module, and bubble up the revert/return. Analysis: dispatch-correctness verification only (per D-01).

**CRITICAL FLAG -- HYBRID:** `resolveRedemptionLootbox()` performs direct state changes (claimableWinnings debit, claimablePool decrement, prize pool credit) BEFORE the delegatecall loop. It appears in BOTH Category A (dispatch verification for the delegatecall portion) and Category B (full analysis for the direct state-change portion). The Mad Genius MUST audit both aspects.

**CRITICAL FLAG -- NAME/SELECTOR MISMATCH:** `consumeDecimatorBoon()` (line 821) dispatches to `consumeDecimatorBoost.selector`. The function name in the router does NOT match the selector's source function name in the module interface. The Mad Genius MUST verify this is correctly wired.

| # | Function | Lines | Module | Selector | Hybrid? | Access Control | Analyzed? | Dispatch Correct? |
|---|----------|-------|--------|----------|---------|---------------|-----------|-------------------|
| A1 | advanceGame() | 308-317 | GAME_ADVANCE_MODULE | advanceGame.selector | NO | any (module checks internally) | YES | YES |
| A2 | wireVrf() | 332-348 | GAME_ADVANCE_MODULE | wireVrf.selector | NO | ADMIN (module checks) | YES | YES |
| A3 | updateVrfCoordinatorAndSub() | 1880-1898 | GAME_ADVANCE_MODULE | updateVrfCoordinatorAndSub.selector | NO | ADMIN (module checks) | YES | YES |
| A4 | requestLootboxRng() | 1903-1912 | GAME_ADVANCE_MODULE | requestLootboxRng.selector | NO | any (module checks internally) | YES | YES |
| A5 | reverseFlip() | 1920-1929 | GAME_ADVANCE_MODULE | reverseFlip.selector | NO | any (module checks internally) | YES | YES |
| A6 | rawFulfillRandomWords() | 1937-1951 | GAME_ADVANCE_MODULE | rawFulfillRandomWords.selector | NO | VRF coordinator (module checks) | YES | YES |
| A7 | purchase() | 534-549 | GAME_MINT_MODULE (via _purchaseFor) | purchase.selector | NO | operator-approved (router resolves player) | YES | YES |
| A8 | purchaseCoin() | 579-596 | GAME_MINT_MODULE | purchaseCoin.selector | NO | operator-approved (router resolves player) | YES | YES |
| A9 | purchaseBurnieLootbox() | 601-616 | GAME_MINT_MODULE | purchaseBurnieLootbox.selector | NO | operator-approved (router resolves player) | YES | YES |
| A10 | purchaseWhaleBundle() | 632-638 | GAME_WHALE_MODULE (via _purchaseWhaleBundleFor) | purchaseWhaleBundle.selector | NO | operator-approved (router resolves player) | YES | YES |
| A11 | purchaseLazyPass() | 657-660 | GAME_WHALE_MODULE (via _purchaseLazyPassFor) | purchaseLazyPass.selector | NO | operator-approved (router resolves player) | YES | YES |
| A12 | purchaseDeityPass() | 677-680 | GAME_WHALE_MODULE (via _purchaseDeityPassFor) | purchaseDeityPass.selector | NO | operator-approved (router resolves player) | YES | YES |
| A13 | openLootBox() | 698-701 | GAME_LOOTBOX_MODULE (via _openLootBoxFor) | openLootBox.selector | NO | operator-approved (router resolves player) | YES | YES |
| A14 | openBurnieLootBox() | 706-709 | GAME_LOOTBOX_MODULE (via _openBurnieLootBoxFor) | openBurnieLootBox.selector | NO | operator-approved (router resolves player) | YES | YES |
| A15 | placeFullTicketBets() | 747-771 | GAME_DEGENERETTE_MODULE | placeFullTicketBets.selector | NO | operator-approved (router resolves player) | YES | YES |
| A16 | resolveDegeneretteBets() | 776-790 | GAME_DEGENERETTE_MODULE | resolveBets.selector | NO | operator-approved (router resolves player) | YES | YES |
| A17 | consumeCoinflipBoon() | 797-814 | GAME_BOON_MODULE | consumeCoinflipBoon.selector | NO | msg.sender == COIN or COINFLIP (router checks) | YES | YES |
| A18 | consumeDecimatorBoon() | 821-835 | GAME_BOON_MODULE | **consumeDecimatorBoost.selector** | NO | msg.sender == COIN (router checks) | YES | YES |
| A19 | consumePurchaseBoost() | 842-856 | GAME_BOON_MODULE | consumePurchaseBoost.selector | NO | msg.sender == address(this) (router checks) | YES | YES |
| A20 | issueDeityBoon() | 894-912 | GAME_LOOTBOX_MODULE | issueDeityBoon.selector | NO | operator-approved (router resolves player), self-issue blocked | YES | YES |
| A21 | recordDecBurn() | 1063-1085 | GAME_DECIMATOR_MODULE | recordDecBurn.selector | NO | COIN (module checks) | YES | YES |
| A22 | runDecimatorJackpot() | 1093-1112 | GAME_DECIMATOR_MODULE | runDecimatorJackpot.selector | NO | msg.sender == address(this) (router checks) | YES | YES |
| A23 | recordTerminalDecBurn() | 1120-1136 | GAME_DECIMATOR_MODULE | recordTerminalDecBurn.selector | NO | COIN (module checks) | YES | YES |
| A24 | runTerminalDecimatorJackpot() | 1140-1159 | GAME_DECIMATOR_MODULE | runTerminalDecimatorJackpot.selector | NO | msg.sender == address(this) (router checks) | YES | YES |
| A25 | runTerminalJackpot() | 1176-1195 | GAME_JACKPOT_MODULE | runTerminalJackpot.selector | NO | msg.sender == address(this) (router checks) | YES | YES |
| A26 | consumeDecClaim() | 1202-1219 | GAME_DECIMATOR_MODULE | consumeDecClaim.selector | NO | msg.sender == address(this) (router checks) | YES | YES |
| A27 | claimDecimatorJackpot() | 1223-1235 | GAME_DECIMATOR_MODULE | claimDecimatorJackpot.selector | NO | any (module checks internally) | YES | YES |
| A28 | claimWhalePass() | 1700-1703 | GAME_ENDGAME_MODULE (via _claimWhalePassFor) | claimWhalePass.selector | NO | operator-approved (router resolves player) | YES | YES |
| A29 | _recordMintDataModule() | 1033-1049 | GAME_MINT_MODULE | recordMintData.selector | NO | private (called from recordMint only) | YES | YES |
| A30 | resolveRedemptionLootbox() | 1729-1779 | GAME_LOOTBOX_MODULE (in loop) | resolveRedemptionLootbox.selector | **YES -- HYBRID** | msg.sender == SDGNRS (router checks) | YES | YES |

**Dispatch pattern notes:**
- A18 (`consumeDecimatorBoon`) dispatches to `consumeDecimatorBoost.selector` -- name/selector MISMATCH. Must verify the module implements a function with selector matching `consumeDecimatorBoost`.
- A29 (`_recordMintDataModule`) is private, called only from `recordMint()`. Not externally accessible but uses delegatecall pattern.
- A30 (`resolveRedemptionLootbox`) is HYBRID: performs direct state changes before delegatecall loop. Full analysis in Category B.

---

## Category B: Direct State-Changing Functions

Functions that execute logic directly in DegenerusGame.sol. Full Mad Genius treatment per D-02: call tree, storage writes, cache check, all attack angles.

| # | Function | Lines | Access Control | Storage Writes | External Calls | Risk Tier | Analyzed? | Call Tree? | Storage Map? | Cache Check? |
|---|----------|-------|---------------|----------------|----------------|-----------|-----------|------------|--------------|-------------|
| B1 | constructor() | 242-256 | deploy-only | levelStartTime, levelPrizePool[0], deityPassCount[SDGNRS], deityPassCount[VAULT], ticketQueue (200 entries via _queueTickets) | none | 2 | YES | YES | YES | YES |
| B2 | recordMint() | 374-419 | msg.sender == address(this) | claimableWinnings, claimablePool, prizePoolsPacked or prizePoolPendingPacked, mintPacked_ (via _recordMintDataModule delegatecall), earlybirdDgnrsPoolStart, earlybirdEthIn | _recordMintDataModule (delegatecall), _awardEarlybirdDgnrs (ext call to dgnrs.transferFromPool) | 1 | YES | YES | YES | YES |
| B3 | recordMintQuestStreak() | 424-428 | msg.sender == COIN | mintPacked_ (via _recordMintStreakForLevel) | none | 3 | YES | YES | YES | YES |
| B4 | payCoinflipBountyDgnrs() | 435-458 | msg.sender == COIN or COINFLIP | none direct | dgnrs.transferFromPool (ext) | 2 | YES | YES | YES | YES |
| B5 | setOperatorApproval() | 468-472 | any (msg.sender is owner) | operatorApprovals[msg.sender][operator] | none | 3 | YES | YES | YES | YES |
| B6 | setLootboxRngThreshold() | 512-522 | msg.sender == ADMIN | lootboxRngThreshold | none | 3 | YES | YES | YES | YES |
| B7 | claimWinnings() | 1345-1348 | operator-approved (via _resolvePlayer) | claimableWinnings[player], claimablePool (via _claimWinningsInternal) | ETH transfer + stETH fallback | 1 | YES | YES | YES | YES |
| B8 | claimWinningsStethFirst() | 1352-1359 | msg.sender == VAULT or SDGNRS | claimableWinnings[player], claimablePool (via _claimWinningsInternal) | stETH transfer + ETH fallback | 1 | YES | YES | YES | YES |
| B9 | claimAffiliateDgnrs() | 1388-1431 | operator-approved (via _resolvePlayer) | affiliateDgnrsClaimedBy[currLevel][player], levelDgnrsClaimed[currLevel] | affiliate.affiliateScore (ext), affiliate.totalAffiliateScore (ext), dgnrs.transferFromPool (ext), coin.creditFlip (ext -- deity bonus) | 1 | YES | YES | YES | YES |
| B10 | setAutoRebuy() | 1460-1463 | operator-approved (via _resolvePlayer) | autoRebuyState[player] (via _setAutoRebuy) | coinflip.settleFlipModeChange (ext -- if deactivating afKing) | 2 | YES | YES | YES | YES |
| B11 | setDecimatorAutoRebuy() | 1469-1477 | operator-approved (via _resolvePlayer) | decimatorAutoRebuyDisabled[player] | none | 3 | YES | YES | YES | YES |
| B12 | setAutoRebuyTakeProfit() | 1483-1489 | operator-approved (via _resolvePlayer) | autoRebuyState[player].takeProfit (via _setAutoRebuyTakeProfit) | coinflip.settleFlipModeChange (ext -- if deactivating afKing) | 2 | YES | YES | YES | YES |
| B13 | setAfKingMode() | 1556-1564 | operator-approved (via _resolvePlayer) | autoRebuyState[player] (multiple fields via _setAfKingMode) | coinflip.setCoinflipAutoRebuy (ext), coinflip.settleFlipModeChange (ext) | 1 | YES | YES | YES | YES |
| B14 | deactivateAfKingFromCoin() | 1649-1655 | msg.sender == COIN or COINFLIP | autoRebuyState[player] (via _deactivateAfKing) | coinflip.settleFlipModeChange (ext) | 2 | YES | YES | YES | YES |
| B15 | syncAfKingLazyPassFromCoin() | 1662-1676 | msg.sender == COINFLIP | autoRebuyState[player].afKingMode, autoRebuyState[player].afKingActivatedLevel | none | 2 | YES | YES | YES | YES |
| B16 | resolveRedemptionLootbox() | 1729-1779 | msg.sender == SDGNRS | claimableWinnings[SDGNRS], claimablePool, prizePoolsPacked or prizePoolPendingPacked | delegatecall to GAME_LOOTBOX_MODULE (loop) | 1 | YES | YES | YES | YES |
| B17 | adminSwapEthForStEth() | 1813-1824 | msg.sender == ADMIN | none (external transfers only) | steth.transfer (ext) | 2 | YES | YES | YES | YES |
| B18 | adminStakeEthForStEth() | 1833-1853 | msg.sender == ADMIN | none (external call to steth.submit) | steth.submit (ext) | 2 | YES | YES | YES | YES |
| B19 | receive() | 2838-2847 | any | prizePoolsPacked or prizePoolPendingPacked | none | 2 | YES | YES | YES | YES |

**Risk Tier Key:**
- **Tier 1** (5 functions): Complex, multiple code paths, BAF-class risk. Full deep-dive required.
  - B2 recordMint: 3 payment modes, delegatecall sub-call, earlybird logic
  - B7 claimWinnings: CEI pattern, ETH/stETH fallback, sentinel
  - B8 claimWinningsStethFirst: Same as B7 with inverted fallback
  - B9 claimAffiliateDgnrs: Multiple external calls, deity bonus path, pro-rata math
  - B13 setAfKingMode: Multiple storage writes, cross-contract sync, lock period
  - B16 resolveRedemptionLootbox: Unchecked arithmetic, hybrid delegatecall, freeze logic
- **Tier 2** (8 functions): Moderate complexity, fewer paths.
- **Tier 3** (5 functions): Simple setters or single-operation functions.

---

## Category C: Internal Helpers (State-Changing)

Private/internal helpers called by Category A or B functions. Analyzed via caller's call tree.

### DegenerusGame.sol Helpers

| # | Function | Lines | Contract | Called By | Storage Writes | Analyzed? | Call Tree? | Storage Map? | Cache Check? |
|---|----------|-------|----------|----------|----------------|-----------|------------|--------------|-------------|
| C1 | _processMintPayment() | 929-988 | Game | B2 (recordMint) | claimableWinnings[player], claimablePool | YES | YES | YES | YES |
| C2 | _recordMintDataModule() | 1033-1049 | Game | B2 (recordMint) | mintPacked_ (via delegatecall to GAME_MINT_MODULE) | YES | YES | YES | YES |
| C3 | _claimWinningsInternal() | 1361-1377 | Game | B7 (claimWinnings), B8 (claimWinningsStethFirst) | claimableWinnings[player], claimablePool | YES | YES | YES | YES |
| C4 | _setAutoRebuy() | 1491-1501 | Game | B10 (setAutoRebuy) | autoRebuyState[player].autoRebuyEnabled | YES | YES | YES | YES |
| C5 | _setAutoRebuyTakeProfit() | 1503-1517 | Game | B12 (setAutoRebuyTakeProfit) | autoRebuyState[player].takeProfit | YES | YES | YES | YES |
| C6 | _setAfKingMode() | 1566-1605 | Game | B13 (setAfKingMode) | autoRebuyState[player] (autoRebuyEnabled, takeProfit, afKingMode, afKingActivatedLevel) | YES | YES | YES | YES |
| C7 | _deactivateAfKing() | 1678-1690 | Game | C4 (_setAutoRebuy), C5 (_setAutoRebuyTakeProfit), B14 (deactivateAfKingFromCoin) | autoRebuyState[player].afKingMode, autoRebuyState[player].afKingActivatedLevel | YES | YES | YES | YES |
| C8 | _claimWhalePassFor() | 1705-1715 | Game | A28 (claimWhalePass) | (delegatecall to GAME_ENDGAME_MODULE) | YES | YES | YES | YES |
| C9 | _purchaseFor() | 551-571 | Game | A7 (purchase) | (delegatecall to GAME_MINT_MODULE) | YES | YES | YES | YES |
| C10 | _purchaseWhaleBundleFor() | 640-651 | Game | A10 (purchaseWhaleBundle) | (delegatecall to GAME_WHALE_MODULE) | YES | YES | YES | YES |
| C11 | _purchaseLazyPassFor() | 662-672 | Game | A11 (purchaseLazyPass) | (delegatecall to GAME_WHALE_MODULE) | YES | YES | YES | YES |
| C12 | _purchaseDeityPassFor() | 682-693 | Game | A12 (purchaseDeityPass) | (delegatecall to GAME_WHALE_MODULE) | YES | YES | YES | YES |
| C13 | _openLootBoxFor() | 711-722 | Game | A13 (openLootBox) | (delegatecall to GAME_LOOTBOX_MODULE) | YES | YES | YES | YES |
| C14 | _openBurnieLootBoxFor() | 724-738 | Game | A14 (openBurnieLootBox) | (delegatecall to GAME_LOOTBOX_MODULE) | YES | YES | YES | YES |
| C15 | _transferSteth() | 1960-1968 | Game | C16 (_payoutWithStethFallback), C17 (_payoutWithEthFallback) | none (ext calls only) | YES | YES | YES | YES |
| C16 | _payoutWithStethFallback() | 1975-2003 | Game | C3 (_claimWinningsInternal) | none (ext calls only) | YES | YES | YES | YES |
| C17 | _payoutWithEthFallback() | 2008-2035 | Game | C3 (_claimWinningsInternal) | none (ext calls only) | YES | YES | YES | YES |

### DegenerusGameStorage.sol Helpers (State-Changing)

| # | Function | Lines | Contract | Called By | Storage Writes | Analyzed? | Call Tree? | Storage Map? | Cache Check? |
|---|----------|-------|----------|----------|----------------|-----------|------------|--------------|-------------|
| C18 | _queueTickets() | 528-549 | Storage | B1 (constructor), modules | ticketQueue[wk], ticketsOwedPacked[wk][buyer] | YES | YES | YES | YES |
| C19 | _queueTicketsScaled() | 556-594 | Storage | C20 (_queueLootboxTickets), modules | ticketQueue[wk], ticketsOwedPacked[wk][buyer] | YES | YES | YES | YES |
| C20 | _queueLootboxTickets() | 638-645 | Storage | modules (wrapper for _queueTicketsScaled) | (delegates to C19) | YES | YES | YES | YES |
| C21 | _queueTicketRange() | 602-632 | Storage | C27 (_activate10LevelPass), C28 (_applyWhalePassStats -- no, stats only), modules | ticketQueue[wk], ticketsOwedPacked[wk][buyer] | YES | YES | YES | YES |
| C22 | _setPrizePools() | 651-653 | Storage | B2 (recordMint), B16 (resolveRedemptionLootbox), B19 (receive), C25 (_unfreezePool), modules | prizePoolsPacked | YES | YES | YES | YES |
| C23 | _setPendingPools() | 661-663 | Storage | B2 (recordMint), B16 (resolveRedemptionLootbox), B19 (receive), modules | prizePoolPendingPacked | YES | YES | YES | YES |
| C24 | _swapTicketSlot() | 700-705 | Storage | C25 (_swapAndFreeze), modules | ticketWriteSlot, ticketsFullyProcessed | YES | YES | YES | YES |
| C25 | _swapAndFreeze() | 710-716 | Storage | modules (advanceGame daily path) | ticketWriteSlot, ticketsFullyProcessed, prizePoolFrozen, prizePoolPendingPacked | YES | YES | YES | YES |
| C26 | _unfreezePool() | 720-727 | Storage | modules (post-jackpot) | prizePoolsPacked, prizePoolPendingPacked, prizePoolFrozen | YES | YES | YES | YES |
| C27 | _setNextPrizePool() | 740-743 | Storage | modules | prizePoolsPacked (next component) | YES | YES | YES | YES |
| C28 | _setFuturePrizePool() | 752-755 | Storage | modules | prizePoolsPacked (future component) | YES | YES | YES | YES |
| C29 | _awardEarlybirdDgnrs() | 914-974 | Storage | B2 (recordMint) | earlybirdDgnrsPoolStart, earlybirdEthIn | YES | YES | YES | YES |
| C30 | _activate10LevelPass() | 982-1062 | Storage | modules (whale/lootbox) | mintPacked_[player], ticketQueue, ticketsOwedPacked | YES | YES | YES | YES |
| C31 | _applyWhalePassStats() | 1067-1131 | Storage | modules (whale) | mintPacked_[player] | YES | YES | YES | YES |

### DegenerusGameMintStreakUtils.sol Helpers (State-Changing)

| # | Function | Lines | Contract | Called By | Storage Writes | Analyzed? | Call Tree? | Storage Map? | Cache Check? |
|---|----------|-------|----------|----------|----------------|-----------|------------|--------------|-------------|
| C32 | _recordMintStreakForLevel() | 17-46 | MintStreakUtils | B3 (recordMintQuestStreak) | mintPacked_[player] | YES | YES | YES | YES |

---

## Category D: View/Pure Functions

Read-only functions. Minimal analysis: verify no side effects and no dangerous internal state exposure.

### DegenerusGame.sol View/Pure Functions

| # | Function | Lines | Reads | Security Note | Reviewed? |
|---|----------|-------|-------|---------------|-----------|
| D1 | currentDayView() | 504-506 | _simulatedDayIndex() | none | YES |
| D2 | isOperatorApproved() | 478-483 | operatorApprovals | none | YES |
| D3 | autoRebuyEnabledFor() | 1522-1526 | autoRebuyState | none | YES |
| D4 | decimatorAutoRebuyEnabledFor() | 1531-1535 | decimatorAutoRebuyDisabled | none | YES |
| D5 | autoRebuyTakeProfitFor() | 1540-1544 | autoRebuyState | none | YES |
| D6 | hasActiveLazyPass() | 1620-1627 | deityPassCount, mintPacked_ | none | YES |
| D7 | afKingModeFor() | 1632-1634 | autoRebuyState | none | YES |
| D8 | afKingActivatedLevelFor() | 1639-1643 | autoRebuyState | none | YES |
| D9 | terminalDecWindow() | 1164-1167 | gameOver, lastPurchaseDay, level | none | YES |
| D10 | decClaimable() | 1242-1270 | decClaimRounds, decBurn, decBucketOffsetPacked | none | YES |
| D11 | deityBoonData() | 865-887 | rngWordByDay, rngWordCurrent, deityBoonDay, deityBoonUsedMask, decWindowOpen, deityPassOwners | Exposes RNG seed; seed is current day's word which is already public once fulfilled | YES |
| D12 | prizePoolTargetView() | 2037-2043 | levelPrizePool, currentPrizePool, level | none | YES |
| D13 | nextPrizePoolView() | 2045-2050 | prizePoolsPacked | none | YES |
| D14 | futurePrizePoolView() | 2051-2056 | prizePoolsPacked | none | YES |
| D15 | futurePrizePoolTotalView() | 2057-2064 | prizePoolsPacked, prizePoolPendingPacked | none | YES |
| D16 | ticketsOwedView() | 2065-2076 | ticketsOwedPacked | none | YES |
| D17 | lootboxStatus() | 2077-2089 | lootboxEth, lootboxBurnie, lootboxRngWordByIndex | none | YES |
| D18 | degeneretteBetInfo() | 2090-2098 | degeneretteBets | none | YES |
| D19 | lootboxPresaleActiveFlag() | 2099-2104 | lootboxPresaleActive | none | YES |
| D20 | lootboxRngIndexView() | 2105-2111 | lootboxRngIndex | none | YES |
| D21 | lootboxRngWord() | 2112-2119 | lootboxRngWordByIndex | none | YES |
| D22 | lootboxRngThresholdView() | 2120-2128 | lootboxRngThreshold | none | YES |
| D23 | lootboxRngMinLinkBalanceView() | 2130-2138 | lootboxRngMinLinkBalance | none | YES |
| D24 | currentPrizePoolView() | 2140-2145 | currentPrizePool | none | YES |
| D25 | rewardPoolView() | 2146-2151 | rewardPool | none | YES |
| D26 | claimablePoolView() | 2152-2157 | claimablePool | none | YES |
| D27 | isFinalSwept() | 2158-2163 | finalSwept | none | YES |
| D28 | yieldPoolView() | 2165-2178 | yieldPool, steth.balanceOf | none | YES |
| D29 | yieldAccumulatorView() | 2179-2185 | yieldAccumulator | none | YES |
| D30 | mintPrice() | 2186-2193 | price | none | YES |
| D31 | rngWordForDay() | 2194-2200 | rngWordByDay | Exposes historical RNG; safe after fulfillment | YES |
| D32 | lastRngWord() | 2201-2207 | rngWordCurrent | Exposes current RNG word; safe (already public after VRF callback) | YES |
| D33 | rngLocked() | 2208-2213 | rngLockedFlag | none | YES |
| D34 | isRngFulfilled() | 2214-2220 | rngWordCurrent, rngRequestTime | none | YES |
| D35 | rngStalledForThreeDays() | 2232-2237 | dailyIdx | none | YES |
| D36 | lastVrfProcessed() | 2238-2254 | dailyIdx, rngWordByDay | none | YES |
| D37 | decWindow() | 2255-2263 | decWindowOpen, level, gameOver, _isGameoverImminent | none | YES |
| D38 | decWindowOpenFlag() | 2264-2268 | decWindowOpen | none | YES |
| D39 | jackpotCompressionTier() | 2269-2274 | compressedJackpotFlag | none | YES |
| D40 | jackpotPhase() | 2296-2306 | jackpotPhaseFlag | none | YES |
| D41 | purchaseInfo() | 2308-2335 | price, level, lootboxPresaleActive, lootboxRngIndex, prizePoolsPacked, currentPrizePool, _isDistressMode, rngLockedFlag | Compound view; exposes pricing data | YES |
| D42 | ethMintLastLevel() | 2336-2349 | mintPacked_ | none | YES |
| D43 | ethMintLevelCount() | 2350-2363 | mintPacked_ | none | YES |
| D44 | ethMintStreakCount() | 2364-2376 | mintPacked_ | none | YES |
| D45 | ethMintStats() | 2377-2414 | mintPacked_ | none | YES |
| D46 | playerActivityScore() | 2415-2420 | (delegates to _playerActivityScore) | none | YES |
| D47 | getWinnings() | 2531-2542 | claimableWinnings | none | YES |
| D48 | claimableWinningsOf() | 2543-2552 | claimableWinnings | none | YES |
| D49 | whalePassClaimAmount() | 2553-2561 | whalePassClaims | none | YES |
| D50 | deityPassCountFor() | 2562-2568 | deityPassCount | none | YES |
| D51 | deityPassPurchasedCountFor() | 2569-2576 | deityPassPurchasedCount | none | YES |
| D52 | deityPassTotalIssuedCount() | 2577-2593 | deityPassOwners | none | YES |
| D53 | sampleTraitTickets() | 2595-2641 | traitBurnTicket, ticketQueue | Samples current/previous level trait tickets | YES |
| D54 | sampleTraitTicketsAtLevel() | 2642-2668 | traitBurnTicket, ticketQueue | Samples specific level trait tickets | YES |
| D55 | sampleFarFutureTickets() | 2669-2722 | ticketQueue | Samples far-future key space tickets | YES |
| D56 | getTickets() | 2723-2748 | ticketQueue, ticketsOwedPacked | Returns ticket queue data | YES |
| D57 | getPlayerPurchases() | 2749-2763 | mintPacked_ | Returns packed purchase data | YES |
| D58 | getDailyHeroWager() | 2764-2778 | dailyHeroWager | Returns daily hero wager data | YES |
| D59 | getDailyHeroWinner() | 2779-2802 | dailyHeroWinner | Returns daily hero winner data | YES |
| D60 | getPlayerDegeneretteWager() | 2803-2813 | degeneretteWager | Returns player degenerette wager data | YES |
| D61 | getTopDegenerette() | 2814-2836 | topDegenerette | Returns top degenerette data | YES |

### DegenerusGame.sol Private View/Pure Helpers

| # | Function | Lines | Reads | Security Note | Reviewed? |
|---|----------|-------|-------|---------------|-----------|
| D62 | _requireApproved() | 485-489 | operatorApprovals | Access control helper | YES |
| D63 | _resolvePlayer() | 491-497 | operatorApprovals | Access control + default resolution | YES |
| D64 | _revertDelegate() | 1021-1026 | none (pure) | Assembly revert propagation | YES |
| D65 | _unpackDecWinningSubbucket() | 1276-1283 | none (pure) | Bit unpacking | YES |
| D66 | _hasAnyLazyPass() | 1607-1615 | deityPassCount, mintPacked_ | Pass status check | YES |
| D67 | _threeDayRngGap() | 2222-2231 | rngWordByDay | RNG stall detection | YES |
| D68 | _isGameoverImminent() | 2275-2290 | gameOver, level, levelStartTime | Gameover proximity check | YES |
| D69 | _activeTicketLevel() | 2291-2295 | level, jackpotPhaseFlag | Ticket target level | YES |
| D70 | _playerActivityScore() | 2421-2507 | mintPacked_, deityPassCount, questView.playerQuestStates, dailyIdx, level | Complex scoring; external view call to questView | YES |
| D71 | _mintCountBonusPoints() | 2508-2530 | none (pure) | Scoring helper | YES |

### DegenerusGameStorage.sol View/Pure Helpers

| # | Function | Lines | Reads | Security Note | Reviewed? |
|---|----------|-------|-------|---------------|-----------|
| D72 | _isDistressMode() | 171-180 | gameOver, levelStartTime, level | Distress mode detection | YES |
| D73 | _getPrizePools() | 655-659 | prizePoolsPacked | Pool unpacking | YES |
| D74 | _getPendingPools() | 665-669 | prizePoolPendingPacked | Pool unpacking | YES |
| D75 | _tqWriteKey() | 677-679 | ticketWriteSlot | Key encoding | YES |
| D76 | _tqReadKey() | 682-684 | ticketWriteSlot | Key encoding | YES |
| D77 | _tqFarFutureKey() | 690-692 | none (pure) | Key encoding | YES |
| D78 | _getNextPrizePool() | 734-737 | prizePoolsPacked | Single-component accessor | YES |
| D79 | _getFuturePrizePool() | 746-749 | prizePoolsPacked | Single-component accessor | YES |
| D80 | _simulatedDayIndex() | 1134-1136 | (calls GameTimeLib) | Day index calculation | YES |
| D81 | _simulatedDayIndexAt() | 1139-1141 | none (pure) | Day index at timestamp | YES |
| D82 | _currentMintDay() | 1144-1150 | dailyIdx | Mint day resolution | YES |
| D83 | _setMintDay() | 1153-1163 | none (pure) | Bit packing helper | YES |

### DegenerusGameStorage.sol Boon Tier Encode/Decode (12 pure functions)

| # | Function | Lines | Reads | Security Note | Reviewed? |
|---|----------|-------|-------|---------------|-----------|
| D84 | _coinflipTierToBps() | 1519-1524 | none (pure) | Tier decode | YES |
| D85 | _lootboxTierToBps() | 1527-1532 | none (pure) | Tier decode | YES |
| D86 | _purchaseTierToBps() | 1535-1540 | none (pure) | Tier decode | YES |
| D87 | _decimatorTierToBps() | 1543-1548 | none (pure) | Tier decode | YES |
| D88 | _whaleTierToBps() | 1551-1556 | none (pure) | Tier decode | YES |
| D89 | _lazyPassTierToBps() | 1559-1564 | none (pure) | Tier decode | YES |
| D90 | _coinflipBpsToTier() | 1567-1572 | none (pure) | Tier encode | YES |
| D91 | _lootboxBpsToTier() | 1575-1580 | none (pure) | Tier encode | YES |
| D92 | _purchaseBpsToTier() | 1583-1588 | none (pure) | Tier encode | YES |
| D93 | _decimatorBpsToTier() | 1591-1596 | none (pure) | Tier encode | YES |
| D94 | _whaleBpsToTier() | 1599-1604 | none (pure) | Tier encode | YES |
| D95 | _lazyPassBpsToTier() | 1607-1612 | none (pure) | Tier encode | YES |

### DegenerusGameMintStreakUtils.sol View Functions

| # | Function | Lines | Reads | Security Note | Reviewed? |
|---|----------|-------|-------|---------------|-----------|
| D96 | _mintStreakEffective() | 49-61 | mintPacked_ | Streak calculation with gap-reset | YES |

---

## Cross-Reference Notes

### Functions present in BOTH Category A and Category B:
- **resolveRedemptionLootbox()** (A30 + B16): HYBRID function. Must verify both dispatch correctness (the loop delegatecall) AND full state-change analysis (the claimableWinnings debit, claimablePool decrement, prize pool credit before the loop).

### Selector/Name Mismatches:
- **A18 consumeDecimatorBoon()**: Router function name `consumeDecimatorBoon` dispatches to `IDegenerusGameBoonModule.consumeDecimatorBoost.selector`. The Mad Genius must verify the BoonModule actually implements `consumeDecimatorBoost` with a matching selector.

### Functions that are pure delegatecall wrappers (no pre/post logic):
- A1-A6: Advance module dispatchers (no pre-logic)
- A7-A16: Purchase/lootbox/bet dispatchers (only _resolvePlayer before dispatch)
- A17-A19: Boon dispatchers (access control check before dispatch)
- A20: Deity boon (self-issue check + resolve before dispatch)
- A21-A28: Decimator/jackpot/whale dispatchers (access control before dispatch where applicable)
- A29: Private delegatecall helper (no pre-logic)
- **A30: HYBRID -- NOT a pure wrapper**

### GAME_GAMEOVER_MODULE:
- Never called from DegenerusGame.sol directly. Called from AdvanceModule. Confirmed out of scope for this phase per D-01; deferred to Phase 104 (AdvanceModule audit).
