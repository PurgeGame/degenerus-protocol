# BURNIE Tokenomics

**Source of Truth**: `BurnieCoin.sol`, `BurnieCoinflip.sol`, `DegenerusGameStorage.sol`

---

## BURNIE Token Overview

BURNIE is the protocol's utility token. It is not pre-minted and has no initial supply. All BURNIE enters circulation through coinflip wins.

### Value Conversion

- **PRICE_COIN_UNIT**: 1000 BURNIE = 1 ETH equivalent
- Formula: `BURNIE_amount = ETH_value * 1000 ether`

---

## Creation: Coinflip System

BURNIE is **only** created via coinflip wins. There is no other minting pathway.

### How Coinflip Stakes Are Created

1. Player buys gamepieces with ETH -> coinflip stakes credited automatically
2. Affiliate rewards credited as flip stakes
3. Ticket processing bounty (500 BURNIE flip credit per incomplete batch)
4. Various game events credit flip stakes

### Coinflip Mechanics

| Parameter | Value |
|-----------|-------|
| Minimum stake | 100 BURNIE |
| Daily reset | 22:57 UTC |
| Claim window (first) | 30 days |
| Claim window (subsequent) | 90 days |
| Auto-rebuy off claim window | 1095 days (3 years) |
| Loss consolation | 1 WWXRP token |

### Two Flip Modes

| Mode | Win Probability | Payout | Expected Value |
|------|-----------------|--------|----------------|
| Equal odds | ~50% | ~2x | -0.25% (slightly negative) |
| Triple odds | ~33% | ~3x | +3% (slightly positive) |

**Mean reward**: 96.85% of stake across both modes.

### Payout Calculation

The coinflip payout is not a simple 2x. The actual payout depends on:
- Base reward rate (96.85% mean of stake)
- Last purchase day scaling (1.00x-1.03x based on volume vs previous day)
- Presale bonus (+6.2% to payout roll when presale active)

---

## BURNIE Sinks (Deflationary Pressure)

### Primary Sinks (by volume)

| Sink | Mechanism | Volume |
|------|-----------|--------|
| Gamepiece purchases (BURNIE) | Burned on purchase, no ETH added to pools | Highest |
| Ticket purchases (BURNIE) | Burned, except last purchase day (enters prize pool) | Medium |
| Marketplace fees | Listing + trade fees burned | Growing |
| Decimator jackpot entries | BURNIE burned for jackpot participation | Periodic |
| Deity pass transfer | 5 ETH worth of BURNIE burned per transfer | Rare |

### BURNIE-Only Ticket Purchases

- **Last purchase day**: BURNIE tickets contribute to prize pool (like ETH)
- **Other days**: Pure burn, tickets still granted, no ETH pool contribution
- **Rate**: priceWei / 20 (1/20th of gamepiece price, or cost of 20 ticket units)

---

## AfKing Mode (Auto-Play)

### Activation Requirements

| Requirement | Value |
|-------------|-------|
| Auto-Rebuy | Enabled |
| Auto-Flip | Enabled |
| Active Lazy Pass | 10-level or 100-level |
| Initial ETH Balance | >= 2 ETH |
| Initial BURNIE Balance | >= 50,000 BURNIE |

Balance requirements only checked at activation. Balances can drop after activation without deactivation.

### Benefits

**Activity Score Bonus**:
- +2% per consecutive level in AfKing mode
- Maximum: +50% (at 25 consecutive levels)
- Applies to: lootbox values, quest rewards, other activity-based calculations

**Recycle Bonus** (auto-rebuy of coinflip winnings):
- Base: +1.6% per recycle
- Deity edge: +2 BPS per half-level since activation, capped at 300 BPS (+3% max)
- Deity recycle cap: 1,000,000 BURNIE per recycle
- **Max total**: ~4.6% per recycle (1.6% base + 3% deity edge)

### Deactivation

Triggers:
- Disable auto-rebuy or auto-flip
- Lazy pass expires
- Manual deactivation

**Consequence**: Level streak resets to 0. Must rebuild from scratch.

### Claiming While Active

- Can claim complete multiples of threshold (2 ETH)
- AfKing stays active regardless of remaining balance
- BURNIE withdrawal requires disabling auto-rebuy first (deactivates AfKing)

---

## Coinflip Bounty System

### AdvanceGame Bounty

- Caller of `advanceGame()` receives **500 BURNIE** as flip credit
- Not minted directly - enters coinflip (~50% becomes actual BURNIE)
- Incentivizes timely game progression

### Coinflip Bounty (All-Time High Stakes)

- Starting bounty: **1000 BURNIE**
- Increments: **1000 BURNIE per day**
- Awarded to player who sets the all-time-high daily stake

---

## BURNIE Supply Dynamics

### Inflationary Forces

| Source | Volume | Impact |
|--------|--------|--------|
| Coinflip wins | All BURNIE creation | Primary |
| Processing bounties (500 BURNIE) | Small, enters coinflip first | Negligible |

### Deflationary Forces

| Sink | Volume | Impact |
|------|--------|--------|
| BURNIE gamepiece purchases | Highest volume | Primary deflation |
| BURNIE ticket purchases | Medium volume | Secondary |
| Marketplace fees | Growing | Tertiary |
| Deity pass transfers | Rare but large (5 ETH worth) | Situational |

### Net Direction

BURNIE is designed to be net-deflationary over time:
- Creation requires ETH investment (coinflip stakes from ETH purchases)
- Burns happen on every BURNIE-denominated purchase
- BURNIE gamepiece purchases burn BURNIE but add nothing to ETH pools
- Players cycle: buy ETH gamepieces -> win coinflip -> get BURNIE -> burn BURNIE on purchases -> need more ETH

---

## Vault BURNIE (DGVB)

The vault holds BURNIE reserves claimable by DGVB share holders.

- DGVB shares are proportional-burn: burn shares, receive pro-rata BURNIE
- BURNIE enters vault from game-over sweep and other protocol mechanisms
- 1 trillion initial share supply; auto-refills when fully burned

---

## Key Economic Properties

1. **No pre-mine**: All BURNIE created through gameplay
2. **Provably fair**: Coinflip outcomes determined by VRF
3. **Deflationary pressure**: Multiple burn sinks exceed creation rate long-term
4. **ETH-backed creation**: Every BURNIE traces back to an ETH purchase
5. **Utility-driven demand**: BURNIE required for purchases, transfers, marketplace
