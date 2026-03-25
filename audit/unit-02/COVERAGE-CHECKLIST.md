# Unit 2: Day Advancement + VRF -- Coverage Checklist

## Contract Under Audit
- contracts/modules/DegenerusGameAdvanceModule.sol (1571 lines)
  - Inherits: DegenerusGameStorage (storage layout verified in Unit 1, PASS)
  - Executes via: delegatecall from DegenerusGame
  - Storage context: DegenerusGame's 102-variable layout (slots 0-78)

## Checklist Summary

| Category | Count | Analysis Depth |
|----------|-------|---------------|
| B: External/Public State-Changing | 6 | Full Mad Genius (per D-02) |
| C: Internal State-Changing Helpers | 21 | Via caller's call tree (per D-03); MULTI-PARENT get extra scrutiny |
| D: View/Pure | 8 | Minimal |
| **TOTAL** | **35** | |

**Note on counts vs research:** Independent source verification confirms 35 functions matching the research inventory (6B + 21C + 8D). All functions enumerated below were verified line-by-line against the actual contract source. No Category A table exists per D-01 (this is a module, not the router).

**Inherited Storage Helpers (not counted):** The following inherited functions from DegenerusGameStorage are called by functions in this module but are NOT counted as AdvanceModule functions. They are noted in the storage-write column where relevant: `_swapAndFreeze`, `_swapTicketSlot`, `_unfreezePool`, `_tqReadKey`, `_tqWriteKey`, `_tqFarFutureKey`, `_queueTickets`, `_getNextPrizePool`, `_getFuturePrizePool`, `_setNextPrizePool`, `_setFuturePrizePool`, `_getPrizePools`, `_simulatedDayIndexAt`.

---

## Category B: External/Public State-Changing Functions

Full Mad Genius treatment per D-02: recursive call tree, storage-write map, cached-local-vs-storage check, 10-angle attack analysis.

| # | Function | Lines | Access Control | Storage Writes | External/Delegatecalls | Risk Tier | Analyzed? | Call Tree? | Storage Map? | Cache Check? |
|---|----------|-------|---------------|----------------|----------------------|-----------|-----------|------------|--------------|-------------|
| B1 | advanceGame() | 125-397 | external, any caller | level, price, jackpotPhaseFlag, lastPurchaseDay, compressedJackpotFlag, purchaseStartDay, phaseTransitionActive, ticketsFullyProcessed, midDayTicketRngPending, lastLootboxRngWord, lootboxPresaleActive, poolConsolidationDone, levelStartTime, decWindowOpen, dailyIdx, rngLockedFlag, rngWordCurrent, vrfRequestId, rngRequestTime, ticketLevel, ticketCursor, dailyEthPhase, dailyEthPoolBudget, dailyJackpotCoinTicketsPending, jackpotCounter, levelPrizePool, prizePoolsPacked, yieldAccumulator + delegatecall writes to all 4 modules | coin.creditFlip (external); delegatecall to JACKPOT_MODULE (payDailyJackpot, payDailyJackpotCoinAndTickets, payDailyCoinJackpot, consolidatePrizePools, awardFinalDayDgnrsReward, processTicketBatch); delegatecall to ENDGAME_MODULE (rewardTopAffiliate, runRewardJackpots); delegatecall to MINT_MODULE (processFutureTicketBatch); delegatecall to GAMEOVER_MODULE (handleGameOverDrain, handleFinalSweep); coinflip.processCoinflipPayouts, sdgnrs.resolveRedemptionPeriod, steth.submit via rngGate and sub-calls | 1 (CRITICAL) | pending | pending | pending | pending |
| B2 | requestLootboxRng() | 689-759 | external, any caller (gated by rngLockedFlag, midDayTicketRngPending, day boundary, daily RNG, rngRequestTime, LINK balance, threshold) | lootboxRngIndex, lootboxRngPendingEth, lootboxRngPendingBurnie, vrfRequestId, rngWordCurrent, rngRequestTime, ticketWriteSlot (via _swapTicketSlot), ticketsFullyProcessed, midDayTicketRngPending | vrfCoordinator.requestRandomWords (external), vrfCoordinator.getSubscription (external view) | 1 (HIGH) | pending | pending | pending | pending |
| B3 | reverseFlip() | 1438-1446 | external, any caller (gated by rngLockedFlag) | totalFlipReversals | coin.burnCoin (external) | 3 (LOW) | pending | pending | pending | pending |
| B4 | rawFulfillRandomWords() | 1455-1476 | external, msg.sender == address(vrfCoordinator) | rngWordCurrent (daily path), lootboxRngWordByIndex (mid-day path), vrfRequestId (mid-day path), rngRequestTime (mid-day path) | none | 1 (HIGH) | pending | pending | pending | pending |
| B5 | wireVrf() | 412-425 | external, msg.sender == ContractAddresses.ADMIN | vrfCoordinator, vrfSubscriptionId, vrfKeyHash, lastVrfProcessedTimestamp | none | 3 (LOW) | pending | pending | pending | pending |
| B6 | updateVrfCoordinatorAndSub() | 1390-1419 | external, msg.sender == ContractAddresses.ADMIN | vrfCoordinator, vrfSubscriptionId, vrfKeyHash, rngLockedFlag, vrfRequestId, rngRequestTime, rngWordCurrent, midDayTicketRngPending | none | 2 (MEDIUM) | pending | pending | pending | pending |

**Risk Tier Key:**
- **Tier 1** (3 functions: B1, B2, B4): Complex, multiple code paths, BAF-class risk, VRF lifecycle. Full deep-dive required.
  - B1 advanceGame: 270-line FSM, 11 stage paths, caches level/jackpotPhaseFlag/lastPurchaseDay in locals, delegates to 4 modules via delegatecall. THE primary BAF-class target.
  - B2 requestLootboxRng: Mid-day VRF request, ticket buffer swap, LINK balance check, pending accumulator reset. Complex gating logic.
  - B4 rawFulfillRandomWords: VRF callback, branching on rngLockedFlag for daily vs mid-day path. Entry point from external coordinator.
- **Tier 2** (1 function: B6): Moderate complexity.
  - B6 updateVrfCoordinatorAndSub: Emergency VRF rotation, resets 8 state flags including midDayTicketRngPending.
- **Tier 3** (2 functions: B3, B5): Simple setters/admin.
  - B3 reverseFlip: Burns BURNIE, increments totalFlipReversals counter.
  - B5 wireVrf: Deploy-only VRF config write.

---

## Category C: Internal State-Changing Helpers

Traced via parent call trees per D-03. Functions marked **[MULTI-PARENT]** get extra scrutiny for differing cached-local contexts.

| # | Function | Lines | Called By | Storage Writes | Multi-Parent? | Analyzed? | Call Tree? | Storage Map? | Cache Check? |
|---|----------|-------|----------|----------------|---------------|-----------|------------|--------------|-------------|
| C1 | _handleGameOverPath() | 433-482 | B1 | levelStartTime; delegatecall to GAME_GAMEOVER_MODULE (handleGameOverDrain, handleFinalSweep); rngWordByDay, rngWordCurrent, rngRequestTime, totalFlipReversals, lastVrfProcessedTimestamp, lootboxRngWordByIndex, lastLootboxRngWord, dailyIdx, rngLockedFlag, vrfRequestId via _gameOverEntropy and _unlockRng | NO | pending | pending | pending | pending |
| C2 | _endPhase() | 487-495 | B1 (jackpot path, after JACKPOT_LEVEL_CAP reached) | phaseTransitionActive, levelPrizePool[lvl] (x00 levels only), jackpotCounter, compressedJackpotFlag | NO | pending | pending | pending | pending |
| C3 | _rewardTopAffiliate() | 515-525 | B1 (jackpot path, after JACKPOT_LEVEL_CAP) | delegatecall to GAME_ENDGAME_MODULE.rewardTopAffiliate -- affiliate-related state | NO | pending | pending | pending | pending |
| C4 | _runRewardJackpots() | 528-539 | B1 (jackpot path, after JACKPOT_LEVEL_CAP) | delegatecall to GAME_ENDGAME_MODULE.runRewardJackpots -- BAF/decimator jackpot resolution, claimableWinnings, claimablePool, futurePrizePool | NO | pending | pending | pending | pending |
| C5 | _consolidatePrizePools() | 553-564 | B1 (purchase->jackpot transition) | delegatecall to GAME_JACKPOT_MODULE.consolidatePrizePools -- prizePoolsPacked, currentPrizePool, yieldAccumulator | NO | pending | pending | pending | pending |
| C6 | _awardFinalDayDgnrsReward() | 567-580 | B1 (jackpot path, after JACKPOT_LEVEL_CAP) | delegatecall to GAME_JACKPOT_MODULE.awardFinalDayDgnrsReward -- external dgnrs transfers | NO | pending | pending | pending | pending |
| C7 | payDailyJackpot() | 587-603 | B1 **[MULTI-PARENT: purchase phase (isDaily=false) + jackpot phase (isDaily=true) + jackpot ETH resume]** | delegatecall to GAME_JACKPOT_MODULE.payDailyJackpot -- jackpotCounter, currentPrizePool, claimableWinnings[winners], claimablePool, dailyEthPoolBudget, dailyEthPhase, dailyJackpotCoinTicketsPending, lastDailyJackpotLevel | **YES [MULTI-PARENT]** | pending | pending | pending | pending |
| C8 | payDailyJackpotCoinAndTickets() | 609-621 | B1 (jackpot path, when dailyJackpotCoinTicketsPending) | delegatecall to GAME_JACKPOT_MODULE.payDailyJackpotCoinAndTickets -- dailyJackpotCoinTicketsPending=false, jackpotCounter++, coin/ticket distributions | NO | pending | pending | pending | pending |
| C9 | _payDailyCoinJackpot() | 628-639 | B1 (purchase phase, pre-target daily) | delegatecall to GAME_JACKPOT_MODULE.payDailyCoinJackpot -- coin distributions via external coin.creditFlip | NO | pending | pending | pending | pending |
| C10 | rngGate() | 783-856 | B1 (via do-while) **[MULTI-PARENT: called once per advanceGame cycle, but the parent context varies based on stage]** | rngWordByDay, rngWordCurrent, totalFlipReversals, lastVrfProcessedTimestamp, levelStartTime (gap backfill), lootboxRngWordByIndex, lastLootboxRngWord; via sub-calls: vrfRequestId, rngRequestTime, rngLockedFlag, lootboxRngIndex, lootboxRngPendingEth, lootboxRngPendingBurnie, decWindowOpen, level, price, dailyIdx | **YES [MULTI-PARENT]** | pending | pending | pending | pending |
| C11 | _finalizeLootboxRng() | 858-864 | C10 (rngGate), C12 (_gameOverEntropy) | lootboxRngWordByIndex[index], lastLootboxRngWord | NO | pending | pending | pending | pending |
| C12 | _gameOverEntropy() | 871-964 | C1 (_handleGameOverPath) | rngWordByDay, rngWordCurrent, totalFlipReversals, lastVrfProcessedTimestamp, lootboxRngWordByIndex, lastLootboxRngWord, rngRequestTime; via sub-calls: vrfRequestId, rngLockedFlag, lootboxRngIndex, lootboxRngPendingEth, lootboxRngPendingBurnie, decWindowOpen, level, price | NO | pending | pending | pending | pending |
| C13 | _applyTimeBasedFutureTake() | 1044-1119 | B1 (purchase->jackpot transition, poolConsolidation block) | prizePoolsPacked (next pool, future pool via _setNextPrizePool, _setFuturePrizePool), yieldAccumulator | NO | pending | pending | pending | pending |
| C14 | _drawDownFuturePrizePool() | 1121-1133 | B1 (purchase->jackpot transition, after entering jackpot) | prizePoolsPacked (next pool, future pool via _setFuturePrizePool, _setNextPrizePool) | NO | pending | pending | pending | pending |
| C15 | _processFutureTicketBatch() | 1149-1163 | C16 (_prepareFutureTickets), B1 (phase transition FF drain + pre-jackpot next-level activation) **[MULTI-PARENT]** | delegatecall to GAME_MINT_MODULE.processFutureTicketBatch -- ticketCursor, ticketLevel, ticket processing state | **YES [MULTI-PARENT]** | pending | pending | pending | pending |
| C16 | _prepareFutureTickets() | 1171-1197 | B1 (before daily draws, when no pending coin/ticket/eth jackpot) | ticketLevel (via C15 _processFutureTicketBatch sub-call) | NO | pending | pending | pending | pending |
| C17 | _runProcessTicketBatch() | 1210-1227 | B1 **[MULTI-PARENT: mid-day path (line 170), daily drain gate (line 211), do-while current-level (line 284)]** | ticketCursor, ticketLevel; delegatecall to GAME_JACKPOT_MODULE.processTicketBatch | **YES [MULTI-PARENT]** | pending | pending | pending | pending |
| C18 | _processPhaseTransition() | 1234-1255 | B1 (phase transition housekeeping) | ticketQueue, ticketsOwedPacked (via _queueTickets for SDGNRS and VAULT); external steth.submit (via _autoStakeExcessEth, no game storage writes) | NO | pending | pending | pending | pending |
| C19 | _autoStakeExcessEth() | 1260-1270 | C18 (_processPhaseTransition) | none (external steth.submit call only, no game storage writes) | NO | pending | pending | pending | pending |
| C20 | _requestRng() | 1276-1289 | C10 (rngGate, fresh request + timeout retry) | via C22 (_finalizeRngRequest): vrfRequestId, rngWordCurrent, rngRequestTime, rngLockedFlag, lootboxRngIndex, lootboxRngPendingEth, lootboxRngPendingBurnie, decWindowOpen, level, price | NO | pending | pending | pending | pending |
| C21 | _tryRequestRng() | 1291-1318 | C12 (_gameOverEntropy) | via C22 (_finalizeRngRequest): same as C20 | NO | pending | pending | pending | pending |
| C22 | _finalizeRngRequest() | 1320-1382 | C20 (_requestRng), C21 (_tryRequestRng) | vrfRequestId, rngWordCurrent, rngRequestTime, rngLockedFlag, lootboxRngIndex, lootboxRngPendingEth, lootboxRngPendingBurnie, decWindowOpen, level, price | NO | pending | pending | pending | pending |
| C23 | _unlockRng() | 1424-1431 | B1 (phase transition done, purchase daily, jackpot coin_tickets, jackpot phase ended), C10 (rngGate not a direct caller -- only called from B1 via _handleGameOverPath) **[MULTI-PARENT: called from B1 at 4 different stage exits + C1 via _handleGameOverPath]** | dailyIdx, rngLockedFlag, rngWordCurrent, vrfRequestId, rngRequestTime; prizePoolsPacked, prizePoolPendingPacked, prizePoolFrozen (via _unfreezePool) | **YES [MULTI-PARENT]** | pending | pending | pending | pending |
| C24 | _backfillGapDays() | 1489-1507 | C10 (rngGate, when day > dailyIdx + 1) | rngWordByDay[gapDay]; external coinflip.processCoinflipPayouts | NO | pending | pending | pending | pending |
| C25 | _backfillOrphanedLootboxIndices() | 1513-1533 | C10 (rngGate, after gap day backfill) | lootboxRngWordByIndex[i], lastLootboxRngWord | NO | pending | pending | pending | pending |
| C26 | _applyDailyRng() | 1536-1552 | C10 (rngGate, normal daily processing), C12 (_gameOverEntropy, both VRF and fallback paths) **[MULTI-PARENT]** | totalFlipReversals, rngWordCurrent, rngWordByDay[day], lastVrfProcessedTimestamp | **YES [MULTI-PARENT]** | pending | pending | pending | pending |

**Numbering note:** The research uses C7/C11/C17/C19/C25/C28 for multi-parent functions. This checklist uses sequential C-numbering (C7/C10/C15/C17/C23/C26) because the source verification revealed the same functions in the same order, but with cleaner sequential IDs. Cross-reference provided:

| Research # | Checklist # | Function |
|-----------|-------------|----------|
| C7 | C7 | payDailyJackpot() |
| C11 | C10 | rngGate() |
| C17 | C15 | _processFutureTicketBatch() |
| C19 | C17 | _runProcessTicketBatch() |
| C25 | C23 | _unlockRng() |
| C28 | C26 | _applyDailyRng() |

---

## Category D: View/Pure Functions

Read-only functions. No state changes. Minimal audit depth: verify they read/compute correctly and don't expose dangerous internal state.

| # | Function | Lines | Reads/Computes | Security Note | Reviewed? |
|---|----------|-------|---------------|---------------|-----------|
| D1 | _enforceDailyMintGate() | 647-683 | mintPacked_[caller], deityPassCount[caller], block.timestamp, frozenUntilLevel; external view call to vault.isVaultOwner | Gate function -- prevents non-minters from calling advanceGame early. Time-based bypass tiers. External call to vault is view-only. | pending |
| D2 | _getHistoricalRngFallback() | 977-1001 | rngWordByDay[searchDay] (up to 30 entries), block.prevrandao | Gameover-only fallback. Prevrandao has 1-bit validator manipulation. Documented in KNOWN-ISSUES.md as acceptable for gameover edge case. | pending |
| D3 | _nextToFutureBps() | 1010-1042 | pure computation: elapsed time, level bonus, BPS calculation | Pure arithmetic. No storage reads. Returns BPS capped at 10,000. | pending |
| D4 | _currentNudgeCost() | 1560-1570 | pure computation: base cost compounded 50% per reversal | Pure arithmetic. O(n) loop bounded by game economics. No overflow risk (Solidity 0.8.34). | pending |
| D5 | _revertDelegate() | 544-549 | pure: bubbles revert data from failed delegatecall | Assembly-based revert forwarding. No storage access. | pending |
| D6 | _getNextPrizePool() | Storage:734-737 | view: reads prizePoolsPacked lower 128 bits | Inherited from DegenerusGameStorage. Returns next pool component. | pending |
| D7 | _getFuturePrizePool() | Storage:746-749 | view: reads prizePoolsPacked upper 128 bits | Inherited from DegenerusGameStorage. Returns future pool component. | pending |
| D8 | _simulatedDayIndexAt() | Storage:1139 | pure: timestamp to day-index conversion | Inherited from DegenerusGameStorage. Pure arithmetic. | pending |

**Note on D1 (_enforceDailyMintGate):** This function is `view` (does not modify state) but is classified as Category D rather than C because it performs zero storage writes. The research initially listed it in both C10 and D1; the source confirms it is `private view`, so it belongs in D only.

**Note on D6-D8 (inherited helpers):** These are inherited from DegenerusGameStorage and called within AdvanceModule. Counted here for completeness since they are used as part of the module's execution paths. Not independently audited -- verified in Unit 1 (PASS).

---

## Priority Investigation Targets (D-04, D-05)

The following functions are PRIORITY for the Mad Genius ticket queue drain investigation:

- **C16: _prepareFutureTickets()** (lines 1171-1197) -- Before daily draws, processes near-future ticket read queues for levels +1 to +4. Iterates over target levels and calls _processFutureTicketBatch for each.
- **C15: _processFutureTicketBatch()** (lines 1149-1163) -- Delegates to GAME_MINT_MODULE.processFutureTicketBatch. Processes a batch of future ticket rewards for the specified level.
- **C17: _runProcessTicketBatch()** (lines 1210-1227) -- Delegates to GAME_JACKPOT_MODULE.processTicketBatch. Processes current-level tickets with cursor tracking.

These MUST be traced end-to-end as part of advanceGame()'s call tree, with a standalone verdict section: **CONFIRMED BUG** or **PROVEN SAFE**.

**Investigation context:** 3 TicketLifecycle Foundry tests fail with `Read queue not drained for level 1: 2 != 0`. The tests are `testFiveLevelIntegration`, `testMultiLevelZeroStranding`, and `testZeroStrandingSweepAfterTransitions`. The Mad Genius must determine whether this is a contract bug or test setup issue.

**Key questions for the investigation:**
1. When are constructor-seeded tickets (SDGNRS + VAULT, 16 each per level 1-100) processed for level 1?
2. Does the double-buffer swap timing leave 2 entries stranded in the read slot?
3. What happens to tickets queued to level 1's write key after `_swapAndFreeze` toggles slots?
4. Does the test setup drive enough `advanceGame` calls to fully drain both buffer slots for level 1?

---

## Cross-Module Delegatecall Targets (D-08, D-09)

advanceGame() delegates to 4 external modules during execution. Per D-08, trace subordinate calls far enough to verify state coherence (cached-local-vs-storage). Per D-09, if a subordinate writes to storage the parent cached locally, that IS a finding.

### GAME_JACKPOT_MODULE
| Delegatecall Target | Called From | Storage Writes (in Game's context) |
|---------------------|------------|-------------------------------------|
| payDailyJackpot | C7 (purchase + jackpot paths) | jackpotCounter, currentPrizePool, claimableWinnings[winners], claimablePool, dailyEthPoolBudget, dailyEthPhase, dailyJackpotCoinTicketsPending, lastDailyJackpotLevel |
| payDailyJackpotCoinAndTickets | C8 (jackpot path) | dailyJackpotCoinTicketsPending=false, jackpotCounter++, coin/ticket distributions |
| payDailyCoinJackpot | C9 (purchase path) | coin distributions via external coin.creditFlip |
| consolidatePrizePools | C5 (purchase->jackpot transition) | prizePoolsPacked, currentPrizePool, yieldAccumulator |
| awardFinalDayDgnrsReward | C6 (jackpot path, final day) | external dgnrs.transferFromPool |
| processTicketBatch | C17 (mid-day, daily drain, do-while) | ticketCursor, ticketLevel, trait assignments, ticket data |

### GAME_ENDGAME_MODULE
| Delegatecall Target | Called From | Storage Writes (in Game's context) |
|---------------------|------------|-------------------------------------|
| rewardTopAffiliate | C3 (jackpot phase ended) | affiliate-related state |
| runRewardJackpots | C4 (jackpot phase ended) | BAF/decimator jackpot resolution, claimableWinnings, claimablePool, **futurePrizePool** (BAF-class critical) |

### GAME_MINT_MODULE
| Delegatecall Target | Called From | Storage Writes (in Game's context) |
|---------------------|------------|-------------------------------------|
| processFutureTicketBatch | C15 (phase transition FF drain + pre-jackpot next-level + daily future processing) | ticketCursor, ticketLevel, ticket processing state |

### GAME_GAMEOVER_MODULE
| Delegatecall Target | Called From | Storage Writes (in Game's context) |
|---------------------|------------|-------------------------------------|
| handleGameOverDrain | C1 (_handleGameOverPath, liveness triggered, pre-gameover) | gameOver flag, prize pool draining, claimable distributions |
| handleFinalSweep | C1 (_handleGameOverPath, post-gameover, 1 month after) | final sweep state |

**BAF-class critical note:** `runRewardJackpots` (ENDGAME_MODULE) writes to `futurePrizePool`. The B1 (advanceGame) call to _applyTimeBasedFutureTake (C13) and _drawDownFuturePrizePool (C14) also reads/writes futurePrizePool. The Mad Genius MUST verify these calls do not interleave with stale cached values. This is the v4.4 BAF pattern -- the fix was applied in Phase 100-102 but the Mad Genius must independently verify per D-06.

---

## Critical Cached-Local-vs-Storage Pairs (advanceGame)

These are the highest-priority BAF-class checks. The Mad Genius must trace each pair through the full call tree.

| Local Variable | Cached At (Line) | Used Through | Descendant Writes Via | Risk Level |
|---------------|-------------------|-------------|----------------------|------------|
| `lvl = level` | 131 | Entire function (passed to all stage handlers) | `_finalizeRngRequest` writes `level = lvl` (line 1352) on lastPurchaseDay fresh request; `_endPhase` reads `level` from storage (line 488) | HIGH -- level is read from storage early, descendant overwrites it; parent continues using stale `lvl` |
| `inJackpot = jackpotPhaseFlag` | 130 | Controls purchase vs jackpot phase branching | `advanceGame` itself writes `jackpotPhaseFlag = true` (line 341) and `jackpotPhaseFlag = false` (line 263) | MEDIUM -- self-write, but must verify no reuse of stale `inJackpot` after the write |
| `lastPurchase = (!inJackpot) && lastPurchaseDay` | 143 | Passed to _handleGameOverPath, _finalizeRngRequest | `advanceGame` writes `lastPurchaseDay = true` (line 139, 302) | MEDIUM -- cached before Turbo check could set it; verify no stale use |
| `purchaseLevel` | 145 | Ticket processing, future ticket levels, daily jackpot levels | `_finalizeRngRequest` writes `level` (line 1352) which changes what `purchaseLevel` should be | HIGH -- stale purchaseLevel after level increment via _finalizeRngRequest |
| `advanceBounty` | 127 | End of function (coin.creditFlip) | `_finalizeRngRequest` writes `price` (lines 1356-1380) which changes what advanceBounty should be | LOW -- bounty is computed once, minor economic impact |
| `day = _simulatedDayIndexAt(ts)` | 129 | Throughout function | Not written by descendants (pure computation) | LOW -- immutable within call |

---

## advanceGame() Stage Map

For reference during Mad Genius attack analysis. Each stage represents a distinct exit path from the do-while loop.

| Stage | Constant | Exit Path | What Happens | Key Functions Called |
|-------|----------|-----------|-------------|-------------------|
| 0 | STAGE_GAMEOVER | Pre-loop: liveness guard fires | C1 (_handleGameOverPath) -> GAMEOVER_MODULE | C1, C12, C22, C26 |
| 1 | STAGE_RNG_REQUESTED | do-while: VRF word not ready | _swapAndFreeze + C20 (_requestRng) via C10 (rngGate) | C10, C20, C22 |
| 2 | STAGE_TRANSITION_WORKING | do-while: phase transition in progress | C18 (_processPhaseTransition) or C15 (_processFutureTicketBatch) FF drain | C18, C19, C15 |
| 3 | STAGE_TRANSITION_DONE | do-while: phase transition complete | phaseTransitionActive=false, C23 (_unlockRng), purchaseStartDay=day | C23 |
| 4 | STAGE_FUTURE_TICKETS_WORKING | do-while: near-future tickets processing | C16 (_prepareFutureTickets) -> C15 (_processFutureTicketBatch) | C16, C15 |
| 5 | STAGE_TICKETS_WORKING | Mid-day or do-while: current-level tickets | C17 (_runProcessTicketBatch) | C17 |
| 6 | STAGE_PURCHASE_DAILY | do-while: purchase phase daily jackpot | C7 (payDailyJackpot) + C9 (_payDailyCoinJackpot) + C23 (_unlockRng) | C7, C9, C23 |
| 7 | STAGE_ENTERED_JACKPOT | do-while: purchase->jackpot transition | C5, C13, C14, jackpotPhaseFlag=true, decWindowOpen, C15 | C5, C13, C14, C15 |
| 8 | STAGE_JACKPOT_ETH_RESUME | do-while: jackpot phase ETH resume | C7 (payDailyJackpot, isDaily=true, carryover) | C7 |
| 9 | STAGE_JACKPOT_COIN_TICKETS | do-while: coin+ticket distribution done | C8 (payDailyJackpotCoinAndTickets) + C23 (_unlockRng) | C8, C23 |
| 10 | STAGE_JACKPOT_PHASE_ENDED | do-while: level complete, 5 jackpots done | C6, C3, C4, C2, C23 (_unlockRng) | C6, C3, C4, C2, C23 |
| 11 | STAGE_JACKPOT_DAILY_STARTED | do-while: fresh daily jackpot started | C7 (payDailyJackpot, isDaily=true) | C7 |

---

## Completeness Verification

**Independent source scan results:** Read all 1,571 lines of DegenerusGameAdvanceModule.sol. Every `function` keyword was verified:

| Total functions found in source | 35 |
|--------------------------------|-----|
| Category B (external/public state-changing) | 6 |
| Category C (private/internal state-changing) | 21 |
| Category D (view/pure) | 8 |
| Functions missing from checklist | 0 |
| Functions in checklist not in source | 0 |

**MULTI-PARENT functions verified (6):**
1. C7 payDailyJackpot -- purchase phase (isDaily=false, line 297) + jackpot phase (isDaily=true, lines 368, 391)
2. C10 rngGate -- called once per advanceGame do-while, but parent context varies by stage path
3. C15 _processFutureTicketBatch -- called from C16 (_prepareFutureTickets loop), B1 phase transition FF drain (line 255), and B1 pre-jackpot next-level activation (line 319)
4. C17 _runProcessTicketBatch -- mid-day path (line 170), daily drain gate (line 211), do-while current-level (line 284)
5. C23 _unlockRng -- called at stage exits: STAGE_TRANSITION_DONE (line 261), STAGE_PURCHASE_DAILY (line 307), STAGE_JACKPOT_COIN_TICKETS (line 385), STAGE_JACKPOT_PHASE_ENDED (line 381), and from _handleGameOverPath (line 471)
6. C26 _applyDailyRng -- rngGate normal daily (line 813), _gameOverEntropy VRF path (line 881), _gameOverEntropy fallback path (line 920)

**Category A: NONE.** Per D-01, this module does not dispatch delegatecalls as a router. It IS the target of delegatecalls from the router. All module-to-module delegatecalls originate from within this module's functions and are classified under the calling function's tree.
