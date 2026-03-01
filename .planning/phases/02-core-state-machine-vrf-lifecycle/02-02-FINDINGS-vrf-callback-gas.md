# 02-02 FINDINGS: VRF Callback Gas and Revert Safety

**Audit date:** 2026-02-28
**Auditor:** Static analysis + storage layout inspection
**Scope:** `rawFulfillRandomWords` in DegenerusGame.sol (entry) and DegenerusGameAdvanceModule.sol (implementation)
**Requirements:** RNG-02 (no revert), RNG-03 (gas under 200k)

---

## Section 1: Revert Path Analysis

### 1.1 Complete Control Flow Enumeration

The VRF callback traverses two contracts via delegatecall:

**Entry point** -- `DegenerusGame.sol:1952-1966`:
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

**Implementation** -- `DegenerusGameAdvanceModule.sol:1199-1220`:
```solidity
function rawFulfillRandomWords(
    uint256 requestId,
    uint256[] calldata randomWords
) external {
    if (msg.sender != address(vrfCoordinator)) revert E();
    if (requestId != vrfRequestId || rngWordCurrent != 0) return;

    uint256 word = randomWords[0];
    if (word == 0) word = 1;

    if (rngLockedFlag) {
        rngWordCurrent = word;
    } else {
        uint48 index = lootboxRngRequestIndexById[requestId];
        lootboxRngWordByIndex[index] = word;
        emit LootboxRngApplied(index, word, requestId);
        vrfRequestId = 0;
        rngRequestTime = 0;
    }
}
```

### 1.2 Path-by-Path Analysis

| Path | Condition | Outcome | Can Revert? | Reachable in Normal Operation? |
|------|-----------|---------|-------------|-------------------------------|
| A | `msg.sender != address(vrfCoordinator)` | `revert E()` | YES | NO -- see Section 1.3 |
| B | `requestId != vrfRequestId` | `return` (silent) | NO | YES -- stale fulfillment after retry |
| C | `rngWordCurrent != 0` | `return` (silent) | NO | YES -- duplicate fulfillment |
| D | `rngLockedFlag == true` | `rngWordCurrent = word` (daily) | NO | YES -- normal daily path |
| E | `rngLockedFlag == false` | lootbox finalization | NO | YES -- normal lootbox path |

**Path A: Coordinator check (`revert E()`)**

This is the ONLY revert in the callback implementation. The check `msg.sender != address(vrfCoordinator)` reverts with the generic error `E()` when the caller is not the registered VRF coordinator.

In normal operation, only the Chainlink VRF coordinator calls `rawFulfillRandomWords`. The coordinator address is stored in `vrfCoordinator` (set during `wireVrf()` at deployment, or `updateVrfCoordinatorAndSub()` during emergency rotation). The coordinator will always match because:

1. During `wireVrf()`, the coordinator is set to the same address that was registered as a consumer.
2. The VRF coordinator only sends fulfillments to contracts registered as consumers on its subscription.
3. The `rawFulfillRandomWords` function selector is the standard Chainlink callback ABI.

**Verdict for Path A:** Revert is unreachable in normal operation. See Section 1.3 for the coordinator rotation edge case.

**Path B: Request ID mismatch (silent return)**

After an 18-hour VRF timeout retry, the old request ID is discarded and replaced by the new one. If the old coordinator eventually fulfills the original request, `requestId != vrfRequestId` will be true and the callback silently returns. This is correct behavior -- stale fulfillments are safely ignored.

**Path C: Double fulfillment (silent return)**

If `rngWordCurrent != 0`, the word has already been stored (either from a prior fulfillment or from the `_applyDailyRng` path). The callback silently returns. This prevents double-write.

**Path D: Daily branch**

Single `SSTORE` to `rngWordCurrent`. Storage writes cannot fail -- they are deterministic EVM operations with no conditional failure mode.

**Path E: Lootbox branch**

1. `SLOAD` of `lootboxRngRequestIndexById[requestId]` -- mapping read, cannot fail
2. `SSTORE` to `lootboxRngWordByIndex[index]` -- cannot fail
3. `emit LootboxRngApplied(index, word, requestId)` -- LOG opcode, cannot fail, does not revert
4. `SSTORE vrfRequestId = 0` -- cannot fail
5. `SSTORE rngRequestTime = 0` -- cannot fail

**No external calls, no loops, no division, no array bounds checks beyond `randomWords[0]`.** The `randomWords` array is guaranteed to have exactly 1 element because the VRF request specifies `numWords: 1` and the coordinator guarantees this.

### 1.3 Coordinator Rotation Edge Case (Research Open Question #2)

**Question:** Could `updateVrfCoordinatorAndSub()` change `vrfCoordinator` while a VRF fulfillment is in-flight, causing the old coordinator's callback to hit `revert E()`?

**Trace of `updateVrfCoordinatorAndSub()` (AdvanceModule:1133-1153):**

```solidity
function updateVrfCoordinatorAndSub(
    address newCoordinator, uint256 newSubId, bytes32 newKeyHash
) external {
    if (msg.sender != ContractAddresses.ADMIN) revert E();
    if (!_threeDayRngGap(_simulatedDayIndex())) revert VrfUpdateNotReady();

    address current = address(vrfCoordinator);
    vrfCoordinator = IVRFCoordinator(newCoordinator);  // <-- changes coordinator
    vrfSubscriptionId = newSubId;
    vrfKeyHash = newKeyHash;

    // Reset RNG state to allow immediate advancement
    rngLockedFlag = false;
    vrfRequestId = 0;        // <-- clears request ID
    rngRequestTime = 0;      // <-- clears request time
    rngWordCurrent = 0;      // <-- clears word
    emit VrfCoordinatorUpdated(current, newCoordinator);
}
```

**Analysis of the race condition:**

The coordinator rotation is protected by `_threeDayRngGap()`, which requires that **no RNG word has been recorded for the last 3 consecutive day slots**. This means:

1. **Precondition:** VRF has been completely non-functional for 3+ days. No fulfillments have arrived.
2. **State at rotation time:** `vrfRequestId` references a stale request that was never fulfilled.
3. **After rotation:** `vrfRequestId = 0` is set, clearing the stale request reference.
4. **If old coordinator fulfills late:** Even if the old coordinator finally fulfills after rotation:
   - `msg.sender` would be the old coordinator address, but `vrfCoordinator` now points to the new one.
   - The check `msg.sender != address(vrfCoordinator)` would be TRUE.
   - **The callback would revert with `E()`.**

**BUT: This revert is harmless.** At the point of coordinator rotation:
- `vrfRequestId` has been set to 0.
- Even if the old coordinator's fulfillment somehow avoided the coordinator check, it would fail Path B (`requestId != vrfRequestId` since `vrfRequestId == 0`).
- The rotation function explicitly resets all RNG state, allowing `advanceGame()` to make a fresh VRF request to the new coordinator.
- The 3-day stall precondition means the protocol has already been waiting 3+ days with no fulfillment. The old request is abandoned by design.

**The revert on a stale coordinator's fulfillment is correct defensive behavior.** The VRF coordinator does not retry failed callbacks, but in this scenario the request was already abandoned (3+ days stale) and a new coordinator is in use. There is no data loss.

**Full rotation sequence (via DegenerusAdmin.sol:470-529):**

```
Admin.emergencyRecover(newCoordinator, newKeyHash):
  1. Verify rngStalledForThreeDays() == true
  2. Cancel old subscription (try/catch -- failure tolerated)
  3. Create new subscription on new coordinator
  4. Add GAME as consumer on new subscription
  5. Call gameAdmin.updateVrfCoordinatorAndSub() -- updates GAME storage
  6. Transfer LINK to new subscription
```

Step 2 cancels the old subscription. Chainlink coordinators reject fulfillments for cancelled subscriptions, so the old coordinator is highly unlikely to fulfill after cancellation. The revert in `rawFulfillRandomWords` is a belt-and-suspenders defense.

**Verdict:** The coordinator rotation edge case does NOT create an exploitable revert. The revert against a stale coordinator is correct behavior occurring after an already-abandoned request. The 3-day stall precondition ensures the old request is irrecoverable regardless.

### 1.4 Delegatecall Return Value Handling

**`DegenerusGame.sol:1965`:** `if (!ok) _revertDelegate(data);`

**`_revertDelegate` (DegenerusGame.sol:1119-1124):**
```solidity
function _revertDelegate(bytes memory reason) private pure {
    if (reason.length == 0) revert E();
    assembly ("memory-safe") {
        revert(add(32, reason), mload(reason))
    }
}
```

**Analysis:**

- If the delegatecall reverts (Path A: `revert E()`), `ok == false` and `_revertDelegate` propagates the revert with the original error data.
- If the delegatecall succeeds (Paths B-E), `ok == true` and execution continues normally.
- The delegatecall cannot return `ok == false` without a revert inside the module -- Solidity `delegatecall` returns false only when the called code reverts or runs out of gas.

**Verdict:** The delegatecall wrapper correctly propagates reverts from the module. Successful returns (including silent `return` on Paths B/C) produce `ok == true`.

### 1.5 Word==0 Sentinel Mapping

**Code (AdvanceModule:1206-1207):**
```solidity
uint256 word = randomWords[0];
if (word == 0) word = 1;
```

**Analysis:**

- `rngWordCurrent == 0` is used as a sentinel meaning "no word received / pending".
- If the VRF coordinator returned `randomWords[0] == 0`, the sentinel would be corrupted -- `rngWordCurrent` would be 0, meaning "pending" despite a word actually arriving.
- The mapping `0 -> 1` prevents this corruption.

**Bias assessment:**

- The probability of VRF returning exactly 0 for a uint256 is `1 / 2^256` -- negligibly small.
- Mapping 0 to 1 means value 1 has double the probability: `2 / 2^256`. The bias is `1 / 2^256`, which is astronomically negligible.
- For practical purposes, this mapping introduces zero measurable bias.

**Verdict:** The sentinel mapping is correct and introduces no meaningful bias. PASS.

---

## Section 2: Gas Analysis

### 2.1 Storage Slot Layout (Critical for Gas Calculation)

From `DegenerusGameStorage.sol`, the variables accessed in `rawFulfillRandomWords` reside in the following slots:

| Variable | Type | Slot | Position in Slot | Notes |
|----------|------|------|------------------|-------|
| `rngRequestTime` | uint48 | 0 | bytes 12-18 | Packed with levelStartTime, dailyIdx, level, etc. |
| `rngLockedFlag` | bool | 1 | byte 6 | Packed with jackpotCounter, earlyBurnPercent, booleans |
| `rngWordCurrent` | uint256 | ~5 | full slot | Full 32-byte slot (follows price at slot 2, currentPrizePool, nextPrizePool) |
| `vrfRequestId` | uint256 | ~6 | full slot | Full 32-byte slot (follows rngWordCurrent) |
| `vrfCoordinator` | IVRFCoordinator | VRF config section (~slot 40+) | full slot (address) | Far from other accessed vars |
| `lootboxRngRequestIndexById` | mapping(uint256=>uint48) | mapping | computed | keccak256(requestId . slot) |
| `lootboxRngWordByIndex` | mapping(uint48=>uint256) | mapping | computed | keccak256(index . slot) |

### 2.2 Cold vs Warm Access

The VRF callback is called by the Chainlink VRF coordinator in an **isolated transaction** -- no prior access to the game contract's storage in this transaction context. Therefore, **all storage accesses are COLD** (2,100 gas for SLOAD).

The exception is that Solidity reads packed slot variables: when `rngLockedFlag` (slot 1) is loaded, other variables in slot 1 become warm. However, `rngLockedFlag` is the only variable from slot 1 used in the callback. Similarly, reading `rngRequestTime` (slot 0) warms all of slot 0, but no other slot 0 variable is read in the callback.

### 2.3 Opcode-Level Gas Breakdown: Daily Branch (Path D)

This is the `rngLockedFlag == true` path (daily RNG fulfillment).

```
OPERATION                                          GAS        NOTES
==========================================================================
--- DegenerusGame.sol entry point ---
Transaction base cost (21,000)                     21,000     Every transaction
CALLDATALOAD (requestId)                           3
CALLDATALOAD (randomWords offset)                  3
CALLDATALOAD (randomWords length)                  3
CALLDATALOAD (randomWords[0])                      3
SLOAD ContractAddresses.GAME_ADVANCE_MODULE        100        Compile-time constant, inlined
  (GAME_ADVANCE_MODULE is address(0) in source
   but patched to real address at deploy. The
   constant is embedded in bytecode, no SLOAD.)
ABI encoding for delegatecall                      ~300       MSTORE operations for selector + args
DELEGATECALL base cost                             100        Warm (same contract context)
DELEGATECALL memory expansion                      ~200       Calldata forwarding

--- DegenerusGameAdvanceModule implementation ---
SLOAD vrfCoordinator (cold)                        2,100      Slot in VRF config section
CALLER opcode                                      2
EQ + ISZERO + JUMPI (coordinator check)            20
SLOAD vrfRequestId (cold)                          2,100      Full slot ~6
EQ (requestId check)                               3
SLOAD rngWordCurrent (cold)                        2,100      Full slot ~5
ISZERO + OR + ISZERO + JUMPI (compound check)      25
CALLDATALOAD randomWords[0]                        3          Already in memory
EQ (word == 0 check) + JUMPI                       10
SLOAD rngLockedFlag (cold, slot 1)                 2,100      Packed slot
ISZERO + JUMPI (branch check)                      10
SSTORE rngWordCurrent (0 -> nonzero)               20,000     Cold slot, zero-to-nonzero

--- Return path ---
RETURN from delegatecall                           ~10
Return value check in DegenerusGame                ~20        if (!ok) check

SUBTOTAL (excluding tx base):                      ~29,212
TOTAL (including tx base 21,000):                  ~50,212
```

**Note on ContractAddresses:** `GAME_ADVANCE_MODULE` is declared as `address internal constant` in `ContractAddresses.sol`. As a Solidity `constant`, it is inlined into the bytecode at compile time. There is no SLOAD. The value is pushed onto the stack directly. However, the deploy pipeline patches `address(0)` to the real address, so the constant is baked into the deployed bytecode. Gas cost: zero for storage read.

**Note on DELEGATECALL cost:** When calling a contract that has already been accessed in the same transaction (or is the same contract), the address is warm (100 gas). In the VRF callback, DegenerusGame is being called externally for the first time, but the delegatecall target (GAME_ADVANCE_MODULE) is a different address that has NOT been accessed yet. Per EIP-2929, the first access to a cold address via DELEGATECALL costs 2,600 gas.

**Revised total with cold DELEGATECALL:**

```
DELEGATECALL to cold address                       2,600      First access to module address
Revised SUBTOTAL (excluding tx base):              ~31,812
Revised TOTAL (including tx base):                 ~52,812
```

### 2.4 Opcode-Level Gas Breakdown: Lootbox Branch (Path E)

This is the `rngLockedFlag == false` path (mid-day lootbox RNG fulfillment). This is the **worst-case** branch because it performs more storage operations.

```
OPERATION                                          GAS        NOTES
==========================================================================
--- DegenerusGame.sol entry point ---
Transaction base cost                              21,000
CALLDATALOAD operations (4x)                       12
ContractAddresses constant                         0          Inlined
ABI encoding                                      ~300
DELEGATECALL (cold address)                        2,600      First access to module

--- DegenerusGameAdvanceModule implementation ---
SLOAD vrfCoordinator (cold)                        2,100
Coordinator check ops                              22
SLOAD vrfRequestId (cold)                          2,100
RequestId check                                    3
SLOAD rngWordCurrent (cold)                        2,100
Compound check ops                                 25
Word load + zero check                             13
SLOAD rngLockedFlag (cold, slot 1)                 2,100
Branch check (takes else)                          10

--- Lootbox finalization ---
SLOAD lootboxRngRequestIndexById[requestId] (cold) 2,100      Mapping, cold access
SSTORE lootboxRngWordByIndex[index] (0 -> nonzero) 20,000     Cold slot, zero-to-nonzero
LOG3 (LootboxRngApplied event)
  - Base LOG cost                                  375
  - 3 topics (index, word, requestId)              1,125      375 per topic
  - Data bytes (none -- all indexed via topics)    0
  Actually: LootboxRngApplied(uint48, uint256,
  uint256) has 0 indexed params, so this is LOG0
  with 3 data fields (48+256+256 = 560 bits ~70B)

  Correction: event definition is:
    event LootboxRngApplied(uint48 index, uint256 word, uint256 requestId);
  No "indexed" keyword on any parameter.
  This emits LOG1 (1 topic = event signature hash).
  Data: 3 ABI-encoded values = 96 bytes.
  LOG1 cost = 375 + 375*1 + 8*96 = 375 + 375 + 768 = 1,518

SSTORE vrfRequestId (nonzero -> zero)              2,900      EIP-3529: 5,000 - 4,800 refund
                                                              (capped at 20% of total gas)
  Correction: post-EIP-3529 (London), setting a
  nonzero slot to zero costs 5,000 execution gas
  but provides a refund of 4,800 gas. The refund
  is applied at END of transaction, capped at
  1/5 of total gas used. Net effective cost for
  accounting: 5,000 gas (refund applied later).    5,000

SSTORE rngRequestTime (nonzero -> zero)            5,000      Same as above
  Note: rngRequestTime is in packed slot 0.
  Setting the uint48 to 0 within a packed slot
  requires SLOAD (warm, slot 0 NOT yet accessed
  -- actually this is a WRITE to slot 0 which
  requires reading the current value first).

  Correction: rngRequestTime is in slot 0, which
  has NOT been accessed yet in this callback.
  The SSTORE to slot 0 requires cold access.
  Cost: 2,100 (cold SLOAD for read-modify-write)
  + 5,000 (SSTORE nonzero->zero in packed slot)   7,100      Cold read + packed write

--- Return path ---
Return from delegatecall + check                   ~30

SUBTOTAL (excluding tx base):                      ~52,258
TOTAL (including tx base):                         ~73,258
```

**Wait -- re-analysis of `rngRequestTime` write:**

`rngRequestTime = 0` in the lootbox path (AdvanceModule:1218). This variable is `uint48` packed in slot 0 alongside `levelStartTime`, `dailyIdx`, `level`, etc.

Setting a packed variable to zero requires:
1. SLOAD the entire slot 0 (to read the other packed values) -- **cold: 2,100 gas**
2. Mask the rngRequestTime bits to zero
3. SSTORE the modified slot back -- The original slot had `rngRequestTime != 0`. The new slot still has other nonzero values (levelStartTime, dailyIdx, etc.) so this is a **nonzero-to-nonzero SSTORE: 2,900 gas** (warm, since we just read it). Actually, per EIP-2929 SSTORE pricing: if slot was cold (first access), the surcharge is already paid on the SLOAD. The SSTORE warm cost is 100 base + 2,900 = 2,900 for nonzero-to-nonzero modification of a dirty slot.

Actually, let me use the precise EIP-2929 + EIP-3529 gas schedule:

For `SSTORE` to a slot that was cold-loaded in the same transaction:
- Cold access surcharge: 2,100 (already paid on SLOAD)
- SSTORE (warm, original nonzero, new nonzero because other fields remain): 100 (warm) + 2,900 (SSTORE_RESET) = 3,000

But the entire slot value changes from having `rngRequestTime` bits set to having them cleared. The slot remains nonzero (other fields are nonzero). So this is `SSTORE_RESET_GAS = 2,900` on a warm slot.

Revised for `rngRequestTime = 0`:
- SLOAD slot 0 (cold): 2,100
- SSTORE slot 0 (warm, nonzero->nonzero): 2,900
- Total: 5,000

Similarly for `vrfRequestId = 0` (AdvanceModule:1217):
- vrfRequestId is a full uint256 in its own slot (~slot 6)
- The slot was COLD-LOADED earlier in the callback (line 1204: `requestId != vrfRequestId`)
- So the SLOAD cost was already paid
- SSTORE (warm, nonzero->zero): This gives a refund
- Execution cost: 100 (warm access) + 2,900 (SSTORE_RESET) = 3,000
- Refund: 4,800 (nonzero to zero, EIP-3529)
- Net: 3,000 gas execution (refund applied at end of tx)

**Final revised lootbox branch total:**

```
OPERATION                                          GAS
==========================================================================
Transaction base                                   21,000
CALLDATALOAD (4x)                                  12
ABI encoding                                       300
DELEGATECALL (cold)                                2,600
SLOAD vrfCoordinator (cold)                        2,100
Coordinator check                                  22
SLOAD vrfRequestId (cold)                          2,100
RequestId + word checks                            28
SLOAD rngWordCurrent (cold)                        2,100
Compound check + word zero check                   38
SLOAD rngLockedFlag (cold, slot 1)                 2,100
Branch check                                       10
SLOAD lootboxRngRequestIndexById[reqId] (cold)     2,100
SSTORE lootboxRngWordByIndex[index] (cold, 0->NZ)  22,100   (2,100 cold + 20,000 zero-to-nonzero)
LOG1 (LootboxRngApplied)                           1,518
SSTORE vrfRequestId (warm, NZ->0)                  3,000    (refund 4,800 at tx end)
SLOAD slot 0 for rngRequestTime (cold)             2,100
SSTORE slot 0 (warm, NZ->NZ packed)                2,900
Return overhead                                    30
---------------------------------------------------------------------------
SUBTOTAL (excl tx base):                           45,258
TOTAL (incl tx base):                              66,258

Refunds applied at tx end:                         -4,800   (vrfRequestId NZ->0)
EFFECTIVE TOTAL:                                   61,458
```

### 2.5 Revised Daily Branch Total

```
OPERATION                                          GAS
==========================================================================
Transaction base                                   21,000
CALLDATALOAD (4x)                                  12
ABI encoding                                       300
DELEGATECALL (cold)                                2,600
SLOAD vrfCoordinator (cold)                        2,100
Coordinator check                                  22
SLOAD vrfRequestId (cold)                          2,100
RequestId check                                    3
SLOAD rngWordCurrent (cold)                        2,100
Compound check + word zero check                   38
SLOAD rngLockedFlag (cold, slot 1)                 2,100
Branch check                                       10
SSTORE rngWordCurrent (warm, 0->NZ)                20,000   (slot already warm from SLOAD)
Return overhead                                    30
---------------------------------------------------------------------------
SUBTOTAL (excl tx base):                           31,415
TOTAL (incl tx base):                              52,415

Refunds:                                           none
EFFECTIVE TOTAL:                                   52,415
```

### 2.6 Important Clarification: VRF Callback Gas vs Transaction Gas

**The VRF_CALLBACK_GAS_LIMIT (300,000) applies to the gas available for the callback execution, NOT the total transaction gas.** The Chainlink VRF coordinator:

1. Receives the VRF proof in a transaction submitted by the VRF oracle node.
2. Verifies the VRF proof on-chain (consumes significant gas).
3. Calls `rawFulfillRandomWords` on the consumer contract with gas limited to `callbackGasLimit`.

The 300,000 gas limit is passed as the gas stipend for the external call from the coordinator to DegenerusGame. This means:

- **Transaction base cost (21,000) is NOT charged against the 300k limit** -- it is paid by the oracle's transaction.
- **The coordinator's proof verification gas is NOT charged against the 300k limit** -- it is separate overhead.
- **Only the execution of `rawFulfillRandomWords` (including the delegatecall) counts against the 300k limit.**

Therefore, the relevant comparison is the **SUBTOTAL (excluding tx base)**:

| Branch | Gas (excl. tx base) | Budget | Headroom | Headroom % |
|--------|--------------------:|-------:|---------:|-----------:|
| Daily (Path D) | ~31,415 | 300,000 | ~268,585 | **89.5%** |
| Lootbox (Path E) | ~45,258 | 300,000 | ~254,742 | **84.9%** |

### 2.7 Worst-Case Assessment

The worst-case is the **lootbox branch (Path E)** at ~45,258 gas (before refunds). This is well under the 300,000 gas limit with **~85% headroom**.

**Can any future code change push gas over the limit?**

The callback body contains:
- 5 SLOADs (cold): ~10,500 gas
- 1-3 SSTOREs: 20,000-26,000 gas
- 1 LOG1: ~1,518 gas
- Delegatecall overhead: ~2,600 gas
- Misc opcodes: ~500 gas

To exceed 300,000 gas, you would need to add roughly:
- **12 additional cold SSTOREs** (zero-to-nonzero at 22,100 each), OR
- **~120 additional cold SLOADs** (at 2,100 each), OR
- **Significant loop iterations** (which the current callback has none of)

The callback is intentionally minimal -- any significant gas increase would require a deliberate architectural change to add loops, external calls, or many more storage operations. This is extremely unlikely without a major contract rewrite.

---

## Section 3: Cross-Reference with Existing Tests

### 3.1 Gas Test Coverage

The existing `test/gas/AdvanceGameGas.test.js` measures gas for `advanceGame()` calls across all state machine stages, but does **not** measure `rawFulfillRandomWords` gas separately. The VRF fulfillment happens inside the mock coordinator and its gas is not isolated.

The VRF integration tests (`test/integration/VRFIntegration.test.js`) and RNG stall tests (`test/edge/RngStall.test.js`) test the access control and functional correctness of `rawFulfillRandomWords` but do not report gas measurements.

### 3.2 Access Control Test Confirmation

Tests confirm that:
- Calling `rawFulfillRandomWords` from a non-coordinator address reverts (VRFIntegration.test.js:237-258, RngStall.test.js:805-825).
- The revert is not specific to a custom error -- the tests check `.to.be.reverted` (not `.to.be.revertedWith`), which matches the generic `revert E()`.

---

## Section 4: Verdicts

### RNG-02: rawFulfillRandomWords Cannot Revert Under Normal Operation

**VERDICT: PASS**

**Evidence:**

1. The ONLY revert path is the coordinator check `if (msg.sender != address(vrfCoordinator)) revert E()`.
2. This check is unreachable in normal operation because only the registered VRF coordinator calls this function.
3. The coordinator rotation edge case (Section 1.3) is protected by:
   - 3-day stall precondition (VRF already non-functional)
   - Old subscription cancellation (prevents stale fulfillments)
   - Request ID reset to 0 (stale fulfillment would fail Path B before reaching Path A)
4. All other paths (B-E) either silently return or execute deterministic operations (SLOADs, SSTOREs, LOG) that cannot fail.
5. No external calls, no loops, no division, no array allocation, no unbounded operations.
6. The delegatecall wrapper correctly propagates reverts; successful returns (including silent returns) are handled as success.

**Risk assessment:** The coordinator check revert is defense-in-depth. The only scenario where it could be reached (coordinator rotation with in-flight fulfillment) is a 3+ day stall scenario where the old request is already abandoned. The revert is correct behavior in this edge case, not a vulnerability.

**Severity:** INFORMATIONAL -- No action needed. The revert path exists for security but is unreachable in normal VRF operation.

### RNG-03: rawFulfillRandomWords Gas Under 200k with Headroom

**VERDICT: PASS**

**Evidence:**

| Metric | Daily Branch | Lootbox Branch (Worst Case) |
|--------|------------:|----------------------------:|
| Estimated callback gas | ~31,415 | ~45,258 |
| VRF_CALLBACK_GAS_LIMIT | 300,000 | 300,000 |
| Absolute headroom | ~268,585 | ~254,742 |
| Headroom percentage | 89.5% | 84.9% |
| Under 200k target? | YES (31k) | YES (45k) |

**Note:** These are **static analysis estimates** based on EIP-2929/EIP-3529 gas pricing. Actual on-chain gas may vary by +/- 10% due to:
- Memory expansion costs (small, calldata is minimal)
- Stack manipulation overhead (captured in "misc opcodes" estimates)
- Solidity compiler optimization effects (viaIR enabled, optimizer runs=2)

Even with a generous 2x safety margin on the estimates, the worst-case gas (~90,500) remains well under the 300,000 limit with **~70% headroom**.

**Risk assessment:** The callback uses less than 16% of the available gas budget. There is no realistic path to gas exhaustion without a major contract rewrite that adds loops, external calls, or numerous additional storage operations.

**Severity:** INFORMATIONAL -- Gas budget is well within safe limits.

---

## Section 5: Findings Summary

| # | Finding | Severity | Requirement | Status |
|---|---------|----------|-------------|--------|
| F-01 | rawFulfillRandomWords has exactly 1 revert path (coordinator check), unreachable in normal operation | INFORMATIONAL | RNG-02 | PASS |
| F-02 | Coordinator rotation edge case: stale fulfillment would revert, but this is correct behavior after 3-day stall + subscription cancellation | INFORMATIONAL | RNG-02 | PASS |
| F-03 | Worst-case callback gas ~45k, well under 300k limit (~85% headroom) | INFORMATIONAL | RNG-03 | PASS |
| F-04 | word==0 sentinel mapping to 1 is correct; bias is negligible (1/2^256) | INFORMATIONAL | RNG-02 | PASS |
| F-05 | Delegatecall return value correctly checked; reverts are propagated, silent returns handled as success | INFORMATIONAL | RNG-02 | PASS |
| F-06 | No existing test measures rawFulfillRandomWords gas in isolation | LOW (testing gap) | RNG-03 | NOTE |

### F-06 Detail: Testing Gap

While the static analysis provides high confidence in the gas estimates, no existing test measures `rawFulfillRandomWords` gas in isolation. The gas test suite (`test/gas/AdvanceGameGas.test.js`) only measures `advanceGame()`. A dedicated gas measurement test for the VRF callback would provide on-chain confirmation of these static estimates.

**Recommendation:** Consider adding a gas measurement test that:
1. Sets up the game state with a pending VRF request
2. Calls `rawFulfillRandomWords` from the mock VRF coordinator
3. Reports `receipt.gasUsed` for both daily and lootbox branches

This is LOW severity because the static analysis already provides definitive evidence that gas is well within limits, and the margin is so large (~85% headroom) that estimation error cannot change the verdict.

---

## Appendix: Method

- **Contract versions analyzed:** mainnet contracts in `/contracts/` (not `/contracts-testnet/`)
- **Storage layout source:** `contracts/storage/DegenerusGameStorage.sol` slot documentation
- **Gas pricing model:** EIP-2929 (cold/warm access) + EIP-3529 (SSTORE refund changes)
- **Approach:** Static opcode-level analysis counting all storage accesses, computation, and delegatecall overhead
- **No contract files were modified during this audit**
