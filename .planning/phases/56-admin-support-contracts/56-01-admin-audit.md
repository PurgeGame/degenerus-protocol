# DegenerusAdmin.sol -- Function-Level Audit

**Contract:** DegenerusAdmin
**File:** contracts/DegenerusAdmin.sol
**Lines:** 750
**Solidity:** 0.8.34
**Audit date:** 2026-03-07

## Summary

Central administration contract managing VRF subscription lifecycle (create, fund, recover, shutdown), emergency recovery with a 3-day stall gate, LINK donation handling via ERC-677 with tiered reward multiplier (3x-to-0x based on subscription balance), Chainlink LINK/ETH price feed health validation, and owner access control via DGVE majority (>50.1% supply). The contract uses compile-time constant addresses from ContractAddresses.sol and deploys atomically with VRF subscription creation and Game consumer wiring.

---

## Function Audit

### Constructor / Initialization

---

### `constructor()` [public]

| Field | Value |
|-------|-------|
| **Signature** | `constructor()` |
| **Visibility** | public (constructor) |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | N/A |

**State Reads:**
- `ContractAddresses.VRF_COORDINATOR` (compile-time constant)
- `ContractAddresses.VRF_KEY_HASH` (compile-time constant)
- `ContractAddresses.GAME` (compile-time constant)

**State Writes:**
- `coordinator` = `ContractAddresses.VRF_COORDINATOR`
- `subscriptionId` = newly created subscription ID from VRF coordinator
- `vrfKeyHash` = `ContractAddresses.VRF_KEY_HASH`

**Callers:** Deployment transaction only (once).

**Callees:**
- `vrfCoordinator.createSubscription()` -- creates VRF subscription
- `vrfCoordinator.addConsumer(subId, ContractAddresses.GAME)` -- registers Game as consumer
- `gameAdmin.wireVrf(VRF_COORDINATOR, subId, VRF_KEY_HASH)` -- pushes VRF config to Game

**ETH Flow:** None.

**Invariants:**
- After construction: `coordinator != address(0)`, `subscriptionId != 0`, `vrfKeyHash != bytes32(0)`
- Game contract is registered as a consumer on the VRF coordinator
- Game contract has VRF coordinator, subscription ID, and key hash configured

**NatSpec Accuracy:** Accurate. States "no constructor parameters" and "VRF config from ContractAddresses" -- both true. States "atomically creates new VRF subscription and wires the Game consumer" -- verified.

**Gas Flags:** None. All three external calls are necessary and non-redundant.

**Verdict:** CORRECT

---

### External -- Admin Operations

---

### `setLinkEthPriceFeed(address feed)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function setLinkEthPriceFeed(address feed) external onlyOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `feed` (address): New Chainlink LINK/ETH price feed address, or zero to disable |
| **Returns** | None |

**State Reads:**
- `linkEthPriceFeed` (current feed, via local `current`)
- `vault.isVaultOwner(msg.sender)` (via `onlyOwner` modifier)

**State Writes:**
- `linkEthPriceFeed` = `feed`

**Callers:** External only, any address holding >50.1% DGVE.

**Callees:**
- `vault.isVaultOwner(msg.sender)` (via `onlyOwner`)
- `_feedHealthy(current)` -- checks health of current feed
- `IAggregatorV3(feed).decimals()` -- validates new feed has 18 decimals (only if feed != address(0))

**ETH Flow:** None.

**Invariants:**
- Can only replace an unhealthy or zero-address feed (FeedHealthy guard)
- If new feed is non-zero, it must report exactly 18 decimals
- Zero-address feed disables oracle-based LINK reward valuation

**NatSpec Accuracy:** Accurate. States "zero address disables oracle-based valuation" -- correct. States "only replaceable if current feed is unhealthy" -- correct, `_feedHealthy` returns false for address(0) so initial set is allowed. States "enforces 18 decimals" -- verified.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `swapGameEthForStEth()` [external payable]

| Field | Value |
|-------|-------|
| **Signature** | `function swapGameEthForStEth() external payable onlyOwner` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | None (uses msg.value) |
| **Returns** | None |

**State Reads:**
- `vault.isVaultOwner(msg.sender)` (via `onlyOwner`)

**State Writes:** None (state changes happen in Game contract).

**Callers:** External only, any address holding >50.1% DGVE.

**Callees:**
- `vault.isVaultOwner(msg.sender)` (via `onlyOwner`)
- `gameAdmin.adminSwapEthForStEth{value: msg.value}(msg.sender, msg.value)` -- forwards ETH to Game, receives stETH back to msg.sender

**ETH Flow:** msg.sender sends ETH via msg.value -> forwarded to Game contract. Game sends stETH to msg.sender.

**Invariants:**
- `msg.value > 0` (InvalidAmount guard)
- ETH and stETH amounts match 1:1 (enforced by Game contract)
- stETH goes to msg.sender (owner), not an arbitrary recipient

**NatSpec Accuracy:** Accurate. States "swap owner ETH for GAME-held stETH (1:1 exchange)" and "stETH sent to msg.sender (owner)" -- both verified. Note: NatSpec says "not arbitrary address" which is correct since recipient is hardcoded to `msg.sender`.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `stakeGameEthToStEth(uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function stakeGameEthToStEth(uint256 amount) external onlyOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `amount` (uint256): Amount of ETH to stake into stETH via Lido |
| **Returns** | None |

**State Reads:**
- `vault.isVaultOwner(msg.sender)` (via `onlyOwner`)

**State Writes:** None (state changes happen in Game contract).

**Callers:** External only, any address holding >50.1% DGVE.

**Callees:**
- `vault.isVaultOwner(msg.sender)` (via `onlyOwner`)
- `gameAdmin.adminStakeEthForStEth(amount)` -- instructs Game to stake ETH to stETH via Lido

**ETH Flow:** None directly (ETH conversion happens inside Game contract).

**Invariants:**
- Owner can convert Game-held idle ETH to yield-bearing stETH
- No ETH enters or leaves Admin contract

**NatSpec Accuracy:** Accurate. States "converts idle ETH to yield-bearing stETH" and "amount of ETH to stake" -- both verified. Note: no zero-amount check here; relies on Game contract validation.

**Gas Flags:** No zero-amount guard on this function (unlike swapGameEthForStEth). The Game contract is expected to handle validation. This is consistent -- staking zero would be a no-op or revert in Lido, not a security issue.

**Verdict:** CORRECT

---

### `setLootboxRngThreshold(uint256 newThreshold)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function setLootboxRngThreshold(uint256 newThreshold) external onlyOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `newThreshold` (uint256): New RNG request threshold in wei |
| **Returns** | None |

**State Reads:**
- `vault.isVaultOwner(msg.sender)` (via `onlyOwner`)

**State Writes:** None (state changes happen in Game contract).

**Callers:** External only, any address holding >50.1% DGVE.

**Callees:**
- `vault.isVaultOwner(msg.sender)` (via `onlyOwner`)
- `gameAdmin.setLootboxRngThreshold(newThreshold)` -- sets threshold in Game contract

**ETH Flow:** None.

**Invariants:**
- Only owner can change lootbox RNG threshold
- Validation of threshold range delegated to Game contract

**NatSpec Accuracy:** Minimal but accurate. States "update lootbox RNG request threshold (wei)" -- verified.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `emergencyRecover(address newCoordinator, bytes32 newKeyHash)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function emergencyRecover(address newCoordinator, bytes32 newKeyHash) external onlyOwner returns (uint256 newSubId)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `newCoordinator` (address): Address of the new VRF coordinator; `newKeyHash` (bytes32): Key hash for the new coordinator |
| **Returns** | `newSubId` (uint256): The newly created subscription ID |

**State Reads:**
- `subscriptionId` (must be non-zero -- NotWired guard)
- `coordinator` (old coordinator address for cancellation)
- `vault.isVaultOwner(msg.sender)` (via `onlyOwner`)
- `gameAdmin.rngStalledForThreeDays()` (3-day stall gate)
- `linkToken.balanceOf(address(this))` (check for residual LINK)

**State Writes:**
- `coordinator` = `newCoordinator`
- `subscriptionId` = `newSubId` (from new coordinator's createSubscription)
- `vrfKeyHash` = `newKeyHash`

**Callers:** External only, any address holding >50.1% DGVE.

**Callees:**
- `vault.isVaultOwner(msg.sender)` (via `onlyOwner`)
- `gameAdmin.rngStalledForThreeDays()` -- verifies 3-day stall condition
- `IVRFCoordinatorV2_5Owner(oldCoord).cancelSubscription(oldSub, address(this))` -- cancels old subscription (try/catch)
- `IVRFCoordinatorV2_5Owner(newCoordinator).createSubscription()` -- creates new subscription
- `IVRFCoordinatorV2_5Owner(newCoordinator).addConsumer(newSubId, GAME)` -- adds Game as consumer
- `gameAdmin.updateVrfCoordinatorAndSub(newCoordinator, newSubId, newKeyHash)` -- pushes new config to Game
- `linkToken.balanceOf(address(this))` -- checks LINK balance
- `linkToken.transferAndCall(newCoordinator, bal, abi.encode(newSubId))` -- funds new subscription (try/catch)

**ETH Flow:** None.

**Invariants:**
- Pre-condition: `subscriptionId != 0` (NotWired), `gameAdmin.rngStalledForThreeDays() == true` (NotStalled), `newCoordinator != address(0)`, `newKeyHash != bytes32(0)` (ZeroAddress)
- Post-condition: coordinator, subscriptionId, and vrfKeyHash all updated to new values; Game contract config updated atomically; any LINK on this contract forwarded to new subscription
- Old subscription cancelled (best-effort via try/catch -- may fail if coordinator is unresponsive)

**NatSpec Accuracy:** Accurate and thorough. Execution order documented as 6 steps matches implementation exactly. Security notes about 3-day stall, try/catch on cancel, non-zero checks, and atomic Game update all verified.

**Gas Flags:** None. The try/catch patterns are necessary for resilience against unresponsive old coordinators.

**Verdict:** CORRECT

---

### External -- VRF Lifecycle

---

### `shutdownVrf()` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function shutdownVrf() external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | None |

**State Reads:**
- `subscriptionId` (checked for zero / early return)
- `coordinator` (used for cancelSubscription call)
- `linkToken.balanceOf(address(this))` (check for residual LINK)

**State Writes:**
- `subscriptionId` = 0 (prevents re-use)

**Callers:** DegenerusGame contract only (during `handleFinalSweep`).

**Callees:**
- `IVRFCoordinatorV2_5Owner(coordinator).cancelSubscription(subId, VAULT)` -- cancels subscription, LINK refund to vault (try/catch)
- `linkToken.balanceOf(address(this))` -- checks for residual LINK
- `linkToken.transfer(VAULT, bal)` -- sweeps residual LINK to vault (try/catch)

**ETH Flow:** None (LINK flow only: subscription LINK refunded to VAULT, residual LINK swept to VAULT).

**Invariants:**
- Only Game contract can call (NotAuthorized guard: `msg.sender == ContractAddresses.GAME`)
- After execution: `subscriptionId == 0` (idempotent -- returns early if already 0)
- All LINK ends up at VAULT address (either via cancelSubscription refund or direct transfer)
- Uses try/catch so caller (Game) can safely fire-and-forget without reverting

**NatSpec Accuracy:** Accurate. States "only callable by the GAME contract (during handleFinalSweep)" -- verified via NotAuthorized check. States "LINK refunded to VAULT address" and "sets subscriptionId to 0 to prevent re-use" -- both verified.

**Gas Flags:** The SubscriptionShutdown event is emitted in two paths: once with `bal` when LINK sweep succeeds (line 567), and once with 0 at the end (line 573). If the cancelSubscription succeeds but LINK sweep fails (or bal is 0), the event correctly reports 0. If both succeed, only the first emit fires (due to `return` on line 568). This is correct -- no duplicate events.

**Verdict:** CORRECT

---

### External -- ERC-677 Callback

---

### `onTokenTransfer(address from, uint256 amount, bytes calldata)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function onTokenTransfer(address from, uint256 amount, bytes calldata) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): Address that sent the LINK; `amount` (uint256): Amount of LINK received; third parameter (bytes calldata): unused |
| **Returns** | None |

**State Reads:**
- `subscriptionId` (must be non-zero)
- `coordinator` (for VRF getSubscription and transferAndCall)
- `linkEthPriceFeed` (indirectly via `this._linkAmountToEth`)

**State Writes:** None directly (reward crediting happens in BurnieCoin via `coinLinkReward.creditLinkReward`).

**Callers:** LINK token contract only (via ERC-677 transferAndCall).

**Callees:**
- `gameAdmin.gameOver()` -- checks if game is over (GameOver guard)
- `IVRFCoordinatorV2_5Owner(coord).getSubscription(subId)` -- reads current subscription balance for multiplier calculation
- `_linkRewardMultiplier(uint256(bal))` -- calculates tiered reward multiplier
- `linkToken.transferAndCall(coord, amount, abi.encode(subId))` -- forwards LINK to VRF subscription
- `this._linkAmountToEth(amount)` -- converts LINK to ETH-equivalent (external self-call for try/catch)
- `gameAdmin.purchaseInfo()` -- gets current ticket price
- `coinLinkReward.creditLinkReward(from, credit)` -- credits BURNIE reward to donor

**ETH Flow:** None (LINK flow: donor -> Admin contract -> VRF subscription; BURNIE credit: calculated and credited to donor).

**Invariants:**
- Only LINK token contract can call (`msg.sender == ContractAddresses.LINK_TOKEN`)
- `amount > 0` (InvalidAmount guard)
- `subscriptionId != 0` (NoSubscription guard)
- Game must not be over (GameOver guard)
- LINK is always forwarded to VRF subscription (even if reward calculation fails)
- Reward multiplier calculated BEFORE forwarding LINK (uses pre-donation subscription balance)
- Multiple early-return safeguards: mult==0, ethEquivalent==0, priceWei==0, credit==0

**NatSpec Accuracy:** Accurate and detailed. The 5-step flow documentation matches implementation:
1. Validate sender is LINK -- verified (line 604)
2. Calculate reward multiplier based on current subscription balance -- verified (lines 615-618, uses balance BEFORE forwarding)
3. Forward LINK to VRF subscription -- verified (lines 621-627)
4. Convert LINK to ETH-equivalent using price feed -- verified (lines 632-638)
5. Credit BURNIE reward to donor -- verified (lines 641-648)

Security note about "multiplier decreases as subscription fills" -- verified by _linkRewardMultiplier tiered structure.

**Gas Flags:** The external self-call `this._linkAmountToEth(amount)` at line 633 is used to enable try/catch on a view function. This incurs additional gas from the external call overhead but is necessary since Solidity does not support try/catch on internal calls. This is a standard pattern.

**Verdict:** CORRECT

---

### External -- View

---

### `_linkAmountToEth(uint256 amount)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function _linkAmountToEth(uint256 amount) external view returns (uint256 ethAmount)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `amount` (uint256): LINK amount in 18 decimals |
| **Returns** | `ethAmount` (uint256): ETH-equivalent amount in 18 decimals, or 0 if unavailable |

**State Reads:**
- `linkEthPriceFeed` (price feed address)

**State Writes:** None (view function).

**Callers:**
- `onTokenTransfer` (via external self-call `this._linkAmountToEth(amount)`)
- Any external caller (publicly accessible)

**Callees:**
- `IAggregatorV3(feed).latestRoundData()` -- fetches latest LINK/ETH price

**ETH Flow:** None.

**Invariants:**
- Returns 0 if: feed is address(0), amount is 0, answer <= 0, updatedAt == 0, answeredInRound < roundId, updatedAt > block.timestamp, or staleness exceeds LINK_ETH_MAX_STALE (1 day)
- Assumes feed returns 18-decimal price (Chainlink LINK/ETH standard)
- Formula: `ethAmount = (amount * uint256(answer)) / 1 ether` -- correct for 18-decimal feed and 18-decimal LINK input

**NatSpec Accuracy:** Mostly accurate. States "exposed as external to allow try/catch in onTokenTransfer" -- verified. Notes about returning 0 on missing feed, zero amount, invalid price, stale rounds -- all verified. One naming note: the underscore prefix conventionally implies internal/private, but the function is external. The dev NatSpec explains this is intentional for the try/catch pattern.

**Gas Flags:** The unchecked block for staleness check (line 680-682) is safe: `block.timestamp - updatedAt` cannot underflow because `updatedAt > block.timestamp` is checked on line 679.

**Verdict:** CORRECT -- Informational: underscore-prefixed external function is unconventional but necessary for the try/catch pattern and documented in NatSpec.

---

### Private -- Helpers

---

### `_linkRewardMultiplier(uint256 subBal)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _linkRewardMultiplier(uint256 subBal) private pure returns (uint256 mult)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `subBal` (uint256): Current VRF subscription LINK balance in 18 decimals |
| **Returns** | `mult` (uint256): Reward multiplier in 18-decimal fixed point (e.g., 3e18 = 3x) |

**State Reads:** None (pure function).

**State Writes:** None (pure function).

**Callers:**
- `onTokenTransfer` (line 618)

**Callees:** None.

**ETH Flow:** None.

**Invariants:**
- Tiered structure verified:
  - `subBal >= 1000 ether` -> returns 0 (fully funded, no reward)
  - `subBal <= 200 ether` -> linear from 3e18 (at 0) to 1e18 (at 200 ether)
    - At 0: `delta = 0`, returns `3e18 - 0 = 3e18` (3x) -- correct
    - At 100 ether: `delta = (100e18 * 2e18) / 200e18 = 1e18`, returns `3e18 - 1e18 = 2e18` (2x) -- correct
    - At 200 ether: `delta = (200e18 * 2e18) / 200e18 = 2e18`, returns `3e18 - 2e18 = 1e18` (1x) -- correct
  - `200 ether < subBal < 1000 ether` -> linear from 1e18 (at 200) to 0 (at 1000)
    - At 600 ether: `excess = 400e18`, `delta2 = (400e18 * 1e18) / 800e18 = 0.5e18`, returns `1e18 - 0.5e18 = 0.5e18` (0.5x) -- correct
    - At 1000 ether: `excess = 800e18`, `delta2 = (800e18 * 1e18) / 800e18 = 1e18`, hits `delta2 >= 1e18` guard, returns 0 -- correct
- Unchecked blocks are safe: `3e18 - delta` where delta <= 2e18; `1e18 - delta2` where delta2 < 1e18

**NatSpec Accuracy:** Accurate. Tiered structure documentation matches implementation exactly. Boundary values verified.

**Gas Flags:** None. The `delta2 >= 1e18` guard on line 709 is technically only reachable at exactly `subBal == 1000 ether`, which is already handled by the first check on line 698. However, for `subBal` values very close to 1000 ether (e.g., 999.999...ether), rounding could theoretically push delta2 to exactly 1e18. The guard is defensive and correct.

**Verdict:** CORRECT

---

### `_feedHealthy(address feed)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _feedHealthy(address feed) private view returns (bool)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `feed` (address): Price feed address to check |
| **Returns** | `bool`: True if feed is responding with valid, fresh data |

**State Reads:** None directly (reads external feed state).

**State Writes:** None (view function).

**Callers:**
- `setLinkEthPriceFeed` (line 414)

**Callees:**
- `IAggregatorV3(feed).latestRoundData()` -- fetches latest price data (try/catch)
- `IAggregatorV3(feed).decimals()` -- checks decimal precision (nested try/catch)

**ETH Flow:** None.

**Invariants:**
- Returns false if: feed is address(0), latestRoundData reverts, answer <= 0, updatedAt == 0, answeredInRound < roundId, updatedAt > block.timestamp, staleness exceeds LINK_ETH_MAX_STALE (1 day), decimals() reverts, or decimals != 18
- Returns true only if ALL health checks pass
- Nested try/catch pattern: outer try/catch for latestRoundData, inner try/catch for decimals -- both must succeed

**NatSpec Accuracy:** Accurate. Documents all three health checks: answer > 0, freshness, answeredInRound >= roundId. Also checks decimals which is mentioned in the `setLinkEthPriceFeed` NatSpec.

**Gas Flags:** The function performs two external calls (latestRoundData + decimals) with try/catch each. This is slightly more gas than combining them but ensures proper error isolation. Acceptable for an admin-only path.

**Verdict:** CORRECT

---

### `onlyOwner()` [modifier]

| Field | Value |
|-------|-------|
| **Signature** | `modifier onlyOwner()` |
| **Visibility** | N/A (modifier) |
| **Mutability** | view (reads external state) |
| **Parameters** | None |
| **Returns** | N/A |

**State Reads:**
- `vault.isVaultOwner(msg.sender)` -- external call to Vault contract

**State Writes:** None.

**Callers:** Applied to: `setLinkEthPriceFeed`, `swapGameEthForStEth`, `stakeGameEthToStEth`, `setLootboxRngThreshold`, `emergencyRecover`

**Callees:**
- `vault.isVaultOwner(msg.sender)` -- checks if caller holds >50.1% of DGVE supply

**ETH Flow:** None.

**Invariants:**
- Reverts with NotOwner if caller does not hold >50.1% DGVE
- Ownership is dynamic -- changes with DGVE token transfers
- No single-address owner pattern; market-based ownership

**NatSpec Accuracy:** Accurate. States "restricts function to anyone holding >50.1% of DGVE" -- verified.

**Gas Flags:** External call on every modifier invocation. Necessary for dynamic ownership model.

**Verdict:** CORRECT

---

## Access Control Matrix

| Modifier/Guard | Functions | Who Can Call |
|----------------|-----------|-------------|
| `onlyOwner` (DGVE >50.1%) | `setLinkEthPriceFeed`, `swapGameEthForStEth`, `stakeGameEthToStEth`, `setLootboxRngThreshold`, `emergencyRecover` | Any address holding >50.1% of DGVE supply |
| Game-only (`msg.sender == GAME`) | `shutdownVrf` | DegenerusGame contract only |
| LINK-only (`msg.sender == LINK_TOKEN`) | `onTokenTransfer` | LINK token contract only (via ERC-677 transferAndCall) |
| None (unrestricted) | `_linkAmountToEth` | Any external caller |
| Constructor | `constructor` | Deployer (once) |
| Private | `_linkRewardMultiplier`, `_feedHealthy` | Internal only |

## Storage Mutation Map

| Function | Variables Written | Write Type |
|----------|------------------|------------|
| `constructor` | `coordinator`, `subscriptionId`, `vrfKeyHash` | Initialize all three VRF state variables |
| `setLinkEthPriceFeed` | `linkEthPriceFeed` | Replace price feed address |
| `emergencyRecover` | `coordinator`, `subscriptionId`, `vrfKeyHash` | Replace all three VRF state variables (migration) |
| `shutdownVrf` | `subscriptionId` | Set to 0 (permanent shutdown) |
| `swapGameEthForStEth` | (none) | Delegates to Game contract |
| `stakeGameEthToStEth` | (none) | Delegates to Game contract |
| `setLootboxRngThreshold` | (none) | Delegates to Game contract |
| `onTokenTransfer` | (none) | Delegates to BurnieCoin (credit) and VRF coordinator (fund) |
| `_linkAmountToEth` | (none) | View function |
| `_linkRewardMultiplier` | (none) | Pure function |
| `_feedHealthy` | (none) | View function |

**Storage variables summary:**
- `coordinator` (address): Written by constructor, emergencyRecover
- `subscriptionId` (uint256): Written by constructor, emergencyRecover, shutdownVrf
- `vrfKeyHash` (bytes32): Written by constructor, emergencyRecover
- `linkEthPriceFeed` (address): Written by setLinkEthPriceFeed

Total: 4 mutable storage variables. All writes are access-controlled.

## Cross-Contract Call Graph

| Function | Calls To | Contract | Method | Direction |
|----------|----------|----------|--------|-----------|
| `constructor` | VRFCoordinatorV2_5 | Chainlink | `createSubscription()` | outbound |
| `constructor` | VRFCoordinatorV2_5 | Chainlink | `addConsumer(subId, GAME)` | outbound |
| `constructor` | DegenerusGame | Game | `wireVrf(coord, subId, keyHash)` | outbound |
| `setLinkEthPriceFeed` | DegenerusVault | Vault | `isVaultOwner(msg.sender)` | outbound (modifier) |
| `setLinkEthPriceFeed` | Chainlink Feed | Chainlink | `decimals()` | outbound |
| `swapGameEthForStEth` | DegenerusVault | Vault | `isVaultOwner(msg.sender)` | outbound (modifier) |
| `swapGameEthForStEth` | DegenerusGame | Game | `adminSwapEthForStEth{value}(sender, amount)` | outbound (payable) |
| `stakeGameEthToStEth` | DegenerusVault | Vault | `isVaultOwner(msg.sender)` | outbound (modifier) |
| `stakeGameEthToStEth` | DegenerusGame | Game | `adminStakeEthForStEth(amount)` | outbound |
| `setLootboxRngThreshold` | DegenerusVault | Vault | `isVaultOwner(msg.sender)` | outbound (modifier) |
| `setLootboxRngThreshold` | DegenerusGame | Game | `setLootboxRngThreshold(threshold)` | outbound |
| `emergencyRecover` | DegenerusVault | Vault | `isVaultOwner(msg.sender)` | outbound (modifier) |
| `emergencyRecover` | DegenerusGame | Game | `rngStalledForThreeDays()` | outbound (view) |
| `emergencyRecover` | VRFCoordinatorV2_5 (old) | Chainlink | `cancelSubscription(oldSub, this)` | outbound (try/catch) |
| `emergencyRecover` | VRFCoordinatorV2_5 (new) | Chainlink | `createSubscription()` | outbound |
| `emergencyRecover` | VRFCoordinatorV2_5 (new) | Chainlink | `addConsumer(newSubId, GAME)` | outbound |
| `emergencyRecover` | DegenerusGame | Game | `updateVrfCoordinatorAndSub(coord, subId, keyHash)` | outbound |
| `emergencyRecover` | LINK Token | Chainlink | `balanceOf(this)` | outbound (view) |
| `emergencyRecover` | LINK Token | Chainlink | `transferAndCall(newCoord, bal, subId)` | outbound (try/catch) |
| `shutdownVrf` | VRFCoordinatorV2_5 | Chainlink | `cancelSubscription(subId, VAULT)` | outbound (try/catch) |
| `shutdownVrf` | LINK Token | Chainlink | `balanceOf(this)` | outbound (view) |
| `shutdownVrf` | LINK Token | Chainlink | `transfer(VAULT, bal)` | outbound (try/catch) |
| `onTokenTransfer` | DegenerusGame | Game | `gameOver()` | outbound (view) |
| `onTokenTransfer` | VRFCoordinatorV2_5 | Chainlink | `getSubscription(subId)` | outbound (view) |
| `onTokenTransfer` | LINK Token | Chainlink | `transferAndCall(coord, amount, subId)` | outbound |
| `onTokenTransfer` | DegenerusAdmin | Self | `_linkAmountToEth(amount)` | self-call (view) |
| `onTokenTransfer` | DegenerusGame | Game | `purchaseInfo()` | outbound (view) |
| `onTokenTransfer` | BurnieCoin | Coin | `creditLinkReward(from, credit)` | outbound |
| `_linkAmountToEth` | Chainlink Feed | Chainlink | `latestRoundData()` | outbound (view) |
| `_feedHealthy` | Chainlink Feed | Chainlink | `latestRoundData()` | outbound (view, try/catch) |
| `_feedHealthy` | Chainlink Feed | Chainlink | `decimals()` | outbound (view, try/catch) |

**Inbound calls to DegenerusAdmin:**
| From | Method | Trigger |
|------|--------|---------|
| LINK Token (ERC-677) | `onTokenTransfer` | LINK donation via `transferAndCall` |
| DegenerusGame | `shutdownVrf` | Final sweep during game-over |
| DGVE majority holder | `setLinkEthPriceFeed`, `swapGameEthForStEth`, `stakeGameEthToStEth`, `setLootboxRngThreshold`, `emergencyRecover` | Admin operations |
| Any address | `_linkAmountToEth` | View function (read-only) |

## Findings Summary

| Severity | Count | Details |
|----------|-------|---------|
| BUG | 0 | None found |
| CONCERN | 0 | None found |
| GAS | 0 | No actionable gas issues (external self-call in `_linkAmountToEth` is necessary for try/catch pattern) |
| INFORMATIONAL | 1 | `_linkAmountToEth` uses underscore-prefix convention for an external function -- documented and intentional for try/catch support |
| CORRECT | 11 | All 11 audited entries (constructor, 5 admin ops, shutdownVrf, onTokenTransfer, _linkAmountToEth, _linkRewardMultiplier, _feedHealthy) plus onlyOwner modifier verified correct |

### Verification Checklist

- [x] VRF subscription lifecycle fully traced: create (constructor) -> fund (onTokenTransfer) -> recover (emergencyRecover) -> shutdown (shutdownVrf)
- [x] Emergency recovery 3-day stall gate verified (`gameAdmin.rngStalledForThreeDays()` check in emergencyRecover)
- [x] LINK donation ERC-677 callback verified (onTokenTransfer sender validation, amount forwarding, reward calculation)
- [x] Tiered reward multiplier verified (3x->1x for 0-200 LINK, 1x->0x for 200-1000 LINK, 0x above 1000 LINK)
- [x] Price feed health checks verified (staleness via LINK_ETH_MAX_STALE, decimals == 18, answer > 0, round validity)
- [x] Owner access control model verified (>50.1% DGVE via vault.isVaultOwner, dynamic market-based ownership)
- [x] All cross-contract calls documented (30 outbound calls across 10 functions)
- [x] NatSpec accuracy verified for every function (1 informational: underscore naming convention)
- [x] Gas flags reviewed (no actionable issues; external self-call pattern is necessary)
- [x] Every function has a structured audit entry with verdict

---

*Audit completed: 2026-03-07*
*Auditor: Claude Opus 4.6*
*Contract status: All 11 function entries CORRECT, 0 bugs, 0 concerns*
