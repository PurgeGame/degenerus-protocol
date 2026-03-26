# Phase 59: RNG Gap Backfill Implementation - Research

**Researched:** 2026-03-22
**Domain:** Solidity smart contract modification -- VRF stall resilience, RNG backfill
**Confidence:** HIGH

## Summary

The VRF stall scenario creates "gap days" where `advanceGame()` could not be called because the VRF coordinator was unresponsive. During these gap days, `rngWordByDay[gapDay]` remains 0, `coinflipDayResult[gapDay]` is never populated (so coinflip stakes on those days are orphaned), and `lootboxRngWordByIndex` for any reserved-but-unfulfilled VRF requests stays at 0 (bricking those lootboxes).

The fix is straightforward: when `advanceGame()` resumes after a coordinator swap and detects `day > dailyIdx + 1`, it must loop through each gap day and (1) derive a deterministic RNG word from the first post-gap VRF word using `keccak256(abi.encodePacked(vrfWord, gapDay))`, (2) call `coinflip.processCoinflipPayouts()` for each gap day to resolve orphaned stakes, and (3) backfill `lootboxRngWordByIndex` for any orphaned indices.

**Primary recommendation:** Add a `_backfillGapDays` private function called from `rngGate()` (or just before it processes the current day) that loops `dailyIdx + 1` through `day - 1`, writing derived RNG words and processing coinflip payouts for each gap day. Handle orphaned lootbox indices as a separate concern within the same function.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| GAP-01 | When advanceGame detects dailyIdx gap (day > dailyIdx+1), backfill rngWordByDay for each missed day using keccak256(vrfWord, gapDay) | Backfill loop in rngGate; see Architecture Pattern 1 |
| GAP-02 | Backfill lootboxRngWordByIndex for any orphaned indices (index had no VRF response) | Orphaned index detection via lootboxRngRequestIndexById; see Architecture Pattern 2 |
| GAP-03 | Clear midDayTicketRngPending during coordinator swap or on first post-gap advance | updateVrfCoordinatorAndSub already resets rngLockedFlag/vrfRequestId/rngRequestTime/rngWordCurrent but misses midDayTicketRngPending; see Pattern 3 |
| GAP-04 | Coinflip stakes on gap days resolve normally via backfilled RNG words (no orphaned balances) | processCoinflipPayouts must be called per gap day; existing claim logic skips unresolved days at line 482-486 of BurnieCoinflip.sol |
| GAP-05 | Lootboxes assigned to orphaned indices can be opened via backfilled RNG words (no bricked lootboxes) | openLootBox/openBurnieLootBox revert with RngNotReady when lootboxRngWordByIndex[index]==0; backfill fixes this |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Solidity | 0.8.34 | Smart contract language | Project standard, no change needed |
| Foundry (forge) | latest | Compilation and testing | Already configured in foundry.toml |
| Hardhat | latest | JS test framework | Existing test suite uses hardhat + ethers |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| MockVRFCoordinator | (internal) | Test VRF callback simulation | contracts/mocks/MockVRFCoordinator.sol already exists |
| forge-std | latest | Foundry test utilities | Already in lib/ |

No new dependencies needed. This is a pure contract modification phase.

## Architecture Patterns

### Relevant Contract Architecture
```
contracts/
  DegenerusGame.sol              # Entry point: advanceGame(), rawFulfillRandomWords() (delegatecall wrappers)
  BurnieCoinflip.sol             # processCoinflipPayouts(bonusFlip, rngWord, epoch) -- must be called per gap day
  modules/
    DegenerusGameAdvanceModule.sol  # ALL modification happens here
      rngGate()                    # Line 765 -- day/RNG processing gate (INSERT backfill here)
      _applyDailyRng()             # Line 1416 -- stores rngWordByDay[day], emits event
      _finalizeLootboxRng()        # Line 827 -- stores lootboxRngWordByIndex[index]
      _unlockRng()                 # Line 1351 -- sets dailyIdx=day, clears VRF state
      updateVrfCoordinatorAndSub() # Line 1328 -- emergency swap (ADD midDayTicketRngPending clear)
      rawFulfillRandomWords()      # Line 1392 -- VRF callback
  storage/
    DegenerusGameStorage.sol       # Storage layout: rngWordByDay, lootboxRngWordByIndex, dailyIdx, etc.
```

### Pattern 1: Gap Day RNG Backfill (GAP-01, GAP-04)

**What:** When `rngGate()` receives the first post-gap VRF word and detects `day > dailyIdx + 1`, loop through each gap day and derive + store an RNG word.

**Where to insert:** In `rngGate()`, after verifying `currentWord != 0 && rngRequestTime != 0` and the request is from the current day (line 791), but BEFORE calling `_applyDailyRng(day, currentWord)`.

**Why this location:** `rngGate` is the single path where daily RNG words get committed. The `_applyDailyRng` call at line 792 handles the current day. Gap days must be resolved first so that `dailyIdx` advances correctly.

**Implementation logic:**
```solidity
// Inside rngGate(), after requestDay >= day check (line 789), before _applyDailyRng:
uint48 idx = dailyIdx;
if (day > idx + 1) {
    _backfillGapDays(currentWord, idx + 1, day, bonusFlip);
}
// Then proceed with normal _applyDailyRng(day, currentWord) for current day
```

The `_backfillGapDays` function:
```solidity
/// @dev Backfill rngWordByDay and process coinflip payouts for gap days
///      caused by VRF stall. Derives deterministic words from the first
///      post-gap VRF word.
/// @param vrfWord The first post-gap VRF random word.
/// @param startDay First gap day (dailyIdx + 1).
/// @param endDay Current day (exclusive -- not backfilled, handled by normal path).
/// @param bonusFlip Whether presale bonus applies to coinflip resolution.
function _backfillGapDays(
    uint256 vrfWord,
    uint48 startDay,
    uint48 endDay,
    bool bonusFlip
) private {
    for (uint48 gapDay = startDay; gapDay < endDay;) {
        uint256 derivedWord = uint256(keccak256(abi.encodePacked(vrfWord, gapDay)));
        if (derivedWord == 0) derivedWord = 1; // Match rawFulfillRandomWords guard
        rngWordByDay[gapDay] = derivedWord;
        // Resolve coinflip stakes for this gap day
        coinflip.processCoinflipPayouts(bonusFlip, derivedWord, gapDay);
        emit DailyRngApplied(gapDay, derivedWord, 0, derivedWord);
        unchecked { ++gapDay; }
    }
}
```

**Critical detail -- nudges:** Gap day backfill words should NOT apply `totalFlipReversals`. Nudges were queued by players AFTER the stall (or just before); they apply only to the current day's VRF word via the normal `_applyDailyRng` path. The backfill derivation uses raw keccak256 with zero nudges (as shown above with `0` in the event).

**Critical detail -- redemption burn periods:** The normal `rngGate` path calls `sdgnrs.resolveRedemptionPeriod()` for each day. During gap backfill, this should be SKIPPED because (a) gap days already passed, the redemption period timer continued ticking based on real time, and (b) calling it for multiple historical days would process the same pending redemption multiple times. The redemption gets resolved on the current day via the normal path.

### Pattern 2: Orphaned Lootbox Index Recovery (GAP-02, GAP-05)

**What:** During a VRF stall, there may be lootbox RNG indices that were reserved (via `_reserveLootboxRngIndex`) but never received a VRF response. These have `lootboxRngWordByIndex[index] == 0`.

**How orphaning happens:**
1. `_requestRng` or `requestLootboxRng` calls `_reserveLootboxRngIndex(requestId)`, advancing `lootboxRngIndex` and mapping `requestId -> index`
2. VRF stalls -- `rawFulfillRandomWords` never fires for that requestId
3. `updateVrfCoordinatorAndSub` clears `vrfRequestId = 0`, `rngRequestTime = 0`, but does NOT backfill `lootboxRngWordByIndex[index]`
4. New coordinator issues fresh requestIds; the old index stays orphaned with word=0

**Detection:** The orphaned index is the one mapped to the old `vrfRequestId` at the time of coordinator swap. Since `updateVrfCoordinatorAndSub` already sets `vrfRequestId = 0`, we need to capture the old requestId BEFORE clearing it, or derive the orphaned index from context.

**Approach A (recommended -- handle in rngGate alongside gap days):**
The `_finalizeLootboxRng(currentWord)` at line 808 handles the CURRENT request's lootbox index. For gap scenarios, any orphaned previous index can be detected because `lootboxRngRequestIndexById[vrfRequestId]` was already cleared by `updateVrfCoordinatorAndSub` (which sets `vrfRequestId = 0`). The orphaned index falls in the range `[last known good index + 1, current lootboxRngIndex - 1]`.

**Simpler approach:** During `updateVrfCoordinatorAndSub`, look up the outgoing requestId's lootbox index via `lootboxRngRequestIndexById[vrfRequestId]` BEFORE clearing `vrfRequestId`, and backfill that specific index using a deterministic derivation. This is cleaner because it resolves the orphan at the exact moment we know it's orphaned.

```solidity
// In updateVrfCoordinatorAndSub, BEFORE clearing vrfRequestId:
uint256 outgoingRequestId = vrfRequestId;
if (outgoingRequestId != 0) {
    uint48 orphanedIndex = lootboxRngRequestIndexById[outgoingRequestId];
    if (orphanedIndex != 0 && lootboxRngWordByIndex[orphanedIndex] == 0) {
        // Derive from previous successful VRF + index for uniqueness
        uint256 fallbackWord = uint256(keccak256(abi.encodePacked(
            lastLootboxRngWord, orphanedIndex
        )));
        if (fallbackWord == 0) fallbackWord = 1;
        lootboxRngWordByIndex[orphanedIndex] = fallbackWord;
        lastLootboxRngWord = fallbackWord;
    }
}
```

**Alternative (backfill in rngGate):** During the gap backfill loop, also derive lootbox words for any indices in the orphaned range. This is more complex to implement correctly because the exact orphaned indices are harder to detect at rngGate time.

**Recommendation:** Handle orphaned lootbox in `updateVrfCoordinatorAndSub` (Phase 60 territory, SWAP-01), and only include the rngWordByDay + coinflip backfill in this phase. However, since GAP-02/GAP-05 are scoped to Phase 59, the orphaned lootbox fix must go here. Use the `updateVrfCoordinatorAndSub` approach.

### Pattern 3: midDayTicketRngPending Clearing (GAP-03)

**What:** If `requestLootboxRng()` was called before the VRF stall (setting `midDayTicketRngPending = true`), and then the coordinator is swapped, this flag stays true. On the next `advanceGame()`, the mid-day path at line 166-170 will read `lootboxRngWordByIndex[lootboxRngIndex - 1]` which may be 0 (if the mid-day request was orphaned), causing a permanent `NotTimeYet` revert.

**Fix location:** `updateVrfCoordinatorAndSub()` at line 1328.

```solidity
// Add to updateVrfCoordinatorAndSub, after the existing state resets:
midDayTicketRngPending = false;
```

**This is a one-line fix** but critically important -- without it, the game can deadlock after coordinator swap if a mid-day lootbox RNG was pending.

### Anti-Patterns to Avoid

- **Full advanceGame replay for gap days:** The requirements explicitly state "No full advanceGame processing needed for gap days -- just RNG backfill." Gap days do NOT need jackpot distributions, ticket processing, level transitions, or any other daily logic. Only `rngWordByDay` and `coinflip.processCoinflipPayouts()` need resolution.

- **Using block.prevrandao or blockhash for backfill entropy:** These are manipulable by validators. The VRF word is already cryptographically secure; deriving from it via keccak256 preserves the security properties.

- **Resetting totalFlipReversals during backfill:** Nudges should only be consumed once, on the current day. Backfilled gap days get raw derived words with zero nudges.

- **Processing gambling burn redemptions for each gap day:** `resolveRedemptionPeriod` should only fire on the current day. Calling it multiple times for historical days would double/triple-process pending redemptions.

- **Unbounded gap loop without gas consideration:** See Pitfall 1 below.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| RNG derivation for gap days | Custom PRNG | `keccak256(abi.encodePacked(vrfWord, gapDay))` | keccak256 is the standard Solidity entropy derivation; matches existing patterns in the codebase (BurnieCoinflip line 784, DegeneretteModule) |
| Mock VRF in tests | New mock | Existing `MockVRFCoordinator.sol` | Already supports `fulfillRandomWords` and `fulfillRandomWordsRaw` |
| Time manipulation in tests | Custom harness | `advanceToNextDay()` and `advanceTime()` from `test/helpers/testUtils.js` | Already proven across the existing test suite |

## Common Pitfalls

### Pitfall 1: Gas Limit on Backfill Loop

**What goes wrong:** If the VRF stall lasts many days (e.g., 30+), the backfill loop processes all gap days in a single transaction. Each iteration costs approximately:
- 1 SSTORE for `rngWordByDay[gapDay]` (22,100 gas cold)
- External call to `coinflip.processCoinflipPayouts()` (~30,000-50,000 gas)
- 1 keccak256 + ABI encode (~100 gas)
- Event emission (~1,500 gas)
- Total per gap day: ~55,000-75,000 gas

For 30 gap days: ~2.25M gas. For 100 gap days: ~7.5M gas. The 14M gas ceiling leaves room for up to ~180 gap days before the backfill alone would breach the limit.

**Why it happens:** VRF coordinator could be down for weeks before governance swaps it.

**How to avoid:** The realistic max stall is bounded by governance (20h+ detection time, then swap proposal + voting + execution). A stall lasting more than a few days is already extreme. If concerned:
- Option A: Accept the risk -- 180 gap days (6 months) of VRF downtime is unrealistic
- Option B: Add a gas-bounded loop with continuation (process N gap days per call), but this adds complexity for an edge case that is extremely unlikely

**Recommendation:** Option A. The governance mechanism limits realistic stalls to days, not months. The 14M gas ceiling comfortably handles 180+ gap days.

**Warning signs:** VRF stall lasting more than 2 weeks should prompt manual verification of the backfill gas cost before executing the first post-swap `advanceGame()`.

### Pitfall 2: Coinflip Stake Window Expiry During Stall

**What goes wrong:** Coinflip claims have a window (`COIN_CLAIM_DAYS`, typically 7-14 days). If the stall exceeds this window, players' gap-day stakes might expire before backfill resolves them.

**Why it happens:** The claim window is measured against `flipsClaimableDay`, which advances when `processCoinflipPayouts` is called. During a stall, `flipsClaimableDay` stays frozen.

**How to avoid:** This is actually NOT a problem. `flipsClaimableDay` is updated by `processCoinflipPayouts()` to `epoch` (the gap day being resolved). The claim window works relative to the LATEST resolved day, not wall-clock time. When backfill calls `processCoinflipPayouts` for gap days in order, `flipsClaimableDay` advances through each gap day. Players' `lastClaim` cursor was frozen during the stall, so the window relative to the new `flipsClaimableDay` should encompass their staked days.

**Warning signs:** If backfill advances `flipsClaimableDay` past a player's oldest unclaimed stake by more than `COIN_CLAIM_DAYS`, those stakes could be skipped. But this only matters if the player had unclaimed stakes from BEFORE the stall. Auto-rebuy users are protected (their window is different).

### Pitfall 3: Double-Processing the Current Day

**What goes wrong:** If the backfill loop includes the current day, it would be processed twice -- once by backfill and once by the normal `_applyDailyRng` path.

**How to avoid:** The loop MUST use `gapDay < day` (exclusive of current day). The current day is handled by the existing `_applyDailyRng(day, currentWord)` at line 792.

### Pitfall 4: Event Semantics for Backfilled Days

**What goes wrong:** Emitting `DailyRngApplied` for backfilled days with `rawWord = derivedWord` (same as `finalWord`) could confuse off-chain indexers that expect `rawWord` to be a direct VRF response.

**How to avoid:** This is acceptable. The event already documents that nudges=0 for backfilled days, which distinguishes them from normal days. Indexers should handle this gracefully. Alternative: emit a new `GapDayBackfilled(gapDay, derivedWord)` event, but this adds interface complexity for minimal benefit.

### Pitfall 5: Orphaned Lootbox Index Detection Edge Cases

**What goes wrong:** If multiple mid-day RNG requests were made before the stall (requestLootboxRng called multiple times), each reserved a separate lootbox index. Only the last `vrfRequestId` is tracked in storage.

**Why it happens:** `_reserveLootboxRngIndex` advances `lootboxRngIndex` on each call. If requestA reserved index 5 and requestB reserved index 6, only requestB's ID is stored in `vrfRequestId`. RequestA's index might already have been fulfilled before the stall (in which case it's fine), but if both were pending, index 5's requestId is lost.

**How to avoid:** In practice, mid-day requests are sequential -- the second request can only happen after the first's VRF response arrives (because `rngRequestTime != 0` blocks new requests at line 690). So only ONE unfulfilled mid-day request can exist at stall time. Combined with at most one daily request, the maximum orphaned indices is 2 (one daily, one mid-day), but the daily request uses the same `vrfRequestId` slot. Check: `requestLootboxRng` reverts if `rngRequestTime != 0` (line 690), confirming only one mid-day request can be in-flight.

**Bottom line:** At most one lootbox index can be orphaned (the one mapped to the current `vrfRequestId`). The `updateVrfCoordinatorAndSub` fix handles this cleanly.

### Pitfall 6: flipsClaimableDay Ordering During Backfill

**What goes wrong:** `processCoinflipPayouts` sets `flipsClaimableDay = epoch` (line 842). If backfill processes gap days out of order, `flipsClaimableDay` could jump backwards, breaking the claim window logic.

**How to avoid:** The backfill loop MUST process gap days in ascending order (startDay to endDay-1). The current loop design (`for (uint48 gapDay = startDay; gapDay < endDay; ++gapDay)`) naturally ensures this.

## Code Examples

### Verified pattern: how `_applyDailyRng` stores words (line 1416-1432)
```solidity
// Source: contracts/modules/DegenerusGameAdvanceModule.sol:1416-1432
function _applyDailyRng(
    uint48 day,
    uint256 rawWord
) private returns (uint256 finalWord) {
    uint256 nudges = totalFlipReversals;
    finalWord = rawWord;
    if (nudges != 0) {
        unchecked {
            finalWord += nudges;
        }
        totalFlipReversals = 0;
    }
    rngWordCurrent = finalWord;
    rngWordByDay[day] = finalWord;
    lastVrfProcessedTimestamp = uint48(block.timestamp);
    emit DailyRngApplied(day, rawWord, nudges, finalWord);
}
```

### Verified pattern: how `processCoinflipPayouts` resolves a day (line 778-842)
```solidity
// Source: contracts/BurnieCoinflip.sol:778-842
function processCoinflipPayouts(
    bool bonusFlip,
    uint256 rngWord,
    uint48 epoch
) external onlyDegenerusGameContract {
    uint256 seedWord = uint256(keccak256(abi.encodePacked(rngWord, epoch)));
    // ... determines rewardPercent and win ...
    coinflipDayResult[epoch] = CoinflipDayResult({
        rewardPercent: rewardPercent,
        win: win
    });
    // ... bounty logic ...
    flipsClaimableDay = epoch;
    // ... event emission ...
}
```

### Verified pattern: how claims skip unresolved days (line 482-486)
```solidity
// Source: contracts/BurnieCoinflip.sol:482-486
// Skip unresolved days (gaps from testnet day-advance or missed resolution)
if (rewardPercent == 0 && !win) {
    unchecked { ++cursor; --remaining; }
    continue;
}
```
This means pre-backfill claims already handle gap days gracefully (skip them), so the backfill is about resolving them -- not preventing crashes.

### Verified pattern: how lootbox open checks RNG (line 549-550)
```solidity
// Source: contracts/modules/DegenerusGameLootboxModule.sol:549-550
uint256 rngWord = lootboxRngWordByIndex[index];
if (rngWord == 0) revert RngNotReady();
```

### Verified pattern: updateVrfCoordinatorAndSub state resets (line 1328-1346)
```solidity
// Source: contracts/modules/DegenerusGameAdvanceModule.sol:1340-1346
// Reset RNG state to allow immediate advancement
rngLockedFlag = false;
vrfRequestId = 0;
rngRequestTime = 0;
rngWordCurrent = 0;
// NOTE: Missing midDayTicketRngPending = false  <-- GAP-03 fix
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No gap handling | Game stalls, manual workaround | Pre-v3.6 | Coinflip stakes orphaned, lootboxes bricked |
| (Proposed) Gap backfill via keccak256 derivation | v3.6 | Automatic recovery when VRF resumes |

**Existing gap handling in claims:** BurnieCoinflip already has line 482-486 that skips unresolved days during claims. This was likely added for testnet scenarios. The backfill approach builds on top of this -- it resolves the days so stakes are not permanently skipped.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Hardhat (ethers v6) + Foundry (forge) |
| Config file | `foundry.toml` (Foundry), `hardhat.config.cjs` (Hardhat) |
| Quick run command | `npx hardhat test test/unit/VRFIntegration.test.js` |
| Full suite command | `npx hardhat test` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| GAP-01 | Gap day RNG backfill via keccak256 | unit | `npx hardhat test test/unit/VRFIntegration.test.js` | Partial -- VRFIntegration.test.js exists but has no gap tests |
| GAP-02 | Orphaned lootbox index backfill | unit | (new test needed) | No -- Wave 0 |
| GAP-03 | midDayTicketRngPending clearing | unit | (new test needed) | No -- Wave 0 |
| GAP-04 | Coinflip claims across gap days | integration | (new test needed) | No -- Wave 0 |
| GAP-05 | Lootbox opens after backfill | integration | (new test needed) | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `npx hardhat test test/unit/VRFIntegration.test.js`
- **Per wave merge:** `npx hardhat test`
- **Phase gate:** Full suite green before verify

### Wave 0 Gaps
Note: Phase 61 is a dedicated testing phase (TEST-01, TEST-02, TEST-03), so Phase 59 focuses on the implementation. However, basic smoke tests should be added to VRFIntegration.test.js to verify the backfill works. The comprehensive stall-swap-resume tests belong to Phase 61.

- [ ] Add gap backfill test cases to `test/unit/VRFIntegration.test.js` or a new file
- [ ] Test helper for simulating multi-day VRF stall (advance time past multiple day boundaries without fulfilling VRF)

## Open Questions

1. **Bounty handling during backfill**
   - What we know: `processCoinflipPayouts` has bounty logic (lines 818-838) that credits `bountyOwedTo` on win days. During gap backfill, the bounty owner from the pre-stall period would be resolved.
   - What's unclear: Is it correct to resolve the bounty for the first gap day, or should bounty handling be skipped during backfill?
   - Recommendation: Allow it. The bounty was legitimately armed before the stall. If the derived RNG produces a win, the bounty owner earned it. No special handling needed.

2. **flipsClaimableDay jump**
   - What we know: Backfill will set `flipsClaimableDay` to each gap day in sequence, ending at `day - 1`. Then the current day's `processCoinflipPayouts` sets it to `day`.
   - What's unclear: Could the rapid jump from pre-stall day to post-stall day cause any claim window issues?
   - Recommendation: Likely fine because `flipsClaimableDay` advancing through gap days in a single tx means all gap days are "resolved" simultaneously. Players claiming after the backfill tx see all gap days as resolved. Players who claimed during the stall already had their claims process correctly (skipping unresolved days).

3. **lastVrfProcessedTimestamp during backfill**
   - What we know: `_applyDailyRng` sets `lastVrfProcessedTimestamp = uint48(block.timestamp)`. The backfill does NOT call `_applyDailyRng`.
   - Recommendation: The backfill function should NOT set `lastVrfProcessedTimestamp` per gap day (the gaps were in the past). The normal `_applyDailyRng` for the current day handles this correctly, setting it to the actual block.timestamp.

## Sources

### Primary (HIGH confidence)
- `contracts/modules/DegenerusGameAdvanceModule.sol` -- Full read of rngGate, _applyDailyRng, _finalizeLootboxRng, _unlockRng, updateVrfCoordinatorAndSub, rawFulfillRandomWords, requestLootboxRng, _requestRng, _finalizeRngRequest, _reserveLootboxRngIndex
- `contracts/BurnieCoinflip.sol` -- processCoinflipPayouts (line 778-857), _claimCoinflipsInternal gap handling (line 482-486), _targetFlipDay
- `contracts/modules/DegenerusGameLootboxModule.sol` -- openLootBox (line 542-614), openBurnieLootBox (line 622-644)
- `contracts/storage/DegenerusGameStorage.sol` -- All relevant storage variables: rngWordByDay, lootboxRngWordByIndex, dailyIdx, midDayTicketRngPending, lootboxRngIndex, lootboxRngRequestIndexById
- `contracts/mocks/MockVRFCoordinator.sol` -- Full read, test harness capabilities
- `audit/gas-ceiling-analysis.md` -- 14M gas ceiling target, per-operation costs
- `audit/KNOWN-ISSUES.md` -- VRF stall acknowledged as known issue

### Secondary (MEDIUM confidence)
- `test/unit/VRFIntegration.test.js` -- Existing test patterns for VRF lifecycle
- `test/helpers/testUtils.js` -- Test helper utilities

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- No new dependencies, pure Solidity modification
- Architecture: HIGH -- All insertion points verified against current code, storage layout confirmed
- Pitfalls: HIGH -- Gas ceiling verified against existing analysis, claim window mechanics traced through code

**Research date:** 2026-03-22
**Valid until:** 2026-04-22 (stable -- contract is pre-audit, changes are controlled)
