# Phase 03c Plan 02: Pricing Formula Arithmetic Verification

**Audit date:** 2026-03-01
**Auditor:** Static analysis (read-only)
**Scope:** WhaleModule pricing (whale bundle, lazy pass, deity pass), PriceLookupLib price curve, boon discount BPS safety
**Contracts audited (READ-ONLY):**
- `contracts/modules/DegenerusGameWhaleModule.sol`
- `contracts/libraries/PriceLookupLib.sol`
- `contracts/modules/DegenerusGameLootboxModule.sol` (boon issuance sites)
- `contracts/modules/DegenerusGameBoonModule.sol` (boon clearing sites)

---

## Section A: Whale Bundle Pricing

### A.1 Unit Price Computation Per Branch

The pricing logic in `_purchaseWhaleBundle` (lines 228-239) has three mutually exclusive branches:

**Branch 1: Boon active (`hasValidBoon = true`)**

Formula: `unitPrice = (WHALE_BUNDLE_STANDARD_PRICE * (10_000 - discountBps)) / 10_000`

Where `WHALE_BUNDLE_STANDARD_PRICE = 4 ether = 4e18 wei`.

Concrete values for each discount tier:

| discountBps | Computation                      | unitPrice (ETH) | unitPrice (wei)  |
|-------------|----------------------------------|-----------------|------------------|
| 1000 (10%)  | (4e18 * 9000) / 10000            | 3.6             | 3,600,000,000,000,000,000 |
| 2500 (25%)  | (4e18 * 7500) / 10000            | 3.0             | 3,000,000,000,000,000,000 |
| 5000 (50%)  | (4e18 * 5000) / 10000            | 2.0             | 2,000,000,000,000,000,000 |
| 0 (legacy)  | Defaults to 1000, same as 10%    | 3.6             | 3,600,000,000,000,000,000 |

All values are exact (no remainder in integer division). Verified: `4e18 * 9000 = 3.6e22`, `3.6e22 / 10000 = 3.6e18`. Clean.

**Branch 2: Early level (`passLevel <= 4`, i.e., game level 0-3)**

`unitPrice = WHALE_BUNDLE_EARLY_PRICE = 2.4 ether = 2,400,000,000,000,000,000 wei`

Constant. No computation needed.

**Branch 3: Standard (fallthrough)**

`unitPrice = WHALE_BUNDLE_STANDARD_PRICE = 4 ether = 4,000,000,000,000,000,000 wei`

Constant. No computation needed.

### A.2 Overflow Check on totalPrice

Formula: `uint256 totalPrice = unitPrice * quantity;`

Maximum case: `unitPrice = 4e18, quantity = 100`
- `totalPrice = 4e18 * 100 = 4e20 = 400 ETH`
- `uint256 max = 2^256 - 1 ~ 1.158e77`
- Ratio: `4e20 / 1.158e77 ~ 3.45e-58`. **No overflow risk.**

Intermediate multiplication check:
- Boon path: `4e18 * 9000 = 3.6e22`. Safe (well within uint256).
- Division `/ 10000` follows immediately. No further intermediate overflow.

**Result: SAFE. No overflow possible at max values.**

### A.3 Decision Tree

```
_purchaseWhaleBundle(buyer, quantity)
|
+-- quantity == 0 || quantity > 100? --> REVERT E()
|
+-- Check boon: whaleBoonDay[buyer] != 0 && currentDay <= boonDay + 4?
|   |
|   +-- YES (hasValidBoon = true)
|   |   |
|   |   +-- discountBps = whaleBoonDiscountBps[buyer]
|   |   +-- discountBps == 0? --> discountBps = 1000 (default 10%)
|   |   +-- unitPrice = (4e18 * (10000 - discountBps)) / 10000
|   |   |   |
|   |   |   +-- discountBps=1000: unitPrice = 3.6 ETH
|   |   |   +-- discountBps=2500: unitPrice = 3.0 ETH
|   |   |   +-- discountBps=5000: unitPrice = 2.0 ETH
|   |   |
|   |   +-- Consume boon (delete day + bps)
|   |
|   +-- NO (hasValidBoon = false)
|       |
|       +-- passLevel <= 4? (game level 0-3)
|       |   +-- YES: unitPrice = 2.4 ETH
|       |   +-- NO:  unitPrice = 4.0 ETH
|
+-- totalPrice = unitPrice * quantity
+-- msg.value != totalPrice? --> REVERT E()
```

**Every leaf produces a positive unitPrice. No zero-price path exists.**

Note: Level eligibility gating (levels 0-3, x49/x99, or boon) is NOT enforced within `_purchaseWhaleBundle` itself. The standard branch (4 ETH) is reachable at any level without a boon. This is traced in plan 03c-01 -- eligibility must be enforced by the DegenerusGame dispatcher.

---

## Section B: Deity Pass Pricing

### B.1 T(n) Formula Verification

Contract formula (line 442):
```solidity
uint256 basePrice = DEITY_PASS_BASE + (k * (k + 1) * 1 ether) / 2;
```

Where `DEITY_PASS_BASE = 24 ether` and `k = deityPassOwners.length` (passes sold so far).

Mathematical equivalent: `basePrice = 24 + T(k)` ETH, where `T(k) = k*(k+1)/2` (triangular number).

Concrete values:

| k (passes sold) | k*(k+1) | T(k) = k*(k+1)/2 | basePrice (ETH) | basePrice (wei)  |
|-----------------|---------|-------------------|-----------------|------------------|
| 0               | 0       | 0                 | 24              | 24e18            |
| 1               | 2       | 1                 | 25              | 25e18            |
| 2               | 6       | 3                 | 27              | 27e18            |
| 10              | 110     | 55                | 79              | 79e18            |
| 15              | 240     | 120               | 144             | 144e18           |
| 20              | 420     | 210               | 234             | 234e18           |
| 31 (max)        | 992     | 496               | 520             | 520e18           |

**Maximum k = 31** because `symbolId >= 32` reverts (line 437) and there are exactly 32 symbols (0-31).

Overflow check at k=31:
- `k * (k + 1) = 31 * 32 = 992`
- `992 * 1 ether = 992 * 1e18 = 9.92e20`
- `9.92e20 / 2 = 4.96e20`
- `24e18 + 4.96e20 = 5.2e20`
- `uint256 max ~ 1.158e77`. Ratio: `5.2e20 / 1.158e77 ~ 4.5e-58`. **No overflow risk.**

Integer division check: `k * (k + 1)` is always even (product of consecutive integers), so `/ 2` always produces an exact result. **No precision loss.**

### B.2 Deity Boon Discount Tiers

Contract code (line 458):
```solidity
uint16 discountBps = boonTier == 3 ? uint16(5000) : (boonTier == 2 ? uint16(2500) : uint16(1000));
```

Applied via: `totalPrice = (basePrice * (10_000 - discountBps)) / 10_000;`

Concrete values at maximum base price (k=31, basePrice=520 ETH):

| boonTier | discountBps | Computation               | totalPrice (ETH) | totalPrice (wei) |
|----------|-------------|---------------------------|-------------------|------------------|
| 1        | 1000 (10%)  | (520e18 * 9000) / 10000   | 468               | 468e18           |
| 2        | 2500 (25%)  | (520e18 * 7500) / 10000   | 390               | 390e18           |
| 3        | 5000 (50%)  | (520e18 * 5000) / 10000   | 260               | 260e18           |
| 0        | N/A         | boonTier check skipped    | 520               | 520e18           |

At minimum base price (k=0, basePrice=24 ETH):

| boonTier | discountBps | totalPrice (ETH) |
|----------|-------------|-------------------|
| 1        | 1000        | 21.6              |
| 2        | 2500        | 18.0              |
| 3        | 5000        | 12.0              |

All values positive. Intermediate: `520e18 * 9000 = 4.68e24`. Well within uint256. **No underflow or overflow.**

Division remainder check: `520e18 * 9000 = 4,680,000e18`, `/ 10000 = 468e18`. Exact. All computed values are exact (no truncation) because `basePrice` is always a whole-ether value and discount multipliers are factors of 10000.

### B.3 Boon Tier Range Boundedness

The `deityPassBoonTier[buyer]` storage variable is `uint8` (storage declaration at DegenerusGameStorage.sol:1304).

**Write sites (non-zero):**
1. `DegenerusGameLootboxModule._applyBoon` (line 1455): `deityPassBoonTier[player] = tier;`
   - `tier` comes from constants: `DEITY_PASS_BOON_TIER_10 = 1`, `DEITY_PASS_BOON_TIER_25 = 2`, `DEITY_PASS_BOON_TIER_50 = 3`
   - Values: {1, 2, 3}. All less than 10000. **SAFE.**

**Consumption site (WhaleModule line 458):**
```solidity
uint16 discountBps = boonTier == 3 ? uint16(5000) : (boonTier == 2 ? uint16(2500) : uint16(1000));
```
- Any `boonTier` value not 2 or 3 maps to `discountBps = 1000` (the default fallback).
- Even if `boonTier` were set to 255 (uint8 max), `discountBps` would be 1000.
- **Maximum discountBps = 5000. Cannot reach 10000. No underflow in `(10_000 - discountBps)` formula.**

**Result: SAFE. Bounded by construction.**

---

## Section C: Lazy Pass Pricing

### C.1 PriceLookupLib.priceForLevel Reference Table

The price curve from `PriceLookupLib.priceForLevel`:

| Level Range         | Price (ETH) | Price (wei)         |
|---------------------|-------------|---------------------|
| 0-4 (intro low)     | 0.01        | 10,000,000,000,000,000 |
| 5-9 (intro high)    | 0.02        | 20,000,000,000,000,000 |
| 10-29               | 0.04        | 40,000,000,000,000,000 |
| 30-59               | 0.08        | 80,000,000,000,000,000 |
| 60-89               | 0.12        | 120,000,000,000,000,000 |
| 90-99               | 0.16        | 160,000,000,000,000,000 |
| x00 (100, 200, ...) | 0.24        | 240,000,000,000,000,000 |
| x01-x29 (cycle)     | 0.04        | 40,000,000,000,000,000 |
| x30-x59 (cycle)     | 0.08        | 80,000,000,000,000,000 |
| x60-x89 (cycle)     | 0.12        | 120,000,000,000,000,000 |
| x90-x99 (cycle)     | 0.16        | 160,000,000,000,000,000 |

### C.2 _lazyPassCost Computation at Representative Levels

`_lazyPassCost(startLevel)` sums `priceForLevel(startLevel + i)` for `i = 0..9`.

Note: The plan erroneously states `_lazyPassCost` sums "tickets per level" but the code sums raw prices. 4 tickets per level is used for ticket queuing, not pricing. `_lazyPassCost` returns the sum of 10 level prices directly.

**Level 0 (currentLevel=0, startLevel=1):** Levels 1-10
- Levels 1-4: 4 * 0.01 = 0.04 ETH
- Levels 5-9: 5 * 0.02 = 0.10 ETH
- Level 10: 1 * 0.04 = 0.04 ETH
- **Total: 0.18 ETH = 180,000,000,000,000,000 wei**

**Level 1 (currentLevel=1, startLevel=2):** Levels 2-11
- Levels 2-4: 3 * 0.01 = 0.03 ETH
- Levels 5-9: 5 * 0.02 = 0.10 ETH
- Levels 10-11: 2 * 0.04 = 0.08 ETH
- **Total: 0.21 ETH = 210,000,000,000,000,000 wei**

**Level 2 (currentLevel=2, startLevel=3):** Levels 3-12
- Levels 3-4: 2 * 0.01 = 0.02 ETH
- Levels 5-9: 5 * 0.02 = 0.10 ETH
- Levels 10-12: 3 * 0.04 = 0.12 ETH
- **Total: 0.24 ETH = 240,000,000,000,000,000 wei**

**Level 3 (currentLevel=3, startLevel=4):** Levels 4-13
- Level 4: 1 * 0.01 = 0.01 ETH
- Levels 5-9: 5 * 0.02 = 0.10 ETH
- Levels 10-13: 4 * 0.04 = 0.16 ETH
- **Total: 0.27 ETH = 270,000,000,000,000,000 wei**

**Level 9 (currentLevel=9, startLevel=10):** Levels 10-19
- Levels 10-19: 10 * 0.04 = 0.40 ETH
- **Total: 0.40 ETH = 400,000,000,000,000,000 wei**

**Level 49 (currentLevel=49, startLevel=50):** Levels 50-59
- Levels 50-59: 10 * 0.08 = 0.80 ETH
- **Total: 0.80 ETH = 800,000,000,000,000,000 wei**

**Level 50 (currentLevel=50, startLevel=51):** Levels 51-60
- Levels 51-59: 9 * 0.08 = 0.72 ETH
- Level 60: 1 * 0.12 = 0.12 ETH
- **Total: 0.84 ETH = 840,000,000,000,000,000 wei**

**Level 99 (currentLevel=99, startLevel=100):** Levels 100-109
- Level 100: 1 * 0.24 = 0.24 ETH
- Levels 101-109: 9 * 0.04 = 0.36 ETH
- **Total: 0.60 ETH = 600,000,000,000,000,000 wei**

**Maximum possible _lazyPassCost:** Occurs at startLevel crossing into x90-x99 range.
- startLevel=90: Levels 90-99, all at 0.16 ETH: 10 * 0.16 = 1.60 ETH
- startLevel=91: Levels 91-100: 9 * 0.16 + 1 * 0.24 = 1.44 + 0.24 = 1.68 ETH

Overflow check: Maximum sum = 1.68 ETH = 1.68e18 wei. uint256 max ~ 1.158e77. **No overflow risk.**

### C.3 Flat 0.24 ETH Path (Levels 0-2 Without Boon)

The flat pricing path applies when `currentLevel <= 2 && !hasValidBoon` (line 354).

Formula (line 356): `uint256 balance = totalPrice - baseCost;`
Where `totalPrice = 0.24 ether` and `baseCost = _lazyPassCost(startLevel)`.

| currentLevel | startLevel | baseCost (ETH) | balance (ETH) | bonusTickets calc                        | bonusTickets |
|--------------|------------|----------------|---------------|------------------------------------------|-------------|
| 0            | 1          | 0.18           | 0.06          | (0.06e18 * 4) / 0.01e18 = 24            | 24           |
| 1            | 2          | 0.21           | 0.03          | (0.03e18 * 4) / 0.01e18 = 12            | 12           |
| 2            | 3          | 0.24           | 0.00          | balance == 0, branch not entered         | 0            |

**All balances are non-negative. No underflow. Verified: `totalPrice >= baseCost` for all eligible levels.**

Bonus tickets formula (line 359): `bonusTickets = uint32((balance * 4) / ticketPrice);`
Where `ticketPrice = PriceLookupLib.priceForLevel(startLevel)`.

At level 0: `ticketPrice = priceForLevel(1) = 0.01 ETH`. `bonusTickets = (0.06e18 * 4) / 0.01e18 = 0.24e18 / 0.01e18 = 24`.
At level 1: `ticketPrice = priceForLevel(2) = 0.01 ETH`. `bonusTickets = (0.03e18 * 4) / 0.01e18 = 0.12e18 / 0.01e18 = 12`.

uint32 overflow check: max bonusTickets = 24. uint32 max = 4,294,967,295. **No overflow risk.**

### C.4 Lazy Pass Boon Discount Path (Level 3+ or With Boon)

When `currentLevel > 2` or `hasValidBoon == true`, the else branch runs (line 361):

```solidity
totalPrice = baseCost;
if (hasValidBoon) {
    if (boonDiscountBps == 0) {
        boonDiscountBps = LAZY_PASS_BOON_DEFAULT_DISCOUNT_BPS; // 1000 (10%)
    }
    totalPrice = (totalPrice * (10_000 - boonDiscountBps)) / 10_000;
}
```

**IMPORTANT FINDING:** `lazyPassBoonDiscountBps` is NEVER written with a non-zero value anywhere in the codebase. All write sites (5 total across BoonModule and WhaleModule) set it to 0. The `lazyPassBoonDay` is similarly never set to a non-zero value. The lazy pass discount boon feature is scaffolded in storage but has no issuance pathway.

Consequence: `hasValidBoon` is always `false` for lazy pass boons through any current code path. The discount computation is dead code.

If the boon discount were ever issued (future code), the same BPS safety analysis applies:
- The `LAZY_PASS_BOON_DEFAULT_DISCOUNT_BPS = 1000` (10%) would be the fallback.
- Maximum plausible `boonDiscountBps` would be constrained by the uint16 type to 65535, but the code structure mirrors whale boon (expect 1000/1500/2500 based on the code pattern and storage doc comment "10/15/25%").
- At `boonDiscountBps = 2500` (max expected): `(baseCost * 7500) / 10000`. Always positive.

**Severity: Informational.** Dead code. No current risk. Future issuance code must bound values below 10000.

---

## Section D: Boon Discount BPS Safety

### D.1 whaleBoonDiscountBps Write Sites

| Location | Value Written | Source | Bounded? |
|----------|---------------|--------|----------|
| LootboxModule line 1427 | `bps` from line 1423-1425 | Constants: 1000, 2500, or 5000 | YES (max 5000) |
| WhaleModule line 231 | Defaults 0 to 1000 | Hardcoded fallback | YES (1000) |
| WhaleModule line 234 | `delete` (= 0) | Clear on consumption | N/A |
| BoonModule line 238 | 0 | Clear on expiry | N/A |

The only non-zero write is from `_applyBoon` in LootboxModule, using constants:
- `LOOTBOX_WHALE_BOON_DISCOUNT_10_BPS = 1000` (line 204)
- `LOOTBOX_WHALE_BOON_DISCOUNT_25_BPS = 2500` (line 205)
- `LOOTBOX_WHALE_BOON_DISCOUNT_50_BPS = 5000` (line 206)

**Maximum possible value: 5000. Cannot reach 10000. SAFE.**

### D.2 lazyPassBoonDiscountBps Write Sites

| Location | Value Written | Source | Bounded? |
|----------|---------------|--------|----------|
| BoonModule line 246 | 0 | Clear on expiry | N/A |
| BoonModule line 251 | 0 | Clear orphaned BPS | N/A |
| WhaleModule line 330 | 0 | Clear on boon expiry | N/A |
| WhaleModule line 333 | 0 | Clear orphaned BPS | N/A |
| WhaleModule line 371 | 0 | Clear on consumption | N/A |

**No non-zero write exists anywhere in the codebase.** This variable can only ever be 0 (default storage value). The lazy pass boon discount is dead code.

**SAFE (trivially -- no issuance pathway exists).**

### D.3 deityPassBoonTier Write Sites

| Location | Value Written | Source | Bounded? |
|----------|---------------|--------|----------|
| LootboxModule line 1455 | `tier` from line 1451-1453 | Constants: 1, 2, or 3 | YES (max 3) |
| WhaleModule line 462 | 0 | Clear on consumption | N/A |
| BoonModule line 260 | 0 | Clear on deity-day expiry | N/A |
| BoonModule line 268 | 0 | Clear on timestamp expiry | N/A |

The only non-zero write uses constants:
- `DEITY_PASS_BOON_TIER_10 = 1` (line 208)
- `DEITY_PASS_BOON_TIER_25 = 2` (line 210)
- `DEITY_PASS_BOON_TIER_50 = 3` (line 212)

At consumption (WhaleModule line 458), these map to discountBps:
- Tier 3 -> 5000, Tier 2 -> 2500, else -> 1000

**Maximum discountBps = 5000. Cannot reach 10000. SAFE.**

### D.4 Cross-Variable Safety Summary

| Variable | Type | Max Non-Zero Value | Max discountBps | `(10000 - discountBps)` min | Risk |
|----------|------|--------------------|-----------------|-----------------------------|------|
| whaleBoonDiscountBps | uint16 | 5000 | 5000 | 5000 | NONE |
| lazyPassBoonDiscountBps | uint16 | 0 (never written) | N/A | N/A | NONE (dead code) |
| deityPassBoonTier | uint8 | 3 | 5000 | 5000 | NONE |

**All discount BPS values are bounded well below 10000. No underflow or zero-price path is possible through any current code path.**

---

## Findings Summary

### Finding PRICING-F01: Lazy Pass Boon Discount is Dead Code

**Severity:** Informational
**Location:** `DegenerusGameStorage.sol:1375-1377` (storage), `DegenerusGameWhaleModule.sol:322-371` (consumption)
**Issue:** The storage variables `lazyPassBoonDay` and `lazyPassBoonDiscountBps` are declared and have consumption/clearing logic, but no code path in the entire codebase ever writes a non-zero value to either variable. The lazy pass discount boon feature is fully scaffolded but unissued.
**Impact:** No runtime impact. All boon-related branches for lazy pass discount are unreachable dead code. The condition `hasValidBoon` at line 321-334 can never be true through any existing code path.
**Recommendation:** Either implement issuance (e.g., add a `DEITY_BOON_LAZY_DISCOUNT_10/25/50` boon type in LootboxModule) or remove the dead storage and consumption code to reduce contract size and gas costs.

### Finding PRICING-F02: All Pricing Formulas Arithmetically Safe

**Severity:** PASS (no issue)
**Details:** Comprehensive arithmetic verification confirms:
- Whale bundle: max `totalPrice = 4e18 * 100 = 4e20` (400 ETH). No overflow.
- Deity pass: max `basePrice = 24e18 + 496e18 = 520e18` (520 ETH). T(n) division by 2 always exact.
- Lazy pass: max `baseCost = 1.68 ETH` (at startLevel 91). No overflow.
- Flat 0.24 ETH: balance is non-negative for all eligible levels (0, 1, 2).
- Bonus tickets: max = 24. No uint32 overflow.
- All BPS discounts bounded at 5000 max. Formula `(10000 - discountBps)` minimum is 5000. No underflow or zero-price.

### Finding PRICING-F03: Whale Bundle Level Eligibility Not Enforced in WhaleModule

**Severity:** Cross-reference (see plan 03c-01)
**Location:** `DegenerusGameWhaleModule._purchaseWhaleBundle`
**Issue:** The pricing logic has no access gate for levels outside 0-3/x49/x99 without boon. At level 5 without a boon, `hasValidBoon=false`, `passLevel=6`, `passLevel <= 4` is false, so `unitPrice = 4 ETH` (standard). The purchase proceeds normally at 4 ETH. The NatSpec says "Available at levels 0-3, x49/x99, or any level with a valid whale boon" but the code does not enforce this within the module.
**Impact:** If the DegenerusGame dispatcher does not enforce level eligibility before delegatecalling WhaleModule, whale bundles can be purchased at any level for 4 ETH. This is not a pricing arithmetic issue but a gating concern traced in plan 03c-01.
