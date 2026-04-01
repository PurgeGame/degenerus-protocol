# Phase 151: Endgame Flag Implementation - Research

**Researched:** 2026-03-31
**Domain:** Solidity smart contract modification -- fixed-point math, storage packing, game state machine
**Confidence:** HIGH

## Summary

This phase replaces a static 30-day elapsed-time BURNIE ticket purchase ban with a dynamic endgame flag based on geometric drip projection math. The core change introduces WAD-scale (1e18) fixed-point exponentiation into the advanceGame flow, packs a new bool into an existing storage slot, and rewires two enforcement points (MintModule and LootboxModule) to check the new flag instead of elapsed time.

The modification is narrow but touches critical game economics. The drip projection uses a closed-form geometric series `futurePool * (1 - 0.9925^n)` where n ranges from 0 to ~120 days. The exponentiation via repeated squaring is the only non-trivial new code -- everything else is wiring an existing pattern (flag checks, far-future redirect via bit 22).

**Primary recommendation:** Implement as three distinct tasks: (1) storage + projection math, (2) advanceGame flag lifecycle, (3) enforcement point rewiring in MintModule and LootboxModule.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Projection rate is 0.75% (75 BPS) per day, deliberately conservative vs the actual 1% daily drip. Use exactly as specified in DRIP-01.
- **D-02:** Use the closed-form geometric series: `totalDrip = futurePool * (1 - 0.9925^n)`. Single exponentiation via repeated squaring, not iterative loop.
- **D-03:** WAD-scale (1e18) fixed-point arithmetic for the exponentiation. 0.9925 represented as 992500000000000000. Exponent n can be up to ~120 days.
- **D-04:** Flag evaluation threshold is L10+ (level >= 10). ROADMAP says L11+ but REQUIREMENTS FLAG-01 is authoritative.
- **D-05:** Flag evaluation runs inside advanceGame, on purchase-phase entry and daily progression. No new entry points.
- **D-06:** Flag storage packed into an existing storage slot (near lastPurchaseDay or jackpotPhaseFlag). Zero additional cold SSTORE cost.
- **D-07:** Flag auto-clears the moment lastPurchaseDay is set (nextPool target met). BURNIE purchases reopen for the final day since the level is confirmed to not be terminal.
- **D-08:** When endgame flag is active and _rollTargetLevel produces currentLevel, redirect to far-future key space (bit 22: `currentLevel | (1 << 22)`). NOT the old +2 shift.
- **D-09:** Only current-level ticket rolls redirect. Near-future rolls (currentLevel+1..+6) land normally even when flag is active.
- **D-10:** Delete from MintModule: `COIN_PURCHASE_CUTOFF`, `COIN_PURCHASE_CUTOFF_LVL0`, `CoinPurchaseCutoff` error, and the elapsed-time revert check at line 615-617.
- **D-11:** Delete from LootboxModule: `BURNIE_LOOT_CUTOFF`, `BURNIE_LOOT_CUTOFF_LVL0`, and the elapsed-time redirect check at lines 648-657.
- **D-12:** Audit ALL other "30 days" references across contracts to confirm none are related to the BURNIE ban. GameOverModule:190 (final sweep) and similar are expected to be unrelated.
- **D-13:** Replace `CoinPurchaseCutoff` error with a new name reflecting the endgame flag mechanism (e.g., `EndgameFlagActive`).

### Claude's Discretion
- Exact storage packing slot choice (whichever existing field offers the cheapest pack)
- Internal function naming and organization
- Specific error name (must reflect endgame flag, not elapsed-time cutoff)

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| REM-01 | 30-day BURNIE ticket purchase ban is fully removed from all levels | Identified exact removal targets: MintModule lines 66-67, 119-120, 614-617; LootboxModule lines 187-190, 648-657. Also verified GameOverModule:190 "30 days" is unrelated (final sweep timer). |
| FLAG-01 | On purchase-phase entry (L10+), compute whether remaining futurePool drip can cover the nextPool gap; if not, set the endgame flag | advanceGame purchase-phase daily path at AdvanceModule:299-316 is the insertion point. Level check uses existing `lvl` local. Drip projection uses `_getFuturePrizePool()`, `_getNextPrizePool()`, `levelPrizePool[]`. |
| FLAG-02 | Each subsequent purchase-phase day, if flag active, re-check and clear if drip projection now covers the gap | Same advanceGame purchase-phase path runs daily -- re-evaluation is naturally part of the same code block. |
| FLAG-03 | Auto-clear the flag at lastPurchaseDay regardless of projection state | `lastPurchaseDay = true` is set at AdvanceModule:146 (turbo) and AdvanceModule:308 (normal). Clear flag at both sites. |
| FLAG-04 | Flag is not checked or set during levels 1-9 or outside purchase phase | Level gate `lvl >= 10` (using `level` storage variable, not `purchaseLevel`) guards evaluation. Purchase-phase-only because evaluation is inside `if (!inJackpot)` block. |
| DRIP-01 | Implement geometric series projection: total remaining drip = sum of futurePool * 0.0075 * 0.9925^i for i in 0..daysRemaining-1 | Closed-form: `totalDrip = futurePool * (1 - 0.9925^n)`. WAD-scale exponentiation via repeated squaring. n = days remaining in purchase phase (up to ~120). |
| DRIP-02 | Compare projected drip total against nextPool deficit (target - current balance) to determine flag state | `deficit = levelPrizePool[lvl] - _getNextPrizePool()` (if nextPool already >= target, no flag needed). Compare against `totalDrip`. |
| ENF-01 | When flag is active, BURNIE ticket purchases revert | Replace elapsed-time revert in `_purchaseCoinFor` (MintModule:614-617) with endgame flag check. |
| ENF-02 | When flag is active, BURNIE lootbox purchases succeed but current-level ticket chance is redirected to far-future tickets | Replace elapsed-time redirect in LootboxModule:648-657 with flag check; change redirect from `currentLevel + 2` to `currentLevel | TICKET_FAR_FUTURE_BIT`. |
| ENF-03 | ETH ticket purchases and ETH lootboxes are unaffected by the flag | ETH purchase path (`purchaseEthTickets`/`purchaseEthLootbox`) never had the ban -- no changes needed. Verify by inspection. |
</phase_requirements>

## Architecture Patterns

### Storage Packing -- Endgame Flag Placement

**Slot 0 is fully packed (32/32 bytes).** Cannot add here without breaking layout.

**Slot 1 has 7 bytes of padding at positions [25:32].** The endgame flag (bool, 1 byte) fits at byte 25 of Slot 1.

Current Slot 1 layout:
```
[0:6]   purchaseStartDay    uint48
[6:22]  price               uint128
[22:23] ticketWriteSlot     uint8
[23:24] ticketsFullyProcessed bool
[24:25] prizePoolFrozen     bool
[25:32] <padding>           7 bytes unused
```

**Recommendation:** Add `endgameFlag` as a `bool` at byte 25 (immediately after `prizePoolFrozen`). This packs into Slot 1 with zero additional SLOAD/SSTORE overhead when any other Slot 1 field is already accessed in the same transaction.

Note: `lastPurchaseDay` and `jackpotPhaseFlag` are in Slot 0, not Slot 1. However, Slot 1's `purchaseStartDay` is read during advanceGame anyway, so accessing the flag from Slot 1 costs no additional cold SLOAD.

### WAD-Scale Exponentiation Pattern

The project has no existing WAD-scale exponentiation. New code needed:

```solidity
/// @dev WAD (1e18) representation of 0.9925 (1 - 0.0075).
uint256 private constant DECAY_RATE_WAD = 992_500_000_000_000_000;
uint256 private constant WAD = 1e18;

/// @dev Compute base^exp in WAD scale via repeated squaring.
///      base is in WAD (e.g., 0.9925e18), exp is a plain integer.
///      Returns result in WAD scale.
function _wadPow(uint256 base, uint256 exp) private pure returns (uint256) {
    uint256 result = WAD;
    while (exp > 0) {
        if (exp & 1 == 1) {
            result = (result * base) / WAD;
        }
        base = (base * base) / WAD;
        exp >>= 1;
    }
    return result;
}
```

**Gas cost:** For n up to 120, repeated squaring takes at most 7 iterations (ceil(log2(120)) = 7). Each iteration is 2 MULs + 1 DIV. Total: ~14 MUL + ~7 DIV = ~700 gas. Negligible.

### Drip Projection Computation

```solidity
/// @dev Compute projected total drip from futurePool over n remaining days.
///      Uses closed-form geometric series: futurePool * (1 - 0.9925^n)
function _projectedDrip(uint256 futurePool, uint256 daysRemaining) private pure returns (uint256) {
    if (daysRemaining == 0) return 0;
    uint256 decayN = _wadPow(DECAY_RATE_WAD, daysRemaining);
    // totalDrip = futurePool * (1 - decayN/WAD) = futurePool * (WAD - decayN) / WAD
    return (futurePool * (WAD - decayN)) / WAD;
}
```

### Flag Evaluation Logic (in advanceGame purchase-phase daily path)

Insertion point: AdvanceModule, inside the purchase-phase daily processing block (after `if (!inJackpot)`, lines 299+).

```solidity
// Evaluate endgame flag for L10+
if (lvl >= 10 && !lastPurchaseDay) {
    uint256 futurePool = _getFuturePrizePool();
    uint256 nextPool = _getNextPrizePool();
    uint256 target = levelPrizePool[lvl];
    if (nextPool < target) {
        uint256 deficit = target - nextPool;
        uint256 daysRemaining = /* compute from liveness guard */;
        uint256 projectedDrip = _projectedDrip(futurePool, daysRemaining);
        endgameFlag = projectedDrip < deficit;
    } else {
        endgameFlag = false;
    }
}
```

**Computing daysRemaining:** The liveness guard fires at `levelStartTime + 120 days` (for lvl > 0). Days remaining = `(levelStartTime + 120 days - block.timestamp) / 1 days`. Note: this is wall-clock days, not game days. Careful with integer division -- round down to be conservative (fewer days = less projected drip = more likely to flag).

### Anti-Patterns to Avoid
- **Loop-based drip summation:** Do NOT iterate over days. Closed-form geometric series is O(log n) via repeated squaring vs O(n) loop. Decision D-02 is explicit.
- **Checking endgameFlag in ETH purchase paths:** ENF-03 requires ETH paths be completely unaffected. The flag must only be checked in BURNIE-specific code paths.
- **Setting flag outside advanceGame:** D-05 requires all evaluation happen inside advanceGame. MintModule and LootboxModule only READ the flag.
- **Using level+1 (purchaseLevel) for the >= 10 check:** The check is on `level` (the current jackpot level), not `purchaseLevel` (which is level+1). FLAG-01 says L10+ meaning level >= 10, so purchaseLevel would be 11+.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Fixed-point exponentiation | Iterative day-by-day drip loop | Closed-form `1 - 0.9925^n` with repeated squaring | O(log n) vs O(n), max 7 iterations vs 120 |
| Far-future ticket redirect | Custom level offset (e.g., +2) | Existing `TICKET_FAR_FUTURE_BIT` (bit 22) key space | Established pattern, guaranteed disjoint from active ticket slots |
| Storage for endgame flag | New storage slot | Pack into Slot 1 byte 25 (existing padding) | Zero additional cold SLOAD cost |

## Common Pitfalls

### Pitfall 1: Off-by-One in daysRemaining Calculation
**What goes wrong:** Integer division of `(deadline - now) / 1 days` can produce n=0 on the last fractional day, causing `_wadPow(x, 0) = WAD` and `projectedDrip = 0`, setting the flag too late or missing the last partial day.
**Why it happens:** Solidity integer division truncates.
**How to avoid:** This is actually correct behavior -- truncating gives a conservative estimate (fewer days = less drip = more likely to flag). But verify edge case: when `daysRemaining == 0`, `_projectedDrip` returns 0, so flag is set (deficit > 0 is almost always true). This is correct -- zero days remaining means no more drip possible.
**Warning signs:** Test with `block.timestamp = levelStartTime + 119 days + 23 hours`.

### Pitfall 2: Flag Not Clearing When lastPurchaseDay Is Set
**What goes wrong:** `lastPurchaseDay` can be set at TWO locations: AdvanceModule:146 (turbo path, early in advanceGame before the daily loop) and AdvanceModule:308 (normal path, inside the purchase-phase daily block). If flag clearing is only added at one site, the other path leaves endgameFlag stale.
**Why it happens:** Two distinct code paths set `lastPurchaseDay = true`.
**How to avoid:** Clear `endgameFlag = false` at BOTH sites where `lastPurchaseDay = true`. Also clear at phase transition (new level start) for hygiene.
**Warning signs:** Test the turbo path (target met within 1 day) separately from the normal path.

### Pitfall 3: WAD Precision Loss in _wadPow
**What goes wrong:** Repeated squaring accumulates rounding error. After 120 iterations of multiply-divide, the result could drift.
**Why it happens:** Each `(result * base) / WAD` loses up to 1 wei of precision.
**How to avoid:** Maximum 7 squaring steps for n=120. Error is at most 7 wei out of 1e18 -- negligible. But verify with a fuzz test: compare Solidity `_wadPow(992500000000000000, n)` against Python `Decimal('0.9925') ** n` for n in [0, 120].
**Warning signs:** None expected -- 7 steps of error is ~7e-18 relative error.

### Pitfall 4: Endgame Flag Evaluated During Jackpot Phase
**What goes wrong:** If flag evaluation code is placed outside the `if (!inJackpot)` guard, it runs during jackpot phase when `lastPurchaseDay` semantics differ.
**Why it happens:** The advanceGame function has both purchase-phase and jackpot-phase paths in the same loop.
**How to avoid:** Place evaluation strictly inside the `!inJackpot` branch. FLAG-04 requires no evaluation outside purchase phase.
**Warning signs:** Search for `endgameFlag` references and verify each is inside a purchase-phase guard.

### Pitfall 5: BURNIE Lootbox Redirect Uses Wrong Key Space
**What goes wrong:** Old code uses `currentLevel + 2` for the redirect (LootboxModule:655). New code must use `currentLevel | TICKET_FAR_FUTURE_BIT`. If old redirect pattern is accidentally retained, tickets land in the normal near-future range instead of the far-future key space.
**Why it happens:** Copy-paste from old code.
**How to avoid:** Use `TICKET_FAR_FUTURE_BIT` constant already defined in GameStorage:160. The resulting key is `currentLevel | (1 << 22)` which is in the 0x400000+ range, completely disjoint from active levels.
**Warning signs:** Verify `targetLevel` after redirect has bit 22 set.

### Pitfall 6: Level 0 Edge Case
**What goes wrong:** Level 0 has a 365-day liveness guard (not 120 days). The old ban used `COIN_PURCHASE_CUTOFF_LVL0 = 335 days` specifically for this. The new endgame flag uses level >= 10 gate, so level 0 is never flagged.
**Why it happens:** The >= 10 gate (FLAG-04) inherently excludes level 0, but the `daysRemaining` calculation must not hardcode 120 days if it's ever reached at level 0.
**How to avoid:** The level >= 10 gate makes this moot. But verify: no code path can evaluate the flag at levels 0-9.

## Code Examples

### Existing Far-Future Key Space Usage (verified from GameStorage:155-160)
```solidity
// contracts/storage/DegenerusGameStorage.sol:155-160
uint24 internal constant TICKET_FAR_FUTURE_BIT = 1 << 22;

function _tqFarFutureKey(uint24 lvl) internal pure returns (uint24) {
    return lvl | TICKET_FAR_FUTURE_BIT;
}
```

### Existing 1% Daily Drip (JackpotModule:601-607, reference for projection rate)
```solidity
// contracts/modules/DegenerusGameJackpotModule.sol:601-607
uint256 poolBps = 100; // 1% daily drip from futurePool
uint256 futurePool = _getFuturePrizePool();
ethDaySlice = (futurePool * poolBps) / 10_000;
_setFuturePrizePool(futurePool - ethDaySlice);
```
Note: Actual drip is 1% (100 BPS). Projection uses conservative 0.75% (75 BPS) rate per D-01. The 0.9925 decay factor = 1 - 0.0075.

### Existing lastPurchaseDay Set Points (both must clear endgameFlag)
```solidity
// AdvanceModule:141-148 (turbo path)
if (!inJackpot && !lastPurchaseDay) {
    uint48 purchaseDays = day - purchaseStartDay;
    if (purchaseDays <= 1 && _getNextPrizePool() >= levelPrizePool[lvl]) {
        lastPurchaseDay = true;
        compressedJackpotFlag = 2;
        // MUST ALSO: endgameFlag = false;
    }
}

// AdvanceModule:305-312 (normal daily path)
if (_getNextPrizePool() >= levelPrizePool[purchaseLevel - 1]) {
    lastPurchaseDay = true;
    if (day - purchaseStartDay <= 3) {
        compressedJackpotFlag = 1;
    }
    // MUST ALSO: endgameFlag = false;
}
```

### Removal Targets (complete list)

**MintModule removals:**
- Line 66-67: `error CoinPurchaseCutoff();` and its NatSpec comment
- Lines 119-120: `COIN_PURCHASE_CUTOFF` and `COIN_PURCHASE_CUTOFF_LVL0` constants
- Lines 614-617: elapsed-time revert check inside `_purchaseCoinFor`

**LootboxModule removals:**
- Lines 187-190: `BURNIE_LOOT_CUTOFF` and `BURNIE_LOOT_CUTOFF_LVL0` constants and their comments
- Lines 648-657: elapsed-time redirect block inside BURNIE lootbox resolution

### Other "30 days" References (verified unrelated)
- `GameOverModule:190` -- `block.timestamp < uint256(gameOverTime) + 30 days` -- final sweep timer, completely unrelated to BURNIE ban
- `GameStorage:528` -- NatSpec about final sweep forfeit -- documentation for above, unrelated

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| 30-day elapsed-time ban | Drip-projection endgame flag | v11.0 (this phase) | Dynamic restriction based on actual pool economics, not arbitrary time |
| `currentLevel + 2` redirect | `currentLevel \| TICKET_FAR_FUTURE_BIT` redirect | v3.9 (bit 22 key space) | Stronger separation via disjoint key space |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge) with Solidity 0.8.34 |
| Config file | `foundry.toml` |
| Quick run command | `forge test --match-contract EndgameFlag -vv` |
| Full suite command | `forge test -vv` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| REM-01 | 30-day ban constants and checks fully removed | unit | `forge test --match-test testNoBanConstants -vv` | Wave 0 |
| FLAG-01 | Flag set on purchase-phase entry at L10+ when drip insufficient | unit | `forge test --match-test testEndgameFlagSet -vv` | Wave 0 |
| FLAG-02 | Flag clears when drip re-covers gap | unit | `forge test --match-test testEndgameFlagClears -vv` | Wave 0 |
| FLAG-03 | Flag auto-clears at lastPurchaseDay | unit | `forge test --match-test testFlagClearsAtLastPurchaseDay -vv` | Wave 0 |
| FLAG-04 | Flag never set at levels 1-9 | unit | `forge test --match-test testNoFlagBelowL10 -vv` | Wave 0 |
| DRIP-01 | Geometric projection matches expected values | unit | `forge test --match-test testDripProjection -vv` | Wave 0 |
| DRIP-02 | Deficit comparison correct | unit | `forge test --match-test testDeficitComparison -vv` | Wave 0 |
| ENF-01 | BURNIE ticket purchase reverts when flag active | unit | `forge test --match-test testBurnieRevertWhenFlagged -vv` | Wave 0 |
| ENF-02 | BURNIE lootbox redirects to far-future when flag active | unit | `forge test --match-test testBurnieLootboxRedirect -vv` | Wave 0 |
| ENF-03 | ETH purchases unaffected by flag | unit | `forge test --match-test testEthUnaffected -vv` | Wave 0 |

### Sampling Rate
- **Per task commit:** `forge test --match-contract EndgameFlag -vv`
- **Per wave merge:** `forge test -vv`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/unit/EndgameFlag.t.sol` -- covers FLAG-01 through FLAG-04, DRIP-01, DRIP-02, ENF-01 through ENF-03, REM-01
- [ ] Test harness may need a helper to fast-forward game to L10+ purchase phase

## Open Questions

1. **daysRemaining source for level 0**
   - What we know: Level 0 liveness guard is 365 days (not 120). But FLAG-04 gates at level >= 10, so level 0 is never evaluated.
   - What's unclear: Nothing -- the gate resolves this.
   - Recommendation: No action needed, but add a code comment explaining the gate excludes level 0.

2. **Flag clearing at level transition (new level start)**
   - What we know: When a new level starts, `lastPurchaseDay` is reset to false. The endgame flag should also reset.
   - What's unclear: Whether phase transition housekeeping (AdvanceModule:253-270) explicitly clears all flags.
   - Recommendation: Clear `endgameFlag = false` in the phase transition block as hygiene, even though FLAG-04 level gate would prevent evaluation at lower levels.

## Sources

### Primary (HIGH confidence)
- `contracts/storage/DegenerusGameStorage.sol` -- storage layout, slot packing, TICKET_FAR_FUTURE_BIT
- `contracts/modules/DegenerusGameMintModule.sol` -- ban check at lines 614-617, constants at 119-120, error at 66-67
- `contracts/modules/DegenerusGameLootboxModule.sol` -- ban redirect at 648-657, constants at 189-190
- `contracts/modules/DegenerusGameAdvanceModule.sol` -- advanceGame flow, lastPurchaseDay set points
- `contracts/modules/DegenerusGameJackpotModule.sol` -- existing 1% daily drip implementation at 601-607
- `.planning/phases/151-endgame-flag-implementation/151-CONTEXT.md` -- all locked decisions

### Secondary (MEDIUM confidence)
- WAD-scale exponentiation via repeated squaring -- standard Solidity pattern (used in Solmate, PRBMath, OpenZeppelin)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all modifications are in existing Solidity contracts with well-understood storage layout
- Architecture: HIGH -- insertion points verified line-by-line in source, storage packing verified from slot map
- Pitfalls: HIGH -- identified from direct code reading of both lastPurchaseDay set points and redirect logic

**Research date:** 2026-03-31
**Valid until:** 2026-04-30 (stable codebase, no external dependency changes expected)
