---
phase: 182-regression-check
plan: 02
subsystem: testing
tags: [hardhat, foundry, regression, fuzz, invariant, baseline]

requires:
  - phase: 167-integration-test-baseline
    provides: v15.0 test baseline (1455 passing, 124 expected failures)
provides:
  - v17.1 test regression verification with zero unexpected failures
  - Complete test results document covering both Hardhat and Foundry
  - Updated failure baseline (9 expected failures replacing 124)
affects: [future-test-updates, v18.0-audit-readiness]

tech-stack:
  added: []
  patterns: [make test-foundry for Foundry address patching, per-directory Hardhat analysis]

key-files:
  created:
    - .planning/phases/182-regression-check/182-02-TEST-RESULTS.md
  modified: []

key-decisions:
  - "Foundry tests require make test-foundry (address patching) -- bare forge test causes setUp() reverts in 28/47 suites due to ContractAddresses.sol mismatch"
  - "All 124 v15.0 baseline expected failures are now resolved -- tests were updated in prior phases"
  - "9 new expected failures documented: 1 affiliate bonus rate (v17.0), 4 WWXRP decimals (post-v15.0), 2 GameOver NotTimeYet (v16.0), 1 rngBypass refactor (v16.0), 1 gap-bit invariant (v17.0)"

patterns-established:
  - "Regression check pattern: run both frameworks, classify every failure against baseline, produce combined verdict"

requirements-completed: [REG-02]

duration: 34min
completed: 2026-04-04
---

# Phase 182 Plan 02: Test Suite Regression Check Summary

**Hardhat 1184/1194 + Foundry 382/384 = 1566 combined passing, 9 expected failures, zero unexpected regressions vs v15.0 baseline**

## Performance

- **Duration:** 34 min
- **Started:** 2026-04-04T06:51:52Z
- **Completed:** 2026-04-04T07:26:43Z
- **Tasks:** 2
- **Files created:** 1

## Accomplishments
- Both Hardhat and Foundry test suites run to completion with all tests classified
- Zero unexpected failures across both frameworks -- no regressions from v16.0-v17.1 refactors
- All 124 v15.0 baseline expected failures now pass (tests updated in prior phases)
- 9 new expected failures fully documented with root cause, version, and classification
- Net improvement: +111 passing tests vs v15.0 baseline

## Task Commits

Each task was committed atomically:

1. **Task 1: Run Hardhat test suite and classify results against v15.0 baseline** - `76e39f09` (docs)
2. **Task 2: Run Foundry test suite and produce combined results document** - `d2da8d5a` (docs)

## Files Created/Modified
- `.planning/phases/182-regression-check/182-02-TEST-RESULTS.md` - Complete test results with Hardhat section, Foundry section, and combined verdict

## Decisions Made
- Foundry tests must be run via `make test-foundry` to patch ContractAddresses.sol with predicted Foundry nonce addresses; bare `forge test` causes setUp() reverts in 28/47 suites
- All 9 failures classified as EXPECTED based on traceability to specific intentional changes in v16.0-v17.1 delta
- GameOver edge test NotTimeYet() failures share the same root cause as v15.0 Foundry baseline Category 1 (time-gating guard requires warp)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Foundry tests required make test-foundry instead of bare forge test**
- **Found during:** Task 2 (Foundry test execution)
- **Issue:** Running `forge test` directly caused setUp() reverts in 28/47 suites because ContractAddresses.sol has local changes that don't match Foundry's predicted nonce-based addresses
- **Fix:** Used `make test-foundry` which patches ContractAddresses.sol, runs tests, and restores the original file automatically
- **Verification:** All 47 suites executed successfully with patching (382 pass, 2 expected fail)
- **Committed in:** d2da8d5a (Task 2 commit)

**2. [Rule 3 - Blocking] Hardhat adversarial test directory missing**
- **Found during:** Task 1 (Hardhat test execution)
- **Issue:** `npm test` references `test/adversarial/*.test.js` but the directory no longer exists, causing MODULE_NOT_FOUND
- **Fix:** Ran tests with explicit globs excluding the adversarial directory
- **Verification:** 1194 tests discovered and executed across 6 remaining directories
- **Committed in:** 76e39f09 (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (2 blocking issues)
**Impact on plan:** Both fixes necessary to complete test execution. No scope creep.

## Issues Encountered
- Mocha file-unloader throws a MODULE_NOT_FOUND error after all tests complete (cosmetic -- does not affect test results, occurs during cleanup phase)
- Foundry compiler cache serialization warnings (`invalid type: sequence, expected a map`) when run without patching -- resolved by using `make test-foundry` which force-recompiles

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Regression check complete: zero unexpected failures confirms v16.0-v17.1 changes are safe
- 9 expected test failures documented for future test update work
- Ready for audit readiness assessment

---
*Phase: 182-regression-check*
*Completed: 2026-04-04*
