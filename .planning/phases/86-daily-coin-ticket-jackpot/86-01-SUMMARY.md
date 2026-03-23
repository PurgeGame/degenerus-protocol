---
phase: 86-daily-coin-ticket-jackpot
plan: 01
subsystem: audit
tags: [burnie, coin-jackpot, jackpotCounter, winner-selection, far-future, near-future, traitBurnTicket, ticketQueue]

# Dependency graph
requires:
  - phase: 81-ticket-creation-queue-mechanics
    provides: "Ticket creation entry points trace, three key spaces (read/write/far-future) proven disjoint"
  - phase: 83-ticket-consumption-winner-selection
    provides: "Ticket consumption paths confirmed: _awardFarFutureCoinJackpot uses _tqFarFutureKey at JM:2543"
provides:
  - "Complete coin jackpot winner selection audit (both entry points, near-future + far-future)"
  - "jackpotCounter lifecycle traced across all 4 contract files (GS, AM, JM, MM)"
  - "v3.8 Category 3 cross-reference with 7 claims verified"
  - "3 INFO findings (DCJ-01, DCJ-02, DCJ-03)"
affects: [86-02, 87, 88, 89]

# Tech tracking
tech-stack:
  added: []
  patterns: [v3.8-cross-reference-verification, multi-entry-point-tracing]

key-files:
  created:
    - audit/v4.0-daily-coin-jackpot-and-counter.md
  modified: []

key-decisions:
  - "DCJ-03 silent skip of near-future coin budget assessed as intentional design per NatSpec at JM:2403-2404"
  - "DCJ-01 stale v3.8 far-future key claim (readKey -> _tqFarFutureKey) classified INFO -- documentation drift only"

patterns-established:
  - "v3.8 Category 3 cross-reference pattern: verify each prior claim with [CONFIRMED]/[DISCREPANCY] tags"

requirements-completed: [DCOIN-01, DCOIN-03, DCOIN-04]

# Metrics
duration: 6min
completed: 2026-03-23
---

# Phase 86 Plan 01: Daily Coin Jackpot & jackpotCounter Lifecycle Summary

**Both coin jackpot entry points traced end-to-end (payDailyCoinJackpot + payDailyJackpotCoinAndTickets) with 218 file:line citations, far-future _tqFarFutureKey winner selection and near-future _randTraitTicketWithIndices documented, jackpotCounter lifecycle traced across GS/AM/JM/MM (8 touchpoints), v3.8 Category 3 claims verified (1 DISCREPANCY), 3 INFO findings**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-23T15:04:41Z
- **Completed:** 2026-03-23T15:10:53Z
- **Tasks:** 2
- **Files created:** 1

## Accomplishments

- Both coin jackpot entry points (purchase phase JM:2360, jackpot phase JM:681) traced end-to-end with complete call graphs and difference table
- Far-future winner selection via `_awardFarFutureCoinJackpot` (JM:2521) documented: `ticketQueue[_tqFarFutureKey(candidate)]` at JM:2543, up to 10 samples in [lvl+5, lvl+99]
- Near-future winner selection via `_awardDailyCoinToTraitWinners` (JM:2418) documented: `_randTraitTicketWithIndices` from `traitBurnTicket[lvl]` with deity virtual entries
- jackpotCounter lifecycle fully traced across all 4 contracts: 1 declaration (GS:245), 2 writes (AM:481 reset, JM:757 increment), 5 reads (AM:224, AM:364, JM:349, JM:484, MM:971)
- counterStep computation documented with all 3 modes: normal (1), compressed (2), turbo (5)
- v3.8 Category 3 cross-reference: 7 claims verified, 5 CONFIRMED, 1 DISCREPANCY (stale readKey claim), 1 line-number drift
- 3 INFO findings documented (DCJ-01 stale key, DCJ-02 line drift, DCJ-03 silent skip)

## Task Commits

Each task was committed atomically:

1. **Task 1: Trace coin jackpot winner selection (both entry points + far-future + near-future)** - `d5f6deb1` (feat)
2. **Task 2: Trace jackpotCounter full lifecycle across all 4 contracts** - content included in Task 1 commit (same file, written atomically)

## Files Created/Modified

- `audit/v4.0-daily-coin-jackpot-and-counter.md` - Complete coin jackpot winner selection audit + jackpotCounter lifecycle, 592 lines, 218+ file:line citations

## Decisions Made

- DCJ-03 (silent skip of near-future coin budget when target level empty): Assessed as intentional design per NatSpec at JM:2403-2404 -- "Returns 0 (skip) if the chosen level has no eligible trait tickets"
- DCJ-01 (stale v3.8 far-future key reference): Classified INFO severity -- documentation drift only, no impact on current code correctness. Represents pre-v3.9 code where far-future reads used `_tqReadKey` instead of dedicated `_tqFarFutureKey`

## Deviations from Plan

None - plan executed exactly as written. Both tasks targeted the same output file, so they were written atomically in a single commit rather than requiring a second commit with no diff.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None - all sections fully populated with verified file:line citations.

## Next Phase Readiness

- Coin jackpot winner selection fully documented, ready for Plan 02 (ticket jackpot distribution)
- jackpotCounter lifecycle provides context for Phases 85, 87, 88 which reference the counter
- v3.8 Category 3 cross-reference complete, remaining categories (1, 2, 4, 5, 6) to be addressed by their respective phases

---
*Phase: 86-daily-coin-ticket-jackpot*
*Completed: 2026-03-23*
