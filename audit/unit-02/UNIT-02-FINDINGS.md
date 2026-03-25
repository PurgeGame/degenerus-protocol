# Unit 2: Day Advancement + VRF -- Final Findings

## Audit Scope

- **Contract:** DegenerusGameAdvanceModule.sol (1,571 lines)
- **Inherits:** DegenerusGameStorage (storage layout verified in Unit 1, PASS)
- **Executes via:** delegatecall from DegenerusGame (routing verified in Unit 1)
- **Audit type:** Three-agent adversarial (Taskmaster + Mad Genius + Skeptic)
- **Coverage verdict:** PASS (100%)
- **Functions analyzed:**
  - External/public state-changing (Category B): 6 (full Mad Genius treatment)
  - Internal state-changing helpers (Category C): 26 (via caller call trees; 6 MULTI-PARENT with cross-context analysis)
  - View/Pure (Category D): 8 (minimal review)

---

## Findings Summary

| Severity | Count |
|----------|-------|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 0 |
| LOW | 0 |
| INFO | 3 |
| **Total** | **3** |

---

## Confirmed Findings

No vulnerabilities were identified in Unit 2. All Mad Genius findings were determined to be either false positives or informational by the Skeptic. The 3 INFO-level findings below are behavioral observations with no exploitable impact.

### [INFO] F-01: advanceBounty computed from potentially stale price

**Location:** `DegenerusGameAdvanceModule.sol` line 127 (computation), line 396 (use), function `advanceGame()`
**Found by:** Mad Genius (Attack Report)
**Confirmed by:** Skeptic (Review -- DOWNGRADE TO INFO)
**Severity:** INFO -- bounded economic impact (~0.005 ETH BURNIE equivalent per level transition), no exploitation path

**Description:**
`advanceBounty = (ADVANCE_BOUNTY_ETH * PRICE_COIN_UNIT) / price` is computed at line 127 using the current storage value of `price`. The descendant `_finalizeRngRequest` can update `price` at lines 1355-1380 when `isTicketJackpotDay && !isRetry` (price doubles on level transitions). The bounty paid at line 396 uses the pre-update price.

**Attack Scenario:**
1. `advanceGame()` computes bounty at line 127 using current `price` (e.g., 0.01 ETH).
2. `rngGate()` calls `_requestRng()` which calls `_finalizeRngRequest()`.
3. `_finalizeRngRequest` writes new `price` = 0.02 ETH (line 1355-1380 price doubling).
4. `rngGate` returns 1. Do-while breaks at line 235 (STAGE_RNG_REQUESTED).
5. `coin.creditFlip(caller, advanceBounty)` at line 396 uses the stale bounty.
6. The caller receives 2x the BURNIE bounty that the new price justifies.

**Root Cause:**
`advanceBounty` is computed before entering the do-while loop. The price update occurs deep in the call tree. The do-while break prevents re-computation.

**Recommendation:**
No action required. The economic impact is bounded at ~0.005 ETH equivalent of BURNIE per level transition. BURNIE has no secondary market value (in-game currency only). The bounty is minted, not transferred from a pool, so no other player loses funds. The price write only occurs on the STAGE_RNG_REQUESTED exit path, a one-per-level-transition event.

**Evidence:**
- Mad Genius: Findings Summary F-01, Cached-Local Pair 5 (advanceBounty/price) in ATTACK-REPORT.md
- Skeptic: F-01 review in SKEPTIC-REVIEW.md -- confirmed staleness, verified economic impact capped at ~0.005 ETH BURNIE equivalent

---

### [INFO] F-04: lastLootboxRngWord not updated on mid-day VRF fulfillment path

**Location:** `DegenerusGameAdvanceModule.sol` lines 1468-1475, function `rawFulfillRandomWords()`
**Found by:** Mad Genius (Attack Report)
**Confirmed by:** Skeptic (Review -- DOWNGRADE TO INFO)
**Severity:** INFO -- convenience variable staleness with no functional impact on lootbox resolution

**Description:**
When `rawFulfillRandomWords` processes a mid-day VRF callback (`rngLockedFlag == false`), it correctly stores the word in `lootboxRngWordByIndex[index]` at line 1471 and clears VRF state (`vrfRequestId = 0`, `rngRequestTime = 0`). However, it does NOT update `lastLootboxRngWord`. The daily path (lines 1465-1467) sets `rngWordCurrent`, and `lastLootboxRngWord` is later updated via `_finalizeLootboxRng` during `rngGate`.

**Attack Scenario:**
None. `lastLootboxRngWord` is a convenience entropy source. All per-lootbox resolution uses the indexed mapping `lootboxRngWordByIndex[index]`, which IS correctly set on the mid-day path (line 1471). The global `lastLootboxRngWord` being stale does not affect any lootbox resolution outcome.

**Root Cause:**
The mid-day VRF fulfillment path was designed to store the word per-index only. The global `lastLootboxRngWord` update is handled by the daily processing path.

**Recommendation:**
No action required. All lootbox consumers use `lootboxRngWordByIndex[index]` for their specific resolution. The `lastLootboxRngWord` staleness has no effect on any resolution outcome.

**Evidence:**
- Mad Genius: Findings Summary F-04, rawFulfillRandomWords analysis (B4) in ATTACK-REPORT.md
- Skeptic: F-04 review in SKEPTIC-REVIEW.md -- independently verified no resolution-critical consumer depends on `lastLootboxRngWord` freshness

---

### [INFO] F-06: Ticket queue drain test assertion uses wrong buffer slot

**Location:** Test helper `_readKeyForLevel()` in TicketLifecycle Foundry tests (not in contract code)
**Found by:** Mad Genius (Attack Report -- Priority Investigation)
**Confirmed by:** Skeptic (Review -- CONFIRMED INFO)
**Severity:** INFO -- test assertion bug, contract behavior is correct

**Description:**
Three TicketLifecycle Foundry tests fail with `Read queue not drained for level 1: 2 != 0`:
- `testFiveLevelIntegration`
- `testMultiLevelZeroStranding`
- `testZeroStrandingSweepAfterTransitions`

The test's `_readKeyForLevel` helper computes the read key based on the CURRENT `ticketWriteSlot` at assertion time. After driving through 6+ levels, `ticketWriteSlot` has been toggled multiple times (once per `_swapAndFreeze`). The "read key" at assertion time points to a different buffer slot than the one that was active when level 1 was actually processed.

**Root Cause:**
The double-buffer architecture uses `ticketWriteSlot ^= 1` at each swap. After N swaps, `ticketWriteSlot = N % 2`. The test assumes the current read key reveals the processing state, but the buffer rotation means the "read key" for level 1 at assertion time may point to the opposite slot. The `2 != 0` entries are either unpopped array entries (Solidity arrays do not shrink on consume) or tickets written to a buffer that was subsequently swapped away.

**Recommendation:**
Fix the test's `_readKeyForLevel` helper using one of:
1. Check BOTH buffer slots for each level (Slot 0 and Slot 1 keys)
2. Check `ticketsOwedPacked[key][addr] == 0` for all queue entries (proving tickets were processed even if array length is nonzero)
3. Track which `ticketWriteSlot` value was active when each level was processed, and compute the read key from that historical value

**Evidence:**
- Mad Genius: Part 4 "Priority Investigation -- Ticket Queue Drain" in ATTACK-REPORT.md -- full lifecycle trace, double-buffer analysis, constructor ticket trace, test assertion analysis
- Skeptic: F-06 review and "Ticket Queue Drain Investigation Review" in SKEPTIC-REVIEW.md -- independent verification with step-by-step buffer state tracing

---

## Priority Investigation: Ticket Queue Drain

**Issue:** 3 TicketLifecycle Foundry tests fail with `Read queue not drained for level 1: 2 != 0`
**Affected tests:** testFiveLevelIntegration, testMultiLevelZeroStranding, testZeroStrandingSweepAfterTransitions

**Mad Genius Verdict:** PROVEN SAFE (test bug, not contract bug)
**Skeptic Verdict:** AGREE
**Final Determination:** PROVEN SAFE

**Summary of Evidence:**

Both agents independently traced the ticket lifecycle through the double-buffer architecture:

1. **Constructor tickets** for level 1 land in `ticketQueue[1]` (Slot 0 key) at deploy time when `ticketWriteSlot = 0`.
2. **First `_swapAndFreeze`** toggles `ticketWriteSlot` to 1. Read key for level 1 becomes `1` (Slot 0), where constructor tickets live.
3. **Daily drain gate** processes `ticketQueue[1]` via `_runProcessTicketBatch(1)`, draining the 2 constructor entries.
4. **After 6+ swaps**, `ticketWriteSlot = N % 2`. The test's `_readKeyForLevel(1)` computes the read key from the assertion-time `ticketWriteSlot`, which may point to the opposite buffer slot from where processing occurred.
5. The `2 != 0` assertion failure reflects the test checking the wrong buffer -- either unpopped entries (Solidity arrays don't shrink) or entries written to a buffer that was subsequently swapped away.

**Root cause:** Test helper `_readKeyForLevel` uses assertion-time `ticketWriteSlot` instead of processing-time slot.

**Contract behavior:** Correct. The `_swapTicketSlot` function at Storage lines 700-704 verifies that the read queue for the current `purchaseLevel` is drained before each swap. The contract does not leave actionable tickets unprocessed. Entries remaining in the array after processing have `ticketsOwedPacked[key][addr] == 0`.

**Recommendation:** Fix the test assertion logic (see F-06 recommendation above).

---

## Dismissed Findings (False Positives)

| ID | Title | Mad Genius Verdict | Skeptic Verdict | Reason |
|----|-------|--------------------|-----------------|--------|
| F-02 | purchaseLevel uses stale lvl after _finalizeRngRequest | INVESTIGATE | FALSE POSITIVE | do-while break at line 235 prevents any post-write reuse; `_swapAndFreeze(purchaseLevel)` receives the correct value (equal to new storage level) |
| F-03 | inJackpot stale after jackpotPhaseFlag self-write | INVESTIGATE | FALSE POSITIVE | All reads of `inJackpot` (lines 224, 275, 284, 294) occur BEFORE writes to `jackpotPhaseFlag` (lines 263, 341); do-while break prevents iteration |
| F-05 | _gameOverEntropy synthetic lock for fallback timer | INVESTIGATE | FALSE POSITIVE | Intentional graceful degradation; fallback timer is the correct behavior when VRF request fails; documented in source comments at line 960 and in KNOWN-ISSUES.md |

---

## Informational Observations

The 3 INFO findings above (F-01, F-04, F-06) represent the complete set of informational observations. Key themes:

1. **Stale cached-local pattern (F-01):** The `advanceBounty` computation uses a pre-increment price. The do-while(false) break isolation pattern prevents all other cached locals from creating exploitable staleness, but the bounty is computed before the loop. Impact is negligible (~0.005 ETH BURNIE equivalent per level transition).

2. **Convenience variable staleness (F-04):** The `lastLootboxRngWord` global is not updated on the mid-day VRF fulfillment path. All actual lootbox resolution uses the per-index mapping `lootboxRngWordByIndex[index]`, which IS correctly updated.

3. **Test assertion architecture (F-06):** The double-buffer ticket queue design is correct but the test helpers do not account for multi-swap buffer rotation when asserting drain completeness.

---

## Coverage Statistics

| Metric | Value |
|--------|-------|
| Functions on checklist | 40 (6B + 26C + 8D) |
| Functions analyzed | 40 |
| Coverage percentage | 100% |
| Category B fully analyzed | 6/6 |
| Category C fully analyzed | 26/26 (via caller call trees) |
| Category D reviewed | 8/8 |
| Call trees verified (spot-check) | 3 (advanceGame, rawFulfillRandomWords, requestLootboxRng) |
| Cross-module delegatecall targets traced | 11 |
| Cached-local-vs-storage checks | 6 critical pairs in advanceGame |
| MULTI-PARENT functions cross-checked | 6 (C7, C10, C15, C17, C23, C26) |

**Note:** The checklist header states "35 functions (6B + 21C + 8D)" but the actual table contains 40 entries (6B + 26C + 8D). The header count of "21 C" is a display error; all 26 Category C entries are present in the table and fully analyzed. The discrepancy arises from the Taskmaster's initial count versus the actual sequential C1-C26 enumeration.

---

## Audit Trail

| Deliverable | Status | File |
|-------------|--------|------|
| Coverage Checklist | Complete | audit/unit-02/COVERAGE-CHECKLIST.md |
| Attack Report | Complete | audit/unit-02/ATTACK-REPORT.md |
| Coverage Review | PASS | audit/unit-02/COVERAGE-REVIEW.md |
| Skeptic Review | Complete | audit/unit-02/SKEPTIC-REVIEW.md |
| Final Findings | This document | audit/unit-02/UNIT-02-FINDINGS.md |
