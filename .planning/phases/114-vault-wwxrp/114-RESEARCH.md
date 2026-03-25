# Phase 114: Vault + WWXRP - Research Notes

**Phase:** 114-vault-wwxrp
**Researched:** 2026-03-25

## Contract Inventory

### DegenerusVaultShare (contracts/DegenerusVault.sol L138-300)
**Purpose:** Minimal ERC20 share token for vault claim rights. Two instances deployed: DGVB (BURNIE claims) and DGVE (ETH+stETH claims).

**State Variables:**
| Variable | Type | Mutability | Notes |
|----------|------|------------|-------|
| name | string | immutable (set in constructor) | Token name |
| symbol | string | immutable (set in constructor) | Token symbol |
| decimals | uint8 | constant = 18 | Standard |
| INITIAL_SUPPLY | uint256 | constant = 1T * 1e18 | Initial mint |
| totalSupply | uint256 | mutable | Current supply |
| balanceOf | mapping(address => uint256) | mutable | Balances |
| allowance | mapping(address => mapping(address => uint256)) | mutable | Allowances |

**Functions (8 total):**
| # | Function | Visibility | State-Changing | Category |
|---|----------|------------|----------------|----------|
| 1 | constructor(name_, symbol_) | - | YES | B |
| 2 | approve(spender, amount) | external | YES | B |
| 3 | transfer(to, amount) | external | YES | B |
| 4 | transferFrom(from, to, amount) | external | YES | B |
| 5 | vaultMint(to, amount) | external onlyVault | YES | B |
| 6 | vaultBurn(from, amount) | external onlyVault | YES | B |
| 7 | _transfer(from, to, amount) | private | YES | C |
| 8 | decimals (constant) | public | NO | D |

**Access Control:**
- `onlyVault` modifier: checks `msg.sender != ContractAddresses.VAULT` (compile-time constant)
- Only vault can mint/burn. Standard ERC20 operations open to all.

**Critical Observations:**
1. `vaultMint` uses unchecked arithmetic for both totalSupply and balanceOf increments. Overflow is theoretically possible if totalSupply + amount > type(uint256).max, but practically impossible with 1T initial supply.
2. `vaultBurn` uses unchecked arithmetic for both totalSupply and balanceOf decrements. Protected by the balance check `if (amount > bal) revert Insufficient()` ensuring balanceOf won't underflow, and since balanceOf[from] <= totalSupply, totalSupply won't underflow either.
3. `_transfer` checks `to != address(0)` but NOT `from != address(0)`. Since _transfer is only called from `transfer` (msg.sender = from) and `transferFrom` (from is a parameter), from=address(0) in transferFrom would succeed but address(0) would need a balance first, which is only possible via the constructor mint to CREATOR.
4. Constructor mints to `ContractAddresses.CREATOR` -- hardcoded address.

### DegenerusVault (contracts/DegenerusVault.sol L309-1050)
**Purpose:** Multi-asset vault with two independent share classes. Holds ETH/stETH (claimed via DGVE) and BURNIE mint allowance (claimed via DGVB).

**State Variables:**
| Variable | Type | Mutability | Notes |
|----------|------|------------|-------|
| coinShare | DegenerusVaultShare | immutable | DGVB token |
| ethShare | DegenerusVaultShare | immutable | DGVE token |
| coinTracked | uint256 | mutable (private) | Tracked BURNIE mint allowance |
| REFILL_SUPPLY | uint256 | constant = 1T * 1e18 | Refill amount |

**External dependencies (all compile-time constants):**
- game (IDegenerusGame) at ContractAddresses.GAME
- gamePlayer (IDegenerusGamePlayerActions) at ContractAddresses.GAME
- coinflipPlayer (ICoinflipPlayerActions) at ContractAddresses.COINFLIP
- coinPlayer (ICoinPlayerActions) at ContractAddresses.COIN
- coinToken (IVaultCoin) at ContractAddresses.COIN
- wwxrpToken (IWWXRPMint) at ContractAddresses.WWXRP
- steth (IStETH) at ContractAddresses.STETH_TOKEN

**Functions (44 total):**
| # | Function | Visibility | State-Changing | Access | Category | Risk |
|---|----------|------------|----------------|--------|----------|------|
| 1 | constructor() | - | YES | - | B | LOW |
| 2 | deposit(coinAmount, stEthAmount) | external payable | YES | onlyGame | B | HIGH |
| 3 | receive() | external payable | YES | open | B | LOW |
| 4 | gameAdvance() | external | YES (proxy) | onlyVaultOwner | B | LOW |
| 5 | gamePurchase(...) | external payable | YES (proxy) | onlyVaultOwner | B | MED |
| 6 | gamePurchaseTicketsBurnie(...) | external | YES (proxy) | onlyVaultOwner | B | LOW |
| 7 | gamePurchaseBurnieLootbox(...) | external | YES (proxy) | onlyVaultOwner | B | LOW |
| 8 | gameOpenLootBox(...) | external | YES (proxy) | onlyVaultOwner | B | LOW |
| 9 | gamePurchaseDeityPassFromBoon(...) | external payable | YES (proxy) | onlyVaultOwner | B | HIGH |
| 10 | gameClaimWinnings() | external | YES (proxy) | onlyVaultOwner | B | LOW |
| 11 | gameClaimWhalePass() | external | YES (proxy) | onlyVaultOwner | B | LOW |
| 12 | gameDegeneretteBetEth(...) | external payable | YES (proxy) | onlyVaultOwner | B | MED |
| 13 | gameDegeneretteBetBurnie(...) | external | YES (proxy) | onlyVaultOwner | B | LOW |
| 14 | gameDegeneretteBetWwxrp(...) | external | YES (proxy) | onlyVaultOwner | B | LOW |
| 15 | gameResolveDegeneretteBets(...) | external | YES (proxy) | onlyVaultOwner | B | LOW |
| 16 | gameSetAutoRebuy(enabled) | external | YES (proxy) | onlyVaultOwner | B | LOW |
| 17 | gameSetAutoRebuyTakeProfit(takeProfit) | external | YES (proxy) | onlyVaultOwner | B | LOW |
| 18 | gameSetDecimatorAutoRebuy(enabled) | external | YES (proxy) | onlyVaultOwner | B | LOW |
| 19 | gameSetAfKingMode(...) | external | YES (proxy) | onlyVaultOwner | B | LOW |
| 20 | gameSetOperatorApproval(operator, approved) | external | YES (proxy) | onlyVaultOwner | B | LOW |
| 21 | coinDepositCoinflip(amount) | external | YES (proxy) | onlyVaultOwner | B | LOW |
| 22 | coinClaimCoinflips(amount) | external | YES (proxy) | onlyVaultOwner | B | LOW |
| 23 | coinDecimatorBurn(amount) | external | YES (proxy) | onlyVaultOwner | B | LOW |
| 24 | coinSetAutoRebuy(enabled, takeProfit) | external | YES (proxy) | onlyVaultOwner | B | LOW |
| 25 | coinSetAutoRebuyTakeProfit(takeProfit) | external | YES (proxy) | onlyVaultOwner | B | LOW |
| 26 | wwxrpMint(to, amount) | external | YES (proxy) | onlyVaultOwner | B | MED |
| 27 | jackpotsClaimDecimator(lvl) | external | YES (proxy) | onlyVaultOwner | B | LOW |
| 28 | burnCoin(player, amount) | external | YES | open (with approval) | B | CRITICAL |
| 29 | burnEth(player, amount) | external | YES | open (with approval) | B | CRITICAL |
| 30 | _burnCoinFor(player, amount) | private | YES | internal | C | CRITICAL |
| 31 | _burnEthFor(player, amount) | private | YES | internal | C | CRITICAL |
| 32 | _combinedValue(extraValue) | private view | NO | internal | D | - |
| 33 | _syncEthReserves() | private view | NO | internal | D | - |
| 34 | _syncCoinReserves() | private | YES (writes coinTracked) | internal | C | MED |
| 35 | _coinReservesView() | private view | NO | internal | D | - |
| 36 | _ethReservesView() | private view | NO | internal | D | - |
| 37 | _stethBalance() | private view | NO | internal | D | - |
| 38 | _payEth(to, amount) | private | YES (sends ETH) | internal | C | MED |
| 39 | _paySteth(to, amount) | private | YES (sends stETH) | internal | C | LOW |
| 40 | _pullSteth(from, amount) | private | YES (pulls stETH) | internal | C | LOW |
| 41 | previewBurnForCoinOut(coinOut) | external view | NO | open | D | - |
| 42 | previewBurnForEthOut(targetValue) | external view | NO | open | D | - |
| 43 | previewCoin(amount) | external view | NO | open | D | - |
| 44 | previewEth(amount) | external view | NO | open | D | - |

**Access Control:**
- `onlyGame`: `msg.sender != ContractAddresses.GAME` -- only the game contract
- `onlyVaultOwner`: `_isVaultOwner(msg.sender)` checks `balance * 1000 > supply * 501` (>50.1% of DGVE)
- `_requireApproved`: `msg.sender != player && !game.isOperatorApproved(player, msg.sender)`
- burnCoin/burnEth: open to msg.sender for own shares, or approved operators for others

### WrappedWrappedXRP (contracts/WrappedWrappedXRP.sol L40-389)
**Purpose:** ERC20 joke token that MAY be backed by wXRP. Intentionally undercollateralized.

**State Variables:**
| Variable | Type | Mutability | Notes |
|----------|------|------------|-------|
| name | string | constant | "Wrapped Wrapped WWXRP (PARODY)" |
| symbol | string | constant | "WWXRP" |
| decimals | uint8 | constant = 18 | |
| totalSupply | uint256 | mutable | Circulating supply (excludes vault allowance) |
| INITIAL_VAULT_ALLOWANCE | uint256 | constant = 1B * 1e18 | Initial uncirculating reserve |
| vaultAllowance | uint256 | mutable | Remaining vault reserve |
| balanceOf | mapping | mutable | Balances |
| allowance | mapping | mutable | Allowances |
| wXRP | IERC20 | constant | wXRP token at ContractAddresses.WXRP |
| MINTER_GAME | address | constant | ContractAddresses.GAME |
| MINTER_COIN | address | constant | ContractAddresses.COIN |
| MINTER_COINFLIP | address | constant | ContractAddresses.COINFLIP |
| MINTER_VAULT | address | constant | ContractAddresses.VAULT |
| wXRPReserves | uint256 | mutable | Tracked wXRP backing |

**Functions (12 total):**
| # | Function | Visibility | State-Changing | Access | Category | Risk |
|---|----------|------------|----------------|--------|----------|------|
| 1 | approve(spender, amount) | external | YES | open | B | LOW |
| 2 | transfer(to, amount) | external | YES | open | B | LOW |
| 3 | transferFrom(from, to, amount) | external | YES | open | B | LOW |
| 4 | unwrap(amount) | external | YES | open | B | HIGH |
| 5 | donate(amount) | external | YES | open | B | MED |
| 6 | mintPrize(to, amount) | external | YES | minters only | B | MED |
| 7 | vaultMintTo(to, amount) | external | YES | vault only | B | MED |
| 8 | burnForGame(from, amount) | external | YES | game only | B | MED |
| 9 | _transfer(from, to, amount) | internal | YES | internal | C | LOW |
| 10 | _mint(to, amount) | internal | YES | internal | C | LOW |
| 11 | _burn(from, amount) | internal | YES | internal | C | LOW |
| 12 | supplyIncUncirculated() | external view | NO | open | D | - |

**Access Control:**
- mintPrize: `msg.sender != MINTER_GAME && msg.sender != MINTER_COIN && msg.sender != MINTER_COINFLIP`
- vaultMintTo: `msg.sender != MINTER_VAULT`
- burnForGame: `msg.sender != MINTER_GAME`
- unwrap/donate/ERC20: open to all

## Critical Attack Surfaces Identified

### 1. Share Math Exploitation (CRITICAL)
**Location:** `_burnCoinFor` L762-802, `_burnEthFor` L833-876
**Pattern:** `claimValue = (reserve * amount) / supplyBefore`
- **Inflation attack:** First depositor could deposit 1 wei, burn all but 1 share, donate to inflate share price, then back-run new deposits. BUT the vault starts with 1T shares minted to CREATOR, so the inflation vector requires the CREATOR to burn down to a small amount first.
- **Rounding:** Division rounds DOWN (Solidity default), meaning the vault keeps the remainder. This favors the vault (correct direction).
- **Zero-supply edge case:** Handled by refill mechanism (1T shares minted when supplyBefore == amount).

### 2. Refill Mechanism (HIGH)
**Location:** `_burnCoinFor` L776-778, `_burnEthFor` L868-870
**Pattern:** If `supplyBefore == amount` (burning ALL shares), mint 1T new shares to the burner.
- After refill, the same user holds 100% of shares AND has already received their proportional claim.
- Key question: Can the refill holder immediately burn again to extract remaining reserves? YES - but they already own 100% of shares after refill, so they get proportionally what's left. This is working as intended since they're the only shareholder.
- Edge case: What if someone deposits between the refill and a second burn? The refill holder still has 1T shares, new deposit increases reserves, proportional claim is correct.

### 3. WWXRP Undercollateralized Unwrap Race (HIGH)
**Location:** `unwrap` L290-306
**Pattern:** Burns WWXRP, checks `wXRPReserves < amount`, transfers wXRP. CEI pattern (burn before transfer).
- Multiple unwrappers competing: first-come-first-served is by design.
- Reentrancy via wXRP: wXRP.transfer could call back, but WWXRP was already burned and wXRPReserves decremented. CEI is correct.
- If wXRP is a malicious token: out of scope (deployment assumption).

### 4. Virtual BURNIE Deposit Desync (MED)
**Location:** `deposit` L454-462, `_syncCoinReserves` L980-983
**Pattern:** coinTracked tracks BURNIE mint allowance. deposit() calls _syncCoinReserves() then coinToken.vaultEscrow(coinAmount) then coinTracked += coinAmount.
- `_syncCoinReserves()` reads the current vaultMintAllowance and sets coinTracked to match. This re-syncs on every deposit.
- BUT: If BURNIE mint allowance changes between syncs (e.g., another contract mints from vault allowance), coinTracked could be stale between _syncCoinReserves calls.
- In _burnCoinFor: `_syncCoinReserves()` is called first, so it always reads fresh. SAFE.

### 5. Vault Owner Threshold Timing (MED)
**Location:** `_isVaultOwner` L415-419
**Pattern:** `balance * 1000 > supply * 501` -- checked on every vault-owner-only call.
- If DGVE is traded, ownership can change between transactions. This is by design.
- Flash loan attack: Borrow DGVE to temporarily become vault owner, execute actions, return. This IS possible if DGVE can be flash loaned. However, DegenerusVaultShare has no flash loan functionality (no flash mint, no flash borrow). An attacker would need to acquire >50.1% through the market or OTC, which is expensive.
- But: standard ERC20 transfers allow atomic composability. In a single transaction, a contract could receive DGVE, become vault owner, act, and return DGVE. This requires a willing DGVE holder to approve the contract.

### 6. gamePurchaseDeityPassFromBoon Complex ETH Flow (MED)
**Location:** L536-546
**Pattern:** Check balance, optionally claim winnings, check balance again, purchase deity pass.
- If `address(this).balance < priceWei`, claims winnings to top up.
- Uses vault's own ETH balance to purchase. This reduces ETH available for DGVE claims.
- This is authorized by vault owner (>50.1% DGVE) so it's working as designed -- vault owner controls vault assets.

### 7. stETH Rounding in Vault (LOW)
**Location:** `_stethBalance` L1024-1026, `_syncEthReserves` L971-977
**Pattern:** stETH rebases can cause 1-2 wei rounding. Combined with division in share math, this could cause minor imprecision.
- Already documented in KNOWN-ISSUES.md: "stETH rounding strengthens invariant."

## Cross-Contract Interaction Map

```
DegenerusVault <---> DegenerusVaultShare (DGVB)
                     DegenerusVaultShare (DGVE)
                <---> DegenerusGame (gameplay proxy)
                <---> BurnieCoin (vaultEscrow, vaultMintTo, transfer)
                <---> BurnieCoinflip (depositCoinflip, claimCoinflips)
                <---> WrappedWrappedXRP (vaultMintTo)
                <---> stETH (Lido) (transfer, transferFrom, balanceOf)

WrappedWrappedXRP <---> wXRP (transfer, transferFrom, balanceOf)
                  <--- DegenerusGame (mintPrize, burnForGame)
                  <--- BurnieCoin (mintPrize)
                  <--- BurnieCoinflip (mintPrize)
                  <--- DegenerusVault (vaultMintTo)
```

## Function Count Summary

| Contract | State-Changing | View/Pure | Total |
|----------|---------------|-----------|-------|
| DegenerusVaultShare | 7 | 1 | 8 |
| DegenerusVault | 34 | 10 | 44 |
| WrappedWrappedXRP | 9 | 3 | 12 |
| **TOTAL** | **50** | **14** | **64** |

State-changing functions requiring full Mad Genius treatment (Category B): ~40
Private/internal helpers analyzed through parents (Category C): ~10
View/pure functions (Category D): ~14
