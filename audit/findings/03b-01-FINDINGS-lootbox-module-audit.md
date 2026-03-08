# 03b-01 FINDINGS: LootboxModule VRF Derivation, Probability Distribution, EV Multiplier, and Boon Weight Audit

**Audit Date:** 2026-03-01
**Target:** `contracts/modules/DegenerusGameLootboxModule.sol` (1749 lines)
**Scope:** READ-ONLY audit. No contract files modified.
**Requirements:** MATH-05 (partial)

---

## Section 1: VRF Derivation and Probability Distribution Audit

### 1.1 VRF Word Derivation Traces

Three resolution entry points exist. Each reads `lootboxRngWordByIndex[index]` and derives a player-unique entropy seed via `keccak256`.

#### Entry Point 1: `openLootBox` (line 544)

1. **VRF word read:** `rngWord = lootboxRngWordByIndex[index]` (line 552)
2. **Guard:** `if (rngWord == 0) revert RngNotReady()` (line 553)
3. **Initial entropy:** `entropy = uint256(keccak256(abi.encode(rngWord, player, day, amount)))` (line 573)
4. **entropyStep chain:**
   - Step 1 (line 785 via `_rollTargetLevel`): `levelEntropy = EntropyLib.entropyStep(entropy)` -- drives target level roll (`levelEntropy % 100`)
   - Step 1a (line 789, 5% path only): `farEntropy = EntropyLib.entropyStep(levelEntropy)` -- drives far-future level offset (`farEntropy % 46 + 5`)
   - Step 2 (line 1518 via `_resolveLootboxRoll`): `nextEntropy = EntropyLib.entropyStep(entropy)` -- drives reward type roll (`nextEntropy % 20`)
   - Step 3+ (varies by reward path): additional entropyStep calls for variance tiers, DGNRS tier, BURNIE variance
   - Step N (line 1027 via `_rollLootboxBoons`): `roll = entropy % BOON_PPM_SCALE` -- drives boon selection
5. **EV multiplier:** Applied via `_applyEvMultiplierWithCap(player, currentLevel, amount, evMultiplierBps)` (lines 586-591) BEFORE entering `_resolveLootboxCommon`
6. **Entropy threading:** Correct -- each `entropyStep` takes previous output as input. The `_resolveLootboxCommon` receives `nextEntropy` from `_rollTargetLevel` and threads it through both rolls (if split).

#### Entry Point 2: `openBurnieLootBox` (line 621)

1. **VRF word read:** `rngWord = lootboxRngWordByIndex[index]` (line 627)
2. **Guard:** `if (rngWord == 0) revert RngNotReady()` (line 628)
3. **Initial entropy:** `entropy = uint256(keccak256(abi.encode(rngWord, player, day, amountEth)))` (line 644)
4. **entropyStep chain:** Same structure as `openLootBox` via `_rollTargetLevel` then `_resolveLootboxCommon`
5. **EV multiplier:** NOT applied. `openBurnieLootBox` does NOT call `_applyEvMultiplierWithCap`. The `amountEth` is passed directly to `_resolveLootboxCommon` at lines 647-660 without any EV scaling.
6. **Boon flags:** `allowWhalePass=false, allowLazyPass=false, emitLootboxEvent=false, allowBoons=true` -- boons ARE rolled but pass awards are excluded

#### Entry Point 3: `resolveLootboxDirect` (line 677)

1. **VRF word read:** `rngWord` is passed as a parameter (line 677) -- no direct `lootboxRngWordByIndex` read
2. **Guard:** `if (amount == 0) return` (line 678) -- no VRF word zero-check since word is passed in
3. **Initial entropy:** `entropy = uint256(keccak256(abi.encode(rngWord, player, day, amount)))` (line 682)
4. **entropyStep chain:** Same structure via `_rollTargetLevel` then `_resolveLootboxCommon`
5. **EV multiplier:** Applied via `_applyEvMultiplierWithCap(player, currentLevel, amount, evMultiplierBps)` (line 686)
6. **Boon flags:** `allowBoons=false` (line 700) -- no boon roll for direct resolution

#### Per-Player Independence Property

**CONFIRMED.** All three entry points derive initial entropy via `keccak256(abi.encode(rngWord, player, day, amount))`. The `player` address is included in the hash, ensuring each player gets a unique entropy seed from the same VRF word. Two players with different addresses opening the same lootbox index will get independent entropy streams.

### 1.2 Reward Type Distribution (roll % 20)

**Location:** `_resolveLootboxRoll` (line 1500), specifically lines 1518-1585.

```
nextEntropy = EntropyLib.entropyStep(entropy);   // line 1518
roll = nextEntropy % 20;                          // line 1521
```

| Roll Range | Count | Probability | Reward Type | Line |
|-----------|-------|-------------|-------------|------|
| 0-10      | 11    | 55%         | Tickets     | 1522 |
| 11-12     | 2     | 10%         | DGNRS       | 1537 |
| 13-14     | 2     | 10%         | WWXRP       | 1553 |
| 15-19     | 5     | 25%         | BURNIE      | 1567 |

**Boundaries verified:**
- `if (roll < 11)` -- roll values 0,1,2,3,4,5,6,7,8,9,10 = 11 values = 55%. **CORRECT.**
- `else if (roll < 13)` -- roll values 11,12 = 2 values = 10%. **CORRECT.**
- `else if (roll < 15)` -- roll values 13,14 = 2 values = 10%. **CORRECT.**
- `else` -- roll values 15,16,17,18,19 = 5 values = 25%. **CORRECT.**
- Sum: 11 + 2 + 2 + 5 = 20 = 100%. **No off-by-one.**

### 1.3 Ticket Variance Tiers

**Location:** `_lootboxTicketCount` (line 1596), variance tier selection at lines 1605-1634.

```
nextEntropy = EntropyLib.entropyStep(entropy);    // line 1605
varianceRoll = nextEntropy % 10_000;              // line 1606
```

| Tier | Roll Range (BPS) | Probability | Multiplier BPS | Multiplier | Line |
|------|-----------------|-------------|----------------|------------|------|
| 1    | 0 - 99          | 1%          | 46,000         | 4.6x       | 1609-1610 |
| 2    | 100 - 499       | 4%          | 23,000         | 2.3x       | 1611-1616 |
| 3    | 500 - 2,499     | 20%         | 11,000         | 1.1x       | 1617-1623 |
| 4    | 2,500 - 6,999   | 45%         | 6,510          | 0.651x     | 1624-1631 |
| 5    | 7,000 - 9,999   | 30%         | 4,500          | 0.45x      | 1632-1633 |

**Boundary verification:**
- Tier 1: `varianceRoll < 100` (0-99) = 100/10000 = 1%. **CORRECT.**
- Tier 2: `varianceRoll < 100 + 400 = 500` (100-499) = 400/10000 = 4%. **CORRECT.**
- Tier 3: `varianceRoll < 500 + 2000 = 2500` (500-2499) = 2000/10000 = 20%. **CORRECT.**
- Tier 4: `varianceRoll < 2500 + 4500 = 7000` (2500-6999) = 4500/10000 = 45%. **CORRECT.**
- Tier 5: else (7000-9999) = 3000/10000 = 30%. **CORRECT.**
- Sum: 100 + 400 + 2000 + 4500 + 3000 = 10000 = 100%. **No gap.**

**BPS constant verification:**
- `LOOTBOX_TICKET_VARIANCE_TIER1_BPS = 46_000` = 4.6x. **CORRECT.**
- `LOOTBOX_TICKET_VARIANCE_TIER2_BPS = 23_000` = 2.3x. **CORRECT.**
- `LOOTBOX_TICKET_VARIANCE_TIER3_BPS = 11_000` = 1.1x. **CORRECT.**
- `LOOTBOX_TICKET_VARIANCE_TIER4_BPS = 6_510` = 0.651x. **CORRECT.**
- `LOOTBOX_TICKET_VARIANCE_TIER5_BPS = 4_500` = 0.45x. **CORRECT.**

**Base ticket budget:** `LOOTBOX_TICKET_ROLL_BPS = 16_100` = 161% of roll amount allocated to ticket budget before variance. With the expected variance multiplier of `0.01*4.6 + 0.04*2.3 + 0.20*1.1 + 0.45*0.651 + 0.30*0.45 = 0.046 + 0.092 + 0.22 + 0.293 + 0.135 = 0.786`, effective ticket EV is `1.61 * 0.786 = 1.265` (126.5% of the roll amount in ticket value).

### 1.4 BURNIE Reward Variance

**Location:** `_resolveLootboxRoll` (line 1567-1585), the `else` branch for roll >= 15.

```
nextEntropy = EntropyLib.entropyStep(nextEntropy);    // line 1569
varianceRoll = nextEntropy % 20;                       // line 1570
```

**Branch probability:**
- Low path: `varianceRoll < 16` -- rolls 0-15 = 16/20 = 80%. **CORRECT.**
- High path: `varianceRoll >= 16` -- rolls 16-19 = 4/20 = 20%. **CORRECT.**

**Low path BPS values (80% chance):**
Base: `LOOTBOX_LARGE_BURNIE_LOW_BASE_BPS = 5_808` (58.08%)
Step: `LOOTBOX_LARGE_BURNIE_LOW_STEP_BPS = 477` (4.77% per step)

| varianceRoll | BPS | Multiplier |
|-------------|-----|------------|
| 0  | 5,808  | 58.08% |
| 1  | 6,285  | 62.85% |
| 2  | 6,762  | 67.62% |
| 3  | 7,239  | 72.39% |
| 4  | 7,716  | 77.16% |
| 5  | 8,193  | 81.93% |
| 6  | 8,670  | 86.70% |
| 7  | 9,147  | 91.47% |
| 8  | 9,624  | 96.24% |
| 9  | 10,101 | 101.01% |
| 10 | 10,578 | 105.78% |
| 11 | 11,055 | 110.55% |
| 12 | 11,532 | 115.32% |
| 13 | 12,009 | 120.09% |
| 14 | 12,486 | 124.86% |
| 15 | 12,963 | 129.63% |

**Range: 58.08% to 129.63%.** Plan documentation said "58%-134%" which is approximately correct but the upper bound is 129.63%, not 134%. This is a minor documentation discrepancy, not a code issue.

**Average low path BPS:** (5808 + 12963) / 2 = 9385.5 BPS = 93.855%

**High path BPS values (20% chance):**
Base: `LOOTBOX_LARGE_BURNIE_HIGH_BASE_BPS = 30_705` (307.05%)
Step: `LOOTBOX_LARGE_BURNIE_HIGH_STEP_BPS = 9_430` (94.30% per step)

| varianceRoll | Offset (roll-16) | BPS | Multiplier |
|-------------|-------------------|-----|------------|
| 16 | 0 | 30,705 | 307.05% |
| 17 | 1 | 40,135 | 401.35% |
| 18 | 2 | 49,565 | 495.65% |
| 19 | 3 | 58,995 | 589.95% |

**Range: 307.05% to 589.95%.** Plan documentation said "307%-590%" which matches.

**Average high path BPS:** (30705 + 58995) / 2 = 44850 BPS = 448.50%

**Combined BURNIE EV (25% path):**
- Low (80%): 93.855%
- High (20%): 448.50%
- E[BURNIE_multiplier] = 0.80 * 0.93855 + 0.20 * 4.4850 = 0.75084 + 0.89700 = 1.6478 (164.78%)

Note: This multiplier is applied to the ETH amount to determine BURNIE value, then converted to BURNIE at the target level's BURNIE price. The actual ETH-equivalent EV depends on BURNIE:ETH exchange rate stability.

### 1.5 Target Level Roll

**Location:** `_rollTargetLevel` (line 781-799).

```
levelEntropy = EntropyLib.entropyStep(entropy);   // line 785
rangeRoll = levelEntropy % 100;                    // line 786
```

| Roll Range | Probability | Level Offset | Range |
|-----------|-------------|--------------|-------|
| 0-4       | 5%          | 5-50 levels ahead | `(farEntropy % 46) + 5` |
| 5-99      | 95%         | 0-5 levels ahead  | `levelEntropy % 6` |

**Verification:**
- Near future (95%): `rangeRoll >= 5` (rolls 5-99 = 95/100). Offset = `levelEntropy % 6` = 0,1,2,3,4,5. **Range 0-5 levels ahead. CORRECT.**
- Far future (5%): `rangeRoll < 5` (rolls 0-4 = 5/100). Additional entropyStep at line 789. Offset = `(farEntropy % 46) + 5` = 5..50. **Range 5-50 levels ahead. CORRECT.**
- **Note (near path):** Uses `levelEntropy % 6` where `levelEntropy` is the same value used for `rangeRoll = levelEntropy % 100`. Since `levelEntropy` is the same word, the near-path's level offset is technically correlated with the range roll. However, `% 6` and `% 100` are not coprime moduli (GCD=2), introducing a minor bias: odd `levelEntropy` values always produce `rangeRoll` odd AND `levelEntropy % 6` odd. For a VRF-seeded 256-bit word this creates negligible statistical deviation. **Informational.**

### 1.6 Lootbox Split Logic

**Location:** `_resolveLootboxCommon` (lines 847-861).

For lootboxes above `LOOTBOX_SPLIT_THRESHOLD = 0.5 ether`:
- `amountFirst = mainAmount / 2`
- `amountSecond = mainAmount - amountFirst` (handles odd wei)
- Two separate `_resolveLootboxRoll` calls with sequential entropy

This means large lootboxes get two independent rolls, each for half the amount. This doubles the sample from the reward distribution -- the player gets two chances at each reward type. This is a design feature, not a bug.

---

## Section 2: EV Multiplier Formula Verification

### 2.1 `_lootboxEvMultiplierFromScore` (lines 469-490)

The function implements piecewise-linear interpolation:

```solidity
// Branch 1: score <= 6000 BPS (0% to 60% activity)
return 8000 + (score * (10000 - 8000)) / 6000
     = 8000 + (score * 2000) / 6000

// Branch 2: score >= 30500 BPS (305%+ activity)
return 13500

// Branch 3: 6000 < score < 30500 (60% to 305% activity)
excess = score - 6000
maxExcess = 30500 - 6000 = 24500
return 10000 + (excess * (13500 - 10000)) / 24500
     = 10000 + (excess * 3500) / 24500
```

**Numeric verification at boundary points:**

| Score (BPS) | Activity % | Branch | Calculation | Result (BPS) | EV % |
|------------|-----------|--------|-------------|--------------|------|
| 0          | 0%        | 1      | 8000 + (0 * 2000) / 6000 = 8000 | 8000 | 80% |
| 3000       | 30%       | 1      | 8000 + (3000 * 2000) / 6000 = 8000 + 1000 = 9000 | 9000 | 90% |
| 6000       | 60%       | 1      | 8000 + (6000 * 2000) / 6000 = 8000 + 2000 = 10000 | 10000 | 100% |
| 6000       | 60%       | 3*     | 10000 + (0 * 3500) / 24500 = 10000 | 10000 | 100% |
| 18250      | 182.5%    | 3      | 10000 + (12250 * 3500) / 24500 = 10000 + 1750 = 11750 | 11750 | 117.5% |
| 30500      | 305%      | 2      | 13500 | 13500 | 135% |
| 50000      | 500%      | 2      | 13500 | 13500 | 135% |

*At score = 6000, branch 1 applies (condition is `<=`). Branch 3 would also produce 10000. **No discontinuity.**

**Integer division truncation analysis:**

Branch 1: `(score * 2000) / 6000`
- Worst case: score = 1 -> (1 * 2000) / 6000 = 2000 / 6000 = 0 (truncated from 0.333)
- Maximum truncation error: 5999/6000 ~= 1 BPS (0.01%)
- At score = 3 -> (3 * 2000) / 6000 = 6000/6000 = 1. First non-zero.
- **Impact:** At very low activity scores (1-2 BPS), the result is 8000 instead of 8000.33-8000.67. Negligible.

Branch 3: `(excess * 3500) / 24500`
- Maximum truncation error: 24499/24500 ~= 1 BPS (0.01%)
- At excess = 7 -> (7 * 3500) / 24500 = 24500/24500 = 1. First non-zero.
- **Impact:** For excess values 1-6 (scores 6001-6006), result is 10000 instead of 10000.14-10000.86. Negligible.

**Verdict:** Formula is mathematically correct with negligible truncation. No discontinuity at any boundary.

### 2.2 `_applyEvMultiplierWithCap` (lines 500-534)

**Logic trace:**

1. If `evMultiplierBps == 10000` (neutral): return `amount` unchanged, no tracking. **Lines 507-509.**
2. Read `usedBenefit = lootboxEvBenefitUsedByLevel[player][lvl]`. **Line 512.**
3. Compute `remainingCap = LOOTBOX_EV_BENEFIT_CAP - usedBenefit` (or 0 if exhausted). **Lines 513-515.**
4. If cap exhausted (`remainingCap == 0`): return `amount` unchanged. **Lines 517-520.**
5. Split: `adjustedPortion = min(amount, remainingCap)`, `neutralPortion = amount - adjustedPortion`. **Lines 523-524.**
6. Track: `lootboxEvBenefitUsedByLevel[player][lvl] += adjustedPortion`. **Line 527.**
7. Scale: `adjustedValue = (adjustedPortion * evMultiplierBps) / 10000`, return `adjustedValue + neutralPortion`. **Lines 532-533.**

**Cap tracking observation (Research Open Question #2):**

The cap tracks `adjustedPortion` (raw input ETH), NOT the benefit delta `(adjustedValue - adjustedPortion)`. This means:
- At 135% EV with 10 ETH cap: player gets `10 * 1.35 = 13.5 ETH` out of 10 ETH input. Actual benefit = 3.5 ETH.
- At 80% EV with 10 ETH cap: player gets `10 * 0.80 = 8.0 ETH` out of 10 ETH input. Actual "benefit" = -2.0 ETH (penalty).
- In the sub-100% case, the cap still depletes by 10 ETH even though the "benefit" is negative.

**This is conservative design:** The cap depletes faster than the actual EV benefit, making it harder to extract value. A player at 135% EV gets 3.5 ETH total benefit from 10 ETH of cap. A player at 80% EV has their penalty limited to 10 ETH of lootboxes, after which they get neutral 100% EV. **Not a vulnerability.**

### 2.3 Per-Level Cap Enforcement on All Three Resolution Paths

**CRITICAL CHECK: Is `_applyEvMultiplierWithCap` called on all three entry points?**

| Entry Point | EV Multiplier Applied? | Cap Enforced? | Lines |
|------------|----------------------|---------------|-------|
| `openLootBox` | YES - `_applyEvMultiplierWithCap(player, currentLevel, amount, evMultiplierBps)` | YES | 582-591 |
| `openBurnieLootBox` | **NO** - `amountEth` passed directly to `_resolveLootboxCommon` | **NO** | 647-660 |
| `resolveLootboxDirect` | YES - `_applyEvMultiplierWithCap(player, currentLevel, amount, evMultiplierBps)` | YES | 685-686 |

**Finding F01 (Informational):** `openBurnieLootBox` does NOT apply the EV multiplier or enforce the per-level cap. The BURNIE-to-ETH conversion at line 635 uses a fixed 80% rate: `amountEth = (burnieAmount * priceWei * 80) / (PRICE_COIN_UNIT * 100)`. This means BURNIE lootboxes always resolve at 80% of their ETH-equivalent value regardless of activity score. This appears intentional -- BURNIE lootboxes are a secondary reward type already discounted, so no EV multiplier is needed. Additionally, `openBurnieLootBox` passes `allowWhalePass=false, allowLazyPass=false` (line 656-659), further limiting value extraction. **No exploit path -- BURNIE lootboxes cannot be used to bypass the cap since they don't benefit from elevated EV.**

**Summary:** Both ETH-based resolution paths (`openLootBox` and `resolveLootboxDirect`) enforce the 10 ETH per-level cap. The BURNIE lootbox path intentionally does not apply EV scaling.

---

## Section 3: Boon Weight Consistency Audit

### 3.1 Weight Enumeration

**Constants (from lines 399-450):**

| Boon Type | Weight Constant | Value |
|-----------|----------------|-------|
| Coinflip 5% | DEITY_BOON_WEIGHT_COINFLIP_5 | 200 |
| Coinflip 10% | DEITY_BOON_WEIGHT_COINFLIP_10 | 40 |
| Coinflip 25% | DEITY_BOON_WEIGHT_COINFLIP_25 | 8 |
| Lootbox 5% | DEITY_BOON_WEIGHT_LOOTBOX_5 | 200 |
| Lootbox 15% | DEITY_BOON_WEIGHT_LOOTBOX_15 | 30 |
| Lootbox 25% | DEITY_BOON_WEIGHT_LOOTBOX_25 | 8 |
| Purchase 5% | DEITY_BOON_WEIGHT_PURCHASE_5 | 400 |
| Purchase 15% | DEITY_BOON_WEIGHT_PURCHASE_15 | 80 |
| Purchase 25% | DEITY_BOON_WEIGHT_PURCHASE_25 | 16 |
| Decimator 10% | DEITY_BOON_WEIGHT_DECIMATOR_10 | 40 |
| Decimator 25% | DEITY_BOON_WEIGHT_DECIMATOR_25 | 8 |
| Decimator 50% | DEITY_BOON_WEIGHT_DECIMATOR_50 | 2 |
| Whale 10% | DEITY_BOON_WEIGHT_WHALE_10 | 28 |
| Whale 25% | DEITY_BOON_WEIGHT_WHALE_25 | 10 |
| Whale 50% | DEITY_BOON_WEIGHT_WHALE_50 | 2 |
| Deity Pass 10% | DEITY_BOON_WEIGHT_DEITY_PASS_10 | 28 |
| Deity Pass 25% | DEITY_BOON_WEIGHT_DEITY_PASS_25 | 10 |
| Deity Pass 50% | DEITY_BOON_WEIGHT_DEITY_PASS_50 | 2 |
| Activity 10 | DEITY_BOON_WEIGHT_ACTIVITY_10 | 100 |
| Activity 25 | DEITY_BOON_WEIGHT_ACTIVITY_25 | 30 |
| Activity 50 | DEITY_BOON_WEIGHT_ACTIVITY_50 | 8 |
| Whale Pass | DEITY_BOON_WEIGHT_WHALE_PASS | 8 |
| Lazy Pass | DEITY_BOON_WEIGHT_LAZY_PASS | 40 |

**Group totals:**
- Coinflip: 200 + 40 + 8 = 248
- Lootbox boost: 200 + 30 + 8 = 238
- Purchase boost: 400 + 80 + 16 = 496
- Decimator: 40 + 8 + 2 = 50
- Whale discount: 28 + 10 + 2 = 40
- Deity Pass: 28 + 10 + 2 = 40
- Activity: 100 + 30 + 8 = 138
- Whale Pass: 8
- Lazy Pass: 40

**Precomputed constants verified:**
- `DEITY_BOON_WEIGHT_TOTAL = 1298` = 248 + 238 + 496 + 50 + 40 + 40 + 138 + 8 + 40 = 1298. **CORRECT.**
- `DEITY_BOON_WEIGHT_TOTAL_NO_DECIMATOR = 1248` = 1298 - 50 = 1248. **CORRECT.**
- `DEITY_BOON_WEIGHT_DEITY_PASS_ALL = 40` = 28 + 10 + 2 = 40. **CORRECT.**

### 3.2 Weight Consistency: `_boonPoolStats` vs `_boonFromRoll` (All 16 Flag Combinations)

Both functions are called from `_rollLootboxBoons` (line 979) with identical flags:
- `decimatorAllowed` (line 1004)
- `deityEligible` (line 1005-1006)
- `allowWhalePass` (from parameter)
- `lazyPassEligible` (line 1007, also `allowLazyPass` to `_boonFromRoll`)

**`_boonPoolStats` weight accumulation order (lines 1084-1204):**
1. Coinflip 5,10,25: always (248)
2. Lootbox 5,15,25: always (238)
3. Purchase 5,15,25: always (496)
4. Decimator 10,25,50: if `decimatorAllowed` (+50)
5. Whale 10,25,50: always (40)
6. Deity Pass 10,25,50: if `deityEligible` (+40)
7. Activity 10,25,50: always (138)
8. Whale Pass: if `allowWhalePass` (+8)
9. Lazy Pass: if `allowLazyPass && lazyPassValue != 0` (+40)

**`_boonFromRoll` cursor accumulation order (lines 1207-1270):**
1. Coinflip 5,10,25: always (248)
2. Lootbox 5,15,25: always (238)
3. Purchase 5,15,25: always (496)
4. Decimator 10,25,50: if `decimatorAllowed` (+50)
5. Whale 10,25,50: always (40)
6. Deity Pass 10,25,50: if `deityEligible` (+40)
7. Activity 10,25,50: always (138)
8. Whale Pass: if `allowWhalePass` (+8)
9. Lazy Pass: if `allowLazyPass` (+40)

**MATCH.** Both functions include exactly the same weight groups under exactly the same conditions, in exactly the same order.

**Exhaustive 16-combination verification:**

Let D=decimatorAllowed, E=deityEligible, W=allowWhalePass, L=allowLazyPass.

| # | D | E | W | L | _boonPoolStats totalWeight | _boonFromRoll max cursor | Match? |
|---|---|---|---|---|---------------------------|-------------------------|--------|
| 1  | F | F | F | F | 248+238+496+40+138 = 1160 | 1160 | YES |
| 2  | F | F | F | T | 1160 + 40 = 1200 | 1200 | YES |
| 3  | F | F | T | F | 1160 + 8 = 1168 | 1168 | YES |
| 4  | F | F | T | T | 1160 + 8 + 40 = 1208 | 1208 | YES |
| 5  | F | T | F | F | 1160 + 40 = 1200 | 1200 | YES |
| 6  | F | T | F | T | 1160 + 40 + 40 = 1240 | 1240 | YES |
| 7  | F | T | T | F | 1160 + 40 + 8 = 1208 | 1208 | YES |
| 8  | F | T | T | T | 1160 + 40 + 8 + 40 = 1248 | 1248 | YES |
| 9  | T | F | F | F | 1160 + 50 = 1210 | 1210 | YES |
| 10 | T | F | F | T | 1160 + 50 + 40 = 1250 | 1250 | YES |
| 11 | T | F | T | F | 1160 + 50 + 8 = 1218 | 1218 | YES |
| 12 | T | F | T | T | 1160 + 50 + 8 + 40 = 1258 | 1258 | YES |
| 13 | T | T | F | F | 1160 + 50 + 40 = 1250 | 1250 | YES |
| 14 | T | T | F | T | 1160 + 50 + 40 + 40 = 1290 | 1290 | YES |
| 15 | T | T | T | F | 1160 + 50 + 40 + 8 = 1258 | 1258 | YES |
| 16 | T | T | T | T | 1160 + 50 + 40 + 8 + 40 = 1298 | 1298 | YES |

**ALL 16 COMBINATIONS MATCH.**

### 3.3 Fallback Reachability Analysis

The fallback `return DEITY_BOON_ACTIVITY_50` at line 1269 fires if `roll >= cursor` after all conditional sections.

In `_rollLootboxBoons`, the roll passed to `_boonFromRoll` is:
```solidity
(roll * totalWeight) / totalChance    // line 1031
```
where `roll < totalChance` (guaranteed by line 1028). Therefore:
```
mapped_roll = (roll * totalWeight) / totalChance < totalWeight
```
Since `roll < totalChance`, the integer division gives `mapped_roll <= totalWeight - 1`. The maximum cursor in `_boonFromRoll` equals `totalWeight`. Since `mapped_roll < totalWeight = max_cursor`, every roll value will be caught by one of the `if (roll < cursor)` checks before reaching the fallback.

**Verdict: The fallback `return DEITY_BOON_ACTIVITY_50` is UNREACHABLE dead code in the `_rollLootboxBoons` path.** Classified as **Informational** -- dead code that cannot execute but adds confusion.

### 3.4 Deity Boon Slot Weight Consistency (`_deityBoonForSlot`)

The `_deityBoonForSlot` function (line 1733-1747) uses precomputed totals instead of `_boonPoolStats`:

```solidity
uint256 total = decimatorAllowed ? DEITY_BOON_WEIGHT_TOTAL : DEITY_BOON_WEIGHT_TOTAL_NO_DECIMATOR;
if (!deityPassAvailable) total -= DEITY_BOON_WEIGHT_DEITY_PASS_ALL;
uint256 roll = seed % total;
return _boonFromRoll(roll, decimatorAllowed, deityPassAvailable, true, true);
```

Fixed flags: `allowWhalePass=true, allowLazyPass=true`.

**Verification for all 4 deity-boon flag combinations (D=decimatorAllowed, P=deityPassAvailable):**

| D | P | Computed total | _boonFromRoll cursor (W=T, L=T) | Match? |
|---|---|---------------|--------------------------------|--------|
| T | T | 1298 | 248+238+496+50+40+40+138+8+40 = 1298 | YES |
| T | F | 1298-40 = 1258 | 248+238+496+50+40+0+138+8+40 = 1258 | YES |
| F | T | 1248 | 248+238+496+0+40+40+138+8+40 = 1248 | YES |
| F | F | 1248-40 = 1208 | 248+238+496+0+40+0+138+8+40 = 1208 | YES |

**All deity boon slot combinations match.** Fallback is unreachable here too since `roll = seed % total < total = cursor_max`.

---

## Section 4: Additional Safety Checks

### 4.1 VRF Word Existence Guards

| Entry Point | Guard | Line |
|------------|-------|------|
| `openLootBox` | `if (rngWord == 0) revert RngNotReady()` | 553 |
| `openBurnieLootBox` | `if (rngWord == 0) revert RngNotReady()` | 628 |
| `resolveLootboxDirect` | No guard (rngWord is a parameter) | 677 |

`resolveLootboxDirect` is called by other modules (delegatecall) with a known VRF word, so the caller is responsible for providing a valid word. This is correct for its usage context (decimator claims, jackpot resolution).

### 4.2 Lootbox Amount Validation

| Entry Point | Amount Check | Line |
|------------|-------------|------|
| `openLootBox` | `if (amount == 0) revert E()` | 549 |
| `openBurnieLootBox` | `if (burnieAmount == 0) revert E()` + `if (amountEth == 0) revert E()` | 625, 636 |
| `resolveLootboxDirect` | `if (amount == 0) return` (silent return, not revert) | 678 |

The maximum lootbox amount is implicitly bounded by the 232-bit field in `lootboxEth` packing (line 548: `amount = packed & ((1 << 232) - 1)`), which caps at ~6.9e69 wei -- effectively unbounded for practical purposes. However, the lootbox amount is set at purchase time, not at resolution time, so the bound is enforced at the deposit path.

### 4.3 Reentrancy Analysis

**External calls during lootbox resolution:**

1. `coin.creditFlip(player, burnieAmount)` (line 952) -- BURNIE credit. This is an internal accounting call, not an ETH transfer.
2. `dgnrs.transferFromPool(...)` (line 1680) -- DGNRS token transfer. ERC20 transfer to player.
3. `wwxrp.mintPrize(player, wwxrpAmount)` (line 1558) -- WWXRP mint to player.
4. `ContractAddresses.GAME_BOON_MODULE.delegatecall(...)` (lines 934, 991) -- Nested delegatecall for boon operations.

**State updates before external calls:**
- `lootboxEth[index][player] = 0` (line 593) -- cleared BEFORE `_resolveLootboxCommon` is called.
- `lootboxBurnie[index][player] = 0` (line 630) -- cleared BEFORE resolution.

The lootbox entry is zeroed before any external call, preventing reentrancy from re-opening the same lootbox. Token transfers (`dgnrs.transferFromPool`, `wwxrp.mintPrize`) are ERC20 calls that could theoretically call back, but the lootbox slot is already cleared. **No reentrancy vector identified.**

### 4.4 RNG Lock Guard

Both `openLootBox` and `openBurnieLootBox` check `if (rngLockedFlag) revert RngLocked()` (lines 545, 622). This prevents lootbox resolution during jackpot processing. `resolveLootboxDirect` does NOT check `rngLockedFlag`, which is correct since it is called during jackpot/decimator resolution where the lock is expected to be set.

---

## Section 5: DGNRS Reward Tiers

**Location:** `_lootboxDgnrsReward` (line 1647-1672)

```
tierRoll = entropy % 1000;    // line 1651
```

| Tier | Roll Range | Probability | PPM | Description |
|------|-----------|-------------|-----|-------------|
| Small | 0-794 | 79.5% | 10 | 0.001% of pool per ETH |
| Medium | 795-944 | 15% | 390 | 0.039% of pool per ETH |
| Large | 945-994 | 5% | 800 | 0.08% of pool per ETH |
| Mega | 995-999 | 0.5% | 8000 | 0.8% of pool per ETH |

Sum: 795 + 150 + 50 + 5 = 1000. **CORRECT.**

The reward is computed as `(poolBalance * ppm * amount) / (1_000_000 * 1 ether)` with a cap at `poolBalance` (line 1669). The formula is correct for the stated pool-fraction-per-ETH mechanic.

---

## Section 6: MATH-05 Partial Verdict

**MATH-05:** "Lootbox EV multiplier formula produces expected values; activity score cannot create guaranteed positive EV extraction"

### Verdict: PASS (Conditional -- Full EV Model Deferred to 03b-03)

**Formula correctness: CONFIRMED.**
1. The piecewise-linear formula produces correct values at all tested boundary points (0%, 60%, 182.5%, 305%, >305%).
2. No discontinuity exists at the branch boundaries (score=6000, score=30500).
3. Integer division truncation is negligible (max 1 BPS = 0.01%).

**Cap enforcement: CONFIRMED on both ETH-based paths.**
1. `openLootBox`: calls `_applyEvMultiplierWithCap`. **Enforced.**
2. `resolveLootboxDirect`: calls `_applyEvMultiplierWithCap`. **Enforced.**
3. `openBurnieLootBox`: intentionally bypasses EV multiplier (hardcoded 80% rate). **Not applicable -- no exploit path.**

**Cap design: Conservative.**
- Tracks raw input amount (not benefit delta), depleting faster than actual benefit
- Maximum extractable benefit at 135% EV: 3.5 ETH per 10 ETH of cap per level
- Cap resets per level but activity score maintenance requires ongoing investment

**Remaining question for 03b-03:** Whether the total expected lootbox EV (across all reward paths) at 135% multiplier exceeds deposit value when accounting for ticket, BURNIE, DGNRS, and WWXRP combined returns. The formula is confirmed correct; the full economic model is needed to determine if the combined paths create positive-EV at any activity tier.

---

## Section 7: Findings Summary

### F01 - `openBurnieLootBox` Does Not Apply EV Multiplier (Informational)

**Severity:** Informational
**Location:** Lines 621-670
**Description:** `openBurnieLootBox` resolves at a hardcoded 80% ETH-equivalent rate without applying the activity-score-based EV multiplier or the per-level cap. This is consistent with BURNIE lootboxes being a secondary, pre-discounted reward type.
**Risk:** None. BURNIE lootboxes cannot be used to bypass the EV cap since they are always resolved at sub-100% EV. Players cannot profitably deposit BURNIE to extract elevated EV.
**Recommendation:** Document this design choice in code comments for clarity.

### F02 - Fallback `return DEITY_BOON_ACTIVITY_50` is Unreachable Dead Code (Informational)

**Severity:** Informational
**Location:** Line 1269
**Description:** The final `return DEITY_BOON_ACTIVITY_50` in `_boonFromRoll` can never execute because: (a) in `_rollLootboxBoons`, the mapped roll is always `< totalWeight`, and the cursor covers exactly `totalWeight` units; (b) in `_deityBoonForSlot`, `roll = seed % total` where `total` equals the cursor range.
**Risk:** None. Dead code does not affect execution.
**Recommendation:** Add a comment `// unreachable: defensive fallback` or use `assert(false)` to make the intent explicit.

### F03 - Target Level Roll Reuses Entropy Word for Two Selections (Informational)

**Severity:** Informational
**Location:** Lines 786-796
**Description:** In the near-future path (95%), `levelEntropy` is used for both `rangeRoll = levelEntropy % 100` (determining near vs far) and `levelOffset = levelEntropy % 6` (determining exact offset). Since GCD(100, 6) = 2, there is a weak correlation: if `rangeRoll` is even, `levelOffset` is also even. However, with VRF-seeded 256-bit entropy, this correlation is overwhelmed by the word's entropy content and creates negligible statistical deviation.
**Risk:** Negligible. No exploitable bias.
**Recommendation:** None required. If desired, an additional `entropyStep` could be used for the level offset to fully decorrelate the two selections.

### F04 - BURNIE Low Path Documentation Range Discrepancy (Informational)

**Severity:** Informational
**Location:** Lines 297-299, research documentation
**Description:** Research and plan documentation describes the BURNIE low path as "58%-134%" but the actual computed range from the constants is 58.08% to 129.63% (base 5808 + 15 * 477 = 12963 BPS). The upper bound is 129.63%, not 134%.
**Risk:** None. Documentation discrepancy only; no code issue.
**Recommendation:** Update documentation to reflect the actual range: 58.08% to 129.63%.

---

## Appendix A: Complete EntropyStep Chain Map

For `openLootBox` resolving a lootbox above 0.5 ETH (split into two rolls):

```
keccak256(rngWord, player, day, amount)
    |
    v
[E0] = initial entropy
    |
[E1] = entropyStep(E0)                  --> rangeRoll = E1 % 100 (target level near/far)
    |
    +-- if rangeRoll < 5:
    |   [E1a] = entropyStep(E1)          --> levelOffset = (E1a % 46) + 5
    |   nextEntropy = E1a
    +-- else:
    |   levelOffset = E1 % 6
    |   nextEntropy = E1
    |
    v
[Roll 1: amountFirst = mainAmount/2]
[E2] = entropyStep(nextEntropy)          --> rewardRoll = E2 % 20
    |
    +-- if rewardRoll < 11 (tickets):
    |   [E3] = entropyStep(E2)           --> varianceRoll = E3 % 10000 (tier selection)
    |   nextEntropy = E3
    +-- if rewardRoll < 13 (DGNRS):
    |   [E3] = entropyStep(E2)           --> tierRoll = E3 % 1000 (DGNRS tier)
    |   nextEntropy = E3
    +-- if rewardRoll < 15 (WWXRP):
    |   [E3] = entropyStep(E2)           --> (consumed but unused for WWXRP selection)
    |   nextEntropy = E3
    +-- else (BURNIE):
        [E3] = entropyStep(E2)           --> varianceRoll = E3 % 20 (low/high path)
        nextEntropy = E3
    |
    v
[Roll 2: amountSecond = mainAmount - amountFirst]
[E4] = entropyStep(E3)                  --> rewardRoll = E4 % 20
    ... (same structure as Roll 1)
    |
    v
[Boon Roll]
boonRoll = finalEntropy % 1_000_000     --> boon selection
```

## Appendix B: Constant Cross-Reference

| Constant Name | Value | Used In | Verified |
|--------------|-------|---------|----------|
| ACTIVITY_SCORE_NEUTRAL_BPS | 6,000 | _lootboxEvMultiplierFromScore | YES |
| ACTIVITY_SCORE_MAX_BPS | 30,500 | _lootboxEvMultiplierFromScore | YES |
| LOOTBOX_EV_MIN_BPS | 8,000 | _lootboxEvMultiplierFromScore | YES |
| LOOTBOX_EV_NEUTRAL_BPS | 10,000 | _lootboxEvMultiplierFromScore, _applyEvMultiplierWithCap | YES |
| LOOTBOX_EV_MAX_BPS | 13,500 | _lootboxEvMultiplierFromScore | YES |
| LOOTBOX_EV_BENEFIT_CAP | 10 ether | _applyEvMultiplierWithCap | YES |
| LOOTBOX_TICKET_ROLL_BPS | 16,100 | _resolveLootboxRoll | YES |
| LOOTBOX_SPLIT_THRESHOLD | 0.5 ether | _resolveLootboxCommon | YES |
| LOOTBOX_BOON_BUDGET_BPS | 1,000 | _resolveLootboxCommon | YES |
| LOOTBOX_BOON_MAX_BUDGET | 1 ether | _resolveLootboxCommon | YES |
| BOON_PPM_SCALE | 1,000,000 | _rollLootboxBoons | YES |
| DEITY_BOON_WEIGHT_TOTAL | 1,298 | _deityBoonForSlot | YES |
| DEITY_BOON_WEIGHT_TOTAL_NO_DECIMATOR | 1,248 | _deityBoonForSlot | YES |
| DEITY_BOON_WEIGHT_DEITY_PASS_ALL | 40 | _deityBoonForSlot | YES |

---

*Audit performed: 2026-03-01*
*Auditor: Claude Opus 4.6*
*Contract: DegenerusGameLootboxModule.sol (1749 lines)*
*No contract files were modified during this audit.*
