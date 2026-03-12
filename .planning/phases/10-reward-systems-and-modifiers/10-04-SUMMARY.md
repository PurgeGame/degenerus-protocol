---
phase: 10-reward-systems-and-modifiers
plan: 04
subsystem: steth-yield
tags: [steth, lido, yield, payout-ordering, rebasing]

requires:
  - phase: 06-eth-inflows-and-pool-architecture
    provides: pool architecture (currentPrizePool, nextPrizePool, claimablePool, futurePrizePool)
provides:
  - stETH integration mechanics (admin staking, auto-staking, yield surplus formula)
  - Payout ordering documentation (ETH-first vs stETH-first)
  - DGNRS burn stETH composition
affects: [11-parameter-reference]

tech-stack:
  added: []
  patterns: [passive-surplus-yield, dual-payout-ordering, approve-pull-deposit]

key-files:
  created: [audit/v1.1-steth-yield.md]
  modified: []

key-decisions:
  - "Included AdvanceModule _autoStakeExcessEth as third stETH entry path alongside admin functions"
  - "Documented DGNRS burn stETH composition with full value formula for agent use"

patterns-established:
  - "Passive surplus pattern: yield has no distribution mechanism, just balance growth"
  - "Dual payout ordering: ETH-first for players, stETH-first for contracts"

requirements-completed: [STETH-01, STETH-02]

duration: 2min
completed: 2026-03-12
---

# Phase 10 Plan 04: stETH Yield Integration Summary

**stETH yield as passive surplus with admin staking constraints, dual payout ordering (ETH-first vs stETH-first), and DGNRS burn composition formula**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-12T16:09:15Z
- **Completed:** 2026-03-12T16:11:45Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Documented admin staking (adminStakeEthForStEth) and rebalancing (adminSwapEthForStEth) with claimablePool constraint
- Documented auto-staking during level transitions via AdvanceModule
- Exact yieldPoolView formula with passive surplus pitfall prominently documented
- Dual payout ordering with full Solidity for both paths (ETH-first and stETH-first)
- DGNRS burn stETH composition with agent-ready value formula
- stETH rounding pitfall documented with fallback handling explanation

## Task Commits

Each task was committed atomically:

1. **Task 1: Create stETH yield integration reference document** - `6bcff4ea` (feat)

## Files Created/Modified
- `audit/v1.1-steth-yield.md` - stETH yield integration reference document (7 sections, 447 lines)

## Decisions Made
- Included AdvanceModule `_autoStakeExcessEth` as a third stETH entry path beyond the two admin functions specified in the plan -- it is critical for agents to understand that staking also happens automatically during level transitions
- Documented DGNRS burn composition with full value formula (`totalMoney * amount / totalSupply`) for direct agent consumption

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- stETH yield mechanics fully documented for parameter reference consolidation in Phase 11
- All four obligation pools referenced in yield formula link back to Phase 6 pool architecture documentation

---
*Phase: 10-reward-systems-and-modifiers*
*Completed: 2026-03-12*
