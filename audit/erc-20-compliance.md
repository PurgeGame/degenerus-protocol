# ERC-20 Compliance Audit

**Date:** 2026-03-27
**Scope:** DGNRS (DegenerusStonk.sol), BURNIE (BurnieCoin.sol), sDGNRS (StakedDegenerusStonk.sol), GNRUS (GNRUS.sol)
**Methodology:** Function-by-function trace against EIP-20 specification, deep edge-case analysis for transferable tokens, soulbound bypass verification for non-transferable tokens

---

## Deviation Summary Table

All deviations are intentional design decisions. Disposition is DOCUMENT per Phase 130 D-05 -- no code changes.

| # | Token | Deviation | EIP-20 Expectation | Actual Behavior | Severity | Disposition | KNOWN-ISSUES |
|---|-------|-----------|--------------------|-----------------|----------|-------------|--------------|
| 1 | DGNRS | Transfer to `address(this)` reverts | EIP-20 does not restrict recipients | `Unauthorized()` revert in `_transfer` | Info | Document | Yes |
| 2 | DGNRS | No EIP-2612 `permit` | Not required by ERC-20 | Not implemented | Info | N/A | No |
| 3 | DGNRS | No `increaseAllowance`/`decreaseAllowance` | Not required by ERC-20 | Not implemented; approve race is ERC-20 known issue | Info | N/A | No |
| 4 | BURNIE | Game contract bypasses allowance in `transferFrom` | EIP-20: transferFrom MUST check allowance | Game contract has implicit infinite approval over all addresses | Low | Document | Yes |
| 5 | BURNIE | `transfer`/`transferFrom` may auto-claim coinflip BURNIE | EIP-20: transfer should only move existing tokens | `_claimCoinflipShortfall` may mint BURNIE to sender before transfer | Info | Document | Yes |
| 6 | BURNIE | Transfer to VAULT burns tokens | EIP-20: transfer should move tokens to recipient | `_transfer` special-cases VAULT -- burns and adds to vault allowance | Info | Document | Yes |
| 7 | BURNIE | No EIP-2612 `permit` | Not required by ERC-20 | Not implemented | Info | N/A | No |
| 8 | sDGNRS | Soulbound -- no transfer/approve/allowance | ERC-20 requires all functions | By design: not an ERC-20 token | N/A | Document | No |
| 9 | GNRUS | Soulbound -- transfer/transferFrom/approve revert | ERC-20 requires functional transfer | `TransferDisabled()` revert on all three | N/A | Document | No |

---

## DGNRS (DegenerusStonk.sol)

**Classification:** ERC-20 token (transferable)
**Contract:** `DegenerusStonk` -- 305 lines
**Verdict:** ERC-20 COMPLIANT with 1 documented deviation

### Function-by-Function Analysis

| Function | EIP-20 Requirement | Implementation | Status |
|----------|-------------------|----------------|--------|
| `name()` | OPTIONAL | `string public constant name = "Degenerus Stonk"` | Compliant |
| `symbol()` | OPTIONAL | `string public constant symbol = "DGNRS"` | Compliant |
| `decimals()` | OPTIONAL | `uint8 public constant decimals = 18` | Compliant |
| `totalSupply` | REQUIRED | `uint256 public totalSupply` -- decremented on burn | Compliant |
| `balanceOf` | REQUIRED | `mapping(address => uint256) public balanceOf` | Compliant |
| `transfer(to, amount)` | REQUIRED | Calls `_transfer(msg.sender, to, amount)`, returns `true` | Compliant |
| `transferFrom(from, to, amount)` | REQUIRED | Checks/decrements allowance (max-uint skip), calls `_transfer`, emits `Approval`, returns `true` | Compliant |
| `approve(spender, amount)` | REQUIRED | Sets allowance, emits `Approval`, returns `true` | Compliant |
| `allowance` | REQUIRED | `mapping(address => mapping(address => uint256)) public allowance` | Compliant |

### Edge Case Analysis

**1. Zero-amount transfer**
Trace: `transfer(to, 0)` -> `_transfer(msg.sender, to, 0)` -> `amount > bal` where `bal >= 0` and `amount == 0` -> passes -> unchecked subtraction `bal - 0 = bal` -> unchecked addition `balanceOf[to] += 0` -> `Transfer` event emitted.
**Result:** Succeeds, emits `Transfer` event with 0 amount. EIP-20 compliant.

**2. Self-transfer**
Trace: `transfer(msg.sender, amount)` -> `_transfer(msg.sender, msg.sender, amount)` -> `bal = balanceOf[msg.sender]` -> `amount > bal` check -> unchecked `balanceOf[msg.sender] = bal - amount` -> unchecked `balanceOf[msg.sender] += amount`. Since `from == to`, the subtraction followed by addition on the same address preserves balance exactly (net zero change). `Transfer` event emitted.
**Result:** Succeeds without loss or double-counting. EIP-20 compliant.

**3. Max-uint approval**
Trace: `approve(spender, type(uint256).max)` -> sets `allowance[msg.sender][spender] = type(uint256).max` -> emits `Approval`. In `transferFrom`: `allowed = type(uint256).max` -> `allowed != type(uint256).max` is false -> allowance deduction skipped entirely.
**Result:** Infinite approval preserved across unlimited transfers. EIP-20 compliant (common gas optimization).

**4. Approve race condition**
DGNRS does not implement `increaseAllowance`/`decreaseAllowance`. The front-running race on `approve(spender, newValue)` is a known ERC-20 specification limitation, not a DGNRS bug. The EIP-20 spec itself documents this: "clients SHOULD make sure to create user interfaces in such a way that they set the allowance first to 0 before setting it to another value."
**Result:** Known ERC-20 limitation. Not a finding.

**5. EIP-2612 (permit)**
Not implemented. EIP-2612 is a separate EIP, not required by ERC-20.
**Result:** Intentional omission. Not a finding.

**6. Transfer to zero address**
Trace: `_transfer(from, address(0), amount)` -> `if (to == address(0)) revert ZeroAddress()`.
**Result:** Reverts. EIP-20 says "Transfers of 0 values MUST be treated as normal transfers" and implementations "SHOULD throw if..." -- blocking zero-address transfers is standard. Compliant.

**7. Transfer to `address(this)` (Deviation #1)**
Trace: `_transfer(from, address(this), amount)` -> `if (to == address(this)) revert Unauthorized()`.
**Result:** Reverts. EIP-20 does NOT mandate this restriction -- any address should be a valid recipient. This prevents accidental token lockup in the contract. **Intentional deviation, wardens could file this.**

**8. Transfer event on zero-amount**
Trace: `_transfer` always executes `emit Transfer(from, to, amount)` regardless of amount value, including 0.
**Result:** `Transfer` event emitted for zero-amount transfers. EIP-20 compliant.

**9. Burn rejects zero amount**
Trace: `_burn(from, 0)` -> `if (amount == 0 || amount > bal) revert Insufficient()`.
**Result:** `burn(0)` reverts. This is not an ERC-20 function -- `burn` is an extension. Not a compliance issue.

**10. `Approval` event on `transferFrom` allowance change**
Trace: `transferFrom` decrements `allowance[from][msg.sender]` and emits `Approval(from, msg.sender, newAllowance)`.
**Result:** Compliant. `Approval` event emitted on allowance decrement per EIP-20 SHOULD recommendation.

**11. Reentrancy via receiver**
Trace: `_transfer` performs only state manipulation (`balanceOf` writes) and `emit Transfer`. No external calls in any ERC-20 function path. `transfer`, `transferFrom`, and `approve` contain zero external calls.
**Result:** No reentrancy surface in ERC-20 functions. Safe.

---

## BURNIE (BurnieCoin.sol)

**Classification:** ERC-20 token (transferable) with game-integration extensions
**Contract:** `BurnieCoin` -- ~900+ lines
**Verdict:** ERC-20 COMPLIANT with 3 documented deviations

### Function-by-Function Analysis

| Function | EIP-20 Requirement | Implementation | Status |
|----------|-------------------|----------------|--------|
| `name()` | OPTIONAL | `string public constant name = "Burnies"` | Compliant |
| `symbol()` | OPTIONAL | `string public constant symbol = "BURNIE"` | Compliant |
| `decimals()` | OPTIONAL | `uint8 public constant decimals = 18` | Compliant |
| `totalSupply()` | REQUIRED | View function reading `_supply.totalSupply` (packed `uint128`). Excludes vault allowance. | Compliant |
| `balanceOf` | REQUIRED | `mapping(address => uint256) public balanceOf` | Compliant |
| `transfer(to, amount)` | REQUIRED | Calls `_claimCoinflipShortfall`, then `_transfer`, returns `true` | Compliant (Deviation #6: auto-claim side effect) |
| `transferFrom(from, to, amount)` | REQUIRED | Game bypass + allowance check, claims shortfall, `_transfer`, returns `true` | Compliant (Deviations #5, #6) |
| `approve(spender, amount)` | REQUIRED | Sets allowance (skips SSTORE if unchanged), emits `Approval`, returns `true` | Compliant |
| `allowance` | REQUIRED | `mapping(address => mapping(address => uint256)) public allowance` | Compliant |

### Edge Case Analysis

**1. Zero-amount transfer**
Trace: `transfer(to, 0)` -> `_claimCoinflipShortfall(msg.sender, 0)` returns immediately (`amount == 0` check at line 591). -> `_transfer(msg.sender, to, 0)` -> `balanceOf[from] -= 0` succeeds (Solidity 0.8+ does not revert on 0 subtraction) -> `balanceOf[to] += 0` -> `Transfer` event emitted.
**Result:** Succeeds, emits `Transfer` with 0 amount. EIP-20 compliant.

**2. Self-transfer**
Trace: `_transfer(from, from, amount)` where `from == to` -> `balanceOf[from] -= amount` -> `balanceOf[to] += amount` (same slot). Net effect: balance unchanged. `Transfer` event emitted.
Special case: if `to == ContractAddresses.VAULT` the vault burn path triggers, but `from` would need to be VAULT for self-transfer, and VAULT cannot self-transfer via this path (would burn its own tokens).
**Result:** Standard self-transfer succeeds without loss. EIP-20 compliant.

**3. Max-uint approval**
Trace: `transferFrom` at line 431: `if (allowed != type(uint256).max && amount != 0)` -- when `allowed == type(uint256).max`, the entire allowance deduction block is skipped.
**Result:** Infinite approval preserved. EIP-20 compliant.

**4. Approve race condition**
No `increaseAllowance`/`decreaseAllowance`. Same known ERC-20 limitation as DGNRS.
**Result:** Known ERC-20 limitation. Not a finding.

**5. Transfer to zero address**
Trace: `_transfer` at line 454: `if (from == address(0) || to == address(0)) revert ZeroAddress()`.
**Result:** Reverts on zero-address recipient. EIP-20 compliant ("SHOULD throw").

**6. Game contract bypass in `transferFrom` (Deviation #5)**
Trace: `transferFrom` at line 428: `if (msg.sender != ContractAddresses.GAME)` -- when caller IS the game contract, the entire allowance check is skipped. The game contract can transfer any player's BURNIE without approval.
EIP-20: "The transferFrom method is used for a withdraw workflow, allowing contracts to transfer tokens on your behalf... The function SHOULD throw unless the _from account has deliberately authorized the sender."
**Result:** Game contract has implicit infinite approval over ALL addresses. **Intentional deviation -- trusted contract pattern. Wardens could file as centralization risk.**

**7. `transferFrom` emits `Approval` event on allowance change**
Trace: At line 435: `emit Approval(from, msg.sender, newAllowance)` -- emitted when allowance is decremented (non-game, non-max-uint, non-zero-amount).
**Result:** More compliant than DGNRS -- follows EIP-20 SHOULD recommendation. Compliant.

**8. Coinflip auto-claim on transfer (Deviation #6)**
Trace: `transfer(to, amount)` -> `_claimCoinflipShortfall(msg.sender, amount)` at line 590-601. If `amount > 0` AND `!rngLocked()` AND `balanceOf[player] < amount`, calls `coinflipContract.claimCoinflipsFromBurnie(player, amount - balance)` which mints BURNIE to the player BEFORE the transfer executes.
EIP-20: Transfer should move existing tokens, not mint new ones as a side effect.
**Result:** Transfer may mint tokens before executing. **Intentional design -- enables seamless UX where players can spend pending coinflip winnings. Wardens could file this as non-standard behavior.**

**9. Transfer to VAULT burns tokens (Deviation #7)**
Trace: `_transfer` at line 458-468: when `to == ContractAddresses.VAULT`, tokens are burned (`_supply.totalSupply -= amount128`) and added to vault allowance (`_supply.vaultAllowance += amount128`). Emits `Transfer(from, address(0), amount)` (burn event) instead of `Transfer(from, VAULT, amount)`.
EIP-20: Transfer to any address should increase that address's `balanceOf`.
**Result:** Sending to VAULT burns instead of transferring. `balanceOf[VAULT]` is never increased. **Intentional design -- VAULT uses virtual allowance model. Wardens could file this.**

**10. EIP-2612 (permit)**
Not implemented. Not required by ERC-20.
**Result:** Intentional omission. Not a finding.

**11. Approve optimization**
Trace: `approve` at line 396: `if (current != amount)` -- skips `SSTORE` if new value equals current value. `Approval` event is ALWAYS emitted regardless (line 399).
**Result:** Gas optimization only. Approval event always fires. EIP-20 compliant.

**12. Reentrancy via `_claimCoinflipShortfall`**
Trace: `transfer`/`transferFrom` call `_claimCoinflipShortfall` which makes an external call to `coinflipContract.claimCoinflipsFromBurnie`. This external call happens BEFORE `_transfer` modifies state.
Risk: The coinflip contract is a compile-time constant (`ContractAddresses.COINFLIP`), not user-controlled. The coinflip contract is trusted and its `claimCoinflipsFromBurnie` only mints to the player -- no callback to BurnieCoin.
**Result:** Accepted trust model. External call is to a trusted, immutable contract address. Not exploitable.

---

## sDGNRS (StakedDegenerusStonk.sol)

**Classification:** Soulbound token -- NOT an ERC-20 token
**Contract:** `StakedDegenerusStonk` -- ~800+ lines
**Verdict:** NOT ERC-20 by design. Soulbound restrictions are airtight.

sDGNRS is a soulbound token. It exposes ERC-20 view functions (`name`, `symbol`, `decimals`, `totalSupply`, `balanceOf`) for wallet and indexer compatibility but is NOT an ERC-20 token. Wardens cannot file ERC-20 compliance issues against a token that does not claim ERC-20 status.

### Implemented Functions (View Only)

| Function | Purpose | Implementation |
|----------|---------|----------------|
| `name()` | Wallet display | `string public constant name = "Staked Degenerus Stonk"` |
| `symbol()` | Wallet display | `string public constant symbol = "sDGNRS"` |
| `decimals()` | Wallet display | `uint8 public constant decimals = 18` |
| `totalSupply` | Indexer compat | `uint256 public totalSupply` |
| `balanceOf` | Indexer compat | `mapping(address => uint256) public balanceOf` |

### NOT Implemented (Confirmed Absent)

| Function | Status | Verification |
|----------|--------|--------------|
| `transfer(address, uint256)` | NOT PRESENT | No `transfer` function exists in the contract. The `IDegenerusCoinPlayer` interface (imported for BURNIE interaction) declares `transfer`, but sDGNRS itself has no such function. |
| `transferFrom(address, address, uint256)` | NOT PRESENT | No `transferFrom` function exists. |
| `approve(address, uint256)` | NOT PRESENT | No `approve` function exists. |
| `allowance` mapping | NOT PRESENT | No `allowance` state variable exists. |

### Restricted Movement Functions (Not Public Transfer)

| Function | Restriction | Purpose |
|----------|-------------|---------|
| `wrapperTransferTo(to, amount)` | `msg.sender == ContractAddresses.DGNRS` only | Creator unwraps DGNRS back to soulbound sDGNRS for specific recipients. Only callable by the DGNRS wrapper contract. |
| `transferFromPool(pool, to, amount)` | `onlyGame` modifier | Game distributes sDGNRS from pre-minted reward pools to players. |
| `transferBetweenPools(from, to, amount)` | `onlyGame` modifier | Internal rebalance between reward pools. No tokens leave the contract. |

### Soulbound Verification

**Is the soulbound property airtight?** YES.

The only ways sDGNRS can move between addresses:
1. `wrapperTransferTo` -- restricted to DGNRS contract, for creator unwrap flow only
2. `transferFromPool` -- restricted to game contract, pool-to-player reward distribution only
3. `transferBetweenPools` -- restricted to game contract, inter-pool rebalance (no external movement)
4. `burn` / `burnWrapped` / `burnForGameWrapper` -- destroy tokens for backing redemption, not transfer

**No public transfer path exists.** A player holding sDGNRS cannot send it to another address. sDGNRS can only arrive via game reward distributions or creator unwrap, and can only leave via burn.

---

## GNRUS (GNRUS.sol)

**Classification:** Soulbound token -- NOT an ERC-20 token
**Contract:** `GNRUS` (DegenerusDonations) -- 539 lines
**Verdict:** NOT ERC-20 by design. Soulbound restrictions are airtight.

GNRUS is a soulbound token. It implements `transfer`, `transferFrom`, and `approve` function signatures that unconditionally revert with `TransferDisabled()`. This pattern ensures wallet UIs surface the function signatures but all calls fail, preventing any accidental expectation of transferability.

### Implemented Functions (View + Reverting Stubs)

| Function | Purpose | Implementation |
|----------|---------|----------------|
| `name()` | Wallet display | `string public constant name = "GNRUS Donations"` |
| `symbol()` | Wallet display | `string public constant symbol = "GNRUS"` |
| `decimals()` | Wallet display | `uint8 public constant decimals = 18` |
| `totalSupply` | Indexer compat | `uint256 public totalSupply` |
| `balanceOf` | Indexer compat | `mapping(address => uint256) public balanceOf` |
| `transfer(address, uint256)` | Soulbound enforcement | `external pure returns (bool) { revert TransferDisabled(); }` |
| `transferFrom(address, address, uint256)` | Soulbound enforcement | `external pure returns (bool) { revert TransferDisabled(); }` |
| `approve(address, uint256)` | Soulbound enforcement | `external pure returns (bool) { revert TransferDisabled(); }` |

### NOT Implemented

| Function | Status |
|----------|--------|
| `allowance` mapping | NOT PRESENT -- no allowance state variable exists. No bypass path. |

### Soulbound Verification

**Is the soulbound property airtight?** YES.

Token movement analysis:
1. `transfer` / `transferFrom` / `approve` -- all revert `TransferDisabled()`. Functions are `pure` (no state access), guaranteeing they always revert regardless of input.
2. `pickCharity(level)` -- restricted to `onlyGame`. Distributes from `balanceOf[address(this)]` (the unallocated pool) to the winning governance recipient. Only the game contract can call this.
3. `_mint(to, amount)` -- `private`. Only called in `constructor()` to mint the full 1T supply to `address(this)`.
4. `burn(amount)` -- public, reduces `msg.sender`'s own balance. Burns tokens for proportional ETH + stETH redemption. Cannot move tokens to another address.
5. `burnAtGameOver()` -- restricted to `onlyGame`. Burns the contract's own unallocated balance. Cannot move tokens to another address.

**No public transfer path exists.** A GNRUS holder cannot send tokens to another address. GNRUS can only arrive via governance distribution (`pickCharity`), and can only leave via `burn()`.

---

## KNOWN-ISSUES.md Recommendations for Phase 134

The following deviations should be added to KNOWN-ISSUES.md. Each entry is formatted ready-to-paste:

### Deviation #1: DGNRS transfer to self-address blocked

```
**DGNRS blocks transfer to its own contract address.** `_transfer` reverts with `Unauthorized()` when `to == address(this)`. EIP-20 does not restrict recipients. This prevents accidental token lockup since DGNRS held by the contract is indistinguishable from the sDGNRS-backed reserve. Intentional design.
```

### Deviation #4: BURNIE game contract allowance bypass

```
**BURNIE game contract bypasses transferFrom allowance.** The DegenerusGame contract can call `transferFrom` without prior approval. This is the trusted contract pattern -- the game address is a compile-time immutable constant, not upgradeable. Enables seamless gameplay transactions without pre-approval UX. All other callers require standard allowance.
```

### Deviation #5: BURNIE auto-claim on transfer

```
**BURNIE transfer/transferFrom may auto-claim pending coinflip winnings.** Before executing a transfer, `_claimCoinflipShortfall` checks if the sender has insufficient balance and auto-claims pending coinflip BURNIE from the trusted BurnieCoinflip contract (compile-time constant). This mints tokens before the transfer, which is non-standard ERC-20 behavior. Intentional UX design -- players can spend winnings without a separate claim step. The coinflip contract is immutable and trusted.
```

### Deviation #6: BURNIE transfer to VAULT burns

```
**BURNIE sent to VAULT is burned, not transferred.** `_transfer` special-cases `to == ContractAddresses.VAULT` -- tokens are burned (totalSupply reduced) and added to vault's virtual mint allowance. The VAULT uses a virtual reserve model where `balanceOf[VAULT]` is always 0 and the actual reserve is tracked in `_supply.vaultAllowance`. Emits `Transfer(from, address(0))` (burn event). Intentional architecture.
```

---

## Overall Conclusion

| Token | Classification | Verdict | Deviations |
|-------|---------------|---------|------------|
| DGNRS | ERC-20 | COMPLIANT | 1 documented (self-address block) |
| BURNIE | ERC-20 | COMPLIANT | 3 documented (game bypass, auto-claim, vault redirect) |
| sDGNRS | Soulbound | NOT ERC-20 | N/A -- soulbound by design, view-only compatibility |
| GNRUS | Soulbound | NOT ERC-20 | N/A -- soulbound by design, reverting transfer stubs |

All 4 tokens behave correctly for their intended purpose. The 4 ERC-20 deviations in DGNRS and BURNIE are intentional design decisions with clear rationale. None represent security vulnerabilities. All should be documented in KNOWN-ISSUES.md to pre-empt warden filings.

The soulbound tokens (sDGNRS, GNRUS) have airtight restrictions with no bypass paths. Filing ERC-20 compliance issues against these tokens is invalid since they do not claim ERC-20 status.
