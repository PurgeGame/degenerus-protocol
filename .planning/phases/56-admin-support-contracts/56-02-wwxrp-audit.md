# WrappedWrappedXRP.sol -- Function-Level Audit

**Contract:** WrappedWrappedXRP
**File:** contracts/WrappedWrappedXRP.sol
**Lines:** 395
**Solidity:** 0.8.34
**Audit date:** 2026-03-07

## Summary

Parody ERC20 token (WWXRP -- "Wrapped Wrapped WWXRP") with intentionally undercollateralized design. The contract holds wXRP reserves that may be less than totalSupply at any time. Unwrapping is first-come-first-served against available reserves. Privileged minting for Game, BurnieCoin, and BurnieCoinflip mints unbacked tokens (increasing the deficit). The Vault can mint from a 1B WWXRP uncirculating reserve. A donate mechanism allows anyone to deposit wXRP to improve the backing ratio. Wrapping (depositing wXRP to receive WWXRP 1:1) is disabled -- the wrap event NatSpec remains as an orphan. CEI pattern is enforced on unwrap (burn before external wXRP transfer).

---

## Function Audit

### Constructor

No explicit constructor is defined. State is initialized via:
- `totalSupply` defaults to 0
- `vaultAllowance` initialized to `INITIAL_VAULT_ALLOWANCE` (1B ether) at declaration
- All compile-time constants sourced from ContractAddresses library

---

### `approve(address spender, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function approve(address spender, uint256 amount) external returns (bool)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `spender` (address): address authorized to spend; `amount` (uint256): maximum spend limit |
| **Returns** | `bool`: always true |

**State Reads:** None
**State Writes:** `allowance[msg.sender][spender]` set to `amount`

**Callers:** External only (any EOA or contract)
**Callees:** None

**ETH Flow:** No
**Invariants:** Allowance is set unconditionally (overwrite semantics). No zero-address check on spender (standard ERC20 behavior -- approve to address(0) is allowed but harmless).
**NatSpec Accuracy:** Accurate. Documents revert conditions via @custom:reverts but no actual reverts in this function -- however the function itself has no revert conditions, so the NatSpec on the function is fine (the revert tags are on transfer/transferFrom, not here).
**Gas Flags:** None
**Verdict:** CORRECT

---

### `transfer(address to, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function transfer(address to, uint256 amount) external returns (bool)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): transfer amount |
| **Returns** | `bool`: always true (reverts on failure) |

**State Reads:** `balanceOf[msg.sender]` (via `_transfer`)
**State Writes:** `balanceOf[msg.sender]` decremented, `balanceOf[to]` incremented (via `_transfer`)

**Callers:** External only (any EOA or contract)
**Callees:** `_transfer(msg.sender, to, amount)`

**ETH Flow:** No
**Invariants:** Sum of all balances unchanged. Neither `from` nor `to` can be address(0).
**NatSpec Accuracy:** Accurate. @custom:reverts correctly lists ZeroAddress and InsufficientBalance.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `transferFrom(address from, address to, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function transferFrom(address from, address to, uint256 amount) external returns (bool)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): source; `to` (address): destination; `amount` (uint256): transfer amount |
| **Returns** | `bool`: always true (reverts on failure) |

**State Reads:** `allowance[from][msg.sender]`, `balanceOf[from]` (via `_transfer`)
**State Writes:** `allowance[from][msg.sender]` decremented (unless unlimited), `balanceOf[from]` decremented, `balanceOf[to]` incremented (via `_transfer`)

**Callers:** External only (any EOA or contract). Used by DegenerusStonk for proportional WWXRP payouts on burn.
**Callees:** `_transfer(from, to, amount)`

**ETH Flow:** No
**Invariants:** Sum of all balances unchanged. Allowance decremented unless `type(uint256).max` (unlimited pattern). Emits Approval event on allowance update.
**NatSpec Accuracy:** Accurate. Correctly documents unlimited allowance pattern and all revert conditions.
**Gas Flags:** None. The Approval event emission on allowance change is a reasonable design choice for ERC20 compatibility.
**Verdict:** CORRECT

---

### `_transfer(address from, address to, uint256 amount)` [internal]

| Field | Value |
|-------|-------|
| **Signature** | `function _transfer(address from, address to, uint256 amount) internal` |
| **Visibility** | internal |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): source; `to` (address): destination; `amount` (uint256): transfer amount |
| **Returns** | None |

**State Reads:** `balanceOf[from]`
**State Writes:** `balanceOf[from]` decremented by `amount`, `balanceOf[to]` incremented by `amount`

**Callers:** `transfer()`, `transferFrom()`
**Callees:** None (emits Transfer event)

**ETH Flow:** No
**Invariants:** Reverts if `from` or `to` is address(0). Reverts if `balanceOf[from] < amount`. Balance conservation: total balances unchanged (debit equals credit). No overflow risk on `balanceOf[to] += amount` in practice because totalSupply caps the sum, though no explicit check (Solidity 0.8+ overflow protection applies).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_mint(address to, uint256 amount)` [internal]

| Field | Value |
|-------|-------|
| **Signature** | `function _mint(address to, uint256 amount) internal` |
| **Visibility** | internal |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): mint amount |
| **Returns** | None |

**State Reads:** None (implicit read of `totalSupply` and `balanceOf[to]` for increment)
**State Writes:** `totalSupply` incremented by `amount`, `balanceOf[to]` incremented by `amount`

**Callers:** `mintPrize()`, `vaultMintTo()`
**Callees:** None (emits Transfer event from address(0))

**ETH Flow:** No
**Invariants:** Reverts if `to` is address(0). No zero-amount check (callers handle this). `totalSupply` always equals sum of all `balanceOf` entries. Overflow protection via Solidity 0.8+.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_burn(address from, uint256 amount)` [internal]

| Field | Value |
|-------|-------|
| **Signature** | `function _burn(address from, uint256 amount) internal` |
| **Visibility** | internal |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): burn source; `amount` (uint256): burn amount |
| **Returns** | None |

**State Reads:** `balanceOf[from]`
**State Writes:** `balanceOf[from]` decremented by `amount`, `totalSupply` decremented by `amount`

**Callers:** `unwrap()`, `burnForGame()`
**Callees:** None (emits Transfer event to address(0))

**ETH Flow:** No
**Invariants:** Reverts if `from` is address(0). Reverts if `balanceOf[from] < amount`. `totalSupply` decremented safely (cannot underflow because `balanceOf[from] >= amount` and totalSupply >= balanceOf[from]).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `unwrap(uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function unwrap(uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `amount` (uint256): amount of WWXRP to unwrap (18 decimals) |
| **Returns** | None |

**State Reads:** `wXRPReserves`, `balanceOf[msg.sender]` (via `_burn`)
**State Writes:** `wXRPReserves` decremented by `amount`, `balanceOf[msg.sender]` decremented (via `_burn`), `totalSupply` decremented (via `_burn`)

**Callers:** External only (any WWXRP holder)
**Callees:** `_burn(msg.sender, amount)`, `wXRP.transfer(msg.sender, amount)` (external call to wXRP ERC20)

**ETH Flow:** No ETH. Moves wXRP tokens: contract reserves -> caller.
**Invariants:**
- Reverts if `amount == 0` (ZeroAmount)
- Reverts if `wXRPReserves < amount` (InsufficientReserves) -- first-come-first-served design
- Reverts if `balanceOf[msg.sender] < amount` (InsufficientBalance via `_burn`)
- Reverts if wXRP.transfer fails (TransferFailed)
- CEI pattern enforced: `_burn()` (state changes) executes before `wXRP.transfer()` (external call)
- After execution: `wXRPReserves` decreases by `amount`, `totalSupply` decreases by `amount`
- The backing ratio (wXRPReserves / totalSupply) may improve, stay same, or worsen depending on relative values

**NatSpec Accuracy:** Accurate. Correctly documents CEI pattern, first-come-first-served semantics, and all revert conditions.
**Gas Flags:** None
**Verdict:** CORRECT -- CEI pattern properly prevents reentrancy. The `wXRPReserves` decrement before external call ensures reserves cannot be double-spent even if wXRP token has a callback.

---

### `donate(uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function donate(uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `amount` (uint256): amount of wXRP to donate (18 decimals) |
| **Returns** | None |

**State Reads:** None (only `wXRPReserves` for increment)
**State Writes:** `wXRPReserves` incremented by `amount`

**Callers:** External only (any address with wXRP balance and approval)
**Callees:** `wXRP.transferFrom(msg.sender, address(this), amount)` (external call to wXRP ERC20)

**ETH Flow:** No ETH. Moves wXRP tokens: donor -> contract.
**Invariants:**
- Reverts if `amount == 0` (ZeroAmount)
- Reverts if wXRP.transferFrom fails (TransferFailed -- insufficient wXRP balance or allowance)
- `wXRPReserves` increases without minting WWXRP, improving the backing ratio
- No WWXRP is minted -- pure reserve increase
- Note: `wXRPReserves` is updated AFTER external call (not strict CEI), but this is safe because `wXRP.transferFrom` pulls tokens INTO the contract (no value leaves), and the only risk would be reentrancy calling `donate` again which would just donate more (donor's loss)

**NatSpec Accuracy:** Accurate. Correctly describes purpose and revert conditions.
**Gas Flags:** None
**Verdict:** CORRECT -- The non-CEI ordering (external call before state write) is safe here because (a) value flows inward, (b) reentrancy would only donate more of caller's own wXRP, and (c) wXRP is a standard ERC20 without callbacks.

---

### `mintPrize(address to, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function mintPrize(address to, uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): mint amount (18 decimals) |
| **Returns** | None |

**State Reads:** None (access control uses compile-time constants)
**State Writes:** `totalSupply` incremented (via `_mint`), `balanceOf[to]` incremented (via `_mint`)

**Callers:** External only, restricted to authorized minters:
- `DegenerusGameLootboxModule.sol` (line 1580): mints 1 WWXRP as lootbox prize
- `DegenerusGameDegeneretteModule.sol` (lines 728, 749): mints payout and consolation prizes
- `BurnieCoinflip.sol` (line 615): mints `lossCount * 1 WWXRP` as coinflip loss reward

**Callees:** `_mint(to, amount)`

**ETH Flow:** No
**Invariants:**
- Reverts if caller is not MINTER_GAME, MINTER_COIN, or MINTER_COINFLIP (OnlyMinter)
- Reverts if `amount == 0` (ZeroAmount)
- Reverts if `to == address(0)` (ZeroAddress via `_mint`)
- Mints WITHOUT backing -- increases totalSupply without increasing wXRPReserves
- Intentionally worsens the backing ratio (by design -- "joke token")

**NatSpec Accuracy:** Accurate. Correctly documents unbacked minting behavior and all revert conditions. Note: the error used is `OnlyMinter` which is shared with `burnForGame` (which only allows MINTER_GAME), while `mintPrize` allows three minters. The error name is accurate for both uses.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `vaultMintTo(address to, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function vaultMintTo(address to, uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): mint amount (18 decimals) |
| **Returns** | None |

**State Reads:** `vaultAllowance`
**State Writes:** `vaultAllowance` decremented by `amount` (unchecked), `totalSupply` incremented (via `_mint`), `balanceOf[to]` incremented (via `_mint`)

**Callers:** External only, restricted to MINTER_VAULT:
- `DegenerusVault.sol` (line 730): vault mints WWXRP to recipient

**Callees:** `_mint(to, amount)`

**ETH Flow:** No
**Invariants:**
- Reverts if caller is not MINTER_VAULT (OnlyVault)
- Reverts if `to == address(0)` (ZeroAddress)
- Returns silently if `amount == 0` (no-op, different from mintPrize which reverts on zero)
- Reverts if `amount > vaultAllowance` (InsufficientVaultAllowance)
- `vaultAllowance` decremented in `unchecked` block -- safe because the `amount > allowanceVault` check above guarantees no underflow
- `INITIAL_VAULT_ALLOWANCE + totalSupply` represents the theoretical max supply
- Like mintPrize, mints WITHOUT wXRP backing

**NatSpec Accuracy:** Accurate. Correctly documents vault-only access and allowance reduction. Note: NatSpec says "Reduces vault allowance and mints to recipient" which matches behavior. However, it does not mention the silent return on zero amount (minor informational).
**Gas Flags:** The `unchecked` block is justified -- the preceding check guarantees `amount <= allowanceVault`.
**Verdict:** CORRECT

---

### `burnForGame(address from, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function burnForGame(address from, uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): address to burn from; `amount` (uint256): burn amount (18 decimals) |
| **Returns** | None |

**State Reads:** `balanceOf[from]` (via `_burn`)
**State Writes:** `balanceOf[from]` decremented (via `_burn`), `totalSupply` decremented (via `_burn`)

**Callers:** External only, restricted to MINTER_GAME:
- `DegenerusGameDegeneretteModule.sol` (line 597): burns WWXRP bet amount from player

**Callees:** `_burn(from, amount)`

**ETH Flow:** No
**Invariants:**
- Reverts if caller is not MINTER_GAME (OnlyMinter) -- note: uses `OnlyMinter` error but only checks against MINTER_GAME (not COIN or COINFLIP)
- Returns silently if `amount == 0` (no-op)
- Reverts if `from == address(0)` (ZeroAddress via `_burn`)
- Reverts if `balanceOf[from] < amount` (InsufficientBalance via `_burn`)
- Burns improve the backing ratio (wXRPReserves unchanged, totalSupply decreases)
- Does NOT reduce wXRPReserves (burn != unwrap)

**NatSpec Accuracy:** Minor inaccuracy: NatSpec says `@custom:reverts OnlyMinter When caller is not the game contract` -- the error name `OnlyMinter` is technically correct but could be confusing since `mintPrize` also uses `OnlyMinter` with different allowed callers. The NatSpec text "the game contract" is accurate for this function specifically.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `supplyIncUncirculated()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function supplyIncUncirculated() external view returns (uint256)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `uint256`: totalSupply + vaultAllowance |

**State Reads:** `totalSupply`, `vaultAllowance`
**State Writes:** None

**Callers:** External only (dashboards, off-chain consumers)
**Callees:** None

**ETH Flow:** No
**Invariants:** Returns `totalSupply + vaultAllowance`. At deployment this equals `INITIAL_VAULT_ALLOWANCE` (1B ether). As vault mints occur, vaultAllowance decreases and totalSupply increases by the same amount, so the sum is conserved for vault mints. For prize mints (mintPrize), totalSupply increases without vaultAllowance decreasing, so `supplyIncUncirculated()` grows. For burns, totalSupply decreases, so `supplyIncUncirculated()` shrinks.
**NatSpec Accuracy:** Accurate. "Total supply including uncirculating vault allowance" matches behavior.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `vaultMintAllowance()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function vaultMintAllowance() external view returns (uint256)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `uint256`: remaining vault allowance |

**State Reads:** `vaultAllowance`
**State Writes:** None

**Callers:** External only. Called by DegenerusVault during deployment sequence (`VAULT calls COIN.vaultMintAllowance()` per project memory -- analogous pattern for WWXRP).
**Callees:** None

**ETH Flow:** No
**Invariants:** Returns `vaultAllowance`, which starts at `INITIAL_VAULT_ALLOWANCE` (1B ether) and only decreases via `vaultMintTo()`.
**NatSpec Accuracy:** Accurate. "Vault mint allowance remaining (uncirculating reserve)" matches behavior.
**Gas Flags:** This function duplicates the public getter for `vaultAllowance` (which is already `public`). The explicit function provides a named interface method but is technically redundant.
**Verdict:** CORRECT -- Informational: redundant with the auto-generated `vaultAllowance()` public getter, but provides a clean named interface for callers.

---

## Orphaned NatSpec

Lines 63-66 contain NatSpec documentation for a `Wrapped` event that no longer exists:

```solidity
/// @notice Emitted when someone wraps wXRP into WWXRP
/// @param user The user who wrapped
/// @param amount Amount of wXRP wrapped (and WWXRP minted)

```

The event declaration was removed when wrapping was disabled, but the NatSpec comments remain. This is a cosmetic issue only -- no functional impact.

**Severity:** Informational (NatSpec hygiene)
