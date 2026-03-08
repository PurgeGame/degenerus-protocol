# Pricing Reference

**Source of Truth**: `PriceLookupLib.sol`, `DegenerusGameWhaleModule.sol`, `DegenerusGameMintModule.sol`

---

## Gamepiece Prices by Level

### Intro Tiers (Levels 0-9)

| Level | Price |
|-------|-------|
| 0-4 | 0.01 ETH |
| 5-9 | 0.02 ETH |

### First Cycle (Levels 10-99)

| Level Range | Price |
|-------------|-------|
| 10-29 | 0.04 ETH |
| 30-59 | 0.08 ETH |
| 60-89 | 0.12 ETH |
| 90-99 | 0.16 ETH |

### Repeating 100-Level Cycles (Level 100+)

| Cycle Offset | Price | Example Levels |
|--------------|-------|----------------|
| x00 | 0.24 ETH | 100, 200, 300 |
| x01-x29 | 0.04 ETH | 101-129, 201-229 |
| x30-x59 | 0.08 ETH | 130-159, 230-259 |
| x60-x89 | 0.12 ETH | 160-189, 260-289 |
| x90-x99 | 0.16 ETH | 190-199, 290-299 |

---

## Ticket Cost Formula

```
costWei = (priceWei * quantity) / 400
```

- **1 full ticket** = quantity 400 = costs priceWei
- **1 trait ticket** = quantity 100 = costs priceWei / 4

| Level | Gamepiece Price | Cost of 400 ticket units | Cost of 100 units |
|-------|-----------------|--------------------------|-------------------|
| 0 | 0.01 ETH | 0.01 ETH | 0.0025 ETH |
| 5 | 0.02 ETH | 0.02 ETH | 0.005 ETH |
| 10 | 0.04 ETH | 0.04 ETH | 0.01 ETH |
| 30 | 0.08 ETH | 0.08 ETH | 0.02 ETH |
| 60 | 0.12 ETH | 0.12 ETH | 0.03 ETH |
| 90 | 0.16 ETH | 0.16 ETH | 0.04 ETH |
| 100 | 0.24 ETH | 0.24 ETH | 0.06 ETH |
| 101 | 0.04 ETH | 0.04 ETH | 0.01 ETH |

---

## Whale Bundle (100-level)

### Availability

| Level | Available? | Price per Bundle |
|-------|-----------|------------------|
| 0-3 | Yes | 2.4 ETH |
| x49, x99 (49, 99, 149...) | Yes | 4 ETH |
| Any level (with boon) | Yes | 4 ETH minus boon discount |
| Other levels | No | - |

### Boon Discounts

| Tier | Discount | Price (off 4 ETH standard) |
|------|----------|----------------------------|
| 1 (default) | 10% | 3.6 ETH |
| 2 | 25% | 3.0 ETH |
| 3 | 50% | 2.0 ETH |

Boon expires after 4 days.

### Ticket Distribution

- **Tickets always start at x1** (next 50-level boundary + 1, or level 1 for early purchases)
- **Bonus levels** (passLevel through level 10): **40 tickets/level** per bundle
- **Standard levels** (11+): **2 tickets/level** per bundle
- **Quantity multiplier**: tickets per level = base * quantity (1-100 bundles)

### Lootbox Allocation

| Mode | Lootbox % of Price |
|------|-------------------|
| Presale | 20% |
| Post-presale | 10% |

### Fund Distribution

| Game State | Next Pool | Future Pool |
|------------|-----------|-------------|
| Pre-game (level 0) | 30% | 70% |
| Post-game (level > 0) | 5% | 95% |

### Ticket Value Calculation

```
Ticket EV = sum over 100 levels of:
  (tickets_per_level / 400) * gamepiece_price_at_level
```

Example - Whale bundle at level 50 (tickets start at L51, cover L51-L150):
- L51-89 (39 levels): 39 * (2/400) * varies
- L90-99 (10 levels): 10 * (2/400) * 0.16 = 0.008 ETH
- L100 (1 level): (2/400) * 0.24 = 0.0012 ETH
- L101-129 (29 levels): 29 * (2/400) * 0.04 = 0.0058 ETH
- L130-150 (21 levels): 21 * (2/400) * 0.08 = 0.0084 ETH

---

## Lazy Pass (10-level)

### Availability

| Level | Available? | Pricing Model |
|-------|-----------|---------------|
| 0-2 | Yes | Flat 0.24 ETH (excess -> bonus tickets) |
| 3 | Yes | Sum of 10 per-level prices |
| x9 (9, 19, 29...) | Yes | Sum of 10 per-level prices |
| Any level (with boon) | Yes | Sum minus boon discount |
| Other levels | No | - |

Renewal allowed when <7 levels remain on current freeze. Cannot stack with deity pass.

### Boon Discounts

| Source | Discount |
|--------|----------|
| Default (legacy) | 10% |
| Configured | 10%, 15%, or 25% |

Boon always gets 10% lootbox regardless of presale status.

### Pricing Table (Sum of Per-Level Prices)

| Start Level | Levels Covered | Price Calculation | Total Price |
|-------------|----------------|-------------------|-------------|
| 1 (from L0) | 1-10 | 4*0.01 + 5*0.02 + 0.04 | 0.18 ETH (flat 0.24) |
| 4 (from L3) | 4-13 | 1*0.01 + 5*0.02 + 4*0.04 | 0.27 ETH |
| 10 (from L9) | 10-19 | 10*0.04 | 0.40 ETH |
| 20 (from L19) | 20-29 | 10*0.04 | 0.40 ETH |
| 30 (from L29) | 30-39 | 10*0.08 | 0.80 ETH |
| 40 (from L39) | 40-49 | 10*0.08 | 0.80 ETH |
| 50 (from L49) | 50-59 | 10*0.08 | 0.80 ETH |
| 60 (from L59) | 60-69 | 10*0.12 | 1.20 ETH |
| 70 (from L69) | 70-79 | 10*0.12 | 1.20 ETH |
| 80 (from L79) | 80-89 | 10*0.12 | 1.20 ETH |
| 90 (from L89) | 90-99 | 10*0.16 | 1.60 ETH |
| 100 (from L99) | 100-109 | 0.24 + 9*0.04 | 0.60 ETH |
| 110 (from L109) | 110-119 | 10*0.04 | 0.40 ETH |

**Levels 0-2**: Flat 0.24 ETH price. The difference between 0.24 and the actual 10-level sum buys bonus tickets at the start level's price.

### Lootbox Allocation

| Mode | Lootbox % of Price |
|------|-------------------|
| Presale (no boon) | 20% |
| Post-presale or boon | 10% |

### Fund Distribution

- **Future pool**: 10% of price
- **Next pool**: 90% of price

---

## Deity Pass

### Availability

- **Any time**, any level
- **Max 1 per player**, 24 total (one per non-dice symbol, IDs 0-23)
- **Symbols**: Q0 Crypto (0-7), Q1 Zodiac (8-15), Q2 Cards (16-23)

### Pricing

Progressive pricing using triangular numbers:

```
Price = 24 + T(n) ETH, where T(n) = n*(n+1)/2, n = passes already sold
```

| Pass # | n | T(n) | Total Price |
|--------|---|------|-------------|
| 1st | 0 | 0 | 24 ETH |
| 2nd | 1 | 1 | 25 ETH |
| 3rd | 2 | 3 | 27 ETH |
| 5th | 4 | 10 | 34 ETH |
| 10th | 9 | 45 | 69 ETH |
| 15th | 14 | 105 | 129 ETH |
| 20th | 19 | 190 | 214 ETH |
| 24th | 23 | 276 | 300 ETH |

### Boon Discounts

| Tier | Discount | Expiry |
|------|----------|--------|
| 1 | 10% | 4 days (lootbox-rolled) or 1 day (deity-granted) |
| 2 | 25% | Same |
| 3 | 50% | Same |

### Included Rewards

- **Tickets**: Same as whale bundle (40/level bonus through L10, 2/level standard, 100 levels)
- **Lootbox**: 20% of price (presale), 10% (post-presale)
- **DGNRS**: 5% of whale pool
- **ERC721 NFT**: Minted with symbolId as tokenId
- **Refundable**: At level 0 (pre-game), full refund if game never starts; levels 1-9 gameover pays 20 ETH per pass

### Transfer

- Costs **5 ETH worth of BURNIE** burned from sender
- Nukes sender's mint stats and quest streak
- One-directional: sender loses all deity perks, receiver gains them
- Blocked at level 0

### Fund Distribution

Same as whale bundle: Pre-game 30% next / 70% future, Post-game 5% next / 95% future.

---

## Lootbox Boost Boons

Consumable boosts applied during whale/lazy/deity purchases:

| Tier | Boost | Max Value | Expiry |
|------|-------|-----------|--------|
| 5% | +500 BPS | 10 ETH | 48 hours |
| 15% | +1500 BPS | 10 ETH | 48 hours |
| 25% | +2500 BPS | 10 ETH | 48 hours |

---

## DGNRS Token Rewards

### From Whale Bundle Purchases

| Recipient | Pool | Share |
|-----------|------|-------|
| Buyer | Whale pool | 1% |
| Direct affiliate | Affiliate pool | 0.1% |
| Upline affiliate | Affiliate pool | 0.02% |

### From Deity Pass Purchases

| Recipient | Pool | Share |
|-----------|------|-------|
| Buyer | Whale pool | 5% |
| Direct affiliate | Affiliate pool | 0.5% |
| Upline affiliate | Affiliate pool | 0.1% |

### Earlybird DGNRS

Available through level 3 only. Emissions target 1,000 ETH total.
