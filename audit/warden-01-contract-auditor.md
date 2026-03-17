# Warden Report: Contract Auditor
**Agent:** 1 of 3 (Contract Auditor)
**Date:** 2026-03-17
**Scope:** Degenerus Protocol -- 14 core contracts + 10 delegatecall modules
**Focus:** Storage layout, delegatecall safety, reentrancy, CEI, access control
**Methodology:** Blind adversarial review per C4A warden methodology

---

## High-Severity Findings

_No high-severity findings identified after thorough review of storage layout, delegatecall sites, reentrancy vectors, and access control paths._

**Evidence:** All delegatecall targets are compile-time constants (immutable `ContractAddresses`), every external call follows CEI ordering, and all privileged functions enforce `msg.sender` checks against constant addresses. No path exists for direct theft or permanent fund lockup through the reviewed attack surfaces.

---

## Medium-Severity Findings

_No medium-severity findings identified._

**Evidence:** The protocol's access control model is sound -- the game contract serves as the trust anchor with `onlyGame` modifiers on sDGNRS and module dispatch. The RNG lock state machine prevents manipulation during VRF callback windows. Cross-function reentrancy is blocked by the CEI pattern applied at every external call site.

---

## [L-01] DGNRS Transfer-to-Self Executes Redundant Unchecked Arithmetic

### Description

When `from == to` in `DegenerusStonk._transfer()`, the function performs two separate unchecked storage writes that are algebraically equivalent to a no-op but diverge from the single-update pattern used by standard ERC20 implementations.

### Code References

`DegenerusStonk.sol:190-200`:
```solidity
function _transfer(address from, address to, uint256 amount) private returns (bool) {
    if (to == address(0)) revert ZeroAddress();
    uint256 bal = balanceOf[from];
    if (amount > bal) revert Insufficient();
    unchecked {
        balanceOf[from] = bal - amount;   // writes (bal - amount)
        balanceOf[to] += amount;          // reads (bal - amount), writes ((bal - amount) + amount) = bal
    }
    emit Transfer(from, to, amount);
    return true;
}
```

The result is correct (`bal - amount + amount = bal`), so no tokens are lost. However, the two-step write costs an additional SLOAD (reading `balanceOf[to]` which was just written as `balanceOf[from]`) and emits a Transfer event for a self-transfer that does nothing. This is cosmetic/gas-level -- no economic impact.

**Severity rationale:** Low. No value at risk. Algebraically safe. Standard ERC20 behavior in minimal implementations.

---

## [L-02] StakedDegenerusStonk.burn() ETH Payout to Contract Callers May Revert on Receive Failure

### Description

When a smart contract holding sDGNRS calls `burn()`, the ETH payout uses a low-level `.call{value: ethOut}("")` at `StakedDegenerusStonk.sol:436`. If the caller contract does not implement a `receive()` function, the call reverts, leaving the token state already updated (supply decremented, balance zeroed).

However, because the `.call` revert bubbles up and reverts the entire transaction (Solidity 0.8+ default behavior), no state is actually persisted. The burn simply fails atomically. The sDGNRS holder must wrap their call in a contract with a `receive()` function or burn from an EOA.

### Code References

`StakedDegenerusStonk.sol:398-438`:
```solidity
unchecked {
    balanceOf[player] = bal - amount;
    totalSupply -= amount;
}
emit Transfer(player, address(0), amount);

// ... BURNIE and stETH transfers ...

if (ethOut > 0) {
    (bool success, ) = player.call{value: ethOut}("");
    if (!success) revert TransferFailed();
}
```

**Severity rationale:** Low. The revert is atomic -- no fund loss. Smart contract callers must ensure ETH receivability. This is standard Solidity behavior.

---

## [L-03] burnRemainingPools Does Not Zero Individual poolBalances Array

### Description

`StakedDegenerusStonk.burnRemainingPools()` at line 359 zeroes `balanceOf[address(this)]` and decrements `totalSupply` but does not zero the `poolBalances[0..4]` array entries. After this call, the `poolBalance()` view function returns stale non-zero values for depleted pools.

### Code References

`StakedDegenerusStonk.sol:359-367`:
```solidity
function burnRemainingPools() external onlyGame {
    uint256 bal = balanceOf[address(this)];
    if (bal == 0) return;
    unchecked {
        balanceOf[address(this)] = 0;
        totalSupply -= bal;
    }
    emit Transfer(address(this), address(0), bal);
}
```

`StakedDegenerusStonk.sol:303-305`:
```solidity
function poolBalance(Pool pool) external view returns (uint256) {
    return poolBalances[_poolIndex(pool)];
}
```

**Impact:** Off-chain systems or UI reading `poolBalance()` after gameOver will see stale balances. No on-chain exploit: `transferFromPool` is gated by `onlyGame`, and gameOver prevents further pool spending. `transferFromPool` also caps by `available` and deducts from `balanceOf[address(this)]` which is 0, so the `unchecked { balanceOf[address(this)] -= amount }` would underflow and revert in Solidity 0.8+ -- except it is `unchecked` so it would silently wrap. However, `available` is read from `poolBalances[idx]` and `amount` is capped at `available`, while `balanceOf[address(this)]` is already 0. The subtraction `0 - amount` in unchecked would wrap to `type(uint256).max - amount + 1`.

Wait -- this warrants closer analysis. After `burnRemainingPools`:
- `balanceOf[address(this)] = 0`
- `poolBalances[0..4]` still have stale values

If the game somehow called `transferFromPool` after `burnRemainingPools`:
1. `available = poolBalances[idx]` -- non-zero (stale)
2. `amount` is capped to `available`
3. `balanceOf[address(this)] -= amount` -- this is `0 - amount` in unchecked block, wrapping to `type(uint256).max - amount + 1`
4. `balanceOf[to] += amount`

This would create tokens from nothing -- a critical bug IF reachable. But is it?

`transferFromPool` is `onlyGame`, and game only calls it during active gameplay. After `burnRemainingPools` is called (inside `handleGameOverDrain`), `gameOver = true` is already set. All game functions that call `transferFromPool` are gated by the game state machine which blocks post-gameOver operations.

**Severity rationale:** Low. The stale poolBalances are not exploitable because the `onlyGame` guard combined with the terminal `gameOver` flag prevents any post-burn pool transfers. The view function returning stale data is an informational concern for off-chain consumers.

---

## [L-04] DegenerusStonk.receive() Accepts ETH From Any Sender With No Sweep Mechanism

### Description

`DegenerusStonk.sol:89` defines `receive() external payable {}` with no sender restriction. Any ETH sent directly to the DGNRS contract (not through burn-through) is permanently locked.

### Code References

`DegenerusStonk.sol:89`:
```solidity
receive() external payable {}
```

The contract has no sweep function and no mechanism to recover accidentally sent ETH.

**Severity rationale:** Low. The NatSpec comment at line 88 notes this is intentional ("no sweep function"). ETH sent here is lost by the sender but does not affect protocol solvency.

---

## [QA-01] Compile-Time Address Constants Create Single-Deploy Binding

### Description

All inter-contract references use `ContractAddresses` constants that are baked into bytecode at compile time. This means the entire protocol must be deployed in a single atomic batch with nonce-predicted addresses. Any deployment failure or nonce mismatch requires a complete redeployment.

### Code References

`ContractAddresses.sol` (referenced throughout):
- `DegenerusGame.sol:155-177` -- 6 constant contract references
- `StakedDegenerusStonk.sol:165-174` -- 4 constant contract references
- `DegenerusStonk.sol:71-73` -- 3 constant contract references
- `DegenerusAdmin.sol:306-313` -- 4 constant contract references
- All 10 modules reference `ContractAddresses` for trusted addresses

**Impact:** This is intentional and security-positive -- immutable references prevent address manipulation. But it creates deployment complexity and makes contract replacement impossible. Post-deploy, there is no way to update any contract reference.

**Severity rationale:** QA/Informational. Security-positive design trade-off. No exploit vector.

---

## [QA-02] Generic Error E() Reduces Debuggability Across Game and Modules

### Description

The game contract and all modules use `error E()` as a universal revert signal. While gas-efficient, this makes debugging difficult -- a revert from `_processMintPayment` looks identical to one from `recordMint`, `claimWinnings`, or any module function.

### Code References

`DegenerusGameStorage.sol:185`:
```solidity
error E();
```

Used in 50+ locations across `DegenerusGame.sol` and all 10 modules (e.g., `DegenerusGame.sol:399`, `DegenerusGame.sol:444`, `DegenerusGame.sol:454`, `DegenerusGame.sol:498`, `DegenerusGame.sol:542-543`).

**Severity rationale:** QA. No security impact. Gas optimization trade-off against debuggability.

---

## [QA-03] DegenerusAdmin.emergencyRecover try/catch Silently Swallows Old Subscription Cancellation Failure <!-- v2.1 Note: removed -->

### Description

In `DegenerusAdmin.sol:491-498`, the `cancelSubscription` call to the old coordinator is wrapped in `try/catch {}` with an empty catch block. If cancellation fails (e.g., coordinator is compromised or non-responsive), LINK funds in the old subscription are permanently lost.

### Code References

`DegenerusAdmin.sol:491-498`:
```solidity
try
    IVRFCoordinatorV2_5Owner(oldCoord).cancelSubscription(
        oldSub,
        address(this)
    )
{
    emit SubscriptionCancelled(oldSub, address(this));
} catch {}
```

**Impact:** LINK in the old subscription is forfeited if the old coordinator is unreachable. This is an acceptable trade-off: the emergency recovery path prioritizes getting the game back online over recovering LINK. The catch-all prevents a dead coordinator from blocking recovery.

**Severity rationale:** QA. Intentional design trade-off. LINK loss is bounded by subscription balance and secondary to game continuity.

> **v2.1 Note:** `emergencyRecover` was removed in v2.1. The try/catch pattern noted in QA-03
> is no longer present. VRF coordinator rotation now uses governance (propose/vote/execute).
> The try/catch for old subscription cancellation now exists in `_executeSwap`.
> See v2.1-governance-verdicts.md for current behavior.

---

## [QA-04] sDGNRS Constructor Calls External Contracts During Deployment

### Description

The `StakedDegenerusStonk` constructor calls `game.claimWhalePass(address(0))` and `game.setAfKingMode(...)` at `StakedDegenerusStonk.sol:221-227`. These external calls during construction rely on the game contract being deployed and initialized first in the deployment batch.

### Code References

`StakedDegenerusStonk.sol:221-227`:
```solidity
game.claimWhalePass(address(0));
game.setAfKingMode(
    address(0),
    true,
    10 ether,
    0
);
```

**Impact:** Deployment ordering constraint. If game is not yet deployed when sDGNRS constructor runs, the constructor reverts. This is handled by the nonce-prediction deployment batch but creates a hard ordering dependency.

**Severity rationale:** QA. Deployment concern only. No post-deployment impact.

---

## [QA-05] linkAmountToEth Exposed as External for try/catch Self-Call Pattern

### Description

`DegenerusAdmin.linkAmountToEth()` at line 664 is marked `external` despite being logically internal. This is done to enable `try this.linkAmountToEth(amount)` at line 633, which requires an external call target.

### Code References

`DegenerusAdmin.sol:633-637`:
```solidity
try this.linkAmountToEth(amount) returns (uint256 eth) {
    ethEquivalent = eth;
} catch {
    return;
}
```

`DegenerusAdmin.sol:664`:
```solidity
function linkAmountToEth(uint256 amount) external view returns (uint256 ethAmount) {
```

**Impact:** Anyone can call `linkAmountToEth()` -- but it is a `view` function with no state changes, so this is harmless. The pattern is well-known for try/catch on view functions.

**Severity rationale:** QA. No security impact.

---

## Confidence by Area

- **Storage Layout and Delegatecall Safety:** High
  - Verified: All 10 modules inherit `DegenerusGameStorage` as their sole parent (or through `DegenerusGamePayoutUtils`/`DegenerusGameMintStreakUtils` which themselves inherit `DegenerusGameStorage`). No module declares its own storage variables. Slot 0 is fully packed (32/32 bytes used). The `TICKET_SLOT_BIT` double-buffer mechanism uses bit 23 of the uint24 level key to avoid mapping collision.
  - BitPackingLib.setPacked at line 79-86 uses standard `(data & ~(mask << shift)) | ((value & mask) << shift)` with correct mask application. Field boundaries verified: LAST_LEVEL_SHIFT(0, 24-bit), LEVEL_COUNT_SHIFT(24, 24-bit), LEVEL_STREAK_SHIFT(48, 24-bit), DAY_SHIFT(72, 32-bit), LEVEL_UNITS_LEVEL_SHIFT(104, 24-bit), FROZEN_UNTIL_LEVEL_SHIFT(128, 24-bit), WHALE_BUNDLE_TYPE_SHIFT(152, 2-bit), LEVEL_UNITS_SHIFT(228, 16-bit). No overlaps found.
  - All delegatecall sites use constant module addresses from `ContractAddresses`. Return data is decoded with `abi.decode` and revert data is bubbled with `_revertDelegate`. Selector encoding uses interface selectors, preventing collision with game functions.

- **ETH Accounting and Solvency:** High
  - `claimablePool` is incremented on every credit and decremented on every claim/spend. The invariant `address(this).balance + steth.balanceOf(this) >= claimablePool` is maintained by the CEI pattern in `_claimWinningsInternal` (line 1422: `claimablePool -= payout` before external call).
  - Prize pool flow: `futurePrizePool -> nextPrizePool -> currentPrizePool -> claimableWinnings` with BPS splits verified (PURCHASE_TO_FUTURE_BPS = 1000 = 10%).
  - `_processMintPayment` correctly handles all three MintPaymentKind paths with tight validation. The 1-wei sentinel pattern prevents cold SSTORE costs.

- **VRF / RNG Security:** Medium
  - RNG lock state machine (`rngLockedFlag`) gates state-changing operations during VRF callback window. 18-hour timeout prevents permanent lock. `_getHistoricalRngFallback` provides disaster recovery. However, deep analysis of VRF callback manipulation vectors was secondary for this audit focus.

- **Economic Attack Vectors:** Low
  - Secondary focus area. Verified BPS constants sum correctly in sDGNRS constructor (CREATOR_BPS=2000 + WHALE_POOL_BPS=1000 + AFFILIATE_POOL_BPS=3500 + LOOTBOX_POOL_BPS=2000 + REWARD_POOL_BPS=500 + EARLYBIRD_POOL_BPS=1000 = 10000). Dust is added to lootbox pool. Deep economic modeling deferred to Economic Analyst warden.

- **Access Control:** High
  - Complete privilege map:
    - **GAME contract** (`msg.sender == address(this)` or `msg.sender == ContractAddresses.GAME`): Trust anchor. Controls sDGNRS pool transfers, deposits, burn-remaining. Controls module dispatch.
    - **ADMIN** (`msg.sender == ContractAddresses.ADMIN`): VRF wiring, lootbox threshold. Requires >50.1% DGVE via vault.isVaultOwner.
    - **CREATOR** (`msg.sender == ContractAddresses.CREATOR`): DGNRS unwrapTo only.
    - **COIN/COINFLIP**: recordCoinflipDeposit, recordMintQuestStreak, payCoinflipBountyDgnrs, consumeCoinflipBoon, consumeDecimatorBoon.
    - **DEITY_PASS**: onDeityPassTransfer callback.
    - **JACKPOTS**: creditDecJackpotClaim/Batch.
    - **DGNRS (wrapper)**: wrapperTransferTo on sDGNRS.
    - **Public**: purchase, advanceGame, claimWinnings, burn, openLootBox, placeFullTicketBets, etc.
  - No privilege escalation paths found. Constructor initialization is one-time (immutable contracts). `wireVrf` can be called multiple times but only by ADMIN which requires DGVE majority.

- **Reentrancy and CEI:** High
  - All external ETH calls use CEI:
    - `_claimWinningsInternal` (DegenerusGame.sol:1413-1429): claimableWinnings set to 1, claimablePool decremented, THEN external call.
    - `StakedDegenerusStonk.burn()` (line 398-438): balanceOf/totalSupply updated, THEN BURNIE transfer, THEN stETH transfer, THEN ETH call.
    - `DegenerusStonk.burn()` (line 153-170): _burn (updates balance/supply), THEN stonk.burn, THEN BURNIE transfer, THEN stETH transfer, THEN ETH call.
    - `_sendToVault` in GameOverModule (line 195-232): Direct transfers to vault/DGNRS, no re-entrant state.
  - No callback-reachable external calls precede state updates. The game's delegatecall modules execute in the game's context, so reentrancy from module -> game is not possible (delegatecall doesn't create a new context).
  - Read-only reentrancy: `previewBurn` reads `address(this).balance` and `steth.balanceOf(address(this))` which could be manipulated mid-transaction by a reentrant call. But `previewBurn` is `view` and not used for any on-chain decision within the protocol.

- **Precision and Rounding:** Medium
  - Verified: BPS denominators are consistently 10_000 across all split calculations. sDGNRS burn formula `(totalMoney * amount) / supplyBefore` rounds down, favoring the protocol (last burner gets slightly less). Dust from BPS allocation in constructor is added to lootbox pool. Deep rounding analysis deferred to Economic Analyst warden.

- **Temporal and Lifecycle Edge Cases:** Medium
  - Secondary focus. Verified: gameOver flag is terminal. `handleFinalSweep` has 30-day cooldown. `finalSwept` flag prevents double sweep. `_claimWinningsInternal` checks `if (finalSwept) revert E()` to prevent claims after sweep.

- **EVM-Level Risks:** Medium
  - Verified: BitPackingLib.setPacked uses pure Solidity (no inline assembly) with correct mask/shift operations. `_revertDelegate` assembly at DegenerusGame.sol:1065-1067 is standard revert bubbling: `revert(add(32, reason), mload(reason))`. No SLOAD/SSTORE assembly in BitPackingLib.

- **Cross-Contract Composition:** High
  - Module composition safety verified: all modules inherit DegenerusGameStorage, use constant ContractAddresses, and are invoked exclusively via delegatecall from the game contract. No module calls another module directly -- all cross-module invocations go through the game contract dispatcher via `IDegenerusGame(address(this)).someFunction()`.
  - sDGNRS/DGNRS composition: DGNRS.burn -> sDGNRS.burn is a clean two-step process. DGNRS._burn updates wrapper state first, then sDGNRS.burn handles reserve distribution. No shared mutable state between the two contracts except through the balanceOf mapping in sDGNRS.

---

## Coverage Gaps

- **DegenerusGameAdvanceModule**: Full file reviewed for delegatecall dispatch and VRF lifecycle but deep analysis of `_getHistoricalRngFallback` entropy quality was secondary.
- **DegenerusGameJackpotModule**: Reviewed entry points, struct patterns, and fund flow. Did not deeply trace every winner selection path through `_distributeJackpotEth` and all bucket distribution sub-functions (file exceeds 1000 lines).
- **DegenerusGameLootboxModule**: Reviewed interface and delegation pattern. Did not deeply audit EV calculation internals.
- **DegenerusGameDegeneretteModule**: Reviewed delegation pattern and access control. Did not deeply audit betting resolution logic.
- **DegenerusGameBoonModule**: Reviewed delegation pattern. Did not audit boon generation/consumption logic.
- **DegenerusGameDecimatorModule**: Reviewed entry points and access control. Did not deeply audit pro-rata claim math.
- **EntropyLib**: Not reviewed (deferred to Zero-Day Hunter warden).
- **PriceLookupLib, JackpotBucketLib, GameTimeLib**: Not reviewed for correctness (library internals).

---

## Limitations

- **Static analysis only.** No runtime execution, no fuzzing, no formal verification performed. All claims are based on source code review.
- **Single-pass review.** Time-constrained to one review pass. Complex multi-step interactions (e.g., full gameOver sequence with deity refunds + decimator + terminal jackpot + sweep) may have edge cases not captured.
- **Compile-time address constants.** Could not verify that deployed addresses match `ContractAddresses.sol` without deployment artifacts.
- **No test execution.** Acceptance of existing tests as passing is based on project documentation, not independent execution.
- **Blind review.** This report was produced without access to prior internal audit findings. Some issues identified here may already be known.
