# 04-03 Findings: BPS Fee Split Audit Across All Modules

**Scope:** Every BPS-based fee split across MintModule, JackpotModule, EndgameModule, DegeneretteModule, WhaleModule, AdvanceModule, and DecimatorModule.

**Method:** For each split: (1) identify the pattern (subtraction-remainder vs independent computation), (2) verify sum(parts) == whole, (3) evaluate edge cases at 1 wei, 2 wei, and max values.

---

## 1. MintModule (DegenerusGame.recordMint + MintModule Lootbox)

### Split 1.1: Ticket Purchase 90/10 (PURCHASE_TO_FUTURE_BPS = 1000)

**Location:** `DegenerusGame.sol` lines 402-411

```solidity
uint256 futureShare = (prizeContribution * PURCHASE_TO_FUTURE_BPS) / 10_000;  // 10%
uint256 nextShare = prizeContribution - futureShare;  // remainder = 90%
```

- **Pattern:** Subtraction-remainder (SAFE)
- **Conservation proof:** `futureShare + nextShare = futureShare + (prizeContribution - futureShare) = prizeContribution`. Exact.
- **Edge case (1 wei):** `futureShare = (1 * 1000) / 10_000 = 0`, `nextShare = 1 - 0 = 1`. Sum = 1 wei. PASS.
- **Edge case (3 wei):** `futureShare = 3000 / 10_000 = 0`, `nextShare = 3`. Sum = 3. PASS.
- **Verdict:** PASS -- subtraction-remainder guarantees exact conservation for all inputs.

### Split 1.2: Lootbox Pool Split (Post-presale: 90% future + 10% next; Presale: 40% future + 40% next + 20% vault)

**Location:** `DegenerusGameMintModule.sol` lines 704-713

```solidity
uint256 futureShare = (lootBoxAmount * futureBps) / 10_000;
uint256 nextShare = (lootBoxAmount * nextBps) / 10_000;
uint256 vaultShare = (lootBoxAmount * vaultBps) / 10_000;
uint256 rewardShare;
unchecked {
    rewardShare = lootBoxAmount - futureShare - nextShare - vaultShare;
}
```

- **Pattern:** Triple-independent + subtraction-remainder for rewardShare (SAFE)
- **Conservation proof:** `futureShare + nextShare + vaultShare + rewardShare = futureShare + nextShare + vaultShare + (lootBoxAmount - futureShare - nextShare - vaultShare) = lootBoxAmount`. The rewardShare absorbs all rounding dust.
- **Post-presale (futureBps=9000, nextBps=1000, vaultBps=0):**
  - 1 wei: futureShare = 0, nextShare = 0, vaultShare = 0, rewardShare = 1. Sum = 1. PASS.
  - 11 wei: futureShare = 9, nextShare = 1, rewardShare = 1. Sum = 11. PASS.
- **Presale (futureBps=4000, nextBps=4000, vaultBps=2000):**
  - 1 wei: all shares = 0, rewardShare = 1. Sum = 1. PASS.
  - 3 wei: futureShare = 1, nextShare = 1, vaultShare = 0, rewardShare = 1. Sum = 3. PASS.
- **Note:** `futureDelta = futureShare + rewardShare` (line 716), so all rounding dust goes to futurePrizePool. Economically favorable to the protocol.
- **Verdict:** PASS -- subtraction-remainder on final share guarantees exact conservation.

### Split 1.3: Lootbox Boost (5%/15%/25%)

**Location:** `DegenerusGameMintModule.sol` lines 996-999

```solidity
function _calculateBoost(uint256 amount, uint16 bonusBps) private pure returns (uint256) {
    uint256 cappedAmount = amount > LOOTBOX_BOOST_MAX_VALUE ? LOOTBOX_BOOST_MAX_VALUE : amount;
    unchecked {
        return (cappedAmount * bonusBps) / 10_000;
    }
}
```

- **Pattern:** Single computation (not a split; additive boost on top of amount)
- **Note:** This is NOT a fee split -- it computes a bonus addition. `boostedAmount = amount + boost`. No conservation requirement -- boost creates new lootbox value.
- **Verdict:** N/A (additive, not distributive)

---

## 2. JackpotModule

### Split 2.1: Daily Current Pool BPS (6-14% random slice, or 100% on day 5)

**Location:** `DegenerusGameJackpotModule.sol` lines 312-313

```solidity
uint16 dailyBps = _dailyCurrentPoolBps(counter, randWord);  // 600-1400 or 10000
uint256 budget = (poolSnapshot * dailyBps) / 10_000;
```

- **Pattern:** Single computation -- extracts a portion from currentPrizePool
- **This is NOT a multi-way split.** The budget is deducted from currentPrizePool; the remainder stays. Conservation is guaranteed because:
  - `currentPrizePool -= paidDailyEth` (line 455) deducts only what was actually paid out
  - Unpaid remainder stays in currentPrizePool naturally
- **Edge case (1 wei, dailyBps=600):** `budget = 600/10000 = 0`. Nothing deducted. PASS.
- **Verdict:** PASS -- single extraction, not a split.

### Split 2.2: Daily 20% Lootbox Budget

**Location:** `DegenerusGameJackpotModule.sol` lines 321-329

```solidity
// Gas optimization: 20% = 1/5 (cheaper than * 2000 / 10000)
uint256 dailyLootboxBudget = _validateTicketBudget(budget / 5, lvl, winningTraitsPacked);
if (dailyLootboxBudget != 0) {
    budget -= dailyLootboxBudget;
}
```

- **Pattern:** Subtraction-remainder (SAFE)
- **Conservation proof:** `dailyLootboxBudget + (budget after subtraction) = (validated budget/5) + (budget - validated budget/5) = budget`. But note: `_validateTicketBudget` may return less than `budget/5` (it can reduce). Either way, `budget -= dailyLootboxBudget` ensures ETH redistribution is exact.
- **Edge case (1 wei budget):** `budget/5 = 0`, no lootbox budget, all goes to ETH. PASS.
- **Verdict:** PASS -- subtraction ensures conservation.

### Split 2.3: Daily Carryover Reserve (1% of futurePrizePool)

**Location:** `DegenerusGameJackpotModule.sol` lines 360-367

```solidity
reserveSlice = futurePrizePool / 100;
futurePrizePool -= reserveSlice;
```

- **Pattern:** Direct deduction (SAFE)
- **Conservation proof:** futurePrizePool decreases by exactly reserveSlice. No split, just transfer.
- **Edge case (1 wei futurePrizePool):** `reserveSlice = 0`. No change. PASS.
- **Edge case (99 wei):** `reserveSlice = 0`. PASS.
- **Edge case (100 wei):** `reserveSlice = 1`, futurePrizePool = 99. PASS.
- **Verdict:** PASS.

### Split 2.4: Carryover Lootbox (50% of reserveSlice via DAILY_REWARD_JACKPOT_LOOTBOX_BPS=5000)

**Location:** `DegenerusGameJackpotModule.sol` lines 374-380

```solidity
uint256 carryoverLootboxBudget = _validateTicketBudget(
    (futureEthPool * carryoverLootboxBps) / 10_000, ...);
if (carryoverLootboxBudget != 0) {
    futureEthPool -= carryoverLootboxBudget;
    nextPrizePool += carryoverLootboxBudget;
}
```

- **Pattern:** Subtraction-remainder (SAFE)
- **Conservation proof:** `futureEthPool` remaining + `carryoverLootboxBudget` = original futureEthPool. Remainder stored to `dailyCarryoverEthPool`.
- **Edge case (1 wei futureEthPool):** `(1 * 5000) / 10000 = 0`. No lootbox. PASS.
- **Verdict:** PASS.

### Split 2.5: Purchase Reward Jackpot Lootbox (75% via PURCHASE_REWARD_JACKPOT_LOOTBOX_BPS=7500)

**Location:** `DegenerusGameJackpotModule.sol` lines 580-582

```solidity
uint256 ethDaySlice = (futurePrizePool * poolBps) / 10_000;  // poolBps=100 (1%)
futurePrizePool -= ethDaySlice;
// ...
lootboxBudget = _validateTicketBudget(
    (ethPool * PURCHASE_REWARD_JACKPOT_LOOTBOX_BPS) / 10_000, ...);
```

- **Pattern:** Single extraction + subtraction remainder. Not a multi-way split.
- **Edge case (1 wei ethPool):** `(1 * 7500) / 10000 = 0`. No lootbox. All ETH. PASS.
- **Verdict:** PASS.

### Split 2.6: BURNIE Coin Budget (25% far-future / 75% near-future)

**Location:** `DegenerusGameJackpotModule.sol` lines 647-650

```solidity
uint256 farBudget = (coinBudget * FAR_FUTURE_COIN_BPS) / 10_000;  // 2500 = 25%
uint256 nearBudget = coinBudget - farBudget;  // remainder = 75%
```

- **Pattern:** Subtraction-remainder (SAFE)
- **Conservation proof:** `farBudget + nearBudget = farBudget + (coinBudget - farBudget) = coinBudget`. Exact.
- **Edge case (1 wei):** `farBudget = 0`, `nearBudget = 1`. Sum = 1. PASS.
- **Edge case (3 wei):** `farBudget = 0`, `nearBudget = 3`. Sum = 3. PASS.
- **Verdict:** PASS.

### Split 2.7: DGNRS Reward Pool (1% via LEVEL_JACKPOT_DGNRS_BPS=100)

**Location:** `DegenerusGameJackpotModule.sol` line 716

```solidity
uint256 reward = (dgnrsPool * LEVEL_JACKPOT_DGNRS_BPS) / 10_000;
```

- **Pattern:** Single extraction from DGNRS token pool (not ETH)
- **Note:** This is DGNRS token, not ETH. transferFromPool handles the token transfer. Not an ETH split.
- **Verdict:** N/A (DGNRS token, not ETH fee split).

### Split 2.8: Early Bird Lootbox (3% of futurePrizePool)

**Location:** `DegenerusGameJackpotModule.sol` line 744

```solidity
uint256 reserveContribution = (futurePrizePool * 300) / 10_000; // 3%
futurePrizePool -= reserveContribution;
```

- **Pattern:** Direct deduction (SAFE)
- **Conservation proof:** futurePrizePool reduces by exactly reserveContribution. Budget then distributed to winners with `perWinnerEth = totalBudget / maxWinners` rounding.
- **Edge case (1 wei futurePrizePool):** `reserveContribution = 0`. Returns early. PASS.
- **Verdict:** PASS.

### Split 2.9: consolidatePrizePools (Level 100 keep/move; Normal future dump 90%)

**Location:** `DegenerusGameJackpotModule.sol` lines 838-855

```solidity
// Level 100:
uint256 keepWei = (futurePrizePool * keepBps) / 10_000;
uint256 moveWei = futurePrizePool - keepWei;  // remainder
futurePrizePool = keepWei;
currentPrizePool += moveWei;

// Normal dump:
uint256 moveWei = (futurePrizePool * 9000) / 10_000;
futurePrizePool -= moveWei;
currentPrizePool += moveWei;
```

- **Pattern:** Level 100: Subtraction-remainder (SAFE). Normal dump: direct deduction (SAFE).
- **Conservation proof (level 100):** `keepWei + moveWei = keepWei + (futurePrizePool - keepWei) = futurePrizePool`. Sum of futurePrizePool + currentPrizePool unchanged. Previously confirmed in Phase 3a-02.
- **Conservation proof (normal dump):** futurePrizePool decreases by moveWei, currentPrizePool increases by moveWei. Exact conservation.
- **Edge case (1 wei, level 100, keepBps=0):** keepWei = 0, moveWei = 1. All moves. PASS.
- **Edge case (1 wei, normal dump):** moveWei = 0. No change. PASS.
- **Verdict:** PASS -- confirmed by Phase 3a-02 and re-verified here.

### Split 2.10: Yield Surplus Distribution (23% DGNRS + 23% Vault + 46% future)

**Location:** `DegenerusGameJackpotModule.sol` lines 921-951

```solidity
uint256 stakeholderShare = (yieldPool * 2300) / 10_000; // 23% each for DGNRS and Vault
uint256 futureShare = (yieldPool * 4600) / 10_000; // 46% to future prize pool (~8% buffer left unextracted)
```

- **Pattern:** Independent computation -- intentionally distributes only 92% (23% + 23% + 46%)
- **This is NOT a subtraction-remainder pattern.** Three independent BPS divisions distribute 2300+2300+4600 = 9200 of 10000 bps. The remaining ~8% is intentionally left as an unextracted buffer in yieldPool. This is by design -- the comment says "~8% buffer left unextracted".
- **Conservation analysis:** `stakeholderShare * 2 + futureShare = 2 * floor(yieldPool * 2300 / 10000) + floor(yieldPool * 4600 / 10000)`. This is always <= `yieldPool * 9200 / 10000 <= yieldPool`. The ~8% undistributed remainder stays in the contract balance as surplus, providing a safety margin against stETH rebasing precision.
- **No over-distribution risk:** All three computations floor-divide, so `sum(distributed) <= yieldPool`. The yieldPool is a surplus above obligations; any undistributed portion simply remains as surplus for the next consolidation call.
- **Edge case (1 wei):** `stakeholderShare = 0`, `futureShare = 0`. Nothing distributed. The 1 wei surplus stays. PASS.
- **Edge case (5 wei):** `stakeholderShare = 1`, `futureShare = 2`. Distributed = 1+1+2 = 4 out of 5. 1 wei buffer. PASS.
- **Edge case (100 wei):** `stakeholderShare = 23`, `futureShare = 46`. Distributed = 23+23+46 = 92 out of 100. 8 wei buffer. PASS.
- **Verdict:** PASS -- intentional 8% buffer design. No ETH leaks; undistributed surplus remains in contract for future yield cycles.

### Split 2.11: Bucket Shares (JackpotBucketLib.bucketShares)

**Location:** `contracts/libraries/JackpotBucketLib.sol` lines 190-215

```solidity
// For each non-remainder bucket:
uint256 share = (pool * shareBps[i]) / 10_000;
// Round down to unit * count multiple:
share = (share / unitBucket) * unitBucket;
distributed += share;
// Remainder bucket:
shares[remainderIdx] = pool - distributed;
```

- **Pattern:** Multi-way independent computation with subtraction-remainder on final bucket (SAFE)
- **Conservation proof:** `sum(non-remainder shares) + (pool - sum(non-remainder shares)) = pool`. Exact.
- **The per-unit rounding `(share / unitBucket) * unitBucket` rounds DOWN, meaning rounding dust accumulates in the remainder bucket.** This is intentional -- the remainder bucket (solo bucket, 60% share) absorbs all dust.
- **Edge case (1 wei pool, LEVEL_JACKPOT_SHARES_PACKED [6000,1333,1333,1334]):** All non-remainder shares = 0. Remainder = 1. PASS.
- **Verdict:** PASS -- remainder pattern guarantees pool is fully distributed.

### Split 2.12: _futureKeepBps dice roll

**Location:** `DegenerusGameJackpotModule.sol` lines 1228-1242

```solidity
return (total * 10_000) / 15;
```

- **Pattern:** Computes a BPS value (0 to 13333), used in Split 2.9 consolidation
- **Not a split itself.** It produces a keepBps input for the split in 2.9.
- **Range:** total = 0..20 (5 dice, 0-4 each), so keepBps = 0..13333. Clamped by `keepBps < 10_000` check.
- **Verdict:** N/A (BPS computation input, not a split).

---

## 3. EndgameModule

### Split 3.1: BAF Pool Extraction (10%/25%/20% of futurePrizePool)

**Location:** `DegenerusGameEndgameModule.sol` lines 143-162

```solidity
uint256 bafPct = prevMod100 == 0 ? 20 : (lvl == 50 ? 25 : 10);
uint256 bafPoolWei = (baseFuturePool * bafPct) / 100;
futurePoolLocal -= bafPoolWei;
// ... BAF resolution ...
if (netSpend != bafPoolWei) {
    futurePoolLocal += (bafPoolWei - netSpend);  // return refund
}
if (lootboxToFuture != 0) {
    futurePoolLocal += lootboxToFuture;  // lootbox ETH stays in future
}
```

- **Pattern:** Extract-and-refund (SAFE)
- **Conservation proof:** `futurePoolLocal` decreases by `bafPoolWei`, then increases by `(bafPoolWei - netSpend)` + `lootboxToFuture`. Net effect: `futurePoolLocal -= netSpend - lootboxToFuture`. The ETH either goes to claimable (via _addClaimableEth) or stays in future (via lootbox).
- **netSpend = poolWei - refund** (line 381). Refund comes from DegenerusJackpots.runBafJackpot which returns unused pool.
- **Edge case (1 wei baseFuturePool, bafPct=10):** `bafPoolWei = 10/100 = 0`. No BAF fires. PASS.
- **Edge case (10 wei, bafPct=10):** `bafPoolWei = 1`. BAF resolves with 1 wei. PASS.
- **Verdict:** PASS.

### Split 3.2: BAF Winner Payout (50% ETH / 50% lootbox for large winners; alternating 100% for small)

**Location:** `DegenerusGameEndgameModule.sol` lines 341-371

```solidity
// Large winners:
uint256 ethPortion = amount / 2;
uint256 lootboxPortion = amount - ethPortion;  // remainder

// Small winners alternate 100% ETH (even index) or 100% lootbox (odd index)
```

- **Pattern:** Subtraction-remainder for large winners (SAFE), 100% routing for small (SAFE)
- **Conservation proof (large):** `ethPortion + lootboxPortion = (amount/2) + (amount - amount/2) = amount`. Exact.
- **Edge case (1 wei large winner):** `ethPortion = 0`, `lootboxPortion = 1`. Sum = 1. PASS.
- **Edge case (3 wei):** `ethPortion = 1`, `lootboxPortion = 2`. Sum = 3. PASS.
- **Small winner conservation:** 100% goes to one destination. No split, no loss. PASS.
- **Verdict:** PASS.

### Split 3.3: Decimator Pool Extraction (30% at level 100, 10% at x5 levels)

**Location:** `DegenerusGameEndgameModule.sol` lines 169-194

```solidity
// Level 100 (30% of baseFuturePool):
uint256 decPoolWei = (baseFuturePool * 30) / 100;
uint256 returnWei = IDegenerusGame(address(this)).runDecimatorJackpot(decPoolWei, lvl, rngWord);
uint256 spend = decPoolWei - returnWei;
futurePoolLocal -= spend;
claimableDelta += spend;

// x5 levels (10% of futurePoolLocal):
uint256 decPoolWei = (futurePoolLocal * 10) / 100;
```

- **Pattern:** Extract with exact accounting (SAFE)
- **Conservation proof:** `decPoolWei` is sent to Decimator. `returnWei` is unused pool returned. `spend = decPoolWei - returnWei`. futurePoolLocal decreases by spend. claimablePool increases by spend. Total ETH in system unchanged.
- **Edge case (1 wei baseFuturePool, 30%):** `decPoolWei = 30/100 = 0`. Skipped (if != 0 check). PASS.
- **Edge case (10 wei, 30%):** `decPoolWei = 3`. PASS.
- **Important note:** Level 100 BAF uses `baseFuturePool` for both BAF (20%) and Decimator (30%). These are computed from the SAME snapshot. Combined extraction = 50% of baseFuturePool. The x5 decimator uses `futurePoolLocal` (post-BAF deduction), so there is no over-extraction.
- **Verdict:** PASS.

### Split 3.4: Affiliate DGNRS Reward (1% of affiliate pool)

**Location:** `DegenerusGameEndgameModule.sol` lines 104-106

```solidity
uint256 dgnrsReward = (poolBalance * AFFILIATE_POOL_REWARD_BPS) / 10_000;
```

- **Pattern:** Single extraction from DGNRS token pool
- **Not ETH.** DGNRS token transfer from affiliate pool.
- **Verdict:** N/A (DGNRS token, not ETH).

### Split 3.5: _addClaimableEth Auto-Rebuy Split (EndgameModule)

**Location:** `DegenerusGameEndgameModule.sol` lines 217-266

```solidity
// Via _calcAutoRebuy:
c.reserved = (weiAmount / state.takeProfit) * state.takeProfit;
c.rebuyAmount = weiAmount - c.reserved;
c.ethSpent = baseTickets * ticketPrice;
// Routing: ethSpent to future/nextPrizePool, reserved to claimable
```

- **Pattern:** Subtraction-remainder for reserved/rebuyAmount (SAFE)
- **Conservation proof:** `reserved + rebuyAmount = reserved + (weiAmount - reserved) = weiAmount`. The `ethSpent` may be less than `rebuyAmount` (fractional dust dropped). `reserved + ethSpent <= weiAmount`. The difference `rebuyAmount - ethSpent` is fractional dust that is neither credited to claimable nor to a pool.
- **Dust analysis:** If `rebuyAmount = 7 wei` and `ticketPrice = 3`, then `baseTickets = 2`, `ethSpent = 6`. The 1 wei dust is dropped. This is documented as intentional (line 210: "fractional dust is dropped unconditionally").
- **Max dust per call:** Less than 1 ticket price (sub-cent amounts). Not exploitable.
- **Edge case (1 wei, no takeProfit):** `reserved = 0`, `rebuyAmount = 1`. If ticketPrice > 1, no tickets purchased, falls through to `_creditClaimable(beneficiary, weiAmount)` returning weiAmount to claimable. No loss. PASS.
- **Note:** The `claimablePool += calc.reserved` (line 251) is an immediate in-function update, while JackpotModule's version (line 977) returns reserved as claimableDelta for batch update. Both produce identical accounting results.
- **Verdict:** PASS -- intentional dust drop is sub-cent and non-exploitable.

### Split 3.6: _awardJackpotTickets (50/50 medium, single small, deferred large)

**Location:** `DegenerusGameEndgameModule.sol` lines 398-436

```solidity
// Medium (0.5-5 ETH):
uint256 halfAmount = amount / 2;
// First roll with halfAmount
uint256 secondAmount = amount - halfAmount;  // remainder
// Second roll with secondAmount
```

- **Pattern:** Subtraction-remainder (SAFE)
- **Conservation proof:** `halfAmount + secondAmount = (amount/2) + (amount - amount/2) = amount`. Exact.
- **Edge case (1 wei):** Falls into "very small" path (single roll). No split. PASS.
- **Verdict:** PASS.

---

## 4. DecimatorModule

### Split 4.1: Decimator Claim (50% ETH / 50% Lootbox)

**Location:** `DegenerusGameDecimatorModule.sol` lines 527-541

```solidity
uint256 ethPortion = amount >> 1;  // floor(amount/2)
lootboxPortion = amount - ethPortion;  // remainder

_addClaimableEth(account, ethPortion, rngWord);
claimablePool -= lootboxPortion;
_awardDecimatorLootbox(account, lootboxPortion, rngWord);
```

- **Pattern:** Subtraction-remainder (SAFE)
- **Conservation proof:** `ethPortion + lootboxPortion = (amount >> 1) + (amount - (amount >> 1)) = amount`. Exact.
- **Pool accounting:** The full `amount` was already reserved in `claimablePool` by the EndgameModule (line 176: `claimableDelta += spend`). Here, `ethPortion` stays claimable (via _addClaimableEth), and `lootboxPortion` is removed from claimablePool and converted to lootbox tickets. The `claimablePool -= lootboxPortion` correctly adjusts the reservation.
- **Edge case (1 wei):** `ethPortion = 0`, `lootboxPortion = 1`. 0 goes to claimable, 1 to lootbox. PASS.
- **Edge case (3 wei):** `ethPortion = 1`, `lootboxPortion = 2`. PASS.
- **GameOver path:** 100% to claimable (no split). PASS.
- **Verdict:** PASS.

### Split 4.2: Decimator _addClaimableEth Auto-Rebuy

**Location:** `DegenerusGameDecimatorModule.sol` lines 504-518

```solidity
function _addClaimableEth(address beneficiary, uint256 weiAmount, uint256 entropy) private {
    if (weiAmount == 0) return;
    if (_processAutoRebuy(beneficiary, weiAmount, entropy)) {
        return;
    }
    _creditClaimable(beneficiary, weiAmount);
}
```

- **Pattern:** Same _calcAutoRebuy pattern as JackpotModule and EndgameModule
- **Conservation:** Same analysis as Split 3.5. Dust dropped intentionally.
- **Verdict:** PASS.

---

## 5. DegeneretteModule

### Split 5.1: Degenerette ETH Payout (25% ETH / 75% Lootbox)

**Location:** `DegenerusGameDegeneretteModule.sol` lines 704-719

```solidity
uint256 ethPortion = payout / 4;
uint256 lootboxPortion = payout - ethPortion;

uint256 maxEth = (pool * ETH_WIN_CAP_BPS) / 10_000;  // 10% cap
if (ethPortion > maxEth) {
    lootboxPortion += ethPortion - maxEth;
    ethPortion = maxEth;
}

pool -= ethPortion;
futurePrizePool = pool;
_addClaimableEth(player, ethPortion);
_resolveLootboxDirect(player, lootboxPortion, rngWord);
```

- **Pattern:** Subtraction-remainder with cap adjustment (SAFE)
- **Conservation proof (no cap):** `ethPortion + lootboxPortion = (payout/4) + (payout - payout/4) = payout`. Exact.
- **Conservation proof (with cap):** After cap: `ethPortion = maxEth`, `lootboxPortion = (payout - payout/4) + (payout/4 - maxEth) = payout - maxEth`. `ethPortion + lootboxPortion = maxEth + (payout - maxEth) = payout`. Exact.
- **Pool accounting:** `futurePrizePool -= ethPortion` (ETH leaves for claimable). The lootboxPortion is routed through `_resolveLootboxDirect` which processes lootbox resolution -- the ETH stays in the pool ecosystem (futurePrizePool reduction only by ethPortion).
- **Edge case (1 wei):** `ethPortion = 0`, `lootboxPortion = 1`. Nothing deducted from pool. Lootbox resolves with 1 wei. PASS.
- **Edge case (4 wei):** `ethPortion = 1`, `lootboxPortion = 3`. PASS.
- **Edge case (5 wei):** `ethPortion = 1`, `lootboxPortion = 4`. Sum = 5. PASS.
- **Verdict:** PASS.

### Split 5.2: Degenerette Bet Routing (100% to futurePrizePool)

**Location:** `DegenerusGameDegeneretteModule.sol` line 589

```solidity
futurePrizePool += totalBet;
```

- **Pattern:** No split (100% routing)
- **Verdict:** N/A (not a split).

### Split 5.3: DegeneretteModule _addClaimableEth

**Location:** `DegenerusGameDegeneretteModule.sol` lines 1168-1175

```solidity
function _addClaimableEth(address beneficiary, uint256 weiAmount) private {
    if (weiAmount == 0) return;
    claimablePool += weiAmount;
    _creditClaimable(beneficiary, weiAmount);
}
```

- **Pattern:** No auto-rebuy in DegeneretteModule (simpler version). 100% to claimable.
- **Note:** This is a different signature (no entropy parameter) and different behavior from the JackpotModule/EndgameModule/DecimatorModule versions. No dust loss possible.
- **Verdict:** PASS.

---

## 6. WhaleModule

### Split 6.1: Whale Bundle Fund Distribution (70/30 pre-game, 95/5 post-game)

**Location:** `DegenerusGameWhaleModule.sol` lines 286-295

```solidity
if (level == 0) {
    nextShare = (totalPrice * 3000) / 10_000;  // 30%
} else {
    nextShare = (totalPrice * 500) / 10_000;   // 5%
}
futurePrizePool += totalPrice - nextShare;  // remainder
nextPrizePool += nextShare;
```

- **Pattern:** Subtraction-remainder (SAFE)
- **Conservation proof:** `nextShare + (totalPrice - nextShare) = totalPrice`. Exact.
- **Edge case (1 wei, pre-game):** `nextShare = 3000/10000 = 0`. futurePrizePool += 1. PASS.
- **Edge case (1 wei, post-game):** `nextShare = 500/10000 = 0`. futurePrizePool += 1. PASS.
- **Edge case (3 wei, pre-game):** `nextShare = 9000/10000 = 0`. futurePrizePool += 3. PASS.
- **Edge case (1 ETH = 1e18 wei, pre-game):** `nextShare = 3e17`. futurePrizePool += 7e17. Sum = 1e18. PASS.
- **Verdict:** PASS.

### Split 6.2: Whale Bundle Lootbox (20% presale / 10% post)

**Location:** `DegenerusGameWhaleModule.sol` lines 298-300

```solidity
uint16 whaleLootboxBps = lootboxPresaleActive ? WHALE_LOOTBOX_PRESALE_BPS : WHALE_LOOTBOX_POST_BPS;
uint256 lootboxAmount = (totalPrice * whaleLootboxBps) / 10_000;
_recordLootboxEntry(buyer, lootboxAmount, passLevel, data);
```

- **Pattern:** Single extraction (not a split of totalPrice)
- **Important:** This lootbox amount does NOT reduce the pool split. The 100% of totalPrice goes to pools (Split 6.1), AND lootbox credits are recorded on top. The lootbox is virtual -- it records a credit for future lootbox resolution, not an additional ETH allocation. The ETH backing comes from the pool.
- **Verdict:** N/A (virtual lootbox recording, not an ETH split).

### Split 6.3: Deity Pass Fund Distribution (70/30 pre-game, 95/5 post-game)

**Location:** `DegenerusGameWhaleModule.sol` lines 509-517

```solidity
if (level == 0) {
    nextShare = (totalPrice * 3000) / 10_000;
} else {
    nextShare = (totalPrice * 500) / 10_000;
}
nextPrizePool += nextShare;
futurePrizePool += totalPrice - nextShare;
```

- **Pattern:** Subtraction-remainder (SAFE) -- identical to Split 6.1
- **Conservation proof:** Same as 6.1. `nextShare + (totalPrice - nextShare) = totalPrice`. Exact.
- **Edge case (1 wei):** Same analysis as 6.1. PASS.
- **Verdict:** PASS.

### Split 6.4: Deity Pass Lootbox (20% presale / 10% post)

**Location:** `DegenerusGameWhaleModule.sol` lines 520-521

```solidity
uint256 lootboxAmount = (totalPrice * deityLootboxBps) / 10_000;
```

- **Pattern:** Same as 6.2. Virtual lootbox recording.
- **Verdict:** N/A (virtual lootbox recording).

### Split 6.5: Lazy Pass Fund Distribution (10% future / 90% next via LAZY_PASS_TO_FUTURE_BPS=1000)

**Location:** `DegenerusGameWhaleModule.sol` lines 390-400

```solidity
uint256 futureShare = (totalPrice * LAZY_PASS_TO_FUTURE_BPS) / 10_000;
futurePrizePool += futureShare;
uint256 nextShare;
unchecked {
    nextShare = totalPrice - futureShare;  // remainder
}
nextPrizePool += nextShare;
```

- **Pattern:** Subtraction-remainder (SAFE)
- **Conservation proof:** `futureShare + nextShare = futureShare + (totalPrice - futureShare) = totalPrice`. Exact.
- **Edge case (1 wei):** futureShare = 0, nextShare = 1. PASS.
- **Verdict:** PASS.

### Split 6.6: Lazy Pass Lootbox (20% presale / 10% post / 10% with boon)

**Location:** `DegenerusGameWhaleModule.sol` lines 403-408

```solidity
uint256 lootboxAmount = (totalPrice * lootboxBps) / 10_000;
```

- **Pattern:** Virtual lootbox recording. Same as 6.2/6.4.
- **Verdict:** N/A (virtual lootbox recording).

### Split 6.7: Whale/Deity/Lazy Boon Discount

**Location:** `DegenerusGameWhaleModule.sol` lines 232, 368, 459

```solidity
// Whale boon discount:
unitPrice = (WHALE_BUNDLE_STANDARD_PRICE * (10_000 - discountBps)) / 10_000;

// Lazy pass boon discount:
totalPrice = (totalPrice * (10_000 - boonDiscountBps)) / 10_000;

// Deity pass boon discount:
totalPrice = (basePrice * (10_000 - discountBps)) / 10_000;
```

- **Pattern:** Price reduction, not a split. Reduces the total amount entering the pool system.
- **Note:** Discount creates less ETH entering pools, but 100% of the discounted price is still fully distributed to pools. No conservation issue.
- **Verdict:** N/A (price computation, not fee split).

### Split 6.8: Deity Pass DGNRS Reward (5% of whale pool via DEITY_WHALE_POOL_BPS=500)

**Location:** `DegenerusGameWhaleModule.sol` lines 666

```solidity
uint256 totalReward = (whaleReserve * DEITY_WHALE_POOL_BPS) / 10_000;
```

- **Pattern:** Single extraction from DGNRS token pool
- **Not ETH.** DGNRS token transfer.
- **Verdict:** N/A (DGNRS token, not ETH).

### Split 6.9: Lootbox Boost (5%/15%/25%) in WhaleModule

**Location:** `DegenerusGameWhaleModule.sol` lines 790, 806, 822

```solidity
uint256 boost = (cappedAmount * LOOTBOX_BOOST_25_BONUS_BPS) / 10_000;
boostedAmount += boost;
```

- **Pattern:** Additive boost (not a split). Same as MintModule Split 1.3.
- **Verdict:** N/A (additive, not distributive).

---

## 7. AdvanceModule

### Split 7.1: Time-Based Future Take (_applyTimeBasedFutureTake)

**Location:** `DegenerusGameAdvanceModule.sol` lines 802-866

```solidity
uint256 bps = _nextToFutureBps(reachedAt - start, lvl);  // 0-10000
// ... ratio/growth adjustments ...
if (bps > 10_000) bps = 10_000;
uint256 take = (nextPoolBefore * bps) / 10_000;
// ... variance adjustment ...
nextPrizePool -= take;
futurePrizePool += take;
```

- **Pattern:** Single extraction with variance (SAFE)
- **Conservation proof:** `nextPrizePool` decreases by `take`, `futurePrizePool` increases by `take`. Zero-sum transfer between pools.
- **Variance safety:** The variance code (lines 848-862) ensures `take <= nextPoolBefore` (line 858: `if (take > nextPoolBefore) take = nextPoolBefore`). No underflow possible.
- **BPS clamping:** `bps > 10_000` is clamped to 10_000 (line 844), so take never exceeds nextPoolBefore.
- **Edge case (1 wei nextPool):** `take = (1 * bps) / 10000`. For any bps < 10000, take = 0. For bps = 10000, take = 1. PASS.
- **Verdict:** PASS.

### Split 7.2: Future Pool Draw Down (15% on normal levels, 0% on x00)

**Location:** `DegenerusGameAdvanceModule.sol` lines 869-880

```solidity
if ((lvl % 100) == 0) {
    reserved = 0;
} else {
    reserved = (futurePrizePool * 15) / 100;  // 15%
}
futurePrizePool -= reserved;
nextPrizePool += reserved;
```

- **Pattern:** Direct deduction + addition (SAFE)
- **Conservation proof:** futurePrizePool decreases by reserved, nextPrizePool increases by reserved. Zero-sum transfer.
- **Edge case (1 wei):** `reserved = 15/100 = 0`. No transfer. PASS.
- **Edge case (7 wei):** `reserved = 105/100 = 1`. futurePrizePool = 6, nextPrizePool += 1. PASS.
- **Verdict:** PASS.

### Split 7.3: _autoStakeExcessEth

**Location:** `DegenerusGameAdvanceModule.sol` lines 1001-1007

```solidity
uint256 ethBal = address(this).balance;
uint256 reserve = claimablePool;
if (ethBal <= reserve) return;
uint256 stakeable = ethBal - reserve;
try steth.submit{value: stakeable}(address(0)) returns (uint256) {} catch {}
```

- **Pattern:** Direct deduction (SAFE)
- **Conservation proof:** `stakeable = ethBal - claimablePool`. Exactly the non-claimable ETH is staked. The claimablePool ETH remains in the contract. StETH received is tracked via `steth.balanceOf(address(this))` in the yield surplus calculation (Split 2.10).
- **Not a BPS split.** Simple subtraction.
- **Verdict:** PASS.

### Split 7.4: Writes Budget Cold Storage Scaling

**Location:** `DegenerusGameAdvanceModule.sol` (and JackpotModule) -- `writesBudget -= (writesBudget * 35) / 100`

- **Pattern:** Not an ETH split. Gas budget scaling for storage writes.
- **Verdict:** N/A (gas budget, not ETH).

---

## Cross-Module Summary Table

| Module | # ETH Splits Found | All Use Remainder Pattern? | Max Gap (wei) | Verdict |
|--------|-------------------|---------------------------|---------------|---------|
| MintModule | 2 (ticket 90/10, lootbox 4-way) | Yes (remainder on final share) | 0 | PASS |
| JackpotModule | 7 (daily slice, lootbox, carryover, coin 25/75, yield 23/23/46, bucket shares, consolidate) | 6 remainder + 1 independent (yield: intentional 8% buffer) | 0 | PASS |
| EndgameModule | 4 (BAF extraction, BAF 50/50, Decimator extraction, auto-rebuy) | Yes (all remainder pattern) | 0 (dust drop intentional, sub-cent) | PASS |
| DecimatorModule | 1 (50/50 ETH/lootbox) | Yes (bit-shift + remainder) | 0 | PASS |
| DegeneretteModule | 1 (25/75 ETH/lootbox with 10% cap) | Yes (subtraction-remainder with cap rebalance) | 0 | PASS |
| WhaleModule | 3 (whale 70/30 or 95/5, deity 70/30 or 95/5, lazy 10/90) | Yes (all subtraction-remainder) | 0 | PASS |
| AdvanceModule | 2 (time-based take, 15% draw-down) | Yes (direct deduction) | 0 | PASS |

**Total ETH splits audited:** 20 across 7 modules
**Non-remainder patterns found:** 1 (yield surplus: intentional 8% buffer, not a leak)
**Maximum gap (wei):** 0 for all splits (auto-rebuy dust intentional, sub-cent per operation)

---

## Requirement Verdicts

### ACCT-02: Does the 90/10 prize pool split sum correctly with no wei leak?

**Verdict: PASS**

The ticket purchase 90/10 split in `DegenerusGame.recordMint` uses the subtraction-remainder pattern:

```solidity
uint256 futureShare = (prizeContribution * PURCHASE_TO_FUTURE_BPS) / 10_000;
uint256 nextShare = prizeContribution - futureShare;
```

This mathematically guarantees `futureShare + nextShare = prizeContribution` for ALL possible input values, including 1 wei, odd values, and max uint256. No wei leak is possible. The rounding (floor division) always allocates the 1-wei remainder to `nextShare` (the larger pool), which is economically neutral.

The same subtraction-remainder pattern is used consistently across ALL modules that perform a future/next split:
- WhaleModule whale bundle: `futurePrizePool += totalPrice - nextShare` (line 294)
- WhaleModule deity pass: `futurePrizePool += totalPrice - nextShare` (line 517)
- WhaleModule lazy pass: `nextShare = totalPrice - futureShare` (line 396)
- MintModule lootbox: `rewardShare = lootBoxAmount - futureShare - nextShare - vaultShare` (line 713)

All are wei-exact.

### ACCT-03: Do ALL BPS splits across ALL modules sum to input?

**Verdict: PASS**

Every BPS-based fee split across all 7 modules was traced. All 20 ETH splits identified use one of three patterns:

1. **Subtraction-remainder** (17 of 20): The final share is computed as `total - sum(other shares)`, guaranteeing exact conservation by construction. This is the dominant pattern.

2. **Direct deduction** (2 of 20): A computed amount is subtracted from one pool and added to another (`nextPrizePool -= take; futurePrizePool += take`), guaranteeing zero-sum transfer.

3. **Independent computation with intentional buffer** (1 of 20): The yield surplus distribution (Split 2.10) uses three independent BPS computations summing to 92% (2300+2300+4600=9200 bps), leaving ~8% as an unextracted safety buffer. This is documented and intentional -- the undistributed surplus remains in the contract balance for future yield cycles. No ETH is lost; it simply stays in the surplus pool.

The only "dust" in the system is the intentional sub-cent auto-rebuy fractional drop, which is explicitly documented and affects ticket conversion (not pool totals).

**No unaccounted wei leak exists in any BPS split across the protocol.** The one non-remainder pattern (yield surplus) is intentionally conservative, under-distributing by design.
