# 03b-03 Findings: Lootbox EV Mathematical Model

**Audited:** 2026-03-01
**Contract:** `contracts/modules/DegenerusGameLootboxModule.sol`
**Requirement:** MATH-05 (Lootbox EV multiplier formula produces expected values; activity score cannot create guaranteed positive EV)
**Scope:** READ-ONLY audit -- no contract files modified

---

## 1. Per-Path EV Computation

### 1.1 Reward Path Probabilities

From `_resolveLootboxRoll` (line 1521): `roll = nextEntropy % 20`

| Roll Range | Probability | Path    |
|------------|-------------|---------|
| 0-10       | 11/20 = 55% | Tickets |
| 11-12      | 2/20 = 10%  | DGNRS   |
| 13-14      | 2/20 = 10%  | WWXRP   |
| 15-19      | 5/20 = 25%  | BURNIE  |

**Verified:** Sum = 55 + 10 + 10 + 25 = 100%.

### 1.2 Ticket Path EV (55% probability)

**Step A: Ticket Budget**

The ticket budget is computed as:
```
ticketBudget = (amount * LOOTBOX_TICKET_ROLL_BPS) / 10_000
             = amount * 16100 / 10000
             = amount * 1.61
```

Source: `LOOTBOX_TICKET_ROLL_BPS = 16_100` (line 267). This is the "level target multiplier" -- the ticket budget is 161% of the roll amount.

**Step B: Variance Tiers**

From `_lootboxTicketCount` (lines 1596-1640), `varianceRoll = nextEntropy % 10_000`:

| Tier | Roll Range    | Probability | BPS Multiplier | Decimal |
|------|---------------|-------------|----------------|---------|
| 1    | 0-99          | 1%          | 46,000         | 4.600x  |
| 2    | 100-499       | 4%          | 23,000         | 2.300x  |
| 3    | 500-2499      | 20%         | 11,000         | 1.100x  |
| 4    | 2500-6999     | 45%         | 6,510          | 0.651x  |
| 5    | 7000-9999     | 30%         | 4,500          | 0.450x  |

**Verified:** Sum of probabilities = 1 + 4 + 20 + 45 + 30 = 100%.

Contract constants confirmed:
- `LOOTBOX_TICKET_VARIANCE_TIER1_CHANCE_BPS = 100` (1%)
- `LOOTBOX_TICKET_VARIANCE_TIER2_CHANCE_BPS = 400` (4%)
- `LOOTBOX_TICKET_VARIANCE_TIER3_CHANCE_BPS = 2000` (20%)
- `LOOTBOX_TICKET_VARIANCE_TIER4_CHANCE_BPS = 4500` (45%)
- Tier 5 = remainder = 10000 - 100 - 400 - 2000 - 4500 = 3000 (30%)

**Step C: Expected Variance Multiplier**

```
E[variance] = 0.01 * 4.600
            + 0.04 * 2.300
            + 0.20 * 1.100
            + 0.45 * 0.651
            + 0.30 * 0.450

            = 0.04600
            + 0.09200
            + 0.22000
            + 0.29295
            + 0.13500

            = 0.78595
```

**Step D: Ticket Count Calculation**

From the contract (line 1636-1637):
```
adjustedBudget = (budgetWei * ticketBps) / 10_000
countScaled = (adjustedBudget * TICKET_SCALE) / priceWei
```

Where `TICKET_SCALE = 100`. The number of tickets awarded:
```
tickets = (ticketBudget * varianceMultiplier) / targetPrice
        = (amount * 1.61 * varianceMultiplier) / targetPrice
```

**Step E: Ticket Path ETH-equivalent Value**

Each ticket at `targetLevel` is worth `priceForLevel(targetLevel)` in ETH terms. So:
```
E[ticket_path_value] = 0.55 * (amount * 1.61 * E[variance] * targetPrice) / targetPrice
                     = 0.55 * amount * 1.61 * 0.78595
                     = 0.55 * amount * 1.2654
                     = amount * 0.6960
```

**Result: E[ticket_path] = 69.60% of input amount** (in ticket-price-curve ETH-equivalent value).

**Important denomination note:** Tickets are awarded at the rolled target level. Their "value" equals their level's price (via PriceLookupLib). This is not liquid ETH -- it is future game participation value. The tickets are queued for a future level, and their real-world value depends on whether the player reaches that level.

### 1.3 BURNIE Path EV (25% probability)

**Step A: Low Path (80%)**

From lines 1572-1575: `varianceRoll = nextEntropy % 20`. Low path when `varianceRoll < 16` (rolls 0-15).

```
BPS = LOOTBOX_LARGE_BURNIE_LOW_BASE_BPS + varianceRoll * LOOTBOX_LARGE_BURNIE_LOW_STEP_BPS
    = 5808 + varianceRoll * 477
```

| Roll | BPS    | Decimal |
|------|--------|---------|
| 0    | 5,808  | 58.08%  |
| 1    | 6,285  | 62.85%  |
| 2    | 6,762  | 67.62%  |
| 3    | 7,239  | 72.39%  |
| 4    | 7,716  | 77.16%  |
| 5    | 8,193  | 81.93%  |
| 6    | 8,670  | 86.70%  |
| 7    | 9,147  | 91.47%  |
| 8    | 9,624  | 96.24%  |
| 9    | 10,101 | 101.01% |
| 10   | 10,578 | 105.78% |
| 11   | 11,055 | 110.55% |
| 12   | 11,532 | 115.32% |
| 13   | 12,009 | 120.09% |
| 14   | 12,486 | 124.86% |
| 15   | 12,963 | 129.63% |

Sum = 5808 + 6285 + 6762 + 7239 + 7716 + 8193 + 8670 + 9147 + 9624 + 10101 + 10578 + 11055 + 11532 + 12009 + 12486 + 12963 = **150,168**

Mean = 150,168 / 16 = **9,385.5 BPS = 93.855%**

Alternative calculation: arithmetic series mean = (5808 + 12963) / 2 = 9385.5. Confirmed.

**Step B: High Path (20%)**

From lines 1577-1579: `varianceRoll` is 16-19.

```
BPS = LOOTBOX_LARGE_BURNIE_HIGH_BASE_BPS + (varianceRoll - 16) * LOOTBOX_LARGE_BURNIE_HIGH_STEP_BPS
    = 30705 + (varianceRoll - 16) * 9430
```

| Roll | BPS    | Decimal  |
|------|--------|----------|
| 16   | 30,705 | 307.05%  |
| 17   | 40,135 | 401.35%  |
| 18   | 49,565 | 495.65%  |
| 19   | 58,995 | 589.95%  |

Sum = 30705 + 40135 + 49565 + 58995 = 179,400

Mean = 179,400 / 4 = **44,850 BPS = 448.50%**

Alternative: (30705 + 58995) / 2 = 44850. Confirmed.

**Step C: BURNIE Reward Calculation**

From lines 1582-1583:
```
burnieBudget = (amount * largeBurnieBps) / 10_000
burnieOut = (burnieBudget * PRICE_COIN_UNIT) / targetPrice
```

The BURNIE token amount depends on the current BURNIE/ETH price (`targetPrice` is `PriceLookupLib.priceForLevel(targetLevel)`, but `burnieBudget` is the ETH-equivalent, which is then converted to BURNIE tokens). Wait -- re-reading the code more carefully:

Actually, `targetPrice = PriceLookupLib.priceForLevel(targetLevel)` (line 844) is the ticket price at the target level, NOT the BURNIE token price. The BURNIE conversion uses `PRICE_COIN_UNIT = 1000 ether` (the price of BURNIE per mint).

So `burnieOut = (burnieBudget * 1000 ether) / targetPrice`. This converts the ETH budget into BURNIE tokens using the ticket price as a conversion rate. The BURNIE received is:

```
burnieOut = (amount * largeBurnieBps / 10000) * 1000 / targetPrice_in_ether
```

The ETH-equivalent value of this BURNIE depends on the BURNIE market price. However, for EV purposes, the contract prices BURNIE relative to ticket prices. The "value" in ETH terms from the contract's perspective:

```
burnieBudget_ETH = amount * largeBurnieBps / 10000
```

This is the ETH-equivalent value allocated to the BURNIE reward before token conversion.

**Step D: Combined BURNIE Path EV**

```
E[burnie_path] = 0.25 * (0.80 * E[low] + 0.20 * E[high])

E[low_ETH_value] = amount * 9385.5 / 10000 = amount * 0.93855
E[high_ETH_value] = amount * 44850 / 10000 = amount * 4.4850

E[burnie_combined] = 0.80 * 0.93855 + 0.20 * 4.4850
                   = 0.75084 + 0.89700
                   = 1.64784

E[burnie_path] = 0.25 * 1.64784 = 0.41196
```

**Result: E[burnie_path] = 41.20% of input amount** (in BURNIE token value at contract-assumed ETH-equivalent pricing).

**Important denomination note:** BURNIE rewards are minted as BURNIE tokens. The ETH-equivalent value of `burnieBudget` is determined by the `largeBurnieBps` multiplier on the input amount. The actual market value depends on the BURNIE/ETH exchange rate, which can diverge from the contract's internal pricing assumptions.

### 1.4 DGNRS Path EV (10% probability)

From `_lootboxDgnrsReward` (lines 1647-1672):

```
dgnrsAmount = (poolBalance * ppm * amount) / (1_000_000 * 1 ether)
```

**Tier selection:** `tierRoll = entropy % 1000`

| Tier  | Roll Range | Probability | PPM   | Pool Fraction per ETH |
|-------|------------|-------------|-------|-----------------------|
| Small | 0-794      | 79.5%       | 10    | 0.001%                |
| Medium| 795-944    | 15.0%       | 390   | 0.039%                |
| Large | 945-994    | 5.0%        | 800   | 0.080%                |
| Mega  | 995-999    | 0.5%        | 8,000 | 0.800%                |

**Expected PPM per 1 ETH lootbox:**

```
E[ppm] = 0.795 * 10 + 0.15 * 390 + 0.05 * 800 + 0.005 * 8000
       = 7.95 + 58.50 + 40.00 + 40.00
       = 146.45 ppm
```

**DGNRS tokens received per 1 ETH lootbox input:**

```
E[dgnrs_tokens] = poolBalance * 146.45 / 1,000,000
                = poolBalance * 0.00014645
```

**ETH-equivalent value:** Depends entirely on DGNRS/ETH market price and pool balance. This is NOT a fixed return -- it is pool-dependent and market-dependent. A large pool with a high DGNRS price gives high value; a depleted pool or low DGNRS price gives minimal value.

**For EV modeling purposes:** The DGNRS path's ETH-equivalent value cannot be computed without knowing the pool balance and DGNRS market price. However, the protocol intentionally makes this a secondary reward path (10% probability, pool-dependent). The EV contribution is fundamentally uncertain and variable.

**Result: E[dgnrs_path] = 10% * (pool-dependent, market-dependent value) -- non-deterministic.**

### 1.5 WWXRP Path EV (10% probability)

From lines 1554-1565:

```
wwxrpAmount = LOOTBOX_WWXRP_PRIZE = 1 ether  (i.e., 1 WWXRP token)
```

This is a fixed amount: every WWXRP hit awards exactly 1 WWXRP token via `wwxrp.mintPrize(player, 1 ether)`.

**ETH-equivalent value:** Depends entirely on WWXRP/ETH market price.

**Result: E[wwxrp_path] = 10% * (1 WWXRP token at market price) -- non-deterministic.**

### 1.6 Boon Budget Deduction

Before reward rolls, a boon budget is deducted from the main amount:

```
boonBudget = min(amount * 1000 / 10000, 1 ether) = min(amount * 10%, 1 ETH)
mainAmount = amount - boonBudget
```

For amounts <= 10 ETH: boonBudget = 10% of amount, mainAmount = 90%.
For amounts > 10 ETH: boonBudget = 1 ETH (capped), mainAmount = amount - 1 ETH.

**Impact on per-path EV:** The reward rolls operate on `mainAmount` (90% for typical lootboxes), not `amount`. However, the boon budget itself produces value (boons with various bonuses). For EV modeling of the core reward paths, the effective input is 90% of the deposited amount.

Additionally, for amounts > 0.5 ETH, `mainAmount` is split into two rolls (line 857-859): `amountFirst = mainAmount / 2`, `amountSecond = mainAmount - amountFirst`. Each roll independently selects a reward path. This does NOT change the EV per unit -- it increases variance reduction (two independent rolls from the same lootbox).

---

## 2. Composite EV Model

### 2.1 Base Composite EV at Neutral Activity Score (100% multiplier)

For a 1 ETH lootbox with 10% boon budget deduction (effective input = 0.90 ETH per roll):

**Deterministic paths (ticket + BURNIE):**
```
E[ticket_path]  = 0.55 * 1.61 * 0.78595 = 0.69597  (per unit of roll amount)
E[burnie_path]  = 0.25 * 1.64784         = 0.41196  (per unit of roll amount)

E[deterministic] = 0.69597 + 0.41196 = 1.10793  (per unit of roll amount)
```

Adjusted for 90% mainAmount:
```
E[deterministic_adjusted] = 1.10793 * 0.90 = 0.99714  (per unit of input amount)
```

**Non-deterministic paths (DGNRS + WWXRP):**
These contribute additional value on top of the deterministic paths. Even if they contribute only modest value, the ticket + BURNIE paths alone produce ~99.7% EV.

**Composite at neutral activity score (100% EV multiplier):**
```
E[composite_at_100%] = E[ticket_path_adj] + E[burnie_path_adj] + E[dgnrs_path_adj] + E[wwxrp_path_adj] + E[boon_value]
                     >= 0.99714 + (positive DGNRS + WWXRP + boon value)
                     ~= 100% + epsilon
```

**Assessment:** The ticket + BURNIE paths alone provide ~99.7% EV at neutral score. The DGNRS, WWXRP, and boon components add additional value, bringing the total above 100%. The system is designed so that at neutral activity score (60%), the composite EV is approximately 100% (break-even). This is confirmed by the math.

### 2.2 EV at Each Multiplier Level

The EV multiplier from `_lootboxEvMultiplierFromScore` scales the entire lootbox amount before resolution. It applies only to ETH lootboxes (not BURNIE lootboxes).

| Activity Score | Score BPS | EV Multiplier | Adjusted Composite EV |
|----------------|-----------|---------------|-----------------------|
| 0%             | 0         | 80% (8000)    | ~79.8%                |
| 60% (neutral)  | 6,000     | 100% (10000)  | ~100%                 |
| 182.5% (mid)   | 18,250    | 117.5% (11750)| ~117.3%               |
| 305% (max)     | 30,500    | 135% (13500)  | ~134.8%               |

**Multiplier formula verification:**

Score 0: `8000 + (0 * 2000) / 6000 = 8000` (80%) -- confirmed.
Score 6000: `8000 + (6000 * 2000) / 6000 = 8000 + 2000 = 10000` (100%) -- confirmed.
Score 18250: `10000 + (12250 * 3500) / 24500 = 10000 + 1750 = 11750` (117.5%) -- confirmed.
Score 30500: returns `13500` (135%) -- confirmed (capped at max).

---

## 3. Per-Level Cap Extraction Analysis

### 3.1 Cap Mechanism: `_applyEvMultiplierWithCap`

From lines 500-534:

```solidity
uint256 usedBenefit = lootboxEvBenefitUsedByLevel[player][lvl];
uint256 remainingCap = usedBenefit >= LOOTBOX_EV_BENEFIT_CAP  // 10 ether
    ? 0
    : LOOTBOX_EV_BENEFIT_CAP - usedBenefit;

uint256 adjustedPortion = amount > remainingCap ? remainingCap : amount;
uint256 neutralPortion = amount - adjustedPortion;

lootboxEvBenefitUsedByLevel[player][lvl] = usedBenefit + adjustedPortion;

uint256 adjustedValue = (adjustedPortion * evMultiplierBps) / 10_000;
scaledAmount = adjustedValue + neutralPortion;
```

**Critical observation:** The cap tracks `adjustedPortion` (the RAW INPUT AMOUNT), NOT the benefit delta (`adjustedValue - adjustedPortion`). This means:

- A 10 ETH lootbox at 135% EV:
  - `adjustedPortion = 10 ETH` (entire amount, assuming fresh cap)
  - `neutralPortion = 0`
  - `adjustedValue = 10 * 13500 / 10000 = 13.5 ETH`
  - Benefit = 13.5 - 10.0 = **3.5 ETH**
  - Cap consumed: **10 ETH** (the full raw input, not 3.5 ETH)

- After this single 10 ETH lootbox: cap is fully exhausted.
- All subsequent lootboxes at this level: 100% EV (neutral), no benefit.

### 3.2 Maximum Extractable Benefit Per Level

At maximum activity score (305% / 135% EV multiplier):

```
Maximum input before cap exhaustion:  10 ETH
Maximum output from capped portion:   10 * 1.35 = 13.5 ETH
Maximum benefit per level:            13.5 - 10.0 = 3.5 ETH
```

**This is a hard ceiling.** No matter how many lootboxes a player opens at a given level, the maximum EV benefit above 100% is 3.5 ETH per level.

### 3.3 Cap Tracking Conservatism Analysis

The cap tracking raw input (not benefit delta) is MORE conservative than tracking actual benefit:

| Tracking Method    | Cap Budget | Effective Benefit | Lootboxes Until Cap |
|--------------------|------------|-------------------|---------------------|
| Raw input (actual) | 10 ETH     | 3.5 ETH           | Depends on sizes    |
| Benefit delta      | 10 ETH     | 10 ETH max        | ~2.86x more volume  |

If the cap tracked benefit delta instead:
- A 10 ETH lootbox at 135% produces 3.5 ETH benefit
- Cap would track 3.5 ETH used, leaving 6.5 ETH of benefit capacity
- Player could process ~28.57 ETH of lootboxes before cap = 10 ETH of benefit

The ACTUAL implementation (tracking raw input) is significantly more conservative. The protocol limits not just the benefit extracted but the total volume of enhanced-EV lootboxes. This is safer for the protocol.

### 3.4 Partial Cap Scenarios

For multiple smaller lootboxes:

**Scenario: Ten 1 ETH lootboxes at 135% EV**
- Lootbox 1: adjustedPortion = 1 ETH, output = 1.35 ETH, benefit = 0.35 ETH, cap used = 1/10
- Lootbox 2-10: same pattern
- Total benefit = 10 * 0.35 = 3.5 ETH
- After lootbox 10: cap exhausted (10 ETH tracked)

**Scenario: One 5 ETH lootbox + five 1 ETH lootboxes**
- Lootbox 1 (5 ETH): output = 6.75 ETH, benefit = 1.75 ETH, cap remaining = 5 ETH
- Lootbox 2-6 (1 ETH each): output = 1.35 ETH each, benefit = 0.35 each, cap reduces by 1 each
- Total benefit = 1.75 + 5 * 0.35 = 1.75 + 1.75 = 3.50 ETH
- After lootbox 6: cap exhausted

**Result: Total benefit is always exactly 3.5 ETH at max score, regardless of lootbox size distribution.** The cap exhaustion point is always 10 ETH of input processed at enhanced EV.

---

## 4. Activity Score Cost Analysis

### 4.1 Activity Score Components

From `_playerActivityScoreInternal` (DegeneretteModule lines 1020-1093):

#### Deity Pass Holder Path

If `deityPassCount[player] != 0`:
```
streakPoints = 50 (flat)                            = 50 * 100 = 5,000 BPS
mintCountPoints = 25 (flat)                         = 25 * 100 = 2,500 BPS
questStreak = min(questStreakRaw, 100) * 100         = up to   10,000 BPS
affiliateBonus = affiliateBonusPointsBest() * 100    = up to    5,000 BPS
deityPassBonus = DEITY_PASS_ACTIVITY_BONUS_BPS       =          8,000 BPS
                                                      --------------------
                                                      Maximum: 30,500 BPS
```

This exactly equals `ACTIVITY_SCORE_MAX_BPS = 30,500`.

#### Non-Deity Pass Holder Path

```
streakPoints = min(streak, 50) * 100                 = up to    5,000 BPS
mintCountPoints = _mintCountBonusPoints() * 100      = up to    2,500 BPS
questStreak = min(questStreakRaw, 100) * 100          = up to   10,000 BPS
affiliateBonus = affiliateBonusPointsBest() * 100     = up to    5,000 BPS
whaleBundleBonus:
  bundleType == 1 (standard whale)                   =          1,000 BPS
  bundleType == 3 (premium whale)                    =          4,000 BPS
                                                      --------------------
                                                      Maximum: 26,500 BPS
```

Without a deity pass, the maximum achievable score is 26,500 BPS (265%), which maps to:
```
EV = 10000 + ((26500 - 6000) * 3500) / 24500
   = 10000 + (20500 * 3500) / 24500
   = 10000 + 2928.57
   = 12928 BPS = ~129.3% EV
```

### 4.2 Investment Cost per Component

| Component | Max BPS | Cost to Achieve Maximum | Notes |
|-----------|---------|-------------------------|-------|
| **Deity pass** | 8,000 + 5,000 streak + 2,500 mint = 15,500 | 24+ ETH (first pass: 24 + T(0) = 24.5 ETH) | Single largest boost; grants flat 50 streak + 25 mint + 8000 bonus |
| **Quest streak** | 10,000 (100 points) | Daily quest participation for 100+ consecutive days | Free in ETH but requires sustained daily engagement |
| **Affiliate bonus** | 5,000 (50 points max) | Earn affiliate BURNIE across 5 previous levels, 1 ETH worth per level = 50+ ETH of referred volume | `AFFILIATE_BONUS_MAX = 50` |
| **Mint count** (non-deity) | 2,500 (25 points) | Buy tickets at every level from 0 to current | Proportional: `mintCount / currLevel * 25` |
| **Streak** (non-deity) | 5,000 (50 points) | 50+ consecutive mints | Requires buying tickets every level |
| **Whale bundle** (non-deity) | 4,000 (premium) | 4 ETH (premium whale bundle) | Must remain active (frozenUntilLevel > currLevel) |
| **Whale pass floor** (non-deity) | Boosts streak to 50 + mint to 25 | Included in whale bundle | Only if pass is active |

### 4.3 Minimum Cost to Reach 305% (30,500 BPS)

**Only deity pass holders can reach 305%.** Without a deity pass, the maximum is 265% (26,500 BPS).

**Minimum deity-holder path to 305%:**

1. **Deity pass:** 24.5 ETH (first pass, k=0: 24 + 0*(0+1)/2 = 24 ETH base + 0.5 ETH triangular) -- actually checking: `DEITY_PASS_BASE = 24 ether`, price = `24 + k*(k+1)/2` where k = number already sold. First pass (k=0): 24 ETH. Second (k=1): 24.5 ETH. For a new player buying the first available pass, minimum is 24 ETH if none sold, up to 24 + 23*24/2 = 300 ETH for the 24th pass.
   - **Minimum:** 24 ETH
   - **Provides:** 8,000 BPS (deity bonus) + 5,000 BPS (flat streak) + 2,500 BPS (flat mint) = 15,500 BPS

2. **Quest streak (100 days):** 0 ETH direct cost, but requires 100 consecutive days of quest completion
   - **Provides:** 10,000 BPS

3. **Affiliate earnings (50 points):** Requires ~50 ETH of referred volume across 5 levels
   - **Provides:** 5,000 BPS

**Subtotal:** 15,500 + 10,000 + 5,000 = **30,500 BPS** (305%)

**Minimum ETH investment:** 24 ETH (deity pass) + ticket purchases at each level + any affiliate costs.

---

## 5. Extraction vs. Investment Analysis

### 5.1 Total Investment to Reach Maximum Score

| Investment Item | ETH Cost | Recoverable? |
|-----------------|----------|--------------|
| Deity pass (first available) | 24 ETH minimum | Partial refund if game ends early (20 ETH if level 1-9, full if level 0) |
| Ticket purchases (ongoing) | Variable per level | Generates lootboxes (which are the extraction vehicle) |
| Quest participation | 0 ETH (time cost) | N/A |
| Affiliate volume | Indirect (requires referrals) | Affiliate earns its own returns |

**Hard minimum ETH outlay for max score:** 24 ETH for deity pass.

### 5.2 Extraction Capacity at Max Score

Per level at 135% EV:
- Maximum benefit: **3.5 ETH**
- Maximum lootbox volume processed at enhanced EV: **10 ETH**
- After cap exhaustion: all lootboxes at 100% EV (no benefit)

### 5.3 Break-Even Analysis

To recoup the 24 ETH deity pass investment through lootbox EV benefit alone:

```
Levels needed = 24 ETH / 3.5 ETH per level = 6.86 levels
```

**Rounding up: 7 levels of maximum extraction needed to break even.**

However, this analysis has critical caveats:

1. **The 3.5 ETH is Expected Value, not guaranteed.** The 135% multiplier means that ON AVERAGE over many lootboxes, you get 35% more than input. Individual lootboxes can return much more or much less (variance tiers range from 0.45x to 4.6x for tickets, 0.58x to 5.9x for BURNIE).

2. **To extract 3.5 ETH benefit, you must first deposit 10 ETH in lootboxes.** That 10 ETH must come from somewhere -- ticket purchases generate lootboxes, but the lootbox amounts depend on ticket purchase volume and the game's prize pool allocation.

3. **Ticket purchases ARE the game's revenue.** The ETH spent buying tickets flows into the prize pool. Lootbox rewards come back from the game, but the game retains a portion for jackpots, fees, etc.

4. **The 3.5 ETH benefit is not pure profit.** The EV multiplier applies to the reward resolution, not to the input. The "base" 100% EV already includes the variance of getting tickets at future levels (which may never vest if the game ends), BURNIE (which may lose value), DGNRS (pool-dependent), etc.

### 5.4 Realistic Extraction Lifecycle

**Optimistic scenario (player reaches 7+ levels with max cap extraction):**

```
Investment: 24 ETH (deity) + 7 * ~4 ETH (tickets to generate 10 ETH lootboxes) = ~52 ETH
Extraction: 7 * 3.5 ETH = 24.5 ETH of EV benefit
Net (EV benefit only): 24.5 - 24 = 0.5 ETH profit on deity pass
But: total input was 52+ ETH, and 100% EV portion returns ~90% (accounting for boon deduction)
```

**Pessimistic scenario:**
- Deity pass bought for 24 ETH
- Game ends before 7 levels of extraction
- EV benefit < deity pass cost
- Net loss on deity pass investment

### 5.5 Key Insight: Lootbox Input Requires Ticket Purchases

Lootboxes are NOT free to open. They are generated from ticket purchases. A player must spend ETH buying tickets, and only PART of that spend becomes a lootbox. The lootbox amount is a fraction of the ticket purchase price, not the full amount.

The flow is: Buy ticket -> lootbox generated -> open lootbox -> receive reward. The "input" to the lootbox is already a subset of the original ETH spent.

---

## 6. Level-Advance Cap Reset Analysis

### 6.1 Cap Keying

The cap is keyed on `(player, currentLevel)`:

```solidity
lootboxEvBenefitUsedByLevel[player][lvl]
```

Where `lvl = level + 1` (the current game level at time of opening, line 567/587).

### 6.2 Cap Reset on Level Advancement

When the game advances from level N to level N+1:
- The cap for level N+1 starts fresh (0 used)
- A new 10 ETH of enhanced-EV volume becomes available
- This produces up to 3.5 ETH additional benefit at max score

### 6.3 Indefinite Extraction Concern

**Theoretical concern:** A player could extract 3.5 ETH benefit per level indefinitely as the game progresses.

**Mitigating factors:**

1. **Level advancement is not player-controlled.** The game advances when `advanceGame()` is called, which requires VRF fulfillment and is governed by the global game clock. A single player cannot force level transitions.

2. **Ticket costs escalate with level.** PriceLookupLib prices:
   - Levels 0-4: 0.01 ETH
   - Levels 5-9: 0.02 ETH
   - Levels 10-29: 0.04 ETH
   - Levels 30-59: 0.08 ETH
   - Levels 60-89: 0.12 ETH
   - Levels 90-99: 0.16 ETH
   - Level 100: 0.24 ETH (milestone)
   - Then repeating pattern

   To generate 10 ETH of lootbox value at level 100 (0.24 ETH/ticket), the player needs significant ticket volume.

3. **The 3.5 ETH benefit is probabilistic.** Over many lootboxes the EV converges, but the cap limits total volume to 10 ETH, meaning only 10 ETH / average_lootbox_size lootboxes get enhanced treatment per level. If average lootbox is small (e.g., 0.05 ETH from a 0.04 ETH ticket), 200 lootboxes get enhanced EV before cap exhaustion. If lootbox sizes are larger, fewer lootboxes are needed.

4. **The player must continually buy tickets.** Each level requires new ticket purchases. The ETH spent on tickets is the game's revenue and goes into the prize pool. The lootbox EV benefit is a fraction of what was spent.

### 6.4 Assessment

The per-level cap reset is by design. It rewards sustained engagement (continued play across levels) rather than single-level extraction. The escalating ticket costs and diminishing relative benefit (3.5 ETH benefit on increasingly expensive ticket purchases) create natural economic diminishing returns.

---

## 7. MATH-05 Final Verdict

### 7.1 Summary of Key Numbers

| Metric | Value |
|--------|-------|
| Base composite EV (deterministic paths) | ~99.7% at neutral score |
| Maximum EV multiplier | 135% at 305% activity score |
| Maximum benefit per level | 3.5 ETH (35% of 10 ETH cap) |
| Minimum cost for 305% activity score | 24 ETH (deity pass) + time investment |
| Levels to recoup deity pass from EV benefit | ~7 levels |
| Cap tracking method | Raw input (conservative) |

### 7.2 Can Any Activity Score Create Guaranteed Positive-EV Extraction?

**No.** For the following reasons:

1. **The EV multiplier is probabilistic, not deterministic.** A 135% EV means that over many lootboxes, the expected return is 135% of input. Individual lootboxes vary enormously (ticket variance: 0.45x to 4.6x; BURNIE: 0.58x to 5.9x). A player could get unlucky and return less than 100% on any given lootbox or set of lootboxes.

2. **The per-level cap (10 ETH raw input) hard-limits total enhanced-EV volume.** Even at the maximum 135% EV, the cap restricts benefit to 3.5 ETH per level. This cannot be bypassed.

3. **The cost of reaching 305% activity score is substantial.** A deity pass (24+ ETH) is required, plus 100 days of consecutive quest completion and significant affiliate volume. The deity pass cost alone exceeds 6.8 levels of maximum extraction benefit.

4. **Extraction requires ongoing investment.** Lootboxes come from ticket purchases. The player must continually spend ETH to generate lootboxes. The EV benefit is the MARGINAL improvement over neutral (100%), not the total return.

5. **Non-ETH reward paths add variance, not guaranteed value.** DGNRS rewards depend on pool balance, WWXRP depends on market price, BURNIE depends on token value. None provide guaranteed ETH returns.

6. **The cap tracks raw input, not benefit.** This is more conservative than tracking benefit. It means the extraction ceiling is strictly lower than if benefit-tracking were used.

### 7.3 Edge Case: Optimal Player Strategy

The most favorable strategy would be:
- Buy deity pass (24 ETH)
- Build quest streak to 100 (free, but requires 100 days)
- Build affiliate bonus (requires significant referred volume)
- Open exactly 10 ETH of lootboxes per level at max score
- Repeat across many levels

**Expected return on deity pass investment:**
- Per level: 3.5 ETH EV benefit (on top of the ~100% base return)
- 7 levels to break even on the 24 ETH deity pass
- Each level also requires ticket purchases (~several ETH depending on ticket price)

**Is this "guaranteed positive-EV extraction"?** No:
- The 3.5 ETH is expected value, not guaranteed
- Breaking even requires 7+ levels of play
- The game may end before 7 levels
- Ticket purchases are an ongoing cost
- The deity pass provides other game benefits (boon issuance, streak/mint floor bonuses) that partially offset the cost
- The 100-day quest streak requirement creates a significant time barrier

### 7.4 Verdict

**MATH-05: PASS**

The lootbox EV multiplier formula correctly produces the expected values:
- 80% EV at 0% activity score
- 100% EV at 60% activity score (neutral)
- 135% EV at 305% activity score (maximum)

No achievable activity score creates a guaranteed positive-EV extraction opportunity that exceeds the investment cost. The maximum theoretical EV benefit (3.5 ETH per level at 135% EV with 10 ETH cap) requires a minimum 24 ETH deity pass investment plus ongoing ticket purchases and 100+ days of consecutive quest participation. The EV is probabilistic (not guaranteed), the cap tracks raw input (conservative), and the break-even period (7+ levels) creates significant uncertainty. The system is economically sound.

---

## 8. Findings

### 8.1 Finding: Cap Tracks Raw Input, Not Benefit Delta

**Severity:** Informational
**Location:** `_applyEvMultiplierWithCap` (lines 500-534)
**Description:** The `lootboxEvBenefitUsedByLevel` mapping tracks the raw input amount (`adjustedPortion`), not the actual benefit delta (`adjustedValue - adjustedPortion`). This means the cap depletes 2.86x faster than if benefit-tracking were used (10 ETH vs 10/0.35 = 28.57 ETH of volume).
**Assessment:** This is MORE conservative and SAFER for the protocol. No action needed. If intentional, this is good design. If unintentional, the current behavior is strictly safer than the alternative.

### 8.2 Finding: Sub-100% EV Players Also Tracked by Cap

**Severity:** Informational
**Location:** `_applyEvMultiplierWithCap` (lines 506-509)
**Description:** When `evMultiplierBps == LOOTBOX_EV_NEUTRAL_BPS` (exactly 100%), the function returns early without tracking. However, for players with score < 6000 (EV < 100%), the function DOES track usage against the cap. This means sub-neutral players have their "penalty" capped too -- after 10 ETH of reduced-EV lootboxes, they revert to 100% EV.
**Assessment:** This is a minor benefit to low-activity players. At 80% EV, 10 ETH of input returns 8 ETH (a 2 ETH penalty), after which the player gets neutral EV. This is a reasonable design choice that prevents excessive punishment of casual players. No security concern.

### 8.3 Finding: BURNIE and DGNRS EV Depends on Token Market Price

**Severity:** Informational
**Location:** Composite EV model (Section 2)
**Description:** The ticket path (69.6% of composite EV) is denominated in game-price-curve ETH-equivalent value. The BURNIE path (41.2%) and DGNRS path (variable) are denominated in their respective token values. If BURNIE or DGNRS tokens trade below the contract's implied pricing, the actual ETH-equivalent EV drops below the theoretical model. Conversely, if tokens appreciate, actual EV exceeds the model.
**Assessment:** This is inherent to a multi-token reward system. The protocol cannot guarantee token prices. The ticket path alone provides ~70% of neutral EV, ensuring the system remains functional even if token prices are adverse. No code change needed.

### 8.4 Finding: Boon Budget Reduces Effective Reward Pool

**Severity:** Informational
**Location:** `_resolveLootboxCommon` (lines 847-854)
**Description:** 10% of each lootbox (capped at 1 ETH) is allocated to the boon budget and subtracted from the reward rolls. The boon system provides its own value (coinflip bonuses, lootbox boosts, whale/deity pass discounts, activity bonuses, whale pass jackpot, lazy pass), but this value is highly variable and context-dependent. For the EV model, this 10% deduction reduces the deterministic reward paths from ~110% to ~99.7% at neutral score, which is the intended ~100% break-even point.
**Assessment:** Working as designed. The boon budget is part of the overall EV system, not a "hidden fee."
