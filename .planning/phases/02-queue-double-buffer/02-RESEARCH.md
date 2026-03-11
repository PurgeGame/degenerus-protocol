# Phase 2: Queue Double-Buffer - Research

**Researched:** 2026-03-11
**Domain:** Solidity mapping key migration, double-buffer queue pattern, delegatecall module coordination
**Confidence:** HIGH

## Summary

Phase 2 wires every ticket queue access site to use the `_tqWriteKey()` / `_tqReadKey()` helpers established in Phase 1. The work is purely mechanical key substitution in existing functions -- no new storage, no new data structures, no architectural changes. The queue helper functions in DegenerusGameStorage.sol (`_queueTickets`, `_queueTicketsScaled`, `_queueTicketRange`) use `ticketQueue[targetLevel]` and `ticketsOwedPacked[targetLevel]` directly and must be changed to use `_tqWriteKey(targetLevel)`. The processing functions in JackpotModule (`processTicketBatch`) and MintModule (`processFutureTicketBatch`) use `ticketQueue[lvl]` and `ticketsOwedPacked[lvl]` and must be changed to use `_tqReadKey(lvl)`.

The second deliverable is `_swapTicketSlot()` with its hard drain gate -- this already exists from Phase 1. The phase must add the QUEUE-04 mid-day swap trigger logic, which is a new code path in `advanceGame` that fires `_swapTicketSlot()` (not `_swapAndFreeze()`) when write queue length >= 440 or jackpot phase is active. This mid-day path replaces the current `revert NotTimeYet()` with conditional swap logic.

A critical nuance: "far-future" winner sampling (`_awardFarFutureCoinJackpot` in JackpotModule, `_pickWinnersFromHistory` in DegenerusGame.sol) reads from `ticketQueue[candidate]` where candidate is `lvl + 5..99` -- these are future purchase levels, meaning they hold tickets written by the write-side. These read operations should sample from BOTH buffer slots (or from whichever slot has entries) to avoid missing eligible winners. However, this is not listed in the phase requirements -- the plan document says these are "far-future" levels and uses raw keys. This needs careful treatment: the simplest approach is to keep them reading both slots (try write key, then read key) or accept that they only see whichever slot has entries at call time.

**Primary recommendation:** Split into two plans: (1) write-path key migration in Storage + read-path key migration in processing modules + tests, (2) mid-day swap trigger in advanceGame + view function considerations + integration tests.

<phase_requirements>

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| QUEUE-01 | All `_queueTickets*` functions use `_tqWriteKey()` for mapping keys | 3 functions in DegenerusGameStorage.sol need key substitution: `_queueTickets` (line 539), `_queueTicketsScaled` (line 571), `_queueTicketRange` (line 627). Total: 8 direct `ticketQueue[targetLevel]` and `ticketsOwedPacked[targetLevel]` accesses to replace. External call sites (modules, constructor) do NOT change -- they pass `targetLevel` to these helpers which internally apply the key. |
| QUEUE-02 | All processing functions use `_tqReadKey()` for mapping keys | 2 processing entry points: `processTicketBatch` in JackpotModule (line 1916), `processFutureTicketBatch` in MintModule (line 294). Plus private helpers: `_processOneTicketEntry` (JackpotModule:2010), `_resolveZeroOwedRemainder` (JackpotModule:1981). Total: ~20 direct `ticketQueue[lvl]` and `ticketsOwedPacked[lvl]` accesses across these functions. |
| QUEUE-03 | `_swapTicketSlot()` reverts with `ReadSlotNotDrained` when read slot non-empty | Already implemented in Phase 1 (DegenerusGameStorage.sol line 723-728) using `revert E()`. Unit test `testSwapTicketSlotRevertsNonEmpty` already passes. Only new work: verify the error name in success criteria matches (plan says `ReadSlotNotDrained` but implementation uses `revert E()` per codebase convention). |
| QUEUE-04 | Mid-day swap trigger when write queue >= 440 or jackpot phase active | New code path in `advanceGame`. Currently `day == dailyIdx` hits `revert NotTimeYet()`. Must be replaced with: check `ticketsFullyProcessed`, process read slot if needed, then check write queue length threshold. Constant 440 needs declaration. |

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

# Grep verification for QUEUE-02 (no direct key access in processing functions)
grep -n 'ticketQueue\[lvl\]\|ticketsOwedPacked\[lvl\]' contracts/modules/DegenerusGameJackpotModule.sol contracts/modules/DegenerusGameMintModule.sol
```

## Architecture Patterns

### Pattern 1: Write-Path Key Substitution (QUEUE-01)

**What:** Replace every `ticketQueue[targetLevel]` with `ticketQueue[wk]` where `wk = _tqWriteKey(targetLevel)` in the three queue helper functions.

**Key insight:** The key computation happens ONCE at the top of each helper function, then the local `wk` variable is used for all mapping accesses within. Both `ticketQueue` and `ticketsOwedPacked` use the same key within each function.

```solidity
// BEFORE (_queueTickets):
function _queueTickets(address buyer, uint24 targetLevel, uint32 quantity) internal {
    if (quantity == 0) return;
    emit TicketsQueued(buyer, targetLevel, quantity);
    uint40 packed = ticketsOwedPacked[targetLevel][buyer];
    // ...
    if (owed == 0 && rem == 0) {
        ticketQueue[targetLevel].push(buyer);
    }
    // ...
    ticketsOwedPacked[targetLevel][buyer] = ...;
}

// AFTER:
function _queueTickets(address buyer, uint24 targetLevel, uint32 quantity) internal {
    if (quantity == 0) return;
    emit TicketsQueued(buyer, targetLevel, quantity);
    uint24 wk = _tqWriteKey(targetLevel);
    uint40 packed = ticketsOwedPacked[wk][buyer];
    // ...
    if (owed == 0 && rem == 0) {
        ticketQueue[wk].push(buyer);
    }
    // ...
    ticketsOwedPacked[wk][buyer] = ...;
}
```

**Affected functions and access counts:**
| Function | `ticketQueue` accesses | `ticketsOwedPacked` accesses |
|----------|----------------------|------------------------------|
| `_queueTickets` (line 539) | 1 (push) | 2 (read + write) |
| `_queueTicketsScaled` (line 571) | 1 (push) | 2 (read + write) |
| `_queueTicketRange` (line 627) | 1 (push per level) | 2 (read + write per level) |

**Event parameters:** The `targetLevel` in events (`TicketsQueued`, `TicketsQueuedScaled`, `TicketsQueuedRange`) should remain the LOGICAL level (not the keyed level). Events are off-chain indexed -- the raw level is more useful to consumers.

### Pattern 2: Read-Path Key Substitution (QUEUE-02)

**What:** Replace every `ticketQueue[lvl]` and `ticketsOwedPacked[lvl]` with keyed versions using `_tqReadKey(lvl)` in processing functions.

**Critical complexity:** The processing functions use `lvl` for BOTH mapping access AND as a parameter to other operations (event emission, cursor tracking, roll salt computation). Only the mapping accesses change -- everything else keeps the logical level.

```solidity
// processTicketBatch (JackpotModule):
function processTicketBatch(uint24 lvl) external returns (bool finished) {
    uint24 rk = _tqReadKey(lvl);  // NEW: compute read key once
    address[] storage queue = ticketQueue[rk];  // CHANGED: was ticketQueue[lvl]
    // ...
    delete ticketQueue[rk];  // CHANGED: was delete ticketQueue[lvl]
    // ...
    // ticketLevel = lvl;  // UNCHANGED: tracks logical level
}
```

**Affected functions in JackpotModule:**
| Function | Line | Changes |
|----------|------|---------|
| `processTicketBatch` | 1916 | `ticketQueue[lvl]` x3 -> `ticketQueue[rk]`; `ticketsOwedPacked[lvl]` via `_processOneTicketEntry` |
| `_processOneTicketEntry` | 2010 | `ticketsOwedPacked[lvl]` x3 -> `ticketsOwedPacked[rk]` (must receive `rk` as parameter OR compute internally) |
| `_resolveZeroOwedRemainder` | 1981 | `ticketsOwedPacked[lvl]` x2 -> `ticketsOwedPacked[rk]` (same: must receive `rk`) |

**Affected functions in MintModule:**
| Function | Line | Changes |
|----------|------|---------|
| `processFutureTicketBatch` | 294 | `ticketQueue[lvl]` x3 -> `ticketQueue[rk]`; `ticketsOwedPacked[lvl]` x7 -> `ticketsOwedPacked[rk]` |

**Design decision for private helpers:** `_processOneTicketEntry` and `_resolveZeroOwedRemainder` in JackpotModule take `lvl` as a parameter and use it for both mapping access and roll salt. Two options:
1. Pass `rk` as an additional parameter (cleanest -- avoids recomputing key per iteration)
2. Rename `lvl` parameter to `rk` and pass the keyed level (confusing -- breaks roll salt semantics)

**Recommendation:** Option 1 -- add `uint24 rk` parameter to private helpers. The parent `processTicketBatch` computes `rk` once and passes it down. The `lvl` parameter stays for logical operations (events, salt, cursor).

### Pattern 3: Mid-Day Swap Trigger (QUEUE-04)

**What:** Replace the `if (day == dailyIdx) revert NotTimeYet()` in `advanceGame` with a conditional mid-day processing path.

**From the plan document (section 4):**
```
if (day == dailyIdx):
  // 1. Process pending tickets from read slot
  if (!ticketsFullyProcessed):
    if (ticketQueue[_tqReadKey(purchaseLevel)].length > 0):
      _runProcessTicketBatch(purchaseLevel)
      emit Advance(STAGE_TICKETS_WORKING, lvl)
      coin.creditFlip(caller, ADVANCE_BOUNTY)
      return
    ticketsFullyProcessed = true

  // 2. Trigger mid-day swap if write queue qualifies
  writeLen = ticketQueue[_tqWriteKey(purchaseLevel)].length
  if (writeLen >= 440 || inJackpot):
    _swapTicketSlot(purchaseLevel)
    emit Advance(STAGE_TICKETS_WORKING, lvl)
    coin.creditFlip(caller, ADVANCE_BOUNTY)
    return

  revert NotTimeYet()
```

**Constant needed:** `uint32 internal constant MID_DAY_SWAP_THRESHOLD = 440;` (out of scope to tune per REQUIREMENTS.md)

### Pattern 4: Far-Future / View Function Handling

**What:** `_awardFarFutureCoinJackpot` (JackpotModule:2548) and `_pickWinnersFromHistory` (DegenerusGame.sol:2670) sample from `ticketQueue[candidate]` for levels 5-99 ahead of current.

**Analysis:** These functions sample winners from future-level ticket queues. At any given time, these future levels contain tickets written by the write buffer. After a swap, some tickets may be in the read buffer (now being processed) while new purchases go to write buffer.

**The key question:** Should these sampling functions look at both buffers?

**Recommendation:** These functions should use the write key (`_tqWriteKey(candidate)`) because:
1. They sample from levels 5-99 ahead -- these are future levels not yet being processed
2. New purchases always go to the write buffer for these levels
3. The read buffer for these levels would only have entries if a swap happened while processing was at a MUCH earlier level (unlikely for levels 5-99 ahead)
4. This is a non-critical best-effort sampling (BURNIE rewards, not ETH jackpots)

However, a simpler option is: check BOTH buffers. If `ticketQueue[writeKey].length + ticketQueue[readKey].length > 0`, sample from whichever has entries. This is more robust but costs an extra SLOAD.

**Simplest safe approach:** Use write key only. Document that during a brief window after swap, some far-future tickets may not be sampled. This is acceptable because:
- These are probabilistic selections with 10 random attempts
- Missing a few entries in a temporary window is not a correctness issue
- The plan document does not mention special handling for these functions

### Anti-Patterns to Avoid

- **Applying read key to write operations:** Queue helpers push to write buffer. Processing functions read from read buffer. Mixing these up silently corrupts the double-buffer invariant.
- **Changing event parameters to keyed levels:** Events should emit LOGICAL levels for off-chain indexing. The keyed level is an internal implementation detail.
- **Forgetting `ticketsOwedPacked` when changing `ticketQueue`:** These two mappings always use the SAME key within any given function. Missing one creates a data consistency bug where tickets are queued in one buffer but owed-count tracked in the other.
- **Changing `ticketCursor` or `ticketLevel` semantics:** These track logical levels, not keyed levels. They must NOT be changed.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Key computation per access | Inline `ticketWriteSlot != 0 ? level \| BIT : level` | `_tqWriteKey()` / `_tqReadKey()` | Single point of truth, already built in Phase 1 |
| Drain gate checking | Manual length checks before swap | `_swapTicketSlot()` hard gate | Already built in Phase 1, reverts automatically |
| Legacy shim removal | Manual find-replace of 70 shim calls | Separate effort per module, using `_getPrizePools()`/`_setPrizePools()` | Phase 2 should focus on queue keys; shim migration can be a plan within this phase or deferred |

## Common Pitfalls

### Pitfall 1: ticketsOwedPacked Key Mismatch
**What goes wrong:** Changing `ticketQueue[targetLevel]` to `ticketQueue[wk]` but leaving `ticketsOwedPacked[targetLevel]` unchanged. Player is added to queue in buffer A but their owed count is tracked under the raw level key. Processing reads from buffer A, finds the player, but reads zero owed tickets from the raw key.
**Why it happens:** The two mappings are accessed at different lines in the function, easy to miss one.
**How to avoid:** For each function, count the total `ticketQueue` + `ticketsOwedPacked` accesses. After migration, the count of keyed accesses must equal the original count.
**Warning signs:** Test where a player queued after a swap has zero tickets when processed.

### Pitfall 2: Private Helper Parameter Signature Change
**What goes wrong:** `_processOneTicketEntry` in JackpotModule currently takes `uint24 lvl` and uses it for both mapping access and roll salt computation. If you rename the parameter to `rk`, the roll salt changes, which changes trait generation determinism.
**Why it happens:** The `lvl` parameter serves dual purpose.
**How to avoid:** Add a NEW `uint24 rk` parameter alongside the existing `lvl`. Use `rk` for mappings, `lvl` for salt.
**Warning signs:** Trait generation produces different results for the same VRF entropy.

### Pitfall 3: Constructor Uses Write Key Correctly by Default
**What goes wrong:** Worrying that the constructor's `_queueTickets` calls need special handling.
**Why it happens:** Constructor runs before any state initialization beyond defaults.
**How to avoid:** `ticketWriteSlot` defaults to 0, so `_tqWriteKey(level)` returns the raw level -- identical to the current behavior. No constructor changes needed. The write-path key substitution in `_queueTickets` handles this automatically.
**Warning signs:** None -- this is a non-issue, but worth documenting.

### Pitfall 4: Mid-Day Path Must Handle ticketsFullyProcessed Gate
**What goes wrong:** The mid-day swap path swaps the buffer while the read slot still has unprocessed entries.
**Why it happens:** Skipping the `ticketsFullyProcessed` check in the mid-day path.
**How to avoid:** Mid-day path MUST process the read slot first (via `_runProcessTicketBatch`), then only attempt a swap when `ticketsFullyProcessed` is true. The `_swapTicketSlot` hard gate provides a safety net, but the flow should not rely on hitting the revert.
**Warning signs:** `_swapTicketSlot` reverts unexpectedly during mid-day calls.

### Pitfall 5: Legacy Shim Migration Scope
**What goes wrong:** Trying to migrate all 70 legacy shim calls in the same plan as the queue key migration, creating an oversized changeset.
**Why it happens:** The shims are marked "REMOVE IN PHASE 2" in the source.
**How to avoid:** Consider splitting: Plan 1 = queue key migration (QUEUE-01 through QUEUE-03), Plan 2 = legacy shim migration + mid-day swap trigger (QUEUE-04) + tests. OR: Plan 1 = all queue work, Plan 2 = shim migration. The shim migration is NOT a QUEUE requirement -- it's cleanup from Phase 1.
**Recommendation:** Keep shim migration as a separate plan within Phase 2 since the comment says "REMOVE IN PHASE 2." This is optional -- the shims work correctly, they're just inefficient (extra SLOAD per call).

### Pitfall 6: View Functions in DegenerusGame.sol
**What goes wrong:** `ticketsOwedView` (line 2061) and `getPlayerPurchases` (line 2742) use raw `lvl` / `level` keys. After queue key migration, they return data for whichever buffer happens to use the raw key.
**Why it happens:** View functions were written before double-buffering.
**How to avoid:** These view functions should use `_tqWriteKey(lvl)` since users want to see their CURRENT (write-side) ticket status. Alternatively, provide both: write-side owed + read-side owed. The simplest change is to use write key, since that's where new purchases land.
**Warning signs:** Players see zero tickets after a swap, until the next swap flips the key back.

## Code Examples

### Write-Path Migration: _queueTickets
```solidity
// Source: DegenerusGameStorage.sol line 539, modified for QUEUE-01
function _queueTickets(
    address buyer,
    uint24 targetLevel,
    uint32 quantity
) internal {
    if (quantity == 0) return;
    emit TicketsQueued(buyer, targetLevel, quantity);  // logical level in event
    uint24 wk = _tqWriteKey(targetLevel);              // NEW
    uint40 packed = ticketsOwedPacked[wk][buyer];       // CHANGED
    uint32 owed = uint32(packed >> 8);
    uint8 rem = uint8(packed);
    if (owed == 0 && rem == 0) {
        ticketQueue[wk].push(buyer);                    // CHANGED
    }
    uint256 newOwed;
    unchecked {
        newOwed = uint256(owed) + quantity;
    }
    if (newOwed > type(uint32).max) {
        newOwed = type(uint32).max;
    }
    if (newOwed != owed) {
        ticketsOwedPacked[wk][buyer] =                  // CHANGED
            (uint40(uint32(newOwed)) << 8) |
            uint40(rem);
    }
}
```

### Read-Path Migration: processTicketBatch
```solidity
// Source: JackpotModule.sol line 1916, modified for QUEUE-02
function processTicketBatch(uint24 lvl) external returns (bool finished) {
    uint24 rk = _tqReadKey(lvl);                        // NEW
    address[] storage queue = ticketQueue[rk];           // CHANGED
    uint256 total = queue.length;

    if (ticketLevel != lvl) {
        ticketLevel = lvl;                               // logical level
        ticketCursor = 0;
    }

    uint256 idx = ticketCursor;
    if (idx >= total) {
        delete ticketQueue[rk];                          // CHANGED
        ticketCursor = 0;
        ticketLevel = 0;
        return true;
    }
    // ... processing loop (pass rk to _processOneTicketEntry) ...
    if (idx >= total) {
        delete ticketQueue[rk];                          // CHANGED
        ticketCursor = 0;
        ticketLevel = 0;
        return true;
    }
    return false;
}
```

### Mid-Day Swap Path
```solidity
// Source: audit/PLAN-ALWAYS-OPEN-PURCHASES.md section 4
// Replaces: if (day == dailyIdx) revert NotTimeYet();
if (day == dailyIdx) {
    // Mid-day path: process read slot, then conditionally swap
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
    if (ticketQueue[wk].length >= MID_DAY_SWAP_THRESHOLD || inJackpot) {
        _swapTicketSlot(purchaseLevel);  // swap only, NO freeze
        emit Advance(STAGE_TICKETS_WORKING, lvl);
        coin.creditFlip(caller, ADVANCE_BOUNTY);
        return;
    }
    revert NotTimeYet();
}
```

## Complete Site Inventory

### Write-path sites (QUEUE-01) -- must use `_tqWriteKey()`
| File | Function | Line | Access Type |
|------|----------|------|-------------|
| DegenerusGameStorage.sol | `_queueTickets` | 546, 550, 560 | `ticketsOwedPacked[targetLevel]` x2, `ticketQueue[targetLevel]` x1 |
| DegenerusGameStorage.sol | `_queueTicketsScaled` | 578, 582, 617 | `ticketsOwedPacked[targetLevel]` x2, `ticketQueue[targetLevel]` x1 |
| DegenerusGameStorage.sol | `_queueTicketRange` | 636, 640, 650 | `ticketsOwedPacked[lvl]` x2, `ticketQueue[lvl]` x1 (per loop iteration) |

### Read-path sites (QUEUE-02) -- must use `_tqReadKey()`
| File | Function | Line | Access Type |
|------|----------|------|-------------|
| JackpotModule.sol | `processTicketBatch` | 1919, 1931, 1971 | `ticketQueue[lvl]` x3 (read, delete, delete) |
| JackpotModule.sol | `_processOneTicketEntry` | 2018 | `ticketsOwedPacked[lvl]` x1 |
| JackpotModule.sol | `_resolveZeroOwedRemainder` | 1991, 1998, 2004 | `ticketsOwedPacked[lvl]` x3 |
| JackpotModule.sol | other private helpers | 2112 | `ticketsOwedPacked[lvl]` x1 (within batch processor) |
| MintModule.sol | `processFutureTicketBatch` | 298, 314, 316, 334, 340, 349, 356, 398, 416, 417 | `ticketQueue[lvl]` x3, `ticketsOwedPacked[lvl]` x7 |

### Far-future / view sites -- needs write key or both-buffer logic
| File | Function | Line | Current Key | Recommended Key |
|------|----------|------|-------------|-----------------|
| JackpotModule.sol | `_awardFarFutureCoinJackpot` | 2574 | `ticketQueue[candidate]` | `_tqWriteKey(candidate)` |
| DegenerusGame.sol | `_pickWinnersFromHistory` | 2680 | `ticketQueue[candidate]` | `_tqWriteKey(candidate)` |
| DegenerusGame.sol | `ticketsOwedView` | 2065 | `ticketsOwedPacked[lvl]` | `_tqWriteKey(lvl)` |
| DegenerusGame.sol | `getPlayerPurchases` | 2745 | `ticketsOwedPacked[level]` | `_tqWriteKey(level)` |

### Legacy shim sites (70 calls across 10 files) -- migrate to `_getPrizePools()`/`_setPrizePools()` pattern
These are NOT queue requirements but are marked "REMOVE IN PHASE 2" in source. Include as a separate plan.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Direct `ticketQueue[level]` access | Keyed via `_tqWriteKey`/`_tqReadKey` | This phase | Enables concurrent purchase + processing |
| Single `revert NotTimeYet()` for same-day calls | Conditional mid-day swap path | This phase | Allows throughput-driven queue draining |
| 70 legacy shim calls for pool access | Direct `_getPrizePools()`/`_setPrizePools()` | This phase (cleanup) | Eliminates extra SLOAD per shim call |

## Open Questions

1. **Far-future sampling: write key only vs. both buffers**
   - What we know: `_awardFarFutureCoinJackpot` samples levels 5-99 ahead. After a swap, some entries may be in the read buffer.
   - What's unclear: Whether missing a few entries in the read buffer (being processed) matters for BURNIE jackpot fairness.
   - Recommendation: Use `_tqWriteKey()` only. The window where entries exist only in read buffer for far-future levels is negligible (processing happens at current/near levels, not 5-99 ahead). Document the edge case.

2. **`_processOneTicketEntry` and `_resolveZeroOwedRemainder` parameter change**
   - What we know: These private functions in JackpotModule need `rk` for mapping access but `lvl` for roll salt.
   - Recommendation: Add `uint24 rk` parameter. Caller (`processTicketBatch`) computes once, passes down. This avoids recomputing `_tqReadKey` per queue entry (gas savings in tight processing loops).

3. **Legacy shim migration scope**
   - What we know: 70 shim calls across 10 files. Source comment says "REMOVE IN PHASE 2."
   - Options: (A) Separate plan within Phase 2 for shim cleanup. (B) Defer to a later phase.
   - Recommendation: Option A -- include as Plan 2, since the source explicitly marks them for this phase and they represent technical debt.

4. **`inJackpot` condition for mid-day swap with empty write queue**
   - What we know: QUEUE-04 says "jackpot phase is active and write queue is non-empty."
   - Implication: During jackpot phase, the mid-day swap fires even for small write queues (1+ entry), not just >= 440.
   - The plan pseudocode uses `if (writeLen >= 440 || inJackpot)` which would fire even with 0 entries in write queue during jackpot. But the hard gate in `_swapTicketSlot` would revert if the read slot is non-empty. Need to clarify: should the jackpot path check `writeLen > 0`?
   - Recommendation: Use `if (writeLen >= MID_DAY_SWAP_THRESHOLD || (inJackpot && writeLen > 0))` to avoid pointless swap attempts with an empty write queue.

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
| QUEUE-01 | `_queueTickets` writes to write-buffer key | unit | `forge test --match-test "testQueueTicketsUsesWriteKey" -vvv` | No -- Wave 0 |
| QUEUE-01 | `_queueTicketsScaled` writes to write-buffer key | unit | `forge test --match-test "testQueueTicketsScaledUsesWriteKey" -vvv` | No -- Wave 0 |
| QUEUE-01 | `_queueTicketRange` writes to write-buffer key | unit | `forge test --match-test "testQueueTicketRangeUsesWriteKey" -vvv` | No -- Wave 0 |
| QUEUE-01 | grep verification: no direct mapping key in write functions | smoke | `grep -c 'ticketQueue\[targetLevel\]\|ticketQueue\[lvl\]' contracts/storage/DegenerusGameStorage.sol` returns 0 | N/A (CLI) |
| QUEUE-02 | `processTicketBatch` reads from read-buffer key | unit | `forge test --match-test "testProcessTicketBatchUsesReadKey" -vvv` | No -- Wave 0 |
| QUEUE-02 | `processFutureTicketBatch` reads from read-buffer key | unit | `forge test --match-test "testProcessFutureTicketBatchUsesReadKey" -vvv` | No -- Wave 0 |
| QUEUE-02 | grep verification: no direct mapping key in processing functions | smoke | grep check on JackpotModule + MintModule | N/A (CLI) |
| QUEUE-03 | `_swapTicketSlot` reverts on non-empty read slot | unit | `forge test --match-test "testSwapTicketSlotRevertsNonEmpty" -vvv` | YES -- Phase 1 |
| QUEUE-04 | Mid-day swap fires at threshold 440 | unit | `forge test --match-test "testMidDaySwapAtThreshold" -vvv` | No -- Wave 0 |
| QUEUE-04 | Mid-day swap fires during jackpot phase with non-empty write | unit | `forge test --match-test "testMidDaySwapJackpotPhase" -vvv` | No -- Wave 0 |
| QUEUE-04 | Mid-day reverts NotTimeYet when below threshold and not jackpot | unit | `forge test --match-test "testMidDayRevertsNotTimeYet" -vvv` | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `forge clean && forge build` (compilation check)
- **Per wave merge:** `forge test` (full suite)
- **Phase gate:** grep verification for QUEUE-01/QUEUE-02 + all unit tests green + full `forge test` green

### Wave 0 Gaps
- [ ] `test/fuzz/QueueDoubleBuffer.t.sol` -- new test file covering QUEUE-01 through QUEUE-04
- [ ] Test harness contract extending StorageHarness to expose queue helpers with key verification
- [ ] For QUEUE-04 mid-day tests: may need a more complex harness that can simulate `advanceGame` state (day, dailyIdx, jackpotPhaseFlag) -- or test the mid-day logic in isolation via a harness that exposes the conditional path

## Sources

### Primary (HIGH confidence)
- `contracts/storage/DegenerusGameStorage.sol` -- all queue helper functions, Phase 1 key encoding helpers, swap function
- `contracts/modules/DegenerusGameJackpotModule.sol` -- `processTicketBatch`, `_processOneTicketEntry`, `_awardFarFutureCoinJackpot`
- `contracts/modules/DegenerusGameMintModule.sol` -- `processFutureTicketBatch`
- `contracts/modules/DegenerusGameAdvanceModule.sol` -- `advanceGame` flow, `_runProcessTicketBatch`, `_processFutureTicketBatch` delegatecall wrapper
- `contracts/DegenerusGame.sol` -- constructor, view functions, `_pickWinnersFromHistory`
- `audit/PLAN-ALWAYS-OPEN-PURCHASES.md` -- sections 2 and 4 (queue double-buffer and advanceGame flow)
- `.planning/phases/01-storage-foundation/01-VERIFICATION.md` -- Phase 1 completion status confirming all helpers exist

### Secondary (MEDIUM confidence)
- `.planning/phases/01-storage-foundation/01-RESEARCH.md` -- storage layout context, patterns established

### Tertiary (LOW confidence)
- None -- all findings verified from source code

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- same as Phase 1, no new tools
- Architecture: HIGH -- all affected code directly examined, line-by-line access inventory completed
- Pitfalls: HIGH -- identified from direct code analysis of mapping access patterns
- Mid-day path: MEDIUM -- plan document provides pseudocode but exact `inJackpot && writeLen > 0` vs `inJackpot` needs planner decision

**Research date:** 2026-03-11
**Valid until:** 2026-04-11 (stable domain; Solidity mapping access patterns don't change)
