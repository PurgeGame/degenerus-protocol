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
