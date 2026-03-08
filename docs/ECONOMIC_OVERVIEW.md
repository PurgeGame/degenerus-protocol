# Degenerus Protocol - Economic Overview

**Source of Truth**: Solidity contracts in `contracts/`

---

## Philosophy

Degenerus is a high-variance, on-chain gamepiece game designed for risk-seeking players.

| Principle | Meaning |
|-----------|---------|
| **Non-upgradeable** | Core gameplay is immutable; no upgrade key for rules |
| **Verifiably fair** | Chainlink VRF for all randomness, auditable on-chain |
| **No house wallet** | ETH stays in on-chain pots, paid out only via game rules |
| **Anti-nit** | Variance deters bots/whales seeking riskless extraction |

---

## Game Loop

### Level Cycle

1. **Purchase Phase**: Buy gamepieces with ETH or BURNIE. Funding target must be met before burn phase opens. Purchases during burn phase apply to the next level.
2. **Burn Phase**: Burn gamepieces to reduce trait counts. First trait to zero (or 1 on special levels) triggers extermination.
3. **Settlement**: Exterminator wins prize slice + Trophy. Level advances.
4. **Timeout**: If no extermination after 5 daily jackpots, level auto-advances.

### Gamepieces & Traits

- Each gamepiece has 4 traits (one per quadrant), deterministically generated via VRF
- Burning decrements trait counts, earns BURNIE credits, enters jackpots
- **Tickets**: Pay priceWei/400 per unit for trait ticket + level jackpot entry

### Pricing

Prices follow intro tiers for levels 0-9, then a 100-level cycle from level 10 onward:

| Level Range | Gamepiece Price | Ticket Price (per 400 units) |
|-------------|-----------------|------------------------------|
| 0-4 | 0.01 ETH | 0.01 ETH |
| 5-9 | 0.02 ETH | 0.02 ETH |
| 10-29 | 0.04 ETH | 0.04 ETH |
| 30-59 | 0.08 ETH | 0.08 ETH |
| 60-89 | 0.12 ETH | 0.12 ETH |
| 90-99 | 0.16 ETH | 0.16 ETH |
| x00 (100,200..) | 0.24 ETH | 0.24 ETH |
| x01-x29 | 0.04 ETH | 0.04 ETH |
| x30-x59 | 0.08 ETH | 0.08 ETH |
| x60-x89 | 0.12 ETH | 0.12 ETH |
| x90-x99 | 0.16 ETH | 0.16 ETH |

1 full ticket = quantity 400 = costs priceWei. Ticket cost formula: `(priceWei * quantity) / 400`

**Code Reference**: `PriceLookupLib.priceForLevel()` in `contracts/libraries/PriceLookupLib.sol`

---

## The Core Mechanism: Future Tickets Create Present Pressure

Most purchases give tickets for levels that haven't happened yet. Those tickets are worthless until the game reaches those levels. Every future ticket holder is economically compelled to ensure every prior level completes.

### Where Future Tickets Come From

| Purchase Type | Tickets For | Who Buys |
|---------------|-------------|----------|
| **Lootbox** | Current level + 0-5 ahead (95%), +5-50 (5%) | Everyone |
| **Lazy Pass** | Next 10 levels | Regular players |
| **Whale Bundle** | Next 100 levels | Whales |
| **Deity Pass** | Next 100 levels + auto-refresh | Long-term players |

### The Pressure Cascade

At any given level, multiple groups need that level to complete:

| Actor | Why They Act | What They Do |
|-------|--------------|--------------|
| **Lootbox holders** | Tickets for L+1 to L+5 are worthless until current level completes | Buy more, call `advanceGame()` |
| **Lazy pass holders** | Tickets for next 10 levels need current level to finish | Same |
| **Whale bundle holders** | Tickets for next 100 levels need current level to finish | Will pay gas to advance |
| **Gamblers** | Want action NOW | Create volume, burn traits |
| **Exterminators** | New level = new jackpot | Push for fast resolution |

### The Compounding Effect

Each level that passes increases pressure on the next level:

- Every new bundle/pass purchase = more people with future tickets
- More future ticket holders = more people who need the next level
- More pressure = more certainty the level will complete
- More certainty = more people willing to buy future tickets
- Positive feedback loop

---

## Purchase Types

### Gamepieces (ETH or BURNIE)

Main entry point: `DegenerusGame.purchase()`

- Buy gamepieces + tickets + lootboxes in one transaction
- ETH purchases credit coinflip stakes
- BURNIE purchases burn BURNIE (deflationary, no ETH added to pools)
- Claimable rebuy bonus for spending all claimable winnings
- All purchase types earn affiliate rewards (lootboxes at 50% rate)
- Payment modes: ETH, claimable winnings, or combined

### Whale Bundle (100-level)

Available at levels 0-3 or x49/x99 boundaries, or any level with a whale boon.

- **Price**: 2.4 ETH (levels 0-3), 4 ETH (x49/x99)
- **Boon discount**: 10%, 25%, or 50% off standard price
- **Tickets**: 40/level for bonus levels (through level 10), 2/level for the rest
- **Lootbox**: 20% of price (presale), 10% (post-presale)
- **Quantity**: 1-100 bundles per transaction

Fund split: Pre-game 30% next / 70% future, Post-game 5% next / 95% future.

### Lazy Pass (10-level)

Available at levels 0-3 or x9 (9, 19, 29...), or with a valid lazy pass boon.

- **Price**: Sum of 10 per-level ticket prices, or flat 0.24 ETH at levels 0-2
- **Boon discount**: 10%, 15%, or 25% off
- **Tickets**: 4 per level across 10 levels
- **Lootbox**: 20% of price (presale), 10% (post-presale)
- **Required for AfKing mode activation**

Fund split: 10% future pool, 90% next pool.

### Deity Pass

Available at any time. One per player, max 24 total (one per non-dice symbol, IDs 0-23).

- **Price**: 24 + T(n) ETH where T(n) = n*(n+1)/2, n = passes sold so far
- **First pass**: 24 ETH, last (24th): 324 ETH
- **Boon discount**: Tier 1 = 10%, Tier 2 = 25%, Tier 3 = 50%
- **Tickets**: Same as whale bundle (40/level bonus + 2/level standard)
- **Transfer cost**: 5 ETH worth of BURNIE
- **Lootbox**: 20% of price (presale), 10% (post-presale)

Fund split: Pre-game 30% next / 70% future, Post-game 5% next / 95% future.

**Permanent perks**: AdvanceGame gate bypass, activity bonus, daily deity boons, AfKing edge, auto-refresh tickets every 100 levels.

---

## BURNIE Token

### Creation

BURNIE is **not minted on purchase**:
1. ETH purchases credit coinflip stakes
2. Stakes enter daily coinflip (~50% win rate via VRF)
3. Winners claim minted BURNIE; losers forfeit stakes

**Mean reward**: 96.85% of stake. Two modes: equal odds (~50/50, -0.25% EV) and triple odds (1/3 win at 3x, +3% EV).

### Burns

- Gamepiece/ticket purchases with BURNIE (primary sink)
- Marketplace fees
- Deity pass transfer cost
- Coinflip entry burns
- Decimator jackpot entries

---

## Loot Boxes

Daily purchase opportunity with randomized rewards. Purchase any amount (minimum enforced), one box per day per player.

### Purchase Split

**Normal mode**: 90% future pool, 10% next pool

**Presale mode**: 40% future pool, 40% next pool, 20% vault

### Reward Roll

| Path | Weight | Outcome |
|------|--------|---------|
| Tickets | 55% | Ticket budget with variance tiers (0.45x-4.6x) |
| BURNIE | 45% | Large BURNIE variance; presale adds +62% bonus |

Plus 10% of EV allocated to boon/pass budget.

### Activity Score EV Multiplier

- **0% activity**: 80% EV
- **60% activity** (neutral): 100% EV
- **Max activity**: 135% EV
- **Cap**: 10 ETH of EV benefit per account per level

### Target Level Roll

- 95%: current level + 0-5
- 5%: current level + 5-50
- Reward value scales with target level's price

---

## Jackpots

| Type | Trigger | Source |
|------|---------|--------|
| **Daily** | Each day during burn phase (max 5/level) | Prize pool: days 1-4 random 6-14%, day 5 remaining 100% |
| **Exterminator** | First burn-phase jackpot after extermination | Current prize pool slice |
| **Level** | End of purchase phase | Weighted by tickets, solo bucket (60%) + quad buckets |
| **BAF** | Every 10 levels | Reward pool slice |
| **Decimator** | Periodic windows | BURNIE burns, bucketed by streak |

---

## Affiliates

Built-in referral marketing. Rewards delivered as coinflip stake (BURNIE creation pathway).

| Payment Type | Levels 1-3 | Levels 4+ |
|--------------|-----------|-----------|
| Fresh ETH | 2.5% | 2% |
| Recycled (claimable) | 0.5% | 0.5% |
| Lootbox | 50% of gamepiece rate | 50% of gamepiece rate |

3-tier referral: Direct affiliate (base) -> Upline 1 (20% of direct) -> Upline 2 (50% of upline 1). Rakeback: 0-25% returned to referred player.

---

## Vault

Long-term reserve with two share classes:

| Share | Claims |
|-------|--------|
| DGVE | ETH/stETH (proportional burn) |
| DGVB | BURNIE (proportional burn) |

Receives: 20% of presale lootbox purchases, game-over sweep.

---

## AfKing Mode

Auto-play system requiring: auto-rebuy enabled, auto-flip enabled, active lazy pass, initial 2 ETH + 50k BURNIE balance.

- **Activity bonus**: +2% per consecutive level, max +50% (at 25 levels)
- **Recycle bonus**: 1.6% base + deity edge (2 BPS per half-level, max 300 BPS)
- Deactivation resets level streak to 0

---

## Game Over

| Condition | Timeout |
|-----------|---------|
| Pre-game (level 0) | 912 days (~2.5 years) |
| Post-game (level > 0) | 365 days (1 year) |

When triggered: contract sweeps all ETH + stETH into vault. BAF pool gets 50%, decimator pool gets the remainder.

Deity pass holders at levels 1-9 receive 20 ETH refund per pass purchased. At level 0, full refund.

---

## Time Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| Pre-game timeout | 912 days | Level 0 inactivity |
| Post-game timeout | 365 days | Level 1+ inactivity |
| VRF retry | 18 hours | RNG request retry |
| Emergency VRF fallback | 3 days | Force VRF rotation |
| Final sweep | 30 days | Post-game-over cleanup |
| Daily reset | 22:57 UTC | Coinflip/jackpot day boundary |
| Presale cap | 200 ETH | Auto-ends lootbox presale |

---

## Solvency & Security

### Why Payouts Are Solvent

- ETH only credited when already inside the system
- Tracked in separate pools with closed-loop accounting
- stETH fallback if raw ETH is temporarily short
- Invariant: `totalBal >= obligations` checked every level

### Admin Capabilities

| Can Do | Cannot Do |
|--------|-----------|
| VRF subscription upkeep | Withdraw game pots |
| Emergency VRF recovery (3-day stall) | Redirect player winnings |
| Stake excess ETH to Lido stETH | Change gameplay rules |
| Swap own ETH for contract stETH (1:1) | Extract funds |

---

## Incentive Alignment

| Actor | Wants | Risk |
|-------|-------|------|
| Gamepiece buyer | Exterminate for prize + Trophy | Worthless if not burned |
| Coinflip player | Win daily flip | ~50% loss rate |
| Affiliate | Active referrals | Revenue depends on network |
| Ticket buyer | Win level jackpot | Sunk cost, variance |
| Vault holder | Long-term accumulation | Illiquid, game-dependent |
| Bundle holder | Game to reach 100+ levels | Locked until freeze expires |
| Deity pass holder | Perpetual ticket income | High upfront cost |

**Core principle**: Everyone is incentivized to keep the game progressing. No one benefits from game stalling.
