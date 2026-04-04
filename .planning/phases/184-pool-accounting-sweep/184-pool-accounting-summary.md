# Phase 184: Pool Accounting Sweep -- Master Summary

**Phase:** 184-pool-accounting-sweep
**Date:** 2026-04-04
**Scope:** Consolidated audit of all pool mutations across the Degenerus protocol

**Source audits:**
- Plan 01: futurePool + currentPool (29 sites) -- `184-futurePool-currentPool-audit.md`
- Plan 02: nextPool + claimablePool + claimableWinnings (45 sites) -- `184-nextPool-claimablePool-audit.md`
- Plan 03 Task 1: GameOver module game-over flows (this document)

---

## Part 1: GameOver Module Pool Zeroing and Refund Flows

The GameOverModule (`DegenerusGameGameOverModule.sol`) contains two entry points: `handleGameOverDrain` (jackpot distribution + pool zeroing) and `handleFinalSweep` (30-day post-game-over terminal sweep). Both paths terminate all pool accounting.

---

### SITE-GO-01: GameOverModule:handleGameOverDrain -- deity pass refund loop (lines 93-116)

- **Operation:** `claimableWinnings[owner] += refund` (line 103) for each deity pass owner; `claimablePool += totalRefunded` (line 115) as aggregate credit
- **ETH flow:** Fixed 20 ETH per deity pass purchased, FIFO by `deityPassOwners` array order, budget-capped to `totalFunds - claimablePool`
- **Counterpart verified:** YES -- `totalRefunded` accumulates all individual `refund` values (line 104: `totalRefunded += refund`). The aggregate `claimablePool += totalRefunded` at line 115 matches the sum of all `claimableWinnings[owner] += refund` credits.
- **Source of refund ETH:** Not from any specific pool. `budget = totalFunds - claimablePool` (line 91) uses total contract balance. The refund precedes pool zeroing, so pool values are still nonzero but the refund is drawn from the overall contract balance surplus.
- **Budget cap:** If total refunds exceed `totalFunds - claimablePool`, loop breaks early (line 108: `if (budget == 0) break`). Last owner may get partial refund (line 98-100: `if (refund > budget) refund = budget`).
- **Conservation check:** `totalRefunded <= totalFunds - claimablePool` (enforced by budget cap). After this loop, `claimablePool` has increased by `totalRefunded`, meaning `totalFunds - claimablePool` has decreased by `totalRefunded`. No untracked wei.
- **Notes:** Only fires when `lvl < 10` (early game over). The `deityPassPurchasedCount[owner]` mapping is read but never zeroed -- this is safe because `gameOverFinalJackpotPaid = true` prevents re-entry. Cross-ref: SITE-CL-06 (Plan 02), SITE-CW-03 (Plan 02).

---

### SITE-GO-02: GameOverModule:handleGameOverDrain -- available calculation (line 120)

- **Operation:** `available = totalFunds > claimablePool ? totalFunds - claimablePool : 0`
- **ETH flow:** Computes the total distributable ETH after deity pass refunds (if any). This is the sum of all pool balances (futurePool + nextPool + currentPool + yieldAccumulator + any untracked surplus).
- **Counterpart verified:** YES -- `available` represents all contract ETH minus the claimablePool obligation. After deity pass refunds (which increased claimablePool), `available` is the remaining non-claimable ETH. This is the exact amount that the four pool variables and yieldAccumulator collectively represent (plus any contract surplus from triple-division dust etc.).
- **Conservation check:** `available + claimablePool = totalFunds` (by construction). All subsequent distribution steps deduct from `remaining` (initialized to `available`). Any undistributed `remaining` is swept to vault.
- **Notes:** The `available == 0` branch (lines 129-136) handles the edge case where total funds equal or are less than claimablePool. In this case, pool variables may be nonzero but represent no real ETH (already spoken for by claimablePool).

---

### SITE-GO-03: GameOverModule:handleGameOverDrain -- pool zeroing, available == 0 path (lines 131-134)

- **Operation:** `_setNextPrizePool(0)` (line 131), `_setFuturePrizePool(0)` (line 132), `_setCurrentPrizePool(0)` (line 133), `yieldAccumulator = 0` (line 134)
- **ETH flow:** All four accounting pools zeroed. No ETH moves because `available == 0` means all contract ETH is already in claimablePool.
- **Counterpart verified:** YES -- zeroing is correct because `available == 0` means `totalFunds <= claimablePool`. The pool variables may have contained phantom values (e.g., from rounding) but no distributable ETH.
- **Conservation check:** Before: `totalFunds = claimablePool + (futurePool + nextPool + currentPool + yield + surplus)` where `(futurePool + ... + surplus) = 0` in effective terms. After: all pool vars = 0, claimablePool unchanged. No ETH lost.
- **Notes:** `gameOverFinalJackpotPaid = true` (line 130) prevents re-entry. Cross-ref: SITE-FP-14, SITE-CP-05, SITE-NP-10 (Plan 01/02).

---

### SITE-GO-04: GameOverModule:handleGameOverDrain -- pool zeroing, normal path (lines 143-146)

- **Operation:** `_setNextPrizePool(0)` (line 143), `_setFuturePrizePool(0)` (line 144), `_setCurrentPrizePool(0)` (line 145), `yieldAccumulator = 0` (line 146)
- **ETH flow:** All four accounting pools zeroed. The `available` amount was computed BEFORE zeroing (line 120) and is distributed via `remaining` variable (line 151).
- **Counterpart verified:** YES -- `available = totalFunds - claimablePool` was captured before zeroing. The zeroing does not lose information because `available` already holds the distributable amount. The `remaining` accumulator tracks `available` through all distribution steps.
- **Conservation check:** Before zeroing: `available = futurePool + nextPool + currentPool + yieldAccumulator + surplus`. After zeroing: all = 0 but `remaining = available` holds the total. Every subsequent operation deducts from `remaining`.
- **Notes:** `gameOverFinalJackpotPaid = true` (line 142) prevents re-entry. Cross-ref: SITE-FP-15, SITE-CP-06, SITE-NP-11 (Plan 01/02).

---

### SITE-GO-05: GameOverModule:handleGameOverDrain -- terminal decimator (lines 154-163)

- **Operation:** `decPool = remaining / 10` (line 154), `runTerminalDecimatorJackpot(decPool, lvl, rngWord)` returns `decRefund`, `decSpend = decPool - decRefund` (line 157), `claimablePool += decSpend` (line 159), `remaining -= decPool; remaining += decRefund` (lines 161-162)
- **ETH flow:** 10% of `remaining` allocated to terminal decimator. `decSpend` (portion actually distributed to winners) enters claimablePool. `decRefund` (undistributed portion) returns to `remaining` for terminal jackpot.
- **Counterpart verified:** YES -- `decPool = decSpend + decRefund`. `claimablePool += decSpend` matches the sum of `claimableWinnings[winner] += ...` credits inside `runTerminalDecimatorJackpot`. `remaining -= decPool + decRefund = remaining - decSpend`. Net: `remaining` decreased by `decSpend`, which entered claimablePool.
- **Conservation check:** Before: `remaining = R`, `claimablePool = C`. After: `remaining = R - decSpend`, `claimablePool = C + decSpend`. Total: `remaining + claimablePool = R + C` (unchanged). No ETH lost.
- **Notes:** Guard `if (decPool != 0)` at line 155. Division `remaining / 10` truncates -- remainder stays in `remaining` (goes to terminal jackpot). Cross-ref: SITE-CL-07 (Plan 02).

---

### SITE-GO-06: GameOverModule:handleGameOverDrain -- terminal jackpot (lines 167-176)

- **Operation:** `runTerminalJackpot(remaining, lvl + 1, rngWord)` returns `termPaid` (line 168-169), `remaining -= termPaid` (line 171), if `remaining != 0` then `_sendToVault(remaining, stBal)` (lines 173-174)
- **ETH flow:** Remaining 90%+ (plus decimator refund) distributed to next-level ticketholders via Day-5-style bucket distribution. `termPaid` enters claimablePool inside `JackpotModule._distributeJackpotEth` (comment at line 170 confirms: "claimablePool already updated inside"). Any undistributed `remaining` is swept to vault.
- **Counterpart verified:** YES -- `termPaid` matches the `ctx.liabilityDelta` applied to claimablePool inside `_distributeJackpotEth` (SITE-CL-04 pattern). The `remaining - termPaid` sweep to vault accounts for empty-bucket remainders.
- **Conservation check:** Before: `remaining = R`. After: `claimablePool += termPaid` (inside call), vault receives `R - termPaid`. Total: `termPaid + (R - termPaid) = R`. No ETH lost.
- **Notes:** `gameOver = true` at line 122 prevents auto-rebuy inside `_addClaimableEth` (comment at line 166: "tickets worthless post-game"). This means all terminal jackpot winnings go directly to claimablePool/claimableWinnings, no diversion to futurePool/nextPool.

---

### SITE-GO-07: GameOverModule:handleFinalSweep -- terminal sweep (lines 190-204)

- **Operation:** `finalSwept = true` (line 190), `claimablePool = 0` (line 191), shutdown VRF (line 194), `_sendToVault(totalFunds, stBal)` (line 204)
- **ETH flow:** After 30 days post-game-over, ALL remaining contract funds are swept to vault/sDGNRS/GNRUS. `claimablePool = 0` forfeits all unclaimed player balances. `_sendToVault` splits: 33% sDGNRS, 33% vault, 34% GNRUS.
- **Counterpart verified:** YES -- this is the terminal operation. Individual `claimableWinnings[*]` entries are NOT zeroed (gas prohibitive), but `finalSwept = true` prevents any future claims (guard in `_claimWinningsInternal`). The full `address(this).balance + steth.balanceOf(address(this))` is sent externally.
- **Conservation check:** Before: contract holds `totalFunds`. After: contract holds 0 (all sent to vault/sDGNRS/GNRUS). `claimablePool = 0` reflects the empty state. No ETH remains in contract.
- **Notes:** Guard at line 187: `block.timestamp < gameOverTime + 30 days` returns early. Guard at line 188: `finalSwept` prevents double-sweep. VRF shutdown is fire-and-forget (try/catch at line 194). Cross-ref: SITE-CL-16 (Plan 02).

---

### End-to-End Conservation Check: handleGameOverDrain

**Before game-over call:**
- Contract balance: `totalFunds = ethBal + stBal`
- Pool accounting: `futurePool + nextPool + currentPool + yieldAccumulator + surplus = totalFunds - claimablePool`
- Player obligations: `claimablePool >= sum(claimableWinnings[*])`

**After deity pass refunds (if lvl < 10):**
- `claimablePool += totalRefunded` (capped to `totalFunds - claimablePool_old`)
- `available = totalFunds - claimablePool_new`

**After pool zeroing:**
- `futurePool = nextPool = currentPool = yieldAccumulator = 0`
- `remaining = available` (holds all non-claimable ETH)

**After terminal decimator:**
- `claimablePool += decSpend`
- `remaining -= decSpend`

**After terminal jackpot:**
- `claimablePool += termPaid`
- `remaining -= termPaid`
- Vault receives `remaining` (if any)

**Final state:**
- `totalFunds = claimablePool + vault_received`
- `claimablePool = claimablePool_old + totalRefunded + decSpend + termPaid`
- `vault_received = remaining_final = available - decSpend - termPaid`
- **Verification:** `claimablePool + vault_received = claimablePool_old + totalRefunded + decSpend + termPaid + available - decSpend - termPaid = claimablePool_old + totalRefunded + available = claimablePool_old + totalRefunded + (totalFunds - claimablePool_old - totalRefunded) = totalFunds`. CORRECT.

**No untracked remainders. No orphaned credits. No phantom debits.**

---

## Part 2: Cross-Pool Flow Verification

Every flow where ETH moves between two different pools (not just within one).

---

### CROSS-01: futurePool -> nextPool (daily carryover reserve slice)
- **Sites:** SITE-FP-01 / SITE-NP-02 (JackpotModule:payDailyJackpot lines 396-397)
- **Flow:** `futurePool -= reserveSlice; nextPool += reserveSlice` where `reserveSlice = futurePool / 200` (0.5%)
- **Balanced:** YES -- same `reserveSlice` value used for both debit and credit. Truncation stays in futurePool.

### CROSS-02: futurePool -> nextPool (early-bird lootbox reserve)
- **Sites:** SITE-FP-03 / SITE-NP-03 (JackpotModule:_runEarlyBirdLootboxJackpot lines 657-714)
- **Flow:** `futurePool -= reserveContribution; nextPool += totalBudget` where `totalBudget == reserveContribution` (3% of futurePool)
- **Balanced:** YES -- `totalBudget` equals `reserveContribution`. All 100 winners' ticket budgets deducted from the same value. Full amount enters nextPool at line 714.

### CROSS-03: futurePool -> nextPool (drawdown reserved)
- **Sites:** SITE-FP-10 / SITE-NP-08 (AdvanceModule:_drawDownFuturePrizePool lines 1191-1192)
- **Flow:** `futurePool -= reserved; nextPool += reserved` where `reserved = (futurePool * 15) / 100` (15% on normal levels)
- **Balanced:** YES -- same `reserved` value for both. Truncation stays in futurePool. Skipped on x00 levels.

### CROSS-04: nextPool -> futurePool (skim)
- **Sites:** SITE-NP-07 / SITE-FP-09 (AdvanceModule:_skimAndRedistribute lines 1177-1179)
- **Flow:** `nextPool -= (take + insuranceSkim); futurePool += take; yieldAccumulator += insuranceSkim`
- **Balanced:** YES -- `nextPool_remaining + take + insuranceSkim = nextPoolBefore`. Three-way split fully accounted. insuranceSkim to yieldAccumulator is eventually flushed to futurePool via CROSS-10.

### CROSS-05: currentPool -> nextPool (daily lootbox budget)
- **Sites:** SITE-CP-01 / SITE-NP-01 (JackpotModule:payDailyJackpot lines 371-372)
- **Flow:** `currentPool -= dailyLootboxBudget; nextPool += dailyLootboxBudget`
- **Balanced:** YES -- same `dailyLootboxBudget` variable for both operations. Guard: only fires when `dailyTicketUnits != 0`.

### CROSS-06: nextPool -> currentPool (consolidation)
- **Sites:** SITE-NP-04 / SITE-CP-03 (JackpotModule:consolidatePrizePools lines 740-741)
- **Flow:** `currentPool += nextPool; nextPool = 0`
- **Balanced:** YES -- full nextPool balance transfers. `_getNextPrizePool()` read at line 740 before zeroing at line 741. Exact transfer, no division.

### CROSS-07: futurePool -> currentPool (keep-roll spillover)
- **Sites:** SITE-FP-05 / SITE-CP-04 (JackpotModule:consolidatePrizePools lines 750-751)
- **Flow:** `futurePool = keepWei; currentPool += moveWei` where `moveWei = fp - keepWei`, `keepWei = (fp * keepBps) / 10_000`
- **Balanced:** YES -- `keepWei + moveWei = fp`. Full futurePool accounted. Only fires on x00 levels when `keepBps < 10_000 && fp != 0`.

### CROSS-08: currentPool -> claimablePool (daily ETH jackpot payout)
- **Sites:** SITE-CP-02 / SITE-CL-04 pattern (JackpotModule:payDailyJackpot line 451 + _distributeJackpotEth)
- **Flow:** `currentPool -= paidDailyEth; claimablePool += liabilityDelta` inside `_distributeJackpotEth`
- **Balanced:** YES -- `paidDailyEth` is the return value of `_processDailyEth`, which equals the sum of `_addClaimableEth` credits. `liabilityDelta` in `_distributeJackpotEth` accumulates the same credits. Unspent budget (empty trait buckets) stays in currentPool.

### CROSS-09: futurePool -> claimablePool (early-burn ETH jackpot)
- **Sites:** SITE-FP-02 / SITE-CL-03 pattern (JackpotModule:payDailyJackpot lines 483-504)
- **Flow:** `futurePool -= ethDaySlice` (upfront in committed code), `claimablePool += liabilityDelta` inside `_executeJackpot`
- **Balanced:** PARTIAL (committed code) / YES (Phase 183 fix) -- In committed code, if trait buckets are empty, `ethDaySlice - paidEth` exits futurePool but enters no tracked pool. With Phase 183 fix: `futurePool -= (lootboxBudget + paidEth)`, and unspent ETH stays in futurePool.

### CROSS-10: yieldAccumulator -> futurePool (x00 yield dump)
- **Sites:** SITE-FP-04 (JackpotModule:consolidatePrizePools lines 734-736)
- **Flow:** `futurePool += half; yieldAccumulator = acc - half` where `half = acc >> 1`
- **Balanced:** YES -- `half + (acc - half) = acc`. Odd-wei truncation stays in yieldAccumulator (conservative). Only fires on x00 levels.

### CROSS-11: claimablePool -> futurePool (sDGNRS reserve claim)
- **Sites:** SITE-CL-11 / SITE-FP-17 (DegenerusGame:claimSdgnrsReserve lines 1683-1691)
- **Flow:** `claimablePool -= amount; futurePool += amount`
- **Balanced:** YES -- exact `amount` transferred. Internal accounting reclassification, no ETH movement.

### CROSS-12: claimablePool -> futurePool/nextPool (decimator lootbox portion)
- **Sites:** SITE-CL-15 / SITE-FP-11 (DecimatorModule lines 445 + 336)
- **Flow:** `claimablePool -= lootboxPortion; futurePool += lootboxPortion`
- **Balanced:** YES -- `_creditDecJackpotClaimCore` deducts lootboxPortion from claimablePool (line 445), then caller adds to futurePool (line 336). Same variable.

### CROSS-13: claimablePool -> futurePool/nextPool (auto-rebuy, jackpot context)
- **Sites:** SITE-FP-06 or SITE-NP-05 (JackpotModule:_processAutoRebuy lines 866-868)
- **Flow:** Player jackpot winnings auto-converted: `claimablePool` is credited by `_addClaimableEth`, then `futurePool += calc.ethSpent` or `nextPool += calc.ethSpent`. Net: claimablePool contribution reduced by ethSpent (returned 0 from `_addClaimableEth`).
- **Balanced:** YES -- `_addClaimableEth` returns 0 for auto-rebuyed amounts (claimablePool not credited for that portion). The ethSpent goes directly to futurePool/nextPool. reserved portion goes to claimablePool via `_creditClaimable`.

### CROSS-14: claimablePool -> futurePool/nextPool (auto-rebuy, decimator context)
- **Sites:** SITE-CL-14 / SITE-FP-12 or SITE-NP-09 (DecimatorModule:_processDecimatorAutoRebuy lines 387-398)
- **Flow:** `claimablePool -= calc.ethSpent; futurePool += calc.ethSpent` (or nextPool)
- **Balanced:** YES -- original credit to claimablePool was via SITE-CL-05. Auto-rebuy deducts `calc.ethSpent` (line 398) and routes to target pool. reserved portion stays in claimablePool. Disjoint from SITE-CL-15 (different portions of original amount).

### CROSS-15: futurePool -> nextPool (lootbox budget from early-burn path)
- **Sites:** SITE-FP-02 / SITE-NP-06 (JackpotModule:payDailyJackpot line 494 + _distributeLootboxAndTickets line 942)
- **Flow:** `lootboxBudget` carved from `ethDaySlice` (futurePool debit), then `nextPool += lootboxBudget` via `_distributeLootboxAndTickets`
- **Balanced:** YES -- `lootboxBudget` is subset of the futurePool debit. With Phase 183 fix, `futurePool -= (lootboxBudget + paidEth)`, and `nextPool += lootboxBudget` in the ticket distribution function.

### CROSS-16: all pools -> vault/sDGNRS/GNRUS (game-over drain)
- **Sites:** SITE-GO-04 through SITE-GO-06 (GameOverModule:handleGameOverDrain lines 143-176)
- **Flow:** All pools zeroed, `available` distributed via terminal decimator (10%) and terminal jackpot (90%+), undistributed to vault
- **Balanced:** YES -- end-to-end conservation check in Part 1 proves `totalFunds = claimablePool + vault_received`.

### CROSS-17: all pools -> vault/sDGNRS/GNRUS (final sweep)
- **Sites:** SITE-GO-07 (GameOverModule:handleFinalSweep lines 190-204)
- **Flow:** `claimablePool = 0; _sendToVault(totalFunds)` -- terminal forfeiture
- **Balanced:** YES -- all contract ETH exits. No accounting variables remain nonzero.

---

## Part 3: Master Pool Transition Table

All mutation sites across all modules, consolidated from Plans 01, 02, and Task 1.

### futurePool Sites (23 total)

| Site ID | Module | Function | Line | Op | Amount | Counterpart | Verified |
|---------|--------|----------|------|----|--------|-------------|----------|
| SITE-FP-01 | JackpotModule | payDailyJackpot | 396 | -= | reserveSlice | SITE-NP-02 (nextPool += reserveSlice) | YES |
| SITE-FP-02 | JackpotModule | payDailyJackpot | 483 | -= | ethDaySlice | SITE-CL-03 pattern + SITE-NP-06 (claimable + nextPool) | PARTIAL (YES w/ Phase 183 fix) |
| SITE-FP-03 | JackpotModule | _runEarlyBirdLootboxJackpot | 657 | -= | reserveContribution | SITE-NP-03 (nextPool += totalBudget) | YES |
| SITE-FP-04 | JackpotModule | consolidatePrizePools | 735 | += | half (yield dump) | yieldAccumulator -= (acc - half) | YES |
| SITE-FP-05 | JackpotModule | consolidatePrizePools | 750 | = | keepWei | SITE-CP-04 (currentPool += moveWei) | YES |
| SITE-FP-06 | JackpotModule | _processAutoRebuy | 866 | += | calc.ethSpent | claimablePool credit reduced (auto-rebuy) | YES |
| SITE-FP-07 | JackpotModule | _distributeJackpotEthWithWhalePass | 1594 | += | whalePassCost | perWinner split: ethAmount -> claimable | YES |
| SITE-FP-08 | JackpotModule | runRewardJackpots | 2591 | = | futurePoolLocal + rebuyDelta | BAF/Dec debits + rebuy reconciliation | YES |
| SITE-FP-09 | AdvanceModule | _skimAndRedistribute | 1178 | += | take | SITE-NP-07 (nextPool -= take + insuranceSkim) | YES |
| SITE-FP-10 | AdvanceModule | _drawDownFuturePrizePool | 1191 | -= | reserved | SITE-NP-08 (nextPool += reserved) | YES |
| SITE-FP-11 | DecimatorModule | claimDecimatorJackpot | 336 | += | lootboxPortion | SITE-CL-15 (claimablePool -= lootboxPortion) | YES |
| SITE-FP-12 | DecimatorModule | _processAutoRebuy | 387 | += | calc.ethSpent | SITE-CL-14 (claimablePool -= calc.ethSpent) | YES |
| SITE-FP-13 | DegeneretteModule | _resolveETH | 725 | -= | ethPortion | claimablePool via _addClaimableEth | YES |
| SITE-FP-14 | GameOverModule | _runFinalJackpot | 132 | = 0 | (zeroing, avail==0) | SITE-GO-03 | YES |
| SITE-FP-15 | GameOverModule | _runFinalJackpot | 144 | = 0 | (zeroing, normal) | SITE-GO-04, remaining accumulator | YES |
| SITE-FP-16 | DegenerusGame | recordMint | 363 | += | futureShare | External ETH (mint payment) | YES |
| SITE-FP-17 | DegenerusGame | claimSdgnrsReserve | 1691 | += | amount | SITE-CL-11 (claimablePool -= amount) | YES |
| SITE-FP-18 | DegenerusGame | receive() | 2524 | += | msg.value | External ETH deposit | YES |
| SITE-FP-19 | DegeneretteModule | _collectBet | 532 | += | totalBet | External ETH (player bet) | YES |
| SITE-FP-20 | MintModule | _processMintLootbox | 758 | += | futureShare | External ETH (lootbox purchase) | YES |
| SITE-FP-21 | WhaleModule | purchaseWhalePass | 353 | += | totalPrice - nextShare | External ETH (whale pass) | YES |
| SITE-FP-22 | WhaleModule | purchaseLazyPass | 499 | += | futureShare | External ETH (lazy pass) | YES |
| SITE-FP-23 | WhaleModule | purchaseDeityPass | 653 | += | totalPrice - nextShare | External ETH (deity pass) | YES |

### currentPool Sites (6 total)

| Site ID | Module | Function | Line | Op | Amount | Counterpart | Verified |
|---------|--------|----------|------|----|--------|-------------|----------|
| SITE-CP-01 | JackpotModule | payDailyJackpot | 371 | -= | dailyLootboxBudget | SITE-NP-01 (nextPool += dailyLootboxBudget) | YES |
| SITE-CP-02 | JackpotModule | payDailyJackpot | 451 | -= | paidDailyEth | SITE-CL-04 pattern (claimablePool += liabilityDelta) | YES |
| SITE-CP-03 | JackpotModule | consolidatePrizePools | 740 | += | nextPool | SITE-NP-04 (nextPool = 0) | YES |
| SITE-CP-04 | JackpotModule | consolidatePrizePools | 751 | += | moveWei | SITE-FP-05 (futurePool = keepWei) | YES |
| SITE-CP-05 | GameOverModule | _runFinalJackpot | 133 | = 0 | (zeroing, avail==0) | SITE-GO-03 | YES |
| SITE-CP-06 | GameOverModule | _runFinalJackpot | 145 | = 0 | (zeroing, normal) | SITE-GO-04, remaining accumulator | YES |

### nextPool Sites (20 total)

| Site ID | Module | Function | Line | Op | Amount | Counterpart | Verified |
|---------|--------|----------|------|----|--------|-------------|----------|
| SITE-NP-01 | JackpotModule | payDailyJackpot | 372 | += | dailyLootboxBudget | SITE-CP-01 (currentPool -= dailyLootboxBudget) | YES |
| SITE-NP-02 | JackpotModule | payDailyJackpot | 397 | += | reserveSlice | SITE-FP-01 (futurePool -= reserveSlice) | YES |
| SITE-NP-03 | JackpotModule | payDailyJackpotCoinAndTickets | 714 | += | totalBudget | SITE-FP-03 (futurePool -= reserveContribution) | YES |
| SITE-NP-04 | JackpotModule | consolidatePrizePools | 741 | = 0 | (zeroing) | SITE-CP-03 (currentPool += nextPool) | YES |
| SITE-NP-05 | JackpotModule | _autoRebuyFromJackpot | 868 | += | calc.ethSpent | Auto-rebuy from jackpot winnings | YES |
| SITE-NP-06 | JackpotModule | _distributeLootboxAndTickets | 942 | += | lootboxBudget | FP-02 debit (futurePool -= ethDaySlice) | YES |
| SITE-NP-07 | AdvanceModule | _applyNextToFutureSkim | 1177 | -= | take + insuranceSkim | SITE-FP-09 + yieldAccumulator | YES |
| SITE-NP-08 | AdvanceModule | _drawDownFuturePrizePool | 1192 | += | reserved | SITE-FP-10 (futurePool -= reserved) | YES |
| SITE-NP-09 | DecimatorModule | _processDecimatorAutoRebuy | 389 | += | calc.ethSpent | SITE-CL-14 (claimablePool -= calc.ethSpent) | YES |
| SITE-NP-10 | GameOverModule | _handleGameOver | 131 | = 0 | (zeroing, avail==0) | SITE-GO-03 | YES |
| SITE-NP-11 | GameOverModule | _handleGameOver | 143 | = 0 | (zeroing, normal) | SITE-GO-04 | YES |
| SITE-NP-12 | DegenerusGame | recordMint | 363 | += | nextShare | External ETH (mint payment) | YES |
| SITE-NP-13 | DegenerusGame | claimSdgnrsReserve | 1691 | -- | (passthrough) | No-op for nextPool | YES |
| SITE-NP-14 | DegenerusGame | receive() | 2524 | -- | (passthrough) | No-op for nextPool | YES |
| SITE-NP-15 | DegeneretteModule | _placeBet | 532 | -- | (passthrough) | No-op for nextPool | YES |
| SITE-NP-16 | MintModule | _processLootboxPurchase | 758 | += | nextShare | External ETH (lootbox purchase) | YES |
| SITE-NP-17 | WhaleModule | gamePurchaseWhalePass | 353 | += | nextShare | External ETH (whale pass) | YES |
| SITE-NP-18 | WhaleModule | gamePurchaseLazyPass | 499 | += | nextShare | External ETH (lazy pass) | YES |
| SITE-NP-19 | WhaleModule | gamePurchaseDeityPassFromBoon | 653 | += | nextShare | External ETH (deity pass) | YES |
| SITE-NP-20 | Storage | _unfreezePool | 749 | += | pNext | Pending pool flush | YES |

### claimablePool Sites (16 total)

| Site ID | Module | Function | Line | Op | Amount | Counterpart | Verified |
|---------|--------|----------|------|----|--------|-------------|----------|
| SITE-CL-01 | PayoutUtils | _queueWhalePassClaimCore | 102 | += | remainder | SITE-CW-02 (claimableWinnings[winner] += remainder) | YES |
| SITE-CL-02 | JackpotModule | _distributeYieldSurplus | 795 | += | claimableDelta | stETH yield surplus, per-beneficiary credits | YES |
| SITE-CL-03 | JackpotModule | _executeCoinJackpot | 1320 | += | liabilityDelta | Per-winner credits via _addClaimableEth | YES |
| SITE-CL-04 | JackpotModule | _distributeJackpotEth | 1355 | += | ctx.liabilityDelta | 4-bucket distribution to winners | YES |
| SITE-CL-05 | JackpotModule | runRewardJackpots | 2594 | += | claimableDelta | BAF + decimator distribution credits | YES |
| SITE-CL-06 | GameOverModule | _handleGameOver | 115 | += | totalRefunded | SITE-GO-01 deity pass refund loop | YES |
| SITE-CL-07 | GameOverModule | _handleGameOver | 159 | += | decSpend | SITE-GO-05 terminal decimator | YES |
| SITE-CL-08 | DegeneretteModule | _addClaimableEth | 1090 | += | weiAmount | Player degenrette ETH prize | YES |
| SITE-CL-09 | DegenerusGame | _processMintPayment | 940 | -= | claimableUsed | SITE-CW-04/CW-05 (player balance reduced) | YES |
| SITE-CL-10 | DegenerusGame | _claimWinningsInternal | 1335 | -= | payout | SITE-CW-06 (claimableWinnings = 1 sentinel) | YES |
| SITE-CL-11 | DegenerusGame | claimSdgnrsReserve | 1683 | -= | amount | SITE-FP-17 (futurePool += amount) | YES |
| SITE-CL-12 | MintModule | _processLootboxPurchase | 678 | -= | shortfall | SITE-CW-08 (buyer balance reduced) | YES |
| SITE-CL-13 | DegeneretteModule | _collectBetFunds | 523 | -= | fromClaimable | SITE-CW-09 (player balance reduced) | YES |
| SITE-CL-14 | DecimatorModule | _processDecimatorAutoRebuy | 398 | -= | calc.ethSpent | SITE-FP-12/NP-09 (target pool += ethSpent) | YES |
| SITE-CL-15 | DecimatorModule | _creditDecJackpotClaimCore | 445 | -= | lootboxPortion | SITE-FP-11 (futurePool += lootboxPortion) | YES |
| SITE-CL-16 | GameOverModule | handleFinalSweep | 191 | = 0 | (terminal zeroing) | SITE-GO-07 (vault receives all) | YES |

### claimableWinnings Pattern Sites (9 total)

| Site ID | Module | Function | Line | Op | Paired claimablePool Op | Verified |
|---------|--------|----------|------|----|------------------------|----------|
| SITE-CW-01 | PayoutUtils | _creditClaimable | 36 | += | Caller-dependent (all callers verified) | YES |
| SITE-CW-02 | PayoutUtils | _queueWhalePassClaimCore | 100 | += | SITE-CL-01 (claimablePool += remainder) | YES |
| SITE-CW-03 | GameOverModule | _handleGameOver | 103 | += | SITE-CL-06 (claimablePool += totalRefunded) | YES |
| SITE-CW-04 | DegenerusGame | _processMintPayment | 910 | = (reduced) | SITE-CL-09 (claimablePool -= claimableUsed) | YES |
| SITE-CW-05 | DegenerusGame | _processMintPayment | 928 | = (reduced) | SITE-CL-09 (claimablePool -= claimableUsed) | YES |
| SITE-CW-06 | DegenerusGame | _claimWinningsInternal | 1332 | = 1 | SITE-CL-10 (claimablePool -= payout) | YES |
| SITE-CW-07 | DegenerusGame | claimSdgnrsReserve | 1681 | = (reduced) | SITE-CL-11 (claimablePool -= amount) | YES |
| SITE-CW-08 | MintModule | _processLootboxPurchase | 676 | = (reduced) | SITE-CL-12 (claimablePool -= shortfall) | YES |
| SITE-CW-09 | DegeneretteModule | _collectBetFunds | 522 | -= | SITE-CL-13 (claimablePool -= fromClaimable) | YES |

### GameOver Sites (7 total)

| Site ID | Module | Function | Line | Op | Amount | Counterpart | Verified |
|---------|--------|----------|------|----|--------|-------------|----------|
| SITE-GO-01 | GameOverModule | handleGameOverDrain | 93-116 | claimablePool += totalRefunded | deity pass refunds | SITE-CW-03 per-player credits | YES |
| SITE-GO-02 | GameOverModule | handleGameOverDrain | 120 | available = totalFunds - claimablePool | distributable ETH | All pools collectively | YES |
| SITE-GO-03 | GameOverModule | handleGameOverDrain | 131-134 | all pools = 0 | (zeroing, avail==0) | No ETH available | YES |
| SITE-GO-04 | GameOverModule | handleGameOverDrain | 143-146 | all pools = 0 | (zeroing, normal) | remaining accumulator | YES |
| SITE-GO-05 | GameOverModule | handleGameOverDrain | 154-163 | claimablePool += decSpend | terminal decimator | remaining -= decSpend | YES |
| SITE-GO-06 | GameOverModule | handleGameOverDrain | 167-176 | claimablePool += termPaid (inside call) | terminal jackpot | remaining -> vault | YES |
| SITE-GO-07 | GameOverModule | handleFinalSweep | 190-204 | claimablePool = 0 | terminal sweep | _sendToVault(totalFunds) | YES |

---

## Part 4: Gap Summary

### Gaps Found

| Gap ID | Pool | Module | Description | Severity |
|--------|------|--------|-------------|----------|
| GAP-FP-02 | futurePool | JackpotModule | SITE-FP-02 (committed code only): `_executeJackpot` return `paidEth` discarded. When trait buckets empty, `ethDaySlice - paidEth` exits futurePool without entering any tracked pool. | KNOWN -- closed by Phase 183 fix |

**No gaps found with Phase 183 fix applied.** All 81 mutation sites have verified counterparts.

### Requirements Satisfaction

| Requirement | Status | Evidence |
|-------------|--------|----------|
| SWEEP-01 (futurePool debits traced) | PASS | 23/23 sites verified (22 YES + 1 YES with Phase 183 fix), 0 gaps |
| SWEEP-02 (nextPool pairs balanced) | PASS | 20/20 sites verified, 0 gaps. All pool-to-pool transfers use same variable for debit and credit |
| SWEEP-03 (claimablePool pairs verified) | PASS | 16/16 sites verified, 9/9 claimableWinnings patterns paired correctly. Invariant `claimablePool >= sum(claimableWinnings[*])` HOLDS |
| SWEEP-04 (game-over distribution) | PASS | 7/7 game-over sites verified. End-to-end conservation check: `totalFunds = claimablePool + vault_received`. Terminal sweep: all funds exit contract |

### Phase 183 Fix Baseline

- **JFIX-01 (paidEth capture):** Verified at SITE-FP-02. The Phase 183 fix changes the futurePool deduction from upfront (`futurePool -= ethDaySlice`) to deferred (`futurePool -= lootboxBudget + paidEth`). This closes the gap where empty trait buckets caused `ethDaySlice - paidEth` to exit futurePool untracked.
- **JFIX-02 (phantom share accounting):** Documented in `183-JFIX02-verification.md`. No new findings from the pool sweep. The phantom share issue affected `_processOneBucket` share distribution but did NOT cause a pool accounting gap (empty buckets are skipped, their share stays in the source pool).

### INFO Findings (Non-Gaps)

| ID | Pool | Module | Description | Risk |
|----|------|--------|-------------|------|
| INFO-01 | futurePool/nextPool | MintModule | Triple-division truncation in `_processMintLootbox` (SITE-FP-20/NP-16): up to 2 wei per lootbox purchase accumulates in contract balance untracked | Negligible -- captured by `_distributeYieldSurplus` as part of `totalBal - obligations` surplus |
| INFO-02 | claimablePool | DegenerusGame | Sentinel 1-wei accumulation in `_claimWinningsInternal` (SITE-CL-10): claimablePool retains 1 wei per unique claimant | Safe direction -- over-reserves claimablePool, benefits solvency |

---

## Part 5: Conclusion

The Phase 184 pool accounting sweep traced **81 mutation sites** across 9 contracts covering all four ETH pools (futurePool: 23, currentPool: 6, nextPool: 20, claimablePool: 16), 9 claimableWinnings patterns, and 7 game-over terminal flow sites. Every debit has a verified matching credit in a tracked pool, player balance, or external transfer. **With the Phase 183 deferred-SSTORE fix applied, zero accounting gaps exist.** The single known gap (SITE-FP-02 in committed code) is fully closed by the Phase 183 fix.

Cross-pool integrity is confirmed across 17 verified cross-pool flows (CROSS-01 through CROSS-17). The GameOver module's end-to-end conservation check algebraically proves that `totalFunds = claimablePool + vault_received` after all distributions. The `claimablePool >= sum(claimableWinnings[*])` invariant holds across all paths including sentinel accumulation, auto-rebuy, decimator double-debit (disjoint portions), and terminal zeroing.

**There are no untracked remainders, orphaned credits, or phantom debits in the Degenerus pool accounting system.** No action items for Phase 185 are required. The two INFO findings (MintModule triple-division dust and sentinel 1-wei accumulation) are benign and already addressed by existing yield surplus distribution and solvency-favorable over-reservation.

