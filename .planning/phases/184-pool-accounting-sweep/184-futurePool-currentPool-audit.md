# futurePool + currentPool Debit/Credit Audit

**Phase:** 184-pool-accounting-sweep
**Date:** 2026-04-04
**Scope:** Every mutation of futurePool (via `_setFuturePrizePool` and `_setPrizePools`) and currentPool (via `_setCurrentPrizePool`) across all modules

**Storage accessors traced:**
- `_setFuturePrizePool(val)` -> reads packed next, writes `(next, uint128(val))` [DegenerusGameStorage.sol:777-780]
- `_setPrizePools(next, future)` -> writes both components atomically [DegenerusGameStorage.sol:676-678]
- `_setPendingPools(next, future)` -> freeze-state accumulator (merged on unfreeze) [DegenerusGameStorage.sol:686-688]
- `_setCurrentPrizePool(val)` -> writes `currentPrizePool = uint128(val)` [DegenerusGameStorage.sol:795-796]
- `_unfreezePool()` -> applies pending to live: `_setPrizePools(next + pNext, future + pFuture)` [DegenerusGameStorage.sol:745-752]

**Freeze-state note:** Several sites have dual paths (frozen vs unfrozen). Frozen writes go to pendingPools, which are applied atomically via `_unfreezePool()`. Both paths are equivalent for accounting purposes -- the credit/debit is the same, just deferred. Audit entries cover the live-pool path; frozen-path equivalence is noted.

**Phase 183 baseline:** The deferred-SSTORE fix (unstaged on main) changes SITE-FP-02 from upfront deduction to deferred deduction. This audit traces BOTH the committed (upfront) and the Phase 183 fix (deferred) patterns.

---

## futurePool Mutation Sites

---

### SITE-FP-01: JackpotModule:payDailyJackpot (daily path) line 396
- **Operation:** futurePool -= reserveSlice
- **Source/Dest:** reserveSlice (0.5% of futurePool) moves to nextPool via `_setNextPrizePool(_getNextPrizePool() + reserveSlice)` at line 397
- **Counterpart verified:** YES -- line 397 `_setNextPrizePool(_getNextPrizePool() + reserveSlice)` credits nextPool by the exact same amount
- **Remainder risk:** `reserveSlice = futurePool / 200` -- integer division truncates, but the truncated amount stays in futurePool (deducting `reserveSlice` from `futurePool` leaves the remainder in-place). No untracked wei.
- **Notes:** Only executes when `!isEarlyBirdDay` (line 379). Guard prevents execution on early-bird days. The carryover ticket units are computed from `reserveSlice` but do not affect pool accounting -- they are queue entries backed by the nextPool credit.

---

### SITE-FP-02: JackpotModule:payDailyJackpot (early-burn path) line 483
- **Operation:** futurePool -= ethDaySlice (upfront deduction in committed code)
- **Source/Dest:** ethDaySlice (1% of futurePool) is consumed by `_executeJackpot` which distributes to claimablePool via `_addClaimableEth`, plus lootboxBudget portion goes to `_distributeLootboxAndTickets` (nextPool backing)
- **Counterpart verified:** PARTIAL -- see analysis below

**Committed code (pre-Phase-183):**
- Line 483: `_setFuturePrizePool(futurePool - ethDaySlice)` -- upfront deduction of full 1% slice
- Line 496-504: `_executeJackpot(...)` return value `paidEth` is DISCARDED
- Line 506: Comment says "Pools already deducted upfront; no additional deduction needed"
- **GAP in committed code:** If `_executeJackpot` pays less than `ethPool` (empty trait buckets), the difference `ethPool - paidEth` exits futurePool but enters no tracked pool. This is the Phase 183 finding.
- lootboxBudget portion: deducted from `ethPool` at line 494, goes to `_distributeLootboxAndTickets` which queues tickets backed by nextPool. The `lootboxBudget` wei exits futurePool via the upfront deduction and enters nextPool via ticket distribution.

**Phase 183 fix (unstaged on main):**
- Removes upfront deduction at line 483
- Captures return: `uint256 paidEth = _executeJackpot(...)`
- Deferred deduction: `_setFuturePrizePool(futurePool - lootboxBudget - paidEth)`
- **After fix:** futurePool -= (lootboxBudget + paidEth). Unspent ETH (`ethPool - paidEth`) stays in futurePool. Fully balanced.

- **Counterpart verified (with Phase 183 fix):** YES -- futurePool debited by exactly `lootboxBudget + paidEth`; lootboxBudget backs tickets in nextPool, paidEth flows to claimablePool via `_addClaimableEth`
- **Remainder risk:** `ethDaySlice = (futurePool * 100) / 10_000` -- integer division truncation stays in futurePool. `lootboxBudget` from `_validateTicketBudget` may further truncate but result backs actual tickets. No untracked wei with Phase 183 fix applied.
- **Notes:** Phase 183 fix is the correct baseline. The committed code has a known accounting gap for empty trait buckets.

---

### SITE-FP-03: JackpotModule:_runEarlyBirdLootboxJackpot line 657
- **Operation:** futurePool -= reserveContribution
- **Source/Dest:** reserveContribution (3% of futurePool) moves to nextPool via `_setNextPrizePool(_getNextPrizePool() + totalBudget)` at line 714. Note: `totalBudget == reserveContribution`.
- **Counterpart verified:** YES -- line 714 `_setNextPrizePool(_getNextPrizePool() + totalBudget)` credits nextPool by the full budget amount. The 100 winners receive lootbox tickets backed by this nextPool credit.
- **Remainder risk:** `reserveContribution = (futurePool * 300) / 10_000` -- integer division truncation stays in futurePool. `perWinnerEth = totalBudget / 100` truncates; `totalBudget - (perWinnerEth * 100)` remains in nextPool (credited as full totalBudget). Tickets are `perWinnerEth / ticketPrice` with further truncation dust staying in nextPool. No untracked wei.
- **Notes:** Early return at line 660 if `totalBudget == 0` -- skip the entire loop but futurePool was already decremented by 0, so no issue. The nextPool credit at line 714 is unconditional (after the early return guard), ensuring all deducted ETH is accounted for.

---

### SITE-FP-04: JackpotModule:consolidatePrizePools (yield dump) line 735
- **Operation:** futurePool += half
- **Source/Dest:** half comes from yieldAccumulator (`half = acc >> 1`), yieldAccumulator decremented by `acc - half` at line 736
- **Counterpart verified:** YES -- `yieldAccumulator = acc - half` at line 736. Total: `half + (acc - half) = acc`. The `>> 1` rounds down, so `acc - half >= half` (excess stays in yieldAccumulator). No ETH lost.
- **Remainder risk:** `acc >> 1` truncates odd wei to yieldAccumulator (comment: "rounds in favor of retention"). No untracked wei.
- **Notes:** Only fires on x00 levels (`lvl % 100 == 0`). yieldAccumulator is funded by insurance skim in AdvanceModule and yield surplus distribution.

---

### SITE-FP-05: JackpotModule:consolidatePrizePools (keep-roll) line 750
- **Operation:** futurePool = keepWei (effectively futurePool -= moveWei)
- **Source/Dest:** moveWei = `fp - keepWei` moves to currentPool via `_setCurrentPrizePool(_getCurrentPrizePool() + moveWei)` at line 751. keepWei = `(fp * keepBps) / 10_000`.
- **Counterpart verified:** YES -- `keepWei + moveWei = keepWei + (fp - keepWei) = fp`. The full futurePool value is accounted for: keepWei stays, moveWei goes to currentPool.
- **Remainder risk:** `keepWei = (fp * keepBps) / 10_000` -- integer division truncation is in `moveWei` (since `moveWei = fp - keepWei`). All of fp is distributed between keepWei and moveWei. No untracked wei.
- **Notes:** Only fires on x00 levels when `keepBps < 10_000 && fp != 0`. If `moveWei == 0` (keepBps rounds to 10000), the inner if-block is skipped and futurePool is unchanged. The `_futureKeepBps` function returns 3000-6500 range via 5-dice roll.

---

### SITE-FP-06: JackpotModule:_processAutoRebuy (lootbox context) line 866
- **Operation:** futurePool += calc.ethSpent (conditional on `calc.toFuture`)
- **Source/Dest:** calc.ethSpent comes from player ETH winnings (the `newAmount` parameter), which was originally from claimablePool or jackpot payout. When `!calc.toFuture`, nextPool is credited instead (line 868).
- **Counterpart verified:** YES -- `newAmount` enters the function as ETH to be rebought. `calc.ethSpent` is the portion spent on tickets (backing pool receives it). `calc.reserved` is returned to player claimable (line 872). `calc.ethSpent + calc.reserved <= newAmount`. The spending goes to either futurePool or nextPool depending on target level.
- **Remainder risk:** `_calcAutoRebuy` computes `ticketCount = ethSpent / targetPrice` with truncation; the `ethSpent` value is `ticketCount * targetPrice`, so no fractional dust. Any `newAmount - ethSpent` portion goes to `calc.reserved` -> `_creditClaimable`.
- **Notes:** This auto-rebuy path is in the lootbox jackpot context. The `toFuture` flag is true when target level is far-future. This function is called from `_addClaimableEth` which is invoked during jackpot distributions.

---

### SITE-FP-07: JackpotModule:_distributeJackpotEthWithWhalePass line 1594
- **Operation:** futurePool += whalePassCost
- **Source/Dest:** whalePassCost comes from the winner's jackpot share (`perWinner`). Split: `ethAmount = perWinner - whalePassCost` goes to claimable via `_creditJackpot`, whalePassCost goes to futurePool. Total: `ethAmount + whalePassCost = perWinner`.
- **Counterpart verified:** YES -- `perWinner` is the winner's share from the jackpot pool (deducted from currentPool or futurePool at the calling site). whalePassCost = `whalePassCount * HALF_WHALE_PASS_PRICE`. The remainder (`perWinner - whalePassCost`) goes to claimable. Full perWinner accounted for.
- **Remainder risk:** `whalePassCount = quarterAmount / HALF_WHALE_PASS_PRICE` truncates. `quarterAmount = perWinner >> 2`. If `whalePassCount == 0`, full perWinner goes to ETH (line 1598). No dust.
- **Notes:** Only fires when `whalePassCount != 0`. The whale pass claims are tracked in `whalePassClaims[winner]` for later redemption.

---

### SITE-FP-08: JackpotModule:runRewardJackpots (rebuyDelta write-back) line 2591
- **Operation:** futurePool = futurePoolLocal + rebuyDelta
- **Source/Dest:** `futurePoolLocal` is a local accumulator tracking BAF/Decimator debits and refunds. `rebuyDelta = _getFuturePrizePool() - baseFuturePool` captures any auto-rebuy writes that went directly to storage during BAF/Decimator execution.
- **Counterpart verified:** YES -- This is a reconciliation write, not a new debit/credit. The actual debits are:
  - BAF: `futurePoolLocal -= bafPoolWei` (line 2534), then refund: `futurePoolLocal += (bafPoolWei - netSpend)` (line 2543), plus lootbox recycling: `futurePoolLocal += lootboxToFuture` (line 2547)
  - Decimator x00: `futurePoolLocal -= spend` (line 2561), spend goes to claimablePool (line 2562)
  - Decimator x5: `futurePoolLocal -= spend` (line 2577), spend goes to claimablePool (line 2579)
  - `claimableDelta` is applied at line 2594: `claimablePool += claimableDelta`
  - Net change: `futurePoolLocal = baseFuturePool - netBAFSpend + lootboxToFuture - decSpend`
  - rebuyDelta captures concurrent auto-rebuy writes to storage
- **Remainder risk:** No division involved in the accumulator pattern. All operations are additive/subtractive with exact values.
- **Notes:** The `if (futurePoolLocal != baseFuturePool)` guard (line 2589) prevents unnecessary SSTORE. rebuyDelta reconciliation is the key innovation -- auto-rebuy can write to `futurePrizePool` storage during `_runBafJackpot`/`runDecimatorJackpot` via `_processAutoRebuy`, and this delta is captured and merged with the local accumulator.

---

### SITE-FP-09: AdvanceModule:_skimAndRedistribute line 1178
- **Operation:** futurePool += take
- **Source/Dest:** take comes from nextPool. `_setNextPrizePool(nextPoolBefore - take - insuranceSkim)` at line 1177. Total nextPool debit: `take + insuranceSkim`. futurePool gets `take`, yieldAccumulator gets `insuranceSkim` (line 1179).
- **Counterpart verified:** YES -- `nextPoolBefore - take - insuranceSkim` remains in nextPool. `take` goes to futurePool. `insuranceSkim` goes to yieldAccumulator. `nextPoolBefore = (remaining nextPool) + take + insuranceSkim`. All accounted.
- **Remainder risk:** `insuranceSkim = (nextPoolBefore * INSURANCE_SKIM_BPS) / 10_000` truncates. Truncation dust stays in nextPool (subtracted as the truncated value). `take` is computed via a multi-step formula with capping but always integer. No untracked wei.
- **Notes:** `maxTake = (nextPoolBefore * NEXT_TO_FUTURE_BPS_MAX) / 10_000` caps take at 80% of nextPool.

---

### SITE-FP-10: AdvanceModule:_drawDownFuturePrizePool line 1191
- **Operation:** futurePool -= reserved
- **Source/Dest:** reserved (15% of futurePool on non-x00 levels) moves to nextPool via `_setNextPrizePool(_getNextPrizePool() + reserved)` at line 1192
- **Counterpart verified:** YES -- line 1192 credits nextPool by exact `reserved` amount
- **Remainder risk:** `reserved = (_getFuturePrizePool() * 15) / 100` truncates. Truncation dust stays in futurePool. No untracked wei.
- **Notes:** Skipped on x00 levels (`reserved = 0`). The `if (reserved != 0)` guard at line 1190 prevents SSTORE when nothing to transfer.

---

### SITE-FP-11: DecimatorModule:claimDecimatorJackpot line 336
- **Operation:** futurePool += lootboxPortion
- **Source/Dest:** lootboxPortion comes from the player's decimator claim amount (originally from claimablePool reservation in `runDecimatorJackpot`). The lootboxPortion is the ticket-conversion share of the claim.
- **Counterpart verified:** YES -- `_creditDecJackpotClaimCore` returns the lootbox portion. The ETH portion goes to claimable via `_addClaimableEth` (called inside core). The total `amountWei` was pre-reserved in claimablePool when the decimator round was created. lootboxPortion backs lootbox tickets in futurePool.
- **Remainder risk:** Lootbox/ETH split is deterministic from the claim parameters. No division-based remainder.
- **Notes:** The `if (lootboxPortion != 0)` guard prevents unnecessary SSTORE. During gameOver (line 325), the full amount goes to claimable via `_addClaimableEth` and no lootbox conversion occurs (early return). Also: `claimablePool -= calc.ethSpent` at line 398 in `_processAutoRebuy` deducts auto-rebuy spend from claimablePool, which was pre-reserved.

---

### SITE-FP-12: DecimatorModule:_processAutoRebuy line 387
- **Operation:** futurePool += calc.ethSpent (conditional on `calc.toFuture`)
- **Source/Dest:** Same auto-rebuy pattern as SITE-FP-06. calc.ethSpent comes from decimator claim amount being converted to tickets. When `!calc.toFuture`, nextPool is credited instead (line 389).
- **Counterpart verified:** YES -- Same logic as SITE-FP-06. The pre-reserved claimablePool amount is deducted by `claimablePool -= calc.ethSpent` at line 398. Tickets are queued, ETH backs the target pool.
- **Remainder risk:** Same as SITE-FP-06. No fractional dust.
- **Notes:** `claimablePool -= calc.ethSpent` at line 398 is the counterpart debit -- the ETH was pre-reserved in claimablePool during decimator round creation, and the auto-rebuy moves it from claimablePool to future/nextPool.

---

### SITE-FP-13: DegeneretteModule:_resolveETH (unfrozen path) line 725
- **Operation:** futurePool -= ethPortion (via `pool -= ethPortion; _setFuturePrizePool(pool)`)
- **Source/Dest:** ethPortion goes to player claimable via `_addClaimableEth(player, ethPortion)` at line 726. The ETH was originally placed in futurePool by the bet at SITE-FP-19.
- **Counterpart verified:** YES -- `_addClaimableEth` credits `claimableWinnings[player]` and `claimablePool` by `ethPortion` (or processes auto-rebuy which routes to pool/claimable).
- **Remainder risk:** `maxEth = (pool * ETH_WIN_CAP_BPS) / 10_000` truncation. If ethPortion > maxEth, excess goes to lootboxPortion (line 718-719). Capped ethPortion is always <= pool (line 716). No untracked wei.
- **Notes:** Frozen path (lines 700-709) uses `_setPendingPools(pNext, pFuture - uint128(ethPortion))` instead -- equivalent debit from pending future pool. Both paths credit `_addClaimableEth`. Lootbox portion (line 730-731) calls `_resolveLootboxDirect` which resolves lootbox rewards but does NOT write to futurePool (confirmed: LootboxModule has zero pool writes in resolve path).

---

### SITE-FP-14: GameOverModule:_runFinalJackpot line 132
- **Operation:** futurePool = 0
- **Source/Dest:** All pool ETH is zeroed. The `available` amount (total funds - claimablePool, line 120) is redistributed via terminal decimator + terminal jackpot + refund flows in the rest of the function.
- **Counterpart verified:** YES -- Line 132 zeros futurePool alongside nextPool (line 131) and currentPool (line 133). The total `available` is computed BEFORE zeroing (line 120) and tracks all non-claimable ETH. It is distributed via: 10% terminal decimator (line 154), 40% terminal jackpot (line 161+), remainder to claimablePool (refund). yieldAccumulator also zeroed (line 134).
- **Remainder risk:** None -- all pools are zeroed to 0, not decremented by computed amounts.
- **Notes:** This is the `available == 0` path (line 129-136). When no funds available, all pools are zeroed and function returns immediately. No distribution needed.

---

### SITE-FP-15: GameOverModule:_runFinalJackpot line 144
- **Operation:** futurePool = 0
- **Source/Dest:** Same zeroing as SITE-FP-14 but on the `available != 0` path (line 142+). Pools are zeroed, then `available` is distributed.
- **Counterpart verified:** YES -- Same logic as SITE-FP-14. Line 143 zeros nextPool, line 144 zeros futurePool, line 145 zeros currentPool, line 146 zeros yieldAccumulator. The full `available` amount is then distributed via terminal decimator, terminal jackpot, and refund.
- **Remainder risk:** None -- all pools zeroed to 0.
- **Notes:** The actual jackpot distribution follows at lines 152+. `remaining` variable tracks unallocated funds and ensures all ETH is distributed or goes to claimablePool.

---

### SITE-FP-16: DegenerusGame:recordMint line 363
- **Operation:** futurePool += futureShare (via `_setPrizePools(next + nextShare, future + futureShare)`)
- **Source/Dest:** futureShare = `(prizeContribution * PURCHASE_TO_FUTURE_BPS) / 10_000`. prizeContribution is the mint cost from player ETH/claimable payment. nextShare = `prizeContribution - futureShare`.
- **Counterpart verified:** YES -- `futureShare + nextShare = futureShare + (prizeContribution - futureShare) = prizeContribution`. The full prize contribution is split between future and next pools. Source is player payment (msg.value or claimableWinnings deduction in `_processMintPayment`).
- **Remainder risk:** `futureShare = (prizeContribution * PURCHASE_TO_FUTURE_BPS) / 10_000` truncates. Truncation goes to nextShare (since `nextShare = prizeContribution - futureShare`). No untracked wei.
- **Notes:** Frozen path uses `_setPendingPools` instead (lines 356-360). Both paths are equivalent.

---

### SITE-FP-17: DegenerusGame:resolveRedemptionLootbox line 1691
- **Operation:** futurePool += amount (via `_setPrizePools(next, future + uint128(amount))`)
- **Source/Dest:** `amount` comes from sDGNRS claimable winnings. Lines 1679-1683: `claimableWinnings[SDGNRS] -= amount` and `claimablePool -= amount`. ETH stays in Game contract balance, just reclassified from claimablePool to futurePool.
- **Counterpart verified:** YES -- `claimablePool -= amount` at line 1683 is the exact counterpart debit. The amount moves from claimablePool to futurePool (internal accounting transfer, no ETH movement).
- **Remainder risk:** None -- exact amount, no division.
- **Notes:** Frozen path uses `_setPendingPools` (lines 1687-1688). Called by sDGNRS during claimRedemption. Guard: `msg.sender != ContractAddresses.SDGNRS` (line 1671).

---

### SITE-FP-18: DegenerusGame:receive() line 2524
- **Operation:** futurePool += msg.value (via `_setPrizePools(next, future + uint128(msg.value))`)
- **Source/Dest:** msg.value is external ETH sent to the contract. This is a pure credit -- new ETH enters the system.
- **Counterpart verified:** YES -- External ETH deposit. No counterpart pool debit needed; the ETH enters from outside the contract's accounting system.
- **Remainder risk:** None -- exact msg.value.
- **Notes:** Frozen path uses `_setPendingPools` (lines 2520-2521). `gameOver` check at line 2518 prevents deposits after game over.

---

### SITE-FP-19: DegeneretteModule:_collectBet (ETH bet) line 532
- **Operation:** futurePool += totalBet (via `_setPrizePools(next, future + uint128(totalBet))`)
- **Source/Dest:** totalBet is the player's ETH bet amount (msg.value or claimable withdrawal, lines 516-523). Pure credit to futurePool from player deposit.
- **Counterpart verified:** YES -- Player deposits ETH (msg.value or claimableWinnings deduction). If from claimable: `claimableWinnings[player] -= fromClaimable` and `claimablePool -= fromClaimable` (lines 522-523). If from msg.value: external ETH. Both sources are tracked.
- **Remainder risk:** None -- exact totalBet amount.
- **Notes:** Frozen path uses `_setPendingPools` (lines 528-529). The bet is tracked via `lootboxRngPendingEth += totalBet` (line 534) for RNG-pending accounting.

---

### SITE-FP-20: MintModule:_processMintLootbox line 758
- **Operation:** futurePool += futureShare (via `_setPrizePools(next + uint128(nextShare), future + uint128(futureShare))`)
- **Source/Dest:** futureShare = `(lootBoxAmount * futureBps) / 10_000`. lootBoxAmount is the lootbox purchase amount. Split: futureShare + nextShare + vaultShare.
- **Counterpart verified:** YES -- `futureShare + nextShare + vaultShare` are derived from lootBoxAmount via BPS splits. vaultShare is sent to vault via `.call{value: vaultShare}` (line 761). `lootBoxAmount - futureShare - nextShare - vaultShare` is truncation dust that stays in the contract untracked. See remainder risk.
- **Remainder risk:** Three separate divisions: `futureShare = (lootBoxAmount * futureBps) / 10_000`, `nextShare = (lootBoxAmount * nextBps) / 10_000`, `vaultShare = (lootBoxAmount * vaultBps) / 10_000`. Each truncates independently. `futureBps + nextBps + vaultBps` may sum to 10000 or less. If sum < 10000, the unallocated portion stays in contract balance untracked. If sum = 10000, triple-division dust (up to 2 wei per lootbox purchase) stays in contract balance.
- **INFO FINDING:** Up to 2 wei per lootbox purchase may accumulate in contract balance without being tracked in any pool. Over many purchases this could accumulate, but the `_distributeYieldSurplus` function treats any `totalBal - obligations` surplus as yield, so this dust is eventually captured. No practical risk.
- **Notes:** Frozen path uses `_setPendingPools` (lines 754-755).

---

### SITE-FP-21: WhaleModule:purchaseWhalePass line 353
- **Operation:** futurePool += (totalPrice - nextShare) (via `_setPrizePools(next + uint128(nextShare), future + uint128(totalPrice - nextShare))`)
- **Source/Dest:** totalPrice is the whale pass purchase price from player ETH. nextShare = 30% at level 0, 5% otherwise. Remainder goes to futurePool.
- **Counterpart verified:** YES -- `nextShare + (totalPrice - nextShare) = totalPrice`. Full purchase price is split between next and future pools. Source is player msg.value (handled by upstream purchase logic).
- **Remainder risk:** `nextShare = (totalPrice * 3000) / 10_000` or `(totalPrice * 500) / 10_000` -- truncation goes to futurePool since `totalPrice - nextShare` captures the remainder. No untracked wei.
- **Notes:** Frozen path uses `_setPendingPools` (lines 346-350). The lootbox bonus (lines 359-364) is a separate virtual award, not a pool write.

---

### SITE-FP-22: WhaleModule:purchaseLazyPass line 499
- **Operation:** futurePool += futureShare (via `_setPrizePools(next + uint128(nextShare), future + uint128(futureShare))`)
- **Source/Dest:** futureShare = `(totalPrice * LAZY_PASS_TO_FUTURE_BPS) / 10_000`. nextShare = `totalPrice - futureShare`. Source is player ETH.
- **Counterpart verified:** YES -- `futureShare + nextShare = futureShare + (totalPrice - futureShare) = totalPrice`. Full price accounted.
- **Remainder risk:** Division truncation goes to nextShare (computed as remainder). No untracked wei.
- **Notes:** Frozen path uses `_setPendingPools` (lines 492-496).

---

### SITE-FP-23: WhaleModule:purchaseDeityPass line 653
- **Operation:** futurePool += (totalPrice - nextShare) (via `_setPrizePools(next + uint128(nextShare), future + uint128(totalPrice - nextShare))`)
- **Source/Dest:** Same pattern as SITE-FP-21. totalPrice is deity pass price. nextShare = 30% at level 0, 5% otherwise.
- **Counterpart verified:** YES -- Same as SITE-FP-21. `nextShare + (totalPrice - nextShare) = totalPrice`.
- **Remainder risk:** Same as SITE-FP-21. Truncation goes to futurePool. No untracked wei.
- **Notes:** Frozen path uses `_setPendingPools` (lines 646-650).

---

---

## currentPool Mutation Sites

---

### SITE-CP-01: JackpotModule:payDailyJackpot (daily lootbox budget) line 371
- **Operation:** currentPool -= dailyLootboxBudget
- **Source/Dest:** dailyLootboxBudget moves to nextPool via `_setNextPrizePool(_getNextPrizePool() + dailyLootboxBudget)` at line 372. This funds lootbox ticket rewards for the daily jackpot phase.
- **Counterpart verified:** YES -- line 372 `_setNextPrizePool(_getNextPrizePool() + dailyLootboxBudget)` credits nextPool by the exact same amount. The debit-credit pair is on adjacent lines (371-372).
- **Remainder risk:** `dailyLootboxBudget` comes from `_validateTicketBudget(budget / 5, ...)` which may truncate `budget / 5`. Truncation dust stays in `budget` (line 361: `budget -= dailyLootboxBudget`). The deducted amount is exact. No untracked wei.
- **Notes:** Guard: `if (dailyTicketUnits != 0)` at line 369 -- the deduction only happens when tickets would actually be queued. If `_budgetToTicketUnits` returns 0 (budget too small for any tickets), the pool transfer is skipped entirely and the budget remains in dailyEthBudget for ETH distribution.

---

### SITE-CP-02: JackpotModule:payDailyJackpot (daily ETH payout) line 451
- **Operation:** currentPool -= paidDailyEth
- **Source/Dest:** paidDailyEth is the actual ETH distributed to daily jackpot winners via `_processDailyEth`. Winners receive ETH via `_addClaimableEth` which credits `claimableWinnings[winner]` and `claimablePool`.
- **Counterpart verified:** YES -- `_processDailyEth` returns paidEth = sum of all `_addClaimableEth` credits across the 4 trait buckets. `paidDailyEth <= dailyEthBudget` (may be less if trait buckets are empty). The currentPool debit exactly matches the total claimablePool credits from `_addClaimableEth` calls.
- **Remainder risk:** `dailyEthBudget - paidDailyEth` represents unspent ETH from empty trait buckets. This unspent amount remains in currentPool (not deducted). No untracked wei.
- **Notes:** Guard: `if (dailyEthBudget != 0)` at line 426. The `_processDailyEth` function handles the `bucketShares` calculation which can produce phantom shares in empty buckets, but `_processDailyEth` only pays actual winners (skips empty buckets at line 1261: `if (count == 0 || share == 0) continue`). The currentPool debit uses the actual `paidDailyEth` return value, not the budget, so phantom shares do not cause a leak here.

---

### SITE-CP-03: JackpotModule:consolidatePrizePools (nextPool merge) line 740
- **Operation:** currentPool += _getNextPrizePool()
- **Source/Dest:** The entire nextPool balance is added to currentPool. nextPool is then zeroed at line 741: `_setNextPrizePool(0)`.
- **Counterpart verified:** YES -- `_setNextPrizePool(0)` at line 741 zeros nextPool. The full nextPool value is read via `_getNextPrizePool()` and added to currentPool. This is a balanced swap: `currentPool_new = currentPool_old + nextPool_old`, `nextPool_new = 0`. Total ETH conserved: `currentPool_new + nextPool_new = currentPool_old + nextPool_old`.
- **Remainder risk:** None -- exact value transfer, no division.
- **Notes:** This is the primary pool consolidation at level transitions. It runs on every level (not just x00). The nextPool accumulates ETH from purchases during the level, and at the next jackpot phase it becomes available in currentPool for daily distribution.

---

### SITE-CP-04: JackpotModule:consolidatePrizePools (keep-roll spillover) line 751
- **Operation:** currentPool += moveWei
- **Source/Dest:** moveWei = `fp - keepWei` where fp is futurePool. keepWei stays in futurePool (SITE-FP-05). moveWei flows from futurePool to currentPool.
- **Counterpart verified:** YES -- Cross-referenced with SITE-FP-05. `_setFuturePrizePool(keepWei)` at line 750 sets futurePool to keepWei. `_setCurrentPrizePool(_getCurrentPrizePool() + moveWei)` at line 751 adds moveWei to currentPool. `keepWei + moveWei = fp`. Full futurePool value accounted.
- **Remainder risk:** `keepWei = (fp * keepBps) / 10_000` truncates. moveWei = `fp - keepWei` captures the truncation. No untracked wei. See SITE-FP-05 for full analysis.
- **Notes:** Only fires on x00 levels when `keepBps < 10_000 && fp != 0 && moveWei != 0`.

---

### SITE-CP-05: GameOverModule:_runFinalJackpot (no-funds path) line 133
- **Operation:** currentPool = 0
- **Source/Dest:** Zeroing during game-over when `available == 0`. All pool ETH has already been distributed or was never present.
- **Counterpart verified:** YES -- Cross-referenced with SITE-FP-14. All four pools (next, future, current) and yieldAccumulator are zeroed simultaneously. The `available == 0` condition (line 129) means `totalFunds <= claimablePool`, so all ETH is already in claimablePool (player-withdrawable).
- **Remainder risk:** None -- zeroing to 0.
- **Notes:** `gameOverFinalJackpotPaid = true` (line 130) prevents re-entry.

---

### SITE-CP-06: GameOverModule:_runFinalJackpot (normal path) line 145
- **Operation:** currentPool = 0
- **Source/Dest:** Zeroing during game-over when `available != 0`. The `available` amount is then distributed via terminal decimator, terminal jackpot, and refund flows.
- **Counterpart verified:** YES -- Cross-referenced with SITE-FP-15. All pools zeroed (lines 143-146). `available = totalFunds - claimablePool` was computed at line 120 before zeroing. `remaining` variable (line 151) tracks `available` through the distribution cascade. Any undistributed `remaining` goes to claimablePool.
- **Remainder risk:** None -- zeroing to 0. The distribution of `available` uses various percentages (10% decimator, etc.) with truncation, but all remainder is tracked via the `remaining` variable.
- **Notes:** The `remaining` accumulator pattern ensures no ETH is lost during terminal distribution. After all distributions, any leftover `remaining` is added to claimablePool for pro-rata refund.

---

## Summary: futurePool + currentPool Audit

| Pool | Total Sites | Verified YES | Verified PARTIAL | Gaps Found |
|------|-------------|--------------|------------------|------------|
| futurePool | 23 | 22 | 1 (FP-02 committed code) | 0 (with Phase 183 fix) |
| currentPool | 6 | 6 | 0 | 0 |
| **Total** | **29** | **28** | **1** | **0** |

### Gaps

**SITE-FP-02 (committed code only):** In the pre-Phase-183 committed code, `_executeJackpot` return value `paidEth` is discarded. When trait buckets are empty, `ethPool - paidEth` exits futurePool but enters no tracked pool. **With Phase 183 fix applied (unstaged on main), this gap is closed.** The fix defers the futurePool deduction to after `_executeJackpot` returns, deducting only `lootboxBudget + paidEth`.

No other gaps found.

### Key Findings

- **All 23 futurePool sites and all 6 currentPool sites have verified counterparts** (with Phase 183 fix for FP-02)
- **Reserve contribution flows (SWEEP-04) fully traced:**
  - SITE-FP-01: reserveSlice (0.5% daily carryover) -> nextPool (line 397)
  - SITE-FP-03: reserveContribution (3% early-bird lootbox) -> nextPool (line 714)
  - SITE-FP-10: reserved (15% drawdown) -> nextPool (line 1192)
- **Phase 183 fix confirmed correct as baseline:** Deferred deduction `futurePool - lootboxBudget - paidEth` accounts for all consumed ETH. Unspent ETH from empty trait buckets remains in futurePool.
- **runRewardJackpots accumulator pattern (FP-08) is correctly reconciled:** Local accumulator tracks BAF/Decimator debits, rebuyDelta captures concurrent auto-rebuy writes to storage, final write merges both.
- **consolidatePrizePools (CP-03/CP-04 + FP-04/FP-05) is a balanced multi-step transfer:** nextPool -> currentPool (exact), futurePool -> currentPool (via keep-roll, truncation captured in moveWei), yieldAccumulator -> futurePool (half, truncation retained).
- **GameOver zeroing (FP-14/FP-15, CP-05/CP-06) is safe:** All pools zeroed atomically, `available` amount computed before zeroing and fully distributed via `remaining` accumulator.
- **INFO finding in MintModule (FP-20):** Triple-division truncation in lootbox split can leave up to 2 wei per purchase untracked in contract balance. This is captured by `_distributeYieldSurplus` which treats any `totalBal - obligations` surplus as yield. No practical risk.
- **Freeze-state accounting is consistent:** All dual-path sites (frozen/unfrozen) use equivalent amounts via `_setPendingPools`/`_setPrizePools`. `_unfreezePool` applies pending atomically. No accounting divergence between paths.
- **Auto-rebuy concurrent write reconciliation (FP-06, FP-08, FP-12):** Auto-rebuy paths can write to futurePool/nextPool storage during delegatecall execution. `runRewardJackpots` captures this via the rebuyDelta pattern. DecimatorModule auto-rebuy deducts from pre-reserved claimablePool.
