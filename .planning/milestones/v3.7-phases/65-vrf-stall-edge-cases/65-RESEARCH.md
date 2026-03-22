# Phase 65: VRF Stall Edge Cases - Research

**Researched:** 2026-03-22
**Domain:** VRF stall recovery edge cases -- gap backfill entropy, gas ceiling, coordinator swap completeness, gameover fallback, dailyIdx timing consistency
**Confidence:** HIGH

## Summary

This phase audits the edge cases in VRF stall recovery, building on the VRF core (Phase 63) and lootbox RNG lifecycle (Phase 64) work. The scope covers seven requirements: gap backfill entropy uniqueness (STALL-01), manipulation window analysis (STALL-02), gas ceiling per-iteration (STALL-03), coordinator swap state cleanup completeness (STALL-04), zero-seed edge case at swap time (STALL-05), gameover fallback entropy quality (STALL-06), and dailyIdx timing consistency across game operations (STALL-07).

The codebase has two backfill mechanisms added in v3.6: `_backfillGapDays` (derives per-day words via `keccak256(vrfWord, gapDay)`) and `_backfillOrphanedLootboxIndices` (derives per-index words via `keccak256(vrfWord, i)`). Both have zero guards. The coordinator swap function `updateVrfCoordinatorAndSub` resets 5 VRF state variables and the `midDayTicketRngPending` flag but does NOT touch `lootboxRngIndex`, `lastLootboxRngWord`, or `totalFlipReversals`. The gameover fallback path uses `_getHistoricalRngFallback` (keccak256 of historical VRF words + prevrandao) with a 3-day timeout. The timing audit covers a critical design distinction: `dailyIdx` (stall-frozen game day counter) vs `_simulatedDayIndex()` (wall-clock day counter used by sDGNRS gambling burns).

**Primary recommendation:** Split into two plans: (1) Foundry fuzz/gas test suite covering STALL-01 through STALL-05 and STALL-07 timing analysis, (2) findings document with C4A severity classifications for all stall edge cases including STALL-06 gameover fallback assessment plus consolidated dailyIdx timing audit.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| STALL-01 | Gap backfill entropy derivation verified -- keccak256(vrfWord, gapDay) produces unique per-day words | Section "Gap Backfill Entropy Derivation" -- preimage uniqueness analysis, code at AdvanceModule lines 1442-1448 |
| STALL-02 | Gap backfill manipulation window analyzed -- time between VRF callback and advanceGame consumption with severity | Section "Manipulation Window Analysis" -- VRF callback stores to rngWordCurrent, advanceGame reads and triggers backfill; window is standard VRF callback-to-consumption |
| STALL-03 | Gap backfill gas ceiling verified -- per-iteration cost profiled, safe upper bound for gap count | Section "Gap Backfill Gas Ceiling" -- per-iteration cost analysis with processCoinflipPayouts included, block gas limit comparison |
| STALL-04 | Coordinator swap state cleanup complete -- all state resets confirmed, orphaned lootbox recovery correct | Section "Coordinator Swap State Inventory" -- complete variable-by-variable audit of updateVrfCoordinatorAndSub |
| STALL-05 | Zero-seed edge case verified -- lastLootboxRngWord==0 at coordinator swap cannot produce degenerate entropy | Section "Zero-Seed Edge Case" -- lastLootboxRngWord consumption trace in processTicketBatch and _backfillOrphanedLootboxIndices |
| STALL-06 | Game-over fallback entropy verified -- _getHistoricalRngFallback and prevrandao usage with C4A severity | Section "Gameover Fallback Entropy" -- V37-001 deferred test coverage, prevrandao 1-bit manipulation analysis |
| STALL-07 | All game operations verified using dailyIdx timing consistently -- resolveRedemptionPeriod clock mechanism audited | Section "DailyIdx Timing Consistency" -- wall-clock vs stall-frozen timing analysis, sDGNRS gambling burn period tracking |
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
| MockVRFCoordinator | Custom (contracts/mocks/) | Simulates Chainlink VRF V2.5 coordinator | All VRF tests |
| VRFHandler | Custom (test/fuzz/helpers/) | Wraps mock VRF for invariant testing | Reuse in fuzz tests |
| DeployProtocol | Custom (test/fuzz/helpers/) | Full protocol deployment for testing | Base contract for all test files |

### Existing Test Infrastructure
| File | Purpose | Reusable? |
|------|---------|-----------|
| test/fuzz/VRFCore.t.sol | VRF core lifecycle tests (Phase 63) | Yes -- helper patterns for _completeDay, coordinator swap |
| test/fuzz/LootboxRngLifecycle.t.sol | Lootbox RNG lifecycle tests (Phase 64) | Yes -- lootbox purchase helpers, word verification |
| test/fuzz/StallResilience.t.sol | Stall/swap/resume integration tests (v3.6) | Yes -- _stallAndSwap, _resumeAfterSwap helpers |
| test/fuzz/helpers/DeployProtocol.sol | Full protocol deployment | Yes -- inherit for all new tests |

**Installation:** No new packages needed. All infrastructure exists.

## Architecture Patterns

### Gap Backfill Entropy Derivation (STALL-01)

**Location:** DegenerusGameAdvanceModule.sol lines 1436-1450

```solidity
function _backfillGapDays(
    uint256 vrfWord,
    uint48 startDay,
    uint48 endDay,
    bool bonusFlip
) private {
    for (uint48 gapDay = startDay; gapDay < endDay;) {
        uint256 derivedWord = uint256(keccak256(abi.encodePacked(vrfWord, gapDay)));
        if (derivedWord == 0) derivedWord = 1;
        rngWordByDay[gapDay] = derivedWord;
        coinflip.processCoinflipPayouts(bonusFlip, derivedWord, gapDay);
        emit DailyRngApplied(gapDay, derivedWord, 0, derivedWord);
        unchecked { ++gapDay; }
    }
}
```

**Entropy uniqueness analysis:**
- Input: `keccak256(abi.encodePacked(vrfWord, gapDay))` where `vrfWord` is a uint256 and `gapDay` is a uint48
- For a fixed `vrfWord`, each distinct `gapDay` produces a distinct preimage (different packed bytes), therefore a distinct derived word (keccak256 collision resistance)
- For different `vrfWord` values (different VRF stall events), the preimages are also distinct
- The `abi.encodePacked(uint256, uint48)` produces 38 bytes (32 + 6). No ambiguity because the first element is fixed-width
- **Zero guard present:** `if (derivedWord == 0) derivedWord = 1`

**Critical property:** Gap days receive zero nudges (`totalFlipReversals` not consumed). The NatSpec at line 1428 documents this explicitly. Players who purchased nudges before the stall get their nudges applied to the current (post-gap) day only.

### Manipulation Window Analysis (STALL-02)

**The window:** VRF callback delivers `rngWordCurrent` via `rawFulfillRandomWords`. The word is consumed on the next `advanceGame` call, which triggers `_backfillGapDays` and `_backfillOrphanedLootboxIndices` before normal daily processing.

**Sequence:**
1. Coordinator swap (`updateVrfCoordinatorAndSub`) clears all VRF state
2. `advanceGame` calls `rngGate` which enters "Need fresh RNG" at line 841
3. `_requestRng` fires, sets `rngLockedFlag = true`, `lootboxRngIndex++`
4. VRF callback arrives (separate transaction), stores word to `rngWordCurrent`
5. `advanceGame` calls `rngGate`, sees `currentWord != 0 && rngRequestTime != 0`
6. Gap detection: `day > idx + 1` triggers `_backfillGapDays(currentWord, ...)`
7. Same call: `_backfillOrphanedLootboxIndices(currentWord)` fills orphaned lootbox indices

**Analysis:**
- Between step 4 (VRF callback) and step 5 (advanceGame consumption), the VRF word is visible on-chain via `rngWordCurrent`. This is the standard VRF callback-to-consumption window that exists for ALL daily VRF usage, not specific to gap backfill.
- During this window, an attacker who sees the VRF word could: (a) compute all gap day derived words, (b) compute coinflip outcomes for gap days, (c) decide whether to claim/not claim coinflip positions. BUT: coinflip positions were already placed BEFORE the stall. Players cannot add new coinflip bets for past gap days. They can only claim existing positions.
- For lootboxes: lootbox purchases during the stall are impossible (no `advanceGame` running means no level progression). Post-swap purchases target the new `lootboxRngIndex`, not orphaned indices.
- **Severity assessment:** INFO. The manipulation window is identical to the standard daily VRF window. No additional attack surface is introduced by gap backfill. Positions are pre-committed before the stall, preventing manipulation of gap day outcomes.

### Gap Backfill Gas Ceiling (STALL-03)

**Per-iteration gas cost of `_backfillGapDays` loop body:**

| Operation | Gas (cold worst case) | Notes |
|-----------|-----------------------|-------|
| `keccak256(abi.encodePacked(vrfWord, gapDay))` | ~36 + 6 (mem) + 30 (keccak) | 38-byte input |
| `if (derivedWord == 0) derivedWord = 1` | ~3 | Comparison |
| `SSTORE rngWordByDay[gapDay]` (0 -> nonzero, cold) | 22,100 | Cold mapping slot, zero-to-nonzero |
| `coinflip.processCoinflipPayouts(...)` external call | ~40,000-80,000 | External call + struct write + bounty logic. See sub-analysis below. |
| `emit DailyRngApplied(...)` LOG4 | ~1,875 | 4 topics + 0 bytes data |
| Loop overhead (unchecked increment, comparison) | ~20 | Trivial |
| **Total per iteration** | **~64,000-104,000** | Range depends on coinflip bounty state |

**Sub-analysis: `processCoinflipPayouts` gas per call:**
- `keccak256(abi.encodePacked(rngWord, epoch))`: ~66
- `seedWord % 20` + reward percent logic: ~100
- `SLOAD degenerusGame` + `lootboxPresaleActiveFlag()` external call: ~5,000
- `SSTORE coinflipDayResult[epoch]` (struct with uint16 + bool, cold mapping): ~22,100
- Bounty resolution (conditional): `SLOAD currentBounty` + `SLOAD bountyOwedTo` + conditional writes: ~4,200-20,000
- **Total processCoinflipPayouts:** ~31,000-47,000

**Per-iteration estimate (refined):** ~85,000-125,000 gas

**Block gas limit analysis (Base L2):**
- Base block gas limit: 30M gas
- Conservative advanceGame overhead (before backfill loop): ~200,000 gas (VRF request, state reads)
- Post-backfill processing (current day): ~100,000 gas minimum
- Available for backfill: ~29.7M gas
- Maximum gap days at 125k per iteration: ~237 days
- Maximum gap days at 85k per iteration: ~349 days

**Practical assessment:** A 237-day VRF stall is operationally implausible. The game has a 120-day inactivity timeout (`DEATH_CLOCK_DURATION`). After 120 days without advancement, the game transitions to game-over via `_gameOverEntropy`, bypassing the normal backfill path entirely. Therefore the maximum practical gap is ~120 days.

**120 days at 125k/iteration:** 15M gas. Well within 30M block gas limit.

**Note:** `_backfillOrphanedLootboxIndices` runs AFTER `_backfillGapDays` in the same transaction. Its per-iteration cost is lower (~25,000 gas -- 1 SLOAD check, 1 keccak256, 1 SSTORE, 1 SSTORE lastLootboxRngWord, 1 LOG). The number of orphaned lootbox indices is bounded by the number of mid-day `requestLootboxRng` calls during the stall period. Since requestLootboxRng cannot fire during a stall (requires daily RNG to be recorded for the current day), the maximum orphaned indices equals 1 (the daily request that was in-flight when the stall began) + N (mid-day requests in-flight). In practice, at most 1-2 orphaned indices.

### Coordinator Swap State Inventory (STALL-04)

**Function:** `updateVrfCoordinatorAndSub` at AdvanceModule lines 1338-1367

**Variables RESET (6 total):**

| Variable | Reset To | Line | Purpose |
|----------|----------|------|---------|
| `vrfCoordinator` | `newCoordinator` | 1346 | New VRF provider address |
| `vrfSubscriptionId` | `newSubId` | 1347 | New LINK billing subscription |
| `vrfKeyHash` | `newKeyHash` | 1348 | New gas lane key hash |
| `rngLockedFlag` | `false` | 1351 | Unlock daily RNG flow |
| `vrfRequestId` | `0` | 1352 | Clear stale request ID |
| `rngRequestTime` | `0` | 1353 | Clear stale request timestamp |
| `rngWordCurrent` | `0` | 1354 | Clear any unprocessed VRF word |
| `midDayTicketRngPending` | `false` | 1359 | Prevent post-swap NotTimeYet deadlock |

**Variables INTENTIONALLY PRESERVED:**

| Variable | Current Value | Why Preserved | Risk |
|----------|--------------|---------------|------|
| `lootboxRngIndex` | Last incremented value | Game state -- purchases reference this index. Orphaned indices handled by `_backfillOrphanedLootboxIndices` on next VRF | SAFE -- backfill mechanism covers this |
| `lastLootboxRngWord` | Last stored lootbox word (or 0 if never set) | Ticket processing entropy source. See STALL-05 analysis | NEEDS ANALYSIS |
| `totalFlipReversals` | Accumulated nudge count | Players paid irreversible BURNIE burns. NatSpec at line 1361-1364 documents this. Resetting would steal user value | SAFE -- documented design decision |
| `dailyIdx` | Last completed day | Gap detection uses `day > dailyIdx + 1`. Must preserve for backfill range calculation | SAFE -- required for gap detection |
| `levelStartTime` | Level start timestamp | Extended by gap duration in rngGate (line 806: `levelStartTime += gapCount * 1 days`) | SAFE -- extended during backfill |
| `rngWordByDay[*]` | Historical daily words | Immutable history. Used by `_getHistoricalRngFallback` | SAFE -- read-only |
| `lootboxRngWordByIndex[*]` | Historical lootbox words | Immutable per-index. Orphaned slots filled by backfill | SAFE -- backfill covers gaps |

**Completeness check:** All VRF-specific state variables from DegenerusGameStorage.sol (slot 0 packed fields: `rngLockedFlag`, `rngRequestTime`; deep slots: `rngWordCurrent`, `vrfRequestId`, `vrfCoordinator`, `vrfSubscriptionId`, `vrfKeyHash`, `midDayTicketRngPending`) are either reset or documented as intentionally preserved. No VRF state variable is overlooked.

### Zero-Seed Edge Case (STALL-05)

**Question:** If `lastLootboxRngWord == 0` when the coordinator swap occurs, can this produce degenerate entropy?

**Consumption points of `lastLootboxRngWord`:**

1. **`processTicketBatch` (JackpotModule line 1916):** `uint256 entropy = lastLootboxRngWord;`
   - Used as entropy seed for ticket trait assignment
   - If 0: `EntropyLib.entropyStep(0) == 0` -- all subsequent steps also return 0
   - Impact: all ticket trait assignments would be deterministic (same traits for every ticket in the batch)

2. **Mid-day drain path (AdvanceModule line 170):** `lastLootboxRngWord = word;`
   - This is a WRITE, not a READ. It updates `lastLootboxRngWord` from `lootboxRngWordByIndex[lootboxRngIndex - 1]`
   - The `word == 0` check at line 168 (`if (word == 0) revert NotTimeYet()`) prevents a zero word from propagating

**When can `lastLootboxRngWord == 0`?**
- At game start, before any VRF fulfillment. `lastLootboxRngWord` is initialized to 0 by default.
- After coordinator swap: the swap does NOT reset `lastLootboxRngWord`. It retains its pre-stall value.
- If the game has NEVER had a successful VRF fulfillment (level 0, day 1), `lastLootboxRngWord` is still 0.

**Post-swap sequence:**
1. Swap resets VRF state but preserves `lastLootboxRngWord`
2. `advanceGame` fires `_requestRng` (new request to new coordinator)
3. VRF callback stores word to `rngWordCurrent`
4. `advanceGame` calls `rngGate` -> `_applyDailyRng` -> `_finalizeLootboxRng(currentWord)` which sets `lastLootboxRngWord = currentWord` (line 849)
5. Any ticket processing AFTER this point uses the new (nonzero) `lastLootboxRngWord`

**The risk window:** Between the coordinator swap and the first post-swap `_finalizeLootboxRng` call, if `processTicketBatch` runs, it would use the pre-swap `lastLootboxRngWord`. If that was 0, ticket trait assignment entropy is degenerate.

**But can this happen?** Ticket processing requires `advanceGame` to enter the mid-day path (line 162: `day == dailyIdx`). After a coordinator swap, `dailyIdx` is the last completed day but `day` (wall-clock) has advanced. So `day > dailyIdx` and the mid-day path is NOT entered. Instead, the gap backfill and daily processing path runs first, which calls `_finalizeLootboxRng` setting `lastLootboxRngWord` to a nonzero value.

**Edge case:** If the swap happens within the same wall-clock day as the last completed day (no gap), `day == dailyIdx` and the mid-day path COULD run. But: (a) `midDayTicketRngPending` was cleared by the swap, so line 166's check fails, and (b) `rngWordByDay[day] != 0` would be true (already completed), so `rngGate` returns early at line 776.

**Severity assessment:** The zero-seed window is unreachable in practice because the coordinator swap precedes a mandatory `advanceGame` -> `rngGate` sequence that sets `lastLootboxRngWord` before any ticket processing can run. However, the theoretical scenario where `lastLootboxRngWord == 0` is fed to `processTicketBatch` should be documented as INFO for defense-in-depth.

### Gameover Fallback Entropy (STALL-06)

**Function:** `_gameOverEntropy` at AdvanceModule lines 858-931

**Three paths:**

1. **Normal VRF (line 867-889):** `rngWordCurrent != 0 && rngRequestTime != 0`. Uses `_applyDailyRng` + `_finalizeLootboxRng`. Identical to daily path. **SAFE -- proven in Phases 63-64.**

2. **Historical fallback (line 892-918):** After `GAMEOVER_RNG_FALLBACK_DELAY` (3 days). Uses `_getHistoricalRngFallback(day)` which collects up to 5 early historical VRF words, hashes them with `currentDay` and `block.prevrandao`. **This is the path requiring C4A severity assessment.**

3. **VRF request attempt (line 923-930):** Calls `_tryRequestRng` (try/catch). If request succeeds, returns 1 (pending). If fails, starts fallback timer.

**`_getHistoricalRngFallback` analysis (lines 944-963):**
```solidity
function _getHistoricalRngFallback(uint48 currentDay) private view returns (uint256 word) {
    uint256 found;
    uint256 combined;
    uint48 searchLimit = currentDay > 30 ? 30 : currentDay;
    for (uint48 searchDay = 1; searchDay < searchLimit; ) {
        uint256 w = rngWordByDay[searchDay];
        if (w != 0) {
            combined = uint256(keccak256(abi.encodePacked(combined, w)));
            unchecked { ++found; }
            if (found == 5) break;
        }
        unchecked { ++searchDay; }
    }
    return uint256(keccak256(abi.encodePacked(combined, currentDay, block.prevrandao)));
}
```

**Entropy quality assessment:**
- **Historical VRF words:** These are committed Chainlink VRF outputs, immutable on-chain. They cannot be manipulated retroactively. If the game has 5+ completed days, `combined` incorporates 5 VRF words.
- **`block.prevrandao`:** Post-Merge Ethereum uses RANDAO as `block.prevrandao`. A validator proposing the block can choose to propose or skip, giving them 1-bit manipulation (influence whether prevrandao is even/odd). On Base L2, the sequencer controls prevrandao entirely.
- **`currentDay`:** Deterministic, not manipulable.

**C4A severity factors:**
- **Trigger condition:** VRF must be dead for 3+ days AFTER gameover is reached. This is an edge-of-an-edge case (gameover itself is rare; VRF dead for 3 days on top of that is extremely unlikely).
- **Impact if manipulated:** The fallback word determines (a) coinflip outcome for the gameover day, (b) lootbox RNG word for the gameover day. On Base L2, the sequencer could choose prevrandao to influence outcomes.
- **Mitigations:** 5 committed VRF words provide 1280 bits of entropy. Even with 1-bit prevrandao manipulation, the combined hash is overwhelmingly unpredictable. The sequencer would need to precompute the keccak256 output for both prevrandao choices and pick the favorable one -- this gives them a 2x advantage on a binary outcome, not a deterministic one.
- **Level 0 fallback:** If NO historical words exist (game at level 0, zero completed days), `combined == 0` and the output is `keccak256(0, currentDay, prevrandao)`. This is prevrandao-only entropy. However, at level 0 there are no player positions to manipulate (no coinflips, no lootboxes).

**V37-001 deferred test coverage:** `_tryRequestRng` gameover entry point was deferred from Phase 63. It is a thin try/catch wrapper around `_finalizeRngRequest` (already proven). Guard branches (`address(0)`, `bytes32(0)`, `0` checks at lines 1242-1248) return `false` if VRF is not configured. This phase should verify these guard branches via unit tests.

**Missing zero guard (V37-003):** `_getHistoricalRngFallback` returns keccak256 output without `if (word == 0) word = 1`. Already documented in Phase 64 as INFO (probability 2^-256). The result flows to `_applyDailyRng` which adds nudges. If nudges are 0, a zero word would pass through to `_finalizeLootboxRng`, storing 0 and causing permanent `RngNotReady` for that lootbox index.

**Severity classification:** INFO for prevrandao manipulation (1-bit bias on gameover-only fallback after 3-day VRF death). The NatSpec at lines 933-941 already documents this trade-off accurately. The `_tryRequestRng` guard branches are trivially correct (return false if VRF not configured).

### DailyIdx Timing Consistency (STALL-07)

**Two clocks in the system:**

1. **`dailyIdx`** -- Game-internal day counter. Set by `_unlockRng(day)` at line 1373. Only advances when `advanceGame` successfully processes a day. **Stall-frozen: does not advance during VRF stall.**

2. **`_simulatedDayIndex()` / `currentDayView()`** -- Wall-clock day counter. Computed from `block.timestamp` via `GameTimeLib.currentDayIndexAt(ts)`. Formula: `(ts - 82620) / 86400 - DEPLOY_DAY_BOUNDARY + 1`. **Continues ticking during stall.**

**Critical finding: `resolveRedemptionPeriod` uses `flipDay = day + 1` where `day` is passed from `rngGate`/`_gameOverEntropy`.**

The `flipDay` parameter to `sdgnrs.resolveRedemptionPeriod(redemptionRoll, flipDay)` is set at:
- rngGate normal path (line 818): `uint48 flipDay = day + 1;` -- `day` is the current game day being processed
- _gameOverEntropy normal VRF (line 881): `uint48 flipDay = day + 1;` -- same
- _gameOverEntropy fallback (line 910): `uint48 flipDay = day + 1;` -- same

The `day` parameter is the `dailyIdx`-aligned game day, not wall-clock. This means during a stall, the redemption period is NOT resolved until the game catches up to that day. The NatSpec at lines 1429-1431 explicitly documents this:

> NOTE: resolveRedemptionPeriod is NOT called for backfilled gap days --
> the redemption timer continued ticking in real time during the stall;
> it resolves only on the current day via the normal rngGate path.

**sDGNRS gambling burn timing:**
- `_submitGamblingClaimFrom` (sDGNRS line 710): `uint48 currentPeriod = game.currentDayView();`
- `currentDayView()` returns `_simulatedDayIndex()` -- wall-clock time
- This means: during a VRF stall, players CAN still submit gambling burns (the period index advances with wall clock). BUT the resolution (`resolveRedemptionPeriod`) only happens when `advanceGame` runs for the current day.
- After stall recovery with backfill: gap days do NOT call `resolveRedemptionPeriod` (documented design). The current day's `rngGate` calls `resolveRedemptionPeriod` once for any pending period.

**Timing mismatch analysis:**
If a player submits a gambling burn during a stall (wall-clock day 5, but `dailyIdx` stuck at 2), they are assigned `periodIndex = 5` (wall-clock). When the stall resolves and backfill processes days 3-4, those gap days do NOT call `resolveRedemptionPeriod`. When the current day (5) processes, it calls `resolveRedemptionPeriod` which resolves the pending period (index 5). The `flipDay` is `5 + 1 = 6`. The coinflip result for day 6 will be available after day 6 completes.

**This is correct behavior:** The redemption period is indexed by wall-clock time (when the burn was submitted), but resolution is gated by game progression (when `advanceGame` runs). The delay is a feature, not a bug -- it prevents gaming the resolution timing.

**Other `block.timestamp` usage in AdvanceModule:**
- Line 129: `uint48 ts = uint48(block.timestamp)` -- entry point timestamp, converted to `day` via `_simulatedDayIndexAt(ts)`. Correct.
- Line 408: `lastVrfProcessedTimestamp = uint48(block.timestamp)` -- tracking. Not game logic.
- Line 655: `uint256 elapsed = (block.timestamp - 82620) % 1 days` -- within-day elapsed time for requestLootboxRng window check. Correct (wall-clock for time-of-day gating).
- Line 682: `uint48 nowTs = uint48(block.timestamp)` -- requestLootboxRng. Correct.
- Line 743, 1286: `rngRequestTime = uint48(block.timestamp)` -- VRF request timestamp for timeout. Correct (wall-clock for timeout tracking).
- Line 1489: `lastVrfProcessedTimestamp = uint48(block.timestamp)` -- tracking. Not game logic.

**Verdict:** All `block.timestamp` usages in AdvanceModule are correct for their purpose (wall-clock gating, timeout tracking, day computation). No `block.timestamp` is used where `dailyIdx` is expected. The `resolveRedemptionPeriod` uses `dailyIdx`-aligned `day + 1` for `flipDay`, which is correct because coinflip results are stored by game day, not wall-clock day.

**DegenerusGame.sol `block.timestamp` usage:**
- Line 245: `levelStartTime = uint48(block.timestamp)` -- game start/reset. Correct.
- Line 2342: `uint48 ts = uint48(block.timestamp)` -- `gamble()` function entry point. Correct.

**No `block.timestamp` in sDGNRS `resolveRedemptionPeriod`:** The function takes `roll` and `flipDay` as parameters from the game contract. It does NOT read `block.timestamp` internally. All timing decisions are made by the caller.

### Anti-Patterns to Avoid

- **Do not assume gap backfill gas is just keccak256 + SSTORE:** The `processCoinflipPayouts` external call dominates the per-iteration cost. Must include it in gas analysis.
- **Do not test only 1-day gaps:** Edge cases include 0-day gaps (no backfill), 1-day gaps (boundary), multi-day gaps, and maximum practical gaps (~120 days before death clock).
- **Do not confuse `dailyIdx` with `_simulatedDayIndex()`:** `dailyIdx` is stall-frozen; `_simulatedDayIndex()` is wall-clock. Tests must verify both are used correctly in their respective contexts.
- **Do not assume `lastLootboxRngWord` is nonzero after coordinator swap:** It retains its pre-swap value, which could theoretically be 0 at game start.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| VRF mock | Custom VRF simulation | MockVRFCoordinator.sol | Already handles fulfillRandomWords + fulfillRandomWordsRaw |
| Protocol deployment | Manual contract setup | DeployProtocol.sol | Deploys all 23 contracts with correct addresses |
| Coordinator swap helper | Manual swap steps | `_doCoordinatorSwap()` from StallResilience.t.sol | Already handles new coordinator deployment + admin prank |
| Gap stall helper | Manual warp + swap steps | `_stallAndSwap()` from StallResilience.t.sol | Combines time warp + swap in one call |
| Gas profiling | Manual opcode counting | `forge test --gas-report` | Foundry native is more accurate, especially with via_ir compiler |

## Common Pitfalls

### Pitfall 1: Gap Backfill Loop Gas Exceeds Block Limit
**What goes wrong:** If the gap count is enormous, `_backfillGapDays` loop could exceed block gas limit and `advanceGame` would revert permanently.
**Why it happens:** Each iteration does 1 external call to `processCoinflipPayouts` + 1 cold SSTORE + 1 event.
**How to avoid:** The death clock (120 days) limits the maximum practical gap. Test with the maximum practical gap count to verify gas is within block limits.
**Warning signs:** `advanceGame` reverts with out-of-gas after a long stall.

### Pitfall 2: Orphaned Lootbox Index After Swap When lootboxRngIndex == 1
**What goes wrong:** `_backfillOrphanedLootboxIndices` has an early return: `if (idx <= 1) return`. If the game has only ever made 1 VRF request (lootboxRngIndex == 1 initially, incremented to 2 on first request), the backfill would scan index 1. But if no request was ever made (still at 1), it returns immediately.
**Why it happens:** `lootboxRngIndex` starts at 1 (initialized in Storage line 1299). The `<= 1` guard handles the case where no lootbox round has ever been reserved.
**How to avoid:** Test the boundary condition: coordinator swap at lootboxRngIndex == 1 (no prior VRF) and at lootboxRngIndex == 2 (one prior VRF, potentially orphaned).
**Warning signs:** `_backfillOrphanedLootboxIndices` silently does nothing when it should fill an orphaned index.

### Pitfall 3: prevrandao Manipulation on L2
**What goes wrong:** On L2 (Base), the sequencer controls `block.prevrandao`. The gameover fallback path uses prevrandao in `_getHistoricalRngFallback`.
**Why it happens:** Base L2 sequencer can set prevrandao to any value.
**How to avoid:** Document as known design trade-off. The 5 committed VRF words provide the bulk of entropy; prevrandao is supplementary. At gameover, the economic impact is bounded.
**Warning signs:** Identical prevrandao values across multiple blocks.

### Pitfall 4: resolveRedemptionPeriod Timing During Multi-Day Gap
**What goes wrong:** A player submits a gambling burn during a stall, expecting resolution on the next day. Gap days do NOT call `resolveRedemptionPeriod`. Resolution only happens when `advanceGame` processes the current day after backfill.
**Why it happens:** Backfill processes gap days with derived entropy but skips redemption resolution (documented at NatSpec lines 1429-1431).
**How to avoid:** This is correct behavior. Test that: (a) gap days do NOT call `resolveRedemptionPeriod`, and (b) the current day DOES resolve pending redemptions after backfill.
**Warning signs:** Pending redemptions stuck in unresolved state after stall recovery.

### Pitfall 5: _tryRequestRng Guard Branches Return False Silently
**What goes wrong:** `_tryRequestRng` returns `false` if VRF is not configured (coordinator == address(0), keyHash == bytes32(0), or subscriptionId == 0). The caller (`_gameOverEntropy`) then falls through to starting the fallback timer (line 928-930).
**Why it happens:** After a coordinator swap to `address(0)` (impossible via admin -- address validated), or if VRF config is cleared. In practice, the admin contract validates the new coordinator address.
**How to avoid:** Test the guard branches to verify they return `false` without reverting or corrupting state.
**Warning signs:** `_gameOverEntropy` hangs in the fallback-timer path unexpectedly.

## Code Examples

### Gap Backfill Entry Point (rngGate lines 794-807)
```solidity
// Source: contracts/modules/DegenerusGameAdvanceModule.sol lines 794-807
// Gap detection and backfill trigger
uint48 idx = dailyIdx;
if (day > idx + 1) {
    uint48 gapCount = day - idx - 1;
    _backfillGapDays(currentWord, idx + 1, day, bonusFlip);
    _backfillOrphanedLootboxIndices(currentWord);
    levelStartTime += gapCount * 1 days;
}
```

### Coordinator Swap State Reset (lines 1338-1367)
```solidity
// Source: contracts/modules/DegenerusGameAdvanceModule.sol lines 1338-1367
function updateVrfCoordinatorAndSub(
    address newCoordinator,
    uint256 newSubId,
    bytes32 newKeyHash
) external {
    if (msg.sender != ContractAddresses.ADMIN) revert E();
    vrfCoordinator = IVRFCoordinator(newCoordinator);
    vrfSubscriptionId = newSubId;
    vrfKeyHash = newKeyHash;
    rngLockedFlag = false;
    vrfRequestId = 0;
    rngRequestTime = 0;
    rngWordCurrent = 0;
    midDayTicketRngPending = false;
    // totalFlipReversals intentionally preserved
    emit VrfCoordinatorUpdated(current, newCoordinator);
}
```

### Gameover Fallback Path (lines 892-920)
```solidity
// Source: contracts/modules/DegenerusGameAdvanceModule.sol lines 892-920
if (rngRequestTime != 0) {
    uint48 elapsed = ts - rngRequestTime;
    if (elapsed >= GAMEOVER_RNG_FALLBACK_DELAY) {  // 3 days
        uint256 fallbackWord = _getHistoricalRngFallback(day);
        fallbackWord = _applyDailyRng(day, fallbackWord);
        // ... coinflip, redemption resolution, lootbox finalization
        _finalizeLootboxRng(fallbackWord);
        return fallbackWord;
    }
    return 0;  // Still waiting
}
```

### Test Pattern: Gap Backfill Entropy Uniqueness
```solidity
// Verify gap day words are unique and derived from VRF word
function test_gapBackfillEntropyUnique(uint256 vrfWord) public {
    vm.assume(vrfWord != 0);
    // Day 1: complete normally
    _completeDay(vrfWord);
    // Stall for 5 days, swap, resume
    MockVRFCoordinator newVRF = _stallAndSwap(5);
    uint256 resumeWord = uint256(keccak256(abi.encode(vrfWord, "resume")));
    _resumeAfterSwap(newVRF, resumeWord);
    // Verify all gap days have unique nonzero words
    uint256 prev;
    for (uint48 d = 2; d <= 6; d++) {
        uint256 w = game.rngWordForDay(d);
        assertTrue(w != 0, "Gap day has nonzero word");
        assertTrue(w != prev, "Gap day words are distinct");
        prev = w;
    }
}
```

### Test Pattern: Gas Profile for Gap Backfill
```solidity
// Profile gas per-iteration for gap backfill
function test_gapBackfillGasCeiling() public {
    _completeDay(0xDEAD0001);
    // Create a 30-day gap (well within death clock)
    MockVRFCoordinator newVRF = _stallAndSwap(30);
    uint256 gasBefore = gasleft();
    _resumeAfterSwap(newVRF, 0xCAFEBABE);
    uint256 gasUsed = gasBefore - gasleft();
    // 30 gap days * ~125k per iteration = ~3.75M + overhead
    assertTrue(gasUsed < 10_000_000, "Gas within block limit for 30-day gap");
}
```

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge) with Solidity 0.8.34 |
| Config file | foundry.toml |
| Quick run command | `forge test --match-path test/fuzz/VRFStallEdgeCases.t.sol -vvv` |
| Full suite command | `forge test --fuzz-runs 1000 -vvv` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| STALL-01 | Gap backfill entropy keccak256(vrfWord, gapDay) produces unique per-day words | fuzz | `forge test --match-test test_gapBackfillEntropy -vvv` | Wave 0 |
| STALL-02 | Manipulation window between VRF callback and advanceGame consumption | code analysis + unit | `forge test --match-test test_manipulationWindow -vvv` | Wave 0 |
| STALL-03 | Gap backfill gas per-iteration profiled, safe upper bound | gas-report | `forge test --match-test test_gapBackfillGas --gas-report -vvv` | Wave 0 |
| STALL-04 | Coordinator swap resets all VRF state, orphaned lootbox recovery correct | unit + fuzz | `forge test --match-test test_coordinatorSwap -vvv` | Wave 0 |
| STALL-05 | lastLootboxRngWord==0 at swap cannot produce degenerate entropy | unit | `forge test --match-test test_zeroSeed -vvv` | Wave 0 |
| STALL-06 | _getHistoricalRngFallback prevrandao + _tryRequestRng guards | unit + analysis | `forge test --match-test test_gameoverFallback -vvv` | Wave 0 |
| STALL-07 | dailyIdx vs _simulatedDayIndex consistency; resolveRedemptionPeriod timing | code analysis + unit | `forge test --match-test test_dailyIdxTiming -vvv` | Wave 0 |

### Sampling Rate
- **Per task commit:** `forge test --match-path test/fuzz/VRFStallEdgeCases.t.sol -vvv`
- **Per wave merge:** `forge test --fuzz-runs 1000 -vvv`
- **Phase gate:** Full suite green before verify

### Wave 0 Gaps
- [ ] `test/fuzz/VRFStallEdgeCases.t.sol` -- new file covering STALL-01 through STALL-07
- [ ] No new framework install needed (Foundry already configured)
- [ ] No new helpers needed (StallResilience.t.sol patterns reusable)

## Open Questions

1. **Base L2 block gas limit during gap backfill**
   - What we know: Base L2 block gas limit is 30M. Per-iteration backfill cost is ~85k-125k. 120-day max gap uses ~15M gas.
   - What's unclear: Whether Base L2 has any transaction-level gas limit lower than block gas limit.
   - Recommendation: Profile actual gas with `forge test --gas-report` for a 120-day gap. Document the result in findings.

2. **`processTicketBatch` with `lastLootboxRngWord == 0` at game start**
   - What we know: `lastLootboxRngWord` is initialized to 0. It is set to a nonzero value by `_finalizeLootboxRng` on the first day completion.
   - What's unclear: Can `processTicketBatch` run before the first day completes (while `lastLootboxRngWord` is still 0)?
   - Recommendation: Trace the ticket queue population path. Tickets are purchased via `purchaseCoin`, which calls `advanceGame` first. If no day has completed, `advanceGame` requests VRF and returns. Tickets cannot be purchased until level > 0, which requires at least one completed day. Therefore `lastLootboxRngWord` should be nonzero by the time tickets exist. Verify this assumption.

3. **Orphaned lootbox index count during stall**
   - What we know: `requestLootboxRng` requires `rngWordByDay[currentDay] != 0` (today's daily RNG recorded). During a stall, `advanceGame` cannot complete, so no daily RNG is recorded. Therefore `requestLootboxRng` cannot fire during a stall.
   - What's unclear: Can there be more than 1 orphaned index after a stall (the one from the daily request that stalled)?
   - Recommendation: The maximum orphaned indices is 1 (the daily request in-flight when stall began). Mid-day requests cannot fire during stall. Verify with test.

## Sources

### Primary (HIGH confidence)
- contracts/modules/DegenerusGameAdvanceModule.sol lines 764-1511 -- All VRF, backfill, coordinator swap, gameover logic
- contracts/StakedDegenerusStonk.sol lines 530-563, 700-717 -- resolveRedemptionPeriod, _submitGamblingClaimFrom timing
- contracts/BurnieCoinflip.sol lines 778-840 -- processCoinflipPayouts gas analysis
- contracts/libraries/GameTimeLib.sol -- Day index computation from timestamp
- contracts/storage/DegenerusGameStorage.sol -- Complete state variable inventory
- contracts/DegenerusGame.sol lines 506-508 -- currentDayView implementation
- audit/v3.6-findings-consolidated.md -- Prior v3.6 VRF stall resilience audit (0 HIGH/MEDIUM/LOW)
- audit/v3.7-vrf-core-findings.md -- Phase 63 VRF core findings (V37-001 deferred _tryRequestRng)
- audit/v3.7-lootbox-rng-findings.md -- Phase 64 lootbox findings (V37-003 missing zero guard, V37-004 lastLootboxRngWord design)
- audit/gas-ceiling-analysis.md -- Prior v3.5 gas ceiling methodology
- .planning/phases/63-vrf-request-fulfillment-core/63-RESEARCH.md -- VRF state variable inventory, callback gas analysis
- .planning/phases/64-lootbox-rng-lifecycle/64-RESEARCH.md -- Lootbox index mutation sites, write sites, zero-state guards

### Secondary (MEDIUM confidence)
- None. All findings verified against source code.

### Tertiary (LOW confidence)
- None. All findings verified against source code.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All infrastructure already exists in repo
- Gap backfill entropy: HIGH - Complete code read, keccak256 preimage analysis verified
- Gas ceiling: MEDIUM - Opcode-level estimates need Foundry gas-report validation; processCoinflipPayouts cost is estimated, not measured
- Coordinator swap: HIGH - Variable-by-variable audit against storage layout
- Zero-seed edge case: HIGH - Full trace of lastLootboxRngWord consumption paths
- Gameover fallback: HIGH - Complete code read of _gameOverEntropy, _getHistoricalRngFallback, _tryRequestRng
- dailyIdx timing: HIGH - All block.timestamp and dailyIdx usages in AdvanceModule, DegenerusGame, and sDGNRS audited

**Research date:** 2026-03-22
**Valid until:** Indefinite (auditing fixed codebase, not evolving API)
