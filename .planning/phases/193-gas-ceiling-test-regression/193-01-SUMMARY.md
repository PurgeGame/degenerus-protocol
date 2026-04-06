---
phase: 193-gas-ceiling-test-regression
plan: 01
subsystem: testing
tags: [gas-benchmark, regression-testing, foundry, hardhat, advanceGame]

requires:
  - phase: 192-delta-extraction-behavioral-verification
    provides: "Function-level changelog and behavioral change proofs for v23.0 jackpot changes"
provides:
  - "Gas ceiling measurement proving advanceGame peak at 6,275,799 gas (4.78x safety margin)"
  - "Test regression verification: Foundry 150/28, Hardhat 1232/13/3 -- zero new failures"
affects: []

tech-stack:
  added: []
  patterns: ["Hardhat gas benchmark harness (test/gas/AdvanceGameGas.test.js) for per-stage gas measurement"]

key-files:
  created:
    - ".planning/phases/193-gas-ceiling-test-regression/193-01-AUDIT.md"
  modified: []

key-decisions:
  - "Used Hardhat gas benchmark harness as canonical gas measurement (17 per-stage measurements vs Foundry single-function gas-report)"
  - "Hardhat baseline updated from 1225/19/3 to 1232/13/3 -- 6 pre-existing distress-mode failures resolved by v23.0 changes, 1 new test added"

patterns-established:
  - "Gas ceiling: peak advanceGame gas measured via AdvanceGameGas.test.js benchmark suite, safety margin calculated as 30M / peak"

requirements-completed: [GAS-01, DELTA-03]

duration: 48m
completed: 2026-04-06
---

# Phase 193 Plan 01: Gas Ceiling & Test Regression Summary

**advanceGame peak gas 6,275,799 (4.78x margin vs 30M limit, down 10.6% from v15.0 baseline); Foundry 150/28 exact match, Hardhat 1232/13/3 zero new failures**

## Performance

- **Duration:** 48 min
- **Started:** 2026-04-06T17:21:37Z
- **Completed:** 2026-04-06T18:10:08Z
- **Tasks:** 1
- **Files created:** 1

## Accomplishments

- Measured advanceGame worst-case gas across all 17 code paths via Hardhat benchmark harness; peak is Phase Transition (stage=2) at 6,275,799 gas
- Confirmed 4.78x safety margin against 30M block gas limit (threshold: >= 1.5x), representing a 10.6% gas DECREASE from prior v15.0 baseline of 7,023,530
- Verified all three new jackpot paths (specialized events, whale pass daily-only, DGNRS fold) are exercised by the benchmark and do not increase worst-case gas
- Foundry: 150 passing / 28 failing -- exact match to v22.0 baseline
- Hardhat: 1232 passing / 13 failing / 3 pending -- zero new failures; 6 pre-existing distress-mode failures resolved, 1 new test (DgnrsSoloBucketReward) added and passing

## Task Commits

Each task was committed atomically:

1. **Task 1: Gas Ceiling Analysis + Test Regression Verification** - `73c54315` (docs)

## Files Created/Modified

- `.planning/phases/193-gas-ceiling-test-regression/193-01-AUDIT.md` - Full gas ceiling analysis with benchmark table, safety margin calculation, new path coverage analysis, and Foundry/Hardhat regression results

## Decisions Made

- **Hardhat benchmark as canonical gas measurement:** The Hardhat gas benchmark harness (test/gas/AdvanceGameGas.test.js) provides 17 per-stage gas measurements with dynamic game state progression, offering more granular visibility than Foundry's single-function gas-report. No Foundry test specifically targets advanceGame gas measurement.
- **Baseline delta documented:** Hardhat counts changed from baseline (1225/19/3 to 1232/13/3) due to 6 pre-existing distress-mode failures resolving and 1 new test being added -- not regressions. Documented in audit with full attribution.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- Foundry `forge test` required running from main repo directory due to worktree missing node_modules symlinks for OpenZeppelin imports. Hardhat gas benchmark successfully ran against the worktree contracts.
- Hardhat test runner exits with code 1 due to a harmless mocha module unload path resolution error (worktree-specific). All tests complete successfully before this error.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- GAS-01 and DELTA-03 requirements satisfied
- Phase 193 (single-plan phase) is complete
- Ready for Phase 194 (payout reference tables) if planned

---
*Phase: 193-gas-ceiling-test-regression*
*Completed: 2026-04-06*
