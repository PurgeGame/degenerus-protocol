# Phase 3: Prize Pool Freeze - Research

**Researched:** 2026-03-11
**Domain:** Solidity prize pool freeze/unfreeze branching, pending accumulator pattern, advanceGame exit-point analysis
**Confidence:** HIGH

## Summary

Phase 3 wires the prize pool freeze mechanism (built in Phase 1: `_swapAndFreeze()`, `_unfreezePool()`, `prizePoolFrozen` flag, `prizePoolPendingPacked` accumulator) into the game's purchase and processing paths. The infrastructure already exists and is tested at the storage level. This phase has three concerns: (1) insert `_swapAndFreeze()` at the single daily RNG request site in `advanceGame`, (2) add freeze branching to all purchase-path pool additions so ETH goes to pending accumulators when frozen, and (3) insert `_unfreezePool()` at the correct `advanceGame` exit points.

All purchase-path pool additions currently use `_legacySetNextPrizePool()` / `_legacySetFuturePrizePool()` shims. The freeze branch replaces each pair with a conditional: when `prizePoolFrozen`, route to `_getPendingPools()` / `_setPendingPools()`; otherwise route to `_getPrizePools()` / `_setPrizePools()`. This also completes the legacy shim migration for purchase paths. The remaining legacy calls in game-logic paths (JackpotModule, AdvanceModule, EndgameModule, DecimatorModule) do NOT need freeze branching -- they operate on live pools during processing.

The unfreeze points require careful analysis of `advanceGame`'s `do { } while(false)` control flow. There are exactly 3 exit points where freeze must clear: (a) purchase-phase daily processing complete (`_unlockRng` when `!jackpotPhaseFlag`), (b) jackpot phase end (after `_endPhase()`), and (c) phase transition completion (before `jackpotPhaseFlag = false`). Between jackpot days, freeze persists -- `_unlockRng` is called but `_unfreezePool()` is NOT.

**Primary recommendation:** Implement as two plans: Plan 1 handles `_swapAndFreeze` insertion at the RNG request site plus all purchase-path freeze branching with unit tests; Plan 2 handles `_unfreezePool` insertion at exit points plus freeze persistence tests across 5 jackpot days.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| FREEZE-01 | `_swapAndFreeze()` called at daily RNG request only | Single insertion point: AdvanceModule line 177-179 (`rngWord == 1` branch). Currently just sets `stage = STAGE_RNG_REQUESTED; break`. Must call `_swapAndFreeze(purchaseLevel)` before the break. Mid-day path (line 165) already correctly uses `_swapTicketSlot()` only -- no change needed. |
| FREEZE-02 | All purchase-path pool additions branch on `prizePoolFrozen` | 7 purchase functions across 4 files with pool-addition sites: DegenerusGame.sol `recordMint` (lines 408-414), DegenerusGame.sol `receive()` (line 2818), MintModule `_purchaseFor` lootbox split (lines 752-756), WhaleModule `_purchaseWhaleBundle` (lines 295-296), WhaleModule `_purchaseLazyPass` (lines 417-425), WhaleModule `_purchaseDeityPass` (lines 536-537), DegeneretteModule `placeBet` (line 588). Each replaces `_legacySet*` calls with freeze-aware branching. |
| FREEZE-03 | `_unfreezePool()` at correct exit points only; no direct `prizePoolFrozen = false` outside `_unfreezePool` | 3 insertion points in AdvanceModule: (a) after `_unlockRng(day)` at line 232 (purchase daily, `!lastPurchaseDay` path), (b) after `_endPhase()` at line 304 (jackpot phase end), (c) after `_unlockRng(day)` at line 189 (phase transition done). Between-jackpot-day `_unlockRng` at line 308 must NOT have `_unfreezePool()`. Grep verification: `prizePoolFrozen = false` must appear only inside `_unfreezePool()` in DegenerusGameStorage.sol. |
| FREEZE-04 | Freeze persists across all 5 jackpot days; accumulators not reset between draws | `_swapAndFreeze` has `if (!prizePoolFrozen)` guard -- during jackpot phase, subsequent daily swaps skip the accumulator reset. Between-day `_unlockRng` (line 308) has no `_unfreezePool()`. Test must simulate 5 sequential daily cycles with purchases between each, verifying pending accumulators grow monotonically and live pools remain constant. |
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

# Run phase 3 tests
forge test --match-path "test/fuzz/PrizePoolFreeze.t.sol" -vvv

# Run all tests (including Phase 1 and 2)
forge test

# Grep verification for FREEZE-01 (single call site)
grep -rn "_swapAndFreeze" contracts/modules/
# Expected: exactly 1 result in AdvanceModule

# Grep verification for FREEZE-03 (no direct freeze clear)
grep -rn "prizePoolFrozen = false" contracts/
# Expected: only in DegenerusGameStorage.sol _unfreezePool()

# Grep verification for legacy shim elimination at purchase sites
grep -n "_legacySet" contracts/DegenerusGame.sol contracts/modules/DegenerusGameMintModule.sol contracts/modules/DegenerusGameWhaleModule.sol contracts/modules/DegenerusGameDegeneretteModule.sol
# Expected: 0 results after Phase 3 (purchase-path sites migrated)
```

## Architecture Patterns

### Purchase-Path Freeze Branching Pattern

Every purchase-path pool addition follows this pattern, replacing the legacy shim pair:

```solidity
// BEFORE (legacy shims, no freeze awareness):
_legacySetFuturePrizePool(_legacyGetFuturePrizePool() + futureShare);
_legacySetNextPrizePool(_legacyGetNextPrizePool() + nextShare);

// AFTER (freeze-aware, packed helpers, single SLOAD+SSTORE per path):
if (prizePoolFrozen) {
    (uint128 pNext, uint128 pFuture) = _getPendingPools();
    _setPendingPools(pNext + uint128(nextShare), pFuture + uint128(futureShare));
} else {
    (uint128 next, uint128 future) = _getPrizePools();
    _setPrizePools(next + uint128(nextShare), future + uint128(futureShare));
}
```

Source: `audit/PLAN-ALWAYS-OPEN-PURCHASES.md` Section 3.

**Key invariant:** Both branches are 1 SLOAD + 1 SSTORE. This is a gas improvement over the legacy shim pattern (which was 2 SLOADs + 2 SSTOREs per pair).

### Variant: Future-Only Additions

Some purchase paths only add to `futurePrizePool` (receive fallback, degenerette bets). Pattern simplifies:

```solidity
// BEFORE:
_legacySetFuturePrizePool(_legacyGetFuturePrizePool() + amount);

// AFTER:
if (prizePoolFrozen) {
    (uint128 pNext, uint128 pFuture) = _getPendingPools();
    _setPendingPools(pNext, pFuture + uint128(amount));
} else {
    (uint128 next, uint128 future) = _getPrizePools();
    _setPrizePools(next, future + uint128(amount));
}
```

### AdvanceGame Exit-Point Mapping

The `advanceGame` daily path uses a `do { } while(false)` pattern with `break` exits. Each exit corresponds to a game state transition. Complete freeze/unfreeze mapping:

| Line | Exit Stage | Freeze Action | Rationale |
|------|-----------|---------------|-----------|
| 177-179 | STAGE_RNG_REQUESTED | `_swapAndFreeze()` | Daily RNG request -- freeze starts here |
| 185-186 | STAGE_TRANSITION_WORKING | none | Mid-transition, freeze already active |
| 188-193 | STAGE_TRANSITION_DONE | `_unfreezePool()` | Transition complete, new purchase phase |
| 208-209 | STAGE_FUTURE_TICKETS_WORKING | none | Still processing, freeze active |
| 217-220 | STAGE_TICKETS_WORKING | none | Still processing, freeze active |
| 232-234 | STAGE_PURCHASE_DAILY | `_unfreezePool()` | Purchase-phase daily done, no jackpot |
| 277-278 | STAGE_ENTERED_JACKPOT | none | Entering jackpot -- freeze persists |
| 293-294 | STAGE_JACKPOT_ETH_RESUME | none | Mid-payout, freeze active |
| 304-306 | STAGE_JACKPOT_PHASE_ENDED | `_unfreezePool()` | All 5 draws done |
| 308-310 | STAGE_JACKPOT_COIN_TICKETS | none | Between jackpot days -- freeze persists |
| 314-315 | STAGE_JACKPOT_DAILY_STARTED | none | Mid-payout, freeze active |

### Anti-Patterns to Avoid

- **Unfreezing between jackpot days:** The `_unlockRng(day)` call at line 308 unlocks RNG for the next day but must NOT unfreeze the pool. All 5 jackpot payouts must use pre-freeze pool values.
- **Resetting pending accumulators between jackpot days:** `_swapAndFreeze` has `if (!prizePoolFrozen)` guard precisely for this -- subsequent daily swaps during jackpot phase skip the accumulator reset.
- **Direct `prizePoolFrozen = false`:** All freeze clearing must go through `_unfreezePool()` which atomically applies pending to live pools. Direct assignment would lose accumulated revenue.
- **Freeze branching in game-logic paths:** JackpotModule (`consolidatePrizePools`, `payDailyJackpot`), AdvanceModule (`_applyTimeBasedFutureTake`, `_drawDownFuturePrizePool`), EndgameModule, DecimatorModule all operate on live pools during processing. They do NOT need freeze branching.

## Purchase Path Catalog (All 7 Functions)

### 1. DegenerusGame.sol -- `recordMint` (lines 405-414)
- **Shares:** `futureShare`, `nextShare` (derived from `prizeContribution`)
- **Current:** `_legacySetFuturePrizePool(... + futureShare)` + `_legacySetNextPrizePool(... + nextShare)`
- **Pattern:** Both next and future, guarded by `if (futureShare != 0)` / `if (nextShare != 0)`
- **Note:** Consolidate both additions into single freeze branch (1 SLOAD+SSTORE vs current 2+2)

### 2. DegenerusGame.sol -- `receive()` (line 2818)
- **Shares:** `msg.value` goes entirely to future pool
- **Current:** `_legacySetFuturePrizePool(_legacyGetFuturePrizePool() + msg.value)`
- **Pattern:** Future-only

### 3. DegenerusGameMintModule.sol -- lootbox split (lines 752-756)
- **Shares:** `futureDelta` (futureShare + rewardShare), `nextShare`
- **Current:** Two separate legacy shim calls
- **Pattern:** Both next and future, guarded by `if (futureDelta != 0)` / `if (nextShare != 0)`

### 4. DegenerusGameWhaleModule.sol -- `_purchaseWhaleBundle` (lines 295-296)
- **Shares:** `totalPrice - nextShare` (to future), `nextShare` (to next)
- **Current:** Two separate legacy shim calls, no zero guards
- **Pattern:** Both next and future, always nonzero

### 5. DegenerusGameWhaleModule.sol -- `_purchaseLazyPass` (lines 417-425)
- **Shares:** `futureShare`, `nextShare` (totalPrice - futureShare)
- **Current:** Two separate legacy shim calls with null guards
- **Pattern:** Both next and future, guarded

### 6. DegenerusGameWhaleModule.sol -- `_purchaseDeityPass` (lines 536-537)
- **Shares:** `nextShare`, `totalPrice - nextShare` (to future)
- **Current:** Two separate legacy shim calls, no zero guards
- **Pattern:** Both next and future, always nonzero

### 7. DegenerusGameDegeneretteModule.sol -- `placeBet` (line 588)
- **Shares:** `totalBet` goes entirely to future pool
- **Current:** `_legacySetFuturePrizePool(_legacyGetFuturePrizePool() + totalBet)`
- **Pattern:** Future-only, inside `if (currency == CURRENCY_ETH)` block

### NOT a purchase path: DegeneretteModule `_distributePayout` (lines 701-717)
- This SUBTRACTS from `futurePrizePool` (pool redistribution for payouts). It is game logic, not purchase revenue. No freeze branching needed.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Freeze flag management | Manual `prizePoolFrozen = true/false` at each site | `_swapAndFreeze()` and `_unfreezePool()` from Phase 1 | Single control points; `_unfreezePool` atomically applies pending; `_swapAndFreeze` conditionally resets accumulators |
| Prize pool reads/writes | Direct `prizePoolsPacked` bit manipulation | `_getPrizePools()` / `_setPrizePools()` / `_getPendingPools()` / `_setPendingPools()` | Encapsulated packing, type-safe uint128 returns |
| Legacy shim replacement | New shims or partial migration | Direct packed helper calls in freeze branch | Shims were explicitly marked for removal and add unnecessary SLOAD overhead |

## Common Pitfalls

### Pitfall 1: Missing an Unfreeze Point
**What goes wrong:** If `_unfreezePool()` is omitted from an exit path, `prizePoolFrozen` stays true permanently. All subsequent purchases accumulate in pending but never apply to live pools.
**Why it happens:** The `do { } while(false)` pattern in `advanceGame` has 11 distinct `break` exits. Only 3 need `_unfreezePool()`.
**How to avoid:** Use the exit-point mapping table above. After implementation, grep for `_unlockRng` and verify each call site's freeze expectation.
**Warning signs:** `prizePoolFrozen` returning true when no RNG request is pending.

### Pitfall 2: Unfreezing Between Jackpot Days
**What goes wrong:** If `_unfreezePool()` is added after the between-day `_unlockRng(day)` at line 308, pending accumulators apply too early. Jackpot days 2-5 see inflated pool values.
**Why it happens:** Natural instinct to pair every `_unlockRng` with `_unfreezePool`. The between-day call at line 308 looks identical to the purchase-daily call at line 232.
**How to avoid:** Only unfreeze at line 232 (purchase daily), line 304 (phase end), and line 189 (transition done). Never at line 308.
**Warning signs:** Pool values changing between jackpot draws.

### Pitfall 3: Accumulator Reset During Jackpot Phase
**What goes wrong:** If `_swapAndFreeze` resets `prizePoolPendingPacked = 0` on every daily swap during jackpot phase, purchases from days 1-4 are silently lost.
**Why it happens:** Without the `if (!prizePoolFrozen)` guard, each jackpot-day swap zeros the accumulators.
**How to avoid:** The guard is already in `_swapAndFreeze()` from Phase 1. Verify in tests that pending grows monotonically across 5 jackpot days.

### Pitfall 4: Degenerette Payout Path Confusion
**What goes wrong:** Adding freeze branching to `_distributePayout` (DegeneretteModule line 701) which SUBTRACTS from the pool.
**Why it happens:** Both `placeBet` (line 588, adds) and `_distributePayout` (line 701, subtracts) touch `futurePrizePool`. They look similar.
**How to avoid:** Only bet placement at line 588 is a purchase-path addition. `_distributePayout` is game logic operating on live pools -- no freeze branch.

### Pitfall 5: Legacy Shim Calls Remaining at Purchase Sites
**What goes wrong:** If a purchase-path site still uses `_legacySetNextPrizePool` instead of the freeze branch, purchases bypass the freeze entirely.
**Why it happens:** Missing a site during migration.
**How to avoid:** After implementation, grep for `_legacySet` calls in the 4 purchase-path files. Should be zero results.

## Code Examples

### FREEZE-01: Add _swapAndFreeze to Daily RNG Request

```solidity
// In advanceGame (AdvanceModule.sol), inside daily path do-while:
uint256 rngWord = rngGate(ts, day, purchaseLevel, lastPurchase);
if (rngWord == 1) {
    _swapAndFreeze(purchaseLevel);   // <<< ADD THIS LINE
    stage = STAGE_RNG_REQUESTED;
    break;
}
```

### FREEZE-02: Purchase Path Freeze Branch (recordMint)

```solidity
// DegenerusGame.sol recordMint, replacing lines 406-414:
if (prizeContribution != 0) {
    uint256 futureShare = (prizeContribution * PURCHASE_TO_FUTURE_BPS) / 10_000;
    uint256 nextShare = prizeContribution - futureShare;
    if (prizePoolFrozen) {
        (uint128 pNext, uint128 pFuture) = _getPendingPools();
        if (nextShare != 0) pNext += uint128(nextShare);
        if (futureShare != 0) pFuture += uint128(futureShare);
        _setPendingPools(pNext, pFuture);
    } else {
        (uint128 next, uint128 future) = _getPrizePools();
        if (nextShare != 0) next += uint128(nextShare);
        if (futureShare != 0) future += uint128(futureShare);
        _setPrizePools(next, future);
    }
}
```

### FREEZE-02: Future-Only Freeze Branch (receive fallback)

```solidity
// DegenerusGame.sol receive():
receive() external payable {
    if (gameOver) revert E();
    if (prizePoolFrozen) {
        (uint128 pNext, uint128 pFuture) = _getPendingPools();
        _setPendingPools(pNext, pFuture + uint128(msg.value));
    } else {
        (uint128 next, uint128 future) = _getPrizePools();
        _setPrizePools(next, future + uint128(msg.value));
    }
}
```

### FREEZE-03: Unfreeze at 3 Exit Points

```solidity
// Exit 1: Purchase daily (line 232 area)
_unlockRng(day);
_unfreezePool();                  // <<< ADD
stage = STAGE_PURCHASE_DAILY;
break;

// Exit 2: Jackpot phase end (line 304 area)
_endPhase();
_unfreezePool();                  // <<< ADD
stage = STAGE_JACKPOT_PHASE_ENDED;
break;

// Exit 3: Phase transition complete (line 189 area)
phaseTransitionActive = false;
_unlockRng(day);
_unfreezePool();                  // <<< ADD
purchaseStartDay = day;
jackpotPhaseFlag = false;
stage = STAGE_TRANSITION_DONE;
break;
```

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge-std Test.sol) |
| Config file | `foundry.toml` |
| Quick run command | `forge test --match-path "test/fuzz/PrizePoolFreeze.t.sol" -vvv` |
| Full suite command | `forge test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FREEZE-01 | `_swapAndFreeze()` at exactly one site (daily RNG) | grep | `grep -rn '_swapAndFreeze' contracts/modules/` (expect 1) | N/A -- grep |
| FREEZE-02 | All 7 purchase-path sites branch on `prizePoolFrozen` | unit | `forge test --match-path "test/fuzz/PrizePoolFreeze.t.sol" --match-test "Frozen\|Unfrozen" -vvv` | No -- Wave 0 |
| FREEZE-03 | `_unfreezePool()` is sole path to clear freeze | grep + unit | `grep -n 'prizePoolFrozen = false' contracts/` (expect 1) | N/A -- grep |
| FREEZE-04 | Freeze persists across 5 jackpot days | unit | `forge test --match-path "test/fuzz/PrizePoolFreeze.t.sol" --match-test "Persist" -vvv` | No -- Wave 0 |

### Testing Strategy: Harness-Based

Following Phase 2's successful pattern, use a `FreezeHarness` contract that inherits `DegenerusGameStorage` and exposes internal functions. The existing `StorageHarness` in `test/fuzz/StorageFoundation.t.sol` already exposes `_swapAndFreeze`, `_unfreezePool`, `prizePoolFrozen`, and all pending/prize pool helpers. Extend or reuse this.

For FREEZE-02, the freeze branching pattern is identical at all 7 sites. A harness test can verify the pattern works correctly (frozen: pending changes, live unchanged; unfrozen: live changes, pending unchanged). The actual contract modifications are mechanical -- each site follows the same template.

For FREEZE-04, simulate 5 daily cycles by:
1. Set `prizePoolFrozen = true` via `_swapAndFreeze`
2. Add to pending pools (simulating purchases) between each "day"
3. Call `_swapAndFreeze` again (should NOT reset accumulators due to `if (!prizePoolFrozen)` guard)
4. Verify pending accumulators grow monotonically
5. Call `_unfreezePool` at end -- verify live pools increase by total accumulated pending

### Sampling Rate
- **Per task commit:** `forge test --match-path "test/fuzz/PrizePoolFreeze.t.sol" -vvv`
- **Per wave merge:** `forge test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/fuzz/PrizePoolFreeze.t.sol` -- FreezeHarness + freeze lifecycle tests for FREEZE-02 and FREEZE-04

## Open Questions

1. **"9 purchase paths" vs 7 purchase functions**
   - What we know: The plan Section 3 table lists 7 pool-addition locations across 4 contracts. The success criteria says "all 9 purchase paths."
   - What's unclear: Whether "9" counts distinct entry points (including e.g. lootbox open paths) or pool-addition sites.
   - Recommendation: Implement freeze branching at all 7 pool-addition functions identified by grep. This covers every `_legacySet*` call in purchase-path files. After implementation, verify with grep that no legacy shim calls remain in the 4 purchase-path contract files.

2. **Legacy shim cleanup scope**
   - What we know: Phase 3 replaces 7 purchase-path legacy shim call sites. Approximately 40+ game-logic legacy shim calls remain in JackpotModule, AdvanceModule, EndgameModule, DecimatorModule, GameOverModule.
   - Recommendation: Only migrate purchase-path shims in Phase 3. Game-logic shim migration is mechanical and can be done in Phase 4 (advanceGame rewrite) or as separate cleanup.

## Sources

### Primary (HIGH confidence)
- `contracts/storage/DegenerusGameStorage.sol` lines 740-757 -- `_swapAndFreeze` and `_unfreezePool` implementations verified present
- `contracts/modules/DegenerusGameAdvanceModule.sol` lines 121-320 -- all 11 exit points mapped from source
- `contracts/DegenerusGame.sol`, `contracts/modules/DegenerusGameMintModule.sol`, `contracts/modules/DegenerusGameWhaleModule.sol`, `contracts/modules/DegenerusGameDegeneretteModule.sol` -- all purchase-path pool additions verified by grep
- `audit/PLAN-ALWAYS-OPEN-PURCHASES.md` Sections 3, 4, 7, 8 -- freeze design specification
- `test/fuzz/StorageFoundation.t.sol` -- existing harness with freeze/unfreeze exposed functions

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- same Foundry/Solidity stack, no new dependencies
- Architecture: HIGH -- all infrastructure functions already implemented in Phase 1; freeze pattern well-defined in plan; all exit points mapped from source code
- Pitfalls: HIGH -- all 11 exit paths in advanceGame mapped; jackpot persistence logic verified in `_swapAndFreeze` source
- Purchase path inventory: HIGH -- exhaustive grep of `_legacySet*` calls cross-referenced with plan Section 3

**Research date:** 2026-03-11
**Valid until:** 2026-04-11 (stable -- no external dependencies, all code in-repo)
