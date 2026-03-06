# Phase 4 Plan 04: Exhaustive Reentrancy Analysis of ETH-Sending Functions

**Requirement:** ACCT-04
**Audited:** 2026-03-01 (original), 2026-03-06 (updated for contract changes)
**Scope:** DegenerusGame.sol + all 10 delegatecall modules
**Critical context:** No `ReentrancyGuard` or `nonReentrant` modifier exists anywhere in the protocol. CEI is the sole protection.

---

## Table of Contents

1. [Part A: claimWinnings CEI Verification](#part-a-claimwinnings-cei-verification)
2. [Part B: Exhaustive Reachable Function Enumeration](#part-b-exhaustive-reachable-function-enumeration)
3. [Part C: Payout Helper Analysis](#part-c-payout-helper-analysis-payoutwithstethfallback--payoutwithethfallback)
4. [Part D: refundDeityPass Status](#part-d-refunddeitypass-status)
5. [Part E: handleGameOverDrain / handleFinalSweep Reentrancy](#part-e-handlegameoverdrain--handlefinalsweep-reentrancy)
6. [Part F: Cross-Function Reentrancy Scenarios](#part-f-cross-function-reentrancy-scenarios)
7. [Slither Cross-Check](#slither-cross-check)
8. [ACCT-04 Verdict](#acct-04-verdict)

---

## Part A: claimWinnings CEI Verification

### Source: `DegenerusGame.sol` lines 1420-1435

```solidity
function _claimWinningsInternal(address player, bool stethFirst) private {
    uint256 amount = claimableWinnings[player];       // CHECK: read balance
    if (amount <= 1) revert E();                      // CHECK: must have > 1 wei
    uint256 payout;
    unchecked {
        claimableWinnings[player] = 1;                // EFFECT: set sentinel
        payout = amount - 1;                          // EFFECT: calculate net
    }
    claimablePool -= payout;                          // EFFECT: decrement aggregate
    emit WinningsClaimed(player, msg.sender, payout); // EFFECT: emit event
    if (stethFirst) {
        _payoutWithEthFallback(player, payout);       // INTERACTION: external call
    } else {
        _payoutWithStethFallback(player, payout);     // INTERACTION: external call
    }
}
```

### CEI Analysis

| Step | What | Line | Before External Call? |
|------|------|------|-----------------------|
| CHECK | Read `claimableWinnings[player]` | 1421 | YES |
| CHECK | Revert if `amount <= 1` | 1422 | YES |
| EFFECT | `claimableWinnings[player] = 1` (sentinel) | 1425 | YES |
| EFFECT | `claimablePool -= payout` | 1428 | YES |
| EFFECT | `emit WinningsClaimed(...)` | 1429 | YES |
| INTERACTION | `_payoutWithStethFallback` or `_payoutWithEthFallback` | 1431/1433 | N/A (this IS the call) |

**Verification 1: No state writes after external call.** Confirmed. Lines 1430-1434 are the payout call and then the function ends at line 1435 with `}`. No state is written after the external call.

**Verification 2: Reentrant self-claim blocked.** If attacker's `receive()` calls `claimWinnings()` again for the same `player`:
- `claimableWinnings[player]` is already set to 1 (sentinel)
- `amount = 1`, check `amount <= 1` is TRUE
- Reverts with `E()`
- **SAFE: Self-reentrancy into claimWinnings is blocked by the sentinel.**

**Verification 3: claimablePool consistency.** `claimablePool -= payout` executes before the external call. If the attacker reenters any function that reads `claimablePool`, it will see the already-decremented value. This prevents double-counting.

### Entry Points

There are two public entry points into `_claimWinningsInternal`:

1. `claimWinnings(address player)` (line 1404): Calls `_resolvePlayer(player)` then `_claimWinningsInternal(player, false)`. Available to any approved operator or the player themselves.

2. `claimWinningsStethFirst()` (line 1411): Restricted to `msg.sender == VAULT || msg.sender == DGNRS`. These are protocol contracts at known addresses. Calls `_claimWinningsInternal(msg.sender, true)`.

The second entry point is safe by access control -- only protocol contracts (VAULT, DGNRS) can call it, not arbitrary attackers.

### CEI Verdict: CORRECT

The CEI pattern is correctly implemented. All state mutations (`claimableWinnings[player] = 1`, `claimablePool -= payout`) occur BEFORE the external call. No state writes occur after the interaction.

---

## Part B: Exhaustive Reachable Function Enumeration

When `_payoutWithStethFallback` or `_payoutWithEthFallback` sends ETH via `call{value:}("")`, the recipient's `receive()` or `fallback()` function executes. From within that callback, an attacker contract can call ANY external function on `DegenerusGame`.

### Mid-Claim State

During the ETH callback from `_claimWinningsInternal`, the contract's state is:

- `claimableWinnings[attacker] = 1` (sentinel, already written)
- `claimablePool` has been decremented by `payout`
- ETH balance of the contract has been reduced by the amount already sent
- `msg.sender` within the callback is the DegenerusGame contract (since DegenerusGame called the attacker)

### Function-by-Function Analysis

| # | Function | Access Guard | rngLockedFlag Guard | Mid-Claim State Conflict | Verdict |
|---|----------|-------------|---------------------|--------------------------|---------|
| 1 | `claimWinnings(player)` | `_resolvePlayer` | None | `claimableWinnings[attacker] = 1` -- reverts `amount <= 1` | **SAFE** |
| 2 | `claimWinningsStethFirst()` | `VAULT` or `DGNRS` only | None | Attacker cannot call this function | **SAFE** |
| 3 | `purchase()` (DirectEth) | `_resolvePlayer` | Partial (lootbox blocked if `rngLockedFlag && lastPurchaseDay && jackpotLevel`) | `msg.value = 0` in callback; `msg.value < amount` reverts. See detailed analysis below. | **SAFE** |
| 4 | `purchase()` (Claimable) | `_resolvePlayer` | Same as #3 | `claimableWinnings[attacker] = 1`; spending claimable requires `claimable > amount`; 1 wei is not enough to purchase anything meaningful. | **SAFE** |
| 5 | `purchase()` (Combined) | `_resolvePlayer` | Same as #3 | Same as #4; claimable portion limited to 0 wei usable (sentinel is 1, available = 0). Combined uses msg.value first then claimable for remainder. | **SAFE** |
| 6 | `purchaseCoin()` | `_resolvePlayer` | RNG check in module | BURNIE-only purchases; no ETH pool impact | **SAFE** |
| 7 | `purchaseBurnieLootbox()` | None | None | BURNIE-only; no ETH impact | **SAFE** |
| 8 | `purchaseWhaleBundle()` | `_resolvePlayer` | `gameOver` check | Requires exact `msg.value == totalPrice`. Within callback, `msg.value = 0`. Would revert. | **SAFE** |
| 9 | `purchaseLazyPass()` | `_resolvePlayer` | `gameOver` check | Requires `msg.value == totalPrice`. Within callback, `msg.value = 0`. Would revert. | **SAFE** |
| 10 | `purchaseDeityPass()` | `_resolvePlayer` | `gameOver` check | Requires `msg.value == totalPrice`. Within callback, `msg.value = 0`. Would revert. | **SAFE** |
| 11 | `placeFullTicketBets()` (ETH) | `_resolvePlayer` | ETH bets: `jackpotResolutionActive` guard; `ethPaid > totalBet` validation | Within callback, `msg.value = 0`. ETH bet with 0 payment: `ethPaid < totalBet`, tries `claimableWinnings[player] - fromClaimable`, but claimable = 1 and bet minimum is `MIN_BET_ETH`. Would revert. | **SAFE** |
| 12 | `placeFullTicketBets()` (BURNIE) | `_resolvePlayer` | None specific | Burns BURNIE, no ETH impact | **SAFE** |
| 13 | `placeFullTicketBetsFromAffiliateCredit()` | `_resolvePlayer` | None | Consumes affiliate credit, BURNIE-only | **SAFE** |
| 14 | `resolveDegeneretteBets()` | `_resolvePlayer` | `rngWord == 0` check | Does not send ETH; credits `claimableWinnings` + `claimablePool`. See Part F scenario #2. | **SAFE** (see Part F) |
| 15 | `advanceGame()` | None | Delegatecall to AdvanceModule | No direct ETH conflict. State changes are pool rotations and RNG processing. Does not send ETH to attacker. | **SAFE** |
| 16 | `receive()` | None | `gameOver` check | `futurePrizePool += msg.value`. Benign; attacker would need to send ETH. | **SAFE** |
| 17 | `recordMint()` | `msg.sender == address(this)` | N/A | Self-call only; attacker cannot call this | **SAFE** |
| 18 | `recordCoinflipDeposit()` | `COIN` or `COINFLIP` only | N/A | Access restricted | **SAFE** |
| 19 | `recordMintQuestStreak()` | `COIN` only | N/A | Access restricted | **SAFE** |
| 20 | `payCoinflipBountyDgnrs()` | `COIN` or `COINFLIP` only | N/A | Access restricted | **SAFE** |
| 21 | `setOperatorApproval()` | None | None | Sets `operatorApprovals[msg.sender][operator]`. Here `msg.sender` would be the attacker contract. No ETH impact. | **SAFE** |
| 22 | `setLootboxRngThreshold()` | `ADMIN` only | N/A | Access restricted | **SAFE** |
| 23 | `onDeityPassTransfer()` | `DEITY_PASS` only | N/A | Access restricted | **SAFE** |
| 24 | `openLootBox()` | `_resolvePlayer` | Requires RNG ready | Credits tickets/rewards via lootbox module; no ETH sent to player | **SAFE** |
| 25 | `openBurnieLootBox()` | `_resolvePlayer` | Requires RNG ready | BURNIE rewards only | **SAFE** |
| 26 | `consumeDecClaim()` | `address(this)` only | N/A | Self-call only | **SAFE** |
| 27 | `claimDecimatorJackpot()` | None | None | Credits `claimableWinnings` via `_addClaimableEth`. See Part F for cross-function analysis. | **SAFE** (see Part F) |
| 28 | `claimWhalePass()` | `_resolvePlayer` | None | Credits tickets via EndgameModule; no direct ETH transfer | **SAFE** |
| 29 | `setAutoRebuy()` | `_resolvePlayer` | `rngLockedFlag` | Sets config flags; no ETH impact | **SAFE** |
| 30 | `setDecimatorAutoRebuy()` | `_resolvePlayer` | `rngLockedFlag` | Sets config flags; no ETH impact | **SAFE** |
| 31 | `adminSwapEthForStEth()` | `ADMIN` only | N/A | Access restricted | **SAFE** |
| 32 | `adminStakeEthForStEth()` | `ADMIN` only | N/A | Access restricted | **SAFE** |
| 33 | `requestLootboxRng()` | None | Internal checks | Delegatecall to AdvanceModule; VRF request, no ETH transfer | **SAFE** |
| 34 | `reverseFlip()` | `_resolvePlayer` | `rngLockedFlag` | Burns BURNIE for nudge; no ETH impact | **SAFE** |
| 35 | `rawFulfillRandomWords()` | VRF coordinator only | N/A | Access restricted | **SAFE** |
| 36 | `updateVrfCoordinatorAndSub()` | `ADMIN` only | N/A | Access restricted | **SAFE** |
| 37 | `wireVrf()` | `ADMIN` only | N/A | Access restricted | **SAFE** |
| 38 | `deactivateAfKingFromCoin()` | `COIN` or `COINFLIP` only | N/A | Access restricted | **SAFE** |
| 39 | `claimAffiliateDgnrs()` | `_resolvePlayer` | None | Transfers DGNRS tokens, no ETH | **SAFE** |
| 40 | All `*View()` functions | None | None | Read-only; no state changes | **SAFE** |

### Detailed Analysis: purchase() During Mid-Claim

A critical subtlety: when the attacker's `receive()` is called by `_payoutWithStethFallback`, the `msg.sender` context inside that callback is `address(DegenerusGame)` (since DegenerusGame is the one sending ETH). When the attacker contract then calls `purchase()` on DegenerusGame:
- `msg.sender` = attacker contract address
- `_resolvePlayer(buyer)` resolves to buyer (attacker or specified address)
- `msg.value` = 0 (no ETH sent with the callback call)
- For `DirectEth` purchase: `msg.value < amount` reverts
- For `Claimable` purchase: `claimableWinnings[player] = 1`, so `claimable <= amount` (1 <= any meaningful cost), reverts
- For `Combined` purchase: `msg.value = 0`, remainder needs claimable, `claimable = 1`, `available = 0`, `remaining != 0` reverts

**All purchase paths during mid-claim revert due to insufficient funds.** SAFE.

### Detailed Analysis: msg.sender Context in Reentrant Calls

When DegenerusGame sends ETH to an attacker contract via `call{value:}("")`:
- Inside the attacker's `receive()`: `msg.sender = address(DegenerusGame)`
- When attacker calls back into DegenerusGame: `msg.sender = address(attacker_contract)`

This means `_resolvePlayer(address(0))` resolves to the attacker contract address, and `_resolvePlayer(someAddress)` requires the attacker to be an approved operator. The attacker can only operate on accounts they control or are approved for.

---

## Part C: Payout Helper Analysis (_payoutWithStethFallback / _payoutWithEthFallback)

### _payoutWithStethFallback (lines 1967-1994)

```solidity
function _payoutWithStethFallback(address to, uint256 amount) private {
    if (amount == 0) return;
    // 1. Try ETH first
    uint256 ethBal = address(this).balance;
    uint256 ethSend = amount <= ethBal ? amount : ethBal;
    if (ethSend != 0) {
        (bool okEth, ) = payable(to).call{value: ethSend}("");   // <-- CALLBACK 1
        if (!okEth) revert E();
    }
    uint256 remaining = amount - ethSend;
    if (remaining == 0) return;
    // 2. stETH fallback
    uint256 stBal = steth.balanceOf(address(this));
    uint256 stSend = remaining <= stBal ? remaining : stBal;
    _transferSteth(to, stSend);                                   // <-- stETH transfer
    // 3. Retry ETH
    uint256 leftover = remaining - stSend;
    if (leftover != 0) {
        uint256 ethRetry = address(this).balance;
        if (ethRetry < leftover) revert E();
        (bool ok, ) = payable(to).call{value: leftover}("");      // <-- CALLBACK 2
        if (!ok) revert E();
    }
}
```

**Analysis: Up to TWO ETH callbacks + ONE stETH transfer**

This function can trigger up to 3 external calls:
1. **ETH call #1** (line 1974): Sends available ETH. Triggers attacker `receive()`.
2. **stETH transfer** (line 1983 via `_transferSteth`): ERC-20 `transfer()` call to Lido stETH. Does NOT trigger `receive()` on the recipient. See stETH analysis below.
3. **ETH call #2** (line 1991): Only if stETH was insufficient to cover remainder. Triggers attacker `receive()` again.

**Is the double-callback exploitable?**

Between Callback 1 and Callback 2:
- `claimableWinnings[attacker]` is already 1 (set before the payout helper was called)
- `claimablePool` is already decremented (set before the payout helper was called)
- The only state that changes between callbacks is the contract's ETH balance (reduced by `ethSend`)

The second callback triggers with `leftover` ETH. The same reentrancy protections apply -- all state was already updated before `_payoutWithStethFallback` was even called. The second callback gives the attacker no additional leverage beyond what they had during the first callback. **SAFE.**

### _payoutWithEthFallback (lines 2000-2014)

```solidity
function _payoutWithEthFallback(address to, uint256 amount) private {
    if (amount == 0) return;
    // 1. stETH first
    uint256 stBal = steth.balanceOf(address(this));
    uint256 stSend = amount <= stBal ? amount : stBal;
    _transferSteth(to, stSend);                                   // <-- stETH transfer
    // 2. ETH fallback
    uint256 remaining = amount - stSend;
    if (remaining == 0) return;
    uint256 ethBal = address(this).balance;
    if (ethBal < remaining) revert E();
    (bool ok, ) = payable(to).call{value: remaining}("");          // <-- CALLBACK
    if (!ok) revert E();
}
```

**Analysis: At most ONE stETH transfer + ONE ETH callback.** Same CEI protections apply. SAFE.

### stETH Transfer Callback Risk

**Question:** Can Lido's `stETH.transfer()` trigger a callback on the recipient?

**Answer: No.** Lido stETH implements a standard ERC-20 `transfer`. It is NOT an ERC-777 token (no `tokensReceived` hook). The `transfer()` function modifies internal share balances and emits a `Transfer` event. It does not call any function on the recipient. stETH's `transfer` is a standard `_transfer` that updates `shares[from]` and `shares[to]` -- no external calls to the recipient.

Additionally, `_transferSteth` (line 1952) has special handling for `ContractAddresses.DGNRS` -- it uses `steth.approve()` then `dgnrs.depositSteth()`. This calls into the DGNRS contract (a known protocol address), not an attacker. For all other recipients, it's a standard `steth.transfer(to, amount)`. **SAFE.**

---

## Part D: refundDeityPass Status

**IMPORTANT UPDATE (2026-03-06):** The `refundDeityPass` function has been REMOVED from the codebase. It no longer exists in `DegenerusGame.sol` or any module. A grep for `refundDeityPass` across the entire `contracts/` directory returns zero results.

The storage variable `deityPassRefundable` still exists in `DegenerusGameStorage.sol` (line 1208) for storage layout compatibility, but no code reads or writes to it.

**Impact on reentrancy analysis:** The removal of `refundDeityPass` eliminates an entire ETH-sending function from the reentrancy attack surface. This is a strictly positive change for security.

**Previous analysis (historical, from v1.0 audit):** The original audit confirmed `refundDeityPass` was safe from reentrancy via `deityPassRefundable[buyer] = 0` before external call. With its removal, this analysis point is moot.

**GO-F01 Cross-Reference:** Phase 3b-02 identified GO-F01 MEDIUM (double-refund path via `refundDeityPass` + `handleGameOverDrain`). This finding is now void -- `refundDeityPass` does not exist. The deity pass gameOver refund in `handleGameOverDrain` uses `deityPassPurchasedCount` (not `deityPassRefundable`), so the two-path double-refund vector is eliminated.

---

## Part E: handleGameOverDrain / handleFinalSweep Reentrancy

Both functions execute via delegatecall from `advanceGame()` through the AdvanceModule, which delegates to `GAME_GAMEOVER_MODULE`.

### handleGameOverDrain (GameOverModule lines 70-151)

**External calls made:**
1. `IDegenerusGame(address(this)).runDecimatorJackpot(...)` (line 130): Self-call (trusted).
2. `IDegenerusGame(address(this)).runTerminalJackpot(...)` (line 142): Self-call (trusted).
3. `_sendToVault(remaining, stBal)` (line 148): Sends ETH/stETH to VAULT and DGNRS (trusted protocol addresses).

**CEI Analysis:**
- `gameOver = true` (line 114) is set BEFORE any external distribution calls
- `gameOverFinalJackpotPaid = true` (line 116) is set BEFORE any external calls
- Deity pass refund credits happen in a loop (lines 85-108) BEFORE external distribution calls
- `claimablePool` increments for deity refunds (line 107) happen BEFORE external calls

**Self-reentrancy guard:** `if (gameOverFinalJackpotPaid) return;` (line 71). Once set to `true` at line 116, any reentrant call immediately returns. **SAFE.**

**Note on _sendToVault (lines 182-219):**
The `_sendToVault` function sends ETH to VAULT and DGNRS via `call{value:}`. These are protocol contracts at fixed addresses. Even if they had `receive()` functions that called back into DegenerusGame:
- `gameOverFinalJackpotPaid = true` would cause `handleGameOverDrain` to early-return
- `gameOver = true` would block most game operations (purchase, whale bundle, lazy pass, deity pass, receive())
- The recipients are trusted protocol contracts that do not reenter

**Verdict: SAFE.**

### handleFinalSweep (GameOverModule lines 158-176)

```solidity
function handleFinalSweep() external {
    if (gameOverTime == 0) return;
    if (block.timestamp < uint256(gameOverTime) + 30 days) return;

    // Shutdown VRF subscription (fire-and-forget; failure must not block sweep)
    try admin.shutdownVrf() {} catch {}

    uint256 ethBal = address(this).balance;
    uint256 stBal = steth.balanceOf(address(this));
    uint256 totalFunds = ethBal + stBal;
    uint256 available = totalFunds > claimablePool ? totalFunds - claimablePool : 0;
    if (available == 0) return;

    _sendToVault(available, stBal);
}
```

**CEI Analysis:** This function has NO state mutations before the external call `_sendToVault`. It reads balances, calculates `available`, and sends. There is no guard against re-calling it.

**Reentrancy concern:** If `_sendToVault` sends ETH to VAULT, and VAULT reenters `advanceGame()` which triggers `handleFinalSweep` again:
1. The function reads `address(this).balance` again -- now lower because ETH was just sent
2. `steth.balanceOf(address(this))` -- may be lower if stETH was transferred
3. `available` will be recalculated with lower balances
4. If `available > 0`, it would try to send again

However, this re-call would NOT cause fund loss beyond what is `available` (excess over `claimablePool`). Each recursive call sends less because balances decrease. The function converges to `available = 0`. Furthermore:
- VAULT and DGNRS are trusted protocol contracts at fixed addresses
- Neither has a `receive()` that calls back into DegenerusGame
- The AdvanceModule only calls `handleFinalSweep` inside the liveness guard path, which requires `gameOver = true` and `block.timestamp >= gameOverTime + 30 days`
- An attacker cannot directly call `handleFinalSweep` on DegenerusGame (it's only accessible via delegatecall from advanceModule during `advanceGame()`)

**Theoretical risk (INFORMATIONAL):** If VAULT or DGNRS had a malicious `receive()` that called `advanceGame()`, and `advanceGame()` triggered `handleFinalSweep` again, funds could be drained incrementally. But this is a trusted-protocol-contracts scenario, not an external attacker scenario. Both VAULT and DGNRS are deployed by the protocol and their code is fixed.

**Verdict: SAFE (recipients are trusted protocol contracts).**

---

## Part F: Cross-Function Reentrancy Scenarios

### Scenario 1: Claim -> Purchase -> Claim

**Attack vector:** Attacker claims winnings, in the `receive()` callback calls `purchase()` to buy tickets with fresh ETH (msg.value from external funding), which triggers auto-rebuy crediting new `claimableWinnings`, then claims again.

**Analysis:**
1. `_claimWinningsInternal` sets `claimableWinnings[attacker] = 1`
2. Attacker's `receive()` fires. Attacker calls `purchase()` with fresh ETH.
3. In `purchase()`, `msg.value = 0` inside the callback (the attacker received ETH, they are not sending new ETH). To send ETH in a reentrant call, the attacker contract must have its own ETH balance and explicitly forward it via `purchase{value: x}()`.
4. Even if the attacker funds the purchase with pre-loaded ETH, tickets do NOT immediately credit `claimableWinnings`. Tickets are queued for processing by `advanceGame()`. The credit to `claimableWinnings` happens later (during jackpot distribution in a separate transaction).
5. Purchase via `Claimable` mode: `claimableWinnings[attacker] = 1`, `available = 0`, reverts.
6. Second `claimWinnings()` call: `amount = 1`, reverts `amount <= 1`.

**Verdict: SAFE.** Purchase does not immediately credit `claimableWinnings`. The sentinel blocks re-claiming. Even with external ETH funding for the purchase, no new claimable is created within the same transaction.

### Scenario 2: Claim -> Degenerette Resolve -> Claim

**Attack vector:** Attacker claims, in `receive()` calls `resolveDegeneretteBets()` which wins ETH, credits `claimableWinnings`, then tries second claim.

**Analysis:**
1. `_claimWinningsInternal` sets `claimableWinnings[attacker] = 1`, decrements `claimablePool`
2. Attacker's `receive()` fires. Attacker calls `resolveDegeneretteBets()` with pending bet IDs.
3. `resolveBets()` -> `_resolveFullTicketBet()` -> `_distributePayout()`:
   - For ETH wins: `_addClaimableEth(player, ethPortion)` (DegeneretteModule line 1168)
   - `_addClaimableEth` does: `claimablePool += weiAmount; claimableWinnings[beneficiary] += weiAmount;`
   - Current state: `claimableWinnings[attacker] = 1`
   - After credit: `claimableWinnings[attacker] = 1 + ethPortion`
   - `claimablePool` is incremented by `ethPortion`
4. Attacker calls `claimWinnings()` again:
   - `amount = claimableWinnings[attacker] = 1 + ethPortion`
   - `amount > 1` -- does NOT revert!
   - `payout = amount - 1 = ethPortion`
   - `claimablePool -= ethPortion`
   - Sends `ethPortion` ETH to attacker

**Is this exploitable?** The attacker receives their degenerette winnings AND the payout from the first claim. But this is NOT a double-spend or value extraction:
- The first claim paid out `originalPayout` (the ETH being sent when the callback triggered)
- The degenerette resolve genuinely won `ethPortion` ETH from `futurePrizePool`
- The second claim withdraws the legitimate `ethPortion` winnings
- `claimablePool` was properly incremented by `_addClaimableEth` before being decremented by the second claim
- The invariant `balance >= claimablePool` holds because: the degenerette payout comes from `futurePrizePool` (which is not part of `claimablePool`), and `claimablePool` was correctly incremented then decremented

**The attacker is simply receiving their legitimate winnings in a single transaction instead of two.** No extra value is extracted. The ETH paid out in the second claim was legitimately won from the degenerette game and properly accounted for in `claimablePool`.

**Key insight:** The sentinel (`claimableWinnings = 1`) prevents re-claiming the SAME balance, but does not prevent claiming NEW credits added by other operations within the same transaction. This is correct behavior -- the new credits represent genuinely earned value, not a double-spend.

**Verdict: SAFE. No value extraction beyond what is legitimately earned.**

### Scenario 3: Claim -> claimDecimatorJackpot -> Claim

**Attack vector:** Attacker claims, in `receive()` calls `claimDecimatorJackpot()` which credits `claimableWinnings`, then claims again.

**Analysis:**
1. `_claimWinningsInternal` sets `claimableWinnings[attacker] = 1`
2. `claimDecimatorJackpot` delegates to DecimatorModule. If attacker is a valid decimator winner:
   - `_addClaimableEth(msg.sender, amountWei, ...)` credits `claimableWinnings[attacker] += amountWei`
   - After: `claimableWinnings[attacker] = 1 + amountWei`
   - `claimablePool += amountWei`
3. Second `claimWinnings()`: `amount = 1 + amountWei > 1`, succeeds
4. Attacker receives decimator payout

Same analysis as Scenario 2: the attacker is claiming legitimately earned decimator rewards. The invariant holds because `claimablePool` was properly incremented. **No extra value extracted.**

**Verdict: SAFE.**

### Scenario 4: Claim -> adminSwapEthForStEth

**Attack vector:** Attacker claims, in `receive()` calls `adminSwapEthForStEth`.

**Analysis:** Requires `msg.sender == ContractAddresses.ADMIN`. Attacker contract is not ADMIN.

**Verdict: SAFE (access control).**

### Scenario 5: Claim -> advanceGame -> handleGameOverDrain

**Attack vector:** Attacker claims winnings, in `receive()` calls `advanceGame()` which triggers `handleGameOverDrain`, potentially distributing funds.

**Analysis:**
1. `advanceGame()` requires meeting the daily mint gate and day advancement conditions
2. Even if conditions are met, `handleGameOverDrain` sets `gameOverFinalJackpotPaid = true` as its guard
3. If `handleGameOverDrain` was already called (likely, since game over triggers it), the early return fires
4. If this is the first call, `gameOver = true` is set, blocking most operations
5. Funds distributed go to jackpot winners and vault -- not to the attacker's claimable
6. `claimablePool` has already been decremented by the first claim

**Verdict: SAFE.** No mechanism to redirect gameOver distribution to benefit the attacker.

### Scenario 6: handleGameOverDrain -> _sendToVault -> reentrant handleGameOverDrain

**Attack vector:** During game over settlement, `_sendToVault` sends ETH to VAULT, which reenters and triggers `handleGameOverDrain` again.

**Analysis:**
1. `gameOverFinalJackpotPaid = true` is set at line 116, BEFORE `_sendToVault` is called at line 148
2. Any reentrant call hits `if (gameOverFinalJackpotPaid) return;` at line 71 and returns immediately
3. VAULT is a trusted protocol contract that does not reenter

**Verdict: SAFE.**

---

## Slither Cross-Check

### Execution

```
$ ~/.local/bin/slither contracts/DegenerusGame.sol --detect reentrancy-eth,reentrancy-no-eth --hardhat-ignore-compile
```

**Result: 0 reentrancy-eth, 3 reentrancy-no-eth**

Slither found ZERO `reentrancy-eth` findings -- the detector specifically designed to find ETH-draining reentrancy vulnerabilities. This confirms the manual analysis: no exploitable reentrancy path exists for ETH extraction.

### reentrancy-no-eth Findings (all false positives)

**Finding 1: `_deactivateAfKing(address)`**
- Writes `state.afKingMode = false` after external call to `coinflip.settleFlipModeChange(player)`
- **Assessment: FALSE POSITIVE.** `coinflip` (BurnieCoinflip) is a trusted protocol contract at compile-time constant address. Cannot be called by an attacker. The `autoRebuyState` write after the call is intentional -- settling flip mode must happen before toggling afKing mode off to ensure consistent state.

**Finding 2: `_setAfKingMode(address,bool,uint256,uint256)`**
- Writes `state.afKingMode = true` after external calls to `coinflip.setCoinflipAutoRebuy(...)` and `coinflip.settleFlipModeChange(...)`
- **Assessment: FALSE POSITIVE.** Same as Finding 1. Trusted protocol contract. The ordering is intentional: set coinflip state first, then mark afKing as active.

**Finding 3: `claimAffiliateDgnrs(address)`**
- Writes `affiliateDgnrsClaimedBy[prevLevel][player] = true` after external calls to `dgnrs.transferFromPool(...)` and `coin.creditFlip(...)`
- **Assessment: FALSE POSITIVE in practice.** Both `dgnrs` (DegenerusStonk) and `coin` (BurnieCoin) are trusted protocol contracts at compile-time constant addresses. A malicious DGNRS/COIN contract could theoretically re-enter and double-claim, but both contracts are protocol-deployed and immutable. Additionally, even if re-entered, the DGNRS `poolBalance` would be reduced by the first transfer, limiting the second claim's value.

### Slither Summary

| Detector | Findings | Real Vulnerabilities |
|----------|----------|---------------------|
| `reentrancy-eth` | 0 | 0 |
| `reentrancy-no-eth` | 3 | 0 (all trusted protocol contracts) |

All 3 reentrancy-no-eth findings involve state writes after external calls to trusted, protocol-deployed contracts (BurnieCoinflip, DegenerusStonk, BurnieCoin) at compile-time constant addresses. These are not exploitable by external attackers.

---

## ACCT-04 Verdict

### Requirement: `claimWinnings()` cannot be reentered to drain funds

### Sub-Verdicts

| Question | Answer | Evidence |
|----------|--------|----------|
| Is claimWinnings safe from self-reentrancy? | **YES** | Sentinel `claimableWinnings[player] = 1` set before external call. Reentrant call sees `amount = 1`, reverts `amount <= 1`. (DegenerusGame.sol lines 1425, 1422) |
| Is claimWinnings safe from cross-function reentrancy? | **YES** | All 40 external functions enumerated. Access-restricted functions (20+) unreachable by attacker. Payable functions (7) require `msg.value > 0` which is 0 in callback. Claimable-spending functions (3) see sentinel of 1 wei, insufficient for any purchase. Degenerette/Decimator resolve can add NEW credits but these are legitimate winnings, not double-spends. |
| Is handleGameOverDrain safe from self-reentrancy? | **YES** | `gameOverFinalJackpotPaid = true` set before distribution calls. Reentrant call returns immediately at line 71. Recipients are trusted protocol contracts. |
| Is handleFinalSweep safe from reentrancy? | **YES** | No mutable state to protect (reads balances, sends excess). Recipients are trusted protocol contracts (VAULT, DGNRS). Theoretical recursive call converges to zero. |
| Are payout helpers safe from double-callback? | **YES** | All CEI mutations occur before `_payoutWithStethFallback`/`_payoutWithEthFallback` is called. Multiple callbacks within payout helpers do not provide additional attack surface. stETH transfer does not trigger recipient callbacks. |
| Does Slither detect any ETH reentrancy? | **NO** | 0 reentrancy-eth findings. 3 reentrancy-no-eth findings, all involving trusted protocol contracts (false positives). |

### Note on refundDeityPass

`refundDeityPass` has been removed from the codebase. It is no longer an attack surface. The deity pass gameOver refund in `handleGameOverDrain` credits `claimableWinnings` (pull pattern) rather than sending ETH directly, so it introduces no reentrancy risk.

### Overall Verdict

## ACCT-04: PASS

The protocol's CEI-only reentrancy protection (without ReentrancyGuard) is correctly implemented across all ETH-sending functions:

1. **claimWinnings**: Sentinel pattern + aggregate pool decrement before external call. Provably safe against both self and cross-function reentrancy.

2. **handleGameOverDrain**: `gameOverFinalJackpotPaid` flag set before distributions. `gameOver = true` blocks most game operations. All recipients are trusted protocol contracts.

3. **handleFinalSweep**: Stateless sweep function. Recipients are trusted protocol contracts.

4. **Payout helpers**: No state changes within helpers; all mutations happen in callers before invoking helpers. stETH transfers do not trigger callbacks.

5. **refundDeityPass**: REMOVED from codebase. No longer an attack surface.

No finding was identified. The absence of `ReentrancyGuard` does not create an exploitable vulnerability because the CEI pattern is consistently and correctly applied in all ETH-sending function families.

---

## Summary of ETH-Sending Functions

| Function | ETH Transfer Method | CEI Guard | Reentrancy Risk |
|----------|-------------------|-----------|-----------------|
| `_claimWinningsInternal` | `_payoutWithStethFallback`/`_payoutWithEthFallback` | Sentinel `= 1` + `claimablePool -=` | SAFE |
| `handleGameOverDrain._sendToVault` | `call{value:}` to VAULT/DGNRS | `gameOverFinalJackpotPaid = true` + `gameOver = true` | SAFE (trusted recipients) |
| `handleFinalSweep._sendToVault` | `call{value:}` to VAULT/DGNRS | Stateless; trusted recipients | SAFE (trusted recipients) |
| `refundDeityPass` | REMOVED | N/A | N/A (no longer exists) |
