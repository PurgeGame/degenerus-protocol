---
phase: 07-jackpot-distribution-mechanics
plan: 03
subsystem: documentation
tags: [baf, decimator, transition-jackpots, burn-tracking, lootbox, whale-pass]

# Dependency graph
requires:
  - phase: 06-eth-inflows-and-pool-architecture
    provides: "futurePrizePool lifecycle and pool storage layout"
provides:
  - "Complete BAF trigger schedule, pool percentages, and payout split reference"
  - "Complete Decimator burn tracking, resolution, claim mechanics reference"
  - "Combined level schedule table (levels 1-110) for BAF/Decimator triggers"
affects: [08-burnie-token-economics, 11-parameter-reference]

# Tech tracking
tech-stack:
  added: []
  patterns: [pool-variable-distinction-baseFuturePool-vs-futurePoolLocal]

key-files:
  created:
    - audit/v1.1-transition-jackpots.md
  modified: []

key-decisions:
  - "Explicit baseFuturePool vs futurePoolLocal distinction throughout all formulas per Research pitfall 3"
  - "Combined level schedule table spans 1-110 to show full 100-level cycle plus overlap"
  - "Documented claim expiry semantics (lastDecClaimRound overwrite) as critical agent-facing warning"

patterns-established:
  - "Pool variable sourcing: always specify exact variable name when referencing pool percentages"

requirements-completed: [JACK-08, JACK-09]

# Metrics
duration: 6min
completed: 2026-03-12
---

# Phase 7 Plan 3: Transition Jackpots Summary

**BAF and Decimator transition jackpot reference with trigger schedules, pool percentage formulas, burn tracking mechanics, claim windows, and combined 110-level schedule table**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-12T14:41:53Z
- **Completed:** 2026-03-12T14:48:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Documented BAF trigger schedule with exact pool percentages (10/25/20%) and Solidity expressions from EndgameModule
- Documented Decimator burn tracking with bucket/subbucket system, multiplier cap formula, and migration mechanics
- Documented Decimator resolution algorithm, pro-rata claim formula, 50/50 ETH/lootbox split, and claim expiry
- Created combined level schedule table covering levels 1-110 showing all BAF and Decimator triggers
- Constants reference table with 11 entries plus key storage variables section

## Task Commits

Each task was committed atomically:

1. **Task 1: Document BAF and Decimator transition jackpot mechanics** - `61b18426` (feat)

**Plan metadata:** pending

## Files Created/Modified
- `audit/v1.1-transition-jackpots.md` - Complete BAF and Decimator transition jackpot reference document (636 lines)

## Decisions Made
- Explicit `baseFuturePool` vs `futurePoolLocal` distinction maintained throughout all pool percentage references, per Research pitfall 3
- Combined level schedule table spans levels 1-110 to show the full first-century cycle plus the beginning of the second century (demonstrating the repeating pattern)
- Claim expiry semantics documented prominently with "CRITICAL" callout since `lastDecClaimRound` overwrite is a non-obvious loss condition

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- JACK-08 and JACK-09 fully addressed
- Phase 7 (all 3 plans) complete, ready for Phase 8 (BURNIE Token Economics)
- Transition jackpot document cross-references pool architecture from Phase 6

---
*Phase: 07-jackpot-distribution-mechanics*
*Completed: 2026-03-12*
