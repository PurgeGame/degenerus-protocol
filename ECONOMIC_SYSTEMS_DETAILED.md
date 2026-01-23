# Degenerus: Detailed Economic Systems & Interactions

A comprehensive technical overview of all economic systems, ETH/BURNIE flows, and pool interactions.

---

## Table of Contents

1. [Core Economic Principles](#core-economic-principles)
2. [ETH Pool Architecture](#eth-pool-architecture)
3. [Purchase Flow](#purchase-flow)
4. [Jackpot Distribution System](#jackpot-distribution-system)
5. [Level Transition Economics](#level-transition-economics)
6. [BURNIE Token Economics](#burnie-token-economics)
7. [Loot Box System](#loot-box-system)
8. [Vault System](#vault-system)
9. [Solvency Mechanism](#solvency-mechanism)
10. [Complete ETH Flow Diagram](#complete-eth-flow-diagram)

---

## Core Economic Principles

### Zero-Rake Model
- **No house edge**: All ETH deposited by players stays in the system
- **Positive sum**: stETH yield adds value without increasing liabilities
- **Player-to-player**: Losses from one player become gains for others

### Closed-Loop Accounting
- Every ETH pool increase is matched by an ETH inflow or internal transfer
- Liabilities never exceed tracked assets
- stETH rebase yield creates an untracked surplus buffer

### Immutable Guarantees
- Admin cannot withdraw prize pools
- All randomness verified via Chainlink VRF
- Game rules cannot change post-deployment
- Vault distributions are mathematically enforced

---

## ETH Pool Architecture

The game tracks ETH liabilities across **7 distinct pools**:

### Active Gameplay Pools

| Pool | Purpose | Funded By | Consumed By |
|------|---------|-----------|-------------|
| **nextPrizePool** | Accumulator for next level's prize pot | • Gamepiece/MAP purchases (ETH)<br>• Loot box purchases<br>• MAP reward conversions | Transferred to currentPrizePool at level start |
| **currentPrizePool** | Active level's jackpot funding | • nextPrizePool (level start)<br>• Extermination keeps (50% on repeat traits) | • Daily jackpots<br>• Extermination jackpots<br>• Level jackpots |
| **rewardPool** | Long-term jackpot reserve | • Extermination keeps (50% on repeat traits)<br>• Loot box purchases<br>• stETH yield bonuses | • Carryover jackpots<br>• Daily jackpot supplements<br>• BAF jackpots (every 10 levels)<br>• Decimator jackpots |

### Reserved Special Pools

| Pool | Purpose | Funded By | Consumed By |
|------|---------|-----------|-------------|
| **decimatorHundredPool** | Level-100 decimator mega-jackpot | Carved from rewardPool at L%100 == 0 | Decimator jackpot at level 100 |
| **bafHundredPool** | Level-100 BAF mega-jackpot | Carved from rewardPool at L%100 == 0 | BAF jackpot at level 100 |

### Player Liability Pool

| Pool | Purpose | Funded By | Consumed By |
|------|---------|-----------|-------------|
| **claimablePool** | Aggregate player winnings awaiting withdrawal | All jackpot payouts (increases claimableWinnings) | Player withdrawals via claimWinnings() |

### Future Prize Pools

| Pool | Purpose | Funded By | Consumed By |
|------|---------|-----------|-------------|
| **futurePrizePool[level]** | Reserved funding for specific future levels | • Loot box opening (from reserve)<br>• Future mint queueing | Transferred to nextPrizePool when target level is reached |
| **futurePrizePoolTotal** | Aggregate of all future level reserves | Sum of all futurePrizePool[*] | Solvency tracking |
| **lootboxReservePool** | Pending loot box prize allocation | Loot box purchases (future share) | Allocated to futurePrizePool[level] when box is opened |

---

## Purchase Flow

### Gamepiece/MAP Purchases (ETH)

```
Player sends ETH
    ↓
recordMint() in DegenerusGame
    ↓
_processMintPayment()
    ↓
nextPrizePool += ETH amount
    ↓
Player credited with:
    • Gamepiece/MAP NFT
    • Coinflip stake (for BURNIE minting)
    • Affiliate rewards (if applicable)
```

**Key Points**:
- 100% of ETH purchase price goes to `nextPrizePool`
- BURNIE purchases burn the token (no ETH added to pools)
- Claimable balance can be used to purchase (reduces `claimablePool`, no new ETH added)

### Loot Box Purchases

**Normal Mode** (60% tickets/gamepieces, 40% BURNIE):
```
Player sends ETH (minimum 0.01 ETH, any amount)
    ↓
Split:
    • 60% → lootboxReservePool (allocated to rolled level at opening)
    • 20% → nextPrizePool
    • 20% → rewardPool
    ↓
When opened (RNG-based d20 roll):
    • Target level rolled: current level + 0-5 (uniform)
    • Ticket quantity calculated using rolled level's price
    • 60% probability (0-11): MAP tickets OR gamepiece for rolled level (116.67% value)
      - Sub-roll: 1/6 chance gamepiece (if budget allows), 5/6 chance tickets
    • 20% probability (12-15): Small BURNIE consolation (5% value)
    • 20% probability (16-19): Large BURNIE jackpot (195% value)
    • Total EV: 110%
```

**Presale Mode** (60% tickets/gamepieces, 40% BURNIE with 2× multiplier):
```
Player sends ETH (minimum 0.01 ETH, any amount)
    ↓
Split:
    • 10% → lootboxReservePool (allocated to rolled level at opening)
    • 10% → nextPrizePool
    • 30% → Vault (immediate)
    • 50% → rewardPool
    ↓
When opened (RNG-based d20 roll):
    • Target level rolled: current level + 0-5 (uniform)
    • Ticket quantity calculated using rolled level's price
    • 60% probability: MAP tickets OR gamepiece for rolled level (116.67% value)
      - Sub-roll: 1/6 chance gamepiece (if budget allows), 5/6 chance tickets
    • 20% probability: Small BURNIE consolation (10% value, 2× multiplier)
    • 20% probability: Large BURNIE jackpot (390% value, 2× multiplier)
    • Total EV: 150%
```

**Presale Benefits**:
- 2× BURNIE on BURNIE rolls
- Bonus flip rewards (extra coinflip multipliers)
- Vault receives 30% immediately (long-term value for share holders)

### Unified Purchase Function (`DegenerusGame.purchase`)

All ETH/claimable purchases use a single unified function:

```
purchase(
    gamepieceQuantity,  // 0 to skip
    mapQuantity,        // 0 to skip
    lootBoxAmount,      // 0 to skip (must be multiple of 0.025 ETH)
    affiliateCode,
    payKind             // DirectEth, Claimable, or Combined
)
    ↓
Track initial claimableWinnings balance
    ↓
Allocate msg.value proportionally:
    • Loot boxes first (always ETH)
    • Remaining ETH split between gamepieces/MAPs
    ↓
Execute each purchase type:
    • Gamepieces → call DegenerusGamepieces.purchase()
    • MAPs → call DegenerusGamepieces.purchase()
    • Loot boxes → handled inline with affiliate support
    ↓
Track final claimableWinnings balance
    ↓
If spent all claimable (balance ≤ 1 wei):
    • Award 10% bonus on total claimable spent
    • Minimum 3 gamepiece-equivalents required
    • Bonus credited as BURNIE (coinflip stake)
```

**Key Benefits**:
- **Single entry point**: All ETH/claimable purchases unified
- **Unified rebuy**: Use all winnings in one transaction
- **Combined bonus**: Full-spend bonus calculated across all purchase types
- **Loot box affiliates**: Loot boxes earn affiliate rewards (50% of gamepiece rate)
- **Gas efficiency**: One transaction for any combo of purchases
- **Flexible payment**: Supports ETH, claimable, or combined payment modes

**BURNIE Purchases**: For buying with BURNIE tokens, use `DegenerusGamepieces.purchase()` with `payInCoin = true`

**Affiliate Rewards by Payment Method**:

| Payment Type | Affiliate Rate | Notes |
|--------------|----------------|-------|
| **ETH** | Level-scaled | Early: 0.25, Mid: 0.1, Late: 0.05-0.30 BURNIE per gamepiece |
| **Claimable** | Flat 0.05 BURNIE | 1/20th of a mint worth, regardless of level |
| **Combined** | Pro-rated | Blends ETH and claimable rates based on payment split |
| **Loot Box** | 50% of ETH rate | (lootBoxAmount ÷ price) × ETH rate × 0.5 |

**Design Rationale**:
- Lower claimable rate incentivizes fresh ETH inflows over recycling
- Still rewards affiliates for all volume types
- Combined purchases blend rates proportionally

---

## Jackpot Distribution System

### Daily Jackpots (Burn Phase)

Occur once per ~24-hour period during burn phase. Up to **10 daily jackpots** per level.

**Funding Sources**:
1. **Current Prize Pool**: Escalating portion of `dailyJackpotBase` (60-122% over 10 jackpots)
2. **Reward Pool Supplement**: Additional contribution for next-level carryover

**Distribution**:
```
Daily Jackpot Total
    ↓
Split into 4 trait buckets (symbol/color quadrants)
    ↓
Per bucket:
    • 80% paid as ETH to current-level winners
    • 20% converted to MAP tickets (cost added to nextPrizePool)
    ↓
currentPrizePool -= ETH paid + MAP cost
nextPrizePool += MAP cost
claimablePool += ETH distributed to winners
```

**Carryover Jackpot** (runs alongside daily):
- Funded by `rewardPool` slice (1-4% based on funding progress)
- Pays 100% ETH to next-level ticket holders
- Rewards early MAP buyers before burn phase opens

**Escalating Payout Schedule**:
- Jackpot 0: 6.1% of dailyJackpotBase
- Jackpot 1: 6.77%
- Jackpot 2: 7.46%
- ...
- Jackpot 9: 12.25%
- Total: 91.56% of dailyJackpotBase

### Level Jackpot (End of Purchase Phase)

Paid once when purchase phase closes and burn phase begins.

**Funding**:
```
currentPrizePool (from previous level)
    ↓
Split into 4 trait buckets (rotated 60/13.33/13.33/13.34%)
    ↓
Per bucket:
    • 80% paid as ETH to MAP holders
    • 20% converted to MAP tickets (cost added to nextPrizePool)
```

**Solo Bucket Mechanism**:
- One bucket gets 60% share (rotates based on entropy)
- Absorbs remainder to prevent dust accumulation
- Higher chance of solo winner = larger individual payout

### Extermination Jackpot

Triggered when a trait count reaches zero (or 1 on L%10=7).

**Prize Split**:
```
currentPrizePool
    ↓
If repeat trait extermination (or special conditions):
    • 50% → rewardPool (kept for future levels)
    • 50% → extermination jackpot
Else:
    • 100% → extermination jackpot
    ↓
Paid to exterminator + burn ticket holders
    ↓
currentPrizePool -= jackpot amount
claimablePool += payouts
rewardPool += keep (if applicable)
```

### Early-Burn Jackpots (Purchase Phase)

Triggered weekly during purchase phase if players burn early.

**Funding**:
- 1.5% of `rewardPool`
- Split: ~75% MAP tickets, ~25% ETH

**Purpose**:
- Incentivize early burning to keep game progressing
- Reward active players during purchase phase

---

## Level Transition Economics

### Purchase Phase → Burn Phase

When funding target is met or time expires:

```
1. Calculate Prize Pool Distribution
    ↓
   nextPrizePool transferred to currentPrizePool
    ↓
2. Set dailyJackpotBase
    ↓
   Split currentPrizePool:
       • ~60-70% → reserved for daily jackpots
       • ~20-30% → level jackpot
       • Remainder → earlyBurnPercent buffer
    ↓
3. Adjust rewardPool Save %
    ↓
   If lastPurchaseDayFlipTotal doubled: save % increases +2% (capped at 98%)
   If lastPurchaseDayFlipTotal halved: save % decreases -2% (min 0%)
    ↓
4. Pay Level Jackpot (MAP holders)
```

### Burn Phase → Next Level (Setup Phase)

When trait exterminated or timeout (10 jackpots):

```
1. Handle Extermination Economics
    ↓
   If repeat trait or L90:
       currentPrizePool ÷ 2 → rewardPool
       Remaining 50% → extermination jackpot
    ↓
2. Reset Counters
    ↓
   jackpotCounter = 0
   Clear daily burn counts
   Increment level
    ↓
3. Update Pricing (100-level cycle)
    ↓
   L1-L9:    0.025 ETH (initial)
   L10-L29:  0.05 ETH
   L30-L79:  0.1 ETH
   L80-L99:  0.15 ETH
   L100:     0.25 ETH
   (cycle repeats)
    ↓
4. Special Level-100 Handling
    ↓
   If level % 100 == 0:
       lastPrizePool = rewardPool (set new target)
       Carve decimatorHundredPool from rewardPool
       Carve bafHundredPool from rewardPool
       price resets to 0.05 ETH
```

---

## BURNIE Token Economics

### Creation (Minting)

BURNIE is **NOT** minted on purchase. Instead:

```
1. ETH Purchase
    ↓
   Player credited with coinflip stake
    ↓
2. Daily Coinflip (VRF-based, ~50% win rate)
    ↓
   Winner: Claim minted BURNIE (stake × payout multiplier)
   Loser: Stake forfeited
    ↓
3. Unclaimed winnings expire after 30 days
```

**Payout Multiplier**:
- Base: Variable multiplier based on VRF roll
- Last purchase day bonus: +6% to the payout roll
- Recycling bonus: Rolling winnings forward increases future stakes

### Destruction (Burning)

BURNIE burns occur in:

1. **Gamepiece/MAP Purchases**: Primary sink (price × BURNIE exchange rate)
2. **Marketplace Fees**: Trading fees burned
3. **Coinflip Entry**: Bonus flip entries burn BURNIE
4. **Decimator Jackpot Entry**: BURNIE burn for decimator tickets
5. **RNG Nudges**: `reverseFlip()` burns BURNIE to influence next RNG word

### Coinflip Activity Impact

**Reward Pool Adjustment**:
- When `lastPurchaseDayFlipTotal` doubles: save % increases +2%
- When `lastPurchaseDayFlipTotal` halves: save % decreases -2%
- Save % range: 0% to 98%
- Higher save % = more ETH retained in `rewardPool` for future levels

**Incentive Alignment**:
- Active coinflip play signals strong community engagement
- Higher activity = more ETH saved for long-term jackpots
- Lower activity = more immediate prize pool distributions

### BURNIE Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         BURNIE CREATION                                 │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                ETH Gamepiece/MAP Purchase
                                    ↓
                    Coinflip Stake Credited
                                    ↓
                    Daily Coinflip (VRF)
                    │
        ┌───────────┴───────────┐
        │                       │
    Win (~50%)             Lose (~50%)
        │                       │
        ↓                       ↓
  BURNIE Minted          Stake Forfeited
  (claim within 30d)     (no BURNIE)
        │
        ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                      BURNIE CIRCULATION                                 │
└─────────────────────────────────────────────────────────────────────────┘
        │
        ├─ Hold (tradeable ERC20)
        ├─ Purchase gamepieces/MAPs (burns BURNIE)
        ├─ Pay marketplace fees (burns BURNIE)
        ├─ Enter decimator jackpots (burns BURNIE)
        ├─ RNG nudges via reverseFlip (burns BURNIE)
        └─ Vault deposits (virtual allowance, 80% to DGVB)
```

**Key Points**:
- BURNIE is **NOT** minted on purchase (only via coinflip wins)
- ~50% of coinflip participants lose stakes (deflationary pressure)
- All BURNIE use cases burn the token (permanent destruction)
- Creates natural scarcity through gambling + utility burns

---

## Loot Box System

### Purchase Mechanics

**Requirements**:
- Minimum amount: 0.01 ETH (no maximum)
- Flexible amounts allow spending exact claimable balances
- One loot box per day per player
- Can add to existing day's loot box
- RNG must be unlocked (no pending VRF request)

**Day Tracking**:
- Days indexed from `JACKPOT_RESET_TIME` offset (~22:57 UTC)
- Each day creates independent loot box opportunity

### Opening Mechanics

**Entropy Source**:
- Chainlink VRF provides random word
- Large purchases (>1 ETH) split into two independent rolls

**Reward Outcomes** (d20 roll):
- Rolls 0-11 (60%): MAP tickets OR gamepiece for future levels
  - Sub-roll (d6): 1/6 chance gamepiece (if budget ≥ 4× MAP price), 5/6 chance tickets
- Rolls 12-15 (20%): Small BURNIE consolation prize
- Rolls 16-19 (20%): Large BURNIE jackpot

**Ticket/Gamepiece Distribution**:
- **Target Level**: Randomly rolled at opening time (current level + 0-5)
  - 6 possible levels, uniform distribution
  - All tickets/gamepieces awarded for the single rolled level
  - Ticket quantity calculated using the rolled level's price
  - **Value Scaling**: Boxes opened at higher levels yield more tickets (cheaper price per ticket)
- **Tickets**: All awarded for the rolled target level
  - Payout: 116.67% of ETH value
  - **Fallback**: If budget < 1 MAP ticket, converts to BURNIE at 80% value (20% penalty)
- **Gamepiece**: Awarded for the rolled target level
  - Only if budget ≥ gamepiece price (4× MAP price for that level)
  - Replaces ~4 MAP tickets with 1 full gamepiece
  - Overall probability: ~10% (60% × 1/6)

**BURNIE Distribution**:
- **Small BURNIE** (20% chance):
  - Normal mode: 5% of ETH value (~1/20th of a mint worth)
  - Presale mode: 10% of ETH value (2× multiplier)
- **Large BURNIE** (20% chance):
  - Normal mode: 195% of ETH value
  - Presale mode: 390% of ETH value (2× multiplier)
- Total BURNIE EV = 40% normal (1% + 39%), 80% presale (2% + 78%)

### Pool Destination Summary

**Normal Mode**:
- 60% future levels reserve (allocated to rolled level at opening)
- 20% next prize pool (level +1)
- 20% reward pool

**Presale Mode**:
- 10% future levels reserve (allocated to rolled level at opening)
- 10% next prize pool (level +1)
- 30% vault (immediate ETH transfer)
- 50% reward pool

**Note**: The future levels percentage is held in `lootboxReservePool` at purchase time, then allocated to the randomly rolled target level when the box is opened.

---

## Vault System

### Three Share Classes

| Share | Token | Claims | Supply |
|-------|-------|--------|--------|
| **DGVB** | Degenerus Vault BURNIE | 80% of BURNIE deposits | 1B initial (burns reduce) |
| **DGVE** | Degenerus Vault ETH | Combined ETH+stETH pool (excludes DGVA 20%) + all stETH yield | 1B initial (burns reduce) |
| **DGVA** | Degenerus Vault All | 20% of ETH+stETH deposits + 20% of BURNIE deposits | 1B initial (burns reduce) |

### Deposit Mechanics

**Only the game contract can call `deposit()`**:

```
Game sends ETH/stETH or virtual BURNIE allowance
    ↓
Vault splits:
    • 20% of combined ETH+stETH → DGVA claimable pool
    • Remaining 80% of ETH+stETH → DGVE claimable pool
    • 20% of BURNIE allowance → DGVA claimable pool
    • Remaining 80% of BURNIE allowance → DGVB claimable pool
    ↓
stETH rebase yield accumulates
    ↓
Yield accrues to DGVE ONLY (not shared with DGVA)
```

**Vault ETH Sources**:
1. Loot box presale purchases (30% direct)
2. Game-over drain (all remaining ETH/stETH)
3. Direct ETH donations (open to anyone)

### Claim Mechanics

**Proportional Burn Model**:

```
claimAmount = (reserveBalance × sharesBurned) / totalShareSupply
```

**Claim Functions**:
- `burnCoin(amount)`: Burns DGVB → mints BURNIE to user
- `burnEth(amount)`: Burns DGVE → sends ETH + stETH to user
- `burnAll(amount)`: Burns DGVA → sends ETH + stETH + BURNIE to user

**Refill Mechanism**:
- If user burns ALL shares of a class → 1B new shares minted to them
- Prevents division-by-zero
- Keeps share tokens perpetually alive

### Vault Long-Term Value

**Accumulation Sources**:
- Presale loot box revenue (30% of all presale ETH)
- Game-over sweep (all remaining assets after 1-2.5 year inactivity)
- stETH rebase yield (on all ETH held by game + vault)

**Distribution Fairness**:
- DGVA gets 20% of deposits but 0% of yield
- DGVE gets remaining 80% of deposits PLUS 100% of yield
- DGVB gets 80% of BURNIE virtual deposits
- All claims are proportional to share ownership

---

## Solvency Mechanism

### The Invariant

```
Total Assets >= Total Liabilities

Where:
    Total Assets = ETH balance + stETH balance
    Total Liabilities = claimablePool + currentPrizePool + nextPrizePool
                        + rewardPool + futurePrizePoolTotal + decimatorHundredPool
                        + bafHundredPool
```

### Mechanism 1: Inflow Matching

Every pool increase matched by ETH inflow or internal transfer:

| Action | Debit | Credit |
|--------|-------|--------|
| ETH purchase | Player wallet | nextPrizePool |
| BURNIE purchase | BURNIE supply | No pool change |
| Claimable purchase | claimablePool | nextPrizePool |
| Level start | nextPrizePool | currentPrizePool |
| Jackpot payout | currentPrizePool or rewardPool | claimablePool |
| Extermination keep | currentPrizePool | rewardPool |
| MAP conversion | currentPrizePool or rewardPool | nextPrizePool |

**Key Principle**: Liabilities never created from thin air; always backed by existing assets.

### Mechanism 2: Untracked Surplus (stETH Yield)

**The Silent Buffer**:

```
1. Game stakes ETH to Lido → receives stETH 1:1
    ↓
2. stETH balance grows via rebase (daily yield)
    ↓
3. Assets increase, liabilities stay constant
    ↓
4. Surplus = (ETH + stETH) - tracked liabilities
    ↓
5. Surplus available for:
    • Covering temporary ETH shortages
    • Bonus rewardPool contributions
    • Buffer against volatility
```

**Yield Injection Points**:
- Level transitions: Check `yieldPool` size, add bonus to `rewardPool`
- Game-over: All yield swept to vault
- Claims: stETH transferable as payout if ETH is short

### Mechanism 3: stETH Interchange

**Payout Fallback**:

```solidity
function _payoutWithStethFallback(address recipient, uint256 amount) {
    if (address(this).balance >= amount) {
        // Prefer ETH for gas efficiency
        recipient.call{value: amount}("");
    } else {
        // Fallback to stETH if ETH temporarily short
        steth.transfer(recipient, amount);
    }
}
```

**Why This Works**:
- stETH ≈ ETH (1:1 peg, minor variance)
- Combined balance always >= liabilities
- Never reverts due to temporary ETH shortage
- Players receive equivalent value

### Over-Collateralization Sources

1. **stETH Yield**: Continuous appreciation of stETH balance
2. **Dust Accumulation**: Rounding in jackpot distributions
3. **Unclaimed Expirations**: Coinflip winnings not claimed within 30 days
4. **Price Appreciation**: stETH value relative to ETH can fluctuate positively

---

## Complete ETH Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           ETH INFLOWS                                   │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
        ┌──────────────┬────────────┴────────────┬─────────────┐
        │              │                         │             │
   Gamepiece/MAP   Loot Box              Loot Box (Presale)  Direct
   Purchase (ETH)  (Normal)                                   Donation
        │              │                         │             │
        ↓              ↓                         ↓             ↓
  nextPrizePool   60% futurePrizePool      10% futurePrizePool  Untracked
   (100%)         20% nextPrizePool        10% nextPrizePool     Yield
                  20% rewardPool           30% Vault (immediate) Buffer
                                           50% rewardPool

┌─────────────────────────────────────────────────────────────────────────┐
│                        LEVEL START TRANSFER                             │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
               nextPrizePool → currentPrizePool
               futurePrizePool[level] → nextPrizePool (if target level)
                                    │
                                    ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                        ACTIVE LEVEL POOLS                               │
└─────────────────────────────────────────────────────────────────────────┘
        │                                          │
  currentPrizePool                          rewardPool
        │                                          │
        ├─ Daily Jackpots (80% ETH, 20% MAP)     ├─ Carryover Jackpots
        ├─ Extermination Jackpots                ├─ Early-Burn Jackpots
        ├─ Level Jackpots (80% ETH, 20% MAP)     ├─ BAF Jackpots (L%10==0)
        │                                         ├─ Decimator Jackpots
        │                                         └─ Yield Bonuses
        ↓                                          ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                    JACKPOT DISTRIBUTION                                 │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
        ┌──────────────┬────────────┴────────────┬─────────────┐
        │              │                         │             │
    ETH Payout    MAP Conversion         Extermination Keep   Unclaimed
        │              │                         │            Expiration
        ↓              ↓                         ↓             ↓
  claimablePool   nextPrizePool            rewardPool     Untracked
  (player wins)   (recycled)               (future use)    Surplus
        │
        ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                         ETH OUTFLOWS                                    │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
        ┌──────────────┬────────────┴────────────┬─────────────┐
        │              │                         │             │
  Player Claims   Game Over Sweep         Vault Presale      stETH
  claimWinnings() (all pools → vault)     (30% loot boxes)   Yield
        │              │                         │             │
        ↓              ↓                         ↓             ↓
   Player Wallet    Vault                      Vault       Accumulates
                    (DGVE/DGVA)                (DGVE/DGVA)  in Balance

┌─────────────────────────────────────────────────────────────────────────┐
│                      SPECIAL RESERVES (L%100)                           │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
        ┌───────────────────────────┴───────────────────────┐
        │                                                   │
  decimatorHundredPool                            bafHundredPool
  (carved from rewardPool at L100)                (carved from rewardPool at L100)
        │                                                   │
        ↓                                                   ↓
  Decimator Jackpot (L100)                        BAF Jackpot (L100)
```

---

## Economic Interactions Summary

### Purchase → Jackpot → Claim Lifecycle

```
1. Player buys gamepiece with ETH
    ↓
2. ETH → nextPrizePool (100%)
    ↓
3. Level starts: nextPrizePool → currentPrizePool
    ↓
4. Jackpots run: currentPrizePool → claimablePool (winners)
    ↓
5. Winner calls claimWinnings(): claimablePool → player wallet
```

### MAP Conversion Recycling

```
1. Jackpot allocated: 1000 ETH total
    ↓
2. 20% converted to MAP tickets: 200 ETH cost
    ↓
3. Payout flow:
    • 800 ETH → claimablePool (current winners)
    • 200 ETH → nextPrizePool (MAP cost)
    ↓
4. MAP tickets awarded to winners (future level entry)
    ↓
5. nextPrizePool now has 200 ETH for next level
```

**Effect**: Extends prize pool longevity, creates multi-level winner opportunities.

### Extermination Keep Mechanism

```
1. Trait exterminated (repeat trait condition)
    ↓
2. currentPrizePool = 1000 ETH
    ↓
3. Split:
    • 500 ETH → rewardPool (keep)
    • 500 ETH → extermination jackpot
    ↓
4. rewardPool grows for future level jackpots
    ↓
5. Next level starts with smaller currentPrizePool but larger rewardPool
```

**Effect**: Balances immediate vs future rewards, prevents prize pool depletion.

### Loot Box Future Value

```
1. Player buys loot box: 1 ETH (normal mode) at level 10
    ↓
2. Split:
    • 0.6 ETH → lootboxReservePool (awaiting level allocation)
    • 0.2 ETH → nextPrizePool
    • 0.2 ETH → rewardPool
    ↓
3. Game progresses to level 15, player opens box
    ↓
4. Target level rolled: level 15 + (0-5) = levels 15-20 (rolled: level 18)
    ↓
5. Reserve allocation:
    • 0.6 ETH: lootboxReservePool → futurePrizePool[18]
    ↓
6. Outcome roll (d20): 60% probability = tickets
    ↓
7. Tickets calculated using level 18 price:
    • Level 18 price: 0.05 ETH
    • Ticket budget: 0.6 × 116.67% = 0.7 ETH
    • Tickets awarded: 0.7 / 0.05 = 14 MAP tickets for level 18
    ↓
8. When level 18 reached:
    • futurePrizePool[18] (0.6 ETH) → nextPrizePool
    • Player's 14 tickets enter jackpot draws
```

**Effect**: Pre-funds future levels, creates long-term player engagement.

### stETH Yield Compounding

```
1. Game stakes 100 ETH to Lido
    ↓
2. Receives 100 stETH
    ↓
3. Daily rebase: stETH balance grows to 100.01
    ↓
4. Liabilities unchanged (still 100 ETH tracked)
    ↓
5. Yield surplus: 0.01 stETH
    ↓
6. At level transition: check yieldPool
    ↓
7. If yieldPool > threshold: bonus → rewardPool
    ↓
8. Cycle continues: yield → rewardPool → jackpots → winners
```

**Effect**: Zero-rake becomes positive-sum over time.

---

## Conclusion

The Degenerus economic system is a closed-loop, over-collateralized, trustless gambling protocol where:

- **All ETH** deposited by players remains in the system
- **All randomness** is verifiable via Chainlink VRF
- **All payouts** are mathematically enforced by smart contracts
- **All yield** accrues to players or long-term vault holders
- **Zero admin control** over prize pools or game rules

The multi-pool architecture balances:
- **Immediate rewards** (currentPrizePool, daily jackpots)
- **Future incentives** (nextPrizePool, futurePrizePool, rewardPool)
- **Long-term value** (vault shares, stETH yield)
- **Solvency guarantees** (claimablePool, over-collateralization)

Every economic interaction is transparent, auditable, and provably fair.
