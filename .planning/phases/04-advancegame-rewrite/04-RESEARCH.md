# Phase 4: advanceGame Rewrite - Research

**Researched:** 2026-03-11
**Domain:** Solidity state machine rewrite (DegenerusGameAdvanceModule)
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

The daily path currently calls `rngGate` first (line 176), THEN processes tickets (line 216). This must be inverted:

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

Every break path must have a documented freeze expectation:

| Break Path | Stage | Freeze Active? | Unfreeze Call? | Rationale |
|------------|-------|---------------|----------------|-----------|
| RNG requested | STAGE_RNG_REQUESTED | YES (just set) | No | Freeze persists until RNG resolves |
| Transition working | STAGE_TRANSITION_WORKING | YES (from RNG request) | No | Transition still in progress |
| Transition done | STAGE_TRANSITION_DONE | NO (just cleared) | Yes (line 191) | Phase complete, unfreeze |
| Future tickets working (final day) | STAGE_FUTURE_TICKETS_WORKING | YES (from RNG request) | No | Still processing |
| Tickets working | STAGE_TICKETS_WORKING | YES (from RNG request) | No | Still processing |
| Purchase daily | STAGE_PURCHASE_DAILY | NO (just cleared) | Yes (line 235) | Daily complete, unfreeze |
| Future tickets (pre-jackpot) | STAGE_FUTURE_TICKETS_WORKING | YES (from RNG request) | No | Still processing |
| Entered jackpot | STAGE_ENTERED_JACKPOT | YES (intentional) | No | Day-1 jackpot runs same day |
| Jackpot ETH resume | STAGE_JACKPOT_ETH_RESUME | YES (jackpot phase) | No | Multi-day jackpot, freeze persists |
| Jackpot phase ended | STAGE_JACKPOT_PHASE_ENDED | NO (just cleared) | Yes (line 308) | All 5 jackpot days complete |
| Jackpot coin tickets (mid) | STAGE_JACKPOT_COIN_TICKETS | YES (jackpot phase) | No | FREEZE-04: freeze persists across all 5 days |
| Jackpot daily started | STAGE_JACKPOT_DAILY_STARTED | YES (jackpot phase) | No | Jackpot day started, processing continues |

**Key invariant:** `_unfreezePool()` is called at exactly 3 exit points:
1. `STAGE_TRANSITION_DONE` (line 191) -- phase transition complete
2. `STAGE_PURCHASE_DAILY` (line 235) -- daily purchase phase complete
3. `STAGE_JACKPOT_PHASE_ENDED` (line 308) -- all 5 jackpot days complete

All other break paths are either:
- Under active freeze (jackpot multi-day, in-progress processing)
- Pre-freeze (mid-day path, game-over path)

### Anti-Patterns to Avoid

- **Moving `_unfreezePool()` to wrong break paths:** The STAGE_ENTERED_JACKPOT break intentionally keeps freeze active. Adding unfreeze there would break FREEZE-04 (multi-day freeze persistence).
- **Double-processing tickets:** The mid-day path and the daily path's new pre-RNG drain step both call `_runProcessTicketBatch`. They must not interfere -- the mid-day path uses `day == dailyIdx` guard, daily path uses `day != dailyIdx`.
- **Forgetting `ticketsFullyProcessed = true` after daily drain:** Without this, subsequent calls re-enter the drain loop even when the read slot is empty, wasting gas.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Freeze-state tracking | Manual boolean tracking per path | Existing `_swapAndFreeze()` / `_unfreezePool()` from Phase 3 | Already atomic with slot swap; adding manual tracking would create consistency hazards |
| Ticket cursor management | Custom cursor logic | Existing `_runProcessTicketBatch()` via JackpotModule delegatecall | Cursor state (`ticketCursor`, `ticketLevel`) managed by JackpotModule; reimplementing risks cursor drift |

## Common Pitfalls

### Pitfall 1: ticketCursor state after daily drain
**What goes wrong:** The pre-RNG drain calls `_runProcessTicketBatch(purchaseLevel)`, which advances `ticketCursor` and `ticketLevel`. If the read slot empties but `ticketsFullyProcessed` is not set, subsequent calls re-enter the drain and `_runProcessTicketBatch` returns `(false, true)` with no work done -- but this burns gas unnecessarily.
**How to avoid:** Set `ticketsFullyProcessed = true` immediately when `_runProcessTicketBatch` returns `finished == true` in the daily drain path.

### Pitfall 2: purchaseLevel calculation under lastPurchaseDay + rngLockedFlag
**What goes wrong:** `purchaseLevel` is computed as `(lastPurchase && rngLockedFlag) ? lvl : lvl + 1` (line 129). When the drain step runs BEFORE `rngGate` (new structure), `rngLockedFlag` is false, so `purchaseLevel = lvl + 1`. After `rngGate` returns 1 and `_requestRng` sets `rngLockedFlag = true`, a subsequent call computes `purchaseLevel = lvl`. The drain must use the same `purchaseLevel` that `_swapAndFreeze` and `_runProcessTicketBatch` use.
**How to avoid:** The drain step runs with `purchaseLevel = lvl + 1` (before RNG lock). The `_swapAndFreeze(purchaseLevel)` call inside the `do { }` block also uses `purchaseLevel` which was captured at function entry. Since `rngLockedFlag` changes INSIDE `_finalizeRngRequest`, and `purchaseLevel` is captured BEFORE the `do { }` block, the value is consistent within a single call. This is already correct in the existing code. No change needed.

### Pitfall 3: Empty read slot on first daily call
**What goes wrong:** On the very first daily call (after mid-day path was the last to run), the read slot might be empty (all processed mid-day). `_runProcessTicketBatch` returns `(false, true)` immediately. Must still set `ticketsFullyProcessed = true` and proceed to RNG.
**How to avoid:** The drain guard should handle this gracefully: if `!ticketsFullyProcessed` and `_runProcessTicketBatch` returns `finished == true` with no work, set the flag and fall through to the `do { }` block.

### Pitfall 4: Mid-day drain vs daily drain interference
**What goes wrong:** Mid-day path (day == dailyIdx) drains the read slot and sets `ticketsFullyProcessed = true`. Then a new day arrives (day > dailyIdx), and the daily path checks `ticketsFullyProcessed` -- which is still true from yesterday. But `_swapAndFreeze` (called when RNG is requested) calls `_swapTicketSlot`, which resets `ticketsFullyProcessed = false`.
**How to avoid:** This is already handled correctly. The `_swapTicketSlot` function (Storage line 734) sets `ticketsFullyProcessed = false` on every swap. So after `_swapAndFreeze` at the RNG request, the flag is false. The next advanceGame call enters the daily drain path and processes the new read slot. The only edge case: the first daily call BEFORE `_swapAndFreeze` runs. At that point `ticketsFullyProcessed` may be true from yesterday's mid-day processing -- meaning we skip the drain and go straight to `rngGate`, which requests RNG and calls `_swapAndFreeze`. This is correct: there's nothing new in the read slot to drain before the swap.

Actually -- this needs more careful analysis. Let me trace the exact sequence:

1. Mid-day: swap happens, `ticketsFullyProcessed = false`. Mid-day drain processes read slot, sets `ticketsFullyProcessed = true`.
2. New day: daily path. `ticketsFullyProcessed` is `true`. We skip drain, enter `do { }`. `rngGate` requests RNG, calls `_swapAndFreeze` which calls `_swapTicketSlot` which sets `ticketsFullyProcessed = false`. Break.
3. Next daily call: `ticketsFullyProcessed` is `false`. Drain runs. This processes the read slot (which was the old write slot that just got swapped). When done, sets `ticketsFullyProcessed = true`. Falls through to `do { }`.
4. `rngGate` returns the RNG word (VRF fulfilled). Proceed to jackpot/phase logic.

This sequence is correct. The key insight: the daily RNG request atomically swaps+freezes, and the NEXT call drains the freshly-swapped read slot.

## Code Examples

### Pattern: Pre-RNG drain gate (new code for daily path)

```solidity
// Source: New code based on mid-day path pattern (lines 147-161)
// Insert BEFORE the do { } while(false) block, AFTER the mid-day guard

// --- Daily drain gate: ensure read slot is fully processed before RNG ---
if (!ticketsFullyProcessed) {
    (bool ticketWorked, bool ticketsFinished) = _runProcessTicketBatch(purchaseLevel);
    if (ticketWorked || !ticketsFinished) {
        emit Advance(STAGE_TICKETS_WORKING, lvl);
        coin.creditFlip(caller, ADVANCE_BOUNTY);
        return;
    }
    ticketsFullyProcessed = true;
}
```

### Pattern: Post-ticket flag set in daily path (inside do { } block)

The current ticket processing at lines 216-222 should also set the flag:

```solidity
// Source: Modification of existing lines 216-222
// After _runProcessTicketBatch returns finished
(bool ticketWorked, bool ticketsFinished) = _runProcessTicketBatch(purchaseLevel);
if (ticketWorked || !ticketsFinished) {
    stage = STAGE_TICKETS_WORKING;
    break;
}
ticketsFullyProcessed = true;  // ADV-03: set before jackpot/phase logic
```

Wait -- there is a subtlety. The ticket processing at lines 216-222 is INSIDE the `do { }` block, which means it runs AFTER `rngGate`. At this point, `_swapAndFreeze` may have been called (on a prior invocation), and we are now draining the read slot that was created by that swap. Setting `ticketsFullyProcessed = true` here ensures it is set before the purchase/jackpot logic that follows (lines 225+). This is ADV-03.

But the pre-RNG drain gate (the new code above) handles ADV-02: ensuring the read slot from the PREVIOUS swap is fully drained before a NEW RNG request can proceed.

Both are needed:
1. **Pre-`do {}` drain** (ADV-02): Drains any leftover read slot from a previous swap before allowing `rngGate` to fire.
2. **Inside-`do {}` flag set** (ADV-03): After the in-cycle ticket batch completes, set the flag before jackpot logic.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single ticket queue with rngLockedFlag blocking purchases | Double-buffer queue with freeze/unfreeze | Phase 1-3 (current milestone) | Purchases never blocked |
| Tickets processed only after RNG | Pre-RNG drain gate + post-swap processing | Phase 4 (this phase) | RNG gated on ticket completion |

## Open Questions

1. **ticketCursor reset on swap**
   - What we know: `_swapTicketSlot` flips `ticketWriteSlot` and sets `ticketsFullyProcessed = false`. It does NOT reset `ticketCursor` or `ticketLevel`.
   - What's unclear: Does `_runProcessTicketBatch` (via JackpotModule's `processTicketBatch`) handle cursor reset internally when called for a new level/slot?
   - Recommendation: Verify by reading `processTicketBatch` in JackpotModule. The cursor is per-call based on `ticketLevel` comparison -- if `lvl != ticketLevel`, the module resets cursor. This is likely already correct but should be verified during implementation.
   - Flagged in STATE.md as an existing concern.

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
- [ ] Harness needs: exposed drain gate, freeze state inspection, ticket processing simulation

### Test Harness Design

Prior phases used isolated harnesses inheriting `DegenerusGameStorage` (QueueHarness, FreezeHarness). Phase 4 tests need a new `AdvanceHarness` that:
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
- `contracts/modules/DegenerusGameAdvanceModule.sol` -- full advanceGame function (lines 121-324), all break paths analyzed
- `contracts/storage/DegenerusGameStorage.sol` -- `_swapTicketSlot` (line 730), `_swapAndFreeze` (line 740), `_unfreezePool` (line 750), `ticketsFullyProcessed` (line 326)
- `.planning/REQUIREMENTS.md` -- ADV-01, ADV-02, ADV-03 definitions
- `.planning/STATE.md` -- Prior phase decisions, ticketCursor concern

### Secondary (MEDIUM confidence)
- `test/fuzz/QueueDoubleBuffer.t.sol` -- QueueHarness pattern for unit testing internal functions
- `test/fuzz/PrizePoolFreeze.t.sol` -- FreezeHarness pattern for freeze lifecycle tests

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Solidity 0.8.34, Foundry, same as all prior phases
- Architecture: HIGH - All code is in-repo and fully traced; break-path analysis is complete
- Pitfalls: HIGH - purchaseLevel calculation and cursor behavior traced through code; edge cases documented
- Test approach: MEDIUM - Harness approach proven in prior phases; JackpotModule cursor behavior needs verification during implementation

**Research date:** 2026-03-11
**Valid until:** 2026-04-11 (stable codebase, no external dependency changes)
