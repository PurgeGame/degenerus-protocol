# VRF Lifecycle Trace (RNG-01)

**Audit date:** 2026-04-10
**Source:** contracts at current HEAD
**Methodology:** Forward trace from first principles per D-03 (no prior RNG audit reliance)

---

## Section 1: Daily VRF Request Path

**Trace:** `advanceGame()` -> `rngGate()` -> `_requestRng()` -> VRF coordinator

### 1.1 Entry: advanceGame()

**Contract:** DegenerusGameAdvanceModule.sol
**Function:** `advanceGame()` (line 156)

The daily processing flow enters RNG via `rngGate()` at line 266:

```solidity
// DegenerusGameAdvanceModule.sol, line 265-268
bool bonusFlip = (inJackpot && jackpotCounter == 0) || lvl == 0;
(uint256 rngWord, uint32 gapDays) = rngGate(
    ts, day, purchaseLevel, lastPurchase, bonusFlip
);
```

When `rngGate` returns `rngWord == 1`, it means a fresh VRF request was just issued. The function then calls `_swapAndFreeze(purchaseLevel)` (line 275) and breaks with `STAGE_RNG_REQUESTED` (line 276).

**State reads:** `jackpotPhaseFlag`, `jackpotCounter`, `level`, `lastPurchaseDay`, `rngLockedFlag`
**State writes:** None at this point (all mutations happen inside `rngGate`)

### 1.2 rngGate decides to request

**Contract:** DegenerusGameAdvanceModule.sol
**Function:** `rngGate()` (line 1000)

When no word is available and no request is pending, `rngGate` triggers a request at line 1067:

```solidity
// DegenerusGameAdvanceModule.sol, line 1066-1068
// Need fresh RNG
_requestRng(isTicketJackpotDay, lvl);
return (1, 0);
```

The return value `(1, 0)` signals "request sent, no gap days."

### 1.3 _requestRng: VRF coordinator call

**Contract:** DegenerusGameAdvanceModule.sol
**Function:** `_requestRng()` (line 1386)

```solidity
// DegenerusGameAdvanceModule.sol, lines 1386-1399
function _requestRng(bool isTicketJackpotDay, uint24 lvl) private {
    uint256 id = vrfCoordinator.requestRandomWords(
        VRFRandomWordsRequest({
            keyHash: vrfKeyHash,
            subId: vrfSubscriptionId,
            requestConfirmations: VRF_REQUEST_CONFIRMATIONS,
            callbackGasLimit: VRF_CALLBACK_GAS_LIMIT,
            numWords: 1,
            extraArgs: hex""
        })
    );
    _finalizeRngRequest(isTicketJackpotDay, lvl, id);
}
```

**VRF parameters (from constants, lines 108-119):**
- `VRF_REQUEST_CONFIRMATIONS = 10` (line 118) -- 10 block confirmations before fulfillment
- `VRF_CALLBACK_GAS_LIMIT = 300_000` (line 111) -- gas limit for callback execution
- `numWords = 1` -- single random word per request
- `keyHash` -- from `vrfKeyHash` (storage, DegenerusGameStorage.sol line 1293)
- `subId` -- from `vrfSubscriptionId` (storage, DegenerusGameStorage.sol line 1298)
- `extraArgs = hex""` -- empty for LINK payment (default)

**External call:** `vrfCoordinator.requestRandomWords()` -- hard reverts if Chainlink request fails (per comment at line 1387). This intentionally halts game progress until VRF funding/config is fixed.

### 1.4 _finalizeRngRequest: state mutations

**Contract:** DegenerusGameAdvanceModule.sol
**Function:** `_finalizeRngRequest()` (line 1422)

```solidity
// DegenerusGameAdvanceModule.sol, lines 1422-1471
function _finalizeRngRequest(
    bool isTicketJackpotDay, uint24 lvl, uint256 requestId
) private {
    bool isRetry = vrfRequestId != 0 &&
        rngRequestTime != 0 &&
        rngWordCurrent == 0;
    if (!isRetry) {
        _lrWrite(LR_INDEX_SHIFT, LR_INDEX_MASK, _lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK) + 1);
        _lrWrite(LR_PENDING_ETH_SHIFT, LR_PENDING_ETH_MASK, 0);
        _lrWrite(LR_PENDING_BURNIE_SHIFT, LR_PENDING_BURNIE_MASK, 0);
    }
    vrfRequestId = requestId;        // line 1439
    rngWordCurrent = 0;              // line 1440
    rngRequestTime = uint48(block.timestamp);  // line 1441
    rngLockedFlag = true;            // line 1442
    ...
}
```

**State mutations:**
| Variable | Value | Line | Purpose |
|----------|-------|------|---------|
| `vrfRequestId` | requestId from coordinator | 1439 | Match fulfillment callback |
| `rngWordCurrent` | 0 | 1440 | Signal "pending" state |
| `rngRequestTime` | block.timestamp | 1441 | Enable timeout detection |
| `rngLockedFlag` | true | 1442 | Block state-changing user actions during resolution |
| `lootboxRngIndex` (packed) | incremented +1 | 1432 | Fresh requests advance index so new purchases target next RNG |
| `lootboxRngPendingEth` (packed) | 0 | 1433 | Reset pending counters for new index |
| `lootboxRngPendingBurnie` (packed) | 0 | 1434 | Reset pending counters for new index |

**Retry handling:** If `isRetry == true` (previous request failed/timed out), the lootbox index is NOT re-incremented (lines 1430-1437). The index was already advanced by the original request.

**Level increment:** On `isTicketJackpotDay && !isRetry`, the level is set to `lvl` (which is `purchaseLevel = level + 1`), and the top affiliate is rewarded before the increment (lines 1447-1470).

**Verdict: TRACED** -- Daily VRF request path fully documented from `advanceGame()` entry through VRF coordinator external call, with all parameters, state mutations, and retry logic proven.

---

## Section 2: Daily VRF Fulfillment Path

**Trace:** VRF coordinator -> `DegenerusGame.rawFulfillRandomWords()` -> `AdvanceModule.rawFulfillRandomWords()` (delegatecall)

### 2.1 Entry: DegenerusGame.rawFulfillRandomWords()

**Contract:** DegenerusGame.sol
**Function:** `rawFulfillRandomWords()` (line 1913)

```solidity
// DegenerusGame.sol, lines 1913-1927
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

**CRITICAL OBSERVATION:** DegenerusGame.sol does NOT validate `msg.sender` before delegatecall. The caller validation happens INSIDE the AdvanceModule (see Section 2.2). Because this is a `delegatecall`, the AdvanceModule code executes with DegenerusGame's `msg.sender`, so the check is equivalent.

**Threat T-215-01 resolution:** The `msg.sender == vrfCoordinator` check at AdvanceModule line 1534 runs in DegenerusGame's context, so `msg.sender` is the actual external caller. This correctly gates the callback to the VRF coordinator only.

### 2.2 Delegatecall target: AdvanceModule.rawFulfillRandomWords()

**Contract:** DegenerusGameAdvanceModule.sol
**Function:** `rawFulfillRandomWords()` (line 1530)

```solidity
// DegenerusGameAdvanceModule.sol, lines 1530-1551
function rawFulfillRandomWords(
    uint256 requestId,
    uint256[] calldata randomWords
) external {
    if (msg.sender != address(vrfCoordinator)) revert E();   // line 1534
    if (requestId != vrfRequestId || rngWordCurrent != 0) return;  // line 1535

    uint256 word = randomWords[0];           // line 1537
    if (word == 0) word = 1;                 // line 1538

    if (rngLockedFlag) {                     // line 1540
        // Daily RNG: store for advanceGame processing
        rngWordCurrent = word;               // line 1542
    } else {                                 // line 1543
        // Mid-day RNG: directly finalize lootbox and clear state
        uint48 index = uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)) - 1;
        lootboxRngWordByIndex[index] = word;  // line 1546
        emit LootboxRngApplied(index, word, requestId);
        vrfRequestId = 0;                    // line 1548
        rngRequestTime = 0;                  // line 1549
    }
}
```

**Validation gates:**
1. `msg.sender != address(vrfCoordinator)` (line 1534) -- reverts if caller is not the VRF coordinator
2. `requestId != vrfRequestId` (line 1535) -- silently returns if request ID does not match the pending request
3. `rngWordCurrent != 0` (line 1535) -- silently returns if a word was already delivered (prevents double-write)

**Zero-word protection:** If VRF returns 0, it is replaced with 1 (line 1538). This prevents 0 from being interpreted as "no word available" in downstream checks.

**Branching logic:**
- **`rngLockedFlag == true` (daily path):** Word stored to `rngWordCurrent` only (line 1542). It is NOT yet written to `rngWordByDay[day]` -- that happens in `_applyDailyRng()` during the next `advanceGame()` call via `rngGate()`.
- **`rngLockedFlag == false` (mid-day lootbox path):** Word stored directly to `lootboxRngWordByIndex[index]` (line 1546) and VRF state cleared.

**State mutations (daily path):**
| Variable | Value | Line | Purpose |
|----------|-------|------|---------|
| `rngWordCurrent` | VRF word (or 1 if 0) | 1542 | Hold word for advanceGame processing |

**State mutations (mid-day path):**
| Variable | Value | Line | Purpose |
|----------|-------|------|---------|
| `lootboxRngWordByIndex[index]` | VRF word | 1546 | Store lootbox-specific word |
| `vrfRequestId` | 0 | 1548 | Clear pending request |
| `rngRequestTime` | 0 | 1549 | Clear timeout tracker |

**Threat T-215-02 assessment:** For the daily path, `rngWordCurrent` acts as a staging variable. The permanent write to `rngWordByDay[day]` occurs in `_applyDailyRng()` (line 1626), which is called exactly once per day via `rngGate()`. The guard `rngWordCurrent != 0` at line 1535 prevents the callback from overwriting a delivered word. Once `_applyDailyRng()` writes to `rngWordByDay[day]`, the `rngWordByDay[day] != 0` check at rngGate line 1008 prevents re-entry to the entire RNG path.

### 2.3 Word flow from fulfillment to storage

After VRF delivers the word to `rngWordCurrent`, the next `advanceGame()` call enters `rngGate()` which detects `currentWord != 0 && rngRequestTime != 0` (line 1013) and proceeds to:

```solidity
// DegenerusGameAdvanceModule.sol, lines 1031-1032
currentWord = _applyDailyRng(day, currentWord);
coinflip.processCoinflipPayouts(bonusFlip, currentWord, day);
```

`_applyDailyRng` (line 1613):

```solidity
// DegenerusGameAdvanceModule.sol, lines 1613-1629
function _applyDailyRng(uint32 day, uint256 rawWord) private returns (uint256 finalWord) {
    uint256 nudges = totalFlipReversals;
    finalWord = rawWord;
    if (nudges != 0) {
        unchecked { finalWord += nudges; }
        totalFlipReversals = 0;           // line 1623
    }
    rngWordCurrent = finalWord;           // line 1625
    rngWordByDay[day] = finalWord;        // line 1626
    lastVrfProcessedTimestamp = uint48(block.timestamp);  // line 1627
    emit DailyRngApplied(day, rawWord, nudges, finalWord);  // line 1628
}
```

**State mutations in _applyDailyRng:**
| Variable | Value | Line | Purpose |
|----------|-------|------|---------|
| `totalFlipReversals` | 0 (if was nonzero) | 1623 | Consume accumulated nudges |
| `rngWordCurrent` | finalWord (rawWord + nudges) | 1625 | Update current word with nudges applied |
| `rngWordByDay[day]` | finalWord | 1626 | Permanent daily word storage |
| `lastVrfProcessedTimestamp` | block.timestamp | 1627 | Track last successful RNG processing |

**Nudge mechanism:** `totalFlipReversals` accumulates BURNIE-purchased nudges. These are added to the raw VRF word before storage. The nudge only affects bit 0 parity (coinflip win/loss) effectively, since all other consumers use modular arithmetic or keccak mixing on the full 256-bit word.

### 2.4 RNG unlock after daily processing

After all daily processing completes (jackpots, transitions, etc.), `_unlockRng(day)` is called:

```solidity
// DegenerusGameAdvanceModule.sol, lines 1513-1520
function _unlockRng(uint32 day) private {
    dailyIdx = day;
    rngLockedFlag = false;
    rngWordCurrent = 0;
    vrfRequestId = 0;
    rngRequestTime = 0;
    _unfreezePool();
}
```

**State mutations:**
| Variable | Value | Line | Purpose |
|----------|-------|------|---------|
| `dailyIdx` | current day | 1514 | Record processed day index |
| `rngLockedFlag` | false | 1515 | Unlock state-changing actions |
| `rngWordCurrent` | 0 | 1516 | Clear consumed word |
| `vrfRequestId` | 0 | 1517 | Clear fulfilled request |
| `rngRequestTime` | 0 | 1518 | Clear request timestamp |

`_unfreezePool()` (DegenerusGameStorage.sol line 770) applies pending prize pool accumulators and clears the freeze flag.

**Verdict: TRACED** -- Daily VRF fulfillment path fully documented from VRF coordinator callback through DegenerusGame delegatecall, AdvanceModule validation, word staging, daily application with nudges, permanent storage, and unlock. Word written exactly once per day; double-write prevented by `rngWordCurrent != 0` guard on callback and `rngWordByDay[day] != 0` guard on rngGate re-entry.

---

## Section 3: rngGate -- Word Retrieval

**Trace:** `advanceGame()` -> `rngGate()` -> returns `(uint256 word, uint32 gapDays)`

**Contract:** DegenerusGameAdvanceModule.sol
**Function:** `rngGate()` (line 1000)

### 3.1 Function signature and parameters

```solidity
// DegenerusGameAdvanceModule.sol, lines 1000-1006
function rngGate(
    uint48 ts,
    uint32 day,
    uint24 lvl,
    bool isTicketJackpotDay,
    bool bonusFlip
) internal returns (uint256 word, uint32 gapDays) {
```

**Parameters:**
- `ts` -- current `block.timestamp` (cast to uint48 at line 158)
- `day` -- current day index from `_simulatedDayIndexAt(ts)` (line 159)
- `lvl` -- `purchaseLevel` (either `level` or `level + 1` depending on RNG lock state)
- `isTicketJackpotDay` -- `lastPurchaseDay` flag (determines level increment at RNG request)
- `bonusFlip` -- true when `(inJackpot && jackpotCounter == 0) || lvl == 0`

### 3.2 Control flow branches

**Branch 1: Word already recorded for today** (line 1008)

```solidity
// line 1008
if (rngWordByDay[day] != 0) return (rngWordByDay[day], 0);
```

If the current day's word exists, return it immediately with 0 gap days. This is the idempotent fast path.

**Branch 2: Fresh VRF word ready** (lines 1010-1053)

```solidity
// lines 1010-1013
uint256 currentWord = rngWordCurrent;
if (currentWord != 0 && rngRequestTime != 0) {
```

When VRF has delivered a word (`rngWordCurrent != 0`) and a request was pending (`rngRequestTime != 0`):

1. **Gap day detection** (lines 1015-1028): If `day > dailyIdx + 1`, gap days exist. Calls `_backfillGapDays()` and `_backfillOrphanedLootboxIndices()`. Extends death clock by gap count.

2. **Daily RNG processing** (line 1031): `_applyDailyRng(day, currentWord)` stores word permanently.

3. **Coinflip processing** (line 1032): `coinflip.processCoinflipPayouts(bonusFlip, currentWord, day)`

4. **Daily quest roll** (line 1033): `quests.rollDailyQuest(day, currentWord)`

5. **Redemption resolution** (lines 1036-1050): If sDGNRS has pending redemptions, derives `redemptionRoll` from `(currentWord >> 8) % 151 + 25` and resolves.

6. **Lootbox finalization** (line 1052): `_finalizeLootboxRng(currentWord)` writes word to current lootbox index.

7. **Return** (line 1053): `return (currentWord, gapDays)`

**Branch 3: VRF pending, check timeout** (lines 1057-1064)

```solidity
// lines 1057-1063
if (rngRequestTime != 0) {
    uint48 elapsed = ts - rngRequestTime;
    if (elapsed >= 12 hours) {
        _requestRng(isTicketJackpotDay, lvl);
        return (1, 0);
    }
    revert RngNotReady();
}
```

If a request is pending but no word has arrived:
- After 12 hours: retry by sending a new `_requestRng()`, return `(1, 0)` (retry signal)
- Before 12 hours: revert `RngNotReady()` -- blocks `advanceGame()` until VRF delivers

**Branch 4: No pending request** (lines 1066-1068)

```solidity
// lines 1066-1068
_requestRng(isTicketJackpotDay, lvl);
return (1, 0);
```

First call of the day with no pending request: fire `_requestRng()` and return `(1, 0)`.

### 3.3 State reads

| Variable | Storage Location | Purpose |
|----------|-----------------|---------|
| `rngWordByDay[day]` | DegenerusGameStorage.sol line 430 | Check if word already recorded |
| `rngWordCurrent` | DegenerusGameStorage.sol line 368 | VRF-delivered word (staging) |
| `rngRequestTime` | DegenerusGameStorage.sol line 239 | Pending request timestamp |
| `dailyIdx` | DegenerusGameStorage.sol | Last processed day index |

### 3.4 Revert conditions

| Condition | Trigger | Effect |
|-----------|---------|--------|
| `RngNotReady()` | VRF pending < 12 hours, no word delivered | Blocks advanceGame until VRF delivers |

**Verdict: TRACED** -- rngGate word retrieval fully documented with all 4 control flow branches, state reads, and the single revert condition proven.

---

## Section 4: Gap Day Backfill

**Trace:** `rngGate()` -> `_backfillGapDays()` -> `rngWordByDay[gapDay]` storage

**Contract:** DegenerusGameAdvanceModule.sol
**Function:** `_backfillGapDays()` (line 1564)

### 4.1 Entry conditions

Called from `rngGate()` when `day > dailyIdx + 1` (line 1016), meaning the VRF stalled and one or more days were skipped.

```solidity
// DegenerusGameAdvanceModule.sol, lines 1016-1018
uint32 gapCount = day - idx - 1;
_backfillGapDays(currentWord, idx + 1, day, bonusFlip);
```

### 4.2 Keccak derivation loop

```solidity
// DegenerusGameAdvanceModule.sol, lines 1564-1585
function _backfillGapDays(
    uint256 vrfWord,
    uint32 startDay,
    uint32 endDay,
    bool bonusFlip
) private {
    if (endDay - startDay > 120) endDay = startDay + 120;  // line 1572
    for (uint32 gapDay = startDay; gapDay < endDay; ) {    // line 1573
        uint256 derivedWord = uint256(
            keccak256(abi.encodePacked(vrfWord, gapDay))    // line 1575
        );
        if (derivedWord == 0) derivedWord = 1;             // line 1577
        rngWordByDay[gapDay] = derivedWord;                // line 1578
        coinflip.processCoinflipPayouts(bonusFlip, derivedWord, gapDay);  // line 1579
        emit DailyRngApplied(gapDay, derivedWord, 0, derivedWord);
        unchecked { ++gapDay; }
    }
}
```

**120-day cap (line 1572):** Limits backfill to 120 gap days to stay within block gas limit (~9M gas). Backfills oldest days first.

**Keccak derivation (line 1575):** Each gap day's word is `keccak256(abi.encodePacked(vrfWord, gapDay))`. This is deterministic from the VRF word and day index. The VRF word was unknown until VRF fulfillment, so the derived words inherit the unpredictability of the source VRF word.

**Zero-word protection (line 1577):** Derived words of 0 are replaced with 1.

**State writes per gap day:**
| Variable | Value | Line | Purpose |
|----------|-------|------|---------|
| `rngWordByDay[gapDay]` | derived word | 1578 | Permanent storage for gap day |

**External calls per gap day:**
- `coinflip.processCoinflipPayouts(bonusFlip, derivedWord, gapDay)` (line 1579) -- resolves coinflips for the gap day

**NOTE (from comment at line 1556):** Gap days get zero nudges (`totalFlipReversals` not consumed). `resolveRedemptionPeriod` is NOT called for backfilled gap days -- the redemption timer continued in real time during the stall.

### 4.3 Orphaned lootbox index backfill

Called immediately after gap day backfill at line 1022:

```solidity
// DegenerusGameAdvanceModule.sol, lines 1591-1610
function _backfillOrphanedLootboxIndices(uint256 vrfWord) private {
    uint48 idx = uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK));
    if (idx <= 1) return;
    for (uint48 i = idx - 1; i >= 1; ) {
        if (lootboxRngWordByIndex[i] != 0) break;
        uint256 fallbackWord = uint256(
            keccak256(abi.encodePacked(vrfWord, i))
        );
        if (fallbackWord == 0) fallbackWord = 1;
        lootboxRngWordByIndex[i] = fallbackWord;
        emit LootboxRngApplied(i, fallbackWord, 0);
        unchecked { --i; }
    }
}
```

Scans backwards from most recent lootbox index, filling any indices that never received a VRF word during the stall. Uses the same `keccak256(vrfWord, i)` pattern with VRF entropy.

**Verdict: TRACED** -- Gap day backfill fully documented with 120-day cap, keccak derivation from VRF word, per-day storage writes, and companion orphaned lootbox index backfill. All derived entropy inherits VRF unpredictability.

---

## Section 5: Lootbox VRF Request/Fulfillment

**Trace:** `requestLootboxRng()` -> VRF coordinator -> `rawFulfillRandomWords()` (mid-day path) or `_finalizeLootboxRng()` (daily path)

**Contract:** DegenerusGameAdvanceModule.sol

### 5.1 Lootbox packed state

**Contract:** DegenerusGameStorage.sol, lines 1300-1332

The lootbox RNG state is packed into a single uint256 slot (`lootboxRngPacked`, line 1315):

| Bits | Field | Type | Purpose |
|------|-------|------|---------|
| 0:47 | `lootboxRngIndex` | uint48 | Current index counter |
| 48:111 | `lootboxRngPendingEth` | uint64 | Pending ETH (scaled /1e15) |
| 112:175 | `lootboxRngThreshold` | uint64 | ETH threshold for triggering VRF |
| 176:183 | `lootboxRngMinLinkBalance` | uint8 | Minimum LINK for request |
| 184:223 | `lootboxRngPendingBurnie` | uint40 | Pending BURNIE (scaled /1e18) |
| 224:231 | `midDayTicketRngPending` | uint8 | Mid-day ticket swap flag |

Accessed via `_lrRead(shift, mask)` (line 1340) and `_lrWrite(shift, mask, value)` (line 1345).

Per-index word storage: `lootboxRngWordByIndex` mapping (DegenerusGameStorage.sol line 1370):

```solidity
// DegenerusGameStorage.sol, line 1370
mapping(uint48 => uint256) internal lootboxRngWordByIndex;
```

### 5.2 requestLootboxRng(): mid-day VRF request

**Contract:** DegenerusGameAdvanceModule.sol
**Function:** `requestLootboxRng()` (line 907)

**Pre-conditions (all revert with `E()` or `RngLocked()` on failure):**

```solidity
// lines 908-921
if (rngLockedFlag) revert RngLocked();                          // line 908
if (_lrRead(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK) != 0) revert E();  // line 911
// ... time window check ...
if ((nowTs - 82620) % 1 days >= 1 days - 15 minutes) revert E();   // line 917
if (rngWordByDay[currentDay] == 0) revert E();                     // line 919
if (rngRequestTime != 0) revert E();                               // line 921
```

| Guard | Line | Purpose |
|-------|------|---------|
| `rngLockedFlag` | 908 | Cannot request during daily RNG processing |
| `midDayTicketRngPending` | 911 | Cannot request while mid-day ticket processing active |
| 15-minute pre-reset window | 917 | Avoid competing with daily jackpot RNG flow |
| `rngWordByDay[currentDay] == 0` | 919 | Daily RNG must be consumed first |
| `rngRequestTime != 0` | 921 | No concurrent VRF request allowed |

**LINK balance check (lines 924-927):**

```solidity
(uint96 linkBal, , , , ) = vrfCoordinator.getSubscription(vrfSubscriptionId);
if (linkBal < MIN_LINK_FOR_LOOTBOX_RNG) revert E();
```

`MIN_LINK_FOR_LOOTBOX_RNG = 40 ether` (line 136).

**Threshold check (lines 930-944):** Requires either `BURNIE_RNG_TRIGGER` (40,000 BURNIE, line 121) of pending BURNIE, or combined ETH-equivalent >= threshold.

**Ticket buffer freeze (lines 949-956):**

```solidity
// lines 949-956
uint24 purchaseLevel_ = level + 1;
uint24 wk = _tqWriteKey(purchaseLevel_);
if (ticketQueue[wk].length > 0 && ticketsFullyProcessed) {
    _swapTicketSlot(purchaseLevel_);
    _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 1);
}
```

Swaps ticket write slot to read slot so tickets purchased after VRF delivery cannot be resolved by this word. Sets `midDayTicketRngPending = 1` flag.

**VRF request (lines 959-968):**

```solidity
uint256 id = vrfCoordinator.requestRandomWords(
    VRFRandomWordsRequest({
        keyHash: vrfKeyHash,
        subId: vrfSubscriptionId,
        requestConfirmations: VRF_MIDDAY_CONFIRMATIONS,
        callbackGasLimit: VRF_CALLBACK_GAS_LIMIT,
        numWords: 1,
        extraArgs: hex""
    })
);
```

`VRF_MIDDAY_CONFIRMATIONS = 4` (line 119) -- fewer confirmations than daily (10) for faster lootbox resolution.

**Post-request state mutations (lines 970-976):**

```solidity
_lrWrite(LR_INDEX_SHIFT, LR_INDEX_MASK, _lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK) + 1);  // line 971
_lrWrite(LR_PENDING_ETH_SHIFT, LR_PENDING_ETH_MASK, 0);   // line 972
_lrWrite(LR_PENDING_BURNIE_SHIFT, LR_PENDING_BURNIE_MASK, 0);  // line 973
vrfRequestId = id;          // line 974
rngWordCurrent = 0;         // line 975
rngRequestTime = uint48(block.timestamp);  // line 976
```

**CRITICAL:** `rngLockedFlag` is NOT set to true here. This is intentional -- mid-day lootbox RNG does not block daily game operations. The flag only gates daily VRF processing.

### 5.3 Mid-day fulfillment path

When `rawFulfillRandomWords()` is called with `rngLockedFlag == false` (line 1543, the `else` branch):

```solidity
// DegenerusGameAdvanceModule.sol, lines 1543-1550
} else {
    uint48 index = uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)) - 1;
    lootboxRngWordByIndex[index] = word;
    emit LootboxRngApplied(index, word, requestId);
    vrfRequestId = 0;
    rngRequestTime = 0;
}
```

Word is stored directly to `lootboxRngWordByIndex[index]` where `index = lootboxRngIndex - 1` (the index that was active when the request was made, since index was incremented after the request at line 971).

### 5.4 Daily fulfillment path (lootbox finalization)

When VRF delivers during the daily path (`rngLockedFlag == true`), the word goes to `rngWordCurrent`. Then `rngGate()` calls `_finalizeLootboxRng(currentWord)` at line 1052:

```solidity
// DegenerusGameAdvanceModule.sol, lines 1071-1076
function _finalizeLootboxRng(uint256 rngWord) private {
    uint48 index = uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)) - 1;
    if (lootboxRngWordByIndex[index] != 0) return;  // line 1073
    lootboxRngWordByIndex[index] = rngWord;          // line 1074
    emit LootboxRngApplied(index, rngWord, vrfRequestId);
}
```

**Guard (line 1073):** If the index already has a word (e.g., from a mid-day fulfillment), skip. This prevents double-write.

**State write:** `lootboxRngWordByIndex[index] = rngWord` -- shares the daily VRF word for lootbox resolution when no separate mid-day VRF was requested.

### 5.5 midDayTicketRngPending flag lifecycle

- **Set to 1:** When `requestLootboxRng()` swaps ticket buffer (line 954)
- **Cleared to 0:** In `advanceGame()` mid-day path when tickets are fully processed (line 204): `_lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0)`
- **Cleared to 0:** In `updateVrfCoordinatorAndSub()` during VRF coordinator rotation (line 1500)
- **Checked:** In `advanceGame()` mid-day path (line 190) -- if set, waits for lootbox word before processing tickets
- **Checked:** In `requestLootboxRng()` (line 911) -- prevents re-request while pending

**Verdict: TRACED** -- Lootbox VRF request and fulfillment fully documented for both mid-day and daily paths. Per-index word storage proven via `lootboxRngWordByIndex` mapping. Packed state layout and flag lifecycle verified.

---

## Section 6: Gameover Fallback

**Trace:** `advanceGame()` -> `_handleGameOverPath()` -> `_gameOverEntropy()` -> historical VRF fallback or revert

**Contract:** DegenerusGameAdvanceModule.sol

### 6.1 Entry: _handleGameOverPath

**Function:** `_handleGameOverPath()` (line 474)

Called from `advanceGame()` at line 178 when the liveness timeout is exceeded:

```solidity
// line 178
if (!inJackpot && !lastPurchase && _handleGameOverPath(day, lvl, psd)) {
    emit Advance(STAGE_GAMEOVER, lvl);
    return;
}
```

Inside `_handleGameOverPath` (lines 507-514):

```solidity
// lines 507-514
if (rngWordByDay[day] == 0) {
    uint256 rngWord = _gameOverEntropy(
        uint48(block.timestamp), day, lvl, lastPurchaseDay
    );
    if (rngWord == 1 || rngWord == 0) return true;
}
```

### 6.2 _gameOverEntropy: three-branch fallback

**Function:** `_gameOverEntropy()` (line 1083)

```solidity
// DegenerusGameAdvanceModule.sol, lines 1083-1163
function _gameOverEntropy(
    uint48 ts, uint32 day, uint24 lvl, bool isTicketJackpotDay
) private returns (uint256 word) {
```

**Branch 1: Word already exists** (line 1089)

```solidity
if (rngWordByDay[day] != 0) return rngWordByDay[day];
```

**Branch 2: Fresh VRF word ready** (lines 1091-1118)

```solidity
uint256 currentWord = rngWordCurrent;
if (currentWord != 0 && rngRequestTime != 0) {
    currentWord = _applyDailyRng(day, currentWord);
    if (lvl != 0) {
        coinflip.processCoinflipPayouts(isTicketJackpotDay, currentWord, day);
    }
    // Resolve gambling burn period if pending
    ...
    _finalizeLootboxRng(currentWord);
    return currentWord;
}
```

Same as `rngGate` Branch 2, but without gap day backfill (gameover does not backfill gaps) and with level-0 coinflip skip.

**Branch 3: Pending request, check for fallback timeout** (lines 1121-1153)

```solidity
// lines 1121-1153
if (rngRequestTime != 0) {
    uint48 elapsed = ts - rngRequestTime;
    if (elapsed >= GAMEOVER_RNG_FALLBACK_DELAY) {   // 3 days (line 109)
        uint256 fallbackWord = _getHistoricalRngFallback(day);
        fallbackWord = _applyDailyRng(day, fallbackWord);
        if (lvl != 0) {
            coinflip.processCoinflipPayouts(isTicketJackpotDay, fallbackWord, day);
        }
        // ... redemption resolution ...
        _finalizeLootboxRng(fallbackWord);
        return fallbackWord;
    }
    revert RngNotReady();
}
```

`GAMEOVER_RNG_FALLBACK_DELAY = 3 days` (line 109). After 3 days with no VRF response, uses historical fallback instead of waiting indefinitely.

**Branch 4: No pending request** (lines 1156-1163)

```solidity
// lines 1156-1163
if (_tryRequestRng(isTicketJackpotDay, lvl)) {
    return 1;
}
// VRF request failed; start fallback timer
rngWordCurrent = 0;
rngRequestTime = ts;
return 0;
```

Uses `_tryRequestRng()` (line 1401) which wraps the VRF call in a try/catch -- unlike `_requestRng()` which hard-reverts. If the VRF request itself fails (e.g., coordinator down), sets `rngRequestTime = ts` to start the 3-day fallback timer, and returns 0.

The calling code at line 514 checks `if (rngWord == 1 || rngWord == 0) return true` -- both the "request sent" (1) and "request failed, timer started" (0) cases cause `advanceGame()` to return early without proceeding to gameover drain.

### 6.3 _getHistoricalRngFallback: prevrandao and historical VRF

**Function:** `_getHistoricalRngFallback()` (line 1177)

```solidity
// DegenerusGameAdvanceModule.sol, lines 1177-1201
function _getHistoricalRngFallback(uint32 currentDay) private view returns (uint256 word) {
    uint256 found;
    uint256 combined;
    uint32 searchLimit = currentDay > 30 ? 30 : currentDay;
    for (uint32 searchDay = 1; searchDay < searchLimit; ) {
        uint256 w = rngWordByDay[searchDay];
        if (w != 0) {
            combined = uint256(keccak256(abi.encodePacked(combined, w)));
            unchecked { ++found; }
            if (found == 5) break;
        }
        unchecked { ++searchDay; }
    }
    word = uint256(
        keccak256(abi.encodePacked(combined, currentDay, block.prevrandao))
    );
    if (word == 0) word = 1;
}
```

**Entropy sources:**
1. **Up to 5 historical VRF words** (from `rngWordByDay` for days 1 through min(30, currentDay)) -- these are committed VRF words that cannot be manipulated
2. **`currentDay`** -- public knowledge, adds domain separation
3. **`block.prevrandao`** -- adds unpredictability at the cost of 1-bit validator manipulation (propose or skip)

**Security trade-off (from NatSpec at lines 1167-1174):** Historical words are committed VRF (non-manipulable). `prevrandao` adds unpredictability at the cost of 1-bit validator bias. Acceptable for a gameover-only fallback path when VRF is dead.

**Edge case:** If no historical words exist (level 0, zero completed advances), falls through to prevrandao-only entropy. The NatSpec notes this is acceptable because level 0 means zero VRF history, and 1-bit validator bias is irrelevant for level-0 gameover.

### 6.4 RngNotReady revert

When `_gameOverEntropy` has a pending request that has not timed out (< 3 days), it reverts:

```solidity
// line 1153
revert RngNotReady();
```

This blocks `advanceGame()` from proceeding to gameover drain until either:
1. VRF delivers a word (Branch 2), or
2. 3-day fallback delay expires (Branch 3)

**Verdict: TRACED** -- Gameover fallback fully documented with four branches: existing word, fresh VRF, historical+prevrandao fallback (after 3 days), and VRF request/timer start. RngNotReady revert blocks premature gameover. Historical fallback mixes up to 5 VRF-committed words with prevrandao.

---

## Summary Table

| Path | Entry | Exit | Word Storage | State Mutations | Verdict |
|------|-------|------|-------------|-----------------|---------|
| Daily VRF Request | `advanceGame()` -> `rngGate()` | `_requestRng()` -> VRF coordinator | N/A (request only) | `rngLockedFlag = true`, `vrfRequestId`, `rngWordCurrent = 0`, `rngRequestTime = ts`, lootbox index++ | TRACED |
| Daily VRF Fulfillment | VRF coordinator -> `DegenerusGame.rawFulfillRandomWords()` | `AdvanceModule.rawFulfillRandomWords()` (delegatecall) | `rngWordCurrent = word` (staging) | `rngWordCurrent` written | TRACED |
| Daily Word Application | `rngGate()` -> `_applyDailyRng()` | Returns word to `advanceGame()` | `rngWordByDay[day] = finalWord` | `totalFlipReversals = 0`, `rngWordCurrent = finalWord`, `lastVrfProcessedTimestamp` | TRACED |
| rngGate Retrieval | `advanceGame()` -> `rngGate()` | Returns `(word, gapDays)` | Read from `rngWordByDay[day]` or via `_applyDailyRng` | Varies by branch (see Section 3) | TRACED |
| Gap Day Backfill | `rngGate()` -> `_backfillGapDays()` | Loop writes | `rngWordByDay[gapDay] = keccak256(vrfWord, gapDay)` | Per-gap-day word storage, coinflip resolution | TRACED |
| Orphaned Lootbox Backfill | `rngGate()` -> `_backfillOrphanedLootboxIndices()` | Loop writes | `lootboxRngWordByIndex[i] = keccak256(vrfWord, i)` | Per-index fallback word storage | TRACED |
| Lootbox VRF Request | `requestLootboxRng()` | VRF coordinator | N/A (request only) | `vrfRequestId`, `rngWordCurrent = 0`, `rngRequestTime = ts`, lootbox index++, pending counters reset, mid-day flag | TRACED |
| Lootbox Mid-Day Fulfillment | VRF coordinator -> `rawFulfillRandomWords()` (`rngLockedFlag == false`) | Direct store | `lootboxRngWordByIndex[index] = word` | `vrfRequestId = 0`, `rngRequestTime = 0` | TRACED |
| Lootbox Daily Finalization | `rngGate()` -> `_finalizeLootboxRng()` | Conditional store | `lootboxRngWordByIndex[index] = rngWord` (if empty) | Single conditional write | TRACED |
| Gameover Fallback | `_handleGameOverPath()` -> `_gameOverEntropy()` | Historical VRF + prevrandao or RngNotReady revert | `rngWordByDay[day] = fallbackWord` (via `_applyDailyRng`) | Same as daily application, plus coinflip/redemption resolution | TRACED |

**Overall assessment:** All 6 sections traced with zero CONCERN findings. The VRF lifecycle is complete and sound:

1. **Request integrity:** Both daily and lootbox requests use proper Chainlink VRF parameters with appropriate confirmation counts (10 daily, 4 mid-day).
2. **Fulfillment security:** Callback validates `msg.sender == vrfCoordinator` and matches `requestId`. Zero-word protection prevents 0-as-pending confusion.
3. **Write-once guarantee:** `rngWordByDay[day]` is effectively write-once per day, guarded by `rngWordByDay[day] != 0` checks at both rngGate entry and `_applyDailyRng` flow. The `rngWordCurrent != 0` guard prevents double-delivery.
4. **Lock lifecycle:** `rngLockedFlag = true` at daily request (line 1442), `rngLockedFlag = false` at unlock (line 1515). Mid-day lootbox does NOT set the flag.
5. **Gap resilience:** Stall recovery via keccak-derived backfill inherits VRF unpredictability with 120-day cap.
6. **Gameover safety:** RngNotReady blocks premature drain. 3-day fallback uses historical VRF + prevrandao -- acceptable trade-off documented.

---

*Audit: 215-01 (RNG-01 VRF Lifecycle)*
*Phase: 215-rng-fresh-eyes*
