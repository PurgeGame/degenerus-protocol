---
phase: 99-callsite-audit
verified: 2026-03-25T15:00:00Z
status: gaps_found
score: 2/4 must-haves verified
gaps:
  - truth: "Every callsite where _processAutoRebuy (JackpotModule) can be reached during daily ETH jackpot execution is listed with its caller chain and per-execution iteration count"
    status: partial
    reason: "Callsite table lists the correct two execution paths but uses the wrong function name (_processDailyEthChunk does not exist; actual function is _processDailyEth at JM:1338) and incorrect line references. Section 2 also includes two non-existent constants (DAILY_JACKPOT_UNITS_AUTOREBUY, DAILY_JACKPOT_UNITS_SAFE) not present in the contract. The invented chunk system (unitsBudget, dailyEthBucketCursor, dailyEthWinnerCursor) does not exist in _processDailyEth."
    artifacts:
      - path: ".planning/phases/99-callsite-audit/99-01-CALLSITE-AUDIT.md"
        issue: "Uses _processDailyEthChunk throughout but actual function is _processDailyEth (JM:1338). No _processDailyEthChunk exists. Constants DAILY_JACKPOT_UNITS_AUTOREBUY and DAILY_JACKPOT_UNITS_SAFE referenced in constants table do not exist in the contract. Chunk system (unitsBudget/cursor state) is fabricated."
    missing:
      - "Replace all occurrences of _processDailyEthChunk with _processDailyEth in Section 2, Section 3, call tree diagram, and Section 6 Phase 100 Targets"
      - "Remove DAILY_JACKPOT_UNITS_AUTOREBUY (JM:167) and DAILY_JACKPOT_UNITS_SAFE (JM:164) rows from the constants table — they do not exist"
      - "Remove the Chunk System Note paragraph — _processDailyEth has no chunk system (no unitsBudget, no cursor state, no complete=false return)"
      - "Correct Phase 100 Target 3: _processDailyEthChunk -> _processDailyEth (JM:1338-1433)"
  - truth: "Every _setFuturePrizePool and _setNextPrizePool call within the _processDailyEth and _runEarlyBirdLootboxJackpot call trees is mapped with: call location, packed slot written, condition under which it fires, and write frequency"
    status: partial
    reason: "All 4 writes are identified and their conditions/frequency are correct. However, all line numbers in the CALL-02 write table are wrong. The Section 7 Verification Notes claims to document corrections but the corrections themselves are wrong — the original PLAN interfaces block had the correct line numbers."
    artifacts:
      - path: ".planning/phases/99-callsite-audit/99-01-CALLSITE-AUDIT.md"
        issue: "CALL-02 write table row 1: claims JM:807 for _setFuturePrizePool in earlybird; actual is JM:778. Row 2: claims JM:863 for _setNextPrizePool in earlybird; actual is JM:834. Row 3: claims JM:1011 for _setFuturePrizePool in _processAutoRebuy; actual is JM:982. Row 4: claims JM:1013 for _setNextPrizePool in _processAutoRebuy; actual is JM:984. Storage.sol line numbers in Section 4 (749, 761) are also off — actual is 740, 752."
    missing:
      - "Correct earlybird _setFuturePrizePool line from JM:807 to JM:778"
      - "Correct earlybird _setNextPrizePool line from JM:863 to JM:834"
      - "Correct _processAutoRebuy _setFuturePrizePool line from JM:1011 to JM:982"
      - "Correct _processAutoRebuy _setNextPrizePool line from JM:1013 to JM:984"
      - "Correct Storage.sol line references: _setNextPrizePool JM:749 -> 740, _setFuturePrizePool JM:761 -> 752"
      - "Update call tree diagram line annotations to match actual line numbers"
human_verification: []
---

# Phase 99: Callsite Audit Verification Report

**Phase Goal:** Every callsite of _processAutoRebuy and every prize pool storage write within auto-rebuy paths is fully inventoried with current behavior documented, providing a complete map before any code changes
**Verified:** 2026-03-25T15:00:00Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Every _processAutoRebuy callsite listed with caller chain and iteration count | PARTIAL | Table identifies both execution paths and earlybird non-call correctly. Core behavior is right. Function name used throughout is _processDailyEthChunk but actual function is _processDailyEth. No _processDailyEthChunk exists in contract. Chunk system invented. |
| 2 | Every _setFuturePrizePool and _setNextPrizePool call mapped with location, slot, condition, frequency | PARTIAL | All 4 write sites identified. Conditions and frequency correct. All 4 line numbers in write table are wrong (see gap detail). |
| 3 | Total SSTORE count per daily ETH jackpot execution is computed from callsite map | VERIFIED | 321 winners x 1 SSTORE each = 321 SSTOREs stated. Gas baseline of 64,200 gas (pool I/O) computed. H14 reconciliation complete. Substance is correct. |
| 4 | Earlybird path is separately quantified and distinguished from main path | VERIFIED | Section 5 (Key Finding) and Section 3 row 3 explicitly state earlybird does NOT call _processAutoRebuy. 2 fixed SSTOREs documented. Directly confirmed against contract source. |

**Score:** 2/4 truths fully verified (2 partial due to inaccurate line numbers and false function name)

---

## Critical Finding: _runEarlyBirdLootboxJackpot does NOT call _processAutoRebuy

**VERIFIED CORRECT against contracts/modules/DegenerusGameJackpotModule.sol**

The function body at JM:772-835 was read in full. The inner loop (JM:800-830) calls only `_queueTickets` (JM:819). There is no call to `_addClaimableEth` or `_processAutoRebuy` anywhere in the function body. The two pool writes are:
- `_setFuturePrizePool` at **JM:778** (not 807 as the audit doc claims)
- `_setNextPrizePool` at **JM:834** (not 863 as the audit doc claims)

The correction of the CONTEXT.md error is the most important finding of the phase and it is correct. Phase 100 batching scope limited to `_processDailyEth` only.

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.planning/phases/99-callsite-audit/99-01-CALLSITE-AUDIT.md` | Complete callsite inventory and SSTORE gas baseline | EXISTS — SUBSTANTIVE — accuracy gaps | File exists, all sections present, all required strings found. Contains inaccurate function name, fabricated chunk system, and wrong line numbers throughout. |

### Acceptance Criteria Check

| Criterion | Result |
|-----------|--------|
| File exists | PASS |
| Contains "CALL-01" | PASS |
| Contains "CALL-02" | PASS |
| Contains DAILY_ETH_MAX_WINNERS with integer value (321) | PASS |
| Contains "Phase 100 Targets" section | PASS |
| Contains "_runEarlyBirdLootboxJackpot" and "does NOT call _processAutoRebuy" | PASS |
| Contains "Batching Opportunity Summary" | PASS |
| Does NOT contain "[fill in]" or "[compute]" | PASS |

All acceptance criteria pass. The gaps are in factual accuracy of function names and line numbers — not in completeness of structure.

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `_processDailyEth` (JM:1338) | `_addClaimableEth` (JM:928) | direct call per winner at JM:1407 | VERIFIED | Confirmed in source: JM:1407 calls _addClaimableEth(w, perWinner, entropyState) |
| `_addClaimableEth` (JM:928) | `_processAutoRebuy` (JM:959) | conditional !gameOver && autoRebuyEnabled at JM:937-942 | VERIFIED | Confirmed in source: JM:937-942 |
| `_processAutoRebuy` (JM:959) | `_setFuturePrizePool` / `_setNextPrizePool` | calc.toFuture branch at JM:981-984 | VERIFIED | Confirmed in source: JM:981-984 with correct lines 982/984 (not 1011/1013 as doc claims) |
| `_runEarlyBirdLootboxJackpot` | `_processAutoRebuy` | — | VERIFIED NOT WIRED | Confirmed: no call path exists. earlybird calls _queueTickets only. |

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| CALL-01 | 99-01-PLAN.md | Every callsite of _processAutoRebuy inventoried with current prize pool write behavior | PARTIAL | Callsite table identifies all paths. Core behavior documented correctly. Wrong function name (_processDailyEthChunk) and non-existent constants undermine document accuracy as a baseline for Phase 100. |
| CALL-02 | 99-01-PLAN.md | Every callsite of _setFuturePrizePool and _setNextPrizePool within auto-rebuy paths mapped | PARTIAL | All 4 write sites identified with correct conditions and frequency. All line numbers in the write table are wrong. |

REQUIREMENTS.md marks both CALL-01 and CALL-02 as complete (checkboxes ticked). Based on actual codebase verification, the substance is there but the reference accuracy is insufficient for use as a pre-change baseline without corrections.

No orphaned requirements: REQUIREMENTS.md Traceability table maps only CALL-01 and CALL-02 to Phase 99, matching the plan frontmatter exactly.

---

## Anti-Patterns Found

| File | Item | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| 99-01-CALLSITE-AUDIT.md | Throughout | Nonexistent function name `_processDailyEthChunk` used in place of actual `_processDailyEth` | Blocker | Phase 100 implementer directed to the wrong function name. Diff between plan and contract would cause confusion. |
| 99-01-CALLSITE-AUDIT.md | Constants table rows 3-4 | `DAILY_JACKPOT_UNITS_AUTOREBUY` (JM:167) and `DAILY_JACKPOT_UNITS_SAFE` (JM:164) do not exist | Warning | False constants in the baseline document. JM:167 is `DAILY_REWARD_JACKPOT_LOOTBOX_BPS`; JM:164 is `FINAL_DAY_DGNRS_BPS`. |
| 99-01-CALLSITE-AUDIT.md | Chunk System Note | Describes unitsBudget, dailyEthBucketCursor, dailyEthWinnerCursor as existing state; none of these exist | Blocker | Phase 100 implementer may believe they need to handle chunk boundary writes that do not exist. |
| 99-01-CALLSITE-AUDIT.md | All line references | Section 7 documents "corrections" that are themselves wrong; all stated corrected line numbers (807, 863, 1011, 1013) are off from actual source (778, 834, 982, 984) | Warning | Pre-change baseline has wrong line anchors. Phase 100 implementer would search wrong lines. |
| 99-01-SUMMARY.md | Decision 2 | Claims function renamed to `_processDailyEthChunk` at JM:1387 "during Phase 97 comment cleanup" | Warning | False claim about function rename. Function is still `_processDailyEth` at JM:1338. |

---

## Behavioral Spot-Checks

Step 7b: SKIPPED — this is a read-only documentation phase, no runnable entry points produced.

---

## Human Verification Required

None — all claims in this phase are documentable code facts, fully verifiable by reading the source.

---

## Gaps Summary

The phase correctly delivers on its most important finding: `_runEarlyBirdLootboxJackpot` does NOT call `_processAutoRebuy`, and this is verified against the actual contract. The earlybird scope correction is sound. The gas baseline math (SSTORE counts, H14 reconciliation) is correct in substance.

However, the audit document contains two categories of errors that undermine its usefulness as a pre-change baseline:

**Category 1 — Wrong function name (blocker):** The function `_processDailyEthChunk` does not exist. The actual function is `_processDailyEth` at JM:1338. This name appears throughout the document in tables, call trees, and Phase 100 Targets. Phase 100 implementers using this document as a guide would search for the wrong function. The SUMMARY compounds this by claiming a rename occurred during Phase 97 that did not happen.

**Category 2 — Wrong line numbers (warning):** The Section 7 "Verification Notes" claims to document line corrections from the plan, but the corrected values are all wrong. The original PLAN interfaces block had the correct line numbers (778, 834, 982, 984). The audit document's "corrections" move them to wrong values (807, 863, 1011, 1013). Additionally, two non-existent constants appear in the constants table.

The fix required is straightforward: rename `_processDailyEthChunk` to `_processDailyEth`, remove the chunk system note, remove the two nonexistent constants, and update all line references to actual values from the source.

---

_Verified: 2026-03-25T15:00:00Z_
_Verifier: Claude (gsd-verifier)_
