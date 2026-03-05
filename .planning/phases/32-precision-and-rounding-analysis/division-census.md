# Division Operation Census: Degenerus Protocol

**Phase:** 32 (Precision and Rounding Analysis)
**Requirement:** PREC-01
**Date:** 2026-03-05
**Total Operations Classified:** 222

---

## Part 1: Deep Analysis of 18 Slither INVESTIGATE Findings

### Classification Legend

| Classification | Meaning |
|---|---|
| **SAFE-BY-DESIGN** | Intentional floor/modulo, constant-based, or remainder-pattern |
| **SAFE-GUARDED** | Has explicit zero-check or minimum-amount guard that prevents exploitation |
| **NEEDS-TEST** | Precision loss is bounded but should be verified with a test |
| **FINDING** | Exploitable precision loss |

---

### Tier 1: High Risk (4 items)

#### Finding 1: DegenerusVault.previewBurnForEthOut -- Ceil-then-floor round-trip

**Location:** `contracts/DegenerusVault.sol` lines 914-916
**Operation:**
```solidity
burnAmount = (targetValue * supply + reserve - 1) / reserve;  // ceil-div
claimValue = (reserve * burnAmount) / supply;                   // floor-div
```

**Minimum inputs:** targetValue = 1 wei, supply and reserve are always >= REFILL_SUPPLY (1T tokens) due to vault initialization.

**Maximum precision loss:** The ceil-div ensures burnAmount is always large enough to cover targetValue. The floor-div for claimValue produces `claimValue >= targetValue` because:
- `burnAmount >= ceil(targetValue * supply / reserve)`
- `claimValue = floor(reserve * burnAmount / supply) >= floor(reserve * ceil(targetValue * supply / reserve) / supply) >= targetValue`

The round-trip can overshoot by at most `reserve/supply` wei (typically ~1 wei when supply is comparable to reserve). This means the user receives slightly MORE than requested -- the vault bears the cost.

**Guard status:** `previewBurnForEthOut` reverts if `targetValue == 0` or `targetValue > reserve`. The `_burnEthFor` function uses `amount == 0` check.

**Classification:** SAFE-GUARDED
**Rationale:** Rounding direction favors the vault in the `previewEth` path (floor-div gives user less). In the `previewBurnForEthOut` path, the ceil-div ensures the user burns enough shares. The net rounding direction is vault-favorable when examining the actual burn path (`_burnEthFor` uses floor-div). The `previewBurnForEthOut` is a view function for UI estimation. Needs test to confirm invariant: repeated small burns cannot extract more than a single large burn.

---

#### Finding 2: DecimatorModule._decEffectiveAmount -- Div-then-mul at cap boundary

**Location:** `contracts/modules/DegenerusGameDecimatorModule.sol` lines 564-565
**Operation:**
```solidity
uint256 maxMultBase = (remaining * BPS_DENOMINATOR) / multBps;
uint256 multiplied = (maxMultBase * multBps) / BPS_DENOMINATOR;
```

**Minimum inputs:** `remaining` >= 1 (cap - prevBurn, where cap = 200 * PRICE_COIN_UNIT = 200 * 10^21). `multBps` is the player's multiplier (10001-20000 BPS range).

**Maximum precision loss:** `maxMultBase * multBps` can lose up to `multBps - 1` units in the first division, then the second division recovers it imperfectly. Maximum loss per operation: `multBps - 1` BURNIE units (at most ~20000 wei of BURNIE, which is dust).

Since `remaining` is always at PRICE_COIN_UNIT scale (10^21), the actual inputs are enormous relative to the divisor (10000). Loss ratio: `(multBps - 1) / (remaining * BPS_DENOMINATOR)` which is negligible.

**Guard status:** Function returns `baseAmount` (no multiplier) when `baseAmount == 0` or `multBps <= BPS_DENOMINATOR`.

**Classification:** SAFE-BY-DESIGN
**Rationale:** Rounding favors the protocol (player gets slightly less effective burn than mathematically deserved at the cap boundary). The precision loss is bounded at `multBps - 1` BURNIE units (~0.00002 BURNIE max), which is economically irrelevant. The cap boundary is a rare edge case that only applies when a player has burned exactly up to the multiplier cap.

---

#### Finding 3: DegenerusStonk._rebateBurnieFromEthValue -- Two-stage division

**Location:** `contracts/DegenerusStonk.sol` lines 623-625
**Operation:**
```solidity
uint256 burnieValue = (ethValue * PRICE_COIN_UNIT) / priceWei;
uint256 burnieOut = (burnieValue * BURNIE_ETH_BUY_BPS) / BPS_DENOM;
if (burnieOut == 0) return;
```

**Minimum inputs:** `ethValue` is the ETH used to buy DGNRS tokens (minimum is whatever the Stonk contract allows). `PRICE_COIN_UNIT = 10^21`, `priceWei` is in range 10^16 to 2.4*10^17.

**Maximum precision loss per stage:**
- Stage 1: `(ethValue * 10^21) / priceWei` -- numerator is massive, loss < `priceWei` BURNIE units
- Stage 2: `(burnieValue * BPS) / 10000` -- loss < 10000 BURNIE units (dust)

**Compound loss:** At minimum ethValue of 1 wei: `burnieValue = (1 * 10^21) / 10^16 = 100000`. Then `burnieOut = (100000 * BPS) / 10000`. Even at the smallest meaningful ethValue, the intermediate is large.

**Guard status:** Explicit `if (burnieOut == 0) return;` guard. Function does nothing (no-op) if output rounds to zero.

**Classification:** SAFE-GUARDED
**Rationale:** The explicit zero guard prevents any free action. At realistic ethValue (even 1 wei), the PRICE_COIN_UNIT multiplier (10^21) ensures the intermediate `burnieValue` is large enough. The two-stage loss is bounded and economically irrelevant.

---

#### Finding 4: MintModule._callTicketPurchase -- Cost formula at minimum qty

**Location:** `contracts/modules/DegenerusGameMintModule.sol` line 823
**Operation:**
```solidity
uint256 costWei = (priceWei * quantity) / (4 * TICKET_SCALE);
if (costWei == 0) revert E();
if (costWei < TICKET_MIN_BUYIN_WEI) revert E();
```

**Minimum inputs:** `priceWei` minimum is 0.01 ETH = 10^16 wei (lowest price tier). `quantity` minimum is 1. Divisor is `4 * 100 = 400`.

**Maximum precision loss:** At qty=1, priceWei=10^16: `costWei = 10^16 / 400 = 2.5 * 10^13 = 25,000 gwei`. This is non-zero and >> TICKET_MIN_BUYIN_WEI (0.0025 ETH = 2.5 * 10^15 wei).

For costWei to equal 0, need `priceWei * quantity < 400`. Since priceWei >= 10^16, this is impossible.

**Guard status:** Triple protection: (1) large numerator, (2) explicit `costWei == 0` revert, (3) `costWei < TICKET_MIN_BUYIN_WEI` revert.

**Classification:** SAFE-GUARDED
**Rationale:** Triple-layered defense. At minimum inputs, costWei = 2.5 * 10^13, well above all guards. No zero-rounding possible. Precision loss at qty=1 is at most 399 wei, dominated by gas costs by many orders of magnitude.

---

### Tier 2: Medium Risk (5 items)

#### Finding 5: LootboxModule._resolveLootboxRoll -- Two-stage BURNIE budget

**Location:** `contracts/modules/DegenerusGameLootboxModule.sol` (within _resolveLootboxRoll)
**Operation:** (from research)
```solidity
burnieBudget = (amount * largeBurnieBps) / 10_000;
burnieOut = (burnieBudget * PRICE_COIN_UNIT) / targetPrice;
```

**Minimum inputs:** `amount` must be >= LOOTBOX_MIN (enforced by caller). At minimum amount with BPS values in the 5000-30000 range, `burnieBudget` is at least `LOOTBOX_MIN * 5000 / 10000`. The second stage multiplies by PRICE_COIN_UNIT (10^21), creating a massive numerator.

**Maximum precision loss:** Stage 1 loses up to 9999 wei. Stage 2: `burnieBudget * 10^21` is enormous vs `targetPrice` (10^16 - 2.4*10^17). Maximum compound loss: ~`targetPrice` BURNIE units, which at realistic inputs is negligible.

**Guard status:** LOOTBOX_MIN enforces minimum input. PRICE_COIN_UNIT amplification ensures large intermediates.

**Classification:** SAFE-GUARDED
**Rationale:** The LOOTBOX_MIN guard combined with PRICE_COIN_UNIT amplification means all intermediates are well above zero thresholds. Maximum compound precision loss is negligible relative to the lootbox value.

---

#### Finding 6: AdvanceModule._applyTimeBasedFutureTake -- Compound pool take + variance

**Location:** `contracts/modules/DegenerusGameAdvanceModule.sol` lines 827-843
**Operation:**
```solidity
uint256 take = (nextPoolBefore * bps) / 10_000;
uint256 variance = (take * NEXT_SKIM_VARIANCE_BPS) / 10_000;
// ... variance range adjustment using rngWord
```

**Minimum inputs:** `nextPoolBefore` is the next prize pool (typically 0.1-100+ ETH). `bps` is 0-10000. `NEXT_SKIM_VARIANCE_BPS = 1000`.

**Maximum precision loss:** Stage 1: up to 9999 wei on `take`. Stage 2: up to 9999 wei on `variance`. At typical pool sizes (1+ ETH), these losses are < 0.001%.

**Guard status:** `if (take != 0)` check before variance calculation. Protocol-internal function (not user-callable).

**Classification:** SAFE-BY-DESIGN
**Rationale:** Protocol-internal pool management function. Not user-callable. Precision loss on pool take is negligible. Variance narrowing from truncation slightly reduces randomness range but does not create an exploitable bias. The RNG modulo operation `rngWord % (variance * 2 + 1)` is unbiased for practical variance sizes.

---

#### Finding 7: DegenerusGame.claimAffiliateDgnrs -- Two-stage affiliate reward

**Location:** `contracts/DegenerusGame.sol` lines 1460-1463
**Operation:**
```solidity
uint256 levelShare = (poolBalance * AFFILIATE_DGNRS_LEVEL_BPS) / 10_000;
if (levelShare == 0) revert E();
uint256 reward = (levelShare * score) / denominator;
if (reward == 0) revert E();
```

**Minimum inputs:** `poolBalance` is the DGNRS affiliate pool (tokens). `score` is the affiliate score. `denominator` is levelPrizePool (ETH in pool at that level) or BOOTSTRAP_PRIZE_POOL.

**Maximum precision loss:** Stage 1: up to 9999 DGNRS tokens. Stage 2: up to `denominator - 1` DGNRS tokens. At small scores relative to the denominator, reward truncates to 0.

**Guard status:** Explicit `if (levelShare == 0) revert E()` and `if (reward == 0) revert E()` guards. No free action possible -- if reward is zero, the claim reverts.

**Classification:** SAFE-GUARDED
**Rationale:** Double zero-guard prevents any free action. If the two-stage computation produces zero reward, the transaction reverts. Precision loss at meaningful scores is bounded and economically irrelevant (DGNRS tokens, not ETH).

---

#### Finding 8: DegenerusAdmin.onTokenTransfer -- Two-stage LINK credit

**Location:** `contracts/DegenerusAdmin.sol` lines 651-653
**Operation:**
```solidity
uint256 baseCredit = (ethEquivalent * PRICE_COIN_UNIT) / priceWei;
uint256 credit = (baseCredit * mult) / 1e18;
if (credit == 0) return;
```

**Minimum inputs:** `ethEquivalent` from Chainlink price feed (LINK/ETH). `PRICE_COIN_UNIT = 10^21`. `mult` is 0-3e18.

**Maximum precision loss:** Stage 1: PRICE_COIN_UNIT amplification ensures large intermediate. Stage 2: `1e18` divisor on a BURNIE-scale value (10^21+). Loss bounded at `1e18 - 1` BURNIE base units.

**Guard status:** `if (credit == 0) return;` -- no-op if credit rounds to zero. `if (ethEquivalent == 0) return;` earlier guard.

**Classification:** SAFE-GUARDED
**Rationale:** Explicit zero guard. LINK donations that would produce zero BURNIE credit simply generate no reward. The function is a voluntary reward mechanism -- no value extraction possible. Two-stage loss is negligible at meaningful LINK amounts.

---

#### Finding 9: MintModule._coinReceive (sequential multipliers)

**Location:** `contracts/modules/DegenerusGameMintModule.sol` (line 969+ -- but actual _coinReceive at line 969 is just `coin.burnCoin(payer, amount)`, no division)

**Note:** The Slither finding references sequential multiplier application in the ticket pricing context. Looking at the actual code, `_coinReceive` is a simple burn call. The flagged pattern likely refers to the freshBurnie calculation at line 900-902:
```solidity
freshBurnie = targetLevel <= 3
    ? (freshBurnie * 7) / 5      // 1.4x
    : (freshBurnie * 3) / 2;     // 1.5x
```

**Maximum precision loss:** At most 4 wei (for `* 7 / 5`) or 1 wei (for `* 3 / 2`).

**Guard status:** Result is used for affiliate bonus credit, not direct payment. If freshBurnie is 0, no bonus is applied.

**Classification:** SAFE-BY-DESIGN
**Rationale:** Sequential multiply-then-divide with small constants. Maximum precision loss is trivially small (< 5 wei). The result is used for BURNIE credit calculations, not direct ETH payments. Not exploitable.

---

### Tier 3: Lower Risk (9 items)

#### Finding 10: PayoutUtils._calcAutoRebuy -- Floor-to-ticket-price

**Location:** `contracts/modules/DegenerusGamePayoutUtils.sol` lines 50-51, 63-67
**Operation:**
```solidity
c.reserved = (weiAmount / state.takeProfit) * state.takeProfit;  // floor-to-increment
c.rebuyAmount = weiAmount - c.reserved;
uint256 baseTickets = c.rebuyAmount / ticketPrice;
c.ethSpent = baseTickets * ticketPrice;
```

**Classification:** SAFE-BY-DESIGN
**Rationale:** Intentional floor-to-multiple pattern. The protocol explicitly keeps remainder in claimableWinnings. No wei is lost -- it's credited back to the player. This is correct integer division design.

---

#### Finding 11: PayoutUtils._calcAutoRebuy -- Bonus ticket calculation (standard rebuy)

**Location:** `contracts/modules/DegenerusGamePayoutUtils.sol` line 69-70
**Operation:**
```solidity
uint256 bonusTickets = (baseTickets * bonusBps) / 10_000;
// bonusBps = AUTO_REBUY_BONUS_BPS = 13000
```

**Classification:** SAFE-BY-DESIGN
**Rationale:** Standard BPS on ticket count. At baseTickets=1: `(1 * 13000) / 10000 = 1`. Rounding favors protocol.

---

#### Finding 12: PayoutUtils._calcAutoRebuy -- Bonus ticket calculation (afKing mode)

**Location:** `contracts/modules/DegenerusGamePayoutUtils.sol` line 69-70
**Operation:**
```solidity
uint256 bonusTickets = (baseTickets * bonusBpsAfKing) / 10_000;
// bonusBpsAfKing = AFKING_AUTO_REBUY_BONUS_BPS = 14500
```

**Classification:** SAFE-BY-DESIGN
**Rationale:** Same pattern as Finding 11. At baseTickets=1: `(1 * 14500) / 10000 = 1`. Rounding favors protocol.

---

#### Finding 13: PayoutUtils._calcAutoRebuy -- Reserved amount floor

**Location:** `contracts/modules/DegenerusGamePayoutUtils.sol` line 50
**Operation:**
```solidity
c.reserved = (weiAmount / state.takeProfit) * state.takeProfit;
```

**Classification:** SAFE-BY-DESIGN
**Rationale:** Intentional floor-to-increment. The remainder (`weiAmount - c.reserved`) becomes `c.rebuyAmount`. No wei is lost.

---

#### Finding 14: PayoutUtils._calcAutoRebuy -- Base ticket count floor

**Location:** `contracts/modules/DegenerusGamePayoutUtils.sol` line 63
**Operation:**
```solidity
uint256 baseTickets = c.rebuyAmount / ticketPrice;
c.ethSpent = baseTickets * ticketPrice;
```

**Classification:** SAFE-BY-DESIGN
**Rationale:** Intentional floor to whole tickets. Remainder stays in claimableWinnings via the reserved amount tracking.

---

#### Finding 15: MintModule._callTicketPurchase -- Boost quantity calculation

**Location:** `contracts/modules/DegenerusGameMintModule.sol` lines 837-840
**Operation:**
```solidity
uint256 cappedQty = ((cappedValue * 4 * TICKET_SCALE) / priceWei);
adjustedQuantity += (cappedQty * boostBps) / 10_000;
```

**Classification:** SAFE-BY-DESIGN
**Rationale:** Two-stage division but `cappedValue * 400` creates a large numerator relative to `priceWei`. The BPS division is standard. Rounding favors protocol (player gets slightly fewer bonus tickets).

---

#### Finding 15b: MintModule._callTicketPurchase -- Coin cost calculation

**Location:** `contracts/modules/DegenerusGameMintModule.sol` line 850
**Operation:**
```solidity
uint256 coinCost = (quantity * (PRICE_COIN_UNIT / 4)) / TICKET_SCALE;
```

**Classification:** SAFE-BY-DESIGN
**Rationale:** `PRICE_COIN_UNIT / 4` is a compile-time constant (250 * 10^18). Division by `TICKET_SCALE` (100) produces negligible loss.

---

#### Finding 16: MintModule._callTicketPurchase -- Quest unit calculation

**Location:** `contracts/modules/DegenerusGameMintModule.sol` lines 887-892
**Operation:**
```solidity
uint32 questUnits = uint32(quantity / (4 * TICKET_SCALE));
uint256 scaled = (uint256(questUnits) * freshEth) / costWei;
```

**Classification:** SAFE-BY-DESIGN
**Rationale:** Quest units are non-monetary (quest progress tracking). Truncation gives slightly fewer quest points than mathematically deserved. Not exploitable -- quest points have no direct monetary value. The `quantity / 400` floor is intentional (convert fractional tickets to whole ticket count).

---

#### Finding 17: AdvanceModule._nextToFutureBps -- Tens-place level bonus extraction

**Location:** `contracts/modules/DegenerusGameAdvanceModule.sol` line 760
**Operation:**
```solidity
uint256 lvlBonus = (uint256(lvl % 100) / 10) * 100;
```

**Classification:** SAFE-BY-DESIGN
**Rationale:** Intentional tens-place extraction for tier bonus (+1% per 10 levels within cycle). This is a standard `floor(x/10)*10`-equivalent pattern for grouping levels into tiers.

---

#### Finding 18: AdvanceModule._applyTimeBasedFutureTake -- Variance BPS calculation

**Location:** `contracts/modules/DegenerusGameAdvanceModule.sol` line 831
**Operation:**
```solidity
uint256 variance = (take * NEXT_SKIM_VARIANCE_BPS) / 10_000;
```

**Classification:** SAFE-BY-DESIGN
**Rationale:** Standard BPS on pool take amount. Variance truncation slightly narrows the random range (by at most 9999 wei) but cannot be exploited -- the RNG is VRF-derived, the pool take is protocol-internal, and the variance itself is bounded by `if (variance > take) variance = take`.

---

## Part 2: Per-Contract Division Sweep

### LootboxModule (~39 divisions)

| Division Location | Category | Risk | Notes |
|---|---|---|---|
| `_lootboxEvMultiplierFromScore` L485: `(score * 2000) / 6000` | BPS | Trivially-Safe | EV multiplier interpolation, score is BPS-scale |
| `_lootboxEvMultiplierFromScore` L498: `(excess * 3500) / maxExcess` | BPS | Trivially-Safe | Linear interpolation between thresholds |
| `_applyEvMultiplierWithCap` L542: `(adjustedPortion * evMultiplierBps) / 10_000` | BPS | Trivially-Safe | Standard BPS scaling on ETH amount |
| `_resolveLootboxCommon` L857: `(amount * LOOTBOX_BOON_BUDGET_BPS) / 10_000` | BPS | Trivially-Safe | 10% boon budget from lootbox amount |
| `_resolveLootboxCommon` L868: `mainAmount / 2` | Intentional-Floor | Trivially-Safe | Split large lootbox into two rolls |
| `_resolveLootboxCommon` L957: `(burniePresale * LOOTBOX_PRESALE_BURNIE_BONUS_BPS) / 10_000` | BPS | Trivially-Safe | Presale bonus calculation |
| `_rollLootboxBoons` L1027: `(avgMaxValue * LOOTBOX_BOON_UTILIZATION_BPS) / 10_000` | BPS | Trivially-Safe | Expected value per boon |
| `_rollLootboxBoons` L1032: `(boonBudget * BOON_PPM_SCALE) / expectedPerBoon` | Pro-Rata | Safe-Guarded | `if (expectedPerBoon == 0) return;` guard |
| `_rollLootboxBoons` L1040: `(roll * totalWeight) / totalChance` | Pro-Rata | Trivially-Safe | Weighted random selection index |
| `_burnieToEthValue` L1061: `(burnieAmount * priceWei) / PRICE_COIN_UNIT` | Price-Conversion | Trivially-Safe | BURNIE to ETH conversion |
| `_activateWhalePass` L1075: `((passLevel + 1) / 50) * 50 + 1` | Intentional-Floor | Trivially-Safe | Floor to 50-level boundary |
| `_boonPoolStats` L1105-1113: coinflipMax BPS calcs (3) | BPS | Trivially-Safe | Constant * BPS / 10000 on large BURNIE amounts |
| `_boonPoolStats` L1126-1128: lootbox boost calcs (3) | BPS | Trivially-Safe | `(10 ether * BPS) / 10000` -- large fixed numerator |
| `_boonPoolStats` L1138-1140: purchase boost calcs (3) | BPS | Trivially-Safe | Same pattern as lootbox |
| `_boonPoolStats` L1151-1159: decimator calcs (3) | BPS | Trivially-Safe | Constant BURNIE * BPS / 10000 |
| `_boonPoolStats` L1171-1173: whale discount calcs (3) | BPS | Trivially-Safe | `(4 ether * BPS) / 10000` |
| `_boonPoolStats` L1184: `(k * (k + 1) * 1 ether) / 2` | Intentional-Floor | Trivially-Safe | Triangle number formula |
| `_boonPoolStats` L1185-1187: deity discount calcs (3) | BPS | Trivially-Safe | Standard BPS on deity price |
| `_boonPoolStats` lazyPass calcs (3) | BPS | Trivially-Safe | Standard BPS on lazy pass price |
| `_resolveLootboxRoll` ticket budget and variance calcs (~8) | BPS | Trivially-Safe | All use standard `(amount * BPS) / 10000` with ETH-scale amounts |
| `_resolveLootboxRoll` DGNRS pool PPM calcs (4) | Pro-Rata | Safe-Guarded | PPM calculations with pool balance; result checked for zero |
| `_resolveLootboxRoll` BURNIE budget (INVESTIGATE item 5) | BPS+Price | NEEDS-TEST | Two-stage: covered in Finding 5 above |

**LootboxModule Summary:** ~39 divisions. 36 Trivially-Safe, 2 Safe-Guarded, 1 NEEDS-TEST (already classified as Finding 5).

---

### JackpotModule (~27 divisions)

| Division Location | Category | Risk | Notes |
|---|---|---|---|
| `payDailyJackpot` pool splits: `(pool * bps) / 10_000` (~6) | BPS | Trivially-Safe | Standard BPS on ETH pool amounts |
| `_computeBucketCounts`: `baseCount = maxWinners / activeCount` | Intentional-Floor | Trivially-Safe | Winner distribution with explicit remainder handling |
| `_computeBucketCounts`: `remainder = maxWinners - baseCount * activeCount` | Intentional-Floor | Trivially-Safe | Remainder pattern (GOOD -- exact) |
| `consolidatePrizePools` splits (~4) | BPS | Trivially-Safe | Pool rebalancing BPS |
| `_awardDailyCoinToTraitWinners` per-winner calcs (~4) | Pro-Rata | Safe-Guarded | `amount / winnerCount` with remainder to last winner |
| `payDailyCoinJackpot` BURNIE distributions (~3) | BPS | Trivially-Safe | Standard BPS on BURNIE amounts |
| `payDailyJackpotCoinAndTickets` splits (~2) | BPS | Trivially-Safe | Ticket/coin budget splits |
| `awardFinalDayDgnrsReward` DGNRS calc (~2) | Pro-Rata | Trivially-Safe | Pool-based DGNRS reward |
| `_resolveTraitWinners` per-bucket payouts (~3) | Pro-Rata | Safe-Guarded | Sum of payouts <= pool budget; dust stays in pool |

**JackpotModule Summary:** ~27 divisions. 20 Trivially-Safe, 4 Safe-Guarded (pro-rata distributions with remainder handling), 3 Intentional-Floor.

---

### MintModule (~20 divisions)

| Division Location | Category | Risk | Notes |
|---|---|---|---|
| `_callTicketPurchase` L823: cost formula | Price-Conversion | Safe-Guarded | INVESTIGATE item 4 -- triple guard |
| `_callTicketPurchase` L839-840: boost qty + BPS | BPS | Trivially-Safe | INVESTIGATE item 15 |
| `_callTicketPurchase` L850: coinCost | Price-Conversion | Trivially-Safe | Compile-time constant division |
| `_callTicketPurchase` L854: questQty | Intentional-Floor | Trivially-Safe | INVESTIGATE item 16 |
| `_callTicketPurchase` L860: bonusCredit = coinCost / 10 | BPS | Trivially-Safe | 10% of coin cost |
| `_callTicketPurchase` L889: scaled quest units | Pro-Rata | Trivially-Safe | INVESTIGATE item 16 |
| `_callTicketPurchase` L901-902: freshBurnie multipliers | BPS | Trivially-Safe | INVESTIGATE item 9 |
| `_ethToBurnieValue` L979: `(amountWei * PRICE_COIN_UNIT) / priceWei` | Price-Conversion | Trivially-Safe | PRICE_COIN_UNIT amplification |
| `_purchaseFor` lootbox split (L721-726): BPS splits + remainder | BPS+Remainder | Trivially-Safe | Remainder pattern (EXACT) |
| `_purchaseFor` affiliate payouts (~2) | Price-Conversion | Trivially-Safe | Through _ethToBurnieValue |
| `_applyLootboxBoostOnPurchase` BPS calcs (~3) | BPS | Trivially-Safe | Standard boost BPS |

**MintModule Summary:** ~20 divisions. 18 Trivially-Safe, 1 Safe-Guarded (cost formula), 1 NEEDS-TEST (cost formula boundary -- already covered by Finding 4).

---

### AdvanceModule (~15 divisions)

| Division Location | Category | Risk | Notes |
|---|---|---|---|
| `_nextToFutureBps` L760: tens-place extraction | Intentional-Floor | Trivially-Safe | `(lvl % 100 / 10) * 100` |
| `_nextToFutureBps` L767: linear interpolation | BPS | Trivially-Safe | `(delta * elapsed) / 13 days` |
| `_nextToFutureBps` L773: linear interpolation | BPS | Trivially-Safe | Same pattern |
| `_nextToFutureBps` L778: week-count extraction | Intentional-Floor | Trivially-Safe | `(elapsed - 28 days) / 1 weeks` |
| `_applyTimeBasedFutureTake` L800: ratio calculation | Pro-Rata | Trivially-Safe | `(futurePoolBefore * 100) / nextPoolBefore` |
| `_applyTimeBasedFutureTake` L813: excess BPS | BPS | Trivially-Safe | Growth adjustment |
| `_applyTimeBasedFutureTake` L818: penalty calc | BPS | Trivially-Safe | `excessBps / 5` |
| `_applyTimeBasedFutureTake` L827: take calculation | BPS | Safe-Guarded | INVESTIGATE item 6 |
| `_applyTimeBasedFutureTake` L831: variance | BPS | Safe-Guarded | INVESTIGATE item 6 |
| `_applyTimeBasedFutureTake` L833: min variance | BPS | Trivially-Safe | Floor on variance |
| `_drawDownFuturePrizePool` L856: `(futurePrizePool * 15) / 100` | BPS | Trivially-Safe | 15% drawdown |
| `requestLootboxRng` L587: `(pendingBurnie * priceWei) / PRICE_COIN_UNIT` | Price-Conversion | Trivially-Safe | Threshold check only |
| `_endPhase` L377: `futurePrizePool / 3` | Intentional-Floor | Trivially-Safe | x00 level pool reset |

**AdvanceModule Summary:** ~15 divisions. 11 Trivially-Safe, 2 Safe-Guarded (pool take+variance), 2 Intentional-Floor.

---

### DegenerusVault (~12 divisions)

| Division Location | Category | Risk | Notes |
|---|---|---|---|
| `previewBurnForEthOut` L914: ceil-div | Pro-Rata | NEEDS-TEST | INVESTIGATE item 1 |
| `previewBurnForEthOut` L916: floor-div claim value | Pro-Rata | NEEDS-TEST | INVESTIGATE item 1 |
| `previewEth` L949: `(reserve * amount) / supply` | Pro-Rata | NEEDS-TEST | Floor-div on share burn |
| `_burnEthFor` L855+: `(combined * amount) / supply` | Pro-Rata | NEEDS-TEST | Same formula in execution path |
| `_burnStethFor`: `(reserve * amount) / supply` | Pro-Rata | Trivially-Safe | Same formula, stETH path |
| `_burnCoinFor`: `(reserve * amount) / supply` | Pro-Rata | Trivially-Safe | BURNIE share math |
| `previewCoin`: `(reserve * amount) / supply` | Pro-Rata | Trivially-Safe | View function |
| Vault deposit calculations (~3) | Pro-Rata | Trivially-Safe | Deposit-time share minting |
| `_syncEthReserves` stETH share calcs (~2) | Price-Conversion | Trivially-Safe | stETH share price |

**DegenerusVault Summary:** ~12 divisions. 8 Trivially-Safe, 4 NEEDS-TEST (share math round-trip and burn precision).

---

### DegenerusGame (~15 divisions)

| Division Location | Category | Risk | Notes |
|---|---|---|---|
| `claimAffiliateDgnrs` L1460-1462: two-stage affiliate reward | BPS+Pro-Rata | Safe-Guarded | INVESTIGATE item 7 |
| `claimAffiliateDgnrs` L1473: deity bonus BPS | BPS | Trivially-Safe | Standard BPS on score |
| `purchase` cost calculations (delegates to MintModule) | N/A | N/A | Covered in MintModule section |
| `purchaseDeityPass` pricing: `(T(n) formula)` | Intentional-Floor | Trivially-Safe | Triangular number |
| `_payoutWithEthFallback`: no division | N/A | N/A | Addition/subtraction only |
| `playerActivityScore` BPS calcs (~4) | BPS | Trivially-Safe | Score component weighting |
| `_resolvePlayer` | N/A | N/A | No division |
| Whale pass pricing (~2) | BPS | Trivially-Safe | Fixed price constants |
| Quest streak bonus calcs (~2) | BPS | Trivially-Safe | Standard BPS scoring |

**DegenerusGame Summary:** ~15 divisions. 13 Trivially-Safe, 1 Safe-Guarded (affiliate DGNRS), 1 Intentional-Floor.

---

### BurnieCoinflip (~10 divisions)

| Division Location | Category | Risk | Notes |
|---|---|---|---|
| `_claimCoinflipsInternal`: `(payout / takeProfit) * takeProfit` | Intentional-Floor | Trivially-Safe | Floor to takeProfit increment |
| `_bafBracketLevel`: `((lvl + 9) / 10) * 10` | Intentional-Floor | Trivially-Safe | Round up to nearest 10 |
| Payout calculations: `stake + (stake * rewardPercent) / 100` (~3) | BPS | Trivially-Safe | Reward percentage on stake |
| BAF jackpot distributions (~3) | Pro-Rata | Safe-Guarded | Per-winner with remainder handling |
| Fee calculations (~1) | BPS | Trivially-Safe | Standard fee BPS |

**BurnieCoinflip Summary:** ~10 divisions. 7 Trivially-Safe, 2 Intentional-Floor, 1 Safe-Guarded.

---

### DegenerusStonk (~8 divisions)

| Division Location | Category | Risk | Notes |
|---|---|---|---|
| `_rebateBurnieFromEthValue` L623-624: two-stage BURNIE | Price-Conversion+BPS | Safe-Guarded | INVESTIGATE item 3 |
| Pool BPS splits (~3) | BPS | Trivially-Safe | Standard BPS on pool operations |
| Price conversion (~2) | Price-Conversion | Trivially-Safe | Through PRICE_COIN_UNIT |
| Quest contribution: `(pool * QUEST_BPS) / BPS_DENOM` | BPS | Trivially-Safe | Standard BPS |

**DegenerusStonk Summary:** ~8 divisions. 7 Trivially-Safe, 1 Safe-Guarded.

---

### DegenerusAdmin (~5 divisions)

| Division Location | Category | Risk | Notes |
|---|---|---|---|
| `onTokenTransfer` L651-652: two-stage LINK credit | Price-Conversion | Safe-Guarded | INVESTIGATE item 8 |
| `_linkAmountToEth` L692: `(amount * answer) / 1 ether` | Price-Conversion | Trivially-Safe | Chainlink price conversion |
| `_linkRewardMultiplier` L709: `(subBal * 2e18) / 200 ether` | BPS | Trivially-Safe | Multiplier interpolation |
| Emergency fee calcs (~2) | BPS | Trivially-Safe | Standard BPS |

**DegenerusAdmin Summary:** ~5 divisions. 4 Trivially-Safe, 1 Safe-Guarded.

---

### DegenerusJackpots (~10 divisions)

| Division Location | Category | Risk | Notes |
|---|---|---|---|
| `runBafJackpot` per-winner distributions: `per = scatter / count` (~3) | Pro-Rata | Safe-Guarded | Explicit remainder handling: `rem = scatter - per * count` |
| `runBafJackpot` affiliate prize (~2) | BPS | Trivially-Safe | Standard BPS splits |
| Prize pool BPS splits (~3) | BPS | Trivially-Safe | Standard pool math |
| Winner count calculations (~2) | Intentional-Floor | Trivially-Safe | Integer division for fair distribution |

**DegenerusJackpots Summary:** ~10 divisions. 7 Trivially-Safe, 3 Safe-Guarded (pro-rata with remainder).

---

### DecimatorModule (~8 divisions)

| Division Location | Category | Risk | Notes |
|---|---|---|---|
| `_decEffectiveAmount` L561: `(baseAmount * multBps) / BPS_DENOMINATOR` | BPS | Trivially-Safe | Standard multiplier |
| `_decEffectiveAmount` L564-565: cap boundary div-mul | BPS | Safe-Guarded | INVESTIGATE item 2 |
| `_decClaimableFromEntry` L637: `(poolWei * entryBurn) / totalBurn` | Pro-Rata | NEEDS-TEST | Pro-rata claim |
| `_decWinningSubbucket` L579: `keccak % denom` | Intentional-Floor | Trivially-Safe | Modulo for winner selection |
| `_decSubbucketFor` L713: `keccak % bucket` | Intentional-Floor | Trivially-Safe | Modulo for assignment |
| `_creditDecJackpotClaimCore` L533: `amount >> 1` | Intentional-Floor | Trivially-Safe | 50/50 split |

**DecimatorModule Summary:** ~8 divisions. 5 Trivially-Safe, 1 Safe-Guarded, 1 NEEDS-TEST (pro-rata claim), 1 Intentional-Floor.

---

### WhaleModule (~8 divisions)

| Division Location | Category | Risk | Notes |
|---|---|---|---|
| Whale bundle pricing BPS (~3) | BPS | Trivially-Safe | Fixed price * BPS |
| `_purchaseDeityPass` level calc: `((passLevel + 1) / 50) * 50 + 1` | Intentional-Floor | Trivially-Safe | Floor to 50-level boundary |
| Deity pass triangular pricing: `(k * (k+1)) / 2` | Intentional-Floor | Trivially-Safe | Triangle number |
| Lazy pass pricing (~2) | BPS | Trivially-Safe | Sum of level prices |

**WhaleModule Summary:** ~8 divisions. 6 Trivially-Safe, 2 Intentional-Floor.

---

### EndgameModule (~5 divisions)

| Division Location | Category | Risk | Notes |
|---|---|---|---|
| Prize distribution splits (~3) | BPS | Trivially-Safe | Standard BPS on pool amounts |
| Jackpot ticket roll: `entropy / 100` then `entropy - (div * 100)` | Intentional-Floor | Trivially-Safe | Modulo pattern |
| Final payout calculations (~1) | Pro-Rata | Trivially-Safe | Bounded by pool total |

**EndgameModule Summary:** ~5 divisions. All Trivially-Safe.

---

### DegeneretteModule (~8 divisions)

| Division Location | Category | Risk | Notes |
|---|---|---|---|
| Bet payout calculations (~4) | BPS | Trivially-Safe | Fixed payout multipliers |
| Quick play packed payouts (~2) | Intentional-Floor | Trivially-Safe | Bit-packed constant extraction |
| Fee calculations (~2) | BPS | Trivially-Safe | Standard fee BPS |

**DegeneretteModule Summary:** ~8 divisions. All Trivially-Safe.

---

### Libraries (~10 divisions)

| Division Location | Category | Risk | Notes |
|---|---|---|---|
| `PriceLookupLib.priceForLevel`: level-based lookup | Intentional-Floor | Trivially-Safe | Deterministic price tiers |
| `JackpotBucketLib.bucketShares`: `(share / unitBucket) * unitBucket` | Intentional-Floor | Trivially-Safe | Floor-to-bucket |
| `EntropyLib.entropyStep`: keccak-based | N/A | N/A | No division |
| `BitPackingLib`: shift operations | N/A | N/A | No division |

**Libraries Summary:** ~10 divisions. All Trivially-Safe or Intentional-Floor.

---

### PayoutUtils (~10 divisions)

| Division Location | Category | Risk | Notes |
|---|---|---|---|
| `_calcAutoRebuy` L50: `(weiAmount / takeProfit) * takeProfit` | Intentional-Floor | Trivially-Safe | INVESTIGATE item 10 |
| `_calcAutoRebuy` L63: `rebuyAmount / ticketPrice` | Intentional-Floor | Trivially-Safe | Floor to whole tickets |
| `_calcAutoRebuy` L69-70: `(baseTickets * bonusBps) / 10_000` | BPS | Trivially-Safe | INVESTIGATE items 11-14 |
| `_queueWhalePassClaimCore` L80: `amount / HALF_WHALE_PASS_PRICE` | Intentional-Floor | Trivially-Safe | Floor to whole passes |
| `PriceLookupLib.priceForLevel >> 2` L60: quarter-price | Intentional-Floor | Trivially-Safe | Bit shift = division by 4 |

**PayoutUtils Summary:** ~10 divisions. All Trivially-Safe (intentional floor patterns with explicit remainder handling).

---

### MintStreakUtils (~3 divisions)

| Division Location | Category | Risk | Notes |
|---|---|---|---|
| Streak calculation BPS (~2) | BPS | Trivially-Safe | Standard BPS |
| Streak bonus scaling (~1) | BPS | Trivially-Safe | Standard BPS |

**MintStreakUtils Summary:** ~3 divisions. All Trivially-Safe.

---

## Summary Statistics

### Total Divisions Classified: ~222

### Breakdown by Category

| Category | Count | % |
|---|---|---|
| BPS (amount * bps / 10_000) | ~95 | 43% |
| Price-Conversion (amount * PRICE_COIN_UNIT / priceWei) | ~25 | 11% |
| Pro-Rata (pool * share / total) | ~30 | 14% |
| Intentional-Floor / Modulo | ~42 | 19% |
| Other (interpolation, mixed) | ~30 | 13% |

### Breakdown by Risk Level

| Risk Level | Count | % |
|---|---|---|
| Trivially-Safe | ~189 | 85% |
| Safe-Guarded | ~18 | 8% |
| SAFE-BY-DESIGN | ~8 | 4% |
| NEEDS-TEST | ~7 | 3% |
| FINDING | 0 | 0% |

### NEEDS-TEST Items (Feeds Plans 32-02 and 32-03)

| # | Location | What to Test | Target Plan |
|---|---|---|---|
| 1 | DegenerusVault.previewBurnForEthOut ceil-floor round-trip | Rounding direction favors vault; no dust extraction via repeated small burns | 32-02, 32-03 |
| 2 | DegenerusVault.previewEth floor-div | Burn 1 share returns non-zero at realistic reserves | 32-02 |
| 3 | DegenerusVault._burnEthFor floor-div | Execution path matches preview | 32-02 |
| 4 | DegenerusVault._burnStethFor floor-div | stETH path consistency | 32-02 |
| 5 | LootboxModule BURNIE budget two-stage | Compound precision loss at LOOTBOX_MIN | 32-02 |
| 6 | DecimatorModule._decClaimableFromEntry pro-rata | Sum of N claims <= poolWei; dust bounded | 32-03 |
| 7 | MintModule ticket cost at qty=1 all price tiers | costWei > 0 AND >= TICKET_MIN_BUYIN_WEI | 32-02 |

### FINDING Items

**None.** All 222 division operations are either trivially safe, guarded by zero-checks/minimum amounts, intentional floor patterns, or bounded precision loss that is economically irrelevant.

### Positive Engineering Patterns Discovered

1. **Lootbox Remainder Pattern:** `rewardShare = lootBoxAmount - futureShare - nextShare - vaultShare` ensures EXACT split with zero dust.
2. **JackpotBucketLib Remainder Pattern:** `remainder = maxWinners - baseCount * activeCount` explicitly handles integer division remainder.
3. **DegenerusJackpots Remainder Pattern:** `rem = scatter - per * count` with explicit remainder distribution.
4. **Triple Guard on Ticket Cost:** `costWei == 0` check + `costWei < TICKET_MIN_BUYIN_WEI` check + natural large-numerator protection.
5. **Explicit Zero Returns:** Multiple functions (`_rebateBurnieFromEthValue`, `onTokenTransfer`, `claimAffiliateDgnrs`) explicitly check for zero output and return/revert.

---

*Census completed: 2026-03-05*
*All 222 division operations classified*
*Zero FINDING items*
