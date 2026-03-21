---
phase: 49-milestone-cleanup
plan: 02
subsystem: testing
tags: [foundry, fuzz, invariant, ghost-variable, burnie, redemption]

# Dependency graph
requires:
  - phase: 45-critical-fixes
    provides: "Split claim design (CP-07) and gambling burn lifecycle"
  - phase: 47-gas-optimization
    provides: "Gas benchmark tests and ghost variable analysis"
provides:
  - "Active ghost_totalBurnieClaimed tracking in RedemptionHandler"
  - "INV-07b invariant_burnieClaimedMonotonic assertion"
  - "Verified gas benchmark baseline (7/7 pass) after Phase 45 restructure"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns: ["Ghost variable balance-delta tracking via coin.balanceOf before/after pattern"]

key-files:
  created: []
  modified:
    - "test/fuzz/handlers/RedemptionHandler.sol"
    - "test/fuzz/invariant/RedemptionInvariants.inv.t.sol"

key-decisions:
  - "Used coin.balanceOf delta (before/after) to track BURNIE claims rather than decoding internal state"
  - "Set 1e30 generous upper bound for BURNIE claimed invariant (matches initial supply order of magnitude)"

patterns-established:
  - "Balance-delta ghost tracking: snapshot balanceOf before action, compute delta after success"

requirements-completed: [INV-07]

# Metrics
duration: 4min
completed: 2026-03-21
---

# Phase 49 Plan 02: INV-07 BURNIE Claimed Invariant Summary

**Activated ghost_totalBurnieClaimed with balance-delta tracking and added INV-07b monotonic boundedness invariant; verified all 7 gas benchmarks and 10 invariant tests pass**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-21T12:53:08Z
- **Completed:** 2026-03-21T12:57:26Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Activated ghost_totalBurnieClaimed from placeholder to active balance-delta tracker in RedemptionHandler action_claim
- Added INV-07b invariant_burnieClaimedMonotonic to RedemptionInvariants proving cumulative BURNIE claims are bounded
- Verified all 7 gas benchmark tests pass (burn, burnWrapped, resolve, claim, hasPending true/false, previewBurn)
- Confirmed full test baseline: 179 passed, 9 pre-existing failures (unchanged), 0 new regressions

## Task Commits

Each task was committed atomically:

1. **Task 1: Activate ghost_totalBurnieClaimed and add BURNIE claimed invariant** - `f4536872` (feat)
2. **Task 2: Verify gas benchmark tests and full test baseline** - verification-only (no file changes)

## Files Created/Modified
- `test/fuzz/handlers/RedemptionHandler.sol` - Added BurnieCoin import/state, constructor param, balance-delta tracking in action_claim, removed placeholder comment
- `test/fuzz/invariant/RedemptionInvariants.inv.t.sol` - Added INV-07b invariant_burnieClaimedMonotonic, updated setUp to pass coin, added ghost_totalBurnieClaimed to call summary

## Decisions Made
- Used coin.balanceOf delta (before/after) to track BURNIE claims rather than decoding internal storage slots -- cleaner and more resilient to storage layout changes
- Set 1e30 as the generous upper bound for the BURNIE claimed invariant, matching the initial BURNIE supply order of magnitude

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- INV-07 integration gap is closed -- ghost_totalBurnieClaimed is no longer a placeholder
- All invariants pass (10/10) including the new INV-07b
- Gas benchmarks confirmed stable after Phase 45 split-claim restructure
- Full test baseline unchanged (179 pass, 9 pre-existing fail)

## Self-Check: PASSED

- [x] test/fuzz/handlers/RedemptionHandler.sol exists
- [x] test/fuzz/invariant/RedemptionInvariants.inv.t.sol exists
- [x] .planning/phases/49-milestone-cleanup/49-02-SUMMARY.md exists
- [x] Commit f4536872 exists in git log

---
*Phase: 49-milestone-cleanup*
*Completed: 2026-03-21*
