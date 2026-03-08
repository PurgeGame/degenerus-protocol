# ECON-07: AfKing Mode Transition Audit

## Objective

Audit afKing mode transitions for double-spend or double-credit windows. AfKing mode enables enhanced auto-rebuy behavior with different recycling rates (1.6% base vs 1% standard). This analysis verifies that toggling afKing mode cannot create windows where a player receives both the enhanced and standard-mode benefits, or where pending coinflip state is handled inconsistently across the mode transition.

## Source Files Audited

| File | Lines | Function |
|------|-------|----------|
| `contracts/DegenerusGame.sol` | 1637-1686 | `setAfKingMode`, `_setAfKingMode` |
| `contracts/DegenerusGame.sol` | 1726-1736 | `deactivateAfKingFromCoin` |
| `contracts/DegenerusGame.sol` | 1738-1757 | `syncAfKingLazyPassFromCoin` |
| `contracts/DegenerusGame.sol` | 1759-1771 | `_deactivateAfKing` |
| `contracts/DegenerusGame.sol` | 1688-1696 | `_hasAnyLazyPass` |
| `contracts/DegenerusGame.sol` | 1572-1582 | `_setAutoRebuy` |
| `contracts/DegenerusGame.sol` | 1584-1598 | `_setAutoRebuyTakeProfit` |
| `contracts/BurnieCoinflip.sol` | 221-228 | `settleFlipModeChange` |
| `contracts/BurnieCoinflip.sol` | 430-619 | `_claimCoinflipsInternal` |
| `contracts/BurnieCoinflip.sol` | 692-765 | `setCoinflipAutoRebuy`, `_setCoinflipAutoRebuy` |
| `contracts/BurnieCoinflip.sol` | 1031-1072 | `_recyclingBonus`, `_afKingRecyclingBonus`, `_afKingDeityBonusHalfBpsWithLevel` |
| `contracts/storage/DegenerusGameStorage.sol` | 764-773 | `AutoRebuyState` struct |

---

## 1. Activation Path Trace

### Function: `setAfKingMode(player, true, ethTakeProfit, coinTakeProfit)`

**Execution flow (DegenerusGame.sol lines 1637-1686):**

```
setAfKingMode(player, true, ethTP, coinTP)
  1. player = _resolvePlayer(player)            // address normalization
  2. _setAfKingMode(player, true, ethTP, coinTP)
     a. if (rngLockedFlag) revert RngLocked()   // GUARD 1: blocks during VRF
     b. if (!_hasAnyLazyPass(player)) revert E() // GUARD 2: lazy pass required
     c. Clamp ethTakeProfit >= AFKING_KEEP_MIN_ETH (5 ETH) if non-zero
     d. Clamp coinTakeProfit >= AFKING_KEEP_MIN_COIN (20000 BURNIE) if non-zero
     e. If !autoRebuyEnabled: set autoRebuyEnabled = true, emit
     f. If takeProfit changed: set takeProfit, emit
     g. coinflip.setCoinflipAutoRebuy(player, true, adjustedCoinKeep) // EXTERNAL CALL 1
     h. If !afKingMode (first activation or re-activation):
        i.  coinflip.settleFlipModeChange(player) // EXTERNAL CALL 2 - settle old state
        ii. state.afKingMode = true               // mode flag SET after settlement
        iii. state.afKingActivatedLevel = level    // lock anchor SET
        iv. emit AfKingModeToggled(player, true)
```

### Guard Analysis

| Guard | Variable | Location | Purpose |
|-------|----------|----------|---------|
| **GUARD 1** | `rngLockedFlag` | Line 1653 | Prevents mode changes during VRF processing |
| **GUARD 2** | `_hasAnyLazyPass` | Line 1658 | Requires lazy pass (frozenUntilLevel > level OR deityPassCount != 0) |

### Ordering Analysis

The critical ordering is at step (h): `settleFlipModeChange` is called BEFORE `afKingMode = true`. This means:

1. `settleFlipModeChange` calls `_claimCoinflipsInternal(player, false)` (BurnieCoinflip line 223)
2. `_claimCoinflipsInternal` calls `game.syncAfKingLazyPassFromCoin(player)` as its first operation (line 436)
3. `syncAfKingLazyPassFromCoin` reads `state.afKingMode` -- which is still `false` at this point
4. So `syncAfKingLazyPassFromCoin` returns `false`, and `_claimCoinflipsInternal` processes all days with `afKingActive = false`
5. All pending coinflip days are settled at the **standard** recycling rate (1%)
6. After settlement returns, `afKingMode` is set to `true`

**Conclusion:** No inconsistency window. Old state is settled at the old rate before the new mode is enabled. The ordering is correct.

### Reentrancy Analysis of settleFlipModeChange

The call chain from `settleFlipModeChange` is:

```
DegenerusGame._setAfKingMode (caller)
  -> BurnieCoinflip.settleFlipModeChange(player) [EXTERNAL CALL]
    -> BurnieCoinflip._claimCoinflipsInternal(player, false) [INTERNAL]
      -> game.syncAfKingLazyPassFromCoin(player) [CALLBACK to DegenerusGame]
      -> jackpots.recordBafFlip(player, ...) [EXTERNAL to Jackpots - if winnings exist]
      -> wwxrp.mintPrize(player, ...) [EXTERNAL to WWXRP - if losses exist]
```

**Callback to DegenerusGame:** `syncAfKingLazyPassFromCoin` is called during settlement. It only reads/writes `afKingMode` and `afKingActivatedLevel`. At this point `afKingMode` is still `false` (set after settlement returns), so the sync returns `false` immediately without modifying state. No reentrancy risk.

**External calls to Jackpots/WWXRP:** These are protocol-owned contracts, not arbitrary external addresses. They cannot call back into `setAfKingMode` because they are not the player. Even if they could, the `_resolvePlayer` call at the top requires `msg.sender` to match. No reentrancy vector.

**Note on `setCoinflipAutoRebuy` (step g):** This is called BEFORE `settleFlipModeChange` at step (h). Inside `_setCoinflipAutoRebuy`, if enabling auto-rebuy when it is already enabled (the non-strict path from Game), it calls `_claimCoinflipsInternal` and then updates `autoRebuyStop`. This means pending coinflips are processed with the current afKingMode (still `false` at this point), which is the correct old-mode behavior. The settlement at step (h.i) then settles any remaining days that might have been processed between steps (g) and (h). However, since `_claimCoinflipsInternal` advances `state.lastClaim`, the second call at step (h.i) would find `start >= latest` and return 0. This is correct -- the settlement is idempotent.

---

## 2. Deactivation Path Trace

### Function: `setAfKingMode(player, false, *, *)`

**Execution flow (DegenerusGame.sol lines 1647-1657, 1759-1771):**

```
_setAfKingMode(player, false, *, *)
  1. if (rngLockedFlag) revert RngLocked()   // GUARD 1: blocks during VRF
  2. _deactivateAfKing(player)
     a. if (!state.afKingMode) return            // no-op if already off
     b. activationLevel = state.afKingActivatedLevel
     c. if (activationLevel != 0):
        unlockLevel = activationLevel + AFKING_LOCK_LEVELS  // +5
        if (level < unlockLevel) revert AfKingLockActive()   // GUARD 3: 5-level lock
     d. coinflip.settleFlipModeChange(player)    // EXTERNAL CALL - settle afKing-rate state
     e. state.afKingMode = false                 // mode flag CLEARED after settlement
     f. state.afKingActivatedLevel = 0           // lock anchor reset
     g. emit AfKingModeToggled(player, false)
```

### Guard Analysis

| Guard | Variable | Condition | Purpose |
|-------|----------|-----------|---------|
| **GUARD 1** | `rngLockedFlag` | Must be false | Prevents mode changes during VRF processing |
| **GUARD 3** | 5-level lock | `level >= activationLevel + 5` | Prevents rapid toggling |

### Ordering Analysis

`settleFlipModeChange` is called at step (d) BEFORE `afKingMode = false` at step (e). This means:

1. `_claimCoinflipsInternal` runs with `afKingMode = true` (still set)
2. `syncAfKingLazyPassFromCoin` returns `true` (assuming lazy pass is still active)
3. All pending coinflip days are settled at the **afKing** recycling rate (1.6% base)
4. After settlement returns, `afKingMode` is set to `false`

**Conclusion:** Correct ordering. Pending state is settled at the mode that was active when those bets were placed. No inconsistency.

### autoRebuyEnabled After Deactivation

After deactivation, `autoRebuyEnabled` is **NOT changed**. Only `afKingMode` and `afKingActivatedLevel` are cleared. This is correct behavior: a player may want standard auto-rebuy (1% recycling) without afKing mode. The deactivation path correctly preserves the auto-rebuy state.

However, there is one indirect path: `_setAutoRebuy(player, false)` (line 1572) calls `_deactivateAfKing(player)` (line 1580). When auto-rebuy is disabled entirely, afKing is also disabled. This is correct -- afKing requires auto-rebuy to be enabled.

---

## 3. External Deactivation Hooks

### 3a. `deactivateAfKingFromCoin(player)` (Line 1726-1736)

```solidity
function deactivateAfKingFromCoin(address player) external {
    if (msg.sender != ContractAddresses.COIN &&
        msg.sender != ContractAddresses.COINFLIP) revert E();
    _deactivateAfKing(player);
}
```

**Access control:** Only COIN or COINFLIP contracts can call this. Not callable by arbitrary addresses.

**Settlement:** YES -- it calls `_deactivateAfKing(player)` which calls `coinflip.settleFlipModeChange(player)` BEFORE clearing the mode flag. Pending state is properly settled.

**5-level lock enforced:** YES -- `_deactivateAfKing` checks `activationLevel + AFKING_LOCK_LEVELS`. However, there is a notable edge case: when `activationLevel == 0`, the lock check is skipped entirely (line 1763: `if (activationLevel != 0)`). This is intentional -- `activationLevel = 0` means the player activated at level 0, and the check `level < 0 + 5` would revert at any level less than 5. But since `activationLevel` is stored as `uint24`, level 0 is a valid activation level. The code handles this by using `activationLevel != 0` as the guard, which means **activation at level 0 has NO lock period**.

**Finding ECON-07-F01 (INFORMATIONAL):** When afKing is activated at level 0, `afKingActivatedLevel = 0`, and `_deactivateAfKing` skips the lock check (`activationLevel != 0` is false). This means a player who activates afKing at level 0 can deactivate immediately without the 5-level lock. However, this is not exploitable:
- At level 0, no coinflip days have been processed yet (game hasn't started level progression)
- The recycling bonus applies to carry amounts, which are zero at game start
- No economic advantage can be extracted from toggling at level 0

### Callers of `deactivateAfKingFromCoin`:

| Caller | Location | Trigger |
|--------|----------|---------|
| `BurnieCoinflip._setCoinflipAutoRebuy` (disable path) | Line 759 | When coinflip auto-rebuy is disabled |
| `BurnieCoinflip._setCoinflipAutoRebuy` (enable path, low takeProfit) | Line 747 | When coinTakeProfit < AFKING_KEEP_MIN_COIN and non-zero |
| `BurnieCoinflip._setCoinflipAutoRebuyTakeProfit` | Line 785 | When takeProfit set below AFKING_KEEP_MIN_COIN and non-zero |

All paths correctly enforce settlement before deactivation via `_deactivateAfKing`.

### 3b. `syncAfKingLazyPassFromCoin(player)` (Line 1738-1757)

```solidity
function syncAfKingLazyPassFromCoin(address player) external returns (bool active) {
    if (msg.sender != ContractAddresses.COINFLIP) revert E();
    AutoRebuyState storage state = autoRebuyState[player];
    if (!state.afKingMode) return false;
    if (_hasAnyLazyPass(player)) return true;

    // Note: settle not called here - it's already being called by the coinflip
    // operation that triggered this sync
    state.afKingMode = false;
    state.afKingActivatedLevel = 0;
    emit AfKingModeToggled(player, false);
    return false;
}
```

**Access control:** Only COINFLIP contract.

**Settlement:** NO -- `settleFlipModeChange` is NOT called. The code comment explicitly states why: "settle not called here - it's already being called by the coinflip operation that triggered this sync."

**Justification:** This is correct. `syncAfKingLazyPassFromCoin` is called from inside `_claimCoinflipsInternal` (line 436), which IS the settlement function. The call chain is:

```
settleFlipModeChange(player)
  -> _claimCoinflipsInternal(player, false)
    -> game.syncAfKingLazyPassFromCoin(player)  // <-- HERE
    -> [processes all pending days using the afKingMode value returned]
```

So the sync happens at the START of settlement. If the lazy pass has expired, `syncAfKingLazyPassFromCoin` sets `afKingMode = false` and returns `false`. The subsequent day-processing loop in `_claimCoinflipsInternal` then processes with `afKingActive = false`, applying the standard 1% rate. This is correct -- the pass has expired, so the enhanced rate should not apply.

**5-level lock:** NOT enforced. This is intentional. When a lazy pass expires naturally (frozenUntilLevel <= level), the protocol should revoke afKing mode regardless of the lock period. The 5-level lock prevents voluntary toggling by the player; pass expiration is an involuntary system event.

**Can an expired lazy pass create an inconsistency?** No. The sync is called at the beginning of every `_claimCoinflipsInternal` invocation. The afKingMode flag is cleared atomically before any day-processing occurs. There is no window where some days are processed at afKing rate and others at standard rate within the same call due to a mid-processing expiration.

---

## 4. settleFlipModeChange Analysis

### Function: `BurnieCoinflip.settleFlipModeChange(player)` (Line 221-228)

```solidity
function settleFlipModeChange(address player) external onlyDegenerusGameContract {
    uint256 mintable = _claimCoinflipsInternal(player, false);
    if (mintable != 0) {
        PlayerCoinflipState storage state = playerState[player];
        state.claimableStored = uint128(uint256(state.claimableStored) + mintable);
    }
}
```

### What Does It Settle?

`_claimCoinflipsInternal(player, false)` processes all unclaimed coinflip days up to `flipsClaimableDay`:

1. Reads current afKingMode via `syncAfKingLazyPassFromCoin`
2. Iterates from `lastClaim + 1` through `flipsClaimableDay` (up to `windowDays` iterations)
3. For each resolved day: reads stake, applies win/loss logic, computes recycling bonus at current rate
4. Updates `lastClaim` pointer, `autoRebuyCarry`
5. Records BAF credit for winning days
6. Returns mintable amount (take-profit-reserved winnings)

The mintable amount is stored in `claimableStored` rather than minted immediately. This avoids token transfer during mode change, keeping the settlement pure state-accounting.

### External Calls Within Settlement

| Call | Target | When | Reentrancy Risk |
|------|--------|------|----------------|
| `game.syncAfKingLazyPassFromCoin(player)` | DegenerusGame | Always (line 436) | LOW -- only reads/writes afKingMode flags |
| `game.deityPassCountFor(player)` | DegenerusGame | When afKingActive (line 447) | NONE -- view function |
| `game.level()` | DegenerusGame | When deity pass exists (line 452) | NONE -- view function |
| `game.purchaseInfo()` | DegenerusGame | When winnings exist (line 586) | NONE -- view function |
| `game.gameOver()` | DegenerusGame | When winnings exist (line 587) | NONE -- view function |
| `jackpots.recordBafFlip(...)` | DegenerusJackpots | When winnings exist (line 602) | LOW -- protocol contract |
| `wwxrp.mintPrize(...)` | WrappedWrappedXRP | When losses exist (line 615) | LOW -- protocol contract |

No external calls to untrusted addresses. All callbacks are to protocol-owned contracts with access controls. No ETH transfers that could trigger fallback reentrancy.

### Idempotency

YES -- calling `settleFlipModeChange` twice in succession is safe:
- First call processes days from `lastClaim+1` to `flipsClaimableDay`, updates `lastClaim`
- Second call: `start >= latest` (line 465), returns `mintable = 0` immediately
- `claimableStored` is only incremented when `mintable != 0`, so no double-credit

### No-Pending-State Case

When there is no pending state (`lastClaim >= flipsClaimableDay`), `_claimCoinflipsInternal` returns 0. The `if (mintable != 0)` guard prevents any state modification. Safe and efficient.

---

## 5. Double-Spend Scenario Analysis

### Scenario 1: Toggle afKing to get enhanced recycling then immediately toggle back

**Attack vector:** Player activates afKing mode, benefits from 1.6% recycling on pending coinflip winnings, then immediately deactivates to avoid the lock-in constraints.

**Protection:** 5-level lock (`AFKING_LOCK_LEVELS = 5`).

**Verification:**

```
_deactivateAfKing(player):
  activationLevel = state.afKingActivatedLevel   // e.g., 10
  unlockLevel = 10 + 5 = 15
  if (level < 15) revert AfKingLockActive()       // ENFORCED
```

The lock is strictly enforced in `_deactivateAfKing` which is the ONLY path for voluntary deactivation. The only bypasses are:
- `syncAfKingLazyPassFromCoin` (pass expiration -- involuntary, not player-controlled)
- Level 0 activation edge case (ECON-07-F01 -- no economic impact)

**Can the player bypass the lock?**
- Cannot call `_deactivateAfKing` directly (private)
- `deactivateAfKingFromCoin` restricted to COIN/COINFLIP contracts
- `setAfKingMode(false)` routes through `_deactivateAfKing` with lock check
- `_setAutoRebuy(false)` routes through `_deactivateAfKing` with lock check
- `_setAutoRebuyTakeProfit` with low value routes through `_deactivateAfKing` with lock check

**Verdict: PREVENTED.** The 5-level lock is strictly enforced on all voluntary deactivation paths.

### Scenario 2: Activate afKing while coinflip is in-flight (VRF-aligned timing)

**Attack vector:** Player times afKing activation to coincide with VRF fulfillment, hoping to get enhanced recycling on coinflip results that were determined under standard mode.

**Protection:** `rngLockedFlag` check at the top of `_setAfKingMode` (line 1653).

**Verification:**

The `rngLockedFlag` is checked as the FIRST operation in `_setAfKingMode`. Since EVM transactions are atomic:
- If `rngLockedFlag` is true when `setAfKingMode` is called, the transaction reverts
- A VRF callback (`rawFulfillRandomWords`) arrives in a SEPARATE transaction
- It is impossible for `rngLockedFlag` to change state mid-execution of `setAfKingMode`
- Chainlink VRF V2.5 fulfillment is asynchronous (separate transaction), so there is no intra-transaction ordering concern

**Can rngLockedFlag be stale?** No. It is read directly from storage. If the VRF lock was set in a previous transaction and not yet cleared, the check correctly blocks. If the VRF lock was cleared, the check correctly allows.

**Verdict: PREVENTED.** The rngLockedFlag check is at the correct position (first guard) and EVM atomicity guarantees no mid-execution state change.

### Scenario 3: Pending auto-rebuy state from pre-afKing processed at afKing rates

**Attack vector:** Player has pending coinflip days with accumulated carry amounts at standard rate. Activates afKing mode. The pending carry is then processed at the enhanced 1.6% rate, giving a retroactive bonus.

**Protection:** `settleFlipModeChange` called BEFORE `afKingMode = true` during activation.

**Verification (activation path, line 1680-1685):**

```solidity
if (!state.afKingMode) {
    coinflip.settleFlipModeChange(player);  // settle ALL pending days at standard rate
    state.afKingMode = true;                // THEN enable enhanced rate
    state.afKingActivatedLevel = level;
}
```

During settlement:
1. `syncAfKingLazyPassFromCoin` returns `false` (afKingMode still false)
2. `afKingActive = rebuyActive && false = false`
3. Loop processes all days with `_recyclingBonus(carry)` (standard 1% rate)
4. `autoRebuyCarry` is updated to final value after all days processed
5. Settlement returns, `lastClaim` is advanced to `flipsClaimableDay`
6. THEN `afKingMode = true`

After activation, any NEW coinflip days processed will correctly use the afKing rate because `syncAfKingLazyPassFromCoin` will return `true`.

**What about `setCoinflipAutoRebuy` at step (g)?** This is called before the settlement at step (h). If auto-rebuy was already enabled, the non-strict path in `_setCoinflipAutoRebuy` also calls `_claimCoinflipsInternal`. This processes days at the standard rate (afKingMode still false). When `settleFlipModeChange` is subsequently called at step (h.i), it finds `lastClaim >= flipsClaimableDay` and returns 0. No double-processing.

**Verdict: PREVENTED.** The settle-then-set ordering ensures all pre-activation state is processed at the standard rate.

### Scenario 4: `deactivateAfKingFromCoin` called externally bypassing settleFlipModeChange

**Attack vector:** External caller (COIN or COINFLIP contract) calls `deactivateAfKingFromCoin`, which might not settle pending state, leaving afKing-rate carry amounts to be processed after mode change.

**Verification:**

```solidity
function deactivateAfKingFromCoin(address player) external {
    if (msg.sender != ContractAddresses.COIN &&
        msg.sender != ContractAddresses.COINFLIP) revert E();
    _deactivateAfKing(player);  // calls settleFlipModeChange INSIDE
}
```

`_deactivateAfKing` (line 1759-1771) calls `coinflip.settleFlipModeChange(player)` at line 1767, BEFORE setting `afKingMode = false` at line 1768.

During settlement:
1. `syncAfKingLazyPassFromCoin` reads `afKingMode = true` (still set)
2. If lazy pass is valid, returns `true`
3. Days are processed at afKing rate (correct -- they were accumulated under afKing mode)
4. Settlement completes, carry is finalized at afKing rate
5. THEN `afKingMode = false`

**Verdict: PREVENTED.** Settlement occurs before deactivation in all paths through `_deactivateAfKing`.

### Scenario 5: Lazy pass expires mid-level during afKing

**Attack vector:** Player's lazy pass expires (frozenUntilLevel reaches current level). Some coinflip days were accumulated under afKing mode. If the mode is revoked without settlement, those days might be processed at the standard rate, or vice versa.

**Verification:**

Lazy pass expiration is detected via `syncAfKingLazyPassFromCoin`, which is called at the START of `_claimCoinflipsInternal`. The sequence:

1. `_claimCoinflipsInternal` called (from any trigger: deposit, claim, settlement)
2. `syncAfKingLazyPassFromCoin(player)` called
3. `_hasAnyLazyPass(player)` returns `false` (pass expired)
4. `afKingMode` set to `false`, `afKingActivatedLevel` set to 0
5. Function returns `false`
6. Back in `_claimCoinflipsInternal`: `afKingActive = rebuyActive && false = false`
7. ALL days in this batch are processed at standard rate

**Is this correct?** The days being processed may have been accumulated while afKing was active. Processing them at the standard rate (1%) instead of afKing rate (1.6%) means the player gets LESS recycling bonus than expected.

However, this is correct protocol behavior: the lazy pass has expired, meaning the player's afKing privilege is revoked. The recycling rate is applied at PROCESSING time, not at BET time (see Section 6 below). Since the pass is expired at processing time, the standard rate applies. This is a design choice, not a bug -- the pass expiration revokes all enhanced benefits immediately.

**Is there a brief window?** No. The sync is atomic within `_claimCoinflipsInternal`. Either all days in the batch are processed at afKing rate (pass valid) or all are processed at standard rate (pass expired). No partial-batch inconsistency.

**Verdict: PREVENTED.** Lazy pass expiration is detected atomically at the start of processing. No window exists.

---

## 6. Auto-Rebuy Rate Consistency

### Where is the rate applied?

The recycling bonus is computed in BurnieCoinflip, in two locations:

**A. During `_claimCoinflipsInternal` (daily processing loop, lines 546-553):**

```solidity
if (afKingActive) {
    carry += _afKingRecyclingBonus(carry, deityBonusHalfBps);  // 1.6% base
} else {
    carry += _recyclingBonus(carry);                            // 1% capped at 1000 BURNIE
}
```

**B. During `depositCoinflip` (fresh deposit rebet, lines 302-310):**

```solidity
bool isAfKing = game.afKingModeFor(caller);
if (isAfKing) {
    uint16 deityBonusHalfBps = game.deityPassCountFor(caller) != 0
        ? _afKingDeityBonusHalfBpsWithLevel(caller, game.level())
        : 0;
    bonus = _afKingRecyclingBonus(rebetAmount, deityBonusHalfBps);
} else {
    bonus = _recyclingBonus(rebetAmount);
}
```

### Is the rate read at processing time or cached at bet time?

**At processing time.** In both locations:

- **Path A:** `afKingActive` is determined at the start of `_claimCoinflipsInternal` via `syncAfKingLazyPassFromCoin` (line 436). This reads the CURRENT `afKingMode` flag, not a cached value from when the bet was placed.

- **Path B:** `isAfKing` is read via `game.afKingModeFor(caller)` (line 302), which reads the CURRENT state.

### Implications

Since the rate is always read at processing time:
- **No double-credit risk from caching.** There is no stored rate that could become stale.
- **Mode changes between bet and processing** cause the new rate to apply. This is by design: `settleFlipModeChange` ensures all pending days are processed BEFORE the mode flag changes, so the rate that applies is always the rate that was active during the batch.
- **Fresh deposits (Path B)** read the current mode at deposit time. Since `setAfKingMode` activation requires `!rngLockedFlag` (no VRF pending) and deposit does not overlap with mode change (separate transaction), the mode is always consistent.

### Rate Values

| Mode | Bonus Function | Base Rate | Cap |
|------|---------------|-----------|-----|
| Standard | `_recyclingBonus` | 1% (`amount / 100`) | 1000 BURNIE |
| AfKing (no deity) | `_afKingRecyclingBonus(amount, 0)` | 1.6% (`AFKING_RECYCLE_BONUS_BPS = 160`, computed as `320 halfBps / 20000`) | None |
| AfKing (with deity) | `_afKingRecyclingBonus(amount, deityBonusHalfBps)` | 1.6% + deity bonus (2 halfBps/level, max 300 halfBps = 1.5%) | Deity portion capped at DEITY_RECYCLE_CAP (1M BURNIE) |

---

## 7. Three-Layer Protection Assessment

### Layer 1: settleFlipModeChange

| Property | Status | Evidence |
|----------|--------|----------|
| Called before activation flag set | PASS | Line 1681 (settle) before line 1682 (flag) |
| Called before deactivation flag cleared | PASS | Line 1767 (settle) before line 1768 (flag) |
| Processes all pending days | PASS | Iterates lastClaim+1 through flipsClaimableDay |
| Idempotent | PASS | Second call returns 0, no state change |
| No reentrancy risk | PASS | Only callbacks to protocol contracts |
| Handles no-pending-state | PASS | Returns 0 without modifying state |

### Layer 2: rngLockedFlag

| Property | Status | Evidence |
|----------|--------|----------|
| Checked on activation | PASS | Line 1653, first guard |
| Checked on deactivation | PASS | Line 1653, first guard |
| EVM atomicity prevents mid-tx change | PASS | VRF fulfillment is separate transaction |
| Cannot be bypassed | PASS | All paths through `_setAfKingMode` hit this check |

### Layer 3: 5-Level Lock (AFKING_LOCK_LEVELS = 5)

| Property | Status | Evidence |
|----------|--------|----------|
| Enforced on voluntary deactivation | PASS | `_deactivateAfKing` line 1764-1765 |
| All deactivation paths use `_deactivateAfKing` | PASS | setAfKingMode(false), setAutoRebuy(false), deactivateAfKingFromCoin, setAutoRebuyTakeProfit (low value) |
| Cannot be bypassed by player | PASS | `_deactivateAfKing` is private, external hooks access-controlled |
| Correctly skipped for pass expiration | PASS | `syncAfKingLazyPassFromCoin` is involuntary system event |
| Level 0 edge case | INFO | activationLevel=0 bypasses lock (ECON-07-F01, no economic impact) |

---

## 8. Additional Deactivation Triggers

For completeness, here are ALL paths that can deactivate afKing mode:

| Path | Trigger | Settlement | Lock Check | Access |
|------|---------|------------|------------|--------|
| `setAfKingMode(false)` | Player voluntary | YES (via _deactivateAfKing) | YES | Player or operator |
| `_setAutoRebuy(false)` | Player disables auto-rebuy | YES (via _deactivateAfKing) | YES | Player or operator |
| `_setAutoRebuyTakeProfit(low)` | Player sets low take-profit | YES (via _deactivateAfKing) | YES | Player or operator |
| `deactivateAfKingFromCoin` | COINFLIP/COIN contract | YES (via _deactivateAfKing) | YES | COIN or COINFLIP only |
| `syncAfKingLazyPassFromCoin` | Pass expiration | NO (in-settlement) | NO (involuntary) | COINFLIP only |

All voluntary paths go through `_deactivateAfKing` with both settlement and lock check. The only exception (`syncAfKingLazyPassFromCoin`) is justified: it is called from within settlement already, and pass expiration is not player-initiated.

---

## ECON-07 Verdict: PASS

### Per-Scenario Summary

| Scenario | Verdict | Primary Protection | Notes |
|----------|---------|-------------------|-------|
| S1: Rapid toggle exploitation | PREVENTED | 5-level lock | Lock strictly enforced on all voluntary paths |
| S2: VRF-aligned timing attack | PREVENTED | rngLockedFlag | EVM atomicity + first-position guard |
| S3: Retroactive rate upgrade | PREVENTED | settleFlipModeChange | Settle-then-set ordering on activation |
| S4: External deactivation bypass | PREVENTED | _deactivateAfKing | All external hooks route through settlement |
| S5: Lazy pass expiration window | PREVENTED | syncAfKingLazyPassFromCoin | Atomic sync at start of processing |

### Findings

| ID | Severity | Description |
|----|----------|-------------|
| ECON-07-F01 | INFORMATIONAL | Activation at level 0 bypasses 5-level lock (`activationLevel != 0` guard). No economic impact -- no accumulated coinflip state exists at level 0. |

### Assessment

The three-layer protection system (settleFlipModeChange, rngLockedFlag, 5-level lock) provides comprehensive defense against afKing mode transition exploitation:

1. **settleFlipModeChange** ensures all pending coinflip state is processed at the correct rate BEFORE any mode flag changes, in both activation and deactivation paths.

2. **rngLockedFlag** prevents mode changes during VRF processing, eliminating any timing-based attacks at the VRF fulfillment boundary.

3. **The 5-level lock** prevents rapid toggling for arbitrage between rate tiers, while correctly allowing involuntary revocation (pass expiration) without the lock constraint.

4. **Rate consistency** is guaranteed by reading afKingMode at processing time (not caching at bet time), combined with the settle-before-change pattern.

5. **No double-spend or double-credit window exists.** The settle-then-set ordering in both activation and deactivation paths, combined with the idempotent settlement function, eliminates any transitional state inconsistency.

**ECON-07: PASS** -- No double-spend or double-credit vulnerabilities in afKing mode transitions.
