# 04-01 FINDINGS: ETH Flow Trace -- Inflow and Outflow Path Audit

**Date:** 2026-03-06 (updated from 2026-03-01 findings to reflect current contract state)
**Scope:** DegenerusGame.sol (2812 lines) and all delegatecall modules
**Objective:** Verify every ETH inflow is fully attributed to pool variables and every ETH outflow reduces pools by exactly the payout amount.

**Key changes since original audit (2026-03-01):**
- `refundDeityPass()` removed entirely (no voluntary pre-gameOver deity refund)
- `receive()` now reverts after `gameOver` (`if (gameOver) revert E();` at line 2809)
- Line numbers shifted throughout due to contract modifications
- GO-F01 MEDIUM (double deity refund) is no longer applicable since `refundDeityPass` was removed

---

## Part 1: ETH Inflow Paths

### Inflow 1: purchase() -> recordMint -> _processMintPayment

**Entry:** `DegenerusGame.sol:540` (purchase) -> delegatecall to MintModule -> self-call to `recordMint` at line 384
**Payment processing:** `_processMintPayment` at `DegenerusGame.sol:992`

**Pool attribution logic (recordMint, lines 396-411):**
```solidity
prizeContribution, newClaimableBalance = _processMintPayment(player, costWei, payKind);
if (prizeContribution != 0) {
    uint256 futureShare = (prizeContribution * PURCHASE_TO_FUTURE_BPS) / 10_000;  // line 403, BPS=1000 (10%)
    if (futureShare != 0) {
        futurePrizePool += futureShare;               // line 406
    }
    uint256 nextShare = prizeContribution - futureShare;  // line 408 (remainder pattern)
    if (nextShare != 0) {
        nextPrizePool += nextShare;                   // line 410
    }
}
```

**Verification:** `futureShare + nextShare = futureShare + (prizeContribution - futureShare) = prizeContribution`. The remainder pattern guarantees exact attribution with zero dust.

**Payment modes (_processMintPayment, lines 992-1051):**
- **DirectEth (line 998):** `msg.value >= amount` required (line 1000: `if (msg.value < amount) revert E()`). `prizeContribution = amount` (line 1001). Overpayment stays in contract balance (unattributed to any pool). This is documented as "ignore remainder for accounting" (line 999). The overpayment becomes part of the yield surplus visible via `yieldPoolView()`.
- **Claimable (line 1003):** `msg.value == 0` required (line 1005). `prizeContribution = amount` (line 1014). `claimablePool -= amount` (line 1042). ETH recycled from claimable to prize pools.
- **Combined (line 1015):** `msg.value <= amount` required (line 1017). Remainder from claimable. `prizeContribution = msg.value + claimableUsed` (line 1036). `claimablePool -= claimableUsed` (line 1042). Must fully cover cost or revert (line 1035).

**INFO:** DirectEth overpayment is not attributed to any pool variable. This is by design -- the overage becomes yield surplus. No ETH is lost; it remains in the contract balance.

**Verdict: PASS** -- Sum of pool increments equals prizeContribution exactly via remainder pattern. All three payment modes correctly computed.

---

### Inflow 2: purchaseWhaleBundle() -> WhaleModule delegatecall

**Entry:** `DegenerusGame.sol:640` -> delegatecall to `DegenerusGameWhaleModule._purchaseWhaleBundle` at `WhaleModule:189`

**Price validation:** `msg.value == totalPrice` (strict equality, line 244: `if (msg.value != totalPrice) revert E()`). No overpayment possible.

**Pool attribution logic (lines 287-297):**
```solidity
// Split payment: pre-game 70/30, post-game 95/5 (future/next) -- comment at line 287
uint256 nextShare;
if (level == 0) {
    nextShare = (totalPrice * 3000) / 10_000;        // 30%  (line 291)
} else {
    nextShare = (totalPrice * 500) / 10_000;          // 5%   (line 293)
}
futurePrizePool += totalPrice - nextShare;            // line 296 (remainder)
nextPrizePool += nextShare;                            // line 297
```

**Verification:** `(totalPrice - nextShare) + nextShare = totalPrice`. Remainder pattern guarantees exact attribution.

**INFO:** NatSpec at DegenerusGame.sol line 633 says "Fund distribution - Level 1: 50% next/25% reward/25% future" but the WhaleModule code does 30%/70% at level 0 and 5%/95% at level >0. The inline comment at line 287 matches the code. This is a documentation inconsistency between the Game contract's NatSpec and the WhaleModule's actual logic.

**Verdict: PASS** -- msg.value strictly equals totalPrice; sum of pool increments equals totalPrice exactly.

---

### Inflow 3: purchaseDeityPass() -> WhaleModule delegatecall

**Entry:** `DegenerusGame.sol:685` -> delegatecall to `DegenerusGameWhaleModule._purchaseDeityPass` at `WhaleModule:460`

**Price validation:** `msg.value == totalPrice` (strict equality, line 491: `if (msg.value != totalPrice) revert E()`). No overpayment possible.

**Pool attribution logic (lines 529-537):**
```solidity
// Fund distribution: pre-game 70/30, post-game 95/5 (future/next) -- line 529
uint256 nextShare;
if (level == 0) {
    nextShare = (totalPrice * 3000) / 10_000;         // 30%  (line 532)
} else {
    nextShare = (totalPrice * 500) / 10_000;          // 5%   (line 534)
}
nextPrizePool += nextShare;                            // line 536
futurePrizePool += totalPrice - nextShare;             // line 537 (remainder)
```

**Verification:** `nextShare + (totalPrice - nextShare) = totalPrice`. Exact attribution via remainder.

**Refund tracking (line 496):** `deityPassPaidTotal[buyer] += totalPrice`. This tracks cumulative payments for gameOver refund calculation. It does not change pool attribution. The pools already received the full amount.

**Note:** `refundDeityPass()` has been removed from the contract. The only deity pass refund path is now via `handleGameOverDrain()` at game-over time.

**Verdict: PASS** -- msg.value strictly equals totalPrice; sum of pool increments equals totalPrice exactly.

---

### Inflow 4: placeFullTicketBets() -> DegeneretteModule delegatecall

**Entry:** `DegenerusGame.sol:812` -> delegatecall to `DegenerusGameDegeneretteModule.placeFullTicketBets` at `DegeneretteModule:382`

**Funds collection:** `_collectBetFunds` at `DegeneretteModule:569`

**ETH path (lines 576-589):**
```solidity
if (currency == CURRENCY_ETH) {
    if (jackpotResolutionActive) revert E();
    if (ethPaid > totalBet) revert InvalidBet();        // line 580: no overpayment allowed
    if (ethPaid < totalBet) {
        uint256 fromClaimable = totalBet - ethPaid;
        if (claimableWinnings[player] <= fromClaimable) revert InvalidBet();
        claimableWinnings[player] -= fromClaimable;      // line 584
        claimablePool -= fromClaimable;                   // line 585
    }
    futurePrizePool += totalBet;                          // line 589: full bet attributed
    lootboxRngPendingEth += totalBet;                     // line 590: pending tracker
}
```

**Verification:**
- If `ethPaid == totalBet`: `futurePrizePool += totalBet` = `msg.value`. Exact attribution.
- If `ethPaid < totalBet`: `futurePrizePool += totalBet`. The ETH component (`ethPaid`) comes from `msg.value`, and the claimable component (`totalBet - ethPaid`) is recycled from claimablePool (which is decremented by `fromClaimable` at line 585). The net effect: `futurePrizePool += totalBet`, `claimablePool -= fromClaimable`. The incoming msg.value plus the claimable reduction exactly equal the pool increment.
- If `ethPaid > totalBet`: revert (line 580). No overpayment.

**Verdict: PASS** -- Full bet amount attributed to futurePrizePool. Claimable recycling properly reduces claimablePool.

---

### Inflow 5: receive()

**Entry:** `DegenerusGame.sol:2808`

**Code (lines 2808-2811):**
```solidity
receive() external payable {
    if (gameOver) revert E();          // line 2809: blocks ETH after game over
    futurePrizePool += msg.value;      // line 2810
}
```

**Verification:** Two lines. After gameOver check, 100% of msg.value attributed to futurePrizePool. No conditional branches affecting attribution, no remainder. This is the only fallback receiver -- there is no `fallback()` function.

**Change from prior findings:** `receive()` now blocks incoming ETH after `gameOver`. Previously it was unconditional. This prevents post-gameOver ETH from becoming trapped without pool attribution.

**Verdict: PASS** -- Complete and unconditional attribution of msg.value to futurePrizePool (when not gameOver). Reverts after gameOver, preventing unattributed ETH accumulation.

---

### Inflow 6 (supplementary): purchaseLazyPass() -> WhaleModule delegatecall

**Entry:** `DegenerusGame.sol:665` -> `WhaleModule._purchaseLazyPass` at line 321

**Price validation:** `msg.value == totalPrice` (strict equality, line 400: `if (msg.value != totalPrice) revert E()`).

**Pool attribution logic (lines 416-426):**
```solidity
uint256 futureShare = (totalPrice * LAZY_PASS_TO_FUTURE_BPS) / 10_000;  // BPS=1000 (10%)
if (futureShare != 0) {
    futurePrizePool += futureShare;                    // line 418
}
uint256 nextShare;
unchecked {
    nextShare = totalPrice - futureShare;              // line 422 (remainder)
}
if (nextShare != 0) {
    nextPrizePool += nextShare;                        // line 425
}
```

**Verification:** `futureShare + nextShare = futureShare + (totalPrice - futureShare) = totalPrice`. Remainder pattern.

**Verdict: PASS** -- msg.value strictly equals totalPrice; sum of pool increments equals totalPrice exactly.

---

### Inflow 7 (supplementary): adminSwapEthForStEth() -- ETH received

**Entry:** `DegenerusGame.sol:1806`

**Validation (lines 1810-1816):**
```solidity
if (msg.sender != ContractAddresses.ADMIN) revert E();
if (recipient == address(0)) revert E();
if (amount == 0 || msg.value != amount) revert E();   // line 1812: strict equality
uint256 stBal = steth.balanceOf(address(this));
if (stBal < amount) revert E();
if (!steth.transfer(recipient, amount)) revert E();   // line 1816: send stETH out
```

**ETH flow:** Admin sends `amount` ETH in. Contract sends `amount` stETH out. No pool variables are modified. This is a value-neutral swap: ETH balance increases by `amount`, stETH balance decreases by `amount`. Net effect on `balance + stETH`: zero (assuming 1:1 ETH/stETH peg).

**Pool impact:** None. No pool variables touched. The incoming ETH is not attributed to any pool because an equal value of stETH leaves.

**Verdict: PASS** -- Net-neutral swap. No pool attribution needed because equal value exits as stETH.

---

## Part 2: ETH Outflow Paths

### Outflow 1: claimWinnings() -> _claimWinningsInternal

**Entry:** `DegenerusGame.sol` claimWinnings/claimWinningsSteth -> `_claimWinningsInternal` at line 1420

**Pool reduction and payout (lines 1420-1436):**
```solidity
function _claimWinningsInternal(address player, bool stethFirst) private {
    if (finalSwept) revert E();                         // line 1421: blocks claims after final sweep
    uint256 amount = claimableWinnings[player];
    if (amount <= 1) revert E();
    uint256 payout;
    unchecked {
        claimableWinnings[player] = 1;                 // line 1426: leave sentinel
        payout = amount - 1;                            // line 1427: subtract sentinel
    }
    claimablePool -= payout;                            // line 1429: CEI -- state before interaction
    emit WinningsClaimed(player, msg.sender, payout);
    if (stethFirst) {
        _payoutWithEthFallback(player, payout);
    } else {
        _payoutWithStethFallback(player, payout);
    }
}
```

**Verification:**
- Pool reduction: `claimablePool -= payout` where `payout = amount - 1`.
- Payout sent: `_payoutWithStethFallback(player, payout)` or `_payoutWithEthFallback(player, payout)` sends exactly `payout` wei (ETH-first or stETH-first, with fallback retry).
- Pool reduction == amount sent == `payout`. Exact match.

**CEI compliance:** State updated (line 1425, 1428) before external call (line 1431/1433). Correct pattern.

**_payoutWithStethFallback (lines 1967-1994):**
- Sends up to `amount` as ETH, remainder as stETH, with retry for edge cases.
- Total sent: `ethSend + stSend + leftover = amount` (guaranteed by logic flow, reverts if insufficient).

**_payoutWithEthFallback (lines 2000-2014):**
- Sends stETH first, then ETH for remainder.
- Total sent: `stSend + remaining = amount` (guaranteed, reverts if insufficient).

**Verdict: PASS** -- claimablePool reduced by exactly payout; external transfer sends exactly payout.

---

### Outflow 2: refundDeityPass() -- REMOVED

**Status:** `refundDeityPass()` has been entirely removed from the contract. There is no voluntary pre-gameOver deity pass refund path.

**Prior finding GO-F01 MEDIUM (double deity refund) is no longer applicable.** The only deity pass refund mechanism is now `handleGameOverDrain()` in the GameOverModule, which is a one-time terminal operation guarded by `gameOverFinalJackpotPaid`.

**Impact on invariant:** Positive. Removing the voluntary refund path eliminates the cross-path double-refund risk that was previously documented. The deity pass refund is now exclusively handled during game-over settlement.

**Verdict: N/A** -- Path no longer exists. Previously documented risk eliminated.

---

### Outflow 3: adminSwapEthForStEth() -- stETH sent

**Entry:** `DegenerusGame.sol:1806`

Already analyzed in Inflow 7. The outflow is `steth.transfer(recipient, amount)` at line 1816.

**Pool impact:** None. No pool variables touched.

**Net-neutrality:** Contract receives `amount` ETH, sends `amount` stETH. For the invariant `balance + stETH >= claimablePool`, assuming 1:1 peg: `(balance + amount) + (stETH - amount) = balance + stETH`. Invariant preserved.

**Risk note:** If stETH trades below 1:1 with ETH (depegs), the swap is value-neutral in nominal terms but the admin receives more value than they send. However, the admin can only execute this if `stBal >= amount`, and the `amount` of ETH they send in replaces the stETH value. The invariant holds in nominal terms.

**Verdict: PASS** -- Net-neutral swap; no pool modification; invariant preserved.

---

### Outflow 4: handleGameOverDrain() -> GameOverModule delegatecall

**Entry:** `DegenerusGame.sol` (called from AdvanceModule during game over detection) -> `DegenerusGameGameOverModule.handleGameOverDrain` at `GameOverModule:70`

**Guard:** `if (gameOverFinalJackpotPaid) return;` (line 71) -- prevents re-execution.

**Deity pass refund logic (lines 80-108):**

**Levels 0-9 (lines 80-108):**
```solidity
if (currentLevel < 10) {
    uint256 refundPerPass = DEITY_PASS_EARLY_GAMEOVER_REFUND;  // 20 ETH flat per pass
    uint256 budget = totalFunds > claimablePool ? totalFunds - claimablePool : 0;  // line 83
    uint256 totalRefunded;
    for (uint256 i; i < ownerCount; ) {
        address owner = deityPassOwners[i];
        uint16 purchasedCount = deityPassPurchasedCount[owner];
        if (purchasedCount != 0) {
            uint256 refund = refundPerPass * uint256(purchasedCount);
            if (refund > budget) { refund = budget; }           // budget cap (line 90)
            if (refund != 0) {
                claimableWinnings[owner] += refund;              // line 95
                totalRefunded += refund;                          // line 96
                budget -= refund;                                 // line 97
            }
            if (budget == 0) break;                               // line 100
        }
    }
    if (totalRefunded != 0) {
        claimablePool += totalRefunded;                          // line 107
    }
}
```
Credits refunds to claimableWinnings and increases claimablePool. No direct ETH transfer -- funds are credited for later claim via claimWinnings(). Budget is capped at `totalFunds - claimablePool` to prevent over-commitment. FIFO by purchase order (iterates `deityPassOwners` array).

**Available funds calculation (line 112):**
```solidity
available = totalFunds > claimablePool ? totalFunds - claimablePool : 0;
```
This recalculates after deity refunds, correctly reflecting the updated claimablePool.

**Decimator distribution (lines 128-137):**
```solidity
uint256 decPool = remaining / 10;                     // 10% of available
uint256 decRefund = runDecimatorJackpot(decPool, lvl, rngWord);
uint256 decSpend = decPool - decRefund;
if (decSpend != 0) {
    claimablePool += decSpend;                         // line 133
}
remaining -= decPool;
remaining += decRefund;                                // line 136: return refund to remaining
```
Decimator processes `decPool`; any unused portion (`decRefund`) flows back to remaining for terminal jackpot. The spent amount is added to claimablePool.

**Terminal jackpot distribution (lines 141-150):**
```solidity
uint256 termPaid = runTerminalJackpot(remaining, lvl + 1, rngWord);
remaining -= termPaid;
if (remaining != 0) {
    _sendToVault(remaining, stBal);                    // line 148
}
```
Terminal jackpot credits winners via JackpotModule (which internally calls `_addClaimableEth` -> `claimablePool +=`). Any undistributed remainder is swept to vault.

**_sendToVault (lines 182-219):**
Splits amount 50/50 between VAULT and DGNRS. Sends stETH first (where available), then ETH for remainder. This is a direct transfer -- it reduces contract balance without touching pool variables. This is correct because `available` was calculated as `totalFunds - claimablePool`, meaning only excess funds above claimable obligations are sent.

**Verification:**
- Deity pass refunds: credited to claimable with matching `claimablePool += totalRefunded` (line 107)
- Decimator spend: `claimablePool += decSpend` (line 133) matches amount credited to winners
- Terminal jackpot: `claimablePool` updated internally by JackpotModule
- Vault sweep of remainder: sends from excess funds above claimablePool
- No pool variable double-counting; each path credits claimablePool by the exact amount added to claimableWinnings

**Verdict: PASS** -- All credits to claimableWinnings have matching claimablePool increases. Vault receives only excess above claimablePool.

---

### Outflow 5: handleFinalSweep() -> GameOverModule delegatecall

> **POST-AUDIT UPDATE:** `handleFinalSweep` was fundamentally rewritten after the original audit. The OLD behavior described below (preserves claimablePool, sweeps only excess, callable multiple times, no state mutation guard) no longer applies. The CURRENT behavior (GameOverModule lines 168-186):
> - Has a `finalSwept` idempotency guard (`if (finalSwept) return;` at line 171)
> - Sets `finalSwept = true` (line 173) and `claimablePool = 0` (line 174), **forfeiting all unclaimed winnings**
> - Sweeps ALL remaining `totalFunds` (not just excess above claimablePool) to vault/DGNRS via `_sendToVault`
> - One-time execution only
> - Additionally, `_claimWinningsInternal` (DegenerusGame.sol line 1420) now has `if (finalSwept) revert E();` at line 1421, blocking all claims after the sweep
> - VRF shutdown (`admin.shutdownVrf()`) is called via try/catch before the sweep (line 177)
>
> **Revised verification:** After `finalSwept = true`, `claimablePool = 0`, and `_sendToVault(totalFunds, stBal)`:
> - All remaining contract balance is sent to vault (50%) and DGNRS (50%)
> - `claimablePool = 0` means no claims can be honored (and `finalSwept` prevents any attempt)
> - The contract reaches true zero terminal balance
> - The `_sendToVault` helper (lines 192-229) splits the amount 50/50 using remainder pattern (no dust)
>
> **Revised verdict: PASS** -- All funds are swept. No funds permanently locked. Players must claim within the 30-day window before the sweep.

**Entry:** `DegenerusGameGameOverModule.handleFinalSweep` at `GameOverModule:168`

~~**Guards (lines 159-160):**~~
```solidity
// CURRENT CODE (lines 168-174):
function handleFinalSweep() external {
    if (gameOverTime == 0) return;                                    // line 169
    if (block.timestamp < uint256(gameOverTime) + 30 days) return;   // line 170
    if (finalSwept) return;                                           // line 171

    finalSwept = true;                                                // line 173
    claimablePool = 0;                                                // line 174
```

**VRF shutdown (line 177):**
```solidity
try admin.shutdownVrf() {} catch {}  // fire-and-forget; failure must not block sweep
```

**Sweep logic (lines 179-185):**
```solidity
uint256 ethBal = address(this).balance;
uint256 stBal = steth.balanceOf(address(this));
uint256 totalFunds = ethBal + stBal;

if (totalFunds == 0) return;

_sendToVault(totalFunds, stBal);                       // line 185
```

**Verification:**
- Sweeps ALL `totalFunds` (entire remaining balance), not just excess above claimablePool.
- `claimablePool` is set to 0 -- unclaimed winnings are forfeited.
- `finalSwept = true` prevents re-execution and blocks future `claimWinnings()` calls.
- `_sendToVault` sends exactly `totalFunds` to VAULT (50%) and DGNRS (50%).
- After sweep: contract holds zero ETH/stETH. True terminal state.

**Dust handling:** `dgnrsAmount = amount / 2`, `vaultAmount = amount - dgnrsAmount`. Remainder pattern: no dust lost.

**Note:** VRF shutdown (`admin.shutdownVrf()`) is called here with try/catch. If VRF shutdown fails, the sweep still proceeds -- LINK tokens remain in the subscription but ETH/stETH sweep is not blocked.

**Verdict: PASS** -- All funds swept to vault/DGNRS. Players must claim within the 30-day post-gameOver window.

---

## Part 3: Internal Conversion Paths

### _autoStakeExcessEth() -- AdvanceModule line 1009

**Code (lines 1009-1015):**
```solidity
function _autoStakeExcessEth() private {
    uint256 ethBal = address(this).balance;
    uint256 reserve = claimablePool;
    if (ethBal <= reserve) return;
    uint256 stakeable = ethBal - reserve;
    try steth.submit{value: stakeable}(address(0)) returns (uint256) {} catch {}
}
```

**Verification:**
- Only stakes `ethBal - claimablePool`. Never touches claimable ETH reserve.
- After staking: `balance = reserve`, `stETH += stakeable (approx)`. So `balance + stETH >= claimablePool` still holds.
- Non-blocking: uses try/catch so Lido failures don't break the game.
- No pool variables modified.

**Verdict: PASS** -- Guards claimablePool reserve. Invariant preserved.

---

### adminStakeEthForStEth() -- DegenerusGame.sol line 1825

**Code (lines 1825-1840):**
```solidity
function adminStakeEthForStEth(uint256 amount) external {
    if (msg.sender != ContractAddresses.ADMIN) revert E();
    if (amount == 0) revert E();
    uint256 ethBal = address(this).balance;
    if (ethBal < amount) revert E();
    uint256 reserve = claimablePool;
    if (ethBal <= reserve) revert E();
    uint256 stakeable = ethBal - reserve;
    if (amount > stakeable) revert E();
    try steth.submit{value: amount}(address(0)) returns (uint256) {} catch { revert E(); }
}
```

**Verification:**
- Guards: `amount <= ethBal - claimablePool`. Never stakes claimable ETH.
- After staking: `balance -= amount`, `stETH += amount (approx)`. So `balance + stETH >= claimablePool` still holds.
- No pool variables modified.
- Unlike `_autoStakeExcessEth`, this version reverts on Lido failure (line 1838-1839).

**Verdict: PASS** -- Same guard pattern as _autoStakeExcessEth. claimablePool reserve protected.

---

## Part 4: Degenerette ETH Payouts (futurePrizePool reduction)

### _distributePayout (ETH) -- DegeneretteModule line 700

**Code (lines 701-719):**
```solidity
if (currency == CURRENCY_ETH) {
    uint256 pool = futurePrizePool;
    uint256 ethPortion = payout / 4;                   // 25% as ETH
    uint256 lootboxPortion = payout - ethPortion;       // 75% as lootbox (remainder)
    uint256 maxEth = (pool * ETH_WIN_CAP_BPS) / 10_000;  // 10% cap
    if (ethPortion > maxEth) {
        lootboxPortion += ethPortion - maxEth;
        ethPortion = maxEth;
    }
    unchecked { pool -= ethPortion; }                   // line 717
    futurePrizePool = pool;                              // line 718
    _addClaimableEth(player, ethPortion);                // line 719
}
```

**ETH accounting:** `futurePrizePool -= ethPortion`. `claimablePool += ethPortion` (via `_addClaimableEth` at line 1168-1174 which calls `_creditClaimable`). Net effect: ETH moves from futurePrizePool to claimablePool.

**_addClaimableEth (DegeneretteModule lines 1168-1175):**
```solidity
function _addClaimableEth(address beneficiary, uint256 weiAmount) private {
    if (weiAmount == 0) return;
    claimablePool += weiAmount;                         // line 1173
    _creditClaimable(beneficiary, weiAmount);            // line 1174
}
```

**Lootbox portion:** `lootboxPortion` does NOT reduce futurePrizePool. It is resolved via `_resolveLootboxDirect` which awards tickets/rewards -- the lootbox ETH stays conceptually in futurePrizePool as the underlying backing for those rewards.

**Solvency:** `ethPortion <= maxEth = pool * 10%`, so `pool - ethPortion >= pool * 90% > 0`. The unchecked subtraction is safe.

**Verdict: PASS** -- futurePrizePool reduction equals exactly the ETH credited to claimable.

---

## Part 5: Requirement Verdicts

### ACCT-01: Core ETH Invariant
**Statement:** `address(this).balance + steth.balanceOf(this) >= claimablePool`

**Analysis:**
- **All 5+ inflow paths** attribute msg.value to pool variables (futurePrizePool, nextPrizePool) or directly to claimablePool. No inflow leaves ETH unattributed (except minor DirectEth overpayment which becomes yield surplus, strengthening the invariant).
- **All outflow paths** reduce the correct pool variable by exactly the amount sent:
  - claimWinnings: `claimablePool -= payout`, sends `payout` (line 1428)
  - adminSwapEthForStEth: net-neutral (ETH in, stETH out, equal amounts) (line 1816)
  - handleGameOverDrain: credits to claimable have matching `claimablePool +=`; vault receives only excess (lines 107, 133)
  - handleFinalSweep: sets `claimablePool = 0` (forfeits unclaimed), sweeps ALL `totalFunds` to vault/DGNRS; `finalSwept` blocks future claims (lines 168-185)
  - refundDeityPass: **REMOVED** -- no longer an outflow path
- **Internal conversions** (_autoStakeExcessEth line 1009, adminStakeEthForStEth line 1825): guard `claimablePool` reserve, converting ETH->stETH without touching pool variables.
- **Degenerette payouts**: `futurePrizePool -= ethPortion`, `claimablePool += ethPortion` -- balanced transfer between pools (lines 717-719).
- **receive() post-gameOver guard**: `if (gameOver) revert E()` at line 2809 prevents unattributed ETH from accumulating after game over.

**Prerequisite for invariant holding:**
1. All `claimablePool +=` operations have matching `claimableWinnings[player] +=` (verified in all paths)
2. All outflows that reduce `balance + stETH` either reduce `claimablePool` by the same amount (claimWinnings) or only touch excess above `claimablePool` (vault sweep, final sweep)
3. stETH 1:1 peg assumption for adminSwapEthForStEth

**Verdict: PASS** -- The invariant holds. Previous conditional qualifier (GO-F01 double deity refund) is resolved: `refundDeityPass()` was removed, eliminating the cross-path double-refund risk. The only remaining assumptions are:
(a) stETH maintains approximate 1:1 peg with ETH
(b) Lido stETH submit returns approximately 1:1 (guaranteed by Lido protocol design)

These are external dependency assumptions, not contract logic concerns.

---

### ACCT-06: receive() Routing
**Statement:** `receive()` correctly routes all incoming ETH

**Code (DegenerusGame.sol:2808-2811):**
```solidity
receive() external payable {
    if (gameOver) revert E();
    futurePrizePool += msg.value;
}
```

**Analysis:**
- No `fallback()` function exists. All plain ETH transfers hit `receive()`.
- Pre-gameOver: 100% of msg.value attributed to futurePrizePool.
- Post-gameOver: reverts, preventing unattributed ETH accumulation.
- No conditional branches affecting attribution (other than gameOver guard).
- Function calls with ETH (purchase, purchaseWhaleBundle, purchaseDeityPass, placeFullTicketBets, adminSwapEthForStEth) route to their specific function selectors and do NOT hit receive().

**Verdict: PASS** -- receive() unconditionally routes all plain ETH transfers to futurePrizePool pre-gameOver, and blocks them post-gameOver.

---

## Summary Table

| # | Path | Direction | Pool Variables | Attribution | Verdict |
|---|------|-----------|----------------|-------------|---------|
| 1 | purchase/recordMint (line 384) | Inflow | nextPrizePool, futurePrizePool | remainder pattern | PASS |
| 2 | purchaseWhaleBundle (line 185) | Inflow | nextPrizePool, futurePrizePool | remainder pattern | PASS |
| 3 | purchaseDeityPass (line 456) | Inflow | nextPrizePool, futurePrizePool | remainder pattern | PASS |
| 4 | placeFullTicketBets (line 382) | Inflow | futurePrizePool | full totalBet | PASS |
| 5 | receive() (line 2808) | Inflow | futurePrizePool | full msg.value | PASS |
| 6 | purchaseLazyPass (line 317) | Inflow | nextPrizePool, futurePrizePool | remainder pattern | PASS |
| 7 | adminSwapEthForStEth (line 1806) | Inflow | none | net-neutral swap | PASS |
| 8 | claimWinnings (line 1420) | Outflow | claimablePool | exact payout | PASS |
| 9 | refundDeityPass | Outflow | -- | **REMOVED** | N/A |
| 10 | adminSwapEthForStEth (line 1806) | Outflow | none | net-neutral swap | PASS |
| 11 | handleGameOverDrain (line 70) | Outflow | claimablePool (credits) | excess to vault | PASS |
| 12 | handleFinalSweep (line 168) | Outflow | claimablePool zeroed; finalSwept set | ALL funds to vault/DGNRS | PASS |
| 13 | _autoStakeExcessEth (line 1009) | Internal | none | guards claimablePool | PASS |
| 14 | adminStakeEthForStEth (line 1825) | Internal | none | guards claimablePool | PASS |
| 15 | degenerette _distributePayout (line 700) | Internal | futurePrizePool -> claimablePool | exact ethPortion | PASS |

**Informational Findings:**
- **INFO-01:** DirectEth overpayment in purchase() is not attributed to any pool variable. The surplus accrues as yield. This is documented and intentional.
- **INFO-02:** WhaleModule/DegenerusGame NatSpec inconsistency on whale bundle fund distribution percentages. Code is self-consistent; only documentation differs.
- **ACCT-01 PASS:** All single-path and cross-path analyses pass. The prior GO-F01 conditional qualifier is resolved (refundDeityPass removed).
- **ACCT-06 PASS:** receive() routing is unconditional (pre-gameOver) and blocks post-gameOver, preventing trapped ETH.
- **refundDeityPass REMOVED:** The voluntary deity pass refund path no longer exists. Deity pass refunds are exclusively handled during game-over settlement via handleGameOverDrain(), which is guarded by `gameOverFinalJackpotPaid` to prevent double execution.
- **claimablePool bypass:** handleGameOverDrain credits deity refunds TO claimablePool (not FROM it). The refund comes from the excess funds pool (`totalFunds - claimablePool`), budget-capped. This is correct because the refund increases the contract's claimable obligations and the funds are already held by the contract.
