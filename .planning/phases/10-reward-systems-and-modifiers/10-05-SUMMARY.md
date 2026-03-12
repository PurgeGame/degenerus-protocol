---
phase: 10-reward-systems-and-modifiers
plan: 05
subsystem: documentation
tags: [quests, burnie, streak, shields, activity-score, daily-rewards]

# Dependency graph
requires:
  - phase: 08-burnie-token-and-coinflip
    provides: BURNIE coinflip mechanics for reward crediting path
  - phase: 09-level-progression-and-endgame
    provides: Activity score formula that quest streak contributes to
provides:
  - Quest type table with all 9 types, targets, slot eligibility, and draw weights
  - Slot 0 prerequisite rule documentation
  - Streak mechanics with shield protection and version gating
  - Quest streak activity score contribution formula
  - Decimator quest availability conditions
affects: [11-parameter-reference]

# Tech tracking
tech-stack:
  added: []
  patterns: [quest-reward-routing-via-coinflip-credit]

key-files:
  created: [audit/v1.1-quest-rewards.md]
  modified: []

key-decisions:
  - "Documented slot 0 prerequisite as CRITICAL PITFALL since it forces daily ETH purchase"
  - "Included full _questTargetValue and _canRollDecimatorQuest Solidity for agent cross-reference"
  - "Documented combo completion mechanic enabling 300 BURNIE single-transaction rewards"

patterns-established:
  - "Quest reward routing: all rewards credited as coinflip stakes via creditFlip, not direct BURNIE mint"

requirements-completed: [QRWD-01, QRWD-02]

# Metrics
duration: 2min
completed: 2026-03-12
---

# Phase 10 Plan 05: Quest Rewards Summary

**9-type daily quest system with fixed BURNIE rewards (100+200/day), weighted slot rolling, streak shields, and 100% activity score cap from quest engagement**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-12T16:09:42Z
- **Completed:** 2026-03-12T16:12:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Documented all 9 quest types with IDs, targets, slot eligibility, and draw weights
- Documented slot 0 MINT_ETH prerequisite rule with exact Solidity check
- Documented streak system including shield consumption, version gating, and combo completion
- Documented quest streak as largest single activity score component (+1%/day, cap 100%)
- Complete constants reference table with source file and line numbers

## Task Commits

Each task was committed atomically:

1. **Task 1: Create quest rewards reference document** - `2b0610ab` (feat)

**Plan metadata:** [pending final commit] (docs: complete plan)

## Files Created/Modified
- `audit/v1.1-quest-rewards.md` - Complete quest reward system reference for game theory agents

## Decisions Made
- Documented slot 0 prerequisite as CRITICAL PITFALL since it forces daily ETH purchase activity before bonus quest completion
- Included full Solidity for key functions (_questTargetValue, _canRollDecimatorQuest, _questSyncState) for agent cross-reference
- Documented combo completion mechanic where completing one slot can auto-complete the paired slot

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Quest reward documentation complete, ready for Phase 11 parameter reference consolidation
- Cross-references to audit/v1.1-endgame-and-activity.md for full activity score integration

---
*Phase: 10-reward-systems-and-modifiers*
*Completed: 2026-03-12*
