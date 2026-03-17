# Warden Report: Economic Analyst
**Agent:** 3 of 3 (Economic Analyst)
**Date:** 2026-03-17
**Scope:** Degenerus Protocol -- 14 core contracts + 10 delegatecall modules
**Focus:** MEV, flash loans, pricing manipulation, solvency invariants, economic game theory
**Methodology:** Blind adversarial review per C4A warden methodology

---

## High-Severity Findings

_No high-severity findings identified. The protocol's core economic defenses -- proportional burn-redeem, onlyGame guards, and pull-pattern withdrawals -- prevent direct value extraction._

**Evidence:** Flash loan attacks are blocked by `onlyGame` on all deposit paths. Sandwich attacks on burns are order-independent (proportional formula). MEV extraction from VRF is limited by the RNG lock state machine. No profitable attack path with 1,000 ETH budget was identified.

---

## Medium-Severity Findings

_No medium-severity findings identified._

---

## [L-01] sDGNRS previewBurn and burn Produce Different ETH/stETH Splits Under Identical Conditions

### Description

`previewBurn()` and `burn()` in `StakedDegenerusStonk` use different logic for the ETH/stETH split. `previewBurn` adds `claimableEth` to `ethAvailable` before checking if `totalValueOwed <= ethAvailable`, while `burn` checks `totalValueOwed > ethBal` first, then claims winnings, then re-reads balances.

### Code References

`StakedDegenerusStonk.sol:454-476` (previewBurn):
```solidity
uint256 ethAvailable = ethBal + claimableEth;
if (totalValueOwed <= ethAvailable) {
    ethOut = totalValueOwed;
} else {
    ethOut = ethAvailable;
    stethOut = totalValueOwed - ethOut;
}
```

`StakedDegenerusStonk.sol:404-416` (burn):
```solidity
if (totalValueOwed > ethBal && claimableEth != 0) {
    game.claimWinnings(address(0));
    ethBal = address(this).balance;
    stethBal = steth.balanceOf(address(this));
}

if (totalValueOwed <= ethBal) {
    ethOut = totalValueOwed;
} else {
    ethOut = ethBal;
    stethOut = totalValueOwed - ethOut;
    if (stethOut > stethBal) revert Insufficient();
}
```

**Impact:** A user calling `previewBurn` may see `ethOut = X, stethOut = 0`, but calling `burn` may produce `ethOut = X - delta, stethOut = delta` if `ethBal` alone (before claiming winnings) is insufficient but `ethBal + claimableEth` is sufficient. The total value (`ethOut + stethOut`) is the same -- only the asset split differs.

**Economic analysis:** No value loss. The user receives the same total backing value. The split difference is cosmetic for automated systems that handle both ETH and stETH, but could cause slippage for a user who expected pure ETH.

**Severity rationale:** Low. Total value is identical. Asset split difference has no economic exploit path.

---

## [L-02] Deity Pass Quadratic Pricing Creates Predictable Early-Buyer Advantage

### Description

Deity pass pricing follows `24 + T(n)` ETH where `T(n) = n*(n+1)/2` and `n = passesSold`.

### Code References

`DegenerusGameWhaleModule.sol:153-154`:
```solidity
uint256 private constant DEITY_PASS_BASE = 24 ether;
```

The pricing formula (implemented in the whale module) produces:
- Pass 0: `24 + 0 = 24 ETH`
- Pass 1: `24 + 1 = 25 ETH`
- Pass 5: `24 + 15 = 39 ETH`
- Pass 10: `24 + 55 = 79 ETH`
- Pass 20: `24 + 210 = 234 ETH`
- Pass 31 (last): `24 + 496 = 520 ETH`

**COST vs PROFIT analysis with 1,000 ETH budget:**

A whale buying early deity passes could acquire passes 0-5 for `24 + 25 + 27 + 30 + 34 + 39 = 179 ETH` (6 passes).

On gameOver at levels 0-9, each pass is refunded 20 ETH (FIFO, budget-capped). 6 passes = 120 ETH refund.

Net loss: `179 - 120 = 59 ETH` (excluding any game rewards from deity pass activity bonuses).

However, deity passes also grant: 80% activity score bonus (`DegenerusGame.sol:216`: `DEITY_PASS_ACTIVITY_BONUS_BPS = 8000`), perpetual PASS_STREAK_FLOOR_POINTS and PASS_MINT_COUNT_FLOOR_POINTS, boon issuance rights, and affiliate DGNRS bonuses.

**Griefing vector:** A whale buying all 32 passes would spend approximately `sum(24 + T(n) for n=0..31) = 768 + sum(T(n) for n=0..31) = 768 + sum(n*(n+1)/2 for n=0..31)`. Computing: `sum(n*(n+1)/2) for n=0..31 = (1/2)*sum(n^2 + n) = (1/2)*(31*32*63/6 + 31*32/2) = (1/2)*(10416 + 496) = 5456`. Total: `768 + 5456 = 6224 ETH`. This exceeds the 1,000 ETH budget and is economically irrational for griefing.

**Severity rationale:** Low. The quadratic pricing is a known design feature. Early buyer advantage is intentional. No profitable manipulation at reasonable capital levels.

---

## [L-03] Vault Share Refill Mechanism Creates Dilution After Full Burn

### Description

When all DGVE or DGVB shares are burned, the vault mints `REFILL_SUPPLY` (1 trillion tokens) to the burner. This means the first depositor after a full burn gets disproportionate share of future deposits.

### Code References

`DegenerusVault.sol:352`:
```solidity
uint256 private constant REFILL_SUPPLY = 1_000_000_000_000 * 1e18;
```

The refill logic (in `burnEth` / `burnCoin` within DegenerusVault) checks if `totalSupply == 0` after burning, and if so, mints `REFILL_SUPPLY` to the burner.

**COST vs PROFIT analysis:**

To trigger refill, an attacker must:
1. Acquire ALL DGVE tokens (cost: market price of 1T tokens, initially held by CREATOR)
2. Burn all tokens (receives all ETH + stETH reserves)
3. Receive 1T refill tokens (owns 100% of empty vault)

The vault would then be empty. Future deposits go entirely to the attacker's share. But:
- Deposits are `onlyGame` (line 455: `modifier onlyGame`), so only game contract deposits accumulate
- The attacker already extracted all reserves in step 2
- New deposits restart from zero -- the attacker's 1T tokens give them 100% of new deposits, but they would have gotten 100% anyway since they're the only shareholder

**Severity rationale:** Low. The refill mechanism prevents division-by-zero but doesn't create a profitable attack. The attacker already owns all shares before refill triggers.

---

## BPS Verification Across Protocol

I systematically verified all BPS constants and their denominators:

### StakedDegenerusStonk.sol
| Constant | Value | Denominator | Usage | Verified |
|---|---|---|---|---|
| BPS_DENOM | 10,000 | - | `StakedDegenerusStonk.sol:152` | BASE |
| CREATOR_BPS | 2,000 | 10,000 | Creator allocation (20%) | YES |
| WHALE_POOL_BPS | 1,000 | 10,000 | Whale pool (10%) | YES |
| AFFILIATE_POOL_BPS | 3,500 | 10,000 | Affiliate pool (35%) | YES |
| LOOTBOX_POOL_BPS | 2,000 | 10,000 | Lootbox pool (20%) | YES |
| REWARD_POOL_BPS | 500 | 10,000 | Reward pool (5%) | YES |
| EARLYBIRD_POOL_BPS | 1,000 | 10,000 | Earlybird pool (10%) | YES |

**Sum check:** 2000 + 1000 + 3500 + 2000 + 500 + 1000 = 10,000 = 100%. **PASS.** Constructor at `StakedDegenerusStonk.sol:195-201` computes each allocation separately and adds dust to lootbox pool if total < INITIAL_SUPPLY.

### DegenerusGame.sol
| Constant | Value | Denominator | Usage | Verified |
|---|---|---|---|---|
| PURCHASE_TO_FUTURE_BPS | 1,000 | 10,000 | 10% to future pool | YES at line 407 |
| COINFLIP_BOUNTY_DGNRS_BPS | 20 | 10,000 | 0.2% of reward pool | YES at line 480 |
| AFFILIATE_DGNRS_DEITY_BONUS_BPS | 2,000 | 10,000 | 20% bonus | YES at line 1470 |
| DEITY_PASS_ACTIVITY_BONUS_BPS | 8,000 | 10,000 | 80% activity bonus | YES |

### DegenerusGameWhaleModule.sol (PPM scale)
| Constant | Value | Scale | Usage | Verified |
|---|---|---|---|---|
| DGNRS_WHALE_REWARD_PPM_SCALE | 1,000,000 | - | PPM base at line 88 | BASE |
| DGNRS_WHALE_MINTER_PPM | 10,000 | 1,000,000 | 1% whale pool | YES |
| DGNRS_AFFILIATE_DIRECT_WHALE_PPM | 1,000 | 1,000,000 | 0.1% affiliate pool | YES |
| DGNRS_AFFILIATE_UPLINE_WHALE_PPM | 200 | 1,000,000 | 0.02% affiliate pool | YES |
| DGNRS_AFFILIATE_DIRECT_DEITY_PPM | 5,000 | 1,000,000 | 0.5% affiliate pool | YES |
| DGNRS_AFFILIATE_UPLINE_DEITY_PPM | 1,000 | 1,000,000 | 0.1% affiliate pool | YES |

### DegenerusGameJackpotModule.sol
| Constant | Value | Denominator | Usage | Verified |
|---|---|---|---|---|
| DAILY_CURRENT_BPS_MIN | 600 | 10,000 | 6% daily min | YES |
| DAILY_CURRENT_BPS_MAX | 1,400 | 10,000 | 14% daily max | YES |
| FINAL_DAY_DGNRS_BPS | 100 | 10,000 | 1% reward pool | YES |
| DAILY_REWARD_JACKPOT_LOOTBOX_BPS | 5,000 | 10,000 | 50% to lootbox | YES |
| PURCHASE_REWARD_JACKPOT_LOOTBOX_BPS | 7,500 | 10,000 | 75% to lootbox | YES |

**Packed share verification:**
- `FINAL_DAY_SHARES_PACKED` at `DegenerusGameJackpotModule.sol:116-120`: [6000, 1333, 1333, 1334] = 10,000 BPS. **PASS.**
- `DAILY_JACKPOT_SHARES_PACKED` at `DegenerusGameJackpotModule.sol:124-125`: [2000, 2000, 2000, 2000] = 8,000 BPS (remaining 2,000 goes to entropy-selected solo bucket). **PASS.**

### BurnieCoinflip.sol
| Constant | Value | Denominator | Usage | Verified |
|---|---|---|---|---|
| COINFLIP_EXTRA_MIN_PERCENT | 78 | - | Min bonus % at line 121 | YES |
| COINFLIP_EXTRA_RANGE | 38 | - | Bonus range at line 122 | YES |
| COINFLIP_REWARD_MEAN_BPS | 9,685 | 10,000 | 96.85% mean payout | YES |
| AFKING_RECYCLE_BONUS_BPS | 160 | 10,000 | 1.6% recycling bonus | YES |

### DegenerusAdmin.sol
| Constant | Value | Context | Verified |
|---|---|---|---|
| PRICE_COIN_UNIT | 1000 ether | BURNIE conversion at line 344 | YES |
| LINK_ETH_MAX_STALE | 1 days | Feed staleness at line 350 | YES |

**Overall BPS audit result:** All BPS constants use consistent 10,000 denominators (or explicit 1,000,000 PPM where noted). No denominator mismatch found. No value creation or leakage from split calculations.

---

## sDGNRS Burn-Redeem Economic Analysis

### Formula

`StakedDegenerusStonk.sol:387-396`:
```solidity
uint256 ethBal = address(this).balance;
uint256 stethBal = steth.balanceOf(address(this));
uint256 claimableEth = _claimableWinnings();
uint256 totalMoney = ethBal + stethBal + claimableEth;
uint256 totalValueOwed = (totalMoney * amount) / supplyBefore;
```

The burn formula is: `payout = (totalReserves * burnAmount) / totalSupply`.

This is the standard proportional redemption formula. It is:
1. **Order-independent:** If A burns before B, A gets `(R * a) / S`. Then B gets `((R - R*a/S) * b) / (S - a) = (R * b * (S - a)) / (S * (S - a)) = (R * b) / S`. Same result regardless of order.
2. **Flash-loan-resistant:** A flash loan cannot profitably inflate reserves because all deposit paths require `onlyGame` authorization (`StakedDegenerusStonk.sol:282`). Flash-loaned ETH cannot be deposited.
3. **Sandwich-resistant:** Since burn payouts are order-independent (proven above), frontrunning a burn transaction has no effect on the backrunner's payout.

### Flash Loan DGNRS Attack

An attacker flash-loans DGNRS from a DEX:
1. Borrow N DGNRS
2. Burn N DGNRS -> receive proportional ETH/stETH/BURNIE
3. Cannot repay the DGNRS loan (tokens were burned)

The attack is self-defeating. Burning destroys the asset needed for repayment. **NOT PROFITABLE.**

### Accumulation Attack

An attacker accumulates DGNRS/sDGNRS over time to increase their share:
1. Buy sDGNRS via DGNRS on secondary markets
2. Wait for reserves to grow (stETH yield, game deposits)
3. Burn for larger proportional share

This is intended behavior -- holding sDGNRS entitles you to proportional backing growth. The accumulation earns exactly the pro-rata share of yield, not excess value. **NOT AN ATTACK -- INTENDED USAGE.**

### Forced ETH Donation Attack

An attacker sends X ETH via selfdestruct to sDGNRS:
- All holders' proportional share increases
- Attacker holding fraction `f` recovers `f * X`
- Net loss: `X * (1 - f)`

**COST vs PROFIT with 1,000 ETH budget, attacker holding 1% (f=0.01):**
- Donate 1,000 ETH
- Recover: 1,000 * 0.01 = 10 ETH
- Net loss: 990 ETH

**NOT PROFITABLE at any realistic ownership fraction.**

---

## ETH Accounting and Solvency

### ETH Entry Paths

1. **Ticket purchases:** `DegenerusGame.purchase()` via `DegenerusGameMintModule.sol` -- ETH flows to `msg.value` of game contract. Split: 90% to `nextPrizePool` (via `_processMintPayment` at `DegenerusGame.sol:975-1034`), 10% to `futurePrizePool` (`PURCHASE_TO_FUTURE_BPS = 1000` at line 199).

2. **Whale bundles:** `DegenerusGameWhaleModule.sol:185` -- 2.4-4 ETH per bundle. Split to next/future pool varies by level (30/70 at level 0, 5/95 at level 1+, per `DegenerusGameWhaleModule.sol:176-178`).

3. **Lazy passes:** `DegenerusGameWhaleModule.sol:109-110` -- 0.24 ETH (levels 0-2) or sum-of-10-level-prices. Split: 90% next, 10% future (`LAZY_PASS_TO_FUTURE_BPS = 1000` at line 124).

4. **Deity passes:** `DegenerusGameWhaleModule.sol:153-154` -- 24 + T(n) ETH. ETH flows to game, split to prize pools.

5. **Degenerette bets:** `DegenerusGameDegeneretteModule.sol` -- ETH bets flow to game contract. Pool cap limits payouts.

6. **Vault deposits:** `DegenerusVault.sol:455` -- `onlyGame`. Game sends ETH/stETH to vault during level transitions.

7. **sDGNRS deposits:** `StakedDegenerusStonk.sol:282` -- `onlyGame`. Game sends ETH to sDGNRS during distributions.

### ETH Exit Paths

1. **claimWinnings:** `DegenerusGame.sol:1397-1429` -- Pull-pattern. `claimablePool -= payout` before external call (CEI at line 1422).

2. **sDGNRS burn:** `StakedDegenerusStonk.sol:379-441` -- Proportional redemption. `balanceOf` and `totalSupply` updated before transfers.

3. **DGNRS burn:** `DegenerusStonk.sol:153-170` -- Burns DGNRS, then burns sDGNRS, then forwards ETH. CEI ordering maintained.

4. **Vault burnEth:** DegenerusVault -- Burns DGVE shares, sends proportional ETH+stETH. `onlyVaultOwner` or permissionless via burnEthFor with approval.

5. **GameOver final sweep:** `DegenerusGameGameOverModule.sol:171-189` -- 30-day delay. 50% to vault, 50% to sDGNRS.

### Solvency Invariant

**Core invariant:** `address(game).balance + steth.balanceOf(game) >= claimablePool`

This holds because:
- `claimablePool` is only incremented when ETH is available (jackpot distributions, which use `available = balance - claimablePool` at `DegenerusGameGameOverModule.sol:110`)
- `claimablePool` is decremented atomically with ETH/stETH transfers in `_claimWinningsInternal` (line 1422)
- The pull pattern prevents partial credit/debit
- stETH rebasing can only increase `steth.balanceOf()` (Lido rounds in favor of the protocol for transfers, strengthening the invariant per `StakedDegenerusStonk.sol:134-136` region of the contract's design)

**Backstop:** If `totalValueOwed > stethBal` in sDGNRS burn, the function reverts with `Insufficient()` at `StakedDegenerusStonk.sol:415`. This prevents over-withdrawal. The worst case is a reverted burn, never an overpayment.

---

## Affiliate Self-Referral Analysis

### Mechanism

`DegenerusAffiliate.sol` implements a 3-tier referral system:
- Player -> Affiliate (base reward)
- Affiliate -> Upline1 (20% of affiliate reward)
- Upline1 -> Upline2 (4% of affiliate reward)

### Self-Referral Attack

An attacker creates their own affiliate code and refers themselves:
1. Create code (attacker is affiliate)
2. Set attacker as own referrer
3. Purchase tickets with own code

**COST vs PROFIT with 1 ETH ticket purchase:**

Fresh ETH affiliate reward rate: 25% at levels 0-3, 20% at levels 4+ (per `DegenerusAffiliate.sol:17-18`).

At level 0: attacker pays 1 ETH for tickets. Affiliate reward = 0.25 * 1 = 0.25 ETH (as BURNIE flip credit, NOT ETH).

But the reward is paid as `creditFlip` -- BURNIE flip stake, not withdrawable ETH. To extract value, the attacker must win the coinflip (50% chance) and then claim. Expected value: `0.25 * 0.5 * ~0.97 (coinflip EV) = ~0.12 ETH equivalent in BURNIE`.

Net cost for 1 ETH of tickets: `1 ETH (paid) - ~0.12 ETH (BURNIE value recovered) = ~0.88 ETH`.

The "self-referral" gives a ~12% discount on tickets. But:
- The reward is in BURNIE (non-ETH), which must be burned or traded
- The coinflip has ~50% win rate, adding variance
- The kickback mechanism (0-25%) reduces the affiliate reward further when active
- Legitimate affiliates provide the same discount to referred players

**Circular farming (A refers B who refers A):**
Both A and B pay ticket costs. Each gets affiliate credit on the other's purchases. The economic effect is the same as self-referral -- both get a ~12% BURNIE discount on tickets. No amplification or value creation.

**Severity rationale:** Not a finding. Self-referral provides modest BURNIE rewards that are part of the intended incentive structure. No ETH extraction possible.

---

## Vault Share Math and Donation Attack

### First-Depositor Attack

Classical ERC4626 first-depositor attack: deposit 1 wei, then donate large amount, then frontrun next depositor.

In DegenerusVault, deposits are `onlyGame` (line 455). No user can directly deposit. The game contract controls all deposits, making first-depositor attacks impossible.

Additionally, shares are pre-minted (1T INITIAL_SUPPLY to CREATOR) at construction (`DegenerusVaultShare.sol:202-204`). There is no "first deposit" scenario -- shares exist from deployment.

### Donation Attack

An attacker sends ETH to the vault's `receive()` (line 466, open to anyone). This increases `address(vault).balance`, which increases `ethBal` in burn calculations.

Like the sDGNRS forced-ETH analysis: the donated ETH is distributed proportionally to all DGVE holders. Attacker loses `donation * (1 - share)`. **NOT PROFITABLE.**

### Share Inflation

DegenerusVaultShare uses unchecked mint at line 261-264:
```solidity
function vaultMint(address to, uint256 amount) external onlyVault {
    unchecked {
        totalSupply += amount;
        balanceOf[to] += amount;
    }
}
```

Only the vault can mint. The only mint path is the refill mechanism (1T tokens when supply hits zero). No external inflation vector exists.

---

## Cross-System Arbitrage Analysis

### Game vs DGNRS Arbitrage

A player can compare:
- Playing the game (tickets, jackpots, lootboxes) for ETH returns
- Buying sDGNRS/DGNRS on secondary market for backing exposure

The game has variable expected returns based on activity score (80-135% lootbox EV). DGNRS backing grows with game deposits (stETH yield + game distributions).

**No risk-free arbitrage exists** because:
- Game returns are variable and RNG-dependent
- DGNRS secondary market price may differ from backing value
- sDGNRS is soulbound (no secondary market)
- DGNRS secondary market price is set by supply/demand, not by an oracle

### Game vs Vault Arbitrage

DGVE holders receive vault deposits (game distributions). DGNRS holders receive sDGNRS backing growth. The two share classes have independent claims and independent markets.

**No arbitrage:** Different assets with different risk profiles. No on-chain mechanism guarantees parity.

### Degenerette vs Game Arbitrage

Degenerette bets use game ETH pool. Winnings come from the pool, losses go to the pool. The payout is capped by pool percentage (`DegenerusGameDegeneretteModule.sol` pool cap).

**No arbitrage:** Degenerette EV is bounded by payout table. High-activity players get better EV (up to ~99.9% ROI per the protocol docs), but this is an intended feature, not an exploit.

---

## [QA-01] Lootbox EV Depends on Activity Score Which Creates Information Asymmetry

### Description

Lootbox expected value scales with the player's activity score (80% base to 135% max for engaged players). This creates an information advantage for players who understand the scoring system -- they can maximize EV by maintaining streaks, quests, and affiliate activity before opening lootboxes.

### Code References

Activity score computation uses data from `DegenerusGameMintModule.sol` (level count, streak, quest data from `DegenerusQuests`, affiliate points, whale bundle status). The score feeds into lootbox reward multipliers in `DegenerusGameLootboxModule.sol`.

**Severity rationale:** QA. Intended design -- the protocol explicitly rewards engagement. Not a bug.

---

## [QA-02] DegenerusAffiliate Kickback Allows 0-25% Range Without Game-Level Enforcement

### Description

Affiliates can set `kickbackBps` from 0 to 2500 (0-25%) via the affiliate contract. There's no game-level minimum, so an affiliate can capture the entire reward with 0% kickback.

### Code References

`DegenerusAffiliate.sol:122-123`:
```solidity
error InvalidKickback();
```

The kickback is capped at 25% but has no minimum. An affiliate with 0% kickback gives nothing back to referred players.

**Severity rationale:** QA. Market-driven -- players choose their affiliate code and can select one with higher kickback.

---

## [QA-03] stETH Rebase Timing Creates Minimal Extractable Value on Burns

### Description

stETH rebases once daily. A burner who burns immediately after a positive rebase captures slightly more stETH value than one who burns immediately before.

**COST vs PROFIT analysis:**

Assume sDGNRS holds 1,000 stETH. Annual stETH yield ~2.5%. Daily rebase increment: `1000 * 0.025 / 365 = ~0.0685 stETH/day`.

A 10% holder burning immediately after rebase captures: `0.0685 * 0.10 = 0.00685 stETH = ~$2.40` (at $350/ETH).

This is the maximum single-burn timing advantage. Gas costs for the burn transaction likely exceed this amount.

**Severity rationale:** QA. The extractable value is negligible (<$3 for a 10% holder). Not economically significant.

---

## Confidence by Area

- **Storage Layout and Delegatecall Safety:** Medium
  - Secondary focus. Verified BPS constants and denominator consistency across all contracts. Did not independently verify storage slot layout.

- **ETH Accounting and Solvency:** High
  - All ETH entry and exit paths traced. Pull-pattern verified in `_claimWinningsInternal`. Solvency invariant `balance + steth >= claimablePool` verified. Game over settlement flow traced: deity refunds (FIFO, budget-capped), 10% decimator, 90% terminal jackpot, remainder to vault.

- **VRF / RNG Security:** Medium
  - Verified RNG lock state machine prevents outcome manipulation. MEV on VRF results limited by 18-hour timeout and post-callback state commit. Did not deeply analyze `_getHistoricalRngFallback` entropy quality.

- **Economic Attack Vectors:** High
  - Flash loan attacks analyzed and found blocked by `onlyGame`. Sandwich attacks on burns proven order-independent (algebraic proof). Deity pass pricing modeled with explicit cost/profit at 1,000 ETH budget. Sybil purchase influence bounded by ticket cost. Affiliate self-referral produces only BURNIE credits (not ETH). Vault donation attacks analyzed. Lootbox EV caps verified against activity score system.

- **Access Control:** Medium
  - Verified `onlyGame` guards on all deposit paths. Verified `onlyVaultOwner` on vault operations. Did not exhaustively enumerate all privileged functions.

- **Reentrancy and CEI:** Medium
  - Verified CEI in `_claimWinningsInternal`, `sDGNRS.burn()`, `DGNRS.burn()`. Did not independently trace every external call site.

- **Precision and Rounding:** High
  - All BPS constants verified with denominator consistency (10,000 for BPS, 1,000,000 for PPM). Packed jackpot shares verified to sum to 10,000. sDGNRS burn formula rounds down (favoring protocol). Constructor dust added to lootbox pool. stETH rounding strengthens the `balance >= claimablePool` invariant.

- **Temporal and Lifecycle Edge Cases:** Medium
  - stETH rebase timing analyzed (max ~$2.40 extractable for 10% holder). Game over settlement ordering reviewed. Did not deeply analyze multi-step interleaving.

- **EVM-Level Risks:** Low
  - Secondary focus. Forced ETH donation analyzed (net loss for attacker). Did not enumerate unchecked blocks.

- **Cross-Contract Composition:** Medium
  - Cross-system arbitrage analyzed (Game vs DGNRS vs Vault vs Degenerette). No risk-free arbitrage found. Proportional burn-redeem formula is the fundamental defense against composition attacks.

---

## Coverage Gaps

- **DegenerusGameMintModule.sol**: Reviewed constant references and integration points. Did not audit full activity score computation or ticket pricing curves (`PriceLookupLib`).
- **DegenerusGameJackpotModule.sol**: Reviewed constants and share distributions. Did not deeply audit winner selection algorithms or daily jackpot chunking logic.
- **DegenerusGameLootboxModule.sol**: Reviewed economic constants (boon budgets, utilization rates). Did not audit full lootbox opening EV calculation.
- **DegenerusGameEndgameModule.sol**: Reviewed BAF/Decimator pool percentages. Did not trace full settlement math.
- **BurnieCoin.sol**: Reviewed supply invariant and mint/burn paths. Did not audit quest integration or vault escrow math in detail.
- **BurnieCoinflip.sol**: Reviewed EV constants and architecture. Did not audit full coinflip resolution, auto-rebuy carry, or bounty system.
- **DegenerusGameDecimatorModule.sol**: Reviewed bucket system and claim logic. Did not model optimal Sybil strategy for bucket manipulation.
- **PriceLookupLib.sol**: Not reviewed (lookup tables for ticket pricing curves).
- **JackpotBucketLib.sol**: Not reviewed (bucket sizing and scaling functions).

---

## Limitations

- **Static analysis only.** No runtime execution, simulation, or formal verification performed. Economic models are based on source code formulas and manual calculation.
- **No market simulation.** Secondary market dynamics for DGNRS, DGVE, DGVB were not modeled. Price impact, liquidity depth, and MEV bot behavior are out of scope.
- **Simplified economic models.** Cost vs profit calculations use linear models. Multi-step strategies combining game actions, burns, and market operations were not exhaustively explored.
- **No stETH oracle integration verification.** stETH rebase behavior assumes standard Lido mechanics. Edge cases around stETH transfer rounding were assumed to follow documented behavior.
- **1,000 ETH baseline.** All attack models use 1,000 ETH as the attacker budget. Lower-capital griefing or higher-capital state attacks may have different economics.
- **Blind review.** This report was produced without access to prior internal audit findings.
