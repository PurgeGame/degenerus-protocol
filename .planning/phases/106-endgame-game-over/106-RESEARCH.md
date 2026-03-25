# Phase 106: Endgame + Game Over -- Research

**Date:** 2026-03-25
**Contracts:**
- `contracts/modules/DegenerusGameEndgameModule.sol` (565 lines)
- `contracts/modules/DegenerusGameGameOverModule.sol` (235 lines)
- `contracts/modules/DegenerusGamePayoutUtils.sol` (92 lines, inherited by EndgameModule)

---

## 1. Complete Function Inventory

### Category B: External State-Changing Functions

| # | Function | Lines | Contract | Risk Tier | Access | Subsystem |
|---|----------|-------|----------|-----------|--------|-----------|
| B1 | `runRewardJackpots(uint24,uint256)` | 172-254 | EndgameModule | Tier 1 [BAF-CRITICAL] | external (delegatecall from advanceGame) | REWARD-JACKPOT |
| B2 | `rewardTopAffiliate(uint24)` | 130-149 | EndgameModule | Tier 3 | external (delegatecall from advanceGame) | AFFILIATE |
| B3 | `claimWhalePass(address)` | 540-559 | EndgameModule | Tier 2 | external (delegatecall from DegenerusGame) | WHALE-PASS |
| B4 | `handleGameOverDrain(uint48)` | 68-163 | GameOverModule | Tier 1 | external (delegatecall from advanceGame) | GAME-OVER |
| B5 | `handleFinalSweep()` | 170-188 | GameOverModule | Tier 2 | external (delegatecall from advanceGame) | GAME-OVER |

**Total: 5 Category B functions**

### Category C: Internal/Private State-Changing Helpers

| # | Function | Lines | Contract | Called By | Flags | Key Writes |
|---|----------|-------|----------|-----------|-------|------------|
| C1 | `_addClaimableEth(address,uint256,uint256)` | 267-316 | EndgameModule | B1 via C2 | [BAF-CRITICAL] | futurePrizePool, nextPrizePool, claimableWinnings, claimablePool, ticketQueue |
| C2 | `_runBafJackpot(uint256,uint24,uint256)` | 356-433 | EndgameModule | B1 | [BAF-PATH] | via C1, via C5/C6 |
| C3 | `_awardJackpotTickets(address,uint256,uint24,uint256)` | 448-486 | EndgameModule | C2 | | ticketQueue, whalePassClaims, claimableWinnings |
| C4 | `_jackpotTicketRoll(address,uint256,uint24,uint256)` | 498-531 | EndgameModule | C3 | | ticketQueue (via _queueLootboxTickets) |
| C5 | `_creditClaimable(address,uint256)` | 30-36 | PayoutUtils | C1, C6 | [MULTI-PARENT] | claimableWinnings |
| C6 | `_queueWhalePassClaimCore(address,uint256)` | 75-91 | PayoutUtils | C2, C3 | [MULTI-PARENT] | whalePassClaims, claimableWinnings, claimablePool |
| C7 | `_sendToVault(uint256,uint256)` | 197-234 | GameOverModule | B4, B5 | [MULTI-PARENT] | (no storage writes; external ETH/stETH transfers) |

**Total: 7 Category C functions**

### Category D: View/Pure Functions

| # | Function | Lines | Contract | Reads/Computes | Security Note |
|---|----------|-------|----------|---------------|---------------|
| D1 | `_calcAutoRebuy(...)` | 38-72 | PayoutUtils | Pure computation: target level, ticket count, take profit | RNG entropy derivation for level offset (EntropyLib.entropyStep) |
| D2 | `_getFuturePrizePool()` | 746-749 | Storage | Reads prizePoolsPacked high 128 bits | Used for BAF reconciliation |
| D3 | `_setFuturePrizePool(uint256)` | 752-755 | Storage | Writes prizePoolsPacked | Used for BAF reconciliation |
| D4 | `_getNextPrizePool()` | 734-737 | Storage | Reads prizePoolsPacked low 128 bits | Used in auto-rebuy |
| D5 | `_setNextPrizePool(uint256)` | 740-743 | Storage | Writes prizePoolsPacked | Used in auto-rebuy and game-over |
| D6 | `_queueTickets(address,uint24,uint32)` | 528-549 | Storage | Writes ticketsOwedPacked, ticketQueue | RNG-locked guard for far-future |
| D7 | `_queueLootboxTickets(address,uint24,uint256)` | 638-645 | Storage | Delegates to _queueTicketsScaled | Wrapper |
| D8 | `_queueTicketRange(address,uint24,uint24,uint32)` | 602-632 | Storage | Writes ticketsOwedPacked, ticketQueue per level | Used by claimWhalePass |
| D9 | `_applyWhalePassStats(address,uint24)` | 1067-~1100 | Storage | Writes mintPacked_ (packed stats) | Used by claimWhalePass |

**Total: 9 Category D functions (inherited helpers)**

**Grand Total: 5B + 7C + 9D = 21 functions across 3 contracts**

---

## 2. BAF-Critical Path Analysis

### The BAF Bug (Historical Context)
The original BAF cache-overwrite bug: `runRewardJackpots()` cached `futurePrizePool` in a local variable, then called `_runBafJackpot()` which called `_addClaimableEth()` which (on auto-rebuy path) wrote directly to `futurePrizePool` storage. When the parent wrote back the stale local, it overwrote the auto-rebuy contribution.

### The Fix (rebuyDelta Reconciliation)
Located at EndgameModule lines 244-246:
```solidity
uint256 rebuyDelta = _getFuturePrizePool() - baseFuturePool;
_setFuturePrizePool(futurePoolLocal + rebuyDelta);
```

### Critical Questions for Mad Genius
1. **Completeness:** Does `rebuyDelta` capture ALL storage-side writes to futurePrizePool during the function body? Or can other code paths also write?
2. **Underflow:** Can `_getFuturePrizePool()` at L245 be LESS than `baseFuturePool`? (Solidity 0.8 would revert -- is that the correct behavior or a DoS vector?)
3. **Edge case:** If `futurePoolLocal == baseFuturePool` (no local changes), the reconciliation is SKIPPED (L244 guard). But what if only rebuy writes happened? Then `futurePoolLocal == baseFuturePool` is true, so the if-block is skipped, and the auto-rebuy writes remain in storage. This is CORRECT -- the guard condition is safe.
4. **Double-counting:** `lootboxToFuture` (returned by `_runBafJackpot`) represents ETH that stays in future pool. It's added to `futurePoolLocal` at L203. Auto-rebuy writes go to storage directly. These are disjoint: lootbox ETH is tracked locally, auto-rebuy ETH is tracked in storage. No double-count.
5. **Decimator path:** `runDecimatorJackpot()` at L215/L231 is called via `IDegenerusGame(address(this))` which routes through the router's delegatecall dispatch. The decimator module may also trigger auto-rebuy paths. The `rebuyDelta` captures ALL writes between `baseFuturePool` and write-back.

### BAF Call Chains in This Module
```
B1 runRewardJackpots
  +- C2 _runBafJackpot
  |    +- C1 _addClaimableEth [BAF-CRITICAL: writes futurePrizePool via auto-rebuy]
  |    |    +- C5 _creditClaimable (no-rebuy path)
  |    |    +- _setFuturePrizePool (rebuy to-future path)
  |    |    +- _setNextPrizePool (rebuy to-next path)
  |    |    +- _queueTickets (rebuy ticket queue)
  |    |    +- C5 _creditClaimable (take-profit reserved portion)
  |    +- C3 _awardJackpotTickets
  |    |    +- C6 _queueWhalePassClaimCore (large amounts)
  |    |    +- C4 _jackpotTicketRoll (small/medium amounts)
  |    |         +- _queueLootboxTickets -> _queueTicketsScaled
  |    +- C6 _queueWhalePassClaimCore (large lootbox half of large winners)
  +- IDegenerusGame.runDecimatorJackpot (cross-module, may also trigger auto-rebuy)
  +- rebuyDelta reconciliation at L244-246
```

---

## 3. Cross-Module Delegatecall Map

| Caller | Target | Route | Returns | State Impact |
|--------|--------|-------|---------|-------------|
| B1 `runRewardJackpots` | `DecimatorModule.runDecimatorJackpot` | `IDegenerusGame(address(this)).runDecimatorJackpot()` -> DegenerusGame router -> delegatecall | `uint256 returnWei` (unspent) | Writes claimableWinnings, claimablePool; may write futurePrizePool via auto-rebuy |
| B4 `handleGameOverDrain` | `DecimatorModule.runTerminalDecimatorJackpot` | Same routing pattern | `uint256 decRefund` | Writes claimableWinnings, claimablePool |
| B4 `handleGameOverDrain` | `JackpotModule.runTerminalJackpot` | Same routing pattern | `uint256 termPaid` | Writes claimableWinnings, claimablePool |

### External (non-delegatecall) Calls

| Caller | Target | Function | Contract | Read/Write |
|--------|--------|----------|----------|-----------|
| B2 `rewardTopAffiliate` | `affiliate.affiliateTop(lvl)` | DegenerusAffiliate | View (external read) |
| B2 `rewardTopAffiliate` | `dgnrs.poolBalance(Pool.Affiliate)` | StakedDegenerusStonk | View (external read) |
| B2 `rewardTopAffiliate` | `dgnrs.transferFromPool(...)` | StakedDegenerusStonk | Write (external transfer) |
| C2 `_runBafJackpot` | `jackpots.runBafJackpot(...)` | DegenerusJackpots | Write (external; returns winners/amounts/refund) |
| B4 `handleGameOverDrain` | `dgnrs.burnRemainingPools()` | StakedDegenerusStonk | Write (external burn) |
| B5 `handleFinalSweep` | `admin.shutdownVrf()` | DegenerusAdmin | Write (fire-and-forget, try/catch) |
| B5 `handleFinalSweep` | `steth.balanceOf(this)` | Lido stETH | View |
| C7 `_sendToVault` | `steth.transfer(VAULT, ...)` | Lido stETH | Write (external transfer) |
| C7 `_sendToVault` | `steth.approve(SDGNRS, ...)` | Lido stETH | Write (external approval) |
| C7 `_sendToVault` | `dgnrs.depositSteth(...)` | StakedDegenerusStonk | Write (external deposit) |
| C7 `_sendToVault` | `VAULT.call{value: ...}("")` | DegenerusVault | Write (ETH transfer) |
| C7 `_sendToVault` | `SDGNRS.call{value: ...}("")` | StakedDegenerusStonk | Write (ETH transfer) |

---

## 4. Risk Tiers for Category B Functions

### Tier 1 -- CRITICAL (deepest analysis required)

**B1 `runRewardJackpots()`** (EndgameModule, L172-254, 83 lines)
- The BAF fix lives here. Cached `futurePoolLocal` with reconciliation via `rebuyDelta`
- Three conditional jackpot paths (BAF at mod10==0, Decimator at mod100==0, Decimator at mod10==5)
- Cross-module delegatecall to DecimatorModule
- Multiple calls to `_addClaimableEth` via `_runBafJackpot` which trigger auto-rebuy storage writes
- Complex accounting: `futurePoolLocal`, `baseFuturePool`, `claimableDelta`, `netSpend`, `lootboxToFuture`

**B4 `handleGameOverDrain()`** (GameOverModule, L68-163, 96 lines)
- Terminal state transition (gameOver = true)
- Complex fund distribution: deity pass refunds, terminal decimator, terminal jackpot
- Multiple cross-module delegatecalls to JackpotModule and DecimatorModule
- stETH + ETH dual accounting
- Budget-capped FIFO deity pass refund loop
- Critical: pool zeroing must happen atomically with distribution

### Tier 2 -- HIGH

**B3 `claimWhalePass()`** (EndgameModule, L540-559, 20 lines)
- Writes whalePassClaims (clear-before-use pattern)
- Calls _queueTicketRange for 100 levels
- gameOver guard

**B5 `handleFinalSweep()`** (GameOverModule, L170-188, 19 lines)
- 30-day timing gate
- Forfeits all unclaimed winnings (claimablePool = 0)
- stETH + ETH split transfer to vault/DGNRS
- VRF shutdown (fire-and-forget)

### Tier 3 -- MEDIUM

**B2 `rewardTopAffiliate()`** (EndgameModule, L130-149, 20 lines)
- External calls to affiliate and dgnrs contracts
- Writes levelDgnrsAllocation mapping
- No cached-local-vs-storage risk (no local pool caching)

---

## 5. Key Pitfalls and Areas Needing Extra Scrutiny

### Pitfall 1: rebuyDelta Edge Cases
- **What if `_getFuturePrizePool()` at L245 underflows?** If auto-rebuy somehow DECREASED futurePrizePool (impossible by design -- it only adds), Solidity 0.8 reverts. But this means a malicious/buggy subordinate that somehow decreases futurePrizePool would DoS `runRewardJackpots`.
- **What if no jackpot fires but auto-rebuy still runs?** If `prevMod10 != 0` and `prevMod10 != 5`, no jackpot fires, `futurePoolLocal == baseFuturePool`, reconciliation is skipped. But auto-rebuy can't trigger without a jackpot distribution, so no writes happen. Safe.

### Pitfall 2: handleGameOverDrain Re-entry via Retry
- L125: `if (rngWord == 0) return;` -- allows retry without latching `gameOverFinalJackpotPaid`
- Between first call (sets `gameOver = true`, `gameOverTime`) and successful retry (sets `gameOverFinalJackpotPaid = true`), the game is in `gameOver = true` but funds haven't been distributed
- During this window, can attacker claim/withdraw? `gameOver = true` blocks most actions; whale pass claim reverts at L541
- The early return at L125 leaves gameOver=true but NOT gameOverFinalJackpotPaid. On retry, L69 passes, L111 re-writes gameOver=true (idempotent), L112 re-writes gameOverTime (potential timestamp change)

### Pitfall 3: _sendToVault stETH Rounding
- stETH rebasing means `steth.balanceOf(address(this))` can differ from what was computed as `stBal`. Between the balance check and the transfer, a rebase could change the actual balance. However, stETH rounding always favors the contract (1-2 wei per transfer), so this is safe (per KNOWN-ISSUES.md).

### Pitfall 4: claimWhalePass Truncation
- L558: `uint32(halfPasses)` -- if `halfPasses` exceeds uint32 max, it truncates silently. However, halfPasses comes from whalePassClaims which is incremented by `fullHalfPasses = amount / HALF_WHALE_PASS_PRICE` (2.25 ether). To overflow uint32 (4.29B), would need 4.29B * 2.25 ETH = 9.66B ETH -- impossible with ETH supply.

### Pitfall 5: handleGameOverDrain Pool Zeroing Before Distribution
- L128-131 zeros all pools BEFORE running terminal jackpots at L139/L151
- This means `runTerminalDecimatorJackpot` and `runTerminalJackpot` see zeroed pools
- They receive the `decPool`/`remaining` as parameter ETH, not from storage pools
- This is intentional: prevents double-distribution and ensures terminal jackpots only use the passed `available` funds

---

## 6. Validation Architecture

### Storage Variables Written by EndgameModule

| Variable | Slot | Written By | Context |
|----------|------|-----------|---------|
| `prizePoolsPacked` (futurePrizePool) | 3 | C1 `_addClaimableEth` (auto-rebuy), B1 reconciliation | BAF-CRITICAL |
| `prizePoolsPacked` (nextPrizePool) | 3 | C1 `_addClaimableEth` (auto-rebuy) | BAF-CRITICAL |
| `claimableWinnings[addr]` | mapping | C1 via C5, C6 | Winner credits |
| `claimablePool` | 10 | C1, B1 L249 | Liability tracking |
| `whalePassClaims[addr]` | mapping | C6 | Deferred claims |
| `ticketsOwedPacked[key][addr]` | nested mapping | via _queueTickets/_queueTicketsScaled/_queueTicketRange | Ticket awards |
| `ticketQueue[key]` | mapping | via _queueTickets/_queueTicketsScaled/_queueTicketRange | Ticket awards |
| `levelDgnrsAllocation[lvl]` | mapping | B2 L148 | Affiliate allocation |
| `autoRebuyState[addr]` | mapping | Read only (not written here) | |
| `mintPacked_[addr]` | mapping | via _applyWhalePassStats | Whale pass stats |

### Storage Variables Written by GameOverModule

| Variable | Slot | Written By | Context |
|----------|------|-----------|---------|
| `gameOver` | 0 (byte 28) | B4 L111 | Terminal flag |
| `gameOverTime` | dedicated slot | B4 L112 | Timestamp |
| `gameOverFinalJackpotPaid` | dedicated slot | B4 L115/L127 | Payout guard |
| `finalSwept` | dedicated slot | B5 L175 | Sweep guard |
| `claimablePool` | 10 | B4 L104/L142, B5 L176 | Liability |
| `claimableWinnings[addr]` | mapping | B4 L92 (deity refund) | Direct write |
| `prizePoolsPacked` (next, future) | 3 | B4 L116-117/L128-129 | Zeroed |
| `currentPrizePool` | 2 | B4 L118/L130 | Zeroed |
| `yieldAccumulator` | dedicated slot | B4 L119/L131 | Zeroed |

---

## 7. MULTI-PARENT Function Analysis Requirements

| Function | Parents | Why Standalone |
|----------|---------|---------------|
| C5 `_creditClaimable` | C1 (auto-rebuy take-profit), C1 (no-rebuy path), C6 (whale pass remainder) | Called from different contexts with different claimablePool accounting expectations |
| C6 `_queueWhalePassClaimCore` | C2 (large winner lootbox half), C3 (large ticket award) | Different callers have different expectations about whether claimablePool is incremented |
| C7 `_sendToVault` | B4 (game-over remainder), B5 (final sweep) | Different stethBal sources and different pre-conditions |

---

*Research complete. Ready for plan creation.*
