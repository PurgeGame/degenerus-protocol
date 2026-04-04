# Phase 143: Vault + Self-Win Delta Audit Report

**Date:** 2026-03-29
**Commit:** 8ff7def8
**Scope:** 3 changes across DegenerusVault.sol and StakedDegenerusStonk.sol

## Findings

### 1. sdgnrsBurn() — DegenerusVault.sol:781-783

```solidity
function sdgnrsBurn(uint256 amount) external onlyVaultOwner returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
    return sdgnrsToken.burn(amount);
}
```

**Access Control:** `onlyVaultOwner` — requires caller to hold >50.1% of DGVE supply. SAFE.

**Reentrancy:** `sdgnrsToken.burn(amount)` has two paths:
- **Game over path:** `_deterministicBurn` → sends ETH via `.call{value:}` to `msg.sender` (vault). Vault has no `receive()` that re-enters sDGNRS. The vault's `receive()` only accepts ETH from game/stETH contracts. SAFE.
- **During game path:** `_submitGamblingClaim` — no external calls, just state updates. SAFE.

**msg.sender context:** `burn()` uses `msg.sender` which is the vault address. Burns from `balanceOf[vault]`. Correct — vault burns its own sDGNRS. SAFE.

**Integration:** During game, burn submits a gambling claim. Vault must later call `sdgnrsClaimRedemption()` to complete. ETH/stETH from game-over path flows to vault balance, increasing DGVE backing. SAFE.

**Verdict: SAFE**

---

### 2. sdgnrsClaimRedemption() — DegenerusVault.sol:787-789

```solidity
function sdgnrsClaimRedemption() external onlyVaultOwner {
    sdgnrsToken.claimRedemption();
}
```

**Access Control:** `onlyVaultOwner`. SAFE.

**msg.sender context:** `claimRedemption()` uses `msg.sender` to look up `pendingRedemptions[msg.sender]`. Since vault is the caller, it claims the vault's own pending redemption. Correct. SAFE.

**Reentrancy:** `claimRedemption()` sends ETH via `_payEth` which uses `.call{value:}` to `msg.sender` (vault). Same receive() analysis as above — no re-entrant path. Also sends BURNIE via `_payBurnie` which does `coin.transfer(player, ...)` — ERC-20 transfer, no callback. SAFE.

**State consistency:** `claimRedemption` clears `pendingRedemptions[player]` and reduces `pendingRedemptionEthValue` / `pendingRedemptionBurnie`. All state updates happen before external calls (CEI pattern). SAFE.

**Verdict: SAFE**

---

### 3. transferFromPool self-win burn — StakedDegenerusStonk.sol:409-416

```solidity
if (to == address(this)) {
    totalSupply -= amount;
    emit Transfer(address(this), address(0), amount);
} else {
    balanceOf[to] += amount;
    emit Transfer(address(this), to, amount);
}
```

**Pool accounting:** `poolBalances[idx] -= amount` and `balanceOf[address(this)] -= amount` both execute unconditionally (line 406-407). In the self-win case, `totalSupply -= amount` replaces the old `balanceOf[address(this)] += amount`.

Before: pool decreases, contract balance net-zero (subtract then add). No supply change. Tokens effectively vanished from pool into contract's general balance.

After: pool decreases, contract balance decreases, supply decreases. Tokens are burned.

**Solvency invariant:** `totalSupply` decreases by `amount`. `balanceOf[address(this)]` decreases by `amount`. The backing assets (ETH, stETH, BURNIE) are unchanged. Therefore: value per remaining token increases. Every remaining holder benefits proportionally. No solvency violation. SAFE.

**Overflow/underflow:** `totalSupply -= amount` is outside the `unchecked` block, so Solidity 0.8 overflow protection applies. Since `amount <= poolBalances[idx] <= balanceOf[address(this)] <= totalSupply`, underflow is impossible. SAFE.

**Edge case — last pool tokens:** If the entire pool is awarded to self, all tokens burn. `totalSupply` may reach 0 if contract held all tokens. This is game-over territory and handled correctly — empty supply means no more burns possible. SAFE.

**ERC-20 compliance:** `Transfer(address(this), address(0), amount)` is the canonical burn event per EIP-20. SAFE.

**Verdict: SAFE**

## Attack Surface Inventory

| # | Surface | Contract | Verdict | Reasoning |
|---|---------|----------|---------|-----------|
| 1 | sdgnrsBurn access control | Vault | SAFE | onlyVaultOwner (>50.1% DGVE) |
| 2 | sdgnrsBurn reentrancy via ETH payout | Vault → sDGNRS | SAFE | Vault receive() restricted, CEI in sDGNRS |
| 3 | sdgnrsBurn msg.sender context | Vault → sDGNRS | SAFE | Burns from balanceOf[vault] correctly |
| 4 | sdgnrsClaimRedemption access control | Vault | SAFE | onlyVaultOwner |
| 5 | sdgnrsClaimRedemption msg.sender | Vault → sDGNRS | SAFE | Claims vault's own pending redemption |
| 6 | sdgnrsClaimRedemption reentrancy | Vault → sDGNRS | SAFE | CEI pattern, restricted receive() |
| 7 | transferFromPool self-win solvency | sDGNRS | SAFE | totalSupply reduction, backing unchanged |
| 8 | transferFromPool self-win overflow | sDGNRS | SAFE | Checked arithmetic, amount ≤ supply |
| 9 | transferFromPool self-win ERC-20 | sDGNRS | SAFE | Canonical burn event emitted |

**Result: 0 VULNERABLE, 0 INFO across 9 attack surfaces.**
