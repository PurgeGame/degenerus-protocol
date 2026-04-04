---
phase: 182-regression-check
plan: 02
subsystem: testing
tags: [hardhat, foundry, regression, fuzz, invariant, solidity]

# Dependency graph
requires:
  - phase: 167-integration-test-baseline
    provides: v15.0 test baseline (1455 passing, 124 expected failures)
provides:
  - v17.1 test regression results -- 1568 passing, 7 expected failures, 0 unexpected
  - Full failure classification with root cause analysis for all 7 expected failures
  - Verification that all 124 v15.0 expected failures are resolved
affects: [test-update, v18-planning]

# Tech tracking
tech-stack:
  added: []
  patterns: [regression-classification-against-baseline]

key-files:
  created:
    - .planning/phases/182-regression-check/182-02-TEST-RESULTS.md
  modified: []

key-decisions:
  - "All 7 failures classified EXPECTED: 5 Hardhat (1 bonus rate, 4 WWXRP scaling), 2 Foundry (1 rngBypass refactor, 1 gap bits cache conflict)"
  - "All 124 v15.0 baseline expected failures resolved (+113 net passing tests)"
  - "Combined verdict: PASS -- zero unexpected failures across both frameworks"

patterns-established:
  - "Test regression classification: compare per-suite counts against prior baseline document"

requirements-completed: [REG-02]

# Metrics
duration: 32min
completed: 2026-04-04
---

# Phase 182 Plan 02: Hardhat + Foundry Regression Check Summary

**1568 passing tests (Hardhat 1186 + Foundry 382), 7 expected failures, zero unexpected regressions across v16.0-v17.1 delta**

## Performance

- **Duration:** 32 min
- **Started:** 2026-04-04T06:42:59Z
- **Completed:** 2026-04-04T07:15:00Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Ran Hardhat test suite: 1186/1194 passing, 5 expected failures (1 affiliate bonus rate, 4 WWXRP decimal scaling), all 13 v15.0 expected failures now pass
- Ran Foundry test suite (standard + invariant): 382/384 passing, 2 expected failures (1 rngBypass refactor, 1 gap bits cache conflict), all 111 v15.0 expected failures now pass
- Combined verdict: PASS -- zero unexpected failures, net +113 passing tests vs v15.0 baseline

## Task Commits

Each task was committed atomically:

1. **Task 1: Run Hardhat test suite and classify results** - `5c538448` (feat)
2. **Task 2: Run Foundry test suite and produce combined results** - `1f83082a` (feat)

## Files Created/Modified
- `.planning/phases/182-regression-check/182-02-TEST-RESULTS.md` - Complete test results with per-framework breakdown, failure classification, and combined verdict

## Decisions Made
- All 5 Hardhat failures classified EXPECTED: 1 affiliate bonus rate change (v17.0), 4 WWXRP decimal scaling fix (v17.1)
- All 2 Foundry failures classified EXPECTED: 1 TicketRouting rngBypass parameter refactor (v16.0), 1 Composition invariant gap bits overlap with affiliate bonus cache (v17.0)
- All 124 v15.0 baseline expected failures confirmed resolved -- no expected failures carried forward

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- `npm test` script references nonexistent `test/adversarial/` directory, causing Mocha error. Workaround: ran tests by explicitly specifying existing directories (access, deploy, unit, integration, edge, gas). Does not affect test coverage -- adversarial directory never existed in this codebase.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Test regression check complete with zero unexpected failures
- 7 test files need updating to match intentional contract changes (not regressions)
- Ready for any further verification or next milestone planning

---
*Phase: 182-regression-check*
*Completed: 2026-04-04*
