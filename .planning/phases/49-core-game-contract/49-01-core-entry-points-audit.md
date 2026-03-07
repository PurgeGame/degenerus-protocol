# DegenerusGame.sol -- Core Entry Points Audit

**Contract:** DegenerusGame
**File:** contracts/DegenerusGame.sol
**Lines:** 2810
**Solidity:** 0.8.34
**Inherits:** DegenerusGameMintStreakUtils -> DegenerusGameStorage
**Audit date:** 2026-03-07

## Summary

Core entry point functions that drive game state, record player activity, configure VRF, and manage operator approvals. `advanceGame()` is the primary state machine driver that delegates to AdvanceModule via delegatecall. `recordMint()` handles all prize pool ETH flow from purchases. Supporting functions manage coinflip tracking, quest streaks, DGNRS bounties, operator approvals, day index views, and lootbox RNG configuration.

---

## Function Audit

### `advanceGame()` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function advanceGame() external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | (none) |
| **Returns** | (none) |

**State Reads:** None directly -- all reads occur within the AdvanceModule delegatecall context.

**State Writes:** None directly -- all writes occur within the AdvanceModule delegatecall context.

**Callers:** Anyone (external). Tiered gating enforced inside AdvanceModule: deity pass holders bypass always; anyone after 30+ min; pass holders after 15+ min; DGVE majority holders always.

**Callees:**
- `ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(IDegenerusGameAdvanceModule.advanceGame.selector)` -- delegates entire state machine tick to AdvanceModule
- `_revertDelegate(data)` -- on delegatecall failure, bubbles up revert reason

**ETH Flow:** None directly. The AdvanceModule (executing in this contract's context) drives all ETH pool movements: `futurePrizePool -> nextPrizePool -> currentPrizePool -> claimableWinnings`, Lido staking, jackpot distributions, deity refunds, etc.

**Invariants:**
- `jackpotPhaseFlag` transitions: `false(PURCHASE) <-> true(JACKPOT)`; `gameOver` is terminal
- Delegatecall executes in Game's storage context -- slot alignment guaranteed by shared DegenerusGameStorage inheritance
- RNG lock prevents manipulation during VRF callback window

**NatSpec Accuracy:** ACCURATE. NatSpec accurately describes: 2.5yr deploy timeout, 365-day inactivity guard, tiered daily gate, RNG gating, batched processing, BURNIE bounty during jackpot phase.

**Gas Flags:** None. The function is a thin delegatecall wrapper with no redundant operations.

**Verdict:** CORRECT

---

### `wireVrf(address, uint256, bytes32)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function wireVrf(address coordinator_, uint256 subId, bytes32 keyHash_) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `coordinator_` (address): VRF coordinator address; `subId` (uint256): VRF subscription ID; `keyHash_` (bytes32): VRF gas lane key hash |
| **Returns** | (none) |

**State Reads:** None directly -- access control checked in AdvanceModule.

**State Writes:** None directly -- VRF config written in AdvanceModule context: `coordinator`, `vrfSubId`, `keyHash` storage variables.

**Callers:** ADMIN contract only (enforced inside AdvanceModule with `msg.sender != ContractAddresses.ADMIN` check).

**Callees:**
- `ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(IDegenerusGameAdvanceModule.wireVrf.selector, coordinator_, subId, keyHash_)` -- sets VRF configuration
- `_revertDelegate(data)` -- on failure

**ETH Flow:** None.

**Invariants:**
- VRF config can be set or rotated (not one-time-only despite NatSpec suggesting "one-time") via `updateVrfCoordinatorAndSub`
- Only ADMIN can call

**NatSpec Accuracy:** MINOR INACCURACY. NatSpec says "One-time VRF setup" but the function "Overwrites any existing config on each call" per its own dev comment. The AdvanceModule also exposes `updateVrfCoordinatorAndSub` for emergency rotation. Not a functional concern -- the "one-time" label refers to the expected deployment flow, not a technical enforcement.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `recordMint(address, uint24, uint256, uint32, MintPaymentKind)` [external payable]

| Field | Value |
|-------|-------|
| **Signature** | `function recordMint(address player, uint24 lvl, uint256 costWei, uint32 mintUnits, MintPaymentKind payKind) external payable returns (uint256 coinReward, uint256 newClaimableBalance)` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | `player` (address): mint recipient; `lvl` (uint24): current level; `costWei` (uint256): total cost in wei; `mintUnits` (uint32): purchase units; `payKind` (MintPaymentKind): payment method |
| **Returns** | `coinReward` (uint256): BURNIE reward; `newClaimableBalance` (uint256): remaining claimable balance |

**State Reads:**
- `claimableWinnings[player]` (in `_processMintPayment`, for Claimable/Combined pay kinds)
- `earlybirdDgnrsPoolStart`, `earlybirdEthIn`, `EARLYBIRD_END_LEVEL`, `EARLYBIRD_TARGET_ETH` (in `_awardEarlybirdDgnrs`)
- `mintPacked_[player]` (in `_recordMintDataModule` via MintModule delegatecall)

**State Writes:**
- `futurePrizePool += futureShare` (10% of prizeContribution via `PURCHASE_TO_FUTURE_BPS = 1000`)
- `nextPrizePool += nextShare` (remaining 90% of prizeContribution)
- `claimableWinnings[player]` (deducted for Claimable/Combined payments)
- `claimablePool -= claimableUsed` (global claimable accounting)
- `earlybirdDgnrsPoolStart`, `earlybirdEthIn` (in `_awardEarlybirdDgnrs`)
- Various fields in `mintPacked_[player]` (via MintModule delegatecall in `_recordMintDataModule`)

**Callers:** Self-call only (`msg.sender != address(this)` check). Called from delegate modules executing in this contract's context (e.g., MintModule.purchase delegatecalls back to Game.recordMint).

**Callees:**
- `_processMintPayment(player, costWei, payKind)` -- handles ETH/claimable payment validation and deduction
- `_recordMintDataModule(player, lvl, mintUnits)` -- delegatecalls to `GAME_MINT_MODULE.recordMintData` for mint history and BURNIE reward calculation
- `_awardEarlybirdDgnrs(player, earlybirdEth, lvl)` -- awards early DGNRS tokens via DGNRS.transferFromPool

**ETH Flow:**
| Path | Source | Destination | Condition |
|------|--------|-------------|-----------|
| Direct ETH purchase | `msg.value` | `nextPrizePool` (90%) + `futurePrizePool` (10%) | `payKind == DirectEth` |
| Claimable purchase | `claimableWinnings[player]` | `nextPrizePool` (90%) + `futurePrizePool` (10%) | `payKind == Claimable` |
| Combined purchase | `msg.value` + `claimableWinnings[player]` | `nextPrizePool` (90%) + `futurePrizePool` (10%) | `payKind == Combined` |

Prize pool split: `PURCHASE_TO_FUTURE_BPS = 1000` (10% to future, 90% to next).

**Revert Conditions:**
- `msg.sender != address(this)` -- not a self-call
- `DirectEth`: `msg.value < amount` -- insufficient ETH
- `Claimable`: `msg.value != 0` -- ETH sent with claimable; `claimable <= amount` -- insufficient balance (preserves 1 wei sentinel)
- `Combined`: `msg.value > amount` -- overpay not allowed; `remaining != 0` after claimable deduction -- insufficient total
- Invalid payKind enum value

**Invariants:**
- `claimablePool` is decremented by exactly `claimableUsed`, matching the deduction from `claimableWinnings[player]`
- 1 wei sentinel preserved in claimable balance (prevents cold->warm SSTORE gas cost)
- `prizeContribution = msg.value + claimableUsed` always equals `costWei` (full coverage required)
- ETH conservation: `futureShare + nextShare == prizeContribution` (no rounding loss since `futureShare = (prizeContribution * 1000) / 10000`)

**NatSpec Accuracy:** ACCURATE. Documents all three payment modes, self-call restriction, prize pool split, and overage handling.

**Gas Flags:**
- INFO: The `if (futureShare != 0)` and `if (nextShare != 0)` zero-checks are defensive (futureShare is 0 only when prizeContribution is 0, which is already guarded by `if (prizeContribution != 0)`). No gas waste since the check is cheap relative to SSTORE.
- INFO: `earlybirdEth` calculation differs between DirectEth and Combined -- in DirectEth, `min(costWei, msg.value)` is used (capping at costWei even if overpaid), while Combined uses `msg.value` directly. This is correct since Combined already enforces `msg.value <= amount`.

**Verdict:** CORRECT

---

### `recordCoinflipDeposit(uint256)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function recordCoinflipDeposit(uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `amount` (uint256): wei amount deposited to coinflip |
| **Returns** | (none) |

**State Reads:**
- `jackpotPhaseFlag` -- checks if in purchase phase
- `lastPurchaseDay` -- checks if last purchase day flag is set

**State Writes:**
- `lastPurchaseDayFlipTotal += amount` -- only when in purchase phase AND last purchase day

**Callers:** COIN or COINFLIP contract only (access-controlled by `msg.sender` check against `ContractAddresses.COIN` and `ContractAddresses.COINFLIP`).

**Callees:** None.

**ETH Flow:** None. This function only tracks accounting; no ETH moves.

**Invariants:**
- Only accumulates during purchase phase (`!jackpotPhaseFlag`) AND on last purchase day (`lastPurchaseDay == true`)
- `lastPurchaseDayFlipTotal` resets on level transition (handled by AdvanceModule)

**NatSpec Accuracy:** ACCURATE. States "Track coinflip deposits for payout tuning on last purchase day" and correctly identifies COIN/COINFLIP as callers.

**Gas Flags:** None. Simple conditional accumulator.

**Verdict:** CORRECT

---

### `recordMintQuestStreak(address)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function recordMintQuestStreak(address player) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player who completed the quest |
| **Returns** | (none) |

**State Reads:**
- `jackpotPhaseFlag`, `level` -- via `_activeTicketLevel()` to compute current mint level
- `mintPacked_[player]` -- via `_recordMintStreakForLevel` to check last completed level and current streak

**State Writes:**
- `mintPacked_[player]` -- via `_recordMintStreakForLevel`: updates `MINT_STREAK_LAST_COMPLETED_SHIFT` (24 bits at position 160) and `LEVEL_STREAK_SHIFT` (24 bits at position 48) within the packed mint data

**Callers:** COIN contract only (`msg.sender != ContractAddresses.COIN` check).

**Callees:**
- `_activeTicketLevel()` -- returns `jackpotPhaseFlag ? level : level + 1`
- `_recordMintStreakForLevel(player, mintLevel)` -- inherited from DegenerusGameMintStreakUtils; records streak completion for the level, incrementing streak if consecutive, resetting to 1 if gap

**ETH Flow:** None.

**Invariants:**
- Idempotent per level: if `lastCompleted == mintLevel`, no-op
- Streak increments only if `lastCompleted + 1 == mintLevel` (consecutive levels)
- Streak capped at `type(uint24).max` (16,777,215)
- Player address(0) is a no-op (checked in `_recordMintStreakForLevel`)

**NatSpec Accuracy:** ACCURATE. "Record mint streak completion after a 1x price ETH quest completes" matches behavior.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `payCoinflipBountyDgnrs(address)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function payCoinflipBountyDgnrs(address player) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): recipient of DGNRS bounty |
| **Returns** | (none) |

**State Reads:** None directly (reads from external DGNRS contract).

**State Writes:** None directly (writes occur in DGNRS contract via `transferFromPool`).

**Callers:** COIN or COINFLIP contract only (access-controlled by `msg.sender` check).

**Callees:**
- `dgnrs.poolBalance(IDegenerusStonk.Pool.Reward)` -- reads Reward pool balance from DGNRS contract
- `dgnrs.transferFromPool(IDegenerusStonk.Pool.Reward, player, payout)` -- transfers DGNRS tokens from Reward pool to player

**ETH Flow:** None. This is a DGNRS token transfer, not ETH.

**Invariants:**
- Payout = `(poolBalance * COINFLIP_BOUNTY_DGNRS_BPS) / 10_000` where `COINFLIP_BOUNTY_DGNRS_BPS = 50` (0.5% of Reward pool)
- Zero-address player -> early return (no-op)
- Zero pool balance -> early return
- Zero payout (rounding) -> early return

**NatSpec Accuracy:** ACCURATE. "Pay DGNRS bounty for the biggest flip record holder" matches; access control documented.

**Gas Flags:** None. Three sequential early-return guards are efficient.

**Verdict:** CORRECT

---

### `setOperatorApproval(address, bool)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function setOperatorApproval(address operator, bool approved) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `operator` (address): operator to approve/revoke; `approved` (bool): true to approve, false to revoke |
| **Returns** | (none) |

**State Reads:** None.

**State Writes:**
- `operatorApprovals[msg.sender][operator] = approved`

**Callers:** Anyone (external). The caller becomes the `owner` (msg.sender).

**Callees:** None (emits `OperatorApproval` event only).

**ETH Flow:** None.

**Invariants:**
- Zero-address operator reverts with `E()` (prevents accidental approvals to address(0))
- Approval is per-owner per-operator (nested mapping)
- Emits `OperatorApproval(owner, operator, approved)` on every call (including redundant approvals)

**NatSpec Accuracy:** ACCURATE.

**Gas Flags:** INFO: No check for redundant approval (setting already-true to true emits event and writes same value). This is intentional -- the gas cost of a same-value SSTORE (warm, no change) is minimal (100 gas).

**Verdict:** CORRECT

---

### `isOperatorApproved(address, address)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function isOperatorApproved(address owner, address operator) external view returns (bool approved)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `owner` (address): player who granted approval; `operator` (address): operator to check |
| **Returns** | `approved` (bool): true if operator is approved for owner |

**State Reads:**
- `operatorApprovals[owner][operator]`

**State Writes:** None.

**Callers:** Anyone (external view).

**Callees:** None.

**ETH Flow:** None.

**Invariants:** Simple mapping lookup, no validation on inputs.

**NatSpec Accuracy:** ACCURATE.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_requireApproved(address)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _requireApproved(address player) private view` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `player` (address): player whose approval is being checked |
| **Returns** | (none) |

**State Reads:**
- `operatorApprovals[player][msg.sender]`

**State Writes:** None.

**Callers:**
- `_resolvePlayer(address)` -- when `player != msg.sender`

**Callees:** None.

**ETH Flow:** None.

**Revert Conditions:**
- `NotApproved()` -- if `msg.sender != player` AND `operatorApprovals[player][msg.sender] == false`

**Invariants:**
- msg.sender is always approved for themselves (short-circuited by `msg.sender != player` check)

**NatSpec Accuracy:** No NatSpec (private function). Behavior is self-documenting.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_resolvePlayer(address)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _resolvePlayer(address player) private view returns (address resolved)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `player` (address): player address to resolve (address(0) = use msg.sender) |
| **Returns** | `resolved` (address): the resolved player address |

**State Reads:**
- `operatorApprovals[player][msg.sender]` -- via `_requireApproved` when `player != msg.sender`

**State Writes:** None.

**Callers:**
- `purchase()`, `purchaseCoin()`, `purchaseBurnieLootbox()`, `purchaseWhaleBundle()`, `purchaseLazyPass()`, `purchaseDeityPass()`, `openLootBox()`, `openBurnieLootBox()`, `claimWinnings()`, `placeFullTicketBets()`, `resolveDegeneretteBets()`, and other external entry points that accept a `buyer`/`player` parameter

**Callees:**
- `_requireApproved(player)` -- checks operator approval when `player != address(0)` and `player != msg.sender`

**ETH Flow:** None.

**Resolution Logic:**
1. `player == address(0)` -> returns `msg.sender` (self-action)
2. `player != msg.sender` -> checks operator approval via `_requireApproved`, returns `player`
3. `player == msg.sender` -> returns `player` directly (no approval check needed)

**Invariants:**
- Return value is never `address(0)` (mapped to `msg.sender`)
- Non-self callers must have explicit operator approval

**NatSpec Accuracy:** No NatSpec (private function). Behavior clear from code.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `currentDayView()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function currentDayView() external view returns (uint48)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | (none) |
| **Returns** | `uint48`: current day index |

**State Reads:**
- None directly -- `_simulatedDayIndex()` calls `GameTimeLib.currentDayIndex()` which computes from `block.timestamp` and `ContractAddresses.DEPLOY_DAY_BOUNDARY`

**State Writes:** None.

**Callers:** Anyone (external view).

**Callees:**
- `_simulatedDayIndex()` -> `GameTimeLib.currentDayIndex()` -- computes day index from current block timestamp and deploy boundary

**ETH Flow:** None.

**Invariants:** Returns monotonically increasing day index based on block timestamp.

**NatSpec Accuracy:** ACCURATE. Simple one-liner: "Current day index."

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `setLootboxRngThreshold(uint256)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function setLootboxRngThreshold(uint256 newThreshold) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `newThreshold` (uint256): new threshold in wei |
| **Returns** | (none) |

**State Reads:**
- `lootboxRngThreshold` (reads current value as `prev`)

**State Writes:**
- `lootboxRngThreshold = newThreshold` (only when `newThreshold != prev`)

**Callers:** ADMIN contract only (`msg.sender != ContractAddresses.ADMIN` check).

**Callees:** None (emits `LootboxRngThresholdUpdated` event).

**ETH Flow:** None.

**Revert Conditions:**
- `msg.sender != ContractAddresses.ADMIN` -- not admin
- `newThreshold == 0` -- zero threshold not allowed

**Invariants:**
- Threshold is always non-zero after any successful call
- When `newThreshold == prev`, emits event but does NOT write storage (gas optimization: avoids same-value SSTORE)
- Event always emitted, even for no-op case (consistent behavior for indexers)

**NatSpec Accuracy:** ACCURATE. Documents ADMIN-only access, non-zero requirement, and event emission.

**Gas Flags:** INFO: The `if (newThreshold == prev)` early-return path emits the event before returning, avoiding the SSTORE while still notifying indexers. This is an intentional gas optimization.

**Verdict:** CORRECT

---

## Delegatecall Dispatch Table

### `advanceGame()` Delegatecall Dispatch

| Entry Point | Target Module Constant | Selector | Interface |
|-------------|----------------------|----------|-----------|
| `advanceGame()` | `ContractAddresses.GAME_ADVANCE_MODULE` | `IDegenerusGameAdvanceModule.advanceGame.selector` | `IDegenerusGameAdvanceModule` |
| `wireVrf(...)` | `ContractAddresses.GAME_ADVANCE_MODULE` | `IDegenerusGameAdvanceModule.wireVrf.selector` | `IDegenerusGameAdvanceModule` |

### `recordMint()` Internal Delegatecall

| Internal Caller | Target Module Constant | Selector | Interface |
|-----------------|----------------------|----------|-----------|
| `_recordMintDataModule(...)` | `ContractAddresses.GAME_MINT_MODULE` | `IDegenerusGameMintModule.recordMintData.selector` | `IDegenerusGameMintModule` |

### Delegatecall Failure Handling

All delegatecall sites follow the same pattern:
```solidity
(bool ok, bytes memory data) = MODULE_ADDRESS.delegatecall(abi.encodeWithSelector(...));
if (!ok) _revertDelegate(data);
```

`_revertDelegate` bubbles up the original revert reason via assembly:
```solidity
function _revertDelegate(bytes memory reason) private pure {
    if (reason.length == 0) revert E();
    assembly ("memory-safe") {
        revert(add(32, reason), mload(reason))
    }
}
```

This preserves custom error selectors from modules (e.g., `RngLocked`, `RngNotReady`) so callers see the original error, not a generic `E()`.

---

## ETH Mutation Path Map

| Path | Source | Destination | Trigger | Function |
|------|--------|-------------|---------|----------|
| Direct ETH purchase (90%) | `msg.value` | `nextPrizePool` | DirectEth or Combined mint | `recordMint -> _processMintPayment` |
| Direct ETH purchase (10%) | `msg.value` | `futurePrizePool` | DirectEth or Combined mint | `recordMint -> _processMintPayment` |
| Claimable purchase (90%) | `claimableWinnings[player]` | `nextPrizePool` (virtual) | Claimable or Combined mint | `recordMint -> _processMintPayment` |
| Claimable purchase (10%) | `claimableWinnings[player]` | `futurePrizePool` (virtual) | Claimable or Combined mint | `recordMint -> _processMintPayment` |
| Claimable pool accounting | `claimablePool` | (decremented) | Claimable deduction | `recordMint -> _processMintPayment` |
| Earlybird DGNRS (token, not ETH) | DGNRS Earlybird pool | `buyer` | ETH purchase at level < 3 | `recordMint -> _awardEarlybirdDgnrs` |
| Coinflip bounty (token, not ETH) | DGNRS Reward pool | `player` | Biggest flip record | `payCoinflipBountyDgnrs` |

**Notes:**
- `recordCoinflipDeposit` does NOT move ETH; it only tracks `lastPurchaseDayFlipTotal` for payout tuning.
- `recordMintQuestStreak` does NOT move ETH; it updates mint streak data in `mintPacked_`.
- `setOperatorApproval`, `isOperatorApproved`, `_requireApproved`, `_resolvePlayer`, `currentDayView`, `setLootboxRngThreshold` move no ETH or tokens.
- `advanceGame` and `wireVrf` are thin delegatecall wrappers; ETH flow within AdvanceModule is documented in Phase 50 (AdvanceModule audit).

### Prize Pool Split Formula

```
prizeContribution = costWei (total payment amount)
futureShare = (prizeContribution * 1000) / 10_000  = 10%
nextShare   = prizeContribution - futureShare       = 90%

futurePrizePool += futureShare
nextPrizePool   += nextShare
```

Conservation: `futureShare + nextShare == prizeContribution` (no rounding loss since 1000 divides 10000 evenly for any integer input).

### Claimable Payment Flow

```
claimableWinnings[player] -= claimableUsed
claimablePool             -= claimableUsed   (global accounting)
prizeContribution         += claimableUsed   (re-enters prize pool split)
```

The 1-wei sentinel pattern (`claimable > amount` for pure Claimable, `claimable > 1` for Combined) prevents cold-to-warm SSTORE transitions (2100 -> 100 gas savings on subsequent reads/writes).

---

## Findings Summary

| Severity | Count | Details |
|----------|-------|---------|
| BUG | 0 | None found |
| CONCERN | 0 | None found |
| GAS | 0 | None (3 INFO-level observations noted inline) |
| CORRECT | 12 | All 12 functions verified correct |

### INFO-Level Observations

1. **`recordMint` zero-checks on futureShare/nextShare:** Defensive but unnecessary when `prizeContribution != 0` already guards. No gas impact.
2. **`setOperatorApproval` redundant write:** No same-value check before SSTORE. Minimal gas impact (warm SSTORE at 100 gas).
3. **`setLootboxRngThreshold` event-before-return:** Intentional optimization -- emits event for same-value case without SSTORE.

### NatSpec Observations

1. **`wireVrf`:** NatSpec header says "One-time VRF setup" but dev comment says "Overwrites any existing config on each call." Not a bug -- refers to expected deployment flow, not a technical constraint.

---

## Access Control Summary

| Function | Access | Enforced By |
|----------|--------|-------------|
| `advanceGame()` | Anyone (gated inside module) | AdvanceModule internal checks |
| `wireVrf(...)` | ADMIN only | AdvanceModule: `msg.sender != ADMIN` |
| `recordMint(...)` | Self-call only | `msg.sender != address(this)` |
| `recordCoinflipDeposit(...)` | COIN or COINFLIP | `msg.sender` check |
| `recordMintQuestStreak(...)` | COIN only | `msg.sender != COIN` |
| `payCoinflipBountyDgnrs(...)` | COIN or COINFLIP | `msg.sender` check |
| `setOperatorApproval(...)` | Anyone (self-approves) | msg.sender is owner |
| `isOperatorApproved(...)` | Anyone (view) | N/A |
| `currentDayView()` | Anyone (view) | N/A |
| `setLootboxRngThreshold(...)` | ADMIN only | `msg.sender != ADMIN` |
