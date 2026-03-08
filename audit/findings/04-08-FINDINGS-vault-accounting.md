# 04-08 Findings: DegenerusVault Accounting Audit

**Auditor:** Claude Opus 4.6 (automated)
**Date:** 2026-03-01
**Scope:** DegenerusVault.sol -- DGVE/DGVB share redemption formulas, rounding, refill mechanism, cross-contract ETH/stETH/BURNIE flows
**Requirement:** ACCT-09

---

## Part A: DGVE (ETH+stETH) Share Redemption

### Function: `_burnEthFor(player, amount)` (lines 839-882)

**Formula traced:**

```solidity
(uint256 ethBal, uint256 stBal, uint256 combined) = _syncEthReserves();
// _syncEthReserves: ethBal = address(this).balance, stBal = steth.balanceOf(this), combined = ethBal + stBal

uint256 claimable = gamePlayer.claimableWinningsOf(address(this));
if (claimable <= 1) { claimable = 0; } else { claimable -= 1; }
// Accounts for the sentinel pattern (game stores 1 as "no balance")

uint256 supplyBefore = share.totalSupply();
uint256 reserve = combined + claimable;
uint256 claimValue = (reserve * amount) / supplyBefore;
```

### A1: Reserve composition

**Question:** Does `reserve` = total ETH + stETH held by vault?

**Answer:** YES, plus game claimable winnings (minus sentinel).

- `combined = address(this).balance + steth.balanceOf(address(this))` -- direct, fresh reads. No caching.
- `claimable` = vault's game winnings minus the 1-wei sentinel. If the vault has game winnings (from being a player via vault owner actions), these are also counted.
- The reserve is **maximally inclusive** of all ETH-denominated value the vault can access.

**Verdict:** CORRECT. The reserve includes all ETH + stETH on hand plus redeemable game winnings.

### A2: Rounding direction

**Formula:** `claimValue = (reserve * amount) / supplyBefore`

Integer division in Solidity truncates toward zero (floors). Since both `reserve * amount` and `supplyBefore` are positive:

- `claimValue <= (reserve * amount) / supplyBefore` (true value)
- The claimer receives **at most** their fair pro-rata share, never more.
- The truncated remainder (up to `supplyBefore - 1` wei) stays in the vault, distributed across remaining shareholders.

**Verdict:** CORRECT. Rounding is vault-favorable (floors against the claimer).

### A3: Post-claim proportional fairness

After burning `amount` shares and paying `claimValue`:
- New reserve = `reserve - claimValue`
- New supply = `supplyBefore - amount`
- Remaining per-share value = `(reserve - claimValue) / (supplyBefore - amount)`

Since `claimValue = floor(reserve * amount / supplyBefore)`, we have:
- `claimValue <= reserve * amount / supplyBefore`
- Therefore `reserve - claimValue >= reserve * (supplyBefore - amount) / supplyBefore`
- So `(reserve - claimValue) / (supplyBefore - amount) >= reserve / supplyBefore`

The remaining per-share value is **at least** equal to the pre-claim per-share value. No extraction beyond fair share.

**Verdict:** CORRECT. Remaining shareholders are never diluted.

### A4: Edge cases

**Last share burned (`amount == supplyBefore`):**
- `claimValue = (reserve * supplyBefore) / supplyBefore = reserve`
- The last claimer receives the full remaining reserve. CORRECT.
- After burn, `supplyBefore == amount` triggers refill: `share.vaultMint(player, REFILL_SUPPLY)`
- Player gets 1T new shares. Since the reserve is now zero, these shares have zero value initially.

**First share burned (max reserve):**
- Works identically -- `claimValue = (reserve * amount) / supplyBefore` produces a small fraction of the reserve. CORRECT.

**Division by zero (`totalSupply == 0`):**
- The refill mechanism prevents this: whenever all shares are burned, 1T new shares are immediately minted.
- During the burn transaction itself, `supplyBefore` is read BEFORE the burn, so it cannot be zero (you cannot burn 0 shares since `amount == 0` is rejected).
- Between transactions, the refill ensures supply never reaches zero.
- **Verdict:** Division by zero is impossible. SAFE.

### A5: stETH yield passive accrual

Between deposit transactions, Lido's stETH rebases upward when staking rewards accrue. Since:
1. `_syncEthReserves()` reads `steth.balanceOf(address(this))` fresh every time (no caching)
2. Rebasing increases `steth.balanceOf()` without any vault action
3. This increases `combined`, which increases `reserve`
4. Which increases `claimValue` for the same number of shares

**stETH yield passively increases DGVE per-share value.** No explicit mint, no accounting action needed.

**Lido slashing risk:** If a Lido slashing event occurs, `steth.balanceOf()` could decrease, reducing DGVE value. This is an inherent risk of holding stETH, not a vault bug.

**Verdict:** CORRECT. stETH yield accrues automatically to DGVE holders via the reserve increasing.

### A6: ETH payout ordering

```solidity
if (claimValue <= ethBal) {
    ethOut = claimValue;        // All ETH
} else {
    ethOut = ethBal;            // All available ETH
    stEthOut = claimValue - ethBal;  // Remainder in stETH
    if (stEthOut > stBal) revert Insufficient();
}
```

- ETH is preferred, stETH is used for the remainder.
- If `claimValue > combined` (vault is underfunded), the `Insufficient` revert fires. This is correct -- cannot pay more than the vault holds.
- The `claimWinnings` auto-claim path (lines 859-863) attempts to top up ETH if `claimValue > combined && claimable != 0`. After claiming, balances are refreshed. This is a convenience feature that allows DGVE redemption without the vault owner manually claiming first.

**Verdict:** CORRECT. ETH-first payout with stETH fallback, proper underfunding guard.

---

## Part B: DGVB (BURNIE) Share Redemption

### Function: `_burnCoinFor(player, amount)` (lines 768-808)

**Formula traced:**

```solidity
uint256 coinBal = _syncCoinReserves();  // = coinToken.vaultMintAllowance()
uint256 supplyBefore = share.totalSupply();
uint256 vaultBal = coinToken.balanceOf(address(this));
uint256 claimable = coinPlayer.previewClaimCoinflips(address(this));
if (vaultBal != 0 || claimable != 0) {
    coinBal += vaultBal + claimable;
}
coinOut = (coinBal * amount) / supplyBefore;
```

### B1: Reserve composition

**Question:** Does `coinBal` = total BURNIE claimable by vault?

**Answer:** YES. The reserve is the sum of three sources:
1. `coinToken.vaultMintAllowance()` -- the vault's virtual BURNIE reserve (can be minted on demand)
2. `coinToken.balanceOf(address(this))` -- actual BURNIE tokens held by the vault
3. `coinPlayer.previewClaimCoinflips(address(this))` -- claimable coinflip winnings (not yet minted)

This captures all BURNIE the vault can access.

**Verdict:** CORRECT. Reserve is maximally inclusive.

### B2: Rounding direction

**Formula:** `coinOut = (coinBal * amount) / supplyBefore`

Same analysis as DGVE: integer division floors. Claimer gets at most their fair share. Truncated wei stays in the reserve.

**Verdict:** CORRECT. Rounding is vault-favorable.

### B3: Payout sourcing (lines 787-807)

The payout prioritizes three sources in order:
1. **Vault BURNIE balance** (`coinToken.transfer`) -- actual tokens on hand
2. **Coinflip claims** (`coinPlayer.claimCoinflips`) -- forces a claim, then transfers the minted tokens
3. **Vault mint allowance** (`coinToken.vaultMintTo`) -- mints from the virtual reserve

```solidity
if (remaining != 0) {
    coinTracked -= remaining;
    coinToken.vaultMintTo(player, remaining);
}
```

**Key observation:** `coinTracked -= remaining` updates the internal tracking before `vaultMintTo`. The `vaultMintTo` function in BurnieCoin decreases `_supply.vaultAllowance` and increases `_supply.totalSupply` by the same amount. This preserves the BurnieCoin invariant `totalSupply + vaultAllowance = supplyIncUncirculated`.

**Verdict:** CORRECT. All three payout paths produce the correct amount of BURNIE, and accounting is consistent.

### B4: `vaultMintTo` correctness (BurnieCoin.sol line 694)

```solidity
function vaultMintTo(address to, uint256 amount) external onlyVault {
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

- `vaultAllowance -= amount128` and `totalSupply += amount128` -- net change to `supplyIncUncirculated` is zero. CORRECT.
- The `Insufficient` check prevents minting more than the allowance. CORRECT.
- The `unchecked` block for `totalSupply += amount128` is safe because `totalSupply + vaultAllowance` starts at 2M ether and `_toUint128` would revert if amount exceeds uint128 max (~340 undecillion). Since `totalSupply` was reduced from `vaultAllowance`, it cannot overflow the uint128 range.

**Verdict:** CORRECT.

### B5: Edge cases

**Last share burned (`amount == supplyBefore`):**
- `coinOut = (coinBal * supplyBefore) / supplyBefore = coinBal`
- Last claimer gets the full BURNIE reserve. CORRECT.
- Refill triggers: `share.vaultMint(player, REFILL_SUPPLY)` -- 1T new shares with zero backing.

**Division by zero:**
- Same analysis as Part A. Supply cannot reach zero due to refill. SAFE.

---

## Part C: Vault Refill Mechanism

### Refill logic (found in both `_burnEthFor` and `_burnCoinFor`):

```solidity
share.vaultBurn(player, amount);
if (supplyBefore == amount) {
    share.vaultMint(player, REFILL_SUPPLY);
}
```

Where `REFILL_SUPPLY = 1_000_000_000_000 * 1e18` (1 trillion with 18 decimals).

### C1: Residual assets after full burn

When `amount == supplyBefore` (all shares burned):
- `claimValue = (reserve * supplyBefore) / supplyBefore = reserve` -- full reserve is paid out
- After payment, the vault holds zero ETH+stETH (for DGVE) or zero BURNIE reserve (for DGVB)
- The new 1T shares have zero backing

**Verdict:** CORRECT. No residual assets remain unclaimed.

### C2: Deposit-before-shares race condition

**Question:** Can someone deposit between the burn (supply=0) and the refill (supply=1T)?

**Answer:** NO. The refill happens in the same transaction as the burn, atomically:
1. `share.vaultBurn(player, amount)` -- supply drops to 0
2. `if (supplyBefore == amount)` -- true
3. `share.vaultMint(player, REFILL_SUPPLY)` -- supply becomes 1T
4. External calls (ETH/stETH transfers) happen AFTER both operations

No other transaction can interleave between steps 1 and 3. The EVM executes the entire function atomically.

**Verdict:** SAFE. No race condition possible.

### C3: Refill trigger guard

**Question:** Can refill be triggered while shares still exist?

**Answer:** NO. The condition is `supplyBefore == amount`, meaning the user must burn **exactly** all shares in a single transaction. If `amount < supplyBefore`, the condition is false and no refill occurs.

**Subtlety:** `supplyBefore` is the total supply, not just the player's balance. If Alice has 60% and Bob has 40%, Alice cannot trigger refill by burning her 60%. She would need to burn 100% (which she cannot, since she only holds 60%). The refill ONLY fires when `amount == totalSupply`, meaning one address must hold 100% of all shares.

**Verdict:** SAFE. Refill is guarded by exact total-supply match.

### C4: Dust attack analysis

**Question:** Can an attacker burn all but 1 share, deposit a large amount, then claim disproportionate value?

**Scenario:** Attacker holds 999,999,999,999.999... shares out of 1T. They burn all but 1 wei of shares (1e-18 shares).

Analysis:
- After burn: supply = 1 wei share, reserve = (reserve * 1) / 1T = negligible (1 wei of original reserve stays)
- If attacker then deposits 100 ETH: reserve = ~100 ETH, 1 share outstanding
- Burning that 1 share: claimValue = (100 ETH * 1) / 1 = 100 ETH -- but the attacker just deposited 100 ETH, so they get back what they put in.

Wait -- the attacker does NOT deposit. Only the GAME contract can call `deposit()` (onlyGame modifier). Direct ETH via `receive()` just adds to the vault's balance.

More realistic scenario:
- Attacker holds 999,999,999,999.999... shares, vault has 100 ETH
- Burns all but 1 share: receives 100 ETH * (1T-1)/(1T) = ~99.9999999999 ETH
- Vault has ~0.000000000001 ETH remaining, 1 share outstanding
- Someone sends ETH to vault via receive() -- say 10 ETH donation
- Attacker burns last share: receives 10.000000000001 ETH
- Refill triggers: 1T new shares, zero backing

The attacker received ~110 ETH total for their 1T shares backed by 100 ETH + a 10 ETH donation that arrived between burns. This is **correct behavior** -- the attacker owned 100% of shares and was entitled to 100% of the reserve at each moment. The 10 ETH donation was correctly captured by the sole shareholder.

**No value extraction vulnerability.** The attacker cannot claim more than the actual reserve at burn time.

**Verdict:** SAFE. Dust attacks cannot extract value beyond fair share.

### C5: vaultMint overflow in refill

```solidity
// In DegenerusVaultShare.vaultMint:
unchecked {
    totalSupply += amount;
    balanceOf[to] += amount;
}
```

The `unchecked` block: after burning all 1T shares, `totalSupply = 0`. Adding `REFILL_SUPPLY = 1T * 1e18` to 0 cannot overflow uint256 (max ~1.16e77, REFILL_SUPPLY ~1e30). SAFE.

Could repeated refill cycles accumulate? No -- refill only triggers when `supplyBefore == amount` (all burned). After refill, supply is 1T again. If burned again, supply goes to 0, then back to 1T. No accumulation.

**Verdict:** SAFE. No overflow risk in refill.

---

## Part D: Cross-Contract Interactions

### D1: ETH arrives via `_sendToVault` (GameOverModule line 182)

The vault's `receive()` function:
```solidity
receive() external payable {
    emit Deposit(msg.sender, msg.value, 0, 0);
}
```

When GameOverModule sends ETH to the vault via `payable(ContractAddresses.VAULT).call{value: ethAmount}("")`, the vault's `receive()` fires and emits a `Deposit` event. The ETH increases `address(this).balance`, which is read fresh by `_syncEthReserves()` on the next DGVE redemption.

**Verdict:** CORRECT. ETH arrives and immediately backs DGVE shares.

### D2: stETH arrives via `_sendToVault` (GameOverModule line 255)

```solidity
if (!steth.transfer(ContractAddresses.VAULT, vaultAmount)) revert E();
```

stETH is transferred directly to the vault. Since `_syncEthReserves()` reads `steth.balanceOf(address(this))` fresh, this transfer immediately increases the DGVE reserve.

**Note:** Due to Lido's share-based rounding, the actual stETH received may be 1-2 wei less than `vaultAmount`. This is the standard stETH transfer rounding behavior, documented in Lido's specifications. The vault receives slightly less than expected, which makes the vault-side accounting marginally conservative (vault-favorable rounding, as the Game's outflow is slightly more than the vault's inflow).

**Verdict:** CORRECT. stETH arrives and immediately backs DGVE shares. 1-2 wei rounding is inherent to stETH, not a bug.

### D3: BURNIE via `vaultEscrow` (BurnieCoin.sol line 677)

When the game calls `coinToken.vaultEscrow(coinAmount)`:
```solidity
function vaultEscrow(uint256 amount) external {
    // Access: GAME or VAULT only
    uint128 amount128 = _toUint128(amount);
    unchecked {
        _supply.vaultAllowance += amount128;
    }
    emit VaultEscrowRecorded(sender, amount);
}
```

Then the vault's `deposit()` calls:
```solidity
_syncCoinReserves();
coinToken.vaultEscrow(coinAmount);
coinTracked += coinAmount;
```

- `_syncCoinReserves()` first syncs `coinTracked` with the actual `vaultMintAllowance()`.
- Then `vaultEscrow` increases the allowance in BurnieCoin.
- Then `coinTracked` is incremented to match.

The `_burnCoinFor` function reads the reserve as `_syncCoinReserves()` which returns the actual `vaultMintAllowance()`, so `coinTracked` is mainly used for internal bookkeeping and is re-synced on every claim via `_syncCoinReserves()`.

**Verdict:** CORRECT. BURNIE escrow correctly increases the DGVB reserve.

### D4: `vaultAllowance` decrement via `vaultMintTo`

When the vault calls `coinToken.vaultMintTo(player, remaining)`:
1. BurnieCoin decreases `_supply.vaultAllowance` by `amount128`
2. BurnieCoin increases `_supply.totalSupply` by `amount128`
3. BurnieCoin increases `balanceOf[player]` by `amount`
4. Vault decreases `coinTracked` by `remaining`

The invariant `totalSupply + vaultAllowance = supplyIncUncirculated` is preserved (decrease allowance + increase totalSupply = net zero change).

The vault's `coinTracked` tracks the vault's view of `vaultAllowance`. After `vaultMintTo`, `coinTracked` is reduced, and the next `_syncCoinReserves()` call will re-sync it to the actual value. This is consistent.

**Verdict:** CORRECT. vaultAllowance correctly decremented, totalSupply correctly incremented.

### D5: JackpotModule daily distribution to vault (line 883-894)

```solidity
claimableDelta =
    _addClaimableEth(ContractAddresses.VAULT, stakeholderShare, rngWord) +
    _addClaimableEth(ContractAddresses.DGNRS, stakeholderShare, rngWord);
if (claimableDelta != 0) claimablePool += claimableDelta;
```

The vault is treated as a regular player for daily jackpot purposes -- it receives `claimableWinnings` in the GAME contract. The vault's `_burnEthFor` accounts for this via `claimable = gamePlayer.claimableWinningsOf(address(this))`, and auto-claims if needed (lines 859-863). This means:

1. Game distributes ETH to vault's `claimableWinnings` (in DegenerusGame storage)
2. When DGVE shares are redeemed, the vault includes this in the reserve calculation
3. If the claim exceeds on-hand ETH+stETH, the vault auto-claims from the game first

**Verdict:** CORRECT. Daily distributions are correctly accounted for in DGVE value.

---

## Informational Observations

### INFO-01: `_syncEthReserves` unchecked addition

```solidity
function _syncEthReserves() private view returns (uint256 ethBal, uint256 stBal, uint256 combined) {
    ethBal = address(this).balance;
    stBal = _stethBalance();
    unchecked {
        combined = ethBal + stBal;
    }
}
```

The `unchecked` addition could theoretically overflow if `ethBal + stBal > type(uint256).max`. In practice, this would require more than ~1.16e59 ETH, which exceeds the entire Ethereum supply by ~50 orders of magnitude. SAFE.

### INFO-02: `coinTracked` serves as internal bookkeeping only

The `coinTracked` variable is always re-synced via `_syncCoinReserves()` before being used in `_burnCoinFor`. Its purpose is to track the vault's view of `vaultAllowance` for the `deposit` flow, but it is not load-bearing for claim correctness since `_syncCoinReserves()` reads the authoritative value from BurnieCoin.

### INFO-03: stETH transfer rounding on claim payout

When `_paySteth(player, stEthOut)` transfers stETH to the claimer, the claimer may receive 1-2 wei less due to Lido's share-based rounding. This means the vault retains 1-2 wei of stETH "dust" per claim. Over many claims, this dust accumulates in the vault, slightly benefiting remaining DGVE holders. This is consistent with the vault-favorable rounding principle.

### INFO-04: Vault as game player -- circular value flow

The vault can be a game player (via vaultOwner functions). This creates a potential circular flow:
1. Vault plays game -> wins ETH -> credited to vault's `claimableWinnings`
2. DGVE redemption includes these winnings in the reserve
3. Vault owner claims DGVE -> receives ETH -> can re-deposit

This is not a vulnerability -- it is intentional design allowing the vault to participate in the game and have its winnings accrue to DGVE holders. The vault owner (>50.1% DGVE holder) takes on game risk on behalf of all DGVE holders.

### INFO-05: Refill recipient is always the burner

When refill triggers, the 1T new shares are minted to the player who burned the last shares:
```solidity
share.vaultMint(player, REFILL_SUPPLY);
```

This means the player who drains the vault completely receives all new shares. This is intentional -- there is no reserve, so the shares are worthless until new deposits arrive. The original INITIAL_SUPPLY went to CREATOR; subsequent refills go to the last redeemer.

---

## ACCT-09 Verdict

**Requirement:** DegenerusVault stETH yield accounting -- COIN mint amounts match expected yields

### Assessment

| Sub-requirement | Status | Evidence |
|----------------|--------|----------|
| DGVE share redemption formula mathematically correct | PASS | `claimValue = (reserve * amount) / supply` is standard proportional redemption; reserve includes ETH + stETH + game claimable |
| Rounding direction is vault-favorable (no extraction) | PASS | Integer division floors; remaining per-share value is >= pre-claim value |
| stETH yield passively increases DGVE value | PASS | `steth.balanceOf()` is read fresh every time; rebasing increases balance automatically |
| DGVB share redemption formula mathematically correct | PASS | `coinOut = (coinBal * amount) / supply` with coinBal = vaultAllowance + balance + coinflip claimable |
| DGVB rounding direction is vault-favorable | PASS | Same integer division flooring |
| Vault refill mechanism is safe | PASS | No residual after full burn; atomic refill; no race condition; no overflow |
| Cross-contract ETH/stETH flows correctly increase DGVE backing | PASS | `receive()` and stETH transfers immediately reflected in fresh balance reads |
| Cross-contract BURNIE flows correctly increase DGVB backing | PASS | `vaultEscrow` increases allowance; `vaultMintTo` correctly transfers from allowance to supply |

### ACCT-09: PASS

The DegenerusVault share-based redemption system is mathematically correct. Both DGVE and DGVB formulas implement standard proportional redemption with vault-favorable rounding. The refill mechanism safely handles the zero-supply edge case. stETH yield accrues passively to DGVE holders via fresh balance reads. All cross-contract flows (ETH, stETH, BURNIE) correctly update the vault's reserves.

No vulnerabilities found. No code modifications required.
