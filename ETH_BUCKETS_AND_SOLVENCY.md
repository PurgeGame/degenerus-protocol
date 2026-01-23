# ETH Buckets & Solvency

How ETH accounting works and why the system stays solvent.

---

## ETH Buckets (Liabilities)

The game tracks ETH liabilities in distinct buckets. Their sum represents total ETH owed.

### Player Liabilities

| Bucket | Purpose | Backing |
|--------|---------|---------|
| `claimablePool` | Aggregate player winnings (jackpots, affiliates) | 1:1 ETH/stETH |

Only increases via internal transfer from other pools or explicit deposit.

### Gameplay Rewards

| Bucket | Purpose |
|--------|---------|
| `currentPrizePool` | Active level's exterminator/jackpot pot |
| `nextPrizePool` | Accumulating pot for next level |
| `rewardPool` | General fund for daily jackpots, BAF, side-prizes |
| `futurePrizePool[level]` | Reserved for specific future levels |
| `futurePrizePoolTotal` | Aggregate of all future level reserves |
| `lootboxReservePool` | Pending allocation for unopened loot boxes (allocated at opening time) |

Funded by ETH inflows and internal transfers. When jackpots pay MAP rewards, the MAP cost is moved into
`nextPrizePool`, recycling value into future prize pools. RewardPool save % adjusts +/- 2% based on
coinflip deposits (capped at 98%).

### Reserved Pools

| Bucket | Purpose |
|--------|---------|
| `decimatorHundredPool` | Level-100 Decimator jackpot |
| `bafHundredPool` | Level-100 BAF jackpot |

Carved from `rewardPool` when needed.

---

## Solvency Guarantee

### The Invariant

```
Total Assets >= Total Liabilities

(ETH Balance + stETH Balance) >= (claimablePool + currentPrizePool + nextPrizePool
                                   + rewardPool + futurePrizePoolTotal + lootboxReservePool
                                   + decimatorHundredPool + bafHundredPool)
```

### Mechanism 1: Inflow Matching

Every bucket increase is coupled with an ETH inflow:

| Action | Effect |
|--------|--------|
| Gamepiece/MAP purchases (ETH) | `nextPrizePool` increases by ETH paid |
| Gamepiece/MAP purchases (claimable) | `claimablePool` decreases, `nextPrizePool` increases by same amount |
| Loot box purchases | ETH split between `lootboxReservePool`, `nextPrizePool`, `rewardPool`, and vault (presale) |
| Loot box opening | `lootboxReservePool` → `futurePrizePool[rolledLevel]` based on rolled target level |
| Jackpot allocations | Created by subtracting from `currentPrizePool` or `rewardPool` |
| Jackpot MAP rewards | `nextPrizePool` increases by the MAP cost taken from prize/reward pools |
| Level transition | `nextPrizePool` → `currentPrizePool` and `futurePrizePool[level]` → `nextPrizePool` |

### Mechanism 2: Untracked Surplus (Yield)

The solvency buffer:

1. ETH staked in Lido earns yield (stETH balance grows)
2. **Result**: Assets increase, liabilities stay the same
3. This surplus silently backs all pools

When `claimablePool` pays out, it draws from `address(this).balance` which includes this surplus.

### Mechanism 3: stETH Interchange

ETH and stETH are fungible for solvency:
- If raw ETH is short for payouts, `_payoutWithStethFallback` transfers stETH instead
- Never reverts due to temporary ETH shortage

---

## Why Solvency Holds

1. **Liabilities never exceed inflows** - closed-loop accounting
2. **Assets grow independently** - yield adds to backing without adding liabilities
3. **No ETH leaves without payout** - every withdrawal comes from a tracked bucket

The system is always over-collateralized by design.
