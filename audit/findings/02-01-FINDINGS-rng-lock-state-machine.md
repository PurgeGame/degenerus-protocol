# 02-01 Findings: rngLockedFlag State Machine Audit

**Audit date:** 2026-02-28
**Auditor:** Static analysis (source-level trace)
**Scope:** All `rngLockedFlag` references in `contracts/` (excluding `contracts-testnet/`)
**Total references found:** 22 (across 6 files)

---

## 1. Complete State Machine Trace

### 1.1 Storage Definition

| File | Line | Declaration |
|------|------|-------------|
| `contracts/storage/DegenerusGameStorage.sol` | 230 | `bool internal rngLockedFlag;` |
| `contracts/storage/DegenerusGameStorage.sol` | 56 | Slot map comment: `[5:6] rngLockedFlag bool Daily RNG lock (jackpot window)` |
| `contracts/storage/DegenerusGameStorage.sol` | 177 | Comment on `rngRequestTime`: "Note: rngLockedFlag (separate bool) controls the daily RNG lock state." |

**Storage location:** Slot 1, byte offset [5:6] (packed with other bool flags and counters in the second slot).

> **POST-AUDIT UPDATE (storage location and line numbers):** The original finding stated "Slot 0, byte offset 6" and declaration at line 241. Per the actual storage layout in DegenerusGameStorage.sol, `rngLockedFlag` is in **Slot 1** at byte offset [5:6], and the declaration is at **line 230**. The slot map comment is at line 56, not 57. These are corrected above.

### 1.2 SET Sites (1 location)

| # | File | Line | Function | Statement |
|---|------|------|----------|-----------|
| S1 | `contracts/modules/DegenerusGameAdvanceModule.sol` | 1085 | `_finalizeRngRequest()` | `rngLockedFlag = true;` |

**Call chains to S1:**

1. **Daily RNG path:**
   `advanceGame()` -> `rngGate()` -> `_requestRng()` -> `_finalizeRngRequest()` -> **rngLockedFlag = true**

2. **Daily RNG retry path (18h timeout):**
   `advanceGame()` -> `rngGate()` [elapsed >= 18h] -> `_requestRng()` -> `_finalizeRngRequest()` -> **rngLockedFlag = true**

3. **Stale VRF word path (request from previous day):**
   `advanceGame()` -> `rngGate()` [requestDay < day] -> `_requestRng()` -> `_finalizeRngRequest()` -> **rngLockedFlag = true**

4. **Gameover RNG path:**
   `advanceGame()` -> `_handleGameOverPath()` -> `_gameOverEntropy()` -> `_tryRequestRng()` -> `_finalizeRngRequest()` -> **rngLockedFlag = true**

**Critical ordering in `_requestRng()` (lines 1013-1026):**
```
Step 1: vrfCoordinator.requestRandomWords(...)  [line 1015]  -- VRF request submitted
Step 2: _finalizeRngRequest(...)                 [line 1025]  -- rngLockedFlag = true
```
The VRF request is submitted BEFORE the lock flag is set. See Section 2 for exploitability analysis.

**`requestLootboxRng()` bypass (lines 579-629):**
This function calls `vrfCoordinator.requestRandomWords()` (line 614) and sets `rngRequestTime` (line 628) but does NOT call `_finalizeRngRequest()` and does NOT set `rngLockedFlag`. This is intentional -- mid-day lootbox RNG should not lock the daily game flow.

### 1.3 CLEAR Sites (2 locations)

| # | File | Line | Function | Statement |
|---|------|------|----------|-----------|
| C1 | `contracts/modules/DegenerusGameAdvanceModule.sol` | 1160 | `_unlockRng()` | `rngLockedFlag = false;` |
| C2 | `contracts/modules/DegenerusGameAdvanceModule.sol` | 1148 | `updateVrfCoordinatorAndSub()` | `rngLockedFlag = false;` |

**Call chains to C1 (`_unlockRng`):**

1. **Purchase phase daily jackpot complete:**
   `advanceGame()` -> [purchase phase, pre-target] -> `_unlockRng(day)` [line 199]

2. **Jackpot phase daily complete (non-final day):**
   `advanceGame()` -> [jackpot phase, jackpotCounter < 5] -> `_unlockRng(day)` [line 276]

3. **Phase transition complete:**
   `advanceGame()` -> [phaseTransitionActive] -> `_processPhaseTransition()` -> `_unlockRng(day)` [line 158]

4. **Gameover RNG acquired:**
   `advanceGame()` -> `_handleGameOverPath()` -> `_gameOverEntropy()` returns word -> `_unlockRng(day)` [line 354]

**`_unlockRng()` resets all VRF state (lines 1158-1164):**
```solidity
function _unlockRng(uint48 day) private {
    dailyIdx = day;
    rngLockedFlag = false;     // Clear lock
    rngWordCurrent = 0;        // Clear word
    vrfRequestId = 0;          // Clear request ID
    rngRequestTime = 0;        // Clear request time
}
```

**Call chain to C2 (`updateVrfCoordinatorAndSub`):**

`DegenerusAdmin.updateVrfCoordinatorAndSub()` -> `DegenerusGame.updateVrfCoordinatorAndSub()` [delegatecall] -> `DegenerusGameAdvanceModule.updateVrfCoordinatorAndSub()` -> **rngLockedFlag = false**

**Preconditions for C2:**
- `msg.sender == ContractAddresses.ADMIN` (line 1138) -- ADMIN contract only
- `_threeDayRngGap(_simulatedDayIndex())` must return true (line 1139) -- 3 consecutive days with no recorded VRF word

**C2 resets all VRF state (lines 1143-1152):**
```solidity
vrfCoordinator = IVRFCoordinator(newCoordinator);
vrfSubscriptionId = newSubId;
vrfKeyHash = newKeyHash;
rngLockedFlag = false;
vrfRequestId = 0;
rngRequestTime = 0;
rngWordCurrent = 0;
```

### 1.4 CHECK Sites (15 unique code locations across 5 contracts)

The research predicted 13 check sites. The actual count is **15 unique code references** (3 storage/comment, 1 set, 2 clear, 15 check/read = 21 functional + 1 comment-only = 22 total). The research's "13 check sites" counted only the user-facing function-level gates, not the branch and view reads. Below is the complete categorization.

#### 1.4.1 Guard Checks (block when locked)

| # | File | Line | Function | Check | Revert | Purpose |
|---|------|------|----------|-------|--------|---------|
| G1 | `AdvanceModule.sol` | 588 | `requestLootboxRng()` | `if (rngLockedFlag) revert E()` | `E()` | Blocks mid-day lootbox RNG requests during daily lock |
| G2 | `AdvanceModule.sol` | 1172 | `reverseFlip()` | `if (rngLockedFlag) revert RngLocked()` | `RngLocked` | Blocks nudges during VRF wait |
| G3 | `MintModule.sol` | 607 | `_purchaseFor()` | `if (lootBoxAmount != 0 && rngLockedFlag && lastPurchaseDay && (purchaseLevel % 5 == 0)) revert E()` | `E()` | Blocks lootbox purchases during BAF/Decimator resolution at jackpot levels only |
| G4 | `MintModule.sol` | 802 | `_callTicketPurchase()` | `if (rngLockedFlag) revert E()` | `E()` | Blocks all ticket-only purchases during lock |
| G5 | `LootboxModule.sol` | 545 | `openLootBox()` | `if (rngLockedFlag) revert RngLocked()` | `RngLocked` | Blocks ETH lootbox opens during lock |
| G6 | `LootboxModule.sol` | 622 | `openBurnieLootBox()` | `if (rngLockedFlag) revert RngLocked()` | `RngLocked` | Blocks BURNIE lootbox opens during lock |
| G7 | `DegenerusGame.sol` | 1549 | `setDecimatorAutoRebuy()` | `if (rngLockedFlag) revert RngLocked()` | `RngLocked` | Blocks decimator auto-rebuy config changes during lock |
| G8 | `DegenerusGame.sol` | 1570 | `_setAutoRebuy()` | `if (rngLockedFlag) revert RngLocked()` | `RngLocked` | Blocks auto-rebuy config changes during lock |
| G9 | `DegenerusGame.sol` | 1585 | `_setAutoRebuyTakeProfit()` | `if (rngLockedFlag) revert RngLocked()` | `RngLocked` | Blocks take-profit config changes during lock |
| G10 | `DegenerusGame.sol` | 1650 | `_setAfKingMode()` | `if (rngLockedFlag) revert RngLocked()` | `RngLocked` | Blocks AfKing mode config changes during lock |

#### 1.4.2 Branch/Read Uses (non-guard)

| # | File | Line | Function | Usage | Purpose |
|---|------|------|----------|-------|---------|
| B1 | `AdvanceModule.sol` | 123 | `advanceGame()` | `purchaseLevel = (lastPurchase && rngLockedFlag) ? lvl : lvl + 1` | Adjusts purchase level when lock is active during lastPurchaseDay (level already incremented in `_finalizeRngRequest`) |
| B2 | `AdvanceModule.sol` | 1209 | `rawFulfillRandomWords()` | `if (rngLockedFlag) { rngWordCurrent = word; } else { ... }` | Routes VRF callback: daily path (locked) stores word; mid-day path (unlocked) finalizes lootbox directly |
| B3 | `DegeneretteModule.sol` | 504 | `_placeBet()` | `jackpotResolutionActive = rngLockedFlag && lastPurchaseDay && ((level + 1) % 5 == 0)` | Detects if jackpot resolution is active; ETH bets blocked when `jackpotResolutionActive == true` |

#### 1.4.3 View Functions (read-only)

| # | File | Line | Function | Usage | Purpose |
|---|------|------|----------|-------|---------|
| V1 | `DegenerusGame.sol` | 2213 | `rngLocked()` | `return rngLockedFlag` | Public view: exposes lock state |
| V2 | `DegenerusGame.sol` | 2255 | `decWindow()` | `on = (decWindowOpen \|\| _isGameoverImminent()) && !(lastPurchaseDay && rngLockedFlag)` | View: decimator window availability |
| V3 | `DegenerusGame.sol` | 2315 | `purchaseInfo()` | `rngLocked_ = rngLockedFlag` | View: returns lock state as part of purchase info struct |

### 1.5 rngRequestTime Dual-State Relationship

`rngRequestTime` serves as a separate but related lock mechanism. It tracks VRF request lifecycle timing.

**SET sites for rngRequestTime:**

| File | Line | Function | Context |
|------|------|----------|---------|
| `AdvanceModule.sol` | 1084 | `_finalizeRngRequest()` | `rngRequestTime = uint48(block.timestamp)` -- daily VRF request |
| `AdvanceModule.sol` | 628 | `requestLootboxRng()` | `rngRequestTime = uint48(block.timestamp)` -- lootbox VRF request |
| `AdvanceModule.sol` | 737 | `_gameOverEntropy()` | `rngRequestTime = ts` -- gameover VRF fallback timer start |

**CLEAR sites for rngRequestTime:**

| File | Line | Function | Context |
|------|------|----------|---------|
| `AdvanceModule.sol` | 1163 | `_unlockRng()` | `rngRequestTime = 0` -- daily processing complete |
| `AdvanceModule.sol` | 1150 | `updateVrfCoordinatorAndSub()` | `rngRequestTime = 0` -- emergency reset |
| `AdvanceModule.sol` | 1218 | `rawFulfillRandomWords()` | `rngRequestTime = 0` -- mid-day lootbox fulfillment (only when `rngLockedFlag == false`) |

**Intentional divergence path (rngRequestTime != 0, rngLockedFlag == false):**

After `requestLootboxRng()` executes:
- `rngRequestTime` = current timestamp (line 628)
- `rngLockedFlag` = false (not modified)

This is the lootbox mid-day VRF path. The dual-state allows:
1. `rngLockedFlag` gates user operations (nudges, purchases, config changes)
2. `rngRequestTime != 0` gates VRF lifecycle transitions (blocks concurrent requests in `requestLootboxRng` at line 589, and drives timeout logic in `rngGate` at line 665)

**CHECK sites for rngRequestTime (selected security-relevant):**

| File | Line | Function | Check |
|------|------|----------|-------|
| `AdvanceModule.sol` | 589 | `requestLootboxRng()` | `if (rngRequestTime != 0) revert E()` -- blocks concurrent lootbox requests |
| `AdvanceModule.sol` | 643 | `rngGate()` | `if (currentWord != 0 && rngRequestTime != 0)` -- word ready, process it |
| `AdvanceModule.sol` | 665 | `rngGate()` | `if (rngRequestTime != 0)` -- waiting for VRF, check timeout |
| `AdvanceModule.sol` | 1063-1064 | `_finalizeRngRequest()` | `prevRequestId != 0 && rngRequestTime != 0 && rngWordCurrent == 0` -- retry detection |

---

## 2. Nudge Window Timing Analysis (RNG-01)

### 2.1 Request Phase: VRF Request -> Lock Set Ordering

In `_requestRng()` (AdvanceModule lines 1013-1026):

```
Step 1: id = vrfCoordinator.requestRandomWords(...)  [line 1015-1024]
Step 2: _finalizeRngRequest(..., id)                  [line 1025]
  Step 2a: rngLockedFlag = true                       [line 1085]
```

**There IS a window within a single transaction where the VRF request has been submitted but `rngLockedFlag` is still `false`.** However, this window exists ONLY within the execution of `_requestRng()` -- a private function called from `advanceGame()` or `_gameOverEntropy()`. No external call or callback can interrupt this sequence within the same transaction.

**Chainlink VRF V2.5 fulfills asynchronously in a separate transaction** (after `VRF_REQUEST_CONFIRMATIONS` = 10 blocks for daily, or 3 blocks for lootbox). The VRF coordinator cannot deliver the random word in the same transaction as the request.

**Verdict: The intra-transaction window between VRF request and lock set is NOT exploitable.** By the time the VRF callback arrives (10+ blocks later), `rngLockedFlag` has been `true` for at least 10 blocks.

### 2.2 Fulfillment Phase: VRF Word Storage

In `rawFulfillRandomWords()` (AdvanceModule lines 1199-1220):

```
Step 1: Coordinator check: msg.sender == vrfCoordinator   [line 1203]
Step 2: Request ID match: requestId == vrfRequestId        [line 1204]
Step 3: Word != 0 guard: word = (word == 0) ? 1 : word    [line 1207]
Step 4: Branch on rngLockedFlag:
  If TRUE  (daily):   rngWordCurrent = word                [line 1211]
  If FALSE (lootbox): finalize lootbox directly            [lines 1214-1218]
```

When `rngLockedFlag == true` (daily path), the word is stored in `rngWordCurrent` but NOT immediately consumed. Consumption happens in the NEXT `advanceGame()` call.

### 2.3 Consumption Phase: Word Application

In `rngGate()` -> `_applyDailyRng()` (AdvanceModule lines 1222-1238):

```
Step 1: nudges = totalFlipReversals                        [line 1227]
Step 2: finalWord = rawWord + nudges (unchecked)           [line 1231]
Step 3: totalFlipReversals = 0                             [line 1233]
Step 4: rngWordCurrent = finalWord                         [line 1235]
Step 5: rngWordByDay[day] = finalWord                      [line 1236]
```

After `_applyDailyRng()`, `_unlockRng()` is called (lines 158, 199, 276, 354), which clears `rngLockedFlag`.

### 2.4 Nudge Accumulation Window

Nudges (`reverseFlip()`) can only accumulate when `rngLockedFlag == false` (G2, line 1172).

**Timeline:**

```
Day N processing:
  _applyDailyRng() -- applies accumulated nudges to Day N's word
  ...game logic...
  _unlockRng(dayN) -- rngLockedFlag = false
                      ^--- NUDGE WINDOW OPENS ---
                      Players can call reverseFlip()
                      Nudges accumulate in totalFlipReversals

Day N+1 advanceGame() called:
  rngGate() -> _requestRng() -> _finalizeRngRequest()
    rngLockedFlag = true
                      ^--- NUDGE WINDOW CLOSES ---
                      All accumulated nudges will be applied to Day N+1's VRF word
  ...VRF fulfillment (10+ blocks later)...

Day N+1 second advanceGame() called (after VRF fulfilled):
  rngGate() detects rngWordCurrent != 0
  _applyDailyRng() applies nudges: finalWord = vrfWord + totalFlipReversals
```

**Key property:** Nudges are accumulated BEFORE the VRF word is known (between `_unlockRng` of Day N and `_requestRng` of Day N+1). The VRF word arrives AFTER the nudge window closes. Players cannot see the VRF word and then nudge.

### 2.5 Lock Continuity Verification

The lock is **continuously set** from VRF request through word consumption:

```
_requestRng():        rngLockedFlag = true    [line 1085]
  ...10+ blocks pass...
rawFulfillRandomWords(): rngWordCurrent = word [line 1211]
  ...next advanceGame() call...
_applyDailyRng():     finalWord applied        [line 1236]
  ...game logic...
_unlockRng():         rngLockedFlag = false    [line 1160]
```

**No gap exists.** The flag remains `true` from `_finalizeRngRequest` until `_unlockRng` -- a span that covers VRF request, VRF fulfillment, word application, and all game logic processing.

---

## 3. Block Proposer Attack Surface (RNG-08)

### 3.1 Attack Scenario: Front-running VRF Fulfillment with Nudges

**Attacker model:** A block proposer/validator who sees the VRF fulfillment transaction in their mempool before including it in a block.

**Attack attempt:**
1. Proposer sees `rawFulfillRandomWords(requestId, [word])` in mempool
2. Proposer extracts the random word from the calldata
3. Proposer wants to call `reverseFlip()` before the fulfillment to influence the outcome

**Why it fails:**
- At the time the VRF fulfillment arrives, `rngLockedFlag == true` (set 10+ blocks ago when the VRF request was made)
- `reverseFlip()` checks `if (rngLockedFlag) revert RngLocked()` (G2, line 1172)
- The proposer CANNOT call `reverseFlip()` -- the transaction would revert
- The proposer also cannot reorder to place a `reverseFlip()` BEFORE the fulfillment because the lock was set in a completely separate, earlier block

### 3.2 Attack Scenario: Reordering Transactions Around Fulfillment

**Attack attempt:** Reorder the fulfillment relative to an `advanceGame()` call.

**Why it fails:**
- `rawFulfillRandomWords()` only stores the word in `rngWordCurrent` (line 1211)
- The word is not consumed until the NEXT `advanceGame()` call processes `rngGate()` -> `_applyDailyRng()`
- Reordering the fulfillment relative to other transactions in the same block has no effect because `advanceGame()` reads `rngWordCurrent` from storage, not from the mempool
- Even if the proposer delays including the fulfillment, the 18h timeout mechanism (line 667) will trigger a re-request

### 3.3 Attack Scenario: Delaying VRF Fulfillment

**Attack attempt:** A proposer who is also a Chainlink node operator withholds the fulfillment transaction.

**Impact:** The game is delayed, not manipulated. After 18 hours (line 667), the next `advanceGame()` call will re-request VRF. The proposer gains no advantage -- they can delay the game but cannot influence the outcome.

### 3.4 Attack Scenario: Manipulating advanceGame Timing

**Attack attempt:** A proposer calls `advanceGame()` immediately after `_unlockRng()` and before other players can nudge.

**Analysis:** This affects FUTURE days, not the current day. The proposer could reduce the nudge window for the next day's word, but nudges are additive to a VRF word that is not yet known. Calling `advanceGame()` early just means fewer nudges accumulate -- which has no strategic value since the VRF word is unpredictable.

---

## 4. Stuck-State Recovery Analysis (RNG-06)

### 4.1 Recovery Path 1: 18-Hour VRF Retry

**Trigger:** VRF coordinator fails to fulfill within 18 hours.

**Mechanism (rngGate, lines 665-671):**
```solidity
if (rngRequestTime != 0) {
    uint48 elapsed = ts - rngRequestTime;
    if (elapsed >= 18 hours) {
        _requestRng(isTicketJackpotDay, lvl);  // Re-request VRF
        return 1;
    }
    revert RngNotReady();
}
```

**Behavior:** The retry calls `_requestRng()` which calls `_finalizeRngRequest()`. The `_finalizeRngRequest` function detects the retry via the `isRetry` check (lines 1062-1065):
```solidity
bool isRetry = prevRequestId != 0 &&
    rngRequestTime != 0 &&
    rngWordCurrent == 0;
```
On retry, it remaps the lootbox RNG index from the old request ID to the new one (lines 1068-1075) and does NOT double-increment the level.

**Premature trigger resistance:** The `elapsed >= 18 hours` check (line 667) prevents premature retries. Anyone calling `advanceGame()` before 18 hours will hit `revert RngNotReady()`.

**Lock state during retry:** `rngLockedFlag` remains `true` throughout the retry process. The retry calls `_requestRng()` -> `_finalizeRngRequest()` which writes `rngLockedFlag = true` again (no-op since it's already true). The lock is never cleared until daily processing completes.

### 4.2 Recovery Path 2: 3-Day Emergency Coordinator Rotation

**Trigger:** VRF coordinator has completely failed for 3+ consecutive days.

**Mechanism (updateVrfCoordinatorAndSub, lines 1133-1153):**

**Preconditions:**
1. `msg.sender == ContractAddresses.ADMIN` (line 1138)
2. `_threeDayRngGap(_simulatedDayIndex())` returns true (line 1139)

**`_threeDayRngGap` logic (lines 1258-1263):**
```solidity
function _threeDayRngGap(uint48 day) private view returns (bool) {
    if (rngWordByDay[day] != 0) return false;       // Today has word: no gap
    if (rngWordByDay[day - 1] != 0) return false;   // Yesterday has word: no gap
    if (day < 2 || rngWordByDay[day - 2] != 0) return false; // Day before has word: no gap
    return true;                                     // 3 days with no word
}
```

**Premature trigger resistance:** Requires 3 full days without any RNG word recorded. The `day < 2` guard prevents underflow on the first 2 days. This function is duplicated identically in both `DegenerusGame.sol` (line 2226) and `DegenerusGameAdvanceModule.sol` (line 1258) -- the copies are consistent.

**Effect:** Resets ALL VRF state including `rngLockedFlag`, installs new coordinator, subscription, and key hash. The game can immediately request new VRF from the replacement coordinator.

### 4.3 Recovery Path 3: Gameover VRF Fallback

**Trigger:** VRF stalls during gameover processing.

**Mechanism (_gameOverEntropy, lines 686-738):**
- If `rngRequestTime != 0` and `elapsed >= GAMEOVER_RNG_FALLBACK_DELAY` (3 days): uses historical VRF word as fallback
- `_getHistoricalRngFallback(day)` searches backwards from day 1 up to 30 days for any recorded VRF word (lines 742-762)
- The historical word is mixed with `currentDay` via `keccak256(abi.encodePacked(word, currentDay))` for uniqueness
- If NO historical words exist (VRF never worked): `revert E()` -- catastrophic, game never had a successful VRF cycle

**Note:** This path calls `_applyDailyRng()` which records the fallback word in `rngWordByDay[day]`, then the caller (`_handleGameOverPath`) calls `_unlockRng(day)` to clear the lock.

### 4.4 Permanent Lock Analysis

**Can `rngLockedFlag` become permanently `true` with no recovery?**

The only way to set `rngLockedFlag = true` is via `_finalizeRngRequest()` (S1). Once set, it is cleared by either:
- `_unlockRng()` (C1) -- requires successful VRF word processing
- `updateVrfCoordinatorAndSub()` (C2) -- emergency, requires 3-day gap + ADMIN

**Scenario analysis:**

| Scenario | Lock set? | Recovery | Permanent? |
|----------|-----------|----------|------------|
| VRF fulfilled normally | Yes | `_unlockRng` after game logic | No |
| VRF not fulfilled within 18h | Yes | Re-request via `rngGate` timeout | No |
| VRF not fulfilled for 3+ days | Yes | `updateVrfCoordinatorAndSub` | No |
| VRF stall during gameover | Yes | Historical word fallback after 3 days | No |
| Chainlink permanently dead + ADMIN lost | Yes | No recovery | **Yes -- but requires ADMIN key loss + Chainlink permanent failure** |

The last scenario is catastrophic but requires two independent failures (Chainlink completely ceasing operations AND the ADMIN key being irrecoverably lost). This is an acceptable residual risk for any VRF-dependent protocol.

---

## 5. Requirement Verdicts

### RNG-01: rngLockedFlag Continuity

**Requirement:** `rngLockedFlag` remains set continuously from VRF request through word consumption in `advanceGame` -- no window exists for nudge manipulation.

**Verdict: PASS**

**Evidence:**
- `rngLockedFlag` is set to `true` in `_finalizeRngRequest()` (line 1085), called immediately after `vrfCoordinator.requestRandomWords()` within the same transaction (lines 1015, 1025)
- The intra-transaction gap between VRF request and lock set is not exploitable because VRF fulfills asynchronously (10+ blocks later for daily, 3+ blocks for lootbox)
- `rngLockedFlag` remains `true` through VRF fulfillment (`rawFulfillRandomWords` does not clear it -- line 1209-1211)
- `rngLockedFlag` remains `true` through word application in `_applyDailyRng()` (lines 1222-1238)
- `rngLockedFlag` is cleared only after all game logic completes, in `_unlockRng()` (line 1160)
- `reverseFlip()` is blocked by `rngLockedFlag` check (line 1172) for the entire duration from request through consumption
- The 18h retry path does NOT clear the lock -- it re-calls `_requestRng()` -> `_finalizeRngRequest()` which writes `true` again

**Lock timeline:**
```
[UNLOCKED] _unlockRng(dayN) clears flag
  --- nudge window open (players can call reverseFlip) ---
[LOCKED]   _finalizeRngRequest() sets flag       <-- request made
  --- nudges blocked (reverseFlip reverts) ---
           rawFulfillRandomWords() stores word   <-- 10+ blocks later
  --- nudges still blocked ---
           _applyDailyRng() applies nudges       <-- next advanceGame
  --- nudges still blocked ---
           game logic processes
[UNLOCKED] _unlockRng(dayN+1) clears flag
```

### RNG-06: Stuck-State Recoverability

**Requirement:** RNG lock cannot be bypassed or stuck permanently -- all stuck states are recoverable via stall recovery.

**Verdict: PASS**

**Evidence:**
- **18h timeout:** `rngGate()` (line 667) re-requests VRF after 18 hours of no fulfillment. Any user can trigger this by calling `advanceGame()`.
- **3-day emergency rotation:** `updateVrfCoordinatorAndSub()` (line 1133) allows ADMIN to install a new VRF coordinator after 3 consecutive days without an RNG word. This clears `rngLockedFlag` (line 1148).
- **Gameover fallback:** `_gameOverEntropy()` (line 714) falls back to historical VRF words after 3 days, allowing gameover to proceed even without a functioning VRF coordinator.
- **No permanent lock scenario exists** under normal operational assumptions (ADMIN key retained, at least one functional VRF coordinator available).
- **`_threeDayRngGap` underflow guard** is present and consistent in both copies (AdvanceModule line 1261, DegenerusGame line 2229): `day < 2` check prevents underflow.

### RNG-08: Block Proposer reverseFlip Exploitation

**Requirement:** `reverseFlip()` nudge mechanism cannot be exploited by a block proposer who sees the fulfilled VRF word in mempool.

**Verdict: PASS**

**Evidence:**
- At VRF fulfillment time, `rngLockedFlag` has been `true` for 10+ blocks (set during `_requestRng()` in a previous block)
- `reverseFlip()` checks `if (rngLockedFlag) revert RngLocked()` (line 1172) -- the proposer cannot nudge
- The proposer cannot reorder transactions to place a `reverseFlip()` before the fulfillment because the lock was set in a completely separate, earlier block
- Even if the proposer delays the fulfillment, the 18h timeout triggers a re-request -- no advantage gained
- Nudges accumulated before the lock was set affect the NEXT day's word, and at that time the VRF word was not yet known -- no foreknowledge possible

---

## 6. Findings

### F1: Misleading Storage Comment on rngRequestTime (Informational)

> **POST-AUDIT UPDATE:** This finding has been resolved. The comment on `rngRequestTime` (now at line 177) was corrected post-audit. It now reads: "Note: rngLockedFlag (separate bool) controls the daily RNG lock state." The misleading "replaces deprecated rngLockedFlag" wording has been removed.

**Location:** `contracts/storage/DegenerusGameStorage.sol`, line 178
**Comment:** "Also serves as the RNG lock flag (replaces deprecated rngLockedFlag)."
**Issue:** `rngLockedFlag` is NOT deprecated -- it is actively used in 15 code locations across 5 contracts. Both `rngLockedFlag` and `rngRequestTime` coexist with distinct purposes.
**Impact:** Could mislead future developers or auditors into thinking `rngLockedFlag` is unused, potentially leading to removal or misunderstanding of the dual-lock design.
**Severity:** Informational
**Recommendation:** Update the comment to reflect the actual dual-purpose design: `rngRequestTime` tracks VRF lifecycle timing, while `rngLockedFlag` gates user-facing operations. Neither replaces the other.

### F2: Intra-Transaction VRF Request Before Lock Set (Informational)

**Location:** `contracts/modules/DegenerusGameAdvanceModule.sol`, lines 1015 and 1025
**Issue:** In `_requestRng()`, `vrfCoordinator.requestRandomWords()` is called BEFORE `_finalizeRngRequest()` sets `rngLockedFlag = true`. If a hypothetical synchronous VRF fulfillment occurred (not possible with Chainlink VRF V2.5), the callback would see `rngLockedFlag == false` and route the word to the lootbox path instead of the daily path.
**Impact:** None in practice. Chainlink VRF V2.5 fulfills asynchronously across separate transactions (after 10 block confirmations for daily requests). The theoretical ordering issue cannot be triggered.
**Severity:** Informational
**Recommendation:** Consider swapping the order (set lock before request) for defense-in-depth, though the current design is safe with Chainlink VRF V2.5. Note that `_tryRequestRng()` has the same ordering via try/catch (lines 1040-1054).

### F3: Conditional Lootbox Purchase Gate at Jackpot Levels (Note)

**Location:** `contracts/modules/DegenerusGameMintModule.sol`, line 607
**Check:** `if (lootBoxAmount != 0 && rngLockedFlag && lastPurchaseDay && (purchaseLevel % 5 == 0)) revert E()`
**Observation:** Unlike G4 (`_callTicketPurchase` which blocks ALL ticket purchases when locked), this gate only blocks lootbox-bearing purchases during specific conditions (lock active AND last purchase day AND jackpot resolution level). This means regular ticket+lootbox purchases are allowed when locked on non-jackpot-resolution days.
**Impact:** This is intentional design -- lootbox purchases should be available during most of the locked period. The conditional gate prevents interference specifically with BAF/Decimator resolution mechanics at jackpot levels.
**Severity:** Note (no action needed; documenting intentional design asymmetry)

---

## 7. Reference: Complete rngLockedFlag Site Index

| # | Category | File | Line | Function |
|---|----------|------|------|----------|
| 1 | DEFINE | `DegenerusGameStorage.sol` | 230 | Variable declaration |
| 2 | COMMENT | `DegenerusGameStorage.sol` | 56 | Slot map documentation |
| 3 | COMMENT | `DegenerusGameStorage.sol` | 177 | Comment on rngRequestTime (corrected post-audit) |
| 4 | SET | `AdvanceModule.sol` | 1085 | `_finalizeRngRequest()` |
| 5 | CLEAR | `AdvanceModule.sol` | 1148 | `updateVrfCoordinatorAndSub()` |
| 6 | CLEAR | `AdvanceModule.sol` | 1160 | `_unlockRng()` |
| 7 | GUARD | `AdvanceModule.sol` | 588 | `requestLootboxRng()` |
| 8 | GUARD | `AdvanceModule.sol` | 1172 | `reverseFlip()` |
| 9 | GUARD | `MintModule.sol` | 607 | `_purchaseFor()` |
| 10 | GUARD | `MintModule.sol` | 802 | `_callTicketPurchase()` |
| 11 | GUARD | `LootboxModule.sol` | 545 | `openLootBox()` |
| 12 | GUARD | `LootboxModule.sol` | 622 | `openBurnieLootBox()` |
| 13 | GUARD | `DegenerusGame.sol` | 1549 | `setDecimatorAutoRebuy()` |
| 14 | GUARD | `DegenerusGame.sol` | 1570 | `_setAutoRebuy()` |
| 15 | GUARD | `DegenerusGame.sol` | 1585 | `_setAutoRebuyTakeProfit()` |
| 16 | GUARD | `DegenerusGame.sol` | 1650 | `_setAfKingMode()` |
| 17 | BRANCH | `AdvanceModule.sol` | 123 | `advanceGame()` |
| 18 | BRANCH | `AdvanceModule.sol` | 1209 | `rawFulfillRandomWords()` |
| 19 | READ | `DegeneretteModule.sol` | 504 | `_placeBet()` |
| 20 | VIEW | `DegenerusGame.sol` | 2213 | `rngLocked()` |
| 21 | VIEW | `DegenerusGame.sol` | 2255 | `decWindow()` |
| 22 | VIEW | `DegenerusGame.sol` | 2315 | `purchaseInfo()` |

---

*Audit scope: contracts/ (excluding contracts-testnet/)*
*Contracts audited: DegenerusGameAdvanceModule.sol, DegenerusGame.sol, DegenerusGameMintModule.sol, DegenerusGameLootboxModule.sol, DegenerusGameDegeneretteModule.sol, DegenerusGameStorage.sol*
*No contract files were modified during this audit.*
