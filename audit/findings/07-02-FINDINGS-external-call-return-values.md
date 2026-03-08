# 07-02 FINDINGS: External Call Return Value Audit

**Audited:** 2026-03-01
**Scope:** All stETH, LINK, and BurnieCoin.burnCoin() external call sites across DegenerusGame.sol, DegenerusVault.sol, DegenerusStonk.sol, DegenerusAdmin.sol, BurnieCoin.sol, and delegatecall modules (AdvanceModule, GameOverModule, JackpotModule, MintModule, WhaleModule, DegeneretteModule)
**Requirements:** XCON-02, XCON-04
**Methodology:** Manual source trace with grep enumeration; every call site verified at the source line

---

## 1. stETH Call Site Enumeration

### 1.1 Complete stETH Call Site Table

All `steth.*` call sites across the entire codebase:

| # | File | Line | Function | stETH Method | Return Checked? | Pattern | Notes |
|---|------|------|----------|-------------|-----------------|---------|-------|
| S1 | DegenerusGame.sol | 1840 | `adminSwapEthForStEth` | `balanceOf` | N/A (view) | Read-only | Balance check before transfer |
| S2 | DegenerusGame.sol | 1842 | `adminSwapEthForStEth` | `transfer` | YES: `if (!steth.transfer(...)) revert E()` | Boolean check | Reverts on false |
| S3 | DegenerusGame.sol | 1863 | `adminStakeEthForStEth` | `submit{value}` | INTENTIONAL IGNORE | try/catch, return discarded | See Section 2 deep analysis |
| S4 | DegenerusGame.sol | 1981 | `_transferSteth` | `approve` | YES: `if (!steth.approve(...)) revert E()` | Boolean check | Approval for DGNRS depositSteth |
| S5 | DegenerusGame.sol | 1985 | `_transferSteth` | `transfer` | YES: `if (!steth.transfer(...)) revert E()` | Boolean check | Direct transfer to recipient |
| S6 | DegenerusGame.sol | 2007 | `_payoutWithStethFallback` | `balanceOf` | N/A (view) | Read-only | Balance for payout calculation |
| S7 | DegenerusGame.sol | 2029 | `_payoutWithEthFallback` | `balanceOf` | N/A (view) | Read-only | Balance for payout calculation |
| S8 | DegenerusGame.sol | 2181 | `yieldPoolView` | `balanceOf` | N/A (view) | Read-only | Yield surplus calculation |
| S9 | DegenerusVault.sol | 1031 | `_stethBalance` | `balanceOf` | N/A (view) | Read-only | Private helper |
| S10 | DegenerusVault.sol | 1046 | `_paySteth` | `transfer` | YES: `if (!steth.transfer(...)) revert TransferFailed()` | Boolean check | Reverts TransferFailed |
| S11 | DegenerusVault.sol | 1054 | `_pullSteth` | `transferFrom` | YES: `if (!steth.transferFrom(...)) revert TransferFailed()` | Boolean check | Reverts TransferFailed |
| S12 | DegenerusStonk.sol | 728 | `depositSteth` | `transferFrom` | YES: `if (!steth.transferFrom(...)) revert TransferFailed()` | Boolean check | Pulls stETH from game |
| S13 | DegenerusStonk.sol | 845 | `burn` | `balanceOf` | N/A (view) | Read-only | Pro-rata calculation |
| S14 | DegenerusStonk.sol | 863 | `burn` | `balanceOf` | N/A (view) | Read-only | Refresh after claimWinnings |
| S15 | DegenerusStonk.sol | 892 | `burn` | `transfer` | YES: `if (!steth.transfer(...)) revert TransferFailed()` | Boolean check | Payout to burner |
| S16 | DegenerusStonk.sol | 919 | `previewBurn` | `balanceOf` | N/A (view) | Read-only | Preview calculation |
| S17 | DegenerusStonk.sol | 943 | `totalBacking` | `balanceOf` | N/A (view) | Read-only | Backing calculation |
| S18 | DegenerusStonk.sol | 1027 | `_lockedClaimableValues` | `balanceOf` | N/A (view) | Read-only | Locked value calculation |
| S19 | AdvanceModule.sol | 1006 | `_autoStakeExcessEth` | `submit{value}` | SILENT CATCH | try/catch, catch is empty | See Section 2 deep analysis |
| S20 | GameOverModule.sol | 74 | `handleGameOverDrain` | `balanceOf` | N/A (view) | Read-only | Total funds calculation |
| S21 | GameOverModule.sol | 233 | `handleFinalSweep` | `balanceOf` | N/A (view) | Read-only | Sweep calculation |
| S22 | GameOverModule.sol | 255 | `_sendToVault` | `transfer` | YES: `if (!steth.transfer(...)) revert E()` | Boolean check | Transfer to VAULT |
| S23 | GameOverModule.sol | 259 | `_sendToVault` | `transfer` | YES: `if (!steth.transfer(...)) revert E()` | Boolean check | Partial transfer to VAULT |
| S24 | GameOverModule.sol | 272 | `_sendToVault` | `approve` | YES: `if (!steth.approve(...)) revert E()` | Boolean check | Approval for DGNRS |
| S25 | GameOverModule.sol | 276 | `_sendToVault` | `approve` | YES: `if (!steth.approve(...)) revert E()` | Boolean check | Partial approval for DGNRS |
| S26 | JackpotModule.sol | 868 | `_distributeYieldSurplus` | `balanceOf` | N/A (view) | Read-only | Yield surplus calculation |

**Summary:** 26 total stETH call sites found.
- 10 `balanceOf` calls: all view/read-only, no return value check needed
- 7 `transfer` calls: ALL checked with `if (!result) revert`
- 2 `transferFrom` calls: ALL checked with `if (!result) revert`
- 3 `approve` calls: ALL checked with `if (!result) revert`
- 2 `submit` calls: both use try/catch (see deep analysis below)

**Result: Zero unchecked state-changing stETH calls.** Every transfer/transferFrom/approve has a boolean return check. Both submit calls use try/catch.

---

## 2. Deep Analysis: stETH.submit() Return Value

### Site S3: DegenerusGame.sol:1863 -- `adminStakeEthForStEth`

```solidity
// stETH return value intentionally ignored: Lido mints 1:1 for ETH, validated by input checks
try steth.submit{value: amount}(address(0)) returns (uint256) {} catch {
    revert E();
}
```

**Analysis:**

a. **Code comment present:** Explicitly documents the intentional ignore with reasoning.

b. **Lido 1:1 deposit model:** When `submit()` succeeds, Lido accepts the ETH and mints stETH to the caller. The stETH balance increases by approximately the ETH amount deposited (subject to 1-2 wei rounding from Lido's share-based accounting). The game does NOT use the return value for accounting -- it tracks ETH pools (claimablePool, currentPrizePool, etc.) and uses `steth.balanceOf(address(this))` for stETH balance queries. This means the return value is genuinely unnecessary.

c. **Return value is shares, not stETH amount:** Lido's `submit()` returns the number of stETH **shares** minted, not the stETH token amount. The share count differs from the stETH amount due to the rebasing mechanism. Using this value directly for ETH-denominated accounting would be a bug. The intentional ignore is therefore the **correct** approach.

d. **try/catch catches reverts:** If Lido's staking is paused, at capacity, or any other revert condition occurs, the catch block fires and reverts with `E()`. No silent failure is possible -- either the submit succeeds (ETH converts to stETH) or the entire transaction reverts.

e. **Verdict: Ignoring the return value is CORRECT and SAFE.** The return value (shares) would be misleading for accounting; the try/catch ensures no silent failures.

### Site S19: AdvanceModule.sol:1006 -- `_autoStakeExcessEth`

```solidity
/// @dev Stake all ETH above claimablePool into stETH via Lido.
///      Uses try/catch so stETH is never a hard dependency -- game
///      continues even if Lido is paused or the call reverts.
function _autoStakeExcessEth() private {
    uint256 ethBal = address(this).balance;
    uint256 reserve = claimablePool;
    if (ethBal <= reserve) return;
    uint256 stakeable = ethBal - reserve;
    try steth.submit{value: stakeable}(address(0)) returns (uint256) {} catch {}
}
```

**Analysis:**

a. This is an **auto-staking optimization** called during `advanceGame()` to earn yield on idle ETH. The empty catch block is intentional -- the code comment explicitly states "game continues even if Lido is paused or the call reverts."

b. **Same return-value-is-shares reasoning as S3** applies. Not using the return value is correct.

c. **Silent catch is safe here** because:
   - The ETH remains in the game contract if staking fails (not lost)
   - The game's accounting is ETH-pool-based and does not depend on stETH staking succeeding
   - The `claimablePool` reserve check ensures player funds are never staked
   - This is a best-effort yield optimization, not a critical path

d. **Verdict: Silent catch on auto-stake is CORRECT and SAFE.** The ETH is preserved regardless, and the game must not halt if Lido is unavailable.

---

## 3. Deep Analysis: stETH Transfer Return Values

### S2: DegenerusGame.sol:1842 -- `adminSwapEthForStEth`
```solidity
if (!steth.transfer(recipient, amount)) revert E();
```
- Boolean return checked with `!`
- Reverts `E()` on false return
- No code path continues after failure
- SAFE

### S4: DegenerusGame.sol:1981 -- `_transferSteth` (DGNRS path)
```solidity
if (!steth.approve(ContractAddresses.DGNRS, amount)) revert E();
```
- Boolean return checked
- Followed by `dgnrs.depositSteth(amount)` only on success
- SAFE

### S5: DegenerusGame.sol:1985 -- `_transferSteth` (direct path)
```solidity
if (!steth.transfer(to, amount)) revert E();
```
- Boolean return checked
- Terminal statement in function
- SAFE

### S10: DegenerusVault.sol:1046 -- `_paySteth`
```solidity
if (!steth.transfer(to, amount)) revert TransferFailed();
```
- Boolean return checked
- Terminal statement
- SAFE

### S11: DegenerusVault.sol:1054 -- `_pullSteth`
```solidity
if (!steth.transferFrom(from, address(this), amount)) revert TransferFailed();
```
- Boolean return checked
- amount == 0 early return protects against unnecessary calls
- SAFE

### S12: DegenerusStonk.sol:728 -- `depositSteth`
```solidity
if (!steth.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();
```
- Boolean return checked
- SAFE

### S15: DegenerusStonk.sol:892 -- `burn`
```solidity
if (!steth.transfer(player, stethOut)) revert TransferFailed();
```
- Boolean return checked
- Guarded by `if (stethOut > 0)` before call
- SAFE

### S22-S25: GameOverModule.sol:255, 259, 272, 276 -- `_sendToVault`
All four stETH operations (2 transfers, 2 approvals) follow the same `if (!result) revert E()` pattern.
- SAFE

**Summary: All 12 state-changing stETH calls (7 transfer, 2 transferFrom, 3 approve) are correctly checked.** The pattern is consistent: boolean return value negated with `!`, followed by immediate revert. No code path ever continues after a false return.

**Note on stETH behavior:** Lido's stETH implementation returns `true` on success and `false` on failure (it does not revert on insufficient balance for transfers). The `if (!result) revert` pattern is the correct way to handle stETH. Using `require(result)` would be equivalent but the explicit revert with named error is preferred.

---

## 4. stETH Callback / Reentrancy Verification

### 4.1 stETH is NOT ERC-677

Lido's stETH is a standard rebasing ERC-20 token. Key properties:

- **transfer():** Standard ERC-20 transfer. Does NOT call `onTokenTransfer` or any callback on the recipient. No reentrancy vector.
- **transferFrom():** Standard ERC-20 transferFrom with allowance check. No callback mechanism.
- **approve():** Standard ERC-20 approval. No callback.
- **submit(address referral):** Accepts ETH, mints stETH shares. The `referral` parameter is **informational only** -- Lido records it for analytics/tracking but does NOT call the referral address. The protocol uses `address(0)` as the referral, which further eliminates any theoretical concern.
- **balanceOf():** View function, no state changes possible.

### 4.2 Conclusion

**stETH operations are reentrancy-safe.** There is no callback mechanism in any stETH function used by the protocol. The only potential reentrancy vector from stETH would be if it were an ERC-777 or ERC-677 token (which it is not). The rebasing mechanism operates at the share level and does not trigger any external calls.

---

## 5. LINK Call Site Enumeration

### 5.1 Complete LINK Call Site Table

All `linkToken.*` call sites in DegenerusAdmin.sol:

| # | File | Line | Function | LINK Method | Return Checked? | Pattern | Notes |
|---|------|------|----------|------------|-----------------|---------|-------|
| L1 | DegenerusAdmin.sol | 515 | `emergencyRecover` | `balanceOf` | N/A (view) | Read-only | Check balance before transfer |
| L2 | DegenerusAdmin.sol | 519 | `emergencyRecover` | `transferAndCall` | YES: try/catch + `ok` check | try/catch with bool | See Section 6 |
| L3 | DegenerusAdmin.sol | 557 | `shutdownAndRefund` | `balanceOf` | N/A (view) | Read-only | Check balance before sweep |
| L4 | DegenerusAdmin.sol | 559 | `shutdownAndRefund` | `transfer` | YES: `if (!linkToken.transfer(...)) revert LinkTransferFailed()` | Boolean check | Reverts LinkTransferFailed |
| L5 | DegenerusAdmin.sol | 595 | `onTokenTransfer` | (sender check) | N/A (access control) | `msg.sender != LINK_TOKEN` | See Section 7 |
| L6 | DegenerusAdmin.sol | 613 | `onTokenTransfer` | `transferAndCall` | YES: try/catch + `ok` check | try/catch with bool | See Section 6 |

**Summary:** 6 LINK-related sites.
- 2 `balanceOf` calls: view-only, no check needed
- 1 `transfer` call: checked with boolean return
- 2 `transferAndCall` calls: both in try/catch with `ok` result check
- 1 sender validation: access control check

**Result: Zero unchecked LINK state-changing calls.**

---

## 6. Deep Analysis: LINK.transferAndCall() Return Values and Reentrancy

### L2: DegenerusAdmin.sol:519 -- `emergencyRecover`

```solidity
uint256 bal = linkToken.balanceOf(address(this));
uint256 funded;
if (bal != 0) {
    try
        linkToken.transferAndCall(
            newCoordinator,
            bal,
            abi.encode(newSubId)
        )
    returns (bool ok) {
        if (ok) {
            funded = bal;
        }
    } catch {}
}
```

**Analysis:**

a. **try/catch wraps the call:** YES. Both the `returns (bool ok)` and the catch block are present.

b. **ok return value checked:** YES. The `if (ok)` condition only records `funded = bal` when the transfer actually succeeded.

c. **catch block behavior:** The empty `catch {}` means a revert from `transferAndCall` is silently absorbed. This is **intentional and correct** for `emergencyRecover` -- this is an emergency recovery function that should complete even if LINK transfer fails. The LINK simply stays on the Admin contract. The `funded` variable correctly records 0 in this case.

d. **Reentrancy:** The recipient is `newCoordinator`, a trusted Chainlink VRF coordinator address. Chainlink's `VRFCoordinatorV2_5` processes the LINK via `onTokenTransfer` to fund a subscription but does NOT call back to `DegenerusAdmin`. The flow terminates at the coordinator. No reentrancy vector.

### L6: DegenerusAdmin.sol:613 -- `onTokenTransfer`

```solidity
try
    linkToken.transferAndCall(coord, amount, abi.encode(subId))
returns (bool ok) {
    if (!ok) revert InvalidAmount();
} catch {
    revert InvalidAmount();
}
```

**Analysis:**

a. **try/catch wraps the call:** YES.

b. **ok return value checked:** YES. `if (!ok) revert InvalidAmount()` reverts on false return.

c. **catch block reverts:** YES. `catch { revert InvalidAmount(); }` ensures no silent continuation. Both failure paths (false return and revert) cause the entire `onTokenTransfer` callback to revert.

d. **Reentrancy analysis of the full flow:**
   1. External sender calls `LINK.transferAndCall(adminAddr, amount, data)`
   2. LINK token transfers LINK to Admin, then calls `Admin.onTokenTransfer(from, amount, data)`
   3. Admin validates `msg.sender == LINK_TOKEN` (line 595)
   4. Admin calls `linkToken.transferAndCall(coord, amount, abi.encode(subId))` to forward LINK to VRF coordinator
   5. LINK token transfers LINK to coordinator, then calls `coordinator.onTokenTransfer(adminAddr, amount, data)`
   6. Coordinator processes the subscription funding. **Coordinator does NOT call back to Admin.**
   7. Flow returns to Admin, which calculates rewards and credits BURNIE.

   **No reentrancy loop exists.** The coordinator is a trusted Chainlink contract that accepts LINK for subscription funding without calling back to the sender. The chain terminates at step 6.

### L4: DegenerusAdmin.sol:559 -- `shutdownAndRefund`

```solidity
if (!linkToken.transfer(target, bal)) revert LinkTransferFailed();
```

- Standard boolean check with dedicated `LinkTransferFailed` error
- Called only when `gameOver()` is true
- SAFE

---

## 7. Deep Analysis: DegenerusAdmin.onTokenTransfer

```solidity
function onTokenTransfer(
    address from,
    uint256 amount,
    bytes calldata
) external {
    // SECURITY: Only accept calls from the LINK token contract.
    if (msg.sender != ContractAddresses.LINK_TOKEN) revert NotAuthorized();
    if (amount == 0) revert InvalidAmount();
    ...
}
```

### 7.1 Sender Validation

**Line 595:** `if (msg.sender != ContractAddresses.LINK_TOKEN) revert NotAuthorized();`

- **Polarity is correct:** Reverts when sender is NOT the LINK token. Only the actual LINK token contract can trigger this callback.
- This prevents fake LINK attacks where a malicious contract could call `onTokenTransfer` directly to claim rewards without actually transferring LINK.

### 7.2 Callback Flow

The `onTokenTransfer` function:
1. Validates sender is LINK token (line 595)
2. Validates amount > 0 (line 596)
3. Checks subscription exists (line 598-599)
4. Checks game is not over (line 602)
5. Reads current subscription balance from coordinator (line 606-608)
6. Calculates reward multiplier (line 609)
7. Forwards LINK to VRF subscription via `transferAndCall` (lines 612-618) -- reverts on failure
8. Credits BURNIE reward to donor via `coinLinkReward.creditLinkRewardFlipStake` (further down)

### 7.3 Reentrancy Analysis

The reentrancy chain is: `LINK.transferAndCall -> Admin.onTokenTransfer -> LINK.transferAndCall -> Coordinator.onTokenTransfer -> (END)`.

The coordinator is a trusted Chainlink contract that does NOT call back to Admin during `onTokenTransfer` processing. The chain terminates at the coordinator. Even if a malicious coordinator existed, the `msg.sender != LINK_TOKEN` check at the entry of `onTokenTransfer` would prevent it from re-entering, because the coordinator's callback would have `msg.sender == LINK_TOKEN` which calls `Admin.onTokenTransfer` -- but this is actually the LINK token calling, not the coordinator. However, in practice, the second `transferAndCall` (Admin -> Coordinator) triggers `Coordinator.onTokenTransfer`, not `Admin.onTokenTransfer`, so there is no recursive call.

**Conclusion: No reentrancy vector.** The LINK callback chain is linear and terminates at the VRF coordinator.

---

## 8. BurnieCoin.burnCoin() Call Site Enumeration

### 8.1 Complete burnCoin Call Site Table

| # | File | Line | Function | Caller Context | Via Delegatecall? | Revert Propagation |
|---|------|------|----------|----------------|-------------------|-------------------|
| B1 | AdvanceModule.sol | 1175 | `reverseFlip` | `coin.burnCoin(msg.sender, cost)` | YES (delegatecall from Game) | Reverts propagate through delegatecall to `_revertDelegate` |
| B2 | DegeneretteModule.sol | 594 | `_handleBet` (BURNIE path) | `coin.burnCoin(player, totalBet)` | YES (delegatecall from Game) | Reverts propagate through delegatecall to `_revertDelegate` |
| B3 | MintModule.sol | 946 | `_coinReceive` | `coin.burnCoin(payer, amount)` | YES (delegatecall from Game) | Reverts propagate through delegatecall to `_revertDelegate` |
| B4 | MintModule.sol | 960 | `_purchaseBurnieLootboxFor` | `coin.burnCoin(buyer, burnieAmount)` | YES (delegatecall from Game) | Reverts propagate through delegatecall to `_revertDelegate` |
| B5 | WhaleModule.sol | 545 | `_handleDeityPassTransfer` | `IDegenerusCoin(COIN).burnCoin(from, burnAmount)` | YES (delegatecall from Game) | Reverts propagate through delegatecall to `_revertDelegate` |

### 8.2 Delegatecall Context Verification

All five call sites are in modules that execute via `delegatecall` from `DegenerusGame.sol`. When a module calls `coin.burnCoin(...)`:

1. The `delegatecall` executes the module code in the context of the Game contract
2. The `coin.burnCoin(...)` call is an external call FROM the Game contract TO the BurnieCoin contract
3. `msg.sender` in BurnieCoin's `onlyTrustedContracts` modifier is `ContractAddresses.GAME` (the Game contract address), which is allowed
4. If `burnCoin` reverts (insufficient balance), the revert propagates back through the delegatecall
5. In Game's dispatch, `(bool ok, bytes memory data) = MODULE.delegatecall(...); if (!ok) _revertDelegate(data);` catches the failure and re-reverts with the original error

**Note on B5 (WhaleModule):** This uses `IDegenerusCoin(ContractAddresses.COIN).burnCoin(from, burnAmount)` with an explicit address cast rather than a storage variable. This is functionally identical -- it still executes in the delegatecall context of the Game contract.

### 8.3 Revert Propagation Confirmation

For each call site, if `burnCoin` reverts:
- The external call returns `false` to the delegatecall frame
- The delegatecall returns `ok = false` to Game
- `_revertDelegate(data)` re-throws the revert reason
- The original transaction reverts

**No code path assumes burnCoin succeeds silently.** Each call site either:
- Is the last operation before state writes that depend on success (B1: emit after burn), or
- Precedes state writes that should only execute on success (B3, B4: quest tracking after burn), or
- Is followed by state changes that are safe to skip on revert (B2, B5: entire delegatecall frame reverts)

---

## 9. BurnieCoin.burnCoin() Internal Behavior Verification

### 9.1 BurnieCoin._burn() (line 488)

```solidity
function _burn(address from, uint256 amount) internal {
    if (from == address(0)) revert ZeroAddress();
    uint128 amount128 = _toUint128(amount);
    if (from == ContractAddresses.VAULT) {
        uint128 allowanceVault = _supply.vaultAllowance;
        if (amount128 > allowanceVault) revert Insufficient();
        unchecked {
            _supply.vaultAllowance = allowanceVault - amount128;
        }
        emit VaultAllowanceSpent(from, amount);
        return;
    }
    // Solidity 0.8+ reverts on underflow if balanceOf[from] < amount
    balanceOf[from] -= amount;
    _supply.totalSupply -= amount128;
    emit Transfer(from, address(0), amount);
}
```

**Revert conditions:**
- `from == address(0)`: reverts `ZeroAddress()`
- VAULT path: `amount128 > allowanceVault`: reverts `Insufficient()`
- Normal path: `balanceOf[from] -= amount` underflows: **Solidity 0.8+ automatic revert** (arithmetic underflow). The code comment at line 500 explicitly documents this: "Solidity 0.8+ reverts on underflow if balanceOf[from] < amount"
- `_toUint128(amount)` reverts if amount > type(uint128).max

**Conclusion:** `_burn` ALWAYS reverts on insufficient balance. There is no silent failure path.

### 9.2 _consumeCoinflipShortfall (line 580)

```solidity
function _consumeCoinflipShortfall(address player, uint256 amount) private returns (uint256 consumed) {
    if (amount == 0) return 0;
    if (degenerusGame.rngLocked()) return 0;
    uint256 balance = balanceOf[player];
    if (balance >= amount) return 0;
    unchecked {
        return IBurnieCoinflip(coinflipContract).consumeCoinflipsForBurn(
            player,
            amount - balance
        );
    }
}
```

**Analysis:**

- If `balance >= amount`: returns 0, meaning `_burn` will burn the full `amount` (which will succeed since balance is sufficient)
- If `balance < amount`: attempts to consume coinflip credits for the shortfall (`amount - balance`)
- The `consumed` value is subtracted from `amount` before `_burn`: `_burn(target, amount - consumed)`
- If `consumed + balanceOf[target] < amount`, the `_burn` call will still revert on underflow
- **`_consumeCoinflipShortfall` cannot mask a burn failure** -- it only reduces the burn amount by the coinflip credits consumed. If the remaining amount exceeds the balance, `_burn` still reverts.

### 9.3 onlyTrustedContracts Modifier (line 619)

```solidity
modifier onlyTrustedContracts() {
    address sender = msg.sender;
    if (
        sender != ContractAddresses.GAME &&
        sender != ContractAddresses.AFFILIATE
    ) revert OnlyTrustedContracts();
    _;
}
```

- Restricts `burnCoin` callers to GAME and AFFILIATE contracts only
- All 5 module call sites execute via delegatecall from GAME, so `msg.sender` is GAME
- No unauthorized contract can call `burnCoin`

### 9.4 Return Value

`burnCoin` has no return value -- its signature is `function burnCoin(address target, uint256 amount) external onlyTrustedContracts`. Failure is communicated exclusively through revert. This is the correct pattern for delegatecall callers, because:
- A revert propagates through delegatecall as `ok = false`
- Game's `_revertDelegate(data)` re-throws the error
- The calling transaction reverts entirely

**No path creates free nudges or coinflips:** If `burnCoin` fails (e.g., player lacks BURNIE), the entire delegatecall frame reverts, undoing all state changes in that call. The player cannot receive a nudge (B1) or place a bet (B2, B3, B4) or transfer a deity pass (B5) without the burn succeeding.

---

## 10. XCON-02 Verdict: stETH + LINK Return Values

### Requirements

1. All stETH call sites checked or intentionally-ignored with documented reasoning
2. All LINK call sites checked via try/catch or boolean check
3. No callback reentrancy vectors

### Evidence

| Criterion | Status | Evidence |
|-----------|--------|----------|
| stETH transfer/transferFrom/approve return values checked | PASS | 12/12 state-changing calls use `if (!result) revert` pattern (S2, S4, S5, S10, S11, S12, S15, S22-S25) |
| stETH.submit() return value handling safe | PASS | 2 sites: S3 uses try/catch with revert on failure (return intentionally ignored -- shares vs amount); S19 uses silent catch for best-effort auto-staking (ETH preserved on failure) |
| stETH balanceOf correctly used | PASS | 10 view calls used for balance checks and calculations; no state-changing reliance on return value |
| LINK transferAndCall return values checked | PASS | 2/2 sites use try/catch with `ok` boolean check (L2, L6) |
| LINK transfer return value checked | PASS | 1/1 site uses `if (!result) revert LinkTransferFailed()` (L4) |
| stETH callback reentrancy | PASS | stETH is standard ERC-20 (not ERC-677/ERC-777); no callbacks on transfer/submit/approve |
| LINK callback reentrancy | PASS | LINK ERC-677 callback chain terminates at VRF coordinator; no recursive re-entry to Admin |
| Admin.onTokenTransfer sender validation | PASS | `msg.sender != LINK_TOKEN` check at line 595 with correct polarity |

### XCON-02 VERDICT: **PASS**

All 26 stETH and 6 LINK call sites across 6 contracts and 3 modules are correctly handled. Every state-changing external call either checks its boolean return value and reverts on failure, or uses try/catch with explicit error handling. The stETH.submit() return value ignore is intentional and correct (return is shares, not stETH amount). No reentrancy vectors exist through stETH or LINK callbacks.

---

## 11. XCON-04 Verdict: BurnieCoin.burnCoin() Safety

### Requirements

1. burnCoin reverts on insufficient balance
2. Revert propagates correctly through delegatecall
3. No path creates free nudges or coinflips

### Evidence

| Criterion | Status | Evidence |
|-----------|--------|----------|
| _burn reverts on insufficient balance | PASS | Solidity 0.8+ underflow revert on `balanceOf[from] -= amount` (line 501); explicit `Insufficient` revert for VAULT path |
| _consumeCoinflipShortfall cannot mask failure | PASS | Only reduces burn amount by consumed coinflip credits; if remaining > balance, _burn still reverts |
| Revert propagates through delegatecall | PASS | All 5 call sites in delegatecall modules; Game catches with `if (!ok) _revertDelegate(data)` at every dispatch site |
| No code assumes silent success | PASS | All call sites either terminate on success or are followed by operations that revert together if burn fails |
| onlyTrustedContracts correctly restricts | PASS | Only GAME and AFFILIATE can call; all module calls route through GAME via delegatecall |
| No free nudges (reverseFlip) | PASS | B1: `coin.burnCoin(msg.sender, cost)` -- if burn reverts, delegatecall reverts, no nudge recorded |
| No free bets (degenerette) | PASS | B2: `coin.burnCoin(player, totalBet)` -- if burn reverts, delegatecall reverts, no bet placed |
| No free purchases (mint) | PASS | B3, B4: burn precedes all state changes; revert undoes entire delegatecall |
| No free deity transfers (whale) | PASS | B5: burn precedes ownership transfer; revert undoes entire delegatecall |

### XCON-04 VERDICT: **PASS**

BurnieCoin.burnCoin() is revert-based with no return value, which is the correct pattern for delegatecall callers. The `_burn` function reverts on insufficient balance via Solidity 0.8+ underflow protection. The `_consumeCoinflipShortfall` helper cannot mask failures. All 5 module call sites correctly propagate reverts through the delegatecall dispatch pattern. No path exists to obtain gameplay benefits (nudges, bets, purchases, transfers) without the burn succeeding.

---

## 12. Additional Observations

### 12.1 DegenerusStonk.sol stETH Sites (Bonus Coverage)

The plan scope specified DegenerusGame.sol and DegenerusVault.sol, but grep enumeration revealed 7 additional stETH call sites in DegenerusStonk.sol (S12-S18). All are correctly handled:
- 1 transferFrom (S12): boolean checked
- 1 transfer (S15): boolean checked
- 5 balanceOf (S13, S14, S16, S17, S18): view calls, no check needed

### 12.2 Delegatecall Module stETH Sites (Bonus Coverage)

3 additional stETH sites found in delegatecall modules (S19, S20-S21, S22-S26). All are correctly handled. The AdvanceModule's silent catch on `submit` (S19) is documented and intentional.

### 12.3 Consistency of Error Pattern

stETH failures in DegenerusGame.sol and modules use `revert E()` (catch-all error). DegenerusVault.sol and DegenerusStonk.sol use `revert TransferFailed()` (dedicated error). DegenerusAdmin.sol uses `revert LinkTransferFailed()` for LINK. All patterns are functionally equivalent -- the specific error name is a developer ergonomics choice, not a safety concern.
