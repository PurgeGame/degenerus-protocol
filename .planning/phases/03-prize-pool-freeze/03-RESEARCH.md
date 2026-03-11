# Phase 3: Prize Pool Freeze - Research

**Researched:** 2026-03-11
**Domain:** Solidity prize pool freeze/unfreeze pattern, pending accumulator branching across purchase paths
**Confidence:** HIGH

## Summary

Phase 3 wires the prize pool freeze mechanism into the game loop. The storage infrastructure already exists from Phase 1: `prizePoolFrozen` (bool in Slot 1), `prizePoolPendingPacked` (uint256 with uint128+uint128 packing), `_swapAndFreeze()`, `_unfreezePool()`, `_getPendingPools()`/`_setPendingPools()`. Phase 2 added the mid-day swap path (which intentionally does NOT freeze). What remains is: (1) calling `_swapAndFreeze()` from the daily RNG request site in `advanceGame`, (2) adding freeze-aware branching to all 9 purchase-path pool addition sites, (3) calling `_unfreezePool()` at the 3 correct exit points, and (4) ensuring freeze persists across all 5 jackpot draw days.

The 9 purchase-path pool addition sites are spread across 5 contracts: DegenerusGame.sol (recordMint + receive fallback), MintModule (lootbox purchase), WhaleModule (whale bundle, lazy pass, deity pass), and DegeneretteModule (degenerette bets). Each currently uses `_legacyGet/SetNextPrizePool` and `_legacyGet/SetFuturePrizePool` shims; Phase 3 replaces those with freeze-branching that routes to either `_setPrizePools()` (live) or `_setPendingPools()` (pending) based on `prizePoolFrozen`. Game-logic pool operations (jackpot payouts, pool consolidation, future drawdown, decimator, endgame) do NOT get freeze branching -- they operate on live pools.

The 3 unfreeze exit points in `advanceGame` are: (a) after purchase-phase daily processing (`_unlockRng` when `!jackpotPhaseFlag`), (b) after 5th jackpot draw (`_endPhase()`), and (c) after phase transition completes (`_processPhaseTransition` returns true). Between jackpot days, the freeze persists -- `_unlockRng` is called but `_unfreezePool()` is NOT called, so pending accumulators keep growing across all 5 draws.

**Primary recommendation:** Add `_swapAndFreeze()` call at the single daily RNG request site, add freeze branching to all 9 purchase-path sites using a consistent pattern (load pending or live pools, add shares, store), add `_unfreezePool()` at exactly 3 exit points, and test with a harness that exposes freeze state and pool values.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| FREEZE-01 | `_swapAndFreeze()` called at daily RNG request only | Currently `advanceGame` line 177 does `rngGate()` and on `rngWord == 1` just breaks. Must add `_swapAndFreeze(purchaseLevel)` before the break at line 178. This is the ONLY call site. Mid-day path at line 165 correctly uses `_swapTicketSlot()` only. |
| FREEZE-02 | All 9 purchase-path pool additions branch on `prizePoolFrozen` | Complete inventory below in "Purchase Path Inventory" section. Each site replaces legacy shim calls with a `if (prizePoolFrozen) { pending } else { live }` branch. |
| FREEZE-03 | `_unfreezePool()` at correct exit points | 3 sites in advanceGame: (1) line 232 after `_unlockRng(day)` in purchase daily path, (2) line 304 after `_endPhase()` in jackpot phase end, (3) line 189 after `_unlockRng(day)` in phase transition completion. No direct `prizePoolFrozen = false` assignment outside `_unfreezePool()`. |
| FREEZE-04 | Freeze persists across all 5 jackpot days | Line 308 `_unlockRng(day)` in between-jackpot-day path does NOT call `_unfreezePool()`. Only the 5th-draw exit (line 304) unfreezes. Pending accumulators grow across all 5 days because `_swapAndFreeze()` checks `if (!prizePoolFrozen)` before zeroing -- when already frozen (jackpot phase day 2-5), accumulators keep growing. |
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

# Run all tests
forge test

# Grep verification: no direct prizePoolFrozen = false outside _unfreezePool
grep -n 'prizePoolFrozen = false' contracts/storage/DegenerusGameStorage.sol
# Expected: 1 result (inside _unfreezePool only)

# Grep verification: _swapAndFreeze called in exactly 1 location
grep -rn '_swapAndFreeze' contracts/
# Expected: definition in storage + 1 call site in AdvanceModule
```

## Architecture Patterns

### Purchase Path Freeze Branch Pattern

Every purchase-path pool addition follows the same pattern:

```solidity
// BEFORE (legacy shims, no freeze awareness):
_legacySetFuturePrizePool(_legacyGetFuturePrizePool() + futureShare);
_legacySetNextPrizePool(_legacyGetNextPrizePool() + nextShare);

// AFTER (freeze-aware, using packed helpers):
if (prizePoolFrozen) {
    (uint128 pNext, uint128 pFuture) = _getPendingPools();
    _setPendingPools(pNext + uint128(nextShare), pFuture + uint128(futureShare));
} else {
    (uint128 next, uint128 future) = _getPrizePools();
    _setPrizePools(next + uint128(nextShare), future + uint128(futureShare));
}
```

Both branches: 1 SLOAD + 1 SSTORE. The pattern is identical at all 9 sites, differing only in variable names for the share amounts.

### Unfreeze Site Pattern

```solidity
// At each exit point:
_unlockRng(day);
_unfreezePool();   // <<< add after _unlockRng at purchase daily and transition end
                   //     add after _endPhase() at jackpot phase end
```

### Sites That Must NOT Get Freeze Branching

Game-logic pool operations continue using `_legacyGet/Set*` shims (or direct packed helpers). These are NOT purchase revenue -- they are pool transfers, drawdowns, and consolidations:

- `_applyTimeBasedFutureTake` -- moves ETH between next and future
- `_consolidatePrizePools` -- merges next into current
- `_drawDownFuturePrizePool` -- moves future into next/current
- `payDailyJackpot` -- draws from future pool for ETH distribution
- Jackpot lootbox budgets -- internal pool accounting
- `_endPhase` pool transfers
- Decimator lootbox payouts
- Endgame settlement
- GameOver drain

These operate on live pool values which is correct -- jackpot payouts use pre-freeze pool values, not inflated by concurrent purchases.

## Purchase Path Inventory (All 9 Sites)

### Site 1: recordMint -- Ticket Purchase Pool Split
- **File:** `DegenerusGame.sol` lines 406-414
- **Variables:** `futureShare`, `nextShare` (derived from `prizeContribution`)
- **Current code:** `_legacySetFuturePrizePool(... + futureShare)` + `_legacySetNextPrizePool(... + nextShare)`
- **Notes:** Two separate shim calls that each do SLOAD+SSTORE. Freeze branch consolidates to 1 SLOAD + 1 SSTORE.

### Site 2: ETH Receive Fallback
- **File:** `DegenerusGame.sol` line 2818
- **Variables:** `msg.value` goes entirely to future pool
- **Current code:** `_legacySetFuturePrizePool(_legacyGetFuturePrizePool() + msg.value)`
- **Notes:** Future-only addition. Freeze branch: `pFuture + uint128(msg.value)` or `future + uint128(msg.value)`.

### Site 3: Lootbox Purchase Pool Split
- **File:** `DegenerusGameMintModule.sol` lines 752-756
- **Variables:** `futureDelta` (futureShare + rewardShare), `nextShare`
- **Current code:** Two separate legacy shim calls
- **Notes:** Distress mode changes BPS splits but the pool addition site is the same.

### Site 4: Whale Bundle Pool Split
- **File:** `DegenerusGameWhaleModule.sol` lines 295-296
- **Variables:** `totalPrice - nextShare` (to future), `nextShare` (to next)
- **Current code:** Two separate legacy shim calls

### Site 5: Lazy Pass Pool Split
- **File:** `DegenerusGameWhaleModule.sol` lines 417-425
- **Variables:** `futureShare`, `nextShare` (totalPrice - futureShare)
- **Current code:** Two separate legacy shim calls with null guards

### Site 6: Deity Pass Pool Split
- **File:** `DegenerusGameWhaleModule.sol` lines 536-537
- **Variables:** `nextShare`, `totalPrice - nextShare` (to future)
- **Current code:** Two separate legacy shim calls

### Site 7: Degenerette ETH Bet
- **File:** `DegenerusGameDegeneretteModule.sol` line 588
- **Variables:** `totalBet` goes entirely to future pool
- **Current code:** `_legacySetFuturePrizePool(_legacyGetFuturePrizePool() + totalBet)`
- **Notes:** Future-only addition, like receive fallback.

### Site 8: Degenerette Payout Return
- **File:** `DegenerusGameDegeneretteModule.sol` lines 701-717
- **Variables:** Losers' ETH returned to future pool
- **Analysis needed:** This is the `_resolveBet` path. When a degenerette bet is resolved and the house wins, the ETH stays in the pool. Need to verify if this is a "purchase path" or "game logic" -- it happens during bet resolution, not purchase time.

### Site 9: Additional whale/lootbox sites
- **Analysis:** The PLAN lists "296-297, 419-426, 537-538" for WhaleModule (3 sites) plus DegenerusGame recordMint + receive + MintModule lootbox + DegeneretteModule = total 7. Need to identify the 8th and 9th.

**CORRECTION -- Revised count from plan review:**

The plan (Section 3) lists these purchase-path addition locations:

| # | File | Lines | Context |
|---|------|-------|---------|
| 1 | DegenerusGame.sol | 411, 415 | `recordMint` ticket purchase pool split |
| 2 | DegenerusGameMintModule.sol | 738, 741 | Lootbox purchase pool split |
| 3 | DegenerusGameWhaleModule.sol | 296-297 | Whale bundle pool split |
| 4 | DegenerusGameWhaleModule.sol | 419-426 | Lazy pass pool split |
| 5 | DegenerusGameWhaleModule.sol | 537-538 | Deity pass pool split |
| 6 | DegenerusGameDegeneretteModule.sol | 589 | Degenerette bets |
| 7 | DegenerusGame.sol | 2820 | ETH receive fallback |

That is 7 distinct sites across 4 contracts. The success criteria says "all 9 purchase paths" -- the additional 2 paths may refer to purchase entry points rather than pool addition sites. For example, `_callTicketPurchase` and `_purchaseFor` are purchase entry points (Phase 5 lock removal), and coinflip/lootbox open are purchase paths that may not directly add to pools.

**Verification needed at plan time:** Confirm whether "9 purchase paths" refers to 9 entry points (including lootbox open, coinflip) or 9 pool-addition sites. The plan's Section 3 table lists 7 pool-addition sites. The integration test should exercise all purchase entry points that can produce pool additions under freeze.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Freeze branch logic | Per-site custom if/else | Consistent pattern from Section 3 of plan | Must be identical at all sites for audit clarity |
| Pool packing/unpacking | Manual bit shifts | `_getPrizePools()`/`_setPrizePools()` and `_getPendingPools()`/`_setPendingPools()` | Already built in Phase 1, tested |
| Freeze lifecycle | Manual flag management | `_swapAndFreeze()` / `_unfreezePool()` | Single control points, already implemented in storage |

## Common Pitfalls

### Pitfall 1: Missing an Unfreeze Site
**What goes wrong:** If `_unfreezePool()` is not called at one of the 3 exit points, `prizePoolFrozen` stays true permanently. All future purchases go to pending accumulators that never apply.
**Why it happens:** The `advanceGame` do-while loop has many break paths. Easy to add unfreeze at the obvious ones and miss a subtle exit.
**How to avoid:** The 3 unfreeze sites are: (1) purchase daily after `_unlockRng`, (2) after `_endPhase()`, (3) after `_processPhaseTransition` completes. Grep for `prizePoolFrozen = false` to verify only `_unfreezePool` sets it.
**Warning signs:** In testing, if `prizePoolFrozen` is still true after a full daily cycle completes, an unfreeze site was missed.

### Pitfall 2: Unfreezing Between Jackpot Days
**What goes wrong:** If `_unfreezePool()` is called at the between-jackpot-day `_unlockRng` (line 308), pending accumulators apply too early. Jackpot day 2-5 payouts use inflated pool values.
**Why it happens:** Natural instinct to pair `_unlockRng` with `_unfreezePool` at every site.
**How to avoid:** Only 3 unfreeze sites. The between-jackpot-day `_unlockRng` at line 308 must NOT call `_unfreezePool()`. The freeze persists until `_endPhase()` on the 5th draw.
**Warning signs:** Pool values change between jackpot days even though no unfreeze should occur.

### Pitfall 3: Zeroing Pending Accumulators on Subsequent Jackpot Day Swaps
**What goes wrong:** `_swapAndFreeze()` zeros `prizePoolPendingPacked` when freezing. If this runs on jackpot day 2 when already frozen, it would zero accumulators from day 1 purchases.
**Why it happens:** Not checking `if (!prizePoolFrozen)` before zeroing.
**How to avoid:** Already handled -- `_swapAndFreeze()` checks `if (!prizePoolFrozen)` before zeroing. When already frozen (jackpot days 2-5), it skips the zero. Verify this with a test.

### Pitfall 4: Casting Overflow on uint128
**What goes wrong:** If a share amount exceeds uint128 max (~3.4e20 ETH), the `uint128()` cast silently truncates.
**Why it happens:** Solidity 0.8 checked arithmetic only catches overflow on arithmetic ops, not on explicit downcasts.
**How to avoid:** Not a practical concern -- total ETH supply is ~120M ETH. The plan notes uint128 max far exceeds total ETH supply. No mitigation needed.

### Pitfall 5: Legacy Shim Calls Remaining at Purchase Sites
**What goes wrong:** If a purchase-path site still uses `_legacySetNextPrizePool` instead of the freeze branch, purchases bypass the freeze entirely and go to live pools.
**Why it happens:** Missing a site during the migration.
**How to avoid:** After implementation, grep for `_legacySet` calls in purchase-path files. All purchase-path sites should use the freeze branch pattern. Game-logic sites may still use legacy shims (or be migrated to direct packed helpers).

### Pitfall 6: Degenerette Bet Resolution Pool Return
**What goes wrong:** Degenerette bet resolution (lines 701-717 in DegeneretteModule) modifies `futurePrizePool` when distributing ETH payouts/returns. If this is treated as a purchase path, freeze branching causes it to accumulate in pending when it should immediately affect live pools.
**Why it happens:** Confusion between bet placement (purchase path) and bet resolution (game logic).
**How to avoid:** Only the bet placement at line 588 (`_legacySetFuturePrizePool(... + totalBet)`) gets freeze branching. Bet resolution at lines 701-717 is game logic (pool redistribution) and stays on live pools.

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

### FREEZE-02: Purchase Path Freeze Branch (recordMint example)

```solidity
// DegenerusGame.sol recordMint, replacing lines 406-414:
if (prizeContribution != 0) {
    uint256 futureShare = (prizeContribution * PURCHASE_TO_FUTURE_BPS) / 10_000;
    uint256 nextShare = prizeContribution - futureShare;
    if (prizePoolFrozen) {
        (uint128 pNext, uint128 pFuture) = _getPendingPools();
        _setPendingPools(
            pNext + uint128(nextShare),
            pFuture + uint128(futureShare)
        );
    } else {
        (uint128 next, uint128 future) = _getPrizePools();
        _setPrizePools(
            next + uint128(nextShare),
            future + uint128(futureShare)
        );
    }
}
```

### FREEZE-02: Future-Only Freeze Branch (receive fallback example)

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
// Exit 1: Purchase daily (after _unlockRng, when !inJackpot)
_unlockRng(day);
_unfreezePool();                  // <<< ADD
stage = STAGE_PURCHASE_DAILY;
break;

// Exit 2: Jackpot phase end (after _endPhase)
_endPhase();
_unfreezePool();                  // <<< ADD
stage = STAGE_JACKPOT_PHASE_ENDED;
break;

// Exit 3: Phase transition complete
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
| FREEZE-01 | `_swapAndFreeze()` called at exactly one site (daily RNG) | unit + grep | `grep -rn '_swapAndFreeze' contracts/modules/ \| wc -l` (expect 1) | No -- Wave 0 |
| FREEZE-02 | All 7 purchase-path sites branch on `prizePoolFrozen` | unit | `forge test --match-path "test/fuzz/PrizePoolFreeze.t.sol" --match-test "testFrozen" -vvv` | No -- Wave 0 |
| FREEZE-03 | `_unfreezePool()` is sole path to clear freeze | grep + unit | `grep -n 'prizePoolFrozen = false' contracts/` (expect 1 in _unfreezePool) | No -- Wave 0 |
| FREEZE-04 | Freeze persists across 5 jackpot days | integration | `forge test --match-path "test/fuzz/PrizePoolFreeze.t.sol" --match-test "testJackpotPersistence" -vvv` | No -- Wave 0 |

### Testing Strategy: Harness-Based (Same as Phase 2)

Following Phase 2's successful pattern, use a `FreezeHarness` contract that inherits `DegenerusGameStorage` and exposes internal functions. This avoids the delegatecall + full contract deployment complexity.

The harness must expose:
- `_swapAndFreeze()` / `_unfreezePool()`
- `_getPrizePools()` / `_setPrizePools()`
- `_getPendingPools()` / `_setPendingPools()`
- `prizePoolFrozen` getter/setter
- Prize pool values for assertion

The integration test for "all 9 purchase paths" cannot use the harness alone -- it needs the actual purchase functions. However, the success criteria specifies "an integration test exercising all 9 purchase paths under active freeze." This likely needs a more comprehensive test harness or deployment. Consider whether the QueueHarness pattern can be extended, or whether this test is better deferred to Phase 4/5 when the full advanceGame rewrite is complete.

**Pragmatic approach:** Test the freeze mechanism (freeze/unfreeze lifecycle, accumulator persistence, pool isolation) with the harness. Test freeze branching at each purchase site with targeted unit tests that set `prizePoolFrozen = true` and verify pool additions go to pending. Defer the full 9-path integration test to Phase 5 when lock removal enables end-to-end purchase testing.

### Sampling Rate
- **Per task commit:** `forge test --match-path "test/fuzz/PrizePoolFreeze.t.sol" -vvv`
- **Per wave merge:** `forge test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/fuzz/PrizePoolFreeze.t.sol` -- FreezeHarness + freeze lifecycle tests covering FREEZE-01 through FREEZE-04
- [ ] Extend existing `QueueHarness` with freeze-related exposed functions if needed

## Open Questions

1. **"9 purchase paths" count**
   - What we know: The plan Section 3 table lists 7 pool-addition sites across 4 contracts. The success criteria says "all 9 purchase paths."
   - What's unclear: Are the 9 paths counting entry points (e.g., including coinflip deposit which calls `recordCoinflipDeposit` but doesn't add to prize pools) or only pool-addition sites?
   - Recommendation: Implement freeze branching at all 7 pool-addition sites identified. The integration test should verify all purchase entry points that result in pool additions. If additional paths are identified during implementation, add freeze branching.

2. **Degenerette bet resolution (lines 701-717)**
   - What we know: Bet placement (line 588) is clearly a purchase path. Bet resolution modifies `futurePrizePool` but is game logic (redistributing existing pool funds for payouts).
   - What's unclear: Should bet resolution also branch on freeze?
   - Recommendation: No -- bet resolution is pool redistribution, not new purchase revenue. Only bet placement at line 588 gets freeze branching.

3. **Legacy shim removal timing**
   - What we know: Phase 2 research noted ~70 legacy shim calls marked "REMOVE IN PHASE 2" but Phase 2 did not remove them (focused on queue double-buffer). Phase 3 replaces 7 purchase-path shim calls with freeze branches.
   - What's unclear: Should remaining non-purchase legacy shim calls also be migrated in Phase 3?
   - Recommendation: Only migrate the 7 purchase-path sites in Phase 3. Non-purchase sites (game logic) can continue using legacy shims until they are migrated in a separate effort. This keeps Phase 3 scope tight.

## Sources

### Primary (HIGH confidence)
- Direct code analysis of `contracts/storage/DegenerusGameStorage.sol` -- all infrastructure functions verified present and correct
- Direct code analysis of `contracts/modules/DegenerusGameAdvanceModule.sol` -- all exit paths mapped
- Direct code analysis of `contracts/DegenerusGame.sol`, `contracts/modules/DegenerusGameMintModule.sol`, `contracts/modules/DegenerusGameWhaleModule.sol`, `contracts/modules/DegenerusGameDegeneretteModule.sol` -- all purchase-path pool additions inventoried
- `audit/PLAN-ALWAYS-OPEN-PURCHASES.md` Section 3 -- freeze design specification
- Phase 2 RESEARCH.md and QueueDoubleBuffer.t.sol -- testing pattern reference

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- same Foundry/Solidity stack, no new dependencies
- Architecture: HIGH -- all infrastructure functions already implemented in Phase 1, freeze pattern is well-defined in the plan
- Pitfalls: HIGH -- all exit paths in advanceGame mapped via direct code reading, freeze edge cases documented in plan Section 8
- Purchase path inventory: HIGH -- grep for `_legacySetNextPrizePool`/`_legacySetFuturePrizePool` is exhaustive; cross-referenced with plan Section 3

**Research date:** 2026-03-11
**Valid until:** 2026-04-11 (stable -- no external dependencies, all code in-repo)
