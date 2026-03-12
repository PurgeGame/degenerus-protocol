---
phase: 09-level-progression-and-endgame
plan: 02
subsystem: audit
tags: [activity-score, death-clock, game-over, terminal-distribution, distress-mode, mint-streak]

# Dependency graph
requires:
  - phase: 07-jackpot-and-decimator
    provides: Jackpot phase draw mechanics referenced by terminal distribution
  - phase: 06-eth-inflow-and-pool-architecture
    provides: Pool architecture and nextPool/futurePool mechanics
provides:
  - Activity score BPS computation formulas for all player types
  - Death clock three-stage escalation timeline with exact Solidity
  - Terminal distribution flow with deity refund, decimator, and terminal jackpot
  - Final sweep 30-day claim window mechanics
  - Lootbox EV multiplier and degenerette ROI consumer thresholds
affects: [10-steth-yield, 11-parameter-reference]

# Tech tracking
tech-stack:
  added: []
  patterns: [piecewise-linear-curve-documentation, three-stage-escalation-timeline]

key-files:
  created: [audit/v1.1-endgame-and-activity.md]
  modified: []

key-decisions:
  - "Documented WWXRP ROI exceeding 100% as explicit agent-facing note (109.9% at max activity)"
  - "Highlighted lvl+1 terminal jackpot targeting as primary pitfall with dedicated callout box"
  - "Included full _playerActivityScore Solidity for agent cross-reference (DegenerusGame.sol:2387-2463)"

patterns-established:
  - "Escalation timeline diagram: visual countdown format for multi-stage time-based mechanics"
  - "Consumer threshold table pattern: link activity score to all downstream reward systems"

requirements-completed: [LEVL-04, END-01, END-02]

# Metrics
duration: 5min
completed: 2026-03-12
---

# Phase 9 Plan 2: Endgame and Activity Summary

**Activity score BPS formulas for three player types with lootbox/degenerette consumer thresholds, three-stage death clock escalation timeline, terminal distribution with lvl+1 targeting, and 30-day final sweep mechanics**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-12T15:35:46Z
- **Completed:** 2026-03-12T15:41:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Complete activity score component breakdown for base, pass-holder, and deity players with exact BPS values
- Mint streak mechanics with storage layout, gap detection, and idempotency semantics
- Three-stage death clock timeline (imminent/distress/game over) with exact Solidity for all checks
- RNG fallback mechanism documenting historical VRF word hashing for game termination guarantee
- Full terminal distribution flow: deity refund, decimator 10%, terminal jackpot 90% (lvl+1), vault sweep
- Final sweep 30-day window with claimable forfeiture and 50/50 vault/DGNRS split
- Consumer threshold tables for lootbox EV (80%-135%) and degenerette ROI (90%-99.9%)
- Agent simulation pseudocode for activity score, death clock, and terminal distribution

## Task Commits

Each task was committed atomically:

1. **Task 1: Create endgame and activity score reference document** - `16d3ef6f` (feat)

**Plan metadata:** [pending]

## Files Created/Modified
- `audit/v1.1-endgame-and-activity.md` - Activity score system, death clock escalation, terminal distribution, and final sweep reference document for game theory agents

## Decisions Made
- Documented WWXRP ROI exceeding 100% as explicit agent-facing note (109.9% at max activity score) since this is a positive-EV scenario agents must model
- Highlighted lvl+1 terminal jackpot targeting as the primary pitfall with a dedicated callout box -- this is the single most counterintuitive detail in the endgame
- Included the complete `_playerActivityScore` Solidity function (77 lines) for agent cross-reference rather than just a summary, following the established pattern from Phase 8

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 9 complete (both plans delivered)
- Activity score and death clock mechanics ready for Phase 11 parameter reference consolidation
- Terminal distribution formulas cross-reference Phase 7 jackpot draw mechanics

---
*Phase: 09-level-progression-and-endgame*
*Completed: 2026-03-12*
