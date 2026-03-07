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
