---
phase: 181-advancegame-revert-safety-audit
plan: "03"
subsystem: audit
tags: [external-calls, revert-safety, advancegame, delegatecall, try-catch, vrf]

# Dependency graph
requires:
  - phase: 181-advancegame-revert-safety-audit
    provides: revert-safety audit context (plans 01-02)
provides:
  - Complete external call revert audit (19 calls) for advanceGame execution path
  - AGSAFE-03 VERIFIED verdict with per-call safety classification
affects: [advancegame-revert-safety, audit-findings]

# Tech tracking
tech-stack:
  added: []
  patterns: [external-call-revert-analysis, delegatecall-msg-sender-tracing, try-catch-failure-tolerance]

key-files:
  created:
    - .planning/phases/181-advancegame-revert-safety-audit/181-03-EXTERNAL-CALLS.md
  modified: []

key-decisions:
  - "All 19 external calls from advanceGame path classified: 17 SAFE, 1 INTENTIONAL (VRF), 2 WRAPPED (stETH + VRF shutdown)"
  - "VRF requestRandomWords hard-revert is INTENTIONAL by design -- halts game until VRF operational"
  - "GameOverModule uses _tryRequestRng (try/catch) instead of _requestRng for VRF fallback path"

patterns-established:
  - "External call classification: SAFE (cannot revert), INTENTIONAL (reverts by design), WRAPPED (try/catch)"
  - "Delegatecall msg.sender tracing: modules running via delegatecall from GAME have msg.sender == GAME on external calls"

requirements-completed: []

# Metrics
duration: 1min
completed: 2026-04-04
---

# Phase 181 Plan 03: External Call Revert Audit Summary

**19 external calls from advanceGame path audited -- 17 SAFE (pure storage ops), 1 INTENTIONAL (VRF halt-by-design), 2 WRAPPED (try/catch), 0 findings**

## Performance

- **Duration:** 1 min
- **Started:** 2026-04-04T05:15:35Z
- **Completed:** 2026-04-04T05:16:55Z
- **Tasks:** 1 (single audit document)
- **Files modified:** 1

## Accomplishments
- Audited every external call (non-delegatecall) reachable from advanceGame execution, including GameOverModule path
- For each of 19 calls: identified call site, target contract+function, access control, revert conditions, failure tolerance, and final verdict
- Confirmed no external call can cause an unexpected revert that blocks game progression
- Identified 7 key safety mechanisms: transferFromPool capping, creditFlip early-returns, processCoinflipPayouts 5-guard callback, GNRUS pickCharity level invariant, GameOverModule double-entry prevention, _tryRequestRng fallback, stETH non-blocking try/catch

## Task Commits

Each task was committed atomically:

1. **Task 1: External call revert audit (AGSAFE-03)** - `afa86f09` (feat)

## Files Created/Modified
- `.planning/phases/181-advancegame-revert-safety-audit/181-03-EXTERNAL-CALLS.md` - Complete external call revert audit with 19 entries covering AdvanceModule, GameOverModule, and callback chains

## Decisions Made
- VRF requestRandomWords classified as INTENTIONAL rather than a finding -- the hard revert is explicitly documented in code comments as a design decision to halt game progress until VRF is operational
- GameOverModule self-calls (EXT-14, EXT-15) classified as external calls because they use regular CALL opcode (not delegatecall), even though target is address(this)
- EXT-13 stETH and EXT-18 shutdownVrf counted in both WRAPPED and SAFE categories since try/catch makes them non-blocking

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Known Stubs
None - audit document is complete with all 19 external calls analyzed.

## Next Phase Readiness
- AGSAFE-03 (external call revert audit) complete
- Ready for consolidation with other 181-phase plans

## Self-Check: PASSED

- FOUND: 181-03-EXTERNAL-CALLS.md
- FOUND: 181-03-SUMMARY.md
- FOUND: commit afa86f09

---
*Phase: 181-advancegame-revert-safety-audit*
*Completed: 2026-04-04*
