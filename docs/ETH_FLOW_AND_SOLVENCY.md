# ETH Flow & Solvency

**Source of Truth**: `DegenerusGameStorage.sol`, `DegenerusGame.sol`, `DegenerusGameJackpotModule.sol`, `DegenerusGameLootboxModule.sol`

---

## ETH Buckets

All pools are stored in `DegenerusGameStorage`:

| Bucket | Purpose |
|--------|---------|
| `currentPrizePool` | Active prize pool for the current level |
| `nextPrizePool` | Pre-funded pool for the next level |
| `futurePrizePool` | Unified reserve for jackpots and carryover |
| `claimablePool` | Aggregate ETH liability for player winnings |

### Claimable Accounting

- `claimableWinnings[address]`: Per-player claimable ETH
- `claimablePool`: Aggregate of all `claimableWinnings`
- Invariant: `claimablePool >= sum(claimableWinnings[*])`

---

## ETH Flow Diagram

```
ETH Sources                    Routing                         Destinations
---------------------------------------------------------------------------
Gamepiece/ticket (ETH)      -> nextPrizePool + futurePrizePool -> Jackpots -> Winners
Lootbox normal mode         -> 90% futurePool, 10% nextPool    -> Future levels
Lootbox presale mode        -> 40% future, 40% next, 20% vault -> Mixed
Whale bundle (pre-game)     -> 30% next, 70% future            -> Prize pools
Whale bundle (post-game)    -> 5% next, 95% future             -> Prize pools
Lazy pass                   -> 10% future, 90% next            -> Prize pools
Deity pass (pre-game)       -> 30% next, 70% future            -> Prize pools
Deity pass (post-game)      -> 5% next, 95% future             -> Prize pools
stETH yield                 -> Increases total balance          -> System backing
```

---

## ETH Distribution by Purchase Type

### Standard Purchases (Gamepieces/Tickets with ETH)

ETH purchases through `DegenerusGame.purchase()` contribute to prize pools. The exact split depends on the MintModule routing.

### Lootbox Purchases

**Normal Mode** (post-presale):

| Destination | Share |
|-------------|-------|
| Future Prize Pool | 90% |
| Next Prize Pool | 10% |

**Presale Mode** (`lootboxPresaleActive == true`):

| Destination | Share |
|-------------|-------|
| Future Prize Pool | 40% |
| Next Prize Pool | 40% |
| Vault | 20% |

Presale auto-ends when mint-only lootbox accumulation reaches **200 ETH**.

### Whale Bundle

| Game State | Next Pool | Future Pool |
|------------|-----------|-------------|
| Level 0 (pre-game) | 30% | 70% |
| Level 1+ (post-game) | 5% | 95% |

Lootbox portion (20% presale, 10% post) is allocated separately on top.

### Lazy Pass

| Destination | Share |
|-------------|-------|
| Future Prize Pool | 10% |
| Next Prize Pool | 90% |

### Deity Pass

Same as whale bundle: Pre-game 30/70, Post-game 5/95.

---

## Pool Lifecycle

### Level Advance Flow

1. `nextPrizePool` becomes `currentPrizePool` when level advances
2. Daily jackpots draw from `currentPrizePool` (6-14% per day, 100% on day 5)
3. `futurePrizePool` drips into `nextPrizePool` each level
4. Jackpot winnings move from `currentPrizePool` to `claimablePool`

### Future Prize Pool Mechanics

- Accumulates from lootbox purchases (90% normal, 40% presale)
- Drips into next pool each level (percentage-based)
- Whale/deity bundle purchases add 70-95% here
- Long-term reserve that backs future level prize pools

---

## Solvency Model

### Core Invariant

```solidity
totalBal = address(this).balance + stETH.balanceOf(address(this));
obligations = currentPrizePool + nextPrizePool + rewardPool + claimablePool + futurePrizePool;
// totalBal >= obligations (checked every level)
```

### Yield Pool View

```solidity
yieldPoolView() = max(0, (ETH balance + stETH balance) - claimablePool)
```

Only `claimablePool` is subtracted - other buckets are internal accounting for jackpot sizing.

### Solvency Guarantees

| Property | Mechanism |
|----------|-----------|
| ETH only credited when in system | No external promises |
| claimablePool fully backed | Reserved before distribution |
| Admin cannot stake claimable | `ethBal - claimablePool` check |
| Yield distributed only on surplus | `totalBal > obligations` gate |
| stETH as fallback | If raw ETH temporarily short |

---

## stETH Integration

- Admin can stake excess ETH (above `claimablePool`) to Lido for yield
- Admin can swap own ETH for contract stETH (1:1, value-neutral)
- stETH rebase yield increases total system backing
- stETH counts toward `totalBal` for solvency checks

---

## Vault Funding

The vault receives ETH from:
- 20% of presale lootbox purchases
- Game-over sweep (all remaining pools)

Vault has two share classes (DGVE for ETH/stETH, DGVB for BURNIE) with proportional-burn redemption.

---

## Payout Destinations

| Payout Type | Source | Destination |
|-------------|--------|-------------|
| Daily jackpot | currentPrizePool | claimableWinnings |
| Level jackpot | currentPrizePool | claimableWinnings |
| Exterminator payout | currentPrizePool | claimableWinnings |
| BAF jackpot | rewardPool | claimableWinnings |
| Player withdrawal | claimableWinnings | Player wallet |
| Vault redemption | Vault reserves | Share holder wallet |

---

## What Cannot Leave the System

- Prize pools cannot be withdrawn by admin
- Winnings cannot be redirected
- Game rules cannot be changed post-deploy
- Pools are closed-loop: ETH in -> pools -> winners only
