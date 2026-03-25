---
phase: 96-gas-ceiling-optimization
plan: 02
subsystem: gas-optimization
tags: [sload, loop-hoisting, gas-audit, daily-jackpot, evm-storage]

# Dependency graph
requires:
  - phase: 96-01
    provides: "Gas ceiling measurements and AT_RISK/TIGHT stage classifications"
  - phase: 95
    provides: "Dead code removal of chunk infrastructure, _winnerUnits identified as redundant"
provides:
  - "SLOAD inventory of all 24 storage reads in daily jackpot hot path"
  - "Loop hoisting audit of 7 loops with 14 hoisting verdicts"
  - "Ranked optimization recommendations for GOPT-03"
affects: [96-gas-ceiling-optimization]

# Tech tracking
tech-stack:
  added: []
  patterns: ["SLOAD audit methodology: trace every storage read to EVM slot, classify cold/warm, compute per-winner gas impact"]

key-files:
  created:
    - ".planning/phases/96-gas-ceiling-optimization/96-OPTIMIZATION-AUDIT.md"
  modified: []

key-decisions:
  - "Only 1 actionable optimization: _winnerUnits removal (674K gas, already planned in Phase 95)"
  - "prizePoolsPacked batching (1.6M gas savings) deferred as architectural change"
  - "gameOver/level parameter passing (32-64K gas each) skipped as marginal vs callsite complexity"

patterns-established:
  - "SLOAD audit pattern: per-variable table with EVM slot, cold/warm, multiplicity, total gas, verdict"
  - "Loop hoisting pattern: per-loop expression inventory with invariant analysis and hoisting verdicts"

requirements-completed: [GOPT-01, GOPT-02]

# Metrics
duration: 5min
completed: 2026-03-25
---

# Phase 96 Plan 02: SLOAD + Loop Hoisting Audit Summary

**24 SLOADs cataloged across daily jackpot hot path: 69.4% unavoidable (per-address mappings), 22.7% optimizable (_winnerUnits dead code = 674K gas), 7.6% already-optimized (warm packed slots); 7 loops analyzed with all library computations confirmed already-hoisted**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-25T04:17:14Z
- **Completed:** 2026-03-25T04:22:30Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Every SLOAD in the daily jackpot hot path (321 auto-rebuy winners, 4 buckets) inventoried with EVM slot, cold/warm status, per-call count, gas impact, and optimization verdict
- Every loop body analyzed for hoistable computation -- all library calls confirmed ALREADY-HOISTED, all per-winner operations confirmed NOT-INVARIANT or MARGINAL
- Combined optimization summary providing ranked recommendations for GOPT-03: only actionable optimization is Phase 95's _winnerUnits removal (674,100 gas)

## Task Commits

Each task was committed atomically:

1. **Task 1: SLOAD audit of daily jackpot hot path** - `a5b3366a` (docs)
2. **Task 2: Loop hoisting audit of daily jackpot code path** - `7b02fb0f` (docs)

## Files Created/Modified
- `.planning/phases/96-gas-ceiling-optimization/96-OPTIMIZATION-AUDIT.md` - Comprehensive SLOAD inventory (24 entries) + loop hoisting audit (7 loops, 14 verdicts) + optimization summary with ranked recommendations

## Decisions Made
- **_winnerUnits is the only significant optimization:** 674,100 gas savings (4.8% of 14M ceiling) from eliminating redundant cold SLOAD per winner. Already targeted by Phase 95 chunk removal.
- **prizePoolsPacked batching deferred:** ~1.6M gas savings from batching 321 read-modify-write cycles into single SSTORE, but requires restructuring _processAutoRebuy return values and all 6+ callers. Flagged as architectural change (Rule 4).
- **Warm SLOAD parameter passing skipped:** gameOver (32K), level (32-64K), rngLockedFlag (0-64K) are all warm Slot 0 reads at 100 gas each. Savings < 0.5% of ceiling, not worth function signature changes across 6-12+ callsites.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- GOPT-01 and GOPT-02 fully addressed in 96-OPTIMIZATION-AUDIT.md
- GOPT-03 (implementation) has clear guidance: only actionable optimization is Phase 95's _winnerUnits removal
- If gas ceiling remains a concern post-Phase-95, the prizePoolsPacked batching opportunity (H14) is documented for future consideration

## Self-Check: PASSED

- FOUND: `.planning/phases/96-gas-ceiling-optimization/96-OPTIMIZATION-AUDIT.md`
- FOUND: `.planning/phases/96-gas-ceiling-optimization/96-02-SUMMARY.md`
- FOUND: commit `a5b3366a` (Task 1: SLOAD audit)
- FOUND: commit `7b02fb0f` (Task 2: Loop hoisting audit)

---
*Phase: 96-gas-ceiling-optimization*
*Completed: 2026-03-25*
