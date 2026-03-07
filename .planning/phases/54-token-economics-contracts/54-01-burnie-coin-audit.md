# BurnieCoin.sol -- Function-Level Audit

**Contract:** BurnieCoin
**File:** contracts/BurnieCoin.sol
**Lines:** 1023
**Solidity:** 0.8.34
**Inherits:** (no explicit inheritance -- implements IDegenerusCoin implicitly)
**Audit date:** 2026-03-07

## Summary

ERC-20 token ("Burnies", BURNIE, 18 decimals) with uint128-packed supply state (`totalSupply` + `vaultAllowance` in a single storage slot). Features include: a coinflip credit/claim system delegated to an external BurnieCoinflip contract, cross-contract mint/burn access for Game/Coinflip/Vault/Admin, quest notification hooks routing through an external IDegenerusQuests module (rollDailyQuest, notifyQuestMint, notifyQuestLootBox, notifyQuestDegenerette, affiliateQuestReward), decimator burn with activity-based multiplier and bucket adjustment for jackpot weighting, vault escrow with 2M BURNIE virtual reserve, and automatic coinflip claim on transfer shortfall.

**Key storage layout:**
- Slot 0: `Supply { uint128 totalSupply; uint128 vaultAllowance }` -- packed in one 32-byte slot
- Slot 1: `mapping(address => uint256) balanceOf`
- Slot 2: `mapping(address => mapping(address => uint256)) allowance`

**Constants:**
- `DECIMATOR_MIN` = 1,000 BURNIE (dust threshold)
- `DECIMATOR_BUCKET_BASE` = 12
- `DECIMATOR_MIN_BUCKET_NORMAL` = 5, `DECIMATOR_MIN_BUCKET_100` = 2
- `DECIMATOR_ACTIVITY_CAP_BPS` = 23,500 (235%)
- `DECIMATOR_BOON_CAP` = 50,000 BURNIE
- `BPS_DENOMINATOR` = 10,000
- `QUEST_TYPE_MINT_ETH` = 1
- Initial vault allowance = 2,000,000 BURNIE

---

## Function Audit

### View/Interface Functions

---

### `claimableCoin()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function claimableCoin() external view returns (uint256)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | none |
| **Returns** | `uint256`: total BURNIE claimable from past winning coinflips for msg.sender |

**State Reads:** none (delegates entirely)
**State Writes:** none

**Callers:** External (UI/frontend)
**Callees:** `IBurnieCoinflip(coinflipContract).previewClaimCoinflips(msg.sender)`

**ETH Flow:** No
**Invariants:** Pure proxy -- always returns same result as calling coinflipContract.previewClaimCoinflips directly
**NatSpec Accuracy:** Accurate. Says "flips only" which is correct since it proxies to BurnieCoinflip.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `balanceOfWithClaimable(address player)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function balanceOfWithClaimable(address player) external view returns (uint256 spendable)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): address to query |
| **Returns** | `uint256 spendable`: total spendable amount right now |

**State Reads:** `balanceOf[player]`, `_supply.vaultAllowance`, `degenerusGame.rngLocked()`
**State Writes:** none

**Callers:** External (UI/frontend, contracts querying spendable balance)
**Callees:** `degenerusGame.rngLocked()`, `IBurnieCoinflip(coinflipContract).previewClaimCoinflips(player)`

**ETH Flow:** No
**Invariants:** If rngLocked, only wallet balance (+ vault allowance if player==VAULT) returned. If unlocked, also includes claimable coinflip winnings. The `unchecked` block for claimable addition is safe because previewClaimCoinflips returns a value bounded by prior burns, so spendable + claimable cannot overflow uint256.
**NatSpec Accuracy:** Accurate. Describes VAULT special handling and RNG lock behavior.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `previewClaimCoinflips(address player)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function previewClaimCoinflips(address player) external view returns (uint256 mintable)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): player to preview for |
| **Returns** | `uint256 mintable`: amount of BURNIE that would be minted on claim |

**State Reads:** none (delegates entirely)
**State Writes:** none

**Callers:** External (UI/frontend)
**Callees:** `IBurnieCoinflip(coinflipContract).previewClaimCoinflips(player)`

**ETH Flow:** No
**Invariants:** Pure proxy
**NatSpec Accuracy:** Accurate
**Gas Flags:** None
**Verdict:** CORRECT

---

### `coinflipAutoRebuyInfo(address player)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function coinflipAutoRebuyInfo(address player) external view returns (bool enabled, uint256 stopAmount, uint256 carry)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): player's address |
| **Returns** | `bool enabled`, `uint256 stopAmount`, `uint256 carry` |

**State Reads:** none (delegates entirely)
**State Writes:** none

**Callers:** External (UI/frontend)
**Callees:** `IBurnieCoinflip(coinflipContract).coinflipAutoRebuyInfo(player)` -- discards 4th return value `startDay`

**ETH Flow:** No
**Invariants:** Pure proxy, drops startDay
**NatSpec Accuracy:** Accurate. Describes each return field.
**Gas Flags:** The 4th return `startDay` is fetched from BurnieCoinflip but discarded. Minimal gas impact since it is already in the same SLOAD.
**Verdict:** CORRECT

---

### `totalSupply()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function totalSupply() external view returns (uint256)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | none |
| **Returns** | `uint256`: circulating supply (excludes vault allowance) |

**State Reads:** `_supply.totalSupply`
**State Writes:** none

**Callers:** External (ERC-20 standard query)
**Callees:** none

**ETH Flow:** No
**Invariants:** totalSupply == sum of all balanceOf entries
**NatSpec Accuracy:** Accurate. Notes exclusion of vault allowance.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `supplyIncUncirculated()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function supplyIncUncirculated() external view returns (uint256)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | none |
| **Returns** | `uint256`: totalSupply + vaultAllowance |

**State Reads:** `_supply.totalSupply`, `_supply.vaultAllowance`
**State Writes:** none

**Callers:** External (dashboards, vault share calculations)
**Callees:** none

**ETH Flow:** No
**Invariants:** Always equals totalSupply + vaultAllowance. Addition cannot overflow because both are uint128 values cast to uint256 before addition.
**NatSpec Accuracy:** Accurate
**Gas Flags:** None
**Verdict:** CORRECT

---

### `vaultMintAllowance()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function vaultMintAllowance() external view returns (uint256)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | none |
| **Returns** | `uint256`: current vault mint allowance |

**State Reads:** `_supply.vaultAllowance`
**State Writes:** none

**Callers:** External (vault share math, dashboards, deploy pipeline checks)
**Callees:** none

**ETH Flow:** No
**Invariants:** Returns current virtual reserve
**NatSpec Accuracy:** Accurate
**Gas Flags:** None
**Verdict:** CORRECT

---

### `coinflipAmount(address player)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function coinflipAmount(address player) external view returns (uint256)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): player to query |
| **Returns** | `uint256`: stake amount for current target day |

**State Reads:** none (delegates entirely)
**State Writes:** none

**Callers:** External (UI/frontend)
**Callees:** `IBurnieCoinflip(coinflipContract).coinflipAmount(player)`

**ETH Flow:** No
**Invariants:** Pure proxy
**NatSpec Accuracy:** Accurate
**Gas Flags:** None
**Verdict:** CORRECT

---

### ERC-20 Core

---

### `approve(address spender, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function approve(address spender, uint256 amount) external returns (bool)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `spender` (address): authorized address; `amount` (uint256): max spend |
| **Returns** | `bool`: always true |

**State Reads:** `allowance[msg.sender][spender]`
**State Writes:** `allowance[msg.sender][spender]` (only if current != amount, gas optimization)

**Callers:** Any user/contract
**Callees:** none

**ETH Flow:** No
**Invariants:** Sets allowance to exact amount. Emits Approval regardless of whether storage write occurs (ERC-20 compliance).
**NatSpec Accuracy:** Accurate. Notes type(uint256).max for infinite approval.
**Gas Flags:** The "only write if current != amount" optimization saves ~5000 gas on no-op re-approvals. Well designed.
**Verdict:** CORRECT

---

### `transfer(address to, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function transfer(address to, uint256 amount) external returns (bool)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): transfer amount |
| **Returns** | `bool`: always true |

**State Reads:** `balanceOf[msg.sender]`, `balanceOf[to]`, `degenerusGame.rngLocked()` (via _claimCoinflipShortfall)
**State Writes:** `balanceOf[msg.sender]`, `balanceOf[to]`, possibly `_supply.totalSupply`/`_supply.vaultAllowance` (if to==VAULT)

**Callers:** Any user/contract
**Callees:** `_claimCoinflipShortfall(msg.sender, amount)`, `_transfer(msg.sender, to, amount)`

**ETH Flow:** No
**Invariants:** Calls _claimCoinflipShortfall first to auto-claim coinflip winnings if balance insufficient -- ensures smooth UX. Then standard _transfer. uint128 truncation safety: _transfer uses _toUint128 only for vault redirect path, never for normal transfers which stay in uint256.
**NatSpec Accuracy:** Accurate
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
| **Returns** | `bool`: always true |

**State Reads:** `allowance[from][msg.sender]`, `balanceOf[from]`, `balanceOf[to]`
**State Writes:** `allowance[from][msg.sender]` (if not GAME and not infinite), `balanceOf[from]`, `balanceOf[to]`

**Callers:** Any user/contract, DegenerusGame (with bypass)
**Callees:** `_claimCoinflipShortfall(from, amount)`, `_transfer(from, to, amount)`

**ETH Flow:** No
**Invariants:**
- Game contract bypasses allowance check entirely (trusted contract pattern)
- Infinite approval (type(uint256).max) skips allowance update
- Zero-amount transfers skip allowance update (optimization)
- Solidity 0.8+ underflow check on `allowed - amount` prevents spending more than allowed
- Emits Approval event when allowance updated (ERC-20 compliant)
**NatSpec Accuracy:** Accurate. Documents game bypass.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_transfer(address from, address to, uint256 amount)` [internal]

| Field | Value |
|-------|-------|
| **Signature** | `function _transfer(address from, address to, uint256 amount) internal` |
| **Visibility** | internal |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): source; `to` (address): destination; `amount` (uint256): transfer amount |
| **Returns** | none |

**State Reads:** `balanceOf[from]`, `balanceOf[to]`
**State Writes:** `balanceOf[from]`, `balanceOf[to]`, and if `to == VAULT`: `_supply.totalSupply`, `_supply.vaultAllowance`

**Callers:** `transfer()`, `transferFrom()`
**Callees:** `_toUint128(amount)` (VAULT path only)

**ETH Flow:** No
**Invariants:**
- Zero address check on both from and to
- VAULT redirect: transfers TO vault are treated as burns (totalSupply decreases) + vault allowance increases. Emits Transfer(from, address(0)) + VaultEscrowRecorded. This preserves the invariant: totalSupply + vaultAllowance = supplyIncUncirculated.
- The unchecked block for VAULT path is safe: totalSupply was increased when the token was minted, so subtracting amount128 (which came from that balance) cannot underflow. vaultAllowance + amount128 is safe because both are uint128, and their sum is checked by _toUint128 on the amount; the total can only grow up to total supply ever minted.
- Normal path: overflow on balanceOf[to] is theoretically possible but requires ~2^256 total supply (impossible).
**NatSpec Accuracy:** Accurate. Notes underflow revert and VAULT redirect.
**Gas Flags:** The VAULT redirect uses unchecked for gas savings; correctness verified.
**Verdict:** CORRECT -- VAULT redirect preserves supply invariant

---

### `_toUint128(uint256 value)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _toUint128(uint256 value) private pure returns (uint128)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `value` (uint256): value to truncate |
| **Returns** | `uint128`: truncated value |

**State Reads:** none
**State Writes:** none

**Callers:** `_transfer()` (VAULT path), `_mint()`, `_burn()`, `vaultEscrow()`, `vaultMintTo()`
**Callees:** none

**ETH Flow:** No
**Invariants:** Reverts with `SupplyOverflow()` if value > type(uint128).max. This is the uint128 truncation safety gate. Max uint128 = ~340 undecillion tokens (3.4e38), far beyond any realistic supply.
**NatSpec Accuracy:** No NatSpec. Acceptable for a trivial private helper.
**Gas Flags:** None
**Verdict:** CORRECT -- prevents silent truncation

---

### Mint/Burn Internals

---

### `_mint(address to, uint256 amount)` [internal]

| Field | Value |
|-------|-------|
| **Signature** | `function _mint(address to, uint256 amount) internal` |
| **Visibility** | internal |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): amount to mint |
| **Returns** | none |

**State Reads:** `_supply.vaultAllowance` (VAULT path), `_supply.totalSupply` (normal path), `balanceOf[to]`
**State Writes:** `_supply.vaultAllowance` (VAULT path) OR `_supply.totalSupply` + `balanceOf[to]` (normal path)

**Callers:** `mintForCoinflip()`, `mintForGame()`, `creditCoin()`
**Callees:** `_toUint128(amount)`

**ETH Flow:** No
**Invariants:**
- Zero address revert
- VAULT path: minting TO vault increases vaultAllowance (unchecked -- bounded by total possible token inflows). Emits VaultEscrowRecorded, NOT Transfer. This is intentional since vault allowance is virtual.
- Normal path: totalSupply += amount128 (checked, will revert on uint128 overflow), balanceOf[to] += amount (uint256, cannot overflow in practice)
- Emits Transfer(address(0), to, amount) for normal path (ERC-20 standard)
**NatSpec Accuracy:** Accurate
**Gas Flags:** VAULT path uses unchecked for vaultAllowance increment. Safe because total mint inflows are bounded by game economics.
**Verdict:** CORRECT

---

### `_burn(address from, uint256 amount)` [internal]

| Field | Value |
|-------|-------|
| **Signature** | `function _burn(address from, uint256 amount) internal` |
| **Visibility** | internal |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): address to burn from; `amount` (uint256): amount to burn |
| **Returns** | none |

**State Reads:** `_supply.vaultAllowance` (VAULT path), `balanceOf[from]`, `_supply.totalSupply`
**State Writes:** `_supply.vaultAllowance` (VAULT path) OR `balanceOf[from]` + `_supply.totalSupply` (normal path)

**Callers:** `burnForCoinflip()`, `burnCoin()`, `decimatorBurn()`
**Callees:** `_toUint128(amount)`

**ETH Flow:** No
**Invariants:**
- Zero address revert
- VAULT path: explicit check `amount128 > allowanceVault` reverts with Insufficient. Reduces vaultAllowance (unchecked, safe after the check). Emits VaultAllowanceSpent, NOT Transfer(from, address(0)). This is intentional since the "burned" tokens were virtual.
- Normal path: balanceOf[from] -= amount (Solidity 0.8+ underflow revert), totalSupply -= amount128 (checked uint128 subtraction)
- Preserves invariant: totalSupply + vaultAllowance = supplyIncUncirculated
**NatSpec Accuracy:** Accurate. Notes CEI pattern usage.
**Gas Flags:** None
**Verdict:** CORRECT

---

### Cross-Contract Mint/Burn Externals

---

### `burnForCoinflip(address from, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function burnForCoinflip(address from, uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): player to burn from; `amount` (uint256): amount to burn |
| **Returns** | none |

**State Reads:** `balanceOf[from]`, `_supply.totalSupply`
**State Writes:** `balanceOf[from]`, `_supply.totalSupply`

**Callers:** BurnieCoinflip contract (external)
**Callees:** `_burn(from, amount)`

**ETH Flow:** No
**Invariants:** Only coinflipContract can call. Reuses `OnlyGame()` error for gas efficiency rather than defining a separate `OnlyCoinflip` error.
**NatSpec Accuracy:** Accurate
**Gas Flags:** Reusing OnlyGame error -- informational only, saves contract size
**Verdict:** CORRECT

---

### `mintForCoinflip(address to, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function mintForCoinflip(address to, uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): amount to mint |
| **Returns** | none |

**State Reads:** `_supply.totalSupply`, `balanceOf[to]`
**State Writes:** `_supply.totalSupply`, `balanceOf[to]`

**Callers:** BurnieCoinflip contract (external)
**Callees:** `_mint(to, amount)`

**ETH Flow:** No
**Invariants:** Only coinflipContract can call. No zero-amount check (unlike mintForGame), but _mint handles zero-address check. A zero-amount mint is a no-op with a Transfer event -- acceptable.
**NatSpec Accuracy:** Accurate
**Gas Flags:** None
**Verdict:** CORRECT

---

### `mintForGame(address to, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function mintForGame(address to, uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): amount to mint |
| **Returns** | none |

**State Reads:** `_supply.totalSupply`, `balanceOf[to]`
**State Writes:** `_supply.totalSupply`, `balanceOf[to]`

**Callers:** DegenerusGame contract (external)
**Callees:** `_mint(to, amount)`

**ETH Flow:** No
**Invariants:** Only GAME can call. Early return on amount == 0 (optimization). Used for Degenerette payouts and other game rewards.
**NatSpec Accuracy:** Accurate. Says "e.g., Degenerette wins."
**Gas Flags:** None
**Verdict:** CORRECT

---

### `vaultEscrow(uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function vaultEscrow(uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `amount` (uint256): amount to add to vault allowance |
| **Returns** | none |

**State Reads:** `_supply.vaultAllowance`
**State Writes:** `_supply.vaultAllowance`

**Callers:** DegenerusGame or DegenerusVault contracts (external)
**Callees:** `_toUint128(amount)`

**ETH Flow:** No
**Invariants:**
- Access control: only GAME or VAULT can call. Reuses `OnlyVault()` error (the error name is slightly misleading since GAME can also call, but acceptable for gas savings).
- Increases vaultAllowance with unchecked addition. Safe because _toUint128 validates the amount fits uint128, and the maximum practical accumulation is bounded by game economics (initial 2M + game rewards).
- Does NOT mint tokens -- only increases virtual allowance
- Emits VaultEscrowRecorded
**NatSpec Accuracy:** Accurate. Says "Increase the vault's mint allowance without transferring tokens."
**Gas Flags:** None
**Verdict:** CORRECT

---

### `vaultMintTo(address to, uint256 amount)` [external onlyVault]

| Field | Value |
|-------|-------|
| **Signature** | `function vaultMintTo(address to, uint256 amount) external onlyVault` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): amount to mint from allowance |
| **Returns** | none |

**State Reads:** `_supply.vaultAllowance`, `_supply.totalSupply`, `balanceOf[to]`
**State Writes:** `_supply.vaultAllowance`, `_supply.totalSupply`, `balanceOf[to]`

**Callers:** DegenerusVault contract only (external)
**Callees:** `_toUint128(amount)`

**ETH Flow:** No
**Invariants:**
- Zero address revert
- Explicit check: amount128 > allowanceVault reverts with Insufficient
- Decreases vaultAllowance, increases totalSupply (unchecked block). The unchecked is safe: allowance was checked above, and totalSupply + amount128 cannot overflow uint128 because the decrease in vaultAllowance balances the increase in totalSupply (total supplyIncUncirculated stays constant in this function... no, totalSupply goes up, vaultAllowance goes down -- net supplyIncUncirculated unchanged -- CORRECT).
- Mints real tokens to recipient (balanceOf[to] += amount)
- Emits VaultAllowanceSpent(address(this), amount) and Transfer(address(0), to, amount)
**NatSpec Accuracy:** Accurate
**Gas Flags:** None. The unchecked block with prior bounds check is correct and gas-efficient.
**Verdict:** CORRECT -- preserves supplyIncUncirculated invariant (totalSupply up, vaultAllowance down by same amount)

---

### Coinflip Credit System

---

### `creditCoin(address player, uint256 amount)` [external onlyFlipCreditors]

| Field | Value |
|-------|-------|
| **Signature** | `function creditCoin(address player, uint256 amount) external onlyFlipCreditors` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): recipient; `amount` (uint256): amount to credit |
| **Returns** | none |

**State Reads:** `_supply.totalSupply`, `balanceOf[player]`
**State Writes:** `_supply.totalSupply`, `balanceOf[player]`

**Callers:** DegenerusGame or DegenerusAffiliate (via onlyFlipCreditors)
**Callees:** `_mint(player, amount)`

**ETH Flow:** No
**Invariants:** Early return on zero address or zero amount. Mints NEW tokens (increases totalSupply) -- note the naming "creditCoin" might suggest transferring existing tokens, but it actually mints. This is intentional for game reward distribution.
**NatSpec Accuracy:** NatSpec says "Credits coin to a player's balance without minting new tokens" (from the interface). This is INACCURATE -- the implementation calls _mint which DOES mint new tokens and increase totalSupply. However, the BurnieCoin.sol function-level NatSpec says "Credit BURNIE directly to a player's wallet balance" which is accurate but ambiguous.
**Gas Flags:** None
**Verdict:** CONCERN (informational) -- Interface NatSpec in IDegenerusCoin says "without minting new tokens" but implementation calls `_mint()`. The contract behavior is correct for game economics (reward minting is intentional), but the interface comment is misleading.

---

### `creditFlip(address player, uint256 amount)` [external onlyFlipCreditors]

| Field | Value |
|-------|-------|
| **Signature** | `function creditFlip(address player, uint256 amount) external onlyFlipCreditors` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): recipient; `amount` (uint256): flip credit amount |
| **Returns** | none |

**State Reads:** none (delegates to coinflipContract)
**State Writes:** none locally (coinflipContract writes internally)

**Callers:** DegenerusGame or DegenerusAffiliate (via onlyFlipCreditors)
**Callees:** `IBurnieCoinflip(coinflipContract).creditFlip(player, amount)`

**ETH Flow:** No
**Invariants:** Pure proxy to coinflipContract. No zero checks here -- delegated to BurnieCoinflip.
**NatSpec Accuracy:** Accurate
**Gas Flags:** None
**Verdict:** CORRECT

---

### `creditFlipBatch(address[3] calldata players, uint256[3] calldata amounts)` [external onlyFlipCreditors]

| Field | Value |
|-------|-------|
| **Signature** | `function creditFlipBatch(address[3] calldata players, uint256[3] calldata amounts) external onlyFlipCreditors` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `players` (address[3]): recipients; `amounts` (uint256[3]): amounts per player |
| **Returns** | none |

**State Reads:** none (delegates to coinflipContract)
**State Writes:** none locally (coinflipContract writes internally)

**Callers:** DegenerusGame or DegenerusAffiliate (via onlyFlipCreditors)
**Callees:** `IBurnieCoinflip(coinflipContract).creditFlipBatch(players, amounts)`

**ETH Flow:** No
**Invariants:** Fixed-size array (3) for gas optimization. Unused slots should be address(0). Pure proxy.
**NatSpec Accuracy:** Accurate. Notes unused slots should be address(0).
**Gas Flags:** None
**Verdict:** CORRECT

---

### `creditLinkReward(address player, uint256 amount)` [external onlyAdmin]

| Field | Value |
|-------|-------|
| **Signature** | `function creditLinkReward(address player, uint256 amount) external onlyAdmin` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): reward recipient; `amount` (uint256): flip credit amount |
| **Returns** | none |

**State Reads:** none locally
**State Writes:** none locally (coinflipContract writes internally)

**Callers:** DegenerusAdmin contract (via onlyAdmin)
**Callees:** `IBurnieCoinflip(coinflipContract).creditFlip(player, amount)`

**ETH Flow:** No
**Invariants:** Early return on zero address or zero amount. Credits flip stake (not wallet balance) as LINK donation reward. Emits LinkCreditRecorded.
**NatSpec Accuracy:** Accurate. Describes LINK donation reward flow.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_claimCoinflipShortfall(address player, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _claimCoinflipShortfall(address player, uint256 amount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player to auto-claim for; `amount` (uint256): required amount |
| **Returns** | none |

**State Reads:** `degenerusGame.rngLocked()`, `balanceOf[player]`
**State Writes:** `balanceOf[player]` (via coinflipContract.claimCoinflipsFromBurnie which calls mintForCoinflip)

**Callers:** `transfer()`, `transferFrom()`
**Callees:** `degenerusGame.rngLocked()`, `IBurnieCoinflip(coinflipContract).claimCoinflipsFromBurnie(player, amount - balance)`

**ETH Flow:** No
**Invariants:**
- Early returns: zero amount, rngLocked (cannot claim during VRF), sufficient balance
- Claims exactly `amount - balance` from coinflip winnings to cover the shortfall
- unchecked subtraction safe: guarded by `balance >= amount` check (only enters if balance < amount)
- The coinflipContract.claimCoinflipsFromBurnie call will mint tokens to the player, increasing their balance to cover the pending transfer
**NatSpec Accuracy:** No NatSpec. Acceptable for private helper.
**Gas Flags:** None
**Verdict:** CORRECT -- elegant auto-claim mechanism

---

### `_consumeCoinflipShortfall(address player, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _consumeCoinflipShortfall(address player, uint256 amount) private returns (uint256 consumed)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player; `amount` (uint256): required amount |
| **Returns** | `uint256 consumed`: amount consumed from coinflip balance |

**State Reads:** `degenerusGame.rngLocked()`, `balanceOf[player]`
**State Writes:** none locally (coinflipContract writes internally -- reduces coinflip balance without minting)

**Callers:** `burnCoin()`, `decimatorBurn()`
**Callees:** `degenerusGame.rngLocked()`, `IBurnieCoinflip(coinflipContract).consumeCoinflipsForBurn(player, amount - balance)`

**ETH Flow:** No
**Invariants:**
- Same early-return pattern as _claimCoinflipShortfall
- Returns the amount consumed (offset from coinflip balance), allowing callers to burn only `amount - consumed` from wallet balance
- Key difference from _claimCoinflipShortfall: consume does NOT mint tokens -- it cancels coinflip credits, effectively burning them. This is correct for burnCoin/decimatorBurn where the intent is destruction, not transfer.
- unchecked subtraction safe: same guard as _claimCoinflipShortfall
**NatSpec Accuracy:** No NatSpec. Acceptable for private helper.
**Gas Flags:** None
**Verdict:** CORRECT -- consume-without-mint pattern for burns

---

### Quest Notification Hooks

---

### `affiliateQuestReward(address player, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function affiliateQuestReward(address player, uint256 amount) external returns (uint256 questReward)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player who triggered affiliate action; `amount` (uint256): base amount |
| **Returns** | `uint256 questReward`: bonus reward earned |

**State Reads:** none locally
**State Writes:** none locally

**Callers:** DegenerusAffiliate contract (explicit check: msg.sender != AFFILIATE)
**Callees:** `questModule.handleAffiliate(player, amount)`, `_questApplyReward(player, reward, questType, streak, completed)`

**ETH Flow:** No
**Invariants:**
- Only AFFILIATE can call (OnlyAffiliate error)
- Early return 0 on zero address or zero amount
- Quest reward returned but NOT credited as flip stake here -- the affiliate contract handles reward distribution. This differs from notifyQuestMint/notifyQuestLootBox/notifyQuestDegenerette which credit flip stakes directly.
**NatSpec Accuracy:** Accurate
**Gas Flags:** None
**Verdict:** CORRECT

---

### `rollDailyQuest(uint48 day, uint256 entropy)` [external onlyDegenerusGameContract]

| Field | Value |
|-------|-------|
| **Signature** | `function rollDailyQuest(uint48 day, uint256 entropy) external onlyDegenerusGameContract` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `day` (uint48): day index; `entropy` (uint256): VRF randomness |
| **Returns** | none |

**State Reads:** none locally
**State Writes:** none locally (questModule writes internally)

**Callers:** DegenerusGame contract (via onlyDegenerusGameContract)
**Callees:** `questModule.rollDailyQuest(day, entropy)`

**ETH Flow:** No
**Invariants:**
- Only GAME can call
- If rolled is true, emits DailyQuestRolled for each of 2 quest types
- If rolled is false (already rolled for this day), no events emitted
- Loop uses unchecked increment -- safe since i < 2 is bounded
- `highDifficulty` is documented as "Always false (difficulty removed)" in the event, meaning the quest module no longer uses difficulty levels
**NatSpec Accuracy:** Accurate
**Gas Flags:** None
**Verdict:** CORRECT

---

### `notifyQuestMint(address player, uint32 quantity, bool paidWithEth)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function notifyQuestMint(address player, uint32 quantity, bool paidWithEth) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): minting player; `quantity` (uint32): mint units; `paidWithEth` (bool): payment method |
| **Returns** | none |

**State Reads:** none locally
**State Writes:** none locally

**Callers:** DegenerusGame contract (explicit msg.sender check)
**Callees:** `questModule.handleMint(player, quantity, paidWithEth)`, `_questApplyReward(...)`, `degenerusGame.recordMintQuestStreak(player)` (conditional), `IBurnieCoinflip(coinflipContract).creditFlip(player, questReward)` (conditional)

**ETH Flow:** No
**Invariants:**
- Only GAME can call
- Quest reward is credited as flip stake via coinflipContract.creditFlip
- Special behavior: if quest completed AND paidWithEth AND questType == QUEST_TYPE_MINT_ETH (1), also calls `degenerusGame.recordMintQuestStreak(player)` to update the mint streak counter
- Flip credit only occurs if questReward != 0
**NatSpec Accuracy:** Accurate. Notes slot-0 streak update on MINT_ETH completion.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `notifyQuestLootBox(address player, uint256 amountWei)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function notifyQuestLootBox(address player, uint256 amountWei) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player; `amountWei` (uint256): ETH spent |
| **Returns** | none |

**State Reads:** none locally
**State Writes:** none locally

**Callers:** DegenerusGame contract (explicit msg.sender check)
**Callees:** `questModule.handleLootBox(player, amountWei)`, `_questApplyReward(...)`, `IBurnieCoinflip(coinflipContract).creditFlip(player, questReward)` (conditional)

**ETH Flow:** No
**Invariants:**
- Only GAME can call
- Quest reward credited as flip stake if questReward != 0
- NatSpec says "Access: game or lootbox contract" but the code only checks for GAME. This is because lootbox operations are delegatecalled through the game contract, so msg.sender is always GAME.
**NatSpec Accuracy:** CONCERN (informational) -- NatSpec says "game or lootbox contract" but code only checks GAME. Functionally correct because lootbox is a delegatecall module, but the comment is misleading about access control.
**Gas Flags:** None
**Verdict:** CORRECT (behavior correct, NatSpec slightly misleading)

---

### `notifyQuestDegenerette(address player, uint256 amount, bool paidWithEth)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function notifyQuestDegenerette(address player, uint256 amount, bool paidWithEth) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player; `amount` (uint256): bet amount; `paidWithEth` (bool): payment type |
| **Returns** | none |

**State Reads:** none locally
**State Writes:** none locally

**Callers:** DegenerusGame contract (explicit msg.sender check)
**Callees:** `questModule.handleDegenerette(player, amount, paidWithEth)`, `_questApplyReward(...)`, `IBurnieCoinflip(coinflipContract).creditFlip(player, questReward)` (conditional)

**ETH Flow:** No
**Invariants:**
- Only GAME can call
- Same pattern as notifyQuestLootBox: route to quest module, apply reward, credit flip
**NatSpec Accuracy:** Accurate
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_questApplyReward(address player, uint256 reward, uint8 questType, uint32 streak, bool completed)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _questApplyReward(address player, uint256 reward, uint8 questType, uint32 streak, bool completed) private returns (uint256)` |
| **Visibility** | private |
| **Mutability** | state-changing (emits event) |
| **Parameters** | `player` (address): player; `reward` (uint256): raw reward; `questType` (uint8): quest type; `streak` (uint32): streak count; `completed` (bool): whether completed |
| **Returns** | `uint256`: reward amount (0 if not completed) |

**State Reads:** none
**State Writes:** none (only emits event)

**Callers:** `affiliateQuestReward()`, `notifyQuestMint()`, `notifyQuestLootBox()`, `notifyQuestDegenerette()`, `decimatorBurn()`
**Callees:** none

**ETH Flow:** No
**Invariants:** Pure event emitter. Returns reward if completed, 0 otherwise. Emits QuestCompleted for off-chain indexers.
**NatSpec Accuracy:** Accurate
**Gas Flags:** None
**Verdict:** CORRECT

---

### Burn Mechanics

---

### `burnCoin(address target, uint256 amount)` [external onlyTrustedContracts]

| Field | Value |
|-------|-------|
| **Signature** | `function burnCoin(address target, uint256 amount) external onlyTrustedContracts` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `target` (address): address to burn from; `amount` (uint256): amount to burn |
| **Returns** | none |

**State Reads:** `degenerusGame.rngLocked()`, `balanceOf[target]`, `_supply.totalSupply`
**State Writes:** `balanceOf[target]`, `_supply.totalSupply`

**Callers:** DegenerusGame or DegenerusAffiliate (via onlyTrustedContracts)
**Callees:** `_consumeCoinflipShortfall(target, amount)`, `_burn(target, amount - consumed)`

**ETH Flow:** No
**Invariants:**
- Only GAME or AFFILIATE can call
- Attempts to consume coinflip credits first (via _consumeCoinflipShortfall), then burns remainder from wallet balance
- `amount - consumed` is safe: consumed is at most the shortfall (amount - balance), so `amount - consumed >= balance >= 0`
- NatSpec says "or affiliate" for callers, consistent with modifier
**NatSpec Accuracy:** Accurate
**Gas Flags:** None
**Verdict:** CORRECT

---

### `decimatorBurn(address player, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function decimatorBurn(address player, uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player (address(0) = msg.sender); `amount` (uint256): BURNIE to burn |
| **Returns** | none |

**State Reads:** `degenerusGame.isOperatorApproved(player, msg.sender)`, `degenerusGame.decWindow()`, `degenerusGame.rngLocked()` (via _consumeCoinflipShortfall), `balanceOf[caller]`, `_supply.totalSupply`, `degenerusGame.playerActivityScore(caller)`, `degenerusGame.consumeDecimatorBoon(caller)`
**State Writes:** `balanceOf[caller]`, `_supply.totalSupply` (via _burn), coinflip state (via creditFlip if quest reward)

**Callers:** Any external caller (players or approved operators)
**Callees:**
1. `degenerusGame.isOperatorApproved(player, msg.sender)` -- only if player != address(0) && player != msg.sender
2. `degenerusGame.decWindow()` -- checks active decimator window
3. `_consumeCoinflipShortfall(caller, amount)` -- consume coinflip credits for burn
4. `_burn(caller, amount - consumed)` -- burn from wallet
5. `questModule.handleDecimator(caller, amount)` -- quest processing
6. `_questApplyReward(...)` -- emit event if quest completed
7. `IBurnieCoinflip(coinflipContract).creditFlip(caller, questReward)` -- credit flip if quest reward
8. `degenerusGame.playerActivityScore(caller)` -- get activity bonus
9. `_decimatorBurnMultiplier(bonusBps)` -- compute multiplier
10. `_adjustDecimatorBucket(bonusBps, minBucket)` -- compute bucket
11. `degenerusGame.consumeDecimatorBoon(caller)` -- consume boon if available
12. `degenerusGame.recordDecBurn(caller, lvl, bucket, baseAmount, decBurnMultBps)` -- record the burn

**ETH Flow:** No
**Invariants:**
- Player determination: address(0) or msg.sender means self-burn; otherwise requires operator approval
- Minimum amount: DECIMATOR_MIN (1,000 BURNIE)
- Must be during active decimator window (checked via degenerusGame.decWindow())
- CEI pattern: burn BEFORE quest processing and downstream calls
- Quest reward: added to baseAmount for weight calculation but NOT burned (credited as flip stake)
- Activity score: capped at DECIMATOR_ACTIVITY_CAP_BPS (23,500 = 235%)
- Bucket: base 12, adjusted down by activity score, min bucket depends on level (5 normal, 2 for x00 levels)
- Boon: percent boost on base amount, capped at DECIMATOR_BOON_CAP (50,000 BURNIE)
- Final bucket used for jackpot weighting via degenerusGame.recordDecBurn
- Emits DecimatorBurn(caller, amount, bucketUsed) -- amount is original burn, not boosted
**NatSpec Accuracy:** Accurate. Comprehensive documentation of CEI pattern and quest bonus interaction.
**Gas Flags:** Multiple external calls to degenerusGame (decWindow, playerActivityScore, consumeDecimatorBoon, recordDecBurn) -- these are unavoidable and gas cost is appropriate for the complexity.
**Verdict:** CORRECT -- thorough CEI, proper access control, well-bounded arithmetic

---

### `_adjustDecimatorBucket(uint256 bonusBps, uint8 minBucket)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _adjustDecimatorBucket(uint256 bonusBps, uint8 minBucket) private pure returns (uint8 adjustedBucket)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `bonusBps` (uint256): activity bonus in basis points; `minBucket` (uint8): floor bucket |
| **Returns** | `uint8 adjustedBucket`: computed bucket (lower = better odds) |

**State Reads:** none
**State Writes:** none

**Callers:** `decimatorBurn()`
**Callees:** none

**ETH Flow:** No
**Invariants:**
- Starts at DECIMATOR_BUCKET_BASE (12)
- If bonusBps == 0, returns 12 (base)
- Caps bonusBps at DECIMATOR_ACTIVITY_CAP_BPS (23,500) -- redundant with caller's cap but defensive
- Computes range = 12 - minBucket (7 for normal, 10 for x00 levels)
- Reduction = (range * bonusBps + CAP/2) / CAP -- rounded division
- Adjusted bucket = 12 - reduction, floored at minBucket
- At max bonus (23,500): reduction = range * 23500 / 23500 = range, so bucket = minBucket
- Result always in [minBucket, DECIMATOR_BUCKET_BASE]
**NatSpec Accuracy:** Accurate
**Gas Flags:** The double cap on bonusBps (caller caps, then this function caps again) is defensive programming -- minimal gas cost.
**Verdict:** CORRECT -- bounded arithmetic, proper rounding

---

### `_decimatorBurnMultiplier(uint256 bonusBps)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _decimatorBurnMultiplier(uint256 bonusBps) private pure returns (uint256 decMultBps)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `bonusBps` (uint256): activity bonus in basis points |
| **Returns** | `uint256 decMultBps`: multiplier in basis points |

**State Reads:** none
**State Writes:** none

**Callers:** `decimatorBurn()`
**Callees:** none

**ETH Flow:** No
**Invariants:**
- Base multiplier: BPS_DENOMINATOR (10,000 = 1x)
- With bonus: 10,000 + bonusBps/3
- At max bonus (23,500): 10,000 + 7,833 = 17,833 bps = 1.7833x
- At zero: 10,000 = 1x
- Formula: 1x + one-third of activity bonus
**NatSpec Accuracy:** Accurate. "1x base plus one-third of activity bonus"
**Gas Flags:** None
**Verdict:** CORRECT

---

### Modifiers

---

### `onlyDegenerusGameContract()` [modifier]

| Field | Value |
|-------|-------|
| **Signature** | `modifier onlyDegenerusGameContract()` |
| **Visibility** | modifier |
| **Check** | `msg.sender != ContractAddresses.GAME` |
| **Error** | `OnlyGame()` |
| **Used by** | `rollDailyQuest()` |

**Verdict:** CORRECT

---

### `onlyTrustedContracts()` [modifier]

| Field | Value |
|-------|-------|
| **Signature** | `modifier onlyTrustedContracts()` |
| **Visibility** | modifier |
| **Check** | `sender != GAME && sender != AFFILIATE` |
| **Error** | `OnlyTrustedContracts()` |
| **Used by** | `burnCoin()` |

**Verdict:** CORRECT

---

### `onlyFlipCreditors()` [modifier]

| Field | Value |
|-------|-------|
| **Signature** | `modifier onlyFlipCreditors()` |
| **Visibility** | modifier |
| **Check** | `sender != GAME && sender != AFFILIATE` |
| **Error** | `OnlyFlipCreditors()` |
| **Used by** | `creditCoin()`, `creditFlip()`, `creditFlipBatch()` |

**Verdict:** CORRECT -- same caller set as onlyTrustedContracts but separate error for clarity

---

### `onlyVault()` [modifier]

| Field | Value |
|-------|-------|
| **Signature** | `modifier onlyVault()` |
| **Visibility** | modifier |
| **Check** | `msg.sender != ContractAddresses.VAULT` |
| **Error** | `OnlyVault()` |
| **Used by** | `vaultMintTo()` |

**Verdict:** CORRECT

---

### `onlyAdmin()` [modifier]

| Field | Value |
|-------|-------|
| **Signature** | `modifier onlyAdmin()` |
| **Visibility** | modifier |
| **Check** | `msg.sender != ContractAddresses.ADMIN` |
| **Error** | `OnlyGame()` (reused error) |
| **Used by** | `creditLinkReward()` |

**Verdict:** CORRECT -- reuses OnlyGame error to save bytecode (informational)
