# Phase 6: ETH Inflows and Pool Architecture - Research

**Researched:** 2026-03-12
**Domain:** Solidity smart contract analysis -- ETH purchase paths, pool storage, and fund routing
**Confidence:** HIGH

## Summary

Phase 6 is a documentation-only phase. The goal is to produce audit documentation precise enough that a game theory agent can trace every ETH wei from purchase entry to pool allocation. All findings below are extracted directly from contract source code in the repository.

The Degenerus protocol has six distinct ETH purchase paths: ticket purchase (ETH and BURNIE), lootbox purchase (ETH and BURNIE), whale bundle, lazy pass, deity pass, and degenerette wagers. Each routes ETH into a two-pool system (next + future) via packed uint256 storage, with a freeze/pending mechanism during RNG processing. Pool transitions follow a lifecycle: future -> next -> current -> claimable, triggered by purchase targets and advanceGame calls.

**Primary recommendation:** Structure documentation around the six purchase types, extract exact BPS constants and Solidity expressions for each, then map the pool lifecycle with transition triggers.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| INFLOW-01 | Document every ETH purchase path with exact cost formulas | All six purchase functions fully analyzed -- ticket, lootbox, whale bundle, lazy pass, deity pass, degenerette. Exact formulas and constants extracted. |
| INFLOW-02 | Document BURNIE-to-ticket conversion path with virtual ETH formulas | `purchaseCoin` and `purchaseBurnieLootbox` analyzed. BURNIE burn amounts and virtual ETH conversion formulas found. |
| INFLOW-03 | Document degenerette wager inflows with min bets and pool caps | `DegenerusGameDegeneretteModule` analyzed. Min bets (0.005 ETH, 100 BURNIE, 1 WWXRP), pool routing (100% to future), payout cap (10% of futurePool) found. |
| INFLOW-04 | Document presale vs post-presale economic differences | Presale toggle `lootboxPresaleActive` starts true, auto-ends at level >= 3 or 200 ETH mint-lootbox cap. Affects lootbox splits, lootbox % on passes, BURNIE bonuses. |
| POOL-01 | Map complete pool lifecycle with transition triggers | Four-pool system (future, next, current, claimable) with packed storage. All transition functions identified in AdvanceModule and JackpotModule. |
| POOL-02 | Document per-purchase-type pool split ratios with exact BPS values | All BPS constants extracted per purchase type, including presale/post-presale variants. |
| POOL-03 | Document freeze/unfreeze mechanics and pending accumulator behavior | `_swapAndFreeze`, `_unfreezePool`, `prizePoolPendingPacked` mechanics fully documented. |
| POOL-04 | Document purchase target calculation and level advancement | `levelPrizePool[level]` ratchet system, BOOTSTRAP_PRIZE_POOL = 50 ETH, `_applyTimeBasedFutureTake` mechanics found. |
</phase_requirements>

## Contract Architecture Overview

### Key Files

| File | Purpose |
|------|---------|
| `contracts/DegenerusGame.sol` | Main contract, entry points, `recordMint`, pool splits for tickets |
| `contracts/modules/DegenerusGameMintModule.sol` | Delegatecall module: `purchase`, `purchaseCoin`, `purchaseBurnieLootbox`, lootbox pool splits |
| `contracts/modules/DegenerusGameWhaleModule.sol` | Delegatecall module: `purchaseWhaleBundle`, `purchaseLazyPass`, `purchaseDeityPass` |
| `contracts/modules/DegenerusGameDegeneretteModule.sol` | Delegatecall module: `placeFullTicketBets`, degenerette wager handling |
| `contracts/modules/DegenerusGameAdvanceModule.sol` | `advanceGame`, pool transitions, purchase target, freeze/unfreeze |
| `contracts/modules/DegenerusGameJackpotModule.sol` | `consolidatePrizePools`, pool merging at level transition |
| `contracts/storage/DegenerusGameStorage.sol` | Canonical storage layout, packed pool helpers, constants |
| `contracts/libraries/PriceLookupLib.sol` | Level-based ticket price tiers |

### Delegatecall Pattern

All modules inherit `DegenerusGameStorage` and execute via `delegatecall` from `DegenerusGame`. Storage slot alignment is critical -- modules cannot declare their own storage variables.

## Purchase Types and Cost Formulas

### 1. Ticket Purchase (ETH) -- `purchase()` via MintModule

**Entry:** `DegenerusGame.purchase(buyer, ticketQuantity, lootBoxAmount, affiliateCode, payKind)`
**Delegatecall to:** `DegenerusGameMintModule.purchase()`

**Cost formula:**
```solidity
// ticketQuantity is scaled by 100 (TICKET_SCALE), 4 tickets = 1 level
uint256 ticketCost = (price * ticketQuantity) / (4 * TICKET_SCALE);
// where TICKET_SCALE = 100
// Minimum: ticketCost >= TICKET_MIN_BUYIN_WEI (0.0025 ether)
```

**Price per level equivalent (4 tickets):** `price` (the current level price from PriceLookupLib)

**Payment kinds:**
- `DirectEth`: `msg.value >= ticketCost`
- `Claimable`: `msg.value == 0`, deducts from `claimableWinnings[player]`
- `Combined`: `msg.value` + claimable shortfall

**Pool split (via `recordMint`):**
```solidity
uint256 futureShare = (prizeContribution * PURCHASE_TO_FUTURE_BPS) / 10_000;
// PURCHASE_TO_FUTURE_BPS = 1000 (10%)
uint256 nextShare = prizeContribution - futureShare; // 90%
```

**Split:** 10% future, 90% next.

### 2. Ticket Purchase (BURNIE) -- `purchaseCoin()` via MintModule

**Entry:** `DegenerusGame.purchaseCoin(buyer, ticketQuantity, lootBoxBurnieAmount)`
**Delegatecall to:** `DegenerusGameMintModule.purchaseCoin()`

**Cost formula:**
```solidity
uint256 coinCost = (quantity * (PRICE_COIN_UNIT / 4)) / TICKET_SCALE;
// PRICE_COIN_UNIT = 1000 ether (1000 BURNIE)
// So 1 ticket (quantity=100) costs 250 BURNIE
// 4 tickets (1 level, quantity=400) costs 1000 BURNIE
```

**BURNIE is burned:** `coin.burnCoin(payer, coinCost)`

**Pool split:** NONE. BURNIE tickets burn tokens; no ETH enters pools. Virtual ETH is NOT added to pools.

**Cutoff:** Blocked when elapsed since `levelStartTime` exceeds 90 days (level > 0) or 335 days (level 0). Prevents cheap positioning before liveness guard.

### 3. Lootbox Purchase (ETH) -- within `purchase()` via MintModule

**Entry:** Same `purchase()` function, `lootBoxAmount > 0`

**Cost:** Direct ETH amount. Minimum: `LOOTBOX_MIN = 0.01 ether`

**Pool split (post-presale / normal):**
```solidity
LOOTBOX_SPLIT_FUTURE_BPS = 9000  // 90% future
LOOTBOX_SPLIT_NEXT_BPS   = 1000  // 10% next
// rewardShare = lootBoxAmount - futureShare - nextShare = 0
// futureDelta = futureShare + rewardShare
```

**Pool split (presale):**
```solidity
LOOTBOX_PRESALE_SPLIT_FUTURE_BPS = 4000  // 40% future
LOOTBOX_PRESALE_SPLIT_NEXT_BPS   = 4000  // 40% next
LOOTBOX_PRESALE_SPLIT_VAULT_BPS  = 2000  // 20% vault (sent to vault contract)
// rewardShare = lootBoxAmount - futureShare - nextShare - vaultShare = 0
```

**Pool split (distress mode):**
```solidity
futureBps = 0;
nextBps   = 10_000;  // 100% next
vaultBps  = 0;
```

### 4. Lootbox Purchase (BURNIE) -- `purchaseBurnieLootbox()` via MintModule

**Entry:** `DegenerusGame.purchaseBurnieLootbox(buyer, burnieAmount)`

**Cost:** `burnieAmount` BURNIE burned. Minimum: `BURNIE_LOOTBOX_MIN = 1000 ether` (1000 BURNIE)

**Virtual ETH for RNG triggering:**
```solidity
uint256 virtualEth = (burnieAmount * priceWei) / PRICE_COIN_UNIT;
// PRICE_COIN_UNIT = 1000 ether
// Used only for _maybeRequestLootboxRng threshold, NOT added to pools
```

**Pool split:** NONE. BURNIE is burned; no ETH enters pools.

### 5. Whale Bundle -- `purchaseWhaleBundle()` via WhaleModule

**Entry:** `DegenerusGame.purchaseWhaleBundle(buyer, quantity)`
**Delegatecall to:** `DegenerusGameWhaleModule.purchaseWhaleBundle()`

**Cost formula:**
```solidity
// With valid boon:
unitPrice = (WHALE_BUNDLE_STANDARD_PRICE * (10_000 - discountBps)) / 10_000;
// discountBps: 1000 (10%), 2500 (25%), or 5000 (50%)

// Without boon, levels 0-3:
unitPrice = WHALE_BUNDLE_EARLY_PRICE;  // 2.4 ether

// Without boon, levels 4+:
unitPrice = WHALE_BUNDLE_STANDARD_PRICE;  // 4 ether

totalPrice = unitPrice * quantity;  // quantity: 1-100
```

**Pool split:**
```solidity
// Level 0 (pre-game):
nextShare = (totalPrice * 3000) / 10_000;  // 30% next, 70% future

// Level > 0 (post-game):
nextShare = (totalPrice * 500) / 10_000;   // 5% next, 95% future
```

**Lootbox component:**
```solidity
// Presale:
WHALE_LOOTBOX_PRESALE_BPS = 2000  // 20% of totalPrice
// Post-presale:
WHALE_LOOTBOX_POST_BPS = 1000     // 10% of totalPrice
// lootboxAmount = (totalPrice * whaleLootboxBps) / 10_000
```

Note: The lootbox amount is a virtual award tracked for the player -- it does NOT subtract from the pool allocation. The full `totalPrice` goes to pools, and the lootbox is an additional virtual balance.

### 6. Lazy Pass -- `purchaseLazyPass()` via WhaleModule

**Entry:** `DegenerusGame.purchaseLazyPass(buyer)`
**Delegatecall to:** `DegenerusGameWhaleModule.purchaseLazyPass()`

**Cost formula:**
```solidity
// Levels 0-2: flat price
benefitValue = 0.24 ether;
// baseCost = sum of PriceLookupLib.priceForLevel(startLevel + i) for i in 0..9
// balance = benefitValue - baseCost  (excess -> bonus tickets)
totalPrice = hasValidBoon
    ? (benefitValue * (10_000 - boonDiscountBps)) / 10_000
    : benefitValue;

// Levels 3+: variable price
benefitValue = baseCost;  // sum of 10 levels of ticket prices
totalPrice = hasValidBoon
    ? (baseCost * (10_000 - boonDiscountBps)) / 10_000
    : baseCost;

// boonDiscountBps defaults to LAZY_PASS_BOON_DEFAULT_DISCOUNT_BPS = 1000 (10%)
```

**_lazyPassCost formula:**
```solidity
function _lazyPassCost(uint24 startLevel) private pure returns (uint256 total) {
    for (uint24 i = 0; i < 10; ) {  // LAZY_PASS_LEVELS = 10
        total += PriceLookupLib.priceForLevel(startLevel + i);
        unchecked { ++i; }
    }
}
```

**Pool split:**
```solidity
uint256 futureShare = (totalPrice * LAZY_PASS_TO_FUTURE_BPS) / 10_000;
// LAZY_PASS_TO_FUTURE_BPS = 1000 (10%)
uint256 nextShare = totalPrice - futureShare;  // 90%
```

**Lootbox component:**
```solidity
// Based on benefitValue (undiscounted), NOT totalPrice (discounted)
LAZY_PASS_LOOTBOX_PRESALE_BPS = 2000  // 20%
LAZY_PASS_LOOTBOX_POST_BPS    = 1000  // 10%
lootboxAmount = (benefitValue * lootboxBps) / 10_000;
```

### 7. Deity Pass -- `purchaseDeityPass()` via WhaleModule

**Entry:** `DegenerusGame.purchaseDeityPass(buyer, symbolId)`
**Delegatecall to:** `DegenerusGameWhaleModule.purchaseDeityPass()`

**Cost formula:**
```solidity
uint256 k = deityPassOwners.length;  // passes sold so far
uint256 basePrice = DEITY_PASS_BASE + (k * (k + 1) * 1 ether) / 2;
// DEITY_PASS_BASE = 24 ether
// T(k) = k*(k+1)/2 = triangular number
// Pass 0: 24 ETH, Pass 1: 25 ETH, Pass 31: 24 + 496 = 520 ETH

// With boon discount (tier 1/2/3):
uint16 discountBps = boonTier == 3 ? 5000 : (boonTier == 2 ? 2500 : 1000);
totalPrice = (basePrice * (10_000 - discountBps)) / 10_000;
```

**Pool split (identical to whale bundle):**
```solidity
// Level 0: 30% next, 70% future
nextShare = (totalPrice * 3000) / 10_000;

// Level > 0: 5% next, 95% future
nextShare = (totalPrice * 500) / 10_000;
```

**Lootbox component:**
```solidity
DEITY_LOOTBOX_PRESALE_BPS = 2000  // 20%
DEITY_LOOTBOX_POST_BPS    = 1000  // 10%
lootboxAmount = (totalPrice * deityLootboxBps) / 10_000;
```

### 8. Degenerette Wagers -- `placeFullTicketBets()` via DegeneretteModule

**Entry:** `DegenerusGame.placeFullTicketBets(player, currency, amountPerTicket, ticketCount, customTicket, heroQuadrant)` (routed via delegatecall)

**Minimum bets:**
```solidity
MIN_BET_ETH    = 5 ether / 1000;   // 0.005 ETH
MIN_BET_BURNIE = 100 ether;         // 100 BURNIE
MIN_BET_WWXRP  = 1 ether;           // 1 WWXRP
```

**Pool routing (ETH bets only):**
```solidity
// 100% to future pool
if (prizePoolFrozen) {
    _setPendingPools(pNext, pFuture + uint128(totalBet));
} else {
    _setPrizePools(next, future + uint128(totalBet));
}
```

**Payout cap:** `ETH_WIN_CAP_BPS = 1000` (10% of futurePool at resolution time)

**BURNIE bets:** Burned. No ETH enters pools. `lootboxRngPendingBurnie` incremented.
**WWXRP bets:** Burned via `wwxrp.burnForGame()`. No pool impact.

## Pool Split Summary Table

| Purchase Type | Condition | Next BPS | Future BPS | Vault BPS | Notes |
|---------------|-----------|----------|------------|-----------|-------|
| Ticket (ETH) | Always | 9000 | 1000 | 0 | 90% next, 10% future |
| Ticket (BURNIE) | Always | -- | -- | -- | No ETH enters pools |
| Lootbox (ETH) | Normal | 1000 | 9000 | 0 | 10% next, 90% future |
| Lootbox (ETH) | Presale | 4000 | 4000 | 2000 | 40/40/20 |
| Lootbox (ETH) | Distress | 10000 | 0 | 0 | 100% next |
| Lootbox (BURNIE) | Always | -- | -- | -- | No ETH enters pools |
| Whale Bundle | Level 0 | 3000 | 7000 | 0 | 30% next, 70% future |
| Whale Bundle | Level > 0 | 500 | 9500 | 0 | 5% next, 95% future |
| Lazy Pass | Always | 9000 | 1000 | 0 | 90% next, 10% future |
| Deity Pass | Level 0 | 3000 | 7000 | 0 | 30% next, 70% future |
| Deity Pass | Level > 0 | 500 | 9500 | 0 | 5% next, 95% future |
| Degenerette (ETH) | Always | 0 | 10000 | 0 | 100% future |

## Pool Architecture

### Storage Layout

```
prizePoolsPacked (uint256):
  [0:128]   nextPrizePool    (uint128)  -- accumulates from purchases for current level
  [128:256] futurePrizePool  (uint128)  -- long-term reserve, future jackpots

currentPrizePool (uint256):
  Full slot -- active jackpot pool for current level during jackpot phase

prizePoolPendingPacked (uint256):
  [0:128]   nextPrizePoolPending   (uint128)  -- pending during freeze
  [128:256] futurePrizePoolPending (uint128)  -- pending during freeze

levelPrizePool (mapping(uint24 => uint256)):
  Snapshot of nextPrizePool at each level transition -- serves as ratchet target
```

### Pool Lifecycle

```
                  Purchase Phase                    Jackpot Phase
                  ============                      =============

  Purchases ----> nextPrizePool ----[target met]---> currentPrizePool ----> claimableWinnings
       |                |                                    |
       +------> futurePrizePool ----[drawdown]-------->------+
                        |
                        +---[time-based skim]<--- nextPrizePool
```

### Transition Triggers (by function name and condition)

**1. future -> next (drawdown at jackpot phase start):**
```solidity
// In DegenerusGameAdvanceModule._drawDownFuturePrizePool(lvl):
// Called when jackpotPhaseFlag transitions to true
if ((lvl % 100) == 0) {
    reserved = 0;  // x00 levels: no drawdown
} else {
    reserved = (_getFuturePrizePool() * 15) / 100;  // 15% of future -> next
}
```

**2. next -> future (time-based skim at level end):**
```solidity
// In DegenerusGameAdvanceModule._applyTimeBasedFutureTake():
// Called when lastPurchaseDay becomes true, before pool consolidation
// BPS range: NEXT_TO_FUTURE_BPS_MIN (1300) to 10000
// Base: NEXT_TO_FUTURE_BPS_FAST (3000) if elapsed < 28 days
// Adjustments: ±200 BPS for ratio, ±200 BPS for growth, random variance
uint256 take = (nextPoolBefore * bps) / 10_000;
// nextPool decreases, futurePool increases
```

**3. next -> current (consolidation at jackpot phase start):**
```solidity
// In DegenerusGameJackpotModule.consolidatePrizePools():
currentPrizePool += _getNextPrizePool();
_setNextPrizePool(0);

// On x00 levels: portion of future also moves to current
// On rare random dump: 90% of future moves to current
```

**4. current -> claimable (daily jackpot payouts):**
```solidity
// In DegenerusGameAdvanceModule.payDailyJackpot():
// Days 1-4: random 6%-14% of remaining currentPrizePool
// Day 5: 100% of remaining currentPrizePool
// Winners receive ETH in claimableWinnings[player]
```

**5. Purchase target condition (next -> jackpot transition):**
```solidity
// In DegenerusGameAdvanceModule.advanceGame():
if (_getNextPrizePool() >= levelPrizePool[purchaseLevel - 1]) {
    lastPurchaseDay = true;
    compressedJackpotFlag = (day - purchaseStartDay <= 2);
}
// levelPrizePool[0] = BOOTSTRAP_PRIZE_POOL = 50 ether
// levelPrizePool[N] is snapshot of nextPrizePool at level N transition
```

**6. x00 level special handling:**
```solidity
// In _endPhase():
if (lvl % 100 == 0) {
    levelPrizePool[lvl] = _getFuturePrizePool() / 3;
}
// Sets target for next level to 1/3 of future pool
```

## Freeze / Unfreeze Mechanics

### When does freeze activate?

```solidity
// In DegenerusGameStorage._swapAndFreeze():
// Called when advanceGame requests daily RNG (day boundary crossed)
function _swapAndFreeze(uint24 purchaseLevel) internal {
    _swapTicketSlot(purchaseLevel);    // swap double-buffer
    if (!prizePoolFrozen) {
        prizePoolFrozen = true;
        prizePoolPendingPacked = 0;     // zero pending accumulators
    }
    // If ALREADY frozen (jackpot phase multi-day), accumulators keep growing
}
```

### How do purchases interact during freeze?

All purchase functions check `prizePoolFrozen`:
```solidity
if (prizePoolFrozen) {
    (uint128 pNext, uint128 pFuture) = _getPendingPools();
    _setPendingPools(pNext + uint128(nextShare), pFuture + uint128(futureShare));
} else {
    (uint128 next, uint128 future) = _getPrizePools();
    _setPrizePools(next + uint128(nextShare), future + uint128(futureShare));
}
```

During freeze, purchases accumulate in `prizePoolPendingPacked` instead of `prizePoolsPacked`.

### When does unfreeze happen?

```solidity
// In DegenerusGameStorage._unfreezePool():
function _unfreezePool() internal {
    if (!prizePoolFrozen) return;
    (uint128 pNext, uint128 pFuture) = _getPendingPools();
    (uint128 next, uint128 future) = _getPrizePools();
    _setPrizePools(next + pNext, future + pFuture);  // merge pending into live
    prizePoolPendingPacked = 0;
    prizePoolFrozen = false;
}
```

**Unfreeze triggers:**
1. After daily RNG resolves during purchase phase (non-jackpot): `advanceGame` calls `_unfreezePool()` after `_unlockRng(day)`
2. After phase transition completes (jackpot -> purchase): `_unfreezePool()` in transition path
3. After jackpot phase ends (day 5 complete): `_unfreezePool()` after `_endPhase()`

**During 5-day jackpot phase:** Pool stays frozen for the entire jackpot phase. Pending accumulators grow across all 5 days. Unfreeeze happens only when jackpot phase ends.

## Presale vs Post-Presale Differences

### Presale Toggle

```solidity
// Storage: starts true
bool internal lootboxPresaleActive = true;

// Auto-end condition (in AdvanceModule, at PURCHASE->JACKPOT transition):
if (lootboxPresaleActive && (lvl >= 3 || lootboxPresaleMintEth >= LOOTBOX_PRESALE_ETH_CAP))
    lootboxPresaleActive = false;
// LOOTBOX_PRESALE_ETH_CAP = 200 ether
// One-way: can never be re-enabled
```

### Differences

| Feature | Presale | Post-Presale |
|---------|---------|-------------|
| Lootbox ETH split | 40% future, 40% next, 20% vault | 90% future, 10% next |
| Whale bundle lootbox % | 20% of price | 10% of price |
| Lazy pass lootbox % | 20% of benefitValue | 10% of benefitValue |
| Deity pass lootbox % | 20% of totalPrice | 10% of totalPrice |
| Lootbox BURNIE reward | 2x BURNIE (presale multiplier) | 1x BURNIE |
| `bonusFlip` on coinflip | Active | Inactive |
| Presale mint-lootbox tracking | `lootboxPresaleMintEth` incremented | Not tracked |

### Presale Auto-End Conditions (OR):
1. `level >= 3` (third level transition)
2. `lootboxPresaleMintEth >= 200 ether` (cumulative mint-path lootbox ETH)

## BURNIE-to-Ticket Virtual ETH

### purchaseCoin (BURNIE tickets)

```solidity
// Cost in BURNIE:
uint256 coinCost = (quantity * (PRICE_COIN_UNIT / 4)) / TICKET_SCALE;
// = (quantity * 250 ether) / 100
// 1 level (4 tickets, quantity=400) = 1000 BURNIE regardless of ETH price

// BURNIE is burned, NOT converted to ETH. No pool contribution.
```

### purchaseBurnieLootbox (BURNIE lootbox)

```solidity
// BURNIE burned:
coin.burnCoin(buyer, burnieAmount);

// Virtual ETH for RNG threshold only:
uint256 virtualEth = (burnieAmount * priceWei) / PRICE_COIN_UNIT;
// This virtualEth is added to lootboxRngPendingEth for RNG threshold tracking
// It does NOT enter pools.
```

### ETH-to-BURNIE value conversion (used for affiliate payments):

```solidity
function _ethToBurnieValue(uint256 amountWei, uint256 priceWei) private pure returns (uint256) {
    return (amountWei * PRICE_COIN_UNIT) / priceWei;
}
// PRICE_COIN_UNIT = 1000 ether
```

## Ticket Price Tiers (PriceLookupLib)

| Level Range | Price per Level (4 tickets) |
|-------------|---------------------------|
| 0-4 | 0.01 ETH |
| 5-9 | 0.02 ETH |
| 10-29 | 0.04 ETH |
| 30-59 | 0.08 ETH |
| 60-89 | 0.12 ETH |
| 90-99 | 0.16 ETH |
| x00 (100, 200...) | 0.24 ETH |
| x01-x29 | 0.04 ETH |
| x30-x59 | 0.08 ETH |
| x60-x89 | 0.12 ETH |
| x90-x99 | 0.16 ETH |

This 100-level cycle repeats forever after level 100.

## Purchase Target and Level Advancement

### Ratchet System

```solidity
// Target for level N+1:
// nextPrizePool must reach levelPrizePool[N]

// levelPrizePool[0] = BOOTSTRAP_PRIZE_POOL = 50 ether  (set in constructor)
// levelPrizePool[N] = snapshot of nextPrizePool at level N transition

// Special case: x00 levels set target differently:
// _endPhase(): levelPrizePool[lvl] = _getFuturePrizePool() / 3

// Check (in advanceGame purchase phase):
if (_getNextPrizePool() >= levelPrizePool[purchaseLevel - 1]) {
    lastPurchaseDay = true;
}
```

### Time-Based Future Take

When `lastPurchaseDay` triggers, before entering jackpot phase, `_applyTimeBasedFutureTake` skims a portion of nextPrizePool into futurePrizePool:

```solidity
// Base BPS depends on elapsed time since level start + 11 days:
// < 28 days: NEXT_TO_FUTURE_BPS_FAST = 3000 (30%)
// > 28 days: NEXT_TO_FUTURE_BPS_MIN (1300) ramping up over 14 days
// + NEXT_TO_FUTURE_BPS_WEEK_STEP (100) per additional week
// + NEXT_TO_FUTURE_BPS_X9_BONUS (200) on x9 levels

// Adjustments: ratio (future/next vs 2:1 baseline), growth (vs lastPool), ±random variance
// Result: portion of nextPool moves to futurePool before consolidation
```

This skim ensures the future pool stays funded even when levels advance quickly.

## Distress Mode

```solidity
function _isDistressMode() internal view returns (bool) {
    if (gameOver) return false;
    uint48 lst = levelStartTime;
    uint48 ts = uint48(block.timestamp);
    if (level == 0) {
        return uint256(ts) + uint256(DISTRESS_MODE_HOURS) * 1 hours >
            uint256(lst) + uint256(_DEPLOY_IDLE_TIMEOUT_DAYS) * 1 days;
        // Within 6 hours of 365-day deploy timeout
    }
    return uint256(ts) + uint256(DISTRESS_MODE_HOURS) * 1 hours > uint256(lst) + 120 days;
    // Within 6 hours of 120-day liveness guard
}
```

During distress mode, lootbox ETH goes 100% to nextPool (to help meet purchase target and avoid game over).

## Common Pitfalls for Documentation

### Pitfall 1: Lootbox Amount Is NOT Subtracted From Pool Split
The whale bundle, lazy pass, and deity pass all award lootbox amounts as a **percentage of purchase price**, but the full purchase price goes to pools. The lootbox is a virtual balance tracked separately in `lootboxEth[index][player]`. It does not reduce the ETH going to pools.

### Pitfall 2: BURNIE Purchases Have Zero Pool Contribution
BURNIE ticket and lootbox purchases burn tokens. No ETH enters any pool. The virtual ETH calculation for BURNIE lootbox is only used for RNG threshold tracking.

### Pitfall 3: Presale Split Includes Vault
During presale, 20% of lootbox ETH is sent directly to the vault contract via `payable(ContractAddresses.VAULT).call{value: vaultShare}("")`. This is a real ETH transfer, not a pool accounting entry.

### Pitfall 4: Freeze Applies to Packed Storage Only
The freeze mechanism only affects `prizePoolsPacked` (next + future). The `currentPrizePool` is a separate full-width uint256 that is NOT frozen. Purchases during freeze write to `prizePoolPendingPacked` which merges into `prizePoolsPacked` at unfreeze.

### Pitfall 5: Lootbox rewardShare Adds to futureDelta
In the lootbox split code: `futureDelta = futureShare + rewardShare`. The rewardShare is `lootBoxAmount - futureShare - nextShare - vaultShare`. In normal mode (post-presale) with 90/10 split, rewardShare = 0. In presale with 40/40/20 split, rewardShare = 0. But the code structure allows for nonzero rewardShare if BPS constants don't sum to 10000.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Foundry (forge) + Hardhat |
| Config file | foundry.toml / hardhat.config.ts |
| Quick run command | N/A (documentation phase) |
| Full suite command | N/A (documentation phase) |

### Phase Requirements -> Test Map

This is a documentation-only phase. Validation is manual review against contract source code.

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INFLOW-01 | ETH purchase cost formulas match source | manual-only | Verify expressions against .sol files | N/A |
| INFLOW-02 | BURNIE conversion formulas match source | manual-only | Verify expressions against .sol files | N/A |
| INFLOW-03 | Degenerette min bets and routing match source | manual-only | Verify against DegeneretteModule.sol | N/A |
| INFLOW-04 | Presale conditionals match source | manual-only | Verify against AdvanceModule line 275 | N/A |
| POOL-01 | Pool lifecycle diagram matches transitions | manual-only | Verify function names against source | N/A |
| POOL-02 | BPS values match contract constants | manual-only | Grep all BPS constants, cross-reference | N/A |
| POOL-03 | Freeze mechanics match _swapAndFreeze/_unfreezePool | manual-only | Verify against storage helpers | N/A |
| POOL-04 | Purchase target formula matches source | manual-only | Verify levelPrizePool logic | N/A |

### Wave 0 Gaps

None -- existing contract source is the test fixture.

## Sources

### Primary (HIGH confidence)
- `contracts/DegenerusGame.sol` -- entry points, recordMint, pool splits for tickets
- `contracts/modules/DegenerusGameMintModule.sol` -- purchase/purchaseCoin/lootbox split constants
- `contracts/modules/DegenerusGameWhaleModule.sol` -- whale/lazy/deity pricing and pool splits
- `contracts/modules/DegenerusGameDegeneretteModule.sol` -- wager routing
- `contracts/modules/DegenerusGameAdvanceModule.sol` -- pool transitions, purchase target, time-based skim
- `contracts/modules/DegenerusGameJackpotModule.sol` -- consolidatePrizePools
- `contracts/storage/DegenerusGameStorage.sol` -- packed pool helpers, constants, freeze logic
- `contracts/libraries/PriceLookupLib.sol` -- ticket price tiers

All findings are HIGH confidence -- extracted directly from contract source code in the repository.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- this is analysis of existing contracts, not library selection
- Architecture: HIGH -- all pool structures and transitions verified against source
- Pitfalls: HIGH -- identified from direct code reading

**Research date:** 2026-03-12
**Valid until:** Indefinite (source code is static)
