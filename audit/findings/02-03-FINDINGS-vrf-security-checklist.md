# 02-03 FINDINGS: VRF Security Checklist

**Auditor:** Claude Opus 4.6 (automated)
**Date:** 2026-02-28
**Scope:** Chainlink VRF V2.5 8-point security checklist, requestId lifecycle, concurrent request safety, 18h retry timeout analysis
**Target files:** `contracts/modules/DegenerusGameAdvanceModule.sol`, `contracts/DegenerusGame.sol`, `contracts/storage/DegenerusGameStorage.sol`
**Requirements:** RNG-04, RNG-05, RNG-07

---

## Section 1: requestId Lifecycle Analysis (RNG-04)

### 1.1 vrfRequestId Reference Inventory

All references to `vrfRequestId` in `contracts/` (excluding `contracts-testnet/`):

| Location | File:Line | Usage | Context |
|----------|-----------|-------|---------|
| Declaration | `DegenerusGameStorage.sol:304` | Declaration | `uint256 internal vrfRequestId;` |
| Assignment (lootbox) | `AdvanceModule.sol:626` | `=` | `vrfRequestId = id` in `requestLootboxRng()` |
| Read (lootbox finalize) | `AdvanceModule.sol:680` | Read | `lootboxRngRequestIndexById[vrfRequestId]` in `_finalizeLootboxRng()` |
| Read (emit) | `AdvanceModule.sol:683` | Read | `emit LootboxRngApplied(index, rngWord, vrfRequestId)` |
| Read (retry detect) | `AdvanceModule.sol:1062` | Read | `prevRequestId = vrfRequestId` in `_finalizeRngRequest()` |
| Assignment (daily/retry) | `AdvanceModule.sol:1082` | `=` | `vrfRequestId = requestId` in `_finalizeRngRequest()` |
| Clear (coordinator rotation) | `AdvanceModule.sol:1149` | `= 0` | `vrfRequestId = 0` in `updateVrfCoordinatorAndSub()` |
| Clear (unlock) | `AdvanceModule.sol:1162` | `= 0` | `vrfRequestId = 0` in `_unlockRng()` |
| Comparison (callback) | `AdvanceModule.sol:1204` | `!=` | `requestId != vrfRequestId` in `rawFulfillRandomWords()` |
| Read (callback lootbox) | `AdvanceModule.sol:1214` | Read | `lootboxRngRequestIndexById[requestId]` (uses parameter, not state) |
| Clear (callback lootbox) | `AdvanceModule.sol:1217` | `= 0` | `vrfRequestId = 0` in lootbox branch of callback |

**Total: 11 references across 2 files (AdvanceModule + Storage).**

### 1.2 Daily RNG requestId Lifecycle

```
Step 1: advanceGame() -> rngGate() -> _requestRng()
        vrfCoordinator.requestRandomWords() returns `id`
        _finalizeRngRequest() called:
          vrfRequestId = id           (line 1082)
          rngWordCurrent = 0          (line 1083)
          rngRequestTime = now        (line 1084)
          rngLockedFlag = true        (line 1085)

Step 2: Chainlink VRF coordinator calls rawFulfillRandomWords(requestId, words)
        DegenerusGame.rawFulfillRandomWords() delegates to AdvanceModule
        Check: msg.sender == vrfCoordinator     -> reverts E() if wrong
        Check: requestId != vrfRequestId        -> silent return if mismatch
        Check: rngWordCurrent != 0              -> silent return if already filled
        rngLockedFlag == true -> daily branch:
          rngWordCurrent = word                 (line 1211)

Step 3: Next advanceGame() -> rngGate()
        rngWordCurrent != 0 && rngRequestTime != 0 -> process daily RNG
        _applyDailyRng(day, currentWord) -> records to rngWordByDay[day]
        _finalizeLootboxRng(currentWord) -> maps lootbox index
        ... game logic ...
        _unlockRng(day):
          dailyIdx = day
          rngLockedFlag = false
          rngWordCurrent = 0
          vrfRequestId = 0              (line 1162)
          rngRequestTime = 0            (line 1163)
```

**Window analysis:** Between Steps 1 and 2, `vrfRequestId` holds the correct value assigned from `requestRandomWords()`. Between Steps 2 and 3, `vrfRequestId` still holds the same value (only cleared in Step 3 by `_unlockRng`). There is no window where `vrfRequestId` could hold a wrong value for the daily flow.

### 1.3 Lootbox RNG requestId Lifecycle

```
Step 1: requestLootboxRng()
        Guards: rngLockedFlag == false, rngRequestTime == 0
        vrfCoordinator.requestRandomWords() returns `id`
        _reserveLootboxRngIndex(id):
          index = lootboxRngIndex (1-based)
          lootboxRngRequestIndexById[id] = index
          lootboxRngIndex = index + 1
        vrfRequestId = id               (line 626)
        rngWordCurrent = 0              (line 627)
        rngRequestTime = now            (line 628)
        rngLockedFlag is NOT set

Step 2: Chainlink calls rawFulfillRandomWords(requestId, words)
        Check: requestId != vrfRequestId -> silent return if mismatch
        rngLockedFlag == false -> lootbox branch:
          index = lootboxRngRequestIndexById[requestId]
          lootboxRngWordByIndex[index] = word   (line 1215)
          emit LootboxRngApplied(index, word, requestId)
          vrfRequestId = 0              (line 1217)
          rngRequestTime = 0            (line 1218)
```

**Window analysis:** Between Steps 1 and 2, `vrfRequestId` holds the lootbox request ID. On callback, the requestId is validated before writing the word. After callback, state is fully cleared. No mismatch window exists.

### 1.4 Stale Daily Fulfillment After Lootbox Overwrite

**Scenario:** A daily VRF request is made (vrfRequestId = A). Before fulfillment, a lootbox request overwrites vrfRequestId = B. The old daily fulfillment (requestId = A) arrives.

**Analysis:** This scenario is **impossible by design**. A daily request sets `rngLockedFlag = true` (line 1085). `requestLootboxRng()` checks `if (rngLockedFlag) revert E()` (line 588). Therefore, a lootbox request cannot overwrite a pending daily request's ID.

**Reverse scenario:** A lootbox VRF request is pending (vrfRequestId = B). Can a daily request overwrite it? `rngGate()` is called from `advanceGame()`. When `rngRequestTime != 0` and `rngWordCurrent == 0`, the code checks if elapsed >= 18h and either retries or reverts `RngNotReady`. The daily `_requestRng()` path through `rngGate()` would only fire if `rngRequestTime == 0` (line 674-676) or on timeout retry (line 667-669). On the timeout retry path, `_finalizeRngRequest()` detects this as a retry (`isRetry = prevRequestId != 0 && rngRequestTime != 0 && rngWordCurrent == 0`, line 1063-1065) and remaps the lootbox index from the old request to the new request. The old fulfillment, if it arrives, will have the wrong requestId and be silently ignored.

**Verdict: SAFE.** The single `vrfRequestId` slot combined with mutual exclusion guards prevents any requestId mismatch scenario.

### 1.5 18h Retry requestId Handling

```
Step 1: Daily request made, vrfRequestId = A, rngLockedFlag = true
Step 2: 18 hours pass without fulfillment
Step 3: advanceGame() -> rngGate() detects elapsed >= 18h
        -> _requestRng() -> vrfCoordinator.requestRandomWords() returns id = B
        -> _finalizeRngRequest() with isRetry = true:
          prevRequestId = A
          reservedIndex = lootboxRngRequestIndexById[A]
          If reservedIndex != 0:
            delete lootboxRngRequestIndexById[A]
            lootboxRngRequestIndexById[B] = reservedIndex
          vrfRequestId = B  (overwrites A)
          rngWordCurrent = 0
          rngRequestTime = now
          rngLockedFlag = true (already true)

Step 4: If old fulfillment for requestId=A arrives:
        requestId (A) != vrfRequestId (B) -> silent return
        Old word is discarded. Correct.

Step 5: New fulfillment for requestId=B arrives:
        requestId (B) == vrfRequestId (B) -> accepted
        Lootbox index correctly mapped to B.
```

**Verdict: SAFE.** The retry path correctly remaps the lootbox index from old to new requestId and overwrites `vrfRequestId` so stale fulfillments are silently ignored.

---

## Section 2: Concurrent Request Safety (RNG-05)

### 2.1 Mutual Exclusion Proof

Daily and lootbox VRF requests share a single `vrfRequestId` slot. The protocol enforces mutual exclusion through two independent guard mechanisms:

**Guard 1: Daily blocks lootbox**
- `_finalizeRngRequest()` sets `rngLockedFlag = true` (line 1085)
- `requestLootboxRng()` checks `if (rngLockedFlag) revert E()` (line 588)
- Result: While a daily VRF request is pending, no lootbox request can be submitted.

**Guard 2: Lootbox blocks daily**
- `requestLootboxRng()` sets `rngRequestTime = uint48(block.timestamp)` (line 628)
- `rngGate()` checks `if (rngRequestTime != 0)` (line 665) and either retries after 18h or reverts `RngNotReady`
- Result: While a lootbox VRF request is pending, `advanceGame()` cannot submit a new daily request (it either waits or retries after timeout).

**Guard 3: Lootbox blocks lootbox**
- `requestLootboxRng()` checks `if (rngRequestTime != 0) revert E()` (line 589)
- Result: While any VRF request is pending (daily or lootbox), no second lootbox request can be submitted.

**Conclusion:** At most ONE VRF request can be pending at any time. The single `vrfRequestId` slot is sufficient.

### 2.2 Edge Case: advanceGame() While Lootbox RNG Pending

**Scenario:** A lootbox VRF request is pending (`rngRequestTime != 0`, `rngLockedFlag = false`, `rngWordCurrent = 0`). A new day begins and someone calls `advanceGame()`.

**Path through rngGate():**
1. `rngWordByDay[day] != 0`? No (new day, not yet recorded). Continue.
2. `currentWord != 0 && rngRequestTime != 0`? `currentWord = 0`, so NO. Skip.
3. `rngRequestTime != 0`? YES. Check elapsed:
   - If `elapsed < 18h`: `revert RngNotReady()`. The daily advance is blocked until the lootbox VRF fulfills or times out.
   - If `elapsed >= 18h`: `_requestRng()` is called. This creates a new daily request that OVERWRITES the lootbox request's `vrfRequestId`. The `_finalizeRngRequest()` detects `isRetry = true` and remaps the lootbox index.

**Sub-scenario: Lootbox VRF fulfills during the same day (before advanceGame):**
1. `rawFulfillRandomWords()` fires, `rngLockedFlag = false` -> lootbox branch.
2. Writes `lootboxRngWordByIndex[index] = word`.
3. Clears `vrfRequestId = 0` and `rngRequestTime = 0`.
4. Now `advanceGame()` -> `rngGate()` -> `rngRequestTime == 0` -> fresh daily request via `_requestRng()`. Clean path.

**Sub-scenario: Lootbox VRF fulfills AFTER the 18h timeout retry:**
1. Daily retry sets `vrfRequestId = B` (new), overwriting lootbox's `vrfRequestId = A`.
2. Lootbox fulfillment arrives with `requestId = A`.
3. `A != B` -> silent return. Lootbox word is lost.
4. **Impact:** The lootbox index that was remapped to the new daily request will receive the daily RNG word via `_finalizeLootboxRng()` during `rngGate()` processing. Lootbox outcomes are derived from the daily word instead of their own VRF word. This is **acceptable** because:
   - The daily word is equally random (same VRF source)
   - This only occurs after an 18h VRF stall (abnormal condition)
   - The alternative would be to leave lootboxes permanently unresolvable

**Verdict: SAFE.** No concurrent request ordering conflict is possible. The timeout fallback correctly handles lootbox index remapping.

---

## Section 3: Research Open Questions Resolved

### 3.1 Lootbox RNG Index 0 Behavior (Open Question #3)

**Question:** Can `lootboxRngRequestIndexById[id]` return 0 for a valid lootbox request, and if so, what happens?

**Storage declaration:**
```solidity
// DegenerusGameStorage.sol:1185
uint48 internal lootboxRngIndex = 1;  // 1-based
```

**Index reservation flow:**
```solidity
// AdvanceModule.sol:1183-1186
function _reserveLootboxRngIndex(uint256 requestId) private {
    uint48 index = lootboxRngIndex;         // starts at 1
    lootboxRngRequestIndexById[requestId] = index;
    lootboxRngIndex = index + 1;
    ...
}
```

**Analysis:**
- `lootboxRngIndex` starts at 1 and only increments. It can never be 0.
- `_reserveLootboxRngIndex()` always maps a requestId to a value >= 1.
- Therefore, `lootboxRngRequestIndexById[validRequestId]` is always >= 1 for any requestId that went through `_reserveLootboxRngIndex()`.

**Can index 0 be reached in rawFulfillRandomWords?**
```solidity
// AdvanceModule.sol:1212-1219
} else {
    uint48 index = lootboxRngRequestIndexById[requestId];
    lootboxRngWordByIndex[index] = word;
    ...
}
```

If `requestId` is valid and came through `_reserveLootboxRngIndex()`, `index` is always >= 1. The only way `index == 0` would be if `lootboxRngRequestIndexById[requestId]` was never set (default mapping value), but this cannot happen because:
- For daily requests: `_finalizeRngRequest()` calls `_reserveLootboxRngIndex(requestId)` (line 1079) on fresh requests, or remaps on retry (lines 1068-1074).
- For lootbox requests: `requestLootboxRng()` calls `_reserveLootboxRngIndex(id)` (line 625).

**However**, the retry path has a subtle edge case:
```solidity
// AdvanceModule.sol:1066-1075
if (isRetry) {
    uint48 reservedIndex = lootboxRngRequestIndexById[prevRequestId];
    if (reservedIndex != 0) {
        delete lootboxRngRequestIndexById[prevRequestId];
        lootboxRngRequestIndexById[requestId] = reservedIndex;
    } else {
        // Do not advance or clear pending on retry.
        lootboxRngRequestIndexById[requestId] = lootboxRngIndex;
    }
}
```

On retry where `reservedIndex == 0` (previous request had no lootbox mapping), the new requestId is mapped to `lootboxRngIndex` (current, not yet reserved). This is >= 1, so still safe.

**What about _finalizeLootboxRng() called from rngGate()?**
```solidity
// AdvanceModule.sol:679-684
function _finalizeLootboxRng(uint256 rngWord) private {
    uint48 index = lootboxRngRequestIndexById[vrfRequestId];
    if (index == 0) return;  // Guard: no lootbox mapping -> skip
    lootboxRngWordByIndex[index] = rngWord;
    emit LootboxRngApplied(index, rngWord, vrfRequestId);
}
```

The `if (index == 0) return` guard at line 681 explicitly handles the case where a daily request has no lootbox mapping (which would happen only if the mapping was already processed/deleted). This is a safety check, not a reachable-in-practice path.

**What about lootboxRngWordByIndex[0]?** This storage slot is never intentionally written to (all indices are >= 1). If it were written to, it would have no effect on game logic because lootbox opens reference indices >= 1.

**Verdict: SAFE.** Index 0 cannot be reached for valid requests. The `if (index == 0) return` guard in `_finalizeLootboxRng()` provides defense-in-depth.

### 3.2 _threeDayRngGap Duplication (Open Question #4)

**DegenerusGame.sol copy (line 2226-2231):**
```solidity
function _threeDayRngGap(uint48 day) private view returns (bool) {
    if (rngWordByDay[day] != 0) return false;
    if (rngWordByDay[day - 1] != 0) return false;
    if (day < 2 || rngWordByDay[day - 2] != 0) return false;
    return true;
}
```

**AdvanceModule.sol copy (line 1258-1263):**
```solidity
function _threeDayRngGap(uint48 day) private view returns (bool) {
    if (rngWordByDay[day] != 0) return false;
    if (rngWordByDay[day - 1] != 0) return false;
    if (day < 2 || rngWordByDay[day - 2] != 0) return false;
    return true;
}
```

**Comparison: IDENTICAL.** Both copies have the same logic, same guard order, same underflow protection (`day < 2` short-circuit).

**Which copy is executed?**

- **AdvanceModule copy:** Called from `updateVrfCoordinatorAndSub()` (AdvanceModule line 1139). This function is invoked via `delegatecall` from `DegenerusGame.updateVrfCoordinatorAndSub()` (DegenerusGame.sol line 1893-1910). Since it's a `delegatecall`, the AdvanceModule's `_threeDayRngGap` is the code that executes, but it reads storage from DegenerusGame's context. This is correct.

- **DegenerusGame copy:** Called from `rngStalledForThreeDays()` (DegenerusGame.sol line 2237). This is a direct `external view` function on DegenerusGame -- NOT delegatecalled. It reads DegenerusGame's own storage. This is also correct.

**Purpose divergence:**
- The AdvanceModule copy gates the `updateVrfCoordinatorAndSub()` action (write path)
- The DegenerusGame copy provides a view function for off-chain queries (read path)

Both copies MUST remain identical because they read the same storage (`rngWordByDay` mapping). If they diverged, the view function could report a different stall status than what the write function enforces.

**Finding: LOW severity (informational).** Code duplication with divergence risk. Both copies are currently identical. No functional issue. See Finding F-02.

### 3.3 Coordinator Rotation Edge Case (Open Question #2)

**Scenario:** VRF has stalled for 3 days. Admin calls `updateVrfCoordinatorAndSub()` to rotate to a new coordinator. During this transition:

1. The old coordinator might still fulfill the outstanding request
2. The new coordinator is now set in `vrfCoordinator`

**What happens if the old coordinator fulfills after rotation?**

```solidity
// AdvanceModule.sol:1203
if (msg.sender != address(vrfCoordinator)) revert E();
```

After rotation, `vrfCoordinator` points to the new coordinator. The old coordinator calling `rawFulfillRandomWords()` would have `msg.sender == oldCoordinator != address(vrfCoordinator)` -> **revert E()**. The old fulfillment is rejected.

**What about the delegatecall wrapper?**

```solidity
// DegenerusGame.sol:1952-1965
function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external {
    (bool ok, bytes memory data) = ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(
        abi.encodeWithSelector(
            IDegenerusGameAdvanceModule.rawFulfillRandomWords.selector,
            requestId, randomWords
        )
    );
    if (!ok) _revertDelegate(data);
}
```

The `msg.sender` check inside the delegatecall reads `msg.sender` from the original call context (the coordinator), and `vrfCoordinator` from DegenerusGame's storage (which was updated by the rotation). So the check correctly rejects the old coordinator.

**But the revert is a problem.** After coordinator rotation, `updateVrfCoordinatorAndSub()` clears `vrfRequestId = 0` (line 1149). So even if the old coordinator somehow got past the `msg.sender` check, the `requestId != vrfRequestId` check would also reject (since `vrfRequestId == 0`).

**Double protection:** Both `msg.sender` check AND `requestId` check prevent cross-coordinator fulfillment.

**Verdict: SAFE.** No cross-coordinator fulfillment ambiguity exists.

---

## Section 4: Chainlink VRF V2.5 8-Point Security Checklist

| # | Checklist Point | Verdict | Code Reference | Reasoning |
|---|----------------|---------|----------------|-----------|
| 1 | **RequestId matching** | **PASS** | `AdvanceModule.sol:1204` | `if (requestId != vrfRequestId \|\| rngWordCurrent != 0) return;` -- silent return on mismatch prevents stale/wrong fulfillments. Silent return (not revert) is correct to avoid wasting coordinator retries. |
| 2 | **Block confirmations** | **PASS** | `AdvanceModule.sol:88-89` | `VRF_REQUEST_CONFIRMATIONS = 10` (daily), `VRF_MIDDAY_CONFIRMATIONS = 3` (lootbox). 10 blocks is conservative for daily high-value operations. 3 blocks for lootbox is acceptable given lower individual value and time-sensitivity. |
| 3 | **No re-requesting/cancellation** | **DEVIATION** | `AdvanceModule.sol:667-669` | 18h timeout triggers re-request via `_requestRng()`. This deviates from the guideline but is a necessary liveness mechanism. The old requestId is overwritten, so old fulfillments are silently ignored. See Section 5 for full analysis. |
| 4 | **Close input windows** | **PASS** | Multiple (13 check sites) | `rngLockedFlag` blocks: nudges (`reverseFlip`, line 1172), ticket purchases (`MintModule:802`), lootbox opens (`LootboxModule:545, 622`), lootbox purchases during jackpot resolution (`MintModule:607`), config changes (`DegenerusGame:1549, 1570, 1585, 1650`), ETH degenerette bets during jackpot resolution (`DegeneretteModule:504-505`). Comprehensive coverage of state-changing operations. |
| 5 | **Callback must not revert** | **PASS** | `AdvanceModule.sol:1199-1220` | Only revert path: `if (msg.sender != address(vrfCoordinator)) revert E()` (line 1203). This is unreachable during normal VRF operation because only the coordinator calls this function. All other checks use `return` (not `revert`). No external calls, no loops, no unbounded operations in the callback. |
| 6 | **Use VRFConsumerBaseV2Plus** | **DEVIATION** | Custom implementation | Protocol does NOT inherit `VRFConsumerBaseV2Plus`. This is a deliberate design choice for delegatecall compatibility (base contract's `immutable` coordinator would conflict with upgradeable storage). The custom implementation replicates all security features: (a) coordinator address validation via `msg.sender` check, (b) request tracking via `vrfRequestId`, (c) callback routing via custom `rawFulfillRandomWords`. Security equivalent. |
| 7 | **Avoid ERC-4337 wallets** | **N/A** | No ERC-4337 integration | Not applicable to this protocol. |
| 8 | **Maintain adequate funding** | **PASS** | `AdvanceModule.sol:592-593` | Lootbox RNG checks `MIN_LINK_FOR_LOOTBOX_RNG = 40 LINK` before requesting. Daily RNG does NOT check LINK balance -- if `requestRandomWords()` reverts due to insufficient LINK, the entire `advanceGame()` transaction reverts, halting game progress. This is intentional and correct: halting is the safe behavior when the protocol cannot obtain randomness. The halt is recoverable once LINK is added. |

**Summary: 6 PASS, 2 DEVIATION, 0 FAIL, 1 N/A**

Both deviations are deliberate design choices with sound security rationale:
- Point 3 (re-requesting): Necessary for liveness; mitigated by requestId overwrite
- Point 6 (no base contract): Necessary for delegatecall architecture; all security features replicated

---

## Section 5: 18h Retry Timeout Analysis (RNG-07)

### 5.1 Timeout Mechanism

**Code (AdvanceModule.sol:664-671):**
```solidity
// Waiting for VRF - check for timeout retry
if (rngRequestTime != 0) {
    uint48 elapsed = ts - rngRequestTime;
    if (elapsed >= 18 hours) {
        _requestRng(isTicketJackpotDay, lvl);
        return 1;
    }
    revert RngNotReady();
}
```

**Condition:** `rngRequestTime != 0` (request was made) AND `rngWordCurrent == 0` (word not yet received) AND `elapsed >= 18 hours`.

**Action:** A new VRF request is submitted. The old request is abandoned. `_finalizeRngRequest()` detects `isRetry = true` and:
1. Remaps the lootbox index from old requestId to new requestId
2. Overwrites `vrfRequestId` with the new value
3. Resets `rngRequestTime` to current timestamp

### 5.2 Validator Abuse Scenario Analysis

**Threat model:** A Chainlink VRF node operator who is also a player (or colluding with a player) could:

1. **Withhold fulfillment for 18h to force re-request:** The validator sees the VRF word but does not submit the fulfillment transaction. After 18h, `advanceGame()` re-requests.

2. **After re-request, the validator sees BOTH the old and new words:** The old word (from request A) and the new word (from request B, if they are also the node for the new request).

3. **Can they choose which word to apply?**
   - **NO.** After re-request, `vrfRequestId = B`. If the validator submits the old fulfillment (requestId = A), it fails the `requestId != vrfRequestId` check and is silently ignored. Only the NEW fulfillment (requestId = B) will be accepted.

4. **Can they delay the NEW fulfillment to get another re-request?**
   - **YES**, but this only repeats the same pattern. Each re-request generates a new independent random word. The validator cannot select among multiple words because only the most recent requestId is accepted.

5. **Can they NOT fulfill at all?**
   - Chainlink VRF has multiple node operators. A single malicious node cannot prevent fulfillment indefinitely. Other nodes in the subscription's key hash gas lane would fulfill the request.
   - If ALL nodes fail (Chainlink outage), the 3-day emergency coordinator rotation (`updateVrfCoordinatorAndSub()`) provides recovery.

6. **Is there any advantage to forcing a re-request?**
   - The new random word is cryptographically independent of the old one. The validator gains no information about the new word from knowing the old word.
   - The only "advantage" is delaying game progress by 18 hours, which is a griefing attack, not a value-extraction attack.
   - Cost: The validator loses their Chainlink reputation/stake for not fulfilling. The protocol loses 18h of game progress. The risk/reward is heavily against the attacker.

### 5.3 Chainlink Re-request Guideline Assessment

Chainlink's guideline states: "Don't re-request randomness." The rationale is that re-requesting allows a miner/validator to see the fulfillment and choose to accept or reject it.

**How the protocol mitigates this:**
- Re-requests happen ONLY after 18h timeout (not on-demand)
- The old requestId is discarded, so the old word cannot be used
- The new word is independent and unknown to the requester
- The 18h delay makes this impractical for value extraction (game state changes daily)

**Assessment:** The deviation from the guideline is necessary for protocol liveness. The mitigation (requestId overwrite) eliminates the word-selection attack that the guideline is designed to prevent. This is a **well-justified deviation**.

### 5.4 Comparison to Chainlink Recommendations

| Guideline | Protocol Approach | Risk |
|-----------|-------------------|------|
| Don't re-request | Re-requests after 18h timeout | MITIGATED: requestId overwrite prevents word selection |
| Use same VRF subscription | Same subscription for retry | COMPLIANT |
| Don't cancel pending requests | Old request abandoned (not cancelled via VRF API) | MITIGATED: Chainlink may still deliver, but it's silently ignored |

---

## Section 6: Requirement Verdicts

### RNG-04: requestId Matching Correctness

**Verdict: PASS**

**Evidence:**
- Single `vrfRequestId` slot with 11 references fully traced (Section 1.1)
- Daily lifecycle: requestId set atomically with lock, checked on callback, cleared on unlock (Section 1.2)
- Lootbox lifecycle: requestId set after index reservation, checked on callback, cleared in callback (Section 1.3)
- Stale fulfillment: silently ignored via requestId mismatch check (Section 1.4)
- Retry path: correctly remaps lootbox index from old to new requestId (Section 1.5)
- No scenario found where a wrong requestId applies the wrong VRF word to wrong game state

### RNG-05: Concurrent Request Safety

**Verdict: PASS**

**Evidence:**
- Three independent mutual exclusion guards prevent concurrent requests (Section 2.1):
  - `rngLockedFlag` blocks lootbox during daily
  - `rngRequestTime` blocks daily during lootbox
  - `rngRequestTime` blocks lootbox during lootbox
- Edge case (advanceGame during lootbox pending) correctly handled via timeout retry or RngNotReady revert (Section 2.2)
- Single `vrfRequestId` slot is sufficient given mutual exclusion guarantees

### RNG-07: 18h Timeout Abuse Resistance

**Verdict: PASS**

**Evidence:**
- Validator cannot select among multiple VRF words because requestId overwrite discards old fulfillments (Section 5.2, points 3-4)
- New words are cryptographically independent of old words (Section 5.2, point 6)
- 18h delay makes timing attacks impractical for daily game mechanics
- Griefing cost (validator reputation/stake loss) exceeds benefit (18h game delay)
- 3-day emergency recovery prevents permanent lockout from sustained attack

---

## Section 7: Findings

### F-01: VRF Request Ordering in _requestRng() (INFORMATIONAL)

**Severity:** INFORMATIONAL
**Location:** `AdvanceModule.sol:1013-1026`
**Description:** The VRF request is submitted to the coordinator BEFORE `rngLockedFlag` is set:
```solidity
function _requestRng(bool isTicketJackpotDay, uint24 lvl) private {
    uint256 id = vrfCoordinator.requestRandomWords(...);  // 1. Request VRF
    _finalizeRngRequest(isTicketJackpotDay, lvl, id);      // 2. Set lock
}
```
If the VRF coordinator fulfilled the request synchronously (in the same transaction), the callback would see `rngLockedFlag == false` and take the lootbox path instead of the daily path.

**Impact:** NONE in practice. Chainlink VRF V2.5 always fulfills asynchronously in a separate transaction. Synchronous fulfillment is architecturally impossible in the Chainlink design.

**Recommendation:** No action required. This is a defense-in-depth observation, not a vulnerability.

### F-02: _threeDayRngGap Code Duplication (INFORMATIONAL)

**Severity:** INFORMATIONAL
**Location:** `DegenerusGame.sol:2226-2231` and `AdvanceModule.sol:1258-1263`
**Description:** Identical `_threeDayRngGap()` function exists in both DegenerusGame and AdvanceModule. The DegenerusGame copy is used for the `rngStalledForThreeDays()` view function. The AdvanceModule copy is used for `updateVrfCoordinatorAndSub()` via delegatecall.

Both copies are currently identical. Both include the `day < 2` underflow guard. However, code duplication creates a divergence risk: if one copy is modified without updating the other, the view function could report inconsistent stall status compared to the write function.

**Impact:** No current issue. Future maintenance risk only.

**Recommendation:** Consider extracting to a shared library function, or add a comment cross-referencing the two copies to alert future developers.

### F-03: rawFulfillRandomWords Lootbox Branch Does Not Check Index == 0 (INFORMATIONAL)

**Severity:** INFORMATIONAL
**Location:** `AdvanceModule.sol:1212-1219`
**Description:** In the lootbox branch of `rawFulfillRandomWords()`:
```solidity
} else {
    uint48 index = lootboxRngRequestIndexById[requestId];
    lootboxRngWordByIndex[index] = word;  // writes to index without checking != 0
    ...
}
```
Unlike `_finalizeLootboxRng()` (line 681) which checks `if (index == 0) return`, the callback's lootbox branch does NOT check for index 0.

**Impact:** NONE. As analyzed in Section 3.1, `lootboxRngRequestIndexById[requestId]` is always >= 1 for any requestId that reaches this code path. The requestId must have gone through either `_reserveLootboxRngIndex()` or the retry remapping, both of which assign values >= 1. Additionally, the `requestId != vrfRequestId` check on line 1204 ensures only valid requestIds reach this branch.

If somehow index 0 were reached, `lootboxRngWordByIndex[0]` would be written to, but this slot is never read by lootbox open logic (which uses indices >= 1). No functional impact.

**Recommendation:** No action required. The guard is unnecessary given the invariants, though adding `if (index == 0) return` would provide defense-in-depth consistency with `_finalizeLootboxRng()`.

---

## Summary of Findings

| ID | Severity | Description | Impact |
|----|----------|-------------|--------|
| F-01 | INFORMATIONAL | VRF request submitted before lock set in `_requestRng()` | None (async fulfillment) |
| F-02 | INFORMATIONAL | `_threeDayRngGap` duplicated in Game and AdvanceModule | None (currently identical) |
| F-03 | INFORMATIONAL | Lootbox callback branch skips index 0 check | None (invariant prevents) |

**No HIGH, MEDIUM, or LOW severity findings.** All three informational findings describe correct code with opportunities for defense-in-depth improvements.
