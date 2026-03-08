# ACCT-10: BurnieCoin Supply Invariant Audit

**Requirement:** ACCT-10 -- Verify `totalSupply + vaultAllowance = supplyIncUncirculated()` holds across all mint and burn paths.

**Contract:** `contracts/BurnieCoin.sol`
**Key Struct:** `Supply { uint128 totalSupply; uint128 vaultAllowance }` (single storage slot)
**Initial State:** `totalSupply = 0`, `vaultAllowance = 2_000_000 ether` (2e24 wei)
**Last Verified:** 2026-03-06 (line numbers updated to match current source)

---

## Part A: Core `_mint` and `_burn` Routing

### `_mint(address to, uint256 amount)` -- Line 468

```solidity
function _mint(address to, uint256 amount) internal {
    if (to == address(0)) revert ZeroAddress();
    uint128 amount128 = _toUint128(amount);
    if (to == ContractAddresses.VAULT) {
        unchecked {
            _supply.vaultAllowance += amount128;
        }
        emit VaultEscrowRecorded(address(0), amount);
        return;                          // <-- early return, no totalSupply change
    }
    _supply.totalSupply += amount128;    // <-- checked arithmetic
    balanceOf[to] += amount;
    emit Transfer(address(0), to, amount);
}
```

**Analysis:**

| Branch | totalSupply delta | vaultAllowance delta | supplyIncUncirculated delta |
|--------|-------------------|----------------------|-----------------------------|
| `to != VAULT` | +amount128 | 0 | +amount128 |
| `to == VAULT` | 0 | +amount128 | +amount128 |

**Conservation check:** In both branches, `totalSupply + vaultAllowance` increases by exactly `amount128`. CORRECT.

**Checked vs unchecked:**
- Non-VAULT path: `totalSupply += amount128` is **checked** (Solidity 0.8+ overflow revert). Safe.
- VAULT path: `vaultAllowance += amount128` is **unchecked**. See Part E for overflow analysis.

### `_burn(address from, uint256 amount)` -- Line 488

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
        return;                          // <-- early return, no totalSupply change
    }
    balanceOf[from] -= amount;           // <-- checked underflow
    _supply.totalSupply -= amount128;    // <-- checked underflow
    emit Transfer(from, address(0), amount);
}
```

**Analysis:**

| Branch | totalSupply delta | vaultAllowance delta | supplyIncUncirculated delta |
|--------|-------------------|----------------------|-----------------------------|
| `from != VAULT` | -amount128 | 0 | -amount128 |
| `from == VAULT` | 0 | -amount128 | -amount128 |

**Conservation check:** In both branches, `totalSupply + vaultAllowance` decreases by exactly `amount128`. CORRECT.

**Underflow protection:**
- Non-VAULT path: `balanceOf[from] -= amount` and `_supply.totalSupply -= amount128` are both checked. Safe.
- VAULT path: Explicit `if (amount128 > allowanceVault) revert Insufficient()` before unchecked subtraction. Safe.

---

## Part B: `vaultMintTo` Path -- Line 694

```solidity
function vaultMintTo(address to, uint256 amount) external onlyVault {
    if (to == address(0)) revert ZeroAddress();
    uint128 amount128 = _toUint128(amount);
    uint128 allowanceVault = _supply.vaultAllowance;
    if (amount128 > allowanceVault) revert Insufficient();
    unchecked {
        _supply.vaultAllowance = allowanceVault - amount128;
        _supply.totalSupply += amount128;
        balanceOf[to] += amount;
    }
    emit VaultAllowanceSpent(address(this), amount);
    emit Transfer(address(0), to, amount);
}
```

**Analysis:**

| totalSupply delta | vaultAllowance delta | supplyIncUncirculated delta |
|-------------------|----------------------|-----------------------------|
| +amount128 | -amount128 | 0 |

**Conservation check:** `totalSupply + vaultAllowance` is UNCHANGED. This is a pure transfer from virtual reserve to circulating supply. CORRECT.

**Overflow safety:**
- `vaultAllowance -= amount128`: Protected by explicit `amount128 > allowanceVault` guard before unchecked block. Safe.
- `totalSupply += amount128`: Since `amount128 <= allowanceVault` (guarded above), and `totalSupply + vaultAllowance <= type(uint128).max` must hold for the struct to be valid, we need to verify this invariant is maintained. Initial total is 2e24, max uint128 is ~3.4e38. The totalSupply can grow to at most `initial_vaultAllowance + all_external_mints`, which cannot approach uint128 max. Safe. See Part E.

**Access control:** `onlyVault` modifier -- only `ContractAddresses.VAULT`. CORRECT.

---

## Part C: `vaultEscrow` Path -- Line 677

```solidity
function vaultEscrow(uint256 amount) external {
    address sender = msg.sender;
    if (
        sender != ContractAddresses.GAME &&
        sender != ContractAddresses.VAULT
    ) revert OnlyVault();
    uint128 amount128 = _toUint128(amount);
    unchecked {
        _supply.vaultAllowance += amount128;
    }
    emit VaultEscrowRecorded(sender, amount);
}
```

**Analysis:**

| totalSupply delta | vaultAllowance delta | supplyIncUncirculated delta |
|-------------------|----------------------|-----------------------------|
| 0 | +amount128 | +amount128 |

**This is an intentional EXPANSION of total supply.** When the GAME contract deposits BURNIE proceeds to the vault, it calls `vaultEscrow` to increase the vault's virtual mint allowance. This represents new BURNIE that the vault can later mint to players via `vaultMintTo`.

**When called:**
- `DegenerusVault.deposit(coinAmount, stEthAmount)` at line 453 -- called by the GAME contract during gameplay revenue distribution.

**Access control:** Restricted to `ContractAddresses.GAME` and `ContractAddresses.VAULT`. CORRECT.

**Conservation context:** This is NOT supply-conserving -- it increases `supplyIncUncirculated`. However, this is by design: when the game deposits BURNIE revenue to the vault, that BURNIE becomes part of the vault's reserves that can be withdrawn by share holders. The expansion represents real economic value accrued to the vault.

---

## Part D: `_transfer(from, VAULT)` Path -- Line 442

**This is an additional supply path not listed in the plan's interface section but discovered during audit.**

```solidity
function _transfer(address from, address to, uint256 amount) internal {
    if (from == address(0) || to == address(0)) revert ZeroAddress();
    balanceOf[from] -= amount;           // checked underflow

    if (to == ContractAddresses.VAULT) {
        uint128 amount128 = _toUint128(amount);
        unchecked {
            _supply.totalSupply -= amount128;
            _supply.vaultAllowance += amount128;
        }
        emit Transfer(from, address(0), amount);
        emit VaultEscrowRecorded(from, amount);
        return;
    }
    balanceOf[to] += amount;
    emit Transfer(from, to, amount);
}
```

**Analysis:**

| totalSupply delta | vaultAllowance delta | supplyIncUncirculated delta |
|-------------------|----------------------|-----------------------------|
| -amount128 | +amount128 | 0 |

**Conservation check:** `totalSupply + vaultAllowance` is UNCHANGED. This is the reverse of `vaultMintTo` -- circulating tokens transferred to VAULT are converted back to virtual allowance. CORRECT.

**Unchecked safety:**
- `totalSupply -= amount128`: Safe because `balanceOf[from] -= amount` succeeded first (checked), meaning `from` had sufficient balance. Since `totalSupply >= sum(all balanceOf)`, we have `totalSupply >= amount128`.
- `vaultAllowance += amount128`: Safe because the amount being added was subtracted from totalSupply, so `totalSupply + vaultAllowance` remains unchanged (no overflow possible if it wasn't overflowed before).

**Access control:** This is an internal function called by `transfer()` and `transferFrom()` -- any token holder can transfer to VAULT. This is by design.

---

## Part E: External Caller Paths

### 1. `burnForCoinflip(address from, uint256 amount)` -- Line 517

```solidity
function burnForCoinflip(address from, uint256 amount) external {
    if (msg.sender != coinflipContract) revert OnlyGame();
    _burn(from, amount);
}
```

- **Access control:** Only `ContractAddresses.COINFLIP`. CORRECT.
- **Routing:** Direct delegation to `_burn(from, amount)`. `from` is a player address (never VAULT in practice -- BurnieCoinflip burns from depositing players).
- **VAULT risk:** If `from == VAULT`, would decrement vaultAllowance. However, BurnieCoinflip never passes VAULT as `from` (confirmed: all 4 call sites in BurnieCoinflip.sol pass `player`/`caller` addresses).

### 2. `mintForCoinflip(address to, uint256 amount)` -- Line 526

```solidity
function mintForCoinflip(address to, uint256 amount) external {
    if (msg.sender != coinflipContract) revert OnlyGame();
    _mint(to, amount);
}
```

- **Access control:** Only `ContractAddresses.COINFLIP`. CORRECT.
- **Routing:** Direct delegation to `_mint(to, amount)`. `to` is always a player address (BurnieCoinflip mints winnings to players, never to VAULT).
- **VAULT risk:** If `to == VAULT`, would increment vaultAllowance (unchecked). No call sites in BurnieCoinflip pass VAULT -- all use `player` address variables.

### 3. `mintForGame(address to, uint256 amount)` -- Line 535

```solidity
function mintForGame(address to, uint256 amount) external {
    if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
    if (amount == 0) return;
    _mint(to, amount);
}
```

- **Access control:** Only `ContractAddresses.GAME` (includes delegatecall modules). CORRECT.
- **Routing:** Direct delegation to `_mint(to, amount)` with zero-amount short-circuit.
- **Callers:** `DegenerusGameDegeneretteModule.sol:726` -- mints degenerette payout to `player`.
- **VAULT risk:** If a delegatecall module passed VAULT as `to`, would route to unchecked vaultAllowance path. No known call site does this.

### 4. `creditCoin(address player, uint256 amount)` -- Line 545

```solidity
function creditCoin(address player, uint256 amount) external onlyFlipCreditors {
    if (player == address(0) || amount == 0) return;
    _mint(player, amount);
}
```

- **Access control:** `onlyFlipCreditors` -- GAME and AFFILIATE. CORRECT.
- **Routing:** Direct delegation to `_mint(player, amount)` with zero-address and zero-amount guards.
- **Callers:** `DegenerusAffiliate.sol:846` -- credits affiliate coin reward to `player`.
- **VAULT risk:** `player == address(0)` returns early, but `player == VAULT` would route to unchecked path. No known caller passes VAULT.

### 5. `burnCoin(address target, uint256 amount)` -- Line 858

```solidity
function burnCoin(address target, uint256 amount) external onlyTrustedContracts {
    uint256 consumed = _consumeCoinflipShortfall(target, amount);
    _burn(target, amount - consumed);
}
```

- **Access control:** `onlyTrustedContracts` -- GAME and AFFILIATE. CORRECT.
- **Routing:** First attempts to consume coinflip shortfall, then burns remainder via `_burn(target, amount - consumed)`.
- **Callers:** `DegenerusGameDegeneretteModule.sol:594`, `DegenerusGameAdvanceModule.sol:1187`, `DegenerusGameMintModule.sol:979,993`, `DegenerusGameWhaleModule.sol:565`. All pass player/buyer addresses.
- **VAULT risk:** If `target == VAULT`, `_consumeCoinflipShortfall` would attempt to query coinflip for VAULT (likely 0), then `_burn(VAULT, amount)` would reduce vaultAllowance. No known caller passes VAULT.

### 6. `decimatorBurn(address player, uint256 amount)` -- Line 879

- **Access control:** Public (any address can call for self, or for another with operator approval).
- **Routing:** Calls `_burn(caller, amount - consumed)` after coinflip shortfall consumption.
- **VAULT risk:** `player`/`caller` are external addresses. Even if someone passed `VAULT` as player, `isOperatorApproved` would likely fail for any EOA caller. Theoretically if VAULT called `decimatorBurn(address(0), amount)`, it would burn from VAULT (reducing vaultAllowance). This is a non-issue: VAULT is a contract that does not call decimatorBurn.

---

## Part F: uint128 Overflow Analysis

### Constants

- `uint128 max = 340,282,366,920,938,463,463,374,607,431,768,211,455` (~3.4e38)
- `2_000_000 ether = 2,000,000 * 10^18 = 2e24`
- Headroom factor: `3.4e38 / 2e24 = 1.7e14` (170 trillion times larger)

### Maximum Achievable Values

**totalSupply** can grow via:
1. `_mint(non-VAULT, amount)` -- checked arithmetic, reverts at uint128 max
2. `vaultMintTo(to, amount)` -- bounded by `amount <= vaultAllowance` (explicit check)

So `totalSupply` is bounded by `initial_vaultAllowance + sum(all external mints)`. External mints are:
- `mintForCoinflip`: Bounded by coinflip game economics (you must burn first)
- `mintForGame`: Bounded by degenerette payouts (sub-neutral EV)
- `creditCoin`: Bounded by affiliate rewards (small fractions of gameplay spend)

These are all economically bounded -- no free-minting paths exist. Theoretical maximum totalSupply: orders of magnitude below uint128 max.

**vaultAllowance** can grow via:
1. `_mint(VAULT, amount)` -- **unchecked** but no known caller passes VAULT
2. `vaultEscrow(amount)` -- **unchecked**, called by GAME/VAULT
3. `_transfer(from, VAULT)` -- **unchecked**, but bounded by existing totalSupply being moved

For `vaultEscrow`: called from `DegenerusVault.deposit()` when GAME deposits BURNIE revenue. The amount deposited must come from actual gameplay. At 2M initial supply and game economics, accumulating anywhere near uint128 max is physically impossible.

### Unchecked Blocks -- Safety Justification

| Location | Operation | Safety Justification |
|----------|-----------|---------------------|
| `_mint(VAULT)` L472 | `vaultAllowance += amount128` | amount128 validated by _toUint128; no known caller passes VAULT; economically bounded |
| `_burn(VAULT)` L494 | `vaultAllowance = allowanceVault - amount128` | Explicit `amount128 > allowanceVault` check before unchecked block |
| `vaultEscrow` L684 | `vaultAllowance += amount128` | amount128 validated by _toUint128; only GAME/VAULT can call; economically bounded |
| `vaultMintTo` L699 | `vaultAllowance = allowanceVault - amount128` | Explicit `amount128 > allowanceVault` check; also `totalSupply += amount128` safe because amount came from allowance |
| `_transfer(VAULT)` L450 | `totalSupply -= amount128; vaultAllowance += amount128` | totalSupply underflow impossible (balanceOf check ran first); vaultAllowance overflow impossible (total sum unchanged) |

### Verdict on uint128 Overflow

**NOT a realistic risk.** The theoretical minimum number of maximal vaultEscrow calls needed to overflow uint128 is ~1.7e14 calls of 2M ether each. Even if every block contained a maximal deposit, this would take billions of years. The `_toUint128()` function also rejects any single amount exceeding uint128 max.

**Informational note:** Three unchecked `vaultAllowance +=` sites (in `_mint(VAULT)`, `vaultEscrow`, and `_transfer(to=VAULT)`) lack explicit overflow checks. The safety relies on economic bounds rather than arithmetic guards. This is an accepted design trade-off for gas efficiency.

---

## Complete Supply Path Summary Table

| Path | Function | totalSupply Delta | vaultAllowance Delta | supplyIncUncirculated Delta | Conservation? | Access Control |
|------|----------|-------------------|----------------------|-----------------------------|---------------|----------------|
| Mint (non-VAULT) | `_mint(to, amount)` | +amount | 0 | +amount | Increases | Internal |
| Mint (VAULT) | `_mint(VAULT, amount)` | 0 | +amount | +amount | Increases | Internal |
| Burn (non-VAULT) | `_burn(from, amount)` | -amount | 0 | -amount | Decreases | Internal |
| Burn (VAULT) | `_burn(VAULT, amount)` | 0 | -amount | -amount | Decreases | Internal |
| Vault mint out | `vaultMintTo(to, amount)` | +amount | -amount | 0 | **Conserved** | onlyVault |
| Vault escrow in | `vaultEscrow(amount)` | 0 | +amount | +amount | Increases | GAME or VAULT |
| Transfer to VAULT | `_transfer(from, VAULT)` | -amount | +amount | 0 | **Conserved** | Internal (any holder) |
| Transfer (non-VAULT) | `_transfer(from, to)` | 0 | 0 | 0 | **Conserved** | Internal (any holder) |

### Key Observations

1. **Supply-conserving paths** (supplyIncUncirculated unchanged): `vaultMintTo`, `_transfer(to=VAULT)`, `_transfer(non-VAULT)`. These move tokens between circulating and virtual reserve.

2. **Supply-expanding paths** (supplyIncUncirculated increases): `_mint(any)`, `vaultEscrow`. These create new supply.

3. **Supply-contracting paths** (supplyIncUncirculated decreases): `_burn(any)`. These destroy supply.

4. **The invariant `totalSupply + vaultAllowance = supplyIncUncirculated()` holds by construction.** The `supplyIncUncirculated()` view function (line 321) computes `uint256(_supply.totalSupply) + uint256(_supply.vaultAllowance)` directly. It cannot diverge from the struct fields because it IS the struct fields.

---

## External Caller Access Control Summary

| External Function | Caller Restriction | Calls | Can Pass VAULT? |
|---|---|---|---|
| `burnForCoinflip(from, amount)` | COINFLIP only | `_burn(from, amount)` | Technically yes, but no caller does |
| `mintForCoinflip(to, amount)` | COINFLIP only | `_mint(to, amount)` | Technically yes, but no caller does |
| `mintForGame(to, amount)` | GAME only | `_mint(to, amount)` | Technically yes, but no caller does |
| `creditCoin(player, amount)` | GAME or AFFILIATE | `_mint(player, amount)` | Technically yes, but no caller does |
| `burnCoin(target, amount)` | GAME or AFFILIATE | `_burn(target, amount-consumed)` | Technically yes, but no caller does |
| `decimatorBurn(player, amount)` | Any (with approval) | `_burn(caller, amount-consumed)` | Only if VAULT called itself |
| `vaultEscrow(amount)` | GAME or VAULT | Direct vaultAllowance++ | N/A (vault-specific) |
| `vaultMintTo(to, amount)` | VAULT only | Direct transfer from allowance | to is recipient, not source |

---

## Findings

### ACCT-10-F01 [INFORMATIONAL]: Unchecked vaultAllowance Increments

**Severity:** Informational
**Location:** `_mint` L472, `vaultEscrow` L684, `_transfer` L452

Three code paths increment `_supply.vaultAllowance` inside `unchecked` blocks without explicit overflow guards. Safety relies entirely on economic bounds (no single amount can exceed uint128 via `_toUint128`, and cumulative additions would require ~1.7e14 calls of 2M ether to overflow).

**Risk:** Theoretical only. No practical exploit path exists given:
- All callers are access-controlled (GAME, VAULT, COINFLIP)
- Economic bounds prevent cumulative overflow
- `_toUint128()` rejects individual amounts > uint128 max

**Recommendation:** No action required. The gas savings from `unchecked` are justified given the 170-trillion-fold safety margin.

### ACCT-10-F02 [INFORMATIONAL]: External Mint/Burn Functions Accept VAULT Address

**Severity:** Informational
**Location:** `mintForCoinflip` L526, `mintForGame` L535, `creditCoin` L545, `burnForCoinflip` L517, `burnCoin` L858

These external functions accept arbitrary addresses including `ContractAddresses.VAULT`. If a trusted caller (COINFLIP, GAME, AFFILIATE) passed VAULT as the target, the operation would route to the vaultAllowance path instead of the totalSupply path. No known caller does this, and the result would still maintain the invariant correctly, but the semantic meaning would differ (e.g., "minting to vault" increases reserve rather than circulating supply).

**Risk:** None. All trusted callers pass player addresses. The VAULT routing is correct even if triggered.

---

## ACCT-10 Verdict: PASS

### Checklist

- [x] `totalSupply + vaultAllowance = supplyIncUncirculated()` holds at all times by construction (view function reads struct fields directly)
- [x] `_mint(VAULT)` correctly routes to `vaultAllowance`, not `totalSupply`
- [x] `_burn(VAULT)` correctly routes from `vaultAllowance`, not `totalSupply`
- [x] `vaultMintTo` is supply-conserving (`vaultAllowance` down, `totalSupply` up by same amount)
- [x] `vaultEscrow` is intentional supply expansion (documented, access-controlled)
- [x] `_transfer(to=VAULT)` is supply-conserving (reverse of vaultMintTo, correctly implemented)
- [x] All external mint/burn paths correctly delegate to `_mint`/`_burn` core
- [x] All external paths have appropriate access control (COINFLIP, GAME, AFFILIATE, VAULT)
- [x] uint128 overflow is not a realistic risk (170-trillion-fold safety margin)
- [x] All `unchecked` blocks have documented safety justification

**Conclusion:** The BurnieCoin supply invariant is correctly maintained across all 8 identified supply paths. The dual-path routing for VAULT addresses is implemented correctly with proper guards. The packed uint128 Supply struct has massive headroom against overflow. Two Informational findings documented (unchecked increments and VAULT-address acceptance) with no security impact.
