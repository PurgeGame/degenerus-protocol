# POOL-02: Pool Mutation SSTORE Catalogue

**Scope:** Every SSTORE site that writes to ETH-denominated storage variables across the protocol
**Method:** Fresh from-scratch audit per D-01; Phase 214 cited as supporting evidence per D-02
**Coverage:** Named pool variables, intermediary memory locals, packed fields, and function return values per D-04

---

## Section 1: Storage Variable Inventory

| # | Variable | Type | Storage Slot | Packing | Written By (Contract List) |
|---|----------|------|-------------|---------|----------------------------|
| 1 | `prizePoolsPacked` | uint256 | Slot 2 (full width) | `[255:128] futurePrizePool \| [127:0] nextPrizePool` (uint128 each) | Storage (helpers), AdvanceModule, JackpotModule, DecimatorModule, DegeneretteModule, MintModule (via recordMint), WhaleModule, GameOverModule |
| 2 | `currentPrizePool` | uint128 | Slot 1 (low 128 bits) | Packed with `claimablePool` in same slot | Storage (helpers), AdvanceModule, JackpotModule, GameOverModule |
| 3 | `claimablePool` | uint128 | Slot 1 (high 128 bits) | Packed with `currentPrizePool` in same slot | AdvanceModule, JackpotModule, DecimatorModule, DegeneretteModule, MintModule (via _processMintPayment), Game.sol, GameOverModule, PayoutUtils |
| 4 | `claimableWinnings` | mapping(address => uint256) | Mapping (computed slot) | Per-recipient, full uint256 | JackpotModule (via _creditClaimable), DecimatorModule, DegeneretteModule, MintModule (via _processMintPayment), Game.sol, GameOverModule, PayoutUtils |
| 5 | `resumeEthPool` | uint128 | Dedicated slot (line 1020) | Single uint128 | JackpotModule (_processDailyEth) |
| 6 | `yieldAccumulator` | uint256 | Dedicated slot (line 1519) | Full width | AdvanceModule, JackpotModule (distributeYieldSurplus), GameOverModule |
| 7 | `levelPrizePool` | mapping(uint24 => uint256) | Mapping (computed slot) | Per-level snapshot, full uint256 | AdvanceModule (_endPhase, advanceGame level transition), Game.sol (constructor) |
| 8 | `prizePoolPendingPacked` | uint256 | Dedicated slot | `[255:128] pendingFuture \| [127:0] pendingNext` (same layout as prizePoolsPacked) | Storage (_setPendingPools), DegeneretteModule, MintModule, WhaleModule |
| 9 | `whalePassClaims` | mapping(address => uint256) | Mapping (computed slot) | Tickets owed per player | JackpotModule (_processSoloBucketWinner), PayoutUtils (_queueWhalePassClaimCore) |

**Note:** Variables 8-9 carry ETH value indirectly: `prizePoolPendingPacked` accumulates pool contributions during freeze windows; `whalePassClaims` represents deferred ticket value backed by futurePool.

---

## Section 2: Per-Contract SSTORE Catalogue

### 2.1: DegenerusGameStorage.sol -- Helper Functions

These helpers mediate most pool writes. No direct external access; all called internally by modules executing via delegatecall in the Game contract's storage context.

| Helper | Lines | Variable Written | Packing Logic | Callers |
|--------|-------|-----------------|---------------|---------|
| `_setPrizePools(next, future)` | 693-695 | `prizePoolsPacked` | `(uint256(future) << 128) \| uint256(next)` | AdvanceModule, JackpotModule, DegeneretteModule, MintModule, WhaleModule |
| `_getPrizePools()` | 697-705 | (read only) | `next = uint128(packed)`, `future = uint128(packed >> 128)` | All modules reading pools |
| `_setPendingPools(next, future)` | 707-709 | `prizePoolPendingPacked` | Same packing as `_setPrizePools` | DegeneretteModule, MintModule, WhaleModule (frozen paths) |
| `_setNextPrizePool(val)` | 790-793 | `prizePoolsPacked` | Reads future, writes `_setPrizePools(uint128(val), future)` | JackpotModule (lootbox, carryover, early-bird, auto-rebuy) |
| `_setFuturePrizePool(val)` | 802-805 | `prizePoolsPacked` | Reads next, writes `_setPrizePools(next, uint128(val))` | JackpotModule (daily drip, whale pass, carryover, early-bird), DecimatorModule |
| `_setCurrentPrizePool(val)` | 820-822 | `currentPrizePool` | `currentPrizePool = uint128(val)` -- narrows uint256 to uint128 | AdvanceModule (via _consolidate), JackpotModule (daily deductions) |
| `_unfreezePool()` | 770-777 | `prizePoolsPacked`, `prizePoolPendingPacked`, `prizePoolFrozen` | Merges pending into live: `_setPrizePools(next + pNext, future + pFuture)`, clears pending to 0 | Called at end of freeze window |
| `_swapAndFreeze(purchaseLevel)` | 760-766 | `prizePoolPendingPacked`, `prizePoolFrozen` | If not frozen: zeros `prizePoolPendingPacked`, sets `prizePoolFrozen = true` | AdvanceModule (RNG request) |

**Integrity verdict:** _setPrizePools packing is correct: future occupies bits [255:128], next occupies bits [127:0], no bit overlap. Confirmed by Phase 214 (214-03: zero state corruption in packed pool fields). **SAFE**.

**uint128 narrowing verdict:** _setCurrentPrizePool narrows uint256 to uint128. Confirmed safe by Phase 214 (214-02: uint128 max = 3.4e20 ETH >> 1.2e8 total ETH supply, margin > 10^12x). **SAFE / INFO**.

---

### 2.2: DegenerusGameAdvanceModule.sol

#### 2.2.1: `_consolidatePoolsAndRewardJackpots` (lines 620-797)

This is the primary pool mutation function. All intermediate pool values are computed in memory variables (`memFuture`, `memNext`, `memCurrent`, `memYieldAcc`), then written back to storage in a single batch at lines 790-795.

| Line | Variable Written | Direction | Amount Source | Guard | Verdict |
|------|-----------------|-----------|---------------|-------|---------|
| 627 | `memFuture` (local) | SET | `_getFuturePrizePool()` | Read from storage | SAFE -- initial load |
| 628 | `memCurrent` (local) | SET | `_getCurrentPrizePool()` | Read from storage | SAFE -- initial load |
| 629 | `memNext` (local) | SET | `_getNextPrizePool()` | Read from storage | SAFE -- initial load |
| 630 | `memYieldAcc` (local) | SET | `yieldAccumulator` | Read from storage | SAFE -- initial load |
| 696 | `memNext` | DECREASE | `take + insuranceSkim` | `take` capped at 80% of memNext; `insuranceSkim` = 1% of memNext | SAFE -- cannot underflow: take + insuranceSkim <= 81% of memNext |
| 697 | `memFuture` | INCREASE | `take` | Sourced from memNext deduction | SAFE -- conservation: memNext decrease = memFuture increase |
| 698 | `memYieldAcc` | INCREASE | `insuranceSkim` | 1% of memNext | SAFE -- sourced from memNext decrease |
| 703-705 | `memFuture` / `memYieldAcc` | INCREASE / DECREASE | x00 half dump: `half = memYieldAcc >> 1` | Only on x00 levels | SAFE -- half <= memYieldAcc, no underflow |
| 725 | `memFuture` | DECREASE | `claimed` (BAF jackpot paidout) | BAF pool <= 20% of baseMemFuture | SAFE -- claimed returned from runBafJackpot self-call, bounded by bafPoolWei |
| 726 | `claimableDelta` (local) | INCREASE | `claimed` | Tracks liability increase | SAFE |
| 733-734 | `memFuture` | DECREASE | `spend` (Decimator) | `spend = decPoolWei - returnWei` | SAFE -- spend bounded by decPoolWei which is 30% or 10% of memFuture |
| 735 | `claimableDelta` (local) | INCREASE | `spend` | Tracks liability increase | SAFE |
| 744-745 | `memFuture` | DECREASE | `spend` (x5 Decimator) | `spend = decPoolWei - returnWei`; decPoolWei = 10% of post-BAF memFuture | SAFE |
| 746 | `claimableDelta` (local) | INCREASE | `spend` | Tracks liability increase | SAFE |
| 765-766 | `memFuture` / `memCurrent` | DECREASE / INCREASE | x00 keep roll `moveWei` | `moveWei = memFuture * (1 - keepBps/10000)`, keepBps in [3000, 6500] | SAFE -- moveWei <= memFuture, conservation maintained |
| 772 | `memCurrent` | INCREASE | `memNext` | Full merge of next into current | SAFE -- memNext zeroed on 773 |
| 773 | `memNext` | SET | `0` | After merge to current | SAFE |
| 784-787 | `memFuture` / `memNext` | DECREASE / INCREASE | 15% drawdown (non-x00) | `reserved = memFuture * 15 / 100` | SAFE -- reserved <= memFuture |
| 790 | `prizePoolsPacked` | SET | `_setPrizePools(uint128(memNext), uint128(memFuture))` | Batch writeback | SAFE -- uint128 narrowing proven safe (214-02) |
| 791 | `currentPrizePool` | SET | `uint128(memCurrent)` | Batch writeback | SAFE -- uint128 narrowing proven safe (214-02) |
| 792 | `yieldAccumulator` | SET | `memYieldAcc` | Batch writeback | SAFE |
| 793-795 | `claimablePool` | INCREASE | `uint128(claimableDelta)` | Only if claimableDelta != 0 | SAFE -- claimableDelta bounded by futurePool which fits uint128; matches credits from BAF/Decimator self-calls |

**Writeback integrity (T-216-08):** Every memory local (`memFuture`, `memNext`, `memCurrent`, `memYieldAcc`) is initialized from storage at lines 627-630 and written back at lines 790-792. No local is lost. **MITIGATED**.

**Self-call interaction (T-216-05):** `runBafJackpot` and `runDecimatorJackpot` are self-calls that may trigger `_addClaimableEth` with auto-rebuy writing to `prizePoolsPacked`. These writes are intentionally overwritten by the batch SSTORE at line 790. The amounts are tracked via `claimableDelta` which adjusts `claimablePool`. Per 214-03: "Auto-rebuy pool writes may be overwritten by pool consolidation memory batch; this is by design." **SAFE**.

#### 2.2.2: `advanceGame` Pool Writes (lines 156-438)

| Line | Variable Written | Direction | Amount Source | Guard | Verdict |
|------|-----------------|-----------|---------------|-------|---------|
| 373 | `levelPrizePool[purchaseLevel]` | SET | `_getNextPrizePool()` | Before consolidation; snapshot of next pool at level transition | SAFE -- read-then-write, no mutation |
| 535 | `levelPrizePool[lvl]` | SET | `_getFuturePrizePool() / 3` | Only on x00 levels in `_endPhase()` | SAFE -- one-third of future pool |

#### 2.2.3: `_distributeYieldSurplus` (lines 595-605)

Delegatecall to JackpotModule -- pool writes happen inside JackpotModule. See section 2.3.

---

### 2.3: DegenerusGameJackpotModule.sol

#### 2.3.1: `distributeYieldSurplus` (lines 716-750)

| Line | Variable Written | Direction | Amount Source | Guard | Verdict |
|------|-----------------|-----------|---------------|-------|---------|
| 731-745 | `claimableWinnings[VAULT]`, `claimableWinnings[SDGNRS]`, `claimableWinnings[GNRUS]` | INCREASE | `quarterShare` each (23% of yield surplus) | yield surplus = totalBal - obligations; only runs if surplus > 0 | SAFE |
| 747 | `claimablePool` | INCREASE | `uint128(d0 + d1 + d2)` | Sum of actual credits (may differ from 3x quarterShare due to auto-rebuy) | SAFE -- bounded by yield surplus |
| 748 | `yieldAccumulator` | INCREASE | `quarterShare` | 23% of yield surplus deposited as insurance | SAFE |

**T-216-07 check:** claimablePool += matches sum of credits from `_addClaimableEth` calls. If auto-rebuy converts some portion to tickets, `claimableDelta` from `_addClaimableEth` is reduced accordingly, and the difference is routed to pool via `_setFuturePrizePool`/`_setNextPrizePool`. Conservation maintained: credited + routed-to-pool = quarterShare. **MITIGATED**.

#### 2.3.2: `_addClaimableEth` (lines 764-788)

| Line | Variable Written | Direction | Amount Source | Guard | Verdict |
|------|-----------------|-----------|---------------|-------|---------|
| 786 | `claimableWinnings[beneficiary]` | INCREASE | `weiAmount` (via `_creditClaimable`) | Non-zero check at 772 | SAFE |
| (caller) | `claimablePool` | INCREASE | Return value `claimableDelta` | Caller responsible for aggregating and writing | SAFE -- designed as deferred write pattern |

**Auto-rebuy path (`_processAutoRebuy`, lines 798-834):**

| Line | Variable Written | Direction | Amount Source | Guard | Verdict |
|------|-----------------|-----------|---------------|-------|---------|
| 817 | `claimableWinnings[player]` | INCREASE | `newAmount` (via `_creditClaimable`) | When no tickets produced | SAFE |
| 824 | `prizePoolsPacked` (future) | INCREASE | `calc.ethSpent` (via `_setFuturePrizePool`) | When `calc.toFuture == true` | SAFE -- ETH recycled from winnings to pool |
| 826 | `prizePoolsPacked` (next) | INCREASE | `calc.ethSpent` (via `_setNextPrizePool`) | When `calc.toFuture == false` | SAFE -- ETH recycled from winnings to pool |
| 830 | `claimableWinnings[player]` | INCREASE | `calc.reserved` (via `_creditClaimable`) | Take-profit portion reserved for claim | SAFE |

#### 2.3.3: `payDailyJackpot` -- Jackpot Phase Path (lines 310-491)

| Line | Variable Written | Direction | Amount Source | Guard | Verdict |
|------|-----------------|-----------|---------------|-------|---------|
| 378-379 | `currentPrizePool` | DECREASE | `dailyLootboxBudget` (via `_setCurrentPrizePool`) | Only when `dailyTicketUnits != 0` | SAFE -- budget derived from currentPrizePool |
| 381 | `prizePoolsPacked` (next) | INCREASE | `dailyLootboxBudget` (via `_setNextPrizePool`) | Same condition | SAFE -- conservation: currentPrizePool down, nextPrizePool up |
| 405 | `prizePoolsPacked` (future) | DECREASE | `reserveSlice` (via `_setFuturePrizePool`) | Only on non-earlybird days; `reserveSlice = futurePoolBal / 200` (0.5%) | SAFE -- 0.5% of futurePool |
| 406 | `prizePoolsPacked` (next) | INCREASE | `reserveSlice` (via `_setNextPrizePool`) | Same condition | SAFE -- conservation: future down, next up |
| 476-477 | `currentPrizePool` | DECREASE | `dailyEthBudget` (via `_setCurrentPrizePool`) | Only on final day (`isFinalPhysicalDay`) | SAFE -- full budget deducted |
| 479-482 | `prizePoolsPacked` (future) | INCREASE | `unpaidDailyEth = dailyEthBudget - paidDailyEth` (via `_setFuturePrizePool`) | Only on final day with unpaid remainder | SAFE -- refund of unawarded ETH to future pool |
| 485 | `currentPrizePool` | DECREASE | `paidDailyEth` (via `_setCurrentPrizePool`) | Non-final days | SAFE -- only paid amount deducted |

#### 2.3.4: `payDailyJackpot` -- Purchase Phase Path (lines 493-536)

| Line | Variable Written | Direction | Amount Source | Guard | Verdict |
|------|-----------------|-----------|---------------|-------|---------|
| 522-524 | `prizePoolsPacked` (future) | DECREASE | `lootboxBudget + paidEth` (via `_setFuturePrizePool`) | Only when `ethDaySlice != 0` (lvl > 0) | SAFE -- deducting only what was consumed |

#### 2.3.5: `_resumeDailyEth` (lines 1131-1156)

| Line | Variable Written | Direction | Amount Source | Guard | Verdict |
|------|-----------------|-----------|---------------|-------|---------|
| 1151 | `prizePoolsPacked` (future) | DECREASE | `paidEth2` (via `_setFuturePrizePool`) | Final day, call 2 | SAFE -- deducting paid amount |
| 1153 | `currentPrizePool` | DECREASE | `paidEth2` (via `_setCurrentPrizePool`) | Non-final day, call 2 | SAFE -- deducting paid amount |

#### 2.3.6: `_processDailyEth` (lines 1182-1292)

| Line | Variable Written | Direction | Amount Source | Guard | Verdict |
|------|-----------------|-----------|---------------|-------|---------|
| 1194-1195 | `resumeEthPool` | SET/CLEAR | `uint256(resumeEthPool)` then `resumeEthPool = 0` | Only in SPLIT_CALL2 mode | SAFE -- reads snapshot then clears |
| 1284-1286 | `claimablePool` | INCREASE | `uint128(liabilityDelta)` | Sum of credits across all buckets | SAFE -- matches sum of `_addClaimableEth` returns |
| 1290 | `resumeEthPool` | SET | `uint128(ethPool)` | Only in SPLIT_CALL1 mode; carries over ETH for call 2 | SAFE -- ethPool is the original budget, uint128 narrowing safe (214-02) |

#### 2.3.7: `_processSoloBucketWinner` (lines 1489-1532)

| Line | Variable Written | Direction | Amount Source | Guard | Verdict |
|------|-----------------|-----------|---------------|-------|---------|
| 1513-1517 | `claimableWinnings[winner]` | INCREASE | `ethAmount` (via `_addClaimableEth`) | When whale pass split applies | SAFE |
| 1520 | `whalePassClaims[winner]` | INCREASE | `whalePassCount` | Deferred ticket claim | SAFE -- no ETH write |
| 1521 | `prizePoolsPacked` (future) | INCREASE | `whalePassCost` (via `_setFuturePrizePool`) | Whale pass cost routes to future pool | SAFE -- matches whale pass conversion |
| 1525-1529 | `claimableWinnings[winner]` | INCREASE | `perWinner` (via `_addClaimableEth`) | When 25% too small for whale pass -- full ETH path | SAFE |

#### 2.3.8: `_payNormalBucket` (lines 1459-1481)

| Line | Variable Written | Direction | Amount Source | Guard | Verdict |
|------|-----------------|-----------|---------------|-------|---------|
| 1471-1472 | `claimableWinnings[w]` | INCREASE | `perWinner` (via `_addClaimableEth`) | Per-winner credit | SAFE |

#### 2.3.9: `_runEarlyBirdLootboxJackpot` (lines 634-710)

| Line | Variable Written | Direction | Amount Source | Guard | Verdict |
|------|-----------------|-----------|---------------|-------|---------|
| 641 | `prizePoolsPacked` (future) | DECREASE | `reserveContribution` (3% of future) via `_setFuturePrizePool` | Budget sourced from futurePool | SAFE |
| 709 | `prizePoolsPacked` (next) | INCREASE | `totalBudget` via `_setNextPrizePool` | Full budget recycled to nextPrizePool | SAFE -- conservation: future down, next up |

#### 2.3.10: `_distributeLootboxAndTickets` (lines 853-877)

| Line | Variable Written | Direction | Amount Source | Guard | Verdict |
|------|-----------------|-----------|---------------|-------|---------|
| 861 | `prizePoolsPacked` (next) | INCREASE | `lootboxBudget` via `_setNextPrizePool` | Purchase-phase lootbox to next pool | SAFE |

#### 2.3.11: `runBafJackpot` (lines 1977-2059)

| Line | Variable Written | Direction | Amount Source | Guard | Verdict |
|------|-----------------|-----------|---------------|-------|---------|
| 2007-2012 | `claimableWinnings[winner]` | INCREASE | `ethPortion` (half of large winner amount) via `_addClaimableEth` | Large winner (>= 5% of pool) | SAFE |
| 2039-2044 | `claimableWinnings[winner]` | INCREASE | `amount` (full amount for even-index small winners) via `_addClaimableEth` | Small winner, even index | SAFE |

**claimableDelta return:** `runBafJackpot` returns `claimableDelta` (sum of `_addClaimableEth` returns). The caller (`_consolidatePoolsAndRewardJackpots`) deducts this from `memFuture` and adds it to `claimablePool`. Lootbox and whale pass portions stay implicitly in `futurePool` (no deduction from memFuture since caller only subtracts `claimableDelta`). **SAFE**.

#### 2.3.12: `runTerminalJackpot` (lines 251-286)

| Line | Variable Written | Direction | Amount Source | Guard | Verdict |
|------|-----------------|-----------|---------------|-------|---------|
| 275-285 | via `_processDailyEth` | (see 2.3.6) | `poolWei` | SPLIT_NONE, not jackpot phase | SAFE -- claimablePool += liabilityDelta within _processDailyEth |

---

### 2.4: DegenerusGameDecimatorModule.sol

#### 2.4.1: `runDecimatorJackpot` (lines 195-247)

No direct pool SSTORE. Stores claim snapshot (`decClaimRounds[lvl].poolWei`) and returns 0 (all funds held) or `poolWei` (refund). The caller (`_consolidatePoolsAndRewardJackpots`) handles the pool accounting based on the return value.

**Verdict:** SAFE -- no pool mutation, pure claim snapshot.

#### 2.4.2: `claimDecimatorJackpot` (lines 307-328)

| Line | Variable Written | Direction | Amount Source | Guard | Verdict |
|------|-----------------|-----------|---------------|-------|---------|
| 316 | `claimableWinnings[msg.sender]` | INCREASE | `amountWei` (via `_creditClaimable`) | `gameOver == true` path (no lootbox split) | SAFE |
| 316 | (implied) `claimablePool` | no write | (already reserved from snapshot) | gameOver path -- claimablePool was already incremented during handleGameOverDrain | INFO -- no claimablePool write needed; liability already tracked |
| 320-327 | `claimableWinnings[msg.sender]` | INCREASE | `ethPortion` (via `_creditDecJackpotClaimCore` -> `_creditClaimable`) | Normal (non-gameover) path | SAFE |
| 326 | `prizePoolsPacked` (future) | INCREASE | `lootboxPortion` (via `_setFuturePrizePool`) | Lootbox portion recycled to futurePool | SAFE |
| 366 | `claimablePool` | DECREASE | `uint128(lootboxPortion)` | Inside `_creditDecJackpotClaimCore` | SAFE -- removes lootbox portion from liability (tickets replace ETH claim) |

**T-216-07 check:** `_creditDecJackpotClaimCore` credits `ethPortion` to claimableWinnings (half the claim) and reduces `claimablePool` by `lootboxPortion` (the other half). The full claim amount was already reserved in `claimablePool` when the decimator round was settled. So: `claimablePool` net change = -lootboxPortion. The ethPortion remains in `claimablePool` to back the `claimableWinnings` credit. **SAFE**.

#### 2.4.3: `runTerminalDecimatorJackpot` (lines 723-771)

No direct pool SSTORE. Returns 0 (funds held for claims) or poolWei (refund). Caller in GameOverModule handles accounting.

#### 2.4.4: `claimTerminalDecimatorJackpot` (lines 779-783)

| Line | Variable Written | Direction | Amount Source | Guard | Verdict |
|------|-----------------|-----------|---------------|-------|---------|
| 782 | `claimableWinnings[msg.sender]` | INCREASE | `amountWei` (via `_creditClaimable`) | Pro-rata share of terminal decimator pool | SAFE |

**Note:** No `claimablePool +=` here. The claimablePool was incremented by `decSpend` in `handleGameOverDrain` (line 165), which reserves the full decimator spend upfront. Individual claims only write to `claimableWinnings` -- the aggregate liability in `claimablePool` was already set. **SAFE**.

---

### 2.5: DegenerusGameDegeneretteModule.sol

#### 2.5.1: `_collectBetFunds` (lines 511-545)

| Line | Variable Written | Direction | Amount Source | Guard | Verdict |
|------|-----------------|-----------|---------------|-------|---------|
| 524 | `claimableWinnings[player]` | DECREASE | `fromClaimable` | ETH shortfall pulled from claimable balance; guard: `claimableWinnings[player] > fromClaimable` (strict >) | SAFE -- leaves sentinel |
| 525 | `claimablePool` | DECREASE | `uint128(fromClaimable)` | Matches claimableWinnings deduction | SAFE |
| 531 | `prizePoolPendingPacked` | INCREASE | `uint128(totalBet)` to future | When `prizePoolFrozen == true` | SAFE -- routes to pending during freeze |
| 533-534 | `prizePoolsPacked` | INCREASE | `uint128(totalBet)` to future | When `prizePoolFrozen == false` | SAFE -- routes to live pool |

#### 2.5.2: `_distributePayout` (lines 684-740)

| Line | Variable Written | Direction | Amount Source | Guard | Verdict |
|------|-----------------|-----------|---------------|-------|---------|
| 710 | `prizePoolPendingPacked` | DECREASE | `uint128(ethPortion)` from pending future | Frozen path; solvency check at 705 (`pFuture >= ethPortion`) | SAFE |
| 711 | `claimableWinnings[player]` | INCREASE | `ethPortion` (via `_addClaimableEth`) | Frozen path | SAFE |
| 711 | `claimablePool` | INCREASE | `uint128(ethPortion)` (inside DegeneretteModule `_addClaimableEth`) | Frozen path | SAFE |
| 727 | `prizePoolsPacked` (future) | DECREASE | `ethPortion` (via `_setFuturePrizePool`) | Unfrozen path; capped at 10% of pool (line 718) | SAFE -- solvency guaranteed by cap |
| 728 | `claimableWinnings[player]` | INCREASE | `ethPortion` (via `_addClaimableEth`) | Unfrozen path | SAFE |
| 728 | `claimablePool` | INCREASE | `uint128(ethPortion)` (inside DegeneretteModule `_addClaimableEth`) | Unfrozen path | SAFE |

**Note:** DegeneretteModule has its own private `_addClaimableEth` (line 1090-1094) which differs from JackpotModule's version: it always credits the full amount with NO auto-rebuy path. It writes `claimablePool += uint128(weiAmount)` and calls `_creditClaimable(beneficiary, weiAmount)`. **T-216-07 check: claimablePool increase matches claimableWinnings increase. MITIGATED.**

---

### 2.6: DegenerusGameMintModule.sol (via `recordMint` in Game.sol)

#### 2.6.1: `recordMint` -> `_processMintPayment` (Game.sol lines 350-391, 903-962)

| Line | Variable Written | Direction | Amount Source | Guard | Verdict |
|------|-----------------|-----------|---------------|-------|---------|
| 923 (Game.sol) | `claimableWinnings[player]` | DECREASE | `amount` (Claimable payKind) or `claimableUsed` (Combined) | Strict > check preserves sentinel | SAFE |
| 941 (Game.sol) | `claimableWinnings[player]` | DECREASE | `claimableUsed` (Combined payKind) | Preserves 1 wei sentinel | SAFE |
| 953 (Game.sol) | `claimablePool` | DECREASE | `uint128(claimableUsed)` | Matches claimableWinnings deduction | SAFE |
| 369-370 (Game.sol) | `prizePoolPendingPacked` | INCREASE | `nextShare + futureShare` | When `prizePoolFrozen == true` | SAFE |
| 375-378 (Game.sol) | `prizePoolsPacked` | INCREASE | `nextShare + futureShare` | When `prizePoolFrozen == false` | SAFE |

#### 2.6.2: `_purchaseFor` -- Lootbox Pool Splits (MintModule lines 1052-1068)

| Line | Variable Written | Direction | Amount Source | Guard | Verdict |
|------|-----------------|-----------|---------------|-------|---------|
| 1057-1061 | `prizePoolPendingPacked` | INCREASE | `nextShare + futureShare` (from lootBoxAmount) | When `prizePoolFrozen == true` | SAFE |
| 1063-1067 | `prizePoolsPacked` | INCREASE | `nextShare + futureShare` | When `prizePoolFrozen == false` | SAFE |

#### 2.6.3: `_purchaseFor` -- Claimable Usage (MintModule lines 928-954)

| Line | Variable Written | Direction | Amount Source | Guard | Verdict |
|------|-----------------|-----------|---------------|-------|---------|
| 951 | `claimableWinnings[buyer]` | DECREASE | `shortfall` | Lootbox claimable shortfall path | SAFE -- preserves sentinel |
| 953 | `claimablePool` | DECREASE | `uint128(shortfall)` | Matches claimableWinnings deduction | SAFE |

---

### 2.7: DegenerusGameWhaleModule.sol

#### 2.7.1: `_purchaseWhaleBundle` (lines 194-365)

| Line | Variable Written | Direction | Amount Source | Guard | Verdict |
|------|-----------------|-----------|---------------|-------|---------|
| 346-350 | `prizePoolPendingPacked` | INCREASE | `nextShare + (totalPrice - nextShare)` | When `prizePoolFrozen == true` | SAFE -- full `totalPrice` allocated |
| 352-356 | `prizePoolsPacked` | INCREASE | `nextShare + (totalPrice - nextShare)` | When `prizePoolFrozen == false` | SAFE |

Split logic: level 0 = 30/70 next/future, level > 0 = 5/95 next/future.

#### 2.7.2: `_purchaseLazyPass` (lines 384-518)

| Line | Variable Written | Direction | Amount Source | Guard | Verdict |
|------|-----------------|-----------|---------------|-------|---------|
| 491-496 | `prizePoolPendingPacked` | INCREASE | `nextShare + futureShare` (from totalPrice) | Frozen path | SAFE |
| 498-502 | `prizePoolsPacked` | INCREASE | `nextShare + futureShare` | Unfrozen path | SAFE |

Split: futureShare = totalPrice * LAZY_PASS_TO_FUTURE_BPS / 10000, nextShare = totalPrice - futureShare.

#### 2.7.3: `_purchaseDeityPass` (lines 542-655)

| Line | Variable Written | Direction | Amount Source | Guard | Verdict |
|------|-----------------|-----------|---------------|-------|---------|
| 645-650 | `prizePoolPendingPacked` | INCREASE | `nextShare + (totalPrice - nextShare)` | Frozen path | SAFE |
| 652-655 | `prizePoolsPacked` | INCREASE | `nextShare + (totalPrice - nextShare)` | Unfrozen path | SAFE |

Same split ratios as whale bundle (30/70 pre-game, 5/95 post-game).

---

### 2.8: DegenerusGameGameOverModule.sol

#### 2.8.1: `handleGameOverDrain` (lines 79-181)

| Line | Variable Written | Direction | Amount Source | Guard | Verdict |
|------|-----------------|-----------|---------------|-------|---------|
| 119 | `claimableWinnings[owner]` | INCREASE | `refund` (deity pass refund) | Only at levels 0-9; budget-capped to `preRefundAvailable` | SAFE |
| 131 | `claimablePool` | INCREASE | `uint128(totalRefunded)` | Sum of all deity pass refunds | SAFE -- matches sum of claimableWinnings credits |
| 144 | `prizePoolsPacked` (next) | SET | `0` (via `_setNextPrizePool(0)`) | Terminal drain: zero all pools | SAFE |
| 145 | `prizePoolsPacked` (future) | SET | `0` (via `_setFuturePrizePool(0)`) | Terminal drain | SAFE |
| 146 | `currentPrizePool` | SET | `0` (via `_setCurrentPrizePool(0)`) | Terminal drain | SAFE |
| 147 | `yieldAccumulator` | SET | `0` | Terminal drain | SAFE |
| 165 | `claimablePool` | INCREASE | `uint128(decSpend)` | Terminal decimator spend reserved upfront | SAFE |
| 194 | `claimablePool` | SET | `0` | Inside handleFinalSweep (30-day post-gameover) | SAFE -- forfeits all unclaimed |

**Terminal sequence:** All named pools zeroed (lines 144-147), then `available` is computed from `totalFunds - claimablePool`. Decimator and terminal jackpot distribute from `available`. Remaining goes to `_sendToVault`. **SAFE -- pools correctly drained to zero, available correctly excludes claimable liability**.

#### 2.8.2: `handleFinalSweep` (lines 188-208)

| Line | Variable Written | Direction | Amount Source | Guard | Verdict |
|------|-----------------|-----------|---------------|-------|---------|
| 194 | `claimablePool` | SET | `0` | 30-day post-gameover; all claims forfeited | SAFE |

No other pool writes -- `_sendToVault` transfers ETH/stETH externally.

---

### 2.9: DegenerusGame.sol (Non-Delegatecall)

#### 2.9.1: `_claimWinningsInternal` (lines 1366-1382)

| Line | Variable Written | Direction | Amount Source | Guard | Verdict |
|------|-----------------|-----------|---------------|-------|---------|
| 1372 | `claimableWinnings[player]` | SET | `1` (sentinel) | Leave 1 wei to avoid cold->warm SSTORE cost | SAFE |
| 1375 | `claimablePool` | DECREASE | `uint128(payout)` where `payout = amount - 1` | CEI: state updated before external call | SAFE -- payout <= claimableWinnings[player] - 1 <= claimablePool |

**T-216-07 check:** claimablePool -= matches claimableWinnings -= (both reduced by same `payout` amount). **MITIGATED**.

#### 2.9.2: `constructor` (Game.sol line 220)

| Line | Variable Written | Direction | Amount Source | Guard | Verdict |
|------|-----------------|-----------|---------------|-------|---------|
| 220 | `levelPrizePool[0]` | SET | `BOOTSTRAP_PRIZE_POOL` | Constructor-only, initialization | SAFE |

---

### 2.10: DegenerusGamePayoutUtils.sol (Inherited Utility)

#### 2.10.1: `_creditClaimable` (lines 33-38)

| Line | Variable Written | Direction | Amount Source | Guard | Verdict |
|------|-----------------|-----------|---------------|-------|---------|
| 36 | `claimableWinnings[beneficiary]` | INCREASE | `weiAmount` | Non-zero check at 34; unchecked (uint256 overflow impossible with real ETH) | SAFE |

This is the leaf function called by all claimable credit paths. Does NOT write to `claimablePool` -- callers are responsible for maintaining the aggregate.

#### 2.10.2: `_queueWhalePassClaimCore` (lines 89-106)

| Line | Variable Written | Direction | Amount Source | Guard | Verdict |
|------|-----------------|-----------|---------------|-------|---------|
| 96 | `whalePassClaims[winner]` | INCREASE | `fullHalfPasses` | Ticket count (not ETH) | SAFE |
| 100 | `claimableWinnings[winner]` | INCREASE | `remainder` (sub-half-pass dust) | Unchecked; remainder < HALF_WHALE_PASS_PRICE | SAFE |
| 102 | `claimablePool` | INCREASE | `uint128(remainder)` | Matches claimableWinnings credit | SAFE |

---

## Section 3: Intermediary Variable Tracking (per D-04)

### 3.1: Memory Locals in `_consolidatePoolsAndRewardJackpots`

| Function | Variable | Type | Lifetime | Written Back To | Risk |
|----------|----------|------|----------|-----------------|------|
| `_consolidatePoolsAndRewardJackpots` | `memFuture` | uint256 | Lines 627-790 | `prizePoolsPacked` (future half) via `_setPrizePools` at 790 | SAFE -- written back unconditionally; all mutations tracked |
| `_consolidatePoolsAndRewardJackpots` | `memNext` | uint256 | Lines 629-790 | `prizePoolsPacked` (next half) via `_setPrizePools` at 790 | SAFE -- written back unconditionally |
| `_consolidatePoolsAndRewardJackpots` | `memCurrent` | uint256 | Lines 628-791 | `currentPrizePool` via direct assignment at 791 | SAFE -- written back unconditionally |
| `_consolidatePoolsAndRewardJackpots` | `memYieldAcc` | uint256 | Lines 630-792 | `yieldAccumulator` via direct assignment at 792 | SAFE -- written back unconditionally |
| `_consolidatePoolsAndRewardJackpots` | `claimableDelta` | uint256 | Lines 712-795 | `claimablePool` via `+= uint128(claimableDelta)` at 794 | SAFE -- only if non-zero |
| `_consolidatePoolsAndRewardJackpots` | `baseMemFuture` | uint256 | Line 709 | Not written back; used as snapshot for BAF/Decimator % calculation | SAFE -- read-only reference point |

**T-216-08 mitigation:** Every memory local that holds an ETH amount during computation is written back to its corresponding storage variable. No local is lost or silently discarded. The batch writeback at lines 790-795 covers all four pool variables and the yield accumulator. **MITIGATED**.

### 3.2: Return Values Carrying ETH Amounts

| Function | Return Value | Type | Destination | Risk |
|----------|-------------|------|-------------|------|
| `runBafJackpot` | `claimableDelta` | uint256 | `_consolidatePoolsAndRewardJackpots`: subtracted from `memFuture`, added to `claimablePool` | SAFE -- amount bounded by bafPoolWei |
| `runDecimatorJackpot` | `returnAmountWei` | uint256 | `_consolidatePoolsAndRewardJackpots`: when returnWei > 0, `spend = decPoolWei - returnWei` deducted from memFuture | SAFE -- return <= decPoolWei |
| `_addClaimableEth` | `claimableDelta` | uint256 | Various callers aggregate into `liabilityDelta` for claimablePool write | SAFE -- return <= weiAmount input |
| `_processDailyEth` | `paidEth` | uint256 | Callers deduct from currentPrizePool or futurePrizePool | SAFE -- paidEth <= ethPool input |
| `_executeJackpot` | `paidEth` | uint256 | `payDailyJackpot` purchase-phase: deducted from futurePrizePool | SAFE -- paidEth <= jp.ethPool |
| `_processSoloBucketWinner` | `claimableDelta`, `ethPaid`, `whalePassSpent` | uint256 x3 | Aggregated into paidDelta and liabilityDelta in `_handleSoloBucketWinner` | SAFE -- sum bounded by perWinner |

### 3.3: uint128-Narrowed Intermediate Values

| Location | Expression | Source Width | Target Width | Safety | Verdict |
|----------|-----------|-------------|-------------|--------|---------|
| `_setPrizePools` L694 | `uint256(future) << 128 \| uint256(next)` | uint128 inputs | uint256 packed | Widening -- always safe | SAFE |
| `_setCurrentPrizePool` L821 | `currentPrizePool = uint128(val)` | uint256 | uint128 | Max pool value << uint128 max (214-02) | SAFE / INFO |
| `claimablePool +=` (all sites) | `uint128(amount)` | uint256 | uint128 | Amount bounded by pool values which fit uint128 (214-02) | SAFE / INFO |
| `resumeEthPool = uint128(ethPool)` L1290 | `uint128(ethPool)` | uint256 | uint128 | ethPool is a fraction of currentPrizePool which fits uint128 | SAFE / INFO |
| `_setPendingPools` L708 | Same packing as _setPrizePools | uint128 inputs | uint256 packed | Widening -- always safe | SAFE |

All uint128 narrowings are confirmed safe by Phase 214 (214-02: pool values cannot exceed total ETH supply of ~1.2e8 ETH = 1.2e26 wei, far below uint128 max of ~3.4e38).

---

## Section 4: SSTORE Verdict Summary

### Master Table

| # | Contract | Function | Line(s) | Variable | Direction | Guard | Verdict |
|---|----------|----------|---------|----------|-----------|-------|---------|
| 1 | AdvanceModule | _consolidatePoolsAndRewardJackpots | 790 | prizePoolsPacked | SET | Memory batch writeback | SAFE |
| 2 | AdvanceModule | _consolidatePoolsAndRewardJackpots | 791 | currentPrizePool | SET | Memory batch writeback | SAFE |
| 3 | AdvanceModule | _consolidatePoolsAndRewardJackpots | 792 | yieldAccumulator | SET | Memory batch writeback | SAFE |
| 4 | AdvanceModule | _consolidatePoolsAndRewardJackpots | 794 | claimablePool | INCREASE | claimableDelta != 0 guard | SAFE |
| 5 | AdvanceModule | advanceGame | 373 | levelPrizePool[purchaseLevel] | SET | Snapshot before consolidation | SAFE |
| 6 | AdvanceModule | _endPhase | 535 | levelPrizePool[lvl] | SET | x00 levels only | SAFE |
| 7 | JackpotModule | distributeYieldSurplus | 747 | claimablePool | INCREASE | Sum of _addClaimableEth returns | SAFE |
| 8 | JackpotModule | distributeYieldSurplus | 748 | yieldAccumulator | INCREASE | quarterShare of surplus | SAFE |
| 9 | JackpotModule | payDailyJackpot (JP) | 378-379 | currentPrizePool | DECREASE | Ticket budget deduction | SAFE |
| 10 | JackpotModule | payDailyJackpot (JP) | 381 | prizePoolsPacked (next) | INCREASE | Matches currentPrizePool deduction | SAFE |
| 11 | JackpotModule | payDailyJackpot (JP) | 405 | prizePoolsPacked (future) | DECREASE | 0.5% carryover slice | SAFE |
| 12 | JackpotModule | payDailyJackpot (JP) | 406 | prizePoolsPacked (next) | INCREASE | Matches carryover deduction | SAFE |
| 13 | JackpotModule | payDailyJackpot (JP) | 476-477 | currentPrizePool | DECREASE | Final day full budget | SAFE |
| 14 | JackpotModule | payDailyJackpot (JP) | 479-482 | prizePoolsPacked (future) | INCREASE | Unpaid ETH refund | SAFE |
| 15 | JackpotModule | payDailyJackpot (JP) | 485 | currentPrizePool | DECREASE | Non-final day paid amount | SAFE |
| 16 | JackpotModule | payDailyJackpot (PP) | 522-524 | prizePoolsPacked (future) | DECREASE | Deferred deduction | SAFE |
| 17 | JackpotModule | _resumeDailyEth | 1151 | prizePoolsPacked (future) | DECREASE | Call 2 final-day paid | SAFE |
| 18 | JackpotModule | _resumeDailyEth | 1153 | currentPrizePool | DECREASE | Call 2 non-final-day paid | SAFE |
| 19 | JackpotModule | _processDailyEth | 1195 | resumeEthPool | SET/CLEAR | SPLIT_CALL2 read-then-clear | SAFE |
| 20 | JackpotModule | _processDailyEth | 1285 | claimablePool | INCREASE | Liability sum across buckets | SAFE |
| 21 | JackpotModule | _processDailyEth | 1290 | resumeEthPool | SET | SPLIT_CALL1 carry | SAFE |
| 22 | JackpotModule | _processSoloBucketWinner | 1520 | whalePassClaims | INCREASE | Deferred ticket | SAFE |
| 23 | JackpotModule | _processSoloBucketWinner | 1521 | prizePoolsPacked (future) | INCREASE | Whale pass cost | SAFE |
| 24 | JackpotModule | _runEarlyBirdLootboxJackpot | 641 | prizePoolsPacked (future) | DECREASE | 3% reserve | SAFE |
| 25 | JackpotModule | _runEarlyBirdLootboxJackpot | 709 | prizePoolsPacked (next) | INCREASE | Budget to next | SAFE |
| 26 | JackpotModule | _distributeLootboxAndTickets | 861 | prizePoolsPacked (next) | INCREASE | Lootbox to next | SAFE |
| 27 | JackpotModule | _processAutoRebuy | 824 | prizePoolsPacked (future) | INCREASE | Rebuy ethSpent | SAFE |
| 28 | JackpotModule | _processAutoRebuy | 826 | prizePoolsPacked (next) | INCREASE | Rebuy ethSpent | SAFE |
| 29 | DecimatorModule | claimDecimatorJackpot | 316 | claimableWinnings | INCREASE | gameOver path | SAFE |
| 30 | DecimatorModule | _creditDecJackpotClaimCore | 363 | claimableWinnings | INCREASE | ethPortion (half) | SAFE |
| 31 | DecimatorModule | _creditDecJackpotClaimCore | 366 | claimablePool | DECREASE | lootboxPortion | SAFE |
| 32 | DecimatorModule | claimDecimatorJackpot | 326 | prizePoolsPacked (future) | INCREASE | Lootbox recycled | SAFE |
| 33 | DecimatorModule | claimTerminalDecimatorJackpot | 782 | claimableWinnings | INCREASE | Pro-rata terminal claim | SAFE |
| 34 | DegeneretteModule | _collectBetFunds | 524 | claimableWinnings | DECREASE | Shortfall from claimable | SAFE |
| 35 | DegeneretteModule | _collectBetFunds | 525 | claimablePool | DECREASE | Matches claimableWinnings | SAFE |
| 36 | DegeneretteModule | _collectBetFunds | 531 | prizePoolPendingPacked | INCREASE | Bet to pending future | SAFE |
| 37 | DegeneretteModule | _collectBetFunds | 533-534 | prizePoolsPacked | INCREASE | Bet to live future | SAFE |
| 38 | DegeneretteModule | _distributePayout | 710 | prizePoolPendingPacked | DECREASE | Frozen payout deduction | SAFE |
| 39 | DegeneretteModule | _distributePayout | 727 | prizePoolsPacked (future) | DECREASE | Unfrozen payout deduction | SAFE |
| 40 | DegeneretteModule | _addClaimableEth | 1092 | claimablePool | INCREASE | Bet winnings credit | SAFE |
| 41 | DegeneretteModule | _addClaimableEth | 1093 | claimableWinnings | INCREASE | Via _creditClaimable | SAFE |
| 42 | MintModule/Game | recordMint | 369-370 | prizePoolPendingPacked | INCREASE | Ticket purchase (frozen) | SAFE |
| 43 | MintModule/Game | recordMint | 375-378 | prizePoolsPacked | INCREASE | Ticket purchase (unfrozen) | SAFE |
| 44 | MintModule | _purchaseFor | 1057-1061 | prizePoolPendingPacked | INCREASE | Lootbox split (frozen) | SAFE |
| 45 | MintModule | _purchaseFor | 1063-1067 | prizePoolsPacked | INCREASE | Lootbox split (unfrozen) | SAFE |
| 46 | MintModule | _purchaseFor | 951 | claimableWinnings | DECREASE | Lootbox claimable shortfall | SAFE |
| 47 | MintModule | _purchaseFor | 953 | claimablePool | DECREASE | Matches claimableWinnings | SAFE |
| 48 | Game.sol | _processMintPayment | 923 | claimableWinnings | DECREASE | Claimable payKind | SAFE |
| 49 | Game.sol | _processMintPayment | 941 | claimableWinnings | DECREASE | Combined payKind | SAFE |
| 50 | Game.sol | _processMintPayment | 953 | claimablePool | DECREASE | Matches claimableUsed | SAFE |
| 51 | WhaleModule | _purchaseWhaleBundle | 346-350 | prizePoolPendingPacked | INCREASE | Bundle payment (frozen) | SAFE |
| 52 | WhaleModule | _purchaseWhaleBundle | 352-356 | prizePoolsPacked | INCREASE | Bundle payment (unfrozen) | SAFE |
| 53 | WhaleModule | _purchaseLazyPass | 491-496 | prizePoolPendingPacked | INCREASE | Pass payment (frozen) | SAFE |
| 54 | WhaleModule | _purchaseLazyPass | 498-502 | prizePoolsPacked | INCREASE | Pass payment (unfrozen) | SAFE |
| 55 | WhaleModule | _purchaseDeityPass | 645-650 | prizePoolPendingPacked | INCREASE | Pass payment (frozen) | SAFE |
| 56 | WhaleModule | _purchaseDeityPass | 652-655 | prizePoolsPacked | INCREASE | Pass payment (unfrozen) | SAFE |
| 57 | GameOverModule | handleGameOverDrain | 119 | claimableWinnings | INCREASE | Deity pass refunds | SAFE |
| 58 | GameOverModule | handleGameOverDrain | 131 | claimablePool | INCREASE | Matches deity refunds | SAFE |
| 59 | GameOverModule | handleGameOverDrain | 144 | prizePoolsPacked (next) | SET 0 | Terminal drain | SAFE |
| 60 | GameOverModule | handleGameOverDrain | 145 | prizePoolsPacked (future) | SET 0 | Terminal drain | SAFE |
| 61 | GameOverModule | handleGameOverDrain | 146 | currentPrizePool | SET 0 | Terminal drain | SAFE |
| 62 | GameOverModule | handleGameOverDrain | 147 | yieldAccumulator | SET 0 | Terminal drain | SAFE |
| 63 | GameOverModule | handleGameOverDrain | 165 | claimablePool | INCREASE | Terminal decimator spend | SAFE |
| 64 | GameOverModule | handleFinalSweep | 194 | claimablePool | SET 0 | 30-day post-gameover | SAFE |
| 65 | Game.sol | _claimWinningsInternal | 1372 | claimableWinnings | SET | Sentinel (1 wei) | SAFE |
| 66 | Game.sol | _claimWinningsInternal | 1375 | claimablePool | DECREASE | Payout amount | SAFE |
| 67 | Game.sol | constructor | 220 | levelPrizePool[0] | SET | Bootstrap initialization | SAFE |
| 68 | PayoutUtils | _creditClaimable | 36 | claimableWinnings | INCREASE | Credit leaf function | SAFE |
| 69 | PayoutUtils | _queueWhalePassClaimCore | 100 | claimableWinnings | INCREASE | Sub-half-pass dust | SAFE |
| 70 | PayoutUtils | _queueWhalePassClaimCore | 102 | claimablePool | INCREASE | Matches dust credit | SAFE |
| 71 | Storage | _unfreezePool | 774 | prizePoolsPacked | INCREASE | Merge pending into live | SAFE |
| 72 | Storage | _unfreezePool | 775 | prizePoolPendingPacked | SET 0 | Clear pending | SAFE |
| 73 | Storage | _swapAndFreeze | 764 | prizePoolPendingPacked | SET 0 | Clear pending on freeze start | SAFE |
| 74 | JackpotModule | _addClaimableEth.claimableWinnings | 786 | claimableWinnings | INCREASE | Via _creditClaimable | SAFE |
| 75 | JackpotModule | runBafJackpot (via _addClaimableEth) | 2007-2044 | claimableWinnings | INCREASE | BAF winner credits | SAFE |

### Counts

| Category | Count |
|----------|-------|
| **Total SSTORE sites** | **75** |
| **SAFE** | **75** |
| **VULNERABLE** | **0** |
| **INFO** (uint128 narrowing, noted in sections) | **5** (lines 821, 794, 1290, all claimablePool casts, setPendingPools) |

All 5 INFO items are uint128 narrowings that are proven safe by Phase 214 (214-02): maximum possible pool value is bounded by total ETH supply (~1.2e8 ETH = 1.2e26 wei) which is far below uint128 max (~3.4e38). These are observations, not vulnerabilities.

### Threat Register Dispositions

| Threat ID | Disposition | Evidence |
|-----------|------------|---------|
| T-216-05 (prizePoolsPacked packing) | MITIGATED | Section 2.1: `_setPrizePools` correctly packs next in [127:0] and future in [255:128] with no overlap. 214-03 confirms zero state corruption. |
| T-216-06 (currentPrizePool uint128 narrowing) | MITIGATED | Section 3.3: 214-02 proves max pool value << uint128 max with 10^12x margin. |
| T-216-07 (claimablePool += without matching deduction) | MITIGATED | Every claimablePool increase across all 75 sites has a corresponding pool deduction or was pre-reserved (decimator snapshots, gameover drain). Detailed per-section T-216-07 checks confirm conservation. |
| T-216-08 (intermediary variables not written back) | MITIGATED | Section 3.1: All 5 memory locals in _consolidatePoolsAndRewardJackpots are written back at lines 790-795. No intermediate value is lost. |

---

**Phase 214 citations (per D-02):**
- 214-02 (Access Control + Integer Overflow): uint128 narrowing safety for currentPrizePool, claimablePool, resumeEthPool -- all proven SAFE with 10^12x margin
- 214-03 (State Composition): packed pool field integrity -- zero state corruption; memory-batch writeback pattern verified safe; auto-rebuy pool writes during self-calls are by design
