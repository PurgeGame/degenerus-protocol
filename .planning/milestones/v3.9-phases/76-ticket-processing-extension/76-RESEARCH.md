# Phase 76: Ticket Processing Extension - Research

**Researched:** 2026-03-22
**Domain:** Solidity batch-processing function extension, cursor state encoding, dual-queue draining
**Confidence:** HIGH

## Summary

Phase 76 extends `processFutureTicketBatch` in DegenerusGameMintModule.sol to drain the far-future (FF) key space after the read-side queue for a given level is exhausted. Currently, the function only reads from `_tqReadKey(lvl)` (line 302) and never touches `_tqFarFutureKey(lvl)`. After Phase 75's routing change sends far-future tickets to the FF key, those tickets would sit permanently unprocessed unless `processFutureTicketBatch` is extended to also drain that key space.

The fix requires: (1) after the read-side queue is fully drained, continue to the FF key queue for the same level; (2) use the `ticketLevel` storage variable to unambiguously signal whether processing is in the read-side phase or the far-future phase (by setting the FF bit on `ticketLevel` when transitioning to FF processing); (3) only return `finished = true` when both queues are drained.

**Primary recommendation:** After draining `ticketQueue[_tqReadKey(lvl)]`, check `ticketQueue[_tqFarFutureKey(lvl)]`. If non-empty, transition to FF processing by setting `ticketLevel = lvl | TICKET_FAR_FUTURE_BIT` and resetting `ticketCursor = 0`, then process the FF queue with the same batching logic. Return `finished = true` only when both the read-side and FF queues are empty.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PROC-01 | processFutureTicketBatch drains the far-future key for each level after the read-side queue is fully drained | Current code at MintModule:302 only uses `_tqReadKey(lvl)`; must add FF key drain after read-side completion |
| PROC-02 | Cursor state tracking distinguishes read-side vs far-future processing (ticketLevel with FF bit) | `ticketLevel` (uint24, Storage:477) can encode the FF bit (bit 22) to signal which phase; `_prepareFutureTickets` (AdvanceModule:1156) reads `ticketLevel` to resume in-flight levels |
| PROC-03 | processFutureTicketBatch returns finished = true only when both queues are drained | Current code returns `finished = true` after read-side drain (MintModule:309,322,419); must defer `finished = true` until FF queue is also empty |
</phase_requirements>

## Architecture Patterns

### Current processFutureTicketBatch Flow (MintModule:298-425)

```
processFutureTicketBatch(lvl) called via delegatecall from AdvanceModule
  |
  +-- rk = _tqReadKey(lvl)                     [line 302]
  +-- queue = ticketQueue[rk]                   [line 303]
  +-- total = queue.length                      [line 304]
  |
  +-- If total == 0:                            [line 306-310]
  |     ticketCursor = 0, ticketLevel = 0
  |     return (false, true, 0)                 <-- BUG: declares "finished" without checking FF key
  |
  +-- If ticketLevel != lvl:                    [line 312-315]
  |     ticketLevel = lvl, ticketCursor = 0     (switch to this level)
  |
  +-- idx = ticketCursor                        [line 317]
  +-- If idx >= total:                          [line 318-323]
  |     delete ticketQueue[rk]
  |     ticketCursor = 0, ticketLevel = 0
  |     return (false, true, 0)                 <-- BUG: same issue
  |
  +-- Batch processing loop (idx < total && used < writesBudget)  [line 334-414]
  |     ... process entries, mint traits ...
  |
  +-- ticketCursor = uint32(idx)                [line 418]
  +-- finished = (idx >= total)                 [line 419]
  +-- If finished:                              [line 420-424]
        delete ticketQueue[rk]
        ticketCursor = 0, ticketLevel = 0
        return (true/false, true, used)         <-- BUG: same issue
```

There are exactly **three exit points** that return `finished = true`. All three only check the read-side queue. None check the FF key.

### Required Fix: Two-Phase Processing

After the read-side queue is drained, the function must check whether an FF queue exists for the same level and, if so, continue processing it before declaring finished.

```
processFutureTicketBatch(lvl) -- PROPOSED FLOW
  |
  +-- Determine which phase we're in from ticketLevel:
  |     If ticketLevel == (lvl | TICKET_FAR_FUTURE_BIT):
  |       -> We're resuming FF processing (phase 2)
  |       -> rk = _tqFarFutureKey(lvl)
  |     Else:
  |       -> We're in read-side processing (phase 1) or starting fresh
  |       -> rk = _tqReadKey(lvl)
  |
  +-- Process the selected queue (same batching logic)
  |
  +-- When the current queue is fully drained:
  |     If we were in phase 1 (read-side):
  |       -> Check if ticketQueue[_tqFarFutureKey(lvl)] is non-empty
  |       -> If yes: set ticketLevel = lvl | TICKET_FAR_FUTURE_BIT,
  |                  ticketCursor = 0, return (worked, false, used)
  |       -> If no:  ticketLevel = 0, ticketCursor = 0,
  |                  return (worked, true, used)
  |     If we were in phase 2 (FF):
  |       -> Both queues drained.
  |       -> ticketLevel = 0, ticketCursor = 0,
  |          return (worked, true, used)
```

### ticketLevel Encoding for PROC-02

The `ticketLevel` storage variable is `uint24` (Storage:477). Phase 74 established `TICKET_FAR_FUTURE_BIT = 1 << 22` as the FF bit for key encoding. The same bit can encode the processing phase in `ticketLevel`:

| ticketLevel value | Meaning | Key to use |
|-------------------|---------|------------|
| `0` | No processing in flight | N/A |
| `lvl` (bit 22 clear) | Processing read-side queue for level `lvl` | `_tqReadKey(lvl)` |
| `lvl \| TICKET_FAR_FUTURE_BIT` (bit 22 set) | Processing FF queue for level `lvl` | `_tqFarFutureKey(lvl)` |

This is unambiguous because real game levels never have bit 22 set (max real level is well below 2^22). The FF bit in `ticketLevel` means "we're in the far-future processing phase for the base level in the lower 22 bits."

### Interaction with _prepareFutureTickets (AdvanceModule:1156-1182)

`_prepareFutureTickets` reads `ticketLevel` to determine the resume level:

```solidity
uint24 resumeLevel = ticketLevel;

// Continue an in-flight future level first to preserve progress.
if (resumeLevel >= startLevel && resumeLevel <= endLevel) {
    (bool worked, bool levelFinished, ) = _processFutureTicketBatch(resumeLevel);
    if (worked || !levelFinished) return false;
}
```

**Critical interaction:** If `ticketLevel` has the FF bit set (e.g., `ticketLevel = 8 | 0x400000 = 0x400008`), then `resumeLevel` will be `0x400008`, which is far outside the `startLevel..endLevel` range (which is `lvl+2..lvl+6`, small values). This means the resume check will be skipped, and the function will enter the loop and call `_processFutureTicketBatch(target)` for each level fresh.

This is a problem: if we were mid-FF-processing for level 8, `_prepareFutureTickets` won't resume it because `0x400008 > endLevel`. The function will call `_processFutureTicketBatch(8)` fresh, which will set `ticketLevel = 8` and start the read-side queue (already empty since it was drained), then transition to the FF queue.

**However, this is actually correct behavior** because:
1. `_prepareFutureTickets` passes the raw level (e.g., 8) to `_processFutureTicketBatch`
2. `processFutureTicketBatch` receives `lvl = 8` and checks `ticketLevel`
3. If `ticketLevel == 8 | TICKET_FAR_FUTURE_BIT`, the function detects it's resuming FF processing
4. It sets `rk = _tqFarFutureKey(8)` and continues from `ticketCursor`

The critical design point is that `processFutureTicketBatch` internally handles the phase detection via `ticketLevel` encoding. The caller (`_prepareFutureTickets`) just passes the raw level.

**BUT there is still a subtlety with the resume path:** `_prepareFutureTickets` checks `resumeLevel >= startLevel && resumeLevel <= endLevel`. When `ticketLevel = lvl | FF_BIT`, `resumeLevel = 0x40000X` which fails this range check. So `_prepareFutureTickets` won't attempt to resume -- it will fall through to the loop and try each level fresh. When it calls `_processFutureTicketBatch(target)` where `target` matches the base level being FF-processed, the function must detect that `ticketLevel = target | FF_BIT` and resume correctly.

**Recommended approach:** Modify `_prepareFutureTickets` to also check the FF-encoded version of `resumeLevel`:

```solidity
uint24 resumeLevel = ticketLevel;
uint24 baseResume = resumeLevel & ~uint24(TICKET_FAR_FUTURE_BIT); // strip FF bit if present

if (baseResume >= startLevel && baseResume <= endLevel) {
    (bool worked, bool levelFinished, ) = _processFutureTicketBatch(baseResume);
    if (worked || !levelFinished) return false;
}
```

Alternatively (simpler): leave `_prepareFutureTickets` unchanged. `processFutureTicketBatch(lvl)` handles the resume internally by checking if `ticketLevel == lvl | FF_BIT`. If `_prepareFutureTickets` skips the resume and calls fresh for each level, `processFutureTicketBatch` will:
- For the level being FF-processed: detect `ticketLevel == lvl | FF_BIT`, go straight to FF queue, resume from `ticketCursor`
- For other levels: process normally

**However**, there is a correctness issue with the simpler approach: if `_prepareFutureTickets` skips the resume check and enters the loop, it will call `_processFutureTicketBatch(startLevel)` first, which may set `ticketLevel = startLevel` (overwriting the FF-processing state for the actual level being worked on). This would lose progress.

**Therefore, the _prepareFutureTickets fix is required.** The resume level must be decoded by stripping the FF bit.

### Interaction with _processFutureTicketBatch Call at Line 305

The single-level call at AdvanceModule:305:
```solidity
uint24 nextLevel = purchaseLevel + 1;
(bool futureWorked, bool futureFinished, ) = _processFutureTicketBatch(nextLevel);
```

This call passes a raw level. `processFutureTicketBatch` will handle both phases internally. No changes needed here because there is no resume logic -- it just calls until `futureFinished == true`.

### Files to Modify

```
contracts/
  modules/
    DegenerusGameMintModule.sol     # Primary: extend processFutureTicketBatch
    DegenerusGameAdvanceModule.sol  # Secondary: fix _prepareFutureTickets resume check
```

No new files (test files in Phase 80). No interface changes -- `processFutureTicketBatch` signature unchanged.

### Anti-Patterns to Avoid

- **Adding a new storage variable for phase tracking:** Use the existing `ticketLevel` uint24 with the FF bit. Adding a new bool or enum wastes a storage slot and creates coupling risk.
- **Copying the entire processing loop:** The read-side and FF processing use identical batching logic. Factor the queue selection (which `rk` to use) into the function entry, then reuse the same loop body.
- **Checking FF queue length inside the main loop:** The FF queue check should happen only at the point where the read-side queue is fully drained, not on every iteration.
- **Returning finished=true between read-side drain and FF queue check:** There must be no point where the function returns `finished=true` after draining the read-side queue but before checking/draining the FF queue.
- **Modifying the interface return type:** The existing `(bool worked, bool finished, uint32 writesUsed)` signature is sufficient. No additional return values needed.
- **Processing both queues in a single call:** The function already has a write budget. It should drain whichever queue is active until the budget is exhausted. Switching from read-side to FF mid-budget is fine, but do not try to estimate remaining budget for the second queue specially.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Phase detection | New storage variable, enum, or bool | `ticketLevel & TICKET_FAR_FUTURE_BIT` check | Bit is already reserved by Phase 74; reuses existing uint24 |
| FF key computation | Inline `lvl \| (1 << 22)` | `_tqFarFutureKey(lvl)` helper from Phase 74 | Consistency, single definition of the bit |
| Base level extraction | Manual bit masking in callers | `ticketLevel & ~uint24(TICKET_FAR_FUTURE_BIT)` or `ticketLevel & uint24((1 << 22) - 1)` | Both are equivalent; the mask strips bit 22 to get the raw level |
| Batch processing logic | Separate loop for FF queue | Same loop body with different `rk` | Identical logic; only the queue key differs |

## Common Pitfalls

### Pitfall 1: Missing FF Queue Check at Empty Read-Side Entry
**What goes wrong:** When `processFutureTicketBatch(lvl)` is called and the read-side queue is already empty (`total == 0` at line 306), the function currently returns `(false, true, 0)` immediately. If the fix only adds FF queue processing after the main loop, this early return bypasses it.
**Why it happens:** There are three `return (false, true, 0)` exit points. The post-loop fix catches only one of them.
**How to avoid:** All three exit points that declare `finished = true` must check the FF queue before returning. Or restructure to have a single "completion" path.
**Warning signs:** Test shows FF tickets stranded when the read-side queue is already empty at the time `processFutureTicketBatch` is called.

### Pitfall 2: _prepareFutureTickets Resume Failure
**What goes wrong:** After processing starts on the FF queue, `ticketLevel = lvl | FF_BIT`. The next `advanceGame` call invokes `_prepareFutureTickets` which reads `ticketLevel` and compares against `startLevel..endLevel`. The FF-encoded value (e.g., 0x400008) exceeds `endLevel`, so the resume path is skipped. The function then calls `_processFutureTicketBatch(startLevel)` which overwrites `ticketLevel`, losing the FF processing cursor.
**Why it happens:** `_prepareFutureTickets` was written before the FF encoding existed.
**How to avoid:** Strip the FF bit when reading `ticketLevel` in `_prepareFutureTickets`.
**Warning signs:** FF processing restarts from the beginning on every `advanceGame` call instead of resuming from `ticketCursor`.

### Pitfall 3: Double-Delete of Read-Side Queue
**What goes wrong:** When transitioning from read-side to FF processing, the code `delete ticketQueue[rk]` for the read-side queue is called. If the function is later called again and re-checks the read-side queue (due to `ticketLevel` not having the FF bit), it would redundantly check an already-deleted queue. This isn't a correctness bug but wastes gas.
**Why it happens:** The transition from phase 1 to phase 2 must clean up the read-side queue exactly once.
**How to avoid:** After draining the read-side queue, `delete` it, then immediately check and transition to FF. The FF bit on `ticketLevel` ensures subsequent calls skip the read-side entirely.
**Warning signs:** Extra SLOAD on empty read-side queue during FF processing.

### Pitfall 4: ticketLevel Collision with processTicketBatch (JackpotModule)
**What goes wrong:** `processTicketBatch` in JackpotModule (line 1890) shares the same `ticketLevel` and `ticketCursor` storage variables. If both functions are in-flight simultaneously, they corrupt each other's state.
**Why it happens:** The storage variables are reused across phases (documented in Storage:469-477).
**How to avoid:** This is actually safe by design -- the advanceGame flow is sequential. `processTicketBatch` (current-level processing) runs to completion before `_prepareFutureTickets`/`_processFutureTicketBatch` (future-level processing) begins. They never interleave. But the FF bit encoding in `ticketLevel` must not confuse `processTicketBatch` -- verify that `processTicketBatch` cannot be called while `ticketLevel` has the FF bit set.
**Warning signs:** `processTicketBatch` interpreting `ticketLevel = lvl | FF_BIT` as a different level and processing the wrong queue.

### Pitfall 5: Budget Accounting Across Phase Transition
**What goes wrong:** If the read-side queue is drained mid-batch (with remaining budget), and the function transitions to the FF queue in the same call, the budget accounting could double-count writes or use an incorrect remaining budget.
**Why it happens:** The transition between phases must correctly account for writes already used.
**How to avoid:** After draining the read-side queue, calculate `writesRemaining = writesBudget - used`. If `writesRemaining > 0` and the FF queue is non-empty, continue processing the FF queue with the remaining budget. Alternatively, return after draining the read-side and let the next call start the FF queue (simpler but less efficient).
**Warning signs:** Gas usage unexpectedly doubling on the transition call.

## Code Examples

### processFutureTicketBatch Extension Pattern

```solidity
// Source: contracts/modules/DegenerusGameMintModule.sol, line 298
// PROPOSED MODIFICATION (structural, not line-exact)

function processFutureTicketBatch(
    uint24 lvl
) external returns (bool worked, bool finished, uint32 writesUsed) {
    uint256 entropy = rngWordCurrent;

    // Determine which phase we're in based on ticketLevel encoding
    bool inFarFuture = (ticketLevel == (lvl | TICKET_FAR_FUTURE_BIT));
    uint24 rk = inFarFuture ? _tqFarFutureKey(lvl) : _tqReadKey(lvl);
    address[] storage queue = ticketQueue[rk];
    uint256 total = queue.length;

    if (total > type(uint32).max) revert E();
    if (total == 0) {
        if (!inFarFuture) {
            // Read-side empty -- check FF queue before declaring finished
            uint24 ffk = _tqFarFutureKey(lvl);
            if (ticketQueue[ffk].length > 0) {
                // Transition to FF phase
                ticketLevel = lvl | TICKET_FAR_FUTURE_BIT;
                ticketCursor = 0;
                return (false, false, 0); // Not finished -- FF queue pending
            }
        }
        // Both queues empty (or FF queue also empty)
        ticketCursor = 0;
        ticketLevel = 0;
        return (false, true, 0);
    }

    // Set cursor for this level/phase if switching
    if (!inFarFuture && ticketLevel != lvl) {
        ticketLevel = lvl;
        ticketCursor = 0;
    }
    // (if inFarFuture, ticketLevel is already set correctly from the transition)

    uint256 idx = ticketCursor;
    if (idx >= total) {
        delete ticketQueue[rk];
        if (!inFarFuture) {
            // Read-side fully drained -- check FF queue
            uint24 ffk = _tqFarFutureKey(lvl);
            if (ticketQueue[ffk].length > 0) {
                ticketLevel = lvl | TICKET_FAR_FUTURE_BIT;
                ticketCursor = 0;
                return (false, false, 0);
            }
        }
        ticketCursor = 0;
        ticketLevel = 0;
        return (false, true, 0);
    }

    // === Existing batch processing loop (unchanged) ===
    // ... (lines 326-414 stay the same) ...

    worked = (used > 0);
    writesUsed = used;
    ticketCursor = uint32(idx);
    finished = (idx >= total);
    if (finished) {
        delete ticketQueue[rk];
        if (!inFarFuture) {
            // Read-side fully drained -- check FF queue
            uint24 ffk = _tqFarFutureKey(lvl);
            if (ticketQueue[ffk].length > 0) {
                ticketLevel = lvl | TICKET_FAR_FUTURE_BIT;
                ticketCursor = 0;
                finished = false; // Not done yet
            } else {
                ticketCursor = 0;
                ticketLevel = 0;
            }
        } else {
            ticketCursor = 0;
            ticketLevel = 0;
        }
    }
}
```

### _prepareFutureTickets Resume Fix

```solidity
// Source: contracts/modules/DegenerusGameAdvanceModule.sol, line 1156
// PROPOSED MODIFICATION

function _prepareFutureTickets(uint24 lvl) private returns (bool finished) {
    uint24 startLevel = lvl + 2;
    uint24 endLevel = lvl + 6;
    uint24 resumeLevel = ticketLevel;

    // Strip FF bit to get base level for range comparison
    // (if FF bit is set, we're mid-FF-processing for that base level)
    uint24 baseResume = resumeLevel & ~uint24(TICKET_FAR_FUTURE_BIT);

    // Continue an in-flight future level first to preserve progress.
    if (baseResume >= startLevel && baseResume <= endLevel) {
        (bool worked, bool levelFinished, ) = _processFutureTicketBatch(
            baseResume  // Pass base level; processFutureTicketBatch detects FF phase internally
        );
        if (worked || !levelFinished) return false;
    }

    // Then probe remaining target levels in order.
    for (uint24 target = startLevel; target <= endLevel; ) {
        if (target != baseResume) {
            (bool worked, bool levelFinished, ) = _processFutureTicketBatch(
                target
            );
            if (worked || !levelFinished) return false;
        }
        unchecked {
            ++target;
        }
    }
    return true;
}
```

### Key State Transitions

```
State Machine for ticketLevel during processFutureTicketBatch:

  [ticketLevel = 0]
       |
       | Called with lvl=N, read-side queue non-empty
       v
  [ticketLevel = N]  -- processing read-side queue
       |
       | Read-side queue fully drained, FF queue non-empty
       v
  [ticketLevel = N | FF_BIT]  -- processing FF queue
       |
       | FF queue fully drained (or FF queue was empty)
       v
  [ticketLevel = 0]  -- finished
```

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge) + Hardhat |
| Config file | foundry.toml, hardhat.config.js |
| Quick run command | `npx hardhat compile` |
| Full suite command | `forge test && npx hardhat test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PROC-01 | processFutureTicketBatch drains FF key after read-side | unit | `forge test --match-test testDrainsFFAfterReadSide -vv` | Wave 0 |
| PROC-02 | ticketLevel encodes FF bit to distinguish processing phase | unit | `forge test --match-test testTicketLevelFFEncoding -vv` | Wave 0 |
| PROC-03 | finished=true only when both queues drained | unit | `forge test --match-test testFinishedRequiresBothQueues -vv` | Wave 0 |

### Sampling Rate
- **Per task commit:** `npx hardhat compile` (must succeed)
- **Per wave merge:** `forge test` (full Foundry suite)
- **Phase gate:** All 3 requirement tests pass + full suite green

### Wave 0 Gaps
- [ ] Foundry test harness exposing `processFutureTicketBatch` with controllable `ticketQueue`, `ticketLevel`, `ticketCursor`, `ticketWriteSlot`, `rngWordCurrent` state
- [ ] Test: read-side queue non-empty, FF queue non-empty -- function drains read-side first, then transitions to FF, then returns finished=true
- [ ] Test: read-side queue empty, FF queue non-empty -- function transitions immediately to FF processing
- [ ] Test: read-side queue non-empty, FF queue empty -- function drains read-side and returns finished=true (no FF phase)
- [ ] Test: both queues empty -- returns (false, true, 0) immediately
- [ ] Test: ticketLevel encodes FF bit during FF processing phase
- [ ] Test: _prepareFutureTickets correctly resumes FF-encoded ticketLevel across advanceGame calls
- [ ] Test: mid-batch budget exhaustion during read-side leaves cursor intact, next call resumes
- [ ] Test: mid-batch budget exhaustion during FF phase leaves cursor intact, next call resumes

Note: Comprehensive integration tests are deferred to Phase 80 (TEST-02, TEST-05). Phase 76 tests focus on the dual-queue draining logic and cursor state encoding.

## Open Questions

1. **Should the function transition to FF processing within the same write budget, or return and start FF on the next call?**
   - What we know: Returning early (with `finished=false`) and starting FF on the next call is simpler and avoids budget-accounting complexity. However, it costs one extra `advanceGame` transaction when the read-side queue is small.
   - What's unclear: Whether the gas cost of one additional tx is significant enough to warrant intra-call transition.
   - Recommendation: Return after draining the read-side queue and start FF on the next call. The simplicity is worth the one-tx overhead. The `advanceBounty` system compensates callers anyway. This avoids pitfall 5 (budget accounting across transition).

2. **Should _prepareFutureTickets strip the FF bit, or should processFutureTicketBatch handle it?**
   - What we know: Both approaches work. Stripping in `_prepareFutureTickets` is cleaner because it keeps the resume logic correct without requiring `processFutureTicketBatch` to handle a "wrong level" input.
   - What's unclear: Whether other callers of `_processFutureTicketBatch` (line 305 in AdvanceModule) are affected.
   - Recommendation: Strip in `_prepareFutureTickets`. The single-level call at line 305 always passes `purchaseLevel + 1` (a raw level), so it is unaffected. `processFutureTicketBatch` detects the FF phase via `ticketLevel` encoding, not the input `lvl` parameter.

3. **Does processTicketBatch (JackpotModule) need a similar FF extension?**
   - What we know: `processTicketBatch` in JackpotModule (line 1890) processes current-level tickets using `_tqReadKey(lvl)`. Current-level tickets are never in the FF key space (they're in the read-side buffer after a slot swap).
   - Recommendation: No change needed. `processTicketBatch` processes the current level's read-side queue (tickets for the level being played). Far-future tickets are only activated by `processFutureTicketBatch` when their target level arrives. These are different functions with different purposes, and `processTicketBatch` never needs to touch the FF key.

## Sources

### Primary (HIGH confidence)
- contracts/modules/DegenerusGameMintModule.sol:298-425 -- Full `processFutureTicketBatch` implementation (current code, read-side only)
- contracts/modules/DegenerusGameAdvanceModule.sol:1134-1182 -- `_processFutureTicketBatch` delegatecall wrapper and `_prepareFutureTickets` caller
- contracts/modules/DegenerusGameAdvanceModule.sol:280-310 -- Single-level call at purchase-to-jackpot transition
- contracts/storage/DegenerusGameStorage.sol:460-477 -- `ticketQueue`, `ticketsOwedPacked`, `ticketCursor`, `ticketLevel` declarations
- contracts/storage/DegenerusGameStorage.sol:714-731 -- `_tqWriteKey`, `_tqReadKey`, `_tqFarFutureKey` key encoding helpers
- contracts/storage/DegenerusGameStorage.sol:162 -- `TICKET_FAR_FUTURE_BIT = 1 << 22` constant
- contracts/interfaces/IDegenerusGameModules.sol:276-283 -- `processFutureTicketBatch` interface (signature unchanged)
- contracts/modules/DegenerusGameJackpotModule.sol:1890-1951 -- `processTicketBatch` (JackpotModule, for comparison; NOT being modified)
- .planning/phases/74-storage-foundation/74-01-PLAN.md -- Phase 74 establishing TICKET_FAR_FUTURE_BIT and _tqFarFutureKey
- .planning/phases/75-ticket-routing-rng-guard/75-01-PLAN.md -- Phase 75 routing far-future tickets to FF key
- .planning/phases/75-ticket-routing-rng-guard/75-RESEARCH.md -- Phase 75 research documenting caller classification and advanceGame flow

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- pure Solidity modification to existing MintModule function; no new libraries, no interface changes
- Architecture: HIGH -- the dual-queue drain pattern is a straightforward extension of the existing single-queue drain; the FF bit encoding in ticketLevel is clean and uses the already-reserved bit 22
- Pitfalls: HIGH -- identified from direct analysis of all three `finished=true` exit points, the `_prepareFutureTickets` resume interaction, and the shared `ticketLevel`/`ticketCursor` storage

**Research date:** 2026-03-22
**Valid until:** Indefinite (Solidity control flow analysis; valid as long as the function signatures and advanceGame call flow remain unchanged)
