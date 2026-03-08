# WhaleModule Pricing Enforcement Audit -- Findings

**Audit Date:** 2026-03-01
**Auditor:** Phase 03c-01 READ-ONLY audit
**Scope:** DegenerusGameWhaleModule.sol (all three purchase functions), DegenerusGame.sol (dispatcher entry points)
**Method:** Static source analysis -- entry point tracing, pricing branch enumeration, arithmetic verification

---

## Executive Summary

Three purchase functions were audited: `purchaseWhaleBundle`, `purchaseLazyPass`, and `purchaseDeityPass`. All three enforce `msg.value == totalPrice` on every path. One HIGH-severity finding was identified: the whale bundle lacks a level eligibility guard, allowing purchases at any level for 4 ETH despite NatSpec documenting restriction to levels 0-3 and x49/x99. One MEDIUM finding was identified: a day-index function mismatch between whale boon and lazy pass boon validity checks. Three LOW/INFORMATIONAL findings were documented.

---

## Finding F01: Whale Bundle Missing Level Eligibility Guard

**Severity:** HIGH (NatSpec-documented access restriction not enforced in code)

**Location:** `DegenerusGameWhaleModule.sol` lines 188-301

**NatSpec (line 167):**
> Available at levels 0-3, x49/x99, or any level with a valid whale boon.

**@custom:reverts tag (line 180):**
> E When not at level 0-3 or x49/x99 and no valid boon exists.

**Code behavior:** The pricing logic at lines 229-239 has three branches:

```solidity
if (hasValidBoon) {
    // Boon discount applied to WHALE_BUNDLE_STANDARD_PRICE (4 ETH)
    unitPrice = (WHALE_BUNDLE_STANDARD_PRICE * (10_000 - discountBps)) / 10_000;
} else if (passLevel <= 4) {
    unitPrice = WHALE_BUNDLE_EARLY_PRICE;   // 2.4 ETH
} else {
    unitPrice = WHALE_BUNDLE_STANDARD_PRICE; // 4 ETH -- NO REVERT
}
```

At level 5 (passLevel=6) without a boon, the code falls through to `unitPrice = 4 ETH` and proceeds. There is no revert for levels outside {0-3, x49, x99} without a boon. The `else` branch acts as a catch-all at the standard price.

**Entry point trace:**
1. `DegenerusGame.purchaseWhaleBundle(buyer, quantity)` (line 640) -- `external payable`
2. `_resolvePlayer(buyer)` -- resolves address(0) to msg.sender, checks approval for third-party purchases. No level check.
3. `_purchaseWhaleBundleFor(buyer, quantity)` (line 648) -- delegatecalls to `GAME_WHALE_MODULE.purchaseWhaleBundle.selector`. No level check before delegation.
4. `WhaleModule.purchaseWhaleBundle(buyer, quantity)` (line 184) -- calls `_purchaseWhaleBundle`. No level check.
5. `_purchaseWhaleBundle` (line 188) -- pricing logic with no level guard.

**No level eligibility check exists anywhere in the call chain.**

**Test coverage:** `test/edge/WhaleBundle.test.js` only tests purchases at level 0 (early price). Lines 126-148 test "level restrictions" but only verify level 0 succeeds, not that level 5+ reverts. No test covers purchase at level 5 or above without a boon.

**Impact analysis:** A player at any level (e.g., level 50, 150, etc.) can purchase a whale bundle for 4 ETH. This bypasses the documented restriction that bundles should only be available at levels 0-3, x49/x99, or with a boon. The economic impact is that whale bundles at arbitrary levels provide 100-level ticket coverage (40 bonus tickets/level for levels up to 10, 2 standard tickets/level for the rest) at the flat 4 ETH standard price, regardless of where in the level cycle the player is.

**Classification rationale:** Rated HIGH because:
- NatSpec explicitly documents a revert condition that does not exist in code
- The `@custom:reverts` tag creates a false assumption for integrators
- The behavior is economically permissive -- bundles at arbitrary levels may not be the design intent

**However**, there is an alternative interpretation: the three-branch pricing (boon discount, early 2.4 ETH, standard 4 ETH) may BE the intended eligibility enforcement. At levels 0-3 you get the discount price (2.4 ETH). At any other level you pay full price (4 ETH). The NatSpec may simply be outdated, reflecting earlier design where bundles were restricted. The standard 4 ETH price itself serves as a disincentive compared to the 2.4 ETH early price.

**Recommendation:** Confirm with protocol designers whether:
(a) Bundles should truly be restricted -- add `if (passLevel > 4 && passLevel % 50 != 0 && !hasValidBoon) revert E();` or equivalent, OR
(b) Any-level purchase at 4 ETH is intentional -- update NatSpec and `@custom:reverts` to reflect actual behavior.

---

## Finding F02: Day-Index Function Mismatch Between Whale Boon and Lazy Pass Boon Validity

> **POST-AUDIT UPDATE:** This finding has been fixed. The whale boon check (WhaleModule line 202) now uses `_simulatedDayIndex()`, consistent with the lazy pass boon check. Both boon validity checks now use the same day-index function.

**Severity:** MEDIUM (inconsistent time source for equivalent operations)

**Location:**
- Whale boon check: `DegenerusGameWhaleModule.sol` line 200 uses `_currentMintDay()`
- Lazy pass boon check: `DegenerusGameWhaleModule.sol` line 325 uses `_simulatedDayIndex()`

**Code:**

Whale bundle boon validity (line 200):
```solidity
uint48 currentDay = _currentMintDay();
hasValidBoon = currentDay <= boonDay + 4;
```

Lazy pass boon validity (line 325):
```solidity
uint48 currentDay = _simulatedDayIndex();
if (currentDay <= boonDay + 4) {
    hasValidBoon = true;
}
```

**Difference:** `_currentMintDay()` returns `dailyIdx != 0 ? dailyIdx : _simulatedDayIndex()`. During active game, `dailyIdx` is set to the day index at the last `advanceGame` call. `_simulatedDayIndex()` always computes from `block.timestamp`. Between advances, these could differ by 1 day if a day boundary has passed since the last advance but no advance has occurred yet.

**Impact:** During active game, the whale boon validity window could be off by +/-1 day compared to the lazy pass boon validity window. In the worst case, a whale boon could expire one day early (if `dailyIdx` is stale and behind real time) or stay valid one day longer than a lazy pass boon granted at the same time.

**Classification rationale:** MEDIUM because:
- Both functions handle equivalent operations (purchase boon validity)
- The inconsistency could cause a 1-day window difference
- During pre-game (level 0), `dailyIdx == 0` so `_currentMintDay()` falls back to `_simulatedDayIndex()` and the two are equivalent
- Practical impact is limited to edge cases at day boundaries during active game

**Recommendation:** Use the same day-index function in both boon checks for consistency. `_simulatedDayIndex()` is the more correct choice since it reflects real time rather than potentially-stale advance state.

---

## Finding F03: Whale Bundle NatSpec Fund Distribution Incorrect

**Severity:** LOW (documentation inconsistency)

**Location:** `DegenerusGameWhaleModule.sol` lines 175-177 (NatSpec) vs lines 286-295 (code)

**NatSpec (lines 175-177):**
> Fund distribution:
> - Pre-game (level 0): 50% next pool, 50% future pool
> - Post-game (level > 0): 5% next pool, 95% future pool

**Code (lines 286-295):**
```solidity
if (level == 0) {
    nextShare = (totalPrice * 3000) / 10_000;  // 30% to next
} else {
    nextShare = (totalPrice * 500) / 10_000;   // 5% to next
}
futurePrizePool += totalPrice - nextShare;      // 70% or 95% to future
```

**Actual distribution:** Pre-game: 30% next / 70% future. Post-game: 5% next / 95% future. The NatSpec incorrectly states 50/50 for pre-game.

**Note:** The deity pass function has the same distribution (30/70 and 5/95) at lines 509-517, and its NatSpec at lines 425-426 correctly states "Pre-game (level 0): 30% next pool, 70% future pool" and "Post-game (level > 0): 5% next pool, 95% future pool". The whale bundle NatSpec is simply outdated.

**Additionally**, the DegenerusGame.sol dispatcher NatSpec (lines 624-637) references "Fixed cost: 6 ETH", "levels 1, 51, 101, 151...", and "50% next/25% reward/25% future" -- all of which are stale from an earlier design iteration.

**Impact:** No functional impact. Documentation-only issue.

---

## Finding F04: Lazy Pass Level Eligibility Check Verified Correct

**Severity:** INFORMATIONAL (confirmed correct, no issue)

**Location:** `DegenerusGameWhaleModule.sol` line 345

> **POST-AUDIT UPDATE (correction):** The original finding quoted the level check as `> 3`, but the actual code at WhaleModule line 345 reads `if (currentLevel > 2 && currentLevel % 10 != 9 && !hasValidBoon) revert E();`. This means levels 0, 1, 2 are allowed (not 0-3). The corrected analysis below reflects the actual `> 2` threshold.

**Code:**
```solidity
if (currentLevel > 2 && currentLevel % 10 != 9 && !hasValidBoon) revert E();
```

**Analysis:** This check enforces:
- `currentLevel <= 2` (levels 0, 1, 2) -- allowed
- `currentLevel % 10 == 9` (levels 9, 19, 29, 39, 49...) -- allowed
- `hasValidBoon == true` -- allowed at any level

This gates to levels 0-2 and x9 (the "lazy pass" entry points).

**Additional guards:**
- Line 338: `if (deityPassCount[buyer] != 0) revert E();` -- deity pass holders cannot buy lazy passes
- Line 345: `if (frozenUntilLevel > currentLevel + 7) revert E();` -- early renewal window (prevents stacking if 7+ levels remain on existing freeze)

---

## Finding F05: lazyPassBoonDiscountBps Never Assigned Non-Zero Value

> **POST-AUDIT UPDATE:** This finding has been fixed. `DegenerusGameLootboxModule.sol` at line 1492 now assigns `lazyPassBoonDiscountBps[player] = bps` with non-zero values during deity boon issuance. The lazy pass boon discount tiers (10%, 25%, 50%) are now functional, matching the whale boon tier pattern. The variable is no longer dead code.

**Severity:** INFORMATIONAL (dead code / placeholder for future feature)

**Location:** `DegenerusGameStorage.sol` line 1377

**Analysis:** The storage variable `lazyPassBoonDiscountBps` is declared and read in multiple places (WhaleModule line 322, BoonModule line 242, LootboxModule line 1283) but is never assigned a non-zero value anywhere in the codebase. All write operations to this variable assign 0 (clearing it).

The lazy pass discount code path at WhaleModule lines 363-372 handles a boon discount by reading `boonDiscountBps = lazyPassBoonDiscountBps[buyer]` and defaulting to `LAZY_PASS_BOON_DEFAULT_DISCOUNT_BPS = 1000` (10%) when it is 0. Since it is always 0, the default is always used.

Meanwhile, `lazyPassBoonDay[buyer]` IS set in the lootbox boon issuance path (via `_applyBoon` for lazy pass boons), so the boon can activate, but the discount tier is always the default 10%.

**Impact:** No functional issue. The discount variable appears to be a placeholder for future tiered lazy pass discounts (matching the whale boon pattern which has 10/25/50% tiers). Currently all lazy pass boons use the 10% default.

---

## Pricing Branch Exhaustiveness

### purchaseWhaleBundle

| Branch | Condition | unitPrice | Enforced? |
|--------|-----------|-----------|-----------|
| Boon | `hasValidBoon == true` | `(4 ETH * (10000 - discountBps)) / 10000` | Yes |
| Early | `!hasValidBoon && passLevel <= 4` | 2.4 ETH | Yes |
| Standard | `!hasValidBoon && passLevel > 4` | 4.0 ETH | Yes (see F01) |

- `totalPrice = unitPrice * quantity` -- max 4 ETH * 100 = 400 ETH, well within uint256
- `msg.value != totalPrice` check at line 242 -- present, reached on all three branches
- No fourth branch or fallthrough exists (if/else if/else is exhaustive)

### purchaseLazyPass

| Branch | Condition | totalPrice | Enforced? |
|--------|-----------|------------|-----------|
| Flat early | `currentLevel <= 2 && !hasValidBoon` | 0.24 ETH | Yes |
| Sum-of-prices | `currentLevel > 2 \|\| hasValidBoon` | `baseCost` (or discounted) | Yes |

- `baseCost = _lazyPassCost(startLevel)` -- sum of 10 level prices via PriceLookupLib
- Flat 0.24 ETH: `balance = totalPrice - baseCost`:
  - Level 0 (startLevel=1): baseCost = 5*0.01 + 5*0.02 = 0.15 ETH. balance = 0.09 ETH. No underflow.
  - Level 1 (startLevel=2): baseCost = 4*0.01 + 5*0.02 + 1*0.04 = 0.18 ETH. balance = 0.06 ETH. No underflow.
  - Level 2 (startLevel=3): baseCost = 3*0.01 + 5*0.02 + 2*0.04 = 0.21 ETH. balance = 0.03 ETH. No underflow.
- `msg.value != totalPrice` check at line 374 -- present, reached on all paths
- Boon discount: `(baseCost * (10000 - discountBps)) / 10000` with discountBps always 1000 (default, see F05). Result: baseCost * 0.9. No underflow risk since discountBps < 10000.

### purchaseDeityPass

| Branch | Condition | totalPrice | Enforced? |
|--------|-----------|------------|-----------|
| Base | No boon | `24 + k*(k+1)/2` ETH | Yes |
| Discounted | Active, non-expired boon | `basePrice * (10000 - discountBps) / 10000` | Yes |

- `basePrice = DEITY_PASS_BASE + (k * (k + 1) * 1 ether) / 2`
  - k=0: 24 + 0 = 24 ETH (verified by test)
  - k=1: 24 + 1 = 25 ETH (verified by test)
  - k=2: 24 + 3 = 27 ETH (verified by test)
  - k=31 (max, since 32 symbols): 24 + 31*32/2 = 24 + 496 = 520 ETH (matches NatSpec)
- Boon tiers: tier 1 = 1000 BPS (10%), tier 2 = 2500 BPS (25%), tier 3 = 5000 BPS (50%)
  - Max discount: 50% of 520 ETH = 260 ETH. Still non-zero. No underflow.
- `msg.value != totalPrice` check at line 466 -- present, reached on all paths
- No level restriction -- NatSpec at line 419 confirms "Available at any time"
- Symbol range: `symbolId >= 32` reverts (line 437)
- Duplicate prevention: `deityBySymbol[symbolId] != address(0)` (line 438), `deityPassCount[buyer] != 0` (line 439)

---

## msg.value Enforcement Summary

| Function | Line | Check | Reached on all paths? |
|----------|------|-------|----------------------|
| `_purchaseWhaleBundle` | 242 | `msg.value != totalPrice` | Yes -- after all 3 pricing branches |
| `_purchaseLazyPass` | 374 | `msg.value != totalPrice` | Yes -- after flat and sum-of-prices paths |
| `_purchaseDeityPass` | 466 | `msg.value != totalPrice` | Yes -- after base and discounted paths |

All three functions have exactly one `msg.value` check, and all pricing branches converge to `totalPrice` before the check. No path bypasses the msg.value validation.

---

## Boon Consumption Atomicity

### Whale Bundle Boon (lines 229-234)

```solidity
if (hasValidBoon) {
    uint16 discountBps = whaleBoonDiscountBps[buyer];
    if (discountBps == 0) discountBps = 1000;
    unitPrice = (WHALE_BUNDLE_STANDARD_PRICE * (10_000 - discountBps)) / 10_000;
    delete whaleBoonDay[buyer];         // Consumed
    delete whaleBoonDiscountBps[buyer]; // Consumed
}
```

- Discount is applied FIRST (lines 230-232), then boon state is deleted (lines 233-234)
- Both `whaleBoonDay` and `whaleBoonDiscountBps` are deleted in the same block
- No path can apply the discount without consuming the boon (they are in the same `if` block)
- No path can consume the boon without applying the discount (delete follows price calculation immediately)
- Deletion occurs BEFORE any external calls (affiliate lookups at line 270, DGNRS transfers at line 281)

### Lazy Pass Boon (lines 363-372)

```solidity
if (hasValidBoon) {
    if (boonDiscountBps == 0) {
        boonDiscountBps = LAZY_PASS_BOON_DEFAULT_DISCOUNT_BPS;
    }
    totalPrice = (totalPrice * (10_000 - boonDiscountBps)) / 10_000;
    lazyPassBoonDay[buyer] = 0;         // Consumed
    lazyPassBoonDiscountBps[buyer] = 0; // Consumed
}
```

- Same pattern: discount applied first, then boon cleared
- Both state variables zeroed atomically
- No external calls between pricing and consumption

### Deity Pass Boon (lines 446-465)

```solidity
if (boonTier != 0) {
    // ... expiry check ...
    if (!expired) {
        uint16 discountBps = boonTier == 3 ? 5000 : (boonTier == 2 ? 2500 : 1000);
        totalPrice = (basePrice * (10_000 - discountBps)) / 10_000;
    }
    // Consume boon regardless of expiry
    deityPassBoonTier[buyer] = 0;
    deityPassBoonTimestamp[buyer] = 0;
    deityDeityPassBoonDay[buyer] = 0;
}
```

- Boon consumed REGARDLESS of whether it was expired (line 461 comment)
- If expired: discount NOT applied, boon still consumed (correct -- prevents reuse)
- If not expired: discount applied, boon consumed
- All three state variables (tier, timestamp, deityDay) zeroed atomically
- No external calls between pricing and consumption

**All boon consumption is atomic with pricing.** No reentrancy or split-operation risk.

---

## Quantity Bounds

| Function | Quantity | Check | Location |
|----------|---------|-------|----------|
| `purchaseWhaleBundle` | 1-100 | `quantity == 0 \|\| quantity > 100` reverts | Line 194 |
| `purchaseLazyPass` | Fixed 1 | No quantity parameter | N/A |
| `purchaseDeityPass` | Fixed 1 per symbol | No quantity parameter; one per buyer enforced via `deityPassCount[buyer] != 0` | Line 439 |

---

## Findings Summary

| ID | Severity | Description | Status |
|----|----------|-------------|--------|
| F01 | HIGH | Whale bundle lacks level eligibility guard (NatSpec says levels 0-3/x49/x99, code allows any level at 4 ETH) | Needs design confirmation |
| F02 | MEDIUM | Day-index function mismatch: whale boon uses `_currentMintDay()`, lazy pass boon uses `_simulatedDayIndex()` | **FIXED POST-AUDIT** -- whale boon now uses `_simulatedDayIndex()` |
| F03 | LOW | Whale bundle NatSpec states 50/50 fund split, code implements 30/70 (pre-game) | Documentation only |
| F04 | INFORMATIONAL | Lazy pass level eligibility check (corrected: `> 2`, not `> 3` as originally stated) | Levels 0-2 and x9, or with boon |
| F05 | INFORMATIONAL | `lazyPassBoonDiscountBps` never assigned non-zero; all lazy pass boons use 10% default | **FIXED POST-AUDIT** -- LootboxModule line 1492 now assigns non-zero values |

---

## Cross-References

- **Research Finding #4** (3c-RESEARCH.md): "Whale Bundle Level Eligibility Check Location" -- **CONFIRMED** as Finding F01. No level guard exists in `_purchaseWhaleBundle` or the DegenerusGame dispatcher.
- **Research Finding #5** (3c-RESEARCH.md): "Lazy Pass baseCost Underflow Edge Case at Level 2" -- **CONFIRMED SAFE**. Arithmetic verified at all three eligible early levels (0, 1, 2). No underflow.
- **MATH-07** requirement: Not directly covered by this plan (BurnieCoinflip scope). Partial overlap: whale bundle pricing arithmetic verified safe.
- **MATH-08** requirement: Not directly covered by this plan (BitPackingLib scope). Partial overlap: mintPacked_ field access in WhaleModule verified consistent.
