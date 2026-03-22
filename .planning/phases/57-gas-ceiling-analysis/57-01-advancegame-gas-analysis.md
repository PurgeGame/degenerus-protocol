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
  |   -> isDaily=false path: early-burn daily distribution
  |   -> _processDailyEthChunk with unitsBudget = DAILY_JACKPOT_UNITS_SAFE = 1000
  |   -> Same chunking as Stage 11 but typically smaller pool (purchase phase, not jackpot phase)
  -> _payDailyCoinJackpot(purchaseLevel, rngWord) [AdvanceModule:286, delegatecall JackpotModule:2361]
  |   -> _calcDailyCoinBudget
  |   -> _awardFarFutureCoinJackpot (10 iterations)
  |   -> _awardDailyCoinToTraitWinners (up to DAILY_COIN_MAX_WINNERS=50)
  -> Conditional: check if _getNextPrizePool() >= levelPrizePool [AdvanceModule:287-292]
  -> _unlockRng(day), _unfreezePool() [AdvanceModule:293-294]
```

**Loop Analysis:**

| Loop | Bound | Per-Iteration Cost | Worst-Case Total |
|------|-------|--------------------|------------------|
| payDailyJackpot(false) Phase 0 chunk | 1000 units / 3 per winner = 333 max | ~25,000 per auto-rebuy winner | ~8,325,000 |
| _payDailyCoinJackpot: _awardFarFutureCoinJackpot | 10 (fixed) | ~8,000 | ~80,000 |
| _payDailyCoinJackpot: _awardDailyCoinToTraitWinners | 50 (DAILY_COIN_MAX_WINNERS) | ~6,000 | ~300,000 |

Note: During the purchase phase, `payDailyJackpot(false, ...)` path follows the same `_processDailyEthChunk` logic with the same `unitsBudget = 1000`. The daily init logic is similar but without earlybird (that only fires on jackpot phase Day 1).

**Storage Operations:**

| Operation | Count | Gas |
|-----------|-------|-----|
| Cold SLOADs (init + 333 autoRebuyState) | ~353 | ~741,300 |
| Cold SSTOREs (333 winner credits + daily state) | ~340 | ~1,700,000 |

**External Calls:**

| Call | Target | Gas |
|------|--------|-----|
| JackpotModule.payDailyJackpot() | delegatecall (cold) | ~2,600 |
| JackpotModule.payDailyCoinJackpot() | delegatecall (cold) | ~2,600 |

**Events:**

| Event | Count | Gas |
|-------|-------|-----|
| JackpotTicketWinner / PlayerCredited (333 ETH winners) | 333 | ~1,165,000 |
| AutoRebuyExecuted (333 auto-rebuy winners) | 333 | ~1,165,000 |
| CoinJackpotWinner (50 coin winners) | 50 | ~175,000 |

**Worst-Case Total (all auto-rebuy):**

| Component | Gas |
|-----------|-----|
| Common overhead | 75,000 |
| Delegatecall hops (JackpotModule x2) | ~5,200 |
| rngGate (word available) | ~5,000 |
| Daily init (trait roll, budget calc) | ~60,000 |
| _processDailyEthChunk (333 auto-rebuy winners) | ~8,325,000 |
| _payDailyCoinJackpot (50 BURNIE winners + 10 far-future) | ~380,000 |
| Winner storage (SLOADs + SSTOREs) | ~2,441,300 |
| Events (333 x 2 + 50 coin) | ~2,505,000 |
| _unlockRng + _unfreezePool | ~10,000 |
| **TOTAL** | **~13,806,500** |

**Headroom:** 14,000,000 - 13,806,500 = **193,500 gas**

**Max Payouts:** Same analysis as Stage 11. The unitsBudget = 1000 caps at 333 auto-rebuy winners per chunk. The daily coin jackpot adds 50 winners but those are BURNIE transfers (cheaper than ETH distribution).

**Risk Level: AT_RISK** (<1M headroom with all auto-rebuy winners; this is the same fundamental constraint as Stage 11)

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

## Heavy-Hitter Summary Table

| Stage | Name | Worst-Case Gas | Headroom | Max Payouts | Risk Level |
|-------|------|----------------|----------|-------------|------------|
| 10 | JACKPOT_PHASE_ENDED | ~6,058,000 | 7,942,000 | 107 (BAF code cap) | SAFE |
| 7 | ENTERED_JACKPOT | ~1,972,000 | 12,028,000 | N/A (consolidation) | SAFE |
| 11 | JACKPOT_DAILY_STARTED | ~14,162,000 (Day 1 + all auto-rebuy) / ~13,157,000 (non-Day-1) | -162,000 / 843,000 | 333 (unitsBudget=1000 / 3) | AT_RISK |
| 6 | PURCHASE_DAILY | ~13,807,000 (all auto-rebuy) | 193,000 | 333 + 50 coin | AT_RISK |
| 0 | GAMEOVER | ~9,036,000 | 4,964,000 | 321 (terminal, no auto-rebuy) + 32 deity | SAFE |
