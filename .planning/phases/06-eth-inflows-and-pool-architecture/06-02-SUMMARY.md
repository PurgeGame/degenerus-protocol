---
phase: 06-eth-inflows-and-pool-architecture
plan: 02
subsystem: documentation
tags: [solidity, prize-pool, packed-storage, freeze-mechanics, level-advancement, jackpot]

# Dependency graph
requires:
  - phase: 06-eth-inflows-and-pool-architecture
    provides: "06-RESEARCH.md with extracted pool constants and transition functions"
provides:
  - "Complete pool lifecycle documentation with storage layout, transitions, freeze/unfreeze, and level advancement"
  - "Per-purchase-type pool split table with verified BPS constants"
  - "ASCII lifecycle diagram mapping every ETH wei path through the pool system"
affects: [07-ticket-purchase-lifecycle, 08-lootbox-lottery-system, 09-jackpot-mechanics, 11-parameter-reference]

# Tech tracking
tech-stack:
  added: []
  patterns: ["packed uint256 storage documentation", "pool lifecycle state machine"]

key-files:
  created:
    - audit/06-pool-architecture.md
  modified: []

key-decisions:
  - "Documented yield surplus distribution as appendix since it is an additional inflow path not covered by purchase-type splits"
  - "Included compressed jackpot mechanics (5 logical days in 3 physical) in daily payout section for completeness"

patterns-established:
  - "Pool split table format: purchase type, condition, next/future/vault BPS, source constant, source file"
  - "Transition documentation format: function name, location, trigger condition, Solidity expression"

requirements-completed: [POOL-01, POOL-02, POOL-03, POOL-04]

# Metrics
duration: 6min
completed: 2026-03-12
---

# Phase 06 Plan 02: Pool Architecture Summary

**Complete pool lifecycle documentation with packed storage layout, 4 transition triggers, 12-row split table, freeze/unfreeze mechanics, and purchase target ratchet system**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-12T14:09:35Z
- **Completed:** 2026-03-12T14:16:24Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Documented all 4 storage primitives (prizePoolsPacked, currentPrizePool, prizePoolPendingPacked, levelPrizePool) with bit layouts and 8 helper functions
- Created ASCII lifecycle diagram showing every pool transition with function names
- Documented all 4 transition triggers (future->next drawdown, next->future skim, next->current consolidation, current->claimable payout) with exact Solidity expressions
- Built 12-row pool split table covering all purchase types with verified BPS constants and source file references
- Documented complete freeze/unfreeze mechanics including multi-day jackpot pending accumulator behavior
- Documented purchase target ratchet system with BOOTSTRAP_PRIZE_POOL, normal snapshots, and x00 special case
- Documented distress mode pool override behavior with activation windows

## Task Commits

Each task was committed atomically:

1. **Task 1: Document pool storage layout and lifecycle transitions** - `10decebd` (feat)

**Plan metadata:** pending (docs: complete plan)

## Files Created/Modified
- `audit/06-pool-architecture.md` - Complete pool architecture reference document (7 sections + appendix)

## Decisions Made
- Included yield surplus distribution as an appendix since it represents an additional inflow to futurePrizePool from stETH appreciation, distinct from purchase-driven splits
- Documented compressed jackpot timing (counterStep=2, dailyBps doubled) within the daily payout section rather than as a separate section

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - documentation-only phase, no external service configuration required.

## Next Phase Readiness
- Pool architecture document ready for consumption by downstream phases (ticket lifecycle, lootbox system, jackpot mechanics)
- All BPS constants and transition triggers verified against contract source
- Level advancement ratchet system documented for parameter reference phase

---
*Phase: 06-eth-inflows-and-pool-architecture*
*Completed: 2026-03-12*
