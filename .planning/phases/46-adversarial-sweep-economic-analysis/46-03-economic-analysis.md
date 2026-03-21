# Phase 46 Plan 03: Economic Analysis

**Date:** 2026-03-21
**Scope:** Rational actor strategy analysis + bank-run scenario modeling
**Reference:** Phase 44 solvency proof, Phase 46 research economic formulas

---

## 1. ETH Payout EV Derivation

### Formula Chain

**At submit** (`_submitGamblingClaimFrom`, StakedDegenerusStonk.sol:700-701):
```solidity
uint256 totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue;  // line 700
uint256 ethValueOwed = (totalMoney * amount) / supplyBefore;                        // line 701
```

`ethValueOwed` represents the player's proportional share of unreserved ETH+stETH+claimable holdings. This is the 100% "fair value" for the burned sDGNRS.

**At claim** (`claimRedemption`, StakedDegenerusStonk.sol:585):
```solidity
uint256 ethPayout = (claim.ethValueOwed * roll) / 100;  // line 585
```

**Roll distribution** (DegenerusGameAdvanceModule.sol:792):
```solidity
uint16 redemptionRoll = uint16((currentWord >> 8) % 151 + 25);  // line 792
```

The roll is uniform over [25, 175] (151 equally-likely values).

### Expected Value Calculation

```
E[roll] = (25 + 26 + ... + 175) / 151
        = (sum of 151 terms, first=25, last=175) / 151
        = (151 * (25 + 175) / 2) / 151
        = (25 + 175) / 2
        = 100
```

Therefore:
```
E[ethPayout] = ethValueOwed * E[roll] / 100
             = ethValueOwed * 100 / 100
             = ethValueOwed
```

**Conclusion: ETH payout is EV-neutral.** E[payout] = fair value. The roll introduces variance (minimum 25% of fair value, maximum 175% of fair value) but does not create a systematic edge for or against the player.

---

## 2. BURNIE Payout EV Derivation

### Formula Chain

**At submit** (`_submitGamblingClaimFrom`, StakedDegenerusStonk.sol:706-707):
```solidity
uint256 totalBurnie = burnieBal + claimableBurnie - pendingRedemptionBurnie;  // line 706
uint256 burnieOwed = (totalBurnie * amount) / supplyBefore;                  // line 707
```

**At resolve** (`resolveRedemptionPeriod`, StakedDegenerusStonk.sol:555-558):
```solidity
burnieToCredit = (pendingRedemptionBurnieBase * roll) / 100;  // line 555 -- credited as virtual coinflip stake
pendingRedemptionBurnie -= pendingRedemptionBurnieBase;        // line 558 -- reservation released
```

**At claim** (`claimRedemption`, StakedDegenerusStonk.sol:591-594):
```solidity
(uint16 rewardPercent, bool flipWon) = coinflip.getCoinflipDayResult(period.flipDay);  // line 591
flipResolved = (rewardPercent != 0 || flipWon);                                        // line 592
if (flipResolved && flipWon) {
    burniePayout = (claim.burnieOwed * roll * (100 + rewardPercent)) / 10000;           // line 594
}
```

If the flip is lost or unresolved, burniePayout = 0.

### Coinflip Win Probability

From BurnieCoinflip.sol:809:
```solidity
bool win = (rngWord & 1) == 1;  // line 809 -- 50/50 based on least significant bit
```

**P(win) = 0.5** (exactly).

### rewardPercent Distribution

From BurnieCoinflip.sol:788-798 (`processCoinflipPayouts`):
```solidity
uint256 roll = seedWord % 20;                                        // line 788
uint16 rewardPercent;
if (roll == 0) {
    rewardPercent = 50;                                               // line 791 -- 5% chance
} else if (roll == 1) {
    rewardPercent = 150;                                              // line 793 -- 5% chance
} else {
    rewardPercent = uint16((seedWord % COINFLIP_EXTRA_RANGE) + COINFLIP_EXTRA_MIN_PERCENT);  // line 796-797
    // COINFLIP_EXTRA_RANGE = 38 (line 122), COINFLIP_EXTRA_MIN_PERCENT = 78 (line 121)
    // Range: [78, 115] (38 values), 90% chance
}
```

Distribution:
| Outcome | Probability | rewardPercent |
|---------|-------------|---------------|
| Unlucky | 1/20 = 5%  | 50            |
| Lucky   | 1/20 = 5%  | 150           |
| Normal  | 18/20 = 90% | Uniform [78, 115] |

### Expected rewardPercent Calculation

For the normal band [78, 115] (38 values, uniform):
```
E[rewardPercent | normal] = (78 + 115) / 2 = 96.5
```

Overall:
```
E[rewardPercent] = 0.05 * 50 + 0.05 * 150 + 0.90 * 96.5
                 = 2.5 + 7.5 + 86.85
                 = 96.85
```

### Expected Reward Multiplier

The BURNIE multiplier is `(100 + rewardPercent) / 100`:
```
E[(100 + rewardPercent) / 100] = (100 + 96.85) / 100 = 1.9685
```

### Full BURNIE EV Calculation

The roll (from AdvanceModule.sol:792, bits 8+ of VRF word) and the rewardPercent (from BurnieCoinflip.sol:783, keccak256 of VRF word with epoch) are derived from different entropy derivations, so they are independent. The coinflip win/loss (bit 0 of VRF word) is also independent of the upper bits.

```
E[burniePayout] = P(win) * burnieOwed * E[roll/100] * E[(100 + rewardPercent)/100]
                = 0.5 * burnieOwed * 1.0 * 1.9685
                = 0.98425 * burnieOwed
```

**Conclusion: BURNIE payout has a 1.575% house edge.** The expected BURNIE payout is 98.425% of fair value. This comes from the combination of:
- 50% flip probability (halves the payout)
- ~1.97x average multiplier on win (nearly doubles it back)
- Net effect: 0.5 * 1.9685 = 0.98425 (slightly below 1.0)

The slight sub-neutrality is due to E[rewardPercent] = 96.85 < 100 -- the 90% normal band has a midpoint of 96.5, which is below the 100% "neutral" threshold. This creates a small structural advantage for the protocol.

---

## 3. Rational Actor Strategy Catalog

### Strategy 1: Timing Attack -- Predict Roll Before Burning

**Description:** Player attempts to observe VRF fulfillment and front-run `advanceGame` to burn at a favorable moment when the roll outcome is known.

**Steps:**
1. Player monitors mempool for VRF fulfillment callback
2. Player observes the VRF word before it is consumed by `advanceGame`
3. Player submits `burn()` transaction to front-run `advanceGame`
4. Player hopes the roll (derived from VRF word) is favorable (>100)

**Cost:** Gas for burn transaction (~200k gas) + monitoring infrastructure

**Expected Return:** N/A -- the attack is blocked by the `rngLocked` guard.

**Repeatability:** N/A

**Verdict:** UNPROFITABLE (no information advantage)

**Evidence:**
- StakedDegenerusStonk.sol:437 -- `if (game.rngLocked()) revert BurnsBlockedDuringRng();` (in `burn`)
- StakedDegenerusStonk.sol:454 -- `if (game.rngLocked()) revert BurnsBlockedDuringRng();` (in `burnWrapped`)
- DegenerusGameAdvanceModule.sol:792 -- roll is computed from VRF word DURING `advanceGame`, not before

**Detail:** The `rngLocked` guard blocks ALL burns while a VRF request is pending (between request and fulfillment). Burns can only occur BEFORE the VRF request is made for the current period. At burn time, the player commits without knowing the future VRF word. After the burn, the roll is determined during `resolveRedemptionPeriod` called within `advanceGame`, using `(currentWord >> 8) % 151 + 25` where `currentWord` is the just-fulfilled VRF word. The player has zero information advantage because the VRF word does not exist at burn time.

---

### Strategy 2: Cap Boundary Manipulation

**Description:** Player monitors `redemptionPeriodBurned` approaching the 50% supply cap and times their burn to be the last burn in a period, consuming remaining cap space to deny others.

**Steps:**
1. Player monitors `redemptionPeriodBurned` approaching `redemptionPeriodSupplySnapshot / 2`
2. Player submits burn for the exact remaining cap space
3. Subsequent burners in the same period are blocked by the `Insufficient()` revert
4. Player receives their proportional share

**Cost:** Gas for burn (~200k gas) + monitoring infrastructure

**Expected Return:** Proportional share -- identical to burning at any other time in the period

**Repeatability:** per-period

**Verdict:** NEUTRAL (no edge from timing within period)

**Evidence:**
- StakedDegenerusStonk.sol:691 -- `if (redemptionPeriodBurned + amount > redemptionPeriodSupplySnapshot / 2) revert Insufficient();` (50% cap check)
- StakedDegenerusStonk.sol:692 -- `redemptionPeriodBurned += amount;` (global accumulator)
- StakedDegenerusStonk.sol:700 -- `totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue` (deducts already-segregated funds)
- StakedDegenerusStonk.sol:701 -- `ethValueOwed = (totalMoney * amount) / supplyBefore` (proportional share)

**Detail:** The proportional share formula `(totalMoney * amount) / supplyBefore` gives fair value regardless of when in the period the burn occurs. Being "last" in a period does not yield extra ETH because each successive burn sees a reduced `totalMoney` (prior burns have already incremented `pendingRedemptionEthValue`, which is subtracted at line 700). The cap is a circuit breaker that limits per-period exposure, not a resource that grants advantage to the last consumer. Denial of service to other burners is temporary (they can burn in the next period) and provides no economic benefit to the attacker.

---

### Strategy 3: Stale Accumulation -- Never Claiming

**Description:** Player burns sDGNRS, receives a gambling claim, and intentionally never calls `claimRedemption`, holding segregated ETH indefinitely.

**Steps:**
1. Player burns sDGNRS, creating a PendingRedemption
2. Period is resolved, player's roll is determined
3. Player never calls `claimRedemption`
4. Segregated ETH remains locked in `pendingRedemptionEthValue` indefinitely

**Cost:** Lost opportunity cost of locked ETH/BURNIE; player cannot participate further

**Expected Return:** None (funds are locked, cannot be redeemed or re-burned)

**Repeatability:** one-time per address

**Verdict:** UNPROFITABLE (self-DoS, no benefit)

**Evidence:**
- StakedDegenerusStonk.sol:724-725 -- `if (claim.periodIndex != 0 && claim.periodIndex != currentPeriod) { revert UnresolvedClaim(); }` (blocks new burns while holding unresolved claim from a different period)
- StakedDegenerusStonk.sol:700 -- `totalMoney = ... - pendingRedemptionEthValue` (stale claim's value is excluded from other burners' proportional share)

**Detail:** The `UnresolvedClaim` revert at line 724-725 prevents the player from submitting a new burn while holding an unclaimed resolved claim from a different period. The player blocks THEMSELVES from further participation. Other players are completely unaffected -- their proportional shares are computed from `totalMoney`, which subtracts `pendingRedemptionEthValue` (line 700). The stale claim's `ethValueOwed` remains in `pendingRedemptionEthValue`, so subsequent burners compute shares against only unreserved assets. There is no systemic risk: the stale ETH is segregated indefinitely, reducing the contract's "active" pool but not creating any insolvency or advantage.

---

### Strategy 4: Multi-Address Splitting (Sybil)

**Description:** Player distributes sDGNRS across multiple addresses to bypass per-address limits or game the 50% cap.

**Steps:**
1. Player acquires sDGNRS via DGNRS wrapper (sDGNRS is soulbound, no direct transfer)
2. Player uses multiple DGNRS addresses to unwrap/burn independently
3. Each address burns and claims independently
4. Player aggregates ETH/BURNIE payouts across addresses

**Cost:** N * gas for burn + N * gas for claim + N DGNRS transfer fees

**Expected Return:** Same total EV as a single burn (proportional share is linear in amount)

**Repeatability:** per-period

**Verdict:** UNPROFITABLE (higher gas cost, same EV)

**Evidence:**
- StakedDegenerusStonk.sol:692 -- `redemptionPeriodBurned += amount;` (GLOBAL accumulator, not per-address)
- StakedDegenerusStonk.sol:701 -- `ethValueOwed = (totalMoney * amount) / supplyBefore` (linear in `amount`)
- StakedDegenerusStonk.sol:691 -- `redemptionPeriodBurned + amount > redemptionPeriodSupplySnapshot / 2` (cap check is against global burned total)
- DegenerusGameAdvanceModule.sol:792 -- roll is per-period, not per-address

**Detail:** The 50% supply cap uses `redemptionPeriodBurned`, a GLOBAL accumulator (line 692), not a per-address one. Splitting across N addresses does not bypass this cap -- the sum of all burns still cannot exceed `redemptionPeriodSupplySnapshot / 2`. The proportional share formula is linear: burning X from one address yields `(totalMoney * X) / supplyBefore`, while burning X/2 from each of two addresses yields `(totalMoney * X/2) / supplyBefore` per address (approximately -- sequential burns see slightly different `totalMoney` and `supplyBefore` values due to prior burns reducing both, but the net effect is equivalent or slightly worse due to rounding). All addresses burning in the same period share the same roll value. Multiple claims in the same period all receive the same `period.roll`. No EV advantage exists from splitting, and the additional gas cost makes it strictly worse.

---

## 4. Bank-Run Scenario Analysis

### 4.1: Maximum Single-Period Burn

**Setup:** All holders decide to burn in the same period.

**Constraint:** The 50% supply cap limits total burns to `redemptionPeriodSupplySnapshot / 2` per period.

**Model:** N players each attempt to burn their full balance. The first burners succeed until `redemptionPeriodBurned` reaches `redemptionPeriodSupplySnapshot / 2`. All subsequent burns revert.

**Evidence:** StakedDegenerusStonk.sol:691 -- `if (redemptionPeriodBurned + amount > redemptionPeriodSupplySnapshot / 2) revert Insufficient();`

**Outcome:** At most 50% of the total supply can be burned in any single period. The cap acts as a circuit breaker, preventing a full bank run from draining more than half the supply at once.

### 4.2: Sequential Period Exhaustion (Multi-Period Bank Run)

**Setup:** Coordinated attack where players burn the maximum 50% each period.

**Model:**
```
Period 1: Supply = S,     burned = S/2,     remaining = S/2,     new snapshot = S/2
Period 2: Supply = S/2,   burned = S/4,     remaining = S/4,     new snapshot = S/4
Period 3: Supply = S/4,   burned = S/8,     remaining = S/8,     new snapshot = S/8
...
Period K: Supply = S/2^(K-1), burned = S/2^K, remaining = S/2^K
```

After K periods: `totalSupply = S / 2^K` (geometric decay).

**Key insight:** The supply asymptotically approaches zero but never reaches it. Each period's cap is half of the CURRENT supply at the start of that period (line 687: `redemptionPeriodSupplySnapshot = totalSupply`), not the original supply. The 50% cap ensures exponential decay, not linear depletion.

### 4.3: Multi-Period Cumulative Reservation vs Holdings

**Goal:** Prove that `pendingRedemptionEthValue < totalHoldings` at every step (the solvency invariant).

**Definitions:**
- P = `pendingRedemptionEthValue` (segregated ETH)
- H = `address(this).balance + steth.balanceOf(address(this)) + claimableWinnings()` (gross holdings)

**totalMoney computation** (StakedDegenerusStonk.sol:700):
```solidity
uint256 totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue;
```
So: `totalMoney = H - P` (unreserved holdings).

**Derivation for a single period with maximum 50% cap burn:**

At submit, for all burns in the period:
```
P_after = P_before + sum((totalMoney_i * amount_i) / supplyBefore_i)
```

Under worst case (50% cap fully consumed, ignoring sequential supply reduction for an upper bound):
```
sum(amount_i) = supplyBefore / 2    (cap constraint)

P_after <= P_before + (H - P_before) * (supplyBefore / 2) / supplyBefore
         = P_before + (H - P_before) / 2
         = P_before / 2 + H / 2
```

**Solvency check:** Is `P_after < H`?
```
P_after = P_before / 2 + H / 2
P_after < H  iff  P_before / 2 + H / 2 < H
              iff  P_before / 2 < H / 2
              iff  P_before < H
```

Since P starts at 0 (< H), and each step preserves the invariant `P < H`, the solvency invariant holds at every step by induction.

**Multi-period recursive formula (from Phase 44 contraction mapping):**
```
P_new = P_old / 2 + H / 2   (worst-case single-period)
```

This is a contraction mapping with fixed point P* = H (which is never reached). Starting from P_0 = 0:
```
P_1 = H/2
P_2 = H/4 + H/2 = 3H/4
P_3 = 3H/8 + H/2 = 7H/8
P_K = (1 - 1/2^K) * H
```

P approaches H from below but never reaches it. **The system is always solvent.**

Note: The Phase 44 contraction mapping `P_new = 0.125 * P_old + 0.875 * H` uses the tighter bound accounting for the roll resolution step (which adjusts P by the roll factor). The derivation above uses the simpler `P/2 + H/2` upper bound. Both confirm convergence: P < H at every step.

### 4.4: Claim Phase During Bank Run

**Setup:** After burns are resolved, all players claim. Some may get high rolls (up to 175%).

**ETH payout per claim:**
```solidity
uint256 ethPayout = (claim.ethValueOwed * roll) / 100;  // StakedDegenerusStonk.sol:585
```

For maximum roll (175):
```
ethPayout = 1.75 * ethValueOwed
```

**Question:** If ALL claimants get roll = 175, can the total payout exceed holdings?

**Worst-case calculation:**

From section 4.3, after a single period of maximum burns: `P <= H/2`.

But P represents the 100% base value. After resolution with roll = 175:
```
rolledEth = (P_base * 175) / 100 = 1.75 * P_base
```

The resolved `pendingRedemptionEthValue` becomes `1.75 * P_base` (the old base is removed and replaced with rolledEth at StakedDegenerusStonk.sol:551).

Total payout if all claimants claim:
```
sum(ethPayout_i) = sum((ethValueOwed_i * roll) / 100)
                 = (sum(ethValueOwed_i) * roll) / 100     [all share same roll]
                 = (P_base * 175) / 100
                 = 1.75 * P_base
```

Since `P_base <= H/2` (from the 50% cap constraint):
```
total_payout = 1.75 * P_base <= 1.75 * H/2 = 0.875 * H
```

**0.875 * H < H**. The contract has sufficient funds to pay ALL claimants even at the maximum possible roll.

**Law of large numbers:** With many claimants, the aggregate roll effect converges to E[roll/100] = 1.0, meaning total payouts converge to P_base (the reserved amount). The worst case above (all max rolls) is theoretical and becomes astronomically unlikely as the number of claimants grows.

**BURNIE during bank run:** BURNIE transitions to the coinflip system at resolution. The coinflip has its own solvency model (virtual stakes). A flip loss means zero BURNIE payout. The expected BURNIE outflow is 0.98425 * burnieOwed (from section 2), which is below the reserved amount. No BURNIE solvency risk during bank runs.

---

## 5. Summary

### Rational Actor Strategies

| Strategy | Verdict | Repeatable | EV |
|----------|---------|------------|-----|
| Timing Attack | UNPROFITABLE | N/A | 0 (rngLocked blocks burns during VRF resolution) |
| Cap Boundary Manipulation | NEUTRAL | per-period | Fair value (proportional share is linear) |
| Stale Accumulation | UNPROFITABLE | one-time | Negative (self-DoS via UnresolvedClaim revert) |
| Multi-Address Splitting | UNPROFITABLE | per-period | Same EV, higher gas cost |

### Economic Fairness

- **ETH payout:** EV-neutral (E[payout] = ethValueOwed, i.e. 100% of fair value)
- **BURNIE payout:** E[payout] = 0.98425 * burnieOwed (1.575% house edge from E[rewardPercent] = 96.85 < 100)
- **No repeatable positive-EV exploit identified**
- House edge on BURNIE is structural (from the rewardPercent distribution midpoint being below 100) and applies uniformly to all players

### Bank-Run Resilience

- **50% supply cap:** Circuit breaker limits single-period exposure to at most half of total supply (StakedDegenerusStonk.sol:691)
- **Multi-period:** Geometric decay `S/2^K` ensures supply never reaches zero
- **Solvency:** P < H maintained at every step (proven by induction: P_after = P_before/2 + H/2 < H when P_before < H)
- **Worst-case all-max-rolls:** 1.75 * P_base <= 1.75 * H/2 = 0.875 * H < H (system remains solvent)
- **Conclusion: System is bank-run resilient**
