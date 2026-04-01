---
phase: 99-callsite-audit
plan: 01
subsystem: audit
tags: [gas-optimization, sstore, prizePoolsPacked, autoRebuy, jackpot, callsite-inventory]

# Dependency graph
requires:
  - phase: 96-gas-ceiling-optimization
    provides: "H14 gas analysis identifying prizePoolsPacked batching opportunity"
provides:
  - "Complete _processAutoRebuy callsite inventory (CALL-01)"
  - "Complete prizePoolsPacked write map for daily ETH paths (CALL-02)"
  - "SSTORE gas baseline with H14 reconciliation"
  - "Phase 100 function-level change targets"
affects: [100-batch-implementation, prizePoolsPacked-batching]

# Tech tracking
tech-stack:
  added: []
  patterns: ["callsite inventory with line-number tracing", "SSTORE gas accounting with warm/cold distinction"]

key-files:
  created:
    - ".planning/phases/99-callsite-audit/99-01-CALLSITE-AUDIT.md"
    - ".planning/phases/99-callsite-audit/99-01-PLAN.md"
  modified: []

key-decisions:
  - "Earlybird path does NOT call _processAutoRebuy -- CONTEXT.md was incorrect; batching scope is _processDailyEthChunk only"
  - "H14 gas figure of ~1.6M uses cold SSTORE pricing; actual pool I/O savings from batching is ~63,800 gas (warm pricing)"

patterns-established:
  - "Warm SSTORE = 100 gas (nonzero->nonzero, same slot already written in tx)"

requirements-completed: [CALL-01, CALL-02]

# Metrics
duration: 5min
completed: 2026-03-25
---

# Phase 99 Plan 01: Callsite Audit Summary

**Complete callsite inventory for _processAutoRebuy and prizePoolsPacked writes across daily ETH jackpot paths, with SSTORE gas baseline and Phase 100 change targets**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-25T14:10:39Z
- **Completed:** 2026-03-25T14:16:07Z
- **Tasks:** 2
- **Files created:** 2 (audit doc + plan)

## Accomplishments

- Verified complete call graph for both in-scope paths (_processDailyEthChunk and _runEarlyBirdLootboxJackpot)
- Confirmed constants: MAX_BUCKET_WINNERS=250, DAILY_ETH_MAX_WINNERS=321
- Key finding: _runEarlyBirdLootboxJackpot does NOT call _processAutoRebuy (corrects CONTEXT.md)
- SSTORE gas baseline: 64,200 gas pool I/O for 321-winner worst case, with H14 reconciliation
- Derived 5 function-level change targets for Phase 100

## Task Commits

Each task was committed atomically:

1. **Task 1+2: Call graph verification + Callsite audit document** - `56bf8f3b` (feat)

**Plan metadata:** (pending -- docs commit)

## Files Created/Modified

- `.planning/phases/99-callsite-audit/99-01-CALLSITE-AUDIT.md` - Complete callsite inventory with SSTORE gas baseline and Phase 100 targets
- `.planning/phases/99-callsite-audit/99-01-PLAN.md` - Plan definition

## Decisions Made

1. **Earlybird scope correction:** CONTEXT.md incorrectly listed _runEarlyBirdLootboxJackpot as a _processAutoRebuy callsite. Verified it calls _queueTickets directly with 2 fixed pool writes. Phase 100 batching applies only to _processDailyEthChunk.

2. **H14 gas reconciliation:** The Phase 96 H14 figure of ~1,634,100 gas represents full per-winner _processAutoRebuy cost (not just pool writes). Actual pool I/O savings from batching is ~63,800 gas, computed using correct warm SSTORE pricing (100 gas per EIP-2929, not 5,000 gas).

3. **Line number corrections:** All 11 line references in the plan's interfaces block were shifted from older codebase version. All functional behaviors confirmed despite line drift. Corrected references documented in Section 7 of audit doc.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected CONTEXT.md claim about earlybird calling _processAutoRebuy**
- **Found during:** Task 1 (call graph verification)
- **Issue:** 99-CONTEXT.md stated _runEarlyBirdLootboxJackpot calls _processAutoRebuy. Actual code calls _queueTickets directly.
- **Fix:** Documented correction in Section 5 of audit document. No code changes (read-only analysis).
- **Files modified:** 99-01-CALLSITE-AUDIT.md (new file, Section 5)
- **Verification:** Verified JM:801-864 contains no reference to _addClaimableEth or _processAutoRebuy

**2. [Rule 1 - Bug] Corrected function name: _processDailyEth -> _processDailyEthChunk**
- **Found during:** Task 1 (call graph verification)
- **Issue:** Plan referenced _processDailyEth; actual function is _processDailyEthChunk (renamed during Phase 97 comment cleanup)
- **Fix:** Used correct function name throughout audit document
- **Files modified:** 99-01-CALLSITE-AUDIT.md (new file)
- **Verification:** grep confirms _processDailyEthChunk at JM:1387

---

**Total deviations:** 2 auto-fixed (2 bugs -- factual corrections from plan/context)
**Impact on plan:** Both corrections improve audit accuracy. No scope creep.

## Issues Encountered

None -- all 7 verification items confirmed or corrected from source.

## User Setup Required

None -- no external service configuration required.

## Next Phase Readiness

- Callsite inventory complete, ready for Phase 100 implementation
- Phase 100 targets clearly defined: 5 function-level changes
- Key constraint: earlybird path requires no changes
- Other callers of _addClaimableEth identified for compatibility audit

---
*Phase: 99-callsite-audit*
*Completed: 2026-03-25*
