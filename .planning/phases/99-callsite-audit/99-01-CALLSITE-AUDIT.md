# Phase 99: Callsite Audit -- _processAutoRebuy and prizePoolsPacked Writes

**Phase:** 99-callsite-audit
**Date:** 2026-03-25
**Requirements:** CALL-01, CALL-02
**Scope:** JackpotModule only -- _processDailyEthChunk and _runEarlyBirdLootboxJackpot paths
**Read-only analysis -- no code changes made**

---

## 1. Scope Statement

### In Scope

- `_processDailyEthChunk` (JM:1387) and its call tree, including `_addClaimableEth` (JM:957) and `_processAutoRebuy` (JM:988), in `DegenerusGameJackpotModule.sol`
- `_runEarlyBirdLootboxJackpot` (JM:801) and its call tree, in `DegenerusGameJackpotModule.sol`
- All `_setFuturePrizePool` and `_setNextPrizePool` calls within these two functions and their transitive callees
- Storage mechanics of `prizePoolsPacked` in `DegenerusGameStorage.sol`

### Out of Scope (per D-01, D-02)

- `DegenerusGameDecimatorModule._processAutoRebuy` -- separate implementation with different signature (returns bool), different call pattern
- `DegenerusGameEndgameModule` -- endgame-specific auto-rebuy-like loops
- Non-loop `prizePoolsPacked` writes across the protocol (26 callsites in 7 modules) -- these are one-shot writes, not loop-iterated
- `payDailyCoinJackpot` / `payDailyJackpotCoinAndTickets` -- distribute coins/tickets, not ETH

---

## 2. CALL-01 -- _processAutoRebuy Callsite Inventory

### Confirmed Constants

| Constant | Value | Source |
|----------|-------|--------|
| `MAX_BUCKET_WINNERS` | 250 | JM:183 |
| `DAILY_ETH_MAX_WINNERS` | 321 | JM:193 |
| `DAILY_JACKPOT_UNITS_AUTOREBUY` | 3 | JM:167 |
| `DAILY_JACKPOT_UNITS_SAFE` | 1000 | JM:164 |

### Callsite Table

| # | Callsite | File:Line | Called By | Condition | Iterations Per Execution | Notes |
|---|----------|-----------|-----------|-----------|--------------------------|-------|
| 1 | `_addClaimableEth` -> `_processAutoRebuy` | JM:970 | `_processDailyEthChunk` Phase 0 winner loop (JM:1479) | `!gameOver && autoRebuyEnabled` | Up to 250 per bucket x 4 buckets, total capped at 321 across all buckets. Chunk system (`unitsBudget=1000`) may split across multiple txs. | Main daily ETH path. Auto-rebuy winners cost 3 units each, non-rebuy winners cost 1 unit each. |
| 2 | `_addClaimableEth` -> `_processAutoRebuy` | JM:970 | `_processDailyEthChunk` Phase 1 carryover (JM:590) | `!gameOver && autoRebuyEnabled` | Up to 321 additional (minus Phase 0 count, floored at `DAILY_CARRYOVER_MIN_WINNERS`). | Second `advanceGame` call; same loop structure as Phase 0, different source level and winner cap. |
| 3 | `_runEarlyBirdLootboxJackpot` | JM:801 | `advanceGame` Day 1 only (JM:381) | `isEarlyBirdDay == true` (counter == 0) | **0 -- does NOT call `_processAutoRebuy`** | Uses `_queueTickets` directly for 100 winners; 2 fixed pool writes outside loop. |

### Call Tree Diagram

```
advanceGame
|
|-- [Day 1 only: isEarlyBirdDay] _runEarlyBirdLootboxJackpot (JM:801)
|   |-- _setFuturePrizePool (JM:807)          <- 1 SSTORE, deduct reserveContribution
|   |-- loop (<=100 winners):
|   |   `-- _queueTickets (JM:848)            <- NO pool writes
|   `-- _setNextPrizePool (JM:863)            <- 1 SSTORE, add totalBudget
|
|-- _processDailyEthChunk Phase 0 (JM:513, current level)
|   `-- loop (<=321 winners across 4 buckets, 250 max per bucket):
|       `-- _addClaimableEth (JM:1479)
|           `-- [if !gameOver && autoRebuyEnabled] _processAutoRebuy (JM:970->988)
|               |-- _calcAutoRebuy (JM:994)
|               |-- [if !calc.hasTickets] _creditClaimable -> return (NO pool write)
|               |-- _queueTickets (JM:1008)
|               `-- [if calc.toFuture]  _setFuturePrizePool (JM:1011) <- 1 SSTORE
|                   [if !calc.toFuture] _setNextPrizePool (JM:1013)   <- 1 SSTORE
|                   (mutually exclusive; at most 1 SSTORE per rebuy winner)
|
`-- _processDailyEthChunk Phase 1 (JM:590, carryover level)
    `-- loop (<=321 winners across 4 buckets, 250 max per bucket):
        `-- _addClaimableEth (JM:1479)
            `-- [if !gameOver && autoRebuyEnabled] _processAutoRebuy (JM:970->988)
                `-- (same as Phase 0 above)
```

### Chunk System Note

The `_processDailyEthChunk` function processes winners in gas-bounded chunks using a `unitsBudget` (default 1000 units). Each non-rebuy winner costs 1 unit; each auto-rebuy winner costs 3 units (`DAILY_JACKPOT_UNITS_AUTOREBUY`). When the budget is exhausted mid-bucket, the function saves cursor state (`dailyEthBucketCursor`, `dailyEthWinnerCursor`) and returns `complete=false`, resuming in the next `advanceGame` transaction. For worst-case SSTORE analysis, we consider the total across all chunks of a single phase.

---

## 3. CALL-02 -- prizePoolsPacked Write Map (In-Scope Paths)

### Write Table

| # | Function | File:Line | Slot Written | Condition | Frequency Per Execution | Loop-Iterated? |
|---|----------|-----------|-------------|-----------|-------------------------|----------------|
| 1 | `_runEarlyBirdLootboxJackpot` | JM:807 | future (high 128 bits) | `reserveContribution > 0` (always true unless futurePool is 0) | 1x per earlybird execution | No -- outside loop |
| 2 | `_runEarlyBirdLootboxJackpot` | JM:863 | next (low 128 bits) | Always (after loop completes) | 1x per earlybird execution | No -- outside loop |
| 3 | `_processAutoRebuy` | JM:1011 | future (high 128 bits) | `calc.hasTickets && calc.toFuture` | 0 to N per execution (N = winners with auto-rebuy and tickets targeting future level) | **YES -- per-winner** |
| 4 | `_processAutoRebuy` | JM:1013 | next (low 128 bits) | `calc.hasTickets && !calc.toFuture` | 0 to N per execution (N = winners with auto-rebuy and tickets targeting next level) | **YES -- per-winner** |

**Note:** Rows 3 and 4 are mutually exclusive per winner call -- each auto-rebuy winner produces at most 1 SSTORE to `prizePoolsPacked`. The `calc.toFuture` flag depends on whether the target level is the immediate next level or a further-future level.

### Out-of-Scope Setup Writes (for context only)

These `prizePoolsPacked` writes occur in `advanceGame` setup, BEFORE `_processDailyEthChunk` runs:

| Location | File:Line | Purpose | Warm/Cold |
|----------|-----------|---------|-----------|
| Daily lootbox budget | JM:404 | `_setNextPrizePool(... + dailyLootboxBudget)` | May be first write (cold) |
| `_runEarlyBirdLootboxJackpot` deduct | JM:807 | `_setFuturePrizePool(... - reserveContribution)` | Day 1 only |
| `_runEarlyBirdLootboxJackpot` add | JM:863 | `_setNextPrizePool(... + totalBudget)` | Day 1 only |

These writes make the `prizePoolsPacked` slot warm before `_processAutoRebuy` fires its first per-winner SSTORE.

---

## 4. SSTORE Gas Baseline (per D-03)

### Storage Slot Mechanics

- `prizePoolsPacked` is a single storage slot (Storage.sol line ~349)
- Low 128 bits: `nextPrizePool`; High 128 bits: `futurePrizePool`
- Both `_setNextPrizePool` (Storage.sol:749-751) and `_setFuturePrizePool` (Storage.sol:761-763) do a full read-modify-write: 1 SLOAD of `prizePoolsPacked` + 1 SSTORE of `prizePoolsPacked`
- After the first write in a transaction, subsequent writes cost the warm SSTORE rate (100 gas per EIP-2929, nonzero-to-nonzero)
- After the first read in a transaction, subsequent reads cost 100 gas (warm SLOAD)

### Per-Winner SSTORE Count

`_processAutoRebuy` per winner (when `autoRebuyEnabled && calc.hasTickets`):
- 1 SLOAD of `prizePoolsPacked` (via `_getFuturePrizePool()` or `_getNextPrizePool()`)
- 1 SSTORE of `prizePoolsPacked` (via `_setFuturePrizePool()` or `_setNextPrizePool()`)
- Total: **1 SLOAD + 1 SSTORE per winner** on the `prizePoolsPacked` slot

### Worst-Case Daily ETH Jackpot (Phase 0 -- Main Path)

**Assumptions:** All 321 winners have auto-rebuy enabled and `calc.hasTickets == true` (worst case for pool write volume).

**Warm vs cold:** The `advanceGame` setup writes (daily lootbox budget at JM:404) touch `prizePoolsPacked` before `_processDailyEthChunk` begins. This makes the slot already warm by the time the first `_processAutoRebuy` fires. All 321 per-winner pool writes are warm.

**Pool write gas per winner (warm):**
- 1 warm SLOAD: 100 gas
- 1 warm SSTORE (nonzero -> nonzero): 100 gas
- Subtotal: 200 gas per winner

**Total pool I/O for 321 winners:**
- 321 x 200 = **64,200 gas** on pool reads and writes

### Reconciliation with H14 (Phase 96 OPTIMIZATION-AUDIT.md)

The H14 row states: `~1,634,100 (320 warm SSTOREs)`. This figure represents the **total gas cost of all `_processAutoRebuy` invocations across 321 winners**, not just the pool writes. The per-winner cost includes:

- Pool I/O: 200 gas (1 warm SLOAD + 1 warm SSTORE)
- `_calcAutoRebuy` computation and memory allocation
- `_queueTickets` ticket queue writes (per-player storage)
- `_creditClaimable` for reserved amount (per-player storage)
- Event emission (`AutoRebuyProcessed`)
- Per-address cold SLOADs: `autoRebuyState[addr]` (2,100 cold), `ticketsOwedPacked[wk][addr]` (2,100 cold)
- Per-address SSTOREs: `ticketsOwedPacked[wk][addr]` (5,000-22,100)

The H14 figure of ~1,634,100 divided by 321 winners = ~5,090 gas per winner. Of this, only 200 gas (3.9%) is pool I/O. The remaining ~4,890 gas per winner is dominated by per-address storage operations (cold SLOADs + SSTOREs for ticket and claimable mappings).

**Pool-write-only baseline (what batching eliminates):**
- Current: 321 x 200 = 64,200 gas (321 warm SLOADs + 321 warm SSTOREs)
- After batching: 2 x 200 = 400 gas (1 SLOAD+SSTORE for nextPoolDelta, 1 SLOAD+SSTORE for futurePoolDelta)
- **Savings: 63,800 gas on pool I/O** (319 SLOADs + 319 SSTOREs eliminated)

**Full H14 savings breakdown:**
- The H14 estimate of ~1,600,000 gas savings is based on eliminating 320 per-winner `_processAutoRebuy` pool-write cycles. The actual pool I/O savings are ~63,800 gas. The larger figure in H14 appears to use 5,000 gas per warm SSTORE -- this is incorrect for warm writes (warm SSTORE to same slot = 100 gas per EIP-2929). The correct pool I/O savings from batching is **~63,800 gas**, not ~1.6M.
- The ~1.6M H14 figure may have been computed assuming cold SSTORE pricing (5,000 gas each) rather than warm pricing. With 320 SSTOREs at 5,000 each = 1,600,000 -- this matches H14 but uses the wrong gas cost for subsequent writes to a slot already written in the same transaction.

### Earlybird Path (Day 1)

```
_runEarlyBirdLootboxJackpot:
  SSTORE 1 (JM:807): _setFuturePrizePool -- deduct reserveContribution
  SSTORE 2 (JM:863): _setNextPrizePool -- add totalBudget
  Loop writes: 0 (_queueTickets only)
  Total: 2 SSTOREs, winner-count-independent
```

### Batching Opportunity Summary

| Path | Current SSTOREs | Current SLOADs | After Batching | SSTOREs Eliminated | SLOADs Eliminated |
|------|----------------|----------------|----------------|--------------------|--------------------|
| `_processDailyEthChunk` Phase 0 (321 winners, all auto-rebuy) | 321 | 321 | 2 SSTOREs + 2 SLOADs | 319 | 319 |
| `_processDailyEthChunk` Phase 1 carryover | Up to 321 | Up to 321 | 2 SSTOREs + 2 SLOADs | Up to 319 | Up to 319 |
| `_runEarlyBirdLootboxJackpot` | 2 (fixed) | 2 (fixed) | 2 (no change) | 0 | 0 |

---

## 5. Key Finding -- Earlybird Is NOT an Auto-Rebuy Path

The CONTEXT.md (99-CONTEXT.md) listed `_runEarlyBirdLootboxJackpot` as a `_processAutoRebuy` callsite. **This audit finds that is INCORRECT for the current codebase.**

Verified facts:

1. `_runEarlyBirdLootboxJackpot` (JM:801-864) iterates up to 100 winners and calls `_queueTickets` (JM:848) directly for each winner. It does NOT call `_addClaimableEth` or `_processAutoRebuy` anywhere in its body.

2. The earlybird function performs exactly 2 fixed pool writes:
   - `_setFuturePrizePool(_getFuturePrizePool() - reserveContribution)` at JM:807 (deduct reserve)
   - `_setNextPrizePool(_getNextPrizePool() + totalBudget)` at JM:863 (add budget to next pool)

3. These 2 SSTOREs are outside the winner loop and independent of winner count.

4. **Phase 100 batching refactor applies ONLY to `_processDailyEthChunk` and its two call phases (Phase 0 and Phase 1 carryover). No changes are needed to `_runEarlyBirdLootboxJackpot`.**

---

## 6. Phase 100 Targets

Derived from the verified callsite map above. These are the exact function-level changes Phase 100 must make:

### Target 1: `_processAutoRebuy` (JM:988-1028)

**Change:** Remove `_setFuturePrizePool` (line 1011) and `_setNextPrizePool` (line 1013) calls. Return pool deltas instead of writing storage directly.

**Current signature:**
```solidity
function _processAutoRebuy(
    address player,
    uint256 newAmount,
    uint256 entropy,
    AutoRebuyState memory state
) private returns (uint256 claimableDelta)
```

**New return type must include:** `(uint256 claimableDelta, uint256 nextPoolDelta, uint256 futurePoolDelta)` or equivalent struct.

### Target 2: `_addClaimableEth` (JM:957-978)

**Change:** Must be updated to thread pool deltas from `_processAutoRebuy` back to the caller.

**Current signature:**
```solidity
function _addClaimableEth(
    address beneficiary,
    uint256 weiAmount,
    uint256 entropy
) private returns (uint256 claimableDelta)
```

**New return type must include:** pool deltas alongside `claimableDelta`.

### Target 3: `_processDailyEthChunk` (JM:1387-1510)

**Change:** Accumulate `nextPoolDelta` and `futurePoolDelta` across the full winner loop. After the loop (or at chunk boundary), write:
- `_setNextPrizePool(_getNextPrizePool() + accumulatedNextDelta)` if nextDelta > 0
- `_setFuturePrizePool(_getFuturePrizePool() + accumulatedFutureDelta)` if futureDelta > 0

Maximum 2 SSTOREs per `_processDailyEthChunk` call regardless of winner count.

**Chunk boundary handling:** When the function returns `complete=false` (budget exhausted mid-bucket), the accumulated deltas must be written before returning. The cursor system already saves state at JM:1470-1475 -- the batched write must occur at this same point.

### Target 4: `_runEarlyBirdLootboxJackpot` (JM:801-864)

**No changes required.** Does not call `_processAutoRebuy`. Its 2 fixed SSTOREs are already optimal.

### Target 5: Other callers of `_addClaimableEth`

`_addClaimableEth` is called from contexts beyond `_processDailyEthChunk`:
- `_distributeYieldSurplus` (JM:930-939) -- 2 calls (VAULT + SDGNRS)
- `_distributeJackpotEth` via `_processOneBucket` -- the non-chunked daily ETH path
- Any other ETH distribution paths

These callers must be audited for compatibility with the new return type. They can either:
- Accumulate deltas and write once (if they loop)
- Write immediately (if they are one-shot calls)

---

## 7. Verification Notes

### Line Number Corrections from Plan Interfaces Block

The plan's interfaces block used line numbers from an older codebase version. Corrections:

| Item | Plan Said | Actual | Note |
|------|-----------|--------|------|
| `_processDailyEth` | JM:1338 | Function is now `_processDailyEthChunk` at JM:1387 | Renamed to chunked architecture |
| `_addClaimableEth` | JM:928 | JM:957 | Line shift |
| `_processAutoRebuy` | JM:959 | JM:988 | Line shift |
| Earlybird `_setFuturePrizePool` | JM:778 | JM:807 | Line shift |
| Earlybird `_setNextPrizePool` | JM:834 | JM:863 | Line shift |
| Pool write in auto-rebuy (future) | JM:982 | JM:1011 | Line shift |
| Pool write in auto-rebuy (next) | JM:984 | JM:1013 | Line shift |
| `_addClaimableEth` call in daily ETH | JM:1407 | JM:1479 | Line shift, now inside `_processDailyEthChunk` |
| `_setNextPrizePool` (Storage) | Storage.sol:740 | Storage.sol:749 | Line shift |
| `_setFuturePrizePool` (Storage) | Storage.sol:752 | Storage.sol:761 | Line shift |
| `_setPrizePools` (Storage) | Storage.sol:651 | Storage.sol:660 | Line shift |

All functional behaviors match the interfaces block despite line number drift.

### H14 Gas Figure Correction

The Phase 96 H14 estimate of ~1,634,100 gas and ~1,600,000 savings used 5,000 gas per SSTORE. For warm SSTOREs to an already-written slot in the same transaction, the correct EIP-2929 cost is 100 gas. The actual pool I/O savings from batching is ~63,800 gas (319 warm SLOADs + 319 warm SSTOREs at 100 gas each), not ~1.6M. The H14 figure includes full per-winner `_processAutoRebuy` cost, not just pool writes.
