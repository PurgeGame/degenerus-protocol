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

