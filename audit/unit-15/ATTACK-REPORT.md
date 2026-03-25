# Unit 15: Libraries -- Mad Genius Attack Report

**Phase:** 117
**Contracts:** EntropyLib (24L), BitPackingLib (88L), GameTimeLib (35L), JackpotBucketLib (307L), PriceLookupLib (47L)
**Agent:** Mad Genius (Opus)
**Date:** 2026-03-25

---

## EntropyLib

---

### E-01: EntropyLib::entropyStep (L16-23)

```solidity
function entropyStep(uint256 state) internal pure returns (uint256) {
    unchecked {
        state ^= state << 7;
        state ^= state >> 9;
        state ^= state << 8;
    }
    return state;
}
```

#### Implementation Analysis

XOR-shift with triple (<<7, >>9, <<8) on uint256. The `unchecked` block is semantically irrelevant -- XOR and shift operations on `uint256` cannot overflow or underflow; shifts that exceed 255 produce 0 bits, and XOR has no carry. The `unchecked` label is a gas micro-optimization (avoiding compiler-inserted checks) but does not change behavior.

**Mathematical Properties of XOR-shift on uint256:**

The standard XOR-shift generator operates on machine words. For uint256 (256-bit), the shift triple (a, b, c) = (7, 9, 8) defines the transformation matrix T = (I + L^7)(I + R^9)(I + L^8) over GF(2)^256, where L^n is the left shift matrix and R^n is the right shift matrix.

For a full-period XOR-shift generator on n-bit words, the characteristic polynomial of T must be primitive over GF(2). For 256-bit, the period would be 2^256 - 1 (maximum). Verifying primitivity for a specific triple on 256 bits requires computing the characteristic polynomial, which is computationally expensive.

**However, the critical security question is not period length, but rather:**
1. Is the entropy seeded from VRF? YES -- all callers seed from VRF-derived words.
2. Is the step function invertible? YES -- XOR-shift with left/right shifts is always invertible (each step is an XOR with a shifted version, which is a linear bijection over GF(2)^256).
3. Is there a degenerate fixed point? **YES -- state = 0.**

#### Attack Analysis

**1. Fixed Point at Zero: entropyStep(0) = 0**

```
state = 0
state ^= 0 << 7 = 0 ^  0 = 0
state ^= 0 >> 9 = 0 ^ 0 = 0
state ^= 0 << 8 = 0 ^ 0 = 0
return 0
```

**Verdict: INVESTIGATE**

If any caller passes state=0 to entropyStep, ALL subsequent derivations produce 0. This means:
- Bucket rotations would always use entropy & 3 = 0 (no rotation)
- Trait selections would produce traits [0, 64, 128, 192] every time
- Winner selections would be deterministic

**Caller Analysis for Zero-Seed Risk:**
- All callers seed from `rngWords[day]` (VRF output). VRF words are keccak256 hashes and are astronomically unlikely to be exactly 0.
- Several callers XOR the entropy with a salt before stepping: `EntropyLib.entropyStep(entropy ^ rollSalt)`. Even if entropy=0, the salt makes the input non-zero.
- In JackpotModule L2029: `EntropyLib.entropyStep(entropy ^ rollSalt)` -- rollSalt includes keccak256 of player data.
- The only path to zero would be: VRF returns exactly 0 for a day's word, AND caller doesn't XOR with salt. Probability: ~1/2^256 per VRF request. Effectively zero.

**Practical Risk: NEGLIGIBLE.** The fixed point at 0 is a mathematical property of every XOR-shift generator, but with VRF seeding the probability of encountering it is astronomically low.

**2. Linearity Over GF(2)**

XOR-shift is a linear transformation over GF(2). This means:
- `entropyStep(a XOR b) = entropyStep(a) XOR entropyStep(b)`
- An attacker who knows the linear structure can predict outputs given known inputs.

**However:** In this protocol, the attacker CANNOT choose the VRF seed. The VRF word is determined by Chainlink and unknown until fulfillment. The attacker cannot observe intermediate entropy states (they're in-memory only). The linearity is exploitable only if the attacker can choose inputs, which requires VRF compromise (out of scope per KNOWN-ISSUES.md).

**Verdict: SAFE** -- Linearity is a theoretical weakness but unexploitable without VRF compromise.

**3. Shift Constant Quality**

The triple (7, 9, 8) is not a well-known XOR-shift triple from Marsaglia's tables (those are for 32/64-bit words). For 256-bit operation, the diffusion properties differ. After one step, a single-bit change in the input propagates to approximately 3 bits (one from each shift operation). After 2-3 chained steps, diffusion covers a significant portion of the 256-bit word.

Most callers apply entropyStep repeatedly (looping over winners/traits), so even if single-step diffusion is modest, the cumulative diffusion after N steps is adequate.

**Verdict: SAFE** -- Diffusion is sufficient given VRF seeding and multi-step usage patterns.

**4. Unchecked Block Safety**

`unchecked` on shift and XOR operations: left shift of uint256 by 7, 8 never overflows (shifts beyond 255 would zero out, but 7 and 8 are well within range). Right shift by 9 simply drops low bits. XOR cannot overflow. **No arithmetic hazard.**

**Verdict: SAFE**

#### Cached-Local-vs-Storage Check
Not applicable -- pure function, no storage access.

#### Summary

| Attack Angle | Verdict |
|-------------|---------|
| Fixed point at 0 | INVESTIGATE (negligible practical risk) |
| GF(2) linearity | SAFE |
| Shift constant quality | SAFE |
| Unchecked arithmetic | SAFE |

---

## BitPackingLib

---

### B-01: BitPackingLib::setPacked (L79-86)

```solidity
function setPacked(
    uint256 data,
    uint256 shift,
    uint256 mask,
    uint256 value
) internal pure returns (uint256) {
    return (data & ~(mask << shift)) | ((value & mask) << shift);
}
```

#### Implementation Analysis

Standard bit-field write operation:
1. `mask << shift` -- positions the mask at the target field
2. `~(mask << shift)` -- creates an inverted mask (1s everywhere except the target field)
3. `data & ~(mask << shift)` -- clears the target field in data
4. `value & mask` -- truncates value to field width
5. `(value & mask) << shift` -- positions the truncated value at the target field
6. OR combines cleared data with new field value

**Correctness Proof:**
- If `mask` is a contiguous run of 1-bits of width W starting at bit 0, and `shift` is the target position, then `setPacked` writes exactly W bits starting at position `shift`.
- The `value & mask` truncation ensures values larger than the field width are silently clipped. This is SAFE (prevents overflow into adjacent fields) but callers should be aware of silent truncation.

#### Attack Analysis

**1. Field Overlap / Bleed-Through**

For bleed-through to occur, `(mask << shift)` for one field must overlap with another field's bit range. Checking all defined field pairs:

| Field A | Bits | Field B | Bits | Overlap? |
|---------|------|---------|------|----------|
| LAST_LEVEL (0, MASK_24) | 0-23 | LEVEL_COUNT (24, MASK_24) | 24-47 | NO |
| LEVEL_COUNT (24, MASK_24) | 24-47 | LEVEL_STREAK (48, MASK_24) | 48-71 | NO |
| LEVEL_STREAK (48, MASK_24) | 48-71 | DAY (72, MASK_32) | 72-103 | NO |
| DAY (72, MASK_32) | 72-103 | LEVEL_UNITS_LEVEL (104, MASK_24) | 104-127 | NO |
| LEVEL_UNITS_LEVEL (104, MASK_24) | 104-127 | FROZEN_UNTIL (128, MASK_24) | 128-151 | NO |
| FROZEN_UNTIL (128, MASK_24) | 128-151 | BUNDLE_TYPE (152, mask=3) | 152-153 | NO |
| BUNDLE_TYPE (152, mask=3) | 152-153 | [gap 154-159] | - | NO |
| STREAK_LAST_COMPLETED (160, MASK_24) | 160-183 | [gap 184-227] | - | NO |
| LEVEL_UNITS (228, MASK_16) | 228-243 | [reserved 244-255] | - | NO |

**All fields are non-overlapping. No bleed-through possible with defined constants.**

**Verdict: SAFE**

**2. Caller Misuse: Wrong (shift, mask) Pairs**

Checking all callers for correct pairing:

- **DegenerusGameStorage L1024-1028:** `setPacked(data, LEVEL_COUNT_SHIFT, MASK_24, ...)` -- 24-bit field at shift 24. CORRECT.
- **DegenerusGameStorage L1030-1033:** `setPacked(data, FROZEN_UNTIL_LEVEL_SHIFT, MASK_24, ...)` -- 24-bit field at shift 128. CORRECT.
- **DegenerusGameStorage L1037-1039:** `setPacked(data, WHALE_BUNDLE_TYPE_SHIFT, 3, ...)` -- 2-bit field at shift 152 with mask=3 (not MASK_24). CORRECT -- bundle type is 2 bits, mask of 3 = 0b11.
- **DegenerusGameStorage L1044-1047:** `setPacked(data, LAST_LEVEL_SHIFT, MASK_24, ...)` -- 24-bit field at shift 0. CORRECT.
- **DegenerusGameMintModule L214-273:** All use correct shift/mask pairs. Verified each call. CORRECT.
- **DegenerusGameWhaleModule L253-256:** `setPacked(data, LEVEL_COUNT_SHIFT, MASK_24, newLevelCount)` etc. CORRECT.
- **WhaleModule L255:** `setPacked(data, WHALE_BUNDLE_TYPE_SHIFT, 3, 3)` -- sets bundle type to 3 (100-level) with mask=3. CORRECT.
- **DegenerusGameBoonModule L312-315:** `setPacked(data, LEVEL_COUNT_SHIFT, MASK_24, ...)`. CORRECT.

**All callers use correct (shift, mask) pairs. No misuse detected.**

**Verdict: SAFE**

**3. Silent Truncation**

`value & mask` silently clips values exceeding the field width. For example, if a 25-bit value is passed with MASK_24, the top bit is lost. Callers should ensure values fit.

Checking critical callers:
- Level values are uint24 (max 16,777,215) -- fits MASK_24. SAFE.
- Day values are uint32 (max 4,294,967,295) -- fits MASK_32. SAFE.
- Level units are uint16 capped to MASK_16 at MintModule L204-205. SAFE.
- Bundle type is 0, 1, or 3 -- fits mask=3. SAFE.

**Verdict: SAFE**

**4. Large Shift Values**

If `shift >= 256`, then `mask << shift` in Solidity 0.8.x produces 0 (EVM SHL/SHR cap at 255). This means `~(mask << shift)` = `~0` = all ones, so the clear step does nothing, and `(value & mask) << shift` = 0, so the set step does nothing. The function becomes a no-op. No corruption, just silent failure to write.

All defined shifts are max 228. No caller passes dynamic shift values. **No risk.**

**Verdict: SAFE**

**5. Comment Discrepancy: WHALE_BUNDLE_TYPE_SHIFT**

The comment at L59 says "Bit position for whale bundle type (bits 152-154)" but the actual field is 2 bits (152-153), not 3 bits (152-154). The comment suggests 3 bits but the mask used by callers is 3 (= 0b11 = 2 bits).

**Verdict: INFO** -- Comment says "bits 152-154" but actual usage is bits 152-153 (2-bit field with mask=3). Not a bug but could confuse future developers.

#### Cached-Local-vs-Storage Check
Not applicable -- pure function, no storage access.

#### Summary

| Attack Angle | Verdict |
|-------------|---------|
| Field overlap / bleed-through | SAFE |
| Caller (shift, mask) misuse | SAFE |
| Silent truncation | SAFE |
| Large shift values | SAFE |
| Comment discrepancy (L59) | INFO |

---

## GameTimeLib

---

### T-01: GameTimeLib::currentDayIndex (L21-23)

```solidity
function currentDayIndex() internal view returns (uint48) {
    return currentDayIndexAt(uint48(block.timestamp));
}
```

#### Implementation Analysis

Wrapper that casts `block.timestamp` to `uint48` and delegates to `currentDayIndexAt`. The `uint48` type can hold values up to 2^48 - 1 = 281,474,976,710,655, which represents a timestamp in the year ~8.9 million. No practical overflow risk.

#### Attack Analysis

**1. uint48 Truncation of block.timestamp**

`block.timestamp` is `uint256`. Casting to `uint48` discards bits above 48. Current timestamp (~1.74 billion) fits in 31 bits. uint48 handles timestamps until year ~8,919,000. **No practical risk.**

**Verdict: SAFE**

---

### T-02: GameTimeLib::currentDayIndexAt (L31-34)

```solidity
function currentDayIndexAt(uint48 ts) internal pure returns (uint48) {
    uint48 currentDayBoundary = uint48((ts - JACKPOT_RESET_TIME) / 1 days);
    return currentDayBoundary - ContractAddresses.DEPLOY_DAY_BOUNDARY + 1;
}
```

#### Implementation Analysis

1. `ts - JACKPOT_RESET_TIME` (= ts - 82620): Subtracts the 22:57 UTC offset to align day boundaries.
2. `/ 1 days` (= / 86400): Integer division gives the absolute day number since epoch, adjusted for the 22:57 UTC boundary.
3. `- ContractAddresses.DEPLOY_DAY_BOUNDARY + 1`: Offsets to deployment day and makes it 1-indexed.

With `DEPLOY_DAY_BOUNDARY = 0` (from ContractAddresses.sol), the formula simplifies to:
`(ts - 82620) / 86400 + 1`

#### Attack Analysis

**1. Underflow: ts < JACKPOT_RESET_TIME (82620)**

If `ts < 82620` (i.e., before 22:57 UTC on January 1, 1970), the subtraction `ts - JACKPOT_RESET_TIME` underflows. Since this is checked arithmetic in Solidity 0.8.34, it **reverts**.

**Practical risk assessment:**
- `block.timestamp` is currently ~1.74 billion (March 2026). It will NEVER be less than 82620.
- The only way to reach ts < 82620 is via `currentDayIndexAt` called directly with a manual timestamp argument. The only caller passing a manual timestamp is `DegenerusGameStorage::_gameDayIndexAt(uint48 ts)` at L1140.
- Tracing `_gameDayIndexAt` callers: used for historical day lookups. If someone passes ts=0 or very small ts, the function reverts. This is SAFE behavior (revert on invalid input is correct).

**Verdict: SAFE** -- Revert on pre-epoch timestamps is correct behavior.

**2. DEPLOY_DAY_BOUNDARY = 0 Anomaly**

With `DEPLOY_DAY_BOUNDARY = 0`, the formula is `(ts - 82620) / 86400 + 1`. For the current timestamp (~1,742,000,000):
- `(1742000000 - 82620) / 86400 + 1` = `1741917380 / 86400 + 1` = `20161 + 1` = 20162

This means the game starts at "day 20162" relative to Unix epoch. This is clearly a **placeholder value** -- the deploy script patches `DEPLOY_DAY_BOUNDARY` to the actual deploy-day boundary before compilation (as noted in the file comment: "Compile-time constants populated by the deploy script").

If deployed with `DEPLOY_DAY_BOUNDARY = 0`, the day index would be enormous (~20,000+). This is a deployment concern, not a library bug.

**Verdict: SAFE** (deployment pipeline responsibility)

**3. Day Boundary Precision**

At exactly ts = 82620 (22:57:00 UTC, Jan 1 1970):
- `(82620 - 82620) / 86400` = 0 / 86400 = 0
- Day index = 0 - DEPLOY_DAY_BOUNDARY + 1

At ts = 82619 (one second before reset): **REVERTS** (underflow on first ever day, but in practice block.timestamp >> 82620).

At ts = 82620 + 86400 = 169020 (22:57:00 UTC, Jan 2 1970):
- `(169020 - 82620) / 86400` = 86400 / 86400 = 1
- Day index advances by 1. **Correct.**

At ts = 82620 + 86399 = 169019 (22:56:59 UTC, Jan 2 1970):
- `(169019 - 82620) / 86400` = 86399 / 86400 = 0 (truncated)
- Same day as before reset. **Correct -- day doesn't change until exactly 22:57 UTC.**

**Verdict: SAFE** -- Day boundaries work correctly at the 22:57 UTC reset time.

**4. uint48 Division Result**

`uint48((ts - JACKPOT_RESET_TIME) / 1 days)`: The division result for current timestamps is ~20,000. uint48 max is ~2.8 * 10^14. No overflow risk for any practical timestamp.

**Verdict: SAFE**

#### Cached-Local-vs-Storage Check
Not applicable -- pure/view functions, no storage access.

#### Summary

| Attack Angle | Verdict |
|-------------|---------|
| Underflow (ts < 82620) | SAFE (correct revert) |
| DEPLOY_DAY_BOUNDARY = 0 | SAFE (deploy script patches) |
| Day boundary precision | SAFE |
| uint48 overflow | SAFE |

---

## JackpotBucketLib

---

### J-01: JackpotBucketLib::traitBucketCounts (L36-51)

```solidity
function traitBucketCounts(uint256 entropy) internal pure returns (uint16[4] memory counts) {
    uint16[4] memory base;
    base[0] = 25; base[1] = 15; base[2] = 8; base[3] = 1;
    uint8 offset = uint8(entropy & 3);
    for (uint8 i; i < 4; ) {
        counts[i] = base[(i + offset) & 3];
        unchecked { ++i; }
    }
}
```

#### Attack Analysis

**1. Rotation Fairness**

`entropy & 3` produces values 0-3. For each offset:
- offset=0: counts = [25, 15, 8, 1] (base order)
- offset=1: counts = [15, 8, 1, 25]
- offset=2: counts = [8, 1, 25, 15]
- offset=3: counts = [1, 25, 15, 8]

Each bucket position gets each base count exactly once across the 4 rotations. The rotation is a cyclic permutation. **Fair.**

However, the entropy source determines which rotation is used. If `entropy & 3` is not uniformly distributed, some rotations occur more than others. Since entropy comes from VRF (uniform random), `entropy & 3` is uniform. **SAFE.**

**2. Solo Bucket Identification**

The solo bucket (count=1) rotates with the offset. Bucket 3 gets count=1 at offset=0, bucket 0 at offset=1, etc. The `soloBucketIndex` function must be consistent with this. Verifying below in J-07.

**Verdict: SAFE**

---

### J-02: JackpotBucketLib::scaleTraitBucketCountsWithCap (L55-95)

#### Attack Analysis

**1. Scaling Precision at Boundaries**

**At ethPool = 10 ETH (JACKPOT_SCALE_MIN_WEI):**
- Falls into `ethPool < JACKPOT_SCALE_FIRST_WEI` (10 < 50).
- range = 50e18 - 10e18 = 40e18
- progress = 10e18 - 10e18 = 0
- scaleBps = 10000 + (0 * 10000) / 40e18 = 10000 (1x, no scaling)
- Since scaleBps == JACKPOT_SCALE_BASE_BPS, the scaling loop is skipped.
- **CORRECT: exactly at threshold = no scaling.**

**At ethPool = 9.99 ETH:**
- Falls into `ethPool < JACKPOT_SCALE_MIN_WEI` early return. No scaling.
- **CORRECT.**

**At ethPool = 50 ETH (JACKPOT_SCALE_FIRST_WEI):**
- Falls into `ethPool < JACKPOT_SCALE_SECOND_WEI` (50 < 200).
- range = 200e18 - 50e18 = 150e18
- progress = 50e18 - 50e18 = 0
- scaleBps = 20000 + (0 * (maxScaleBps - 20000)) / 150e18 = 20000 (2x)
- **CORRECT: exactly at first target = 2x.**

**At ethPool = 200 ETH (JACKPOT_SCALE_SECOND_WEI):**
- Falls into else branch.
- scaleBps = maxScaleBps.
- **CORRECT: at cap = max scale.**

**Transition continuity at 50 ETH:**
- From below: scaleBps approaches 20000 as ethPool approaches 50e18.
- From above: scaleBps starts at 20000.
- **CONTINUOUS. No jump.**

**2. Solo Bucket Protection**

L81-82: `if (baseCount > 1)` -- only scales buckets with count > 1. Solo bucket (count=1) is never scaled. **CORRECT.**

**3. Scaled Value Safety**

L84: `if (scaled < baseCount) scaled = baseCount` -- prevents scaling from reducing counts (would only happen if scaleBps < 10000, which the logic prevents).
L85: `if (scaled > type(uint16).max) scaled = type(uint16).max` -- caps at 65535. With max base count of 25 and max reasonable maxScaleBps (say 40000 = 4x), max scaled = 25 * 40000 / 10000 = 100. uint16 easily holds this. The cap is defensive. **SAFE.**

**4. Return Path**

After scaling, calls `capBucketCounts(counts, maxTotal, entropy)`. Analyzed in J-05.

**Verdict: SAFE**

---

### J-03: JackpotBucketLib::bucketCountsForPoolCap (L98-107)

Convenience wrapper: returns zeros for ethPool=0, otherwise calls traitBucketCounts then scaleTraitBucketCountsWithCap. **Trivially correct.** The zero check at L104 ensures empty pools don't trigger unnecessary computation.

**Verdict: SAFE**

---

### J-04: JackpotBucketLib::sumBucketCounts (L110-112)

```solidity
function sumBucketCounts(uint16[4] memory counts) internal pure returns (uint256 total) {
    total = uint256(counts[0]) + counts[1] + counts[2] + counts[3];
}
```

Sum of 4 uint16 values. Max possible = 4 * 65535 = 262140. Stored in uint256. **No overflow possible.**

**Verdict: SAFE**

---

### J-05: JackpotBucketLib::capBucketCounts (L115-203)

This is the most complex function. Detailed analysis:

#### Implementation Analysis

**Case 1: maxTotal = 0 (L121-127)**
Sets all counts to 0. **CORRECT.**

**Case 2: total = 0 (L130-136)**
All counts already 0. Sets all to 0 (redundant but harmless). **CORRECT.**

**Case 3: maxTotal = 1 (L137-144)**
Zeros all buckets, then sets the solo bucket index to 1. Uses `soloBucketIndex(entropy)` to determine which bucket is the solo. **CORRECT.**

**Case 4: total <= maxTotal (L145)**
No capping needed. Returns as-is. **CORRECT.**

**Case 5: total > maxTotal (L147+)** -- the complex path.

1. `nonSoloCap = maxTotal - 1` (reserve 1 for solo bucket)
2. `nonSoloTotal = total - 1` (subtract the solo bucket's count of 1)
3. For each bucket with count > 1: `scaled = (bucketCount * nonSoloCap) / nonSoloTotal`, minimum 1
4. Sum `scaledTotal`
5. If `scaledTotal > nonSoloCap`: trim by zeroing smallest buckets using entropy-driven rotation
6. If `scaledTotal < nonSoloCap`: distribute remainder to non-solo buckets

#### Attack Analysis

**1. Trim Loop Exhaustion (scaledTotal > nonSoloCap)**

The trim loop (L170-181) iterates exactly 4 times. It can zero out at most 3 buckets (those with `capped[idx] == 1 && counts[idx] > 1` -- meaning non-solo buckets that were scaled down to the minimum of 1).

**Worst case analysis:**
- 3 non-solo buckets (counts > 1) each get minimum scaled value of 1.
- scaledTotal = 3 (from non-solo minimums).
- nonSoloCap could be as low as 1 (maxTotal = 2).
- excess = 3 - 1 = 2.
- Trim loop zeros 2 of the 3 non-solo buckets (those with capped==1).
- scaledTotal drops by 2, now equals 1. Equals nonSoloCap. **SUCCESS.**

**Can excess exceed 3?** With 3 non-solo buckets each at minimum 1, scaledTotal = 3. nonSoloCap minimum is 1. So excess max = 3 - 1 = 2. The loop can handle this (zeros 2 of 3 eligible buckets).

What if 2 non-solo buckets? scaledTotal min = 2, nonSoloCap min = 1, excess = 1. Trim zeros 1 bucket. **OK.**

What if some non-solo buckets have scaled > 1? Then they're NOT eligible for trimming (condition `capped[idx] == 1`). But if they're larger, scaledTotal is larger too... Let me think about this more carefully.

The minimum guarantee (`if (scaled == 0) scaled = 1` at L155) only fires when `bucketCount * nonSoloCap < nonSoloTotal`. This happens when the bucket's proportion is less than 1/nonSoloCap. The number of buckets that can hit this minimum depends on the distribution.

**Can the trim loop fail to drain all excess?**

The trim loop only zeros buckets where `capped[idx] == 1 && counts[idx] > 1`. If a non-solo bucket was scaled to 2 or higher, it's NOT zeroed by the trim loop. But it also contributed more to scaledTotal.

The key insight: the minimum guarantee means each non-solo bucket contributes at least 1 to scaledTotal. With 3 non-solo buckets, scaledTotal >= 3. If nonSoloCap = 1, excess = 2. The loop can zero at most the buckets with capped==1. If all 3 have capped==1, it zeros 2 (with excess=2), leaving 1. **Works.**

If 2 have capped==1 and 1 has capped==2: scaledTotal = 2*1 + 2 = 4. excess = 4 - 1 = 3. Trim zeros 2 (the ones with capped==1). scaledTotal drops to 4-2=2. But nonSoloCap=1, so excess=1 remains. **THE TRIM LOOP FAILS TO FULLY DRAIN.**

**Wait.** Let me re-check. After zeroing a bucket, the loop decrements `excess`. Starting excess=3:
- Zero first eligible: excess becomes 2
- Zero second eligible: excess becomes 1
- Third bucket has capped==2, not eligible. Loop ends with excess=1 remaining.

**BUT:** Is this scenario actually reachable? Let me check if `capped[idx]==2` AND `capped[other]==1` can happen simultaneously when nonSoloCap=1.

With nonSoloCap=1: `scaled = (bucketCount * 1) / nonSoloTotal`. For any bucketCount, this gives 0 or 1 (since bucketCount <= nonSoloTotal for non-solo). Floored to 0, then minimum 1. So ALL non-solo buckets get capped==1 when nonSoloCap=1.

scaledTotal = 3 (all non-solo buckets at 1). excess = 3 - 1 = 2. All 3 are eligible for trim. Loop zeros 2. scaledTotal = 1 = nonSoloCap. **WORKS.**

**What about nonSoloCap=2?**
`scaled = (bucketCount * 2) / nonSoloTotal`. With base counts [25,15,8] (non-solo) and nonSoloTotal=48:
- 25: scaled = 50/48 = 1
- 15: scaled = 30/48 = 0 -> minimum 1
- 8: scaled = 16/48 = 0 -> minimum 1
scaledTotal = 3. excess = 3 - 2 = 1. All 3 have capped==1 and counts > 1. Loop zeros 1. scaledTotal = 2 = nonSoloCap. **WORKS.**

**General case proof:** When scaledTotal > nonSoloCap, every non-solo bucket with capped==1 is eligible for zeroing. The number of such buckets is at least (scaledTotal - nonSoloCap) because:
- Each non-solo bucket contributes >= 1 to scaledTotal
- If k buckets have capped==1, they contribute exactly k to scaledTotal
- The remaining (3-k) buckets each contribute >= 2
- scaledTotal >= k + 2*(3-k) = 6-k
- For trim to fail: excess > k, meaning scaledTotal - nonSoloCap > k
- scaledTotal >= 6-k, so 6-k - nonSoloCap > k, meaning 6 - nonSoloCap > 2k, meaning k < (6 - nonSoloCap)/2
- But nonSoloCap >= 1 (since maxTotal >= 2 for this path), so k < 2.5, i.e., k <= 2
- With k=2: scaledTotal >= 6-2=4, non-solo with capped>=2 contributes >=2. So scaledTotal = 2 + capped_large. nonSoloCap >= 1. excess = 2+capped_large - nonSoloCap. Trim zeroes 2 buckets, reducing scaledTotal by 2. New scaledTotal = capped_large. For this to still exceed nonSoloCap: capped_large > nonSoloCap.
  - capped_large = (bucketCount * nonSoloCap) / nonSoloTotal. Max bucketCount for non-solo = 25. nonSoloTotal >= 48. capped_large = (25 * nonSoloCap) / 48. For capped_large > nonSoloCap: 25/48 > 1? NO. 25/48 < 1, so capped_large < nonSoloCap.

**Therefore: after trimming all eligible buckets (capped==1), the remaining scaledTotal (from capped>=2 buckets) is always <= nonSoloCap.** The trim loop ALWAYS succeeds.

**Verdict: SAFE** -- The trim loop is mathematically guaranteed to reduce scaledTotal to <= nonSoloCap.

**2. Remainder Distribution**

L186-200: When scaledTotal < nonSoloCap, remainder is distributed round-robin to non-solo buckets (capped > 1). The entropy-driven offset ensures fairness.

**Can remainder exceed the number of non-solo buckets?** With 3 non-solo buckets, each can receive +1 per loop iteration. The loop runs exactly 4 times. If remainder > 3 (more slots than non-solo buckets exist), only 3 can receive +1 per pass, but the loop only runs 4 times total. Since non-solo buckets have capped >= 2, they're eligible. But with only 4 iterations, max remainder distributable = 3 (can't add to solo bucket).

**Can remainder > 3?** scaledTotal is the sum of 3 non-solo scaled values. Each is at least 1 and at most (25 * nonSoloCap) / nonSoloTotal. The minimum scaledTotal is 3 (all at 1). nonSoloCap - 3 is the max remainder. For large nonSoloCap and base counts [25,15,8], the scaling formula distributes proportionally, so remainder is small (rounding error from integer division). Maximum remainder = 3 (one for each non-solo bucket). The loop handles up to 3 additions in 4 iterations. **SAFE.**

**Actually, can remainder > 3?** Consider nonSoloCap = 100, nonSoloTotal = 48. scaled[25] = (25*100)/48 = 52. scaled[15] = (15*100)/48 = 31. scaled[8] = (8*100)/48 = 16. scaledTotal = 52+31+16 = 99. remainder = 100-99 = 1. With proportional scaling, remainder is always small (at most 2 due to integer truncation rounding down). **SAFE.**

**Verdict: SAFE**

**3. Solo Bucket Count Assumption**

The function assumes exactly one bucket has count=1 (the solo bucket). If called with counts where no bucket has count=1, the logic breaks:
- `nonSoloTotal = total - 1` subtracts 1 regardless
- All buckets would be scaled as non-solo (count > 1 check)

**However:** `capBucketCounts` is only called from `scaleTraitBucketCountsWithCap` (L94), which operates on output from `traitBucketCounts`. The base counts are always [25,15,8,1] rotated, guaranteeing exactly one bucket with count=1. Scaling only affects counts > 1, so the solo bucket remains 1. **SAFE by caller guarantee.**

**Verdict: SAFE**

---

### J-06: JackpotBucketLib::bucketShares (L211-237)

```solidity
function bucketShares(
    uint256 pool,
    uint16[4] memory shareBps,
    uint16[4] memory bucketCounts,
    uint8 remainderIdx,
    uint256 unit
) internal pure returns (uint256[4] memory shares)
```

#### Attack Analysis

**1. Conservation: distributed + remainder == pool?**

L218-235: For each non-remainder bucket (i != remainderIdx):
- `share = (pool * shareBps[i]) / 10000`
- If count != 0 and unit != 0: `share = (share / unitBucket) * unitBucket` (round down to unit multiple)
- `distributed += share` (note: adds share even when count==0, but share is computed as (pool * shareBps[i]) / 10000 regardless)

**Wait -- L229-230:** `if (count != 0) { shares[i] = share; }` and `distributed += share;` is OUTSIDE the if block at L230.

Let me re-read:
```
if (i != remainderIdx) {
    uint16 count = bucketCounts[i];
    uint256 share = (pool * shareBps[i]) / 10_000;
    if (count != 0) {
        if (unit != 0) {
            uint256 unitBucket = unit * count;
            share = (share / unitBucket) * unitBucket;
        }
        shares[i] = share;
    }
    distributed += share;  // <-- ALWAYS adds to distributed, even when count==0
}
```

When `count == 0` for a non-remainder bucket: `share = (pool * shareBps[i]) / 10000` is computed but NOT stored in `shares[i]`. But it IS added to `distributed`. Then `shares[remainderIdx] = pool - distributed`.

This means: when a bucket has count==0, its BPS share is subtracted from the remainder bucket but NOT awarded to anyone. **The pool is underallocated.**

**Is this a bug?** When bucketCounts[i] == 0, there are no winners in that bucket, so the share should go to... the remainder? Let me check: `distributed` includes the dead share, so `shares[remainderIdx] = pool - distributed` gets LESS. The dead share is lost.

**Caller context:** `capBucketCounts` can zero out some buckets (trim loop L172-173 sets `capped[idx] = 0`). When this happens, `bucketShares` allocates a share to that bucket via BPS but doesn't store it, and doesn't redirect it to the remainder. The ETH/COIN for that bucket effectively vanishes from the distribution.

**Wait.** Let me re-examine. When count==0:
- share is computed from BPS
- share is NOT stored in shares[i] (shares[i] remains 0)
- share IS added to distributed
- remainder = pool - distributed (smaller because of the dead share)

So the total actually distributed = sum(shares[0..3]) = shares of non-zero-count buckets + shares[remainderIdx]. Which = pool - dead_shares. **Some pool funds are not distributed.**

**BUT:** How much? In the trim scenario with very small maxTotal (e.g., maxTotal=2): one solo bucket gets 1 winner, potentially 2 non-solo buckets get zeroed. Their combined BPS share (e.g., 10% + 5% = 15% of pool) would be lost.

**Verdict: INVESTIGATE** -- When capBucketCounts zeros out non-solo buckets (the trim path), bucketShares does not redistribute their BPS allocation to the remainder. Pool funds may be under-distributed.

**2. Unit Rounding Overflow**

L225-226: `unitBucket = unit * count`. If unit and count are both large, this could overflow uint256. In practice, `unit` is `PriceLookupLib.priceForLevel(lvl+1) >> 2` (max ~0.06 ETH = 6e16 wei) and `count` is at most ~100 (after scaling). Product max ~ 6e18. No uint256 overflow risk. **SAFE.**

**3. BPS Sum != 10000**

If `sum(shareBps[0..3]) != 10000`, the share computation is incorrect. However, the BPS values come from `shareBpsByBucket` which unpacks a packed uint64. The packing is done during contract deployment and is assumed correct. **SAFE (deployment responsibility).**

**4. Zero Pool**

If `pool == 0`, all shares are 0, distributed = 0, shares[remainderIdx] = 0. **CORRECT.**

#### Summary

| Attack Angle | Verdict |
|-------------|---------|
| Pool conservation (zeroed buckets) | INVESTIGATE |
| Unit rounding overflow | SAFE |
| BPS sum invariant | SAFE (deployment) |
| Zero pool | SAFE |

---

### J-07: JackpotBucketLib::soloBucketIndex (L240-242)

```solidity
function soloBucketIndex(uint256 entropy) internal pure returns (uint8) {
    return uint8((uint256(3) - (entropy & 3)) & 3);
}
```

#### Attack Analysis

**1. Consistency with traitBucketCounts Rotation**

In `traitBucketCounts`, with offset = `entropy & 3`:
- The solo bucket (base count = 1) is at base index 3.
- After rotation: position of count=1 is at `(3 + (4 - offset)) & 3` = `(3 - offset) & 3`.

Wait, let me trace: `counts[i] = base[(i + offset) & 3]`. For counts[i] to be 1, we need `(i + offset) & 3 == 3`, i.e., `i = (3 - offset) & 3`.

`soloBucketIndex` returns `(3 - (entropy & 3)) & 3` = `(3 - offset) & 3`. **MATCHES.**

**Verdict: SAFE** -- soloBucketIndex correctly identifies the solo bucket for any entropy value.

---

### J-08: JackpotBucketLib::rotatedShareBps (L245-248)

```solidity
function rotatedShareBps(uint64 packed, uint8 offset, uint8 traitIdx) internal pure returns (uint16) {
    uint8 baseIndex = uint8((uint256(traitIdx) + uint256(offset) + 1) & 3);
    return uint16(packed >> (baseIndex * 16));
}
```

#### Attack Analysis

**1. Bit Extraction Correctness**

The packed uint64 contains 4 x uint16 values at positions [0-15], [16-31], [32-47], [48-63]. `packed >> (baseIndex * 16)` shifts to the target slot, then `uint16()` truncates to 16 bits. **CORRECT for baseIndex 0-3.**

**2. Index Range**

`(traitIdx + offset + 1) & 3` always produces 0-3. The `& 3` mask guarantees this. `baseIndex * 16` is max 48. Shifting uint64 by 48 produces a 16-bit value. **SAFE.**

**3. The +1 Offset**

The `+1` in the formula creates an asymmetry. For traitIdx=0, offset=0: baseIndex = 1 (not 0). This means the rotation doesn't start at the "natural" position. This is a design choice for fairness distribution, not a bug.

**Verdict: SAFE**

---

### J-09: JackpotBucketLib::shareBpsByBucket (L251-257)

Wrapper that calls `rotatedShareBps` for each of 4 buckets. Unchecked loop increment (gas optimization). **Trivially correct** given J-08.

**Verdict: SAFE**

---

### J-10: JackpotBucketLib::packWinningTraits (L264-266)

```solidity
function packWinningTraits(uint8[4] memory traits) internal pure returns (uint32 packed) {
    packed = uint32(traits[0]) | (uint32(traits[1]) << 8) | (uint32(traits[2]) << 16) | (uint32(traits[3]) << 24);
}
```

4 x uint8 packed into uint32 at positions [0-7], [8-15], [16-23], [24-31]. Each trait is 0-255 (uint8), fitting perfectly in 8 bits. No overlap. **CORRECT.**

**Verdict: SAFE**

---

### J-11: JackpotBucketLib::unpackWinningTraits (L269-274)

```solidity
traits[0] = uint8(packed);
traits[1] = uint8(packed >> 8);
traits[2] = uint8(packed >> 16);
traits[3] = uint8(packed >> 24);
```

Inverse of packWinningTraits. `uint8()` cast truncates to lower 8 bits after shift. **CORRECT roundtrip: unpack(pack(x)) == x for all valid inputs.**

**Verdict: SAFE**

---

### J-12: JackpotBucketLib::getRandomTraits (L278-283)

```solidity
function getRandomTraits(uint256 rw) internal pure returns (uint8[4] memory w) {
    w[0] = uint8(rw & 0x3F);            // Quadrant 0: 0-63
    w[1] = 64 + uint8((rw >> 6) & 0x3F); // Quadrant 1: 64-127
    w[2] = 128 + uint8((rw >> 12) & 0x3F); // Quadrant 2: 128-191
    w[3] = 192 + uint8((rw >> 18) & 0x3F); // Quadrant 3: 192-255
}
```

#### Attack Analysis

**1. Range Correctness**

- `rw & 0x3F` = 0-63. w[0] = 0-63. **Quadrant 0: CORRECT.**
- `(rw >> 6) & 0x3F` = 0-63. w[1] = 64-127. **Quadrant 1: CORRECT.**
- `(rw >> 12) & 0x3F` = 0-63. w[2] = 128-191. **Quadrant 2: CORRECT.**
- `(rw >> 18) & 0x3F` = 0-63. w[3] = 192-255. **Quadrant 3: CORRECT.**

Each quadrant covers 64 values. 4 quadrants x 64 = 256 values, covering the full uint8 range 0-255. No overlap between quadrants. **CORRECT.**

**2. Addition Overflow**

`64 + uint8(...)`: uint8 max is 255. 64 + 63 = 127. Fits in uint8. **SAFE.**
`128 + uint8(...)`: 128 + 63 = 191. Fits in uint8. **SAFE.**
`192 + uint8(...)`: 192 + 63 = 255. Fits in uint8. **SAFE.**

**3. Entropy Bit Independence**

Each quadrant uses 6 non-overlapping bits from rw: bits [0-5], [6-11], [12-17], [18-23]. Total: 24 bits consumed. The remaining 232 bits of rw are unused. The 4 trait values are independent (drawn from different bit regions). **CORRECT.**

**4. Bias**

Each quadrant extracts 6 bits, giving 64 equally likely outcomes per quadrant. With VRF-seeded entropy, the distribution is uniform within each quadrant. **No bias.**

**Verdict: SAFE**

---

### J-13: JackpotBucketLib::bucketOrderLargestFirst (L290-306)

```solidity
function bucketOrderLargestFirst(uint16[4] memory counts) internal pure returns (uint8[4] memory order) {
    uint8 largestIdx;
    uint16 largestCount = counts[0];
    for (uint8 i = 1; i < 4; ++i) {
        if (counts[i] > largestCount) {
            largestCount = counts[i];
            largestIdx = i;
        }
    }
    order[0] = largestIdx;
    uint8 k = 1;
    for (uint8 i; i < 4; ++i) {
        if (i != largestIdx) {
            order[k++] = i;
        }
    }
}
```

#### Attack Analysis

**1. Sorting Completeness**

This function does NOT fully sort. It only finds the LARGEST bucket and puts it first. The remaining 3 buckets are in their original index order (not sorted by count). The function name says "largest first" which is accurate -- it's not "sort descending."

**2. Tie Breaking**

`if (counts[i] > largestCount)` -- strictly greater. If two buckets tie for largest, the FIRST one (lower index) wins. This is deterministic and consistent. **CORRECT for documented behavior.**

**3. All Indices Appear**

order[0] = largestIdx. Then for i in 0..3, if i != largestIdx, order[k++] = i. This produces exactly 4 entries covering all indices 0-3. **CORRECT.**

**4. Edge Case: All Equal**

If counts = [10, 10, 10, 10]: largestIdx = 0 (first match). order = [0, 1, 2, 3]. **CORRECT** -- tie goes to lowest index.

**5. Edge Case: All Zero**

counts = [0, 0, 0, 0]: largestIdx = 0. order = [0, 1, 2, 3]. **CORRECT.**

**Verdict: SAFE**

---

## PriceLookupLib

---

### P-01: PriceLookupLib::priceForLevel (L21-46)

```solidity
function priceForLevel(uint24 targetLevel) internal pure returns (uint256) {
    if (targetLevel < 5) return 0.01 ether;
    if (targetLevel < 10) return 0.02 ether;
    if (targetLevel < 30) return 0.04 ether;
    if (targetLevel < 60) return 0.08 ether;
    if (targetLevel < 90) return 0.12 ether;
    if (targetLevel < 100) return 0.16 ether;

    uint256 cycleOffset = targetLevel % 100;

    if (cycleOffset == 0) {
        return 0.24 ether;
    } else if (cycleOffset < 30) {
        return 0.04 ether;
    } else if (cycleOffset < 60) {
        return 0.08 ether;
    } else if (cycleOffset < 90) {
        return 0.12 ether;
    } else {
        return 0.16 ether;
    }
}
```

#### Attack Analysis

**1. Boundary Correctness**

| Level | Expected | Code Path | Actual | Match? |
|-------|----------|-----------|--------|--------|
| 0 | 0.01 ETH | `< 5` | 0.01 ETH | YES |
| 4 | 0.01 ETH | `< 5` | 0.01 ETH | YES |
| 5 | 0.02 ETH | `< 10` | 0.02 ETH | YES |
| 9 | 0.02 ETH | `< 10` | 0.02 ETH | YES |
| 10 | 0.04 ETH | `< 30` | 0.04 ETH | YES |
| 29 | 0.04 ETH | `< 30` | 0.04 ETH | YES |
| 30 | 0.08 ETH | `< 60` | 0.08 ETH | YES |
| 59 | 0.08 ETH | `< 60` | 0.08 ETH | YES |
| 60 | 0.12 ETH | `< 90` | 0.12 ETH | YES |
| 89 | 0.12 ETH | `< 90` | 0.12 ETH | YES |
| 90 | 0.16 ETH | `< 100` | 0.16 ETH | YES |
| 99 | 0.16 ETH | `< 100` | 0.16 ETH | YES |
| 100 | 0.24 ETH | `% 100 == 0` | 0.24 ETH | YES |
| 101 | 0.04 ETH | `% 100 < 30` | 0.04 ETH | YES |
| 129 | 0.04 ETH | `% 100 < 30` | 0.04 ETH | YES |
| 130 | 0.08 ETH | `% 100 < 60` | 0.08 ETH | YES |
| 200 | 0.24 ETH | `% 100 == 0` | 0.24 ETH | YES |
| 299 | 0.16 ETH | `% 100 >= 90` | 0.16 ETH | YES |
| 300 | 0.24 ETH | `% 100 == 0` | 0.24 ETH | YES |

**All boundaries correct. No off-by-one errors.**

**2. First Cycle vs Repeating Cycle Transition**

Levels 10-29 in the first cycle use the `< 30` check (returning 0.04 ETH). This is the same price as the repeating cycle's x01-x29 tier. No discontinuity.

Level 10 is NOT a milestone (milestones are at x00 for levels >= 100). Level 10 correctly returns 0.04 ETH. **CORRECT.**

**3. uint24 Maximum**

`uint24 max = 16777215`. `16777215 % 100 = 15`. Falls into `cycleOffset < 30`, returns 0.04 ETH. **Valid -- no edge case issue.**

**4. Level 0**

Returns 0.01 ETH. This is the cheapest possible price. Used correctly by callers for the first purchase. **CORRECT.**

**5. Completeness of if/else Chain**

The first 6 checks cover levels 0-99 exhaustively. The remaining code handles levels >= 100 via cycleOffset:
- `== 0`: milestone
- `< 30`: early
- `< 60`: mid
- `< 90`: late
- `else`: final (covers 90-99)

All values of cycleOffset (0-99) are covered. **No unreachable or missing paths.**

**6. Caller Misuse: Level Parameter Trust**

Callers pass `uint24` level values. The function returns a valid price for ANY uint24 input. No caller validation needed. **SAFE.**

#### Cached-Local-vs-Storage Check
Not applicable -- pure function, no storage access.

#### Summary

| Attack Angle | Verdict |
|-------------|---------|
| Boundary correctness | SAFE |
| Cycle transition | SAFE |
| uint24 max | SAFE |
| Level 0 | SAFE |
| Code path completeness | SAFE |
| Caller misuse | SAFE |

---

## Findings Summary

### INVESTIGATE Findings

| ID | Finding | Library | Severity Estimate |
|----|---------|---------|-------------------|
| LIB-01 | entropyStep(0) = 0 fixed point | EntropyLib | LOW (negligible VRF probability) |
| LIB-02 | bucketShares: zeroed-bucket BPS share lost from distribution | JackpotBucketLib | MEDIUM (pool under-distribution when buckets trimmed) |

### INFO Findings

| ID | Finding | Library |
|----|---------|---------|
| LIB-I1 | Comment discrepancy: WHALE_BUNDLE_TYPE_SHIFT says "bits 152-154" but field is 2 bits (152-153) | BitPackingLib |

### SAFE Functions (No Findings)

All 18 functions analyzed. 16 functions are fully SAFE with no findings. 2 functions have INVESTIGATE findings (E-01, J-06).

### Coverage Confirmation

| Library | Functions Analyzed | Complete? |
|---------|-------------------|-----------|
| EntropyLib | 1/1 | YES |
| BitPackingLib | 1/1 (+11 constants) | YES |
| GameTimeLib | 2/2 (+1 constant) | YES |
| JackpotBucketLib | 13/13 (+5 constants) | YES |
| PriceLookupLib | 1/1 | YES |
| **TOTAL** | **18/18** | **100%** |
