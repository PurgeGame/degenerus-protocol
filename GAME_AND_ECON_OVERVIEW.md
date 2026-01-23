# Degenerus: Game & Economy Overview

## Philosophy

Degenerus is a high-variance, on-chain NFT game designed for risk-seeking players.

| Principle | Meaning |
|-----------|---------|
| **Non-upgradeable** | Core gameplay is immutable; no "upgrade key" for rules |
| **Verifiably fair** | Chainlink VRF for all randomness, auditable on-chain |
| **No house wallet** | ETH stays in on-chain pots, paid out only via game rules |
| **Anti-nit** | Variance deters bots/whales seeking riskless extraction |

---

## Game Loop

### Level Cycle

1. **Purchase Phase**: Buy gamepieces with ETH (or BURNIE; BURNIE burns and does not add ETH to pots). Funding target must be met before burn phase opens. Purchases can still occur outside purchase phase; in burn phase they apply to the next level.
2. **Burn Phase**: Burn gamepieces to reduce trait counts. First trait to zero (or 1 on L%10=7) = "Exterminated."
3. **Settlement**: Exterminator wins prize slice + Trophy. Level advances.
4. **Timeout**: If no extermination after ~10 daily jackpots, level auto-advances.

### Gamepieces & Traits

- Each gamepiece has 4 traits (one per quadrant), deterministically generated
- Burning decrements trait counts, earns BURNIE credits, enters jackpots
- **MAPs**: Pay 1/4 gamepiece price for 1 trait ticket + level jackpot entry (ETH/claimable anytime RNG is unlocked; BURNIE only on last purchase day)

### Pricing

Prices increase through 100-level cycles, then reset.

### Purchases

**Main Entry Point: `DegenerusGame.purchase()`**

All ETH/claimable purchases go through one unified function:
- **Gamepieces + MAPs + Loot Boxes**: Buy any combination in one transaction
- **Claimable Rebuy Bonus**: Spending all claimable winnings earns a 10% bonus (minimum 3 gamepiece-equivalents)
- **Affiliate Support**: All purchase types earn affiliate rewards (loot boxes at 50% rate)
- **Payment Modes**: Supports ETH, claimable winnings, or combined payment

**BURNIE Purchases**: Use `DegenerusGamepieces.purchase()` for buying with BURNIE tokens

---

## BURNIE Token

### Creation

BURNIE is **not minted on purchase**:
1. ETH purchases credit coinflip stakes
2. Stakes enter daily coinflip (~50% win rate via VRF)
3. Winners claim minted BURNIE; losers forfeit stakes

### Burns

- Gamepiece/MAP purchases with BURNIE (primary sink)
- Marketplace fees
- Coinflip entry burns
- Decimator jackpot entries
- RNG nudges

### Coinflip

- ~50% win rate, variable payout multiplier
- Last purchase day adds a +6% bonus to the payout roll
- Winnings are claimable after the day's flip resolves; unclaimed winnings expire after 30 days
- Recycling bonus for rolling winnings forward
- Bounty for setting all-time high stakes
- Feeds the BAF jackpot (fires every 10 levels)

---

## ETH Flow

```
ETH In                          On-Chain Buckets              Payouts
─────────────────────────────────────────────────────────────────────
Gamepiece/MAP buys (ETH)   →    Prize pools + jackpots   →   Winners
Loot box purchases         →    Future/next/reward pools →   MAP tickets/BURNIE
Direct ETH inflows         →    Reward pool              →   Special jackpots
                           →    Vault transfers          →   Share holders
```

**stETH**: Some ETH can be staked to Lido. Yield increases system backing and can expand reward budgets.

Some jackpots pay a MAP-ticket slice. The ETH value of those MAP rewards is routed into `nextPrizePool`,
so ticket rewards recycle ETH into future prize pools.

---

## Jackpots

| Type | Trigger | Source |
|------|---------|--------|
| **Daily** | Each day during burn phase | Prize pool + reward slice |
| **Extermination** | Trait hits zero | Prize pool |
| **Carryover** | After extermination | Reward pool (next-level tickets) |
| **Level** | End of purchase phase | Weighted by MAPs |
| **BAF** | Every 10 levels | Reward pool slice |
| **Decimator** | Periodic windows | BURNIE burns, bucketed by streak |

Note: jackpot payouts can convert a portion of ETH into MAP tickets; the MAP cost is added to `nextPrizePool`.

### Early Entry Advantage

- Daily jackpots draw winners for **both** current and next level
- Early MAPs get next-level tickets before burn phase opens
- Early burners hit more jackpot draws for the same tickets

---

## Game Over

If inactive for ~1 year (or ~2.5 years if never started):
1. Game enters GAMEOVER
2. Contract sweeps all ETH + stETH into the vault

---

## Loot Boxes

Daily purchase opportunity with randomized rewards.

### Mechanics

- Purchase any amount (minimum 0.01 ETH) - flexible to use exact claimable balances
- One loot box per day per player (can add to existing)
- Two modes: Normal and Presale

### Normal Mode (60% tickets/gamepieces, 40% BURNIE)

- **ETH Split**: 60% future levels, 20% next prize pool, 20% reward pool
- **Rewards**: d20 roll determines payout type
  - 60% probability (rolls 0-11): MAP tickets OR gamepiece for future levels (116.67% of ETH value)
    - Within this outcome: 1/6 chance for gamepiece (if budget allows), 5/6 chance for tickets
  - 20% probability (rolls 12-15): Small BURNIE consolation (5% of ETH value)
  - 20% probability (rolls 16-19): Large BURNIE jackpot (195% of ETH value)
  - **Total EV: 110%** (70% + 1% + 39%)

### Presale Mode (60% tickets/gamepieces, 40% BURNIE with 2× multiplier)

- **ETH Split**: 10% future levels, 10% next prize pool, 30% vault, 50% reward pool
- **Rewards**: Same d20 roll mechanic with 2× BURNIE multiplier
  - 60% probability: MAP tickets OR gamepiece for future levels (116.67% of ETH value)
    - Within this outcome: 1/6 chance for gamepiece (if budget allows), 5/6 chance for tickets
  - 20% probability: Small BURNIE consolation (10% of ETH value, 2× multiplier)
  - 20% probability: Large BURNIE jackpot (390% of ETH value, 2× multiplier)
  - **Total EV: 150%** (70% + 2% + 78%)
- **Bonus**: Presale purchases get extra coinflip multipliers

### Opening

- Requires VRF random word (after daily reset)
- Large purchases (>1 ETH) split into two independent rolls
- **Target Level**: Randomly rolled at opening time (current level + 0-5)
  - Box value scales with level price at opening, not purchase
  - Encourages strategic timing for maximum reward value
- **Tickets**: All tickets/gamepieces awarded for the rolled target level
  - Ticket quantity calculated using the rolled level's price
  - If budget < 1 MAP ticket: Fallback converts to BURNIE at 80% value (20% penalty)
- **Gamepiece**: Awarded for target level (only if budget >= 4× MAP price)
  - ~10% overall chance (60% ticket outcome × 1/6)
  - Replaces ~4 MAP tickets with 1 full gamepiece

---

## Affiliates

Built-in marketing: the protocol rewards people who bring new participants.

### How It Works

- Create affiliate code with chosen rakeback %
- Referral buys credit you + up to 2 uplines
- Rewards delivered as **flip credit** (coinflip stake)
- System can auto-buy MAPs for affiliates during purchase phase

### Affiliate Rewards by Payment Method

**ETH Purchases:**
- Early levels (≤3) or purchase phase: 0.25 BURNIE per gamepiece-equivalent
- Mid levels (4-40) burn phase: 0.1 BURNIE per gamepiece-equivalent
- Late levels (>40): 0.05-0.30 BURNIE depending on phase

**Claimable Purchases:**
- Flat rate: 0.05 BURNIE per gamepiece-equivalent (1/20th of a mint)
- Lower rate incentivizes fresh ETH while still rewarding volume

**Combined Purchases:**
- Pro-rated between ETH and claimable rates based on payment split

**Loot Box Purchases:**
- 50% of normal gamepiece affiliate rate
- Calculated as lootBoxAmount ÷ price × base rate × 0.5

### Why It's Effective

- Earnings tied to volume driven, not single jackpot wins
- Late entrants refill pots that pay earlier participants
- Affiliates have incentive to keep game progressing

---

## Vault

Long-term reserve with three share classes:

| Share | Claims |
|-------|--------|
| DGVB | BURNIE |
| DGVE | ETH/stETH |
| DGVA | 20% share of ETH/stETH + BURNIE |

Receives: vault share of game inflows and final sweep.

Note: DGVA claims 20% of combined ETH+stETH deposits and 20% of BURNIE allowances; stETH rebase yield accrues to DGVE only.

---

## Marketplace

Non-custodial gamepiece trading. Fees (listing + trade %) are burned as BURNIE.

---

## Solvency & Security

### Why Payouts Are Solvent

- ETH only credited when already inside the system
- Tracked in separate pots with closed-loop accounting
- stETH fallback if raw ETH is temporarily short

### Admin Capabilities

| Can Do | Cannot Do |
|--------|-----------|
| VRF subscription upkeep | Withdraw game pots |
| Emergency VRF recovery (3-day stall) | Redirect player winnings |
| One-time wiring (`wireAll`) | Change gameplay rules |

---

## Incentive Alignment

| Actor | Wants | Risk |
|-------|-------|------|
| Gamepiece Buyer | Exterminate for prize + Trophy | Worthless if not burned |
| Coinflip Player | Win daily flip | ~50% total loss |
| Affiliate | Active referrals | Revenue depends on network |
| MAP Buyer | Win level jackpot | Sunk cost, variance |
| Vault Holder | Long-term accumulation | Illiquid, game-dependent |

**Core principle**: Everyone is incentivized to keep the game progressing.
