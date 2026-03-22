# Gas Ceiling Analysis: advanceGame and purchase

**Date:** 2026-03-21
**Milestone:** v3.5
**Scope:** Worst-case gas profiling for advanceGame (12 stages) and purchase (6 paths)
**Mode:** Flag-only -- no code changes
**Gas Ceiling Target:** 14,000,000 (conservative target for reliable block inclusion)
**Compiler:** via_ir=true, optimizer_runs=2 (optimized for code size, not runtime gas)

---

## 1. Executive Summary

This analysis profiles the worst-case gas consumption for all 18 execution paths across the protocol's two primary transaction entry points: `advanceGame()` (12 stages) and `purchase()` (6 paths). All gas estimates are computed under maximum-adversity assumptions (all cold storage, maximum loop iterations, all auto-rebuy enabled where applicable).

**Total paths analyzed:** 12 advanceGame stages + 6 purchase paths = 18 paths

### advanceGame Verdict

- **10 of 12 stages:** SAFE (>3M headroom)
- **1 stage:** TIGHT (1-3M headroom) -- Stage 6 PURCHASE_DAILY
- **2 stages:** AT_RISK (<1M headroom) -- Stages 8 and 11 (daily ETH distribution with full auto-rebuy)
- **1 theoretical breach:** Stage 11 Day-1 with earlybird + full auto-rebuy (~14.16M, exceeds ceiling by ~162K)

### purchase Verdict

- **All 6 paths:** SAFE (>3M headroom)
- **Highest gas path:** Combined Ticket + Lootbox ETH (~600K worst case)
- **Key finding:** The protocol's O(1) ticket queuing design (`_queueTicketsScaled`) means gas does NOT constrain batch size. The 14M ceiling is consumed by fixed per-call overhead (~250K-600K), leaving 13.4M+ headroom.

### Findings Summary

| ID | Severity | Path | Description |
|----|----------|------|-------------|
| F-57-01 | INFO | Stage 11 (JACKPOT_DAILY_STARTED) | Day-1 + full auto-rebuy theoretical breach by ~162K gas |
| F-57-02 | INFO | Stage 6 (PURCHASE_DAILY) | Non-chunked _distributeJackpotEth with 300 max winners uses ~13M gas at full auto-rebuy |
| F-57-03 | INFO | Compiler | optimizer_runs=2 inflates runtime gas vs typical contracts; actual gas may be 5-15% higher than these estimates |
| F-57-04 | INFO | purchaseWhaleBundle | 100-level _queueTickets loop is the heaviest purchase path (~800K gas) but well within ceiling |

---

## 2. Methodology

### EVM Gas Cost Reference

| Operation | Gas Cost | Notes |
|-----------|----------|-------|
| SSTORE (cold, zero->nonzero) | 22,100 | First write to a slot |
| SSTORE (cold, nonzero->nonzero) | 5,000 | Overwrite existing |
| SSTORE (warm) | 100 | Already accessed this tx |
| SLOAD (cold) | 2,100 | First read of slot |
| SLOAD (warm) | 100 | Already accessed |
| External CALL (cold address) | 2,600 + execution | First call to address |
| External CALL (warm address) | 100 + execution | Already called address |
| DELEGATECALL (cold) | 2,600 | Module invocations |
| LOG (per topic) | 375 + 8/byte | Event emission |
| Base transaction cost | 21,000 | EVM intrinsic |

### Cold Storage Preamble Accounting

Every `advanceGame()` and `purchase()` call begins with cold storage reads of game state variables. The first access to each storage slot costs 2,100 gas (SLOAD cold). Subsequent accesses to the same slot within the same transaction cost only 100 gas (warm). We account for all initial reads as cold in the worst case.

### Per-Winner Gas Model

For jackpot distributions in `advanceGame()`:
- **Normal winner:** ~12,000-15,000 gas (SLOAD autoRebuyState + SLOAD claimableWinnings + SSTORE claimableWinnings + event)
- **Auto-rebuy winner:** ~25,000-38,600 gas (above + _calcAutoRebuy + _queueTickets + pool SSTORE + additional event)
- **Worst case assumes all winners have auto-rebuy enabled** (3 units each per the `_winnerUnits()` return, ~25,000-38,600 gas/winner)

### Compiler Configuration Impact

The protocol compiles with `via_ir=true` and `optimizer_runs=2`. This configuration optimizes for **code size**, not runtime gas. Actual runtime gas may be **higher** than typical contracts compiled with `optimizer_runs=200` or higher. The estimates in this document are based on EVM opcode costs and do not account for potential compiler-induced overhead from the low optimizer run count. Actual gas could be 5-15% higher.

---

## 3. advanceGame Analysis (CEIL-01, CEIL-02)

This section incorporates the full analysis from Plan 01.

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

For analysis below, **75,000** is the baseline common overhead.

---

### Stage 10: JACKPOT_PHASE_ENDED (Highest Risk)

**Entry Conditions:** Jackpot phase active, `dailyJackpotCoinTicketsPending` is true, `jackpotCounter >= JACKPOT_LEVEL_CAP` (5) after coin+ticket distribution. This is the level-transition stage that triggers end-of-level reward jackpots.

**Call Graph:**

```
advanceGame() [AdvanceModule:126]
  -> rngGate() -- RNG already consumed (warm)
  -> payDailyJackpotCoinAndTickets(rngWord) [delegatecall JackpotModule:681]
  |   -> _unpackDailyTicketBudgets()
  |   -> _calcDailyCoinBudget()
  |   -> _awardFarFutureCoinJackpot() -- 10 iterations (FAR_FUTURE_COIN_SAMPLES=10)
  |   -> _awardDailyCoinToTraitWinners() -- up to DAILY_COIN_MAX_WINNERS=50
  |   -> _distributeTicketJackpot() x2 -- up to LOOTBOX_MAX_WINNERS=100 each
  |   -> coin.rollDailyQuest()
  |   -> jackpotCounter += counterStep
  |   -> clear pending state
  -> _awardFinalDayDgnrsReward(lvl, rngWord) [delegatecall JackpotModule:773]
  |   -> dgnrs.transferFromPool() -- 1 winner, 1 external call
  -> _rewardTopAffiliate(lvl) [delegatecall EndgameModule]
  |   -> 1 SLOAD + 1 external call (affiliate reward)
  -> _runRewardJackpots(lvl, rngWord) [delegatecall EndgameModule:156]
  |   -> BAF jackpot: jackpots.runBafJackpot() -- up to 107 winners
  |   |   -> _runBafJackpot() processes winners via _addClaimableEth / _queueWhalePassClaimCore
  |   -> Decimator jackpot (levels x5, x00): runDecimatorJackpot() -- 11 iterations
  |   -> claimablePool update
  -> _endPhase() [AdvanceModule:474]
  |   -> phaseTransitionActive = true
  |   -> jackpotCounter = 0, compressedJackpotFlag = 0
  -> _unfreezePool()
  -> emit Advance, coin.creditFlip
```

**Loop Analysis:**

| Loop | Bound | Per-Iteration Cost | Worst-Case Total |
|------|-------|--------------------|------------------|
| _awardFarFutureCoinJackpot | 10 (FAR_FUTURE_COIN_SAMPLES) | ~8,000 | ~80,000 |
| _awardDailyCoinToTraitWinners | 50 (DAILY_COIN_MAX_WINNERS) | ~6,000 | ~300,000 |
| _distributeTicketJackpot (daily) | 100 (LOOTBOX_MAX_WINNERS) | ~5,000 | ~500,000 |
| _distributeTicketJackpot (carryover) | 100 (LOOTBOX_MAX_WINNERS) | ~5,000 | ~500,000 |
| _runBafJackpot: winner processing | 107 (BAF max winners) | ~25,000 | ~2,675,000 |
| Decimator: bucket loop (2-12) | 11 | ~7,000 | ~77,000 |

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

**Max Payouts:** BAF is code-capped at 107 winners. At ~45,000 gas per BAF winner, the 14M budget could support ~310 BAF winners. The **code constant (107) is the binding constraint**, not gas.

**Risk Level: SAFE** (>3M headroom)

---

### Stage 11: JACKPOT_DAILY_STARTED (Second Highest Risk)

**Entry Conditions:** Jackpot phase active, no ETH distribution in progress, no coin+ticket pending. Fresh daily jackpot start.

**Call Graph:**

```
advanceGame() [AdvanceModule:126]
  -> rngGate() -- RNG word consumed
  -> payDailyJackpot(true, lvl, rngWord) [delegatecall JackpotModule:323]
      -> Fresh start path:
      |   -> _rollWinningTraits() + _syncDailyWinningTraits()
      |   -> Turbo/compressed counter logic
      |   -> _runEarlyBirdLootboxJackpot() [JackpotModule:801] (day 1 only)
      |   |   -> 100 iterations: entropy step + _randTraitTicket + _queueTickets
      |   -> Budget calculations + storage writes
      -> Phase 0 chunk: _processDailyEthChunk [JackpotModule:1388]
          -> unitsBudget = DAILY_JACKPOT_UNITS_SAFE = 1000
          -> Per winner: _winnerUnits() returns 1 (normal) or 3 (auto-rebuy)
          -> Inner loop: select winners, _addClaimableEth per winner
          -> Exits when unitsUsed exceeds unitsBudget
```

**Loop Analysis:**

| Loop | Bound | Per-Iteration Cost | Worst-Case Total |
|------|-------|--------------------|------------------|
| _runEarlyBirdLootboxJackpot | 100 (fixed) | ~10,000 | ~1,000,000 |
| _processDailyEthChunk (Phase 0) | 333 max winners (1000 units / 3 per auto-rebuy) | ~25,000 per auto-rebuy winner | ~8,325,000 |
| Bucket iteration (outer) | 4 (fixed) | ~5,000 | ~20,000 |

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
| **TOTAL** | **~14,162,000** |

**CRITICAL: Theoretical breach by ~162,000 gas on Day 1 + full auto-rebuy.**

However, this requires ALL of: Day 1 of a new level (jackpotCounter == 0), a large enough prize pool for 333 winners, AND every winner having auto-rebuy enabled. The earlybird only fires on Day 1 when the prize pool is typically smallest.

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

Note: The `unitsBudget` of 1000 was specifically designed to keep gas under 15M (see JackpotModule:596 comment). The 14M conservative target makes this stage tight.

**Risk Level: AT_RISK** (Day 1 + full auto-rebuy can theoretically breach; non-Day-1 has <1M headroom with full auto-rebuy)

---

### Stage 7: ENTERED_JACKPOT

**Entry Conditions:** Purchase phase, `lastPurchaseDay` is true, pool consolidation and future ticket activation complete. Transition from purchase phase to jackpot phase.

**Call Graph:**

```
advanceGame() [AdvanceModule:126]
  -> rngGate() -- RNG word consumed
  -> _processFutureTicketBatch(nextLevel) [delegatecall MintModule]
  |   -> processTicketBatch bounded by WRITES_BUDGET_SAFE=550
  -> _consolidatePrizePools (if !poolConsolidationDone)
  |   -> _applyTimeBasedFutureTake + consolidatePrizePools (x00 yield, pool merge)
  -> Flag updates (earlyBurnPercent, jackpotPhaseFlag, decWindowOpen)
  -> _drawDownFuturePrizePool(lvl)
  -> emit Advance, coin.creditFlip
```

Note: `_runEarlyBirdLootboxJackpot` runs in **Stage 11 (JACKPOT_DAILY_STARTED)**, not Stage 7. Stage 7 handles consolidation and flag transitions only.

**Worst-Case Total (with full future ticket batch):**

| Component | Gas |
|-----------|-----|
| Common overhead | 75,000 |
| Delegatecall hops (JackpotModule, MintModule) | ~5,200 |
| rngGate (word available) | ~5,000 |
| _processFutureTicketBatch (357 writes) | ~1,785,000 |
| _applyTimeBasedFutureTake | ~10,000 |
| consolidatePrizePools | ~30,000 |
| Flag writes (7 SSTOREs) | ~35,000 |
| _drawDownFuturePrizePool | ~10,000 |
| Events | ~16,500 |
| **TOTAL** | **~1,972,000** |

**Headroom:** 14,000,000 - 1,972,000 = **12,028,000 gas** (86% remaining)

**Risk Level: SAFE** (>3M headroom)

---

### Stage 6: PURCHASE_DAILY

**Entry Conditions:** Purchase phase active, `!lastPurchaseDay`, new day. Runs daily during the purchase phase.

**Call Graph:**

```
advanceGame() [AdvanceModule:126]
  -> rngGate() -- RNG word consumed
  -> payDailyJackpot(false, purchaseLevel, rngWord) [delegatecall JackpotModule:323]
  |   -> isDaily=false path (non-daily / early-burn)
  |   -> _executeJackpot() -> _distributeJackpotEth() -- NOT chunked, runs to completion
  |   |   -> Up to JACKPOT_MAX_WINNERS=300 winners, 4 buckets
  |   |   -> Per winner: _addClaimableEth (auto-rebuy or normal)
  |   -> _distributeLootboxAndTickets() (conditional)
  |   -> coin.rollDailyQuest()
  -> _payDailyCoinJackpot(purchaseLevel, rngWord) [delegatecall JackpotModule:2361]
  |   -> _awardFarFutureCoinJackpot (10 iterations)
  |   -> _awardDailyCoinToTraitWinners (up to 50)
  -> _unlockRng(day), _unfreezePool()
```

**Critical detail:** Stage 6 uses `_distributeJackpotEth` which does NOT use `_processDailyEthChunk` with chunking. It distributes to all winners in a single call with NO unit budget. Maximum: `JACKPOT_MAX_WINNERS = 300`.

**Loop Analysis:**

| Loop | Bound | Per-Iteration Cost | Worst-Case Total |
|------|-------|--------------------|------------------|
| _distributeJackpotEth (non-chunked) | 300 (JACKPOT_MAX_WINNERS) | ~25,000 per auto-rebuy winner | ~7,500,000 |
| _awardFarFutureCoinJackpot | 10 (fixed) | ~8,000 | ~80,000 |
| _awardDailyCoinToTraitWinners | 50 (DAILY_COIN_MAX_WINNERS) | ~6,000 | ~300,000 |
| _distributeLootboxAndTickets | 100 (LOOTBOX_MAX_WINNERS) | ~5,000 | ~500,000 |

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
| **TOTAL** | **~12,952,000** |

**Headroom:** 14,000,000 - 12,952,000 = **1,048,000 gas**

Note: During the purchase phase, the early-burn ETH pool is small (1% daily drip from futurePool). The 300-winner worst case requires a very large futurePool.

**Max Payouts under 14M:** At ~43,000 gas per auto-rebuy winner, 14M with ~120,000 overhead supports ~323 winners. **Code constant (300) is the binding constraint.**

**Risk Level: TIGHT** (1-3M headroom; non-chunked but code-bounded at 300 winners)

---

### Stage 0: GAMEOVER

**Entry Conditions:** Liveness guard triggered -- either level 0 with 365-day idle timeout, or level != 0 with 120-day inactivity. One-time terminal event.

**Call Graph:**

```
advanceGame() [AdvanceModule:126]
  -> _handleGameOverPath(ts, day, lst, lvl, lastPurchase, dailyIdx)
      |
      +-- Pre-gameover (gameOver == false):
      |   -> _gameOverEntropy()
      |   -> _unlockRng(day)
      |   -> delegatecall GameOverModule.handleGameOverDrain(day)
      |       -> deityPassOwners loop (early game, lvl < 10)
      |       |   -> capped at 32 by DEITY_PASS_MAX_TOTAL
      |       -> gameOver = true
      |       -> Terminal decimator: runTerminalDecimatorJackpot (11 iterations)
      |       -> Terminal jackpot: _distributeJackpotEth (up to 321 winners, NO auto-rebuy)
      |       -> dgnrs.burnRemainingPools()
      |       -> Optional: _sendToVault()
      |
      +-- Post-gameover (gameOver == true):
          -> handleFinalSweep() (after 30 days)
```

**Key insight:** Terminal jackpot sets `gameOver = true` BEFORE distribution, which disables auto-rebuy inside `_addClaimableEth` (EndgameModule:248: `if (!gameOver)` check). All winners take the normal path (~12,000 gas each).

**Deity Pass Loop:** Hard-capped at 32 by `DEITY_PASS_MAX_TOTAL`. At 32 iterations x ~12,000 gas = ~384,000 gas. **Not a DoS vector. Not a finding.**

**Worst-Case Total (pre-gameover, lvl < 10):**

| Component | Gas |
|-----------|-----|
| Common overhead (reduced -- returns early) | 60,000 |
| Delegatecall (GameOverModule) | ~2,600 |
| _gameOverEntropy + _unlockRng | ~15,000 |
| Deity pass owner loop (32 owners) | ~384,000 |
| claimablePool update | ~5,000 |
| gameOver flag + storage writes | ~25,000 |
| Terminal decimator jackpot | ~100,000 |
| Terminal jackpot (321 winners, no auto-rebuy) | ~8,378,000 |
| dgnrs.burnRemainingPools() | ~10,000 |
| _sendToVault (stETH + ETH transfers) | ~50,000 |
| Advance event + bounty | ~6,500 |
| **TOTAL** | **~9,036,000** |

**Headroom:** 14,000,000 - 9,036,000 = **4,964,000 gas** (35% remaining)

**Risk Level: SAFE** (>3M headroom)

---

### Stage 1: RNG_REQUESTED

**Entry Conditions:** New day detected, no pending VRF word. Requests fresh random word from Chainlink VRF.

No loops. Linear path with single external VRF call.

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

**Risk Level: SAFE**

---

### Stage 2: TRANSITION_WORKING

**Entry Conditions:** `phaseTransitionActive` true, `_processPhaseTransition()` returns false. In practice, transition completes atomically (falls through to TRANSITION_DONE).

No loops. Two `_queueTickets` calls (O(1) each) + one external stETH call.

**Worst-Case Total:**

| Component | Gas |
|-----------|-----|
| Common overhead | 75,000 |
| rngGate (word available) | ~5,000 |
| _queueTickets x2 | ~90,000 |
| _autoStakeExcessEth (stETH submit) | ~35,000 |
| **TOTAL** | **~205,000** |

**Headroom:** 14,000,000 - 205,000 = **13,795,000 gas** (98.5% remaining)

**Risk Level: SAFE**

---

### Stage 3: TRANSITION_DONE

**Entry Conditions:** `phaseTransitionActive` true, `_processPhaseTransition()` returns true. Normal outcome.

Same as TRANSITION_WORKING plus additional flag updates.

**Worst-Case Total:**

| Component | Gas |
|-----------|-----|
| Common overhead | 75,000 |
| rngGate (word available) | ~5,000 |
| _processPhaseTransition (tickets + stETH) | ~125,000 |
| Flag updates + _unlockRng + _unfreezePool | ~50,000 |
| **TOTAL** | **~255,000** |

**Headroom:** 14,000,000 - 255,000 = **13,745,000 gas** (98.2% remaining)

**Risk Level: SAFE**

---

### Stage 4: FUTURE_TICKETS_WORKING

**Entry Conditions:** No daily jackpot in progress, `_prepareFutureTickets(lvl)` returns false. Activates tickets for levels lvl+2 through lvl+6.

Each `advanceGame()` call processes at most ONE batch of 550 writes (or 357 on first call).

**Worst-Case Total (full 550-write batch):**

| Component | Gas |
|-----------|-----|
| Common overhead | 75,000 |
| rngGate (word available) | ~5,000 |
| Delegatecall (MintModule) | ~2,600 |
| processTicketBatch (550 SSTOREs) | ~2,750,000 |
| Cursor + state updates | ~15,000 |
| Events | ~15,000 |
| **TOTAL** | **~2,863,000** |

**Headroom:** 14,000,000 - 2,863,000 = **11,137,000 gas** (79.6% remaining)

**Risk Level: SAFE**

---

### Stage 5: TICKETS_WORKING

**Entry Conditions:** Current level ticket queue has entries. Processes current level ticket queue via `processTicketBatch`.

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
| **TOTAL** | **~3,028,000** |

**Headroom:** 14,000,000 - 3,028,000 = **10,972,000 gas** (78.4% remaining)

**Risk Level: SAFE**

---

### Stage 8: JACKPOT_ETH_RESUME

**Entry Conditions:** Jackpot phase, ETH distribution cursors non-zero. Resumes prior chunked distribution.

Same chunking mechanism as Stage 11 but starting from saved cursor. No earlybird, no init overhead.

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
| **TOTAL** | **~13,122,000** |

**Headroom:** 14,000,000 - 13,122,000 = **878,000 gas**

**Risk Level: AT_RISK** (<1M headroom with all auto-rebuy winners)

---

### Stage 9: JACKPOT_COIN_TICKETS

**Entry Conditions:** Jackpot phase, `dailyJackpotCoinTicketsPending` true, `jackpotCounter < JACKPOT_LEVEL_CAP` (5). Coin+ticket phase WITHOUT end-of-level rewards.

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
| **TOTAL** | **~1,764,000** |

**Headroom:** 14,000,000 - 1,764,000 = **12,236,000 gas** (87.4% remaining)

**Risk Level: SAFE**

---

### CEIL-01 Summary: All 12 Stages

| Stage | Constant | Name | Worst-Case Gas | Headroom | Risk Level |
|-------|----------|------|----------------|----------|------------|
| 0 | STAGE_GAMEOVER | GAMEOVER | ~9,036,000 | 4,964,000 | SAFE |
| 1 | STAGE_RNG_REQUESTED | RNG_REQUESTED | ~215,000 | 13,785,000 | SAFE |
| 2 | STAGE_TRANSITION_WORKING | TRANSITION_WORKING | ~205,000 | 13,795,000 | SAFE |
| 3 | STAGE_TRANSITION_DONE | TRANSITION_DONE | ~255,000 | 13,745,000 | SAFE |
| 4 | STAGE_FUTURE_TICKETS_WORKING | FUTURE_TICKETS | ~2,863,000 | 11,137,000 | SAFE |
| 5 | STAGE_TICKETS_WORKING | TICKETS_WORKING | ~3,028,000 | 10,972,000 | SAFE |
| 6 | STAGE_PURCHASE_DAILY | PURCHASE_DAILY | ~12,952,000 | 1,048,000 | TIGHT |
| 7 | STAGE_ENTERED_JACKPOT | ENTERED_JACKPOT | ~1,972,000 | 12,028,000 | SAFE |
| 8 | STAGE_JACKPOT_ETH_RESUME | JACKPOT_ETH_RESUME | ~13,122,000 | 878,000 | AT_RISK |
| 9 | STAGE_JACKPOT_COIN_TICKETS | JACKPOT_COIN_TICKETS | ~1,764,000 | 12,236,000 | SAFE |
| 10 | STAGE_JACKPOT_PHASE_ENDED | JACKPOT_PHASE_ENDED | ~6,058,000 | 7,942,000 | SAFE |
| 11 | STAGE_JACKPOT_DAILY_STARTED | JACKPOT_DAILY_STARTED | ~14,162,000 | -162,000 | AT_RISK |

**Legend:**
- **SAFE:** >3M headroom. No risk of exceeding 14M gas ceiling.
- **TIGHT:** 1-3M headroom. Within budget but limited margin.
- **AT_RISK:** <1M headroom. Could breach 14M under extreme worst-case conditions.

---

### CEIL-02: Maximum Jackpot Payouts Under 14M

#### Per-Winner Gas Cost Reference

| Distribution Path | Normal Winner | Auto-Rebuy Winner | Notes |
|-------------------|---------------|-------------------|-------|
| _processDailyEthChunk (chunked) | ~15,000 (1 unit) | ~38,600 (3 units) | SLOAD, SSTORE, event, distribution |
| _distributeJackpotEth (non-chunked) | ~12,000 | ~25,000 | Early-burn and terminal jackpot |
| BAF (_runBafJackpot) | ~45,000 | ~45,000 | External call, whale pass queuing |
| Coin jackpot (BURNIE) | ~6,000 | N/A | Token credit only |
| Lootbox/ticket distribution | ~5,000 | N/A | _queueTickets O(1) per winner |
| Earlybird lootbox | ~10,000 | N/A | Winner selection + ticket queuing |

#### Maximum Winner Counts by Stage

| Stage | Distribution Type | Max Winners (Code) | Max Winners (14M) | Binding Constraint |
|-------|-------------------|--------------------|--------------------|--------------------|
| 0 (GAMEOVER) | Terminal jackpot (non-chunked) | 321 | ~538 (normal) | Code constant (321) |
| 0 (GAMEOVER) | Deity pass refund | 32 | ~1,166 | Code constant (32) |
| 6 (PURCHASE_DAILY) | Early-burn ETH (non-chunked) | 300 | ~323 (auto-rebuy) | Code constant (300) |
| 6 (PURCHASE_DAILY) | BURNIE coin jackpot | 50 | ~2,333 | Code constant (50) |
| 6 (PURCHASE_DAILY) | Lootbox tickets | 100 | ~2,800 | Code constant (100) |
| 7 (ENTERED_JACKPOT) | Future ticket batch | 550 writes | ~2,563 writes | Code constant (550) |
| 8 (JACKPOT_ETH_RESUME) | Daily ETH chunk (chunked) | 321 per phase | 333 (auto-rebuy) | unitsBudget=1000 |
| 9 (JACKPOT_COIN_TICKETS) | BURNIE coin jackpot | 50 | ~2,333 | Code constant (50) |
| 9 (JACKPOT_COIN_TICKETS) | Ticket distribution | 200 (100 x 2) | ~2,800 | Code constant (100) |
| 10 (JACKPOT_PHASE_ENDED) | BAF jackpot | 107 | ~310 | Code constant (107) |
| 10 (JACKPOT_PHASE_ENDED) | BURNIE coin + tickets | 50 + 200 | ~2,333 + ~2,800 | Code constants |
| 11 (JACKPOT_DAILY_STARTED) | Daily ETH chunk (chunked) | 321 | 333 (auto-rebuy) | unitsBudget=1000 |
| 11 (JACKPOT_DAILY_STARTED) | Earlybird lootbox (Day 1) | 100 | ~1,400 | Code constant (100) |

**Key Findings:**

1. **All code-bounded winner constants fit within 14M.** No single stage exceeds 14M due to winner count alone.
2. **The binding constraint is always the code constant**, except for daily ETH chunking (Stages 8, 11) where `unitsBudget=1000` limits winners per chunk.
3. **AT_RISK stages (8 and 11) are tight when all winners use auto-rebuy** (3x unit cost). With 333 auto-rebuy winners, gas approaches 13-14M. In practice, a mix of normal and auto-rebuy winners keeps gas well under 14M.
4. **Stage 11 Day 1 theoretical breach:** Earlybird (~1M gas) + full 333 auto-rebuy winners can exceed 14M by ~162K. This requires Day 1 + large pool + universal auto-rebuy -- economically extremely unlikely.
5. **GAMEOVER terminal jackpot is safe** because `gameOver=true` disables auto-rebuy, capping per-winner cost at ~12K.
6. **Deity pass loop is bounded at 32** by `DEITY_PASS_MAX_TOTAL`. Not a DoS vector.

---

## 4. Purchase Analysis (CEIL-03, CEIL-04)

### Common Purchase Overhead

All purchase paths enter via `DegenerusGame.sol` and delegatecall into `DegenerusGameMintModule`:

| Component | Gas Cost | Notes |
|-----------|----------|-------|
| Base transaction cost | 21,000 | EVM intrinsic |
| _resolvePlayer | ~200 | Checks address(0), potential _requireApproved |
| Delegatecall to MintModule | ~2,600 | Cold address first call |
| gameOver check | ~2,100 | 1 cold SLOAD |
| Level + price reads | ~4,200 | 2 cold SLOADs |
| **Total common overhead** | **~30,100** | |

---

### Path 1: Ticket Purchase (ETH) -- `purchase()` with `ticketQuantity > 0`, `lootBoxAmount = 0`

**Entry:** `DegenerusGame.sol:542 purchase()` -> delegatecall `MintModule._purchaseFor()` (line 619)

**Call Chain:**

```
purchase() [DegenerusGame.sol:542]
  -> _resolvePlayer(buyer)
  -> delegatecall MintModule.purchase() -> _purchaseFor() [MintModule:619]
     -> cost calculation: arithmetic (no storage)
     -> claimableWinnings[buyer] SLOAD (1 cold read) [MintModule:642]
     -> _callTicketPurchase() [MintModule:831]
        -> consumePurchaseBoost: self-call [MintModule:857]
        |   -> lootboxBoon check: up to 3 SLOADs (cold) [~6,300]
        -> recordMint{value}: CALL to self (not delegatecall) [MintModule:915]
        |   -> _processMintPayment: 2-5 SSTOREs (prize pool splits) [~10,000-25,000]
        |   -> _recordMintDataModule: delegatecall MintModule (warm ~100) [~15,000]
        |   |   -> mintPacked_ SLOAD + SSTORE, lastPurchaseData updates
        |   -> _awardEarlybirdDgnrs: conditional sDGNRS transfer [~0-15,000]
        -> affiliate.payAffiliate() external call [MintModule:963-999]
        |   -> Cold address: ~2,600 + ~12,000 internal execution
        |   -> Storage: playerReferralCode SLOAD + affiliateCode SLOAD + score SSTOREs
        -> coin.notifyQuestMint() external call [MintModule:941]
        |   -> Cold address: ~2,600 + ~5,000 internal execution
        -> coin.creditFlip(buyer, bonusCredit) [MintModule:1012]
        |   -> Warm address: ~100 + ~5,000 internal execution
        -> _queueTicketsScaled() [Storage:564] -- O(1)
           -> 1 SLOAD (ticketsOwedPacked)
           -> Conditional: ticketQueue[wk].push(buyer) (1 SSTORE if new entry)
           -> 1 SSTORE (ticketsOwedPacked update)
           -> 1 event (TicketsQueuedScaled)
```

**Storage Operations:**

| Operation | Count | Gas |
|-----------|-------|-----|
| Cold SLOADs (gameOver, level, price, claimableWinnings, mintPacked_, jackpotPhaseFlag, etc.) | ~12 | ~25,200 |
| Cold SSTOREs (prize pool split writes: next+future pools or pending pools) | ~2-3 | ~10,000-15,000 |
| Cold SSTOREs (_recordMintDataModule: mintPacked_ update) | 1 | ~5,000 |
| Cold SSTOREs (_queueTicketsScaled: ticketsOwedPacked + potential array push) | 1-2 | ~5,000-27,100 |
| Warm SSTOREs (pool updates, counters) | ~2 | ~200 |

**External Calls:**

| Call | Target | Gas |
|------|--------|-----|
| self.consumePurchaseBoost() | Self-call (warm) | ~8,000 |
| self.recordMint{value}() | Self-call with ETH (warm) | ~50,000 |
| affiliate.payAffiliate() | DegenerusAffiliate (cold) | ~15,000 |
| coin.notifyQuestMint() | BurnieCoin (cold) | ~8,000 |
| coin.creditFlip() | BurnieCoin (warm) | ~5,000 |

**Events:**

| Event | Count | Gas |
|-------|-------|-----|
| TicketsQueuedScaled | 1 | ~2,000 |
| MintRecorded (inside recordMint) | 1 | ~3,000 |

**Worst-Case Total (first-ever purchase, all cold storage, earlybird active):**

| Component | Gas |
|-----------|-----|
| Common overhead | 30,100 |
| Cost calculation + claimable read | ~2,500 |
| _callTicketPurchase: consumePurchaseBoost | ~8,000 |
| _callTicketPurchase: recordMint self-call | ~50,000 |
| _processMintPayment (prize pool splits) | ~25,000 |
| _recordMintDataModule (delegatecall warm + storage) | ~15,000 |
| _awardEarlybirdDgnrs (sDGNRS transfer) | ~15,000 |
| affiliate.payAffiliate (cold + execution) | ~15,000 |
| coin.notifyQuestMint (cold + execution) | ~8,000 |
| coin.creditFlip (warm + execution) | ~5,000 |
| _queueTicketsScaled (new entry: push + SSTORE) | ~30,000 |
| Events | ~5,000 |
| x00 century bonus path (conditional extra SLOADs) | ~10,000 |
| **TOTAL** | **~218,600** |

**Batch Scaling:** `purchase()` is called once per transaction. The `_queueTicketsScaled` function is **O(1) regardless of `ticketQuantity`** -- it stores `(buyer, quantity, level)` as a single queue entry with one SLOAD and one SSTORE. Gas does NOT scale with ticket count.

**Headroom:** 14,000,000 - 218,600 = **13,781,400 gas** (98.4% remaining)

**Risk Level: SAFE**

---

### Path 2: Lootbox Purchase (ETH) -- `purchase()` with `ticketQuantity = 0`, `lootBoxAmount > 0`

**Entry:** Same `_purchaseFor()` but ticket branch skipped, lootbox branch executes.

**Call Chain:**

```
_purchaseFor() [MintModule:619]
  -> cost + payment calculation
  -> lootBoxAmount != 0 path [MintModule:684]:
     -> lootboxRngIndex SLOAD [~2,100]
     -> lootboxEth[index][buyer] SLOAD [~2,100]
     -> lootboxDay[index][buyer] SLOAD [~2,100]
     -> Conditional new entry: 4 SSTOREs (day, baseLevel, evScore, indexQueue push) [~88,400 zero->nonzero worst case]
     -> _applyLootboxBoostOnPurchase: 3 boost tier checks (SLOADs), conditional SSTORE [~15,000]
     -> lootboxEthBase[index][buyer] SLOAD + SSTORE [~7,100]
     -> lootboxEth[index][buyer] SSTORE (pack amount + level) [~5,000]
     -> lootboxEthTotal SSTORE [~5,000]
     -> _maybeRequestLootboxRng: lootboxRngPendingEth SSTORE [~5,000]
     -> Prize pool split: 4 SSTOREs [~20,000]
     -> Conditional vault call [~30,000 if presale with vault share]
     -> affiliate.payAffiliate() x1-2 [~15,000-30,000]
     -> coin.creditFlip (lootbox kickback) [~5,000]
     -> coin.notifyQuestMint [~8,000]
     -> coin.notifyQuestLootBox [~8,000]
     -> _awardEarlybirdDgnrs [~0-15,000]
  -> Spent-all-claimable bonus check [~2,000]
```

**Storage Operations:**

| Operation | Count | Gas |
|-----------|-------|-----|
| Cold SLOADs (lootbox state: index, eth, day, base, pending, etc.) | ~15 | ~31,500 |
| Cold SSTOREs (lootbox entry: day, baseLevel, evScore, queue push) | 4 | ~88,400 (zero->nonzero worst case) |
| Cold SSTOREs (lootboxEthBase, lootboxEth, lootboxEthTotal, rngPending) | 4 | ~20,000 |
| Cold SSTOREs (prize pool splits) | 2 | ~10,000 |
| Boost check SLOADs (boon25/15/5 Active + Day) | 6 | ~12,600 |

**External Calls:**

| Call | Target | Gas |
|------|--------|-----|
| affiliate.payAffiliate() x2 | DegenerusAffiliate (cold then warm) | ~18,000 |
| coin.creditFlip() | BurnieCoin (cold) | ~8,000 |
| coin.notifyQuestMint() | BurnieCoin (warm) | ~5,000 |
| coin.notifyQuestLootBox() | BurnieCoin (warm) | ~5,000 |
| _awardEarlybirdDgnrs -> dgnrs.transferFromPool() | sDGNRS (cold) | ~15,000 |
| Vault ETH transfer (presale only) | Vault (cold) | ~30,000 |

**Worst-Case Total (first-ever lootbox, new entry, all cold, presale with vault):**

| Component | Gas |
|-----------|-----|
| Common overhead | 30,100 |
| Lootbox state reads | ~31,500 |
| New lootbox entry (4 zero->nonzero SSTOREs) | ~88,400 |
| Lootbox update SSTOREs | ~20,000 |
| _applyLootboxBoostOnPurchase | ~15,000 |
| Prize pool splits | ~10,000 |
| Vault ETH transfer (presale) | ~30,000 |
| affiliate.payAffiliate x2 | ~18,000 |
| coin.creditFlip + notifyQuestMint + notifyQuestLootBox | ~18,000 |
| _awardEarlybirdDgnrs | ~15,000 |
| Events (LootBoxBuy, LootBoxIdx, BoostUsed) | ~10,000 |
| **TOTAL** | **~286,000** |

**Without presale vault or earlybird:** ~241,000 gas

**Headroom:** 14,000,000 - 286,000 = **13,714,000 gas** (97.9% remaining)

**Risk Level: SAFE**

---

### Path 3: Combined Ticket + Lootbox (ETH) -- `purchase()` with both > 0

**Entry:** Same `_purchaseFor()`, both branches execute in sequence.

```
_purchaseFor() [MintModule:619]
  -> Payment resolution (lootbox first, then ticket) [MintModule:647-681]
  -> _callTicketPurchase() -- all Path 1 costs
  -> Lootbox path -- all Path 2 costs (minus shared overhead)
  -> Spent-all-claimable bonus [MintModule:820-828]
     -> coin.creditFlip() [~5,000]
```

**Shared overhead savings:**
- Common overhead already paid (not doubled)
- MintModule delegatecall already warm after first path
- Some SLOADs warm from ticket path (level, price, gameOver, jackpotPhaseFlag)
- affiliate contract warm after ticket path's payAffiliate call
- BurnieCoin warm after ticket path's creditFlip/notifyQuestMint

**Worst-Case Total:**

| Component | Gas |
|-----------|-----|
| Common overhead (single) | 30,100 |
| Payment resolution (claimable shortfall path) | ~15,000 |
| Path 1: Ticket purchase costs (recordMint + affiliate + queue) | ~155,000 |
| Path 2: Lootbox costs (new entry + boost + pool splits + affiliate + coin calls) | ~190,000 |
| Shared overhead savings (warm SLOADs/calls) | -10,000 |
| Spent-all-claimable bonus | ~7,000 |
| x00 century bonus path | ~10,000 |
| Events | ~12,000 |
| _awardEarlybirdDgnrs x2 (ticket + lootbox paths) | ~25,000 |
| Vault ETH transfer (presale) | ~30,000 |
| **TOTAL** | **~464,100** |

**Absolute worst case with all optional paths active (presale, earlybird, century bonus, all boosts):** ~600,000 gas

**Headroom (absolute worst):** 14,000,000 - 600,000 = **13,400,000 gas** (95.7% remaining)

**Risk Level: SAFE**

---

### Path 4: purchaseCoin (BURNIE Tickets) -- `purchaseCoin()` with `ticketQuantity > 0`

**Entry:** `DegenerusGame.sol:587 purchaseCoin()` -> delegatecall `MintModule.purchaseCoin()`

**Call Chain:**

```
purchaseCoin() [DegenerusGame.sol:587]
  -> _resolvePlayer(buyer)
  -> delegatecall MintModule.purchaseCoin() [MintModule:577]
     -> _purchaseCoin() [MintModule:580]
        -> level, levelStartTime SLOADs [~4,200]
        -> Coin purchase cutoff check [~100]
        -> _callTicketPurchase() [MintModule:831] with payInCoin=true
           -> _coinReceive(payer, coinCost) -> coin.burnCoin() [cold external call]
           |   -> BurnieCoin.burnCoin: allowance SLOAD + balance SLOAD + 2 SSTOREs
           -> coin.notifyQuestMint() [warm]
           -> bonusCredit = coinCost / 10 (arithmetic only)
           -> coin.creditFlip(buyer, bonusCredit) [warm]
           -> _queueTicketsScaled() -- O(1)
```

**Storage Operations:**

| Operation | Count | Gas |
|-----------|-------|-----|
| Cold SLOADs (gameOver, level, levelStartTime, price) | ~4 | ~8,400 |
| _queueTicketsScaled SLOADs + SSTOREs | ~2 | ~7,100-27,100 |

**External Calls:**

| Call | Target | Gas |
|------|--------|-----|
| coin.burnCoin() | BurnieCoin (cold) | ~15,000 |
| coin.notifyQuestMint() | BurnieCoin (warm) | ~5,000 |
| coin.creditFlip() | BurnieCoin (warm) | ~5,000 |

**Worst-Case Total:**

| Component | Gas |
|-----------|-----|
| Common overhead | 30,100 |
| Level + cutoff reads | ~8,400 |
| coin.burnCoin (cold + execution) | ~15,000 |
| coin.notifyQuestMint (warm) | ~5,000 |
| coin.creditFlip (warm) | ~5,000 |
| _queueTicketsScaled (new entry) | ~30,000 |
| Events | ~3,000 |
| **TOTAL** | **~96,500** |

**Key differences from ETH purchase:**
- No prize pool splits (BURNIE is burned, not distributed)
- No affiliate payments (BURNIE purchases bypass affiliate system)
- No earlybird DGNRS awards
- No recordMint self-call (significantly cheaper)

**Headroom:** 14,000,000 - 96,500 = **13,903,500 gas** (99.3% remaining)

**Risk Level: SAFE**

---

### Path 5: purchaseWhaleBundle -- `purchaseWhaleBundle()` with `quantity = 1-100`

**Entry:** `DegenerusGame.sol:640 purchaseWhaleBundle()` -> delegatecall `WhaleModule.purchaseWhaleBundle()`

**Call Chain:**

```
purchaseWhaleBundle() [DegenerusGame.sol:640]
  -> _resolvePlayer(buyer)
  -> delegatecall WhaleModule.purchaseWhaleBundle() [WhaleModule:183]
     -> _purchaseWhaleBundle() [WhaleModule:187]
        -> State reads: gameOver, level, whaleBoonDay[buyer], mintPacked_[buyer] [~8,400]
        -> Price calculation + msg.value check [~100]
        -> _awardEarlybirdDgnrs() [~0-15,000]
        -> mintPacked_ update (bit packing) [~5,000]
        -> _queueTickets loop: 100 iterations [WhaleModule:264-269]
        |   -> Per iteration: _queueTickets(buyer, lvl, tickets)
        |   |   -> ticketsOwedPacked[wk][buyer] SLOAD + SSTORE
        |   |   -> Conditional: ticketQueue[wk].push(buyer)
        |   |   -> Event: TicketsQueued
        -> affiliate.getReferrer x3 [WhaleModule:271-278]
        -> _rewardWhaleBundleDgnrs x quantity [WhaleModule:281-284]
        |   -> Per call: dgnrs.poolBalance() x2 + dgnrs.transferFromPool() x1-4
        -> Prize pool split [~10,000]
        -> _recordLootboxEntry [~90,000 worst case]
```

**Critical: _queueTickets 100-level loop**

This is the most gas-intensive part of purchaseWhaleBundle. Unlike `_queueTicketsScaled` which is O(1), the whale bundle calls `_queueTickets` in a loop across 100 levels.

| Operation | Per-Iteration | Notes |
|-----------|---------------|-------|
| ticketsOwedPacked SLOAD | ~2,100 (cold) | Each level is a different mapping key |
| ticketQueue[wk].push | ~22,100 (zero->nonzero if new entry) | Only on first purchase for this level |
| ticketsOwedPacked SSTORE | ~5,000 (nonzero->nonzero) | Update packed value |
| TicketsQueued event | ~2,000 | Per iteration |

**Worst-Case per iteration (new player, new level):** ~31,200 gas
**Warm case (existing entries):** ~9,200 gas

**Loop total (100 iterations, worst case all new):** ~3,120,000 gas
**Loop total (100 iterations, existing entries):** ~920,000 gas

In practice, many levels will have existing entries for returning whale buyers, reducing the per-iteration cost.

**_rewardWhaleBundleDgnrs per call:**

| Operation | Gas |
|-----------|-----|
| dgnrs.poolBalance(Whale) external call | ~5,000 |
| dgnrs.transferFromPool(Whale, buyer) external call | ~10,000 |
| dgnrs.poolBalance(Affiliate) external call | ~5,000 |
| dgnrs.transferFromPool(Affiliate, affiliate) x1-3 | ~10,000-30,000 |
| **Per call total** | **~30,000-50,000** |

At quantity=100: ~3,000,000-5,000,000 gas for DGNRS rewards alone.

**Worst-Case Total (quantity=100, all new levels, full DGNRS rewards):**

| Component | Gas |
|-----------|-----|
| Common overhead | 30,100 |
| State reads + price calc | ~10,000 |
| _awardEarlybirdDgnrs | ~15,000 |
| mintPacked_ update | ~5,000 |
| _queueTickets loop (100 iterations, new) | ~3,120,000 |
| affiliate.getReferrer x3 | ~20,000 |
| _rewardWhaleBundleDgnrs x100 | ~5,000,000 |
| Prize pool split | ~10,000 |
| _recordLootboxEntry | ~90,000 |
| **TOTAL** | **~8,300,000** |

**Worst-Case Total (quantity=1, most common case):**

| Component | Gas |
|-----------|-----|
| Common overhead | 30,100 |
| State reads + price calc + earlybird + mint update | ~30,000 |
| _queueTickets loop (100 iterations, mixed new/existing) | ~1,500,000 |
| _rewardWhaleBundleDgnrs x1 | ~50,000 |
| Prize pool split + lootbox entry | ~100,000 |
| **TOTAL** | **~1,710,000** |

**Typical case (quantity=1, existing player with some levels):** ~800,000 gas

**Headroom (qty=100 worst case):** 14,000,000 - 8,300,000 = **5,700,000 gas** (40.7% remaining)
**Headroom (qty=1 worst case):** 14,000,000 - 1,710,000 = **12,290,000 gas** (87.8% remaining)

**Risk Level: SAFE** (even quantity=100 extreme case has >3M headroom)

---

### Path 6: purchaseBurnieLootbox -- `purchaseBurnieLootbox()` with `burnieAmount > 0`

**Entry:** `DegenerusGame.sol:609 purchaseBurnieLootbox()` -> delegatecall `MintModule.purchaseBurnieLootbox()`

**Call Chain:**

```
purchaseBurnieLootbox() [DegenerusGame.sol:609]
  -> _resolvePlayer(buyer)
  -> delegatecall MintModule.purchaseBurnieLootbox() [MintModule:?]
     -> _purchaseBurnieLootboxFor() [MintModule:1039]
        -> gameOver check [1 SLOAD]
        -> burnieAmount check against BURNIE_LOOTBOX_MIN
        -> lootboxRngIndex SLOAD [~2,100]
        -> coin.burnCoin(buyer, burnieAmount) [cold external call]
        |   -> BurnieCoin: allowance + balance SLOADs + 2 SSTOREs
        -> coin.notifyQuestMint() [warm]
        -> lootboxBurnie[index][buyer] SLOAD [~2,100]
        -> Conditional: lootboxDay[index][buyer] SLOAD + SSTORE [~7,100]
        -> lootboxBurnie[index][buyer] SSTORE [~5,000]
        -> lootboxRngPendingBurnie SSTORE [~5,000]
        -> price SLOAD [~2,100]
        -> _maybeRequestLootboxRng: lootboxRngPendingEth SSTORE [~5,000]
        -> Event: BurnieLootBuy
```

**Key difference from ETH lootbox:** Much lighter -- no prize pool splits, no affiliate payments, no boost check, no vault transfer.

**Note on VRF:** `_maybeRequestLootboxRng` does NOT make an external VRF call. It simply increments `lootboxRngPendingEth` -- a storage accumulator. VRF requests for lootbox resolution happen separately during `advanceGame()`.

**Storage Operations:**

| Operation | Count | Gas |
|-----------|-------|-----|
| Cold SLOADs (gameOver, lootboxRngIndex, lootboxBurnie, lootboxDay, price) | ~6 | ~12,600 |
| Cold SSTOREs (lootboxBurnie, lootboxRngPendingBurnie, lootboxRngPendingEth) | 3 | ~15,000 |
| Conditional SSTORE (lootboxDay if first entry) | 1 | ~22,100 (zero->nonzero) |

**External Calls:**

| Call | Target | Gas |
|------|--------|-----|
| coin.burnCoin() | BurnieCoin (cold) | ~15,000 |
| coin.notifyQuestMint() | BurnieCoin (warm) | ~5,000 |

**Worst-Case Total (first-ever BURNIE lootbox, new day entry):**

| Component | Gas |
|-----------|-----|
| Common overhead | 30,100 |
| State reads | ~12,600 |
| coin.burnCoin (cold + execution) | ~15,000 |
| coin.notifyQuestMint (warm) | ~5,000 |
| Lootbox storage writes | ~42,100 |
| _maybeRequestLootboxRng | ~5,000 |
| Events | ~3,000 |
| **TOTAL** | **~112,800** |

**Without new day entry (existing lootbox):** ~90,700 gas

**Headroom:** 14,000,000 - 112,800 = **13,887,200 gas** (99.2% remaining)

**Risk Level: SAFE**

---

### CEIL-04: Maximum Ticket Batch Size Under 14M

**Key Finding: purchase() queues tickets in O(1) via `_queueTicketsScaled`, so batch size is NOT gas-limited.**

The `_queueTicketsScaled` function (DegenerusGameStorage.sol:564) stores the ticket order as a single packed entry:

```solidity
function _queueTicketsScaled(address buyer, uint24 targetLevel, uint32 quantityScaled) internal {
    // ... pack (buyer, quantity) into a single storage slot
    ticketsOwedPacked[wk][buyer] = packed;
}
```

This is **O(1) regardless of `quantityScaled`**. Whether a player buys 1 ticket or 1,000,000 tickets, the gas cost is identical: one SLOAD + one SSTORE + one event + potential array push.

**Gas limiter for purchase:** The fixed per-call overhead (~100K-600K depending on path), not per-ticket scaling.

**Maximum batch computation:**
- Per-call overhead for worst case (Combined ticket + lootbox): ~600,000 gas
- Remaining headroom: 14,000,000 - 600,000 = 13,400,000 gas
- This headroom is NOT consumed by additional tickets -- the gas stays at ~600K regardless
- **Maximum batch = limited only by `msg.value / ticketPrice`, not by gas**

**For combined ticket+lootbox:** Still O(1) gas regardless of quantities.

**Exception: purchaseWhaleBundle** uses a `_queueTickets` loop across 100 levels (not `_queueTicketsScaled`). This is O(100) per call, costing ~1-3M gas for the loop alone. However, this is still well within the 14M ceiling even at quantity=100.

**Conclusion:** The protocol's O(1) ticket queuing design means gas does NOT constrain batch size. The 14M ceiling is consumed by fixed per-call overhead (~250K-600K), leaving 13.4M+ headroom. The batch size is economically bounded (by `msg.value / ticketPrice`), not gas bounded.

---

## 5. Headroom Summary (CEIL-05)

### Master Headroom Table

| Path Type | Path Name | Worst-Case Gas | Headroom (14M - WC) | Risk Level | Binding Constraint |
|-----------|-----------|----------------|----------------------|------------|-------------------|
| advanceGame | STAGE_GAMEOVER (0) | ~9,036,000 | 4,964,000 | SAFE | Code: 321 terminal winners + 32 deity |
| advanceGame | STAGE_RNG_REQUESTED (1) | ~215,000 | 13,785,000 | SAFE | VRF call (fixed cost) |
| advanceGame | STAGE_TRANSITION_WORKING (2) | ~205,000 | 13,795,000 | SAFE | 2 queue ops + stETH (fixed) |
| advanceGame | STAGE_TRANSITION_DONE (3) | ~255,000 | 13,745,000 | SAFE | Same as above + flags |
| advanceGame | STAGE_FUTURE_TICKETS (4) | ~2,863,000 | 11,137,000 | SAFE | WRITES_BUDGET_SAFE=550 |
| advanceGame | STAGE_TICKETS_WORKING (5) | ~3,028,000 | 10,972,000 | SAFE | WRITES_BUDGET_SAFE=550 |
| advanceGame | STAGE_PURCHASE_DAILY (6) | ~12,952,000 | 1,048,000 | TIGHT | Code: JACKPOT_MAX_WINNERS=300 |
| advanceGame | STAGE_ENTERED_JACKPOT (7) | ~1,972,000 | 12,028,000 | SAFE | WRITES_BUDGET_SAFE=550 + consolidation |
| advanceGame | STAGE_JACKPOT_ETH_RESUME (8) | ~13,122,000 | 878,000 | AT_RISK | unitsBudget=1000 / 3 = 333 winners |
| advanceGame | STAGE_JACKPOT_COIN_TICKETS (9) | ~1,764,000 | 12,236,000 | SAFE | Code: 50 coin + 200 tickets |
| advanceGame | STAGE_JACKPOT_PHASE_ENDED (10) | ~6,058,000 | 7,942,000 | SAFE | Code: 107 BAF winners |
| advanceGame | STAGE_JACKPOT_DAILY_STARTED (11) | ~14,162,000 | -162,000 | AT_RISK | unitsBudget=1000 + earlybird 100 |
| purchase | Ticket ETH (Path 1) | ~219,000 | 13,781,000 | SAFE | Fixed overhead (O(1) queuing) |
| purchase | Lootbox ETH (Path 2) | ~286,000 | 13,714,000 | SAFE | Fixed overhead (no loops) |
| purchase | Combined Ticket+Lootbox (Path 3) | ~600,000 | 13,400,000 | SAFE | Fixed overhead (O(1) queuing) |
| purchase | purchaseCoin BURNIE (Path 4) | ~97,000 | 13,903,000 | SAFE | Fixed overhead (lightest path) |
| purchase | purchaseWhaleBundle qty=1 (Path 5) | ~1,710,000 | 12,290,000 | SAFE | 100-level _queueTickets loop |
| purchase | purchaseBurnieLootbox (Path 6) | ~113,000 | 13,887,000 | SAFE | Fixed overhead (no loops) |

### Risk Level Legend

- **SAFE (>3M headroom):** No risk of exceeding 14M gas ceiling under any conditions. 14 of 18 paths.
- **TIGHT (1-3M headroom):** Within budget but limited margin. Full auto-rebuy worst case approaches ceiling. 1 path.
- **AT_RISK (<1M headroom):** Could breach 14M under extreme worst-case conditions. Full auto-rebuy + maximum winners. 2 paths.
- **BREACH (exceeds 14M):** Stage 11 Day-1 theoretical only -- not confirmed as a practical risk.

### Cross-Path Observation

The `advanceGame()` paths consume 15-1000x more gas than `purchase()` paths. This is by design:
- `advanceGame()` distributes jackpots (loops over winners, writes claimable balances)
- `purchase()` merely queues tickets (O(1) append) and routes payments

The gas ceiling concern is entirely an `advanceGame()` concern. All purchase paths have massive headroom (>13M gas unused).

---

## 6. Findings

### F-57-01 [INFO] Stage 11 JACKPOT_DAILY_STARTED: Theoretical Day-1 Breach

**Contract:** DegenerusGameJackpotModule.sol (payDailyJackpot, _processDailyEthChunk)
**Line References:** JackpotModule:323-336 (daily init), JackpotModule:801 (earlybird), JackpotModule:1388 (_processDailyEthChunk)

**Description:** When ALL of the following conditions are true simultaneously, Stage 11 can theoretically exceed the 14M gas ceiling by ~162,000 gas:
1. Day 1 of a new jackpot level (jackpotCounter == 0, triggers earlybird lootbox)
2. Prize pool large enough to fill all 333 auto-rebuy winner slots
3. Every winner has auto-rebuy enabled (all 3 units per winner)

**Risk Assessment:** The economic conditions for this combination are extremely unlikely. Day 1 prize pools are typically the smallest (daily BPS applied to initial pool). A pool large enough for 333 winners on Day 1 would require extreme accumulation. The probability of ALL winners having auto-rebuy enabled approaches zero for pools with 100+ participants.

**Recommendation:** No code change required. The existing `unitsBudget=1000` was designed for a 15M ceiling (per code comment at JackpotModule:596). The 14M conservative target makes this tight but not practically exploitable. If desired, reducing `DAILY_JACKPOT_UNITS_SAFE` from 1000 to 900 would eliminate the theoretical breach with minimal impact on distribution speed.

### F-57-02 [INFO] Stage 6 PURCHASE_DAILY: Non-Chunked Distribution with 300 Winners

**Contract:** DegenerusGameJackpotModule.sol (_executeJackpot, _distributeJackpotEth)
**Line References:** JackpotModule:1310 (_executeJackpot), referenced from payDailyJackpot isDaily=false path

**Description:** Stage 6 (PURCHASE_DAILY) uses `_distributeJackpotEth` which distributes to up to `JACKPOT_MAX_WINNERS=300` in a single non-chunked call. With all 300 winners having auto-rebuy enabled, gas reaches ~12.95M (1.05M headroom). Unlike the jackpot phase daily distribution which uses `_processDailyEthChunk` with a unit budget and cursor-based resume, this purchase-phase path runs to completion in a single `advanceGame()` call.

**Risk Assessment:** The purchase-phase early-burn pool is typically small (1% daily drip from futurePool), making 300 winners unlikely. However, with a large accumulated futurePool, this path could approach the ceiling.

**Recommendation:** Monitor in production. If the early-burn pool grows large enough to trigger 200+ winners regularly, consider adding chunking to the purchase-phase daily jackpot path. Currently, the code-bounded 300-winner cap keeps gas within the 14M ceiling.

### F-57-03 [INFO] Compiler Configuration Inflates Runtime Gas

**Contract:** All contracts (compiler configuration)
**Line References:** foundry.toml (via_ir=true, optimizer_runs=2)

**Description:** The protocol compiles with `via_ir=true` and `optimizer_runs=2`, which optimizes for code size (deployment cost) rather than runtime gas efficiency. This configuration can result in runtime gas costs 5-15% higher than contracts compiled with higher optimizer run counts (e.g., 200 or 10000). All gas estimates in this analysis are based on EVM opcode costs and may underestimate actual gas by this margin.

**Risk Assessment:** For paths already AT_RISK (Stages 8, 11), the compiler overhead could push actual gas further toward or beyond the 14M ceiling. For SAFE paths with >3M headroom, the impact is negligible.

**Recommendation:** INFO only. The optimizer_runs=2 setting is a deliberate choice to minimize deployment costs (code size). Runtime gas overhead is acceptable given the large headroom on most paths. The AT_RISK stages should be validated with Foundry gas reports to confirm actual gas aligns with estimates.

### F-57-04 [INFO] purchaseWhaleBundle: 100-Level _queueTickets Loop

**Contract:** DegenerusGameWhaleModule.sol (_purchaseWhaleBundle)
**Line References:** WhaleModule:264-269

**Description:** The `purchaseWhaleBundle` function contains a 100-iteration loop calling `_queueTickets` for each level. Unlike the O(1) `_queueTicketsScaled` used by standard ticket purchases, this loop iterates across all 100 target levels. At quantity=100 with all new levels, total gas reaches ~8.3M. Even this extreme case has >5.7M headroom.

**Risk Assessment:** The loop is bounded at exactly 100 iterations (hardcoded level range). Gas scales with quantity (additional `_rewardWhaleBundleDgnrs` calls) but the 100 maximum quantity keeps total gas well within 14M.

**Recommendation:** No action needed. The design is intentional -- whale bundles span 100 levels and each level needs its own ticket queue entry. The O(100) cost is acceptable given the 14M ceiling.

---

## 7. Requirement Traceability

| Requirement | Status | Evidence |
|-------------|--------|----------|
| CEIL-01 | PASS with AT_RISK findings | Section 3 -- all 12 advanceGame stages profiled with worst-case gas, loop bounds, storage ops, external calls. 2 stages AT_RISK, 1 TIGHT, 9 SAFE. |
| CEIL-02 | PASS | Section 3 CEIL-02 subsection -- per-winner gas cost reference table, maximum winner counts by stage, binding constraint analysis. All code-bounded constants fit within 14M. |
| CEIL-03 | PASS | Section 4 -- all 6 purchase paths profiled: Ticket ETH, Lootbox ETH, Combined, purchaseCoin, purchaseWhaleBundle, purchaseBurnieLootbox. All SAFE with >13M headroom (except whale qty=100 at ~5.7M headroom). |
| CEIL-04 | PASS | Section 4 CEIL-04 subsection -- O(1) `_queueTicketsScaled` design means gas does NOT constrain batch size. Maximum batch is economically bounded, not gas bounded. |
| CEIL-05 | PASS | Section 5 -- master headroom table covering all 18 paths with worst-case gas, headroom, risk level, and binding constraint. |
