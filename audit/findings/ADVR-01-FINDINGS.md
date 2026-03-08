# ADVR-01 Findings: ETH Extraction

**Warden:** "ETH Drainer" (whale warden persona)
**Brief:** Prove ETH solvency invariant can be violated
**Scope:** All ETH inflow/outflow paths across DegenerusGame and 10 delegatecall modules
**Information:** Source code only (no prior audit results)
**Session Date:** 2026-03-05

## Summary

**Result: No Medium+ findings discovered.**

After exhaustive tracing of all ETH inflows (7 entry points) and outflows (8 transfer sites), no path was found that violates the solvency invariant `address(game).balance + steth.balanceOf(game) >= claimablePool`. Every ETH outflow is gated by a properly-maintained accounting variable, and the CEI pattern is consistently applied across all payout sites.

## Methodology

1. Mapped every `msg.value` entry point and traced ETH routing to pool variables
2. Mapped every `.call{value:}` exit point and verified the accounting source
3. Traced every `claimableWinnings[x] +=` site and verified matching `claimablePool +=`
4. Analyzed stETH rebasing behavior relative to solvency invariant
5. Checked admin functions for reserve protection bypass

## ETH Inflow Analysis

| Entry Point | ETH Destination | Accounting |
|------------|-----------------|------------|
| `purchase()` via MintModule | nextPrizePool (90%) + futurePrizePool (10%) | Splits computed from `amount`, BPS sum = 10000, verified |
| `purchaseWhaleBundle()` via WhaleModule | futurePrizePool + nextPrizePool | `totalPrice = unitPrice * quantity`, `msg.value == totalPrice` enforced (line 242) |
| `purchaseLazyPass()` via WhaleModule | futurePrizePool + nextPrizePool | `msg.value == totalPrice` enforced (line 397) |
| `purchaseDeityPass()` via WhaleModule | futurePrizePool + nextPrizePool | Price = 24 + T(n), `msg.value` validated |
| `placeFullTicketBets()` via DegeneretteModule | From claimable or msg.value | ETH bets paid from claimable (decrements claimablePool) or msg.value (stays in contract) |
| `adminSwapEthForStEth()` | Value-neutral: ETH in, stETH out | `msg.value == amount` enforced, stETH transfer of equal amount |
| `receive()` | futurePrizePool | Direct addition, no accounting gap |

**Assessment:** All inflows are exact-amount validated. No path allows ETH to enter without being tracked in a pool variable.

## ETH Outflow Analysis

### Site 1: `_payoutWithStethFallback()` (DegenerusGame.sol:2015-2042)

> **POST-AUDIT UPDATE:** `refundDeityPass()` was removed entirely from the codebase. This transfer site is now called only from `_claimWinningsInternal()`.

Called from `_claimWinningsInternal()` and `refundDeityPass()`.

**claimWinnings path:**
- CEI pattern: `claimableWinnings[player] = 1` (Effect), `claimablePool -= payout` (Effect), THEN `_payoutWithStethFallback(player, payout)` (Interaction)
- `payout = amount - 1` where `amount = claimableWinnings[player]` which was previously credited
- **Defense:** payout is exactly what was credited minus 1 wei sentinel. claimablePool is decremented by exact payout amount. Cannot extract more than credited.

**refundDeityPass path:**
- `deityPassRefundable[buyer] = 0` (zeroed BEFORE payout)
- Pool decrements: `futurePrizePool -= remaining; nextPrizePool -= remaining`
- These pools were incremented when deity pass was purchased
- **Defense:** refund amount = `deityPassRefundable[buyer]`, which is set during purchase and can never exceed what was paid. Double-refund blocked by zeroing before payout.

### Site 2: `_payoutWithEthFallback()` (DegenerusGame.sol:2048-2062)

Called from `claimWinningsStethFirst()` for VAULT/DGNRS only.
- Same CEI as Site 1 but with stETH-first ordering
- **Defense:** Restricted to VAULT and DGNRS addresses only (line 1462-1464). Same accounting.

### Site 3: `adminSwapEthForStEth()` -- stETH transfer out (DegenerusGame.sol:1854-1865)

- Admin sends ETH in (`msg.value == amount`), receives stETH out
- Net effect: ETH balance increases by `amount`, stETH balance decreases by `amount`
- **Defense:** Value-neutral by construction. `msg.value != amount` reverts.

### Site 4: `adminStakeEthForStEth()` (DegenerusGame.sol:1873-1888)

- Converts ETH to stETH via Lido submit
- **Defense:** `uint256 stakeable = ethBal - reserve` where `reserve = claimablePool`. Cannot stake ETH reserved for claims. Lido returns stETH 1:1.

### Sites 5-6: `_sendToVault()` in GameOverModule (lines 184-221)

- Two `.call{value:}` sites to VAULT and DGNRS
- Called from `handleGameOverDrain()` and `handleFinalSweep()`
- **Defense:** `available = totalFunds > claimablePool ? totalFunds - claimablePool : 0`. Only sends excess above claimablePool. Cannot touch reserved funds.
- `handleGameOverDrain`: `gameOverFinalJackpotPaid = true` set before distribution. Prevents double-call.
- `handleFinalSweep`: `block.timestamp < gameOverTime + 30 days` guard. Only sweeps excess.

### Site 7: MintModule vault share (DegenerusGameMintModule.sol:737)

- `payable(ContractAddresses.VAULT).call{value: vaultShare}("")`
- This sends a portion of lootbox purchase ETH directly to VAULT
- `vaultShare` is computed from BPS split of `lootBoxAmount`: `vaultShare = (lootBoxAmount * vaultBps) / 10_000`
- The remaining ETH goes to futurePrizePool and nextPrizePool
- **Defense:** Total of all shares (future + next + vault + reward) = lootBoxAmount. No overcounting.

### Site 8: DegeneretteModule ETH payouts

- DegeneretteModule `_addClaimableEth()` credits to `claimableWinnings` AND `claimablePool` (line 1173)
- ETH bets: msg.value stays in contract or is deducted from claimableWinnings
- Payouts: credited to claimableWinnings, pulled via claimWinnings() later
- **Defense:** All payouts go through claimable accounting. No direct ETH push to players.

## Specific Attack Vector Results

### 1. Pool double-counting
**Attempt:** Can ETH be counted in both nextPrizePool and claimablePool simultaneously?
**Result:** INFEASIBLE. ETH enters pools (next/future) via purchase, exits pools via jackpot distribution which moves to claimablePool. The flow is one-directional: purchase -> next/future -> current -> claimable. At no point is the same ETH in two pools.
**Defense:** `_consolidatePrizePools()` in AdvanceModule moves nextPrizePool -> currentPrizePool. The full amount is moved, not duplicated. `claimablePool` is only incremented when claimableWinnings is credited.

### 2. stETH rebasing mismatch
**Attempt:** stETH rebases upward, creating a gap between tracked pools and actual balance.
**Result:** NOT A VULNERABILITY. stETH rebasing increases `steth.balanceOf(game)` which is on the LEFT side of the invariant. The RIGHT side (claimablePool) is ETH-denominated. Rebasing only strengthens the invariant, never weakens it.
**Defense:** The invariant is `balance + stethBalance >= claimablePool`. stETH rebasing increases left side.

### 3. Admin stake reserve bypass
**Attempt:** Can adminStakeEthForStEth bypass the claimablePool reserve check?
**Result:** INFEASIBLE. Line 1881: `if (ethBal <= reserve) revert E()`. Line 1882: `uint256 stakeable = ethBal - reserve`. Cannot stake if ETH balance <= claimablePool.
**Defense:** DegenerusGame.sol:1879-1882 -- explicit reserve check.

### 4. Auto-rebuy accounting gap
**Attempt:** When auto-rebuy fires in EndgameModule._addClaimableEth(), does it correctly handle the ETH split?
**Result:** SAFE. When auto-rebuy fires: `calc.ethSpent` goes to `nextPrizePool` or `futurePrizePool`, `calc.reserved` goes to both `_creditClaimable()` AND `claimablePool += calc.reserved` (EndgameModule.sol:251). The return value is 0 (no claimable delta for caller), so caller does NOT add to claimablePool. No double-count.
**Defense:** EndgameModule.sol:240-260 -- returns 0 when auto-rebuy fires, preventing caller from adding to claimablePool again.

### 5. Whale pass claim overflow
**Attempt:** Can whalePassClaims accumulate without ETH backing?
**Result:** INFEASIBLE. `whalePassClaims[winner]` is incremented by `fullHalfPasses = amount / HALF_WHALE_PASS_PRICE` in `_queueWhalePassClaimCore()`. The `amount` comes from jackpot ETH that was previously in futurePrizePool. The ETH stays in the contract (not transferred). When claimed via `claimWhalePass()`, it awards TICKETS (not ETH). The claimable ETH remainder is properly tracked in both claimableWinnings and claimablePool (PayoutUtils.sol:88-91).
**Defense:** PayoutUtils.sol:77-93 -- whale pass claims convert to tickets, remainder credited properly.

### 6. Deity pass refund drain

> **POST-AUDIT UPDATE:** `refundDeityPass()` was removed entirely from the codebase. This attack vector no longer exists.

**Attempt:** Can refundDeityPass drain more than was paid?
**Result:** INFEASIBLE. `deityPassRefundable[buyer]` is set during purchase in WhaleModule and can never exceed what was paid. It's zeroed before payout (DegenerusGame.sol:708). Double-refund impossible.
**Defense:** DegenerusGame.sol:706-708 -- zero check and zero-before-payout.

### 7. Game over double-drain
**Attempt:** Can handleGameOverDrain be called multiple times?
**Result:** INFEASIBLE. Line 62: `if (gameOverFinalJackpotPaid) return;`. Line 122: `gameOverFinalJackpotPaid = true;`. Set before any distribution.
**Defense:** GameOverModule.sol:62 + 122 -- idempotent guard.

### 8. Degenerette payout amplification
**Attempt:** Can bet resolution pay out more than wagered across all players?
**Result:** INFEASIBLE. Degenerette bets use claimable-sourced ETH. The `_addClaimableEth()` in DegeneretteModule credits both claimableWinnings and claimablePool (line 1173). Payout amounts are computed from match outcomes with bounded multipliers. Total payouts are capped by the bet pool.
**Defense:** DegeneretteModule.sol:1168-1175 -- proper dual accounting on credit.

### 9. Flash loan timing
**Attempt:** Can flash-loaned ETH manipulate pool calculations?
**Result:** INFEASIBLE. All purchase functions require `msg.value == price`. The ETH enters pools immediately. There's no calculation based on `address(this).balance` during purchase (except adminStakeEthForStEth which is admin-only). Flash loans can't inflate pools beyond what was paid.
**Defense:** Exact-value validation on all purchase functions.

### 10. Cross-module pool confusion
**Attempt:** Do all modules reference the same pool variables correctly?
**Result:** SAFE. All modules inherit DegenerusGameStorage. Storage layout is verified (v1.0 Phase 1: zero slot collisions). All modules read/write the same `claimablePool`, `futurePrizePool`, `nextPrizePool`, `claimableWinnings` mapping.
**Defense:** Shared storage via inheritance from DegenerusGameStorage.

## Conclusion

No ETH extraction vulnerability found. The protocol maintains strict accounting discipline:
1. Every ETH inflow has exact-value validation (`msg.value == price`)
2. Every pool transition is unidirectional (purchase -> next/future -> current -> claimable)
3. Every claimableWinnings increment has a matching claimablePool increment
4. Every ETH outflow follows CEI pattern with pre-transfer state updates
5. Admin functions cannot access claimablePool reserves
6. stETH rebasing only strengthens the solvency invariant

The invariant `address(game).balance + steth.balanceOf(game) >= claimablePool` holds by construction.
