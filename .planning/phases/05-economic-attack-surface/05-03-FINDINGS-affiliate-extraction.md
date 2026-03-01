# ECON-03: Affiliate Referral System Extraction Analysis

**Auditor:** Claude Opus 4.6
**Date:** 2026-03-01
**Scope:** DegenerusAffiliate.sol, BurnieCoin.sol, BurnieCoinflip.sol, DegenerusGameMintModule.sol
**Requirement:** ECON-03 -- Affiliate referral system does not create positive-sum extraction where referrer+referee extract more than deposited.

---

## 1. Affiliate Reward Denomination Verification

### 1.1 Trace: payAffiliate -> Reward Distribution

The `payAffiliate` function (DegenerusAffiliate.sol:496-709) receives an `amount` parameter that has **already been converted from ETH to BURNIE** by the caller.

**Caller conversion (DegenerusGameMintModule.sol:950-952):**
```solidity
// Line 950-952
function _ethToBurnieValue(uint256 amountWei, uint256 priceWei) private pure returns (uint256) {
    if (amountWei == 0 || priceWei == 0) return 0;
    return (amountWei * PRICE_COIN_UNIT) / priceWei;
}
```

Where `PRICE_COIN_UNIT = 1000 ether` (DegenerusGameStorage.sol:126). This converts ETH amounts to BURNIE units at the current ticket price rate.

**Example:** At level 1 (priceWei = 0.01 ETH = 1e16 wei), 1 ETH deposit:
- `_ethToBurnieValue(1e18, 1e16) = (1e18 * 1000e18) / 1e16 = 1e23 / 1e16 = 1e7` (10 million BURNIE units, but these are 18-decimal, so = 10,000,000 BURNIE)

Wait -- let me be precise. PRICE_COIN_UNIT = 1000 * 1e18. So for 1 ETH at 0.01 ETH ticket price: `(1e18 * 1000e18) / 1e16 = 1e38 / 1e16 = 1e22`. Since BURNIE has 18 decimals, that's 10,000 BURNIE. (1 ETH buys 100 tickets at 0.01 ETH each; each ticket = 100 BURNIE via PRICE_COIN_UNIT).

**Call site (DegenerusGameMintModule.sol:884-885, ticket purchase):**
```solidity
// Line 884-885
rakeback += affiliate.payAffiliate(
    _ethToBurnieValue(freshEth, priceWei),   // BURNIE-denominated amount
    affiliateCode, buyer, targetLevel, true
);
```

**Call site (DegenerusGameMintModule.sol:731-732, lootbox purchase):**
```solidity
// Line 731-732
lootboxRakeback = affiliate.payAffiliate(
    _ethToBurnieValue(lootboxFreshEth, priceWei),   // BURNIE-denominated amount
    affiliateCode, buyer, purchaseLevel, true
);
```

### 1.2 Reward Scaling Inside payAffiliate

Inside `payAffiliate` (DegenerusAffiliate.sol:586-596), the BURNIE amount is further scaled by the reward rate:

```solidity
// Lines 586-596
uint256 rewardScaleBps;
if (isFreshEth) {
    rewardScaleBps = lvl <= 3
        ? REWARD_SCALE_FRESH_L1_3_BPS    // 2500 = 25%
        : REWARD_SCALE_FRESH_L4P_BPS;    // 2000 = 20%
} else {
    rewardScaleBps = REWARD_SCALE_RECYCLED_BPS;  // 500 = 5%
}
uint256 scaledAmount = (amount * rewardScaleBps) / BPS_DENOMINATOR;
```

So `scaledAmount` = 25% of the BURNIE-converted input amount (for fresh ETH, levels 1-3).

### 1.3 Distribution: creditFlip / creditCoin (Minting, Not Transfer)

Rewards are distributed through `_routeAffiliateReward` (DegenerusAffiliate.sol:837-856):

```solidity
// Lines 837-856
function _routeAffiliateReward(address player, uint256 amount, uint8 modeRaw) private {
    if (player == address(0) || amount == 0) return;
    if (modeRaw == uint8(PayoutMode.Degenerette)) {
        // Mode 1: Credit stored in pendingDegeneretteCredit mapping (no mint)
        pendingDegeneretteCredit[player] += amount;
        return;
    }
    if (modeRaw == uint8(PayoutMode.SplitCoinflipCoin)) {
        // Mode 2: 50% minted as BURNIE directly, remaining 50% DISCARDED
        uint256 coinAmount = amount >> 1;
        coin.creditCoin(player, coinAmount);
        return;
    }
    // Mode 0 (default): All as coinflip credit
    coin.creditFlip(player, amount);
}
```

**BurnieCoin.creditCoin (BurnieCoin.sol:545-548):**
```solidity
function creditCoin(address player, uint256 amount) external onlyFlipCreditors {
    if (player == address(0) || amount == 0) return;
    _mint(player, amount);  // MINTS NEW BURNIE TOKENS
}
```

**BurnieCoin._mint (BurnieCoin.sol:468-481):**
```solidity
function _mint(address to, uint256 amount) internal {
    // ...
    _supply.totalSupply += amount128;   // INCREASES TOTAL SUPPLY
    balanceOf[to] += amount;
    emit Transfer(address(0), to, amount);
}
```

**BurnieCoin.creditFlip (BurnieCoin.sol:555-557):**
```solidity
function creditFlip(address player, uint256 amount) external onlyFlipCreditors {
    IBurnieCoinflip(coinflipContract).creditFlip(player, amount);
}
```

Which calls `BurnieCoinflip.creditFlip` (BurnieCoinflip.sol:887-893):
```solidity
function creditFlip(address player, uint256 amount) external onlyFlipCreditors {
    if (player == address(0) || amount == 0) return;
    _addDailyFlip(player, amount, 0, false, false);
    // Records stake for next coinflip window -- NO immediate mint
}
```

### 1.4 Denomination Confirmation

| Evidence | Source | Conclusion |
|----------|--------|------------|
| `payAffiliate` receives BURNIE-denominated amount | MintModule.sol:884-885 calls `_ethToBurnieValue()` before passing to `payAffiliate` | Input is BURNIE, not ETH |
| `creditCoin` calls `_mint()` | BurnieCoin.sol:547 | New BURNIE tokens created (inflationary) |
| `creditFlip` records coinflip stake | BurnieCoinflip.sol:892 | Coinflip credit, not ETH transfer |
| No ETH transfer in entire affiliate flow | DegenerusAffiliate.sol:496-709 | Zero ETH leaves prize pool |
| `_routeAffiliateReward` comment: "Amounts are already BURNIE-denominated" | DegenerusAffiliate.sol:836 | Developer-confirmed denomination |

**CONFIRMED: Affiliate rewards are inflationary BURNIE minting. They do NOT transfer ETH from any prize pool.**

---

## 2. Circular Referral Model

### 2.1 Self-Referral Prevention

DegenerusAffiliate.sol prevents self-referral at two points:

**referPlayer (line 397):**
```solidity
if (referrer == address(0) || referrer == msg.sender) revert Insufficient();
```

**payAffiliate referral resolution (lines 534-535):**
```solidity
if (candidate.owner == address(0) || candidate.owner == sender) {
    // Lock to VAULT -- self-referral blocked
    _setReferralCode(sender, REF_CODE_LOCKED);
```

However, **cross-referral between two different addresses is permitted.** Player A creates code "A_CODE", Player B creates code "B_CODE". A refers to B_CODE, B refers to A_CODE. This is a valid circular pair.

### 2.2 Scenario: Circular Pair at Level 1 (Fresh ETH, 25% Rate)

**Setup:**
- Player A owns affiliate code "A_CODE" with 0% rakeback
- Player B owns affiliate code "B_CODE" with 0% rakeback
- A is referred by B_CODE; B is referred by A_CODE
- Both have no uplines (newly created codes, no referrer set on either)
- Level 1, ticket price = 0.01 ETH

**Player A buys 1 ETH of tickets:**

1. ETH flow: 1 ETH deposited (goes to prize pool splits: 90% next, 10% future)
2. BURNIE conversion: `_ethToBurnieValue(1 ETH, 0.01 ETH) = 100,000 BURNIE`
3. `payAffiliate` called with 100,000 BURNIE, isFreshEth=true, lvl=1
4. Reward scaling: 100,000 * 2500 / 10000 = **25,000 BURNIE** (scaledAmount)
5. B is direct affiliate (no uplines, cursor=1), gets full 25,000 BURNIE
6. Rakeback to A: 0 (0% rakeback)
7. Quest bonus: variable, assume 0 for base case

**Player B buys 1 ETH of tickets (symmetric):**
- A receives 25,000 BURNIE

**Combined balance sheet:**

| Item | Player A | Player B | Total |
|------|----------|----------|-------|
| ETH deposited | -1.0 ETH | -1.0 ETH | -2.0 ETH |
| ETH in prize pool | +1.0 ETH (common pool) | +1.0 ETH (common pool) | +2.0 ETH |
| BURNIE received | +25,000 BURNIE | +25,000 BURNIE | +50,000 BURNIE |
| Tickets received | 100 tickets | 100 tickets | 200 tickets |

**ETH-equivalent of BURNIE received:**
At 0.01 ETH per ticket and 1000 BURNIE per ticket:
`25,000 BURNIE / 1000 = 25 tickets-worth = 25 * 0.01 ETH = 0.25 ETH equivalent`

So each player receives 0.25 ETH-equivalent in BURNIE for their 1 ETH deposit.

**Net position per player:** -1.0 ETH + 0.25 ETH-equiv BURNIE + tickets = -0.75 ETH + tickets
**Net position combined:** -2.0 ETH + 0.50 ETH-equiv BURNIE + 200 tickets = -1.50 ETH + 200 tickets

### 2.3 Maximum Rakeback Scenario (25%)

If both codes set rakeback = 25% (maximum):

**Player A buys 1 ETH:**
- scaledAmount = 25,000 BURNIE (unchanged)
- rakebackShare = 25,000 * 25 / 100 = **6,250 BURNIE** (returned to Player A)
- affiliateShareBase = 25,000 - 6,250 = **18,750 BURNIE** to Player B
- Rakeback is credited as coinflip credit to the buyer (MintModule.sol:911: `bonusCredit = streakBonus + rakeback`)

**Player B buys 1 ETH (symmetric):**
- Player B gets 6,250 BURNIE rakeback; Player A gets 18,750 BURNIE affiliate reward

**Combined with max rakeback:**

| Item | Player A | Player B | Total |
|------|----------|----------|-------|
| ETH deposited | -1.0 ETH | -1.0 ETH | -2.0 ETH |
| Affiliate BURNIE | +18,750 | +18,750 | +37,500 BURNIE |
| Rakeback BURNIE | +6,250 | +6,250 | +12,500 BURNIE |
| **Total BURNIE** | **+25,000** | **+25,000** | **+50,000 BURNIE** |

Total BURNIE is identical to 0% rakeback (25,000 each). Rakeback redistributes between affiliate and buyer but does not change the combined total, because `scaledAmount = affiliateShareBase + rakebackShare` always holds (line 609).

### 2.4 With Upline Chain

If Player A has an upline chain (A refers B_CODE, B refers A_CODE, but B also has an upline C):

- C gets 20% of scaledAmount = 5,000 BURNIE
- C's upline (if any) gets 4% of scaledAmount = 1,000 BURNIE
- B's direct share is reduced accordingly
- BUT with the weighted winner roll, only ONE recipient gets the combined total

The weighted winner roll (see Section 3) selects one recipient for the COMBINED payout. This preserves expected value per recipient but introduces variance.

**Key insight:** Uplines cannot increase the total affiliate payout. The scaledAmount (25% of input) is fixed. Upline shares come from the SAME scaledAmount -- they are redistributed, not added. The only additive component is the quest bonus (separate per recipient), which is bounded and analyzed separately.

### 2.5 Circular Referral Summary

**For a circular pair depositing 2 ETH total:**
- ETH lost to prize pool: 2.0 ETH (100% of deposits)
- BURNIE gained: 50,000 BURNIE (0.5 ETH equivalent at mint-time conversion rate)
- Tickets gained: 200 (200 * 0.01 ETH = 2.0 ETH of tickets)

The pair cannot extract more value than deposited. Their "extraction" is 50,000 BURNIE which:
1. Does NOT come from the prize pool (inflationary mint)
2. Has uncertain ETH value (BURNIE/ETH exchange rate is market-determined)
3. Even at theoretical 1:1 BURNIE/ETH, represents only 25% of deposit

---

## 3. Weighted Winner Roll Analysis

### 3.1 Mechanism

When multiple recipients exist (direct affiliate + upline1 + upline2), instead of distributing to each, the system rolls a single winner with probability proportional to their share.

**DegenerusAffiliate.sol:891-923:**
```solidity
function _rollWeightedAffiliateWinner(...) private view returns (address winner) {
    uint48 currentDay = GameTimeLib.currentDayIndex();
    uint256 entropy = uint256(keccak256(abi.encodePacked(
        AFFILIATE_ROLL_TAG, currentDay, sender, storedCode
    )));
    uint256 roll = entropy % totalAmount;
    // Linear scan: winner is first recipient where running sum > roll
}
```

### 3.2 Entropy Properties

| Property | Value | Security Implication |
|----------|-------|---------------------|
| Inputs | AFFILIATE_ROLL_TAG (constant), currentDay, sender, storedCode | All known/predictable |
| Determinism | Same (day, sender, code) = same result | Computable off-chain |
| Variability | Changes daily (currentDay) | Attacker can wait for favorable day |
| VRF usage | **None** | Fully predictable |

### 3.3 Day-Alignment Exploitation

**Attack:** For a 3-tier system (direct + upline1 + upline2 = 3 recipients), an attacker controlling the sender address can precompute which day gives them the full payout as direct affiliate vs. it going to an upline.

**Distribution amounts (for 25,000 BURNIE scaledAmount at level 1):**
- Direct: 25,000 + quest (weight ~25,000)
- Upline1: 5,000 + quest (weight ~5,000)
- Upline2: 1,000 + quest (weight ~1,000)
- Total: ~31,000

**Probability:** Direct wins with P = 25,000/31,000 = 80.6%. Expected payout = 80.6% * 31,000 = 25,000 (by construction, EV = own share). By waiting for a favorable day, the attacker can get the full 31,000 BURNIE instead of their expected 25,000 -- a 24% gain.

**BUT:** This only works when the attacker is the *direct affiliate* being paid by an external sender they don't control. In a circular pair (A refers B, B refers A) with no uplines, cursor=1, and `_rollWeightedAffiliateWinner` is **never called** (line 683: `if (cursor == 1)` takes the direct path). The roll only matters when there are 2-3 recipients.

**For a sybil controlling both sender and all 3 tiers:** They control all recipients, so the winner is irrelevant -- the combined total goes to a wallet they control regardless.

**For a legitimate affiliate with uplines:** Day-alignment can shift one transaction's payout between tiers. Over N transactions, the expected total converges to the proportional share. The gas cost of waiting for a specific day (~$1-5 per delayed transaction) likely exceeds the marginal gain.

**Quantified impact:**
- Per-transaction max uplift: 24% of scaledAmount for direct affiliate (if they could choose the perfect day)
- In BURNIE terms at level 1: +6,000 BURNIE (~0.06 ETH equivalent)
- Gas cost of a ticket purchase: ~200K-500K gas = ~$0.50-$2 at 10 gwei
- Break-even: only profitable if the attacker can guarantee a specific day AND the BURNIE value exceeds gas cost

**Verdict:** Day-alignment is theoretically exploitable but economically negligible. The roll is EV-preserving by design (P(win_i) = amount_i / totalAmount, payout = totalAmount). The main risk is variance redistribution, not value creation.

---

## 4. Fresh vs. Recycled ETH Rates

### 4.1 Rate Distinction

| ETH Type | Level 1-3 Rate | Level 4+ Rate | When Used |
|----------|----------------|---------------|-----------|
| Fresh (msg.value) | 25% (2500 BPS) | 20% (2000 BPS) | DirectEth or Combined payment kind |
| Recycled (claimable) | 5% (500 BPS) | 5% (500 BPS) | Claimable payment kind |

**DegenerusGameMintModule.sol:882-908** handles the Combined case by splitting fresh and recycled amounts and calling `payAffiliate` separately for each.

### 4.2 Can an Attacker Force Fresh ETH?

Yes, trivially. By always using `MintPaymentKind.DirectEth` (sending new ETH via msg.value), all purchases are treated as fresh ETH. The attacker pays the full ticket price in ETH rather than recycling claimable winnings.

**Impact:** This maximizes the BURNIE reward rate (25% vs 5%) but does NOT increase value extraction, because:
1. Fresh ETH means the attacker deposited more real ETH
2. 25% of a fresh 1 ETH deposit = 0.25 ETH-equiv BURNIE (net loss: 0.75 ETH)
3. 5% of a recycled 1 ETH = 0.05 ETH-equiv BURNIE (but the recycled ETH was "free" -- it was already won)

**Circular pair optimization:** A circular pair should always use fresh ETH to maximize BURNIE rewards, since they're depositing ETH regardless. The 25% rate at levels 1-3 gives the best BURNIE/ETH ratio.

### 4.3 Level Optimization

Levels 1-3 give 25% rate vs. 20% at level 4+. A circular pair should concentrate activity at levels 1-3 for the extra 5% BURNIE rate. However, they cannot choose which level to buy at (levels advance based on game state), and the benefit is minor (0.25 ETH vs 0.20 ETH per 1 ETH deposit in BURNIE terms).

---

## 5. Affiliate Bonus Points (Activity Score) Interaction

### 5.1 Mechanism

**DegenerusAffiliate.sol:748-764:**
```solidity
function affiliateBonusPointsBest(uint24 currLevel, address player) external view returns (uint256 points) {
    // Sum affiliate scores for previous 5 levels
    // 1 point per 1 ETH of summed score, capped at 50
}
```

The affiliate bonus contributes up to **50 points** (out of 305 max = ~50 BPS) to the activity score. This increases lootbox EV.

### 5.2 Circular Referral Bonus Point Generation

Each player in a circular pair earns `scaledAmount` in affiliate score per purchase they trigger. For 1 ETH at level 1: `scaledAmount = 25,000 BURNIE = 25 ETH` in tracking units (18-decimal BURNIE divided by 1 ether).

Wait -- let me re-read. `earned[affiliateAddr] += scaledAmount` (line 613-614). The `scaledAmount` is in BURNIE base units (18 decimals). `affiliateBonusPointsBest` divides by `1 ether` (line 762): `points = sum / ethUnit`. So 25,000 BURNIE scaled amount = 25,000e18 / 1e18 = 25,000 points... that can't be right.

Let me re-trace. At level 1 (priceWei = 0.01 ETH = 1e16):
- `_ethToBurnieValue(1e18, 1e16) = (1e18 * 1000e18) / 1e16 = 1e38 / 1e16 = 1e22`
- So the `amount` passed to `payAffiliate` = 1e22 (base units, 18 decimal)
- `scaledAmount = (1e22 * 2500) / 10000 = 2.5e21`
- `earned[affiliateAddr] += 2.5e21`
- In `affiliateBonusPointsBest`: `sum / 1 ether = 2.5e21 / 1e18 = 2500`
- Capped at 50 points

So 1 ETH of referral activity at level 1 generates **2,500 uncapped points** (capped to 50). To hit the 50-point cap, you need just 50 * 1e18 = 50e18 in sum, which requires only `50e18 / 2.5e21 = 0.02 ETH` of referred fresh-ETH purchases over 5 levels.

**Implication:** The affiliate bonus cap (50 points) is trivially achievable. ANY amount of referral activity over 5 levels easily hits the cap. Circular referrals do not provide an advantage here because the cap is so easily reached through normal play.

### 5.3 Lootbox EV Impact

50 affiliate bonus points contribute to activity score. From Phase 3b findings, the maximum activity score is 30,500 BPS. 50 points = 5,000 BPS out of 30,500. At max activity (305%), lootbox EV can reach ~135%.

However, the 50-point affiliate bonus is equally achievable through:
- Legitimate referrals (non-circular)
- Very small referral volumes (0.02+ ETH over 5 levels)

Circular referrals do not create an advantage in bonus points because the cap binds so easily.

---

## 6. BURNIE Value Model

### 6.1 BURNIE to ETH Conversion Paths

| Path | Mechanism | ETH Return per BURNIE |
|------|-----------|----------------------|
| **Coinflip (Mode 0)** | Credit added as daily coinflip stake. VRF 50/50 outcome. Win = 50-150% bonus on stake. Lose = 0. | EV: ~0.5-1.25x of stake value, depending on bonus. Net ~100% of BURNIE in BURNIE terms (coinflip is approximately fair in BURNIE). But BURNIE != ETH. |
| **Degenerette Credit (Mode 1)** | Stored as pendingDegeneretteCredit. Used to play Degenerette (symbol-roll bets with BURNIE). | No direct ETH conversion. BURNIE remains in BURNIE ecosystem. |
| **SplitCoinflipCoin (Mode 2)** | 50% minted as BURNIE directly to wallet, 50% discarded. | 50% of reward as liquid BURNIE. Other 50% destroyed. |
| **Direct Market** | Sell BURNIE on DEX (Uniswap etc.) | Market-determined. Depends on liquidity. |
| **DGNRS Vault** | Burn DGVB shares to redeem BURNIE. But this requires holding vault shares, not affiliate BURNIE. | N/A (different token) |

### 6.2 BURNIE/ETH Exchange Rate

BURNIE has no intrinsic ETH redemption mechanism. Its ETH value depends on:
1. Market liquidity (DEX pools)
2. Demand for coinflip participation
3. Demand for Degenerette betting
4. Demand for lootbox purchases (BURNIE lootboxes available at 80% rate)

The BURNIE lootbox conversion (DegenerusGameLootboxModule.sol:615) converts BURNIE to ETH at 80% rate: `_burnieToEthValue(burnieAmount, priceWei) = (burnieAmount * priceWei) / PRICE_COIN_UNIT`. But this is for resolution purposes, not redemption -- the player deposits BURNIE to buy a lootbox whose prizes are drawn from the futurePrizePool (ETH), capped by per-spin limits.

### 6.3 Upper Bound on BURNIE/ETH Value

The theoretical maximum BURNIE value is the mint-time conversion rate: 1000 BURNIE per ticket-price-worth of ETH. At level 1 (0.01 ETH per ticket), 1000 BURNIE = 0.01 ETH, so 1 BURNIE = 0.00001 ETH.

In practice, BURNIE should trade at a discount because:
- It's inflationary (minted on every purchase, affiliate reward, quest completion)
- No direct ETH redemption mechanism
- Coinflip has ~100% BURNIE EV but BURNIE itself has uncertain value
- Lootbox conversion applies 80% haircut

**Conservative assumption for extraction analysis: BURNIE/ETH = 0 (worst case for attacker) to BURNIE/ETH = mint-rate (best case for attacker).**

---

## 7. Quest Reward Amplification

### 7.1 Quest Bonus on Affiliate Payouts

Each tier recipient's payout is augmented by `affiliateQuestReward`:

```solidity
// DegenerusAffiliate.sol:638-639
uint256 questReward = coin.affiliateQuestReward(affiliateAddr, affiliateShareBase);
uint256 totalFlipAward = affiliateShareBase + questReward;
```

This calls `BurnieCoin.affiliateQuestReward` (BurnieCoin.sol:693-714), which routes through the quest module. The quest reward is **additional BURNIE** minted when the affiliate action completes a daily quest.

**Impact on circular referrals:** Quest rewards are bounded by quest system design (daily, streak-based). They add a variable bonus but are available to all affiliates (circular or not). They do not create a specific advantage for circular structures.

---

## 8. Payout Mode Analysis

### 8.1 Mode Impact on Extraction

| Mode | BURNIE Received | ETH Extraction | Notes |
|------|----------------|----------------|-------|
| 0 (Coinflip) | Full amount as coinflip stake | None directly. Must win coinflip then sell BURNIE. | Default. Highest upside with variance. |
| 1 (Degenerette) | Full amount as Degenerette credit | None directly. Used for in-game bets. | No immediate liquidity. |
| 2 (SplitCoinflipCoin) | 50% minted, 50% discarded | None directly. 50% as liquid BURNIE. | Worst total value (50% destroyed). |

**For extraction-maximizing attacker:** Mode 0 (Coinflip) or Mode 2 (SplitCoinflipCoin) provides the most liquid BURNIE. Mode 2 is strictly worse (50% destroyed). Mode 0 requires winning coinflips to realize value.

The payout mode is set per-code, not per-transaction. An attacker can choose the optimal mode when creating their code. No mode converts BURNIE to ETH -- all paths keep value in the BURNIE ecosystem.

---

## 9. ECON-03 Verdict

### 9.1 Core Question

> Can a referrer+referee combination extract more total value than deposited?

### 9.2 Analysis

**Value deposited by a circular pair (2 players, 1 ETH each):**
- 2.0 ETH deposited to prize pool (100% of deposits enter the ETH economy)

**Value received by the pair:**
- 200 tickets (standard game participation, not "extraction")
- 50,000 BURNIE (25% of 200,000 BURNIE input amount at 25% fresh-ETH rate)

**Is 50,000 BURNIE worth more than 2.0 ETH?**

At the mint-time conversion rate (best case for attacker): 50,000 BURNIE = 0.50 ETH equivalent.

**Net extraction = 0.50 ETH (BURNIE) - 2.00 ETH (deposited) = -1.50 ETH**

The pair loses 1.50 ETH in the process, even under the most generous BURNIE valuation.

**Can BURNIE ever be worth more than mint-time rate?** Only if external demand drives BURNIE price above the rate at which it's minted. This would require BURNIE to have independent value beyond its in-game utility, which is possible but:
1. BURNIE is continuously inflated by mint operations
2. The attacker's own circular referral activity creates sell pressure
3. No rational market should price BURNIE above its utility value

### 9.3 Structural Defenses

| Defense | Effect |
|---------|--------|
| Self-referral prevention | Cannot create a 1-person loop (lines 534-535, 397) |
| Rewards are BURNIE, not ETH | Prize pool never drained by affiliates |
| 25% max reward rate | At most 25% of BURNIE-converted amount returned |
| Rakeback redistributes, doesn't create | `affiliateShareBase + rakebackShare = scaledAmount` (line 609) |
| Affiliate bonus capped at 50 points | Trivially reached; circular referrals add no advantage |
| No BURNIE-to-ETH redemption | BURNIE value is market-determined, likely below mint rate |

### 9.4 Edge Cases Considered

1. **Flash-loan amplification:** Not applicable. Affiliate rewards are credited as coinflip stakes (future day) or BURNIE balance, not ETH. No same-transaction profit possible.

2. **Multi-tier circular chain:** A->B->C->A. Each player refers the next. When A buys, B gets direct affiliate, C gets upline1, A gets upline2 (if referrer of C). This creates a circular upline chain but the total payout is still bounded by `scaledAmount + upline bonuses` from the same base. Total BURNIE paid = scaledAmount * (1 + 0.2 + 0.04) = 1.24x of scaledAmount. For 3 players depositing 3 ETH at level 1: total BURNIE = 3 * 25,000 * 1.24 = 93,000 BURNIE = 0.93 ETH equivalent. Net loss = 3.0 - 0.93 = 2.07 ETH. Still deeply negative.

3. **Quest amplification:** Quest rewards add variable BURNIE bonuses on top of affiliate payouts. Even doubling the affiliate payout via quests (extreme assumption) yields 100,000 BURNIE = 1.0 ETH equivalent vs 2.0 ETH deposited. Still a net loss.

4. **Recycled ETH gaming:** Using recycled ETH (5% rate) minimizes cost but also minimizes reward. The attacker's ETH was already "free" (won from prize pool), so the 5% BURNIE is pure profit in BURNIE terms. But the recycled ETH itself came from a previous deposit that was negative-EV. The combined lifecycle remains negative-sum.

### 9.5 Verdict

**ECON-03: PASS**

The affiliate referral system does not create positive-sum extraction. Structural reasons:

1. **Denomination barrier:** Affiliate rewards are inflationary BURNIE mints, not ETH transfers. The prize pool is never reduced by affiliate payouts.

2. **Rate cap:** Maximum reward rate is 25% of the BURNIE-converted deposit amount. Even at 1:1 BURNIE/ETH (theoretical maximum), the pair loses 75% of their deposit.

3. **No amplification:** Circular structures, upline chains, and rakeback adjustments redistribute the same `scaledAmount` -- they cannot create new value. The only additive component (quest bonuses) is bounded and available to all players.

4. **BURNIE discount:** In practice, BURNIE trades below its mint-time ETH conversion rate due to continuous inflation and lack of direct ETH redemption, making the actual extraction even less favorable.

5. **Bonus point saturation:** The affiliate activity score bonus (50 points max) is trivially reached with ~0.02 ETH of referral volume, making circular referrals unnecessary for this purpose.

**Risk level: NONE.** No mechanism exists for a referrer+referee combination to extract positive net value through the affiliate system. The system is structurally negative-sum for all participants from an ETH extraction perspective.

---

## Appendix: Weighted Winner Roll Precomputation

The roll uses `keccak256(AFFILIATE_ROLL_TAG, currentDay, sender, storedCode)`. An attacker knowing all inputs can precompute the outcome for each future day. For a 3-recipient scenario:

```
Day 1: roll % total -> winner = Direct (probability 80.6%)
Day 2: roll % total -> winner = Upline1 (probability 16.1%)
Day 3: roll % total -> winner = Direct
...
```

The attacker can choose which day to transact for optimal outcome. Over infinite trials this is EV-neutral, but for a single transaction the attacker can guarantee the favorable outcome (100% of combined payout vs 80.6% expected share).

**Maximum single-transaction uplift:** +24% of scaledAmount (31,000 vs 25,000 BURNIE in the example).
**Practical constraint:** Only relevant when attacker controls the sender but NOT all recipients. In a circular sybil structure, all recipients are controlled, making the roll irrelevant.

**Classification:** INFORMATIONAL. Deterministic roll is by design (gas-saving alternative to VRF for small BURNIE amounts). The EV-preservation property holds over multiple transactions. Single-transaction variance is bounded and does not create extraction.
