# ETH Inflows: Complete Purchase Path Reference

**Purpose:** Reference for game theory agents to compute the exact ETH cost for any purchase type at any game state, without reading contract source code.

**Date:** 2026-03-12
**Source contracts:** DegenerusGame.sol, MintModule, WhaleModule, DegeneretteModule, AdvanceModule, DegenerusGameStorage.sol, PriceLookupLib.sol

---

## Table of Contents

1. [Ticket Purchase (ETH)](#1-ticket-purchase-eth)
2. [Lootbox Purchase (ETH)](#2-lootbox-purchase-eth)
3. [Whale Bundle](#3-whale-bundle)
4. [Lazy Pass](#4-lazy-pass)
5. [Deity Pass](#5-deity-pass)
6. [BURNIE-to-Ticket Conversion](#6-burnie-to-ticket-conversion)
7. [Degenerette Wagers](#7-degenerette-wagers)
8. [Presale vs Post-Presale](#8-presale-vs-post-presale)
9. [Pool Split Summary Table](#9-pool-split-summary-table)

---

## 1. Ticket Purchase (ETH)

**Entry point:** `DegenerusGame.purchase(buyer, ticketQuantity, lootBoxAmount, affiliateCode, payKind)`
Delegatecall to: `DegenerusGameMintModule.purchase()`

**Source:** `contracts/modules/DegenerusGameMintModule.sol` line 634

### Cost Formula

```solidity
uint256 ticketCost = (priceWei * ticketQuantity) / (4 * TICKET_SCALE);
// TICKET_SCALE = 100                         (DegenerusGameStorage.sol:129)
// TICKET_MIN_BUYIN_WEI = 0.0025 ether        (MintModule.sol:94)
// 4 tickets = 1 level; ticketQuantity is scaled by TICKET_SCALE
// Example: 4 tickets at level 0 = (0.01 ether * 400) / 400 = 0.01 ether
```

**Minimum:** `ticketCost >= TICKET_MIN_BUYIN_WEI` (0.0025 ETH). Reverts if below.

### Payment Kinds

| PayKind | Source of ETH | Condition |
|---------|--------------|-----------|
| `DirectEth` | `msg.value` | `msg.value >= ticketCost` |
| `Claimable` | `claimableWinnings[player]` | `msg.value == 0`, balance sufficient |
| `Combined` | `msg.value` + claimable shortfall | Partial ETH + partial claimable |

### Pool Split (via `recordMint` in DegenerusGame.sol)

```solidity
uint256 futureShare = (prizeContribution * PURCHASE_TO_FUTURE_BPS) / 10_000;
// PURCHASE_TO_FUTURE_BPS = 1000               (DegenerusGame.sol:198)
uint256 nextShare = prizeContribution - futureShare;
```

**Split:** 10% future, 90% next. Applies to every ETH ticket purchase unconditionally.

### Ticket Price Tiers (PriceLookupLib)

| Level Range | Price per Level (4 tickets) |
|-------------|---------------------------|
| 0--4 | 0.01 ETH |
| 5--9 | 0.02 ETH |
| 10--29 | 0.04 ETH |
| 30--59 | 0.08 ETH |
| 60--89 | 0.12 ETH |
| 90--99 | 0.16 ETH |
| x00 (100, 200, ...) | 0.24 ETH |
| x01--x29 | 0.04 ETH |
| x30--x59 | 0.08 ETH |
| x60--x89 | 0.12 ETH |
| x90--x99 | 0.16 ETH |

The 100-level cycle repeats indefinitely after level 100.

**Source:** `contracts/libraries/PriceLookupLib.sol`

---

## 2. Lootbox Purchase (ETH)

**Entry point:** Same `purchase()` function, triggered when `lootBoxAmount > 0`.
Delegatecall to: `DegenerusGameMintModule.purchase()`

**Source:** `contracts/modules/DegenerusGameMintModule.sol` lines 628, 685--740

### Cost

Direct ETH amount. No formula -- player sends ETH equal to desired lootbox value.

**Minimum:** `LOOTBOX_MIN = 0.01 ether` (MintModule.sol:90)

### Pool Split: Normal (Post-Presale)

```solidity
LOOTBOX_SPLIT_FUTURE_BPS = 9000   // 90% future   (MintModule.sol:105)
LOOTBOX_SPLIT_NEXT_BPS   = 1000   // 10% next      (MintModule.sol:106)
// rewardShare = lootBoxAmount - futureShare - nextShare = 0
// futureDelta = futureShare + rewardShare
```

**Split:** 90% future, 10% next.

### Pool Split: Presale

```solidity
LOOTBOX_PRESALE_SPLIT_FUTURE_BPS = 4000  // 40% future   (MintModule.sol:109)
LOOTBOX_PRESALE_SPLIT_NEXT_BPS   = 4000  // 40% next      (MintModule.sol:110)
LOOTBOX_PRESALE_SPLIT_VAULT_BPS  = 2000  // 20% vault     (MintModule.sol:111)
// vaultShare sent via: payable(ContractAddresses.VAULT).call{value: vaultShare}("")
```

**Split:** 40% future, 40% next, 20% vault (real ETH transfer to vault contract).

### Pool Split: Distress Mode

```solidity
futureBps = 0;
nextBps   = 10_000;  // 100% next
vaultBps  = 0;
```

**Split:** 100% next. Overrides both presale and normal splits. Triggered within 6 hours of liveness guard expiry (see Section 8 notes).

---

## 3. Whale Bundle

**Entry point:** `DegenerusGame.purchaseWhaleBundle(buyer, quantity)`
Delegatecall to: `DegenerusGameWhaleModule.purchaseWhaleBundle()`

**Source:** `contracts/modules/DegenerusGameWhaleModule.sol` lines 127--305

### Pricing

```solidity
WHALE_BUNDLE_EARLY_PRICE    = 2.4 ether   // levels 0-3   (WhaleModule.sol:127)
WHALE_BUNDLE_STANDARD_PRICE = 4 ether     // levels 4+    (WhaleModule.sol:130)
```

**With boon discount:**

```solidity
unitPrice = (WHALE_BUNDLE_STANDARD_PRICE * (10_000 - discountBps)) / 10_000;
// discountBps by tier:
//   Tier 1: 1000  (10% off) -> 3.6 ETH
//   Tier 2: 2500  (25% off) -> 3.0 ETH
//   Tier 3: 5000  (50% off) -> 2.0 ETH
```

**Without boon:**

```solidity
unitPrice = level <= 3
    ? WHALE_BUNDLE_EARLY_PRICE    // 2.4 ETH
    : WHALE_BUNDLE_STANDARD_PRICE // 4.0 ETH

totalPrice = unitPrice * quantity;  // quantity: 1-100
```

### Pool Split

```solidity
// Level 0 (pre-game):
nextShare = (totalPrice * 3000) / 10_000;   // 30% next, 70% future

// Level > 0 (post-game):
nextShare = (totalPrice * 500) / 10_000;    // 5% next, 95% future
```

### Lootbox Component

```solidity
WHALE_LOOTBOX_PRESALE_BPS = 2000   // 20% of totalPrice  (WhaleModule.sol:142)
WHALE_LOOTBOX_POST_BPS    = 1000   // 10% of totalPrice  (WhaleModule.sol:145)
lootboxAmount = (totalPrice * whaleLootboxBps) / 10_000;
```

**Important:** The lootbox amount is a virtual award tracked in `lootboxEth[index][player]`. It does NOT subtract from the pool allocation. The full `totalPrice` goes to pools.

---

## 4. Lazy Pass

**Entry point:** `DegenerusGame.purchaseLazyPass(buyer)`
Delegatecall to: `DegenerusGameWhaleModule.purchaseLazyPass()`

**Source:** `contracts/modules/DegenerusGameWhaleModule.sol` lines 115--438

### Pricing

**Levels 0--2 (flat price):**

```solidity
benefitValue = 0.24 ether;
// baseCost = sum of PriceLookupLib.priceForLevel(startLevel + i) for i in 0..9
// balance = benefitValue - baseCost  (excess -> bonus tickets)
totalPrice = hasValidBoon
    ? (benefitValue * (10_000 - boonDiscountBps)) / 10_000
    : benefitValue;
```

**Levels 3+ (variable price):**

```solidity
benefitValue = _lazyPassCost(startLevel);  // sum of 10 level prices
totalPrice = hasValidBoon
    ? (benefitValue * (10_000 - boonDiscountBps)) / 10_000
    : benefitValue;
```

**`_lazyPassCost` formula:**

```solidity
function _lazyPassCost(uint24 startLevel) private pure returns (uint256 total) {
    for (uint24 i = 0; i < 10; ) {  // LAZY_PASS_LEVELS = 10
        total += PriceLookupLib.priceForLevel(startLevel + i);
        unchecked { ++i; }
    }
}
```

**Boon discount:**

```solidity
LAZY_PASS_BOON_DEFAULT_DISCOUNT_BPS = 1000  // 10%   (WhaleModule.sol:121)
```

### Pool Split

```solidity
uint256 futureShare = (totalPrice * LAZY_PASS_TO_FUTURE_BPS) / 10_000;
// LAZY_PASS_TO_FUTURE_BPS = 1000              (WhaleModule.sol:124)
uint256 nextShare = totalPrice - futureShare;  // 90%
```

**Split:** 10% future, 90% next. Same ratio as ticket purchases.

### Lootbox Component

```solidity
LAZY_PASS_LOOTBOX_PRESALE_BPS = 2000  // 20% of benefitValue  (WhaleModule.sol:115)
LAZY_PASS_LOOTBOX_POST_BPS    = 1000  // 10% of benefitValue  (WhaleModule.sol:118)
lootboxAmount = (benefitValue * lootboxBps) / 10_000;
```

**Important:** Lootbox is computed on `benefitValue` (undiscounted), NOT on `totalPrice` (discounted). This means boon holders get a larger lootbox-to-cost ratio.

---

## 5. Deity Pass

**Entry point:** `DegenerusGame.purchaseDeityPass(buyer, symbolId)`
Delegatecall to: `DegenerusGameWhaleModule.purchaseDeityPass()`

**Source:** `contracts/modules/DegenerusGameWhaleModule.sol` lines 148--553

### Pricing

```solidity
uint256 k = deityPassOwners.length;  // passes sold so far
uint256 basePrice = DEITY_PASS_BASE + (k * (k + 1) * 1 ether) / 2;
// DEITY_PASS_BASE = 24 ether                  (WhaleModule.sol:154)
// T(k) = k*(k+1)/2 = triangular number
```

**Example prices:**

| Pass # (k) | Base Price | Triangular Add | Total Base |
|-------------|-----------|----------------|------------|
| 0 | 24 ETH | 0 | 24.0 ETH |
| 1 | 24 ETH | 1 | 25.0 ETH |
| 5 | 24 ETH | 15 | 39.0 ETH |
| 10 | 24 ETH | 55 | 79.0 ETH |
| 31 | 24 ETH | 496 | 520.0 ETH |

**With boon discount:**

```solidity
uint16 discountBps = boonTier == 3 ? 5000 : (boonTier == 2 ? 2500 : 1000);
totalPrice = (basePrice * (10_000 - discountBps)) / 10_000;
```

### Pool Split (identical to whale bundle)

```solidity
// Level 0: 30% next, 70% future
nextShare = (totalPrice * 3000) / 10_000;

// Level > 0: 5% next, 95% future
nextShare = (totalPrice * 500) / 10_000;
```

### Lootbox Component

```solidity
DEITY_LOOTBOX_PRESALE_BPS = 2000   // 20% of totalPrice  (WhaleModule.sol:148)
DEITY_LOOTBOX_POST_BPS    = 1000   // 10% of totalPrice  (WhaleModule.sol:151)
lootboxAmount = (totalPrice * deityLootboxBps) / 10_000;
```

---

## 6. BURNIE-to-Ticket Conversion

These paths burn BURNIE tokens. **Zero ETH enters any pool.**

### purchaseCoin (BURNIE Tickets)

**Entry:** `DegenerusGame.purchaseCoin(buyer, ticketQuantity, lootBoxBurnieAmount)`
Delegatecall to: `DegenerusGameMintModule.purchaseCoin()`

**Source:** `contracts/modules/DegenerusGameMintModule.sol` line 873

```solidity
uint256 coinCost = (quantity * (PRICE_COIN_UNIT / 4)) / TICKET_SCALE;
// PRICE_COIN_UNIT = 1000 ether                (DegenerusGameStorage.sol:125)
// = (quantity * 250 ether) / 100
// 1 ticket (quantity=100): 250 BURNIE
// 4 tickets / 1 level (quantity=400): 1000 BURNIE
```

BURNIE is burned via `coin.burnCoin(payer, coinCost)`. **No ETH contribution to pools.**

Fixed cost: 1000 BURNIE per level regardless of current ETH ticket price.

**Cutoff timing:**

- Level > 0: blocked after 90 days elapsed since `levelStartTime`
- Level 0: blocked after 335 days elapsed since `levelStartTime`

This prevents cheap BURNIE-ticket positioning before the liveness guard.

### purchaseBurnieLootbox (BURNIE Lootbox)

**Entry:** `DegenerusGame.purchaseBurnieLootbox(buyer, burnieAmount)`

**Source:** `contracts/modules/DegenerusGameMintModule.sol` line 1011

```solidity
// Minimum: BURNIE_LOOTBOX_MIN = 1000 ether    (MintModule.sol:92)
coin.burnCoin(buyer, burnieAmount);

// Virtual ETH for RNG threshold only:
uint256 virtualEth = (burnieAmount * priceWei) / PRICE_COIN_UNIT;
// Added to lootboxRngPendingEth for threshold tracking
// Does NOT enter pools
```

### _ethToBurnieValue (Affiliate Conversions)

```solidity
function _ethToBurnieValue(uint256 amountWei, uint256 priceWei) private pure returns (uint256) {
    return (amountWei * PRICE_COIN_UNIT) / priceWei;
}
// PRICE_COIN_UNIT = 1000 ether
```

**Source:** `contracts/modules/DegenerusGameMintModule.sol` line 1006

---

## 7. Degenerette Wagers

**Entry point:** `DegenerusGame.placeFullTicketBets(player, currency, amountPerTicket, ticketCount, customTicket, heroQuadrant)`
Delegatecall to: `DegenerusGameDegeneretteModule`

**Source:** `contracts/modules/DegenerusGameDegeneretteModule.sol` lines 223--683

### Minimum Bets

```solidity
MIN_BET_ETH    = 5 ether / 1000;   // 0.005 ETH   (DegeneretteModule.sol:242)
MIN_BET_BURNIE = 100 ether;         // 100 BURNIE   (DegeneretteModule.sol:245)
MIN_BET_WWXRP  = 1 ether;           // 1 WWXRP      (DegeneretteModule.sol:248)
```

### ETH Wager Routing

```solidity
// 100% to future pool
if (prizePoolFrozen) {
    _setPendingPools(pNext, pFuture + uint128(totalBet));
} else {
    _setPrizePools(next, future + uint128(totalBet));
}
```

**Split:** 100% future, 0% next. ETH wagers go entirely to the future pool.

### Payout Cap

```solidity
ETH_WIN_CAP_BPS = 1000              // (DegeneretteModule.sol:223)
uint256 maxEth = (pool * ETH_WIN_CAP_BPS) / 10_000;
// Maximum payout = 10% of futurePool at resolution time
```

### Non-ETH Wagers

- **BURNIE bets:** Burned. `lootboxRngPendingBurnie` incremented. No pool impact.
- **WWXRP bets:** Burned via `wwxrp.burnForGame()`. No pool impact.

---

## 8. Presale vs Post-Presale

### Toggle Mechanism

```solidity
// Storage: starts true
bool internal lootboxPresaleActive = true;   // (DegenerusGameStorage.sol:800)

// Auto-end condition (in AdvanceModule at PURCHASE->JACKPOT transition):
if (lootboxPresaleActive && (lvl >= 3 || lootboxPresaleMintEth >= LOOTBOX_PRESALE_ETH_CAP))
    lootboxPresaleActive = false;
// LOOTBOX_PRESALE_ETH_CAP = 200 ether         (AdvanceModule.sol:110)
```

**Source:** `contracts/modules/DegenerusGameAdvanceModule.sol` line 275

### Auto-End Conditions (OR)

1. `level >= 3` (third level transition)
2. `lootboxPresaleMintEth >= 200 ether` (cumulative mint-path lootbox ETH)

**One-way:** Once set to false, presale can never be re-enabled.

### Feature Comparison Table

| Feature | Presale (lootboxPresaleActive=true) | Post-Presale (lootboxPresaleActive=false) |
|---------|-------------------------------------|------------------------------------------|
| Lootbox ETH split | 40% future / 40% next / 20% vault | 90% future / 10% next |
| Whale bundle lootbox % | 20% of totalPrice (WHALE_LOOTBOX_PRESALE_BPS=2000) | 10% of totalPrice (WHALE_LOOTBOX_POST_BPS=1000) |
| Lazy pass lootbox % | 20% of benefitValue (LAZY_PASS_LOOTBOX_PRESALE_BPS=2000) | 10% of benefitValue (LAZY_PASS_LOOTBOX_POST_BPS=1000) |
| Deity pass lootbox % | 20% of totalPrice (DEITY_LOOTBOX_PRESALE_BPS=2000) | 10% of totalPrice (DEITY_LOOTBOX_POST_BPS=1000) |
| Lootbox BURNIE reward | 2x multiplier (presale bonus) | 1x multiplier |
| `bonusFlip` on coinflip | Active | Inactive |
| Presale mint-lootbox tracking | `lootboxPresaleMintEth` incremented | Not tracked |

---

## 9. Pool Split Summary Table

| Purchase Type | Condition | Next BPS | Future BPS | Vault BPS | Notes |
|---------------|-----------|----------|------------|-----------|-------|
| Ticket (ETH) | Always | 9000 | 1000 | 0 | PURCHASE_TO_FUTURE_BPS=1000 |
| Ticket (BURNIE) | Always | -- | -- | -- | No ETH enters pools; BURNIE burned |
| Lootbox (ETH) | Normal (post-presale) | 1000 | 9000 | 0 | LOOTBOX_SPLIT_*_BPS |
| Lootbox (ETH) | Presale | 4000 | 4000 | 2000 | LOOTBOX_PRESALE_SPLIT_*_BPS; vault is real ETH transfer |
| Lootbox (ETH) | Distress | 10000 | 0 | 0 | Overrides presale/normal |
| Lootbox (BURNIE) | Always | -- | -- | -- | No ETH enters pools; BURNIE burned |
| Whale Bundle | Level 0 | 3000 | 7000 | 0 | Pre-game pricing |
| Whale Bundle | Level > 0 | 500 | 9500 | 0 | Post-game pricing |
| Lazy Pass | Always | 9000 | 1000 | 0 | LAZY_PASS_TO_FUTURE_BPS=1000 |
| Deity Pass | Level 0 | 3000 | 7000 | 0 | Same split as whale bundle |
| Deity Pass | Level > 0 | 500 | 9500 | 0 | Same split as whale bundle |
| Degenerette (ETH) | Always | 0 | 10000 | 0 | 100% future |
| Degenerette (BURNIE) | Always | -- | -- | -- | Burned; no pool impact |
| Degenerette (WWXRP) | Always | -- | -- | -- | Burned; no pool impact |

---

## Common Pitfalls

> **Pitfall 1: Lootbox Amount Is NOT Subtracted From Pool Split.**
> Whale bundle, lazy pass, and deity pass all award lootbox amounts as a percentage of purchase price, but the full purchase price goes to pools. The lootbox is a virtual balance tracked separately in `lootboxEth[index][player]`. It does not reduce the ETH going to pools.

> **Pitfall 2: BURNIE Purchases Have Zero Pool Contribution.**
> BURNIE ticket and lootbox purchases burn tokens. No ETH enters any pool. The virtual ETH calculation for BURNIE lootbox (`virtualEth = (burnieAmount * priceWei) / PRICE_COIN_UNIT`) is only used for RNG threshold tracking.

> **Pitfall 3: Presale Split Includes Real Vault Transfer.**
> During presale, 20% of lootbox ETH is sent directly to the vault contract via `payable(ContractAddresses.VAULT).call{value: vaultShare}("")`. This is a real ETH transfer out of the contract, not a pool accounting entry.

> **Pitfall 4: Freeze Applies to Packed Storage Only.**
> The freeze mechanism only affects `prizePoolsPacked` (next + future). The `currentPrizePool` is a separate full-width uint256 that is NOT frozen. During freeze, purchases write to `prizePoolPendingPacked`, which merges into `prizePoolsPacked` at unfreeze.

> **Pitfall 5: Lootbox rewardShare Adds to futureDelta.**
> In the lootbox split code: `futureDelta = futureShare + rewardShare`. The rewardShare is `lootBoxAmount - futureShare - nextShare - vaultShare`. In both normal (90/10) and presale (40/40/20) modes, rewardShare = 0 because BPS constants sum to 10000. But the code structure would route any remainder to future if constants were changed.

---

## Constant Cross-Reference

All constants verified against contract source on 2026-03-12.

| Constant | Value | Source File | Line |
|----------|-------|-------------|------|
| PURCHASE_TO_FUTURE_BPS | 1000 | DegenerusGame.sol | 198 |
| TICKET_SCALE | 100 | DegenerusGameStorage.sol | 129 |
| TICKET_MIN_BUYIN_WEI | 0.0025 ether | MintModule.sol | 94 |
| PRICE_COIN_UNIT | 1000 ether | DegenerusGameStorage.sol | 125 |
| LOOTBOX_MIN | 0.01 ether | MintModule.sol | 90 |
| BURNIE_LOOTBOX_MIN | 1000 ether | MintModule.sol | 92 |
| LOOTBOX_SPLIT_FUTURE_BPS | 9000 | MintModule.sol | 105 |
| LOOTBOX_SPLIT_NEXT_BPS | 1000 | MintModule.sol | 106 |
| LOOTBOX_PRESALE_SPLIT_FUTURE_BPS | 4000 | MintModule.sol | 109 |
| LOOTBOX_PRESALE_SPLIT_NEXT_BPS | 4000 | MintModule.sol | 110 |
| LOOTBOX_PRESALE_SPLIT_VAULT_BPS | 2000 | MintModule.sol | 111 |
| WHALE_BUNDLE_EARLY_PRICE | 2.4 ether | WhaleModule.sol | 127 |
| WHALE_BUNDLE_STANDARD_PRICE | 4 ether | WhaleModule.sol | 130 |
| WHALE_LOOTBOX_PRESALE_BPS | 2000 | WhaleModule.sol | 142 |
| WHALE_LOOTBOX_POST_BPS | 1000 | WhaleModule.sol | 145 |
| LAZY_PASS_TO_FUTURE_BPS | 1000 | WhaleModule.sol | 124 |
| LAZY_PASS_BOON_DEFAULT_DISCOUNT_BPS | 1000 | WhaleModule.sol | 121 |
| LAZY_PASS_LOOTBOX_PRESALE_BPS | 2000 | WhaleModule.sol | 115 |
| LAZY_PASS_LOOTBOX_POST_BPS | 1000 | WhaleModule.sol | 118 |
| DEITY_PASS_BASE | 24 ether | WhaleModule.sol | 154 |
| DEITY_LOOTBOX_PRESALE_BPS | 2000 | WhaleModule.sol | 148 |
| DEITY_LOOTBOX_POST_BPS | 1000 | WhaleModule.sol | 151 |
| MIN_BET_ETH | 0.005 ether | DegeneretteModule.sol | 242 |
| MIN_BET_BURNIE | 100 ether | DegeneretteModule.sol | 245 |
| MIN_BET_WWXRP | 1 ether | DegeneretteModule.sol | 248 |
| ETH_WIN_CAP_BPS | 1000 | DegeneretteModule.sol | 223 |
| LOOTBOX_PRESALE_ETH_CAP | 200 ether | AdvanceModule.sol | 110 |
