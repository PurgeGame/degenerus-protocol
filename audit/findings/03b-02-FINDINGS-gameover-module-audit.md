# GameOverModule Terminal Settlement Audit

**Audit target:** `contracts/modules/DegenerusGameGameOverModule.sol` (287 lines)
**Audit date:** 2026-03-01
**Requirement:** MATH-05 (partial -- terminal settlement fund distribution correctness)

---

## 1. Terminal Settlement Path Trace

### 1.1 Re-Entry Guard Analysis

The `handleGameOverDrain` function (line 67) begins with:

```solidity
if (gameOverFinalJackpotPaid) return; // Line 68
```

**Guard placement:** BEFORE any state mutation or external call. This is correct -- early return prevents any re-execution.

**Guard set point:** Lines 126-128:

```solidity
gameOver = true;                      // Line 126
gameOverTime = uint48(block.timestamp); // Line 127
gameOverFinalJackpotPaid = true;      // Line 128
```

The guard is set AFTER refund credits (lines 80-120) but BEFORE the BAF/Decimator distribution calls (lines 139-147). This ordering means:

- If the function reverts during BAF/Decimator distribution, the guard IS already set (`gameOver` and `gameOverFinalJackpotPaid` are set before external calls), so on retry the function returns immediately at line 68 without distributing.
- **Wait -- this is wrong.** If BAF/Decimator distribution reverts, the entire transaction reverts, rolling back ALL state changes including `gameOverFinalJackpotPaid = true`. So the guard is safe: it will be set only on successful completion, and on retry the full function re-executes.

**Verdict on re-entry guard:** The guard at line 68 returns early if `gameOverFinalJackpotPaid` is already true. Since the flag is set within the same transaction as distribution calls, and a revert would roll back everything, there is no path that sets the flag without completing (or at least attempting) distribution. The `return` at line 130 (`if (available == 0)`) and line 134 (`if (rngWord == 0)`) both occur AFTER lines 126-128, so in those cases the guard is set but distribution is skipped intentionally (no funds or no RNG word). **PASS -- no re-entry vulnerability.**

**Exit paths that set the guard:**

| Path | Lines | Guard Set? | Distribution Done? |
|------|-------|------------|-------------------|
| Already processed | 68 | N/A (returns early) | N/A |
| available == 0 | 126-130 | Yes | No (nothing to distribute) |
| rngWord == 0 | 126-134 | Yes | No (RNG not ready) |
| Normal completion | 126-147 | Yes | Yes |

All paths that reach line 126 set `gameOverFinalJackpotPaid = true`. The function cannot exit after line 126 without setting the guard. **PASS.**

### 1.2 Deity Pass Refund Tier Trace

> **POST-AUDIT UPDATE (deity pass refund tiers):** The code was significantly reworked after this audit. The original audit described two separate deity pass refund tiers: level 0 (full refund of `deityPassPaidTotal[owner]`) and levels 1-9 (fixed 20 ETH per pass). The current code has a **single** refund tier: all levels below 10 (`currentLevel < 10`) receive a fixed `DEITY_PASS_EARLY_GAMEOVER_REFUND = 20 ether` per pass purchased, budget-capped to available funds, processed FIFO by purchase order. There is no separate level-0 full-refund path and no use of `deityPassPaidTotal` for refund amounts. The two-tier analysis below reflects the code at audit time, not the current implementation.

**Level 0 -- Full Refund (lines 77-97)**

Conditions: `currentLevel == 0 && !jackpotPhaseFlag`

This means the game never progressed past purchase phase at level 0.

```solidity
uint256 ownerCount = deityPassOwners.length;      // Line 78
uint256 totalRefunded;                              // Line 79
for (uint256 i; i < ownerCount; ) {                // Line 80
    address owner = deityPassOwners[i];             // Line 81
    uint256 refund = deityPassPaidTotal[owner];     // Line 82
    if (refund != 0) {                              // Line 83
        unchecked {
            claimableWinnings[owner] += refund;     // Line 85
            totalRefunded += refund;                // Line 86
        }
        deityPassPaidTotal[owner] = 0;              // Line 88
        deityPassRefundable[owner] = 0;             // Line 89
    }
    unchecked { ++i; }                              // Line 91-93
}
if (totalRefunded != 0) {
    claimablePool += totalRefunded;                 // Line 96
}
```

**Overflow analysis for `unchecked` blocks:**
- `claimableWinnings[owner] += refund`: Maximum single-owner payment is ~300 ETH (deity pass k=23: 24 + T(23) = 24 + 276 = 300 ETH). With repeated purchases impossible (`deityPassCount[buyer] != 0` guard in WhaleModule:439), each owner has at most one payment. 300 ETH is ~3e20 wei, well within uint256 range. **Safe.**
- `totalRefunded += refund`: Maximum total across 32 owners: sum of all deity pass prices = 24*32 + sum(k*(k+1)/2, k=0..31) = 768 + 5456 = 6224 ETH. Actually, maximum of 32 unique deity pass owners (bounded by symbolId < 32 at WhaleModule:437). Total paid = sum_{k=0}^{31} (24 + k*(k+1)/2) = 32*24 + sum_{k=0}^{31} k*(k+1)/2 = 768 + 5456 = 6224 ETH = ~6.2e21 wei. uint256 max is ~1.16e77. **Safe.**

**Zero-payment handling:** If `deityPassPaidTotal[owner] == 0` for any owner, the `if (refund != 0)` guard at line 83 skips them. **Correct.**

**State cleanup:** `deityPassPaidTotal[owner] = 0` and `deityPassRefundable[owner] = 0` are zeroed after credit. Prevents double-claim within the same function. **Correct.**

**Level 1-9 -- Fixed 20 ETH/pass Refund (lines 98-121)**

Conditions: `currentLevel >= 1 && currentLevel < 10`

```solidity
uint256 refundPerPass = DEITY_PASS_EARLY_GAMEOVER_REFUND; // 20 ether, Line 99
uint256 ownerCount = deityPassOwners.length;               // Line 100
uint256 totalRefunded;                                      // Line 101
for (uint256 i; i < ownerCount; ) {                        // Line 102
    address owner = deityPassOwners[i];                     // Line 103
    uint16 purchasedCount = deityPassPurchasedCount[owner]; // Line 104
    if (purchasedCount != 0) {                              // Line 105
        uint256 refund = refundPerPass * uint256(purchasedCount); // Line 106
        unchecked {
            claimableWinnings[owner] += refund;             // Line 108
            totalRefunded += refund;                        // Line 109
        }
        deityPassPaidTotal[owner] = 0;                      // Line 111
        deityPassRefundable[owner] = 0;                     // Line 112
    }
    unchecked { ++i; }                                      // Line 114-116
}
if (totalRefunded != 0) {
    claimablePool += totalRefunded;                          // Line 119
}
```

**Overflow analysis:**
- `refundPerPass * uint256(purchasedCount)`: Maximum `purchasedCount` is 1 (each buyer can only buy once per WhaleModule:439 `deityPassCount[buyer] != 0` check). But `deityPassPurchasedCount` is a uint16, so theoretically up to 65535 if there were a bug elsewhere. Even at 65535 * 20 ETH = 1.31M ETH, this is ~1.3e24 wei, still within uint256. **Safe.**
- `totalRefunded`: Max 32 owners * 20 ETH = 640 ETH. **Safe.**
- Uses `deityPassPurchasedCount[owner]` (not `deityPassPaidTotal`). This is correct -- the fixed refund is per-pass, not per-amount-paid. **Correct field used.**

**Note on deityPassPaidTotal vs deityPassPurchasedCount:** In the level 1-9 branch, refund is based on `purchasedCount` (number of passes), not `paidTotal` (amount paid). Both `deityPassPaidTotal` and `deityPassRefundable` are zeroed anyway (lines 111-112), which prevents any interaction with the level 0 branch. **Consistent cleanup.**

**Level 10+ -- No Refund (implicit)**

Conditions: `currentLevel >= 10` (neither branch is entered)

If `currentLevel >= 10`, neither the level 0 branch (`currentLevel == 0`) nor the level 1-9 branch (`currentLevel >= 1 && currentLevel < 10`) is taken. No refund loop executes. No refund is credited. `totalRefunded` remains 0. `claimablePool` is unchanged.

**No fallthrough risk:** The `if/else if` structure ensures exactly one branch executes. If `currentLevel >= 10`, neither condition is true, and execution continues to line 123 (available balance computation). **PASS.**

**Edge: currentLevel == 0 with jackpotPhaseFlag == true**

If `currentLevel == 0 && jackpotPhaseFlag == true`, the level 0 full refund branch is NOT entered (due to `!jackpotPhaseFlag`). The level 1-9 branch is NOT entered either (`currentLevel >= 1` fails). So no refund occurs. This is correct behavior: if the jackpot phase was entered at level 0 (somehow), players have participated in the game and the full refund is no longer appropriate.

### 1.3 Available Balance Safety

**Line 124:**
```solidity
uint256 available = totalFunds > claimablePool ? totalFunds - claimablePool : 0;
```

**Underflow protection:** The ternary check `totalFunds > claimablePool` prevents underflow. If refunds push `claimablePool` above `totalFunds`, `available = 0` and no distribution occurs (line 130: `if (available == 0) return`). **PASS -- no underflow possible.**

**`totalFunds` definition (lines 73-75):**
```solidity
uint256 ethBal = address(this).balance;
uint256 stBal = steth.balanceOf(address(this));
uint256 totalFunds = ethBal + stBal;
```

This is the ACTUAL contract balance (ETH + stETH), not an accounting variable. It reflects real holdings at the time of the call. This means:
- External ETH deposits (selfdestruct, coinbase) would inflate `totalFunds` but not `claimablePool`, making more funds available for distribution. Not exploitable (benefits BAF/Decimator winners).
- stETH rebasing could slightly inflate or deflate `stBal`. Positive rebases are handled correctly (extra funds go to distribution).

**Scenario: All refunds exceed contract balance**

If deity pass payments were already spent (on jackpots, prizes, etc.) before game-over at level 0, then:
- `claimablePool += totalRefunded` makes `claimablePool` large
- `totalFunds` (actual balance) is reduced
- `available = 0`, no BAF/Decimator distribution
- Deity pass holders have `claimableWinnings` credits that may exceed actual contract funds

This creates a **first-come-first-served claim race** where early claimants drain the remaining balance. However, at level 0 with `!jackpotPhaseFlag`, minimal funds should have been spent (only initial distributions from `futurePrizePool`/`nextPrizePool`). The deity pass payments should still largely be in the contract.

### 1.4 BAF/Decimator Distribution

**BAF (lines 139-145):**
```solidity
uint256 bafPool = remaining / 2;                           // Line 139
if (bafPool != 0) {                                         // Line 140
    uint256 bafSpend = _payGameOverBafEthOnly(bafPool, rngWord, lvl); // Line 141
    if (bafSpend != 0) {
        remaining -= bafSpend;                               // Line 143
    }
}
```

`_payGameOverBafEthOnly` (lines 155-187) calls `jackpots.runBafJackpot(amount, bafLvl, rngWord)` which is an external call to the Jackpots contract. The Jackpots contract returns winners and amounts. The function then credits `claimableWinnings[winner]` and adds to `claimablePool`.

**Key observation:** `bafSpend` is the amount actually credited to winners (returned as `credited` at line 186). If the Jackpots contract returns zero winners, `credited = 0` and `remaining` is unchanged. The uncredited portion stays in `remaining` for the Decimator.

**Dust on odd amounts:** `bafPool = remaining / 2` truncates. On odd `remaining`, 1 wei stays in `remaining`. After BAF spends `bafSpend` from `bafPool`, the Decimator gets `remaining - bafSpend`. If `bafSpend < bafPool`, the unspent BAF portion also flows to Decimator. **No dust lost.**

**If Jackpots contract reverts:** The entire `handleGameOverDrain` transaction reverts. `gameOver` and `gameOverFinalJackpotPaid` are NOT set. The function can be retried. **Safe.**

**Decimator (line 147):**
```solidity
_payGameOverDecimatorEthOnly(remaining, rngWord, lvl, stBal); // Line 147
```

`_payGameOverDecimatorEthOnly` (lines 206-222) calls `IDegenerusGame(address(this)).runDecimatorJackpot(amount, lvl, rngWord)` -- a self-call that delegatecalls to the DecimatorModule. The DecimatorModule returns `refund` (unawarded amount). The function then:
- Credits `claimablePool += netSpend` (line 219)
- If refund exists, sends it to vault via `_sendToVault(refund, stethBal)` (line 221)

**Interesting:** The Decimator call uses `IDegenerusGame(address(this)).runDecimatorJackpot(...)` which is a regular call to self (not delegatecall). This goes through the DegenerusGame `runDecimatorJackpot` function (line 1256), which then delegatecalls to the DecimatorModule. This double-hop is necessary because the DecimatorModule expects `msg.sender == GAME`. **Correct pattern.**

**If no Decimator winners:** `refund = amount` (full pool returned), `netSpend = 0`, entire amount sent to vault. **Correct.**

### 1.5 Final State Mutations

```solidity
gameOver = true;                        // Line 126 -- terminal, irreversible
gameOverTime = uint48(block.timestamp); // Line 127 -- timestamp for sweep timer
gameOverFinalJackpotPaid = true;        // Line 128 -- re-entry guard
```

These are set BEFORE external calls (BAF/Decimator distribution at lines 139-147). However, if those external calls revert, the transaction reverts entirely, rolling back these mutations. If they succeed, the mutations persist.

**CEI (Checks-Effects-Interactions) pattern:**
- Checks: `gameOverFinalJackpotPaid` guard (line 68), level checks (lines 77-121)
- Effects: Refund credits (lines 84-96, 107-119), `gameOver`/`gameOverTime`/`gameOverFinalJackpotPaid` (lines 126-128)
- Interactions: BAF jackpot external call (line 141 -> jackpots.runBafJackpot), Decimator self-call (line 147 -> runDecimatorJackpot), vault transfer (line 221 -> _sendToVault)

State mutations at lines 126-128 are before interactions. Additional `claimablePool` mutations happen in `_payGameOverBafEthOnly` (line 183) and `_payGameOverDecimatorEthOnly` (line 219) DURING interactions. These are incremental additions to `claimablePool`, which is a running total. A reentrancy would find `gameOverFinalJackpotPaid = true` and return early. **Safe.**

---

## 2. handleFinalSweep and _sendToVault Audit

### 2.1 handleFinalSweep (lines 228-243)

```solidity
function handleFinalSweep() external {
    if (gameOverTime == 0) return;                                    // Line 229
    if (block.timestamp < uint256(gameOverTime) + 30 days) return;   // Line 230

    uint256 ethBal = address(this).balance;                           // Line 232
    uint256 stBal = steth.balanceOf(address(this));                  // Line 233
    uint256 totalFunds = ethBal + stBal;                             // Line 234

    uint256 available = totalFunds > claimablePool ? totalFunds - claimablePool : 0; // Line 237

    if (available == 0) return;                                       // Line 239

    _sendToVault(available, stBal);                                   // Line 242
}
```

**30-day guard (line 230):**
- `gameOverTime` is set to `uint48(block.timestamp)` in `handleGameOverDrain` (line 127).
- The check `block.timestamp < uint256(gameOverTime) + 30 days` prevents early sweep.
- Cast to `uint256` prevents uint48 overflow when adding 30 days (30 * 86400 = 2,592,000 seconds). uint48 max is ~2.8e14, current timestamps are ~1.7e9. Adding 2.6M is safe even in uint48, but the uint256 cast is defensive. **PASS.**

**Multiple calls after 30 days:**
- No re-entry guard like `gameOverFinalJackpotPaid`. Can be called multiple times.
- Each call recomputes `available = totalFunds > claimablePool ? totalFunds - claimablePool : 0`.
- After the first successful sweep, `address(this).balance` is reduced by the ETH sent. On the next call, `totalFunds` is lower, `available` is likely 0 (or reduced by the sweep amount). If stETH rebases add value, another sweep could send the excess. **Harmless -- idempotent behavior.**

**claimablePool preservation (line 237):**
- `claimablePool` is NOT modified by `handleFinalSweep`. Players can still claim their `claimableWinnings` after sweep.
- The `available` computation excludes `claimablePool`, so only surplus funds are swept. **PASS -- claimable winnings preserved.**

**available == 0 (line 239):**
- If no surplus, function returns. No-op. No revert. **Correct.**

### 2.2 _sendToVault (lines 249-286)

```solidity
function _sendToVault(uint256 amount, uint256 stethBal) private {
    uint256 dgnrsAmount = amount / 2;              // Line 250 -- 50% to DGNRS
    uint256 vaultAmount = amount - dgnrsAmount;    // Line 251 -- 50% to VAULT (gets rounding remainder)
```

**Rounding:** On odd `amount`, `dgnrsAmount = floor(amount/2)` and `vaultAmount = amount - dgnrsAmount = ceil(amount/2)`. The VAULT gets the extra 1 wei on odd amounts. **Max dust: 1 wei. Always accounted for -- no loss.**

**VAULT transfer (lines 253-268):**
```solidity
if (vaultAmount != 0) {
    if (vaultAmount <= stethBal) {
        // Send all as stETH
        if (!steth.transfer(ContractAddresses.VAULT, vaultAmount)) revert E();
        stethBal -= vaultAmount;
    } else {
        // Send available stETH + remainder as ETH
        if (stethBal != 0) {
            if (!steth.transfer(ContractAddresses.VAULT, stethBal)) revert E();
        }
        uint256 ethAmount = vaultAmount - stethBal;
        stethBal = 0;
        if (ethAmount != 0) {
            (bool ok, ) = payable(ContractAddresses.VAULT).call{value: ethAmount}("");
            if (!ok) revert E();
        }
    }
}
```

**ETH transfer method:** Uses `.call{value: ethAmount}("")` with return check. No gas stipend limit (unlimited gas forwarded). The VAULT contract must be able to receive ETH (via receive/fallback). **If VAULT reverts, entire sweep reverts.** This is acceptable -- VAULT is a protocol-owned contract, not user-controlled.

**stETH priority:** stETH is sent first (preferred over ETH). This minimizes the need for ETH transfers and is gas-efficient.

**DGNRS transfer (lines 270-285):**
```solidity
if (dgnrsAmount != 0) {
    if (dgnrsAmount <= stethBal) {
        // Approve and deposit stETH to DGNRS
        if (!steth.approve(ContractAddresses.DGNRS, dgnrsAmount)) revert E();
        dgnrs.depositSteth(dgnrsAmount);
    } else {
        // Approve/deposit available stETH + send remainder as ETH
        if (stethBal != 0) {
            if (!steth.approve(ContractAddresses.DGNRS, stethBal)) revert E();
            dgnrs.depositSteth(stethBal);
        }
        uint256 ethAmount = dgnrsAmount - stethBal;
        if (ethAmount != 0) {
            (bool ok, ) = payable(ContractAddresses.DGNRS).call{value: ethAmount}("");
            if (!ok) revert E();
        }
    }
}
```

**DGNRS stETH handling:** Uses `approve` + `depositSteth` pattern (pull-based). The DGNRS contract must implement `depositSteth(uint256)` to pull the approved stETH. If the approve fails (returns false) or `depositSteth` reverts, the entire sweep reverts. **Acceptable -- protocol-owned contract.**

**ETH to DGNRS:** Same `.call{value:}` pattern as VAULT. **Consistent.**

**Interaction between VAULT and DGNRS stETH splits:**
The `stethBal` variable is mutated as stETH is consumed:
1. VAULT gets stETH first (up to `vaultAmount`)
2. `stethBal -= vaultAmount` (or `stethBal = 0` if all stETH sent)
3. DGNRS gets remaining stETH (up to `dgnrsAmount`)

This ensures stETH is not double-counted. Both recipients get their share of stETH + ETH. **PASS -- 50/50 split verified, max 1 wei rounding to VAULT's benefit.**

---

## 3. Iteration Bound Verification

### 3.1 deityPassOwners Array Bounds

**Push location:** `deityPassOwners.push(buyer)` at `DegenerusGameWhaleModule.sol:476` -- the ONLY push in the codebase.

**Purchase guards in WhaleModule `_purchaseDeityPass` (lines 436-509):**
- `symbolId >= 32` reverts (line 437) -- max 32 symbol IDs (0-31)
- `deityBySymbol[symbolId] != address(0)` reverts (line 438) -- each symbol can only be used once
- `deityPassCount[buyer] != 0` reverts (line 439) -- each address can only buy once

These three guards together bound the maximum number of unique entries in `deityPassOwners` to **32**. The constant `DEITY_PASS_MAX_TOTAL = 32` in LootboxModule now matches this bound and is used for deity pass boon availability checks.

**Impact on GameOverModule:** The refund loops at lines 80-93 and 102-116 iterate `deityPassOwners.length`, which is at most 32. Gas cost: ~32 * (2 SLOAD + 1 SSTORE) = ~32 * 25,000 = ~800,000 gas. Well within the block gas limit (30M). **PASS -- bounded and gas-safe.**

### 3.2 Other Loops in GameOverModule

**`_payGameOverBafEthOnly` (lines 167-180):**
```solidity
uint256 len = winners.length;
for (uint256 i; i < len; ) { ... }
```
`winners` comes from `jackpots.runBafJackpot(...)` which allocates a fixed array of size 106 (DegenerusJackpots.sol:234: `new address[](106)`). The returned array may be shorter (sliced), but max is 106 iterations. **Bounded.**

**No other loops in GameOverModule.** Only the deity pass refund loops and the BAF winner credit loop. **All bounded.**

---

## 4. Available Balance Safety Analysis (Underflow Assessment)

### 4.1 Core Safety Check

Both `handleGameOverDrain` (line 124) and `handleFinalSweep` (line 237) use:

```solidity
uint256 available = totalFunds > claimablePool ? totalFunds - claimablePool : 0;
```

**Verdict: SAFE.** The ternary guard prevents underflow wrapping. When `claimablePool >= totalFunds`, `available = 0` and no distribution/sweep occurs. **PASS -- underflow impossible.**

### 4.2 Can totalRefunded Exceed totalFunds?

**Level 0 scenario:** All deity pass payments were deposited into the contract via `msg.value` in `purchaseDeityPass`. At level 0 with `!jackpotPhaseFlag`, no jackpots have been paid, no prizes distributed. The only fund outflows at level 0 are:
- `_awardEarlybirdDgnrs` (DGNRS minting, does not move ETH)
- `_rewardDeityPassDgnrs` (DGNRS minting, does not move ETH)
- `deityPassRefundable` credits (ETH reserved but not moved)

Since deity pass payments enter as ETH and no ETH exits during level 0 (assuming no manual `refundDeityPass` calls), `totalFunds >= sum(deityPassPaidTotal[*])` should hold. After crediting to `claimablePool`, `totalFunds >= claimablePool` should hold. **Safe under normal operation.**

**Exception:** If `refundDeityPass` is called before game-over (see Finding GO-F01 below), ETH exits the contract, but `deityPassPaidTotal` is NOT zeroed. This creates a divergence. See Section 8.

### 4.3 Level 1-9 Scenario

At levels 1-9, some funds may have been spent on jackpots. The fixed 20 ETH/pass refund (max 32 * 20 = 640 ETH) could exceed remaining funds. The ternary guard handles this: if `claimablePool > totalFunds` after refunds, `available = 0`. No BAF/Decimator distribution. **Safe.**

---

## 5. Edge Case Analysis

### 5.1 Zero Deity Pass Owners

If `handleGameOverDrain` is called with `deityPassOwners.length == 0`:
- Level 0 branch: `ownerCount = 0`, loop body never executes, `totalRefunded = 0`, `claimablePool` unchanged.
- Level 1-9 branch: same behavior.
- `available = totalFunds - claimablePool` (could be all funds), all go to BAF/Decimator. **Correct.**

### 5.2 Level 0 with jackpotPhaseFlag == true

Conditions: `currentLevel == 0`, `jackpotPhaseFlag == true`.
- Level 0 branch: `currentLevel == 0 && !jackpotPhaseFlag` is FALSE (jackpotPhaseFlag is true).
- Level 1-9 branch: `currentLevel >= 1 && currentLevel < 10` is FALSE (currentLevel is 0).
- **No refund issued.** All available funds go to BAF/Decimator. This is correct: if jackpot phase was entered (even at level 0), the game has progressed and full refund is inappropriate.

### 5.3 totalFunds == claimablePool

If `totalFunds == claimablePool` (all funds are reserved for claims):
- `available = totalFunds > claimablePool ? ... : 0` evaluates to `0` (not strictly greater).
- Line 130: `if (available == 0) return;` -- early exit.
- `gameOver = true` and `gameOverFinalJackpotPaid = true` are already set (lines 126-128). Terminal state entered. No distribution. **Correct.**

### 5.4 handleGameOverDrain with rngWord == 0

If `rngWordByDay[day] == 0` (no RNG word available for the given day):
- Lines 126-128: `gameOver`, `gameOverTime`, `gameOverFinalJackpotPaid` are set.
- Line 130: `available != 0` (assuming funds exist), continues.
- Line 133: `uint256 rngWord = rngWordByDay[day]` is 0.
- Line 134: `if (rngWord == 0) return;` -- early exit without distribution.

**Result:** Game-over state is set (`gameOver = true`), guard is set (`gameOverFinalJackpotPaid = true`), but NO BAF/Decimator distribution occurs. Funds remain in contract. `handleFinalSweep` can sweep them after 30 days.

This is the scenario documented in Phase 2 finding FSM-F02. **Consistent with prior analysis.**

---

## 6. Cross-Reference with Phase 2 Findings

### 6.1 FSM-F02: handleGameOverDrain Receives Stale dailyIdx (LOW)

**Phase 2 finding:** `handleGameOverDrain` is called with `_dailyIdx` (the state variable value at `advanceGame()` entry), but the RNG word may have been recorded under a different day index (the new `day` computed by `_gameOverEntropy`). This causes `rngWordByDay[_dailyIdx] == 0` at line 133, skipping BAF/Decimator distribution.

**GameOverModule impact:**
- `gameOver = true` and `gameOverFinalJackpotPaid = true` are set regardless.
- BAF/Decimator distribution is silently skipped (line 134 returns early).
- All funds remain in the contract and are accessible via `handleFinalSweep` after 30 days.
- Players' `claimableWinnings` (from deity pass refunds) are preserved.

**Severity confirmation: LOW.** No funds are lost. The BAF/Decimator jackpot selection is skipped, but the same funds are swept to vault/DGNRS after 30 days instead. This is a suboptimal distribution (vault/DGNRS instead of BAF/Decimator winners), not a loss.

### 6.2 FSM-03: Multi-Step Game-Over Sequence (PASS)

**Phase 2 verdict:** Multi-step game-over handles all intermediate states. GameOverModule correctly handles being called at any point because:
- `gameOverFinalJackpotPaid` guard (line 68) prevents re-execution.
- `handleFinalSweep` only activates after `gameOverTime != 0` (line 229) and 30 days have elapsed (line 230).
- The two functions are independent: `handleGameOverDrain` sets up the terminal state, `handleFinalSweep` cleans up after 30 days.

**Confirmed: Consistent with Phase 2 analysis.**

---

## 7. MATH-05 Partial Verdict: Terminal Settlement Fund Distribution

**MATH-05 requirement:** Verify terminal settlement produces correct fund distribution outcomes.

### Fund Flow Summary

```
Total Funds = ETH balance + stETH balance
                |
                v
Deity pass refunds (if applicable)
  - Level 0: Full refund (deityPassPaidTotal per owner)
  - Level 1-9: 20 ETH per pass
  - Level 10+: None
                |
                v
claimablePool += totalRefunded
                |
                v
available = totalFunds - claimablePool (guarded >= 0)
                |
                +--- 50% to BAF Jackpot (credited to winners via claimableWinnings)
                |       |
                |       +--- Unawarded BAF stays in remaining
                |
                +--- Remainder to Decimator Jackpot
                        |
                        +--- Winners credited via claimablePool
                        |
                        +--- Refund (no winners) -> _sendToVault (50/50 VAULT/DGNRS)

After 30 days:
  handleFinalSweep -> available = totalFunds - claimablePool
                        |
                        +--- _sendToVault (50/50 VAULT/DGNRS)
```

### Correctness Assessment

| Property | Status | Evidence |
|----------|--------|----------|
| Re-entry guard prevents double execution | PASS | Line 68: early return if `gameOverFinalJackpotPaid` is true |
| Deity pass level 0 full refund uses correct field | PASS | `deityPassPaidTotal[owner]` (line 82) -- what was actually paid |
| Deity pass level 1-9 fixed refund uses correct field | PASS | `deityPassPurchasedCount[owner]` (line 104) -- number of passes |
| Deity pass level 10+ no refund | PASS | Neither branch entered for `currentLevel >= 10` |
| Available balance cannot underflow | PASS | Ternary guard at lines 124 and 237 |
| BAF gets 50% of available | PASS | `bafPool = remaining / 2` (line 139) |
| Decimator gets remainder | PASS | `remaining` after BAF spend (line 147) |
| _sendToVault 50/50 split VAULT/DGNRS | PASS | `dgnrsAmount = amount/2`, `vaultAmount = amount - dgnrsAmount` (lines 250-251) |
| Rounding dust: max 1 wei, goes to VAULT | PASS | Verified in Section 2.2 |
| claimablePool preserved after sweep | PASS | `handleFinalSweep` does not modify `claimablePool` (Section 2.1) |
| 30-day sweep guard | PASS | `block.timestamp < gameOverTime + 30 days` returns early (line 230) |
| Iteration bounds | PASS | Max 32 deity pass owners (Section 3.1), max 106 BAF winners (Section 3.2) |
| deityPassPaidTotal/deityPassRefundable zeroed after credit | PASS | Lines 88-89 and 111-112 |

**MATH-05 Terminal Settlement Partial Verdict: PASS (conditional on GO-F01 assessment)**

The terminal settlement fund distribution is correct for all normal operation paths. One edge case involving interaction with `refundDeityPass` is documented as finding GO-F01 below.

---

## 8. Findings

### Finding GO-F01: Potential Double Refund via refundDeityPass + handleGameOverDrain Interaction (MEDIUM)

> **POST-AUDIT UPDATE:** This finding is **void**. The `refundDeityPass` function has been removed entirely from the codebase. No `refundDeityPass` function exists in `DegenerusGame.sol` or any other contract. The double-refund scenario described below can no longer occur.

**Severity:** MEDIUM
**Location:** `DegenerusGameGameOverModule.sol:82` and `DegenerusGame.sol:699-728`
**Type:** Accounting inconsistency

**Description:**

The `refundDeityPass` function (DegenerusGame.sol:699-728) allows deity pass holders to claim refunds at level 0 after the refund window opens (day > 730, `DEITY_PASS_REFUND_DAYS`). The function:
1. Reads `deityPassRefundable[buyer]` for the refund amount
2. Zeroes `deityPassRefundable[buyer] = 0`
3. Pulls ETH from `futurePrizePool`/`nextPrizePool`
4. Sends ETH directly to the buyer via `_payoutWithStethFallback`
5. Does **NOT** zero `deityPassPaidTotal[buyer]`
6. Does **NOT** remove the buyer from `deityPassOwners`

If game-over subsequently triggers at level 0 (after day 912, `DEPLOY_IDLE_TIMEOUT_DAYS`), `handleGameOverDrain` (line 82) reads `deityPassPaidTotal[owner]` (still non-zero) and credits the same amount to `claimableWinnings[owner]`, effectively giving the buyer a second refund.

**Attack scenario:**
1. Buyer purchases deity pass at k=0 for 24 ETH
2. At day 731, buyer calls `refundDeityPass` and receives 24 ETH directly
3. At day 913, anyone calls `advanceGame` triggering game-over liveness
4. `handleGameOverDrain` credits `claimableWinnings[buyer] += 24 ETH`
5. Buyer withdraws another 24 ETH from `claimableWinnings`
6. Net: 48 ETH out for 24 ETH in (double refund)

**Conditions required:**
- Level must remain at 0 (game never started)
- `jackpotPhaseFlag` must be false
- Buyer must call `refundDeityPass` between day 731 and day 912
- Game-over must trigger after day 912

**Maximum impact:**
If all 32 deity pass holders refund and then game-over triggers, the total double-refund is up to `sum(deityPassPaidTotal)` = up to ~6224 ETH. In practice, the contract balance may not have enough to honor all double-refund claims, creating a first-come-first-served drain.

**Mitigating factors:**
1. This only applies to the level 0, no-jackpot-phase scenario (game never started).
2. The refund window (day 731-912) is narrow.
3. The `available = totalFunds > claimablePool ? ... : 0` guard prevents underflow, but the `claimableWinnings` credits still exist and can be withdrawn from remaining balance.
4. `refundDeityPass` reduces `futurePrizePool`/`nextPrizePool`, but these are accounting variables for prize allocation -- the actual ETH leaves the contract, reducing `totalFunds` for the game-over computation.

**Recommendation (out of scope for this read-only audit):** Zero `deityPassPaidTotal[buyer]` in `refundDeityPass`, or check `deityPassPaidTotal[owner] > 0` AND `deityPassRefundable[owner] > 0` in the game-over refund loop.

---

### Finding GO-F02: handleGameOverDrain Sets Terminal State Before Distribution (INFORMATIONAL)

**Severity:** INFORMATIONAL
**Location:** `DegenerusGameGameOverModule.sol:126-128` (before lines 139-147)

**Description:**

`gameOver = true` and `gameOverFinalJackpotPaid = true` are set at lines 126-128, BEFORE the BAF and Decimator distribution calls at lines 139-147. If the transaction completes successfully, this ordering is irrelevant. If the distribution calls revert, the entire transaction reverts, rolling back all state changes.

This is not a vulnerability. The ordering places the terminal state flag within the same atomic transaction as the distribution, and EVM atomicity ensures either everything commits or nothing does. However, the Checks-Effects-Interactions pattern conventionally recommends effects before interactions, which this follows correctly.

**Verdict:** No action needed. Pattern is correct for EVM atomicity.

---

### Finding GO-F03: deityPassOwners Bounded by symbolId (32), DEITY_PASS_MAX_TOTAL Aligned — RESOLVED

**Severity:** INFORMATIONAL — **RESOLVED**
**Location:** `DegenerusGameWhaleModule.sol:437,476`, `DegenerusGameLootboxModule.sol:217`

**Description:**

The `deityPassOwners` array is bounded by `symbolId < 32` (WhaleModule:437) and one-pass-per-buyer guards, allowing up to 32 entries. The LootboxModule constant `DEITY_PASS_MAX_TOTAL` has been updated from 24 to 32, aligning with the actual symbol ID space. Deity pass discount boons are now available for all 32 potential passes.

**Verdict:** Resolved. No discrepancy remains.

---

### Finding GO-F04: Cross-Reference: FSM-F02 Stale dailyIdx Skips Distribution (LOW)

> **POST-AUDIT UPDATE:** This finding has been addressed. The `_dailyIdx` parameter is now commented out in `_handleGameOverPath` (AdvanceModule line 335: `uint48 /* _dailyIdx */`), and `handleGameOverDrain` is called with the current `day` value instead of the stale entry-time `dailyIdx`. See the corresponding update on FSM-F02 in 02-04-FINDINGS.

**Severity:** LOW (confirmed from Phase 2)
**Location:** `DegenerusGameAdvanceModule.sol:357-361` -> `DegenerusGameGameOverModule.sol:133-134`

**Description:**

As documented in Phase 2 finding FSM-F02, `handleGameOverDrain` receives the old `dailyIdx` from `advanceGame()` entry, but the RNG word is recorded under the new `day` computed by `_gameOverEntropy`. This causes `rngWordByDay[_dailyIdx] == 0`, and the distribution is skipped (line 134: `if (rngWord == 0) return`).

**GameOverModule-specific impact:**
- `gameOver = true`, `gameOverFinalJackpotPaid = true` are set.
- No BAF or Decimator distribution occurs.
- All `available` funds remain in the contract.
- `handleFinalSweep` after 30 days sends these funds to VAULT/DGNRS (50/50).
- Deity pass refunds are credited regardless (refund loop runs before the rngWord check).

**Confirmed: Consistent with Phase 2 analysis. No escalation needed.**

---

## Summary of Findings

| ID | Severity | Title | Impact |
|----|----------|-------|--------|
| GO-F01 | MEDIUM | Potential double refund via refundDeityPass + handleGameOverDrain | **VOID POST-AUDIT** -- `refundDeityPass` was removed entirely from the codebase |
| GO-F02 | INFORMATIONAL | Terminal state set before distribution calls | Safe due to EVM atomicity, no action needed |
| GO-F03 | INFORMATIONAL | deityPassOwners bounded by 32 (symbolId), DEITY_PASS_MAX_TOTAL aligned | **RESOLVED** — constant updated to 32 |
| GO-F04 | LOW | FSM-F02 cross-reference: stale dailyIdx skips distribution | **FIXED POST-AUDIT** -- `_dailyIdx` param commented out; `day` passed instead |

---

*Audit completed: 2026-03-01*
*Auditor: Claude Opus 4.6*
*No contract files were modified during this audit.*
