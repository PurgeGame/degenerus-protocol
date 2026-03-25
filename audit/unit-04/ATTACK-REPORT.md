# Unit 4: Endgame + Game Over -- Attack Report

**Agent:** Mad Genius (Attacker)
**Contracts:** DegenerusGameEndgameModule.sol (565 lines), DegenerusGameGameOverModule.sol (235 lines), DegenerusGamePayoutUtils.sol (92 lines)
**Date:** 2026-03-25

---

## Findings Summary

| ID | Function | Verdict | Severity | Title |
|----|----------|---------|----------|-------|
| F-01 | runRewardJackpots | INVESTIGATE | INFO | rebuyDelta reconciliation skipped when futurePoolLocal == baseFuturePool but auto-rebuy writes occurred during Decimator-only paths |
| F-02 | handleGameOverDrain | INVESTIGATE | INFO | gameOverTime re-stamped on retry when rngWord becomes available after initial call |
| F-03 | handleGameOverDrain | INVESTIGATE | LOW | Deity pass refund loop uses unchecked arithmetic on claimableWinnings -- safe due to ETH supply bounds but undocumented |
| F-04 | claimWhalePass | INVESTIGATE | INFO | startLevel hardcoded to level + 1 regardless of jackpotPhaseFlag state |
| F-05 | _runBafJackpot | INVESTIGATE | INFO | Event RewardJackpotsSettled emits futurePoolLocal (pre-rebuyDelta) not final storage value |

**5 Category B functions and 7 Category C helpers analyzed. 3 MULTI-PARENT functions received cross-parent scrutiny. No VULNERABLE findings. 5 INVESTIGATE findings (1 LOW, 4 INFO). BAF rebuyDelta reconciliation: PROVEN CORRECT.**

---

## Part 1: Category B Functions -- Full Attack Analysis

---

## EndgameModule::runRewardJackpots(uint24 lvl, uint256 rngWord) (lines 172-254) [B1] [BAF-CRITICAL]

### Call Tree
```
runRewardJackpots(lvl, rngWord) [line 172] -- external
  +-- _getFuturePrizePool() [line 173] -- reads prizePoolsPacked (Storage L746-749)
  +-- futurePoolLocal = result [line 173] -- LOCAL CACHE
  +-- baseFuturePool = futurePoolLocal [line 176] -- LOCAL SNAPSHOT
  +-- if (prevMod10 == 0): BAF path [line 185]
  |    +-- bafPct calculation [line 186]
  |    +-- bafPoolWei = (baseFuturePool * bafPct) / 100 [line 187]
  |    +-- futurePoolLocal -= bafPoolWei [line 190] -- LOCAL DEDUCTION
  |    +-- _runBafJackpot(bafPoolWei, lvl, rngWord) [line 195] -- C2
  |    |    +-- jackpots.runBafJackpot(poolWei, lvl, rngWord) [line 373] -- external call
  |    |    +-- winner loop [line 386-426]:
  |    |    |    +-- large winners (amount >= largeWinnerThreshold) [line 391]:
  |    |    |    |    +-- _addClaimableEth(winner, ethPortion, rngWord) [line 396] -- C1 [BAF-CRITICAL]
  |    |    |    |    |    +-- if autoRebuy: _setFuturePrizePool(_getFuturePrizePool() + calc.ethSpent) [line 292]
  |    |    |    |    |    |    ^^^ WRITES DIRECTLY TO futurePrizePool STORAGE
  |    |    |    |    |    +-- or _setNextPrizePool(_getNextPrizePool() + calc.ethSpent) [line 294]
  |    |    |    |    |    +-- _queueTickets(beneficiary, calc.targetLevel, calc.ticketCount) [line 297]
  |    |    |    |    |    +-- _creditClaimable(beneficiary, calc.reserved) [line 300] -- if take-profit
  |    |    |    |    |    +-- or _creditClaimable(beneficiary, weiAmount) [line 287/314] -- no-rebuy path
  |    |    |    |    +-- _awardJackpotTickets(winner, lootboxPortion, lvl, rngWord) [line 401] -- C3
  |    |    |    |    |    +-- _queueWhalePassClaimCore(winner, amount) [line 456] -- large
  |    |    |    |    |    +-- _jackpotTicketRoll(...) [line 462/469/478] -- C4
  |    |    |    |    |         +-- EntropyLib.entropyStep(entropy) [line 504]
  |    |    |    |    |         +-- _queueLootboxTickets(winner, targetLevel, quantityScaled) [line 528]
  |    |    |    |    +-- or _queueWhalePassClaimCore(winner, lootboxPortion) [line 409] -- large lootbox
  |    |    |    +-- small even winners [line 414]:
  |    |    |    |    +-- _addClaimableEth(winner, amount, rngWord) [line 416] -- C1 [BAF-CRITICAL]
  |    |    |    +-- small odd winners [line 417]:
  |    |    |         +-- _awardJackpotTickets(winner, amount, lvl, rngWord) [line 419] -- C3
  |    |    +-- returns (netSpend, claimableDelta, lootboxToFuture)
  |    +-- futurePoolLocal += (bafPoolWei - netSpend) [line 199] -- refund to local
  |    +-- futurePoolLocal += lootboxToFuture [line 203] -- lootbox stays in pool
  +-- if (prevMod100 == 0): Decimator level-100 path [line 211]
  |    +-- decPoolWei = (baseFuturePool * 30) / 100 [line 212]
  |    +-- IDegenerusGame(address(this)).runDecimatorJackpot(decPoolWei, lvl, rngWord) [line 214-215]
  |    |    -- routes through Game router -> delegatecall DecimatorModule
  |    |    -- may trigger auto-rebuy -> writes futurePrizePool storage
  |    +-- futurePoolLocal -= spend [line 217]
  +-- if (prevMod10 == 5 && prevMod100 != 95): Decimator mid-decile path [line 226]
  |    +-- decPoolWei = (futurePoolLocal * 10) / 100 [line 228] -- NOTE: uses futurePoolLocal not baseFuturePool
  |    +-- IDegenerusGame(address(this)).runDecimatorJackpot(decPoolWei, lvl, rngWord) [line 230-231]
  |    +-- futurePoolLocal -= spend [line 233]
  +-- RECONCILIATION [line 244-246]:
  |    +-- if (futurePoolLocal != baseFuturePool):
  |    |    +-- rebuyDelta = _getFuturePrizePool() - baseFuturePool [line 245]
  |    |    +-- _setFuturePrizePool(futurePoolLocal + rebuyDelta) [line 246]
  +-- if (claimableDelta != 0): claimablePool += claimableDelta [line 249]
  +-- emit RewardJackpotsSettled(lvl, futurePoolLocal, claimableDelta) [line 252]
```

### Storage Writes (Full Tree)

| Variable | Written By | Line | Context |
|----------|-----------|------|---------|
| `prizePoolsPacked` (futurePrizePool) | C1 `_addClaimableEth` via `_setFuturePrizePool` | 292 | Auto-rebuy to-future path |
| `prizePoolsPacked` (nextPrizePool) | C1 `_addClaimableEth` via `_setNextPrizePool` | 294 | Auto-rebuy to-next path |
| `prizePoolsPacked` (futurePrizePool) | B1 reconciliation via `_setFuturePrizePool` | 246 | Final write-back |
| `claimableWinnings[winner]` | C5 `_creditClaimable` | PayoutUtils L33 | Via C1 (no-rebuy/take-profit) |
| `claimablePool` | C1 `_addClaimableEth` | 301 | Take-profit reserved portion |
| `claimablePool` | B1 | 249 | Aggregate claimableDelta |
| `whalePassClaims[winner]` | C6 `_queueWhalePassClaimCore` | PayoutUtils L82 | Large lootbox |
| `claimableWinnings[winner]` | C6 `_queueWhalePassClaimCore` | PayoutUtils L86 | Whale pass remainder |
| `claimablePool` | C6 `_queueWhalePassClaimCore` | PayoutUtils L88 | Whale pass remainder |
| `ticketsOwedPacked[key][addr]` | `_queueTickets` | Storage L547 | Auto-rebuy tickets |
| `ticketQueue[key]` | `_queueTickets` | Storage L542 | Auto-rebuy tickets (push) |
| `ticketsOwedPacked[key][addr]` | `_queueLootboxTickets` via `_queueTicketsScaled` | Storage L591 | Lootbox tickets |
| `ticketQueue[key]` | `_queueLootboxTickets` via `_queueTicketsScaled` | Storage L570 | Lootbox tickets (push) |

### Cached-Local-vs-Storage Check

**THE BAF PATTERN CHECK -- #1 PRIORITY**

| Ancestor Local | Storage Variable | Descendant Writer | Verdict |
|---------------|-----------------|-------------------|---------|
| `futurePoolLocal` (L173) | `prizePoolsPacked` (futurePrizePool) | C1 `_addClaimableEth` at L292 (`_setFuturePrizePool`) | **SAFE** -- reconciled via rebuyDelta at L245-246 |
| `baseFuturePool` (L176) | `prizePoolsPacked` (futurePrizePool) | C1 `_addClaimableEth` at L292 | **SAFE** -- baseFuturePool is read-only snapshot, never written back |
| `claimableDelta` (L179) | `claimablePool` (slot 10) | C1 `_addClaimableEth` at L301 (take-profit), C6 at PayoutUtils L88 | **SAFE** -- `claimableDelta` tracks RETURN VALUES from C2/C1, not raw claimablePool. The take-profit writes to claimablePool are NOT double-counted because `_addClaimableEth` returns 0 on auto-rebuy path (L310), and the take-profit portion goes directly to claimablePool at L301 without being included in claimableDelta. The B1-level `claimablePool += claimableDelta` at L249 only adds the non-rebuy ETH credits. |

**rebuyDelta Proof of Correctness:**

1. At entry (L173): `futurePoolLocal = _getFuturePrizePool()` = storage value S0
2. `baseFuturePool = S0` (L176)
3. During execution, auto-rebuy writes to storage: S0 -> S0 + R (where R = total rebuy ETH to future)
4. `futurePoolLocal` is modified locally: S0 -> S0 - bafPool + refund + lootbox - decSpend = L (local computation)
5. At reconciliation (L244): `futurePoolLocal (L) != baseFuturePool (S0)` -- condition TRUE (jackpot fired)
6. `rebuyDelta = _getFuturePrizePool() - baseFuturePool = (S0 + R) - S0 = R`
7. `_setFuturePrizePool(futurePoolLocal + rebuyDelta) = L + R` = correct final value

**Edge case analysis:**
- **Only rebuy writes, no jackpot fires:** prevMod10 != 0 and prevMod10 != 5, so no jackpot fires. No calls to `_addClaimableEth`. No storage writes. `futurePoolLocal == baseFuturePool`. Reconciliation skipped. SAFE.
- **Jackpot fires but no auto-rebuy:** `rebuyDelta = _getFuturePrizePool() - baseFuturePool = S0 - S0 = 0`. `_setFuturePrizePool(L + 0) = L`. SAFE.
- **Level 100 special (BAF + Decimator both fire):** Both paths may trigger auto-rebuy. Both contribute to R. `rebuyDelta = R` captures all. SAFE.
- **DecimatorJackpot also triggers auto-rebuy:** The `runDecimatorJackpot` call routes through Game router -> DecimatorModule. DecimatorModule operates in delegatecall context, so its auto-rebuy writes go to the SAME futurePrizePool storage slot. `rebuyDelta` at L245 captures these writes. SAFE.

**F-01 Investigation:** At level 5 (prevMod10 == 5), only the Decimator fires (not BAF). The Decimator calls `runDecimatorJackpot` which MAY trigger auto-rebuy, writing to futurePrizePool storage. But `futurePoolLocal` was decremented by `spend` at L233. If `spend != 0`, then `futurePoolLocal != baseFuturePool`, so reconciliation fires. SAFE. BUT: if `decPoolWei == 0` (futurePoolLocal == 0), then no Decimator fires, `futurePoolLocal == baseFuturePool`, reconciliation skipped. No auto-rebuy possible since no jackpot distributed. SAFE.

### Attack Analysis

**State Coherence:** The BAF reconciliation mechanism is correct. `rebuyDelta` captures exactly the auto-rebuy writes between cache time and write-back time. No stale-cache overwrite is possible. VERDICT: **SAFE**

**Access Control:** External function, called via delegatecall from `_processPhaseTransition` in AdvanceModule. Only reachable during level transition via advanceGame flow. No direct external access possible (delegatecall required). VERDICT: **SAFE**

**RNG Manipulation:** `rngWord` is a VRF word passed from the calling context. The function passes it through to `jackpots.runBafJackpot()` for winner selection and to `_addClaimableEth` for auto-rebuy level offset. The VRF word is committed before any player-controllable state changes. VERDICT: **SAFE**

**Cross-Contract State Desync:** `jackpots.runBafJackpot()` is an external call to DegenerusJackpots. It returns winners/amounts/refund. The DegenerusJackpots contract reads from the Game contract's ticket state (which is frozen during jackpot phase). No state desync risk: ticket state is frozen, and the external call only reads. VERDICT: **SAFE**

**Edge Cases:** Zero futurePool (no BAF/Decimator pool to distribute): bafPoolWei/decPoolWei = 0, loops don't execute, no state changes. Level 0 (prevMod10 = 0, prevMod100 = 0): BAF fires with 20% + Decimator with 30%. Both use `baseFuturePool` for sizing. Combined 50% draw. VERDICT: **SAFE**

**Conditional Paths:** All three conditional blocks (BAF, Decimator-100, Decimator-mid) analyzed above. Level 50 gets 20% BAF (special case at L186). Level 100 gets 20% BAF + 30% Decimator. Levels ending in 5 (except 95) get 10% Decimator from `futurePoolLocal` (post-BAF if applicable). VERDICT: **SAFE**

**Economic/MEV:** The function is called during advanceGame which is permissionless but sequential. An attacker cannot front-run the jackpot itself -- it fires deterministically based on VRF word. VERDICT: **SAFE**

**Griefing:** No griefing vector. Function is deterministic given inputs. VERDICT: **SAFE**

**Ordering/Sequencing:** BAF fires before Decimator. At level 100, BAF uses `baseFuturePool` for 20%, then Decimator uses `baseFuturePool` for 30%. Combined 50% of entry pool. The `futurePoolLocal` tracks remaining correctly. Mid-decile Decimator (L228) uses `futurePoolLocal` (post-BAF), which is correct -- it gets 10% of the reduced pool. VERDICT: **SAFE**

**Silent Failures:** The `if (futurePoolLocal != baseFuturePool)` guard at L244 could silently skip reconciliation if no jackpot fires. But in that case, no auto-rebuy writes occur, so no reconciliation is needed. VERDICT: **SAFE**

**F-05 (INFO):** The `RewardJackpotsSettled` event at L252 emits `futurePoolLocal` (pre-rebuyDelta reconciliation), not the final storage value (`futurePoolLocal + rebuyDelta`). Indexers relying on this event may see a pool value that doesn't match on-chain state when auto-rebuy is active. Impact: cosmetic only (off-chain indexer confusion). Not exploitable.

---

## EndgameModule::rewardTopAffiliate(uint24 lvl) (lines 130-149) [B2]

### Call Tree
```
rewardTopAffiliate(lvl) [line 130] -- external
  +-- affiliate.affiliateTop(lvl) [line 131] -- external call to DegenerusAffiliate
  +-- if (top != address(0)) [line 133]:
  |    +-- dgnrs.poolBalance(Pool.Affiliate) [line 134] -- external view
  |    +-- dgnrsReward = (poolBalance * 100) / 10_000 = 1% [line 135-136]
  |    +-- dgnrs.transferFromPool(Pool.Affiliate, top, dgnrsReward) [line 137-141] -- external write
  |    +-- emit AffiliateDgnrsReward [line 142]
  +-- remainingPool = dgnrs.poolBalance(Pool.Affiliate) [line 147] -- external view (AFTER transfer)
  +-- levelDgnrsAllocation[lvl] = (remainingPool * 500) / 10_000 = 5% [line 148]
```

### Storage Writes (Full Tree)

| Variable | Written By | Line | Context |
|----------|-----------|------|---------|
| `levelDgnrsAllocation[lvl]` | B2 | 148 | 5% of remaining affiliate pool snapshot |

### Cached-Local-vs-Storage Check

No local caching of storage variables. `poolBalance` is read from external contract (dgnrs), not from game storage. `remainingPool` is re-read AFTER the transfer (L147), not cached. SAFE.

### Attack Analysis

**State Coherence:** No cached-local-vs-storage pattern. External reads are fresh. VERDICT: **SAFE**

**Access Control:** External, called via delegatecall from advanceGame during level transition. VERDICT: **SAFE**

**RNG Manipulation:** No RNG involved. VERDICT: **N/A**

**Cross-Contract State Desync:** Two sequential calls to `dgnrs.poolBalance()` (L134 and L147). Between them, `transferFromPool` reduces the pool. L147 correctly reads the POST-transfer balance. VERDICT: **SAFE**

**Edge Cases:** If top == address(0): transfer skipped, but segregation still happens (L147-148). This is correct -- per-affiliate claims still need an allocation even if no top affiliate exists. If poolBalance == 0: dgnrsReward = 0, transferFromPool sends 0 (no-op). levelDgnrsAllocation = 0. VERDICT: **SAFE**

**Conditional Paths:** Only one branch (top != address(0)). Allocation happens unconditionally after the if-block. VERDICT: **SAFE**

**Economic/MEV:** An attacker cannot manipulate affiliateTop results -- they are determined by cumulative affiliate scores frozen at level transition. VERDICT: **SAFE**

**Griefing:** No griefing vector. VERDICT: **SAFE**

**Ordering/Sequencing:** Called once per level transition. Per-level paid flag would guard against double-call, but the function doesn't check one -- it relies on the caller (advanceGame) calling it once. However, `levelDgnrsAllocation[lvl]` is idempotent (overwrites same value if called twice with same `lvl`). The `transferFromPool` would transfer twice, but each transfer is 1% of remaining (decreasing). VERDICT: **SAFE** (caller-guarded)

**Silent Failures:** `transferFromPool` returns `paid` (actual amount transferred). If it returns 0 due to insufficient balance, the event still emits with 0. Not harmful. VERDICT: **SAFE**

---

## EndgameModule::claimWhalePass(address player) (lines 540-559) [B3]

### Call Tree
```
claimWhalePass(player) [line 540] -- external
  +-- if (gameOver) revert E() [line 541] -- terminal state guard
  +-- halfPasses = whalePassClaims[player] [line 542] -- read mapping
  +-- if (halfPasses == 0) return [line 543] -- no-op guard
  +-- whalePassClaims[player] = 0 [line 546] -- CLEAR BEFORE USE (anti-double-claim)
  +-- startLevel = level + 1 [line 554] -- always next level
  +-- _applyWhalePassStats(player, startLevel) [line 556] -- D9, writes mintPacked_
  +-- emit WhalePassClaimed [line 557]
  +-- _queueTicketRange(player, startLevel, 100, uint32(halfPasses)) [line 558] -- D8
       +-- loop 100 times [Storage L611-631]:
            +-- for each level: ticketsOwedPacked[wk][buyer] += ticketsPerLevel
            +-- ticketQueue[wk].push(buyer) if first entry
```

### Storage Writes (Full Tree)

| Variable | Written By | Line | Context |
|----------|-----------|------|---------|
| `whalePassClaims[player]` | B3 | 546 | Cleared to 0 |
| `mintPacked_[player]` | `_applyWhalePassStats` | Storage ~1067-1100 | Whale pass stats update |
| `ticketsOwedPacked[key][player]` | `_queueTicketRange` | Storage L624 | Per-level ticket increment (100 levels) |
| `ticketQueue[key]` | `_queueTicketRange` | Storage L619 | Push buyer to queue (100 levels) |

### Cached-Local-vs-Storage Check

| Ancestor Local | Storage Variable | Descendant Writer | Verdict |
|---------------|-----------------|-------------------|---------|
| `halfPasses` (L542) | `whalePassClaims[player]` | B3 at L546 (clear) | **SAFE** -- halfPasses read once, clear happens immediately, no stale reuse |
| `startLevel` (L554) | `level` | none | **SAFE** -- level not modified by any descendant in this call |

### Attack Analysis

**State Coherence:** No BAF pattern. Clear-before-use on whalePassClaims prevents double-claim. VERDICT: **SAFE**

**Access Control:** External, called via delegatecall from DegenerusGame (L1707 in Game). The `player` parameter is the claim target. The Game contract's `claimWhalePass` wrapper (L1703-1714) allows anyone to claim FOR any player (permissionless). This is by design -- tickets only benefit the player. VERDICT: **SAFE**

**RNG Manipulation:** No RNG involved. Ticket distribution is deterministic. VERDICT: **N/A**

**Edge Cases:** halfPasses = 0: early return (L543). gameOver: revert (L541). uint32 truncation (L558): halfPasses is uint256 but cast to uint32. ETH supply bounds prevent overflow (see research). VERDICT: **SAFE**

**F-04 (INFO):** `startLevel = level + 1` is hardcoded regardless of whether we're in jackpot phase or purchase phase. The comment at L549-551 mentions both cases but the code always uses `level + 1`. During purchase phase, the current level's tickets can still be processed, so starting at `level` would give the player one extra level of coverage. However, using `level + 1` is conservative and consistent -- it ensures tickets are always for FUTURE levels. Not a bug, but the comment is slightly misleading about the distinction.

**Conditional Paths:** Only two: gameOver revert and halfPasses == 0 return. Main path is straightforward. VERDICT: **SAFE**

**Griefing:** A griefing vector: anyone can call `claimWhalePass(player)` before the player wants to. This is by design (permissionless claiming helps players who don't actively claim). Tickets start at `level + 1`, so early claiming only affects the start level. Not harmful. VERDICT: **SAFE**

**Silent Failures:** None. VERDICT: **SAFE**

---

## GameOverModule::handleGameOverDrain(uint48 day) (lines 68-163) [B4]

### Call Tree
```
handleGameOverDrain(day) [line 68] -- external
  +-- if (gameOverFinalJackpotPaid) return [line 69] -- already-paid guard
  +-- lvl = level [line 71] -- read storage
  +-- ethBal = address(this).balance [line 73]
  +-- stBal = steth.balanceOf(address(this)) [line 74] -- external view
  +-- totalFunds = ethBal + stBal [line 75]
  +-- if (lvl < 10): deity pass refund path [line 77-106]
  |    +-- refundPerPass = 20 ether [line 78]
  |    +-- ownerCount = deityPassOwners.length [line 79]
  |    +-- budget = totalFunds - claimablePool (or 0) [line 80]
  |    +-- FIFO loop [line 82-102]:
  |    |    +-- owner = deityPassOwners[i] [line 83]
  |    |    +-- purchasedCount = deityPassPurchasedCount[owner] [line 84]
  |    |    +-- refund = min(refundPerPass * purchasedCount, budget) [line 86-89]
  |    |    +-- claimableWinnings[owner] += refund [line 92] -- UNCHECKED
  |    |    +-- totalRefunded += refund [line 93] -- UNCHECKED
  |    |    +-- budget -= refund [line 94] -- UNCHECKED
  |    +-- claimablePool += totalRefunded [line 104]
  +-- available = totalFunds - claimablePool (or 0) [line 109]
  +-- gameOver = true [line 111]
  +-- gameOverTime = uint48(block.timestamp) [line 112]
  +-- if (available == 0): zero pools and return [line 114-121]
  |    +-- gameOverFinalJackpotPaid = true [line 115]
  |    +-- _setNextPrizePool(0), _setFuturePrizePool(0), currentPrizePool = 0, yieldAccumulator = 0
  +-- rngWord = rngWordByDay[day] [line 124]
  +-- if (rngWord == 0) return [line 125] -- RNG not ready, allow retry
  +-- gameOverFinalJackpotPaid = true [line 127]
  +-- _setNextPrizePool(0), _setFuturePrizePool(0), currentPrizePool = 0, yieldAccumulator = 0 [line 128-131]
  +-- remaining = available [line 134]
  +-- 10% Terminal Decimator [line 137-146]:
  |    +-- decPool = remaining / 10 [line 137]
  |    +-- IDegenerusGame(address(this)).runTerminalDecimatorJackpot(decPool, lvl, rngWord) [line 139]
  |    +-- claimablePool += decSpend [line 142]
  |    +-- remaining -= decPool + decRefund [line 144-145]
  +-- Terminal Jackpot [line 150-158]:
  |    +-- IDegenerusGame(address(this)).runTerminalJackpot(remaining, lvl+1, rngWord) [line 151-152]
  |    +-- remaining -= termPaid [line 154]
  |    +-- if (remaining != 0): _sendToVault(remaining, stBal) [line 157] -- C7
  +-- dgnrs.burnRemainingPools() [line 162] -- external call
```

### Storage Writes (Full Tree)

| Variable | Written By | Line | Context |
|----------|-----------|------|---------|
| `claimableWinnings[owner]` | B4 deity refund loop | 92 | Unchecked increment |
| `claimablePool` | B4 deity refund | 104 | Aggregate deity refund |
| `gameOver` | B4 | 111 | Terminal state flag |
| `gameOverTime` | B4 | 112 | Timestamp |
| `gameOverFinalJackpotPaid` | B4 | 115 or 127 | Payout guard |
| `prizePoolsPacked` (next, future) | B4 via _setNextPrizePool/_setFuturePrizePool | 116-117 or 128-129 | Zeroed |
| `currentPrizePool` | B4 | 118 or 130 | Zeroed |
| `yieldAccumulator` | B4 | 119 or 131 | Zeroed |
| `claimablePool` | B4 | 142 | Terminal decimator spend |
| (cross-module writes by runTerminalDecimatorJackpot) | DecimatorModule | L139 | claimableWinnings, claimablePool |
| (cross-module writes by runTerminalJackpot) | JackpotModule | L151 | claimableWinnings, claimablePool |

### Cached-Local-vs-Storage Check

| Ancestor Local | Storage Variable | Descendant Writer | Verdict |
|---------------|-----------------|-------------------|---------|
| `lvl` (L71) | `level` | none | **SAFE** -- level not modified |
| `ethBal` (L73) | `address(this).balance` | `_sendToVault` at L157 (ETH transfer) | **SAFE** -- ethBal used only for totalFunds calculation; actual transfers use `remaining` and `stBal` parameters |
| `stBal` (L74) | stETH balance | `_sendToVault` at L157 | **INVESTIGATE** -- stBal is computed at L74, but by the time _sendToVault is called at L157, stETH balance may have changed due to rebasing. However, _sendToVault receives `stBal` as parameter and handles the case where stethBal < requested amount by falling back to ETH. SAFE. |
| `totalFunds` (L75) | address(this).balance + stETH | runTerminalDecimatorJackpot, runTerminalJackpot | **SAFE** -- totalFunds is used only for budget/available calculation. The actual distribution uses `remaining` which is decremented as funds are allocated. No write-back. |
| `available` (L109) | derived from totalFunds - claimablePool | deity refund loop writes claimablePool at L104 | **SAFE** -- `available` is computed AFTER the deity refund loop, so it correctly reflects the post-refund claimablePool. |
| `remaining` (L134) | none (local tracking) | none | **SAFE** -- purely local accounting variable |

**CRITICAL NOTE:** The pool zeroing at L128-131 happens BEFORE runTerminalDecimatorJackpot and runTerminalJackpot. These subordinate calls operate in delegatecall context and see zeroed pools. However, they receive their ETH budgets as function parameters (`decPool`, `remaining`), not from storage pools. The zeroing prevents double-distribution if the function somehow re-enters (it can't, but defense in depth). SAFE.

### Attack Analysis

**State Coherence:** No BAF-class stale-cache pattern. `available` is computed after deity refunds. Pool zeroing before distribution is safe because budgets are passed as parameters. VERDICT: **SAFE**

**Access Control:** External, called via delegatecall from advanceGame. The `day` parameter controls which RNG word is used. An attacker could pass different `day` values to influence the RNG word used, but `rngWordByDay` is populated by VRF fulfillment -- the attacker cannot choose which word to use, only which day index to look up. VERDICT: **SAFE**

**RNG Manipulation:** `rngWord = rngWordByDay[day]` at L124. The `day` parameter is passed by the caller (advanceGame), which passes the correct `dailyIdx`. If an attacker called with a different `day`, the VRF word would be the word for that day (or 0 if none). The gameover path in advanceGame calculates the correct `day`. VERDICT: **SAFE**

**Cross-Contract State Desync:** `steth.balanceOf(address(this))` at L74 could differ from actual balance at transfer time due to stETH rebasing. However, `_sendToVault` handles this by using the `stBal` parameter and falling back to ETH for any shortfall. VERDICT: **SAFE**

**Edge Cases:**
- `gameOverFinalJackpotPaid = true`: early return at L69. SAFE.
- `available == 0`: pools zeroed, no jackpots. SAFE.
- `rngWord == 0`: early return WITHOUT latching gameOverFinalJackpotPaid. Allows retry. See F-02.
- `lvl < 10` + no deity pass owners: loop doesn't execute, totalRefunded = 0. SAFE.
- `decPool = 0` (remaining == 0 or very small): Decimator skipped. SAFE.

**F-02 (INFO):** When `rngWord == 0` at L125, the function returns early. But `gameOver` was set to `true` at L111 and `gameOverTime` was set at L112. On retry (when rngWord becomes available), L111 re-writes `gameOver = true` (idempotent) but L112 re-writes `gameOverTime = uint48(block.timestamp)` with a NEW timestamp. This means the 30-day waiting period for `handleFinalSweep` is measured from the RETRY timestamp, not the original game-over timestamp. Impact: the 30-day window is slightly extended, which is conservative (gives players more time to claim). Not exploitable for fund extraction.

**F-03 (LOW):** The deity pass refund loop uses `unchecked` arithmetic at L91-95. `claimableWinnings[owner] += refund` and `totalRefunded += refund` are unchecked. While ETH supply bounds make overflow impossible in practice (~120M ETH / 20 ETH per pass = 6M passes max, well within uint256), the use of unchecked on user-facing accounting without an explicit comment about overflow safety is worth noting. Not a vulnerability due to ETH supply constraints.

**Conditional Paths:** Two major paths: lvl < 10 (deity refund + jackpot) and lvl >= 10 (jackpot only). available == 0 path (L114-121). rngWord == 0 retry path (L125). All analyzed. VERDICT: **SAFE**

**Economic/MEV:** The game-over trigger comes from liveness guards (120-day inactivity or 365-day deploy timeout). An attacker cannot trigger game-over on demand. The jackpot distribution is deterministic given the VRF word. VERDICT: **SAFE**

**Griefing:** Pool zeroing before jackpot distribution could strand funds if `runTerminalJackpot` reverts. However, pools are zeroed AFTER `gameOverFinalJackpotPaid = true` (L127), so retry is not possible. If `runTerminalJackpot` reverts, the entire transaction reverts, including the pool zeroing. Solidity atomicity prevents fund stranding. VERDICT: **SAFE**

**Silent Failures:** `if (gameOverFinalJackpotPaid) return` at L69 silently succeeds. This is intentional (idempotent). `if (rngWord == 0) return` at L125 silently succeeds, but this sets gameOver=true without distributing funds -- intentional retry pattern. VERDICT: **SAFE**

---

## GameOverModule::handleFinalSweep() (lines 170-188) [B5]

### Call Tree
```
handleFinalSweep() [line 170] -- external
  +-- if (gameOverTime == 0) return [line 171] -- game not over
  +-- if (block.timestamp < gameOverTime + 30 days) return [line 172] -- too early
  +-- if (finalSwept) return [line 173] -- already swept
  +-- finalSwept = true [line 175]
  +-- claimablePool = 0 [line 176] -- forfeits all unclaimed winnings
  +-- try admin.shutdownVrf() {} catch {} [line 179] -- fire-and-forget
  +-- ethBal = address(this).balance [line 181]
  +-- stBal = steth.balanceOf(address(this)) [line 182]
  +-- totalFunds = ethBal + stBal [line 183]
  +-- if (totalFunds == 0) return [line 185]
  +-- _sendToVault(totalFunds, stBal) [line 187] -- C7
```

### Storage Writes (Full Tree)

| Variable | Written By | Line | Context |
|----------|-----------|------|---------|
| `finalSwept` | B5 | 175 | One-time latch |
| `claimablePool` | B5 | 176 | Zeroed (forfeit unclaimed) |

### Cached-Local-vs-Storage Check

No storage values cached locally before descendant calls. `totalFunds` and `stBal` are derived from external reads (`address(this).balance`, `steth.balanceOf`), not game storage. SAFE.

### Attack Analysis

**State Coherence:** No cached-local-vs-storage pattern. VERDICT: **SAFE**

**Access Control:** External, called via delegatecall. Three guards: gameOverTime != 0, 30-day delay, !finalSwept. VERDICT: **SAFE**

**Edge Cases:** `totalFunds == 0`: early return. `gameOverTime == 0`: early return. Too early: early return. All safe. VERDICT: **SAFE**

**Conditional Paths:** Main path is linear after three guards. VERDICT: **SAFE**

**Economic/MEV:** Front-running risk: an attacker could front-run the sweep to claim their winnings before claimablePool is zeroed. This is the INTENDED behavior -- the 30-day window exists to allow claims. After 30 days, unclaimed funds are forfeited. VERDICT: **SAFE (by design)**

**Griefing:** VRF shutdown failure caught by try/catch -- doesn't block sweep. stETH/ETH transfer failure reverts the entire transaction, but finalSwept is set BEFORE the transfer (L175). Wait -- if _sendToVault reverts, the entire transaction reverts including finalSwept = true. So a permanently failing stETH transfer could block the sweep. However, stETH is a standard ERC20 and VAULT/SDGNRS are protocol contracts that accept transfers. VERDICT: **SAFE** (standard trust assumptions)

**Silent Failures:** Three early-return guards at top. All intentional. VERDICT: **SAFE**

---

## Part 2: Category C Helpers -- Analysis Through Parent Call Trees

### C1: _addClaimableEth (EndgameModule L267-316) [BAF-CRITICAL]

Analyzed in detail under B1 call tree. The auto-rebuy path at L291-295 writes to futurePrizePool or nextPrizePool storage, which is the BAF-critical write. The return value convention is critical:
- Auto-rebuy with tickets: returns 0 (L310) -- ETH went to pool, not claimable
- Auto-rebuy no tickets (too small): returns weiAmount (L288) -- full amount claimable
- No auto-rebuy: returns weiAmount (L315) -- full amount claimable

The return value is accumulated into `claimableDelta` by B1, which is then added to `claimablePool` at B1 L249. The take-profit portion (calc.reserved) goes directly to claimablePool at L301 and is NOT included in the return value. This dual accounting (return value for B1-level aggregation + direct write for take-profit) is correct because the B1-level `claimablePool +=` and the C1-level `claimablePool +=` target the same storage variable and both are additive.

### C2: _runBafJackpot (EndgameModule L356-433) [BAF-PATH]

Analyzed in detail under B1 call tree. Key accounting: `lootboxToFuture` tracks ETH that stays in the future pool (for lootbox tickets that represent "notional" ETH). `netSpend = poolWei - refund` is the total consumed from future pool. `claimableDelta` is the ETH credited to claimable balances (non-rebuy portions only).

### C3: _awardJackpotTickets (EndgameModule L448-486)

Three-tier dispatch: large (> 5 ETH) -> whale pass claim. Medium (0.5-5 ETH) -> split in half, two rolls. Small (<= 0.5 ETH) -> single roll. Correctly handles odd amounts (L477: secondAmount = amount - halfAmount).

### C4: _jackpotTicketRoll (EndgameModule L498-531)

Entropy stepping at L504. Roll distribution: 30% min level, 65% +1 to +4, 5% +5 to +50. Level pricing from PriceLookupLib. Scaled ticket calculation at L527. No storage cached locally.

---

## Part 3: Multi-Parent Standalone Analysis

### C5: _creditClaimable (PayoutUtils L30-36) [MULTI-PARENT]

**Parents:**
1. C1 `_addClaimableEth` at L287 (auto-rebuy no tickets) and L314 (no auto-rebuy) -- full weiAmount
2. C1 `_addClaimableEth` at L300 (take-profit reserved portion) -- calc.reserved
3. C6 `_queueWhalePassClaimCore` at L86 (whale pass remainder) -- remainder

**Analysis per parent:**
- **C1 at L287/L314:** Parent has no cached claimableWinnings or claimablePool. The _creditClaimable write to claimableWinnings[beneficiary] does not conflict with any parent cache. SAFE.
- **C1 at L300:** Same analysis. The claimablePool += calc.reserved at L301 is a SEPARATE write in C1, not in _creditClaimable. No conflict. SAFE.
- **C6 at L86:** Parent C6 has no cached values. The claimablePool += remainder at C6 L88 is a separate write. SAFE.

**Verdict: SAFE for all parents.** _creditClaimable is a simple leaf function that only writes `claimableWinnings[beneficiary]` and emits an event. No upstream cache conflict possible.

### C6: _queueWhalePassClaimCore (PayoutUtils L75-91) [MULTI-PARENT]

**Parents:**
1. C2 `_runBafJackpot` at L409 (large winner lootbox half, lootboxPortion > LOOTBOX_CLAIM_THRESHOLD)
2. C3 `_awardJackpotTickets` at L456 (large amount > LOOTBOX_CLAIM_THRESHOLD)

**Analysis per parent:**
- **C2 at L409:** C2 tracks `lootboxTotal` locally. C6 writes to `whalePassClaims[winner]` and potentially `claimableWinnings[winner]` + `claimablePool` for the remainder. C2's `lootboxTotal` is not a storage variable -- it's a local counter. No cache conflict. SAFE.
- **C3 at L456:** C3 has no cached storage values. SAFE.

**Critical check:** C6 writes `claimablePool += remainder` at L88. B1 accumulates `claimableDelta` from `_addClaimableEth` returns and adds to `claimablePool` at L249. These are DIFFERENT flows: C6's remainder write goes directly to storage, while B1's `claimableDelta` is tracked locally. Are they double-counted?

No. C6's `claimablePool += remainder` accounts for the whale pass remainder (small amount not divisible into half-passes). B1's `claimableDelta` comes from `_addClaimableEth` returns, which do NOT include whale pass remainder amounts. The whale pass portion is tracked in `lootboxToFuture` (stays in future pool), not in `claimableDelta`. The only overlap would be if `_queueWhalePassClaimCore` was called from a path that also contributes to `claimableDelta`, but the whale pass remainder goes directly to claimablePool via C6, independent of the B1-level aggregation.

**Verdict: SAFE for all parents.**

### C7: _sendToVault (GameOverModule L197-234) [MULTI-PARENT]

**Parents:**
1. B4 `handleGameOverDrain` at L157 (game-over remainder)
2. B5 `handleFinalSweep` at L187 (full final sweep)

**Analysis per parent:**
- **B4 at L157:** Called with `remaining` (unallocated after terminal jackpots) and `stBal` (snapshot from L74). By this point, stETH may have been partially consumed by dgnrs.depositSteth (called by cross-module runTerminalJackpot internals). However, `_sendToVault` handles the case where `stethBal` < requested by falling back to ETH. The `remaining` parameter is the ETH budget, which may be smaller than actual contract balance. SAFE.
- **B5 at L187:** Called with `totalFunds` (full balance) and `stBal` (fresh read at L182). No prior transfers in this call, so stBal is fresh. SAFE.

**Verdict: SAFE for both parents.**

---

## Findings Detail

### F-01: rebuyDelta reconciliation event value mismatch

**Function:** `runRewardJackpots` (B1), line 252
**Verdict:** INVESTIGATE
**Severity:** INFO

The `RewardJackpotsSettled` event emits `futurePoolLocal` as the `futurePool` parameter, but the actual storage value after reconciliation is `futurePoolLocal + rebuyDelta`. When auto-rebuy is active, indexers see a pool value that is `rebuyDelta` less than the actual on-chain value. Impact: cosmetic only. Off-chain indexers may need to account for this. Not exploitable.

### F-02: gameOverTime re-stamped on retry

**Function:** `handleGameOverDrain` (B4), line 112
**Verdict:** INVESTIGATE
**Severity:** INFO

When `rngWord == 0` (L125), the function returns early but has already set `gameOver = true` (L111) and `gameOverTime = uint48(block.timestamp)` (L112). On retry (when rngWord is populated), L112 re-writes `gameOverTime` with the new timestamp. The 30-day waiting period for `handleFinalSweep` (L172) is measured from the RETRY timestamp, not the original game-over timestamp. Impact: extends the claim window, which is conservative. Not exploitable.

### F-03: Unchecked deity pass refund arithmetic

**Function:** `handleGameOverDrain` (B4), lines 91-95
**Verdict:** INVESTIGATE
**Severity:** LOW

The deity pass refund loop uses `unchecked` for `claimableWinnings[owner] += refund`, `totalRefunded += refund`, and `budget -= refund`. While overflow is impossible due to ETH supply bounds (max ~120M ETH, 20 ETH per pass, max ~6M passes = 120M ETH = well within uint256), the use of unchecked on user-facing accounting is a code hygiene concern. The `budget -= refund` is safe because `refund <= budget` is enforced by L87-88.

### F-04: claimWhalePass startLevel always level + 1

**Function:** `claimWhalePass` (B3), line 554
**Verdict:** INVESTIGATE
**Severity:** INFO

`startLevel = level + 1` regardless of game phase. The comment (L549-551) describes different behavior for jackpot vs purchase phase, but the code always uses `level + 1`. This is conservative (ensures tickets are for future levels). Not a vulnerability, but the comment is slightly misleading.

### F-05: Event emits pre-reconciliation pool value

**Function:** `runRewardJackpots` (B1), line 252
**Verdict:** INVESTIGATE
**Severity:** INFO

Duplicate of F-01 from a different angle. The `RewardJackpotsSettled` event's `futurePool` field is `futurePoolLocal` (pre-rebuyDelta), not the final reconciled value. Indexers should read on-chain state for authoritative pool values rather than relying solely on event parameters.
