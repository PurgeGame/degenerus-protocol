# Jackpots & Affiliates

**Source of Truth**: `DegenerusGameJackpotModule.sol`, `DegenerusGameDecimatorModule.sol`, `DegenerusAffiliate.sol`, `DegenerusGameLootboxModule.sol`

---

## Jackpot System

### Daily Jackpot

**When**: Every day during burn phase, up to **5 jackpots per level**

**Pool Source**: `currentPrizePool`

**Daily Payout Schedule**:

| Day | Payout |
|-----|--------|
| Days 1-4 | Random 6%-14% of remaining currentPrizePool |
| Day 5 | 100% of remaining currentPrizePool |

After 5 daily jackpots without extermination, the level auto-advances.

**Winner Distribution**:
- **Solo bucket** (1 winner from entropy-selected trait): 20%
- **4 trait buckets** (distributed among trait ticket holders): 20% each

**Winner Caps**:
- Max winners per trait bucket: 250
- Max total winners per jackpot: 300
- Max daily ETH winners: 321
- Max daily BURNIE winners: 50
- Max lootbox winners: 100

### Daily BURNIE Jackpot

Runs every day alongside the ETH jackpot in a separate transaction.

**Budget**: 0.5% of `lastPrizePool` converted to BURNIE equivalent

**Distribution** (fixed, no variance):

| Pool | Share | Max Winners |
|------|-------|-------------|
| Current level tickets | 50% | 50 |
| Near future (levels +1 to +5) | 25% | 25 draws |
| Far future (levels +6 to +50) | 25% | 25 draws |

Future draws randomly select a level within range. If the selected level has no tickets, that BURNIE is not paid (no redistribution).

### Level Jackpot

**Trigger**: End of purchase phase (funding target met + last purchase day)

**Pool**: Accumulated `currentPrizePool`

**Distribution**:
- **Solo bucket**: 60% (1 winner from random trait)
- **Quad buckets**: ~13.33% each (4 trait-based distributions)

**Ticket jackpot portion**: 20% of ETH pool converts to tickets

**Critical window** (`rngLockedFlag && lastPurchaseDay`):
- Gamepiece purchases BLOCKED (prevents jackpot sniping)
- Ticket purchases BLOCKED (universal processing gate)
- Lootbox purchases ALLOWED (separate RNG)

### Exterminator Payout

**Trigger**: First burn-phase jackpot after a trait is exterminated

**Recipient**: The exterminator (player who burned the final trait)

**Reward**: Prize pool slice + Trophy NFT

### BAF Jackpot (Bonus Activity Factor)

**Trigger**: Every 10 levels

**Source**: Reward pool slice

**Distribution**: Based on player activity scores (flip activity, timing, consistency)

**Game Over Split**:
- BAF pool gets 50% of available funds
- Decimator pool gets remainder

### Decimator Jackpot

**Trigger**: Periodic windows (every x levels)

**Entry**: Players burn BURNIE into subbuckets

**Resolution**: VRF selects winning subbucket; BURNIE distributed pro-rata among bucket entries

**Anti-gaming**: Hedging across all subbuckets provides no mathematical edge (just reduces variance)

---

## Lootbox System

### Purchase Mechanics

- Any amount (minimum enforced), ETH only (not claimable or BURNIE)
- One lootbox per day per player (can add to existing)
- Two modes: Normal and Presale

### Purchase Split

**Normal Mode** (post-presale):
- 90% -> `futurePrizePool`
- 10% -> `nextPrizePool`

**Presale Mode** (`lootboxPresaleActive == true`):
- 40% -> `futurePrizePool`
- 40% -> `nextPrizePool`
- 20% -> Vault (immediate transfer)

Presale ends automatically at **200 ETH** cumulative mint-only lootbox volume.

### Reward Roll

Two main paths:

| Path | Weight | Outcome |
|------|--------|---------|
| Tickets | 55% | Ticket budget with variance tiers |
| BURNIE | 45% | Large BURNIE variance |

Plus: 10% of lootbox EV allocated to boon/pass budget (separate from main roll).

### Ticket Variance Tiers (55% path)

| Tier | Probability | Multiplier |
|------|-------------|-----------|
| 1 (Jackpot) | 1% | 4.6x |
| 2 (High) | 4% | 2.3x |
| 3 (Good) | 20% | 1.1x |
| 4 (Standard) | 45% | 0.651x |
| 5 (Low) | 30% | 0.45x |

### BURNIE Path (45%)

Presale adds **+62% bonus** to BURNIE rewards on this path.

### DGNRS Pool Allocation (from lootbox)

| Tier | Probability | Pool Share per ETH |
|------|-------------|--------------------|
| Small | ~79.5% | 0.001% |
| Medium | ~15% | 0.039% |
| Large | ~5% | 0.08% |
| Mega | ~0.5% | 0.8% |

### WWXRP Prize

Fixed **1 WWXRP token** (gag prize) on certain rolls.

### Activity Score EV Multiplier

Applied to lootbox amount at opening:

| Activity Score | EV Multiplier |
|----------------|---------------|
| 0% (new player) | 80% |
| 60% (neutral) | 100% |
| 260%+ (max) | 135% |

**Benefit cap**: 10 ETH of EV benefit per account per level.

Presale does **not** override the EV curve; it only adds +62% to BURNIE path.

### Target Level Roll

| Probability | Target |
|-------------|--------|
| 95% | Current level + 0-5 |
| 5% | Current level + 5-50 |

Reward value scales with **target level's price**, not purchase level. If target level is current or past, tickets convert to BURNIE equivalent.

### Lootbox Boon Roll (Separate)

- **Chance**: 2% per ETH of lootbox amount (base amount before EV scaling)
- **Pool/weights**: Same as deity boons
- **Limit**: One boon max per lootbox
- **Refresh**: If you already have an active boon category, lootbox boons refresh/upgrade that category

### Large Purchase Split

Purchases > 0.5 ETH split into two independent rolls for additional variance.

---

## Affiliate System

### How It Works

1. Create affiliate code with chosen rakeback percentage
2. Referral purchases credit you + up to 2 uplines
3. Rewards delivered as **flip credit** (coinflip stake -> BURNIE pathway)

### Affiliate Reward Rates

| Payment Type | Levels 1-3 | Levels 4+ |
|--------------|-----------|-----------|
| Fresh ETH | 2.5% | 2% |
| Recycled (claimable) ETH | 0.5% | 0.5% |
| Lootbox | 50% of gamepiece rate | 50% of gamepiece rate |

### Referral Chain

| Tier | Recipient | Share |
|------|-----------|-------|
| Direct affiliate | Referrer | Base reward |
| Upline 1 | Referrer's referrer | 20% of direct reward |
| Upline 2 | Upline 1's referrer | 50% of upline 1 (= 10% of direct) |

### Rakeback

- Configurable 0-25% of affiliate reward returned to referred player
- Set by the affiliate at code creation time

### DGNRS Affiliate Rewards (Whale/Deity purchases)

Separate from ETH affiliate rewards, paid from DGNRS pools:

| Purchase Type | Direct Affiliate | Upline |
|---------------|-----------------|--------|
| Whale Bundle | 0.1% of affiliate pool | 0.02% |
| Deity Pass | 0.5% of affiliate pool | 0.1% |

---

## Ticket Processing & RNG Security

### RNG Locking Mechanism

- Tickets lock to the **first RNG after purchase** (prevents timing exploits)
- **Universal ticket processing gate**: all new RNG requests blocked until queue clear
- Processing in batches (500 tickets per transaction)
- **500 BURNIE bounty** (as flip credit) to processors when work incomplete

### Purchase Gating

| Item | When Blocked |
|------|--------------|
| Tickets | During ticket processing (`rngLockedFlag`) |
| Gamepieces | During `rngLockedFlag && lastPurchaseDay` (level jackpot window) |
| Lootboxes | Never blocked (separate RNG) |

Typical block duration: 1-3 blocks (~12-36 seconds)

### Two Independent RNG Streams

**Daily/Jackpot RNG** (`rngWordCurrent`):
- Used for: daily jackpots, level jackpots, ticket trait assignment
- Requested via: `advanceGame()` only

**Lootbox RNG** (per-index):
- Used for: lootbox opening
- Requested via: threshold trigger or manual BURNIE burn

Both streams gated by ticket processing completion.

---

## Game Over Distribution

When the game enters GAMEOVER (after timeout):

1. Contract sweeps all ETH + stETH into vault
2. BAF pool receives 50% of available funds
3. Decimator pool receives remainder
4. Deity pass holders at levels 1-9: 20 ETH refund per pass purchased
5. Deity pass holders at level 0: full purchase price refund

### Timeout Constants

| Condition | Timeout |
|-----------|---------|
| Level 0 (pre-game) | 912 days (~2.5 years) |
| Level 1+ (post-game) | 365 days (1 year) |
| Final sweep after gameover | 30 days |
