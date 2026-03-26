# Phase 71: advanceGame Day RNG Window - Research

**Researched:** 2026-03-22
**Domain:** Smart contract audit -- daily VRF word flow, commitment window analysis, cross-day contamination
**Confidence:** HIGH

## Summary

Phase 71 is a pure audit/documentation phase. The deliverable is a markdown document that traces how the daily VRF random word flows from `rawFulfillRandomWords` through every downstream consumer in `advanceGame`, proves the commitment window is safe, and proves no cross-day state contamination exists.

Phase 68 already cataloged all 51 VRF-touched variables with forward/backward traces. Phase 69 rendered 51/51 SAFE verdicts with an exhaustive cross-reference proof. Phase 71 takes a narrower, deeper view: specifically tracing the **daily** VRF word (as distinct from mid-day lootbox RNG) through its complete consumption chain, mapping the commitment window specific to `advanceGame`, and proving that day N processing cannot contaminate day N+1 outcomes.

**Primary recommendation:** Structure the audit document around three artifacts: (1) a data dependency graph of the daily VRF word flow, (2) a commitment window table for advanceGame-specific state, (3) a cross-day boundary analysis proving isolation. Leverage Phase 68/69's existing inventory rather than re-deriving it -- this phase adds the temporal/flow dimension missing from the per-variable verdicts.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DAYRNG-01 | Daily VRF word flow traced through all consumers: jackpot selection, lootbox index assignment, coinflip resolution, with data dependency graph | The full consumer chain is documented in sections 1.1-1.18 of the Phase 68 inventory. Research below maps the exact flow path, bit allocation, and derivation at each consumer. |
| DAYRNG-02 | Commitment window for advanceGame: what state can change between VRF request (in advanceGame) and fulfillment that affects outcome selection | Phase 69 proved 51/51 SAFE. This phase narrows to the advanceGame-specific window and catalogs what permissionless actions are possible between `_requestRng` and `rawFulfillRandomWords` return. |
| DAYRNG-03 | Cross-day carry-over analysis: verify day N pending state doesn't leak into or contaminate day N+1 RNG outcomes | Research below documents `_unlockRng` reset semantics, `rngWordByDay` immutability, `dailyIdx` gating, and the key isolation boundaries. |
</phase_requirements>

## Architecture Patterns

### Daily VRF Word Lifecycle (DAYRNG-01 core)

The daily VRF word follows this exact flow through advanceGame:

```
1. advanceGame() called by any user (permissionless)
   |
2. rngGate() entered
   |-- rngWordByDay[day] != 0 ? => return cached (already processed today)
   |-- rngWordCurrent != 0 && rngRequestTime != 0 ? => VRF word ready, process
   |-- else => _requestRng() -> _swapAndFreeze() -> return 1 (sentinel)
   |
3. On first new-day call: _requestRng() fires
   |-- VRF coordinator.requestRandomWords() called
   |-- _finalizeRngRequest() sets: rngLockedFlag=true, lootboxRngIndex++,
   |   vrfRequestId=id, rngRequestTime=now
   |-- _swapAndFreeze() swaps ticket double-buffer, activates prizePoolFrozen
   |
4. rawFulfillRandomWords() callback from VRF coordinator
   |-- validates msg.sender == vrfCoordinator, requestId match
   |-- rngLockedFlag == true => stores rngWordCurrent = word (daily path)
   |
5. Next advanceGame() call enters rngGate(), finds rngWordCurrent != 0
   |-- Gap day handling (if day > dailyIdx + 1): _backfillGapDays, _backfillOrphanedLootboxIndices
   |-- _applyDailyRng(day, rawWord): adds totalFlipReversals, stores to rngWordByDay[day]
   |
6. Consumers receive the finalized daily word:
   |
   |-- coinflip.processCoinflipPayouts(bonusFlip, currentWord, day)
   |     bit 0: win/loss (rngWord & 1)
   |     full word: keccak256(rngWord, epoch) => rewardPercent (% 20)
   |
   |-- sdgnrs.resolveRedemptionPeriod(roll, flipDay)
   |     bits 8+: redemptionRoll = ((currentWord >> 8) % 151) + 25
   |
   |-- _finalizeLootboxRng(currentWord)
   |     full word: stored as lootboxRngWordByIndex[index]
   |
   |-- return currentWord to advanceGame caller
   |
7. advanceGame uses returned word for:
   |-- payDailyJackpot(isDaily, lvl, rngWord)
   |     full word: _rollWinningTraits, _dailyCurrentPoolBps, winner index selection
   |-- _payDailyCoinJackpot(lvl, rngWord)
   |     full word: trait/winner selection for BURNIE jackpot
   |-- _applyTimeBasedFutureTake(ts, lvl, rngWord) [on lastPurchaseDay]
   |     full word: additive random BPS, variance rolls
   |-- _consolidatePrizePools(lvl, rngWord) [on lastPurchaseDay]
   |     full word: future keep BPS, yield distribution
   |-- payDailyJackpotCoinAndTickets(rngWord)
   |     full word: coin+ticket distribution
   |-- _runRewardJackpots(lvl, rngWord) [on final jackpot day]
   |     full word: BAF/Decimator jackpot winner selection
   |
8. After all processing: _unlockRng(day)
   |-- dailyIdx = day
   |-- rngLockedFlag = false
   |-- rngWordCurrent = 0, vrfRequestId = 0, rngRequestTime = 0
```

### Bit Allocation Map (from AdvanceModule lines 746-763)

| Bit(s) | Consumer | Operation | Location |
|--------|----------|-----------|----------|
| 0 | Coinflip win/loss | `rngWord & 1` | BurnieCoinflip.sol:810 |
| 8+ | Redemption roll | `(currentWord >> 8) % 151 + 25` | AdvanceModule.sol:804-805 |
| full | Coinflip reward percent | `keccak256(rngWord, epoch) % 20` | BurnieCoinflip.sol:784 |
| full | Jackpot winner selection | delegatecall (full word) | JackpotModule |
| full | Coin jackpot | delegatecall (full word) | JackpotModule |
| full | Lootbox RNG | stored as `lootboxRngWordByIndex` | AdvanceModule:843-848 |
| full | Future take variance | `rngWord % (variance * 2 + 1)` | AdvanceModule:1066 |
| full | Prize pool consolidation | delegatecall (full word) | JackpotModule |
| full | Reward jackpots | delegatecall (full word) | EndgameModule |

"Full" consumers use keccak mixing or modular arithmetic on the full 256-bit word. No bit-level collision concern exists between the bit-0 and bit-8+ direct consumers and the "full" consumers because the latter hash or mod the entire word.

### advanceGame Commitment Window (DAYRNG-02 core)

The commitment window opens when `_requestRng` is called (which sets `rngLockedFlag = true`) and closes when `_unlockRng` is called after all daily processing.

**Timeline:**
```
    advanceGame() call N          VRF callback           advanceGame() call N+1
    |                             |                      |
    _requestRng()                 rawFulfillRandomWords   rngGate() processes word
    _swapAndFreeze()              stores rngWordCurrent   _applyDailyRng()
    rngLockedFlag = true          (word != 0 now)         consumers fire
    prizePoolFrozen = true                                _unlockRng()
    |<--- COMMITMENT WINDOW --->|<--- PROCESSING ------->|
    |   VRF in-flight            word stored but not      word consumed,
    |   no word yet              yet consumed             state reset
```

**What can change during the commitment window (between `_requestRng` and `rawFulfillRandomWords`):**

Phase 69 proved all 87 permissionless paths SAFE via 7 protection mechanisms. For the advanceGame daily window specifically:

| Permissionless Action | State Written | Why SAFE |
|----------------------|---------------|----------|
| purchase() / purchaseCoin() | ticketQueue[WRITE slot] | Double-buffer: read slot frozen at swap time |
| purchase() / purchaseCoin() | prizePoolPendingPacked | Frozen: goes to pending accumulators, not live pools |
| purchase() / purchaseCoin() | prizePoolsPacked (future) | Future pool not read during outcome computation for this day |
| purchase() / purchaseCoin() | lootboxEth/Day/Base[NEXT index] | Index-keyed: lootboxRngIndex already incremented, new purchases target next index |
| reverseFlip() | totalFlipReversals | rngLockedFlag guard: reverts with RngLocked() |
| depositCoinflip() | coinflipBalance[epoch+1] | Day-keyed: deposits target future day (epoch = today+1 at minimum), current day already has its coinflip resolved |
| burn() / burnWrapped() (sDGNRS) | pendingRedemption* vars | rngLockedFlag guard: `game.rngLocked()` check reverts with BurnsBlockedDuringRng |
| placeFullTicketBets() | degeneretteBets, pool vars | Index-keyed: bet records current lootboxRngIndex (already incremented) |
| setAutoRebuy() | autoRebuyState | Outcome-irrelevant: affects payout routing, not winner selection |
| claimWinnings() | claimableWinnings | Outcome-irrelevant: post-determination claim |

**What can change between `rawFulfillRandomWords` and the next `advanceGame` processing call:**

This is a subtle sub-window. After VRF stores `rngWordCurrent`, but before the next `advanceGame` call processes it, ALL of the above actions remain possible (rngLockedFlag is still true). The processing does not happen until a user calls `advanceGame()` again. However, this is safe because:
- `rngWordCurrent` is already committed (VRF word stored)
- `_applyDailyRng` reads `totalFlipReversals` which is frozen by rngLockedFlag
- All consumer reads use the committed word, not any state written after fulfillment

### Cross-Day Boundary Analysis (DAYRNG-03 core)

**Day transition mechanism:**

```
_unlockRng(day):
    dailyIdx = day          // Advances the monotonic day counter
    rngLockedFlag = false   // Allows new reverseFlip/burns
    rngWordCurrent = 0      // Clears consumed word
    vrfRequestId = 0        // Clears VRF request state
    rngRequestTime = 0      // Clears request timestamp
```

**Key isolation boundaries:**

1. **`rngWordByDay[day]` is immutable after write.** Written once by `_applyDailyRng` (line 1533). The rngGate early-return check `if (rngWordByDay[day] != 0) return rngWordByDay[day]` (line 776) prevents reprocessing. No mutation path exists post-write.

2. **`dailyIdx` gates new-day detection.** advanceGame checks `if (day == dailyIdx)` (line 154) to detect same-day vs new-day. Same-day falls into the mid-day ticket drain path. New-day triggers the full RNG cycle. `dailyIdx` is only updated by `_unlockRng`, which runs after ALL daily processing is complete.

3. **`rngWordCurrent` is cleared to 0 by `_unlockRng`.** Day N+1's VRF request starts fresh. The VRF word from day N cannot leak forward because it is zeroed before the lock is released.

4. **`totalFlipReversals` is reset to 0 by `_applyDailyRng`.** Day N nudges are consumed and cleared. Day N+1 starts with zero nudges accumulated.

5. **Coinflip epoch keying.** `processCoinflipPayouts` receives the epoch (day index) parameter. `coinflipDayResult[epoch]` is keyed by day, preventing cross-day result collision. `coinflipBalance[epoch][player]` deposits for day N cannot affect day N+1 resolution.

6. **Lootbox index keying.** `lootboxRngIndex` is incremented at each `_finalizeRngRequest`. New purchases after day N's RNG request target the NEXT index. Day N's lootbox word is stored at `lootboxRngWordByIndex[index]` where index was frozen at request time.

7. **Redemption period isolation.** `resolveRedemptionPeriod` stores results keyed by `redemptionPeriodIndex`. The period increments at redemption resolution boundaries. Day N resolution cannot overwrite day N+1's period.

8. **Gap day handling.** If VRF stalls and day N+1 arrives without day N being processed, `_backfillGapDays` derives deterministic words from the fresh VRF word via `keccak256(vrfWord, gapDay)`. Each gap day gets its own derived word, stored to `rngWordByDay[gapDay]`. No forward contamination: the fresh VRF word is unknown at request time and each gap day's derived word is unique.

**Carry-over state that persists across days (legitimate, not contamination):**

| State | Persists Across Days? | Why Not Contamination |
|-------|----------------------|----------------------|
| `traitBurnTicket[level]` | Yes (across entire level) | Populated by processTicketBatch, frozen at swap. Accumulates across a level, not reset per day. RNG selects FROM this array, doesn't modify it. |
| `currentPrizePool` | Yes (within a level) | Accumulated pool for the level. RNG determines how much to distribute, not the pool amount itself. |
| `jackpotCounter` | Yes (within jackpot phase) | Incremented by `payDailyJackpotCoinAndTickets` each day. Determines day-within-phase, affects BPS selection. Written by game-internal path only. |
| `compressedJackpotFlag` | Yes (within jackpot phase) | Set when target reached on day 1 or 3. Read-only during jackpot processing. |
| `lastDailyJackpotWinningTraits` | Yes (within a single jackpot cycle) | Stored during payDailyJackpot Phase 1, restored during payDailyJackpotCoinAndTickets Phase 2. Both happen within the same advanceGame call chain, then cleared at next fresh jackpot. |
| `dailyEthPoolBudget` | Transient (within a single advanceGame chain) | Set at start of payDailyJackpot, consumed during the same processing chain, zeroed at completion. If advanceGame is called again (resume), it restores from stored state. |

None of these carry-over items allow day N's RNG outcome to influence day N+1's RNG word selection. The VRF word is externally sourced and unknown until fulfillment. Carry-over state affects what the RNG word is applied TO (pool sizes, ticket arrays, counter positions), but not the RNG word itself or how it selects outcomes.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Data dependency graph | Custom visualization tool | ASCII/markdown flow diagram as in Phase 68 inventory format | Audit document, not executable artifact |
| Variable inventory | New catalog from scratch | Phase 68/69 inventory (`audit/v3.8-commitment-window-inventory.md`) | Already contains all 51 variables with slots, mutations, and verdicts |
| Protection mechanism proof | New analysis | Phase 69 CW-04 proof (87 paths enumerated) | Exhaustive proof already exists; Phase 71 narrows to daily-specific perspective |

## Common Pitfalls

### Pitfall 1: Confusing Daily vs Mid-Day VRF Paths
**What goes wrong:** Treating all VRF fulfillment paths as identical when the daily path (rngLockedFlag=true) and mid-day lootbox path (rngLockedFlag=false) have different state machines and different consumers.
**Why it happens:** Both enter through `rawFulfillRandomWords`, but branch on `rngLockedFlag`.
**How to avoid:** The data dependency graph MUST show both paths distinctly. Daily path: stores `rngWordCurrent`, consumed by next `advanceGame`. Mid-day path: directly stores `lootboxRngWordByIndex[index]`, no advanceGame needed.
**Warning signs:** Analyzing mid-day consumers (lootbox index assignment) as if they use the daily word path.

### Pitfall 2: Missing the Sub-Window Between VRF Fulfillment and Processing
**What goes wrong:** Only analyzing the request-to-fulfillment window, missing that the word sits in `rngWordCurrent` until a user calls `advanceGame` again.
**Why it happens:** Standard commitment window analysis focuses on request-to-callback. Here, callback stores the word but does NOT process it -- processing requires another external call.
**How to avoid:** Explicitly address both sub-windows: (a) request to fulfillment, (b) fulfillment to processing. Both must be proven safe.
**Warning signs:** No mention of what happens if `rngWordCurrent != 0` but no one calls `advanceGame` for hours.

### Pitfall 3: Overlooking Gap Day Contamination
**What goes wrong:** Assuming VRF delivers one word per day and missing the gap day backfill path where a single VRF word generates multiple derived day words.
**Why it happens:** Gap days are an edge case triggered by VRF stalls (Chainlink downtime, LINK depletion).
**How to avoid:** The cross-day analysis MUST address `_backfillGapDays` and `_backfillOrphanedLootboxIndices` explicitly, showing that derived words are deterministic from the fresh VRF word and cannot be manipulated.
**Warning signs:** Cross-day analysis that only considers the one-day-at-a-time happy path.

### Pitfall 4: Confusing "State Persists Across Days" with "State Contaminates Days"
**What goes wrong:** Flagging legitimate carry-over state (traitBurnTicket, currentPrizePool, jackpotCounter) as cross-day contamination when it is part of normal game mechanics.
**Why it happens:** The requirement says "day N pending state doesn't leak into day N+1 RNG outcomes." State that persists across days (like the prize pool) is not contamination -- it is the game state the RNG operates on.
**How to avoid:** Define contamination precisely: day N's RNG OUTCOME (the specific random selections made) influencing day N+1's RNG WORD or OUTCOME SELECTION. Carry-over game state is the input context, not a contamination vector.
**Warning signs:** Flagging currentPrizePool persistence as a finding.

## Code Examples

### rngGate Flow (AdvanceModule lines 768-841)
```solidity
// Source: contracts/modules/DegenerusGameAdvanceModule.sol:768-841
function rngGate(...) internal returns (uint256 word) {
    // Already processed today? Return cached word.
    if (rngWordByDay[day] != 0) return rngWordByDay[day];

    uint256 currentWord = rngWordCurrent;
    // VRF word ready?
    if (currentWord != 0 && rngRequestTime != 0) {
        // Gap day backfill if needed
        if (day > idx + 1) {
            _backfillGapDays(currentWord, idx + 1, day, bonusFlip);
            _backfillOrphanedLootboxIndices(currentWord);
            levelStartTime += gapCount * 1 days;
        }
        // Apply nudges, store final word
        currentWord = _applyDailyRng(day, currentWord);
        // Consumers:
        coinflip.processCoinflipPayouts(bonusFlip, currentWord, day);
        // ... redemption resolution
        _finalizeLootboxRng(currentWord);
        return currentWord;
    }
    // No word yet: request or wait
    _requestRng(isTicketJackpotDay, lvl);
    return 1; // sentinel
}
```

### _unlockRng Reset (AdvanceModule lines 1409-1415)
```solidity
// Source: contracts/modules/DegenerusGameAdvanceModule.sol:1409-1415
function _unlockRng(uint48 day) private {
    dailyIdx = day;           // Advance day counter
    rngLockedFlag = false;    // Release lock
    rngWordCurrent = 0;       // Clear consumed word
    vrfRequestId = 0;         // Clear request state
    rngRequestTime = 0;       // Clear request time
}
```

### _applyDailyRng Nudge Application (AdvanceModule lines 1520-1536)
```solidity
// Source: contracts/modules/DegenerusGameAdvanceModule.sol:1520-1536
function _applyDailyRng(uint48 day, uint256 rawWord) private returns (uint256 finalWord) {
    uint256 nudges = totalFlipReversals;
    finalWord = rawWord;
    if (nudges != 0) {
        unchecked { finalWord += nudges; }
        totalFlipReversals = 0;  // Consumed and cleared
    }
    rngWordCurrent = finalWord;
    rngWordByDay[day] = finalWord;  // Immutable archive
    lastVrfProcessedTimestamp = uint48(block.timestamp);
}
```

### Day Index Calculation (GameTimeLib)
```solidity
// Source: contracts/libraries/GameTimeLib.sol:31-34
function currentDayIndexAt(uint48 ts) internal pure returns (uint48) {
    uint48 currentDayBoundary = uint48((ts - JACKPOT_RESET_TIME) / 1 days);
    return currentDayBoundary - ContractAddresses.DEPLOY_DAY_BOUNDARY + 1;
}
// JACKPOT_RESET_TIME = 82620 (22:57 UTC)
// Days reset at 22:57 UTC, Day 1 = deploy day
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Phase 68-69: per-variable verdicts | Phase 71: temporal flow analysis | This phase | Adds flow dimension to static inventory |
| Single commitment window | Dual-window (daily + mid-day) analysis | Phase 68-69 established | Both windows must be addressed separately |
| Assume one-day-at-a-time | Gap day backfill path | v3.6 (stall resilience) | Gap days derive words from fresh VRF, not predictable state |

## Open Questions

1. **depositCoinflip() during commitment window targets which epoch?**
   - What we know: `_addDailyFlip` in BurnieCoinflip adds to `coinflipBalance[day][player]` where `day` is calculated from `block.timestamp`. The `rngLockedFlag` does NOT gate `depositCoinflip` -- there is no rngLocked check in BurnieCoinflip.
   - What's unclear: If a player deposits a coinflip during the daily commitment window, does the deposit target the current day (whose outcome is being determined) or the next day?
   - Recommendation: The audit document must trace the exact epoch calculation in `_addDailyFlip` / `_depositCoinflip` to prove that deposits during the window target a future day (not the day being resolved). Phase 69 verdict #43 says "Day-keyed temporal separation" -- this must be verified with code citations.

2. **Is `_swapAndFreeze` always called before `_requestRng` in all code paths?**
   - What we know: In the normal advanceGame flow, `_swapAndFreeze(purchaseLevel)` is called at line 233, immediately after `rngGate` returns 1 (sentinel for request). The `_requestRng` call happens inside `rngGate`.
   - What's unclear: The `rngGate` function calls `_requestRng` directly at line 839. The `_swapAndFreeze` is called AFTER `rngGate` returns at line 233. This means `_requestRng` fires BEFORE `_swapAndFreeze`.
   - Recommendation: Verify the exact ordering: `rngGate -> _requestRng -> return 1 -> advanceGame calls _swapAndFreeze`. The ticket buffer swap happens AFTER the VRF request, but rngLockedFlag is set true inside `_finalizeRngRequest` (called by `_requestRng`), so reverseFlip and burns are already blocked when `_swapAndFreeze` runs. The audit must note this ordering explicitly.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Hardhat + Foundry (dual) |
| Config file | `hardhat.config.js` / `foundry.toml` |
| Quick run command | N/A (audit-only phase, no code changes) |
| Full suite command | N/A |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DAYRNG-01 | Daily VRF word flow data dependency graph | manual-only | N/A -- audit document deliverable | N/A |
| DAYRNG-02 | Commitment window state-change analysis | manual-only | N/A -- audit document deliverable | N/A |
| DAYRNG-03 | Cross-day carry-over proof | manual-only | N/A -- audit document deliverable | N/A |

**Justification for manual-only:** This is an audit/analysis phase. The deliverable is a markdown document containing traced analysis with code citations. No code is modified. Verification means checking that the document correctly cites contract code and the logic chains are sound.

### Wave 0 Gaps
None -- existing test infrastructure covers code correctness. This phase produces documentation, not code changes.

## Key Contracts and Line References

| Contract | File | Key Functions | Relevant Lines |
|----------|------|---------------|----------------|
| AdvanceModule | `contracts/modules/DegenerusGameAdvanceModule.sol` | `advanceGame`, `rngGate`, `_requestRng`, `_finalizeRngRequest`, `rawFulfillRandomWords`, `_applyDailyRng`, `_unlockRng`, `_backfillGapDays`, `_backfillOrphanedLootboxIndices`, `_finalizeLootboxRng`, `requestLootboxRng`, `reverseFlip` | 125-385 (advanceGame), 677-744 (requestLootboxRng), 746-763 (bit allocation), 768-841 (rngGate), 1261-1367 (_requestRng/_finalizeRngRequest), 1409-1415 (_unlockRng), 1439-1460 (rawFulfillRandomWords), 1462-1517 (backfill), 1520-1536 (_applyDailyRng) |
| BurnieCoinflip | `contracts/BurnieCoinflip.sol` | `processCoinflipPayouts` | 778-862 |
| StakedDegenerusStonk | `contracts/StakedDegenerusStonk.sol` | `resolveRedemptionPeriod` | 540-565 |
| JackpotModule | `contracts/modules/DegenerusGameJackpotModule.sol` | `payDailyJackpot`, `payDailyJackpotCoinAndTickets` | 323-522, 681-766 |
| GameTimeLib | `contracts/libraries/GameTimeLib.sol` | `currentDayIndexAt` | 31-34 |
| DegenerusGameStorage | `contracts/storage/DegenerusGameStorage.sol` | `_swapTicketSlot`, `_swapAndFreeze`, `_unlockRng` state vars | 713-729 |

## Upstream Dependencies

| Artifact | Location | What This Phase Uses From It |
|----------|----------|------------------------------|
| Phase 68 Forward+Backward Trace | `audit/v3.8-commitment-window-inventory.md` sections 1.1-1.18, Cat 1-7 | All 51 variables with slots, contracts, purposes, function chains |
| Phase 69 Mutation Verdicts | `audit/v3.8-commitment-window-inventory.md` Verdict Summary + CW-04 Proof | 51/51 SAFE verdicts, 87 permissionless paths enumerated, 7 protection mechanisms |
| Bit Allocation Map | `contracts/modules/DegenerusGameAdvanceModule.sol` lines 746-763 | How daily VRF word bits are consumed by each downstream consumer |

## Sources

### Primary (HIGH confidence)
- `contracts/modules/DegenerusGameAdvanceModule.sol` -- advanceGame, rngGate, rawFulfillRandomWords, _applyDailyRng, _unlockRng, all VRF lifecycle functions (direct code reading)
- `contracts/BurnieCoinflip.sol` -- processCoinflipPayouts, coinflip resolution logic (direct code reading)
- `contracts/StakedDegenerusStonk.sol` -- resolveRedemptionPeriod (direct code reading)
- `contracts/modules/DegenerusGameJackpotModule.sol` -- payDailyJackpot, payDailyJackpotCoinAndTickets (direct code reading)
- `contracts/storage/DegenerusGameStorage.sol` -- storage layout, _swapTicketSlot, _swapAndFreeze (direct code reading)
- `contracts/libraries/GameTimeLib.sol` -- day index calculation (direct code reading)
- `audit/v3.8-commitment-window-inventory.md` -- Phase 68/69 complete inventory with forward trace, backward trace, mutation surface, verdicts, and CW-04 proof

### Secondary (MEDIUM confidence)
- Phase 69 summary (`.planning/phases/69-mutation-verdicts/69-02-SUMMARY.md`) -- confirms 87 paths enumerated with 7 protection mechanisms

## Metadata

**Confidence breakdown:**
- Daily VRF flow: HIGH - traced directly from contract code, all function chains verified
- Commitment window analysis: HIGH - builds on Phase 69's exhaustive 51/51 SAFE proof, narrows to advanceGame-specific window
- Cross-day boundary analysis: HIGH - _unlockRng reset semantics, rngWordByDay immutability, and dailyIdx gating all verified from code
- Open questions: MEDIUM - depositCoinflip epoch targeting and _swapAndFreeze ordering need verification in audit document

**Research date:** 2026-03-22
**Valid until:** 2026-04-22 (stable - auditing existing deployed contract code)
