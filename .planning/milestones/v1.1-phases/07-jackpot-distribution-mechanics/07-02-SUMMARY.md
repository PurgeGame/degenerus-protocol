---
phase: 07-jackpot-distribution-mechanics
plan: 02
subsystem: audit
tags: [jackpot, distribution, trait-buckets, carryover, compressed-jackpot, burnie, lootbox]

# Dependency graph
requires:
  - phase: 06-eth-inflows-pool-architecture
    provides: currentPrizePool lifecycle and freeze mechanics (06-pool-architecture.md)
provides:
  - Complete 5-day jackpot-phase draw reference document (audit/07-jackpot-phase-draws.md)
  - Day-by-day simulation pseudocode for game theory agents
  - Constants reference table with 26 entries and source line numbers
affects: [07-03-transition-jackpots, 11-parameter-reference]

# Tech tracking
tech-stack:
  added: []
  patterns: [day-by-day flow documentation, agent simulation pseudocode appendix]

key-files:
  created:
    - audit/07-jackpot-phase-draws.md
  modified: []

key-decisions:
  - "Included agent simulation pseudocode as appendix for direct computational use"
  - "Documented compressed jackpot as physical vs logical day mapping table for clarity"
  - "Consolidated all lootbox conversion ratios in dedicated section for cross-reference"

patterns-established:
  - "Appendix pseudocode: simulatable summary for agents who need computation without full document"

requirements-completed: [JACK-03, JACK-04, JACK-05, JACK-06, JACK-07]

# Metrics
duration: 8min
completed: 2026-03-12
---

# Phase 7 Plan 2: Jackpot-Phase 5-Day Draws Summary

**5-day jackpot draw sequence with daily pool slicing (6-14% random / 100% day-5), 4 trait bucket distribution, carryover mechanics, compressed mode, and BURNIE parallel payouts**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-12T14:42:19Z
- **Completed:** 2026-03-12T14:50:00Z
- **Tasks:** 1
- **Files created:** 1

## Accomplishments
- Documented complete day-by-day jackpot phase flow with exact Solidity expressions and line references
- Covered all 9 sections: overview, daily pool slice, trait buckets, early-bird, carryover, compressed jackpot, lootbox conversion, BURNIE distribution, constants table
- 26-entry constants reference table with source file and line numbers
- Agent simulation pseudocode enabling day-by-day computation without contract source

## Task Commits

Each task was committed atomically:

1. **Task 1: Document 5-day jackpot-phase draw sequence with trait buckets and carryover** - `da7e0c71` (feat)

**Plan metadata:** (pending)

## Files Created/Modified
- `audit/07-jackpot-phase-draws.md` - Complete 5-day jackpot-phase draw reference (645 lines)

## Decisions Made
- Included agent simulation pseudocode as an appendix section to enable direct computational use by game theory agents
- Documented compressed jackpot physical vs logical day mapping as a table rather than prose for agent parseability
- Consolidated lootbox conversion ratios from all jackpot-phase sources into a single cross-reference table

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Jackpot-phase draw mechanics complete, ready for 07-03 (BAF and Decimator transition jackpots)
- The document references 07-03 for transition jackpots that fire after day 5

---
*Phase: 07-jackpot-distribution-mechanics*
*Completed: 2026-03-12*
