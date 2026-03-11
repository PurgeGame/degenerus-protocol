# Phase 4: advanceGame Rewrite - Research

**Researched:** 2026-03-11
**Domain:** Solidity state machine rewrite (DegenerusGameAdvanceModule.sol)
**Confidence:** HIGH

## Summary

Phase 4 rewrites the `advanceGame` function in `DegenerusGameAdvanceModule.sol` to correctly integrate the double-buffer ticket queue and prize pool freeze system built in Phases 1-3. The primary change is inserting a `ticketsFullyProcessed` gate before the daily RNG request and ensuring every `do { } while(false)` break path either unfreezes the pool or is demonstrably under active freeze by design.

The current code already has the mid-day path (lines 147-171) correctly implemented from Phase 2, including the `ticketsFullyProcessed` flag management and mid-day swap trigger. The daily path (the `do { } while(false)` block, lines 174-320) has `_swapAndFreeze` and `_unfreezePool` wired at the correct sites from Phase 3. What remains is: (1) gating the daily RNG request behind `ticketsFullyProcessed`, (2) setting the flag before jackpot/phase logic, and (3) verifying every break path's freeze-state correctness with tests.

**Primary recommendation:** Restructure the daily path to drain the read slot BEFORE entering `rngGate`, gate the RNG request on `ticketsFullyProcessed == true`, and write tests that assert freeze-state invariants at every break path.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| ADV-01 | Mid-day path: process read slot, trigger swap (no freeze) when qualified | Mid-day path already implemented in Phase 2 (lines 147-171). Needs test confirming pools are NOT frozen after mid-day call. |
| ADV-02 | Daily path gates RNG request behind `ticketsFullyProcessed` | Current daily path calls `rngGate` before checking tickets. Must restructure to drain read slot first, then proceed to RNG only when `ticketsFullyProcessed == true`. |
| ADV-03 | `ticketsFullyProcessed` set before jackpot/phase logic executes | Currently `ticketsFullyProcessed` is never set in the daily path. Must add explicit `ticketsFullyProcessed = true` after the read slot drain completes, before jackpot/phase logic. |
</phase_requirements>

## Architecture Patterns

### Current advanceGame Control Flow (lines 121-324)

```
advanceGame()
  |-- GameOver check (early return)
  |-- Daily mint gate
  |-- IF day == dailyIdx (MID-DAY PATH)
  |     |-- Drain read slot if !ticketsFullyProcessed
  |     |-- Swap write->read if threshold met
  |     \-- revert NotTimeYet
  |
  \-- DAILY PATH: do { } while(false)
        |-- rngGate() -> if returns 1: _swapAndFreeze, break (STAGE_RNG_REQUESTED)
        |-- phaseTransitionActive? process transition, break
        |-- Final jackpot day? process future tickets
        |-- _runProcessTicketBatch -> if working: break (STAGE_TICKETS_WORKING)
        |-- PURCHASE PHASE (!inJackpot)
        |     |-- Pre-target: daily jackpots, _unlockRng, _unfreezePool, break (STAGE_PURCHASE_DAILY)
        |     |-- lastPurchaseDay: future tickets, consolidate, enter jackpot, break (STAGE_ENTERED_JACKPOT)
        |     (no unfreeze - intentional: day-1 jackpot runs same day)
        |
        \-- JACKPOT PHASE (inJackpot)
              |-- ETH resume: payDailyJackpot, break (STAGE_JACKPOT_ETH_RESUME)
              |-- Coin+tickets pending:
              |     |-- counter >= CAP: _endPhase, _unfreezePool, break (STAGE_JACKPOT_PHASE_ENDED)
              |     \-- counter < CAP: _unlockRng (no unfreeze), break (STAGE_JACKPOT_COIN_TICKETS)
              \-- Fresh daily jackpot: payDailyJackpot, break (STAGE_JACKPOT_DAILY_STARTED)
```

### Required Restructuring

The daily path currently calls `rngGate` first (line 176), THEN processes tickets (line 216). This must be restructured so ticket draining happens first:

```
DAILY PATH (restructured):
  |-- IF !ticketsFullyProcessed:
  |     |-- Drain read slot via _runProcessTicketBatch
  |     |-- If still working: emit Advance, return (bounce caller)
  |     |-- If done: ticketsFullyProcessed = true
  |
  |-- do { } while(false)  -- ONLY entered when ticketsFullyProcessed == true
        |-- rngGate() -> if returns 1: _swapAndFreeze, break
        |-- ... (rest unchanged)
```

This ensures ADV-02 (RNG gate) and ADV-03 (flag set before jackpot logic) are both satisfied structurally.

### Break Path Freeze-State Audit

Every break path with documented freeze expectation:

| # | Break Path | Stage Constant | Freeze Active? | Unfreeze Call? | Rationale |
|---|------------|-------|---------------|----------------|-----------|
| 1 | RNG requested | STAGE_RNG_REQUESTED | YES (just set) | No | Freeze persists until RNG resolves |
| 2 | Transition working | STAGE_TRANSITION_WORKING | YES (from RNG req) | No | Transition still in progress |
| 3 | Transition done | STAGE_TRANSITION_DONE | NO (just cleared) | YES (line 191) | Phase complete, unfreeze |
| 4 | Future tickets (final day) | STAGE_FUTURE_TICKETS_WORKING | YES (from RNG req) | No | Still processing |
| 5 | Tickets working | STAGE_TICKETS_WORKING | YES (from RNG req) | No | Still processing |
| 6 | Purchase daily | STAGE_PURCHASE_DAILY | NO (just cleared) | YES (line 235) | Daily complete, unfreeze |
| 7 | Future tickets (pre-jackpot) | STAGE_FUTURE_TICKETS_WORKING | YES (from RNG req) | No | Still processing |
| 8 | Entered jackpot | STAGE_ENTERED_JACKPOT | YES (intentional) | No | Day-1 jackpot runs same day |
| 9 | Jackpot ETH resume | STAGE_JACKPOT_ETH_RESUME | YES (jackpot phase) | No | Multi-day jackpot in progress |
| 10 | Jackpot phase ended | STAGE_JACKPOT_PHASE_ENDED | NO (just cleared) | YES (line 308) | All 5 jackpot days complete |
| 11 | Jackpot coin tickets (mid) | STAGE_JACKPOT_COIN_TICKETS | YES (jackpot phase) | No | FREEZE-04: freeze persists across all 5 days |
| 12 | Jackpot daily started | STAGE_JACKPOT_DAILY_STARTED | YES (jackpot phase) | No | Jackpot day started, processing continues |

**Key invariant:** `_unfreezePool()` is called at exactly 3 exit points:
1. `STAGE_TRANSITION_DONE` (line 191) -- phase transition complete
2. `STAGE_PURCHASE_DAILY` (line 235) -- daily purchase phase complete
3. `STAGE_JACKPOT_PHASE_ENDED` (line 308) -- all 5 jackpot days complete

All other break paths are either (a) intermediate processing steps that will reach an unfreeze on a subsequent call, or (b) intentionally under active freeze during multi-day jackpot phase (FREEZE-04).

### Anti-Patterns to Avoid

- **Moving `_unfreezePool()` to wrong break paths:** The STAGE_ENTERED_JACKPOT break intentionally keeps freeze active. Adding unfreeze there would break FREEZE-04 (multi-day freeze persistence).
- **Placing the drain gate inside the `do{}while(false)`:** A `break` from a drain check would fall through to `emit Advance + coin.creditFlip` but the stage variable would be uninitialized (zero). Use `return` (full exit) instead.
- **Forgetting `ticketsFullyProcessed = true` after daily drain:** Without this, subsequent calls re-enter the drain loop even when the read slot is empty, wasting gas.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Freeze-state tracking | Manual boolean tracking per path | Existing `_swapAndFreeze()` / `_unfreezePool()` from Phase 3 | Already atomic with slot swap; adding manual tracking creates consistency hazards |
| Ticket cursor management | Custom cursor logic | Existing `_runProcessTicketBatch()` via JackpotModule delegatecall | Cursor state managed by JackpotModule; reimplementing risks cursor drift |
| Read slot draining | New drain function | Same `_runProcessTicketBatch(purchaseLevel)` used in mid-day path | Proven gas-bounded, handles cursor reset on level change (JackpotModule line 1924-1926) |

## Common Pitfalls

### Pitfall 1: Empty read slot on first daily call
**What goes wrong:** On the first daily call after mid-day processing, the read slot is empty (already drained mid-day). `_runProcessTicketBatch` returns `(false, true)` with no work done but `ticketsFullyProcessed` might still be false if a swap occurred.
**How to avoid:** The drain guard must handle the empty-read-slot case. Check if `ticketQueue[readKey].length > 0` before calling `_runProcessTicketBatch`, same as the mid-day path does (line 151). If empty, just set `ticketsFullyProcessed = true` and proceed.

### Pitfall 2: purchaseLevel calculation under lastPurchaseDay + rngLockedFlag
**What goes wrong:** `purchaseLevel` is computed as `(lastPurchase && rngLockedFlag) ? lvl : lvl + 1` (line 129). The drain step runs BEFORE `rngGate` (new structure), when `rngLockedFlag` is false, so `purchaseLevel = lvl + 1`. This is correct and consistent with how the mid-day path uses it.
**How to avoid:** No change needed. `purchaseLevel` is captured once at function entry and used consistently throughout.

### Pitfall 3: _swapAndFreeze resetting ticketsFullyProcessed
**What goes wrong:** When `_swapAndFreeze` is called (line 178), it internally calls `_swapTicketSlot` which sets `ticketsFullyProcessed = false` (Storage line 734). This is correct -- the new read slot hasn't been drained yet.
**How to avoid:** This is the desired behavior. The next `advanceGame` call enters the daily drain path and processes the new read slot before allowing further RNG/jackpot progress.

### Pitfall 4: ticketCursor state after swap
**What goes wrong:** `_swapTicketSlot` flips `ticketWriteSlot` but does NOT reset `ticketCursor` or `ticketLevel`. If the cursor was mid-way through the old read slot, it would carry over.
**How to avoid:** Already handled by JackpotModule's `processTicketBatch` (line 1924): when `ticketLevel != lvl`, the cursor resets to 0. Since the new read slot is a different conceptual level context, the module handles the reset internally. Verified by reading JackpotModule lines 1920-1935.

### Pitfall 5: Daily-path ticket processing at line 216 becomes partially redundant
**What goes wrong:** After adding the pre-RNG drain gate, the ticket processing at lines 216-222 (inside the `do{}while(false)`) may seem redundant. However, it serves a different purpose: processing tickets that were swapped in by `_swapAndFreeze` on a PREVIOUS call and are now being drained.
**How to avoid:** Keep both: (a) the pre-`do{}` drain handles leftover tickets from previous swaps, and (b) the in-`do{}` ticket processing at line 216 handles the normal ticket batch flow. Add `ticketsFullyProcessed = true` after line 222 (when `_runProcessTicketBatch` returns finished) to satisfy ADV-03.

## Code Examples

### Pattern: Pre-RNG drain gate (new code for daily path)

```solidity
// Source: New code based on mid-day path pattern (lines 147-161)
// Insert AFTER the mid-day guard (line 171), BEFORE the do { } while(false) block (line 174)

// --- Daily drain gate: ensure read slot is fully processed before RNG ---
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
```

### Pattern: Post-ticket flag set inside do{} block (ADV-03)

```solidity
// Source: Modification of existing lines 216-222
// After _runProcessTicketBatch returns finished, set flag before jackpot logic

(bool ticketWorked, bool ticketsFinished) = _runProcessTicketBatch(purchaseLevel);
if (ticketWorked || !ticketsFinished) {
    stage = STAGE_TICKETS_WORKING;
    break;
}
ticketsFullyProcessed = true;  // ADV-03: guaranteed true before purchase/jackpot branches
```

### Multi-call sequence trace

```
Call 1 (mid-day): Queue has 500 tickets in write slot
  -> mid-day swap triggers (_swapTicketSlot), ticketsFullyProcessed = false
  -> returns

Call 2 (mid-day): Read slot has 500 tickets
  -> drain read slot via _runProcessTicketBatch (partial)
  -> returns STAGE_TICKETS_WORKING

Call 3..N (mid-day): Continue draining
  -> eventually: ticketsFullyProcessed = true

Call N+1 (new day): ticketsFullyProcessed is true
  -> skip daily drain gate
  -> enter do { } while(false)
  -> rngGate() requests RNG
  -> _swapAndFreeze() swaps buffers, ticketsFullyProcessed = false
  -> break STAGE_RNG_REQUESTED

Call N+2 (same day): ticketsFullyProcessed is false
  -> daily drain gate: process new read slot (old write slot entries)
  -> returns STAGE_TICKETS_WORKING

Call N+3..M: Continue draining
  -> eventually: ticketsFullyProcessed = true

Call M+1 (same day): ticketsFullyProcessed is true, RNG fulfilled
  -> skip daily drain gate
  -> enter do { } while(false)
  -> rngGate() returns RNG word
  -> _runProcessTicketBatch (line 216) on read slot -- may be empty
  -> proceed to purchase/jackpot logic
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single ticket queue with rngLockedFlag blocking purchases | Double-buffer queue with freeze/unfreeze | Phase 1-3 (current milestone) | Purchases never blocked |
| Tickets processed only after RNG, no explicit gate | Pre-RNG drain gate + `ticketsFullyProcessed` flag | Phase 4 (this phase) | RNG gated on ticket completion |
| Implicit read-slot empty guard via `_swapTicketSlot` revert | Explicit `ticketsFullyProcessed` boolean gate | Phase 4 (this phase) | Clear intent, testable |

## Open Questions

1. **Is line 216 ticket processing redundant after the drain gate?**
   - What we know: The pre-`do{}` drain ensures the read slot is empty before RNG. After `_swapAndFreeze` swaps, the read slot has fresh entries. But `_swapAndFreeze` sets `ticketsFullyProcessed = false`, so the NEXT call's drain gate handles those.
   - What's unclear: Whether line 216 ever fires with a non-empty read slot in the new flow. The pre-`do{}` drain ensures `ticketsFullyProcessed = true` before the `do{}` block. Inside the block, `rngGate` may call `_swapAndFreeze` which resets the flag -- but this happens with a `break` (line 180), so line 216 is never reached on the same call.
   - Recommendation: Line 216 may only fire when RNG is fulfilled (rngGate returns a word, not 1). At that point, `ticketsFullyProcessed` was set to `true` by the drain gate. The read slot should be empty. `_runProcessTicketBatch` returns `(false, true)` and falls through. **Line 216 is effectively a no-op in the new flow but is harmless.** Keep it as defensive code, add `ticketsFullyProcessed = true` after it for ADV-03.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge test) |
| Config file | foundry.toml |
| Quick run command | `forge test --match-contract AdvanceGameRewrite -vvv` |
| Full suite command | `forge test -vvv` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ADV-01 | Mid-day processes read slot, triggers swap without freeze | unit | `forge test --match-test "test_midDay.*noFreeze" -vvv` | No (Wave 0) |
| ADV-02 | Daily RNG blocks when ticketsFullyProcessed == false | unit | `forge test --match-test "test_dailyRng.*gated" -vvv` | No (Wave 0) |
| ADV-03 | ticketsFullyProcessed set before jackpot logic fires | unit | `forge test --match-test "test_ticketsProcessed.*beforeJackpot" -vvv` | No (Wave 0) |
| SC-4 | Every do{} break path has correct freeze-state | unit | `forge test --match-test "test_breakPath.*freeze" -vvv` | No (Wave 0) |

### Sampling Rate
- **Per task commit:** `forge test --match-contract AdvanceGameRewrite -vvv`
- **Per wave merge:** `forge test -vvv`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/fuzz/AdvanceGameRewrite.t.sol` -- AdvanceHarness + all ADV-01/02/03 tests
- [ ] Harness needs: exposed drain gate, freeze state inspection, ticket queue population, `ticketsFullyProcessed` getter/setter

### Test Harness Design

Prior phases used isolated harnesses inheriting `DegenerusGameStorage` (StorageHarness, QueueHarness, FreezeHarness). Phase 4 tests need a new `AdvanceHarness` that:
1. Inherits `DegenerusGameStorage`
2. Exposes `ticketsFullyProcessed` getter/setter
3. Exposes `prizePoolFrozen` getter
4. Exposes `_swapAndFreeze`, `_unfreezePool`, `_swapTicketSlot`
5. Simulates the drain-gate logic (the new pre-`do{}` code)
6. Can populate ticket queues in both read and write slots

Testing the full `advanceGame` function end-to-end is impractical due to delegatecall dependencies on external modules (JackpotModule, EndgameModule, MintModule). Instead, test the building blocks:
- Drain gate logic (new code)
- `ticketsFullyProcessed` flag lifecycle across swap/drain/set sequences
- Freeze state at each conceptual break point (simulate with harness)

## Sources

### Primary (HIGH confidence)
- `contracts/modules/DegenerusGameAdvanceModule.sol` -- full advanceGame function (lines 121-324), rngGate (lines 671-717), _unlockRng (line 1210), _requestRng (line 1061), all break paths analyzed
- `contracts/storage/DegenerusGameStorage.sol` -- `_swapTicketSlot` (line 730), `_swapAndFreeze` (line 740), `_unfreezePool` (line 750), `ticketsFullyProcessed` (line 326)
- `contracts/modules/DegenerusGameJackpotModule.sol` -- `processTicketBatch` (lines 1905-1979), ticketCursor reset behavior (lines 1924-1926)
- `audit/state-changing-function-audits.md` -- advanceGame audit (lines 2094-2194)

### Secondary (MEDIUM confidence)
- `test/fuzz/QueueDoubleBuffer.t.sol` -- QueueHarness pattern for unit testing internal functions
- `test/fuzz/PrizePoolFreeze.t.sol` -- FreezeHarness pattern for freeze lifecycle tests
- `.planning/STATE.md` -- Prior phase decisions, ticketCursor concern (resolved in this research)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Solidity 0.8.34, Foundry, same as all prior phases
- Architecture: HIGH - All code is in-repo and fully traced; break-path analysis is complete
- Pitfalls: HIGH - purchaseLevel calculation and cursor behavior traced through code; edge cases documented
- Test approach: MEDIUM - Harness approach proven in prior phases; full advanceGame integration testing impractical

**Research date:** 2026-03-11
**Valid until:** 2026-04-11 (stable codebase, no external dependency changes)
