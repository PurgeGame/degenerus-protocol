---
phase: 52-invariant-test-suite
plan: 02
subsystem: testing
tags: [foundry, fuzz, invariant, solidity, redemption, lootbox-split]

# Dependency graph
requires:
  - phase: 51-redemption-lootbox-audit
    provides: "Algebraic proof of 50/50 split conservation (REDM-01), RedemptionClaimed event signature"
  - phase: 45-invariant-test-suite
    provides: "RedemptionHandler, DeployProtocol, VRFHandler infrastructure, INV-01 through INV-07b"
provides:
  - "INV-03 pure arithmetic fuzz tests proving split identity for all production inputs"
  - "INV-08 lifecycle invariant proving split conservation through burn-resolve-claim execution"
  - "Ghost variable tracking for ethDirect vs lootboxEth per claim via RedemptionClaimed event parsing"
affects: [53-final-report, invariant-regression]

# Tech tracking
tech-stack:
  added: []
  patterns: ["vm.recordLogs() event parsing in handler for ghost variable tracking"]

key-files:
  created:
    - test/fuzz/RedemptionSplit.t.sol
  modified:
    - test/fuzz/handlers/RedemptionHandler.sol
    - test/fuzz/invariant/RedemptionInvariants.inv.t.sol

key-decisions:
  - "Fixed floor/ceiling assertion: lootboxEth >= ethDirect (not vice versa) since ethDirect = floor(x/2)"

patterns-established:
  - "Event-based ghost tracking: use vm.recordLogs() + keccak256 signature matching to track intermediate values not stored on-chain"

requirements-completed: [INV-03]

# Metrics
duration: 3min
completed: 2026-03-21
---

# Phase 52 Plan 02: Redemption Split Invariant Summary

**INV-03 redemption lootbox split conservation proven at two levels: pure arithmetic fuzz (3 tests x 1000 runs) and lifecycle invariant (INV-08, 256 runs x 128 depth) via RedemptionClaimed event ghost tracking**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-21T20:30:56Z
- **Completed:** 2026-03-21T20:33:38Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Three pure arithmetic fuzz tests proving ethDirect + lootboxEth == totalRolledEth for all production-realistic inputs (ethValueOwed in [1, 160 ether], roll in [25, 175])
- Lifecycle invariant (INV-08) proving split conservation holds through full burn-resolve-claim execution via RedemptionClaimed event parsing
- Extended RedemptionHandler with ghost_totalEthDirect, ghost_totalLootboxEth, ghost_totalRolledEth tracking
- All 11 RedemptionInvariants pass with zero regressions (INV-01 through INV-07b + INV-08 + canary + callSummary)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create RedemptionSplit.t.sol with pure arithmetic fuzz test** - `b722ef2f` (test)
2. **Task 2: Extend RedemptionHandler with split ghost variables and lifecycle invariant** - `6816a758` (feat)

## Files Created/Modified
- `test/fuzz/RedemptionSplit.t.sol` - Pure arithmetic fuzz tests for INV-03 split conservation (3 test functions)
- `test/fuzz/handlers/RedemptionHandler.sol` - Added 3 ghost variables + vm.recordLogs() event parsing in action_claim
- `test/fuzz/invariant/RedemptionInvariants.inv.t.sol` - Added invariant_lootboxSplitConservation (INV-08) + split tracking in callSummary

## Decisions Made
- Fixed floor/ceiling assertion direction in testFuzz_INV03_splitConservation_noGameOver: `lootboxEth >= ethDirect` because ethDirect = floor(totalRolledEth/2) and lootboxEth = totalRolledEth - floor(totalRolledEth/2), so lootboxEth gets the extra wei for odd totals

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed incorrect floor division assertion direction in split test**
- **Found during:** Task 1 (RedemptionSplit.t.sol creation)
- **Issue:** Plan specified `ethDirect >= lootboxEth` but the actual split logic gives ethDirect = floor(x/2) and lootboxEth = x - floor(x/2), meaning lootboxEth >= ethDirect for odd values
- **Fix:** Changed assertion to `lootboxEth >= ethDirect` and `lootboxEth - ethDirect <= 1`
- **Files modified:** test/fuzz/RedemptionSplit.t.sol
- **Verification:** All 3 fuzz tests pass with 1000+ runs
- **Committed in:** b722ef2f (Task 1 commit)

**2. [Rule 1 - Bug] Fixed Solidity tuple deconstruction syntax in handler**
- **Found during:** Task 2 (RedemptionHandler modification)
- **Issue:** Plan mixed named and unnamed parameters in abi.decode tuple (`uint16 , bool , uint256 ethPayout, ...`) which is invalid Solidity syntax
- **Fix:** Changed to use all unnamed with only needed variables named: `(, , uint256 ethPayout, , uint256 lootboxEth)`
- **Files modified:** test/fuzz/handlers/RedemptionHandler.sol
- **Verification:** Compilation succeeds, all 11 invariants pass
- **Committed in:** 6816a758 (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (2 bugs)
**Impact on plan:** Both fixes were necessary for correctness. No scope creep.

## Issues Encountered
None beyond the auto-fixed deviations.

## User Setup Required
None - no external service configuration required.

## Known Stubs
None - all tests are fully wired and operational.

## Next Phase Readiness
- INV-03 requirement fully satisfied at both arithmetic and lifecycle levels
- Phase 52 invariant test suite complete (plans 01 and 02)
- Ready for Phase 53 (final report) or verifier pass

## Self-Check: PASSED

All files exist, all commits verified.

---
*Phase: 52-invariant-test-suite*
*Completed: 2026-03-21*
