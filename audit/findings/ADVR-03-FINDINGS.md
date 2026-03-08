# ADVR-03 Findings: claimWinnings Overflow

**Warden:** "Overflow Hunter" (precision math persona)
**Brief:** Prove sum(claimableWinnings[all]) can exceed claimablePool
**Scope:** All claimableWinnings/claimablePool increment and decrement sites
**Information:** Source code + v2.0 QA findings
**Session Date:** 2026-03-05

## Summary

**Result: No Medium+ findings discovered.**

After exhaustive tracing of every claimableWinnings increment site and every claimablePool increment site across all 10 modules + main contract, no accounting mismatch was found. Every claimableWinnings credit has a matching claimablePool credit, either directly at the call site or via the caller's aggregation of return values.

## Methodology

1. Grepped all `claimableWinnings[...] +=` sites across the codebase
2. Grepped all `claimablePool +=` and `claimablePool -=` sites
3. For each credit site: traced the calling chain to verify claimablePool is updated
4. Analyzed the 1 wei sentinel pattern for accumulation risk
5. Analyzed the DecimatorModule pre-reservation model
6. Analyzed auto-rebuy return value handling across all three modules

## Accounting Trace

### Core Credit Function: _creditClaimable() (PayoutUtils.sol:30-36)

```solidity
function _creditClaimable(address beneficiary, uint256 weiAmount) internal {
    if (weiAmount == 0) return;
    unchecked { claimableWinnings[beneficiary] += weiAmount; }
}
```

**Critical:** This function does NOT update claimablePool. All callers must handle claimablePool themselves.

### Site-by-Site Verification

| Site | Module | claimableWinnings += | claimablePool += | Match? |
|------|--------|---------------------|-------------------|--------|
| _creditClaimable() | PayoutUtils | weiAmount | N/A (caller) | Caller verified |
| _queueWhalePassClaimCore() | PayoutUtils:88-90 | remainder | remainder | YES |
| handleGameOverDrain (level 0) | GameOverModule:79 | refund | totalRefunded (line 90) | YES |
| handleGameOverDrain (level 1-9) | GameOverModule:102 | refund | totalRefunded (line 113) | YES |
| handleGameOverDrain (decimator) | GameOverModule:139 | via runDecimatorJackpot | decSpend (line 139) | YES |
| handleGameOverDrain (terminal) | GameOverModule:148-150 | via runTerminalJackpot | inside _distributeJackpotEth | YES |

### _addClaimableEth() Variants (3 independent implementations)

**JackpotModule._addClaimableEth() (lines 965-985):**
- Normal path: calls `_creditClaimable(beneficiary, weiAmount)`, returns `weiAmount`
- Auto-rebuy path: calls `_processAutoRebuy()`, returns `calc.reserved`
- Caller adds return value to `claimablePool` via `liabilityDelta` accumulator
- **Verified:** _distributeJackpotEth (line 1564): `claimablePool += ctx.liabilityDelta`
- **Verified:** payDailyJackpot (line 1484, 1516): `claimablePool += liabilityDelta`
- **Verified:** _distributeYieldSurplus (line 948): `claimablePool += claimableDelta`

**EndgameModule._addClaimableEth() (lines 217-266):**
- Normal path: calls `_creditClaimable(beneficiary, weiAmount)`, returns `weiAmount`
- Auto-rebuy path: calls `_calcAutoRebuy()`, credits reserved via `_creditClaimable()`, returns 0
- **Critical detail:** When auto-rebuy fires and calc.reserved != 0, line 251 does `claimablePool += calc.reserved` INSIDE the function, then returns 0 so the caller does NOT double-count
- **Verified:** runRewardJackpots (line 202): `claimablePool += claimableDelta` -- only adds the non-auto-rebuy portion

**DecimatorModule._addClaimableEth() (lines 508-518):**
- Normal path: calls `_creditClaimable(beneficiary, weiAmount)`, returns void
- Auto-rebuy path: calls `_processAutoRebuy()`, returns void
- **Critical detail:** DecimatorModule uses a pre-reservation model. claimablePool is incremented at reservation time (EndgameModule line 176/193/202), NOT at claim time
- On auto-rebuy: `claimablePool -= calc.ethSpent` (line 492) deducts the converted portion from the pre-reserved pool
- On lootbox split: `claimablePool -= lootboxPortion` (line 539) deducts the lootbox conversion
- **Verified:** Pre-reserved amount = spend from runDecimatorJackpot. Individual claims deduct from this reservation. Net effect: exact accounting.

### DecimatorModule Pre-Reservation Model (Deep Trace)

1. `runDecimatorJackpot(poolWei, lvl, rngWord)` is called from EndgameModule
2. If winners exist: returns 0 (all funds held). `spend = poolWei - 0 = poolWei`
3. EndgameModule: `claimableDelta += spend` then `claimablePool += claimableDelta` (line 202)
4. Pool is now reserved in claimablePool = poolWei
5. Individual claims via `creditDecJackpotClaimBatch()`:
   - `_creditDecJackpotClaimCore()` splits 50/50 ETH/lootbox
   - ETH portion: `_addClaimableEth(account, ethPortion, rngWord)` -> `_creditClaimable()` (adds to claimableWinnings)
   - Lootbox portion: `claimablePool -= lootboxPortion` (removes from pool, goes to futurePrizePool)
   - If auto-rebuy: `claimablePool -= calc.ethSpent` (removes ticket conversion from pool)
   - **Net: claimablePool starts at poolWei, each claim deducts its non-claimable portions. Final claimablePool = sum of actual claimableWinnings credits.**

**Is there a gap?** NO.
- Pre-reserved: poolWei in claimablePool
- For each winner: ethPortion credited to claimableWinnings, lootboxPortion deducted from claimablePool
- If auto-rebuy fires on ethPortion: reserved credited to claimableWinnings, ethSpent deducted from claimablePool
- Net: claimablePool tracks exactly what's in claimableWinnings

### Specific Attack Vector Results

### Vector A: _creditClaimable / claimablePool Mismatch

**Attempt:** Find a caller of `_creditClaimable()` that forgets to update `claimablePool`.

**Result:** INFEASIBLE. All callers verified:

1. `_addClaimableEth()` (JackpotModule): Returns weiAmount or calc.reserved -> caller adds to claimablePool via liabilityDelta
2. `_addClaimableEth()` (EndgameModule): Returns weiAmount or adds calc.reserved internally + returns 0
3. `_addClaimableEth()` (DecimatorModule): Pre-reserved model, no return needed
4. `_queueWhalePassClaimCore()`: Adds remainder to claimablePool at line 90
5. `_processAutoRebuy()` (JackpotModule): Returns calc.reserved -> caller adds
6. `_processAutoRebuy()` (DecimatorModule): Deducts ethSpent from pre-reserved pool
7. handleGameOverDrain deity refunds: totalRefunded added at lines 90/113

**Defense:** Every credit path verified.

### Vector B: Auto-Rebuy Return Value Confusion

**Attempt:** Check if auto-rebuy return values cause double-counting or under-counting.

**Result:** INFEASIBLE. Three distinct patterns, all correct:

1. **JackpotModule**: `_addClaimableEth()` returns `calc.reserved` (the take-profit amount credited to claimable). `ethSpent` goes to next/futurePool. Caller adds return value to claimablePool. No double-count.

2. **EndgameModule**: `_addClaimableEth()` adds `calc.reserved` to claimablePool internally (line 251), returns 0. Caller adds 0. No double-count.

3. **DecimatorModule**: `_processAutoRebuy()` deducts `calc.ethSpent` from pre-reserved claimablePool (line 492). `calc.reserved` stays in the pre-reserved portion. Correct.

**Defense:** Each module handles the pattern consistently within its own model.

### Vector C: 1 Wei Sentinel Accumulation

**Attempt:** Can sum of sentinels exceed what claimablePool tracks?

**Result:** NOT A VULNERABILITY. Analysis:

- When a player first receives winnings: `claimableWinnings[player] += weiAmount`, `claimablePool += weiAmount`
- When player claims: `payout = amount - 1`, `claimablePool -= payout`
- After claim: `claimableWinnings[player] = 1`, claimablePool has 1 wei still reserved
- Sum of sentinels = number_of_players_who_claimed * 1 wei
- claimablePool retains these sentinel weis (only `payout = amount - 1` is deducted)

**The sentinel wei IS tracked in claimablePool.** When claimablePool is incremented by `weiAmount`, and only `amount - 1` is deducted on claim, 1 wei per player remains in claimablePool.

**Defense:** Sentinel pattern is balanced -- claimablePool keeps the 1 wei per active player.

### Vector D: Unchecked Arithmetic Overflow

**Attempt:** Can `unchecked { claimableWinnings[beneficiary] += weiAmount; }` overflow?

**Result:** INFEASIBLE. uint256 max = 1.16 * 10^77. Total ETH supply = 120M ETH = 1.2 * 10^26 wei. Would need 10^51x total ETH supply to overflow. Physically impossible.

**Defense:** Total ETH supply is negligible compared to uint256 max.

### Vector E: DecimatorModule Double-Credit

**Attempt:** Can the pre-reservation + individual claims result in double-counting?

**Result:** INFEASIBLE (detailed above in pre-reservation model trace). The key insight is:
- `runDecimatorJackpot()` returns 0 when winners exist (funds held)
- EndgameModule adds `spend = poolWei` to claimablePool (pre-reservation)
- Each claim either keeps the ETH portion in claimablePool (via _creditClaimable to claimableWinnings, balanced by pre-reserved pool) or deducts from claimablePool (lootbox, auto-rebuy conversion)
- When no winners: returns poolWei, spend = 0, nothing added to claimablePool
- When level already active (double-call): returns poolWei, spend = 0

**Defense:** Pre-reservation exactly equals total possible claims. Deductions on conversion maintain balance.

### Vector F: GameOver Deity Refund Overcredit

**Attempt:** Can deity pass refunds credit more than available in contract?

**Result:** INFEASIBLE.

- Level 0 game-over: refund = `deityPassPaidTotal[owner]` (exact amount paid)
- Level 1-9 game-over: refund = `DEITY_PASS_EARLY_GAMEOVER_REFUND * purchasedCount` (fixed 20 ETH * count)
- Deity pass price = 24 + T(n) ETH where T(n) = n*(n+1)/2, minimum 25 ETH for first pass
- Fixed refund of 20 ETH < 25 ETH minimum paid. Always under-refunds.
- `totalRefunded` is accumulated and added to `claimablePool` in a single write
- `available = totalFunds > claimablePool ? totalFunds - claimablePool : 0` (line 118) ensures vault distribution only sends excess

**Defense:** Fixed refund < minimum price. Level 0 refund = exact amount paid.

## Conclusion

No claimableWinnings overflow vulnerability found. The protocol maintains strict dual-accounting discipline through three distinct patterns:

1. **Return-value pattern** (JackpotModule): `_addClaimableEth()` returns claimableDelta, caller accumulates and writes to claimablePool once at end of distribution
2. **Internal-update pattern** (EndgameModule): `_addClaimableEth()` updates claimablePool internally when auto-rebuy fires, returns 0 to prevent double-counting
3. **Pre-reservation pattern** (DecimatorModule): claimablePool pre-reserved at jackpot resolution, individual claims deduct non-claimable conversions

All three patterns maintain the invariant: `sum(claimableWinnings[all]) <= claimablePool` at all times.

The 1 wei sentinel is properly balanced -- claimablePool retains the sentinel wei since only `amount - 1` is deducted on claims.
