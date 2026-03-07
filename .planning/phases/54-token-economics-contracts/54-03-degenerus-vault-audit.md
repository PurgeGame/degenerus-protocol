# DegenerusVault.sol -- Function-Level Audit

**Contract:** DegenerusVault (+ DegenerusVaultShare helper)
**File:** contracts/DegenerusVault.sol
**Lines:** 1055
**Solidity:** 0.8.34
**Inherits:** None (standalone contracts, no inheritance)
**Audit date:** 2026-03-07

## Summary

DegenerusVault is a multi-asset vault with two independent share classes (DGVE for ETH+stETH, DGVB for BURNIE). The vault deploys two `DegenerusVaultShare` ERC-20 tokens at construction. It provides game proxy functions so the vault owner (holder of >50.1% DGVE) can play the Degenerus game through the vault. The vault accepts deposits from the GAME contract only (ETH, stETH, virtual BURNIE escrow). Users burn shares to extract proportional assets. stETH yield from Lido rebasing accrues passively to DGVE holders. A refill mechanism mints 1T new shares when all shares are burned, preventing division-by-zero.

**Two contracts in file:**
1. `DegenerusVaultShare` -- Minimal ERC-20 with vault-only mint/burn (lines 136-298)
2. `DegenerusVault` -- Main vault contract (lines 307-1055)

**Total functions audited:** 48 (7 in DegenerusVaultShare + 41 in DegenerusVault)

---

## Function Audit

---

## A. DegenerusVaultShare (ERC-20 Share Token)

---

### `constructor(string memory name_, string memory symbol_)` [public]

| Field | Value |
|-------|-------|
| **Signature** | `constructor(string memory name_, string memory symbol_)` |
| **Visibility** | public |
| **Mutability** | state-changing |
| **Parameters** | `name_` (string): token name; `symbol_` (string): token symbol |
| **Returns** | N/A |

**State Reads:** `ContractAddresses.CREATOR` (compile-time constant)
**State Writes:** `name`, `symbol`, `totalSupply` (= INITIAL_SUPPLY = 1T * 1e18), `balanceOf[CREATOR]` (= INITIAL_SUPPLY)

**Callers:** Deployed by DegenerusVault constructor (twice: once for DGVB, once for DGVE)
**Callees:** None (emits Transfer event)

**ETH Flow:** None
**Invariants:** After construction, totalSupply == INITIAL_SUPPLY and balanceOf[CREATOR] == INITIAL_SUPPLY. No other balances set.
**NatSpec Accuracy:** Accurate. States "initial supply is minted to CREATOR."
**Gas Flags:** None
**Verdict:** CORRECT

---

### `approve(address spender, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function approve(address spender, uint256 amount) external returns (bool)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `spender` (address): address to approve; `amount` (uint256): allowance amount |
| **Returns** | `bool`: always true |

**State Reads:** None
**State Writes:** `allowance[msg.sender][spender]` = amount

**Callers:** External (users)
**Callees:** None (emits Approval event)

**ETH Flow:** None
**Invariants:** Allowance can be set to any value including 0. No zero-address check on spender (standard ERC-20 pattern).
**NatSpec Accuracy:** Accurate. Mentions type(uint256).max for unlimited.
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
**State Writes:** `balanceOf[msg.sender]` (decremented), `balanceOf[to]` (incremented) (via `_transfer`)

**Callers:** External (users, vault contract for BURNIE transfer in `_burnCoinFor`)
**Callees:** `_transfer(msg.sender, to, amount)`

**ETH Flow:** None
**Invariants:** Sum of all balances unchanged. Reverts if to == address(0) or insufficient balance.
**NatSpec Accuracy:** Accurate.
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

**State Reads:** `allowance[from][msg.sender]`
**State Writes:** `allowance[from][msg.sender]` (decremented if not max), `balanceOf[from]` (decremented), `balanceOf[to]` (incremented)

**Callers:** External (users, operators)
**Callees:** `_transfer(from, to, amount)`

**ETH Flow:** None
**Invariants:** Allowance decremented before transfer (CEI). Infinite allowance (type(uint256).max) not decremented -- standard gas optimization. Emits Approval event on allowance change.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `vaultMint(address to, uint256 amount)` [external, onlyVault]

| Field | Value |
|-------|-------|
| **Signature** | `function vaultMint(address to, uint256 amount) external onlyVault` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): mint amount |
| **Returns** | None |

**State Reads:** None
**State Writes:** `totalSupply` (incremented), `balanceOf[to]` (incremented)

**Callers:** DegenerusVault._burnCoinFor (refill), DegenerusVault._burnEthFor (refill)
**Callees:** None (emits Transfer from address(0))

**ETH Flow:** None
**Invariants:** Only callable by VAULT. Reverts if to == address(0). Uses unchecked arithmetic -- overflow is theoretically possible but practically impossible (totalSupply would need to exceed 2^256).
**NatSpec Accuracy:** Accurate. States "Used for refill mechanism when all shares are burned."
**Gas Flags:** Unchecked addition -- safe in practice (1T * 1e18 * 2 << 2^256).
**Verdict:** CORRECT

---

### `vaultBurn(address from, uint256 amount)` [external, onlyVault]

| Field | Value |
|-------|-------|
| **Signature** | `function vaultBurn(address from, uint256 amount) external onlyVault` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): holder to burn from; `amount` (uint256): burn amount |
| **Returns** | None |

**State Reads:** `balanceOf[from]`
**State Writes:** `balanceOf[from]` (decremented), `totalSupply` (decremented)

**Callers:** DegenerusVault._burnCoinFor, DegenerusVault._burnEthFor
**Callees:** None (emits Transfer to address(0))

**ETH Flow:** None
**Invariants:** Checks amount <= balance before burning. Uses unchecked subtraction -- safe because of the prior check.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_transfer(address from, address to, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _transfer(address from, address to, uint256 amount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): source; `to` (address): destination; `amount` (uint256): transfer amount |
| **Returns** | None |

**State Reads:** `balanceOf[from]`
**State Writes:** `balanceOf[from]` (decremented), `balanceOf[to]` (incremented)

**Callers:** `transfer`, `transferFrom`
**Callees:** None (emits Transfer event)

**ETH Flow:** None
**Invariants:** Reverts on to == address(0) or insufficient balance. Unchecked arithmetic -- underflow safe (amount <= bal checked), overflow on balanceOf[to] practically impossible (sum of balances <= totalSupply).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** No zero-address check on `from` -- acceptable since `from` always originates from msg.sender or allowance-checked addresses.
**Verdict:** CORRECT

---

## B. DegenerusVault -- Modifiers & Access Control

---

### `onlyGame()` [modifier]

| Field | Value |
|-------|-------|
| **Signature** | `modifier onlyGame()` |
| **Visibility** | internal (modifier) |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | N/A |

**State Reads:** `ContractAddresses.GAME` (compile-time constant)
**State Writes:** None

**Callers:** `deposit`
**Callees:** None

**ETH Flow:** None
**Invariants:** Only the GAME contract can call deposit.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `onlyVaultOwner()` [modifier]

| Field | Value |
|-------|-------|
| **Signature** | `modifier onlyVaultOwner()` |
| **Visibility** | internal (modifier) |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | N/A |

**State Reads:** `ethShare.totalSupply()`, `ethShare.balanceOf(msg.sender)` (via `_isVaultOwner`)
**State Writes:** None

**Callers:** All 27 game proxy/coin proxy/claim functions
**Callees:** `_isVaultOwner(msg.sender)`

**ETH Flow:** None
**Invariants:** Requires balance * 1000 > supply * 501 (i.e., >50.1% of DGVE).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** Two external calls per invocation (totalSupply + balanceOf on DegenerusVaultShare). These are same-transaction calls to contracts deployed by this contract. Acceptable.
**Verdict:** CORRECT

---

### `_requireApproved(address player)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _requireApproved(address player) private view` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `player` (address): player to check approval for |
| **Returns** | None (reverts if not approved) |

**State Reads:** `game.isOperatorApproved(player, msg.sender)` (external call to GAME)
**State Writes:** None

**Callers:** `burnCoin`, `burnEth`
**Callees:** `game.isOperatorApproved(player, msg.sender)`

**ETH Flow:** None
**Invariants:** Skips check if msg.sender == player. Otherwise checks game contract's operator approval system.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** External call to GAME contract for operator check.
**Verdict:** CORRECT

---

### `_isVaultOwner(address account)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _isVaultOwner(address account) private view returns (bool)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `account` (address): address to check |
| **Returns** | `bool`: true if >50.1% of DGVE |

**State Reads:** `ethShare.totalSupply()`, `ethShare.balanceOf(account)`
**State Writes:** None

**Callers:** `onlyVaultOwner` modifier, `isVaultOwner` (external wrapper)
**Callees:** `ethShare.totalSupply()`, `ethShare.balanceOf(account)`

**ETH Flow:** None
**Invariants:** Formula: balance * 1000 > supply * 501. This means >50.1% is required (not >=50.1%). If supply is 0 and balance is 0, returns false (0 > 0 is false) -- but supply can never be 0 due to refill mechanism.
**NatSpec Accuracy:** Accurate. Comment says ">50.1%".
**Gas Flags:** None
**Verdict:** CORRECT

---

### `isVaultOwner(address account)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function isVaultOwner(address account) external view returns (bool)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `account` (address): address to check |
| **Returns** | `bool`: true if >50.1% of DGVE |

**State Reads:** Via `_isVaultOwner`
**State Writes:** None

**Callers:** External (UI, other contracts)
**Callees:** `_isVaultOwner(account)`

**ETH Flow:** None
**Invariants:** Public wrapper for `_isVaultOwner`.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

## C. DegenerusVault -- Constructor

---

### `constructor()` [public]

| Field | Value |
|-------|-------|
| **Signature** | `constructor()` |
| **Visibility** | public |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | N/A |

**State Reads:** `coinToken.vaultMintAllowance()` (external call to COIN contract)
**State Writes:** `coinShare` (immutable, set to new DegenerusVaultShare("Degenerus Vault Burnie", "DGVB")), `ethShare` (immutable, set to new DegenerusVaultShare("Degenerus Vault Eth", "DGVE")), `coinTracked` (set to initial coin allowance)

**Callers:** Deployer
**Callees:** `new DegenerusVaultShare(...)` (x2), `coinToken.vaultMintAllowance()`

**ETH Flow:** None
**Invariants:** COIN contract must be deployed before VAULT (to call vaultMintAllowance). Both share tokens get INITIAL_SUPPLY (1T * 1e18) minted to CREATOR.
**NatSpec Accuracy:** Accurate. States "Deploys DGVB and DGVE tokens. Creator receives initial 1T supply of each."
**Gas Flags:** None
**Verdict:** CORRECT

---

## D. DegenerusVault -- Deposit

---

### `deposit(uint256 coinAmount, uint256 stEthAmount)` [external payable, onlyGame]

| Field | Value |
|-------|-------|
| **Signature** | `function deposit(uint256 coinAmount, uint256 stEthAmount) external payable onlyGame` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | `coinAmount` (uint256): BURNIE mint allowance to escrow; `stEthAmount` (uint256): stETH to pull from GAME |
| **Returns** | None |

**State Reads:** `coinToken.vaultMintAllowance()` (via `_syncCoinReserves` if coinAmount != 0)
**State Writes:** `coinTracked` (synced + coinAmount if coinAmount != 0)

**Callers:** DegenerusGame (external, the GAME contract)
**Callees:** `_syncCoinReserves()`, `coinToken.vaultEscrow(coinAmount)`, `_pullSteth(msg.sender, stEthAmount)`

**ETH Flow:** msg.value from GAME -> vault ETH balance. stETH from GAME -> vault stETH balance (via transferFrom). BURNIE is virtual (escrow increases allowance, no token transfer).
**Invariants:** Only GAME can call. coinToken.vaultEscrow increases the vault's mint allowance on the coin contract. stETH transferFrom requires GAME to have approved the vault.
**NatSpec Accuracy:** Accurate. Explains virtual BURNIE deposit, ETH via msg.value, stETH via transferFrom.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `receive()` [external payable]

| Field | Value |
|-------|-------|
| **Signature** | `receive() external payable` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | None |
| **Returns** | None |

**State Reads:** None
**State Writes:** None (ETH balance increases implicitly)

**Callers:** Any external sender (donation pathway)
**Callees:** None (emits Deposit event with 0 stETH and 0 BURNIE)

**ETH Flow:** msg.value -> vault ETH balance (donated, accrues to DGVE holders)
**Invariants:** Open to any sender. ETH donations increase the backing ratio of DGVE shares.
**NatSpec Accuracy:** Accurate. Says "Receive ETH donations from any sender."
**Gas Flags:** None
**Verdict:** CORRECT

---

## E. DegenerusVault -- Game Proxy Functions

---

### `gameAdvance()` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gameAdvance() external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner modifier
**State Writes:** None (state changes happen in GAME contract)

**Callers:** Vault owner (>50.1% DGVE holder)
**Callees:** `gamePlayer.advanceGame()`

**ETH Flow:** None directly. The advanceGame call may trigger Lido stETH submission inside the GAME contract, which could send ETH to Lido.
**Invariants:** Only vault owner can advance the game on behalf of the vault.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `gamePurchase(uint256 ticketQuantity, uint256 lootBoxAmount, bytes32 affiliateCode, MintPaymentKind payKind, uint256 ethValue)` [external payable, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gamePurchase(uint256 ticketQuantity, uint256 lootBoxAmount, bytes32 affiliateCode, MintPaymentKind payKind, uint256 ethValue) external payable onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | `ticketQuantity` (uint256): number of tickets; `lootBoxAmount` (uint256): ETH for lootboxes; `affiliateCode` (bytes32): affiliate code; `payKind` (MintPaymentKind): payment method; `ethValue` (uint256): additional ETH from vault balance |
| **Returns** | None |

**State Reads:** `address(this).balance` (via `_combinedValue`)
**State Writes:** None directly (state changes in GAME)

**Callers:** Vault owner
**Callees:** `_combinedValue(ethValue)`, `gamePlayer.purchase{value: totalValue}(address(this), ...)`

**ETH Flow:** msg.value + ethValue from vault balance -> GAME contract via purchase{value}. Vault is the `buyer` (address(this)).
**Invariants:** _combinedValue reverts if msg.value + ethValue > address(this).balance. Vault acts as buyer so game tickets accrue to the vault address.
**NatSpec Accuracy:** Accurate. Explains msg.value combination with vault balance.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `gamePurchaseTicketsBurnie(uint256 ticketQuantity)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gamePurchaseTicketsBurnie(uint256 ticketQuantity) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `ticketQuantity` (uint256): number of tickets |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in GAME/COIN)

**Callers:** Vault owner
**Callees:** `gamePlayer.purchaseCoin(address(this), ticketQuantity, 0)`

**ETH Flow:** None (BURNIE-denominated purchase, no ETH)
**Invariants:** Reverts if ticketQuantity == 0. Passes 0 for lootBoxBurnieAmount (tickets only, no lootbox).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `gamePurchaseBurnieLootbox(uint256 burnieAmount)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gamePurchaseBurnieLootbox(uint256 burnieAmount) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `burnieAmount` (uint256): BURNIE to spend on lootbox |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in GAME/COIN)

**Callers:** Vault owner
**Callees:** `gamePlayer.purchaseBurnieLootbox(address(this), burnieAmount)`

**ETH Flow:** None (BURNIE-denominated)
**Invariants:** Reverts if burnieAmount == 0.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `gameOpenLootBox(uint48 lootboxIndex)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gameOpenLootBox(uint48 lootboxIndex) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `lootboxIndex` (uint48): index of the lootbox to open |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in GAME)

**Callers:** Vault owner
**Callees:** `gamePlayer.openLootBox(address(this), lootboxIndex)`

**ETH Flow:** Game may send ETH/stETH/BURNIE/DGNRS rewards to the vault as a result.
**Invariants:** Vault is the player (address(this)).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `gamePurchaseDeityPassFromBoon(uint256 priceWei)` [external payable, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gamePurchaseDeityPassFromBoon(uint256 priceWei) external payable onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | `priceWei` (uint256): expected deity pass price |
| **Returns** | None |

**State Reads:** `address(this).balance`, `gamePlayer.claimableWinningsOf(address(this))`
**State Writes:** None directly (state changes in GAME)

**Callers:** Vault owner
**Callees:** `gamePlayer.claimableWinningsOf(address(this))`, `gamePlayer.claimWinnings(address(this))`, `gamePlayer.purchaseDeityPass{value: priceWei}(address(this), true)`

**ETH Flow:** If vault balance < priceWei, auto-claims game winnings first. Then sends priceWei to GAME for deity pass purchase. The `true` parameter means "use boon" (post-presale deity pass).
**Invariants:** Reverts if priceWei == 0 or vault balance insufficient even after claiming winnings. The claimable > 1 check avoids claiming dust (game uses 1 wei as sentinel for "has claimable").
**NatSpec Accuracy:** Accurate. Mentions the pricing formula (24 + T(n) ETH).
**Gas Flags:** None
**Verdict:** CORRECT

---

### `gameClaimWinnings()` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gameClaimWinnings() external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (GAME updates claimable balance)

**Callers:** Vault owner
**Callees:** `gamePlayer.claimWinningsStethFirst()`

**ETH Flow:** GAME sends ETH or stETH to the vault (claimWinningsStethFirst prefers stETH). This accrues to DGVE holders.
**Invariants:** Uses claimWinningsStethFirst (not claimWinnings) -- intentional vault optimization since stETH earns yield and both accrue to DGVE.
**NatSpec Accuracy:** Accurate. States "preferring stETH."
**Gas Flags:** None
**Verdict:** CORRECT

---

### `gameClaimWhalePass()` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gameClaimWhalePass() external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in GAME)

**Callers:** Vault owner
**Callees:** `gamePlayer.claimWhalePass(address(this))`

**ETH Flow:** None (whale pass is a status, not a token transfer)
**Invariants:** Vault is the player (address(this)).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `gameDegeneretteBetEth(uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 customSpecial, uint256 ethValue)` [external payable, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gameDegeneretteBetEth(uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 customSpecial, uint256 ethValue) external payable onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | `amountPerTicket` (uint128): bet per ticket; `ticketCount` (uint8): number of tickets; `customTicket` (uint32): packed traits; `customSpecial` (uint8): hero quadrant; `ethValue` (uint256): additional vault ETH |
| **Returns** | None |

**State Reads:** `address(this).balance` (via `_combinedValue`)
**State Writes:** None directly (state changes in GAME)

**Callers:** Vault owner
**Callees:** `_combinedValue(ethValue)`, `gamePlayer.placeFullTicketBets{value: totalValue}(address(this), 0, ...)`

**ETH Flow:** msg.value + ethValue -> GAME contract. Currency = 0 (ETH).
**Invariants:** Reverts if totalValue > totalBet (overpayment guard). This prevents sending more ETH than the bet requires. Uses _combinedValue for balance check.
**NatSpec Accuracy:** Mostly accurate. NatSpec says "customSpecial" but the interface parameter name is `heroQuadrant`. The NatSpec description "(1=ETH,2=BURNIE,3=DGNRS)" is misleading -- the actual interface defines it as hero quadrant (0-3 for payout boost, 0xFF for no hero).
**Gas Flags:** None
**Verdict:** CONCERN -- NatSpec for `customSpecial` parameter is inaccurate. It describes currency types but the underlying interface parameter is `heroQuadrant` for payout boost selection. Functional behavior is correct since the value is passed through unchanged.

---

### `gameDegeneretteBetBurnie(uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 customSpecial)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gameDegeneretteBetBurnie(uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 customSpecial) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `amountPerTicket` (uint128): bet per ticket; `ticketCount` (uint8): tickets; `customTicket` (uint32): packed traits; `customSpecial` (uint8): hero quadrant |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in GAME)

**Callers:** Vault owner
**Callees:** `gamePlayer.placeFullTicketBets(address(this), 1, ...)` (currency = 1 = BURNIE)

**ETH Flow:** None (BURNIE-denominated bet)
**Invariants:** No ETH forwarded. BURNIE is burned from vault's coin balance by the GAME contract.
**NatSpec Accuracy:** Same concern as gameDegeneretteBetEth regarding `customSpecial`.
**Gas Flags:** None
**Verdict:** CORRECT (functional, NatSpec informational only)

---

### `gameDegeneretteBetWwxrp(uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 customSpecial)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gameDegeneretteBetWwxrp(uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 customSpecial) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `amountPerTicket` (uint128): bet per ticket; `ticketCount` (uint8): tickets; `customTicket` (uint32): packed traits; `customSpecial` (uint8): hero quadrant |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in GAME)

**Callers:** Vault owner
**Callees:** `gamePlayer.placeFullTicketBets(address(this), 3, ...)` (currency = 3 = WWXRP)

**ETH Flow:** None (WWXRP-denominated bet)
**Invariants:** No ETH forwarded. WWXRP is burned from vault by the GAME contract.
**NatSpec Accuracy:** Same concern as gameDegeneretteBetEth regarding `customSpecial`.
**Gas Flags:** None
**Verdict:** CORRECT (functional, NatSpec informational only)

---

### `gameResolveDegeneretteBets(uint64[] calldata betIds)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gameResolveDegeneretteBets(uint64[] calldata betIds) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `betIds` (uint64[]): bet identifiers to resolve |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in GAME)

**Callers:** Vault owner
**Callees:** `gamePlayer.resolveDegeneretteBets(address(this), betIds)`

**ETH Flow:** GAME may send ETH/BURNIE/WWXRP winnings to vault upon resolution.
**Invariants:** Vault is the player (address(this)).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `gameSetAutoRebuy(bool enabled)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gameSetAutoRebuy(bool enabled) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `enabled` (bool): enable/disable auto-rebuy |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in GAME)

**Callers:** Vault owner
**Callees:** `gamePlayer.setAutoRebuy(address(this), enabled)`

**ETH Flow:** None (configuration only)
**Invariants:** None
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `gameSetAutoRebuyTakeProfit(uint256 takeProfit)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gameSetAutoRebuyTakeProfit(uint256 takeProfit) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `takeProfit` (uint256): take profit threshold |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in GAME)

**Callers:** Vault owner
**Callees:** `gamePlayer.setAutoRebuyTakeProfit(address(this), takeProfit)`

**ETH Flow:** None (configuration only)
**Invariants:** None
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `gameSetDecimatorAutoRebuy(bool enabled)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gameSetDecimatorAutoRebuy(bool enabled) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `enabled` (bool): enable/disable decimator auto-rebuy |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in GAME)

**Callers:** Vault owner
**Callees:** `gamePlayer.setDecimatorAutoRebuy(address(this), enabled)`

**ETH Flow:** None (configuration only)
**Invariants:** None
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `gameSetAfKingMode(bool enabled, uint256 ethTakeProfit, uint256 coinTakeProfit)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gameSetAfKingMode(bool enabled, uint256 ethTakeProfit, uint256 coinTakeProfit) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `enabled` (bool): enable/disable AFK king mode; `ethTakeProfit` (uint256): ETH take profit; `coinTakeProfit` (uint256): coin take profit |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in GAME)

**Callers:** Vault owner
**Callees:** `gamePlayer.setAfKingMode(address(this), enabled, ethTakeProfit, coinTakeProfit)`

**ETH Flow:** None (configuration only)
**Invariants:** None
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `gameSetOperatorApproval(address operator, bool approved)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gameSetOperatorApproval(address operator, bool approved) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `operator` (address): address to approve/revoke; `approved` (bool): approval status |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in GAME)

**Callers:** Vault owner
**Callees:** `gamePlayer.setOperatorApproval(operator, approved)`

**ETH Flow:** None (configuration only)
**Invariants:** None
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

## F. DegenerusVault -- Coin Proxy Functions

---

### `coinDepositCoinflip(uint256 amount)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function coinDepositCoinflip(uint256 amount) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `amount` (uint256): BURNIE to deposit into coinflip |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in COIN)

**Callers:** Vault owner
**Callees:** `coinPlayer.depositCoinflip(address(this), amount)`

**ETH Flow:** None (BURNIE-denominated)
**Invariants:** BURNIE is transferred from vault to coinflip pool via the COIN contract.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `coinClaimCoinflips(uint256 amount)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function coinClaimCoinflips(uint256 amount) external onlyVaultOwner returns (uint256 claimed)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `amount` (uint256): maximum amount to claim |
| **Returns** | `claimed` (uint256): actual amount claimed |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in COIN)

**Callers:** Vault owner
**Callees:** `coinPlayer.claimCoinflips(address(this), amount)`

**ETH Flow:** None (BURNIE-denominated)
**Invariants:** Returns actual claimed amount (may be less than requested).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `coinClaimCoinflipsTakeProfit(uint256 multiples)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function coinClaimCoinflipsTakeProfit(uint256 multiples) external onlyVaultOwner returns (uint256 claimed)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `multiples` (uint256): number of take profit multiples |
| **Returns** | `claimed` (uint256): actual amount claimed |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in COIN)

**Callers:** Vault owner
**Callees:** `coinPlayer.claimCoinflipsTakeProfit(address(this), multiples)`

**ETH Flow:** None (BURNIE-denominated)
**Invariants:** None
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `coinDecimatorBurn(uint256 amount)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function coinDecimatorBurn(uint256 amount) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `amount` (uint256): BURNIE to burn in decimator |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in COIN/GAME)

**Callers:** Vault owner
**Callees:** `coinPlayer.decimatorBurn(address(this), amount)`

**ETH Flow:** None (BURNIE burn for decimator jackpot eligibility)
**Invariants:** None
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `coinSetAutoRebuy(bool enabled, uint256 takeProfit)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function coinSetAutoRebuy(bool enabled, uint256 takeProfit) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `enabled` (bool): enable/disable; `takeProfit` (uint256): take profit threshold |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in COIN)

**Callers:** Vault owner
**Callees:** `coinPlayer.setCoinflipAutoRebuy(address(this), enabled, takeProfit)`

**ETH Flow:** None (configuration only)
**Invariants:** None
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `coinSetAutoRebuyTakeProfit(uint256 takeProfit)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function coinSetAutoRebuyTakeProfit(uint256 takeProfit) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `takeProfit` (uint256): take profit threshold |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in COIN)

**Callers:** Vault owner
**Callees:** `coinPlayer.setCoinflipAutoRebuyTakeProfit(address(this), takeProfit)`

**ETH Flow:** None (configuration only)
**Invariants:** None
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `wwxrpMint(address to, uint256 amount)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function wwxrpMint(address to, uint256 amount) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): WWXRP to mint |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in WWXRP contract)

**Callers:** Vault owner
**Callees:** `wwxrpToken.vaultMintTo(to, amount)`

**ETH Flow:** None (WWXRP token mint)
**Invariants:** Early return if amount == 0. The WWXRP contract enforces its own allowance limits.
**NatSpec Accuracy:** Accurate. Mentions "uncirculating reserve."
**Gas Flags:** None
**Verdict:** CORRECT

---

### `jackpotsClaimDecimator(uint24 lvl)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function jackpotsClaimDecimator(uint24 lvl) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): jackpot level to claim |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in GAME)

**Callers:** Vault owner
**Callees:** `gamePlayer.claimDecimatorJackpot(lvl)`

**ETH Flow:** GAME sends ETH to vault if vault won the decimator jackpot at that level.
**Invariants:** None
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

## G. DegenerusVault -- Burn/Claim Functions

---

### `burnCoin(address player, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function burnCoin(address player, uint256 amount) external returns (uint256 coinOut)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): address to burn shares for (address(0) = msg.sender); `amount` (uint256): DGVB shares to burn |
| **Returns** | `coinOut` (uint256): BURNIE sent to player |

**State Reads:** Via `_requireApproved` (game.isOperatorApproved)
**State Writes:** Via `_burnCoinFor`

**Callers:** External (DGVB holders, operators)
**Callees:** `_requireApproved(player)`, `_burnCoinFor(player, amount)`

**ETH Flow:** None (BURNIE output only)
**Invariants:** If player is address(0), uses msg.sender. If player != msg.sender, checks operator approval via game contract.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_burnCoinFor(address player, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _burnCoinFor(address player, uint256 amount) private returns (uint256 coinOut)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): recipient of BURNIE; `amount` (uint256): DGVB shares to burn |
| **Returns** | `coinOut` (uint256): BURNIE sent to player |

**State Reads:** `coinToken.vaultMintAllowance()` (via `_syncCoinReserves`), `coinShare.totalSupply()`, `coinToken.balanceOf(address(this))`, `coinPlayer.previewClaimCoinflips(address(this))`
**State Writes:** `coinTracked` (via `_syncCoinReserves`, and decremented when minting remainder)

**Callers:** `burnCoin`
**Callees:** `_syncCoinReserves()`, `coinShare.totalSupply()`, `coinToken.balanceOf(address(this))`, `coinPlayer.previewClaimCoinflips(address(this))`, `coinShare.vaultBurn(player, amount)`, `coinShare.vaultMint(player, REFILL_SUPPLY)` (if burning all), `coinToken.transfer(player, ...)`, `coinPlayer.claimCoinflips(address(this), remaining)`, `coinToken.vaultMintTo(player, remaining)`

**ETH Flow:** None
**Invariants:**
1. coinOut = (totalReserve * amount) / supplyBefore -- rounds DOWN (in vault's favor).
2. Total reserve = vaultMintAllowance + vault BURNIE balance + claimable coinflips.
3. Payment priority: vault balance first, then claim coinflips, then mint from allowance.
4. Refill: if burning entire supply, mint REFILL_SUPPLY (1T) to the burner.
5. coinTracked decremented by the minted remainder amount.

**NatSpec Accuracy:** Accurate.
**Gas Flags:** Multiple external calls (totalSupply, balanceOf, previewClaimCoinflips, claimCoinflips). This is inherent to the multi-source payout logic.
**Verdict:** CORRECT -- Rounding is in vault's favor (floor division). Payment waterfall ensures BURNIE is sourced from the cheapest path (balance > coinflips > mint). Refill prevents zero-supply.

---

### `burnEth(address player, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function burnEth(address player, uint256 amount) external returns (uint256 ethOut, uint256 stEthOut)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): address to burn shares for (address(0) = msg.sender); `amount` (uint256): DGVE shares to burn |
| **Returns** | `ethOut` (uint256): ETH sent to player; `stEthOut` (uint256): stETH sent to player |

**State Reads:** Via `_requireApproved`
**State Writes:** Via `_burnEthFor`

**Callers:** External (DGVE holders, operators)
**Callees:** `_requireApproved(player)`, `_burnEthFor(player, amount)`

**ETH Flow:** ETH and/or stETH from vault -> player
**Invariants:** Same approval pattern as burnCoin.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_burnEthFor(address player, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _burnEthFor(address player, uint256 amount) private returns (uint256 ethOut, uint256 stEthOut)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): recipient of ETH/stETH; `amount` (uint256): DGVE shares to burn |
| **Returns** | `ethOut` (uint256): ETH sent; `stEthOut` (uint256): stETH sent |

**State Reads:** `address(this).balance`, `steth.balanceOf(address(this))` (via `_syncEthReserves`), `gamePlayer.claimableWinningsOf(address(this))`, `ethShare.totalSupply()`
**State Writes:** None directly in vault storage (share burn happens in DegenerusVaultShare)

**Callers:** `burnEth`
**Callees:** `_syncEthReserves()`, `gamePlayer.claimableWinningsOf(address(this))`, `ethShare.totalSupply()`, `gamePlayer.claimWinnings(address(this))`, `_stethBalance()`, `ethShare.vaultBurn(player, amount)`, `ethShare.vaultMint(player, REFILL_SUPPLY)`, `_payEth(player, ethOut)`, `_paySteth(player, stEthOut)`

**ETH Flow:** vault ETH -> player (preferred), vault stETH -> player (remainder)
**Invariants:**
1. reserve = ethBal + stethBal + claimable (with claimable adjusted: if claimable <= 1, treat as 0; else claimable -= 1).
2. claimValue = (reserve * amount) / supplyBefore -- rounds DOWN (in vault's favor).
3. If claimValue > ethBal + stethBal and claimable != 0, auto-claims game winnings first to increase ETH balance.
4. ETH preferred: if claimValue <= ethBal, all ETH. Else ethBal ETH + (claimValue - ethBal) stETH.
5. Reverts if stEthOut > stBal (insufficient stETH).
6. Refill: if burning entire supply, mint REFILL_SUPPLY to burner.

**NatSpec Accuracy:** Accurate. Mentions "ETH is preferred over stETH."
**Gas Flags:** Multiple external calls. Auto-claim of game winnings adds gas but is necessary for correctness.
**Verdict:** CORRECT -- Rounding is in vault's favor (floor division). Auto-claim prevents scenarios where claimable value is locked. ETH preference minimizes stETH transfers (which have 1-2 wei rounding in Lido).

---

## H. DegenerusVault -- Preview/View Functions

---

### `previewBurnForCoinOut(uint256 coinOut)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function previewBurnForCoinOut(uint256 coinOut) external view returns (uint256 burnAmount)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `coinOut` (uint256): target BURNIE to receive |
| **Returns** | `burnAmount` (uint256): DGVB shares required to burn |

**State Reads:** `coinToken.vaultMintAllowance()`, `coinToken.balanceOf(address(this))`, `coinPlayer.previewClaimCoinflips(address(this))` (via `_coinReservesView`), `coinShare.totalSupply()`
**State Writes:** None

**Callers:** External (UI)
**Callees:** `_coinReservesView()`, `coinShare.totalSupply()`

**ETH Flow:** None
**Invariants:** Uses ceiling division: (coinOut * supply + reserve - 1) / reserve. This ensures the user burns enough shares (rounds UP against the user). Reverts if coinOut == 0 or coinOut > reserve.
**NatSpec Accuracy:** Accurate. States "ceiling division."
**Gas Flags:** None
**Verdict:** CORRECT -- Ceiling division correctly ensures sufficient burn amount.

---

### `previewBurnForEthOut(uint256 targetValue)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function previewBurnForEthOut(uint256 targetValue) external view returns (uint256 burnAmount, uint256 ethOut, uint256 stEthOut)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `targetValue` (uint256): target combined ETH+stETH value |
| **Returns** | `burnAmount` (uint256): DGVE shares to burn; `ethOut` (uint256): estimated ETH; `stEthOut` (uint256): estimated stETH |

**State Reads:** `ethShare.totalSupply()`, ETH+stETH reserves (via `_ethReservesView`)
**State Writes:** None

**Callers:** External (UI)
**Callees:** `ethShare.totalSupply()`, `_ethReservesView()`

**ETH Flow:** None (view only)
**Invariants:** Uses ceiling division for burnAmount. Then re-computes claimValue using floor division to show the actual output. ethOut/stEthOut split follows ETH-preferred logic.
**NatSpec Accuracy:** Accurate. Notes "ceiling division" and "estimated."
**Gas Flags:** None
**Verdict:** CORRECT -- Two-step calculation is correct: ceiling for input, floor for output preview.

---

### `previewCoin(uint256 amount)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function previewCoin(uint256 amount) external view returns (uint256 coinOut)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `amount` (uint256): DGVB shares to preview burning |
| **Returns** | `coinOut` (uint256): BURNIE that would be received |

**State Reads:** `coinShare.totalSupply()`, coin reserves (via `_coinReservesView`)
**State Writes:** None

**Callers:** External (UI)
**Callees:** `coinShare.totalSupply()`, `_coinReservesView()`

**ETH Flow:** None (view only)
**Invariants:** Floor division (rounds against user). Reverts if amount == 0 or amount > supply.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `previewEth(uint256 amount)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function previewEth(uint256 amount) external view returns (uint256 ethOut, uint256 stEthOut)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `amount` (uint256): DGVE shares to preview burning |
| **Returns** | `ethOut` (uint256): ETH that would be sent; `stEthOut` (uint256): stETH that would be sent |

**State Reads:** `ethShare.totalSupply()`, ETH+stETH reserves (via `_ethReservesView`)
**State Writes:** None

**Callers:** External (UI)
**Callees:** `ethShare.totalSupply()`, `_ethReservesView()`

**ETH Flow:** None (view only)
**Invariants:** Floor division. ETH-preferred output split. Reverts if amount == 0 or amount > supply.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

## I. DegenerusVault -- Internal Helpers

---

### `_combinedValue(uint256 extraValue)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _combinedValue(uint256 extraValue) private view returns (uint256 totalValue)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `extraValue` (uint256): additional ETH from vault balance |
| **Returns** | `totalValue` (uint256): combined msg.value + extraValue |

**State Reads:** `address(this).balance`
**State Writes:** None

**Callers:** `gamePurchase`, `gameDegeneretteBetEth`
**Callees:** None

**ETH Flow:** None (calculation only). Note: msg.value is already included in address(this).balance at this point.
**Invariants:** If extraValue == 0, returns msg.value (no vault balance used). Otherwise, checks msg.value + extraValue <= address(this).balance. Since msg.value is already in the balance, this is correct -- it ensures the vault has enough native ETH to cover the extra amount.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_syncEthReserves()` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _syncEthReserves() private view returns (uint256 ethBal, uint256 stBal, uint256 combined)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `ethBal` (uint256): ETH balance; `stBal` (uint256): stETH balance; `combined` (uint256): sum |

**State Reads:** `address(this).balance`, `steth.balanceOf(address(this))`
**State Writes:** None

**Callers:** `_burnEthFor`
**Callees:** `_stethBalance()`

**ETH Flow:** None (view only)
**Invariants:** Uses unchecked addition -- safe because ETH + stETH < 2^256.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_syncCoinReserves()` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _syncCoinReserves() private returns (uint256 synced)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | `synced` (uint256): current vault mint allowance |

**State Reads:** `coinToken.vaultMintAllowance()`
**State Writes:** `coinTracked` (set to current allowance)

**Callers:** `deposit`, `_burnCoinFor`
**Callees:** `coinToken.vaultMintAllowance()`

**ETH Flow:** None
**Invariants:** Syncs local tracking with the actual on-chain allowance from the coin contract. This handles cases where the allowance changed due to external minting (vaultMintTo calls from other sources).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_coinReservesView()` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _coinReservesView() private view returns (uint256 mainReserve)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `mainReserve` (uint256): total BURNIE reserve (allowance + balance + claimable) |

**State Reads:** `coinToken.vaultMintAllowance()`, `coinToken.balanceOf(address(this))`, `coinPlayer.previewClaimCoinflips(address(this))`
**State Writes:** None

**Callers:** `previewBurnForCoinOut`, `previewCoin`
**Callees:** `coinToken.vaultMintAllowance()`, `coinToken.balanceOf(address(this))`, `coinPlayer.previewClaimCoinflips(address(this))`

**ETH Flow:** None
**Invariants:** mainReserve = allowance + vaultBal + claimable. Uses unchecked addition (safe for token amounts). Only adds vaultBal+claimable if at least one is non-zero (gas opt).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_ethReservesView()` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _ethReservesView() private view returns (uint256 mainReserve, uint256 ethBal)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `mainReserve` (uint256): total ETH+stETH+claimable reserve; `ethBal` (uint256): current ETH balance |

**State Reads:** `address(this).balance`, `steth.balanceOf(address(this))`, `gamePlayer.claimableWinningsOf(address(this))`
**State Writes:** None

**Callers:** `previewBurnForEthOut`, `previewEth`
**Callees:** `_stethBalance()`, `gamePlayer.claimableWinningsOf(address(this))`

**ETH Flow:** None (view only)
**Invariants:** claimable adjusted: if <= 1, treated as 0; else claimable -= 1. This matches the game's sentinel value pattern (1 wei = "has claimed before but nothing pending"). All unchecked additions safe.
**NatSpec Accuracy:** Accurate. Notes "stETH rebase yield accrues to DGVE only."
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_stethBalance()` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _stethBalance() private view returns (uint256)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `uint256`: stETH balance of vault |

**State Reads:** `steth.balanceOf(address(this))`
**State Writes:** None

**Callers:** `_syncEthReserves`, `_burnEthFor`, `_ethReservesView` (indirectly)
**Callees:** `steth.balanceOf(address(this))`

**ETH Flow:** None
**Invariants:** Simple wrapper for stETH balance query.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_payEth(address to, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _payEth(address to, uint256 amount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): ETH to send |
| **Returns** | None |

**State Reads:** None
**State Writes:** None (ETH balance decreases implicitly)

**Callers:** `_burnEthFor`
**Callees:** `to.call{value: amount}("")`

**ETH Flow:** vault -> `to` via low-level call
**Invariants:** Reverts on failure (TransferFailed). Uses low-level call (supports contracts with custom receive).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** No gas limit on call -- intentional to support contract recipients.
**Verdict:** CORRECT

---

### `_paySteth(address to, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _paySteth(address to, uint256 amount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): stETH to transfer |
| **Returns** | None |

**State Reads:** None
**State Writes:** None (stETH balance decreases)

**Callers:** `_burnEthFor`
**Callees:** `steth.transfer(to, amount)`

**ETH Flow:** stETH from vault -> `to`
**Invariants:** Reverts if transfer returns false.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** Lido stETH transfers may have 1-2 wei rounding. This is a known Lido behavior and does not affect vault correctness (rounding is negligible and vault uses floor division).
**Verdict:** CORRECT

---

### `_pullSteth(address from, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _pullSteth(address from, uint256 amount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): source; `amount` (uint256): stETH to pull |
| **Returns** | None |

**State Reads:** None
**State Writes:** None (stETH balance increases)

**Callers:** `deposit`
**Callees:** `steth.transferFrom(from, address(this), amount)`

**ETH Flow:** stETH from `from` (GAME) -> vault
**Invariants:** No-op if amount == 0. Requires prior stETH approval from `from`. Reverts if transfer fails.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---
