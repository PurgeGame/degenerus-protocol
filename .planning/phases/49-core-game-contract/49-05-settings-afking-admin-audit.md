# DegenerusGame.sol -- Settings, AfKing, Admin & Payout Audit

**Contract:** DegenerusGame
**File:** contracts/DegenerusGame.sol
**Lines audited:** 1516-2012
**Solidity:** 0.8.34
**Inherits:** DegenerusGameMintStreakUtils -> DegenerusGameStorage
**Audit date:** 2026-03-07

## Summary

Player settings (auto-rebuy, afKing mode), admin operations (ETH/stETH swaps, VRF coordinator updates), VRF lifecycle (lootbox RNG, coinflip reversal, VRF fulfillment), and ETH/stETH payout primitives used by all claim paths.

## Function Audit

---

### `setAutoRebuy(address player, bool enabled)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function setAutoRebuy(address player, bool enabled) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player address to configure (address(0) = msg.sender); `enabled` (bool): true to enable auto-rebuy, false to disable |
| **Returns** | None |

**State Reads:**
- `operatorApprovals[player][msg.sender]` (via `_resolvePlayer` -> `_requireApproved`)

**State Writes:**
- Delegates to `_setAutoRebuy` (see below)

**Callers:** External entry point. Called by players or approved operators.

**Callees:**
- `_resolvePlayer(player)` -- resolves address(0) to msg.sender, checks operator approval
- `_setAutoRebuy(player, enabled)` -- internal implementation

**ETH Flow:** None.

**Invariants:**
- Only `msg.sender` or an approved operator can modify a player's settings
- Resolves `address(0)` to `msg.sender` for convenience

**NatSpec Accuracy:** NatSpec accurately describes auto-rebuy toggle, bonus percentages (30% default, 45% afKing), and ticket conversion mechanics. The function correctly delegates to `_setAutoRebuy`.

**Gas Flags:** None. Simple delegation wrapper.

**Verdict:** CORRECT

---

### `setDecimatorAutoRebuy(address player, bool enabled)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function setDecimatorAutoRebuy(address player, bool enabled) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player address to configure (address(0) = msg.sender); `enabled` (bool): true to enable decimator auto-rebuy, false to disable |
| **Returns** | None |

**State Reads:**
- `operatorApprovals[player][msg.sender]` (via `_resolvePlayer` -> `_requireApproved`)
- `rngLockedFlag` -- checked for RNG lock
- `decimatorAutoRebuyDisabled[player]` -- current toggle state

**State Writes:**
- `decimatorAutoRebuyDisabled[player]` -- set to `!enabled` (inverted storage: true = disabled)

**Callers:** External entry point. Called by players or approved operators.

**Callees:**
- `_resolvePlayer(player)` -- resolves address(0) to msg.sender, checks operator approval

**ETH Flow:** None.

**Invariants:**
- DGNRS contract cannot toggle this setting (`revert E()` if `player == ContractAddresses.DGNRS`)
- Cannot modify during RNG lock (`revert RngLocked()`)
- Default is enabled (mapping defaults to `false`, and `!false` = enabled)

**NatSpec Accuracy:** NatSpec correctly states "Default is enabled" and "DGNRS is not permitted to toggle this setting." Both match the implementation.

**Gas Flags:**
- Conditional write (`if (decimatorAutoRebuyDisabled[player] != disabled)`) prevents redundant SSTORE. Efficient pattern.
- Event emitted even on no-op (same state). This is an informational -- the event always reflects the current user intent.

**Verdict:** CORRECT

---

### `setAutoRebuyTakeProfit(address player, uint256 takeProfit)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function setAutoRebuyTakeProfit(address player, uint256 takeProfit) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player address to configure (address(0) = msg.sender); `takeProfit` (uint256): amount in wei reserved for manual claim (0 = rebuy all) |
| **Returns** | None |

**State Reads:**
- `operatorApprovals[player][msg.sender]` (via `_resolvePlayer` -> `_requireApproved`)

**State Writes:**
- Delegates to `_setAutoRebuyTakeProfit` (see below)

**Callers:** External entry point. Called by players or approved operators.

**Callees:**
- `_resolvePlayer(player)` -- resolves address(0) to msg.sender, checks operator approval
- `_setAutoRebuyTakeProfit(player, takeProfit)` -- internal implementation

**ETH Flow:** None.

**Invariants:**
- Only `msg.sender` or an approved operator can modify a player's settings

**NatSpec Accuracy:** NatSpec correctly describes "complete multiples remain claimable; remainder is eligible for auto-rebuy" and "0 means no reservation (rebuy all)."

**Gas Flags:** None. Simple delegation wrapper.

**Verdict:** CORRECT

---

### `_setAutoRebuy(address player, bool enabled)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _setAutoRebuy(address player, bool enabled) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): resolved player address; `enabled` (bool): new toggle state |
| **Returns** | None |

**State Reads:**
- `rngLockedFlag` -- checked for RNG lock
- `autoRebuyState[player].autoRebuyEnabled` -- current toggle state
- `autoRebuyState[player].afKingMode` (via `_deactivateAfKing`)

**State Writes:**
- `autoRebuyState[player].autoRebuyEnabled` -- set to `enabled` (conditional write)

**Callers:**
- `setAutoRebuy(address, bool)` -- external entry point

**Callees:**
- `_deactivateAfKing(player)` -- called when disabling auto-rebuy (afKing requires auto-rebuy)

**ETH Flow:** None.

**Invariants:**
- Cannot modify during RNG lock (`revert RngLocked()`)
- Disabling auto-rebuy forces afKing deactivation (afKing depends on auto-rebuy being on)
- Event emitted even on no-op (same state). Informational.

**NatSpec Accuracy:** No NatSpec on this private function. Behavior is clear from code: toggle with RNG guard and afKing coupling.

**Gas Flags:**
- Conditional write prevents redundant SSTORE. Efficient.
- Event always emitted regardless of state change -- consistent with `setDecimatorAutoRebuy` pattern.

**Verdict:** CORRECT

---

### `_setAutoRebuyTakeProfit(address player, uint256 takeProfit)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _setAutoRebuyTakeProfit(address player, uint256 takeProfit) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): resolved player address; `takeProfit` (uint256): amount in wei |
| **Returns** | None |

**State Reads:**
- `rngLockedFlag` -- checked for RNG lock
- `autoRebuyState[player].takeProfit` -- current take profit value
- `autoRebuyState[player].afKingMode` (via `_deactivateAfKing`)

**State Writes:**
- `autoRebuyState[player].takeProfit` -- set to `uint128(takeProfit)` (conditional write)

**Callers:**
- `setAutoRebuyTakeProfit(address, uint256)` -- external entry point

**Callees:**
- `_deactivateAfKing(player)` -- called when `takeProfit != 0 && takeProfit < AFKING_KEEP_MIN_ETH` (5 ETH)

**ETH Flow:** None.

**Invariants:**
- Cannot modify during RNG lock (`revert RngLocked()`)
- If take profit is nonzero but below 5 ETH minimum for afKing, afKing is deactivated
- `uint128` truncation: values > type(uint128).max silently truncate. This is safe because `uint128` holds up to ~3.4e20 ETH, far exceeding realistic values.

**NatSpec Accuracy:** No NatSpec on this private function. Behavior matches parent's NatSpec.

**Gas Flags:**
- Conditional write prevents redundant SSTORE. Efficient.
- Event uses the original `takeProfit` (uint256), not the truncated `uint128` value. This could theoretically differ if caller passes > 2^128, but this is unrealistic and the truncation in storage is the intended behavior.

**Verdict:** CORRECT

---

### `autoRebuyEnabledFor(address player)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function autoRebuyEnabledFor(address player) external view returns (bool enabled)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): player address to check |
| **Returns** | `enabled` (bool): true if auto-rebuy is enabled |

**State Reads:**
- `autoRebuyState[player].autoRebuyEnabled`

**State Writes:** None.

**Callers:** External view for UI/frontend.

**Callees:** None.

**ETH Flow:** None.

**Invariants:** Pure read, no side effects.

**NatSpec Accuracy:** Accurate. "Check if auto-rebuy is enabled for a player" matches behavior.

**Gas Flags:** None. Single SLOAD.

**Verdict:** CORRECT

---

### `decimatorAutoRebuyEnabledFor(address player)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function decimatorAutoRebuyEnabledFor(address player) external view returns (bool enabled)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): player address to check |
| **Returns** | `enabled` (bool): true if decimator auto-rebuy is enabled |

**State Reads:**
- `decimatorAutoRebuyDisabled[player]`

**State Writes:** None.

**Callers:** External view for UI/frontend; also read by DecimatorModule during claim processing.

**Callees:** None.

**ETH Flow:** None.

**Invariants:** Returns `!decimatorAutoRebuyDisabled[player]` -- inverted storage convention, default enabled.

**NatSpec Accuracy:** Accurate. "Check if decimator auto-rebuy is enabled for a player" matches behavior.

**Gas Flags:** None. Single SLOAD.

**Verdict:** CORRECT

---

### `autoRebuyTakeProfitFor(address player)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function autoRebuyTakeProfitFor(address player) external view returns (uint256 takeProfit)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): player address to check |
| **Returns** | `takeProfit` (uint256): amount reserved as complete multiples (wei) |

**State Reads:**
- `autoRebuyState[player].takeProfit`

**State Writes:** None.

**Callers:** External view for UI/frontend.

**Callees:** None.

**ETH Flow:** None.

**Invariants:** Returns uint128 value widened to uint256.

**NatSpec Accuracy:** NatSpec says "Amount reserved as complete multiples (wei)" which matches the semantic intent. The return value is the raw `takeProfit` from storage.

**Gas Flags:** None. Single SLOAD.

**Verdict:** CORRECT

---

### `setAfKingMode(address player, bool enabled, uint256 ethTakeProfit, uint256 coinTakeProfit)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function setAfKingMode(address player, bool enabled, uint256 ethTakeProfit, uint256 coinTakeProfit) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player address (address(0) = msg.sender); `enabled` (bool): true to enable afKing, false to disable; `ethTakeProfit` (uint256): desired ETH take profit (wei); `coinTakeProfit` (uint256): desired coin take profit (BURNIE, 18 decimals) |
| **Returns** | None |

**State Reads:**
- `operatorApprovals[player][msg.sender]` (via `_resolvePlayer` -> `_requireApproved`)

**State Writes:**
- Delegates to `_setAfKingMode` (see below)

**Callers:** External entry point. Called by players or approved operators.

**Callees:**
- `_resolvePlayer(player)` -- resolves address(0) to msg.sender, checks operator approval
- `_setAfKingMode(player, enabled, ethTakeProfit, coinTakeProfit)` -- internal implementation

**ETH Flow:** None.

**Invariants:**
- Only `msg.sender` or an approved operator can modify a player's settings

**NatSpec Accuracy:** NatSpec accurately describes: enabling forces auto-rebuy on, clamps take profit to minimums (5 ETH / 20k BURNIE) unless set to 0, requires lazy pass. Custom reverts (RngLocked, E, AfKingLockActive) are documented and match implementation.

**Gas Flags:** None. Simple delegation wrapper.

**Verdict:** CORRECT

---

### `_setAfKingMode(address player, bool enabled, uint256 ethTakeProfit, uint256 coinTakeProfit)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _setAfKingMode(address player, bool enabled, uint256 ethTakeProfit, uint256 coinTakeProfit) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): resolved player address; `enabled` (bool): toggle; `ethTakeProfit` (uint256): desired ETH take profit; `coinTakeProfit` (uint256): desired BURNIE take profit |
| **Returns** | None |

**State Reads:**
- `rngLockedFlag` -- checked for RNG lock
- `deityPassCount[player]` (via `_hasAnyLazyPass`)
- `mintPacked_[player]` (via `_hasAnyLazyPass`) -- frozen until level
- `level` (via `_hasAnyLazyPass`) -- current game level
- `autoRebuyState[player]` -- full struct: autoRebuyEnabled, takeProfit, afKingMode, afKingActivatedLevel

**State Writes:**
- `autoRebuyState[player].autoRebuyEnabled` -- forced true (conditional write)
- `autoRebuyState[player].takeProfit` -- set to clamped ETH take profit (conditional write)
- `autoRebuyState[player].afKingMode` -- set true (conditional write)
- `autoRebuyState[player].afKingActivatedLevel` -- set to current `level`

**Callers:**
- `setAfKingMode(address, bool, uint256, uint256)` -- external entry point

**Callees:**
- `_deactivateAfKing(player)` -- called when `enabled == false`
- `_hasAnyLazyPass(player)` -- lazy pass check (deity pass or frozen-until-level)
- `coinflip.setCoinflipAutoRebuy(player, true, adjustedCoinKeep)` -- enables coinflip auto-rebuy with clamped take profit
- `coinflip.settleFlipModeChange(player)` -- settles pending coinflip before mode change (only on first activation)

**ETH Flow:** None directly. The coinflip cross-contract calls do not move ETH.

**Invariants:**
- Requires lazy pass (deity pass or frozen-until-level > current level) to enable
- Cannot modify during RNG lock
- ETH take profit clamped to minimum 5 ETH if nonzero (0 allowed = rebuy all)
- Coin take profit clamped to minimum 20,000 BURNIE if nonzero (0 allowed = rebuy all)
- Forces auto-rebuy enabled as prerequisite
- `settleFlipModeChange` called before mode change to prevent pending-flip inconsistency
- `afKingActivatedLevel` always set to current level on activation (even re-activation, since it doesn't re-enter the block if already afKingMode)

**NatSpec Accuracy:** No NatSpec on private function. Parent NatSpec covers behavior accurately.

**Gas Flags:**
- Three conditional writes prevent redundant SSTOREs. Efficient.
- Two cross-contract calls (`coinflip.setCoinflipAutoRebuy`, `coinflip.settleFlipModeChange`) are necessary for consistency but add gas cost. These only fire on mode transitions.

**Verdict:** CORRECT

---

### `_hasAnyLazyPass(address player)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _hasAnyLazyPass(address player) private view returns (bool)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `player` (address): player address to check |
| **Returns** | `bool`: true if player has any active lazy pass |

**State Reads:**
- `deityPassCount[player]` -- deity pass count (nonzero = has pass)
- `mintPacked_[player]` -- bit-packed mint data (frozen-until-level field)
- `level` -- current game level

**State Writes:** None.

**Callers:**
- `_setAfKingMode(address, bool, uint256, uint256)` -- verifies lazy pass for afKing activation
- `syncAfKingLazyPassFromCoin(address)` -- verifies lazy pass still active during sync

**Callees:** None. Pure computation on storage reads.

**ETH Flow:** None.

**Invariants:**
- Returns true if deity pass count is nonzero (deity pass is perpetual lazy pass)
- Returns true if frozen-until-level (24-bit field at FROZEN_UNTIL_LEVEL_SHIFT=128) is strictly greater than current level
- `FROZEN_UNTIL_LEVEL_SHIFT = 128`, `MASK_24 = 0xFFFFFF` -- extracts bits [128:151] from mintPacked_

**NatSpec Accuracy:** No NatSpec. Function name and logic are self-documenting.

**Gas Flags:** None. Two SLOADs maximum (short-circuits on deity pass).

**Verdict:** CORRECT

---

### `hasActiveLazyPass(address player)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function hasActiveLazyPass(address player) external view returns (bool)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): player address to check |
| **Returns** | `bool`: true if player has active lazy pass |

**State Reads:**
- `deityPassCount[player]` -- deity pass count
- `mintPacked_[player]` -- bit-packed mint data (frozen-until-level field)
- `level` -- current game level

**State Writes:** None.

**Callers:** External view for UI/frontend.

**Callees:** None. Pure computation on storage reads.

**ETH Flow:** None.

**Invariants:**
- Exact duplicate logic of `_hasAnyLazyPass`. Both check deity pass count and frozen-until-level.
- This is the public-facing version; `_hasAnyLazyPass` is the internal version used by state-changing functions.

**NatSpec Accuracy:** NatSpec correctly states "True if player has frozenUntilLevel > current level OR deity pass." Matches implementation exactly.

**Gas Flags:**
- Code duplication with `_hasAnyLazyPass`. Informational -- this is a deliberate pattern. The external function cannot call the private function without gas overhead of an internal call, and the logic is trivial (4 lines). The duplication avoids extra stack operations.

**Verdict:** CORRECT

---

### `afKingModeFor(address player)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function afKingModeFor(address player) external view returns (bool active)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): player address to check |
| **Returns** | `active` (bool): true if afKing mode is active |

**State Reads:**
- `autoRebuyState[player].afKingMode`

**State Writes:** None.

**Callers:** External view for UI/frontend.

**Callees:** None.

**ETH Flow:** None.

**Invariants:** Pure read, no side effects.

**NatSpec Accuracy:** Accurate. "Check if afKing mode is active for a player" matches behavior.

**Gas Flags:** None. Single SLOAD.

**Verdict:** CORRECT

---

### `afKingActivatedLevelFor(address player)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function afKingActivatedLevelFor(address player) external view returns (uint24 activationLevel)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): player address to check |
| **Returns** | `activationLevel` (uint24): level at which afKing mode was enabled (0 if inactive) |

**State Reads:**
- `autoRebuyState[player].afKingActivatedLevel`

**State Writes:** None.

**Callers:** External view for UI/frontend.

**Callees:** None.

**ETH Flow:** None.

**Invariants:** Returns 0 when afKing is inactive (reset by `_deactivateAfKing`).

**NatSpec Accuracy:** NatSpec correctly states "0 if inactive" which matches the reset behavior in `_deactivateAfKing`.

**Gas Flags:** None. Single SLOAD.

**Verdict:** CORRECT

---

### `deactivateAfKingFromCoin(address player)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function deactivateAfKingFromCoin(address player) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player to deactivate afKing for |
| **Returns** | None |

**State Reads:**
- `msg.sender` -- checked against COIN and COINFLIP addresses
- Via `_deactivateAfKing`: `autoRebuyState[player]`

**State Writes:**
- Via `_deactivateAfKing`: `autoRebuyState[player].afKingMode`, `autoRebuyState[player].afKingActivatedLevel`

**Callers:** Called by BurnieCoin (COIN) or BurnieCoinflip (COINFLIP) contracts when they need to deactivate afKing (e.g., player disables coinflip auto-rebuy or sells all coins).

**Callees:**
- `_deactivateAfKing(player)` -- internal deactivation with lock period check

**ETH Flow:** None.

**Invariants:**
- Access: COIN or COINFLIP only (`revert E()` for others)
- Lock period enforced via `_deactivateAfKing` -- if within AFKING_LOCK_LEVELS (5) of activation, reverts with `AfKingLockActive`

**NatSpec Accuracy:** NatSpec says "Access: COIN or COINFLIP contract only" and the code checks both. The revert documentation matches.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `syncAfKingLazyPassFromCoin(address player)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function syncAfKingLazyPassFromCoin(address player) external returns (bool active)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player to sync afKing status for |
| **Returns** | `active` (bool): true if afKing remains active after sync |

**State Reads:**
- `msg.sender` -- checked against COINFLIP address
- `autoRebuyState[player].afKingMode` -- current afKing state
- `deityPassCount[player]` (via `_hasAnyLazyPass`)
- `mintPacked_[player]` (via `_hasAnyLazyPass`)
- `level` (via `_hasAnyLazyPass`)

**State Writes:**
- `autoRebuyState[player].afKingMode` -- set to false if lazy pass expired
- `autoRebuyState[player].afKingActivatedLevel` -- reset to 0 if lazy pass expired

**Callers:** Called by BurnieCoinflip (COINFLIP) during deposit/claim operations that call `_syncAfKingLazyPass`.

**Callees:**
- `_hasAnyLazyPass(player)` -- checks if player still has valid lazy pass

**ETH Flow:** None.

**Invariants:**
- Access: COINFLIP only (`revert E()` for others)
- If afKing not active, returns false immediately (no state change)
- If lazy pass still valid, returns true (no state change)
- If lazy pass expired, deactivates afKing without lock period check (no `AfKingLockActive` revert)
- Settle not called: comment explains coinflip operation already handles settlement
- Unlike `_deactivateAfKing`, this bypasses the lock period check because it's a passive expiry (lazy pass ran out), not a voluntary deactivation

**NatSpec Accuracy:** NatSpec says "Access: COINFLIP contract only" -- matches code (only checks COINFLIP, not COIN). NatSpec says "Sync afKing lazy pass status and revoke if inactive" -- accurate.

**Gas Flags:** None. Efficient short-circuit returns.

**Verdict:** CORRECT

---

### `_deactivateAfKing(address player)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _deactivateAfKing(address player) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player to deactivate afKing for |
| **Returns** | None |

**State Reads:**
- `autoRebuyState[player].afKingMode` -- checks if currently active
- `autoRebuyState[player].afKingActivatedLevel` -- used for lock period check
- `level` -- current game level

**State Writes:**
- `autoRebuyState[player].afKingMode` -- set to false
- `autoRebuyState[player].afKingActivatedLevel` -- reset to 0

**Callers:**
- `_setAutoRebuy(address, bool)` -- when disabling auto-rebuy
- `_setAutoRebuyTakeProfit(address, uint256)` -- when take profit below afKing minimum
- `_setAfKingMode(address, bool, uint256, uint256)` -- when explicitly disabling afKing
- `deactivateAfKingFromCoin(address)` -- cross-contract hook

**Callees:**
- `coinflip.settleFlipModeChange(player)` -- settles pending coinflip before mode change

**ETH Flow:** None directly. `settleFlipModeChange` is a settlement call.

**Invariants:**
- No-op if afKing not active (early return)
- Lock period enforced: if `activationLevel != 0` and `level < activationLevel + AFKING_LOCK_LEVELS (5)`, reverts with `AfKingLockActive`
- Special case: `activationLevel == 0` (activated at level 0) bypasses lock check entirely. This means afKing activated at level 0 can be immediately deactivated. This is intentional -- the lock prevents deactivation during the first 5 levels after activation, and level 0 activation means unlock at level 5 would always pass since `0 + 5 = 5`.
- Wait: Actually, `activationLevel != 0` guard means level 0 activation skips the lock. At level 0, `activationLevel = 0`, so the lock block is skipped entirely. The player could deactivate immediately. At level 1+, the lock would apply. This is a potential concern but reviewing the flow: `_setAfKingMode` sets `afKingActivatedLevel = level`. At level 0, this is 0. The `if (activationLevel != 0)` guard skips the lock. So a player who activates afKing at level 0 can deactivate immediately. This appears intentional since the game starts at level 0 and players should be able to experiment with settings before the game truly begins.
- `settleFlipModeChange` called before state mutation -- ensures pending coinflip bets are settled at the old mode
- Event emitted after state mutation

**NatSpec Accuracy:** No NatSpec on private function. Code is self-documenting.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `adminSwapEthForStEth(address recipient, uint256 amount)` [external payable]

| Field | Value |
|-------|-------|
| **Signature** | `function adminSwapEthForStEth(address recipient, uint256 amount) external payable` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | `recipient` (address): address to receive stETH; `amount` (uint256): ETH amount to swap (must match msg.value) |
| **Returns** | None |

**State Reads:**
- `steth.balanceOf(address(this))` -- game's stETH balance (external call to Lido)

**State Writes:**
- None in game storage. External stETH transfer alters stETH contract state.

**Callers:** Called by DegenerusAdmin contract only.

**Callees:**
- `steth.balanceOf(address(this))` -- check stETH balance
- `steth.transfer(recipient, amount)` -- transfer stETH to recipient

**ETH Flow:**
- **IN:** `msg.value` (ETH) from ADMIN contract enters game's ETH balance
- **OUT:** `amount` of stETH transferred from game to `recipient`
- Net effect: Game gains ETH, loses stETH of equal value. Value-neutral swap.

**Invariants:**
- Access: ADMIN only (`revert E()` for others)
- `recipient` must not be address(0) (`revert E()`)
- `amount` must be nonzero (`revert E()`)
- `msg.value` must exactly equal `amount` (`revert E()`)
- Game must hold sufficient stETH (`stBal >= amount`, `revert E()`)
- stETH transfer must succeed (`revert E()` on failure)
- Value-neutral: ADMIN sends exact ETH to receive game-held stETH. No fund extraction possible -- ADMIN cannot send less ETH than stETH received.

**NatSpec Accuracy:** NatSpec accurately describes "Admin-only swap: caller sends ETH in and receives game-held stETH." Security note "Value-neutral swap, ADMIN cannot extract funds" is accurate. Custom reverts documented.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `adminStakeEthForStEth(uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function adminStakeEthForStEth(uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `amount` (uint256): ETH amount to stake via Lido |
| **Returns** | None |

**State Reads:**
- `address(this).balance` -- game's ETH balance
- `claimablePool` -- reserved ETH for player claims

**State Writes:**
- None in game storage. Lido mints stETH to game address (external state change).

**Callers:** Called by DegenerusAdmin contract only.

**Callees:**
- `steth.submit{value: amount}(address(0))` -- Lido ETH-to-stETH stake (referral = address(0))

**ETH Flow:**
- **OUT:** `amount` ETH sent to Lido staking contract
- **IN:** stETH minted 1:1 to game address (Lido invariant)
- Net effect: Game converts ETH to stETH for yield. Value-preserving.

**Invariants:**
- Access: ADMIN only (`revert E()`)
- Amount must be nonzero (`revert E()`)
- Game must hold sufficient ETH (`ethBal >= amount`, `revert E()`)
- Game ETH balance must exceed claimablePool reserve (`ethBal > reserve`, `revert E()`)
- Stakeable amount is `ethBal - reserve`; amount must not exceed stakeable (`revert E()`)
- claimablePool is protected: admin cannot stake ETH reserved for player claims
- Lido submit wrapped in try/catch: reverts with generic `E()` on failure

**NatSpec Accuracy:** NatSpec accurately describes "Cannot stake ETH reserved for player claims (claimablePool)." Security note is correct. The return value comment "stETH return value intentionally ignored: Lido mints 1:1 for ETH, validated by input checks" is accurate -- the empty try body `returns (uint256) {}` discards the return.

**Gas Flags:**
- The `ethBal <= reserve` and `amount > stakeable` checks are two separate conditions that could theoretically be combined, but they provide clearer error semantics and the gas difference is negligible. Informational.

**Verdict:** CORRECT

---

### `updateVrfCoordinatorAndSub(address newCoordinator, uint256 newSubId, bytes32 newKeyHash)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function updateVrfCoordinatorAndSub(address newCoordinator, uint256 newSubId, bytes32 newKeyHash) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `newCoordinator` (address): new VRF coordinator address; `newSubId` (uint256): new subscription ID; `newKeyHash` (bytes32): new key hash for gas lane |
| **Returns** | None |

**State Reads:**
- Delegated to AdvanceModule (reads `rngRequestTime`, `msg.sender`, `ContractAddresses.ADMIN`)

**State Writes:**
- Delegated to AdvanceModule (writes VRF coordinator, subscription ID, key hash in game storage)

**Callers:** Called by DegenerusAdmin contract.

**Callees:**
- `ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(IDegenerusGameAdvanceModule.updateVrfCoordinatorAndSub.selector, ...)` -- full logic in AdvanceModule
- `_revertDelegate(data)` -- bubble up errors on failure

**ETH Flow:** None.

**Invariants:**
- Access: ADMIN only (enforced in AdvanceModule)
- 3-day stall condition required (VRF must have been unresponsive for 3+ days)
- Recovery mechanism only -- not for routine changes
- Delegatecall preserves game storage context

**NatSpec Accuracy:** NatSpec accurately describes "Emergency VRF coordinator rotation after 3-day stall." Custom reverts (`VrfUpdateNotReady`, `E`) are documented. The 3-day security requirement is noted.

**Gas Flags:** None. Simple delegatecall dispatch.

**Verdict:** CORRECT

---

### `requestLootboxRng()` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function requestLootboxRng() external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | None |

**State Reads:**
- Delegated to AdvanceModule

**State Writes:**
- Delegated to AdvanceModule (VRF request state)

**Callers:** External -- callable by anyone (permissionless trigger).

**Callees:**
- `ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(IDegenerusGameAdvanceModule.requestLootboxRng.selector)` -- full logic in AdvanceModule
- `_revertDelegate(data)` -- bubble up errors on failure

**ETH Flow:** None directly. The AdvanceModule may interact with Chainlink VRF (LINK token for payment is handled by subscription).

**Invariants:**
- Permissionless: anyone can trigger, but AdvanceModule enforces preconditions (daily RNG consumed, request windows, pending value threshold)
- Delegatecall preserves game storage context

**NatSpec Accuracy:** NatSpec correctly states "Callable by anyone. Reverts if daily RNG has not been consumed, if request windows are locked, or if pending lootbox value is below threshold."

**Gas Flags:** None. Simple delegatecall dispatch.

**Verdict:** CORRECT

---

### `reverseFlip()` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function reverseFlip() external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | None |

**State Reads:**
- Delegated to AdvanceModule

**State Writes:**
- Delegated to AdvanceModule (nudge counter, BURNIE burn)

**Callers:** External -- callable by any player.

**Callees:**
- `ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(IDegenerusGameAdvanceModule.reverseFlip.selector)` -- full logic in AdvanceModule
- `_revertDelegate(data)` -- bubble up errors on failure

**ETH Flow:** None directly. The AdvanceModule burns BURNIE tokens from the caller.

**Invariants:**
- Cost scales +50% per queued nudge, resets after VRF fulfillment
- Only available when RNG is unlocked (before VRF request)
- Players influence but cannot predict the base VRF word

**NatSpec Accuracy:** NatSpec accurately describes the nudge mechanism: "+50% per queued nudge", "resets after fulfillment", "Only available while RNG is unlocked." The security note "Players cannot predict the base word, only influence it" is correct.

**Gas Flags:** None. Simple delegatecall dispatch.

**Verdict:** CORRECT

---

### `rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `requestId` (uint256): VRF request ID to match; `randomWords` (uint256[]): array containing the random word (expected length 1) |
| **Returns** | None |

**State Reads:**
- Delegated to AdvanceModule (reads `vrfRequestId`, VRF coordinator address, nudge counter)

**State Writes:**
- Delegated to AdvanceModule (writes `rngWordCurrent`, `rngWordByDay[dailyIdx]`, clears nudge state)

**Callers:** Called by Chainlink VRF Coordinator contract only (enforced in AdvanceModule).

**Callees:**
- `ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(IDegenerusGameAdvanceModule.rawFulfillRandomWords.selector, ...)` -- full logic in AdvanceModule
- `_revertDelegate(data)` -- bubble up errors on failure

**ETH Flow:** None.

**Invariants:**
- Access: VRF coordinator only (validated in AdvanceModule)
- Request ID must match pending request (prevents stale/mismatched fulfillments)
- Nudges applied to random word before storage (word += nudge count)
- Single random word expected (array length 1)
- Delegatecall preserves game storage context

**NatSpec Accuracy:** NatSpec accurately describes "Access: VRF coordinator only", "Validates requestId and coordinator address", "Applies any queued nudges before storing the word."

**Gas Flags:** None. Simple delegatecall dispatch.

**Verdict:** CORRECT

---

### `_transferSteth(address to, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _transferSteth(address to, uint256 amount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient of stETH; `amount` (uint256): stETH amount to transfer |
| **Returns** | None |

**State Reads:**
- None in game storage. External calls to stETH and DGNRS contracts.

**State Writes:**
- None in game storage. External stETH balance changes.

**Callers:**
- `_payoutWithStethFallback(address, uint256)` -- stETH portion of fallback payout
- `_payoutWithEthFallback(address, uint256)` -- stETH-first payout
- `adminSwapEthForStEth` does NOT use this -- it calls `steth.transfer` directly

**Callees:**
- `steth.approve(ContractAddresses.DGNRS, amount)` -- approve DGNRS to pull stETH (DGNRS path only)
- `dgnrs.depositSteth(amount)` -- deposit stETH into DGNRS reserves (DGNRS path only)
- `steth.transfer(to, amount)` -- direct stETH transfer (non-DGNRS path)

**ETH Flow:**
- **OUT:** stETH transferred from game to `to` (or deposited into DGNRS)
- Special case for DGNRS: approve + depositSteth pattern (DGNRS pulls stETH via transferFrom internally)

**Invariants:**
- Zero-amount guard: returns immediately if `amount == 0`
- DGNRS special path: uses approve + deposit pattern instead of direct transfer (DGNRS needs to track deposits internally)
- Non-DGNRS path: direct stETH.transfer with success check
- Transfer failure reverts with `E()`

**NatSpec Accuracy:** No NatSpec on private function. Code is self-documenting.

**Gas Flags:**
- Approve before deposit: the approval could theoretically be front-run, but since this is called from within game contract execution (not a user-facing approval flow), the approve + deposit are atomic within the transaction. Safe.

**Verdict:** CORRECT

---

### `_payoutWithStethFallback(address to, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _payoutWithStethFallback(address to, uint256 amount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): total wei to send |
| **Returns** | None |

**State Reads:**
- `address(this).balance` -- game's ETH balance (read twice: initial and retry)
- `steth.balanceOf(address(this))` -- game's stETH balance

**State Writes:**
- None in game storage. External balance changes via ETH transfer and stETH transfer.

**Callers:** Called by jackpot payout, claim, and distribution functions throughout DegenerusGame and its modules (via delegatecall).

**Callees:**
- `payable(to).call{value: ethSend}("")` -- ETH transfer (low-level call)
- `_transferSteth(to, stSend)` -- stETH transfer for remainder
- `payable(to).call{value: leftover}("")` -- ETH retry for any final remainder

**ETH Flow:**
- **Priority:** ETH first, then stETH for remainder, then ETH retry for leftover
- **Phase 1:** Send up to `min(amount, ethBal)` as ETH
- **Phase 2:** Send up to `min(remaining, stBal)` as stETH
- **Phase 3:** If still remaining after stETH, retry with refreshed ETH balance

**Invariants:**
- Zero-amount guard: returns immediately if `amount == 0`
- ETH transfer uses low-level `.call{value:}("")` -- safe pattern (no gas limit, returns success boolean)
- ETH transfer failure reverts immediately (`revert E()`)
- stETH fallback: sends whatever stETH is available, capped at remainder
- Retry mechanism: covers edge case where stETH was short but new ETH arrived (e.g., from stETH transfer to DGNRS which may send ETH back, or reentrancy-safe scenarios)
- Final retry: reverts if refreshed ETH balance < leftover (`revert E()`)
- Total payout exactly equals `amount` (ETH + stETH + retry ETH = amount)

**NatSpec Accuracy:** NatSpec says "Send ETH first, then stETH for remainder" -- the actual function name says "StethFallback" meaning stETH is the fallback, ETH is preferred. NatSpec and implementation match. The "Includes retry logic if stETH is short but ETH arrives" note is accurate.

**Gas Flags:**
- Three-phase payout adds gas compared to a simple transfer, but the fallback logic is necessary for robustness. No optimization opportunity without sacrificing correctness.
- `address(this).balance` read twice (initial + retry). The retry read is necessary since ETH balance may have changed after stETH operations.

**Verdict:** CORRECT

---

### `_payoutWithEthFallback(address to, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _payoutWithEthFallback(address to, uint256 amount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): total wei to send |
| **Returns** | None |

**State Reads:**
- `steth.balanceOf(address(this))` -- game's stETH balance
- `address(this).balance` -- game's ETH balance (for fallback)

**State Writes:**
- None in game storage. External balance changes via stETH and ETH transfers.

**Callers:** Called by vault/DGNRS reserve claims and admin-related payout paths where stETH is preferred.

**Callees:**
- `_transferSteth(to, stSend)` -- stETH transfer (primary)
- `payable(to).call{value: remaining}("")` -- ETH transfer for remainder (fallback)

**ETH Flow:**
- **Priority:** stETH first, then ETH for remainder
- **Phase 1:** Send up to `min(amount, stBal)` as stETH
- **Phase 2:** Send remaining as ETH (reverts if insufficient)

**Invariants:**
- Zero-amount guard: returns immediately if `amount == 0`
- stETH transfer uses `_transferSteth` (handles DGNRS special case)
- ETH fallback: reverts if ETH balance < remaining (`revert E()`)
- ETH transfer failure reverts (`revert E()`)
- Simpler than `_payoutWithStethFallback` -- no retry mechanism (two phases only)
- Total payout exactly equals `amount` (stETH + ETH = amount)

**NatSpec Accuracy:** NatSpec says "Send stETH first, then ETH for remainder. Used for vault/DGNRS reserve claims (stETH preferred)." Matches implementation.

**Gas Flags:** None. Two-phase payout is minimal.

**Verdict:** CORRECT

---

## ETH Mutation Path Map

| Path | Source | Destination | Trigger | Function |
|------|--------|-------------|---------|----------|
| Admin swap (ETH in) | ADMIN contract | address(this).balance | Admin action | `adminSwapEthForStEth` |
| Admin swap (stETH out) | stETH balance (game) | recipient address | Admin action | `adminSwapEthForStEth` |
| Admin stake | address(this).balance | Lido stETH contract | Admin action | `adminStakeEthForStEth` |
| Staked stETH return | Lido stETH contract | stETH balance (game) | Admin action (1:1 mint) | `adminStakeEthForStEth` |
| ETH payout (primary) | address(this).balance | player address | claim/payout | `_payoutWithStethFallback` |
| stETH payout (fallback) | stETH balance (game) | player address | claim/payout (ETH insufficient) | `_payoutWithStethFallback` |
| ETH retry payout | address(this).balance | player address | claim/payout (stETH also insufficient) | `_payoutWithStethFallback` |
| stETH payout (primary) | stETH balance (game) | player address / DGNRS | reserve claim | `_payoutWithEthFallback` |
| ETH payout (fallback) | address(this).balance | player address | reserve claim (stETH insufficient) | `_payoutWithEthFallback` |
| stETH to DGNRS | stETH balance (game) | DGNRS contract (via approve+deposit) | payout to DGNRS | `_transferSteth` |
| stETH direct transfer | stETH balance (game) | recipient address | payout to non-DGNRS | `_transferSteth` |

### Payout Strategy Summary

| Function | Primary Asset | Fallback | Use Case |
|----------|--------------|----------|----------|
| `_payoutWithStethFallback` | ETH | stETH, then ETH retry | Player claims (ETH preferred by players) |
| `_payoutWithEthFallback` | stETH | ETH | Vault/DGNRS reserves (stETH preferred for yield) |
| `_transferSteth` | stETH | None (reverts) | Low-level stETH transfer primitive |

## Findings Summary

### Severity Counts

| Severity | Count |
|----------|-------|
| **BUG** | 0 |
| **CONCERN** | 0 |
| **GAS (Informational)** | 3 |
| **NatSpec (Informational)** | 0 |

### Gas Informationals

1. **Event emitted on no-op state changes** (setDecimatorAutoRebuy, _setAutoRebuy): Events fire even when the toggle state doesn't change. This is consistent across the codebase and reflects user intent rather than state mutation. Harmless.

2. **Dual balance checks in adminStakeEthForStEth**: `ethBal < amount` and `amount > stakeable` are two separate checks that could be combined to `amount > ethBal - reserve` with a single underflow guard. Gas difference is negligible and current form is more readable.

3. **Code duplication between `_hasAnyLazyPass` and `hasActiveLazyPass`**: Identical logic in private and external versions. Deliberate optimization -- avoids extra internal call overhead for trivial (4-line) logic.

### Security Verification

| Check | Status |
|-------|--------|
| Admin access control (ADMIN-only) | VERIFIED on adminSwapEthForStEth, adminStakeEthForStEth, updateVrfCoordinatorAndSub |
| Cross-contract access control (COIN/COINFLIP) | VERIFIED on deactivateAfKingFromCoin (COIN or COINFLIP), syncAfKingLazyPassFromCoin (COINFLIP only) |
| VRF coordinator access control | VERIFIED (enforced in AdvanceModule via delegatecall) |
| claimablePool protection | VERIFIED in adminStakeEthForStEth (cannot stake reserved ETH) |
| Pull pattern compliance | VERIFIED: payout helpers are called by claim functions, not push-based |
| CEI compliance | VERIFIED: all state mutations precede external calls in payout paths |
| Value-neutral admin swaps | VERIFIED: msg.value must equal amount in adminSwapEthForStEth |
| RNG lock guards | VERIFIED on _setAutoRebuy, _setAutoRebuyTakeProfit, setDecimatorAutoRebuy, _setAfKingMode |
| AfKing lock period enforcement | VERIFIED: AFKING_LOCK_LEVELS=5, bypassed only for level-0 activation (intentional) and passive expiry via syncAfKingLazyPassFromCoin |

### Key Observations

1. **No fund extraction possible via admin functions**: `adminSwapEthForStEth` requires exact ETH input matching stETH output. `adminStakeEthForStEth` converts ETH to stETH 1:1 via Lido. Neither function can extract value.

2. **AfKing lock bypass at level 0 is intentional**: Players activating afKing at level 0 can deactivate immediately since `afKingActivatedLevel == 0` skips the lock check. This allows experimentation before the game starts.

3. **Payout helpers are robust**: The three-phase fallback in `_payoutWithStethFallback` (ETH -> stETH -> ETH retry) handles edge cases where balances change during execution.

4. **VRF functions are thin dispatchers**: `updateVrfCoordinatorAndSub`, `requestLootboxRng`, `reverseFlip`, and `rawFulfillRandomWords` all delegate to the AdvanceModule. Access control and logic are fully in the module (audited in Phase 50).

### Total Functions Audited: 26

| Category | Count | Verdicts |
|----------|-------|----------|
| Auto-rebuy settings | 8 | 8 CORRECT |
| AfKing mode | 9 | 9 CORRECT |
| Admin operations | 2 | 2 CORRECT |
| VRF lifecycle | 4 | 4 CORRECT |
| Payout helpers | 3 | 3 CORRECT |
| **Total** | **26** | **26 CORRECT** |
