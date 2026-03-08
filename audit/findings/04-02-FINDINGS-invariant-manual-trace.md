# Phase 4 Plan 02: claimablePool Invariant Manual Trace

**Requirement:** ACCT-01
**Invariant:** `address(this).balance + steth.balanceOf(this) >= claimablePool`
**Method:** Systematic manual trace of all claimablePool mutation sites across 7 modules
**Date:** 2026-03-06 (line numbers verified against current source)

---

## Methodology

For each claimablePool mutation site:
- **DECREMENT sites:** Verify the ETH/stETH either leaves the contract or moves to a non-claimable pool, maintaining the invariant.
- **INCREMENT sites:** Verify ETH/stETH backing exists (from prize pools, msg.value, or yield surplus), and verify claimableWinnings is also incremented by the same amount (or a documented exception applies).
- **READ-ONLY sites:** Confirm no mutation occurs.

**Site inventory:** Exhaustive grep `claimablePool -=` and `claimablePool +=` across all contract files. Result: 6 decrements, 10 increments, 2 read-only guards = 18 total sites.

---

## DECREMENT Sites (6 mutations)

### D1. DegenerusGame.sol:1042 -- `_processMintPayment`

```solidity
claimablePool -= claimableUsed;  // Line 1042
```

**Context:** Player spends claimable winnings to pay for ticket purchases. The `claimableUsed` amount is deducted from both `claimableWinnings[player]` (lines 1012/1030) and `claimablePool` (line 1042). The ETH backing remains in the contract -- it is redirected to `prizeContribution` (line 1036: `prizeContribution = msg.value + claimableUsed`) which flows into `nextPrizePool`/`futurePrizePool` via `recordMint`.

**claimableWinnings delta:** `-claimableUsed` (lines 1012/1030)
**claimablePool delta:** `-claimableUsed` (line 1042)
**ETH backing:** ETH stays in contract (internal pool transfer). `claimablePool` goes down, but `address(this).balance` is unchanged.

**Verdict: SAFE.** Both claimablePool and claimableWinnings decrease by the same amount. The ETH remains in the contract, moving to prize pools. Invariant maintained.

---

### D2. DegenerusGame.sol:1429 -- `_claimWinningsInternal`

```solidity
if (finalSwept) revert E();       // Line 1421 (blocks claims after final sweep)
// ...
claimableWinnings[player] = 1;    // Line 1426 (sentinel)
claimablePool -= payout;           // Line 1429
// Then: external ETH/stETH transfer to player
```

**Context:** Player withdraws claimable winnings. CEI pattern: state updated before external call.

**claimableWinnings delta:** Set to 1 (sentinel), effective `-payout`
**claimablePool delta:** `-payout`
**ETH backing:** `payout` amount of ETH or stETH leaves the contract via `_payoutWithEthFallback`/`_payoutWithStethFallback`. Both `claimablePool` and `address(this).balance + steth.balanceOf(this)` decrease by `payout`.

**Verdict: SAFE.** Both sides of the invariant decrease by exactly `payout`. Invariant maintained.

---

### D3. DecimatorModule.sol:492 -- Decimator auto-rebuy ticket conversion

```solidity
claimablePool -= calc.ethSpent;  // Line 492
```

**Context:** When a decimator jackpot winner has auto-rebuy enabled, their ETH winnings are converted to tickets. The `calc.ethSpent` portion goes to `futurePrizePool` (line 481) or `nextPrizePool` (line 483). The pool was pre-reserved in `claimablePool` by the EndgameModule (line 202) or GameOverModule (line 133) when the decimator jackpot was initially funded. This decrement removes the ticket-converted portion from the pre-reservation.

**claimableWinnings delta:** No change for the ethSpent portion (tickets queued instead). If `calc.reserved != 0`, `claimableWinnings[beneficiary] += calc.reserved` (line 488 via `_creditClaimable`).
**claimablePool delta:** `-calc.ethSpent` (line 492). Note: `calc.reserved` is NOT removed from claimablePool (it stays reserved for the take-profit portion).
**ETH backing:** ETH stays in contract (moves from claimablePool reservation to `futurePrizePool`/`nextPrizePool`). `address(this).balance` unchanged.

**Verdict: SAFE.** claimablePool decreases by ethSpent; ETH is still in the contract but now in prize pools, not claimable. Invariant maintained (left side unchanged, right side decreased).

---

### D4. DecimatorModule.sol:539 -- Decimator lootbox conversion

```solidity
claimablePool -= lootboxPortion;  // Line 539
```

**Context:** In `_creditDecJackpotClaimCore`, a decimator claim is split 50/50: half ETH (credited via `_addClaimableEth`, line 536) and half lootbox (line 539-540). The lootbox portion is removed from `claimablePool` because it is converted to lootbox tickets (not claimable ETH). The lootbox portion is later added to `futurePrizePool` by the caller (line 430: `futurePrizePool += lootboxPortion`).

**claimableWinnings delta:** No change for lootbox portion (player gets lootbox tickets instead)
**claimablePool delta:** `-lootboxPortion`
**ETH backing:** ETH stays in contract (moves from claimable reservation to `futurePrizePool`). `address(this).balance` unchanged.

**Verdict: SAFE.** claimablePool decreases; ETH remains in contract in a non-claimable pool. Invariant maintained.

---

### D5. DegeneretteModule.sol:585 -- ETH bet using claimable winnings

```solidity
claimableWinnings[player] -= fromClaimable;  // Line 584
claimablePool -= fromClaimable;               // Line 585
// Then: futurePrizePool += totalBet;          // Line 589
```

**Context:** When a player places a Degenerette ETH bet partially or fully from claimable winnings, the claimable amount is consumed and the bet amount moves to `futurePrizePool`.

**claimableWinnings delta:** `-fromClaimable` (line 584)
**claimablePool delta:** `-fromClaimable` (line 585)
**ETH backing:** ETH stays in contract (moves to `futurePrizePool`). `address(this).balance` unchanged.

**Verdict: SAFE.** Both claimablePool and claimableWinnings decrease symmetrically. ETH remains in contract. Invariant maintained.

---

### D6. MintModule.sol:658 -- Lootbox shortfall from claimable

```solidity
claimableWinnings[buyer] = claimable - shortfall;  // Line 656
claimablePool -= shortfall;                          // Line 658
```

**Context:** When lootbox purchase cost exceeds remaining ETH from msg.value, the shortfall is pulled from `claimableWinnings[buyer]`. The shortfall ETH is redirected to lootbox payment flows (stays in contract).

**Note:** This site was not in the original research inventory (which listed only 5 decrements). Discovered via exhaustive `claimablePool -=` grep across all contracts.

**claimableWinnings delta:** `-shortfall` (line 656)
**claimablePool delta:** `-shortfall` (line 658)
**ETH backing:** ETH stays in contract (used for lootbox purchase internally).

**Verdict: SAFE.** Symmetric decrement. ETH remains in contract. Invariant maintained.

---

## INCREMENT Sites (10 mutations)

### I1. PayoutUtils.sol:90 -- `_queueWhalePassClaimCore` remainder

```solidity
claimableWinnings[winner] += remainder;  // Line 88
claimablePool += remainder;               // Line 90
```

**Context:** When a jackpot payout is processed via `_queueWhalePassClaimCore`, the amount is divided into whale pass claim units (`HALF_WHALE_PASS_PRICE`). The `remainder` that doesn't fill a full whale pass unit is credited directly to claimable.

**ETH backing source:** The ETH was taken from `currentPrizePool` or `futurePrizePool` by the jackpot distribution logic BEFORE calling this function. The caller already removed the ETH from the source pool, so the backing exists in `address(this).balance` (or stETH).

**claimableWinnings delta:** `+remainder` (line 88)
**claimablePool delta:** `+remainder` (line 90)
**Symmetry:** YES -- both increment by the same amount.

**Verdict: SAFE.** ETH backing exists from prize pool drawdown. Symmetric increment. Invariant maintained.

**Note on whale pass full units:** The `fullHalfPasses` portion is queued as whale pass claims (line 84) and NOT added to claimablePool. These whale pass claims are eventually fulfilled by lootbox ticket conversions, where the ETH value stays in prize pools (e.g., `futurePrizePool += whalePassSpent` in JackpotModule line 1814). This is correct -- the whale pass ETH is NOT claimable ETH.

---

### I2. EndgameModule.sol:202 -- `runRewardJackpots` BAF/Decimator credits

```solidity
claimablePool += claimableDelta;  // Line 202
```

**Context:** In `runRewardJackpots`, the `claimableDelta` accumulates claimable amounts from both BAF jackpot (via `_runBafJackpot`, line 154) and Decimator jackpot (lines 176/193). For BAF, `claimableDelta += claimed` where `claimed` is the return value of `_runBafJackpot` which tracks ETH credits via `_addClaimableEth` (returns `claimableDelta`). For Decimator, `claimableDelta += spend` where `spend = decPoolWei - returnWei`.

**ETH backing source (BAF):** `futurePoolLocal -= bafPoolWei` (line 148). The full BAF pool is first removed from futurePrizePool. ETH credited to winners comes from this pool.

**ETH backing source (Decimator):** `futurePoolLocal -= spend` (line 175/191). The decimator spend is removed from futurePrizePool.

**BAF path analysis:**
- `_runBafJackpot` returns `claimableDelta` which is the sum of all `_addClaimableEth` return values.
- `_addClaimableEth` (EndgameModule version, line 217) returns `weiAmount` when no auto-rebuy, `0` when auto-rebuy converts all (and increments claimablePool internally at line 251), or falls through to the normal credit path.
- `_creditClaimable` increments `claimableWinnings[beneficiary]` by the same amount.
- Symmetry: `claimablePool += claimableDelta` matches `sum(claimableWinnings increments)` for the non-auto-rebuy portion. Auto-rebuy portion is handled by I3.

**Decimator pre-reservation:**
- For decimator, `runDecimatorJackpot` returns 0 when claims exist (all funds held). `spend = decPoolWei - 0 = decPoolWei`.
- `claimableDelta += spend` reserves the FULL decimator pool in claimablePool.
- Individual player `claimableWinnings` are NOT incremented yet (they claim later via `claimDecimatorJackpot`).
- This creates a temporary asymmetry: `claimablePool > sum(claimableWinnings)`.
- **See Open Question 1 below for decimator pre-reservation cleanup analysis.**

**claimableWinnings delta:** BAF: `+weiAmount` per winner (via `_creditClaimable`). Decimator: deferred to claim time.
**claimablePool delta:** `+claimableDelta` (BAF claimed + decimator spend)

**Verdict: SAFE for BAF. SAFE for Decimator (pre-reservation is correct, see OQ1).** The invariant `balance + stETH >= claimablePool` holds because the ETH was removed from futurePrizePool (which is an accounting variable only, not a separate balance). The ETH is in `address(this).balance` or stETH, and `claimablePool` correctly tracks what is owed.

---

### I3. EndgameModule.sol:251 -- `_addClaimableEth` auto-rebuy take profit

```solidity
claimablePool += calc.reserved;  // Line 251
```

**Context:** This is the AUTO-REBUY PATH -- the most complex path. When `_addClaimableEth` in EndgameModule is called and the beneficiary has auto-rebuy enabled:

1. `_calcAutoRebuy` (PayoutUtils.sol) computes: `reserved` (take-profit portion), `rebuyAmount = weiAmount - reserved`, `ethSpent` (tickets purchased), and dust = `rebuyAmount - ethSpent`.
2. If `calc.hasTickets` is true:
   - `calc.ethSpent` goes to `futurePrizePool` or `nextPrizePool` (lines 241-244) -- NOT claimable
   - `calc.reserved` goes to `_creditClaimable(beneficiary, calc.reserved)` (line 250) -- claimable
   - `claimablePool += calc.reserved` (line 251) -- matches the creditClaimable call
   - Returns 0 (line 260) -- the caller does NOT add to claimablePool again

**Take-profit calculation (PayoutUtils.sol lines 49-52):**
```solidity
if (state.takeProfit != 0) {
    c.reserved = (weiAmount / state.takeProfit) * state.takeProfit;
}
c.rebuyAmount = weiAmount - c.reserved;
```
The `takeProfit` field is a divisor/modulus. `reserved = floor(weiAmount / takeProfit) * takeProfit` rounds `weiAmount` down to the nearest multiple of `takeProfit`. The fractional remainder (`rebuyAmount`) is what goes to auto-rebuy ticket conversion.

**Dust analysis:** `dust = rebuyAmount - ethSpent = (weiAmount - reserved) - (baseTickets * ticketPrice)`. Since `baseTickets = rebuyAmount / ticketPrice` (floor division), `ethSpent = baseTickets * ticketPrice <= rebuyAmount`. So `dust = rebuyAmount % ticketPrice`. This dust is NEITHER added to claimablePool NOR to any prize pool. It effectively stays in the contract as unaccounted ETH.

**Invariant impact of dust:** Dust remains in `address(this).balance` but is not tracked in any pool variable. This means `address(this).balance + stETH > claimablePool + currentPrizePool + nextPrizePool + futurePrizePool`. The invariant `balance + stETH >= claimablePool` is STRENGTHENED (not weakened) by dust.

**claimableWinnings delta:** `+calc.reserved` (via `_creditClaimable`)
**claimablePool delta:** `+calc.reserved` (line 251)
**Return value:** 0 (so caller does NOT double-increment claimablePool)
**Symmetry:** YES for reserved portion. Rebuy portion goes to prize pools. Dust stays in contract.

**Verdict: SAFE.** claimablePool only increments by the take-profit portion, which is exactly what's credited to claimableWinnings. The rebuy portion goes to prize pools (not claimable). Dust stays in contract (strengthens invariant). Invariant maintained.

---

### I4. JackpotModule.sol:948 -- Yield surplus stakeholder credits

```solidity
if (claimableDelta != 0) claimablePool += claimableDelta;  // Line 948
```

**Context:** In `_distributeYieldSurplus` (called from `consolidatePrizePools`), yield surplus (stETH appreciation above obligations) is distributed: 23% to VAULT, 23% to DGNRS, ~46% to futurePrizePool.

**ETH backing source:** `yieldPool = totalBal - obligations` (line 931) where `obligations = currentPrizePool + nextPrizePool + claimablePool + futurePrizePool`. The yield surplus is ETH/stETH that exists in the contract beyond all tracked obligations. It is REAL backing.

**claimableDelta composition:** Sum of `_addClaimableEth(VAULT, stakeholderShare, rngWord)` + `_addClaimableEth(DGNRS, stakeholderShare, rngWord)`. Each `_addClaimableEth` call either returns `weiAmount` (if no auto-rebuy, `_creditClaimable` called) or `calc.reserved` (if auto-rebuy). The returned value is exactly what was credited to `claimableWinnings`.

**claimableWinnings delta:** `+stakeholderShare` each for VAULT and DGNRS (or `calc.reserved` if auto-rebuy)
**claimablePool delta:** `+claimableDelta` (sum of the above)
**Symmetry:** YES

**Verdict: SAFE.** Yield surplus is real ETH/stETH above all obligations. Symmetric increment. Invariant maintained.

---

### I5. JackpotModule.sol:1484 -- Daily jackpot ETH credits (mid-chunk exit)

```solidity
if (liabilityDelta != 0) {
    claimablePool += liabilityDelta;  // Line 1484
}
return (paidEth, false);  // Incomplete -- will resume
```

**Context:** In `_processDailyEthChunk`, when the units budget is exhausted mid-bucket, `liabilityDelta` accumulates all `_addClaimableEth` return values for winners processed so far. The cursor is saved for resumption.

**ETH backing source:** Daily jackpot ETH comes from `currentPrizePool` which was debited by the caller. The backing ETH is in the contract.

**claimableDelta composition:** `liabilityDelta += claimableDelta` (line 1503) where `claimableDelta` is the return value of `_addClaimableEth(w, perWinner, entropyState)`. This equals `perWinner` if no auto-rebuy, or `calc.reserved` if auto-rebuy.

**claimableWinnings delta:** Sum of all `_creditClaimable` calls made during the chunk.
**claimablePool delta:** `+liabilityDelta`
**Symmetry:** YES

**Verdict: SAFE.** ETH backing from currentPrizePool. Symmetric increment. Invariant maintained.

---

### I6. JackpotModule.sol:1516 -- Daily jackpot ETH credits (complete)

```solidity
if (liabilityDelta != 0) {
    claimablePool += liabilityDelta;  // Line 1516
}
```

**Context:** Same as I5 but for the complete (non-interrupted) path. When all buckets are processed without hitting the units budget, liabilityDelta is committed.

**Analysis:** Identical to I5. ETH from currentPrizePool, symmetric increment.

**Verdict: SAFE.** Invariant maintained.

---

### I7. JackpotModule.sol:1564 -- Level/terminal jackpot ETH credits

```solidity
if (ctx.liabilityDelta != 0) {
    claimablePool += ctx.liabilityDelta;  // Line 1564
}
```

**Context:** In `_distributeJackpotEth`, level and terminal jackpot ETH is distributed across 4 trait buckets. Each bucket calls `_processOneBucket` which calls `_resolveTraitWinners`. The `liabilityDelta` accumulates across all 4 buckets.

**ETH backing source:** `ethPool` parameter comes from `currentPrizePool` (for level jackpots) or from `remaining` funds in GameOverModule's `handleGameOverDrain` (for terminal jackpot via `runTerminalJackpot`). In both cases, the backing ETH is in the contract.

**Note:** The GameOverModule's BAF terminal jackpot (line 142-143) goes through `runTerminalJackpot` which delegates to this function. The `claimablePool` update for game-over BAF happens HERE (I7), not in GameOverModule itself. GameOverModule line 144 comment confirms: "claimablePool already updated inside JackpotModule._distributeJackpotEth".

**claimableWinnings delta:** Sum of all per-winner credits via `_addClaimableEth` and `_creditJackpot`.
**claimablePool delta:** `+ctx.liabilityDelta`
**Symmetry:** YES -- `ctx.liabilityDelta` accumulates from `_resolveTraitWinners` which returns `totalLiability` (line 1754), which is the sum of all `_addClaimableEth` return values.

**Verdict: SAFE.** ETH backing from prize pools. Symmetric increment. Invariant maintained.

---

### I8. DegeneretteModule.sol:1173 -- Degenerette ETH win credit

```solidity
claimablePool += weiAmount;                    // Line 1173
_creditClaimable(beneficiary, weiAmount);       // Line 1174
```

**Context:** In DegeneretteModule's `_addClaimableEth` (a simplified version without auto-rebuy), when a player wins a Degenerette ETH bet, the ETH portion of the payout is credited.

**ETH backing source:** The ETH comes from `futurePrizePool` which was decremented in the bet resolution function. The ETH was already in the contract when the bet was placed (ETH bets go to `futurePrizePool` at line 589).

**claimableWinnings delta:** `+weiAmount` (via `_creditClaimable` line 1174)
**claimablePool delta:** `+weiAmount` (line 1173)
**Symmetry:** YES

**Verdict: SAFE.** ETH backing from futurePrizePool drawdown. Symmetric increment. Invariant maintained.

---

### I9. GameOverModule.sol:107 -- Deity pass refund on game over

```solidity
claimableWinnings[owner] += refund;    // Line 95
totalRefunded += refund;                // Line 96
// ... (loop iterates all deity pass owners)
claimablePool += totalRefunded;         // Line 107
```

**Context:** When game over occurs at levels 0-9 (early game over), deity pass holders receive refunds. The refund amount is `DEITY_PASS_EARLY_GAMEOVER_REFUND * purchasedCount` per owner, budget-capped by `available = totalFunds - claimablePool` (line 83).

**ETH backing source:** The deity pass purchase ETH was deposited into `futurePrizePool` at purchase time (via WhaleModule). At game over, `totalFunds = address(this).balance + steth.balanceOf(address(this))` (line 78). The budget cap ensures refunds cannot exceed available non-claimable funds.

**Critical check:** Can `totalRefunded` exceed available funds?
- The budget variable starts at `totalFunds - claimablePool` (line 83)
- Each refund is capped at `budget` (line 90-91)
- After each refund, `budget -= refund` (line 97)
- Loop breaks when `budget == 0` (line 100)
- Therefore `totalRefunded <= totalFunds - claimablePool`, guaranteeing solvency.

**claimableWinnings delta:** `+refund` per owner
**claimablePool delta:** `+totalRefunded` (sum of all refunds)
**Symmetry:** YES -- `totalRefunded = sum(refunds) = sum(claimableWinnings increments)`

**Verdict: SAFE.** ETH backing from original deity pass deposits, budget-capped. Symmetric increment. Invariant maintained.

---

### I10. GameOverModule.sol:133 -- Decimator jackpot on game over

```solidity
uint256 decSpend = decPool - decRefund;
if (decSpend != 0) {
    claimablePool += decSpend;           // Line 133
}
```

**Context:** During `handleGameOverDrain`, 10% of remaining non-claimable funds are allocated to a decimator jackpot via `runDecimatorJackpot`. If there are qualifying winners, `decRefund = 0` and the full `decPool` is reserved in claimablePool for individual player claims.

**ETH backing source:** `decPool = remaining / 10` where `remaining = available = totalFunds - claimablePool`. The decimator pool comes from non-claimable funds.

**Decimator pre-reservation:** `claimablePool += decSpend` reserves the FULL decimator pool in claimablePool. Individual `claimableWinnings` increments happen when players call `claimDecimatorJackpot`. This is the same pre-reservation pattern as I2 (EndgameModule line 202).

**Note on BAF terminal jackpot:** The remaining 90% (+ decimator refund) is distributed via `runTerminalJackpot` (line 142-143) which delegates to JackpotModule's `_distributeJackpotEth`. The claimablePool update for that path happens at I7, not here. GameOverModule does NOT directly increment claimablePool for the BAF portion.

**Decimator symmetry (temporary asymmetry):** `claimablePool += decSpend` but `sum(claimableWinnings increments) = 0` at this point. See Open Question 1 for cleanup analysis.

**Verdict: SAFE.** The pre-reservation is correct -- `claimablePool` holds funds for future individual claims. The invariant `balance + stETH >= claimablePool` holds because the ETH is in the contract.

---

## READ-ONLY Sites (2)

### R1. DegenerusGame.sol:1831 -- `adminStakeEthForStEth`

```solidity
uint256 reserve = claimablePool;           // Line 1831
if (ethBal <= reserve) revert E();         // Line 1832
uint256 stakeable = ethBal - reserve;      // Line 1833
```

**Context:** Admin staking function reads `claimablePool` to ensure only non-claimable ETH is staked into stETH.

**Mutation:** None. Read-only guard.
**Verdict: NOT A MUTATION. Guard correctly preserves invariant by preventing staking of claimable ETH.**

---

### R2. AdvanceModule.sol:1011 -- `_autoStakeExcessEth`

```solidity
uint256 ethBal = address(this).balance;    // Line 1010
uint256 reserve = claimablePool;           // Line 1011
if (ethBal <= reserve) return;             // Line 1012
uint256 stakeable = ethBal - reserve;      // Line 1013
try steth.submit{value: stakeable}(address(0)) returns (uint256) {} catch {}  // Line 1014
```

**Context:** Auto-stake converts excess ETH to stETH via Lido. Only non-claimable ETH is staked.

**Invariant impact:** `address(this).balance` decreases by `stakeable`, but `steth.balanceOf(address(this))` increases by approximately `stakeable` (minus potential 1-2 wei rounding from Lido share conversion). Since `stakeable = ethBal - claimablePool`, the invariant `balance + stETH >= claimablePool` becomes `(ethBal - stakeable) + (stETH + ~stakeable) >= claimablePool` = `claimablePool + stETH + ~stakeable >= claimablePool`. Safe.

**Verdict: NOT A MUTATION. Guard correctly preserves invariant. Lido 1-2 wei rounding loss is negligible and absorbed by yield surplus.**

---

## Summary Table

| # | File:Line | Operation | claimablePool Delta | claimableWinnings Delta | ETH Backing | Verdict |
|---|-----------|-----------|--------------------|-----------------------|-------------|---------|
| D1 | Game.sol:1042 | _processMintPayment spending | -claimableUsed | -claimableUsed | Stays in contract (to prize pools) | SAFE |
| D2 | Game.sol:1428 | _claimWinningsInternal withdrawal | -payout | -payout (set to sentinel) | Leaves contract (ETH/stETH transfer) | SAFE |
| D3 | Decimator.sol:492 | Auto-rebuy ticket conversion | -calc.ethSpent | 0 (tickets queued) | Stays in contract (to prize pools) | SAFE |
| D4 | Decimator.sol:539 | Lootbox conversion | -lootboxPortion | 0 (lootbox tickets) | Stays in contract (to futurePrizePool) | SAFE |
| D5 | Degenerette.sol:585 | ETH bet from claimable | -fromClaimable | -fromClaimable | Stays in contract (to futurePrizePool) | SAFE |
| D6 | MintModule.sol:658 | Lootbox shortfall | -shortfall | -shortfall | Stays in contract (to lootbox flows) | SAFE |
| I1 | PayoutUtils.sol:90 | Whale pass remainder | +remainder | +remainder | From prize pool drawdown | SAFE |
| I2 | Endgame.sol:202 | BAF/Decimator credits | +claimableDelta | +claimed (BAF) / deferred (Dec) | From futurePrizePool | SAFE |
| I3 | Endgame.sol:251 | Auto-rebuy take profit | +calc.reserved | +calc.reserved | From prize pool (caller) | SAFE |
| I4 | Jackpot.sol:948 | Yield surplus credits | +claimableDelta | +stakeholderShare (per entity) | From yield surplus | SAFE |
| I5 | Jackpot.sol:1484 | Daily jackpot (mid-chunk) | +liabilityDelta | +sum(perWinner credits) | From currentPrizePool | SAFE |
| I6 | Jackpot.sol:1516 | Daily jackpot (complete) | +liabilityDelta | +sum(perWinner credits) | From currentPrizePool | SAFE |
| I7 | Jackpot.sol:1564 | Level/terminal jackpot | +ctx.liabilityDelta | +sum(per-winner credits) | From currentPrizePool or remaining | SAFE |
| I8 | Degenerette.sol:1173 | ETH win credit | +weiAmount | +weiAmount | From futurePrizePool | SAFE |
| I9 | GameOver.sol:107 | Deity pass refund | +totalRefunded | +sum(refunds) | From original deity deposits | SAFE |
| I10 | GameOver.sol:133 | Decimator game-over jackpot | +decSpend | deferred (pre-reservation) | From available non-claimable | SAFE |
| R1 | Game.sol:1831 | adminStakeEthForStEth guard | 0 (read-only) | 0 | N/A | N/A |
| R2 | Advance.sol:1011 | _autoStakeExcessEth guard | 0 (read-only) | 0 | N/A | N/A |

---

## Open Questions from Research -- Resolved

### OQ1: Decimator Pre-Reservation Cleanup

**Question:** Does `claimablePool == sum(claimableWinnings)` restore after all decimator claims?

**Answer: YES, with a caveat.**

The lifecycle:
1. `runDecimatorJackpot(poolWei, lvl, rngWord)` returns 0 (all funds held). Caller adds `poolWei` to `claimablePool` (EndgameModule line 202, or GameOverModule line 133).
2. At this point: `claimablePool` increased by `poolWei`, but no individual `claimableWinnings` incremented. Temporary asymmetry.
3. Players call `claimDecimatorJackpot(lvl)`:
   - `_consumeDecClaim` returns `amountWei` (pro-rata share based on player's burn amount vs total).
   - Normal path: `_creditDecJackpotClaimCore` splits 50/50: ETH half via `_addClaimableEth` (credits `claimableWinnings` via `_creditClaimable`, does NOT increment `claimablePool` because Decimator's `_addClaimableEth` doesn't), lootbox half decrements `claimablePool -= lootboxPortion` (line 539).
   - Game-over path: full `amountWei` goes to `_addClaimableEth` (credits `claimableWinnings` only, `claimablePool` unchanged).

**Normal claim path accounting per player claim of `amountWei`:**
- `ethPortion = amountWei >> 1`
- `lootboxPortion = amountWei - ethPortion`
- `claimableWinnings[player] += ethPortion` (via `_addClaimableEth` -> `_creditClaimable`, assuming no auto-rebuy)
- `claimablePool -= lootboxPortion` (line 539)
- Net claimablePool effect per claim: `-lootboxPortion`
- Net claimableWinnings effect per claim: `+ethPortion`

After ALL winners claim: `claimablePool` net = `poolWei - sum(lootboxPortions)` = `poolWei - sum(amountWei - ethPortion)` = `sum(ethPortion)`. And `sum(claimableWinnings increments)` = `sum(ethPortion)`. **Equality restored.**

**With auto-rebuy:** If a decimator claimant has auto-rebuy enabled, `_processAutoRebuy` returns true. In that case:
- `claimablePool -= calc.ethSpent` (line 492) removes the ticket portion
- `calc.reserved` goes to `_creditClaimable` (but claimablePool is NOT incremented -- it was pre-reserved)
- Net claimablePool effect: `-calc.ethSpent` (additional decrement beyond lootboxPortion)
- This is correct: auto-rebuy converts MORE of the pre-reservation to prize pools

**Caveat -- unclaimed funds:** If some winners never claim, their share stays in `claimablePool` without a corresponding `claimableWinnings` entry. Furthermore, when the next decimator runs, `lastDecClaimRound` is overwritten (DecimatorModule line 349), making old claims impossible. The unclaimed `claimablePool` reservation persists permanently.

> **POST-AUDIT UPDATE:** `handleFinalSweep` was rewritten post-audit. It now sets `claimablePool = 0` and sweeps ALL remaining funds. Unclaimed decimator reservations are no longer permanently locked -- they are forfeited and swept to vault/DGNRS after the 30-day post-gameOver window. See 04-06 Section 3 for details.

**Invariant impact of unclaimed decimator funds (pre-sweep):** `claimablePool` is slightly higher than `sum(claimableWinnings)`. This means the contract holds MORE backing than needed for actual claims. The invariant `balance + stETH >= claimablePool` still holds because the ETH is in the contract. During the 30-day post-gameOver claim window, the unclaimed portion stays reserved. After `handleFinalSweep` executes, `claimablePool` is zeroed and all remaining funds (including unclaimed decimator reservations) are swept to vault/DGNRS.

**Severity: INFORMATIONAL.** The invariant is maintained. The locked funds issue is a minor capital efficiency concern, not a security vulnerability. In practice, the amounts are likely small relative to total pool size.

---

### OQ2: Auto-Rebuy Dust Handling

**Question:** What happens to `rebuyAmount - ethSpent` (the dust)?

**Answer:** The dust (`rebuyAmount - calc.ethSpent`) is NOT tracked in any pool variable. It remains in `address(this).balance` as unaccounted ETH.

**Trace (PayoutUtils.sol lines 49-67):**
```
reserved = floor(weiAmount / takeProfit) * takeProfit     [line 50]
rebuyAmount = weiAmount - reserved                         [line 52]
ethSpent = floor(rebuyAmount / ticketPrice) * ticketPrice  [line 67]
dust = rebuyAmount - ethSpent = rebuyAmount % ticketPrice
```

- `reserved` -> `claimablePool` + `claimableWinnings` (tracked)
- `ethSpent` -> `futurePrizePool` or `nextPrizePool` (tracked)
- `dust` -> nowhere (untracked)

**Invariant impact:** Dust strengthens the invariant. `address(this).balance` is higher than `sum(all pool variables)`. The dust accumulates over time as micro-amounts (typically < 1 ticket price per auto-rebuy event). Eventually, `_autoStakeExcessEth` will stake this dust into stETH, or `handleFinalSweep` will sweep it to vault/DGNRS (post-audit: sweeps ALL remaining `totalFunds` after zeroing `claimablePool`).

**Severity: INFORMATIONAL.** Dust is safe. Untracked ETH makes the contract more solvent.

---

### OQ3: Does Any Path Credit claimableWinnings WITHOUT Incrementing claimablePool?

**Answer: YES, but only in intentional pre-reservation patterns.**

1. **Decimator claim path (normal mode):** `_creditDecJackpotClaimCore` -> `_addClaimableEth` (DecimatorModule line 508) -> `_creditClaimable` increments `claimableWinnings` without incrementing `claimablePool`. This is correct because `claimablePool` was pre-incremented when the decimator jackpot was funded (EndgameModule line 202 or GameOverModule line 133).

2. **Decimator claim path (game-over mode):** `_addClaimableEth` -> `_creditClaimable` increments `claimableWinnings` without incrementing `claimablePool`. Same pre-reservation logic.

3. **Decimator auto-rebuy path:** When auto-rebuy converts the ethSpent portion, `_processAutoRebuy` returns true without calling `_creditClaimable` for the ethSpent portion. Instead, `claimablePool -= calc.ethSpent` (line 492) removes that portion from the pre-reservation. The `calc.reserved` take-profit IS credited via `_creditClaimable` but claimablePool is NOT incremented (it was already pre-reserved). Correct.

4. **No unintentional path exists.** Every other `_creditClaimable` call is paired with either:
   - A direct `claimablePool += weiAmount` in the same function (DegeneretteModule line 1173, PayoutUtils line 90), OR
   - A returned `claimableDelta`/`liabilityDelta` value that the caller adds to `claimablePool` (EndgameModule line 202, JackpotModule lines 948/1484/1516/1564).

**Verdict: No invariant violation.** All asymmetric paths are intentional pre-reservation patterns where `claimablePool` was already incremented by a caller.

---

## ACCT-01 Verdict

### PASS

The core accounting invariant `address(this).balance + steth.balanceOf(this) >= claimablePool` holds across all 18 claimablePool sites (6 decrements, 10 increments, 2 read-only guards).

**Evidence:**
- All 6 DECREMENT sites either (a) send ETH/stETH out of the contract by the same amount (D2), or (b) move ETH from claimablePool to non-claimable pools within the contract (D1, D3, D4, D5, D6). Both preserve the invariant.
- All 10 INCREMENT sites have verified ETH/stETH backing from prize pools, yield surplus, or original deposits. Each increment is either symmetric with a `claimableWinnings` increment, or is a documented pre-reservation (decimator) where individual claims are deferred.
- Both READ-ONLY sites correctly guard against staking claimable ETH.
- Auto-rebuy dust is untracked, which STRENGTHENS the invariant.
- Decimator pre-reservation creates temporary asymmetry that is resolved by individual claims. Unclaimed portions remain safely in claimablePool (locked, not exploitable).
- No unintentional path credits claimableWinnings without a corresponding claimablePool increment.

**Informational findings:**
1. **Decimator unclaimed funds lock:** If decimator winners never claim before the next decimator runs, their `claimablePool` reservation persists permanently without a corresponding `claimableWinnings` entry. This is a minor capital efficiency concern (ETH locked in `claimablePool` that can never be claimed or swept). Not a security issue.
2. **Auto-rebuy dust accumulation:** Fractional wei from auto-rebuy calculations accumulates as untracked ETH. Eventually staked or swept (post-audit: `handleFinalSweep` sweeps ALL remaining funds). Not a security issue.
3. **stETH transfer rounding (Lido 1-2 wei):** When stETH is transferred to players, 1-2 wei may be retained by the contract due to share-based rounding. This STRENGTHENS the invariant. Not a security issue.
4. **Research inventory correction:** Research listed 5 decrement sites; actual count is 6 (MintModule.sol:658 lootbox shortfall was missing). Research listed line numbers from an older codebase revision; all line references in this document are verified against current source.
