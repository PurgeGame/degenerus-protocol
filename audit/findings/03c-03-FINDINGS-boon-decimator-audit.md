# Phase 3c Plan 03: BoonModule and DecimatorModule Audit Findings

**Date:** 2026-03-01
**Auditor:** Automated static analysis
**Scope:** `contracts/modules/DegenerusGameBoonModule.sol`, `contracts/modules/DegenerusGameDecimatorModule.sol`
**Method:** Line-by-line trace of all code paths, arithmetic edge case verification

---

## Part A: BoonModule Audit

### Finding A1: consumeCoinflipBoon -- State Clearing Completeness

**Severity:** PASS
**Location:** BoonModule.sol lines 36-59

**Analysis:** Three return paths exist:

| Path | Condition | coinflipBoonBps | coinflipBoonTimestamp | deityCoinflipBoonDay |
|------|-----------|-----------------|----------------------|---------------------|
| 1 (L37) | `player == address(0)` | unchanged | unchanged | unchanged |
| 2 (L41-46) | Deity expired: `deityDay != 0 && deityDay != currentDay` | = 0 (L42) | = 0 (L43) | = 0 (L44) |
| 3 (L48-53) | Timestamp expired: `ts > 0 && nowTs > ts + EXPIRY` | = 0 (L49) | = 0 (L50) | = 0 (L51) |
| 4 (L55) | `boonBps == 0` (no boon) | unchanged (already 0) | unchanged | unchanged |
| 5 (L56-58) | Active boon consumed | = 0 (L56) | = 0 (L57) | = 0 (L58) |

**Verdict:** All three state variables are cleared atomically on every path that consumes or expires the boon. Path 1 (zero address) and Path 4 (no boon) correctly skip clearing since there is nothing to clear. PASS.

---

### Finding A2: consumePurchaseBoost -- State Clearing Completeness

**Severity:** PASS
**Location:** BoonModule.sol lines 64-87

**Analysis:** Identical structure to consumeCoinflipBoon. Three return paths that consume/expire:

| Path | Condition | purchaseBoostBps | purchaseBoostTimestamp | deityPurchaseBoostDay |
|------|-----------|-----------------|----------------------|----------------------|
| 1 (L65) | `player == address(0)` | unchanged | unchanged | unchanged |
| 2 (L69-74) | Deity expired | = 0 (L70) | = 0 (L71) | = 0 (L72) |
| 3 (L76-81) | Timestamp expired | = 0 (L77) | = 0 (L78) | = 0 (L79) |
| 4 (L82) | `boostBps == 0` | unchanged (already 0) | unchanged | unchanged |
| 5 (L84-86) | Active boost consumed | = 0 (L84) | = 0 (L85) | = 0 (L86) |

**Verdict:** All three state variables cleared atomically. PASS.

---

### Finding A3: consumeDecimatorBoost -- State Clearing Completeness

**Severity:** PASS
**Location:** BoonModule.sol lines 92-105

**Analysis:** The decimator boost has only TWO state variables: `decimatorBoostBps` and `deityDecimatorBoostDay`. There is no `decimatorBoostTimestamp` storage variable. This is correct because the decimator boost is deity-only (no lootbox-rolled variant), so it only uses day-based expiry.

| Path | Condition | decimatorBoostBps | deityDecimatorBoostDay |
|------|-----------|-------------------|----------------------|
| 1 (L93) | `player == address(0)` | unchanged | unchanged |
| 2 (L96-99) | Deity expired | = 0 (L97) | = 0 (L98) |
| 3 (L101) | `boostBps == 0` | unchanged (already 0) | unchanged |
| 4 (L103-104) | Active boost consumed | = 0 (L103) | = 0 (L104) |

Note: `_simulatedDayIndex()` (no argument) is used instead of `_simulatedDayIndexAt(nowTs)` -- functionally equivalent since both resolve to `GameTimeLib.currentDayIndex()` which uses `block.timestamp`. The inconsistency in calling convention is cosmetic only.

**Verdict:** Both state variables cleared atomically. No timestamp variable exists (correct by design). PASS.

---

### Finding A4: consumeActivityBoon -- State Clearing Completeness

**Severity:** PASS
**Location:** BoonModule.sol lines 309-359

**Analysis:** Activity boon has three state variables: `activityBoonPending`, `activityBoonTimestamp`, `deityActivityBoonDay`.

| Path | Condition | activityBoonPending | activityBoonTimestamp | deityActivityBoonDay |
|------|-----------|--------------------|-----------------------|---------------------|
| 1 (L311) | `pending == 0` or `player == address(0)` | unchanged | unchanged | unchanged |
| 2 (L316-321) | Deity expired | = 0 (L317) | = 0 (L318) | = 0 (L319) |
| 3 (L324-329) | Timestamp expired | = 0 (L325) | = 0 (L326) | = 0 (L327) |
| 4 (L331-358) | Active boon consumed | = 0 (L331) | = 0 (L332) | = 0 (L333) |

**Verdict:** All three state variables cleared atomically on every consume/expire path. The actual boon effect (levelCount increment + quest streak bonus) only executes on Path 4 (active boon consumed). PASS.

---

### Finding A5: consumeActivityBoon levelCount Overflow Protection

**Severity:** PASS
**Location:** BoonModule.sol lines 340-353

**Analysis:**

```solidity
uint256 countSum = uint256(levelCount) + pending;           // L340
uint24 newLevelCount = countSum > type(uint24).max          // L341
    ? type(uint24).max                                       // L342
    : uint24(countSum);                                      // L343
```

- `levelCount` is uint24 (max 16,777,215)
- `pending` is uint24 (max 16,777,215)
- Promoted to uint256 for addition: max sum = 33,554,430
- Capped to `type(uint24).max = 16,777,215` if overflow

The capped value `newLevelCount` is then passed to `BitPackingLib.setPacked` with `MASK_24`:
```solidity
data = BitPackingLib.setPacked(data, BitPackingLib.LEVEL_COUNT_SHIFT, BitPackingLib.MASK_24, newLevelCount);
```

Since `newLevelCount <= type(uint24).max` and `MASK_24 = (1 << 24) - 1 = 16,777,215`, the value fits within the mask. No field bleed.

Additionally, `bonus` (for quest streak) is separately capped: `pending > type(uint16).max ? type(uint16).max : uint16(pending)`. Since `awardQuestStreakBonus` takes uint16, this prevents truncation.

**Verdict:** Overflow protection correctly applied. Capped value used in all subsequent operations. PASS.

---

### Finding A6: Expiry Logic Consistency -- Day-Based vs Timestamp-Based

**Severity:** PASS
**Location:** All consume functions and checkAndClearExpiredBoon

**Analysis of expiry mechanisms:**

**Day-based expiry (deity-granted boons):**
- Pattern: `deityDay != 0 && deityDay != currentDay` -> expired
- Semantics: Boon valid only on the day it was granted (same-day expiry)
- Used by: ALL boon types (coinflip, purchase, decimator, lootbox x3, whale, activity, deity pass)

**Timestamp-based expiry (lootbox-rolled/self-acquired boons):**
- Pattern: `ts > 0 && nowTs > ts + EXPIRY_SECONDS` -> expired
- Semantics: Boon valid for a fixed duration from grant time
- Used by: coinflip (172800s = 2 days), lootbox x3 (172800s = 2 days), purchase (345600s = 4 days), activity (172800s = 2 days)

**Boons that can use BOTH mechanisms:**
| Boon Type | Day-Based | Timestamp-Based | Can Use Both |
|-----------|-----------|-----------------|--------------|
| Coinflip | Yes (deity) | Yes (lootbox) | Yes |
| Lootbox 25/15/5 | Yes (deity) | Yes (lootbox) | Yes |
| Purchase Boost | Yes (deity) | Yes (lootbox) | Yes |
| Decimator Boost | Yes (deity) | No (deity-only) | No |
| Whale Boon | Yes (deity) | No (day-only) | No |
| Lazy Pass Boon | No | No (day+4 window) | N/A (separate logic) |
| Deity Pass Boon | Yes (deity) | Yes (timestamp) | Yes |
| Activity Boon | Yes (deity) | Yes (lootbox) | Yes |

**Priority:** When both mechanisms apply, deity-day check runs FIRST. If the deity day is expired, all state is cleared immediately without checking the timestamp. This prevents a scenario where a deity boon expires but timestamp-based expiry has not yet kicked in.

**Edge case -- both active:** If `deityDay != 0 && deityDay == currentDay`, the deity check passes (not expired), and the timestamp check runs second. If the timestamp is also expired, the boon is cleared. This is correct: deity same-day grant + expired timestamp = expired.

**Verdict:** Expiry mechanisms are consistently applied. Deity-day takes priority. PASS.

---

### Finding A7: checkAndClearExpiredBoon Completeness

**Severity:** PASS (with one Informational note)
**Location:** BoonModule.sol lines 115-304

**Enumeration of all 10 boon categories handled:**

| # | Boon Category | State Variable(s) | Lines | Cleared on Expiry |
|---|---------------|-------------------|-------|-------------------|
| 1 | Coinflip Boon | coinflipBoonBps, coinflipBoonTimestamp, deityCoinflipBoonDay | 119-136 | All 3 cleared |
| 2 | Lootbox 25% Boost | lootboxBoon25Active, deityLootboxBoon25Day | 138-158 | Active + DeityDay cleared |
| 3 | Lootbox 15% Boost | lootboxBoon15Active, deityLootboxBoon15Day | 160-180 | Active + DeityDay cleared |
| 4 | Lootbox 5% Boost | lootboxBoon5Active, deityLootboxBoon5Day | 182-202 | Active + DeityDay cleared |
| 5 | Purchase Boost | purchaseBoostBps, purchaseBoostTimestamp, deityPurchaseBoostDay | 204-221 | All 3 cleared |
| 6 | Decimator Boost | decimatorBoostBps, deityDecimatorBoostDay | 223-231 | Both cleared |
| 7 | Whale Boon | whaleBoonDay, deityWhaleBoonDay, whaleBoonDiscountBps | 233-240 | All 3 cleared |
| 8 | Lazy Pass Boon | lazyPassBoonDay, lazyPassBoonDiscountBps | 241-253 | Both cleared |
| 9 | Deity Pass Boon | deityPassBoonTier, deityPassBoonTimestamp, deityDeityPassBoonDay | 255-273 | All 3 cleared |
| 10 | Activity Boon | activityBoonPending, activityBoonTimestamp, deityActivityBoonDay | 275-292 | All 3 cleared |

**Count: 10 distinct boon categories. Matches expected count.**

**hasAnyBoon return value (L294-303):**
```solidity
return (whaleDay != 0 ||
    lazyDay != 0 ||
    coinflipBps != 0 ||
    lootbox25 ||
    lootbox15 ||
    lootbox5 ||
    purchaseBps != 0 ||
    decimatorBps != 0 ||
    activityPending != 0 ||
    deityTier != 0);
```

All 10 categories are represented in the OR chain. Each local variable is updated to reflect clearing (e.g., `coinflipBps = 0` after clearing). The return value correctly reflects the post-clearing state.

**Informational note -- Lootbox Timestamp Not Cleared:**

For lootbox boons (25/15/5), the `lootboxBoon*Timestamp` field is read for expiry checking but NEVER cleared during expiry/clearing. Only `lootboxBoon*Active` and `deityLootboxBoon*Day` are zeroed. The stale timestamp persists in storage.

This is harmless because:
1. The primary state check is `lootboxBoon*Active` (bool). When false, the boon is inactive regardless of timestamp.
2. When a new boon is granted (LootboxModule L1348-1380), the timestamp is overwritten.
3. The stale timestamp occupies storage but has zero functional impact.
4. Gas optimization: avoiding the extra SSTORE saves ~5,000 gas per lootbox boon cleared.

**Verdict:** PASS. All 10 categories correctly handled. Stale lootbox timestamp is a deliberate gas optimization, not a bug.

---

### Finding A8: Stale Boon Edge Case -- currentDay == 0

**Severity:** PASS (not reachable)
**Location:** `_simulatedDayIndexAt` via `GameTimeLib.currentDayIndexAt`

**Analysis:**

`GameTimeLib.currentDayIndexAt(ts)` computes:
```solidity
uint48 currentDayBoundary = uint48((ts - JACKPOT_RESET_TIME) / 1 days);
return currentDayBoundary - ContractAddresses.DEPLOY_DAY_BOUNDARY + 1;
```

The `+ 1` ensures the minimum return value is 1 (when `currentDayBoundary == DEPLOY_DAY_BOUNDARY`, i.e., on deploy day).

At deployment, `DEPLOY_DAY_BOUNDARY` is patched to the actual deploy-day boundary value. Post-deployment, `block.timestamp >= deploy_time`, so `currentDayBoundary >= DEPLOY_DAY_BOUNDARY`, and the result is always >= 1.

Therefore `currentDay == 0` is unreachable in any post-deployment context.

Even if `currentDay` were somehow 0, the check `deityDay != 0 && deityDay != currentDay` would evaluate as:
- If `deityDay = 0`: short-circuits false (safe -- deity not set)
- If `deityDay != 0 && deityDay != 0`: always true (boon would be cleared)

So the comparison is safe even in the theoretical `currentDay == 0` case.

**Verdict:** PASS. `currentDay == 0` is unreachable. Even if reached, the comparison fails safe.

---

### Finding A9: Lazy Pass Boon Expiry -- Non-Standard Pattern

**Severity:** Informational
**Location:** BoonModule.sol lines 241-253

**Analysis:** The lazy pass boon uses a unique expiry mechanism different from all other boons:

```solidity
if (lazyDay != 0 && currentDay > lazyDay + 4) {
    // Expired: clear day + discount
}
```

This is a 4-day window expiry (`currentDay > lazyDay + 4` means the boon is valid for days `lazyDay` through `lazyDay + 4` inclusive). This differs from:
- Deity same-day expiry (`deityDay != currentDay`)
- Timestamp duration expiry (`nowTs > ts + EXPIRY_SECONDS`)

Additionally, line 250-252 handles an orphaned discount:
```solidity
} else if (lazyDay == 0 && lazyDiscount != 0) {
    lazyPassBoonDiscountBps[player] = 0;
    lazyDiscount = 0;
}
```

This defensive cleanup catches any case where `lazyPassBoonDay` was cleared but `lazyPassBoonDiscountBps` was not.

**Verdict:** Informational. The non-standard expiry is appropriate for lazy pass mechanics (multi-day validity). The orphan cleanup is good defensive coding.

---

### Finding A10: Deity Pass Boon Expiry -- Hybrid Day/Timestamp Pattern

**Severity:** PASS
**Location:** BoonModule.sol lines 255-273

**Analysis:** The deity pass boon uses a hybrid expiry:

```solidity
if (deityTier != 0) {
    uint48 deityDay = deityDeityPassBoonDay[player];
    if (deityDay != 0) {
        if (currentDay > deityDay) {  // Different from other deity checks!
            // Clear all 3 state vars
        }
    } else {
        // No deity day -> check timestamp expiry
        uint48 ts = deityPassBoonTimestamp[player];
        if (ts > 0 && nowTs > uint256(ts) + PURCHASE_BOOST_EXPIRY_SECONDS) {
            // Clear tier + timestamp (no deity day to clear)
        }
    }
}
```

Key difference from other deity boon checks:
- Other boons: `deityDay != 0 && deityDay != currentDay` (expired if not same day)
- Deity pass: `deityDay != 0` then `currentDay > deityDay` (expired if past the grant day)

This means the deity pass boon survives through the end of the grant day (valid while `currentDay <= deityDay`), whereas other deity boons expire as soon as the day changes (`deityDay != currentDay`). Since `currentDay` only increases, `currentDay > deityDay` and `deityDay != currentDay` are equivalent for the transition from grant day to next day. The only difference would be if `currentDay < deityDay`, which cannot happen (deity day is set to the current day at grant time).

**Verdict:** PASS. The `currentDay > deityDay` check is functionally equivalent to `deityDay != currentDay` given monotonically increasing day indices.

---

## Part B: DecimatorModule Audit

### Finding B1: recordDecBurn Bucket Migration Correctness

**Severity:** PASS
**Location:** DecimatorModule.sol lines 222-281

**Analysis -- First burn (bucket == 0):**
```
L236: if (m.bucket == 0)            // No previous entry
L237:   m.bucket = bucket            // Set bucket
L238:   m.subBucket = _decSubbucketFor(player, lvl, bucket)  // Deterministic sub
```
No aggregate updates needed (prevBurn = 0 for first burn).

**Analysis -- Migration to better bucket (bucket < m.bucket):**
```
L241: _decRemoveSubbucket(lvl, m.bucket, m.subBucket, prevBurn)
      // Removes prevBurn from OLD subbucket aggregate
L242: m.bucket = bucket              // Update to new bucket
L243: m.subBucket = _decSubbucketFor(player, lvl, bucket)  // New deterministic sub
L245: if (prevBurn != 0)
L246:   _decUpdateSubbucket(lvl, m.bucket, m.subBucket, prevBurn)
        // Adds prevBurn to NEW subbucket aggregate
```

Line-by-line trace of a concrete migration:
- Player has prevBurn=100, bucket=5, subBucket=2. Aggregate for [lvl][5][2] includes 100.
- Player calls with bucket=3.
- L241: `_decRemoveSubbucket(lvl, 5, 2, 100)` -> aggregate[5][2] -= 100
- L242-243: bucket=3, subBucket = hash(player, lvl, 3) % 3 (e.g., 1)
- L246: `_decUpdateSubbucket(lvl, 3, 1, 100)` -> aggregate[3][1] += 100

Now the new burn is computed and added:
- L259: `updated = 100 + effectiveAmount` (say effectiveAmount = 50)
- L260-261: `newBurn = 150` (no saturation needed)
- L262-264: `e.burn = 150; e.bucket = 3; e.subBucket = 1;`
- L267: `delta = 150 - 100 = 50`
- L269: `_decUpdateSubbucket(lvl, 3, 1, 50)` -> aggregate[3][1] += 50

Final state: aggregate[3][1] = 100 + 50 = 150 = player's burn. aggregate[5][2] reduced by 100. No leak.

**Same bucket case (bucket == m.bucket or bucket > m.bucket):**
- Neither the if nor the else-if triggers. No migration occurs.
- Only delta is added to the existing subbucket.

**Verdict:** PASS. No aggregate leak on migration. Remove-from-old + add-to-new + subsequent delta tracking is correct.

---

### Finding B2: uint192 Saturation Consistency

**Severity:** PASS
**Location:** DecimatorModule.sol lines 258-269

**Analysis:**

```solidity
uint256 updated = uint256(prevBurn) + effectiveAmount;   // L259
if (updated > type(uint192).max) updated = type(uint192).max;  // L260
uint192 newBurn = uint192(updated);                       // L261
e.burn = newBurn;                                          // L262
...
uint192 delta = newBurn - prevBurn;                       // L267
if (delta != 0) {
    _decUpdateSubbucket(lvl, bucketUsed, m.subBucket, delta);  // L269
}
```

When saturation occurs:
- `updated = type(uint192).max`
- `newBurn = type(uint192).max`
- `delta = type(uint192).max - prevBurn`

This is correct because `delta` reflects the actual increase written to the player's entry. The subbucket aggregate receives exactly `delta`, maintaining the invariant:

**Invariant:** `sum(player.burn for all players in subbucket) == decBucketBurnTotal[lvl][denom][sub]`

Since the player's burn is set to `type(uint192).max` and the aggregate is incremented by `delta = type(uint192).max - prevBurn`, the aggregate tracks the actual player burn values, not the unsaturated amounts.

**Edge case -- already saturated:**
- `prevBurn = type(uint192).max`, `effectiveAmount > 0`
- `updated = type(uint192).max + effectiveAmount > type(uint192).max` (promoted to uint256)
- Saturated: `updated = type(uint192).max`
- `newBurn = type(uint192).max`
- `delta = type(uint192).max - type(uint192).max = 0`
- No aggregate update. Correct -- player burn didn't change.

But wait: `prevBurn >= DECIMATOR_MULTIPLIER_CAP` causes `_decEffectiveAmount` to return `baseAmount` (1x). With a saturated prevBurn (uint192.max >> DECIMATOR_MULTIPLIER_CAP = 200 * 1000 ether), effectiveAmount = baseAmount. The uint256 addition `type(uint192).max + baseAmount` is safe in uint256 space.

**Verdict:** PASS. Saturation delta correctly reflects actual burn increase. Aggregate invariant maintained.

---

### Finding B3: _decEffectiveAmount Edge Cases

**Severity:** PASS
**Location:** DecimatorModule.sol lines 548-568

**Constants:**
- `BPS_DENOMINATOR = 10,000`
- `DECIMATOR_MULTIPLIER_CAP = 200 * 1000 ether = 200,000e18`

**Edge 1: `prevBurn == DECIMATOR_MULTIPLIER_CAP`**
```
L555: prevBurn >= DECIMATOR_MULTIPLIER_CAP -> true
return baseAmount  // 1x, no multiplier
```
Correct. Cap reached, all new burns at 1x.

**Edge 2: `prevBurn == DECIMATOR_MULTIPLIER_CAP - 1`**
```
remaining = 1 (1 wei)
fullEffective = (baseAmount * multBps) / 10000  // e.g. baseAmount=1000, multBps=20000 -> 2000
fullEffective (2000) > remaining (1) -> split logic

maxMultBase = (1 * 10000) / 20000 = 0  (integer division)
maxMultBase (0) > baseAmount (1000)? No.
multiplied = (0 * 20000) / 10000 = 0
effectiveAmount = 0 + (1000 - 0) = 1000 = baseAmount
```
Correct. When remaining is too small for even 1 wei of multiplied burn, entire baseAmount is at 1x.

**Edge 3: `multBps = 10001` (just above 1x)**
```
remaining = DECIMATOR_MULTIPLIER_CAP - prevBurn  // assume prevBurn=0 -> remaining=200,000e18
fullEffective = (baseAmount * 10001) / 10000  // slightly above baseAmount
if fullEffective <= remaining -> return fullEffective
```
For any reasonable baseAmount (much less than 200,000e18), this returns the full multiplied amount. Correct.

**Edge 4: `baseAmount = 0`**
```
L553: if (baseAmount == 0) return 0;
```
Immediate return. Correct.

**Edge 5: `multBps = 0` or `multBps <= BPS_DENOMINATOR`**
```
L555: multBps <= BPS_DENOMINATOR -> true
return baseAmount  // 1x
```
Correct. No multiplier or <=1x multiplier means 1x.

**Edge 6: maxMultBase > baseAmount (line 565)**
```
This can occur when: (remaining * 10000) / multBps > baseAmount
i.e., remaining is large relative to baseAmount.
Example: remaining=500e18, baseAmount=100e18, multBps=20000
maxMultBase = (500e18 * 10000) / 20000 = 250e18 > 100e18
maxMultBase capped to baseAmount (100e18)
multiplied = (100e18 * 20000) / 10000 = 200e18
effectiveAmount = 200e18 + 0 = 200e18
```
This is the normal case where the entire baseAmount fits within the cap. The `if (maxMultBase > baseAmount)` guard prevents over-crediting. The final `effectiveAmount = 200e18` equals `fullEffective`, which is correct since `fullEffective <= remaining`.

Wait: if `fullEffective <= remaining`, we would have returned on L562. The split logic only runs when `fullEffective > remaining`. Let me re-check:

```
fullEffective = (100e18 * 20000) / 10000 = 200e18
remaining = 500e18
200e18 <= 500e18 -> return fullEffective (L562)
```

Split logic is NOT reached in this case. The `maxMultBase > baseAmount` guard only fires when split is needed but `remaining` is large enough to absorb the multiplied portion. Let me construct a case where it fires:

```
remaining = 150e18, baseAmount = 100e18, multBps = 20000
fullEffective = 200e18 > 150e18 -> split
maxMultBase = (150e18 * 10000) / 20000 = 75e18
75e18 > 100e18? No. -> maxMultBase = 75e18
multiplied = (75e18 * 20000) / 10000 = 150e18
effectiveAmount = 150e18 + (100e18 - 75e18) = 150e18 + 25e18 = 175e18
```

Verification: 75e18 at 2x = 150e18 (fills remaining cap), 25e18 at 1x = 25e18. Total = 175e18. prevBurn + 175e18 would push 25e18 past the cap at 1x. Correct split behavior.

For the guard to trigger:
```
remaining = 300e18, baseAmount = 100e18, multBps = 15000 (1.5x)
fullEffective = 150e18 > 300e18? No -> return fullEffective at L562
```
Can't trigger with fullEffective <= remaining. Let me try:
```
remaining = 50e18, baseAmount = 100e18, multBps = 15000
fullEffective = 150e18 > 50e18 -> split
maxMultBase = (50e18 * 10000) / 15000 = 33.33e18 = 33333...e15 (truncated)
33.33e18 > 100e18? No.
```

For it to trigger, we need `(remaining * 10000) / multBps > baseAmount`, which means `remaining > baseAmount * multBps / 10000 = fullEffective`. But split only runs when `fullEffective > remaining`. Contradiction. So `maxMultBase > baseAmount` can NEVER be true when the split logic is reached.

The guard on L565 is dead code in practice -- it is a defensive check that can never trigger given the precondition on L562. This is safe (defense-in-depth, no functional issue).

**Verdict:** PASS. All edge cases produce correct results. The `maxMultBase > baseAmount` guard is a safe defensive check (dead code).

---

### Finding B4: 4-Bit Subbucket Packing Safety

**Severity:** PASS
**Location:** DecimatorModule.sol lines 589-610

**Analysis of `_packDecWinningSubbucket`:**

```solidity
uint8 shift = (denom - 2) << 2;  // 4 bits per denom, starting at denom=2
uint64 mask = uint64(0xF) << shift;
return (packed & ~mask) | ((uint64(sub) & 0xF) << shift);
```

**Bit layout for denoms 2-12:**

| Denom | Shift | Bit Range | Max Sub (denom-1) | Binary | Fits 4 bits? |
|-------|-------|-----------|-------------------|--------|-------------|
| 2 | 0 | [0:3] | 1 | 0001 | Yes |
| 3 | 4 | [4:7] | 2 | 0010 | Yes |
| 4 | 8 | [8:11] | 3 | 0011 | Yes |
| 5 | 12 | [12:15] | 4 | 0100 | Yes |
| 6 | 16 | [16:19] | 5 | 0101 | Yes |
| 7 | 20 | [20:23] | 6 | 0110 | Yes |
| 8 | 24 | [24:27] | 7 | 0111 | Yes |
| 9 | 28 | [28:31] | 8 | 1000 | Yes |
| 10 | 32 | [32:35] | 9 | 1001 | Yes |
| 11 | 36 | [36:39] | 10 | 1010 | Yes |
| 12 | 40 | [40:43] | 11 | 1011 | Yes |

Total bits used: 44 (fits in uint64 which has 64 bits).

Maximum subbucket value: 11 (for denom=12). Binary: 1011 = 4 bits. Masked with 0xF (1111): no data loss.

**Source of sub values:**

`_decSubbucketFor` returns `hash % bucket` where `bucket <= 12` (enforced by `DECIMATOR_MAX_DENOM = 12`). Maximum return value: 11.

`_decWinningSubbucket` returns `hash % denom` where `denom <= 12`. Maximum return value: 11.

**Can denom > 12 ever be passed?**

`recordDecBurn` receives `bucket` from external call (COIN contract), but the `bucket` parameter is only used when `m.bucket == 0` (first burn) or `bucket < m.bucket` (improvement). The `DECIMATOR_MAX_DENOM = 12` constant is used only in `runDecimatorJackpot` loop bounds (`denom <= DECIMATOR_MAX_DENOM`). The coin contract is responsible for validating bucket bounds before calling `recordDecBurn`.

If the coin contract passes `bucket > 12`, the entry would be created with that bucket but the packing in `runDecimatorJackpot` would never iterate over it (loop stops at 12). This means burns with bucket > 12 would never be in any winning subbucket. No overflow in packing because packing only occurs within the 2-12 loop.

**Verdict:** PASS. Maximum subbucket value 11 fits in 4 bits. Total 44 bits fit in uint64. No overflow possible within the 2-12 denom range.

---

### Finding B5: _decRemoveSubbucket Underflow Protection

**Severity:** PASS
**Location:** DecimatorModule.sol lines 688-698

**Analysis:**

```solidity
function _decRemoveSubbucket(uint24 lvl, uint8 denom, uint8 sub, uint192 delta) internal {
    if (delta == 0 || denom == 0) return;
    uint256 slotTotal = decBucketBurnTotal[lvl][denom][sub];
    if (slotTotal < uint256(delta)) revert E();
    decBucketBurnTotal[lvl][denom][sub] = slotTotal - uint256(delta);
}
```

The function explicitly checks `slotTotal < delta` and reverts if so. This prevents aggregate underflow.

Under normal operation, `prevBurn` (passed as `delta`) was previously added to this exact subbucket aggregate. So `slotTotal >= prevBurn` should always hold unless there is a bug elsewhere.

**Verdict:** PASS. Underflow is guarded with explicit revert.

---

### Finding B6: Double-Claim Prevention

**Severity:** PASS
**Location:** DecimatorModule.sol lines 369-392 (\_consumeDecClaim) and lines 441-449 (decClaimable view)

**Analysis of claim flow:**

```
_consumeDecClaim(player, lvl):
  L374: if (lastDecClaimRound.lvl != lvl) revert DecClaimInactive();  // Only latest round
  L377: if (e.claimed != 0) revert DecAlreadyClaimed();              // Double-claim guard
  L382-387: amountWei = _decClaimableFromEntry(...)                  // Calculate share
  L388: if (amountWei == 0) revert DecNotWinner();                   // Not a winner
  L391: e.claimed = 1;                                                // Mark claimed
```

**Claim paths:**

1. `claimDecimatorJackpot(lvl)` (L416-432) -- player self-claims:
   - Calls `_consumeDecClaim(msg.sender, lvl)` which sets `e.claimed = 1` BEFORE any external calls or state changes.
   - Subsequent calls to payout functions (`_addClaimableEth`, `_creditDecJackpotClaimCore`) cannot re-enter `_consumeDecClaim` because `e.claimed` is already 1.

2. `consumeDecClaim(player, lvl)` (L400-406) -- game-initiated claim:
   - Access-restricted to `ContractAddresses.GAME`.
   - Calls `_consumeDecClaim(player, lvl)` which sets `e.claimed = 1`.

**Re-entrancy analysis:**

After `e.claimed = 1` (L391), the function returns `amountWei`. In `claimDecimatorJackpot`:
- L419-421: if `gameOver`, calls `_addClaimableEth` which may trigger `_processAutoRebuy` -> internal state only, no external calls to untrusted contracts.
- L424-431: else, calls `_creditDecJackpotClaimCore` which calls `_awardDecimatorLootbox` -> delegatecall to LootboxModule (trusted code) or `_queueWhalePassClaimCore` (internal).

No external calls to untrusted contracts after claim marking. Even if re-entrancy were possible, `e.claimed = 1` would cause `DecAlreadyClaimed` revert.

**View function safety (decClaimable, L441-449):**
```
_decClaimable(round, player, lvl):
  L656: if (e.claimed != 0) return (0, false);  // Claimed returns zero
```

View function correctly returns 0 for already-claimed entries.

**Round expiry:** Claims are only valid for `lastDecClaimRound.lvl == lvl`. When a new decimator round runs (`runDecimatorJackpot`), it overwrites `lastDecClaimRound.lvl`, immediately expiring all unclaimed entries from the previous round. This is intentional (claims expire).

**Verdict:** PASS. Double-claim prevention is effective. `e.claimed` is set before any external interaction. Round expiry provides additional time-bounding.

---

### Finding B7: recordDecBurn -- Same Bucket Different Sub Edge Case

**Severity:** Informational
**Location:** DecimatorModule.sol lines 236-248

**Analysis:** If a player calls `recordDecBurn` with the same bucket they already have, neither the `if (m.bucket == 0)` nor the `else if (bucket < m.bucket)` triggers. The player stays in their existing bucket/subbucket. This is correct -- a player cannot change their subbucket within the same bucket.

If the player calls with `bucket = 0`, the `else if (bucket != 0 && bucket < m.bucket)` fails on `bucket != 0`. The player stays in their existing bucket. This is also correct.

If the player calls with `bucket > m.bucket`, same result -- no migration, no change. Only strictly better (lower) bucket triggers migration.

**Verdict:** Informational. All non-improvement cases correctly preserve existing bucket assignment.

---

### Finding B8: runDecimatorJackpot -- Double-Snapshot Prevention

**Severity:** PASS
**Location:** DecimatorModule.sol lines 298-355

**Analysis:**

```solidity
L306: if (lastDecClaimRound.lvl == lvl) return poolWei;
```

If the same level is already snapshotted, the full pool is returned (no double-snapshot). This prevents:
1. Overwriting claim data while claims are in progress
2. Resetting the winning subbuckets for the same level

The function also returns `poolWei` when:
- `totalBurn == 0` (no qualifying burns -- no one participated)
- `totalBurn > type(uint232).max` (defensive overflow guard)

**Verdict:** PASS. Double-snapshot correctly prevented.

---

## Summary of Findings

### Severity Distribution

| Severity | Count | Details |
|----------|-------|---------|
| PASS | 14 | All critical checks verified |
| Informational | 3 | A7 (stale lootbox timestamps), A9 (lazy pass non-standard expiry), B7 (same-bucket no-op) |
| LOW | 0 | None |
| MEDIUM | 0 | None |
| HIGH | 0 | None |
| CRITICAL | 0 | None |

### Must-Have Truths Verification

| Truth Statement | Verified | Finding |
|-----------------|----------|---------|
| Every consumeXxxBoon function clears all associated state variables atomically | YES | A1, A2, A3, A4 |
| checkAndClearExpiredBoon handles all 10+ boon types with correct expiry logic | YES | A7 (10 categories enumerated) |
| Deity-granted boons use day-based expiry and lootbox-rolled boons use timestamp-based consistently | YES | A6 |
| DecimatorModule recordDecBurn bucket migration correctly removes from old and adds to new aggregate | YES | B1 |
| Decimator uint192 burn saturation prevents overflow | YES | B2 |
| _decEffectiveAmount multiplier cap split logic handles all edge cases | YES | B3 |
| Decimator 4-bit subbucket packing cannot overflow (max sub value = 11 < 16) | YES | B4 |
| Double-claim prevention via e.claimed=1 is effective across all claim paths | YES | B6 |

### Notable Design Observations

1. **Lootbox boons use bool as primary state**, not BPS values. Timestamp is auxiliary for expiry only. This differs from coinflip/purchase/decimator boons which use BPS as primary state.

2. **Dead code in _decEffectiveAmount**: The `maxMultBase > baseAmount` guard on L565 can never trigger given the precondition check on L562. Safe but unnecessary.

3. **Decimator bucket validation is externalized**: The coin contract (caller of `recordDecBurn`) is responsible for ensuring `bucket` is in [2, 12]. The module does not enforce this. Burns with `bucket > 12` would silently participate but never win (loop in `runDecimatorJackpot` stops at 12).
