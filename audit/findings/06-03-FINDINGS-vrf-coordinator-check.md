# AUTH-02: VRF Coordinator Callback Validation Audit

**Requirement:** AUTH-02 -- Prove that the VRF coordinator callback is restricted to the coordinator address only.

**Scope:** rawFulfillRandomWords entry point, delegatecall dispatch chain, vrfCoordinator storage lifecycle, alternative bypass paths.

**Contracts Audited (READ-ONLY):**
- `contracts/DegenerusGame.sol` (proxy dispatcher)
- `contracts/modules/DegenerusGameAdvanceModule.sol` (callback logic)
- `contracts/DegenerusAdmin.sol` (VRF wiring and emergency recovery)
- `contracts/storage/DegenerusGameStorage.sol` (storage layout)

---

## 1. rawFulfillRandomWords Entry Point (DegenerusGame.sol)

**Location:** DegenerusGame.sol, lines 1955-1969

```solidity
function rawFulfillRandomWords(
    uint256 requestId,
    uint256[] calldata randomWords
) external {
    (bool ok, bytes memory data) = ContractAddresses
        .GAME_ADVANCE_MODULE
        .delegatecall(
            abi.encodeWithSelector(
                IDegenerusGameAdvanceModule.rawFulfillRandomWords.selector,
                requestId,
                randomWords
            )
        );
    if (!ok) _revertDelegate(data);
}
```

**Findings:**

| Check | Result |
|-------|--------|
| Declared as `external`? | YES -- required for Chainlink VRF callback |
| DegenerusGame checks msg.sender before delegatecall? | NO -- it blindly delegates |
| Relies solely on AdvanceModule's check? | YES |
| Dispatch uses delegatecall (not call)? | YES -- `.delegatecall(...)` confirmed |
| Dispatch target is constant? | YES -- `ContractAddresses.GAME_ADVANCE_MODULE` is a compile-time constant |
| Selector matches AdvanceModule function? | YES -- `IDegenerusGameAdvanceModule.rawFulfillRandomWords.selector` |

**Assessment:** DegenerusGame does NOT perform any caller validation. It unconditionally delegatecalls to the AdvanceModule at a compile-time constant address. The coordinator check is solely in the AdvanceModule. This is safe because: (a) the delegatecall target is immutable, and (b) delegatecall preserves msg.sender (see Section 3).

---

## 2. AdvanceModule Coordinator Check

**Location:** DegenerusGameAdvanceModule.sol, lines 1199-1220

```solidity
function rawFulfillRandomWords(
    uint256 requestId,
    uint256[] calldata randomWords
) external {
    if (msg.sender != address(vrfCoordinator)) revert E();  // LINE 1203
    if (requestId != vrfRequestId || rngWordCurrent != 0) return;

    uint256 word = randomWords[0];
    if (word == 0) word = 1;

    if (rngLockedFlag) {
        // Daily RNG: store for advanceGame processing
        rngWordCurrent = word;
    } else {
        // Mid-day RNG: directly finalize lootbox RNG
        uint48 index = lootboxRngRequestIndexById[requestId];
        lootboxRngWordByIndex[index] = word;
        emit LootboxRngApplied(index, word, requestId);
        vrfRequestId = 0;
        rngRequestTime = 0;
    }
}
```

**Findings:**

| Check | Result |
|-------|--------|
| Exact check present? | YES -- `if (msg.sender != address(vrfCoordinator)) revert E();` |
| Check is FIRST statement? | YES -- line 1203, before any state read or mutation |
| Revert error type | `E()` -- custom error, cannot be caught by external try/catch because this runs via delegatecall from DegenerusGame |
| Code path bypass? | NO -- the check is unconditional. No early return, no conditional branch before it |
| State mutation before check? | NONE -- no SLOAD, SSTORE, or event before line 1203 (the `address(vrfCoordinator)` read is a pure comparison operand) |

**Assessment:** The coordinator check is the absolute first executable statement. Any caller that is not the vrfCoordinator address causes an immediate revert. There is no code path that bypasses this check.

---

## 3. Delegatecall msg.sender Preservation

**Solidity semantics:** When Contract A delegatecalls to Contract B, inside B's code:
- `msg.sender` = the original caller of A (NOT A itself)
- `msg.value` = the original value sent to A
- Storage reads/writes operate on A's storage

**Applied to VRF callback chain:**
1. Chainlink VRF Coordinator calls `DegenerusGame.rawFulfillRandomWords()` -- `msg.sender` = VRF Coordinator address
2. DegenerusGame delegatecalls to AdvanceModule -- inside AdvanceModule, `msg.sender` is still the VRF Coordinator (preserved by delegatecall)
3. AdvanceModule checks `msg.sender != address(vrfCoordinator)` -- this correctly compares the original external caller against the stored coordinator

**Verified:** DegenerusGame uses `.delegatecall()` (line 1961), NOT `.call()`. This is consistent with ALL other module dispatches in DegenerusGame (advanceGame, wireVrf, updateVrfCoordinatorAndSub, purchase, etc.) -- the entire protocol uses the same delegatecall dispatch pattern for all module functions.

**Critical note:** If DegenerusGame had used `.call()` instead of `.delegatecall()`, then msg.sender inside AdvanceModule would be the DegenerusGame address, NOT the VRF coordinator. This would break the coordinator check entirely. The use of delegatecall is correct and essential.

---

## 4. vrfCoordinator Storage Variable Lifecycle

### 4.1 Declaration

**Location:** DegenerusGameStorage.sol, line 1170

```solidity
IVRFCoordinator internal vrfCoordinator;
```

- Type: `IVRFCoordinator` (interface type, stored as address)
- Visibility: `internal` (accessible to inheriting contracts/modules via delegatecall)
- Initial value: `address(0)` (Solidity default for uninitialized storage)

### 4.2 Initialization via wireVrf()

**Location:** DegenerusGameAdvanceModule.sol, lines 301-313

```solidity
function wireVrf(
    address coordinator_,
    uint256 subId,
    bytes32 keyHash_
) external {
    if (msg.sender != ContractAddresses.ADMIN) revert E();

    address current = address(vrfCoordinator);
    vrfCoordinator = IVRFCoordinator(coordinator_);
    vrfSubscriptionId = subId;
    vrfKeyHash = keyHash_;
    emit VrfCoordinatorUpdated(current, coordinator_);
}
```

| Check | Result |
|-------|--------|
| Access gate | `msg.sender != ContractAddresses.ADMIN` -- ADMIN only |
| Re-initialization guard | NONE -- wireVrf can be called multiple times by ADMIN |
| Zero-address check | NONE -- no validation on `coordinator_` parameter |

**Call chain:** DegenerusAdmin constructor (line 382) calls `gameAdmin.wireVrf(...)` which calls DegenerusGame.wireVrf() which delegatecalls to AdvanceModule.wireVrf(). The msg.sender check sees ContractAddresses.ADMIN (the Admin contract address), which passes.

**Observation -- wireVrf lacks re-initialization guard:** wireVrf can be called multiple times. However, only ContractAddresses.ADMIN can call it, and ADMIN's constructor calls it exactly once. After construction, there is no other code path in DegenerusAdmin that calls wireVrf(). The ADMIN contract has no public function exposing wireVrf() after construction. This means wireVrf is effectively one-time despite lacking an explicit guard.

**Observation -- wireVrf lacks zero-address check:** If ADMIN somehow passed `address(0)` as coordinator_, the vrfCoordinator would be set to address(0). This is mitigated by: (a) ADMIN's constructor passes `ContractAddresses.VRF_COORDINATOR` which is a compile-time constant, and (b) _tryRequestRng (line 1033) explicitly checks `address(vrfCoordinator) == address(0)` and returns false, preventing VRF requests to address(0).

### 4.3 Update via updateVrfCoordinatorAndSub()

**Location:** DegenerusGameAdvanceModule.sol, lines 1133-1153

```solidity
function updateVrfCoordinatorAndSub(
    address newCoordinator,
    uint256 newSubId,
    bytes32 newKeyHash
) external {
    if (msg.sender != ContractAddresses.ADMIN) revert E();
    if (!_threeDayRngGap(_simulatedDayIndex()))
        revert VrfUpdateNotReady();

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

**Access gates (two layers):**

1. **AdvanceModule gate:** `msg.sender != ContractAddresses.ADMIN` -- only the ADMIN contract can call this
2. **Temporal gate:** `_threeDayRngGap()` -- requires 3 consecutive days with no VRF word recorded

**_threeDayRngGap analysis** (line 1258-1263):
```solidity
function _threeDayRngGap(uint48 day) private view returns (bool) {
    if (rngWordByDay[day] != 0) return false;
    if (rngWordByDay[day - 1] != 0) return false;
    if (day < 2 || rngWordByDay[day - 2] != 0) return false;
    return true;
}
```

This requires that rngWordByDay for the current day, yesterday, and two days ago are ALL zero. This can only happen if:
- The VRF coordinator has genuinely failed to deliver words for 3 days, OR
- The game has not yet advanced past day 2 (no words recorded yet)

**Can _threeDayRngGap be triggered artificially?** No. rngWordByDay is only written in `_applyDailyRng()` (line 1236) which is called during advanceGame processing. An attacker cannot delete existing rngWordByDay entries -- they are write-once per day. The only way to have 3 consecutive zero entries is genuine VRF failure.

**DegenerusAdmin.emergencyRecover()** (line 470-532):
The ADMIN contract's `emergencyRecover()` function is the external entry point. It has ADDITIONAL gates:
- `onlyOwner` modifier (CREATOR or 30%+ DGVE holder)
- `subscriptionId == 0` check (must be wired)
- `gameAdmin.rngStalledForThreeDays()` check (calls DegenerusGame's view function which delegates to `_threeDayRngGap`)
- `newCoordinator == address(0) || newKeyHash == bytes32(0)` check (non-zero required)

This function then calls `gameAdmin.updateVrfCoordinatorAndSub()` which routes through DegenerusGame to AdvanceModule.

---

## 5. Trust Assumption: Malicious Coordinator Rotation

**Scenario:** A malicious vault owner (>30% DGVE) could:
1. Wait for (or cause) a 3-day VRF stall
2. Call `emergencyRecover()` with a coordinator they control
3. Their fake coordinator calls `rawFulfillRandomWords()` with chosen words
4. They now control all game outcomes

**Assessment:** This is an **accepted trust assumption**, not a vulnerability.

**Mitigations:**
- Requires vault ownership (>30% DGVE or CREATOR) -- highest privilege level in the protocol
- Requires a genuine 3-day VRF stall -- cannot be manufactured by the owner (Chainlink is external)
- The 3-day window gives the community time to detect a stall and react
- The vault owner already has broad administrative powers; controlling VRF is not a privilege escalation beyond their existing trust level

**Note on "causing" a stall:** The owner cannot prevent Chainlink from delivering VRF words. Chainlink's VRF coordinator calls rawFulfillRandomWords directly on DegenerusGame -- there is no ADMIN intermediary that could block it. The only way to stall VRF is if Chainlink itself fails or the subscription runs out of LINK. LINK funding is controlled by ADMIN, so an owner could theoretically drain the subscription, wait 3 days, then rotate. This is a known trust assumption of the owner role.

---

## 6. Alternative Entry Paths Analysis

### 6.1 Fallback Function

DegenerusGame has NO `fallback()` function. It has a `receive()` function (line 2786) that only adds to `futurePrizePool`. Unknown selectors will revert with no matching function.

### 6.2 Attacker-Controlled Calldata via Delegatecall

All delegatecall dispatches in DegenerusGame use hardcoded selectors:
```solidity
abi.encodeWithSelector(IDegenerusGameAdvanceModule.rawFulfillRandomWords.selector, ...)
```

There is no generic "forward any calldata to a module" function. Each module function has its own wrapper in DegenerusGame with a fixed selector. An attacker cannot inject arbitrary selectors into any delegatecall.

### 6.3 Reentrancy via ETH-Sending Functions

**claimWinnings (line 1428):** Uses CEI pattern -- `claimableWinnings[player] = 1` and `claimablePool -= payout` are set BEFORE the ETH transfer. Even if the recipient re-enters rawFulfillRandomWords during the ETH callback, the coordinator check would reject them (re-entrant msg.sender would be DegenerusGame or the recipient, not the VRF coordinator).

**receive() (line 2786):** Only increments `futurePrizePool`. Cannot route to rawFulfillRandomWords.

**Other ETH transfers (_transferSteth, _payoutWithStethFallback, etc.):** All are internal functions called from within DegenerusGame. Even if a recipient re-entered, they would need to be the VRF coordinator address to pass the check.

### 6.4 Cross-Module Delegatecall

No module dispatches to another module. Each delegatecall targets a specific constant address with a specific selector. AdvanceModule cannot be reached through MintModule, WhaleModule, or any other module.

**Conclusion:** There is NO alternative path to invoke rawFulfillRandomWords that bypasses the coordinator check.

---

## 7. Zero-Address Edge Case

**If vrfCoordinator == address(0) before wireVrf:**

- `rawFulfillRandomWords` check: `msg.sender != address(vrfCoordinator)` becomes `msg.sender != address(0)`
- Can address(0) call rawFulfillRandomWords? **Practically no.** No contract exists at address(0) on Ethereum. The zero address is a burn address with no code. No EOA has the private key for address(0) (computationally infeasible).
- Even if theoretically possible, `requestId != vrfRequestId` would fail since no VRF request was ever made (vrfRequestId = 0 and requestId = 0 would match, but `rngWordCurrent != 0` check provides secondary defense only if already fulfilled).

**wireVrf zero-check:** wireVrf does NOT check for `coordinator_ == address(0)`. However:
- ADMIN passes `ContractAddresses.VRF_COORDINATOR` (compile-time constant, non-zero on mainnet)
- `_tryRequestRng` (line 1033) explicitly checks `address(vrfCoordinator) == address(0)` and returns false, preventing VRF requests to address(0)
- `_requestRng` (line 1015) does NOT check for zero and would revert on the external call (no code at address(0))

**Risk:** Negligible. The zero-address edge case is not exploitable in practice.

---

## 8. AUTH-02 Verdict

### Summary Table

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Coordinator check present | PASS | AdvanceModule line 1203: `if (msg.sender != address(vrfCoordinator)) revert E();` |
| Check is first in function | PASS | Line 1203 is the absolute first statement, before any state read or mutation |
| msg.sender preserved through delegatecall | PASS | DegenerusGame uses `.delegatecall()` (line 1961), standard Solidity semantics preserve msg.sender |
| Dispatch target immutable | PASS | `ContractAddresses.GAME_ADVANCE_MODULE` is a compile-time constant |
| wireVrf properly gated | PASS | `msg.sender != ContractAddresses.ADMIN` check (line 306), effectively one-time via constructor |
| updateVrfCoordinatorAndSub properly gated | PASS | Dual gate: ADMIN-only (line 1138) + 3-day RNG stall (line 1139) |
| No bypass paths | PASS | No fallback, no generic delegatecall, no reentrancy path, no cross-module dispatch |
| Zero-address edge case | PASS | Not exploitable; _tryRequestRng has explicit zero guard |

### Informational Observations

1. **wireVrf lacks explicit re-initialization guard:** While effectively one-time (no post-constructor code path in ADMIN calls it), an explicit `if (address(vrfCoordinator) != address(0)) revert` guard would provide defense-in-depth. Rated INFORMATIONAL -- no exploit path exists.

2. **wireVrf lacks zero-address parameter validation:** A `require(coordinator_ != address(0))` would prevent misconfiguration. Mitigated by compile-time constant usage and _tryRequestRng zero guard. Rated INFORMATIONAL.

3. **DegenerusGame does not pre-check msg.sender:** The coordinator check is entirely in the AdvanceModule, reached via delegatecall. A redundant check in DegenerusGame.rawFulfillRandomWords would provide defense-in-depth but is not necessary for security (delegatecall target is immutable). Rated INFORMATIONAL.

---

### AUTH-02: PASS

The VRF coordinator callback is conclusively restricted to the coordinator address only. The check is the first statement in rawFulfillRandomWords, msg.sender is correctly preserved through delegatecall, all vrfCoordinator update paths are properly gated (ADMIN-only + 3-day stall), and no alternative bypass path exists. The coordinator rotation trust assumption (vault owner + 3-day stall) is a documented and accepted design decision, not a vulnerability.
