# SLOAD + Loop Hoisting Audit -- Daily Jackpot Hot Path

**Date:** 2026-03-25
**Scope:** Daily jackpot ETH distribution code path (worst case: 321 auto-rebuy winners, 4 populated buckets)
**Contract:** `contracts/modules/DegenerusGameJackpotModule.sol`
**Support:** `contracts/modules/DegenerusGamePayoutUtils.sol`, `contracts/storage/DegenerusGameStorage.sol`

---

## Scope

Functions audited for storage reads (SLOADs) in the daily jackpot hot path:

| Function | File:Lines | Role |
|----------|------------|------|
| `payDailyJackpot` | JackpotModule:323-607 | Init block (fresh start) + Phase 0/1 dispatch |
| `_processDailyEthChunk` | JackpotModule:1387-1510 | Outer bucket loop (4 iters) + inner winner loop (up to 321 total) |
| `_addClaimableEth` | JackpotModule:957-978 | Per-winner dispatch: normal vs auto-rebuy |
| `_processAutoRebuy` | JackpotModule:988-1028 | Auto-rebuy path: `_calcAutoRebuy` + `_queueTickets` + pool update |
| `_creditClaimable` | PayoutUtils:30-36 | Normal winner path: `claimableWinnings` SLOAD + SSTORE |
| `_clearDailyEthState` | JackpotModule:2785-2793 | Cleanup SSTOREs (6 variables zeroed) |
| `_randTraitTicketWithIndices` | JackpotModule:2283-2337 | Per-bucket winner selection from `traitBurnTicket` storage array |
| `_winnerUnits` | JackpotModule:1358-1364 | Per-winner unit cost (reads `autoRebuyState`) |

---

## SLOAD Inventory (GOPT-01)

Every storage read in the daily jackpot hot path, traced to EVM slot, with cold/warm classification and optimization verdict.

**Conventions:**
- **Cold SLOAD** = first access to a slot in the transaction = 2,100 gas
- **Warm SLOAD** = subsequent access to an already-loaded slot = 100 gas
- **Per-winner** = multiplied by winner count (up to 321 in worst case)
- **Per-bucket** = multiplied by bucket count (4 in worst case)
- **Per-call** = once per `payDailyJackpot` invocation (fixed cost)

### SLOAD Inventory Table

| # | Variable | Solidity Line | EVM Slot | Cold/Warm | Multiplicity | Count (321 winners) | Gas Per Read | Total Gas (321) | Verdict |
|---|----------|---------------|----------|-----------|-------------|---------------------|-------------|----------------|---------|
| 1 | `dailyEthPoolBudget` | payDailyJackpot:489 | Dedicated (Slot N) | Cold | Per-call | 1 | 2,100 | 2,100 | NECESSARY |
| 2 | `dailyEthPhase` | payDailyJackpot:488 | Slot 1 | Cold | Per-call | 1 | 2,100 | 2,100 | NECESSARY |
| 3 | `currentPrizePool` | payDailyJackpot:522 (SSTORE) | Slot 2 | Cold | Per-call | 1 | 2,100 | 2,100 | NECESSARY |
| 4 | `dailyCarryoverEthPool` | payDailyJackpot:547 | Dedicated (Slot N+M) | Cold | Per-call | 1 | 2,100 | 2,100 | NECESSARY |
| 5 | `dailyCarryoverWinnerCap` | payDailyJackpot:547 | Dedicated (Slot N+M+1 area) | Cold | Per-call | 1 | 2,100 | 2,100 | NECESSARY |
| 6 | `dailyTicketBudgetsPacked` | payDailyJackpot:483 | Dedicated | Cold | Per-call | 1 | 2,100 | 2,100 | NECESSARY |
| 7 | `jackpotCounter` | payDailyJackpot:484 | Slot 0 | Cold | Per-call | 1 | 2,100 | 2,100 | NECESSARY |
| 8 | `traitBurnTicket[lvl][trait].length` | _randTraitTicketWithIndices:2295 | Mapping keccak | Cold per bucket | Per-bucket | 4 | 2,100 | 8,400 | NECESSARY |
| 9 | `traitBurnTicket[lvl][trait][idx]` (holders array elements) | _randTraitTicketWithIndices:2325 | Mapping keccak | Cold per unique element | Per-winner | up to 321 | 2,100 | 674,100 | NECESSARY |
| 10 | `deityBySymbol[fullSymId]` | _randTraitTicketWithIndices:2304 | Mapping keccak | Cold per bucket | Per-bucket | 4 | 2,100 | 8,400 | NECESSARY |
| 11 | `autoRebuyState[beneficiary]` via `_winnerUnits` | _winnerUnits:1361 | Mapping keccak | Cold (unique addr) | Per-winner | 321 | 2,100 | 674,100 | **OPTIMIZE** |
| 12 | `gameOver` | _addClaimableEth:966 | Slot 0 | Warm (Slot 0 read at #7) | Per-winner | 321 | 100 | 32,100 | MARGINAL |
| 13 | `autoRebuyState[beneficiary]` via `_addClaimableEth` | _addClaimableEth:967 | Mapping keccak | Warm (same key read at #11) | Per-winner | 321 | 100 | 32,100 | ALREADY-OPTIMIZED |
| 14 | `level` | _processAutoRebuy:999 (via `_calcAutoRebuy`) | Slot 0 | Warm (Slot 0 read at #7) | Per-winner (auto-rebuy) | 321 | 100 | 32,100 | MARGINAL |
| 15 | `level` | _queueTickets:544 (via `targetLevel > level + 5`) | Slot 0 | Warm | Per-winner (auto-rebuy) | 321 | 100 | 32,100 | MARGINAL |
| 16 | `rngLockedFlag` | _queueTickets:545 | Slot 0 | Warm | Per-winner (auto-rebuy, FF only) | up to 321 | 100 | 32,100 | MARGINAL |
| 17 | `phaseTransitionActive` | _queueTickets:545 | Slot 0 | Warm | Per-winner (auto-rebuy, FF+locked) | up to 321 | 100 | 32,100 | MARGINAL |
| 18 | `ticketsOwedPacked[wk][buyer]` | _queueTickets:547 | Mapping keccak | Cold (unique key) | Per-winner (auto-rebuy) | 321 | 2,100 | 674,100 | NECESSARY |
| 19 | `prizePoolsPacked` | _setFuturePrizePool/_setNextPrizePool (via `_getPrizePools`) | Slot 3 | Cold first, warm after | Per-winner (auto-rebuy) | 321 (320 warm) | 100 (warm) | 2,100 + 32,000 = 34,100 | ALREADY-OPTIMIZED |
| 20 | `claimableWinnings[beneficiary]` | _creditClaimable:33 | Mapping keccak | Cold (unique addr) | Per-winner | 321 | 2,100 | 674,100 | NECESSARY |
| 21 | `claimablePool` | _processDailyEthChunk:1504-1505 | Dedicated | Cold | Per-call (end accumulation) | 1 | 2,100 | 2,100 | NECESSARY |
| 22 | `ticketQueue[wk].length` (push) | _queueTickets:551 | Mapping keccak | Cold first, warm after | Per-winner (auto-rebuy, first credit) | variable | 2,100 | variable | NECESSARY |
| 23 | `dailyEthBucketCursor` | _processDailyEthChunk:1413 | Slot 0 | Warm | Per-call | 1 | 100 | 100 | NECESSARY |
| 24 | `dailyEthWinnerCursor` | _processDailyEthChunk:1414 | Dedicated | Cold | Per-call | 1 | 2,100 | 2,100 | NECESSARY |

**Note on #11 and #13:** The `_winnerUnits(w)` function at line 1468 reads `autoRebuyState[winner].autoRebuyEnabled` -- a cold SLOAD (2,100 gas) per unique winner address. Then `_addClaimableEth` at line 967 reads `autoRebuyState[beneficiary]` again for the same address. Since the same mapping slot was already loaded by `_winnerUnits`, this second read is warm (100 gas). However, the `_winnerUnits` SLOAD is **redundant**: its only purpose is to compute a "unit cost" for the now-dead chunking budget system. Since the chunking budget (`unitsBudget`) early-return path at line 1469 is dead code (proven in Phase 95: 321 winners x 3 units = 963 < 1000 budget), the `_winnerUnits` call serves no purpose and wastes a cold SLOAD per winner.

---

## Per-Function SLOAD Breakdown

### `payDailyJackpot` Init + Phase 0 Dispatch (lines 323-557)

| Category | SLOADs | Gas |
|----------|--------|-----|
| Cold (per-call) | 7 (#1-7) | 14,700 |
| Warm (per-call) | 1 (#23 -- Slot 0 cursor) | 100 |
| **Total** | **8** | **14,800** |

These are fixed per-call costs. All are NECESSARY -- they read the daily jackpot state to determine budget, phase, and dispatch.

### `_processDailyEthChunk` (lines 1387-1510)

| Category | SLOADs | Gas (321 winners) |
|----------|--------|-------------------|
| Cold per-call | 2 (#21 claimablePool, #24 dailyEthWinnerCursor) | 4,200 |
| Cold per-bucket | 8 (#8 traitBurnTicket length x4, #10 deityBySymbol x4) | 16,800 |
| Cold per-winner via `_winnerUnits` | 321 (#11 autoRebuyState -- **REDUNDANT**) | 674,100 |
| **Subtotal chunk function** | **331** | **695,100** |

### `_addClaimableEth` (lines 957-978) -- called per winner

| Category | SLOADs | Gas per winner | Gas (321 winners) |
|----------|--------|---------------|-------------------|
| Warm | 1 (#12 gameOver -- Slot 0) | 100 | 32,100 |
| Warm | 1 (#13 autoRebuyState -- already loaded by `_winnerUnits`) | 100 | 32,100 |
| **Subtotal** | **2** | **200** | **64,200** |

### `_processAutoRebuy` (lines 988-1028) -- called per auto-rebuy winner

| Category | SLOADs | Gas per winner | Gas (321 winners) |
|----------|--------|---------------|-------------------|
| Warm | 1 (#14 level -- Slot 0) | 100 | 32,100 |
| Warm | 1-3 (#15 level, #16 rngLockedFlag, #17 phaseTransitionActive -- all Slot 0) | 100-300 | 32,100-96,300 |
| Cold | 1 (#18 ticketsOwedPacked -- unique key) | 2,100 | 674,100 |
| Warm | 1 (#19 prizePoolsPacked -- Slot 3, warm after first) | 100 | 34,100 |
| Cold | 1 (#20 claimableWinnings -- unique addr, if `calc.reserved != 0`) | 2,100 | 674,100 |
| **Subtotal (worst case)** | **~5** | **~4,600** | **~1,478,500** |

Note: `_creditClaimable` is called twice per auto-rebuy winner when `calc.reserved != 0` -- once via `_creditClaimable(player, calc.reserved)` at line 1017. However, the second SLOAD is warm (same `claimableWinnings[player]` slot). So the second `_creditClaimable` call costs only ~100 gas for the SLOAD.

### `_clearDailyEthState` (lines 2785-2793)

No SLOADs (only SSTOREs). Writes zeros to 6 storage variables. Gas is dominated by SSTOREs (slot-clear refunds may apply).

---

## SLOAD Optimization Candidates

### Candidate 1: `_winnerUnits` Redundant Cold SLOAD

| Property | Value |
|----------|-------|
| **Variable** | `autoRebuyState[winner]` |
| **Location** | `_winnerUnits` at line 1361, called from `_processDailyEthChunk` line 1468 |
| **Current behavior** | Cold SLOAD (2,100 gas) per winner to check `autoRebuyEnabled`, returns 1 or 3 "units" |
| **Why redundant** | The units budget system is dead code. `unitsBudget = DAILY_JACKPOT_UNITS_SAFE = 1000`. With max 321 winners at 3 units each = 963 < 1000, the budget check at line 1469 (`unitsUsed + cost > unitsBudget`) can NEVER trigger. The early-return path (cursor save, `return (paidEth, false)`) is unreachable. |
| **Optimization** | Remove `_winnerUnits` call and the entire unit budget system (`unitsUsed`, `unitsBudget` parameter, cursor-save path). This eliminates the cold SLOAD per winner. |
| **Gas saved** | 2,100 gas/winner x 321 winners = **674,100 gas** |
| **Complexity** | Low -- remove dead code (already proven dead in Phase 95 analysis) |
| **Risk** | None -- behavioral equivalence proven: the chunking budget path was unreachable |
| **Recommendation** | **IMPLEMENT** (already done in Phase 95 refactor; this audit confirms the savings are real) |

**Important note:** This optimization was already identified and recommended in Phase 95's dead code removal analysis. If the Phase 95 refactor has been applied to the deployed contract, this SLOAD is already eliminated. The code in the current worktree still contains `_winnerUnits` -- this audit documents the savings that Phase 95's removal achieves.

### Candidate 2: `gameOver` Warm SLOAD Per Winner

| Property | Value |
|----------|-------|
| **Variable** | `gameOver` (packed in Slot 0, byte offset 28) |
| **Location** | `_addClaimableEth` at line 966 |
| **Current behavior** | Warm SLOAD (100 gas) per winner -- Slot 0 was already loaded in the `payDailyJackpot` preamble |
| **Optimization** | Pass `gameOver` as a `bool` parameter to `_addClaimableEth` instead of re-reading storage |
| **Gas saved** | 100 gas/winner x 321 winners = **32,100 gas** |
| **Complexity** | Low -- add one `bool` parameter to `_addClaimableEth` and all callers |
| **Risk** | Negligible -- `gameOver` is immutable within a transaction (only set by `_setGameOver`, which is a separate advanceGame stage) |
| **Recommendation** | **SKIP** -- 32,100 gas savings is marginal (0.23% of 14M ceiling). Adding a parameter to `_addClaimableEth` affects all call sites across multiple modules. The function signature change would ripple through `_runEarlyBirdLootboxJackpot`, `_yieldSkim`, `_distributeJackpotEth`, and other callers. The code complexity cost outweighs the gas benefit. |

### Candidate 3: `level` Warm SLOAD Per Auto-Rebuy Winner

| Property | Value |
|----------|-------|
| **Variable** | `level` (packed in Slot 0, byte offset 18-20) |
| **Location** | `_processAutoRebuy` at line 999 (via `_calcAutoRebuy`), `_queueTickets` at line 544 |
| **Current behavior** | Warm SLOAD (100 gas) per auto-rebuy winner -- Slot 0 already loaded |
| **Optimization** | Pass `level` as a parameter to `_processAutoRebuy` and `_queueTickets` |
| **Gas saved** | 100-200 gas/winner x 321 winners = **32,100-64,200 gas** |
| **Complexity** | Medium -- `_queueTickets` is called from 12+ sites across the codebase. Changing its signature is a widespread refactor. |
| **Risk** | Low -- `level` does not change within a single advanceGame call |
| **Recommendation** | **SKIP** -- 32-64K gas savings (0.23-0.46% of 14M ceiling) does not justify touching 12+ call sites. The warm SLOAD cost (100 gas) is already near-optimal. |

### Candidate 4: `rngLockedFlag` / `phaseTransitionActive` in `_queueTickets`

| Property | Value |
|----------|-------|
| **Variable** | `rngLockedFlag`, `phaseTransitionActive` (both Slot 0) |
| **Location** | `_queueTickets` at line 545 |
| **Current behavior** | Warm SLOAD (100 gas each) per auto-rebuy winner for the `if (isFarFuture && rngLockedFlag && !phaseTransitionActive) revert` guard |
| **Optimization** | These reads are only needed when `isFarFuture` is true (ticket target > level + 5). For near-future tickets, the guard short-circuits. During daily jackpot processing, `phaseTransitionActive` is true, so the revert never fires regardless. |
| **Gas saved** | 0-200 gas/winner x 321 = **0-64,200 gas** (depends on how many are far-future) |
| **Recommendation** | **SKIP** -- already guarded by `isFarFuture` short-circuit. These are warm SLOADs (Slot 0) at 100 gas each. Negligible. |

---

## Cumulative SLOAD Summary

### Worst Case: 321 Auto-Rebuy Winners, 4 Populated Buckets

| Category | SLOAD Count | Total Gas |
|----------|-------------|-----------|
| **Per-call fixed (cold)** | 10 | 21,000 |
| **Per-bucket (cold)** | 8 | 16,800 |
| **Per-winner cold (unavoidable -- unique addresses)** | | |
| -- `autoRebuyState[addr]` (via `_winnerUnits`) | 321 | 674,100 |
| -- `autoRebuyState[addr]` (via `_addClaimableEth`, warm) | 321 | 32,100 |
| -- `claimableWinnings[addr]` | 321 | 674,100 |
| -- `ticketsOwedPacked[wk][addr]` | 321 | 674,100 |
| **Per-winner cold (array element reads)** | | |
| -- `traitBurnTicket[lvl][trait][idx]` (holder addresses) | up to 321 | 674,100 |
| **Per-winner warm (Slot 0 packed)** | | |
| -- `gameOver` | 321 | 32,100 |
| -- `level` (2 reads: `_calcAutoRebuy` + `_queueTickets`) | 642 | 64,200 |
| -- `rngLockedFlag` / `phaseTransitionActive` | up to 642 | 64,200 |
| **Per-winner warm (Slot 3 packed)** | | |
| -- `prizePoolsPacked` | 321 | 34,100 |
| **Total** | **~3,549** | **~2,962,900** |

### Breakdown: Unavoidable vs Optimizable

| Classification | Gas | % of SLOAD Total |
|----------------|-----|-------------------|
| **Unavoidable** (unique per-address mappings + per-bucket storage) | 2,055,000 | 69.4% |
| **Already-optimized** (warm reads of packed slots) | 226,600 | 7.6% |
| **Optimizable** (`_winnerUnits` redundant cold SLOAD) | 674,100 | 22.7% |
| **Marginal** (warm SLOADs that could be passed as params) | ~7,200 | 0.2% |
| **Total** | **~2,962,900** | **100%** |

### SLOAD Gas as Percentage of Total Gas Budget

- Total gas budget: 14,000,000 (14M ceiling)
- Estimated total gas for Stage 11 (321 auto-rebuy winners): ~13,400,000-14,200,000
- SLOAD gas: ~2,962,900 (21.2% of budget)
- Unavoidable SLOAD gas: ~2,055,000 (14.7% of budget)
- The single optimizable SLOAD (`_winnerUnits`): 674,100 (4.8% of budget)

### SSTORE Gas Summary (For Context)

SSTOREs are not the focus of this audit, but for completeness:

| Variable | Per-Call Count | Gas Per Write | Total Gas (321) | Notes |
|----------|---------------|--------------|-----------------|-------|
| `claimableWinnings[addr]` | 321 | 5,000 (nonzero-to-nonzero) or 22,100 (zero-to-nonzero) | 1,605,000 - 7,094,100 | Dominant SSTORE cost |
| `ticketsOwedPacked[wk][addr]` | 321 | 5,000 or 22,100 | 1,605,000 - 7,094,100 | Second-largest SSTORE cost |
| `prizePoolsPacked` | 321 | 5,000 (warm) | 1,605,000 | Per-winner pool update |
| `claimablePool` | 1 | 5,000 | 5,000 | Accumulated at end |
| `currentPrizePool` | 1 | 5,000 | 5,000 | Deducted after chunk |
| `ticketQueue[wk]` (push) | variable | 22,100 (new entry) | variable | Only on first credit per player per wk |

The SSTORE costs for `claimableWinnings` and `ticketsOwedPacked` dwarf the SLOAD costs. These are unavoidable -- each unique winner address requires a storage write.

---

## Loop Hoisting Audit (GOPT-02)

Every loop in the daily jackpot hot path analyzed for loop-invariant computation that could be hoisted above the loop.

### Loop Inventory

| Loop | Location (file:line) | Bound | Iterations (worst case) | Body Contains |
|------|----------------------|-------|------------------------|---------------|
| L1: `_processDailyEthChunk` outer bucket loop | JackpotModule:1427 (`for j < 4`) | 4 (constant) | 4 | `_randTraitTicketWithIndices`, `EntropyLib.entropyStep`, share/count arithmetic, inner loop L2 |
| L2: `_processDailyEthChunk` inner winner loop | JackpotModule:1466 (`for i < len`) | `winners.length` per bucket, up to 250 | 321 total across 4 buckets | `_winnerUnits(w)`, `_addClaimableEth(w, perWinner, entropyState)`, `emit JackpotTicketWinner`, `paidEth +=`, `liabilityDelta +=` |
| L3: `_addClaimableEth` (per-winner function call) | JackpotModule:957-978 | N/A (called per L2 iteration) | 321 | `gameOver` check, `autoRebuyState` read, branch to `_processAutoRebuy` or `_creditClaimable` |
| L4: `_processAutoRebuy` (per-auto-rebuy-winner call) | JackpotModule:988-1028 | N/A (called per L3 auto-rebuy branch) | up to 321 | `_calcAutoRebuy` (pure), `_queueTickets`, `_setFuturePrizePool`/`_setNextPrizePool`, `_creditClaimable` (if reserved), `emit AutoRebuyProcessed` |
| L5: `_runEarlyBirdLootboxJackpot` winner loop | JackpotModule:829 (`for i < 100`) | 100 (constant) | 100 (Day 1 only) | `EntropyLib.entropyStep`, `_randTraitTicket`, `_queueTickets`, `levelPrices[offset]` lookup |
| L6: `_runEarlyBirdLootboxJackpot` price precompute loop | JackpotModule:819 (`for l < 5`) | 5 (constant) | 5 (Day 1 only) | `PriceLookupLib.priceForLevel(baseLevel + l)` -- precomputes prices for L5 |
| L7: `_randTraitTicketWithIndices` winner selection loop | JackpotModule:2322 (`for i < numWinners`) | `numWinners` (up to 250 per bucket) | up to 321 total | `slice % effectiveLen`, `holders[idx]` storage read, bit rotation |

### Per-Loop Hoisting Analysis

#### L1: Outer Bucket Loop (4 iterations)

**Expressions evaluated per iteration:**

| Expression | Line | Invariant? | Analysis |
|------------|------|------------|----------|
| `order[j]` | 1428 | NOT-INVARIANT | Depends on iteration variable `j` |
| `bucketCounts[traitIdx]` | 1429 | NOT-INVARIANT | `traitIdx` varies per iteration |
| `shares[traitIdx]` | 1430 | NOT-INVARIANT | `traitIdx` varies per iteration |
| `EntropyLib.entropyStep(...)` | 1436-1438 | NOT-INVARIANT | Input includes `traitIdx` and `share` which vary |
| `_randTraitTicketWithIndices(traitBurnTicket[lvl], ...)` | 1447-1453 | NOT-INVARIANT | `traitIds[traitIdx]`, `totalCount`, and entropy vary per bucket |
| `perWinner = share / totalCount` | 1459 | NOT-INVARIANT | Both `share` and `totalCount` are per-bucket |

**Verdict:** All expressions in L1 body depend on the iteration variable `traitIdx`. No loop-invariant computation to hoist.

**Pre-loop hoisted computations (confirmed ALREADY-HOISTED):**

| Computation | Line | Status |
|-------------|------|--------|
| `PriceLookupLib.priceForLevel(lvl + 1) >> 2` | 1400 | ALREADY-HOISTED -- computed as `unit` before L1 |
| `JackpotBucketLib.soloBucketIndex(entropy)` | 1401 | ALREADY-HOISTED -- computed as `remainderIdx` before L1 |
| `JackpotBucketLib.bucketShares(ethPool, shareBps, bucketCounts, remainderIdx, unit)` | 1402-1408 | ALREADY-HOISTED -- computed as `shares[4]` memory array before L1 |
| `JackpotBucketLib.bucketOrderLargestFirst(bucketCounts)` | 1410-1412 | ALREADY-HOISTED -- computed as `order[4]` memory array before L1 |

#### L2: Inner Winner Loop (up to 250 per bucket, 321 total)

**Expressions evaluated per iteration:**

| Expression | Line | Invariant? | Analysis |
|------------|------|------------|----------|
| `winners[i]` | 1467 | NOT-INVARIANT | Depends on `i` |
| `_winnerUnits(w)` | 1468 | NOT-INVARIANT | Depends on `w` (per-winner address) |
| `unitsUsed + cost > unitsBudget` | 1469 | NOT-INVARIANT | `unitsUsed` accumulates, `cost` varies by winner |
| `_addClaimableEth(w, perWinner, entropyState)` | 1479-1483 | NOT-INVARIANT (w varies) | `w` is per-winner; `perWinner` and `entropyState` are invariant within this inner loop |
| `perWinner` (value used in _addClaimableEth) | 1459 | INVARIANT within L2 | Computed at L1 level: `share / totalCount`. Same for all winners in this bucket. |
| `entropyState` (passed to _addClaimableEth) | 1436-1438 | INVARIANT within L2 | Computed once per bucket (L1 level). Does not change across L2 iterations. |
| `traitIds[traitIdx]` (in emit) | 1487 | INVARIANT within L2 | Fixed for this bucket iteration |
| `emit JackpotTicketWinner(...)` | 1484-1490 | NOT-INVARIANT | Per-winner event with `w`, `ticketIndexes[i]` |

**Invariant within L2 but already used correctly:**
- `perWinner` -- computed before L2 at L1 level (line 1459). Correctly used as-is.
- `entropyState` -- computed before L2 at L1 level (line 1436-1438). Correctly used as-is.
- `traitIds[traitIdx]` -- fixed for this bucket. Correctly used as-is.

**Verdict:** `perWinner` and `entropyState` are already computed above L2 (at L1 level) and passed into L2 body calls. No additional hoisting opportunity.

#### L3: `_addClaimableEth` (called per winner)

**Expressions evaluated per call:**

| Expression | Line | Invariant across calls? | Analysis |
|------------|------|------------------------|----------|
| `gameOver` storage read | 966 | YES (invariant) | `gameOver` does not change during daily jackpot processing. Could be hoisted to caller and passed as parameter. |
| `autoRebuyState[beneficiary]` | 967 | NO | Different beneficiary each call |
| `state.autoRebuyEnabled` | 968 | NO | Per-winner state |

**`gameOver` as hoisting candidate:** This is a warm SLOAD (Slot 0, 100 gas per winner). See SLOAD Candidate 2 above. The compiler may optimize this: the `via_ir` pipeline with SSA analysis can detect that `gameOver` is invariant within the call (no SSTORE to Slot 0 between reads). If so, the compiler would cache it in a register after the first read. Empirical measurement would be needed to confirm compiler behavior.

#### L4: `_processAutoRebuy` (called per auto-rebuy winner)

**Expressions evaluated per call:**

| Expression | Line | Invariant across calls? | Analysis |
|------------|------|------------------------|----------|
| `level` (passed to `_calcAutoRebuy`) | 999 | YES (invariant) | `level` does not change during jackpot processing. Warm Slot 0 read. |
| `13_000` (bonusBps constant) | 1000 | YES | Literal constant, zero gas |
| `14_500` (bonusBpsAfKing constant) | 1001 | YES | Literal constant, zero gas |
| `_calcAutoRebuy(...)` (pure function) | 994-1002 | NO | Arguments vary per winner (`player`, `newAmount`, `entropy`, `state`) |
| `_queueTickets(player, calc.targetLevel, calc.ticketCount)` | 1008 | NO | Per-winner arguments |
| `_setFuturePrizePool(_getFuturePrizePool() + calc.ethSpent)` | 1011 | NO | `ethSpent` varies, and `prizePoolsPacked` is read-modify-write per call |
| `_setNextPrizePool(_getNextPrizePool() + calc.ethSpent)` | 1013 | NO | Same as above |
| `_creditClaimable(player, calc.reserved)` | 1017 | NO | Per-winner |

**`level` as hoisting candidate:** See SLOAD Candidate 3 above. `_processAutoRebuy` already receives `state` (AutoRebuyState) as a parameter. Adding `level` would be straightforward but affects the function signature. The warm SLOAD cost (100 gas) makes this marginal.

**`prizePoolsPacked` read-modify-write accumulation:** Each auto-rebuy winner reads `prizePoolsPacked` (SLOAD, warm after first = 100 gas), adds `ethSpent`, and writes it back (SSTORE, warm = 5,000 gas). The SLOAD is unavoidable because each write changes the value for the next read. However, the write cost dominates (5,000 >> 100). An alternative would be to accumulate `ethSpent` totals in memory (split by `toFuture` flag) and do a single SSTORE at the end. This would save ~320 SSTOREs x 5,000 = 1,600,000 gas but requires restructuring the prize pool update to batch. **This is an architectural change (Rule 4 territory) -- flagging for GOPT-03 consideration.**

#### L5: `_runEarlyBirdLootboxJackpot` Winner Loop (100 iterations, Day 1 only)

**Expressions evaluated per iteration:**

| Expression | Line | Invariant? | Analysis |
|------------|------|------------|----------|
| `EntropyLib.entropyStep(entropy)` | 830 | NOT-INVARIANT | Chained -- each call feeds the next |
| `uint8(entropy)` | 831 | NOT-INVARIANT | Derived from changing entropy |
| `_randTraitTicket(traitBurnTicket[lvl], ...)` | 832-838 | NOT-INVARIANT | `entropy`, `traitId`, `salt` all vary |
| `EntropyLib.entropyStep(entropy)` (second) | 842 | NOT-INVARIANT | Chained |
| `uint24(entropy % 5)` | 843 | NOT-INVARIANT | Derived from changing entropy |
| `levelPrices[levelOffset]` | 844 | NOT-INVARIANT | `levelOffset` varies; but `levelPrices` array is invariant |
| `perWinnerEth` | 815 | INVARIANT | Computed before loop: `totalBudget / 100`. Same for all winners. |
| `perWinnerEth / ticketPrice` | 846 | NOT-INVARIANT | `ticketPrice` varies per winner |

**Already-hoisted computations (confirmed):**

| Computation | Line | Status |
|-------------|------|--------|
| `levelPrices[0..4]` precomputed via L6 | 819-826 | ALREADY-HOISTED -- `PriceLookupLib.priceForLevel` called 5 times before loop, results cached in memory array |
| `perWinnerEth = totalBudget / maxWinners` | 815 | ALREADY-HOISTED -- computed before loop |

**Verdict:** L5 is well-optimized. The expensive `PriceLookupLib.priceForLevel` calls are precomputed in L6 and cached in the `levelPrices` memory array. `perWinnerEth` is pre-computed. No hoisting opportunities.

#### L6: Price Precompute Loop (5 iterations, Day 1 only)

This loop IS the hoisting mechanism for L5. It precomputes `PriceLookupLib.priceForLevel` for 5 levels before the 100-winner loop. At 5 iterations of a pure library call, the gas cost is negligible (~1,000 gas total).

**Verdict:** ALREADY-HOISTED (this loop is itself the optimization for L5).

#### L7: `_randTraitTicketWithIndices` Winner Selection Loop (up to 250 per call)

**Expressions evaluated per iteration:**

| Expression | Line | Invariant? | Analysis |
|------------|------|------------|----------|
| `slice % effectiveLen` | 2323 | NOT-INVARIANT | `slice` rotates each iteration |
| `holders[idx]` | 2325 | NOT-INVARIANT | `idx` varies (but this is a storage array read -- cold SLOAD) |
| `deity` | 2328 | INVARIANT | Same deity address for all iterations in this call |
| `effectiveLen` | 2311 | INVARIANT | Computed before loop from `len + virtualCount` |

**`deity` and `effectiveLen` are already hoisted.** Both are computed before the loop (lines 2301-2311) and used as-is inside. The `holders[idx]` reads are unavoidable cold SLOADs (unique storage array elements).

**Verdict:** No hoisting opportunities. `deity` and `effectiveLen` are already pre-computed.

### Hoisting Verdicts Table

| # | Computation | Loop | Invariant? | Current Gas (321 winners) | If Hoisted | Savings | Verdict |
|---|-------------|------|------------|--------------------------|------------|---------|---------|
| H1 | `PriceLookupLib.priceForLevel(lvl+1) >> 2` | L1 | Yes | N/A | N/A | 0 | ALREADY-HOISTED |
| H2 | `JackpotBucketLib.soloBucketIndex(entropy)` | L1 | Yes | N/A | N/A | 0 | ALREADY-HOISTED |
| H3 | `JackpotBucketLib.bucketShares(...)` | L1 | Yes | N/A | N/A | 0 | ALREADY-HOISTED |
| H4 | `JackpotBucketLib.bucketOrderLargestFirst(...)` | L1 | Yes | N/A | N/A | 0 | ALREADY-HOISTED |
| H5 | `perWinner = share / totalCount` | L2 (within L1) | Yes (within L2) | N/A | N/A | 0 | ALREADY-HOISTED (computed at L1 level) |
| H6 | `entropyState` | L2 (within L1) | Yes (within L2) | N/A | N/A | 0 | ALREADY-HOISTED (computed at L1 level) |
| H7 | `gameOver` check in `_addClaimableEth` | L2 (via L3) | Yes | 32,100 (warm SLOAD) | 0 (pass as param) | 32,100 | SKIP (marginal, wide callsite impact) |
| H8 | `level` in `_processAutoRebuy` | L2 (via L4) | Yes | 32,100 (warm SLOAD) | 0 (pass as param) | 32,100 | SKIP (marginal, 12+ callsites) |
| H9 | `level` in `_queueTickets` | L2 (via L4) | Yes | 32,100 (warm SLOAD) | 0 (pass as param) | 32,100 | SKIP (marginal, 12+ callsites) |
| H10 | `levelPrices[0..4]` precompute | L5 (via L6) | Yes | N/A | N/A | 0 | ALREADY-HOISTED (L6 is the hoist) |
| H11 | `perWinnerEth` in earlybird | L5 | Yes | N/A | N/A | 0 | ALREADY-HOISTED |
| H12 | `deity` in `_randTraitTicketWithIndices` | L7 | Yes | N/A | N/A | 0 | ALREADY-HOISTED |
| H13 | `effectiveLen` in `_randTraitTicketWithIndices` | L7 | Yes | N/A | N/A | 0 | ALREADY-HOISTED |
| H14 | `prizePoolsPacked` accumulation in `_processAutoRebuy` | L2 (via L4) | NO (read-modify-write) | ~1,634,100 (320 warm SSTOREs) | ~5,200 (1 SSTORE) | ~1,600,000 | NOT-INVARIANT (see note below) |

**Note on H14 (prizePoolsPacked batching):** Each auto-rebuy winner calls `_setFuturePrizePool` or `_setNextPrizePool`, which reads `prizePoolsPacked`, modifies one half, and writes back. With 321 auto-rebuy winners, this is 321 read-modify-write cycles. The SSTOREs (5,000 gas warm) dominate. An alternative is to accumulate `nextPoolDelta` and `futurePoolDelta` in memory across all winners, then write once at the end. This would save ~320 warm SSTOREs = ~1,600,000 gas. However, this requires restructuring `_processAutoRebuy` to return pool deltas instead of writing directly, and restructuring `_processDailyEthChunk` to accumulate and apply them. This is an **architectural change** requiring careful analysis of all callers of `_processAutoRebuy` and `_addClaimableEth` (used in 6+ contexts beyond daily jackpot). Flagging for GOPT-03 consideration.

---

## Optimization Summary

### Combined Findings (SLOAD Audit + Loop Hoisting)

Ranked by gas impact:

| Rank | Optimization | Gas Savings | Complexity | Status | Recommendation |
|------|-------------|------------|------------|--------|---------------|
| 1 | **Remove `_winnerUnits` dead code** (SLOAD #11) | 674,100 | Low | Identified in Phase 95 | **IMPLEMENT** via Phase 95 chunk removal (already planned) |
| 2 | **Batch `prizePoolsPacked` writes** (H14) | ~1,600,000 | High | New finding | **DEFER** -- architectural change, requires restructuring _processAutoRebuy return values and all callers. Flag for future optimization if gas ceiling becomes critical. |
| 3 | **Pass `gameOver` as parameter** (SLOAD #12 / H7) | 32,100 | Low-Medium | New finding | **SKIP** -- 0.23% of ceiling, affects 6+ callsites across modules |
| 4 | **Pass `level` as parameter** (SLOAD #14-15 / H8-H9) | 32,100-64,200 | Medium | Known | **SKIP** -- 0.23-0.46% of ceiling, affects 12+ callsites |
| 5 | **Pass `rngLockedFlag`/`phaseTransitionActive` as params** (SLOAD #16-17) | 0-64,200 | Medium | Known | **SKIP** -- already short-circuited by `isFarFuture` |

### Summary Verdict

**Actionable optimizations for GOPT-03: 1 (the Phase 95 `_winnerUnits` removal)**

The daily jackpot hot path is well-optimized. Key findings:

1. **All library computations are already hoisted above the loop.** `PriceLookupLib.priceForLevel`, `JackpotBucketLib.soloBucketIndex`, `bucketShares`, and `bucketOrderLargestFirst` are computed once before the 4-bucket outer loop. Per-bucket values (`perWinner`, `entropyState`) are computed at the L1 level and reused across L2 iterations. The earlybird loop pre-caches `levelPrices[5]` via a dedicated precompute loop.

2. **The dominant cost is unavoidable per-address cold SLOADs and SSTOREs.** Each unique winner requires cold reads of `autoRebuyState[addr]` (2,100), `claimableWinnings[addr]` (2,100), `ticketsOwedPacked[wk][addr]` (2,100), and `traitBurnTicket[lvl][trait][idx]` (2,100) -- plus corresponding SSTOREs for `claimableWinnings` (5,000-22,100) and `ticketsOwedPacked` (5,000-22,100). These are inherent to the per-winner processing model and cannot be optimized without changing the data model.

3. **The only significant optimizable SLOAD is the `_winnerUnits` dead code** -- already targeted by Phase 95's chunk removal refactor. Removing it saves 674,100 gas (4.8% of the 14M ceiling).

4. **The `prizePoolsPacked` batching opportunity (H14)** could save ~1.6M gas but requires architectural changes to `_processAutoRebuy` return values, accumulation in `_processDailyEthChunk`, and careful review of all other callers. This is disproportionate in complexity for a function that is already near its gas ceiling.

5. **Warm SLOAD optimizations (gameOver, level, rngLockedFlag)** save 32K-64K gas each -- marginal at 0.23-0.46% of the 14M ceiling. The `via_ir` compiler may already be caching these register-level. Not worth the function signature changes.

**Recommendation for GOPT-03:** If the Phase 95 chunk removal has been applied, no additional code changes are recommended for the daily jackpot hot path. The remaining gas costs are dominated by unavoidable per-address storage operations. If further gas reduction is needed in the future, the `prizePoolsPacked` batching (H14) is the only remaining opportunity with meaningful impact, but it requires architectural review.
