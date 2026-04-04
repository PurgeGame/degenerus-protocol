# nextPool + claimablePool Debit/Credit Audit

**Phase:** 184-pool-accounting-sweep
**Plan:** 02
**Date:** 2026-04-04

---

## Part 1: nextPool Mutation Sites

All sites that write to nextPool via `_setNextPrizePool()` or dual `_setPrizePools(next, future)` calls.

Storage: `_setNextPrizePool(val)` reads current `(next, future) = _getPrizePools()` then writes `_setPrizePools(uint128(val), future)`. The dual `_setPrizePools(next, future)` writes both components atomically to `prizePoolsPacked`.

---

### SITE-NP-01: JackpotModule:payDailyJackpot line 372
- **Operation:** `_setNextPrizePool(_getNextPrizePool() + dailyLootboxBudget)` -- nextPool += dailyLootboxBudget
- **Source/Dest:** Credit from currentPool debit at line 371: `_setCurrentPrizePool(_getCurrentPrizePool() - dailyLootboxBudget)`
- **Counterpart verified:** YES -- line 371 deducts the identical `dailyLootboxBudget` amount from currentPool. The value is computed once and used in both operations.
- **Remainder risk:** None. The same variable `dailyLootboxBudget` is used for both the currentPool debit and the nextPool credit. No division occurs between them.
- **Notes:** Guarded by `if (dailyTicketUnits != 0)` -- if budget-to-ticket conversion yields 0 tickets, neither pool is modified (budget stays in currentPool). This is correct: tickets back the nextPool credit, so no tickets = no transfer.

### SITE-NP-02: JackpotModule:payDailyJackpot line 397
- **Operation:** `_setNextPrizePool(_getNextPrizePool() + reserveSlice)` -- nextPool += reserveSlice
- **Source/Dest:** Credit from futurePool debit at line 396: `_setFuturePrizePool(futurePool - reserveSlice)`
- **Counterpart verified:** YES -- line 396 deducts `reserveSlice` from futurePool. `reserveSlice = futurePool / 200` (0.5%), computed from the pre-debit snapshot at line 394.
- **Remainder risk:** None. `reserveSlice` is computed once and used identically for both the futurePool debit and nextPool credit.
- **Notes:** Guarded by `!isEarlyBirdDay` -- early bird days skip carryover entirely. Division `futurePool / 200` rounds down, meaning slightly less than 0.5% moves. Remainder stays in futurePool (conservative).

### SITE-NP-03: JackpotModule:payDailyJackpotCoinAndTickets line 714
- **Operation:** `_setNextPrizePool(_getNextPrizePool() + totalBudget)` -- nextPool += totalBudget
- **Source/Dest:** Credit from lootbox purchase phase -- `totalBudget` is the accumulated sum of all lootbox budgets distributed in this batch (daily ticket units converted to ETH). The ETH comes from nextPool backing already present (these are ticket distributions, not new ETH).
- **Counterpart verified:** YES -- `totalBudget` accumulates in the loop at lines 679-710 via `totalBudget += budget` where `budget` is computed from `_ticketUnitsToBudget` conversions. This represents the ETH equivalent of distributed tickets.
- **Remainder risk:** `_ticketUnitsToBudget` and `_budgetToTicketUnits` are inverse operations with potential rounding. The ticket-units intermediary means the reconverted budget may differ slightly from original allocation. However, this is tickets-to-budget direction, and any excess stays in nextPool.
- **Notes:** Comment says "All budget goes to nextPrizePool (like purchases during purchase phase)". This is a re-crediting of ticket backing that was previously moved to nextPool via SITE-NP-01/NP-02.

### SITE-NP-04: JackpotModule:consolidatePrizePools line 741
- **Operation:** `_setNextPrizePool(0)` -- nextPool = 0 (zeroing)
- **Source/Dest:** Full nextPool balance moved to currentPool at line 740: `_setCurrentPrizePool(_getCurrentPrizePool() + _getNextPrizePool())`
- **Counterpart verified:** YES -- line 740 reads `_getNextPrizePool()` and adds it to currentPool. Line 741 zeros nextPool. The read at 740 happens before the write at 741, and both use the same packed storage word (so the read captures the pre-zero value).
- **Remainder risk:** None. The full nextPool balance transfers -- no division or partial transfer.
- **Notes:** This is the level-transition consolidation. All nextPool backing accumulated during the purchase phase merges into currentPool for jackpot distribution. Happens once per level advance.

### SITE-NP-05: JackpotModule:_autoRebuyFromJackpot line 868
- **Operation:** `_setNextPrizePool(_getNextPrizePool() + calc.ethSpent)` -- nextPool += calc.ethSpent
- **Source/Dest:** Credit from jackpot winnings. `calc.ethSpent` is the portion of the player's jackpot payout that was auto-converted to tickets. The ETH was previously credited to the player via `_addClaimableEth` in jackpot distribution, then immediately re-invested.
- **Counterpart verified:** YES -- the ETH originates from jackpot distribution (claimablePool credit). The auto-rebuy deducts from the player's claimable and routes `calc.ethSpent` to the appropriate pool. When `calc.toFuture` is true, it goes to futurePool instead (line 866). Only one path executes.
- **Remainder risk:** `calc.reserved` (portion not converted to tickets) is returned to player via `_creditClaimable`. `calc.ethSpent + calc.reserved` equals the original `newAmount` input. No wei lost.
- **Notes:** Guarded by `if (!calc.hasTickets)` -- if no tickets generated, full amount stays as claimable (line 859). The `calc.toFuture` branch routes far-future tickets to futurePool rather than nextPool.

### SITE-NP-06: JackpotModule:_distributeLootboxAndTickets line 942
- **Operation:** `_setNextPrizePool(_getNextPrizePool() + lootboxBudget)` -- nextPool += lootboxBudget
- **Source/Dest:** Credit from lootbox budget allocation. `lootboxBudget` is the computed portion of daily jackpot budget earmarked for lootbox distribution. Originates from currentPool via the daily budget calculation.
- **Counterpart verified:** YES -- `lootboxBudget` is passed as a parameter from the caller, which computed it from the daily budget allocation. The ETH was already in currentPool and is being allocated to nextPool to back the distributed lootbox tickets.
- **Remainder risk:** None for the pool credit itself. The ticket distribution at lines 945-957 is independent of the pool credit -- `lootboxBudget` goes to nextPool unconditionally, while ticket units are computed from a potentially reduced `ticketBasis = (lootboxBudget * ticketConversionBps) / 10_000`. This means more ETH backs the pool than the ticket count represents (conservative).
- **Notes:** The full `lootboxBudget` enters nextPool even if `ticketConversionBps < 10000`. This creates a slight over-backing which is safe (pool has more ETH than ticket claims warrant).

### SITE-NP-07: AdvanceModule:_applyNextToFutureSkim line 1177
- **Operation:** `_setNextPrizePool(nextPoolBefore - take - insuranceSkim)` -- nextPool -= (take + insuranceSkim)
- **Source/Dest:** Debit split two ways: `take` goes to futurePool at line 1178 (`_setFuturePrizePool(futurePoolBefore + take)`), `insuranceSkim` goes to yieldAccumulator at line 1179 (`yieldAccumulator += insuranceSkim`).
- **Counterpart verified:** YES -- `take` is traced to futurePool credit (line 1178). `insuranceSkim = (nextPoolBefore * INSURANCE_SKIM_BPS) / 10_000` goes to `yieldAccumulator` (line 1179), which is later swept to futurePool in `consolidatePrizePools` (line 735).
- **Remainder risk:** `take` is computed via a multi-step process (base percentage + RNG variance + cap). `insuranceSkim` uses BPS division which rounds down. Remainder of `nextPoolBefore - take - insuranceSkim` stays in nextPool. All three destinations (nextPool remainder, futurePool, yieldAccumulator) are tracked.
- **Notes:** `take` is capped at `(nextPoolBefore * NEXT_TO_FUTURE_BPS_MAX) / 10_000` (80%). Combined with `insuranceSkim`, the total debit from nextPool is bounded. The `nextPoolBefore` snapshot ensures atomic accounting.

### SITE-NP-08: AdvanceModule:_drawDownFuturePrizePool line 1192
- **Operation:** `_setNextPrizePool(_getNextPrizePool() + reserved)` -- nextPool += reserved
- **Source/Dest:** Credit from futurePool debit at line 1191: `_setFuturePrizePool(_getFuturePrizePool() - reserved)`. `reserved = (_getFuturePrizePool() * 15) / 100` (15% of futurePool on normal levels).
- **Counterpart verified:** YES -- line 1191 deducts `reserved` from futurePool. Line 1192 adds the same `reserved` to nextPool. The `_getFuturePrizePool()` call at line 1187 (computation) and line 1191 (debit) are sequential and consistent.
- **Remainder risk:** Division `/ 100` rounds down. Remainder stays in futurePool (conservative).
- **Notes:** Guarded by `reserved != 0` (line 1190). On x00 levels, `reserved = 0` and no transfer occurs. The futurePool read at line 1187 may differ from the read at line 1191 only if another write occurs between them -- but `_drawDownFuturePrizePool` is a private function called sequentially, so this is safe.

### SITE-NP-09: DecimatorModule:_processDecimatorAutoRebuy line 389
- **Operation:** `_setNextPrizePool(_getNextPrizePool() + calc.ethSpent)` -- nextPool += calc.ethSpent
- **Source/Dest:** Credit from claimablePool. The decimator auto-rebuy converts a player's decimator prize into tickets. `calc.ethSpent` is deducted from claimablePool at line 398: `claimablePool -= calc.ethSpent`.
- **Counterpart verified:** YES -- line 398 deducts from claimablePool. Line 389 (or 387 for futurePool) credits the target pool. `calc.toFuture` routes to futurePool (line 387) or nextPool (line 389).
- **Remainder risk:** `calc.reserved` (unconverted portion) is credited back to player via `_creditClaimable` (line 394). `calc.ethSpent + calc.reserved <= weiAmount` (the original input). No wei lost.
- **Notes:** The claimablePool debit at line 398 deducts `calc.ethSpent` specifically (not the full `weiAmount`). The reserved portion stays in claimablePool as player balance. Only one of futurePool/nextPool is credited based on `calc.toFuture`.

### SITE-NP-10: GameOverModule:_handleGameOver line 131
- **Operation:** `_setNextPrizePool(0)` -- nextPool = 0 (zeroing)
- **Source/Dest:** Terminal zeroing when `available == 0`. All four pools are zeroed: nextPool (131), futurePool (132), currentPool (133), yieldAccumulator (134). No ETH moves because `available == 0`.
- **Counterpart verified:** YES -- this is the terminal branch where total contract funds equal or are less than claimablePool. No ETH is available for distribution, so zeroing the accounting pools is correct (they represent zero distributable ETH).
- **Remainder risk:** None. The pools may have had non-zero values that represented the same ETH as claimablePool. Zeroing them is correct because the ETH is fully spoken for by existing claimable balances.
- **Notes:** Reached when `totalFunds <= claimablePool`. The `gameOverFinalJackpotPaid = true` flag prevents re-entry.

### SITE-NP-11: GameOverModule:_handleGameOver line 143
- **Operation:** `_setNextPrizePool(0)` -- nextPool = 0 (zeroing)
- **Source/Dest:** Terminal zeroing in the normal game-over path (ETH available for distribution). All four pools zeroed, then `available` is distributed via terminal jackpot.
- **Counterpart verified:** YES -- `available = totalFunds - claimablePool` (line 120). The zeroed pool balances are accounted for within `available`. Distribution at lines 154-176 routes `available` through decimator jackpot and terminal jackpot, with remainder sent to vault.
- **Remainder risk:** None for the zeroing itself. The distribution path handles remainders explicitly: `remaining -= decPool; remaining += decRefund` tracks decimator, and undistributed `remaining` goes to vault (line 174).
- **Notes:** This and SITE-NP-10 are the two game-over terminal paths. Both zero all four pools. The difference is whether ETH is available for distribution.

### SITE-NP-12: DegenerusGame:recordMint line 363
- **Operation:** `_setPrizePools(next + uint128(nextShare), future + uint128(futureShare))` -- nextPool += nextShare
- **Source/Dest:** Credit from mint payment. `nextShare = prizeContribution - futureShare` where `prizeContribution` comes from `_processMintPayment` (msg.value or claimable balance). `futureShare = (prizeContribution * PURCHASE_TO_FUTURE_BPS) / 10_000`.
- **Counterpart verified:** YES -- `prizeContribution` originates from external ETH (msg.value) or claimable balance deduction. futurePool gets `futureShare`, nextPool gets `nextShare = prizeContribution - futureShare`. Total `nextShare + futureShare = prizeContribution`.
- **Remainder risk:** `futureShare` uses BPS division (rounds down). `nextShare = prizeContribution - futureShare` captures the remainder. No wei lost.
- **Notes:** Respects freeze state -- if `prizePoolFrozen`, amounts go to pending pools instead (lines 355-360), which are flushed via `_unfreezePool` later. The nextPool component of the dual write is the nextShare credit.

### SITE-NP-13: DegenerusGame:claimSdgnrsReserve line 1691
- **Operation:** `_setPrizePools(next, future + uint128(amount))` -- nextPool unchanged (passthrough)
- **Source/Dest:** nextPool is read and written back unchanged. Only futurePool is credited with `amount` (from claimablePool debit at line 1683).
- **Counterpart verified:** YES (no-op for nextPool) -- nextPool value is preserved. The `next` variable is read at line 1690 and written back unchanged.
- **Remainder risk:** None for nextPool.
- **Notes:** This is a claimablePool -> futurePool transfer. nextPool is a passthrough in the dual write.

### SITE-NP-14: DegenerusGame:receive() line 2524
- **Operation:** `_setPrizePools(next, future + uint128(msg.value))` -- nextPool unchanged (passthrough)
- **Source/Dest:** nextPool is read and written back unchanged. Only futurePool is credited with msg.value.
- **Counterpart verified:** YES (no-op for nextPool) -- nextPool value is preserved.
- **Remainder risk:** None for nextPool.
- **Notes:** Plain ETH transfers go entirely to futurePool. nextPool passthrough.

### SITE-NP-15: DegeneretteModule:_placeBet line 532
- **Operation:** `_setPrizePools(next, future + uint128(totalBet))` -- nextPool unchanged (passthrough)
- **Source/Dest:** nextPool is read and written back unchanged. Only futurePool is credited with `totalBet`.
- **Counterpart verified:** YES (no-op for nextPool) -- nextPool value is preserved.
- **Remainder risk:** None for nextPool.
- **Notes:** Degenrette ETH bets go to futurePool. nextPool passthrough.

### SITE-NP-16: MintModule:_processLootboxPurchase line 758
- **Operation:** `_setPrizePools(next + uint128(nextShare), future + uint128(futureShare))` -- nextPool += nextShare
- **Source/Dest:** Credit from lootbox purchase payment. `nextShare = (lootBoxAmount * nextBps) / 10_000` where `lootBoxAmount` comes from the player's ETH payment (msg.value or claimable). `futureShare = (lootBoxAmount * futureBps) / 10_000`.
- **Counterpart verified:** YES -- `lootBoxAmount` originates from player payment. BPS splits route portions to nextPool, futurePool, and optionally vault (lines 760-762). `nextShare + futureShare + vaultShare` may be slightly less than `lootBoxAmount` due to rounding, but these are credits from external ETH (not pool-to-pool transfers).
- **Remainder risk:** Three BPS divisions from the same `lootBoxAmount`. `nextShare + futureShare + vaultShare` may be less than `lootBoxAmount` by up to 2 wei due to triple rounding. The unaccounted remainder (up to 2 wei) stays in the contract balance but enters no tracked pool. This is negligible but technically a dust leak.
- **Notes:** Respects freeze state via pending pool path (lines 753-755). The vault share is sent as an external ETH transfer.

### SITE-NP-17: WhaleModule:gamePurchaseWhalePass line 353
- **Operation:** `_setPrizePools(next + uint128(nextShare), future + uint128(totalPrice - nextShare))` -- nextPool += nextShare
- **Source/Dest:** Credit from whale pass purchase (msg.value). `nextShare` varies by level: 30% at level 0, 5% otherwise. `totalPrice - nextShare` goes to futurePool.
- **Counterpart verified:** YES -- `nextShare + (totalPrice - nextShare) = totalPrice`. Full purchase price is allocated between nextPool and futurePool. No remainder.
- **Remainder risk:** `nextShare = (totalPrice * 3000) / 10_000` or `(totalPrice * 500) / 10_000` -- BPS division rounds down. futurePool gets `totalPrice - nextShare` which absorbs the remainder. No wei lost.
- **Notes:** Respects freeze state (lines 345-350). Three whale pass functions share this pattern.

### SITE-NP-18: WhaleModule:gamePurchaseLazyPass line 499
- **Operation:** `_setPrizePools(next + uint128(nextShare), future + uint128(futureShare))` -- nextPool += nextShare
- **Source/Dest:** Credit from lazy pass purchase. `futureShare = (totalPrice * LAZY_PASS_TO_FUTURE_BPS) / 10_000`. `nextShare = totalPrice - futureShare`.
- **Counterpart verified:** YES -- `nextShare + futureShare = totalPrice`. Full price allocated. No remainder.
- **Remainder risk:** Division rounds down for futureShare. nextShare = totalPrice - futureShare absorbs remainder. No wei lost.
- **Notes:** Respects freeze state.

### SITE-NP-19: WhaleModule:gamePurchaseDeityPassFromBoon line 653
- **Operation:** `_setPrizePools(next + uint128(nextShare), future + uint128(totalPrice - nextShare))` -- nextPool += nextShare
- **Source/Dest:** Credit from deity pass purchase (msg.value). Same split pattern as whale pass (30% or 5% based on level).
- **Counterpart verified:** YES -- `nextShare + (totalPrice - nextShare) = totalPrice`. No remainder.
- **Remainder risk:** Same as SITE-NP-17. futurePool absorbs division remainder.
- **Notes:** Respects freeze state.

### SITE-NP-20: Storage:_unfreezePool line 749
- **Operation:** `_setPrizePools(next + pNext, future + pFuture)` -- nextPool += pNext
- **Source/Dest:** Credit from pending pool accumulator. During freeze, purchases accumulate in `prizePoolPendingPacked`. On unfreeze, pending amounts are flushed to live pools.
- **Counterpart verified:** YES -- `pNext` and `pFuture` were accumulated during the freeze period via `_setPendingPools` calls. The pending packed word is zeroed at line 750. Every `_setPendingPools` call that credited pNext has a matching external source (msg.value, claimable deduction, etc.) already traced in the corresponding SITE-NP entries above (which document both frozen and unfrozen paths).
- **Remainder risk:** None. The full pending amounts are flushed.
- **Notes:** `prizePoolPendingPacked = 0` at line 750 clears the accumulator. `prizePoolFrozen = false` at line 751 re-enables direct writes.

---
