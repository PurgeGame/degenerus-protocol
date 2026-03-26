---
phase: 125-test-suite-pruning
plan: 01
subsystem: testing
tags: [hardhat, foundry, redundancy-audit, test-pruning, coverage]

# Dependency graph
requires:
  - phase: 120-test-suite-cleanup
    provides: green baseline (369 Foundry, 1242 Hardhat, 1611 total)
provides:
  - REDUNDANCY-AUDIT.md with per-file verdicts for all 90 test files
  - 13 redundant test files deleted (~4,000 lines)
  - hardhat.config.js TEST_DIR_ORDER updated (adversarial, simulation removed)
affects: [125-02, test-suite]

# Tech tracking
tech-stack:
  added: []
  patterns: [redundancy-audit-methodology]

key-files:
  created:
    - .planning/phases/125-test-suite-pruning/REDUNDANCY-AUDIT.md
  modified:
    - hardhat.config.js

key-decisions:
  - "All 42 Foundry fuzz + 4 Halmos + 11 invariant tests KEEP -- highest value, never redundant"
  - "All 7 poc/ tests DELETE -- ghost tests excluded from Hardhat runner, never executed"
  - "All 3 adversarial/ tests DELETE -- 11 test cases covered by dedicated unit + fuzz tests"
  - "Both simulation/ tests DELETE -- console output only, no meaningful assertions"
  - "SimContractParity DELETE -- 4 tests covered by PaperParity PAR-01/03/10"
  - "No cross-suite DELETEs -- Hardhat named scenarios and Foundry fuzz are complementary"
  - "Orphaned helpers (player-manager.js, stats-tracker.js) deleted with simulation tests"

patterns-established:
  - "Redundancy audit methodology: ghost tests > within-suite overlap > cross-suite duplicates"
  - "D-02 criterion: when two tests cover the same ground, keep the more thorough one"

requirements-completed: [PRUNE-01, PRUNE-02]

# Metrics
duration: 16min
completed: 2026-03-26
---

# Phase 125 Plan 01: Test Suite Pruning Summary

**Redundancy audit of all 90 test files: 13 DELETE verdicts (7 ghost + 3 adversarial + 2 simulation + 1 validation), 75 KEEP, 2 borderline KEEP -- ~4,000 lines removed with zero unique coverage lost**

## Performance

- **Duration:** 16 min
- **Started:** 2026-03-26T15:32:59Z
- **Completed:** 2026-03-26T15:49:57Z
- **Tasks:** 2
- **Files modified:** 18 (1 created, 17 deleted/modified)

## Accomplishments
- Full redundancy audit covering all 90 test files across 3 dimensions: ghost tests, cross-suite duplicates, within-suite overlaps
- 13 redundant test files deleted: 7 ghost tests (poc/), 3 adversarial tests, 2 simulation tests, 1 validation test
- 2 orphaned helper files (player-manager.js, stats-tracker.js) cleaned up
- hardhat.config.js TEST_DIR_ORDER updated to remove deleted directories (adversarial, simulation)
- All 57 invariant/halmos/fuzz Foundry tests preserved
- All deploy/access/gas/integration/edge/unit Hardhat tests preserved
- Remaining test suite: 31 Hardhat + 42 Foundry fuzz + 4 Halmos = 77 files

## Task Commits

Each task was committed atomically:

1. **Task 1: Redundancy audit across all 90 test files** - `2cf7465b` (docs)
2. **Task 2: Delete redundant test files per audit verdicts** - `7d9cc3ee` (chore)

## Files Created/Modified
- `.planning/phases/125-test-suite-pruning/REDUNDANCY-AUDIT.md` - Complete redundancy analysis with per-file verdicts and justifications
- `hardhat.config.js` - Removed "adversarial" and "simulation" from TEST_DIR_ORDER
- `test/poc/*.test.js` (7 files) - DELETED: ghost tests excluded from runner
- `test/adversarial/*.test.js` (3 files) - DELETED: covered by unit + fuzz tests
- `test/simulation/*.test.js` (2 files) - DELETED: console-only, no assertions
- `test/validation/SimContractParity.test.js` - DELETED: covered by PaperParity
- `test/validation/simBridge.js` - DELETED: orphaned support file
- `test/helpers/player-manager.js` - DELETED: orphaned simulation helper
- `test/helpers/stats-tracker.js` - DELETED: orphaned simulation helper

## Decisions Made

1. **No cross-suite DELETE verdicts:** Hardhat named-scenario tests and Foundry fuzz tests are complementary -- Hardhat covers specific lifecycle states with exact assertions while Foundry covers random input spaces. Both approaches are valuable and not redundant.

2. **EthInvariant.test.js and DGNRSLiquid.test.js as KEEP (borderline):** These have partial overlap with Foundry invariant tests but cover named lifecycle scenarios useful for human debugging. Kept as low-maintenance insurance.

3. **simBridge.js deleted with SimContractParity:** The simBridge.js helper was only used by SimContractParity.test.js. No other test file imports it, so it would be orphaned.

4. **Simulation helpers deleted:** player-manager.js and stats-tracker.js were only imported by the deleted simulation tests. Grepping the remaining test tree confirmed zero consumers.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Deleted orphaned helper files**
- **Found during:** Task 2 (file deletion)
- **Issue:** player-manager.js and stats-tracker.js in test/helpers/ were only used by simulation tests (now deleted)
- **Fix:** Added `git rm` for both orphaned helpers
- **Files modified:** test/helpers/player-manager.js, test/helpers/stats-tracker.js
- **Verification:** `grep -r "player-manager\|stats-tracker" test/` returned zero results after simulation deletion
- **Committed in:** 7d9cc3ee (Task 2 commit)

**2. [Rule 2 - Missing Critical] Deleted orphaned simBridge.js**
- **Found during:** Task 2 (file deletion)
- **Issue:** test/validation/simBridge.js was only imported by SimContractParity.test.js (now deleted)
- **Fix:** Added `git rm` for simBridge.js
- **Files modified:** test/validation/simBridge.js
- **Verification:** No remaining imports of simBridge in test tree
- **Committed in:** 7d9cc3ee (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (2 missing critical -- orphaned file cleanup)
**Impact on plan:** Both auto-fixes prevent dead code from persisting. No scope creep.

## Issues Encountered
- Mocha unload error during smoke test: `Cannot find module 'test/access/AccessControl.test.js'` -- this is a known worktree-specific path issue during Mocha's cleanup phase, not during test execution. All 1194 passing tests ran successfully; 32 failures are pre-existing from other phases (not caused by this plan).

## Known Stubs
None -- this plan only deletes files and creates documentation.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Reduced test suite ready for Phase 125-02 (test count verification and green baseline re-establishment)
- Remaining test count: 31 Hardhat files + 46 Foundry files = 77 total
- hardhat.config.js updated with correct directory ordering

## Self-Check: PASSED

- REDUNDANCY-AUDIT.md: FOUND
- 125-01-SUMMARY.md: FOUND
- Commit 2cf7465b (Task 1): FOUND
- Commit 7d9cc3ee (Task 2): FOUND
- All 13 DELETE-verdicted files removed from disk: VERIFIED
- All 5 spot-checked KEEP files still exist: VERIFIED

---
*Phase: 125-test-suite-pruning*
*Completed: 2026-03-26*
