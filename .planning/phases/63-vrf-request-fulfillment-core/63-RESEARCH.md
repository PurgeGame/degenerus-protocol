# Phase 63: VRF Request/Fulfillment Core - Research

**Researched:** 2026-03-22
**Domain:** Chainlink VRF V2.5 request/fulfillment lifecycle audit in DegenerusGame
**Confidence:** HIGH

## Summary

This phase audits the core VRF request and fulfillment mechanism in DegenerusGame, focusing on four areas: (1) rawFulfillRandomWords callback revert-safety and gas budget, (2) vrfRequestId lifecycle correctness, (3) rngLockedFlag mutual exclusion between daily and mid-day VRF, and (4) 12h timeout retry correctness.

The VRF integration spans two contracts: DegenerusGame.sol (entry point, delegatecall proxy) and DegenerusGameAdvanceModule.sol (all VRF logic). The main contract's `rawFulfillRandomWords` is a thin delegatecall wrapper. All state lives in DegenerusGameStorage.sol and is accessed through the delegatecall context.

**Primary recommendation:** Audit should trace every code path through rawFulfillRandomWords (both daily and mid-day branches), enumerate all SSTORE operations for gas budgeting, then systematically prove _finalizeRngRequest's retry detection and rngLockedFlag mutual exclusion via Foundry fuzz tests.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| VRFC-01 | rawFulfillRandomWords cannot revert (except msg.sender check), gas budget sufficient for all code paths | Gas analysis of callback paths (Section: Architecture Patterns, "Callback Gas Analysis"); code path enumeration of daily vs mid-day branches |
| VRFC-02 | vrfRequestId lifecycle verified -- set on request, cleared on fulfillment, retry detection correct in _finalizeRngRequest | State variable tracing (Section: Architecture Patterns, "VRF Request ID Lifecycle"); _finalizeRngRequest retry detection logic analysis |
| VRFC-03 | rngLockedFlag mutual exclusion proven airtight -- no path allows daily and mid-day VRF requests to collide | Mutual exclusion analysis (Section: Architecture Patterns, "rngLockedFlag Mutual Exclusion"); requestLootboxRng guard analysis |
| VRFC-04 | VRF 12h timeout retry path verified -- stale request detection and re-request behavior correct | Timeout analysis (Section: Architecture Patterns, "12h Timeout Retry Logic"); lootboxRngIndex corruption analysis |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Foundry (forge) | Latest | Fuzz/invariant testing, gas profiling | Already configured in foundry.toml; project standard |
| forge-std | Latest | Test assertions, vm cheatcodes | Already in lib/ |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| MockVRFCoordinator | Custom (contracts/mocks/) | Simulates Chainlink VRF V2.5 coordinator | All VRF tests -- already deployed by DeployProtocol.sol |
| VRFHandler | Custom (test/fuzz/helpers/) | Wraps mock VRF for invariant testing | Reuse in new fuzz/invariant tests |
| DeployProtocol | Custom (test/fuzz/helpers/) | Full protocol deployment for testing | Base contract for all new test files |

### Existing Test Infrastructure
| File | Purpose | Reusable? |
|------|---------|-----------|
| test/fuzz/VRFLifecycle.t.sol | Basic VRF fulfillment + level advancement tests | Yes -- extend with new invariants |
| test/fuzz/StallResilience.t.sol | Stall/swap/resume integration tests | Yes -- pattern for coordinator swap tests |
| test/fuzz/helpers/DeployProtocol.sol | Full protocol deployment | Yes -- inherit for all new tests |
| test/fuzz/helpers/VRFHandler.sol | VRF fulfillment handler for fuzzing | Yes -- use for invariant tests |
| contracts/mocks/MockVRFCoordinator.sol | Mock Chainlink coordinator | Yes -- already supports fulfillRandomWords + fulfillRandomWordsRaw |

**Installation:** No new packages needed. All infrastructure exists.

**Test commands:**
```bash
forge test --match-path test/fuzz/VRFLifecycle.t.sol -vvv     # Existing VRF tests
forge test --match-path test/fuzz/StallResilience.t.sol -vvv   # Existing stall tests
forge test --fuzz-runs 1000 -vvv                                # Full fuzz suite
```

## Architecture Patterns

### VRF State Variables (Complete Inventory)

All VRF-related state lives in DegenerusGameStorage.sol:

| Variable | Type | Slot | Purpose |
|----------|------|------|---------|
| `rngRequestTime` | uint48 | Slot 0 [12:18] | Timestamp of last VRF request; 0 = no request in-flight |
| `rngLockedFlag` | bool | Slot 0 [26:27] | Daily RNG lock; true during jackpot resolution window |
| `rngWordCurrent` | uint256 | Slot 5 | Latest VRF word (0 = pending); consumed by advanceGame |
| `vrfRequestId` | uint256 | Slot 6 | Last VRF request ID for fulfillment matching |
| `vrfCoordinator` | IVRFCoordinator | Deep slot | Coordinator contract address (mutable for emergency rotation) |
| `vrfKeyHash` | bytes32 | Deep slot | Gas lane key hash |
| `vrfSubscriptionId` | uint256 | Deep slot | LINK billing subscription ID |
| `lootboxRngIndex` | uint48 | Deep slot | 1-based index for lootbox RNG rounds (starts at 1) |
| `lootboxRngWordByIndex` | mapping(uint48=>uint256) | mapping | RNG word per lootbox index |
| `lastLootboxRngWord` | uint256 | Deep slot | Last resolved lootbox word |
| `midDayTicketRngPending` | bool | Deep slot | True when mid-day ticket buffer swap is pending VRF |
| `rngWordByDay` | mapping(uint48=>uint256) | mapping | Daily RNG word indexed by game day |
| `lastVrfProcessedTimestamp` | uint48 | Deep slot | Timestamp of last successful VRF processing |

### VRF Request Entry Points (3 total)

1. **`_requestRng` (daily)** -- Called from `rngGate` during `advanceGame`. Hard-reverts on Chainlink failure. Sets `rngLockedFlag = true`. Uses 10 block confirmations.

2. **`requestLootboxRng` (mid-day)** -- Standalone external function. Does NOT set `rngLockedFlag`. Uses 3 block confirmations. Guards: `rngLockedFlag` must be false, `rngRequestTime` must be 0, current day's daily RNG must already be recorded, not in 15-min pre-reset window, LINK balance >= 40 LINK, pending lootbox value above threshold.

3. **`_tryRequestRng` (gameover)** -- Called from `_gameOverEntropy`. Non-reverting (try/catch). Falls back to historical entropy if request fails.

### Pattern 1: rawFulfillRandomWords Callback Flow

**What:** The Chainlink coordinator calls `rawFulfillRandomWords(requestId, randomWords)` on DegenerusGame.sol, which delegatecalls to DegenerusGameAdvanceModule.sol.

**DegenerusGame.sol (lines 2001-2015) -- Proxy layer:**
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

**DegenerusGameAdvanceModule.sol (lines 1402-1423) -- Actual logic:**
```solidity
function rawFulfillRandomWords(
    uint256 requestId,
    uint256[] calldata randomWords
) external {
    if (msg.sender != address(vrfCoordinator)) revert E();
    if (requestId != vrfRequestId || rngWordCurrent != 0) return;  // Silent return, NOT revert

    uint256 word = randomWords[0];
    if (word == 0) word = 1;  // Zero-guard

    if (rngLockedFlag) {
        // Daily RNG: store for advanceGame processing
        rngWordCurrent = word;
    } else {
        // Mid-day RNG: directly finalize lootbox
        uint48 index = lootboxRngIndex - 1;
        lootboxRngWordByIndex[index] = word;
        emit LootboxRngApplied(index, word, requestId);
        vrfRequestId = 0;
        rngRequestTime = 0;
    }
}
```

**Critical audit observation:** The `if (!ok) _revertDelegate(data)` in the proxy means if the delegatecall itself fails (out of gas, stack overflow), the outer function WILL revert. But within the module's rawFulfillRandomWords, the only revert is `if (msg.sender != address(vrfCoordinator)) revert E()`. All other paths either `return` silently or execute storage writes.

### Callback Gas Analysis (VRFC-01)

The 300,000 gas callback limit (`VRF_CALLBACK_GAS_LIMIT = 300_000`) must cover:

**Path A: Daily RNG (rngLockedFlag == true)**
| Operation | Gas (worst case cold) | Notes |
|-----------|-----------------------|-------|
| Transaction overhead | ~21,000 | Chainlink pays this |
| Coordinator overhead | ~90,000-112,000 | Chainlink's verification; NOT charged to callback |
| DELEGATECALL to module | 2,600 | Cold module address |
| SLOAD vrfCoordinator | 2,100 | Cold, Slot deep |
| msg.sender comparison | ~3 | Trivial |
| SLOAD vrfRequestId | 2,100 | Cold, Slot 6 |
| SLOAD rngWordCurrent | 2,100 | Cold, Slot 5 |
| Comparison + branch | ~20 | Trivial |
| calldata read randomWords[0] | ~40 | calldata access |
| SLOAD rngLockedFlag | 2,100 | Cold, Slot 0 |
| SSTORE rngWordCurrent (0 -> nonzero) | 22,100 | Cold, zero-to-nonzero |
| Return + cleanup | ~200 | ABI return |
| **Total Path A** | **~33,363** | Well under 300k |

**Path B: Mid-day RNG (rngLockedFlag == false)**
| Operation | Gas (worst case cold) | Notes |
|-----------|-----------------------|-------|
| DELEGATECALL to module | 2,600 | Cold module address |
| SLOAD vrfCoordinator | 2,100 | Cold |
| SLOAD vrfRequestId | 2,100 | Cold |
| SLOAD rngWordCurrent | 2,100 | Cold |
| SLOAD rngLockedFlag | 2,100 | Cold |
| SLOAD lootboxRngIndex | 2,100 | Cold |
| SSTORE lootboxRngWordByIndex[index] (0 -> nonzero) | 22,100 | Cold mapping, zero-to-nonzero |
| LOG3 (LootboxRngApplied, 3 indexed + data) | ~1,500 | 3 topics + 32 bytes |
| SSTORE vrfRequestId (nonzero -> zero) | 100 + 4,800 refund | Warm after earlier read; zero-out gets refund |
| SSTORE rngRequestTime (nonzero -> zero) | 5,000 | Cold slot 0 write (same slot as rngLockedFlag, but different packed position -- still 1 SSTORE) |
| Return + cleanup | ~200 | |
| **Total Path B** | **~46,900** | Well under 300k |

**Path C: Silent return (stale/duplicate)**
| Operation | Gas (worst case cold) | Notes |
|-----------|-----------------------|-------|
| DELEGATECALL | 2,600 | |
| SLOAD vrfCoordinator | 2,100 | |
| SLOAD vrfRequestId | 2,100 | |
| SLOAD rngWordCurrent | 2,100 | |
| Return | ~200 | |
| **Total Path C** | **~9,100** | Trivial |

**Verdict:** All paths are well under 100k gas, far below the 300k budget. The 300k limit provides ~6x safety margin on the most expensive path.

**Important note on Slot 0 packing:** `rngLockedFlag` (byte 26), `rngRequestTime` (bytes 12-17), and several other fields share EVM Slot 0. A single SLOAD reads the entire 32-byte slot. The mid-day path writes back to Slot 0 via `rngRequestTime = 0`, which is a single SSTORE to the packed slot. This is warm after the initial SLOAD.

### VRF Request ID Lifecycle (VRFC-02)

**Set points:**
1. `_finalizeRngRequest(...)` -- line 1284: `vrfRequestId = requestId`
2. `requestLootboxRng()` -- line 741: `vrfRequestId = id`

**Clear points:**
1. `rawFulfillRandomWords` mid-day branch -- line 1420: `vrfRequestId = 0`
2. `_unlockRng(day)` -- line 1376: `vrfRequestId = 0`
3. `updateVrfCoordinatorAndSub(...)` -- line 1352: `vrfRequestId = 0`

**Matching logic in rawFulfillRandomWords (line 1407):**
```solidity
if (requestId != vrfRequestId || rngWordCurrent != 0) return;
```
This silently discards: (a) stale fulfillments from old request IDs, (b) duplicate fulfillments when rngWordCurrent already set.

**Retry detection in _finalizeRngRequest (lines 1272-1274):**
```solidity
bool isRetry = vrfRequestId != 0 &&
    rngRequestTime != 0 &&
    rngWordCurrent == 0;
```
A retry is detected when: there's an existing request ID AND a request timestamp AND no word has been received. This correctly distinguishes:
- **Fresh request:** vrfRequestId == 0 (cleared by _unlockRng) -> `isRetry = false` -> lootboxRngIndex++
- **Retry (timeout):** vrfRequestId != 0, rngRequestTime != 0, rngWordCurrent == 0 -> `isRetry = true` -> NO lootboxRngIndex increment
- **Post-fulfillment re-request:** vrfRequestId != 0, rngWordCurrent != 0 -> `isRetry = false` (NOTE: this case should not occur because rngGate processes the word before requesting new RNG)

**Audit concern: requestLootboxRng sets vrfRequestId but does NOT use _finalizeRngRequest.** It directly writes `vrfRequestId = id` at line 741 and `lootboxRngIndex++` at line 738. This is correct because: (a) the `rngRequestTime != 0` guard at line 690 prevents a second mid-day request while one is in-flight, (b) mid-day requests always increment the index (no retry concept for mid-day -- if the word arrives via rawFulfillRandomWords, it's directly stored).

### rngLockedFlag Mutual Exclusion (VRFC-03)

**rngLockedFlag = true set by:**
- `_finalizeRngRequest` -- line 1287 (daily RNG request)

**rngLockedFlag = false set by:**
- `_unlockRng` -- line 1374 (end of daily processing)
- `updateVrfCoordinatorAndSub` -- line 1351 (emergency rotation)

**rngLockedFlag is NOT set by requestLootboxRng.** This is the key design: mid-day lootbox RNG does not lock the daily flow.

**Guard in requestLootboxRng (line 680):**
```solidity
if (rngLockedFlag) revert RngLocked();
```

**Guard analysis -- can daily and mid-day requests collide?**

Scenario 1: Daily request in-flight, mid-day attempted
- `_requestRng` sets `rngLockedFlag = true`
- `requestLootboxRng` checks `rngLockedFlag` at line 680 -> reverts with `RngLocked()`
- **SAFE: blocked by rngLockedFlag guard**

Scenario 2: Mid-day request in-flight, daily attempted
- `requestLootboxRng` does NOT set `rngLockedFlag`
- `requestLootboxRng` sets `rngRequestTime` to current timestamp (line 743)
- `advanceGame` -> `rngGate` -> checks `rngWordByDay[day]` -> if daily word not recorded, enters RNG request logic
- BUT `rngRequestTime != 0` at line 690 would have blocked a second `requestLootboxRng` call
- In `rngGate`, `rngRequestTime != 0` enters the "Waiting for VRF" branch (line 831), checks timeout, and either retries or reverts `RngNotReady`
- **KEY OBSERVATION:** rngGate's "waiting for VRF" path at line 831 does NOT distinguish between a daily-pending and mid-day-pending request. If a mid-day request is in-flight and advanceGame is called on a new day, rngGate will either: (a) wait for the mid-day fulfillment (revert RngNotReady), or (b) after 12h timeout, call `_requestRng` which overwrites vrfRequestId and sets rngLockedFlag=true.

**Critical scenario to audit:** Mid-day requestLootboxRng fires at time T. At time T+N (new day), advanceGame calls rngGate. rngGate sees `rngRequestTime != 0` and `rngWordCurrent == 0` (mid-day word went to lootboxRngWordByIndex, not rngWordCurrent). BUT WAIT -- if the mid-day callback already fired, `vrfRequestId` was cleared to 0 and `rngRequestTime` was cleared to 0 in the mid-day branch of rawFulfillRandomWords (lines 1420-1421). So rngGate would enter the "Need fresh RNG" branch (line 841) and call `_requestRng` normally.

**The collision risk is if mid-day VRF has NOT been fulfilled when advanceGame runs on a new day.** In that case rngGate enters the waiting path, sees `rngRequestTime != 0`, waits for timeout or fulfillment. If the mid-day VRF arrives while daily is waiting, rawFulfillRandomWords matches the mid-day requestId and stores the word in lootboxRngWordByIndex (since rngLockedFlag is false). Then on the next advanceGame call, rngRequestTime is still nonzero but rngWordCurrent is 0, so it retries or waits more. After 12h timeout from rngRequestTime, `_requestRng` is called which sets `rngLockedFlag = true` and overwrites vrfRequestId.

**Additional guard:** requestLootboxRng has a 15-minute pre-reset window block (line 686):
```solidity
if (_simulatedDayIndexAt(nowTs + 15 minutes) > currentDay) revert E();
```
This prevents mid-day requests within 15 minutes of the daily boundary, reducing collision window.

### 12h Timeout Retry Logic (VRFC-04)

**Location:** rngGate lines 831-837:
```solidity
if (rngRequestTime != 0) {
    uint48 elapsed = ts - rngRequestTime;
    if (elapsed >= 12 hours) {
        _requestRng(isTicketJackpotDay, lvl);
        return 1;
    }
    revert RngNotReady();
}
```

**Flow:**
1. VRF request fires, `rngRequestTime` set to `block.timestamp`
2. Each `advanceGame` call checks: has it been >= 12 hours since request?
3. If yes: calls `_requestRng` -> `_finalizeRngRequest` which detects retry
4. `_finalizeRngRequest` retry detection: `vrfRequestId != 0 && rngRequestTime != 0 && rngWordCurrent == 0` -> `isRetry = true`
5. On retry: `lootboxRngIndex` is NOT incremented (line 1275-1280), only vrfRequestId, rngWordCurrent, rngRequestTime are updated

**lootboxRngIndex corruption analysis:**
- Fresh daily request: `isRetry = false` -> `lootboxRngIndex++` (correct: new lootbox round)
- Timeout retry: `isRetry = true` -> NO increment (correct: same lootbox round, new request ID)
- Fresh mid-day request (requestLootboxRng): increments at line 738 (correct: independent increment)

**Edge case -- stale VRF word from old request arrives after retry:**
After retry, vrfRequestId is overwritten with new ID. If old VRF arrives, `requestId != vrfRequestId` -> silently discarded at line 1407. **SAFE.**

**Edge case -- rngGate sees rngWordCurrent != 0 from old day:**
If a VRF word arrives (rngWordCurrent set), but it was requested on a previous day, rngGate detects this at lines 783-791:
```solidity
uint48 requestDay = _simulatedDayIndexAt(rngRequestTime);
if (requestDay < day) {
    _finalizeLootboxRng(currentWord);  // Use for lootboxes
    rngWordCurrent = 0;
    _requestRng(isTicketJackpotDay, lvl);  // Request fresh daily
    return 1;
}
```
**SAFE:** stale daily words are redirected to lootbox use only, then fresh RNG is requested.

### Anti-Patterns to Avoid
- **Do not assume warm storage in gas analysis:** The VRF callback is a separate transaction; all SLOADs are cold.
- **Do not conflate requestLootboxRng and _requestRng paths:** They have different guards and different state mutation patterns.
- **Do not test only happy paths:** Must fuzz timeout retries, stale fulfillments, coordinator changes, and cross-day boundary requests.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| VRF mock | Custom VRF simulation | MockVRFCoordinator.sol | Already handles requestRandomWords + fulfillRandomWords; supports raw fulfillment for edge cases |
| Protocol deployment | Manual contract setup | DeployProtocol.sol | Deploys all 23 contracts with correct addresses; critical for delegatecall-based architecture |
| VRF fulfillment handler | Manual fulfill in tests | VRFHandler.sol | Wraps mock with ghost tracking and bounds; reusable across invariant tests |
| Gas profiling | Manual opcode counting | forge test --gas-report | Foundry's native gas reporting is more accurate than manual counting |

## Common Pitfalls

### Pitfall 1: Delegatecall msg.sender Confusion
**What goes wrong:** In the callback, `msg.sender` inside the delegatecalled module is the VRF coordinator (correct -- delegatecall preserves msg.sender). But tests might call rawFulfillRandomWords directly on the game contract, which would make msg.sender the test contract, not the mock VRF.
**Why it happens:** delegatecall preserves msg.sender from the outer call.
**How to avoid:** Always call `mockVRF.fulfillRandomWords(reqId, word)` which makes the mock coordinator the msg.sender. Never call `game.rawFulfillRandomWords(...)` directly in tests unless testing the unauthorized caller revert.
**Warning signs:** Tests pass but with wrong msg.sender, or tests always revert with E().

### Pitfall 2: Packed Slot 0 Side Effects
**What goes wrong:** rngLockedFlag, rngRequestTime, dailyIdx, and other fields share Slot 0. Writing one field via assembly or packed access could corrupt adjacent fields.
**Why it happens:** Solidity handles packing correctly for individual field writes, but audit must verify no raw assembly manipulation of Slot 0 exists.
**How to avoid:** Verify all Slot 0 field writes go through normal Solidity assignments, not assembly.
**Warning signs:** State corruption after VRF callback -- flags in wrong state.

### Pitfall 3: Mid-day/Daily Request Ordering at Day Boundary
**What goes wrong:** If requestLootboxRng fires just before the day boundary and VRF fulfills just after, the mid-day branch of rawFulfillRandomWords runs (rngLockedFlag still false), clearing vrfRequestId and rngRequestTime. The daily flow then proceeds normally. BUT if the mid-day VRF is very slow and the daily request fires first (via timeout retry), the old mid-day request's fulfillment will be silently discarded because vrfRequestId was overwritten.
**Why it happens:** The 15-minute pre-reset guard reduces but doesn't eliminate this window.
**How to avoid:** The 15-minute guard + 12h timeout make this mostly theoretical. Test it anyway.
**Warning signs:** Lost lootbox RNG word -- lootboxRngWordByIndex[index] never filled.

### Pitfall 4: Double lootboxRngIndex Increment on Retry
**What goes wrong:** If retry detection fails, _finalizeRngRequest increments lootboxRngIndex again, creating a "gap" index that never gets a VRF word.
**Why it happens:** isRetry condition has three conjuncts; if any is wrong, fresh-request path runs.
**How to avoid:** Fuzz test that verifies: after a timeout retry, lootboxRngIndex == pre-retry lootboxRngIndex.
**Warning signs:** lootboxRngWordByIndex[index] == 0 for indices that should have been filled.

### Pitfall 5: rngWordCurrent Not Cleared After Daily Processing
**What goes wrong:** If rngWordCurrent persists across transactions, a stale word could be used.
**Why it happens:** _unlockRng clears rngWordCurrent, vrfRequestId, and rngRequestTime. If any code path skips _unlockRng...
**How to avoid:** Trace every rngGate exit path to verify _unlockRng is called on the final advanceGame call of the day.
**Warning signs:** rngWordCurrent != 0 when rngLockedFlag == false (outside of mid-day fulfillment window).

## Code Examples

### Test Pattern: VRF Callback Revert-Safety
```solidity
// Source: Verified from contracts/modules/DegenerusGameAdvanceModule.sol lines 1402-1423
// Prove callback never reverts (except bad sender)
function test_callbackNeverReverts(uint256 requestId, uint256 randomWord) public {
    // Setup: make a VRF request
    game.advanceGame();
    uint256 realReqId = mockVRF.lastRequestId();

    // Fulfill with any word -- should not revert
    mockVRF.fulfillRandomWords(realReqId, randomWord);

    // Stale request ID -- should silently return, not revert
    mockVRF.fulfillRandomWordsRaw(realReqId + 999, address(game), randomWord);

    // Duplicate fulfillment -- should silently return
    mockVRF.fulfillRandomWordsRaw(realReqId, address(game), randomWord);
}
```

### Test Pattern: Retry Does Not Double-Increment lootboxRngIndex
```solidity
// Source: Verified from contracts/modules/DegenerusGameAdvanceModule.sol lines 1267-1282
function test_retryNoDoubleIncrement() public {
    // Day 1: normal advance
    _completeDay(0xDEAD0001);

    // Day 2: request but don't fulfill
    vm.warp(block.timestamp + 1 days);
    game.advanceGame();
    uint48 indexAfterRequest = game.lootboxRngIndexView();

    // Wait 12+ hours for timeout
    vm.warp(block.timestamp + 13 hours);

    // Retry: should NOT increment lootboxRngIndex
    game.advanceGame();
    assertEq(game.lootboxRngIndexView(), indexAfterRequest, "Index should not change on retry");
}
```

### Test Pattern: rngLockedFlag Mutual Exclusion
```solidity
// Source: Verified from contracts/modules/DegenerusGameAdvanceModule.sol lines 680, 1287
function test_midDayBlockedDuringDaily() public {
    // Trigger daily RNG request
    vm.warp(block.timestamp + 1 days);
    game.advanceGame();
    assertTrue(game.rngLocked(), "Daily RNG should lock");

    // Mid-day request should revert
    vm.expectRevert();  // RngLocked
    game.requestLootboxRng();
}
```

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge) with Solidity 0.8.34 |
| Config file | foundry.toml |
| Quick run command | `forge test --match-path test/fuzz/VRFCore.t.sol -vvv` |
| Full suite command | `forge test --fuzz-runs 1000 -vvv` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| VRFC-01 | rawFulfillRandomWords never reverts (except bad sender); 300k gas sufficient | fuzz + gas | `forge test --match-test test_callbackNeverReverts --gas-report -vvv` | Wave 0 |
| VRFC-02 | vrfRequestId set/clear/match lifecycle; retry detection correct | fuzz | `forge test --match-test test_vrfRequestIdLifecycle -vvv` | Wave 0 |
| VRFC-03 | rngLockedFlag prevents daily/mid-day collision | unit + fuzz | `forge test --match-test test_rngLockedMutualExclusion -vvv` | Wave 0 |
| VRFC-04 | 12h timeout retry without lootboxRngIndex corruption | fuzz | `forge test --match-test test_timeoutRetry -vvv` | Wave 0 |

### Sampling Rate
- **Per task commit:** `forge test --match-path test/fuzz/VRFCore.t.sol -vvv`
- **Per wave merge:** `forge test --fuzz-runs 1000 -vvv`
- **Phase gate:** Full suite green before verify

### Wave 0 Gaps
- [ ] `test/fuzz/VRFCore.t.sol` -- new file covering VRFC-01 through VRFC-04
- [ ] No new framework install needed (Foundry already configured)
- [ ] No new helpers needed (VRFHandler + DeployProtocol already exist)

## Open Questions

1. **Slot 0 packed write atomicity**
   - What we know: rngLockedFlag, rngRequestTime, dailyIdx share Slot 0. Solidity handles individual field writes correctly.
   - What's unclear: Are there any assembly blocks in Storage or modules that write raw Slot 0?
   - Recommendation: Grep for `assembly` blocks accessing slot 0; if none, mark as SAFE.

2. **requestLootboxRng + rngGate interaction on same day**
   - What we know: requestLootboxRng sets rngRequestTime; if mid-day VRF fulfills, it clears rngRequestTime. So rngGate sees rngRequestTime == 0 and requests fresh daily RNG.
   - What's unclear: Is there a race where rngGate runs before mid-day VRF fulfills on the same day? It would see rngRequestTime != 0 and enter the "waiting" path, reverting with RngNotReady.
   - Recommendation: This is correct behavior (wait for VRF). But verify via test that after mid-day fulfillment, advanceGame proceeds normally.

3. **MockVRFCoordinator fulfillRandomWords reverts on callback failure**
   - What we know: The mock's `fulfillRandomWords` has `require(ok, "VRF callback failed")` -- it reverts if the callback reverts.
   - What's unclear: Real Chainlink coordinator may handle callback failure differently (not propagating revert).
   - Recommendation: For testing revert-safety, use `fulfillRandomWordsRaw` which also reverts. For testing gas limits, use `forge test --gas-report`.

## Sources

### Primary (HIGH confidence)
- contracts/modules/DegenerusGameAdvanceModule.sol lines 675-1423 -- All VRF logic (request, callback, retry, lootbox)
- contracts/DegenerusGame.sol lines 2001-2015 -- rawFulfillRandomWords delegatecall proxy
- contracts/storage/DegenerusGameStorage.sol -- Complete state variable inventory with slot layout
- contracts/interfaces/IVRFCoordinator.sol -- VRF V2.5 interface used by the protocol
- audit/gas-ceiling-analysis.md -- Prior gas analysis methodology (EVM opcode costs)
- audit/v3.6-findings-consolidated.md -- Recent VRF stall resilience audit findings (0 HIGH/MEDIUM/LOW)

### Secondary (MEDIUM confidence)
- [Chainlink VRF V2.5 Getting Started](https://docs.chain.link/vrf/v2-5/getting-started) -- callbackGasLimit semantics
- [Chainlink VRF V2.5 Billing](https://docs.chain.link/vrf/v2-5/billing) -- Gas overhead is separate from callback gas budget
- [Chainlink VRF Best Practices](https://docs.chain.link/vrf/v2/best-practices) -- Callback should not revert; coordinator overhead not charged to callback

### Tertiary (LOW confidence)
- None. All findings verified against source code.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All infrastructure already exists in repo
- Architecture: HIGH - Complete code read of all VRF paths, state variables inventoried from storage layout
- Gas analysis: HIGH - Opcode-level cost enumeration using established EVM gas costs from prior audit methodology
- Pitfalls: HIGH - Derived from actual code paths and prior v3.6 audit findings

**Research date:** 2026-03-22
**Valid until:** Indefinite (auditing fixed codebase, not evolving API)
