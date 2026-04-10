# Delta Extraction: Modules + Storage

**Diff boundary:** v5.0..HEAD (per D-01)
**Method:** Fresh git diff only (per D-02)
**Change threshold:** Semantic code changes only; comment/NatSpec-only = UNCHANGED (per D-03)

## Contract Classification

| Contract | Status | Lines Changed | Justification |
|----------|--------|---------------|---------------|
| DegenerusGameAdvanceModule.sol | MODIFIED | +873 / -873 (net rewrite) | Pool consolidation inlined, EndgameModule functions absorbed, drip projection added, price table replaced by PriceLookupLib, day index type narrowed uint48->uint32, two-call ETH split support, reverseFlip removed |
| DegenerusGameBoonModule.sol | MODIFIED | +10 changes | BoonConsumed events added to all four consumption paths; duplicate quests constant removed (now in Storage) |
| DegenerusGameDecimatorModule.sol | MODIFIED | +241 changes | Auto-rebuy removed from claim path (uses _creditClaimable directly), claimablePool narrowed to uint128, terminal decimator burns blocked at <=7 days (was <=1), time multiplier formula redesigned, day-index arithmetic replaces timestamp arithmetic |
| DegenerusGameDegeneretteModule.sol | MODIFIED | +502 changes | WXRP consolation prize removed, placeFullTicketBets renamed placeDegeneretteBet, quest notifications route to IDegenerusQuests.handleDegenerette, activity score uses shared _playerActivityScore, lootbox RNG index reads from packed _lrRead, coin.creditFlipBatch replaced by coinflip.creditFlip, lootboxRngPendingEth/Burnie use packed milli-ETH/whole-BURNIE encoding |
| DegenerusGameEndgameModule.sol | DELETED | -565 lines | Entire module eliminated; functions redistributed to AdvanceModule (rewardTopAffiliate, runRewardJackpots) and JackpotModule (runBafJackpot, _awardJackpotTickets, _jackpotTicketRoll, claimWhalePass->WhaleModule) |
| DegenerusGameGameOverModule.sol | MODIFIED | +171 changes | gameOverStatePacked replaces individual bools, GNRUS added as third sweep recipient (33/33/34 split replaces 50/50), burnAtGameOver calls added for GNRUS and sDGNRS, RNG gate defense-in-depth added, GameOverDrained/FinalSwept events added, claimablePool narrowed to uint128, _sendStethFirst helper extracted |
| DegenerusGameJackpotModule.sol | MODIFIED | +2157 changes (largest) | consolidatePrizePools removed (inlined to AdvanceModule), distributeYieldSurplus made external, _distributeJackpotEth and _processDailyEth unified, two-call daily ETH split (SPLIT_NONE/CALL1/CALL2), processTicketBatch moved to MintModule, _raritySymbolBatch moved to MintModule, awardFinalDayDgnrsReward inlined into _handleSoloBucketWinner, _randTraitTicket and _randTraitTicketWithIndices merged (keccak per-winner indexing replaces bit-rotation), carryover reworked (0.5% ticket-only, fixed source offset), coin.creditFlipBatch replaced by coinflip.creditFlip, BAF/reward jackpots moved from EndgameModule, _calculateDayIndex removed, events restructured (JackpotEthWin/JackpotTicketWin/JackpotBurnieWin/JackpotDgnrsWin/JackpotWhalePassWin replace JackpotTicketWinner) |
| DegenerusGameLootboxModule.sol | MODIFIED | +200 changes | coin.creditFlip replaced by coinflip.creditFlip, _activeBoonCategory and _boonCategory removed (multi-boon per player), presaleActive reads from packed _psRead, deityPassCount replaced by mintPacked_ bit check, BURNIE lootbox endgame ticket redirect uses gameOverPossible flag instead of timestamp cutoff, boon upgrade semantics unified (deity boons use upgrade-only like lootbox) |
| DegenerusGameMintModule.sol | MODIFIED | +889 changes | processTicketBatch moved here from JackpotModule, _raritySymbolBatch and related helpers moved here, inherits DegenerusGameMintStreakUtils, affiliate bonus cached in mintPacked_ bits 185-214, CoinPurchaseCutoff replaced by GameOverPossible error, coin/affiliate constants removed (now in Storage), PriceLookupLib used for price |
| DegenerusGameMintStreakUtils.sol | MODIFIED | +115 changes | _playerActivityScore added (5-component scoring: mint streak, mint count, quest streak, affiliate bonus, deity/whale pass), _activeTicketLevel helper added, two overloads for convenience |
| DegenerusGamePayoutUtils.sol | MODIFIED | +16 changes | NatSpec documentation added to _creditClaimable and _calcAutoRebuy, claimablePool cast to uint128 in _queueWhalePassClaimCore |
| DegenerusGameWhaleModule.sol | MODIFIED | +358 changes | claimWhalePass moved here from EndgameModule, WhalePassClaimed event added, DeityPassPurchased event added, deityPassCount replaced by mintPacked_ bit (HAS_DEITY_PASS_SHIFT), presaleActive reads from packed _psRead, lootboxRngPendingEth replaced by packed _lrWrite, _maybeRequestLootboxRng inlined, _queueTickets gains rngBypass parameter |
| DegenerusGameStorage.sol | MODIFIED | +719 changes | Full slot 0 repack (levelStartTime->purchaseStartDay uint32, dailyIdx uint32, poolConsolidationDone/dailyEthPhase removed, ticketsFullyProcessed/gameOverPossible/ticketWriteSlot/prizePoolFrozen moved in), slot 1 repacked (currentPrizePool uint128 + claimablePool uint128), price removed (PriceLookupLib), presaleStatePacked/gameOverStatePacked/dailyJackpotTraitsPacked bitfield packing, _isDistressMode rewritten for day-index, _queueTickets/_queueTicketsScaled/_queueTicketRange gain rngBypass parameter, new events/constants/contract refs centralized, _getCurrentPrizePool/_setCurrentPrizePool helpers added |

## Function-Level Changelog

### DegenerusGameAdvanceModule.sol (MODIFIED)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| advanceGame | external | MODIFIED | Death clock uses day-index arithmetic (purchaseStartDay + 120 days). Price computed via PriceLookupLib. Bounty multiplier separated from base. gameOverPossible flag checked/cleared. Pool consolidation inlined via _consolidatePoolsAndRewardJackpots. GNRUS charity.pickCharity called at level transition. quests.rollDailyQuest/rollLevelQuest called. reverseFlip/awardFinalDayDgnrsReward/drawDownFuturePrizePool calls removed. |
| _handleGameOverPath | private | MODIFIED | Signature changed (removed ts, lst, lastPurchase; added psd). Uses day-index comparison instead of timestamp. _unlockRng moved after delegatecall. |
| _rewardTopAffiliate | private | MODIFIED | Inlined from EndgameModule delegatecall. Now directly calls affiliate.affiliateTop, dgnrs.transferFromPool, and sets levelDgnrsAllocation. AffiliateDgnrsReward event emitted locally. |
| _distributeYieldSurplus | private | ADDED | Wraps delegatecall to JackpotModule.distributeYieldSurplus (replaces direct call to _distributeYieldSurplus which was private in JackpotModule). |
| _consolidatePoolsAndRewardJackpots | private | ADDED | Replaces separate _applyTimeBasedFutureTake, _consolidatePrizePools, _drawDownFuturePrizePool, _runRewardJackpots. All pool math computed in memory; single SSTORE batch at end. Includes future take, x00 yield dump, BAF/Decimator dispatch, x00 keep roll, merge next->current, coinflip credit, future->next drawdown. |
| _applyTimeBasedFutureTake | internal | REMOVED | Logic inlined into _consolidatePoolsAndRewardJackpots. |
| _drawDownFuturePrizePool | private | REMOVED | Logic inlined into _consolidatePoolsAndRewardJackpots. |
| _consolidatePrizePools | private | REMOVED | Logic inlined into _consolidatePoolsAndRewardJackpots (was delegatecall to JackpotModule). |
| _awardFinalDayDgnrsReward | private | REMOVED | Removed; DGNRS reward now handled inline in JackpotModule._handleSoloBucketWinner on final day. |
| _runRewardJackpots | private | REMOVED | Logic inlined into _consolidatePoolsAndRewardJackpots (BAF/Decimator dispatch). |
| rngGate | internal | MODIFIED | Returns (uint256 word, uint32 gapDays) tuple. purchaseStartDay adjusted by gapDays. quests.rollDailyQuest called. resolveRedemptionPeriod return value no longer used for coinflip credit. |
| _gameOverEntropy | private | MODIFIED | Day parameter changed to uint32. resolveRedemptionPeriod return value no longer used. Fallback path reverts RngNotReady() instead of returning 0. |
| _requestRng | private | MODIFIED | Price table removed (PriceLookupLib). VRF coordinator address check removed (always valid). Decimator window open/close moved here from advanceGame (at level increment time). Level increment triggers _rewardTopAffiliate and charityResolve.pickCharity. lootboxRngIndex/pending use packed _lrRead/_lrWrite. |
| reverseFlip | external | REMOVED | Nudge purchase function removed entirely. |
| _currentNudgeCost | private | REMOVED | Removed with reverseFlip. |
| _nextToFutureBps | internal | MODIFIED | Parameters changed from uint48 elapsed to uint32 elapsed. Arithmetic changed from seconds to days. NEXT_TO_FUTURE_BPS_WEEK_STEP replaced by NEXT_TO_FUTURE_BPS_DAY_STEP. |
| payDailyJackpot | internal | MODIFIED | Parameter renamed isDaily -> isJackpotPhase. |
| _enforceDailyMintGate | private | MODIFIED | dailyIdx_ parameter changed to uint32. Deity pass check via mintPacked_ bit instead of deityPassCount mapping. |
| requestLootboxRng | external | MODIFIED | Packed lootbox RNG state reads/writes via _lrRead/_lrWrite. midDayTicketRngPending via packed field. Price via PriceLookupLib. |
| _runProcessTicketBatch | private | MODIFIED | Delegatecall target changed from JackpotModule to MintModule. |
| _processPhaseTransition | private | MODIFIED | _queueTickets calls gain rngBypass=true parameter. |
| _backfillGapDays | private | MODIFIED | Parameters narrowed to uint32. 120-day gap cap added for gas safety. |
| _unlockRng | private | MODIFIED | Day parameter changed to uint32. |
| _backfillOrphanedLootboxIndices | private | MODIFIED | lootboxRngIndex read via packed _lrRead. lastLootboxRngWord assignment removed. |
| _applyDailyRng | private | MODIFIED | Day parameter changed to uint32. |
| _finalizeLootboxRng | private | MODIFIED | lootboxRngIndex read via packed _lrRead. lastLootboxRngWord assignment removed. |
| _wadPow | private | ADDED | Fixed-point exponentiation (1e18 scale) for drip projection. |
| _projectedDrip | private | ADDED | Geometric series drip projection from futurePool over n days. |
| _evaluateGameOverAndTarget | private | ADDED | Sets/clears gameOverPossible flag based on drip projection vs nextPool deficit. Returns whether target is met. |
| RewardJackpotsSettled | event | ADDED (MOVED) | Moved from EndgameModule. Emitted from _consolidatePoolsAndRewardJackpots. |
| AffiliateDgnrsReward | event | ADDED (MOVED) | Moved from EndgameModule. Emitted from _rewardTopAffiliate. |

### DegenerusGameBoonModule.sol (MODIFIED)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| consumeCoinflipBoon | external | MODIFIED | Emits BoonConsumed(player, 1, boonBps) after clearing boon state. |
| consumePurchaseBoost | external | MODIFIED | Emits BoonConsumed(player, 2, boostBps) after clearing boon state. |
| consumeDecimatorBoost | external | MODIFIED | Emits BoonConsumed(player, 3, boostBps) after clearing boon state. |
| consumeActivityBoon | external | MODIFIED | Emits BoonConsumed(player, 5, bonus) after quest streak bonus award. |
| quests constant | internal | REMOVED | Removed (now centralized in DegenerusGameStorage). |

### DegenerusGameDecimatorModule.sol (MODIFIED)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| recordDecimatorBurn | external | MODIFIED | NatSpec updated: "entry migrates" -> "carried over to the new bucket". |
| runDecimatorJackpot | external | MODIFIED | DecimatorResolved event emitted with packed offsets, pool, and totalBurn. |
| claimDecimatorJackpot | external | MODIFIED | Freeze rationale updated. Game-over path uses _creditClaimable instead of _addClaimableEth (auto-rebuy removed). |
| _processAutoRebuy | private | REMOVED | Auto-rebuy removed from decimator claims. |
| _addClaimableEth | private | REMOVED | Replaced by direct _creditClaimable calls. |
| _splitDecClaim | private | MODIFIED | Uses _creditClaimable instead of _addClaimableEth. claimablePool cast to uint128. |
| _awardDecimatorLootbox | private | MODIFIED | Large amounts: inline whale pass calculation with explicit _queueTicketRange call (replaces _queueWhalePassClaimCore). Remainder credited directly. |
| recordTerminalDecBurn | external | MODIFIED | Burns blocked at <=7 days (was <=1 day). |
| claimTerminalDecimatorJackpot | external | MODIFIED | prizePoolFrozen check removed. Uses _creditClaimable instead of _addClaimableEth. |
| _terminalDecMultiplierBps | private | MODIFIED | Redesigned: >10 days: linear 20x (day 120) to 1x (day 10). 7-10 days: flat 1x. <=7 days: blocked. |
| _terminalDecDaysRemaining | private | MODIFIED | Uses day-index arithmetic (purchaseStartDay + deadline) instead of timestamp. |
| AutoRebuyProcessed | event | REMOVED | Removed with auto-rebuy path. |
| DecimatorResolved | event | ADDED | Emitted when subbuckets are resolved. |

### DegenerusGameDegeneretteModule.sol (MODIFIED)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| placeFullTicketBets | external | RENAMED | Renamed to placeDegeneretteBet. |
| _placeFullTicketBets | private | RENAMED | Renamed to _placeDegeneretteBet. Quest notification changed from coin.notifyQuestDegenerette to quests.handleDegenerette. |
| _placeFullTicketBetsCore | private | RENAMED | Renamed to _placeDegeneretteBetCore. lootboxRngIndex read via _lrRead. Activity score uses _playerActivityScore with explicit quest streak fetch. BetPlaced event index field cast to uint32. |
| _collectBetFunds | private | MODIFIED | claimablePool narrowed to uint128. lootboxRngPendingEth/Burnie use packed milli-ETH/whole-BURNIE encoding via _lrWrite. |
| _resolveFullTicketBet | private | MODIFIED | Index field decoded as uint32. |
| _distributePayout | private | MODIFIED | claimablePool narrowed to uint128. |
| resolveBets | external | MODIFIED | Parameter formatting change only. |
| ConsolationPrize | event | REMOVED | Consolation prizes removed entirely. |
| _maybeAwardConsolation | private | REMOVED | Consolation prize logic removed. |
| coin/questView/affiliate constants | internal | REMOVED | Centralized in DegenerusGameStorage. |
| IDegenerusQuestView interface | - | REMOVED (MOVED) | Moved to DegenerusGameStorage. |

### DegenerusGameEndgameModule.sol (DELETED)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| rewardTopAffiliate | external | MOVED to AdvanceModule._rewardTopAffiliate | Inlined as private function in AdvanceModule. Same logic, no longer delegatecall. |
| runRewardJackpots | external | MOVED to AdvanceModule._consolidatePoolsAndRewardJackpots | BAF/Decimator dispatch logic inlined into AdvanceModule's batched pool consolidation. |
| _addClaimableEth | private | MOVED to JackpotModule._addClaimableEth | Auto-rebuy credit logic moved to JackpotModule (modified signature returns tuple). |
| _runBafJackpot | private | MOVED to JackpotModule.runBafJackpot | Made external (called via self-call). Returns claimableDelta only (refund/lootbox stay in futurePool implicitly). |
| _awardJackpotTickets | private | MOVED to JackpotModule._awardJackpotTickets | Same logic, now in JackpotModule. |
| _jackpotTicketRoll | private | MOVED to JackpotModule._jackpotTicketRoll | Same logic, now in JackpotModule. |
| claimWhalePass | external | MOVED to WhaleModule.claimWhalePass | Same logic. _queueTicketRange gains rngBypass parameter. |
| AutoRebuyExecuted | event | REMOVED | No longer emitted (auto-rebuy tracking simplified). |
| RewardJackpotsSettled | event | MOVED to AdvanceModule | Emitted from _consolidatePoolsAndRewardJackpots. |
| AffiliateDgnrsReward | event | MOVED to AdvanceModule | Emitted from _rewardTopAffiliate. |
| WhalePassClaimed | event | MOVED to WhaleModule | Emitted from claimWhalePass. |

### DegenerusGameGameOverModule.sol (MODIFIED)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| handleGameOverDrain | external | MODIFIED | Day parameter changed to uint32. gameOverFinalJackpotPaid replaced by _goRead packed check. Pre-refund available computed before side effects. RNG gate defense-in-depth (revert if funds exist but word unavailable). charityGameOver.burnAtGameOver() and dgnrs.burnAtGameOver() called. burnRemainingPools removed. GameOverDrained event emitted. claimablePool narrowed to uint128. currentPrizePool via _setCurrentPrizePool. |
| handleFinalSweep | external | MODIFIED | All game-over state reads/writes via _goRead/_goWrite packed fields. FinalSwept event emitted. |
| _sendToVault | private | MODIFIED | Split changed from 50/50 (vault/DGNRS) to 33/33/34 (sDGNRS/vault/GNRUS). Extracted _sendStethFirst helper. |
| _sendStethFirst | private | ADDED | Sends stETH-first to a recipient, then ETH for remainder. Returns updated stETH balance. |
| IGNRUSGameOver interface | - | ADDED | Interface for GNRUS.burnAtGameOver(). |
| GameOverDrained | event | ADDED | Emitted when gameover drain processes terminal jackpots. |
| FinalSwept | event | ADDED | Emitted when final sweep forfeits unclaimed winnings. |
| dgnrs constant | internal | REMOVED | Centralized in DegenerusGameStorage. |

### DegenerusGameJackpotModule.sol (MODIFIED)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| consolidatePrizePools | external | REMOVED | Inlined into AdvanceModule._consolidatePoolsAndRewardJackpots. |
| _distributeYieldSurplus | private | RENAMED/MODIFIED | Renamed to distributeYieldSurplus (made external). GNRUS added as third yield recipient (23% each to vault, sDGNRS, GNRUS, 23% accumulator). |
| awardFinalDayDgnrsReward | external | REMOVED | Logic inlined into _handleSoloBucketWinner (final-day DGNRS reward applied inline during solo bucket ETH distribution). |
| payDailyJackpot | external | MODIFIED | Parameter renamed isDaily->isJackpotPhase. Resume check uses resumeEthPool instead of dailyEthPoolBudget/dailyEthPhase. Carryover reworked: 0.5% of futurePool as tickets (was 1% ETH+lootbox), fixed random source offset [1..4] (was probed up to 5). Purchase phase: deferred pool deduction model. coin.rollDailyQuest removed. |
| payDailyJackpotCoinAndTickets | external | MODIFIED | Reads winning traits from _djtRead packed field. Carryover tickets target current level (or lvl+1 on final day). coin.rollDailyQuest removed. _distributeTicketJackpot gains queueLvl parameter. |
| _addClaimableEth | private | MODIFIED | Returns (claimableDelta, rebuyLevel, rebuyTickets) tuple for event emission. |
| _processAutoRebuy | private | MODIFIED | Returns (claimableDelta, rebuyLevel, rebuyTickets) tuple. _queueTickets gains rngBypass=true. AutoRebuyProcessed event removed. |
| _processDailyEth | private | MODIFIED (major rewrite) | Renamed from separate _processDailyEth and _distributeJackpotEth. Unified function handles all paths with splitMode (SPLIT_NONE/CALL1/CALL2) and isJackpotPhase parameters. Solo bucket gets whale pass + DGNRS on final day (jackpot phase only). Ordered bucket iteration with call1 mask for split routing. |
| _resumeDailyEth | private | ADDED | Call 2 of two-call daily ETH split. Reconstructs params from stored state and processes mid buckets. |
| _handleSoloBucketWinner | private | ADDED | Extracted from _processDailyEth to avoid stack-too-deep. Handles whale pass, DGNRS reward on final day, emits specialized events. |
| _payNormalBucket | private | ADDED | Extracted from _processDailyEth for normal (non-solo) bucket winner payment. |
| _distributeJackpotEth | private | REMOVED | Merged into _processDailyEth. |
| _processOneBucket | private | REMOVED | Merged into _processDailyEth loop. |
| JackpotEthCtx | struct | REMOVED | Replaced by local variables in _processDailyEth. |
| _resolveTraitWinners | private | MODIFIED | payCoin parameter removed (coin path eliminated). Uses _randTraitTicket (merged). Returns simplified tuple. |
| _creditJackpot | private | REMOVED | Coin path eliminated; ETH path inlined as _addClaimableEth. |
| _runJackpotEthFlow | private | MODIFIED | Fixed bucket counts [20, 12, 6, 1] = 39 winners with entropy rotation. Calls _processDailyEth instead of _distributeJackpotEth. |
| _executeJackpot | private | MODIFIED | Returns paidEth (was void). |
| _runEarlyBirdLootboxJackpot | private | MODIFIED | Uses merged _randTraitTicket with ticketIndexes. _queueTickets gains rngBypass=true. JackpotTicketWin event emitted. |
| _distributeLootboxAndTickets | private | MODIFIED | _distributeTicketJackpot gains queueLvl parameter. PURCHASE_PHASE_TICKET_MAX_WINNERS replaces LOOTBOX_MAX_WINNERS. |
| _distributeTicketJackpot | private | MODIFIED | Gains sourceLvl and queueLvl parameters (decoupled source level from ticket target level). |
| _distributeTicketsToBuckets | private | MODIFIED | Gains sourceLvl and queueLvl parameters. |
| _distributeTicketsToBucket | private | MODIFIED | Gains sourceLvl and queueLvl parameters. Emits JackpotTicketWin event. |
| _getWinningTraits | private | RENAMED | Renamed to _applyHeroOverride. No longer generates base traits (caller provides them). Only applies hero override if top hero symbol exists. |
| _rollWinningTraits | private | MODIFIED | Simplified: always uses random traits + hero override. Removed lvl and useBurnCounts parameters. |
| _syncDailyWinningTraits | private | MODIFIED | Uses _djtWrite packed field helpers. Day parameter changed to uint32. |
| _loadDailyWinningTraits | private | MODIFIED | Uses _djtRead packed field helpers. Day parameter changed to uint32. |
| _calcDailyCoinBudget | private | MODIFIED | Uses PriceLookupLib.priceForLevel(level) instead of price storage variable. |
| _selectDailyCoinTargetLevel | private | MODIFIED | Removed _hasTraitTickets check (always returns candidate). Removed packedTraits parameter. Made pure. |
| _awardDailyCoinToTraitWinners | private | MODIFIED | Uses merged _randTraitTicket. coin.creditFlipBatch replaced by individual coinflip.creditFlip calls. JackpotBurnieWin event replaces JackpotTicketWinner. Batch array removed. MAX_BUCKET_WINNERS cap removed from bucket count. |
| _awardFarFutureCoinJackpot | private | MODIFIED | Dynamic arrays replace fixed-3 batch arrays. coin.creditFlipBatch called once with full arrays. |
| _topHeroSymbol | private | MODIFIED | Day parameter changed to uint48->uint32. |
| processTicketBatch | external | REMOVED (MOVED to MintModule) | Entire ticket batch processing system moved. |
| _processOneTicketEntry | private | REMOVED (MOVED to MintModule) | |
| _resolveZeroOwedRemainder | private | REMOVED (MOVED to MintModule) | |
| _generateTicketBatch | private | REMOVED (MOVED to MintModule) | |
| _finalizeTicketEntry | private | REMOVED (MOVED to MintModule) | |
| _rollRemainder | private | REMOVED (MOVED to MintModule) | |
| _raritySymbolBatch | private | REMOVED (MOVED to MintModule) | Assembly-based trait generation moved to MintModule. |
| _randTraitTicket | private | MODIFIED | Merged with _randTraitTicketWithIndices. Now returns both addresses and ticketIndexes. Per-winner indexing uses keccak256(abi.encode(randomWord, trait, salt, i)) instead of bit rotation. |
| _randTraitTicketWithIndices | private | REMOVED | Merged into _randTraitTicket. |
| _calculateDayIndex | private | REMOVED | Replaced by direct _simulatedDayIndex() calls. |
| _creditDgnrsCoinflip | private | REMOVED | Inlined into AdvanceModule._consolidatePoolsAndRewardJackpots. |
| _futureKeepBps | private | REMOVED | Inlined into AdvanceModule._consolidatePoolsAndRewardJackpots. |
| _hasTraitTickets | private | REMOVED | No longer needed (budget validation removed). |
| _validateTicketBudget | private | REMOVED | Budget validation removed (budgets always allocated regardless of ticket presence). |
| _hasActualTraitTickets | private | REMOVED | No longer needed. |
| _highestCarryoverSourceOffset | private | REMOVED | Carryover source selection simplified to pure random. |
| _selectCarryoverSourceOffset | private | REMOVED | Replaced by inline keccak256 modulo. |
| _clearDailyEthState | private | REMOVED | State variables removed (dailyEthPhase, dailyEthPoolBudget, dailyCarryoverEthPool, dailyCarryoverWinnerCap). |
| _processSoloBucketWinner | private | MODIFIED | Returns extended tuple with rebuyLevel and rebuyTickets. Uses _addClaimableEth 3-return variant. |
| runBafJackpot | external | ADDED (MOVED from EndgameModule) | BAF jackpot execution. Made external (called via self-call from AdvanceModule). Returns claimableDelta only. Emits JackpotEthWin/JackpotTicketWin/JackpotWhalePassWin events. |
| _awardJackpotTickets | private | ADDED (MOVED from EndgameModule) | Ticket award tiering logic. |
| _jackpotTicketRoll | private | ADDED (MOVED from EndgameModule) | Probabilistic ticket roll. _queueLootboxTickets gains rngBypass=true. |
| AutoRebuyProcessed | event | REMOVED | |
| DailyCarryoverStarted | event | REMOVED | |
| JackpotTicketWinner | event | REMOVED | Replaced by JackpotEthWin, JackpotTicketWin, JackpotBurnieWin. |
| JackpotEthWin | event | ADDED | ETH win with rebuy info. |
| JackpotTicketWin | event | ADDED | Ticket win with source level. |
| JackpotBurnieWin | event | ADDED | BURNIE coin win. |
| JackpotDgnrsWin | event | ADDED | DGNRS reward to solo bucket winner on final day. |
| JackpotWhalePassWin | event | ADDED | Whale pass award to solo bucket winner. |
| coin constant | internal | REMOVED | Centralized in DegenerusGameStorage. |
| dgnrs constant | internal | REMOVED | Centralized in DegenerusGameStorage. |

### DegenerusGameLootboxModule.sol (MODIFIED)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| openLootbox | external | MODIFIED | presaleActive reads from _psRead packed field. Day index changed to uint32. |
| openBurnieLootbox | external | MODIFIED | Price via PriceLookupLib. BURNIE lootbox endgame redirect uses gameOverPossible flag + TICKET_FAR_FUTURE_BIT instead of timestamp-based cutoff. Event index cast to uint32. |
| resolveLootboxDirect | external | MODIFIED | Day index changed to uint32. |
| resolveRedemptionLootbox | external | MODIFIED | Day index changed to uint32. |
| deityBoonSlots | external | MODIFIED | Return type day changed to uint32. |
| issueDeityBoon | external | MODIFIED | Day changed to uint32. |
| _resolveLootboxCommon | private | MODIFIED | Day parameter changed to uint32. _queueTicketsScaled gains rngBypass=false. coin.creditFlip replaced by coinflip.creditFlip. |
| _rollLootboxBoons | private | MODIFIED | _activeBoonCategory check removed (players can hold multiple boons). Day changed to uint32. deityPassCount check replaced by mintPacked_ bit. |
| _activeBoonCategory | private | REMOVED | Multi-boon support: players can hold one boon per category simultaneously. |
| _boonCategory | private | REMOVED | No longer needed for exclusion logic. |
| _applyBoon | private | MODIFIED | Day parameters changed to uint32. All deity boon paths use upgrade semantics (was overwrite). Isolated bitmask operations per category. |
| _activate10LevelPass | private | MODIFIED | _queueTickets gains rngBypass=false. |
| _boonPoolStats | private | MODIFIED | Price via PriceLookupLib. |
| _deityDailySeed | private | MODIFIED | Day parameter changed to uint32. |
| _deityBoonForSlot | private | MODIFIED | Day parameter changed to uint32. |
| _rollTargetLevel (whale pass jackpot) | private | MODIFIED | Day parameter changed to uint32. |
| coin constant | internal | REMOVED | Centralized in DegenerusGameStorage. |
| dgnrs constant | internal | REMOVED | Centralized in DegenerusGameStorage. |
| BURNIE_LOOT_CUTOFF constants | private | REMOVED | Replaced by gameOverPossible flag. |
| BOON_CAT_* constants | private | REMOVED | No longer needed for category exclusion. |

### DegenerusGameMintModule.sol (MODIFIED)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| recordMintData | external | MODIFIED | Affiliate bonus cached in mintPacked_ bits 185-214 on level transitions. Formatting refactored for readability. |
| processTicketBatch | external | ADDED (MOVED from JackpotModule) | Current-level ticket batch processing with gas-bounded iteration. Entropy sourced from lootboxRngWordByIndex via _lrRead. |
| _processOneTicketEntry | private | ADDED (MOVED from JackpotModule) | Single ticket entry processor. |
| _resolveZeroOwedRemainder | private | ADDED (MOVED from JackpotModule) | Zero-owed remainder resolution. |
| _raritySymbolBatch | private | ADDED (MOVED from JackpotModule) | Assembly-based bulk trait generation (LCG PRNG). |
| _finalizeTicketEntry | private | ADDED (MOVED from JackpotModule) | Ticket entry finalization with remainder roll. |
| _rollRemainder | private | ADDED (MOVED from JackpotModule) | Fractional ticket remainder roll. |
| CoinPurchaseCutoff | error | REMOVED | Replaced by GameOverPossible error. |
| GameOverPossible | error | ADDED | Reverts when drip projection cannot cover nextPool deficit. |
| Inherits DegenerusGameMintStreakUtils | - | ADDED | Was DegenerusGameStorage. Now inherits shared activity score logic. |
| coin/affiliate constants | internal | REMOVED | Centralized in DegenerusGameStorage. |
| COIN_PURCHASE_CUTOFF constants | private | REMOVED | Replaced by gameOverPossible flag logic. |

### DegenerusGameMintStreakUtils.sol (MODIFIED)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| _playerActivityScore(player, questStreak, streakBaseLevel) | internal | ADDED | 5-component activity score: mint streak (max 50%), mint count (level-based), quest streak (max 100%), affiliate bonus (cached or live), deity/whale pass bonus. Deity pass: 50% streak + 25% mint + 80% bonus. Active pass: floor 50% streak / 25% mint. |
| _playerActivityScore(player, questStreak) | internal | ADDED | Convenience overload using _activeTicketLevel() as streak base. |
| _activeTicketLevel | internal | ADDED | Returns level (jackpot phase) or level+1 (purchase phase) for ticket targeting. |

### DegenerusGamePayoutUtils.sol (MODIFIED)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| _creditClaimable | internal | MODIFIED | NatSpec documentation added. |
| _calcAutoRebuy | internal | MODIFIED | NatSpec documentation added. |
| _queueWhalePassClaimCore | internal | MODIFIED | claimablePool cast to uint128. |

### DegenerusGameWhaleModule.sol (MODIFIED)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| purchaseWhaleBundle | external | MODIFIED | Formatting refactored. |
| _purchaseWhaleBundle | private | MODIFIED | presaleActive reads from _psRead. deityPassCount replaced by mintPacked_ bit (HAS_DEITY_PASS_SHIFT). _queueTickets gains rngBypass=false. lootboxRngPendingEth via packed _lrWrite/milli-ETH encoding. |
| purchaseLazyPass | external | MODIFIED | deityPassCount replaced by mintPacked_ bit check. presaleActive via _psRead. _queueTickets gains rngBypass=false. |
| purchaseDeityPass | external | MODIFIED | deityPassCount replaced by mintPacked_ bit. deityPassCount[buyer]=1 replaced by BitPackingLib.setPacked. presaleActive via _psRead. lootboxRngPendingEth via packed _lrWrite. DeityPassPurchased event emitted. |
| claimWhalePass | external | ADDED (MOVED from EndgameModule) | Same logic. _queueTicketRange gains rngBypass=false. WhalePassClaimed event emitted. |
| _recordLootboxEntry | private | MODIFIED | lootboxRngIndex via _lrRead. LootBoxIndexAssigned index cast to uint32. lootboxRngPendingEth via packed _lrWrite/milli-ETH. |
| _maybeRequestLootboxRng | private | REMOVED | Inlined into _recordLootboxEntry (single _lrWrite call). |
| _applyLootboxBoostOnPurchase | private | MODIFIED | Day parameter changed to uint32. |
| _recordLootboxMintDay | private | MODIFIED | Formatting refactored. |
| WhalePassClaimed | event | ADDED (MOVED from EndgameModule) | |
| DeityPassPurchased | event | ADDED | New event for deity pass purchases. |
| affiliate constant | internal | REMOVED | Centralized in DegenerusGameStorage. |
| dgnrs constant | internal | REMOVED | Centralized in DegenerusGameStorage. |

### DegenerusGameStorage.sol (MODIFIED)

#### Storage Variable Changes

| Variable | Change | Description |
|----------|--------|-------------|
| levelStartTime (uint48) | REMOVED | Replaced by purchaseStartDay (uint32 day index). |
| purchaseStartDay | MODIFIED | Type changed uint48->uint32, moved from slot 1 to slot 0 byte [0:4]. |
| dailyIdx | MODIFIED | Type changed uint48->uint32, slot 0 byte [4:8]. |
| poolConsolidationDone (bool) | REMOVED | No longer needed (consolidation is single-call in AdvanceModule). |
| dailyEthPhase (uint8) | REMOVED | Two-call split uses resumeEthPool instead. |
| compressedJackpotFlag | MODIFIED | Moved within slot 0. |
| ticketsFullyProcessed | MODIFIED | Moved from slot 1 to slot 0. |
| gameOverPossible (bool) | ADDED | Drip projection endgame flag. Slot 0 byte [27:28]. |
| ticketWriteSlot | MODIFIED | Type changed uint8->bool. Moved from slot 1 to slot 0. Toggle via negation replaces XOR. |
| prizePoolFrozen | MODIFIED | Moved from slot 1 to slot 0. |
| price (uint128) | REMOVED | Replaced by PriceLookupLib.priceForLevel(). |
| currentPrizePool | MODIFIED | Type changed uint256->uint128. Moved to slot 1 alongside claimablePool. |
| claimablePool | MODIFIED | Type changed uint256->uint128. Moved from standalone slot to slot 1 alongside currentPrizePool. |
| dailyEthPoolBudget (uint256) | REMOVED | Two-call split uses resumeEthPool and dailyTicketBudgetsPacked. |
| dailyCarryoverEthPool (uint256) | REMOVED | Carryover is now ticket-only (no separate ETH pool). |
| dailyCarryoverWinnerCap (uint16) | REMOVED | No longer needed. |
| lootboxPresaleActive (bool) | REMOVED | Replaced by presaleStatePacked bit field. |
| lootboxPresaleMintEth (uint256) | REMOVED | Replaced by presaleStatePacked bit field (uint128). |
| presaleStatePacked (uint256) | ADDED | Packed: lootboxPresaleActive (8 bits) + lootboxPresaleMintEth (128 bits). |
| gameOverTime (uint48) | REMOVED | Replaced by gameOverStatePacked bit field. |
| gameOverFinalJackpotPaid (bool) | REMOVED | Replaced by gameOverStatePacked bit field. |
| finalSwept (bool) | REMOVED | Replaced by gameOverStatePacked bit field. |
| gameOverStatePacked (uint256) | ADDED | Packed: gameOverTime (48 bits) + gameOverFinalJackpotPaid (8 bits) + finalSwept (8 bits). |
| decimatorAutoRebuyDisabled mapping | REMOVED | Auto-rebuy for decimator claims removed. |
| lastDailyJackpotWinningTraits (uint32) | REMOVED | Replaced by dailyJackpotTraitsPacked bit field. |
| lastDailyJackpotLevel (uint24) | REMOVED | Replaced by dailyJackpotTraitsPacked bit field. |
| lastDailyJackpotDay (uint48) | REMOVED | Replaced by dailyJackpotTraitsPacked bit field. |
| dailyJackpotTraitsPacked (uint256) | ADDED | Packed: traits (32 bits) + level (24 bits) + day (32 bits). |
| rngWordByDay mapping key | MODIFIED | Key type changed uint48->uint32. |

#### Function Changes in Storage

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| _isDistressMode | internal | MODIFIED | Rewritten for day-index arithmetic. Uses purchaseStartDay and _simulatedDayIndex() instead of levelStartTime and block.timestamp. |
| _queueTickets | internal | MODIFIED | Gains rngBypass parameter (replaces phaseTransitionActive check). |
| _queueTicketsScaled | internal | MODIFIED | Gains rngBypass parameter. |
| _queueTicketRange | internal | MODIFIED | Gains rngBypass parameter. |
| _queueLootboxTickets | internal | MODIFIED | Gains rngBypass parameter. Passes through to _queueTicketsScaled. |
| _tqWriteKey | internal | MODIFIED | Uses bool comparison (ticketWriteSlot ? ...) instead of uint8 (ticketWriteSlot != 0 ? ...). |
| _tqReadKey | internal | MODIFIED | Uses bool negation (!ticketWriteSlot ? ...) instead of uint8 (ticketWriteSlot == 0 ? ...). |
| _swapTicketSlot | internal | MODIFIED | Uses bool negation (ticketWriteSlot = !ticketWriteSlot) instead of XOR (ticketWriteSlot ^= 1). |
| _getCurrentPrizePool | internal | ADDED | Reads uint128 currentPrizePool, widens to uint256. |
| _setCurrentPrizePool | internal | ADDED | Narrows uint256 to uint128 for storage. |
| _psRead / _psWrite | internal | ADDED | Read/write helpers for presaleStatePacked. |
| _goRead / _goWrite | internal | ADDED | Read/write helpers for gameOverStatePacked. |
| _djtRead / _djtWrite | internal | ADDED | Read/write helpers for dailyJackpotTraitsPacked. |
| IDegenerusQuestView interface | - | ADDED (MOVED from DegeneretteModule) | Quest view interface centralized in storage. |
| coin/coinflip/quests/questView/affiliate/dgnrs | constant | ADDED | External contract references centralized from individual modules. |
| DEITY_PASS_ACTIVITY_BONUS_BPS | constant | ADDED | Centralized from DegeneretteModule. |
| PASS_STREAK_FLOOR_POINTS | constant | ADDED | Centralized from DegeneretteModule. |
| PASS_MINT_COUNT_FLOOR_POINTS | constant | ADDED | Centralized from DegeneretteModule. |
| DISTRESS_MODE_HOURS (uint48) | constant | REMOVED | Distress mode is now day-granularity. |
| _DEPLOY_IDLE_TIMEOUT_DAYS | constant | MODIFIED | Type changed uint48->uint32. |
| DeityPassPurchased | event | ADDED | |
| GameOverDrained | event | ADDED | |
| FinalSwept | event | ADDED | |
| BoonConsumed | event | ADDED | |
| AdminSwapEthForStEth | event | ADDED | |
| AdminStakeEthForStEth | event | ADDED | |
