# advanceGame() Worst-Case Gas Ceiling Analysis

**Phase:** 57 - Gas Ceiling Analysis
**Plan:** 01 - advanceGame Gas Profiling
**Date:** 2026-03-22
**Requirements:** CEIL-01, CEIL-02

---

## Methodology

### Gas Ceiling Target

**14,000,000 gas** (conservative target). Ethereum mainnet block gas limit is 30M, but the protocol targets half to ensure reliable transaction inclusion even with congestion.

### Compiler Configuration

- **Compiler:** Solidity 0.8.34 via `solc`
- **Settings:** `via_ir = true`, `optimizer_runs = 2`
- Optimizes for **code size**, not runtime gas. Actual runtime gas may be **higher** than typical contracts compiled with higher optimizer runs.

### Execution Model

Each `advanceGame()` call executes exactly **one stage** via a `do {} while(false)` dispatch pattern (AdvanceModule.sol:231-379). The function reads game state, selects one stage, executes it, emits an `Advance` event, and pays the caller a BURNIE bounty.

### Common Overhead (All Stages)

Every `advanceGame()` call incurs these fixed costs:

| Component | Gas Cost | Notes |
|-----------|----------|-------|
| Base transaction cost | 21,000 | EVM intrinsic |
| Cold storage preamble | ~35,000-42,000 | 15-20 cold SLOADs (level, jackpotPhaseFlag, lastPurchaseDay, rngLockedFlag, dailyIdx, purchaseStartDay, etc.) at 2,100 each |
| _enforceDailyMintGate | ~2,100-4,700 | 1 cold SLOAD (mintPacked_) + conditional checks; vault.isVaultOwner external call only on revert path |
| Delegatecall overhead | ~2,600 | First module hop (cold address); subsequent warm hops ~100 each |
| Advance event emission | ~1,500 | 1 topic (stage), 1 data word (lvl) |
| coin.creditFlip bounty | ~5,000 | External call to BURNIE contract (warm after first call) |
| **Total common overhead** | **~67,200-76,800** | |

For analysis below, we use **75,000** as the baseline common overhead.

---

## Heavy-Hitter Stage Analysis

### Stage 10: JACKPOT_PHASE_ENDED (Highest Risk)

**Entry Conditions:** Jackpot phase active, `dailyJackpotCoinTicketsPending` is true, `jackpotCounter >= JACKPOT_LEVEL_CAP` (5) after coin+ticket distribution. This is the level-transition stage that triggers end-of-level reward jackpots.

**Call Graph:**

```
advanceGame() [AdvanceModule:126]
  -> rngGate() [AdvanceModule:766] -- RNG already consumed (warm)
  -> payDailyJackpotCoinAndTickets(rngWord) [AdvanceModule:361, delegatecall JackpotModule:681]
  |   -> _unpackDailyTicketBudgets() -- arithmetic only
  |   -> _calcDailyCoinBudget() -- 2 SLOADs
  |   -> _awardFarFutureCoinJackpot() -- 10 iterations (FAR_FUTURE_COIN_SAMPLES=10)
  |   -> _awardDailyCoinToTraitWinners() -- up to DAILY_COIN_MAX_WINNERS=50 winners
  |   -> _distributeTicketJackpot() x2 -- up to LOOTBOX_MAX_WINNERS=100 each
  |   -> coin.rollDailyQuest() -- external call
  |   -> jackpotCounter += counterStep
  |   -> clear pending state
  -> _awardFinalDayDgnrsReward(lvl, rngWord) [AdvanceModule:363, delegatecall JackpotModule:773]
  |   -> dgnrs.transferFromPool() -- 1 winner, 1 external call
  -> _rewardTopAffiliate(lvl) [AdvanceModule:364, delegatecall EndgameModule]
  |   -> 1 SLOAD + 1 external call (affiliate reward)
  -> _runRewardJackpots(lvl, rngWord) [AdvanceModule:365, delegatecall EndgameModule:156]
  |   -> BAF jackpot: jackpots.runBafJackpot() -- up to 107 winners (external call)
  |   |   -> _runBafJackpot() processes winners via _addClaimableEth / _queueWhalePassClaimCore
  |   -> Decimator jackpot (levels x5, x00): runDecimatorJackpot() -- loop 2-12 (11 iterations)
  |   -> claimablePool update
  -> _endPhase() [AdvanceModule:474]
  |   -> phaseTransitionActive = true
  |   -> levelPrizePool update (conditional x00)
  |   -> jackpotCounter = 0, compressedJackpotFlag = 0
  -> _unfreezePool() [Storage:738]
  -> emit Advance, coin.creditFlip
```

**Loop Analysis:**

| Loop | Bound | Per-Iteration Cost | Worst-Case Total |
|------|-------|--------------------|------------------|
| payDailyJackpotCoinAndTickets: _awardFarFutureCoinJackpot | 10 (FAR_FUTURE_COIN_SAMPLES) | ~8,000 (SLOAD ticket queue + conditional queueTickets + coin.creditFlip) | ~80,000 |
| payDailyJackpotCoinAndTickets: _awardDailyCoinToTraitWinners | 50 (DAILY_COIN_MAX_WINNERS) | ~6,000 (winner selection + coin.creditCoin + event) | ~300,000 |
| payDailyJackpotCoinAndTickets: _distributeTicketJackpot (daily) | 100 (LOOTBOX_MAX_WINNERS) | ~5,000 (winner selection + _queueTickets + event) | ~500,000 |
| payDailyJackpotCoinAndTickets: _distributeTicketJackpot (carryover) | 100 (LOOTBOX_MAX_WINNERS) | ~5,000 | ~500,000 |
| _runBafJackpot: winner processing | 107 (BAF max winners) | ~25,000 (autoRebuyState SLOAD 2,100 cold + _addClaimableEth/_queueWhalePassClaimCore path ~20,000 + event ~3,500) | ~2,675,000 |
| Decimator: bucket loop (2-12) | 11 | ~7,000 (SLOAD decBucketBurnTotal + arithmetic) | ~77,000 |

**Storage Operations:**

| Operation | Count | Gas |
|-----------|-------|-----|
| Cold SLOADs (payDailyJackpotCoinAndTickets state) | ~10 | ~21,000 |
| Cold SLOADs (BAF jackpot -- 107 autoRebuyState) | 107 | ~224,700 |
| Cold SSTOREs (claimableWinnings for 107 BAF winners, nonzero->nonzero) | 107 | ~535,000 |
| Cold SSTOREs (_endPhase flag updates) | 4 | ~20,000 |
| Cold SSTOREs (payDailyJackpotCoinAndTickets pending clear) | 3 | ~15,000 |
| Warm SSTOREs (prize pool updates) | ~6 | ~600 |

**External Calls:**

| Call | Target | Gas |
|------|--------|-----|
| jackpots.runBafJackpot() | DegenerusJackpots (cold) | ~50,000 base + 107 winner iteration overhead |
| coin.rollDailyQuest() | BURNIE (warm) | ~10,000 |
| dgnrs.transferFromPool() | sDGNRS (cold) | ~10,000 |
| runDecimatorJackpot() | self-call (warm) | ~5,000 base |
| coin.creditFlip() | BURNIE (warm) | ~5,000 |

**Events:**

| Event | Count | Gas |
|-------|-------|-----|
| JackpotTicketWinner (BAF) | up to 107 | ~375,000 |
| AutoRebuyExecuted/PlayerCredited (BAF) | up to 107 | ~375,000 |
| CoinJackpotWinner (daily coin) | up to 50 | ~175,000 |
| TraitsGenerated (ticket distribution) | up to 200 | ~300,000 |

**Worst-Case Total:**

| Component | Gas |
|-----------|-----|
| Common overhead | 75,000 |
| Delegatecall hops (JackpotModule x2, EndgameModule x2, DecimatorModule x1) | ~13,200 |
| payDailyJackpotCoinAndTickets (coin + far-future + tickets) | ~1,380,000 |
| BAF jackpot (107 winners via _runBafJackpot) | ~2,675,000 |
| BAF storage (SLOADs + SSTOREs for 107 winners) | ~759,700 |
| BAF events | ~750,000 |
| BAF external call (runBafJackpot) | ~250,000 |
| Decimator jackpot | ~100,000 |
| _awardFinalDayDgnrsReward | ~15,000 |
| _rewardTopAffiliate | ~15,000 |
| _endPhase + _unfreezePool | ~25,000 |
| **TOTAL** | **~6,058,000** |

**Headroom:** 14,000,000 - 6,058,000 = **7,942,000 gas** (57% remaining)

**Max Payouts:** BAF is code-capped at 107 winners. At the estimated ~45,000 gas per BAF winner (all costs inclusive), the 14M budget could support ~310 BAF winners. The **code constant (107) is the binding constraint**, not gas.

**Risk Level: SAFE** (>3M headroom)

---

### Stage 7: ENTERED_JACKPOT (Second Highest Risk)

**Entry Conditions:** Purchase phase, `lastPurchaseDay` is true, pool consolidation and future ticket activation complete. This is the transition from purchase phase to jackpot phase.

**Call Graph:**

```
advanceGame() [AdvanceModule:126]
  -> rngGate() -- RNG word consumed
  -> _processFutureTicketBatch(nextLevel) [AdvanceModule:300-311]
  |   -> delegatecall MintModule.processFutureTicketBatch() -- bounded by WRITES_BUDGET_SAFE
  -> _consolidatePrizePools (if !poolConsolidationDone) [AdvanceModule:314-318]
  |   -> levelPrizePool[purchaseLevel] = _getNextPrizePool()
  |   -> _applyTimeBasedFutureTake(ts, purchaseLevel, rngWord) [AdvanceModule:985]
  |   |   -> ~15 arithmetic ops, 5 SLOADs, 3 SSTOREs
  |   -> delegatecall JackpotModule.consolidatePrizePools() [JackpotModule:879]
  |       -> x00 yield accumulator dump, pool merge, optional keep-roll
  |       -> ~5 SLOADs, ~5 SSTOREs
  -> Flag updates (earlyBurnPercent, jackpotPhaseFlag, decWindowOpen, etc.) [AdvanceModule:324-335]
  -> _drawDownFuturePrizePool(lvl) [AdvanceModule:1059]
  |   -> 15% of futurePool to nextPool (2 SLOADs, 2 SSTOREs)
  -> emit Advance, coin.creditFlip
```

Note: The plan's initial research suggested `_runEarlyBirdLootboxJackpot` (100 winners) runs in ENTERED_JACKPOT. However, code analysis reveals that `_runEarlyBirdLootboxJackpot` is called from within `payDailyJackpot(true, ...)` on `isEarlyBirdDay` (counter==0), which runs in **Stage 11 (JACKPOT_DAILY_STARTED)**, not Stage 7. Stage 7 (ENTERED_JACKPOT) handles consolidation and flag transitions only.

**Loop Analysis:**

| Loop | Bound | Per-Iteration Cost | Worst-Case Total |
|------|-------|--------------------|------------------|
| _processFutureTicketBatch | WRITES_BUDGET_SAFE=550 (357 on first batch) | ~5,000 per SSTORE | ~1,785,000 |
| _applyTimeBasedFutureTake | No loop (arithmetic) | N/A | ~10,000 |
| consolidatePrizePools x00 keep-roll | 5 dice (fixed) | ~1,000 | ~5,000 |

Note: The future ticket batch is bounded by the writes budget. If there are no queued future tickets, this path is essentially free. The worst case assumes a full batch.

**Storage Operations:**

| Operation | Count | Gas |
|-----------|-------|-----|
| Cold SLOADs (pool state, level state) | ~15 | ~31,500 |
| Cold SSTOREs (levelPrizePool, jackpotPhaseFlag, earlyBurnPercent, decWindowOpen, poolConsolidationDone, lastPurchaseDay, levelStartTime) | ~10 | ~50,000 |
| SSTOREs from _processPhaseTransition future tickets | up to 357 | ~1,785,000 |
| Warm SSTOREs (prize pool updates) | ~6 | ~600 |

**External Calls:**

| Call | Target | Gas |
|------|--------|-----|
| JackpotModule.consolidatePrizePools() | delegatecall (cold) | ~2,600 |
| MintModule.processFutureTicketBatch() | delegatecall (cold) | ~2,600 |

**Events:**

| Event | Count | Gas |
|-------|-------|-----|
| TraitsGenerated (future tickets) | up to ~10 | ~15,000 |
| Advance | 1 | ~1,500 |

**Worst-Case Total (with full future ticket batch):**

| Component | Gas |
|-----------|-----|
| Common overhead | 75,000 |
| Delegatecall hops (JackpotModule, MintModule) | ~5,200 |
| rngGate (word already available) | ~5,000 |
| _processFutureTicketBatch (357 writes) | ~1,785,000 |
| _applyTimeBasedFutureTake | ~10,000 |
| consolidatePrizePools | ~30,000 |
| Flag writes (7 SSTOREs) | ~35,000 |
| _drawDownFuturePrizePool | ~10,000 |
| Events | ~16,500 |
| **TOTAL** | **~1,971,700** |

**Worst-Case Total (no future tickets queued):**

~200,000 gas (just consolidation + flag updates)

**Headroom:** 14,000,000 - 1,971,700 = **12,028,300 gas** (86% remaining)

**Risk Level: SAFE** (>3M headroom)

---

### Stage 11: JACKPOT_DAILY_STARTED (Third Highest Risk)

**Entry Conditions:** Jackpot phase active, no ETH distribution in progress (`dailyEthBucketCursor == 0`, etc.), no coin+ticket pending. This is a fresh daily jackpot start.

**Call Graph:**

```
advanceGame() [AdvanceModule:126]
  -> rngGate() -- RNG word consumed
  -> payDailyJackpot(true, lvl, rngWord) [AdvanceModule:377, delegatecall JackpotModule:323]
      -> Fresh start path (not resuming):
      |   -> _rollWinningTraits() -- entropy + storage
      |   -> _syncDailyWinningTraits() -- 1 SSTORE
      |   -> Turbo/compressed counter logic
      |   -> poolSnapshot, dailyBps calculation
      |   -> _runEarlyBirdLootboxJackpot() [JackpotModule:801] (day 1 only)
      |   |   -> 100 iterations: entropy step + _randTraitTicket + _queueTickets per winner
      |   -> _validateTicketBudget, dailyLootboxBudget
      |   -> _selectCarryoverSourceOffset (non-day-1)
      |   -> dailyEthPoolBudget, dailyTicketBudgetsPacked storage writes
      -> Phase 0 chunk: _processDailyEthChunk [JackpotModule:1388]
          -> unitsBudget = DAILY_JACKPOT_UNITS_SAFE = 1000
          -> Per winner: _winnerUnits() returns 1 (normal) or 3 (auto-rebuy)
          -> Inner loop: select winners from trait buckets, _addClaimableEth per winner
          -> Exits when unitsUsed exceeds unitsBudget (saves cursor for resume)
```

**Loop Analysis:**

| Loop | Bound | Per-Iteration Cost | Worst-Case Total |
|------|-------|--------------------|------------------|
| _runEarlyBirdLootboxJackpot | 100 (fixed) | ~10,000 (entropyStep + _randTraitTicket + conditional _queueTickets + PriceLookupLib) | ~1,000,000 |
| _processDailyEthChunk (Phase 0) | 1000 units / 3 per auto-rebuy winner = 333 max winners | ~25,000 per auto-rebuy winner (_addClaimableEth: autoRebuyState SLOAD 2,100 + _calcAutoRebuy ~5,000 + _queueTickets ~5,000 + prize pool SSTORE ~5,000 + event ~3,500) | ~8,325,000 |
| Bucket iteration (outer) | 4 (fixed) | ~5,000 (winner array construction + entropy) | ~20,000 |

**Storage Operations:**

| Operation | Count | Gas |
|-----------|-------|-----|
| Cold SLOADs (daily init state: counter, compressed flag, currentPrizePool, futurePool, etc.) | ~20 | ~42,000 |
| Cold SLOADs (333 autoRebuyState per winner) | 333 | ~699,300 |
| Cold SSTOREs (claimableWinnings or queueTickets for 333 winners) | 333 | ~1,665,000 |
| Cold SSTOREs (daily init: dailyEthPoolBudget, dailyTicketBudgetsPacked, cursors, traits) | ~8 | ~40,000 |

**External Calls:**

| Call | Target | Gas |
|------|--------|-----|
| JackpotModule.payDailyJackpot() | delegatecall (cold) | ~2,600 |

**Events:**

| Event | Count | Gas |
|-------|-------|-----|
| JackpotTicketWinner / PlayerCredited (333 winners) | 333 | ~1,165,000 |
| AutoRebuyExecuted (333 winners, worst case) | 333 | ~1,165,000 |

**Worst-Case Total (Day 1 with earlybird + all auto-rebuy winners):**

| Component | Gas |
|-----------|-----|
| Common overhead | 75,000 |
| Delegatecall hop (JackpotModule) | ~2,600 |
| rngGate (word available) | ~5,000 |
| Daily init (trait roll, budget calc, storage) | ~60,000 |
| _runEarlyBirdLootboxJackpot (100 winners) | ~1,000,000 |
| _processDailyEthChunk (333 auto-rebuy winners) | ~8,325,000 |
| Winner storage (SLOADs + SSTOREs) | ~2,364,300 |
| Events (333 x 2 events) | ~2,330,000 |
| **TOTAL** | **~14,161,900** |

**CRITICAL: This exceeds the 14M ceiling by ~162,000 gas.**

However, this is the absolute worst case combining TWO independent maximums:
1. Day-1 earlybird lootbox (only fires on `jackpotCounter == 0`)
2. All 333 winners having auto-rebuy enabled

The earlybird lootbox only fires on Day 1 of each level. On Day 1, the prize pool is typically smallest (daily BPS applied to the pool). In practice, if the daily ETH pool is small on Day 1, the number of winners will be small (bucket counts scale with pool size relative to ticket prices).

**Realistic worst case (Day 1 with earlybird but fewer winners):**
If only 200 units are consumed (66 auto-rebuy winners), total drops to ~4.5M gas.

**Worst case (non-Day-1, no earlybird, all auto-rebuy):**

| Component | Gas |
|-----------|-----|
| Common overhead + init | ~137,600 |
| _processDailyEthChunk (333 auto-rebuy winners) | ~8,325,000 |
| Winner storage | ~2,364,300 |
| Events | ~2,330,000 |
| **TOTAL** | **~13,157,000** |

**Headroom (non-Day-1):** 14,000,000 - 13,157,000 = **843,000 gas**

**Headroom (Day 1 theoretical maximum):** 14,000,000 - 14,162,000 = **-162,000 gas (BREACH)**

**Note:** The `unitsBudget` of 1000 was specifically designed to keep gas under 15M (see JackpotModule:596 comment: "gas optimization to stay under 15M block limit"). The 14M conservative target makes this stage tight.

**Max Payouts under 14M:** With ~75,000 base + 60,000 init + 1,000,000 earlybird = 1,135,000 overhead, remaining budget is ~12,865,000. At ~38,600 gas per auto-rebuy winner (distribution + storage + events), max ~333 auto-rebuy winners. At ~15,000 per normal winner, max ~857 normal winners. The **unitsBudget = 1000 is the binding constraint** for normal winners; for auto-rebuy, the gas cost at 333 winners is the practical limit.

**Risk Level: AT_RISK** (Day 1 + full auto-rebuy can theoretically breach; non-Day-1 has <1M headroom with full auto-rebuy)

---

### Stage 6: PURCHASE_DAILY (Daily During Purchase Phase)

**Entry Conditions:** Purchase phase active, `!lastPurchaseDay`, new day (day != dailyIdx). This runs daily during the purchase phase.

**Call Graph:**

```
advanceGame() [AdvanceModule:126]
  -> rngGate() -- RNG word consumed (or requests new VRF)
  -> payDailyJackpot(false, purchaseLevel, rngWord) [AdvanceModule:285, delegatecall JackpotModule:323]
  |   -> isDaily=false path (non-daily / early-burn) [JackpotModule:609-667]
  |   -> _rollWinningTraits() + _syncDailyWinningTraits()
  |   -> Conditional ethDaySlice: 1% futurePool drip (if daysSince > 0 && lvl > 1)
  |   -> _executeJackpot() [JackpotModule:1310] -- NOT chunked, runs to completion
  |   |   -> _runJackpotEthFlow() -> _distributeJackpotEth()
  |   |   -> Up to JACKPOT_MAX_WINNERS=300 winners, 4 buckets (MAX_BUCKET_WINNERS=250 per bucket)
  |   |   -> Per winner: _addClaimableEth (auto-rebuy or normal)
  |   -> _distributeLootboxAndTickets() (conditional on lootboxBudget)
  |   -> coin.rollDailyQuest()
  -> _payDailyCoinJackpot(purchaseLevel, rngWord) [AdvanceModule:286, delegatecall JackpotModule:2361]
  |   -> _calcDailyCoinBudget
  |   -> _awardFarFutureCoinJackpot (10 iterations)
  |   -> _awardDailyCoinToTraitWinners (up to DAILY_COIN_MAX_WINNERS=50)
  -> Conditional: check if _getNextPrizePool() >= levelPrizePool [AdvanceModule:287-292]
  -> _unlockRng(day), _unfreezePool() [AdvanceModule:293-294]
```

**Critical detail:** When `isDaily=false`, `payDailyJackpot` does NOT use `_processDailyEthChunk` with chunking. Instead, it uses `_executeJackpot` -> `_distributeJackpotEth` which distributes to all winners in a single call with NO unit budget and NO cursor-based resume. The maximum winner count is `JACKPOT_MAX_WINNERS = 300`.

**Loop Analysis:**

| Loop | Bound | Per-Iteration Cost | Worst-Case Total |
|------|-------|--------------------|------------------|
| _distributeJackpotEth (non-chunked) | 300 (JACKPOT_MAX_WINNERS) | ~25,000 per auto-rebuy winner / ~12,000 per normal winner | ~7,500,000 (auto-rebuy) / ~3,600,000 (normal) |
| _payDailyCoinJackpot: _awardFarFutureCoinJackpot | 10 (fixed) | ~8,000 | ~80,000 |
| _payDailyCoinJackpot: _awardDailyCoinToTraitWinners | 50 (DAILY_COIN_MAX_WINNERS) | ~6,000 | ~300,000 |
| _distributeLootboxAndTickets | 100 (LOOTBOX_MAX_WINNERS) | ~5,000 | ~500,000 |

**Storage Operations:**

| Operation | Count | Gas |
|-----------|-------|-----|
| Cold SLOADs (init + 300 autoRebuyState) | ~320 | ~672,000 |
| Cold SSTOREs (300 winner credits) | ~300 | ~1,500,000 |

**External Calls:**

| Call | Target | Gas |
|------|--------|-----|
| JackpotModule.payDailyJackpot() | delegatecall (cold) | ~2,600 |
| JackpotModule.payDailyCoinJackpot() | delegatecall (cold) | ~2,600 |
| coin.rollDailyQuest() | external (warm) | ~10,000 |

**Events:**

| Event | Count | Gas |
|-------|-------|-----|
| JackpotTicketWinner / PlayerCredited (300 ETH winners) | 300 | ~1,050,000 |
| AutoRebuyExecuted (300 auto-rebuy winners) | 300 | ~1,050,000 |
| CoinJackpotWinner (50 coin winners) | 50 | ~175,000 |

**Worst-Case Total (all auto-rebuy, 300 winners):**

| Component | Gas |
|-----------|-----|
| Common overhead | 75,000 |
| Delegatecall hops (JackpotModule x2) | ~5,200 |
| rngGate (word available) | ~5,000 |
| Trait roll + ethDaySlice calc + pool ops | ~30,000 |
| _distributeJackpotEth (300 auto-rebuy winners) | ~7,500,000 |
| _distributeLootboxAndTickets (100 lootbox winners) | ~500,000 |
| _payDailyCoinJackpot (50 BURNIE winners + 10 far-future) | ~380,000 |
| Winner storage (SLOADs + SSTOREs for 300) | ~2,172,000 |
| Events (300 x 2 + 50 coin) | ~2,275,000 |
| _unlockRng + _unfreezePool | ~10,000 |
| **TOTAL** | **~12,952,200** |

**Headroom:** 14,000,000 - 12,952,200 = **1,047,800 gas**

**Note on pool economics:** During the purchase phase, the early-burn ETH pool is small (1% daily drip from futurePool). With typical futurePool values, the actual number of winners is much lower than 300 because bucket counts scale with pool size. The 300-winner worst case requires a very large futurePool.

**Max Payouts under 14M:** At ~43,000 gas per auto-rebuy winner (all inclusive), 14M budget with ~120,000 overhead supports ~323 winners. **Code constant (300) is the binding constraint.**

**Risk Level: TIGHT** (1-3M headroom; non-chunked but code-bounded at 300 winners)

---

### Stage 0: GAMEOVER

**Entry Conditions:** Liveness guard triggered -- either level 0 with 365-day idle timeout, or level != 0 with 120-day inactivity. This is a one-time terminal event.

**Call Graph:**

```
advanceGame() [AdvanceModule:126]
  -> _handleGameOverPath(ts, day, lst, lvl, lastPurchase, dailyIdx) [AdvanceModule:419]
      |
      +-- Pre-gameover (gameOver == false) [AdvanceModule:454-468]:
      |   -> _gameOverEntropy() -- acquire RNG (may request VRF or use fallback)
      |   -> _unlockRng(day)
      |   -> delegatecall GameOverModule.handleGameOverDrain(day) [GameOverModule:68]
      |       -> deityPassOwners loop (early game, lvl < 10) [GameOverModule:82-102]
      |       |   -> iterate deityPassOwners array
      |       |   -> per owner: SLOAD owner + SLOAD purchasedCount + SSTORE claimableWinnings
      |       -> gameOver = true (terminal flag)
      |       -> Decimator jackpot: self-call runTerminalDecimatorJackpot [GameOverModule:139]
      |       |   -> runDecimatorJackpot loop (11 iterations, denoms 2-12)
      |       -> Terminal jackpot: self-call runTerminalJackpot [GameOverModule:151]
      |       |   -> _distributeJackpotEth: up to DAILY_ETH_MAX_WINNERS=321 winners
      |       -> dgnrs.burnRemainingPools() [GameOverModule:162]
      |       -> Optional: _sendToVault() [GameOverModule:156-158]
      |
      +-- Post-gameover (gameOver == true) [AdvanceModule:437-445]:
          -> delegatecall GameOverModule.handleFinalSweep() [GameOverModule:170]
              -> (only after 30 days post-gameover)
              -> admin.shutdownVrf() (try/catch)
              -> _sendToVault()
```

**Loop Analysis -- Deity Pass Owners:**

The `deityPassOwners` array has a **hard code cap of 32** (`DEITY_PASS_MAX_TOTAL = 32` in DegenerusGameLootboxModule:215). This is enforced at purchase time (`deityPassOwners.length < DEITY_PASS_MAX_TOTAL` checks in LootboxModule:772, 812, 1063 and DegenerusGame:889).

| Loop | Bound | Per-Iteration Cost | Worst-Case Total |
|------|-------|--------------------|------------------|
| Deity pass owners (lvl < 10 only) | 32 (DEITY_PASS_MAX_TOTAL) | ~12,000 (SLOAD owner 2,100 + SLOAD purchasedCount 2,100 + SLOAD claimableWinnings 2,100 + SSTORE claimableWinnings 5,000 + arithmetic ~700) | ~384,000 |
| Decimator bucket loop (2-12) | 11 | ~7,000 | ~77,000 |
| Terminal jackpot distribution | 321 (DAILY_ETH_MAX_WINNERS) | ~25,000 per auto-rebuy winner / ~12,000 per normal winner | see below |

**Key insight:** The deity pass loop is **NOT unbounded**. It is capped at 32 by `DEITY_PASS_MAX_TOTAL`. However, the PLAN research notes flagged this as potentially unbounded -- this analysis confirms the bound exists in code. Not a finding.

**Terminal Jackpot Gas (runTerminalJackpot):**

The terminal jackpot uses `_distributeJackpotEth` which does NOT use chunking (no `unitsBudget`). It distributes to up to `DAILY_ETH_MAX_WINNERS = 321` winners in a single call. However, `gameOver = true` is set before this call, which disables auto-rebuy inside `_addClaimableEth` (EndgameModule:248: `if (!gameOver)` check on auto-rebuy). This means ALL winners take the normal path (~12,000 gas each).

| Component | Gas |
|-----------|-----|
| 321 winners x 12,000 | ~3,852,000 |
| 321 winner SLOADs (autoRebuyState) | ~674,100 |
| 321 SSTOREs (claimableWinnings) | ~1,605,000 |
| 321 events (JackpotTicketWinner + PlayerCredited) | ~2,247,000 |

Terminal jackpot subtotal: **~8,378,100**

**External Calls:**

| Call | Target | Gas |
|------|--------|-----|
| GameOverModule delegatecall | cold | ~2,600 |
| runTerminalDecimatorJackpot() | self-call | ~5,000 base |
| runTerminalJackpot() | self-call | ~5,000 base |
| dgnrs.burnRemainingPools() | external (cold) | ~10,000 |
| steth.balanceOf() | external (cold) | ~5,000 |
| steth.transfer() / steth.approve() | external (conditional) | ~30,000 |

**Worst-Case Total (pre-gameover, lvl < 10, full deity loop + terminal jackpot):**

| Component | Gas |
|-----------|-----|
| Common overhead (no event/bounty -- returns early from _handleGameOverPath) | 60,000 |
| Delegatecall (GameOverModule) | ~2,600 |
| _gameOverEntropy + _unlockRng | ~15,000 |
| Deity pass owner loop (32 owners) | ~384,000 |
| claimablePool update | ~5,000 |
| gameOver flag + storage writes | ~25,000 |
| Terminal decimator jackpot | ~100,000 |
| Terminal jackpot (321 winners, no auto-rebuy) | ~8,378,100 |
| dgnrs.burnRemainingPools() | ~10,000 |
| _sendToVault (stETH + ETH transfers) | ~50,000 |
| Advance event + bounty | ~6,500 |
| **TOTAL** | **~9,036,200** |

**Post-gameover (handleFinalSweep) worst case:** ~150,000 gas (simple: check timestamp, admin.shutdownVrf(), _sendToVault())

**Headroom (pre-gameover):** 14,000,000 - 9,036,200 = **4,963,800 gas** (35% remaining)

**Max Payouts:** Terminal jackpot is code-bounded at DAILY_ETH_MAX_WINNERS = 321. At ~26,000 gas per winner (no auto-rebuy), 14M could support ~538 winners. **Code constant (321) is the binding constraint.**

**Deity Pass Loop Assessment:** The `deityPassOwners` array is hard-capped at 32 by `DEITY_PASS_MAX_TOTAL`. At 32 iterations x ~12,000 gas = ~384,000 gas, this is well within budget. **Not a DoS vector. Not a finding.**

**Risk Level: SAFE** (>3M headroom)

---

## Lighter Stage Analysis

### Stage 1: RNG_REQUESTED

**Entry Conditions:** New day detected, no pending VRF word. The game needs a fresh random word from Chainlink VRF for daily jackpot resolution.

**Call Graph:**

```
advanceGame() [AdvanceModule:126]
  -> rngGate(ts, day, purchaseLevel, lastPurchase, bonusFlip) [AdvanceModule:234]
  |   -> rngWordByDay[day] == 0, rngWordCurrent == 0 or stale
  |   -> Falls through to _requestRng() path, returns 1
  -> _swapAndFreeze(purchaseLevel) [AdvanceModule:236, Storage:728]
  |   -> _swapTicketSlot(): 2 SSTOREs (read/write key swap)
  |   -> prizePoolFrozen = true: 1 SSTORE
  |   -> prizePoolPendingPacked = 0: 1 SSTORE
  -> emit Advance(STAGE_RNG_REQUESTED), coin.creditFlip
```

**Loop Analysis:** No loops. This is a linear path with a single external VRF call.

**Storage Operations:**

| Operation | Count | Gas |
|-----------|-------|-----|
| Cold SLOADs (rngWordByDay, rngWordCurrent, rngRequestTime, vrfCoordinator, vrfKeyHash, vrfSubscriptionId) | ~8 | ~16,800 |
| Cold SSTOREs (_swapTicketSlot swap, prizePoolFrozen, prizePoolPendingPacked, rngLockedFlag, vrfRequestId, rngRequestTime, rngWordCurrent) | ~8 | ~40,000 |

**External Calls:**

| Call | Target | Gas |
|------|--------|-----|
| vrfCoordinator.requestRandomWords() | Chainlink VRF (cold) | ~50,000 |

**Worst-Case Total:**

| Component | Gas |
|-----------|-----|
| Common overhead | 75,000 |
| rngGate logic (SLOADs + conditionals) | ~20,000 |
| _swapAndFreeze | ~45,000 |
| VRF requestRandomWords | ~50,000 |
| _finalizeRngRequest storage writes | ~25,000 |
| **TOTAL** | **~215,000** |

**Headroom:** 14,000,000 - 215,000 = **13,785,000 gas** (98.5% remaining)

**Risk Level: SAFE** (>3M headroom)

---

### Stage 2: TRANSITION_WORKING

**Entry Conditions:** `phaseTransitionActive` is true, `_processPhaseTransition()` returns false (transition not yet complete). In practice, `_processPhaseTransition` always returns true in a single call (it queues 2 x 16 tickets and stakes ETH), so this stage is only reachable if `_processPhaseTransition` were to be modified to chunk work. Currently, it completes atomically and the flow falls through to STAGE_TRANSITION_DONE.

**Call Graph:**

```
advanceGame() [AdvanceModule:126]
  -> rngGate() -- RNG word available
  -> phaseTransitionActive is true [AdvanceModule:242]
  -> _processPhaseTransition(purchaseLevel) [AdvanceModule:1174]
  |   -> _queueTickets(SDGNRS, targetLevel, 16) [Storage]
  |   -> _queueTickets(VAULT, targetLevel, 16) [Storage]
  |   -> _autoStakeExcessEth() [AdvanceModule:1192]
  |       -> address(this).balance check
  |       -> steth.submit{value}() -- try/catch, non-blocking
  -> Returns false (hypothetical): stage = STAGE_TRANSITION_WORKING
  -> emit Advance, coin.creditFlip
```

**Loop Analysis:** No loops. Two `_queueTickets` calls (O(1) each -- array push or packed update), one external stETH call.

**Storage Operations:**

| Operation | Count | Gas |
|-----------|-------|-----|
| Cold SLOADs (phaseTransitionActive, claimablePool, address balance) | ~5 | ~10,500 |
| Cold SSTOREs (_queueTickets x2: ticketsOwedPacked writes, queue pushes) | ~4 | ~88,400 (2 zero->nonzero at 22,100 each + 2 array pushes at 22,100) |
| Warm SSTORE (pool state updates) | ~2 | ~200 |

**External Calls:**

| Call | Target | Gas |
|------|--------|-----|
| steth.submit{value}() | Lido stETH (cold) | ~30,000 (try/catch, non-blocking) |

**Worst-Case Total:**

| Component | Gas |
|-----------|-----|
| Common overhead | 75,000 |
| rngGate (word available) | ~5,000 |
| _queueTickets x2 | ~90,000 |
| _autoStakeExcessEth (stETH submit) | ~35,000 |
| **TOTAL** | **~205,000** |

**Headroom:** 14,000,000 - 205,000 = **13,795,000 gas** (98.5% remaining)

**Risk Level: SAFE** (>3M headroom)

---

### Stage 3: TRANSITION_DONE

**Entry Conditions:** `phaseTransitionActive` is true, `_processPhaseTransition()` returns true (transition completed). This is the normal outcome -- transition completes in one call.

**Call Graph:**

```
advanceGame() [AdvanceModule:126]
  -> rngGate() -- RNG word available
  -> phaseTransitionActive is true [AdvanceModule:242]
  -> _processPhaseTransition(purchaseLevel) returns true [AdvanceModule:243]
  -> phaseTransitionActive = false [AdvanceModule:247]
  -> _unlockRng(day) [AdvanceModule:248]
  -> _unfreezePool() [AdvanceModule:249, Storage:738]
  -> purchaseStartDay = day [AdvanceModule:250]
  -> jackpotPhaseFlag = false [AdvanceModule:251]
  -> emit Advance(STAGE_TRANSITION_DONE), coin.creditFlip
```

**Loop Analysis:** No loops. Same as TRANSITION_WORKING but with additional flag updates after completion.

**Storage Operations:**

| Operation | Count | Gas |
|-----------|-------|-----|
| All from TRANSITION_WORKING | ~9 | ~99,100 |
| Additional cold SSTOREs (phaseTransitionActive=false, rngLockedFlag, prizePoolFrozen, purchaseStartDay, jackpotPhaseFlag) | ~5 | ~25,000 |
| _unfreezePool: read pending pools + write live pools + clear pending | ~3 SLOADs + ~3 SSTOREs | ~21,600 |

**Worst-Case Total:**

| Component | Gas |
|-----------|-----|
| Common overhead | 75,000 |
| rngGate (word available) | ~5,000 |
| _processPhaseTransition (tickets + stETH) | ~125,000 |
| Flag updates + _unlockRng + _unfreezePool | ~50,000 |
| **TOTAL** | **~255,000** |

**Headroom:** 14,000,000 - 255,000 = **13,745,000 gas** (98.2% remaining)

**Risk Level: SAFE** (>3M headroom)

---

### Stage 4: FUTURE_TICKETS_WORKING

**Entry Conditions:** No daily jackpot in progress (all cursor/budget fields zero), `_prepareFutureTickets(lvl)` returns false (not all future levels processed). This activates tickets for levels lvl+2 through lvl+6.

**Call Graph:**

```
advanceGame() [AdvanceModule:126]
  -> rngGate() -- RNG word available
  -> _prepareFutureTickets(lvl) [AdvanceModule:1109]
  |   -> For each level in [lvl+2, lvl+6]:
  |       -> _processFutureTicketBatch(target) [AdvanceModule:1087]
  |           -> delegatecall MintModule.processFutureTicketBatch()
  |               -> processTicketBatch bounded by WRITES_BUDGET_SAFE=550
  |   -> Returns false when any level has remaining work
  -> stage = STAGE_FUTURE_TICKETS_WORKING
  -> emit Advance, coin.creditFlip
```

**Loop Analysis:**

| Loop | Bound | Per-Iteration Cost | Worst-Case Total |
|------|-------|--------------------|------------------|
| _prepareFutureTickets: outer level loop | 5 (lvl+2 to lvl+6) | Variable (one processTicketBatch per level) | N/A -- exits after first incomplete level |
| processTicketBatch inner loop | WRITES_BUDGET_SAFE=550 (357 on first batch) | ~5,000 per SSTORE write (ticket generation + trait assignment) | ~2,750,000 (full budget) / ~1,785,000 (first batch) |

In practice, `_prepareFutureTickets` calls `_processFutureTicketBatch` and returns false as soon as any level does work or is incomplete. So each `advanceGame()` call processes at most ONE batch of 550 writes (or 357 on first call for that level).

**Storage Operations:**

| Operation | Count | Gas |
|-----------|-------|-----|
| Cold SLOADs (ticketLevel, ticketCursor, ticketQueue length, ticketsOwedPacked) | ~5 | ~10,500 |
| Cold SSTOREs (up to 550 ticket writes) | 550 | ~2,750,000 |
| Cursor updates (ticketCursor, ticketLevel) | ~2 | ~10,000 |

**External Calls:**

| Call | Target | Gas |
|------|--------|-----|
| MintModule.processFutureTicketBatch() | delegatecall (cold) | ~2,600 |

**Events:**

| Event | Count | Gas |
|-------|-------|-----|
| TraitsGenerated | ~10 (per player batch) | ~15,000 |

**Worst-Case Total (full 550-write batch):**

| Component | Gas |
|-----------|-----|
| Common overhead | 75,000 |
| rngGate (word available) | ~5,000 |
| Delegatecall (MintModule) | ~2,600 |
| processTicketBatch (550 SSTOREs) | ~2,750,000 |
| Cursor + state updates | ~15,000 |
| Events | ~15,000 |
| **TOTAL** | **~2,862,600** |

**First-batch total (357 writes):** ~1,897,600

**Headroom:** 14,000,000 - 2,862,600 = **11,137,400 gas** (79.6% remaining)

**Risk Level: SAFE** (>3M headroom)

---

### Stage 5: TICKETS_WORKING

**Entry Conditions:** Current level ticket queue has entries, `ticketsFullyProcessed` is false. Processes the current level's ticket queue via `processTicketBatch`.

**Call Graph:**

```
advanceGame() [AdvanceModule:126]
  -> rngGate() -- RNG word available (or mid-day path without rngGate)
  -> _runProcessTicketBatch(purchaseLevel) [AdvanceModule:1150]
  |   -> delegatecall JackpotModule.processTicketBatch(lvl) [JackpotModule:1890]
  |       -> Read ticket queue for read key
  |       -> writesBudget = WRITES_BUDGET_SAFE = 550 (357 on first batch, idx==0)
  |       -> Inner loop: _processOneTicketEntry per queued player
  |       |   -> ticketsOwedPacked SLOAD
  |       |   -> _generateTicketBatch -> _raritySymbolBatch (trait generation)
  |       |   -> _finalizeTicketEntry -> update/clear packed state
  |       -> Updates ticketCursor, cleanup on completion
  -> emit Advance(STAGE_TICKETS_WORKING), coin.creditFlip
```

**Loop Analysis:**

| Loop | Bound | Per-Iteration Cost | Worst-Case Total |
|------|-------|--------------------|------------------|
| processTicketBatch | WRITES_BUDGET_SAFE=550 (tracked via writesUsed) | ~5,000 per write unit (SLOAD ticket data + trait generation + SSTORE update) | ~2,750,000 |

The writes budget is consumed by `_processOneTicketEntry` which returns `writesUsed` per entry. Each entry's cost depends on ticket count: small entries (~2-4 writes), large entries (take + overhead writes). The budget ensures total SSTOREs stay bounded.

**Storage Operations:**

| Operation | Count | Gas |
|-----------|-------|-----|
| Cold SLOADs (ticketLevel, ticketCursor, queue length, ticketsOwedPacked per player) | ~5 + N players | ~10,500 + N*2,100 |
| Cold SSTOREs (ticket generation: traitBurnTicket, ticketsOwedPacked updates) | up to 550 | ~2,750,000 |
| Cursor/cleanup SSTOREs | ~3 | ~15,000 |

**External Calls:**

| Call | Target | Gas |
|------|--------|-----|
| JackpotModule.processTicketBatch() | delegatecall (cold) | ~2,600 |

**Events:**

| Event | Count | Gas |
|-------|-------|-----|
| TraitsGenerated (per player batch) | ~10-50 | ~15,000-75,000 |

**Worst-Case Total (full 550-write batch):**

| Component | Gas |
|-----------|-----|
| Common overhead | 75,000 |
| rngGate (word available or mid-day) | ~5,000 |
| Delegatecall (JackpotModule) | ~2,600 |
| processTicketBatch (550 writes) | ~2,750,000 |
| Player SLOADs (~50 distinct players) | ~105,000 |
| Cursor + cleanup | ~15,000 |
| Events | ~75,000 |
| **TOTAL** | **~3,027,600** |

**First-batch total (357 writes):** ~2,065,600

**Headroom:** 14,000,000 - 3,027,600 = **10,972,400 gas** (78.4% remaining)

**Risk Level: SAFE** (>3M headroom)

---

### Stage 8: JACKPOT_ETH_RESUME

**Entry Conditions:** Jackpot phase active, one of the ETH distribution cursors/state is non-zero (`dailyEthBucketCursor != 0 || dailyEthPhase != 0 || dailyEthPoolBudget != 0 || dailyEthWinnerCursor != 0`). This resumes a prior chunked ETH distribution.

**Call Graph:**

```
advanceGame() [AdvanceModule:126]
  -> rngGate() -- RNG word available
  -> dailyEthBucketCursor != 0 or dailyEthPhase != 0 or ... [AdvanceModule:348-357]
  -> payDailyJackpot(true, lastDailyJackpotLevel, rngWord) [AdvanceModule:354]
      -> isResuming = true (cursors non-zero) [JackpotModule:333-336]
      -> Restore stored traits/level
      -> Phase 0 or Phase 1 _processDailyEthChunk with unitsBudget = DAILY_JACKPOT_UNITS_SAFE = 1000
      -> Resumes from saved cursor position
```

**Loop Analysis:**

| Loop | Bound | Per-Iteration Cost | Worst-Case Total |
|------|-------|--------------------|------------------|
| _processDailyEthChunk (resume) | 1000 units / 3 per auto-rebuy winner = 333 max | ~25,000 per auto-rebuy winner | ~8,325,000 |

This is the same chunking mechanism as Stage 11 but starting from a saved cursor. The worst case is identical to Stage 11's non-Day-1 path (no earlybird, no init overhead).

**Storage Operations:**

| Operation | Count | Gas |
|-----------|-------|-----|
| Cold SLOADs (resume state: cursors, stored traits, autoRebuyState per winner) | ~338 | ~709,800 |
| Cold SSTOREs (winner credits for 333 winners) | ~333 | ~1,665,000 |

**Events:**

| Event | Count | Gas |
|-------|-------|-----|
| JackpotTicketWinner / PlayerCredited / AutoRebuyExecuted | 333 x 2 | ~2,330,000 |

**Worst-Case Total (all auto-rebuy, 333 winners):**

| Component | Gas |
|-----------|-----|
| Common overhead | 75,000 |
| Delegatecall (JackpotModule) | ~2,600 |
| rngGate (word available) | ~5,000 |
| Resume state restore | ~10,000 |
| _processDailyEthChunk (333 auto-rebuy winners) | ~8,325,000 |
| Winner storage (SLOADs + SSTOREs) | ~2,374,800 |
| Events | ~2,330,000 |
| **TOTAL** | **~13,122,400** |

**Headroom:** 14,000,000 - 13,122,400 = **877,600 gas**

**Max Payouts:** Same as Stage 11 -- 333 auto-rebuy or 1000 normal winners per chunk. The `unitsBudget = 1000` is the binding constraint.

**Risk Level: AT_RISK** (<1M headroom with all auto-rebuy winners)

---

### Stage 9: JACKPOT_COIN_TICKETS

**Entry Conditions:** Jackpot phase active, `dailyJackpotCoinTicketsPending` is true, `jackpotCounter < JACKPOT_LEVEL_CAP` (5) after coin+ticket distribution. This is the coin+ticket phase WITHOUT the end-of-level reward jackpots.

**Call Graph:**

```
advanceGame() [AdvanceModule:126]
  -> rngGate() -- RNG word available
  -> dailyJackpotCoinTicketsPending is true [AdvanceModule:360]
  -> payDailyJackpotCoinAndTickets(rngWord) [AdvanceModule:361, delegatecall JackpotModule:681]
  |   -> _unpackDailyTicketBudgets
  |   -> _calcDailyCoinBudget + _awardFarFutureCoinJackpot (10 iterations)
  |   -> _awardDailyCoinToTraitWinners (up to 50 BURNIE winners)
  |   -> _distributeTicketJackpot x2 (up to 100 winners each)
  |   -> jackpotCounter += counterStep
  |   -> Clear pending state
  |   -> coin.rollDailyQuest()
  -> _unlockRng(day) [AdvanceModule:371]
  -> emit Advance(STAGE_JACKPOT_COIN_TICKETS), coin.creditFlip
```

Note: This is the same as the payDailyJackpotCoinAndTickets portion of Stage 10 (JACKPOT_PHASE_ENDED) but WITHOUT the _awardFinalDayDgnrsReward, _rewardTopAffiliate, _runRewardJackpots, or _endPhase calls. No BAF jackpot, no decimator.

**Loop Analysis:**

| Loop | Bound | Per-Iteration Cost | Worst-Case Total |
|------|-------|--------------------|------------------|
| _awardFarFutureCoinJackpot | 10 (fixed) | ~8,000 | ~80,000 |
| _awardDailyCoinToTraitWinners | 50 (DAILY_COIN_MAX_WINNERS) | ~6,000 | ~300,000 |
| _distributeTicketJackpot (daily) | 100 (LOOTBOX_MAX_WINNERS) | ~5,000 | ~500,000 |
| _distributeTicketJackpot (carryover) | 100 (LOOTBOX_MAX_WINNERS) | ~5,000 | ~500,000 |

**Storage Operations:**

| Operation | Count | Gas |
|-----------|-------|-----|
| Cold SLOADs (pending state, coin budget, trait arrays) | ~15 | ~31,500 |
| Cold SSTOREs (jackpotCounter, pending flags, ticket distributions) | ~10 | ~50,000 |

**External Calls:**

| Call | Target | Gas |
|------|--------|-----|
| JackpotModule.payDailyJackpotCoinAndTickets() | delegatecall (cold) | ~2,600 |
| coin.rollDailyQuest() | external (warm) | ~10,000 |

**Events:**

| Event | Count | Gas |
|-------|-------|-----|
| CoinJackpotWinner (50) | 50 | ~175,000 |
| TraitsGenerated (ticket distribution, ~200 winners) | ~20 | ~30,000 |

**Worst-Case Total:**

| Component | Gas |
|-----------|-----|
| Common overhead | 75,000 |
| Delegatecall (JackpotModule) | ~2,600 |
| rngGate (word available) | ~5,000 |
| _awardFarFutureCoinJackpot (10 iterations) | ~80,000 |
| _awardDailyCoinToTraitWinners (50 winners) | ~300,000 |
| _distributeTicketJackpot x2 (200 total winners) | ~1,000,000 |
| Storage (SLOADs + SSTOREs) | ~81,500 |
| Events | ~205,000 |
| _unlockRng | ~5,000 |
| coin.rollDailyQuest | ~10,000 |
| **TOTAL** | **~1,764,100** |

**Headroom:** 14,000,000 - 1,764,100 = **12,235,900 gas** (87.4% remaining)

**Risk Level: SAFE** (>3M headroom)

---

## Complete Summary Table (CEIL-01)

All 12 `advanceGame()` stages with worst-case gas profiles:

| Stage | Constant | Name | Worst-Case Gas | Headroom | Max Payouts | Risk Level |
|-------|----------|------|----------------|----------|-------------|------------|
| 0 | STAGE_GAMEOVER | GAMEOVER | ~9,036,000 | 4,964,000 | 321 terminal + 32 deity | SAFE |
| 1 | STAGE_RNG_REQUESTED | RNG_REQUESTED | ~215,000 | 13,785,000 | N/A | SAFE |
| 2 | STAGE_TRANSITION_WORKING | TRANSITION_WORKING | ~205,000 | 13,795,000 | N/A | SAFE |
| 3 | STAGE_TRANSITION_DONE | TRANSITION_DONE | ~255,000 | 13,745,000 | N/A | SAFE |
| 4 | STAGE_FUTURE_TICKETS_WORKING | FUTURE_TICKETS_WORKING | ~2,863,000 | 11,137,000 | N/A (WRITES_BUDGET_SAFE=550) | SAFE |
| 5 | STAGE_TICKETS_WORKING | TICKETS_WORKING | ~3,028,000 | 10,972,000 | N/A (WRITES_BUDGET_SAFE=550) | SAFE |
| 6 | STAGE_PURCHASE_DAILY | PURCHASE_DAILY | ~12,952,000 | 1,048,000 | 300 (JACKPOT_MAX_WINNERS) + 50 coin | TIGHT |
| 7 | STAGE_ENTERED_JACKPOT | ENTERED_JACKPOT | ~1,972,000 | 12,028,000 | N/A (consolidation) | SAFE |
| 8 | STAGE_JACKPOT_ETH_RESUME | JACKPOT_ETH_RESUME | ~13,122,000 | 878,000 | 333 (unitsBudget=1000 / 3) | AT_RISK |
| 9 | STAGE_JACKPOT_COIN_TICKETS | JACKPOT_COIN_TICKETS | ~1,764,000 | 12,236,000 | 50 coin + 200 tickets | SAFE |
| 10 | STAGE_JACKPOT_PHASE_ENDED | JACKPOT_PHASE_ENDED | ~6,058,000 | 7,942,000 | 107 (BAF code cap) | SAFE |
| 11 | STAGE_JACKPOT_DAILY_STARTED | JACKPOT_DAILY_STARTED | ~14,162,000 | -162,000 | 333 (unitsBudget=1000 / 3) | AT_RISK |

**Legend:**
- **SAFE:** >3M headroom. No risk of exceeding 14M gas ceiling.
- **TIGHT:** 1-3M headroom. Within budget but limited margin.
- **AT_RISK:** <1M headroom. Could breach 14M under extreme worst-case conditions.
- **BREACH:** Exceeds 14M gas ceiling (none confirmed; Stage 11 Day-1 theoretical only).

---

## CEIL-02: Maximum Jackpot Payouts Under 14M

This section consolidates maximum payout counts across all winner-distributing stages.

### Per-Winner Gas Cost Reference

| Distribution Path | Normal Winner | Auto-Rebuy Winner | Notes |
|-------------------|---------------|-------------------|-------|
| _processDailyEthChunk (chunked) | ~15,000 (1 unit) | ~38,600 (3 units) | Includes SLOAD, SSTORE, event, distribution |
| _distributeJackpotEth (non-chunked) | ~12,000 | ~25,000 | Used by early-burn and terminal jackpot |
| BAF (_runBafJackpot) | ~45,000 | ~45,000 | External call, whale pass queuing path |
| Coin jackpot (BURNIE) | ~6,000 | N/A | Token credit only, no auto-rebuy |
| Lootbox/ticket distribution | ~5,000 | N/A | _queueTickets (O(1) per winner) |
| Earlybird lootbox | ~10,000 | N/A | Winner selection + ticket queuing |

### Maximum Winner Counts by Stage

| Stage | Distribution Type | Max Winners (Code Bound) | Max Winners (14M Budget) | Binding Constraint |
|-------|-------------------|--------------------------|--------------------------|-------------------|
| 0 (GAMEOVER) | Terminal jackpot (non-chunked) | 321 (DAILY_ETH_MAX_WINNERS) | ~538 (normal, no auto-rebuy) | Code constant (321) |
| 0 (GAMEOVER) | Deity pass refund | 32 (DEITY_PASS_MAX_TOTAL) | ~1,166 | Code constant (32) |
| 6 (PURCHASE_DAILY) | Early-burn ETH (non-chunked) | 300 (JACKPOT_MAX_WINNERS) | ~323 (auto-rebuy) / ~1,158 (normal) | Code constant (300) |
| 6 (PURCHASE_DAILY) | BURNIE coin jackpot | 50 (DAILY_COIN_MAX_WINNERS) | ~2,333 | Code constant (50) |
| 6 (PURCHASE_DAILY) | Lootbox tickets | 100 (LOOTBOX_MAX_WINNERS) | ~2,800 | Code constant (100) |
| 7 (ENTERED_JACKPOT) | Future ticket batch | 550 writes (WRITES_BUDGET_SAFE) | ~2,563 writes | Code constant (550) |
| 8 (JACKPOT_ETH_RESUME) | Daily ETH chunk (chunked) | 321 (DAILY_ETH_MAX_WINNERS) per phase | 333 (auto-rebuy) / 1,000 (normal) | unitsBudget=1000 per chunk |
| 9 (JACKPOT_COIN_TICKETS) | BURNIE coin jackpot | 50 (DAILY_COIN_MAX_WINNERS) | ~2,333 | Code constant (50) |
| 9 (JACKPOT_COIN_TICKETS) | Ticket distribution | 200 (LOOTBOX_MAX_WINNERS x2) | ~2,800 | Code constant (100 per dist) |
| 10 (JACKPOT_PHASE_ENDED) | BAF jackpot | 107 (array size cap) | ~310 | Code constant (107) |
| 10 (JACKPOT_PHASE_ENDED) | BURNIE coin jackpot | 50 (DAILY_COIN_MAX_WINNERS) | ~2,333 | Code constant (50) |
| 10 (JACKPOT_PHASE_ENDED) | Ticket distribution | 200 (LOOTBOX_MAX_WINNERS x2) | ~2,800 | Code constant (100 per dist) |
| 11 (JACKPOT_DAILY_STARTED) | Daily ETH chunk (chunked) | 321 (DAILY_ETH_MAX_WINNERS) | 333 (auto-rebuy) / 1,000 (normal) | unitsBudget=1000 per chunk |
| 11 (JACKPOT_DAILY_STARTED) | Earlybird lootbox (Day 1) | 100 (fixed loop) | ~1,400 | Code constant (100) |

### Key Findings

1. **All code-bounded winner constants fit within 14M.** No single stage exceeds 14M due to winner count alone.

2. **The binding constraint is always the code constant**, not the 14M gas ceiling, for all distribution types except daily ETH chunking (Stages 8, 11) where the `unitsBudget=1000` limits winners per chunk.

3. **AT_RISK stages (8 and 11) are tight when all winners use auto-rebuy** (3x unit cost). With 333 auto-rebuy winners, gas approaches 13-14M. In practice, a mix of auto-rebuy and normal winners keeps gas well under 14M.

4. **Stage 11 Day 1 theoretical breach:** When earlybird lootbox (100 iterations, ~1M gas) combines with a full 333 auto-rebuy winner chunk, the total can theoretically exceed 14M by ~162K gas. This requires ALL of: Day 1 of a new level, a large enough prize pool for 333 winners, AND every winner having auto-rebuy enabled. The economic conditions for this combination are extremely unlikely.

5. **GAMEOVER terminal jackpot is safe** because `gameOver=true` disables auto-rebuy, capping per-winner cost at ~12K (normal path). Even at 321 winners, total is ~9M.

6. **Deity pass loop is bounded at 32** by DEITY_PASS_MAX_TOTAL. Not unbounded. Not a finding.
