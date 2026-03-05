# Reward Manipulation and Boon Stacking Report

**Phase:** 34 -- Economic Composition and Auditor Re-examination
**Plan:** 02
**Date:** 2026-03-05
**Analyst:** Independent source-level trace

---

## ECON-04: Activity Score Manipulation Cost-Benefit Analysis

### Activity Score Components Traced from Source

**Source:** `DegenerusGame.sol` lines 2420-2482, `DegenerusGameDegeneretteModule.sol` lines 1052-1099

The activity score is computed inline at lootbox opening time via `_lootboxEvMultiplierBps()` which calls `playerActivityScore()`. The score is a composite BPS value built from five components:

#### Component 1: Mint Streak (max 5000 BPS / 50%)

**Source:** Lines 2435-2436: `uint256 streakPoints = streak > 50 ? 50 : uint256(streak);`

- 1 point per consecutive level with ETH mint, capped at 50 points
- Translated to BPS: `streakPoints * 100` (line 2451)
- **Cost to maximize:** 1 ETH-mint ticket per level for 50 consecutive levels. At level prices starting ~0.0015 ETH and increasing, minimum cost is the sum of 50 level prices. Conservatively ~0.5-5 ETH depending on starting level.
- **Pass holder floor:** If whale/deity pass active, streak is floored at `PASS_STREAK_FLOOR_POINTS` (line 2444)

#### Component 2: Mint Count (max 2500 BPS / 25%)

**Source:** `_mintCountBonusPoints()` (lines 2493-2504):

```solidity
if (currLevel == 0) return 0;
if (mintCount >= currLevel) return 25;
return (uint256(mintCount) * 25) / uint256(currLevel);
```

- Ratio-based: `mintCount / currLevel * 25`, max 25 points
- Perfect participation (mint every level) = 25 points = 2500 BPS
- **Cost to maximize:** 1 ETH-mint per level for all levels played. Same as streak cost but requires ALL levels, not just consecutive.
- **Pass holder floor:** Floored at `PASS_MINT_COUNT_FLOOR_POINTS` if pass active (line 2448)

#### Component 3: Quest Streak (max 10000 BPS / 100%)

**Source:** Lines 2457-2461:

```solidity
(uint32 questStreakRaw, , , ) = questView.playerQuestStates(player);
uint256 questStreak = questStreakRaw > 100 ? 100 : uint256(questStreakRaw);
bonusBps += questStreak * 100;
```

- 1 point per consecutive daily quest completion, capped at 100 (=10000 BPS)
- `awardQuestStreakBonus()` is called by the Quests contract (access-controlled)
- **Cost to maximize:** 100 consecutive days of quest completion. Quests require gameplay actions (purchases, claims, etc.), each with ETH cost.

#### Component 4: Affiliate Bonus (max 5000 BPS / 50%)

**Source:** Line 2465-2467:

```solidity
bonusBps += affiliate.affiliateBonusPointsBest(currLevel, player) * 100;
```

- Based on affiliate earnings over last 5 levels relative to a denominator
- Max 50 points (5000 BPS)
- **Cost to maximize:** Generating sufficient affiliate volume. Requires referred players to make purchases. Cannot be self-generated due to self-referral guards (ECON-03).

#### Component 5: Pass Bonus (1000-8000 BPS)

**Source:** Lines 2469-2478:

```solidity
if (hasDeityPass) {
    bonusBps += DEITY_PASS_ACTIVITY_BONUS_BPS; // 8000 = 80%
} else if (frozenUntilLevel > currLevel) {
    if (bundleType == 1) bonusBps += 1000;      // Whale 10-level: +10%
    else if (bundleType == 3) bonusBps += 4000;  // Whale 100-level: +40%
}
```

- Deity pass: 80% (8000 BPS), cost 24+ ETH
- Whale 100-level: 40% (4000 BPS), cost 4 ETH
- Whale 10-level: 10% (1000 BPS), cost 2.4 ETH

**Note:** Deity pass holders get a shortcut (lines 2431-2433): streak=50 and mintCount=25 automatically, bypassing those two components. Total deity base: 50+25+100+50+80 = 305% max.

### EV Extraction Calculation

**Lootbox EV multiplier** (LootboxModule lines 479-500):

| Activity Score | EV Multiplier |
|---------------|---------------|
| 0 BPS (0%) | 8000 BPS (80%) |
| 6000 BPS (60%) | 10000 BPS (100%) -- neutral |
| 25500 BPS (255%) | 13500 BPS (135%) -- max |

**EV Benefit Cap** (lines 331-332): `LOOTBOX_EV_BENEFIT_CAP = 10 ether` per account per level.

The cap is enforced in `_applyEvMultiplierWithCap()` (lines 510-544):
- Tracks `lootboxEvBenefitUsedByLevel[player][lvl]`
- Only applies EV multiplier to uncapped portion
- Remainder gets 100% EV (neutral)

**Maximum excess EV per level:** 35% of 10 ETH = 3.5 ETH (at 135% multiplier on 10 ETH cap).

### Cost-Benefit of Cheapest Max-EV Path

**Deity pass path (fastest to max EV):**
- Deity pass: 24 ETH (first pass) + T(n) additional
- Gives: 50% streak + 25% mintCount + 80% pass = 155% base
- Still needs: quest streak (100%) to reach 255%+
- Quest streak requires 100 consecutive days
- **Total cost:** 24+ ETH + 100 days of daily quests + ticket purchases for quest completion

**Break-even analysis:**
- Investment: 24 ETH (deity pass)
- Max excess EV per level: 3.5 ETH
- Levels needed to break even on deity pass alone: 24 / 3.5 = ~7 levels
- But: deity pass also provides other benefits (ticket packages, boons), and 3.5 ETH is the MAXIMUM excess EV (requires 255%+ score, which needs 100-day quest streak)

**Sybil scenario:** Create N wallets, each with minimum investment to reach 260% score.
- Each wallet needs: deity pass (24 ETH) OR whale pass (4 ETH) + sustained play
- With whale 100-level pass: 4 ETH + multi-level participation
- Max EV benefit: 3.5 ETH per level (capped)
- Cannot reach 255% without quest streak (100 days) even with whale pass
- Sybil cost per wallet: 4+ ETH + 100 days commitment
- ROI: 3.5 ETH/level * levels_played - 4 ETH - ticket_costs
- **Not profitable for sybil at scale** because each wallet requires 100-day quest commitment

### Activity Boon Interaction

**`consumeActivityBoon()`** (BoonModule lines 309-343):

```solidity
activityBoonPending[player] = 0;
uint24 levelCount = ...; // read from mintPacked_
uint256 countSum = uint256(levelCount) + pending; // pending = 10/25/50
uint24 newLevelCount = ... // capped at uint24 max
```

The activity boon adds 10/25/50 to `levelCount` (not activityScore directly). This affects the `_mintCountBonusPoints()` calculation:

- **Effect on mintCount component:** `mintCount / currLevel * 25`. Adding phantom levels to mintCount INCREASES the ratio (closer to 25 max).
- **But:** This is bounded. If mintCount already >= currLevel, adding more has no effect (already capped at 25 points).
- **At early levels:** Adding 50 to mintCount at level 10 means mintCount=60, currLevel=10, ratio=25 (maxed). This helps reach max mintCount faster.
- **Net EV impact:** Max 2500 BPS (25%) boost to activity score, worth at most `(25% / 255%) * 3.5 ETH = ~0.34 ETH` additional excess EV per level. The boon itself is a lootbox reward with EV already accounted for.

### Verdict: ECON-04

**SAFE.** Activity score manipulation cannot produce net-positive value extraction because:
1. Each component requires proportional ETH investment (tickets, passes)
2. Quest streak requires 100 consecutive days of genuine participation
3. Affiliate bonus requires referred players (cannot self-generate per ECON-03)
4. EV benefit is hard-capped at 10 ETH per account per level
5. Maximum excess EV (3.5 ETH/level) requires 7+ levels to break even on deity pass alone
6. Activity boon adds to levelCount (bounded helper), not a direct score override
7. Sybil attacks are uneconomical due to per-wallet time commitment (100 days)

**Confidence:** HIGH

---

## ECON-05: Boon Effect Stacking and Cross-Category Interaction Analysis

### Complete Boon Lifecycle Trace

**Source:** `contracts/modules/DegenerusGameBoonModule.sol`, `contracts/modules/DegenerusGameLootboxModule.sol`

#### Boon Category 1: Coinflip Boon (5/10/25% BPS)

- **Granted by:** Lootbox RNG (categories BOON_CAT_COINFLIP = 1)
- **Storage:** `coinflipBoonBps[player]`, `coinflipBoonDay[player]`, `deityCoinflipBoonDay[player]`
- **Consumed by:** `consumeCoinflipBoon()` (BoonModule lines 37-59)
- **Applied at:** BurnieCoinflip deposit (external call from Coinflip contract)
- **Consume pattern:** Reads `coinflipBoonBps[player]`, then zeros all three storage slots
- **Expiry:** 2 days (`COINFLIP_BOON_EXPIRY_DAYS = 2`)
- **Verified:** Consumed exactly once. After consumption, bps=0, day=0, deityDay=0.

#### Boon Category 2: Purchase Boost (5/15/25% BPS)

- **Granted by:** Lootbox RNG (categories BOON_CAT_PURCHASE = 4)
- **Storage:** `purchaseBoostBps[player]`, `purchaseBoostDay[player]`, `deityPurchaseBoostDay[player]`
- **Consumed by:** `consumePurchaseBoost()` (BoonModule lines 64-86)
- **Applied at:** Game.purchase() via MintModule
- **Consume pattern:** Reads `purchaseBoostBps[player]`, then zeros all three storage slots
- **Expiry:** 4 days (`PURCHASE_BOOST_EXPIRY_DAYS = 4`)
- **Verified:** Consumed exactly once. Same zero-after-read pattern.

#### Boon Category 3: Lootbox Boost (5/15/25%)

- **Granted by:** Lootbox RNG (categories BOON_CAT_LOOTBOX = 3)
- **Storage:** `lootboxBoon5Active[player]`, `lootboxBoon15Active[player]`, `lootboxBoon25Active[player]` (boolean flags), plus day/deityDay tracking per tier
- **Applied at:** LootboxModule `_recordLootboxEntry()` during lootbox resolution
- **Consume pattern:** Read from boolean storage. NOT consumed on single use -- the boon remains active until it expires or a new boon overwrites it.
- **Expiry:** 2 days (`LOOTBOX_BOOST_EXPIRY_DAYS = 2`)
- **Verified:** Active boons are checked during `checkAndClearExpiredBoon()`. A new lootbox boon of the same tier overwrites the existing one (same storage slot). Multiple tiers CAN be active simultaneously (5%, 15%, 25% are separate booleans). However, the lootbox resolution logic reads the highest active tier.

#### Boon Category 4: Decimator Boost (10/25/50% BPS)

- **Granted by:** Lootbox RNG (categories BOON_CAT_DECIMATOR = 6)
- **Storage:** `decimatorBoostBps[player]`, `deityDecimatorBoostDay[player]`
- **Consumed by:** `consumeDecimatorBoost()` (BoonModule lines 91-104)
- **Applied at:** BurnieCoin.decimatorBurn()
- **Consume pattern:** Reads bps, then zeros both slots
- **Expiry:** No explicit day-based expiry (only deity day check). Persists until consumed or deity day expires.
- **Verified:** Consumed exactly once.

#### Boon Category 5: Whale Discount (10/25/50%)

- **Granted by:** Lootbox RNG (categories BOON_CAT_WHALE = 7)
- **Storage:** `whaleBoonDay[player]`, `whaleBoonDiscountBps[player]`, `deityWhaleBoonDay[player]`
- **Applied at:** WhaleModule.purchaseWhaleBundle()
- **Consume pattern:** Read from storage. Cleared by `checkAndClearExpiredBoon()` or consumed at whale purchase.
- **Verified:** One-time discount application.

#### Boon Category 6: Lazy Pass Discount (10/25/50%)

- **Granted by:** Lootbox RNG (categories BOON_CAT_LAZY_PASS = 12)
- **Storage:** `lazyPassBoonDay[player]`, `lazyPassBoonDiscountBps[player]`, `deityLazyPassBoonDay[player]`
- **Applied at:** WhaleModule.purchaseLazyPass()
- **Expiry:** 4 days
- **Verified:** One-time discount application.

#### Boon Category 7: Deity Pass Discount (tier-based)

- **Granted by:** Lootbox RNG (categories BOON_CAT_DEITY_PASS = 10)
- **Storage:** `deityPassBoonTier[player]`, `deityPassBoonDay[player]`, `deityDeityPassBoonDay[player]`
- **Applied at:** WhaleModule.purchaseDeityPass()
- **Expiry:** 4 days (`DEITY_PASS_BOON_EXPIRY_DAYS = 4`)
- **Verified:** Tier stored as uint8, consumed at deity purchase.

#### Boon Category 8: Activity Boon (10/25/50 points)

- **Granted by:** Lootbox RNG (categories BOON_CAT_ACTIVITY = 9)
- **Storage:** `activityBoonPending[player]`, `activityBoonDay[player]`, `deityActivityBoonDay[player]`
- **Consumed by:** `consumeActivityBoon()` (BoonModule lines 309-343)
- **Applied at:** LootboxModule.openLootBox() via nested delegatecall (LootboxModule line 945)
- **Consume pattern:** Reads `activityBoonPending`, zeros all three slots, adds to `levelCount` in `mintPacked_`
- **Expiry:** 2 days (uses `COINFLIP_BOON_EXPIRY_DAYS`)
- **Verified:** Consumed exactly once. Adds to levelCount, not activityScore directly.

### Cross-Category Stacking Analysis

**Can a player have ALL boon types simultaneously?**

Yes. Each category uses separate storage slots. A player could have:
- Coinflip boon (5% in coinflipBoonBps)
- Purchase boost (15% in purchaseBoostBps)
- Lootbox boost (25% in lootboxBoon25Active)
- Decimator boost (50% in decimatorBoostBps)
- Whale discount (25% in whaleBoonDiscountBps)
- Activity boon (50 points in activityBoonPending)

**Can multiple boons apply in a single transaction?**

Let me trace the `purchase()` flow:
1. MintModule processes purchase -> calls `consumePurchaseBoost()` -> applies boost to ticket/BURNIE calculation
2. If lootbox is included in purchase, LootboxModule processes lootbox -> reads lootbox boost from storage -> applies to lootbox value
3. Activity boon is consumed during lootbox resolution (if triggered)

**Result:** In a single `purchase()` call with lootbox:
- Purchase boost applies to the purchase (extra tickets/BURNIE)
- Lootbox boost applies to lootbox value (separate operation)
- Activity boon applies to levelCount (separate effect)

These three boons CAN apply in the same transaction, but to DIFFERENT operations:
- Purchase boost: affects ticket count calculation
- Lootbox boost: affects lootbox ETH/BURNIE distribution
- Activity boon: affects future activity score (not current lootbox)

**No multiplicative interaction:** Purchase boost does not multiply lootbox boost. Each applies an additive BPS bonus to its own base value independently.

**Can two boons apply to the SAME value calculation?**

Checking all paths:
- Purchase: only `consumePurchaseBoost()` applies
- Lootbox opening: lootbox boost (5/15/25%) applies to base value, activity score affects EV multiplier (separate calculation)
- Coinflip: only `consumeCoinflipBoon()` applies
- Decimator: only `consumeDecimatorBoost()` applies
- Whale/deity purchase: only respective discount boon applies

**Edge case -- lootbox + activity score:** During lootbox resolution, the activity boon is consumed (adding to levelCount). But the EV multiplier was already calculated from the activity score AT THE TIME of opening. The activity boon affects FUTURE lootbox EV, not the current one. No same-value compounding.

### Boon Overwrite and Accumulation

**New boon overwrites existing same-category boon:** Checked in lootbox boon granting code (LootboxModule). When a new coinflip boon is granted while one exists, the new BPS value overwrites the old one. A player cannot accumulate multiple same-category boons.

**`checkAndClearExpiredBoon()`** (BoonModule lines 114-300): Called during lootbox resolution. Sweeps all categories, clearing expired boons. Returns true if any remain active. This prevents stale boons from being applied.

### Verdict: ECON-05

**SAFE.** Boon effect stacking cannot compound to unintended advantage because:
1. Each boon category applies to a distinct operation (coinflip, purchase, lootbox, decimator, whale, lazy, deity, activity)
2. No two boons apply to the same value calculation
3. Within a category, new boons overwrite existing ones (no accumulation)
4. Consume-on-use pattern (zero-after-read) prevents reuse for all consumed boons
5. Lootbox boost is the only non-consumed boon and has time-based expiry
6. Cross-category presence in a single tx produces only additive (not multiplicative) benefits on separate operations
7. Activity boon affects future EV, not current lootbox resolution

**Confidence:** HIGH
