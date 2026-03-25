# Unit 15: Libraries -- Taskmaster Coverage Checklist

**Phase:** 117
**Contracts:** EntropyLib, BitPackingLib, GameTimeLib, JackpotBucketLib, PriceLookupLib
**Generated:** 2026-03-25
**Total Functions:** 19 (all internal pure/view -- Category D)

---

## Contract 1: EntropyLib (EntropyLib.sol, 24 lines)

### Function Inventory

| # | Function | Lines | Visibility | Mutability | Category |
|---|----------|-------|------------|------------|----------|
| E-01 | entropyStep(uint256 state) | L16-23 | internal | pure | D |

### Caller Map

| Caller Contract | Call Sites | Context |
|----------------|------------|---------|
| DegenerusGameJackpotModule | L801, L813, L1127, L1375, L1557, L2029, L2373, L2461 | Entropy derivation for trait selection, winner picks, decimator rolls |
| DegenerusGameEndgameModule | L504 | Level-end reward entropy |
| DegenerusGameLootboxModule | L838, L842, L1635, L1656, L1672, L1686, L1722 | Lootbox resolution entropy |
| DegenerusGamePayoutUtils | L54 | Level offset derivation |
| DegenerusGameMintModule | L545 | Purchase roll entropy |

**Total call sites: 20+**

### Critical Properties to Verify
- [ ] No fixed points (entropyStep(x) == x for some x) -- especially entropyStep(0)
- [ ] No short cycles that could produce predictable sequences
- [ ] XOR-shift triple (7, 9, 8) produces adequate diffusion on uint256
- [ ] Unchecked block: no overflow/underflow issues with shift operations on uint256

---

## Contract 2: BitPackingLib (BitPackingLib.sol, 88 lines)

### Function Inventory

| # | Function | Lines | Visibility | Mutability | Category |
|---|----------|-------|------------|------------|----------|
| B-01 | setPacked(data, shift, mask, value) | L79-86 | internal | pure | D |

### Constant Inventory

| # | Constant | Value | Bits | Verified Width |
|---|----------|-------|------|----------------|
| B-C1 | MASK_16 | (1<<16)-1 = 0xFFFF | 16 | YES |
| B-C2 | MASK_24 | (1<<24)-1 = 0xFFFFFF | 24 | YES |
| B-C3 | MASK_32 | (1<<32)-1 = 0xFFFFFFFF | 32 | YES |
| B-C4 | LAST_LEVEL_SHIFT | 0 | bits 0-23 | YES (24-bit field) |
| B-C5 | LEVEL_COUNT_SHIFT | 24 | bits 24-47 | YES (24-bit field) |
| B-C6 | LEVEL_STREAK_SHIFT | 48 | bits 48-71 | YES (24-bit field) |
| B-C7 | DAY_SHIFT | 72 | bits 72-103 | YES (32-bit field) |
| B-C8 | LEVEL_UNITS_LEVEL_SHIFT | 104 | bits 104-127 | YES (24-bit field) |
| B-C9 | FROZEN_UNTIL_LEVEL_SHIFT | 128 | bits 128-151 | YES (24-bit field) |
| B-C10 | WHALE_BUNDLE_TYPE_SHIFT | 152 | bits 152-153 | 2-bit field (callers use mask=3) |
| B-C11 | LEVEL_UNITS_SHIFT | 228 | bits 228-243 | YES (16-bit field) |

### Layout Verification

```
Bit Position: 0         24        48        72         104       128       152  154  160       184       228    244  256
              |---------|---------|---------|----------|---------|---------|--|----|---------|---------|------|------|
Field:        LAST_LVL  LVL_CNT  LVL_STRK  DAY       UNITS_LVL FROZEN   BT (gap) STREAK_LC (gap)     UNITS  (rsv)
Width:        24        24       24         32        24        24        2  6    24        44        16     12
```

**Key verification:** LEVEL_UNITS_SHIFT (228) + MASK_16 (16 bits) = bits 228-243. Bits 244-255 reserved. No overflow past uint256 boundary (256 bits). **SAFE.**

### Caller Map

| Caller Contract | Usage Pattern | Call Sites |
|----------------|---------------|------------|
| DegenerusGameStorage | setPacked for levelCount, frozenUntilLevel, bundleType, lastLevel, day | L1024-1128 |
| DegenerusGameMintModule | setPacked for levelUnits, unitsLevel, frozenUntil, bundleType, lastLevel, levelCount | L214-273 |
| DegenerusGameWhaleModule | setPacked for levelCount, frozenUntil, bundleType, lastLevel + direct shift/mask reads | L209-814 |
| DegenerusGameBoonModule | setPacked for levelCount | L312-315 |
| DegenerusGame | Direct shift/mask reads for view functions | L1611-2438 |
| DegenerusGameAdvanceModule | Direct shift/mask reads for day, frozenUntilLevel | L657-675 |
| DegenerusGameDegeneretteModule | Direct shift/mask reads for levelCount, frozenUntil, bundleType | L1013-1022 |
| DegenerusGameMintStreakUtils | Direct mask reads + shift for levelStreak, streakLastCompleted | L13-59 |

**Total call sites: 50+**

### Critical Properties to Verify
- [ ] setPacked formula is correct: (data & ~(mask << shift)) | ((value & mask) << shift)
- [ ] No field overlap between any two defined fields in the layout
- [ ] All callers pass correct (shift, mask) pairs -- no mismatched shift+mask
- [ ] Gap regions [154-159], [184-227], [244-255] are never written to
- [ ] WHALE_BUNDLE_TYPE at shift 152 with mask=3 (2 bits) doesn't bleed into gap at 154

---

## Contract 3: GameTimeLib (GameTimeLib.sol, 35 lines)

### Function Inventory

| # | Function | Lines | Visibility | Mutability | Category |
|---|----------|-------|------------|------------|----------|
| T-01 | currentDayIndex() | L21-23 | internal | view | D |
| T-02 | currentDayIndexAt(uint48 ts) | L31-34 | internal | pure | D |

### Constant Inventory

| # | Constant | Value | Notes |
|---|----------|-------|-------|
| T-C1 | JACKPOT_RESET_TIME | 82620 | 22:57 UTC = 22*3600 + 57*60 = 82620 seconds |

### Caller Map

| Caller Contract | Call Sites | Context |
|----------------|------------|---------|
| DegenerusGameStorage | L1135 (currentDayIndex), L1140 (currentDayIndexAt) | Game-wide day tracking |
| DegenerusAffiliate | L559, L815 (currentDayIndex) | Affiliate day tracking |

### Critical Properties to Verify
- [ ] Underflow safety: ts < JACKPOT_RESET_TIME (first ~23h of deployment) -- does uint48 subtraction revert?
- [ ] DEPLOY_DAY_BOUNDARY = 0 (from ContractAddresses.sol) -- what does this mean for day index?
- [ ] Day 1 semantics: verify first valid timestamp produces day index 1
- [ ] uint48 cast of block.timestamp: safe until year ~8.9 million (no practical concern)
- [ ] Integer division truncation: (ts - 82620) / 86400 -- verify boundary behavior at exact reset time

---

## Contract 4: JackpotBucketLib (JackpotBucketLib.sol, 307 lines)

### Function Inventory

| # | Function | Lines | Visibility | Mutability | Category | Complexity |
|---|----------|-------|------------|------------|----------|------------|
| J-01 | traitBucketCounts(entropy) | L36-51 | internal | pure | D | LOW |
| J-02 | scaleTraitBucketCountsWithCap(baseCounts, ethPool, entropy, maxTotal, maxScaleBps) | L55-95 | internal | pure | D | HIGH |
| J-03 | bucketCountsForPoolCap(ethPool, entropy, maxTotal, maxScaleBps) | L98-107 | internal | pure | D | LOW |
| J-04 | sumBucketCounts(counts) | L110-112 | internal | pure | D | LOW |
| J-05 | capBucketCounts(counts, maxTotal, entropy) | L115-203 | internal | pure | D | HIGH |
| J-06 | bucketShares(pool, shareBps, bucketCounts, remainderIdx, unit) | L211-237 | internal | pure | D | MED |
| J-07 | soloBucketIndex(entropy) | L240-242 | internal | pure | D | LOW |
| J-08 | rotatedShareBps(packed, offset, traitIdx) | L245-248 | internal | pure | D | LOW |
| J-09 | shareBpsByBucket(packed, offset) | L251-257 | internal | pure | D | LOW |
| J-10 | packWinningTraits(traits) | L264-266 | internal | pure | D | LOW |
| J-11 | unpackWinningTraits(packed) | L269-274 | internal | pure | D | LOW |
| J-12 | getRandomTraits(rw) | L278-283 | internal | pure | D | LOW |
| J-13 | bucketOrderLargestFirst(counts) | L290-306 | internal | pure | D | MED |

### Constant Inventory

| # | Constant | Value | Notes |
|---|----------|-------|-------|
| J-C1 | JACKPOT_SCALE_MIN_WEI | 10 ether | Scaling threshold |
| J-C2 | JACKPOT_SCALE_FIRST_WEI | 50 ether | 2x target |
| J-C3 | JACKPOT_SCALE_SECOND_WEI | 200 ether | Max scale target |
| J-C4 | JACKPOT_SCALE_BASE_BPS | 10000 | 1x base |
| J-C5 | JACKPOT_SCALE_FIRST_BPS | 20000 | 2x scale |

### Caller Map

| Caller Function | Library Functions Used | Lines |
|----------------|----------------------|-------|
| JackpotModule::_runDailyJackpotForPool | bucketCountsForPoolCap, shareBpsByBucket, bucketShares, soloBucketIndex, bucketOrderLargestFirst, unpackWinningTraits | L285-1360 |
| JackpotModule::_runCoinJackpot | unpackWinningTraits, soloBucketIndex, bucketShares | L1448-1449 |
| JackpotModule::_pickTraitWinners | traitBucketCounts | L1302 |
| JackpotModule::_generateTraits | getRandomTraits, packWinningTraits | L2540-2545 |
| JackpotModule::_traitJackpotClaim | unpackWinningTraits | L2351, L2599 |

### Critical Properties to Verify
- [ ] traitBucketCounts: rotation by (entropy & 3) produces all 4 permutations
- [ ] scaleTraitBucketCountsWithCap: linear interpolation correct at boundaries (10, 50, 200 ETH)
- [ ] scaleTraitBucketCountsWithCap: solo bucket (count==1) never scaled
- [ ] capBucketCounts: maxTotal=0 returns all zeros
- [ ] capBucketCounts: maxTotal=1 returns solo bucket only
- [ ] capBucketCounts: trim loop fully drains excess (can't leave scaledTotal > nonSoloCap)
- [ ] capBucketCounts: remainder distribution only adds to non-solo buckets
- [ ] bucketShares: distributed + remainder == pool (no dust leak, no over-distribution)
- [ ] bucketShares: unit rounding doesn't cause over-distribution
- [ ] soloBucketIndex: consistent with traitBucketCounts rotation (solo=1 maps correctly)
- [ ] getRandomTraits: 4 quadrants cover full 0-255 trait space without overlap
- [ ] packWinningTraits/unpackWinningTraits: roundtrip preserves all 4 trait values
- [ ] bucketOrderLargestFirst: ties keep lower index (stable), all 4 indices appear in output

---

## Contract 5: PriceLookupLib (PriceLookupLib.sol, 47 lines)

### Function Inventory

| # | Function | Lines | Visibility | Mutability | Category |
|---|----------|-------|------------|------------|----------|
| P-01 | priceForLevel(uint24 targetLevel) | L21-46 | internal | pure | D |

### Caller Map

| Caller Contract | Call Sites | Context |
|----------------|------------|---------|
| DegenerusGameEndgameModule | L525 | Level-end reward pricing |
| DegenerusGameWhaleModule | L384, L575 | Whale bundle pricing |
| DegenerusGameJackpotModule | L791, L1039, L1350, L1447 | Jackpot unit pricing |
| DegenerusGamePayoutUtils | L60 | Payout ticket pricing |
| DegenerusGameLootboxModule | L897, L1812 | Lootbox pricing |

**Total call sites: 12+**

### Price Tier Verification Table

| Level Range | Expected Price | Tier |
|------------|---------------|------|
| 0-4 | 0.01 ETH | Intro low |
| 5-9 | 0.02 ETH | Intro high |
| 10-29 | 0.04 ETH | Cycle 1, standard early |
| 30-59 | 0.08 ETH | Cycle 1, standard mid |
| 60-89 | 0.12 ETH | Cycle 1, standard late |
| 90-99 | 0.16 ETH | Cycle 1, standard final |
| 100, 200, 300... | 0.24 ETH | Milestone |
| x01-x29 | 0.04 ETH | Cycle N, early |
| x30-x59 | 0.08 ETH | Cycle N, mid |
| x60-x89 | 0.12 ETH | Cycle N, late |
| x90-x99 | 0.16 ETH | Cycle N, final |

### Critical Properties to Verify
- [ ] Boundary: level 4 -> 0.01, level 5 -> 0.02 (no gap or overlap)
- [ ] Boundary: level 9 -> 0.02, level 10 -> 0.04 (intro->standard transition)
- [ ] Boundary: level 99 -> 0.16, level 100 -> 0.24 (milestone)
- [ ] Boundary: level 100 -> 0.24, level 101 -> 0.04 (milestone->early)
- [ ] uint24 max (16777215): cycleOffset = 16777215 % 100 = 15, returns 0.04 ETH -- valid
- [ ] Level 0: returns 0.01 ETH (cheapest tier)
- [ ] No unreachable code paths in the if/else chain

---

## Coverage Summary

| Library | Functions | Constants | Complexity | Call Sites |
|---------|-----------|-----------|------------|------------|
| EntropyLib | 1 | 0 | LOW | 20+ |
| BitPackingLib | 1 | 11 | LOW | 50+ |
| GameTimeLib | 2 | 1 | LOW | 4 |
| JackpotBucketLib | 13 | 5 | HIGH | 25+ |
| PriceLookupLib | 1 | 0 | LOW | 12+ |
| **TOTAL** | **18 functions** | **17 constants** | - | **111+** |

### Taskmaster Verdict: CHECKLIST READY

All 18 functions across 5 libraries inventoried with:
- Full function signatures and line numbers
- Complete caller maps with specific line references
- Critical properties to verify for each library
- Constant verification for packed layout correctness
- Price tier boundary verification table

**Ready for Mad Genius attack analysis.**
