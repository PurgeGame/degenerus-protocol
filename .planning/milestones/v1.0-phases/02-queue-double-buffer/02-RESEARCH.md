# Phase 2: Queue Double-Buffer - Research

**Researched:** 2026-03-11
**Domain:** Solidity mapping key migration, double-buffer queue write/read path separation
**Confidence:** HIGH

## Summary

Phase 2 wires the double-buffer key encoding (built in Phase 1) into all ticket queue call sites. The `_tqWriteKey()` and `_tqReadKey()` helpers already exist in DegenerusGameStorage.sol; this phase replaces every raw `targetLevel`/`lvl` key in `ticketQueue[...]` and `ticketsOwedPacked[...]` accesses with the appropriate keyed variant, adds the mid-day swap trigger logic, and ensures `_swapTicketSlot()` hard gate is exercised in tests.

There are two distinct categories of call sites: (1) **write-path** functions in DegenerusGameStorage.sol (`_queueTickets`, `_queueTicketsScaled`, `_queueTicketRange`) that must use `_tqWriteKey()`, and (2) **read-path** functions in JackpotModule (`processTicketBatch`, `_processOneTicketEntry`, `_resolveZeroOwedRemainder`) and MintModule (`processFutureTicketBatch`) that must use `_tqReadKey()`. Additionally, there are view functions and a "far future coin" lottery function that read `ticketQueue` directly -- these need case-by-case analysis.

The mid-day swap trigger (QUEUE-04) is new logic in `advanceGame` that does not exist today. The current `advanceGame` has no mid-day path (`day == dailyIdx` immediately reverts with `NotTimeYet()`). Phase 2 must add the mid-day path that processes pending read-slot tickets and triggers queue swaps when the write queue reaches 440 entries or when jackpot phase is active and write queue is non-empty.

There are also ~70 legacy compatibility shim calls (`_legacyGetNextPrizePool`, etc.) marked "REMOVE IN PHASE 2" in the source. These should be migrated to direct `_getPrizePools()`/`_setPrizePools()` calls as part of this phase.

**Primary recommendation:** Modify the 3 storage helper functions to use `_tqWriteKey()` internally (single point of change for all write callers), modify the 2 processing entry points to compute `_tqReadKey()` and pass it to private helpers, add the mid-day path to `advanceGame`, and migrate legacy shims.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| QUEUE-01 | All `_queueTickets*` functions use `_tqWriteKey()` for mapping keys | 3 write-path functions in DegenerusGameStorage.sol (lines 539, 571, 627) use raw `targetLevel`/`lvl`. Each must call `_tqWriteKey(targetLevel)` before accessing `ticketQueue` and `ticketsOwedPacked`. The 4th function `_queueLootboxTickets` delegates to `_queueTicketsScaled` so it inherits the fix. All 18+ external callers across modules inherit the fix automatically since the key encoding happens inside the storage helper. |
| QUEUE-02 | All processing functions use `_tqReadKey()` for mapping keys | 3 read-path entry points: JackpotModule `processTicketBatch` (line 1919), JackpotModule `_processOneTicketEntry`+`_resolveZeroOwedRemainder` (lines 1991-2112), MintModule `processFutureTicketBatch` (line 298). Each uses raw `lvl` to access `ticketQueue[lvl]` and `ticketsOwedPacked[lvl][player]`. Must convert to `_tqReadKey(lvl)`. |
| QUEUE-03 | `_swapTicketSlot()` reverts when read slot non-empty | Already implemented in Phase 1 (DegenerusGameStorage.sol line 723-728) using `revert E()`. Already tested in StorageFoundation.t.sol (`testSwapTicketSlotRevertsNonEmpty`). Success criteria says "revert with `ReadSlotNotDrained`" but implementation uses `revert E()` per codebase convention -- this satisfies the intent. |
| QUEUE-04 | Mid-day swap trigger when write queue >= 440 or jackpot phase active and write queue non-empty | Current `advanceGame` reverts with `NotTimeYet()` when `day == dailyIdx` (line 146). Must add mid-day path: (1) process pending read-slot tickets, (2) trigger `_swapTicketSlot()` when write queue >= 440 or `jackpotPhaseFlag && writeLen > 0`, (3) return to allow next call to process freshly-swapped read slot. |
</phase_requirements>

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Foundry (forge) | latest | Build, test | Already configured in `foundry.toml` |
| Solidity | 0.8.34 | Smart contract language | Locked in pragma |
| forge-std | latest | Test framework (Test.sol) | Used by all existing tests |

### Key Commands
```bash
# Build verification
forge clean && forge build

# Run phase 2 tests
forge test --match-path "test/fuzz/QueueDoubleBuffer.t.sol" -vvv

# Run all tests (including Phase 1)
forge test

# Grep verification for QUEUE-01 (no direct key access in write functions)
grep -n 'ticketQueue\[targetLevel\]\|ticketsOwedPacked\[targetLevel\]' contracts/storage/DegenerusGameStorage.sol
# Expected: 0 results (only comments may remain)

# Grep verification for QUEUE-02 (no direct key access in processing functions)
grep -n 'ticketQueue\[lvl\]\|ticketsOwedPacked\[lvl\]' contracts/modules/DegenerusGameJackpotModule.sol contracts/modules/DegenerusGameMintModule.sol
# Expected: 0 results in processing functions
```

## Complete Call Site Inventory

### Write-Path Functions (QUEUE-01) -- In DegenerusGameStorage.sol

Functions that push to `ticketQueue` and write to `ticketsOwedPacked`. Must use `_tqWriteKey()`.

| Function | Line | `ticketQueue` accesses | `ticketsOwedPacked` accesses | Total |
|----------|------|----------------------|------------------------------|-------|
| `_queueTickets` | 539 | 1 (push, line 550) | 2 (read 546, write 560) | 3 |
| `_queueTicketsScaled` | 571 | 1 (push, line 582) | 2 (read 578, write 617) | 3 |
| `_queueTicketRange` | 627 | 1/iter (push, line 640) | 2/iter (read 636, write 650) | 3/iter |

**Callers of write-path functions (NO changes needed):**

| Caller | File | Line | Notes |
|--------|------|------|-------|
| Constructor | DegenerusGame.sol | 264-265 | `ticketWriteSlot=0` at deploy, `_tqWriteKey` returns raw level -- correct |
| `_processPhaseTransition` | AdvanceModule | 1005-1006 | Vault perpetual tickets |
| `_queueTicketsScaled` | MintModule | 992 | Purchase-driven tickets |
| `_queueTickets` | JackpotModule | 851, 1016, 1214 | Jackpot-awarded tickets |
| `_queueTickets` | EndgameModule | 253 | Endgame settlement |
| `_queueLootboxTickets` | EndgameModule | 485 | Delegates to `_queueTicketsScaled` |
| `_queueTicketRange` | EndgameModule | 515 | Whale pass claim |
| `_queueTickets` | DecimatorModule | 485 | Decimator payouts |
| `_queueTicketsScaled` | LootboxModule | 971 | Lootbox future tickets |
| `_queueTickets` | LootboxModule | 1103 | Lootbox tickets |
| `_queueTickets` | WhaleModule | 267, 412, 525 | Whale bundle tickets |
| `_queueTicketRange` | DegenerusGameStorage | 1211 | Whale pass internal |

### Read-Path Functions (QUEUE-02) -- In JackpotModule and MintModule

Functions that iterate `ticketQueue` and read/write `ticketsOwedPacked` during processing. Must use `_tqReadKey()`.

**JackpotModule:**

| Function | Line | Access | Count |
|----------|------|--------|-------|
| `processTicketBatch` | 1919 | `ticketQueue[lvl]` (storage ref) | 1 |
| `processTicketBatch` | 1931 | `delete ticketQueue[lvl]` | 1 |
| `processTicketBatch` | 1971 | `delete ticketQueue[lvl]` | 1 |
| `_processOneTicketEntry` | 2018 | `ticketsOwedPacked[lvl][player]` (read) | 1 |
| `_processOneTicketEntry` | 2112 | `ticketsOwedPacked[lvl][player]` (write) | 1 |
| `_resolveZeroOwedRemainder` | 1991 | `ticketsOwedPacked[lvl][player] = 0` | 1 |
| `_resolveZeroOwedRemainder` | 1998 | `ticketsOwedPacked[lvl][player] = 0` | 1 |
| `_resolveZeroOwedRemainder` | 2004 | `ticketsOwedPacked[lvl][player] = newPacked` | 1 |

**MintModule (`processFutureTicketBatch`):**

| Line | Access |
|------|--------|
| 298 | `ticketQueue[lvl]` (storage ref) |
| 314 | `delete ticketQueue[lvl]` |
| 334 | `ticketsOwedPacked[lvl][player]` (read) |
| 340 | `ticketsOwedPacked[lvl][player] = 0` |
| 349 | `ticketsOwedPacked[lvl][player] = 0` |
| 356 | `ticketsOwedPacked[lvl][player] = rolledPacked` |
| 398 | `ticketsOwedPacked[lvl][player] = newPacked` |
| 416 | `delete ticketQueue[lvl]` |

### View and Lottery Functions (case-by-case)

| Function | File | Line | Current Key | Recommended |
|----------|------|------|-------------|-------------|
| `ticketsOwedView` | DegenerusGame.sol | 2065 | `lvl` | Use `_tqWriteKey(lvl)` -- shows pending tickets |
| `getPlayerPurchases` | DegenerusGame.sol | 2745 | `level` | Use `_tqWriteKey(level)` -- shows pending tickets |
| `_sampleFarFutureCoinWinners` | JackpotModule | 2574 | `candidate` | Use `_tqWriteKey(candidate)` -- future levels have entries in write slot |
| `sampleFarFutureCoinWinners` | DegenerusGame.sol | 2680 | `candidate` | Use `_tqWriteKey(candidate)` -- same logic |

### Legacy Shim Calls (cleanup, marked "REMOVE IN PHASE 2")

~70 calls across 10 files using `_legacyGetNextPrizePool()`, `_legacySetNextPrizePool()`, `_legacyGetFuturePrizePool()`, `_legacySetFuturePrizePool()`. Migrate to `_getPrizePools()`/`_setPrizePools()` pattern (load at function entry, work with locals, single store at exit).

**Key files by call count:**
| File | Approximate Calls |
|------|-------------------|
| JackpotModule | ~20 |
| AdvanceModule | ~10 |
| DegenerusGame.sol | ~8 |
| WhaleModule | ~6 |
| DecimatorModule | ~5 |
| EndgameModule | ~5 |
| MintModule | ~3 |
| DegeneretteModule | ~3 |
| GameOverModule | ~4 |

## Architecture Patterns

### Pattern 1: Centralized Key Encoding in Storage Helpers (QUEUE-01)
**What:** The 3 write-path functions compute the key internally. All 18+ callers get correct behavior without changes.
**Implementation:** Add `uint24 wk = _tqWriteKey(targetLevel);` as the first meaningful line, then replace all `targetLevel` in mapping accesses with `wk`.
**Critical rule:** Events keep emitting the raw `targetLevel` -- events are for off-chain indexing and should reflect the logical level, not the buffer key.

```solidity
function _queueTickets(address buyer, uint24 targetLevel, uint32 quantity) internal {
    if (quantity == 0) return;
    emit TicketsQueued(buyer, targetLevel, quantity);  // logical level
    uint24 wk = _tqWriteKey(targetLevel);              // keyed level
    uint40 packed = ticketsOwedPacked[wk][buyer];
    // ... all mapping accesses use wk ...
}
```

### Pattern 2: Read Key Passed to Private Helpers (QUEUE-02)
**What:** Processing entry points compute `rk = _tqReadKey(lvl)` once, then pass `rk` to all private helpers alongside the original `lvl`.
**Why:** Avoids repeated SLOAD of `ticketWriteSlot` in inner loops. `_processOneTicketEntry` is called per queue entry -- computing `_tqReadKey` inside it would add an SLOAD per entry.
**Critical rule:** `lvl` stays for logical operations (event emission, roll salt, cursor tracking). `rk` is for mapping access only.

```solidity
function processTicketBatch(uint24 lvl) external returns (bool finished) {
    uint24 rk = _tqReadKey(lvl);
    address[] storage queue = ticketQueue[rk];
    // ... pass rk to _processOneTicketEntry ...
    delete ticketQueue[rk];
}

// Private helper gets BOTH lvl (for salt) and rk (for mappings)
function _processOneTicketEntry(
    address player, uint24 lvl, uint24 rk, /* existing params */
) private returns (uint32 writesUsed, bool advance) {
    uint40 packed = ticketsOwedPacked[rk][player];  // rk for mapping
    uint256 rollSalt = (uint256(lvl) << 224) | ...;  // lvl for salt
}
```

### Pattern 3: Mid-Day Path in advanceGame (QUEUE-04)
**What:** Replace `if (day == dailyIdx) revert NotTimeYet();` with conditional mid-day processing.
**Structure:**
```
if (day == dailyIdx):
  1. If read slot not drained: process batch, return
  2. If read slot empty: set ticketsFullyProcessed = true
  3. Check write queue: if >= 440 or (jackpotPhase && > 0): swap, return
  4. Otherwise: revert NotTimeYet()
```
**Constant needed:** `uint32 private constant MID_DAY_SWAP_THRESHOLD = 440;` in AdvanceModule.
**Key distinction:** Mid-day swap uses `_swapTicketSlot()` (no freeze). Only the daily path at RNG request uses `_swapAndFreeze()`.

### Pattern 4: Legacy Shim Migration
**What:** Replace `_legacyGetNextPrizePool()` / `_legacySetNextPrizePool()` pattern with `_getPrizePools()` / `_setPrizePools()`.
**Migration pattern for functions that touch both pools multiple times:**
```solidity
// BEFORE (multiple SLOADs via shims):
_legacySetNextPrizePool(_legacyGetNextPrizePool() + nextShare);
_legacySetFuturePrizePool(_legacyGetFuturePrizePool() + futureShare);

// AFTER (1 SLOAD at entry, locals throughout, 1 SSTORE at exit):
(uint128 next, uint128 future) = _getPrizePools();
next += uint128(nextShare);
future += uint128(futureShare);
_setPrizePools(next, future);
```
**For functions that only read one pool:** Can still use the packed getter and ignore the unused component.

### Anti-Patterns to Avoid
- **Encoding the key at caller sites:** Write-path key goes inside `_queueTickets*`, NOT in modules calling them.
- **Mixing raw and keyed levels in the same function:** Once `rk` is computed, ALL mapping accesses use `rk`. Using `lvl` for one mapping and `rk` for another creates a data consistency bug.
- **Changing event parameters to keyed levels:** Events use logical levels for off-chain indexing.
- **Changing `ticketCursor`/`ticketLevel` to use keyed levels:** These track logical processing state, not buffer keys.
- **Using `_swapAndFreeze()` for mid-day swaps:** Mid-day swaps do NOT freeze prize pools.
- **Renaming `lvl` to `rk` in private helpers:** The `lvl` parameter serves dual purpose (mapping key + roll salt). Renaming it to `rk` changes roll salt computation, breaking trait generation determinism.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Key computation | Inline ternary at each access site | `_tqWriteKey()` / `_tqReadKey()` once at function entry | Single point of truth, Phase 1 built |
| Drain gate checking | Manual length checks before swap | `_swapTicketSlot()` hard gate | Already built in Phase 1, reverts automatically |
| Pool access | Legacy shims (`_legacyGet/SetNextPrizePool`) | `_getPrizePools()`/`_setPrizePools()` with locals | Saves SLOADs, single SSTORE per function |

## Common Pitfalls

### Pitfall 1: ticketsOwedPacked Key Mismatch (CRITICAL)
**What goes wrong:** Changing `ticketQueue[targetLevel]` to `ticketQueue[wk]` but leaving `ticketsOwedPacked[targetLevel]` unchanged. Player is added to queue in buffer A but their owed count is tracked under the raw level key. Processing reads from buffer A, finds the player, but reads zero owed tickets.
**Why it happens:** The two mappings are accessed at different lines in the function, easy to miss one.
**How to avoid:** For each function, count total mapping accesses before and after. After migration, every `ticketQueue` and `ticketsOwedPacked` access must use the same keyed variable.
**Warning signs:** Players have zero tickets when processed despite being in the queue.

### Pitfall 2: Private Helper Parameter Change Breaks Roll Salt
**What goes wrong:** Renaming `lvl` parameter to `rk` in `_processOneTicketEntry` changes the roll salt computation `(uint256(lvl) << 224) | ...`, which changes trait generation results for the same VRF entropy.
**Why it happens:** The `lvl` parameter serves dual purpose: mapping key + cryptographic salt.
**How to avoid:** Add a NEW `uint24 rk` parameter alongside existing `lvl`. Use `rk` for mappings, `lvl` for salt.
**Warning signs:** Trait generation produces different results for same inputs.

### Pitfall 3: Mid-Day Path Must Process Read Slot First
**What goes wrong:** Mid-day swap fires while read slot still has unprocessed entries. The `_swapTicketSlot` hard gate reverts.
**Why it happens:** Skipping the `ticketsFullyProcessed` check or the read-slot length check.
**How to avoid:** Mid-day path must: (1) check `!ticketsFullyProcessed`, (2) process read slot via `_runProcessTicketBatch`, (3) only attempt swap after read slot is empty. The hard gate is a safety net, not the primary flow control.
**Warning signs:** `_swapTicketSlot` reverts during mid-day `advanceGame` calls.

### Pitfall 4: `delete ticketQueue[lvl]` Uses Wrong Key
**What goes wrong:** Processing function changes `ticketQueue[lvl]` to `ticketQueue[rk]` for the storage reference at the top but misses the `delete ticketQueue[lvl]` at the bottom. The read-slot array is not actually deleted.
**Why it happens:** The `delete` statements are at the end of the function, far from the key computation.
**How to avoid:** Search for ALL occurrences of `ticketQueue[lvl]` in each function. There are typically 3 (storage ref, delete if done mid-loop, delete if done at end).
**Warning signs:** Processed entries reappear; queue length never returns to zero.

### Pitfall 5: Legacy Shim Migration Overflow Safety
**What goes wrong:** When migrating from `_legacySetNextPrizePool(uint256)` to `_setPrizePools(uint128, uint128)`, the uint256 value may exceed uint128 max, causing silent truncation.
**Why it happens:** The original `nextPrizePool` was uint256; the packed version uses uint128.
**How to avoid:** uint128 max is ~3.4e20 ETH -- far exceeds total ETH supply. The truncation risk is theoretical. However, use `uint128(value)` cast explicitly at each migration site so the intent is clear.
**Warning signs:** None in practice; defensive casting is sufficient.

### Pitfall 6: View Functions After Swap
**What goes wrong:** `ticketsOwedView` uses raw level. After a swap, pending tickets are at the write-key and processed tickets at the read-key (empty after processing).
**Why it happens:** View functions were written before double-buffering.
**How to avoid:** Update to use `_tqWriteKey(lvl)` for the primary view (shows pending tickets).
**Impact:** LOW -- frontend-only, no state corruption.

## Code Examples

### Write-Path: _queueTickets (Complete)
```solidity
// Source: DegenerusGameStorage.sol line 539, modified for QUEUE-01
function _queueTickets(
    address buyer,
    uint24 targetLevel,
    uint32 quantity
) internal {
    if (quantity == 0) return;
    emit TicketsQueued(buyer, targetLevel, quantity);
    uint24 wk = _tqWriteKey(targetLevel);
    uint40 packed = ticketsOwedPacked[wk][buyer];
    uint32 owed = uint32(packed >> 8);
    uint8 rem = uint8(packed);
    if (owed == 0 && rem == 0) {
        ticketQueue[wk].push(buyer);
    }
    uint256 newOwed;
    unchecked {
        newOwed = uint256(owed) + quantity;
    }
    if (newOwed > type(uint32).max) {
        newOwed = type(uint32).max;
    }
    if (newOwed != owed) {
        ticketsOwedPacked[wk][buyer] =
            (uint40(uint32(newOwed)) << 8) |
            uint40(rem);
    }
}
```

### Read-Path: processTicketBatch (Skeleton)
```solidity
// Source: JackpotModule line 1916, modified for QUEUE-02
function processTicketBatch(uint24 lvl) external returns (bool finished) {
    uint24 rk = _tqReadKey(lvl);
    address[] storage queue = ticketQueue[rk];
    uint256 total = queue.length;

    if (ticketLevel != lvl) {
        ticketLevel = lvl;    // logical level for cursor tracking
        ticketCursor = 0;
    }

    uint256 idx = ticketCursor;
    if (idx >= total) {
        delete ticketQueue[rk];
        ticketCursor = 0;
        ticketLevel = 0;
        return true;
    }
    // ... processing loop passes rk to _processOneTicketEntry ...
    (uint32 writesUsed, bool advance) = _processOneTicketEntry(
        queue[idx], lvl, rk, /* other params */
    );
    // ...
    if (idx >= total) {
        delete ticketQueue[rk];
        ticketCursor = 0;
        ticketLevel = 0;
        return true;
    }
    return false;
}
```

### Mid-Day Path (advanceGame)
```solidity
// Source: PLAN-ALWAYS-OPEN-PURCHASES.md section 4
// Replaces: if (day == dailyIdx) revert NotTimeYet();
if (day == dailyIdx) {
    if (!ticketsFullyProcessed) {
        uint24 rk = _tqReadKey(purchaseLevel);
        if (ticketQueue[rk].length > 0) {
            (bool ticketWorked, bool ticketsFinished) = _runProcessTicketBatch(purchaseLevel);
            if (ticketWorked || !ticketsFinished) {
                emit Advance(STAGE_TICKETS_WORKING, lvl);
                coin.creditFlip(caller, ADVANCE_BOUNTY);
                return;
            }
        }
        ticketsFullyProcessed = true;
    }

    uint24 wk = _tqWriteKey(purchaseLevel);
    uint256 writeLen = ticketQueue[wk].length;
    if (writeLen >= MID_DAY_SWAP_THRESHOLD || (inJackpot && writeLen > 0)) {
        _swapTicketSlot(purchaseLevel);  // swap only, NO freeze
        emit Advance(STAGE_TICKETS_WORKING, lvl);
        coin.creditFlip(caller, ADVANCE_BOUNTY);
        return;
    }
    revert NotTimeYet();
}
```

### Legacy Shim Migration Example
```solidity
// BEFORE (multiple SLOADs + SSTOREs via shims):
_legacySetFuturePrizePool(_legacyGetFuturePrizePool() + futureShare);
_legacySetNextPrizePool(_legacyGetNextPrizePool() + nextShare);

// AFTER (single SLOAD + single SSTORE):
(uint128 next, uint128 future) = _getPrizePools();
_setPrizePools(next + uint128(nextShare), future + uint128(futureShare));
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Direct `ticketQueue[level]` | Keyed via `_tqWriteKey`/`_tqReadKey` | This phase | Enables concurrent purchase + processing |
| `revert NotTimeYet()` for same-day calls | Conditional mid-day swap path | This phase | Allows throughput-driven queue draining |
| 70 legacy shim calls | Direct `_getPrizePools()`/`_setPrizePools()` | This phase | Eliminates extra SLOAD per call |

## Open Questions

1. **`_processOneTicketEntry` and `_resolveZeroOwedRemainder` parameter change**
   - What we know: These private JackpotModule functions need `rk` for mapping access but `lvl` for roll salt.
   - Recommendation: Add `uint24 rk` parameter. `processTicketBatch` computes once, passes down. This avoids recomputing `_tqReadKey` per queue entry.

2. **Far-future sampling: write key only vs. both buffers**
   - What we know: `_sampleFarFutureCoinWinners` (JackpotModule:2574) and `sampleFarFutureCoinWinners` (DegenerusGame.sol:2680) sample levels 5-99 ahead.
   - Recommendation: Use `_tqWriteKey()` only. Future-level entries are always pending (write slot). The window where entries exist in read buffer for far-future levels is negligible.

3. **Mid-day jackpot condition: `inJackpot` alone vs. `inJackpot && writeLen > 0`**
   - What we know: The plan pseudocode uses `writeLen >= 440 || inJackpot` which would trigger even with empty write queue. The hard gate would succeed (empty read slot) but the swap would be pointless.
   - Recommendation: Use `writeLen >= 440 || (inJackpot && writeLen > 0)` to avoid no-op swaps.

4. **Legacy shim migration scope within this phase**
   - What we know: ~70 calls marked "REMOVE IN PHASE 2". This is independent of queue key work.
   - Recommendation: Separate plan within Phase 2. Queue keys are Plan 1, shim migration is Plan 2.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry forge-std (Test.sol), Solidity 0.8.34, via_ir=true |
| Config file | `foundry.toml` |
| Quick run command | `forge test --match-path "test/fuzz/QueueDoubleBuffer.t.sol" -vvv` |
| Full suite command | `forge test` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| QUEUE-01 | `_queueTickets` writes to write-buffer key, not raw level | unit | `forge test --match-test "testQueueTicketsUsesWriteKey" -vvv` | No -- Wave 0 |
| QUEUE-01 | `_queueTicketsScaled` writes to write-buffer key | unit | `forge test --match-test "testQueueTicketsScaledUsesWriteKey" -vvv` | No -- Wave 0 |
| QUEUE-01 | `_queueTicketRange` writes to write-buffer key for each level | unit | `forge test --match-test "testQueueTicketRangeUsesWriteKey" -vvv` | No -- Wave 0 |
| QUEUE-01 | Grep: no direct mapping key access in write functions | smoke | See grep commands in Standard Stack | N/A (CLI) |
| QUEUE-02 | `processTicketBatch` reads from read-buffer key | unit | `forge test --match-test "testProcessTicketBatchUsesReadKey" -vvv` | No -- Wave 0 |
| QUEUE-02 | `processFutureTicketBatch` reads from read-buffer key | unit | `forge test --match-test "testFutureTicketBatchUsesReadKey" -vvv` | No -- Wave 0 |
| QUEUE-02 | Grep: no direct mapping key access in processing functions | smoke | See grep commands in Standard Stack | N/A (CLI) |
| QUEUE-03 | `_swapTicketSlot` reverts on non-empty read slot | unit | `forge test --match-test "testSwapTicketSlotRevertsNonEmpty" -vvv` | YES (StorageFoundation.t.sol) |
| QUEUE-04 | Mid-day swap fires at threshold 440 | unit | `forge test --match-test "testMidDaySwapAtThreshold" -vvv` | No -- Wave 0 |
| QUEUE-04 | Mid-day swap fires during jackpot phase with non-empty write | unit | `forge test --match-test "testMidDaySwapJackpotPhase" -vvv` | No -- Wave 0 |
| QUEUE-04 | Mid-day reverts NotTimeYet when below threshold and not jackpot | unit | `forge test --match-test "testMidDayRevertsNotTimeYet" -vvv` | No -- Wave 0 |
| ALL | `forge clean && forge build` zero errors | smoke | `forge clean && forge build` | N/A |

### Sampling Rate
- **Per task commit:** `forge clean && forge build` (compilation)
- **Per wave merge:** `forge test` (full suite)
- **Phase gate:** Grep verification for QUEUE-01/QUEUE-02 + all unit tests green + full `forge test` green

### Wave 0 Gaps
- [ ] `test/fuzz/QueueDoubleBuffer.t.sol` -- new test file covering QUEUE-01 through QUEUE-04
- [ ] Extended StorageHarness (or new harness) exposing queue write/read functions with key verification via `vm.load`
- [ ] For QUEUE-02 tests: harness that can exercise `processTicketBatch` without full delegatecall setup -- or use StorageHarness to verify key separation at the mapping level
- [ ] For QUEUE-04 mid-day tests: harness that can set `dailyIdx`, `ticketsFullyProcessed`, `jackpotPhaseFlag` and test conditional swap logic
- Framework install: no gaps (forge-std already in `lib/`)

## Sources

### Primary (HIGH confidence)
- `contracts/storage/DegenerusGameStorage.sol` -- all queue helpers (lines 539-676), key encoding (lines 706-715), swap function (lines 723-728), legacy shims (lines 753-781)
- `contracts/modules/DegenerusGameJackpotModule.sol` -- `processTicketBatch` (1916-1977), `_processOneTicketEntry` (2010-2112), `_resolveZeroOwedRemainder` (1981-2007), `_sampleFarFutureCoinWinners` (2548-2589)
- `contracts/modules/DegenerusGameMintModule.sol` -- `processFutureTicketBatch` (294-420)
- `contracts/modules/DegenerusGameAdvanceModule.sol` -- `advanceGame` (121-295), `_runProcessTicketBatch` (976-993), `_prepareFinalDayFutureTickets` (935-963)
- `contracts/DegenerusGame.sol` -- constructor (256-268), `ticketsOwedView` (2061-2066), `getPlayerPurchases` (2742-2746), `sampleFarFutureCoinWinners` (2670-2698)
- `audit/PLAN-ALWAYS-OPEN-PURCHASES.md` -- sections 2 (queue double-buffer) and 4 (advanceGame flow)
- `test/fuzz/StorageFoundation.t.sol` -- existing harness and Phase 1 tests

### Secondary (MEDIUM confidence)
- `.planning/phases/01-storage-foundation/01-RESEARCH.md` -- Phase 1 patterns and storage layout context
- `.planning/REQUIREMENTS.md` -- QUEUE-01 through QUEUE-04 definitions

### Tertiary (LOW confidence)
- None -- all findings verified from source code

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- same Foundry/Solidity stack as Phase 1
- Architecture: HIGH -- every affected call site inventoried from source grep, line-by-line verification
- Pitfalls: HIGH -- each derived from specific code analysis (dual-mapping consistency, parameter semantics, delete statements)
- Mid-day path: HIGH -- exact pseudocode in plan document, verified against current advanceGame structure (line 146)

**Research date:** 2026-03-11
**Valid until:** 2026-04-11 (stable domain; Solidity mapping semantics don't change)
