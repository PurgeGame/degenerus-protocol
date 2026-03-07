# JackpotBucketLib.sol -- Exhaustive Function-Level Audit

**File:** `contracts/libraries/JackpotBucketLib.sol`
**Lines:** 307 (including comments/whitespace)
**Functions:** 13 internal pure functions
**Constants:** 5 (JACKPOT_SCALE_MIN_WEI, JACKPOT_SCALE_FIRST_WEI, JACKPOT_SCALE_SECOND_WEI, JACKPOT_SCALE_BASE_BPS, JACKPOT_SCALE_FIRST_BPS)
**Pragma:** solidity 0.8.34
**License:** AGPL-3.0-only

All functions are `internal pure` -- they are inlined by the compiler at call sites (zero CALL overhead). The library is not deployed as a separate contract.

---

## Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `JACKPOT_SCALE_MIN_WEI` | 10 ether | Pool threshold below which no scaling occurs |
| `JACKPOT_SCALE_FIRST_WEI` | 50 ether | Pool size where scale reaches 2x (20000 BPS) |
| `JACKPOT_SCALE_SECOND_WEI` | 200 ether | Pool size where scale reaches maxScaleBps (cap) |
| `JACKPOT_SCALE_BASE_BPS` | 10,000 | 1x in basis points (no scaling) |
| `JACKPOT_SCALE_FIRST_BPS` | 20,000 | 2x in basis points |

---

## Function Audit

### Category: Bucket Count Functions

---

### `traitBucketCounts(uint256 entropy)` [internal pure]

| Field | Value |
|-------|-------|
| **Signature** | `function traitBucketCounts(uint256 entropy) internal pure returns (uint16[4] memory counts)` |
| **Visibility** | internal |
| **Mutability** | pure |
| **Parameters** | `entropy` (uint256): VRF-derived randomness word used for rotation |
| **Returns** | `counts` (uint16[4]): Winner counts for each of 4 trait buckets |

**Logic Flow:**
1. Creates base array `[25, 15, 8, 1]` representing Large, Mid, Small, Solo bucket sizes.
2. Extracts rotation offset from `entropy & 3` (bottom 2 bits, values 0-3).
3. Rotates bucket assignments: `counts[i] = base[(i + offset) & 3]`.

**Rotation Analysis:**
- `offset=0`: counts = [25, 15, 8, 1] (base order)
- `offset=1`: counts = [15, 8, 1, 25] (shifted left by 1)
- `offset=2`: counts = [8, 1, 25, 15] (shifted left by 2)
- `offset=3`: counts = [1, 25, 15, 8] (shifted left by 3)

Each bucket index receives each base count exactly once across the 4 entropy values. This ensures fairness -- no trait quadrant is permanently advantaged.

**Callers:** `bucketCountsForPoolCap` (line 105), `_runJackpotEthFlow` in JackpotModule (line 1341)
**Callees:** None

**Invariants:**
- Sum of returned counts is always 49 (25+15+8+1)
- Exactly one bucket has count 1 (solo)
- Exactly one bucket has count 25, one has 15, one has 8

**NatSpec Accuracy:** Accurate. States base counts are rotated by entropy bottom 2 bits.
**Gas Flags:** None. Memory-only operations, loop is 4 iterations with unchecked increment.
**Verdict:** CORRECT

---

### `scaleTraitBucketCountsWithCap(uint16[4] memory baseCounts, uint256 ethPool, uint256 entropy, uint16 maxTotal, uint32 maxScaleBps)` [internal pure]

| Field | Value |
|-------|-------|
| **Signature** | `function scaleTraitBucketCountsWithCap(uint16[4] memory baseCounts, uint256 ethPool, uint256 entropy, uint16 maxTotal, uint32 maxScaleBps) internal pure returns (uint16[4] memory counts)` |
| **Visibility** | internal |
| **Mutability** | pure |
| **Parameters** | `baseCounts` (uint16[4]): Base bucket counts from traitBucketCounts; `ethPool` (uint256): Current ETH pool size; `entropy` (uint256): Randomness for cap distribution; `maxTotal` (uint16): Maximum total winners allowed; `maxScaleBps` (uint32): Maximum scale in basis points (e.g., 40000 = 4x) |
| **Returns** | `counts` (uint16[4]): Scaled and capped bucket counts |

**Logic Flow:**
1. Copy baseCounts to counts.
2. If `ethPool < 10 ETH`: return unscaled (early return).
3. Compute `scaleBps` via piecewise linear interpolation:
   - `[10, 50) ETH`: linearly interpolate from 10000 (1x) to 20000 (2x)
   - `[50, 200) ETH`: linearly interpolate from 20000 (2x) to maxScaleBps
   - `>= 200 ETH`: cap at maxScaleBps
4. If `scaleBps != 10000` (i.e., any scaling needed):
   - For each bucket where `baseCount > 1` (skips solo bucket):
     - `scaled = (baseCount * scaleBps) / 10000`
     - Clamp: `if scaled < baseCount` set to baseCount (prevents downscale)
     - Clamp: `if scaled > uint16.max` set to uint16.max (overflow protection)
5. Call `capBucketCounts(counts, maxTotal, entropy)` to enforce total cap.

**Scaling Verification at Key Thresholds (with maxScaleBps=40000):**
- ethPool = 5 ETH: scaleBps not computed (early return), scale = 1x
- ethPool = 10 ETH: scaleBps = 10000 (1x), no-op due to `scaleBps != 10000` check
- ethPool = 30 ETH: progress = 20, range = 40, scaleBps = 10000 + (20 * 10000) / 40 = 15000 (1.5x)
- ethPool = 50 ETH: progress = 0 in second branch, scaleBps = 20000 (2x)
- ethPool = 125 ETH: progress = 75, range = 150, scaleBps = 20000 + (75 * 20000) / 150 = 30000 (3x)
- ethPool = 200+ ETH: scaleBps = 40000 (4x, capped)

**Solo Bucket Protection:** The `baseCount > 1` check ensures the solo bucket (count=1) is never scaled. This preserves the solo winner concept regardless of pool size.

**Overflow Safety:** `uint256(baseCount) * scaleBps` -- baseCount is uint16 (max 65535), scaleBps is uint32 (max ~4B). Product max = 65535 * 4,294,967,295 = ~2.8e14, well within uint256. The uint16.max clamp prevents truncation on downcast.

**Callers:** `bucketCountsForPoolCap` (line 106), `_runJackpotEthFlow` in JackpotModule (line 1344)
**Callees:** `capBucketCounts`

**Invariants:**
- Solo bucket (count=1) is never modified
- Scaled counts are always >= base counts (no downscaling)
- Final total is <= maxTotal (enforced by capBucketCounts)

**NatSpec Accuracy:** Accurate. States "1x under 10 ETH, linearly to 2x by 50 ETH, linearly to maxScaleBps by 200 ETH, then capped."
**Gas Flags:** None. Linear arithmetic, 4-iteration loop with unchecked increment.
**Verdict:** CORRECT

---

### `bucketCountsForPoolCap(uint256 ethPool, uint256 entropy, uint16 maxTotal, uint32 maxScaleBps)` [internal pure]

| Field | Value |
|-------|-------|
| **Signature** | `function bucketCountsForPoolCap(uint256 ethPool, uint256 entropy, uint16 maxTotal, uint32 maxScaleBps) internal pure returns (uint16[4] memory bucketCounts)` |
| **Visibility** | internal |
| **Mutability** | pure |
| **Parameters** | `ethPool` (uint256): Current ETH pool size; `entropy` (uint256): VRF randomness; `maxTotal` (uint16): Maximum total winners; `maxScaleBps` (uint32): Maximum scale BPS |
| **Returns** | `bucketCounts` (uint16[4]): Scaled and capped bucket counts, or all zeros if pool empty |

**Logic Flow:**
1. If `ethPool == 0`: return zero-initialized array (default memory value).
2. Get base counts via `traitBucketCounts(entropy)`.
3. Scale and cap via `scaleTraitBucketCountsWithCap(baseCounts, ethPool, entropy, maxTotal, maxScaleBps)`.

**Callers:** `distributeJackpotFinalDay` in JackpotModule (line 300)
**Callees:** `traitBucketCounts`, `scaleTraitBucketCountsWithCap`

**Invariants:**
- Returns all zeros if and only if ethPool == 0
- For non-zero pool, total winners <= maxTotal

**NatSpec Accuracy:** Accurate. States "returns zeroes when pool is empty."
**Gas Flags:** None. Simple convenience wrapper.
**Verdict:** CORRECT

---

### `sumBucketCounts(uint16[4] memory counts)` [internal pure]

| Field | Value |
|-------|-------|
| **Signature** | `function sumBucketCounts(uint16[4] memory counts) internal pure returns (uint256 total)` |
| **Visibility** | internal |
| **Mutability** | pure |
| **Parameters** | `counts` (uint16[4]): Array of 4 bucket counts |
| **Returns** | `total` (uint256): Sum of all 4 counts |

**Logic Flow:**
1. `total = uint256(counts[0]) + counts[1] + counts[2] + counts[3]`

**Overflow Analysis:** Maximum value = 4 * 65535 = 262,140, which trivially fits in uint256. The explicit cast of `counts[0]` to uint256 ensures the addition is performed in uint256 space, avoiding uint16 overflow on intermediate sums.

**Callers:** `capBucketCounts` (line 129)
**Callees:** None

**Invariants:** Result <= 4 * type(uint16).max = 262,140
**NatSpec Accuracy:** Accurate. Simple and correct.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `capBucketCounts(uint16[4] memory counts, uint16 maxTotal, uint256 entropy)` [internal pure]

| Field | Value |
|-------|-------|
| **Signature** | `function capBucketCounts(uint16[4] memory counts, uint16 maxTotal, uint256 entropy) internal pure returns (uint16[4] memory capped)` |
| **Visibility** | internal |
| **Mutability** | pure |
| **Parameters** | `counts` (uint16[4]): Input bucket counts; `maxTotal` (uint16): Maximum allowed total winners; `entropy` (uint256): Randomness for remainder distribution and trim ordering |
| **Returns** | `capped` (uint16[4]): Capped bucket counts |

**Logic Flow:**

1. Copy counts to capped.
2. **Edge case: maxTotal == 0**: Set all to 0, return.
3. Compute `total = sumBucketCounts(counts)`.
4. **Edge case: total == 0**: Set all to 0, return. (Defensive; shouldn't happen with valid inputs.)
5. **Edge case: maxTotal == 1**: Set all to 0 except `capped[soloBucketIndex(entropy)] = 1`. Return.
6. **No-op case: total <= maxTotal**: Return unchanged.
7. **Proportional scaling:**
   - `nonSoloCap = maxTotal - 1` (reserve 1 for solo)
   - `nonSoloTotal = total - 1` (exclude solo from denominator)
   - For each non-solo bucket (count > 1): `scaled = (count * nonSoloCap) / nonSoloTotal`. Minimum 1.
   - Track `scaledTotal` as sum of scaled non-solo counts.
8. **Excess trimming** (if `scaledTotal > nonSoloCap`):
   - Compute `excess = scaledTotal - nonSoloCap`.
   - Use `entropy >> 24` bottom 2 bits as trim offset.
   - Zero out non-solo buckets with count 1 (smallest) in entropy-rotated order until excess eliminated.
9. **Remainder distribution** (if `scaledTotal < nonSoloCap`):
   - Compute `remainder = nonSoloCap - scaledTotal`.
   - Distribute +1 to non-solo buckets (count > 1) in entropy-rotated order.

**Solo Preservation Analysis:**
- The solo bucket (count==1) is never touched in the scaling loop (guard: `bucketCount > 1`).
- The solo bucket index is determined by `soloBucketIndex(entropy)` only in the maxTotal==1 case.
- In the proportional scaling path, the solo bucket is implicitly preserved because it has count=1, which does not satisfy `count > 1`.
- The nonSoloCap calculation (`maxTotal - 1`) reserves exactly 1 slot for solo.

**Trim/Remainder Entropy Independence:**
- Trim and remainder use `entropy >> 24` bits 24-25, independent of the rotation offset (bits 0-1) used in traitBucketCounts. Good entropy separation.

**Potential Edge Case:** If all 4 buckets have count=1 (no bucket > 1), the scaling loop does nothing, scaledTotal=0, and the remainder loop adds to no buckets (all have count=1, not > 1), leaving all zeros for non-solo. In practice, this never happens because traitBucketCounts always produces exactly one count=1 bucket and three counts > 1.

**Callers:** `scaleTraitBucketCountsWithCap` (line 94)
**Callees:** `sumBucketCounts`, `soloBucketIndex`

**Invariants:**
- Sum of capped <= maxTotal
- Solo bucket (count=1) is preserved at 1 (when maxTotal >= 1)
- When total <= maxTotal, counts are returned unchanged

**NatSpec Accuracy:** Accurate. States "Caps total winners while keeping the solo bucket fixed at 1 when present."
**Gas Flags:** None. Two 4-iteration loops at most. Trim loop short-circuits on excess==0.
**Verdict:** CORRECT

---

### Category: Share & Index Functions

---

### `bucketShares(uint256 pool, uint16[4] memory shareBps, uint16[4] memory bucketCounts, uint8 remainderIdx, uint256 unit)` [internal pure]

| Field | Value |
|-------|-------|
| **Signature** | `function bucketShares(uint256 pool, uint16[4] memory shareBps, uint16[4] memory bucketCounts, uint8 remainderIdx, uint256 unit) internal pure returns (uint256[4] memory shares)` |
| **Visibility** | internal |
| **Mutability** | pure |
| **Parameters** | `pool` (uint256): Total ETH/COIN pool to distribute; `shareBps` (uint16[4]): Basis points share per bucket (must sum to 10000); `bucketCounts` (uint16[4]): Winner counts per bucket; `remainderIdx` (uint8): Bucket index that absorbs rounding dust; `unit` (uint256): Rounding unit (e.g., ticket price / 4) |
| **Returns** | `shares` (uint256[4]): ETH/COIN allocated to each bucket |

**Logic Flow:**
1. Initialize `distributed = 0`.
2. For each bucket `i` (0..3):
   - If `i != remainderIdx`:
     - `share = (pool * shareBps[i]) / 10000`
     - If `count != 0` and `unit != 0`:
       - `unitBucket = unit * count`
       - `share = (share / unitBucket) * unitBucket` (round down to nearest multiple)
     - If `count != 0`: store share; else share remains 0 but still adds to distributed.
     - Add share to `distributed`.
3. `shares[remainderIdx] = pool - distributed` (remainder bucket absorbs all dust).

**Dust Prevention:** The remainder bucket gets `pool - distributed`, which is always >= the BPS-computed share for that bucket (since all other buckets are rounded down). This guarantees: `sum(shares) == pool` exactly. No wei is lost.

**Important Detail:** When `count == 0` for a non-remainder bucket, the share is computed (`pool * shareBps[i] / 10000`) but NOT stored in `shares[i]` (stays 0). However, the share IS still added to `distributed`. This means the remainder bucket effectively absorbs the share of empty non-remainder buckets. This is correct behavior -- if a bucket has zero winners, its allocation flows to the remainder bucket.

**Unit Rounding:** When `unit != 0`, shares are rounded to multiples of `unit * count`. This ensures each winner in the bucket receives a clean multiple of `unit`. The remainder bucket compensates for this rounding.

**Callers:** `_distributeJackpotEth` in JackpotModule (line 1415), `_distributeNormalJackpotEth` in JackpotModule (line 1540)
**Callees:** None

**Invariants:**
- `sum(shares) == pool` (exact, no dust)
- Non-remainder shares are rounded down to `unit * count` multiples
- Remainder share >= its BPS-computed share (absorbs rounding dust)

**NatSpec Accuracy:** Accurate. States "Round non-solo buckets to unit * winnerCount; remainder goes to the override bucket."
**Gas Flags:** None. Single 4-iteration loop. Division operations are unavoidable.
**Verdict:** CORRECT

---

### `soloBucketIndex(uint256 entropy)` [internal pure]

| Field | Value |
|-------|-------|
| **Signature** | `function soloBucketIndex(uint256 entropy) internal pure returns (uint8)` |
| **Visibility** | internal |
| **Mutability** | pure |
| **Parameters** | `entropy` (uint256): VRF randomness |
| **Returns** | `uint8`: Index (0-3) of the solo bucket |

**Logic Flow:**
1. `return uint8((uint256(3) - (entropy & 3)) & 3)`

**Mapping Verification:**
- `entropy & 3 == 0`: (3 - 0) & 3 = 3 & 3 = **3**
- `entropy & 3 == 1`: (3 - 1) & 3 = 2 & 3 = **2**
- `entropy & 3 == 2`: (3 - 2) & 3 = 1 & 3 = **1**
- `entropy & 3 == 3`: (3 - 3) & 3 = 0 & 3 = **0**

Maps {0,1,2,3} -> {3,2,1,0}. This is the reverse mapping, consistent with the rotation in `traitBucketCounts`.

**Consistency with traitBucketCounts:**
- In `traitBucketCounts`, `offset = entropy & 3`, and `counts[i] = base[(i + offset) & 3]`.
- base[3] = 1 (solo). So `counts[i] == 1` when `(i + offset) & 3 == 3`, i.e., `i == (3 - offset) & 3`.
- `soloBucketIndex` returns `(3 - (entropy & 3)) & 3` which equals `(3 - offset) & 3`. Consistent.

**Callers:** `capBucketCounts` (line 142), `_distributeJackpotEth` in JackpotModule (line 1414), `_distributeDgnrsFinalDay` in JackpotModule (line 783), `_distributeNormalJackpotEth` in JackpotModule (line 1536, 1538)
**Callees:** None

**Invariants:** Result is always in range [0, 3]
**NatSpec Accuracy:** Accurate. States "Returns the solo bucket index (receives 60% share)."
**Gas Flags:** None. Single arithmetic expression.
**Verdict:** CORRECT

---

### `rotatedShareBps(uint64 packed, uint8 offset, uint8 traitIdx)` [internal pure]

| Field | Value |
|-------|-------|
| **Signature** | `function rotatedShareBps(uint64 packed, uint8 offset, uint8 traitIdx) internal pure returns (uint16)` |
| **Visibility** | internal |
| **Mutability** | pure |
| **Parameters** | `packed` (uint64): 4 x 16-bit share BPS values packed into uint64; `offset` (uint8): Rotation offset (from entropy); `traitIdx` (uint8): Trait bucket index (0-3) |
| **Returns** | `uint16`: Share BPS for the given trait bucket |

**Logic Flow:**
1. `baseIndex = (traitIdx + offset + 1) & 3`
2. Extract 16 bits: `uint16(packed >> (baseIndex * 16))`

**Bit Layout of packed (uint64):**
- Bits [0-15]: share[0]
- Bits [16-31]: share[1]
- Bits [32-47]: share[2]
- Bits [48-63]: share[3]

**Rotation:** The `+1` in the baseIndex formula shifts the base index, ensuring the rotation is offset by 1 from the trait index. This creates a different rotation pattern than bucket counts, providing independent fairness for shares vs. counts.

**Extraction:** `packed >> (baseIndex * 16)` shifts right, then `uint16()` masks to bottom 16 bits. For baseIndex 0, extracts bits [0-15]; for baseIndex 3, extracts bits [48-63].

**Callers:** `shareBpsByBucket` (line 254)
**Callees:** None

**Invariants:** baseIndex is always in [0,3], so shift is always in {0, 16, 32, 48} -- all valid for uint64.
**NatSpec Accuracy:** Accurate. States "Rotates share BPS based on offset and trait index."
**Gas Flags:** None. Single arithmetic + shift.
**Verdict:** CORRECT

---

### `shareBpsByBucket(uint64 packed, uint8 offset)` [internal pure]

| Field | Value |
|-------|-------|
| **Signature** | `function shareBpsByBucket(uint64 packed, uint8 offset) internal pure returns (uint16[4] memory shares)` |
| **Visibility** | internal |
| **Mutability** | pure |
| **Parameters** | `packed` (uint64): Packed share BPS values; `offset` (uint8): Rotation offset |
| **Returns** | `shares` (uint16[4]): Unpacked and rotated share BPS for each bucket |

**Logic Flow:**
1. For each `i` in 0..3: `shares[i] = rotatedShareBps(packed, offset, i)`
2. Uses unchecked block for the entire loop (safe since only incrementing uint8 < 4).

**Callers:** `distributeJackpotFinalDay` in JackpotModule (line 306), `_executeJackpot` in JackpotModule (line 1325)
**Callees:** `rotatedShareBps`

**Invariants:** Sum of returned shares should equal 10000 if the packed values sum to 10000 (rotation is a permutation, not a transformation).
**NatSpec Accuracy:** Accurate. States "Unpacks share BPS from packed uint64 with rotation offset for fairness."
**Gas Flags:** None.
**Verdict:** CORRECT

---

### Category: Trait Packing/Unpacking

---

### `packWinningTraits(uint8[4] memory traits)` [internal pure]

| Field | Value |
|-------|-------|
| **Signature** | `function packWinningTraits(uint8[4] memory traits) internal pure returns (uint32 packed)` |
| **Visibility** | internal |
| **Mutability** | pure |
| **Parameters** | `traits` (uint8[4]): 4 trait IDs (0-255 each) |
| **Returns** | `packed` (uint32): Packed representation |

**Logic Flow:**
1. `packed = uint32(traits[0]) | (uint32(traits[1]) << 8) | (uint32(traits[2]) << 16) | (uint32(traits[3]) << 24)`

**Bit Layout:**
- Bits [0-7]: traits[0]
- Bits [8-15]: traits[1]
- Bits [16-23]: traits[2]
- Bits [24-31]: traits[3]

**Roundtrip Verification:** `unpackWinningTraits(packWinningTraits([a, b, c, d]))` extracts:
- `uint8(packed)` = a (bits 0-7)
- `uint8(packed >> 8)` = b (bits 8-15)
- `uint8(packed >> 16)` = c (bits 16-23)
- `uint8(packed >> 24)` = d (bits 24-31)

Roundtrip is exact for all uint8 values. No data loss.

**Callers:** `_rollWinningTraits` in JackpotModule (lines 2632, 2636)
**Callees:** None

**Invariants:** Bijective mapping -- every uint32 maps to a unique uint8[4] and vice versa.
**NatSpec Accuracy:** Accurate. States "Packs 4 trait IDs (0-255 each) into a single uint32."
**Gas Flags:** None. Single expression with shifts and ORs.
**Verdict:** CORRECT

---

### `unpackWinningTraits(uint32 packed)` [internal pure]

| Field | Value |
|-------|-------|
| **Signature** | `function unpackWinningTraits(uint32 packed) internal pure returns (uint8[4] memory traits)` |
| **Visibility** | internal |
| **Mutability** | pure |
| **Parameters** | `packed` (uint32): Packed trait representation |
| **Returns** | `traits` (uint8[4]): Unpacked trait IDs |

**Logic Flow:**
1. `traits[0] = uint8(packed)` -- bits [0-7]
2. `traits[1] = uint8(packed >> 8)` -- bits [8-15]
3. `traits[2] = uint8(packed >> 16)` -- bits [16-23]
4. `traits[3] = uint8(packed >> 24)` -- bits [24-31]

Exact inverse of `packWinningTraits`. See roundtrip verification above.

**Callers:** Multiple sites in JackpotModule: `distributeJackpotFinalDay` (line 296), `_distributeDgnrsFinalDay` (line 785), `_hasTraitTickets` (line 1041), `_selectAndStoreWinners` (line 1117), `_executeJackpot` (line 1322), `_distributeCoinJackpot` (line 2453), `_hasActualTraitTickets` (line 2689)
**Callees:** None

**Invariants:** `packWinningTraits(unpackWinningTraits(x)) == x` for all uint32 x.
**NatSpec Accuracy:** Accurate. States "Unpacks a uint32 into 4 trait IDs."
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `getRandomTraits(uint256 rw)` [internal pure]

| Field | Value |
|-------|-------|
| **Signature** | `function getRandomTraits(uint256 rw) internal pure returns (uint8[4] memory w)` |
| **Visibility** | internal |
| **Mutability** | pure |
| **Parameters** | `rw` (uint256): VRF random word for trait derivation |
| **Returns** | `w` (uint8[4]): 4 trait IDs, one per quadrant |

**Logic Flow:**
1. `w[0] = uint8(rw & 0x3F)` -- uses bits [0-5], range [0, 63]
2. `w[1] = 64 + uint8((rw >> 6) & 0x3F)` -- uses bits [6-11], range [64, 127]
3. `w[2] = 128 + uint8((rw >> 12) & 0x3F)` -- uses bits [12-17], range [128, 191]
4. `w[3] = 192 + uint8((rw >> 18) & 0x3F)` -- uses bits [18-23], range [192, 255]

**Quadrant Range Verification:**
- `0x3F` = 63. Mask ensures 6-bit extraction (values 0-63).
- Quadrant 0: 0 + [0,63] = [0, 63]. Correct.
- Quadrant 1: 64 + [0,63] = [64, 127]. Correct.
- Quadrant 2: 128 + [0,63] = [128, 191]. Correct.
- Quadrant 3: 192 + [0,63] = [192, 255]. Correct.

**Overflow Check:** `192 + 63 = 255 = type(uint8).max`. No overflow. The addition `64 +`, `128 +`, `192 +` is performed in uint256 context (from the `uint8()` cast of the masked value), then truncated to uint8. Since all results are <= 255, no truncation data loss occurs.

**Entropy Independence:** Uses non-overlapping 6-bit windows from the random word (bits 0-5, 6-11, 12-17, 18-23). Each quadrant's trait is independently random with uniform distribution over 64 values.

**Coverage:** Each quadrant covers exactly 64 out of 256 possible trait IDs. Trait IDs in the gaps (e.g., trait 64 is reachable in Q1 but 63 is the max in Q0) are fully covered. Total coverage: 4 * 64 = 256 = all trait IDs are reachable.

**Callers:** `_rollWinningTraits` in JackpotModule (line 2637)
**Callees:** None

**Invariants:**
- Each trait is in its correct quadrant range
- No two traits can be in the same quadrant
- All 256 possible trait IDs are reachable (each with probability 1/64 within its quadrant)

**NatSpec Accuracy:** Accurate. States "Each quadrant uses 6 bits (0-63 range)" and lists quadrant offsets.
**Gas Flags:** None. Bit operations only.
**Verdict:** CORRECT

---

### Category: Ordering

---

### `bucketOrderLargestFirst(uint16[4] memory counts)` [internal pure]

| Field | Value |
|-------|-------|
| **Signature** | `function bucketOrderLargestFirst(uint16[4] memory counts) internal pure returns (uint8[4] memory order)` |
| **Visibility** | internal |
| **Mutability** | pure |
| **Parameters** | `counts` (uint16[4]): Bucket winner counts |
| **Returns** | `order` (uint8[4]): Bucket indices ordered largest-first |

**Logic Flow:**
1. Find largest bucket: iterate i=1..3, track `largestIdx` and `largestCount`. Ties keep lower index (strict `>`, not `>=`).
2. Set `order[0] = largestIdx`.
3. Fill remaining positions in original index order: `order[1..3]` = indices != largestIdx, preserving original order.

**Partial Sort Behavior:** Only the first element (order[0]) is guaranteed to be the largest bucket index. The remaining elements are in their original index order (0, 1, 2, 3 minus the largest), NOT sorted by count. This is intentional -- the function name says "LargestFirst" not "FullSort."

**Example:** counts = [8, 25, 15, 1]
- largestIdx = 1 (count 25)
- order = [1, 0, 2, 3]

**Example with tie:** counts = [25, 25, 15, 1]
- largestIdx = 0 (first 25, strict `>` doesn't update for second 25)
- order = [0, 1, 2, 3]

**Callers:** `_distributeJackpotEth` in JackpotModule (line 1423)
**Callees:** None

**Invariants:**
- order[0] is the index of the bucket with the largest count
- Ties are broken by lower index (stable)
- Remaining indices are in ascending order

**NatSpec Accuracy:** Accurate. States "largest count first; ties keep lower index."
**Gas Flags:** None. Two short loops (3 and 4 iterations).
**Verdict:** CORRECT

---

## Bucket Scaling Analysis

The following table shows bucket count scaling at key ETH pool thresholds. Base counts are [25, 15, 8, 1] (before rotation). The solo bucket (count=1) is never scaled. Two configurations are used in the codebase:

**Configuration A -- Normal Jackpot:** maxScaleBps=40,000 (4x), JACKPOT_MAX_WINNERS=300
**Configuration B -- Daily/Final Day:** maxScaleBps=66,667 (6.67x), DAILY_ETH_MAX_WINNERS=321

### Configuration A: Normal Jackpot (4x cap, 300 max winners)

| ETH Pool | Scale BPS | Scale Factor | Non-Solo Counts | Total Winners | Capped? |
|----------|-----------|--------------|-----------------|---------------|---------|
| 0 ETH | N/A | N/A | [0, 0, 0, 0] | 0 | N/A (empty pool) |
| 5 ETH | 10,000 | 1.00x | [25, 15, 8, 1] | 49 | No |
| 10 ETH | 10,000 | 1.00x | [25, 15, 8, 1] | 49 | No |
| 25 ETH | 13,750 | 1.38x | [34, 20, 11, 1] | 66 | No |
| 30 ETH | 15,000 | 1.50x | [37, 22, 12, 1] | 72 | No |
| 50 ETH | 20,000 | 2.00x | [50, 30, 16, 1] | 97 | No |
| 100 ETH | 26,666 | 2.67x | [66, 39, 21, 1] | 127 | No |
| 125 ETH | 30,000 | 3.00x | [75, 45, 24, 1] | 145 | No |
| 200 ETH | 40,000 | 4.00x | [100, 60, 32, 1] | 193 | No |
| 500 ETH | 40,000 | 4.00x | [100, 60, 32, 1] | 193 | No |

With maxTotal=300 and max uncapped total of 193, the cap is never reached under Configuration A. This means `capBucketCounts` is always a no-op for normal jackpots.

### Configuration B: Daily Jackpot (6.67x cap, 321 max winners)

| ETH Pool | Scale BPS | Scale Factor | Non-Solo Counts | Total Winners | Capped? |
|----------|-----------|--------------|-----------------|---------------|---------|
| 0 ETH | N/A | N/A | [0, 0, 0, 0] | 0 | N/A |
| 5 ETH | 10,000 | 1.00x | [25, 15, 8, 1] | 49 | No |
| 50 ETH | 20,000 | 2.00x | [50, 30, 16, 1] | 97 | No |
| 200 ETH | 66,667 | 6.67x | [166, 100, 53, 1] | 320 | No |
| 500 ETH | 66,667 | 6.67x | [166, 100, 53, 1] | 320 | No |

With maxTotal=321 and max uncapped total of 320, the cap is also never reached under Configuration B. The constants are precisely tuned: `(25 * 66667) / 10000 = 166`, `(15 * 66667) / 10000 = 100`, `(8 * 66667) / 10000 = 53`, total = 166 + 100 + 53 + 1 = 320 <= 321.

**Observation:** The cap mechanism (`capBucketCounts`) exists as a safety net but is never triggered by the current constant configuration. The constants were chosen to make the 4x/6.67x scaled totals fit within the respective maxTotal values. This is good defensive programming.

---

## Share Distribution Verification

The `bucketShares` function guarantees exact distribution of the pool with zero dust loss:

**Mechanism:**
1. For each non-remainder bucket: `share = (pool * shareBps[i]) / 10000`, rounded down to `unit * count` multiples.
2. The remainder bucket receives: `pool - sum(other shares)`.

**Proof of exactness:** `shares[remainderIdx] = pool - distributed`, where `distributed` is the sum of all non-remainder shares. Therefore `sum(shares) = distributed + (pool - distributed) = pool`. QED.

**Rounding direction:** Non-remainder buckets are always rounded DOWN (integer division). This means the remainder bucket always receives >= its BPS-proportional share. The remainder bucket (solo bucket, which receives the 60% share) benefits from all rounding dust.

**Edge case -- all bucketCounts are 0 except remainder:**
When all non-remainder buckets have count=0, their shares are computed but not stored (stay 0). The share values are still added to `distributed`. Then `shares[remainderIdx] = pool - distributed`. If all shareBps sum to 10000, then `distributed = pool - (pool * shareBps[remainderIdx] / 10000)` and the remainder gets the rest. Due to integer division, this may differ from `pool * shareBps[remainderIdx] / 10000` by at most a few wei.

**Edge case -- unit is 0:**
When `unit == 0`, no unit rounding is applied. Shares are just `(pool * shareBps[i]) / 10000` without further rounding. Dust still goes to remainder.

---

## Library Call Sites

All 13 functions are called exclusively from `DegenerusGameJackpotModule.sol`. No other contract imports or uses `JackpotBucketLib`.

### Call Site Map

| Function | Line(s) | Calling Function | Context |
|----------|---------|-----------------|---------|
| `unpackWinningTraits` | 296 | `distributeJackpotFinalDay` | Unpack traits for final-day jackpot distribution |
| `unpackWinningTraits` | 785 | `_distributeDgnrsFinalDay` | Re-derive traits for DGNRS token final-day reward |
| `unpackWinningTraits` | 1041 | `_hasTraitTickets` | Check if any trait has tickets at a level |
| `unpackWinningTraits` | 1117 | `_selectAndStoreWinners` | Unpack traits for winner selection |
| `unpackWinningTraits` | 1322 | `_executeJackpot` | Unpack traits for standard jackpot execution |
| `unpackWinningTraits` | 2453 | `_distributeCoinJackpot` | Unpack traits for BURNIE coin jackpot |
| `unpackWinningTraits` | 2689 | `_hasActualTraitTickets` | Check for actual (non-virtual) trait tickets |
| `bucketCountsForPoolCap` | 300 | `distributeJackpotFinalDay` | Get scaled bucket counts for final-day ETH pool |
| `shareBpsByBucket` | 306 | `distributeJackpotFinalDay` | Get rotated share BPS for final-day distribution |
| `shareBpsByBucket` | 1325 | `_executeJackpot` | Get rotated share BPS for standard jackpot |
| `soloBucketIndex` | 783 | `_distributeDgnrsFinalDay` | Find solo bucket for DGNRS reward targeting |
| `soloBucketIndex` | 1414 | `_distributeJackpotEth` | Identify remainder bucket (=solo) for share calc |
| `soloBucketIndex` | 1536, 1538 | `_distributeNormalJackpotEth` | Identify remainder and solo buckets |
| `traitBucketCounts` | 1341 | `_runJackpotEthFlow` | Get base counts for standard jackpot |
| `scaleTraitBucketCountsWithCap` | 1344-1350 | `_runJackpotEthFlow` | Scale and cap for standard jackpot |
| `bucketShares` | 1415 | `_distributeJackpotEth` | Compute per-bucket ETH shares (final-day chunked) |
| `bucketShares` | 1540 | `_distributeNormalJackpotEth` | Compute per-bucket ETH shares (normal) |
| `bucketOrderLargestFirst` | 1423 | `_distributeJackpotEth` | Order buckets for chunked distribution (largest first for gas efficiency) |
| `packWinningTraits` | 2632 | `_rollWinningTraits` | Pack burn-count-weighted traits |
| `packWinningTraits` | 2636 | `_rollWinningTraits` | Pack random traits (non-burn path) |
| `getRandomTraits` | 2637 | `_rollWinningTraits` | Derive random traits when not using burn counts |

**Total call sites:** 22 references across 11 distinct caller functions, all within JackpotModule.

**Most-called function:** `unpackWinningTraits` (7 call sites) -- used wherever packed winning traits need to be interpreted.

**Least-called functions:** `sumBucketCounts` (0 external call sites, called only by `capBucketCounts` within the library), `getRandomTraits` (1 call site).

---

## Findings Summary

### Verdict Distribution

| Verdict | Count | Functions |
|---------|-------|-----------|
| CORRECT | 13 | All functions |
| CONCERN | 0 | -- |
| BUG | 0 | -- |
| GAS | 0 | -- |

### Key Findings

1. **All 13 functions verified CORRECT.** No bugs, no concerns, no gas issues found.

2. **Solo bucket preservation is robust.** The `count > 1` guard in `scaleTraitBucketCountsWithCap` and the `nonSoloCap = maxTotal - 1` reserve in `capBucketCounts` together ensure the solo bucket is never modified during scaling or capping.

3. **Dust-free share distribution.** The remainder-bucket pattern in `bucketShares` algebraically guarantees `sum(shares) == pool` with zero wei lost.

4. **Trait quadrant coverage is complete.** `getRandomTraits` covers all 256 trait IDs across 4 non-overlapping quadrants of 64 each, with uniform probability within each quadrant.

5. **Pack/unpack roundtrip is exact.** `unpackWinningTraits(packWinningTraits(x)) == x` for all valid inputs. Bijective mapping.

6. **Cap mechanism is a safety net.** Current constant configurations (4x/300 and 6.67x/321) are tuned such that uncapped totals never exceed maxTotal. The cap logic exists as defensive programming.

7. **Entropy bit usage is well-separated.** Bucket rotation uses bits [0-1], solo index derives from the same bits (intentionally inverse), share rotation adds +1 offset. Trait generation uses bits [0-23]. Cap trimming/remainder uses bits [24-25]. No unintended entropy correlation between independent decisions.

8. **`bucketOrderLargestFirst` is a partial sort.** Only order[0] is guaranteed to be the largest. The remaining elements maintain original index order. This is sufficient for its single use case in `_distributeJackpotEth`, which processes the largest bucket first for gas efficiency in chunked distribution.
