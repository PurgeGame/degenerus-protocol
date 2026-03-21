---
phase: 45-invariant-test-suite
plan: 03
subsystem: testing
tags: [foundry, invariant-testing, fuzz, redemption, solidity]

# Dependency graph
requires:
  - phase: 45-01
    provides: Phase 44 fixes applied to contracts (CP-06, CP-07, CP-08, Seam-1)
  - phase: 45-02
    provides: RedemptionHandler with ghost variables and multi-actor burn-resolve-claim lifecycle
provides:
  - 7 invariant test functions (INV-01 through INV-07) proving redemption system correctness
  - RedemptionInvariants test contract wired to RedemptionHandler and VRFHandler
  - Regression guard for all Phase 44 findings
affects: [phase-46, audit-report, deployment-readiness]

# Tech tracking
tech-stack:
  added: []
  patterns: [invariant-test-with-ghost-counters, vm-load-slot-reads-for-internal-state, split-claim-double-claim-detection]

key-files:
  created:
    - test/fuzz/invariant/RedemptionInvariants.inv.t.sol
  modified:
    - test/fuzz/handlers/RedemptionHandler.sol

key-decisions:
  - "Double-claim detection checks ETH transfer delta, not try/catch success, due to CP-07 split claim design"

patterns-established:
  - "Split claim awareness: claimRedemption can succeed twice (ETH first, BURNIE later) -- not a double claim"
  - "Ghost counter pattern: deviation counters (ghost_doubleClaim, ghost_rollOutOfBounds, etc.) asserted == 0 in invariants"

requirements-completed: [INV-01, INV-02, INV-03, INV-04, INV-05, INV-06, INV-07]

# Metrics
duration: 3min
completed: 2026-03-21
---

# Phase 45 Plan 03: Redemption Invariants Summary

**7 invariant tests proving ETH solvency, no double-claim, period monotonicity, supply consistency, 50% cap, roll bounds, and aggregate tracking -- all passing at 256 runs x 128 depth**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-21T04:57:57Z
- **Completed:** 2026-03-21T05:01:42Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- All 7 invariant functions (INV-01 through INV-07) implemented and passing with zero failures
- Handler exercises full burn-resolve-claim lifecycle: ghost_totalBurned > 0, ghost_periodsResolved > 0, ghost_claimCount > 0
- Double-claim detection refined to account for CP-07 split claim design (ETH-first, BURNIE-later)
- Canary and call summary diagnostics included for debugging visibility

## Task Commits

Each task was committed atomically:

1. **Task 1: Create RedemptionInvariants with all 7 invariant functions** - `a775d78d` (feat)
2. **Task 2: Run invariant test suite and verify all 7 pass** - `6672258b` (fix)

## Files Created/Modified
- `test/fuzz/invariant/RedemptionInvariants.inv.t.sol` - 197-line invariant test contract with 7 core invariants + canary + call summary
- `test/fuzz/handlers/RedemptionHandler.sol` - Fixed double-claim detection to check ETH transfer delta instead of try/catch success

## Decisions Made
- **Double-claim detection via ETH delta:** CP-07 split claim means claimRedemption() can succeed twice legitimately (ETH claim, then BURNIE claim). Only flag ghost_doubleClaim when the second call transfers ETH, not just when it doesn't revert. This aligns the invariant with the actual security property: "no ETH paid twice for the same burn."

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed double-claim false positive from CP-07 split claim path**
- **Found during:** Task 2 (invariant test run)
- **Issue:** INV-02 failed because claimRedemption() succeeds on partial re-claim (BURNIE portion still pending after ETH-only claim). The handler's try/catch treated this as a double claim.
- **Fix:** Changed re-claim detection to check `currentActor.balance > ethBeforeReClaim` -- only counts as double-claim if ETH actually moves on the second call.
- **Files modified:** test/fuzz/handlers/RedemptionHandler.sol
- **Verification:** All 9 tests pass (256 runs, depth 128, 0 failures)
- **Committed in:** 6672258b (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Essential fix aligning the handler's double-claim detection with the CP-07 split claim design. No scope creep.

## Issues Encountered
- `console.log` not auto-imported via DeployProtocol inheritance chain -- resolved by adding explicit `import "forge-std/Test.sol"` to the invariant contract

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 45 invariant test suite complete: all 3 plans (fixes, handler, invariants) delivered
- 7 invariant tests provide regression protection for all Phase 44 findings
- Ready for Phase 46 (documentation sync) or Phase 48 (next milestone work)

## Self-Check: PASSED

- FOUND: test/fuzz/invariant/RedemptionInvariants.inv.t.sol
- FOUND: .planning/phases/45-invariant-test-suite/45-03-SUMMARY.md
- FOUND: a775d78d (Task 1 commit)
- FOUND: 6672258b (Task 2 commit)

---
*Phase: 45-invariant-test-suite*
*Completed: 2026-03-21*
