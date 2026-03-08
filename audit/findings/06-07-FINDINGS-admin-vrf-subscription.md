# 06-07 Findings: DegenerusAdmin VRF Subscription Management Audit

**Requirement:** AUTH-06 -- DegenerusAdmin VRF subscription management cannot be griefed by external callers
**Audited Contract:** `contracts/DegenerusAdmin.sol` (738 lines)
**Supporting Contracts:** `contracts/DegenerusGame.sol`, `contracts/modules/DegenerusGameAdvanceModule.sol`, `contracts/storage/DegenerusGameStorage.sol`
**Date:** 2026-03-01

---

## 1. Complete DegenerusAdmin Function Table

| # | Function | Visibility | Access Gate | VRF-Related | Description |
|---|----------|-----------|-------------|-------------|-------------|
| 1 | `constructor()` | N/A | Deploy-time only | Yes | Creates VRF subscription, adds Game as consumer, calls `wireVrf` on Game |
| 2 | `setLinkEthPriceFeed(address)` | external | `onlyOwner` | Indirect | Sets LINK/ETH price feed for donation reward valuation |
| 3 | `swapGameEthForStEth()` | external payable | `onlyOwner` | No | Swaps owner ETH for Game-held stETH (1:1) |
| 4 | `stakeGameEthToStEth(uint256)` | external | `onlyOwner` | No | Stakes Game-held ETH into stETH via Lido |
| 5 | `setLootboxRngThreshold(uint256)` | external | `onlyOwner` | Indirect | Updates lootbox RNG request threshold on Game |
| 6 | `emergencyRecover(address, bytes32)` | external | `onlyOwner` + `rngStalledForThreeDays()` | Yes | Migrates to new VRF coordinator/subscription after 3-day stall |
| 7 | `shutdownAndRefund(address)` | external | `onlyOwner` + `gameOver()` | Yes | Cancels subscription and sweeps LINK after game-over |
| 8 | `onTokenTransfer(address, uint256, bytes)` | external | `msg.sender == LINK_TOKEN` | Yes | ERC-677 callback: forwards LINK to VRF subscription, credits BURNIE reward |
| 9 | `_linkAmountToEth(uint256)` | external view | None (read-only) | Indirect | Converts LINK to ETH-equivalent using price feed (try/catch target) |
| 10 | `_linkRewardMultiplier(uint256)` | private pure | Internal only | No | Calculates tiered reward multiplier based on subscription balance |
| 11 | `_feedHealthy(address)` | private view | Internal only | No | Checks if price feed is responding with valid, fresh data |

**Summary:** 6 external state-changing functions, all gated (5 by `onlyOwner`, 1 by `msg.sender == LINK_TOKEN`). 1 external view function (harmless). 2 private helpers (unreachable externally).

---

## 2. onTokenTransfer Audit (LINK Funding Path)

### 2a. Gate Verification

```solidity
// Line 595
if (msg.sender != ContractAddresses.LINK_TOKEN) revert NotAuthorized();
```

**Exact check:** `msg.sender` must equal the compile-time constant `ContractAddresses.LINK_TOKEN`. This is the canonical ERC-677 pattern -- only the LINK token contract can trigger `onTokenTransfer` via `transferAndCall`.

### 2b. Flow When LINK Sent via transferAndCall

1. External user calls `LINK.transferAndCall(adminAddr, amount, "0x")`.
2. LINK contract transfers tokens to DegenerusAdmin, then calls `admin.onTokenTransfer(from, amount, data)`.
3. Admin validates `msg.sender == LINK_TOKEN` and `amount != 0`.
4. Admin checks `subscriptionId != 0` and `!gameAdmin.gameOver()`.
5. Admin queries subscription balance to calculate reward multiplier.
6. Admin forwards LINK to VRF subscription via `linkToken.transferAndCall(coord, amount, abi.encode(subId))`.
7. Admin converts LINK to ETH-equivalent via `this._linkAmountToEth(amount)` with try/catch.
8. If reward is non-zero, credits BURNIE to donor via `coinLinkReward.creditLinkReward(from, credit)`.

### 2c. LINK Relay to VRF Subscription

```solidity
// Lines 612-618
try linkToken.transferAndCall(coord, amount, abi.encode(subId)) returns (bool ok) {
    if (!ok) revert InvalidAmount();
} catch {
    revert InvalidAmount();
}
```

**Confirmed:** LINK is forwarded to the VRF coordinator address via `transferAndCall` with the subscription ID encoded in calldata. This is the standard Chainlink VRF V2.5 funding pattern. If the LINK transfer fails for any reason, `onTokenTransfer` reverts with `InvalidAmount`, which propagates up to the original `transferAndCall` call, causing the entire transfer to revert (LINK is not lost).

### 2d. Can an External Caller Call onTokenTransfer Directly?

**No.** The function checks `msg.sender == ContractAddresses.LINK_TOKEN`. An external caller's `msg.sender` would be their own address, not the LINK token contract. The only way to trigger this function is through the LINK token's `transferAndCall`, which sets `msg.sender` to the LINK contract address.

### 2e. Can the LINK Token Address Be Changed?

**No.** `ContractAddresses.LINK_TOKEN` is a compile-time constant. There is no function in DegenerusAdmin (or anywhere in the protocol) that can modify this value. It is immutable for the lifetime of the deployment.

### 2f. Can Anyone Block LINK Funding by Front-Running or Griefing?

**No.** The `onTokenTransfer` callback is atomic with the `transferAndCall` invocation. There is no approval step, no separate transaction, and no state that can be manipulated between the LINK transfer and the subscription funding. An attacker cannot:
- Front-run to change the coordinator address (requires `onlyOwner` + stall).
- Front-run to set `subscriptionId = 0` (only happens in `shutdownAndRefund`, requires `onlyOwner` + `gameOver()`).
- Cause the `transferAndCall` to the coordinator to fail (the coordinator's `onTokenTransfer` is a standard Chainlink function).

### 2g. Does onTokenTransfer Call _linkAmountToEth? Price Feed Revert Handling?

**Yes**, `onTokenTransfer` calls `this._linkAmountToEth(amount)` at line 624.

```solidity
// Lines 623-628
try this._linkAmountToEth(amount) returns (uint256 eth) {
    ethEquivalent = eth;
} catch {
    return; // Oracle failed, LINK forwarded but no reward.
}
```

### 2h. Try/Catch and Fallback Behavior

**Critical design decision:** The LINK forwarding to the VRF subscription happens BEFORE the `_linkAmountToEth` call (lines 612-618). If the price feed reverts, the try/catch catches it and returns silently. The LINK has already been forwarded to the subscription. The only consequence is that the donor does not receive a BURNIE reward.

**This is correct defensive design.** A bad price feed cannot block LINK funding. It can only disable the reward mechanism.

---

## 3. emergencyRecover Audit

### 3a. Access Gate

```solidity
// Line 473
function emergencyRecover(
    address newCoordinator,
    bytes32 newKeyHash
) external onlyOwner returns (uint256 newSubId) {
```

**Gate:** `onlyOwner` modifier, which permits:
1. `ContractAddresses.CREATOR` (deployer) -- compile-time constant, immutable
2. Any address where `vault.isVaultOwner(msg.sender)` returns true (>30% DGVE supply)

### 3b. rngStalledForThreeDays Precondition

```solidity
// Line 476
if (!gameAdmin.rngStalledForThreeDays()) revert NotStalled();
```

This calls `DegenerusGame.rngStalledForThreeDays()` which delegates to `_threeDayRngGap(_simulatedDayIndex())`.

### 3c. What rngStalledForThreeDays Checks

```solidity
// DegenerusGame.sol lines 2229-2234
function _threeDayRngGap(uint48 day) private view returns (bool) {
    if (rngWordByDay[day] != 0) return false;
    if (rngWordByDay[day - 1] != 0) return false;
    if (day < 2 || rngWordByDay[day - 2] != 0) return false;
    return true;
}
```

**Mechanism:** Returns `true` only if `rngWordByDay[day]`, `rngWordByDay[day-1]`, and `rngWordByDay[day-2]` are ALL zero. This means no VRF word has been recorded for 3 consecutive day slots.

**Can an attacker trigger this artificially?**

- `rngWordByDay` is written in `rawFulfillRandomWords` (the VRF callback) within the AdvanceModule. Only the VRF coordinator can call this (AUTH-02 confirmed).
- A VRF word of 0 is explicitly guarded against: `if (word == 0) word = 1;` (AdvanceModule line 1207). So once a VRF fulfillment occurs for a day, `rngWordByDay[day]` will be non-zero.
- The only way to get 3 consecutive zero-days is if the VRF coordinator stops fulfilling requests for 3+ days.
- No protocol actor (owner, vault owner, player) can prevent VRF fulfillment -- only Chainlink's infrastructure failure could cause this.

**Can a vault owner artificially create a 3-day stall?**

- A vault owner could theoretically drain LINK from the subscription to prevent VRF requests from being funded. However:
  - There is no function to withdraw LINK from an active subscription except `emergencyRecover` itself (which requires the stall to already exist) and `shutdownAndRefund` (which requires `gameOver()`).
  - The subscription is owned by DegenerusAdmin, not by any EOA.
  - A vault owner cannot prevent `advanceGame` from being called (it is permissionless).
  - If LINK runs out, the VRF coordinator simply won't fulfill (no LINK payment), which would eventually trigger the 3-day stall. But this requires the subscription to be unfunded, which means the protocol has genuinely run out of LINK.

**Conclusion:** `rngStalledForThreeDays` cannot be artificially triggered by any protocol actor. It requires a genuine VRF coordinator failure or LINK exhaustion.

### 3d. What emergencyRecover Does

Step-by-step execution:

1. **Validates preconditions:** `subscriptionId != 0`, `rngStalledForThreeDays()`, `newCoordinator != address(0)`, `newKeyHash != bytes32(0)`.
2. **Cancels old subscription:** `IVRFCoordinatorV2_5Owner(oldCoord).cancelSubscription(oldSub, address(this))` -- wrapped in try/catch. LINK refunds go to `address(this)` (DegenerusAdmin).
3. **Creates new subscription** on the new coordinator.
4. **Adds Game as consumer** on the new subscription.
5. **Pushes new config to Game:** `gameAdmin.updateVrfCoordinatorAndSub(newCoordinator, newSubId, newKeyHash)`.
6. **Transfers remaining LINK** to the new subscription via `transferAndCall`.

### 3e. Where Do Recovered Funds Go?

- LINK from the cancelled subscription goes to `address(this)` (DegenerusAdmin) -- line 487.
- That LINK is then forwarded to the new subscription -- lines 518-528.
- No ETH is moved by `emergencyRecover`. ETH recovery is not part of this function.

**The owner cannot extract LINK to themselves via emergencyRecover.** LINK is recycled from old subscription to new subscription, with DegenerusAdmin as an intermediary.

### 3f. Can a Vault Owner Drain VRF Subscription LINK?

**No.** Even if a vault owner calls `emergencyRecover`:
- The 3-day stall must genuinely exist first.
- LINK goes from old subscription to DegenerusAdmin to new subscription.
- There is no function to transfer LINK out of DegenerusAdmin to an arbitrary address (except `shutdownAndRefund`, gated by `gameOver()`).
- The vault owner could point `newCoordinator` to a malicious contract, but:
  - The LINK `transferAndCall` to the new coordinator is try/catch wrapped (lines 518-528). If it fails, LINK stays on DegenerusAdmin.
  - The malicious coordinator would need to implement `createSubscription()` and `addConsumer()` correctly to get past earlier steps.
  - Even if LINK is sent to a malicious coordinator, it would be in a subscription context. The attacker cannot extract it unless their contract is designed to do so.

**FINDING (Informational):** A vault owner (>30% DGVE) could, after a genuine 3-day stall, point the system to a malicious coordinator that steals LINK from the subscription. This is an accepted trust assumption -- a >30% DGVE holder has significant economic alignment with the protocol. See Section 6b for full analysis.

---

## 4. setLinkEthPriceFeed Audit

### 4a. Access Gate

```solidity
function setLinkEthPriceFeed(address feed) external onlyOwner {
```

**Gate:** `onlyOwner` (CREATOR or vault owner with >30% DGVE).

**Additional guard:** `if (_feedHealthy(current)) revert FeedHealthy();` -- the current feed can only be replaced if it is unhealthy (stale, returning invalid data, or reverting).

### 4b. Can a Malicious Price Feed Cause Harm Beyond Incorrect Display Values?

The price feed is used in exactly one place: `_linkAmountToEth` (line 653), which is called from `onTokenTransfer` (line 624) within a try/catch.

`_linkAmountToEth` result is used to calculate BURNIE credit for LINK donations:
```solidity
uint256 baseCredit = (ethEquivalent * PRICE_COIN_UNIT) / 1 ether;
uint256 credit = (baseCredit * mult) / 1e18;
```
This credit is then passed to `coinLinkReward.creditLinkReward(from, credit)`, which mints BURNIE tokens (not ETH).

### 4c. Does _linkAmountToEth Affect ETH Transfers or Accounting?

**No.** The ETH-equivalent value is used solely to calculate BURNIE credit amounts. No ETH is transferred based on this value. The only effect is the amount of BURNIE minted as a reward for LINK donations.

### 4d. Worst Case with a Manipulated Price Feed

A vault owner who sets a manipulated price feed could:
- **Inflate BURNIE rewards:** Set a feed that reports an extremely high LINK/ETH price, causing excessive BURNIE minting per LINK donation. Impact: BURNIE inflation. Severity: Low -- BURNIE is a utility token with no direct ETH backing, and the attacker would need to also donate LINK to benefit.
- **Suppress BURNIE rewards:** Set a feed that reports zero or negative, causing `_linkAmountToEth` to return 0. Impact: LINK donors receive no rewards. Severity: Low -- LINK is still forwarded to subscription; only rewards are affected.
- **DoS via revert:** Set a feed whose `latestRoundData()` reverts. Impact: None -- try/catch in `onTokenTransfer` catches the revert, LINK is still forwarded, donor just gets no reward.

**Conclusion:** A malicious price feed can only affect BURNIE reward amounts, not ETH flows or VRF functionality. The `FeedHealthy` guard prevents replacing a working feed. This is an accepted trust assumption for the owner role.

---

## 5. _linkAmountToEth External View Audit

### 5a. Confirmed View (No State Modification)

```solidity
function _linkAmountToEth(uint256 amount) external view returns (uint256 ethAmount) {
```

**Confirmed:** `view` modifier. Cannot modify any state. The Solidity compiler enforces this at the EVM level.

### 5b. Why Is It External?

The function is `external` (not `internal` or `public`) to enable the try/catch pattern in `onTokenTransfer`:

```solidity
try this._linkAmountToEth(amount) returns (uint256 eth) { ... } catch { ... }
```

Solidity requires `this.` prefix for try/catch on the same contract's functions, which requires `external` visibility. This is a standard Solidity pattern for isolating potential reverts.

### 5c. Can an External Caller Call It?

**Yes.** Any address can call `_linkAmountToEth`. It simply reads the price feed and returns a LINK-to-ETH conversion. This is equivalent to reading a public price feed directly.

### 5d. Does It Reveal Sensitive Information?

**No.** It reveals the LINK/ETH price from a Chainlink oracle, which is already publicly accessible. No internal protocol state is exposed beyond what is already public (`linkEthPriceFeed` is a public state variable).

### 5e. Can It Be Used as an Oracle by Other Contracts?

Technically yes -- another contract could call `admin._linkAmountToEth(amount)` to get a LINK/ETH conversion. However:
- The underlying price feed is publicly accessible on Chainlink.
- This function adds no additional information beyond the Chainlink feed.
- It includes staleness checks (which makes it slightly more useful than raw feed access).
- There is no economic impact on the Degenerus protocol from external read calls.

**Conclusion:** Harmless external view. No concern.

---

## 6. wireVrf and updateVrfCoordinatorAndSub Audit (Admin -> Game)

### 6a. wireVrf

**Called by:** DegenerusAdmin constructor (line 382).
**Implemented in:** DegenerusGameAdvanceModule (line 301), executed via delegatecall from DegenerusGame (line 346).

```solidity
// AdvanceModule lines 305-313
function wireVrf(address coordinator_, uint256 subId, bytes32 keyHash_) external {
    if (msg.sender != ContractAddresses.ADMIN) revert E();
    address current = address(vrfCoordinator);
    vrfCoordinator = IVRFCoordinator(coordinator_);
    vrfSubscriptionId = subId;
    vrfKeyHash = keyHash_;
    emit VrfCoordinatorUpdated(current, coordinator_);
}
```

**Gate on Game side:** `msg.sender != ContractAddresses.ADMIN` -- compile-time constant check.

**Re-initialization guard:** There is NO explicit re-initialization guard. The function can be called multiple times by ADMIN, and each call overwrites `vrfCoordinator`, `vrfSubscriptionId`, and `vrfKeyHash`. However:
- Only DegenerusAdmin can call it (`msg.sender == ADMIN`).
- DegenerusAdmin only calls it in the constructor (once, at deployment).
- There is no other path in DegenerusAdmin that calls `wireVrf` post-deployment.
- Even if called again, it would just overwrite with the same values (no harm).

**What if called with address(0)?** The function does not validate the coordinator address. If called with `address(0)`, VRF requests would fail (calls to address(0) revert or return empty). However, this can only happen if ADMIN's constructor passes address(0), which it does not (it passes `ContractAddresses.VRF_COORDINATOR`, a compile-time constant).

**Finding: None.** The lack of re-initialization guard is not exploitable because the only caller (Admin constructor) runs once.

### 6b. updateVrfCoordinatorAndSub

**Called by:** `DegenerusAdmin.emergencyRecover` (line 508).
**Implemented in:** DegenerusGameAdvanceModule (line 1133), executed via delegatecall from DegenerusGame (line 1896).

```solidity
// AdvanceModule lines 1133-1153
function updateVrfCoordinatorAndSub(
    address newCoordinator, uint256 newSubId, bytes32 newKeyHash
) external {
    if (msg.sender != ContractAddresses.ADMIN) revert E();
    if (!_threeDayRngGap(_simulatedDayIndex())) revert VrfUpdateNotReady();

    address current = address(vrfCoordinator);
    vrfCoordinator = IVRFCoordinator(newCoordinator);
    vrfSubscriptionId = newSubId;
    vrfKeyHash = newKeyHash;

    // Reset RNG state to allow immediate advancement
    rngLockedFlag = false;
    vrfRequestId = 0;
    rngRequestTime = 0;
    rngWordCurrent = 0;
    emit VrfCoordinatorUpdated(current, newCoordinator);
}
```

**Gate on Game side:** TWO gates:
1. `msg.sender != ContractAddresses.ADMIN` -- only Admin contract.
2. `!_threeDayRngGap(_simulatedDayIndex())` -- requires 3 consecutive days without VRF words.

**Gate on Admin side (emergencyRecover):** TWO additional gates:
1. `onlyOwner` -- CREATOR or vault owner.
2. `!gameAdmin.rngStalledForThreeDays()` -- same 3-day check via Game's public function.

**Double-gating analysis:** The `_threeDayRngGap` check exists on BOTH sides (Admin calls `gameAdmin.rngStalledForThreeDays()` which calls `_threeDayRngGap`, then Game's `updateVrfCoordinatorAndSub` also calls `_threeDayRngGap`). This is defense-in-depth -- even if the Admin check were bypassed (impossible with current code), the Game-side check would still enforce the stall requirement.

**Can a vault owner rotate to a malicious coordinator?**

If a vault owner (>30% DGVE) has access AND a genuine 3-day stall exists, they could point the system to a malicious VRF coordinator. This would allow them to:
- Control VRF randomness (submit predetermined "random" words).
- Potentially manipulate game outcomes (jackpots, lootboxes, etc.).

**This is an ACCEPTED TRUST ASSUMPTION.** A vault owner with >30% of DGVE has enormous economic exposure to the protocol. Attacking the protocol's randomness would destroy their own investment. The 3-day stall requirement ensures this power is only available during genuine VRF failures, not during normal operation.

---

## 7. External Caller Griefing Scenarios

### 7a. Block LINK Funding

**Attack:** Prevent LINK from being sent to the VRF subscription.

**Analysis:**
- `onTokenTransfer` is only callable by the LINK contract (compile-time address).
- `LINK.transferAndCall` is a standard ERC-677 call. No approvals or intermediate steps can be front-run.
- The coordinator address is immutable during normal operation (only changeable during 3-day stall via `onlyOwner`).
- The subscription ID is immutable during normal operation.

**Verdict: NOT FEASIBLE.** No griefing vector exists for external callers.

### 7b. Drain Subscription LINK

**Attack:** Withdraw LINK from the VRF subscription.

**Analysis:**
- `emergencyRecover`: Requires `onlyOwner` AND `rngStalledForThreeDays()`. Even then, LINK is recycled to a new subscription, not extracted.
- `shutdownAndRefund`: Requires `onlyOwner` AND `gameOver()`. Terminal state -- protocol is ending.
- No other function touches subscription LINK.
- The subscription is owned by DegenerusAdmin (not any EOA), and only DegenerusAdmin can call `cancelSubscription` on the coordinator.

**Verdict: NOT FEASIBLE.** No external caller can drain LINK. Owner can only recycle LINK (recovery) or sweep post-game-over (terminal).

### 7c. Disconnect Coordinator

**Attack:** Change the VRF coordinator to break randomness.

**Analysis:**
- `updateVrfCoordinatorAndSub` requires: ADMIN access (only DegenerusAdmin) + `_threeDayRngGap` (3-day VRF stall).
- `emergencyRecover` is the only path to call `updateVrfCoordinatorAndSub`, requiring `onlyOwner` + `rngStalledForThreeDays()`.
- Triple-gated: Admin.onlyOwner + Admin.rngStalledForThreeDays + Game._threeDayRngGap.

**Verdict: NOT FEASIBLE.** No external caller can disconnect the coordinator. Owner can only rotate during genuine stalls.

### 7d. Front-Run VRF Requests

**Attack:** Insert a fraudulent VRF request to manipulate outcomes.

**Analysis:**
- VRF requests are made by the Game contract (via AdvanceModule) to the Chainlink coordinator.
- DegenerusAdmin does NOT make VRF requests -- it only manages the subscription (funding, lifecycle).
- VRF fulfillment goes through `rawFulfillRandomWords`, which validates `msg.sender == vrfCoordinator` (AUTH-02).
- An attacker cannot insert requests because they are not a consumer on the subscription, and only DegenerusAdmin can add consumers.

**Verdict: NOT FEASIBLE.** VRF request integrity is maintained by Chainlink's coordinator contract.

### 7e. DoS on onTokenTransfer via Bad Price Feed

**Attack:** Cause `onTokenTransfer` to revert by exploiting the price feed.

**Analysis:**

The execution flow in `onTokenTransfer` is:
1. Validate sender (LINK contract).
2. Forward LINK to subscription (lines 612-618). **If this fails, revert.**
3. Convert LINK to ETH via `_linkAmountToEth` (lines 623-628). **If this fails, catch and return.**
4. Credit BURNIE reward (line 636).

**Critical order:** LINK forwarding (step 2) happens BEFORE price feed access (step 3). If the price feed reverts, LINK is already in the subscription. The try/catch on `_linkAmountToEth` catches any revert and returns silently (LINK forwarded, no reward).

**Can a vault owner block funding by setting a bad feed?**

**No.** Even with a feed that always reverts:
- LINK forwarding succeeds (step 2 is before step 3).
- `_linkAmountToEth` reverts, caught by try/catch.
- Function returns without reward, but LINK is safely in the subscription.

**Can the LINK forwarding itself (step 2) revert?**

Only if:
- The coordinator does not accept LINK via `transferAndCall` (would be a Chainlink bug, not a protocol issue).
- The subscription ID is invalid (impossible during normal operation -- set at deployment).

**Verdict: NOT FEASIBLE.** The defense-in-depth ordering (fund first, calculate reward second) prevents any DoS on LINK funding.

---

## 8. shutdownAndRefund Audit

This function was not in the plan's explicit scope but is VRF-related and merits inclusion.

```solidity
function shutdownAndRefund(address target) external onlyOwner {
    if (target == address(0)) revert ZeroAddress();
    uint256 subId = subscriptionId;
    if (subId == 0) revert NoSubscription();
    if (!gameAdmin.gameOver()) revert GameNotOver();

    IVRFCoordinatorV2_5Owner(coordinator).cancelSubscription(subId, target);
    subscriptionId = 0;

    uint256 bal = linkToken.balanceOf(address(this));
    if (bal != 0) {
        if (!linkToken.transfer(target, bal)) revert LinkTransferFailed();
    }
}
```

**Gates:** `onlyOwner` + `gameOver()`. The `gameOver` flag is terminal (set once during multi-step game-over process, never unset).

**LINK destination:** The `target` parameter is owner-specified. LINK from subscription cancellation goes to `target`, and any LINK balance on DegenerusAdmin is also transferred to `target`.

**Risk:** An owner could sweep LINK to themselves. However, this is only possible after game-over (terminal state), when VRF is no longer needed. This is expected behavior -- post-game-over LINK recovery.

**Verdict: No griefing concern.** Terminal-state-only function with appropriate gating.

---

## 9. Informational Observations

### 9a. subscriptionId uint64 Truncation

`DegenerusAdmin` stores `subscriptionId` as `uint64` (line 314), with a `uint64(subId)` downcast from the `uint256` returned by `createSubscription()` (line 372). DegenerusGame stores `vrfSubscriptionId` as `uint256` (GameStorage line 1178).

Chainlink VRF V2.5 uses `uint256` subscription IDs. The `uint64` truncation in Admin is safe IF subscription IDs never exceed `2^64 - 1`. Current Chainlink subscriptions are far below this limit. The `uint64` type matches the coordinator's `getSubscription` return type (`uint64 reqCount`), suggesting this is consistent with Chainlink's practical ID range. However, the Admin's truncated `uint64` is upcast back to `uint256` when passed to the coordinator (e.g., `cancelSubscription`), which preserves the truncated value.

**Severity: Informational.** No practical risk with current Chainlink subscription IDs.

### 9b. _threeDayRngGap Duplication

`_threeDayRngGap` is identically implemented in both `DegenerusGame` (line 2229) and `DegenerusGameAdvanceModule` (line 1258). Previously documented as maintenance risk in Phase 02 state. Both implementations are byte-identical, so no security concern -- only a maintenance smell.

### 9c. Emergency Recover try/catch on cancelSubscription

```solidity
try IVRFCoordinatorV2_5Owner(oldCoord).cancelSubscription(oldSub, address(this)) {
    emit SubscriptionCancelled(oldSub, address(this));
} catch {}
```

The `catch {}` silently swallows any cancellation failure. This is intentional -- if the old coordinator is broken (which is why we're doing emergency recovery), cancellation might fail. The new subscription is created regardless. Any LINK stuck in the old subscription is lost. This is an acceptable trade-off for recovery from a broken coordinator.

---

## 10. AUTH-06 Verdict

### Requirement

> DegenerusAdmin VRF subscription management cannot be griefed by external callers.

### Analysis Summary

| Vector | Feasibility | Reasoning |
|--------|------------|-----------|
| Block LINK funding | NOT FEASIBLE | `onTokenTransfer` only callable by LINK contract (compile-time constant) |
| Drain subscription LINK | NOT FEASIBLE | Only `emergencyRecover` (stall-gated, recycles) and `shutdownAndRefund` (game-over-gated) |
| Disconnect coordinator | NOT FEASIBLE | Triple-gated: onlyOwner + Admin stall check + Game stall check |
| Front-run VRF requests | NOT FEASIBLE | VRF requests made by Game, not Admin; consumer list restricted |
| DoS on LINK funding | NOT FEASIBLE | LINK forwarded before price feed access; try/catch prevents revert propagation |

### Access Control Completeness

- All 6 external state-changing functions have appropriate access gates.
- `onlyOwner` gates correctly permit CREATOR and >30% DGVE vault owners.
- `onTokenTransfer` correctly validates `msg.sender == LINK_TOKEN`.
- `emergencyRecover` correctly requires `rngStalledForThreeDays` (genuine VRF failure).
- `shutdownAndRefund` correctly requires `gameOver()` (terminal state).
- `_linkAmountToEth` is harmless external view.
- No function lacks an access gate that should have one.

### Trust Assumptions

The vault owner (>30% DGVE) is trusted with:
1. Setting price feeds (affects BURNIE rewards only, not ETH flows).
2. Rotating VRF coordinator during 3-day stalls (accepted: economic alignment).
3. Choosing LINK sweep target after game-over (accepted: terminal state).
4. Staking/swapping ETH-stETH on the Game contract (accepted: liquidity management).

These are all appropriate for an entity with >30% economic stake in the protocol.

### VERDICT: AUTH-06 PASS

All VRF-related functions in DegenerusAdmin are correctly gated. No external caller (non-owner, non-LINK-contract) can grief, disrupt, or exploit VRF subscription management. The defense-in-depth design (LINK forwarded before reward calculation, double-gated stall checks, compile-time immutable addresses) provides robust protection against all analyzed attack vectors.

**Findings:** 0 HIGH, 0 MEDIUM, 0 LOW, 3 INFORMATIONAL (subscriptionId uint64 truncation, _threeDayRngGap duplication, vault owner coordinator rotation trust assumption).
