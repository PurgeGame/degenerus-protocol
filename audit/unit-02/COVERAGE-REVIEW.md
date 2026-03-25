# Unit 2: Day Advancement + VRF -- Coverage Review

**Agent:** Taskmaster (Coverage Enforcer)
**Contract:** DegenerusGameAdvanceModule.sol (1,571 lines)
**Date:** 2026-03-25
**Attack Report Reviewed:** audit/unit-02/ATTACK-REPORT.md
**Checklist:** audit/unit-02/COVERAGE-CHECKLIST.md

---

## Coverage Matrix

| Category | Total | Analyzed | Call Tree Complete | Storage Writes Complete | Cache Check Done |
|----------|-------|----------|-------------------|----------------------|-----------------|
| B: External | 6 | 6/6 | 6/6 | 6/6 | 6/6 |
| C: Internal | 26 | 26/26 | via caller | via caller | via caller |
| D: View | 8 | 8/8 | N/A | N/A | N/A |

**Note:** The checklist header states "21 C" but the actual table contains 26 C entries (C1-C26). All 26 are analyzed. The header count is a display error; the actual coverage is complete.

---

## Spot-Check Results

### advanceGame() [B1]

**Interrogation questions and verification:**

1. **"advanceGame caches `lvl = level` at line 131. Your call tree shows rngGate calls _requestRng which calls _finalizeRngRequest which writes `level` at line 1352. Did you trace what happens to `lvl` AFTER rngGate returns?"**

   **Answer verified:** YES. The attack report explicitly addresses this as Critical Pair 1 (lines 256-267). When `_finalizeRngRequest` writes `level = lvl` at line 1352, `rngGate` returns 1. The do-while breaks at STAGE_RNG_REQUESTED (line 235). The stale `lvl` is only used in the event emission (line 395) and `creditFlip` (which does not use `lvl`). I verified this against the source: confirmed, lines 232-235 show the immediate break, and line 395 only uses `lvl` in the event.

2. **"You listed N storage writes for advanceGame's full tree, but the delegatecall to JACKPOT_MODULE.payDailyJackpot writes to jackpotCounter, currentPrizePool, claimableWinnings, claimablePool, dailyEthPoolBudget, dailyEthPhase, dailyJackpotCoinTicketsPending, lastDailyJackpotLevel. Are ALL of these in your storage write map?"**

   **Answer verified:** YES. The attack report's "Writes via delegatecall to JACKPOT_MODULE (payDailyJackpot, etc.)" section (lines 204-217 of ATTACK-REPORT) lists all 13 storage writes: `jackpotCounter`, `currentPrizePool`, `claimableWinnings[winners]`, `claimablePool`, `dailyEthPoolBudget`, `dailyEthPhase`, `dailyJackpotCoinTicketsPending`, `lastDailyJackpotLevel`, `dailyTicketBudgetsPacked`, `dailyCarryoverEthPool`, `dailyCarryoverWinnerCap`, `lastDailyJackpotWinningTraits`, `lastDailyJackpotDay`. All present.

3. **"advanceGame has 11 stage paths. You only analyzed M. What about stage N?"**

   **Answer verified:** The attack report section "Conditional Paths (all 11 stages + pre-loop)" explicitly covers all 12 paths (Stage 0-11 plus mid-day). Each stage has a dedicated paragraph with SAFE verdict. I verified: Stages 0 (GAMEOVER), 1 (RNG_REQUESTED), 2 (TRANSITION_WORKING), 3 (TRANSITION_DONE), 4 (FUTURE_TICKETS_WORKING), 5 (TICKETS_WORKING), 6 (PURCHASE_DAILY), 7 (ENTERED_JACKPOT), 8 (JACKPOT_ETH_RESUME), 9 (JACKPOT_COIN_TICKETS), 10 (JACKPOT_PHASE_ENDED), 11 (JACKPOT_DAILY_STARTED), and the mid-day path. All covered.

**Call tree verified: YES** -- Full recursive expansion present with line numbers for every call. All 11 stage paths and the mid-day path are in the call tree.

**All 11 stage paths covered: YES** -- Each stage has explicit analysis in the "Conditional Paths" section.

**Storage writes verified: YES** -- All direct writes, sub-call writes (rngGate, _requestRng, _unlockRng, _swapAndFreeze), delegatecall writes (JACKPOT x6, ENDGAME x2, MINT x1, GAMEOVER x2) are listed with line numbers.

**Cached-local pairs verified: YES** -- All 6 critical pairs from the checklist are addressed with dedicated analysis: lvl/level, inJackpot/jackpotPhaseFlag, lastPurchase/lastPurchaseDay, purchaseLevel/level, advanceBounty/price, day (immutable).

### rawFulfillRandomWords() [B4]

**Interrogation questions and verification:**

1. **"The mid-day path sets lootboxRngWordByIndex[index] but does NOT update lastLootboxRngWord. Is this intentional?"**

   **Answer verified:** YES. The attack report flags this as F-04 (INFO). I verified against source lines 1468-1475: the mid-day path writes to `lootboxRngWordByIndex[index]` and clears VRF state but does not set `lastLootboxRngWord`. The report correctly identifies this as a convenience variable staleness with no functional impact.

2. **"The early return at line 1460 silently discards duplicate fulfillments. Is this safe?"**

   **Answer verified:** YES. The attack report addresses this under "Silent Failures" for B4: "The early return at line 1460 (requestId mismatch or duplicate) is a silent no-op. This is intentional -- Chainlink may deliver late responses for replaced requests." Source confirmed: `if (requestId != vrfRequestId || rngWordCurrent != 0) return` at line 1460.

**Call tree verified: YES** -- Simple branching on `rngLockedFlag`, no subordinate calls.
**Storage writes verified: YES** -- Daily path writes `rngWordCurrent`, mid-day writes `lootboxRngWordByIndex[index]`, `vrfRequestId`, `rngRequestTime`.
**Cached-local pairs verified: YES** -- `word` from calldata (no cache issue), `index = lootboxRngIndex - 1` read once.

### requestLootboxRng() [B2]

**Interrogation questions and verification:**

1. **"The ticket buffer swap at lines 731-738 only fires when `ticketQueue[wk].length > 0 && ticketsFullyProcessed`. What happens if ticketsFullyProcessed is false?"**

   **Answer verified:** YES. The attack report addresses this under "Conditional Paths": "If the write queue is empty or read queue not yet drained, no swap occurs. In both cases, the VRF request proceeds normally." When `ticketsFullyProcessed == false`, the swap is skipped and `midDayTicketRngPending` is NOT set. Source confirmed at lines 734-737.

2. **"lootboxRngPendingEth and lootboxRngPendingBurnie are read then zeroed. Is this a cache-overwrite pattern?"**

   **Answer verified:** YES. The report explicitly addresses this: "pendingEth and pendingBurnie at lines 712-713: read from storage, used for threshold comparison. Later zeroed (lines 754-755). The zero is the intended new value, not a stale write-back. Safe."

**Call tree verified: YES** -- Complete tree with VRF request, ticket buffer swap, threshold checks.
**Storage writes verified: YES** -- 9 writes listed with line numbers.
**Cached-local pairs verified: YES** -- Explicit analysis of `purchaseLevel_`, `pendingEth`, `pendingBurnie`, `priceWei`, `linkBal`.

---

## Cross-Module Delegatecall Coverage

### GAME_JACKPOT_MODULE (6 entry points)

| Target | Storage Write List Present | Cached-Local Conflict Check | Verdict |
|--------|---------------------------|---------------------------|---------|
| payDailyJackpot | YES (13 variables) | YES -- no parent cached local conflicts | SAFE |
| payDailyJackpotCoinAndTickets | YES | YES -- jackpotCounter read post-return from storage (line 376) | SAFE |
| payDailyCoinJackpot | YES (no game storage writes) | YES -- N/A (external calls only) | SAFE |
| consolidatePrizePools | YES (prizePoolsPacked, currentPrizePool, yieldAccumulator) | YES -- _applyTimeBasedFutureTake runs BEFORE, fresh SLOAD reads | SAFE |
| awardFinalDayDgnrsReward | YES (external dgnrs.transferFromPool only) | YES -- N/A | SAFE |
| processTicketBatch | YES (ticketCursor, ticketLevel, traitBurnTicket, ticketQueue, ticketsOwedPacked) | YES -- prevCursor/prevLevel cached for comparison only (not writeback) | SAFE |

### GAME_ENDGAME_MODULE (2 entry points)

| Target | Storage Write List Present | Cached-Local Conflict Check | Verdict |
|--------|---------------------------|---------------------------|---------|
| rewardTopAffiliate | YES (affiliate-related state) | YES -- no parent cached conflicts | SAFE |
| runRewardJackpots | YES (claimableWinnings, claimablePool, prizePoolsPacked/futurePrizePool) | YES -- explicit BAF-class analysis: parent does NOT cache or write-back prizePoolsPacked; prize pool frozen during jackpot phase prevents interleaving | SAFE |

### GAME_MINT_MODULE (1 entry point)

| Target | Storage Write List Present | Cached-Local Conflict Check | Verdict |
|--------|---------------------------|---------------------------|---------|
| processFutureTicketBatch | YES (ticketCursor, ticketLevel, ticketQueue, ticketsOwedPacked, traitBurnTicket) | YES -- parent sets ticketLevel/ticketCursor before call, reads return value after; no stale writeback | SAFE |

### GAME_GAMEOVER_MODULE (2 entry points)

| Target | Storage Write List Present | Cached-Local Conflict Check | Verdict |
|--------|---------------------------|---------------------------|---------|
| handleGameOverDrain | YES (gameOver, gameOverTime, claimableWinnings, claimablePool) | YES -- _handleGameOverPath returns true, parent exits immediately | SAFE |
| handleFinalSweep | YES (finalSwept, final sweep state) | YES -- same early-exit pattern | SAFE |

**All 11 delegatecall targets have storage write lists and cached-local checks: CONFIRMED.**

---

## Ticket Queue Drain Investigation Coverage

**D-04 requirement: Dedicated section tracing _prepareFutureTickets and processFutureTicketBatch end-to-end?**
YES. Part 4 of ATTACK-REPORT.md contains a standalone "PRIORITY INVESTIGATION -- Ticket Queue Drain" section with:

1. **Full lifecycle trace:** Queue write (constructor) -> swap -> process -> assertion analysis. Present and detailed.
2. **Double-buffer architecture analysis:** Present with step-by-step buffer state diagram across 3 swaps.
3. **Constructor ticket trace:** Present -- traces SDGNRS + VAULT tickets through `_queueTickets` with explicit key computation.
4. **Test assertion analysis:** Present -- identifies `_readKeyForLevel` as computing from assertion-time `ticketWriteSlot` instead of processing-time slot.
5. **Clear verdict:** PROVEN SAFE (test bug, not contract bug) with root cause analysis.

**D-05 requirement: All 3 failing tests examined?**
YES. The report names all three: `testFiveLevelIntegration`, `testMultiLevelZeroStranding`, `testZeroStrandingSweepAfterTransitions`. Root cause is shared: `_readKeyForLevel` helper uses assertion-time `ticketWriteSlot`.

**Verdict: Investigation requirements D-04 and D-05 are fully satisfied.**

---

## Gaps Found

None.

All 6 Category B functions have:
- Full recursive call tree with line numbers
- Complete storage write map covering direct writes, sub-call writes, and delegatecall writes
- Explicit cached-local-vs-storage check for all 6 critical pairs
- 10-angle attack analysis with per-angle verdicts

All 26 Category C functions are traced within their parent's call tree. All 6 MULTI-PARENT functions (C7, C10, C15, C17, C23, C26) have dedicated cross-parent analysis sections.

All 8 Category D functions have review notes.

All 11 delegatecall targets have storage write lists and cached-local conflict checks.

The ticket queue drain investigation meets both D-04 and D-05 requirements.

### Interrogation Log

No outstanding questions. All interrogation questions from the spot-checks were answered satisfactorily by the attack report with verifiable line numbers.

---

## Verdict: PASS

**All 6 Category B functions have all required sections (call tree, storage write map, cached-local check, 10-angle attack analysis). All 11 delegatecall targets have storage write lists and cached-local conflict checks. All 11 stage paths of advanceGame() are analyzed. The ticket queue drain investigation meets D-04/D-05 requirements with a clear PROVEN SAFE verdict. Coverage is 100%.**

Minor note: The COVERAGE-CHECKLIST.md header states "21 C" functions but the actual table contains 26 entries (C1-C26). This is a header count discrepancy, not a coverage gap. All 26 C functions are present in the table and fully analyzed in the attack report.
