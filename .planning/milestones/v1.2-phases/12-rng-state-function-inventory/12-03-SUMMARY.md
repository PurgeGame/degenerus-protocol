---
phase: 12-rng-state-function-inventory
plan: 03
subsystem: audit
tags: [rng, vrf, chainlink, data-flow, call-graph, security-audit]

# Dependency graph
requires:
  - phase: 12-01
    provides: RNG storage variable inventory with lifecycle traces
  - phase: 12-02
    provides: RNG function catalogue with guard analysis

provides:
  - "Daily RNG data flow: VRF callback through rngWordCurrent/rngWordByDay to 9 consumption points"
  - "Lootbox RNG data flow: requestLootboxRng through lootboxRngWordByIndex to 8 consumption points"
  - "Mid-day ticket flow trace with buffer swap, VRF callback, and lastLootboxRngWord lifecycle"
  - "Call graphs for all 27 external entry points grouped by RNG role (producer/consumer/influencer/guard)"
  - "Cross-reference matrix: entry point x vars written/read/guards/lock/freeze callability"

affects: [13-rng-delta-verification, 14-manipulation-window-analysis, 15-rng-adversarial-analysis]

# Tech tracking
tech-stack:
  added: []
  patterns: [ascii-data-flow-diagrams, call-graph-with-guard-annotation, cross-reference-matrix]

key-files:
  created: [audit/v1.2-rng-data-flow.md]
  modified: []

key-decisions:
  - "Documented stale-word recycling path (cross-day VRF word routed to lootbox index then fresh daily request) as explicit flow diagram"
  - "Identified piggyback pattern: daily VRF finalization also writes to pending lootbox index via _finalizeLootboxRng"
  - "Classified 27 entry points into 4 RNG roles: 3 producers, 6 consumers, 7+ influencers, 2 guards"

patterns-established:
  - "Call graph format: entry point -> internal calls -> READS/WRITES annotations with line numbers"
  - "Cross-reference matrix format: entry point x vars written, vars read, guards, lock callability, freeze callability"

requirements-completed: [RVAR-03, RFN-03]

# Metrics
duration: 4min
completed: 2026-03-14
---

# Phase 12 Plan 03: RNG Data Flow & Call Graphs Summary

**VRF entropy traced from Chainlink callback to all 17 consumption points across daily/lootbox/mid-day paths, with call graphs for 27 entry points and cross-reference matrix for Phase 14 manipulation analysis**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-14T17:35:12Z
- **Completed:** 2026-03-14T17:39:30Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Traced daily RNG data flow from `rawFulfillRandomWords` through nudge application (`_applyDailyRng`) to 9 downstream consumers: coinflip, daily jackpots (ETH/coin/tickets), BAF, decimator, winning traits, early-bird lootbox, final-day DGNRS reward
- Traced lootbox RNG data flow from `requestLootboxRng` through `lootboxRngWordByIndex` to 8 consumers: lootbox open (ETH/BURNIE), degenerette bets, ticket batch trait assignment, future ticket activation, deity boons, mint data
- Documented mid-day ticket flow lifecycle including buffer swap, VRF callback, `lastLootboxRngWord` update, and `processTicketBatch` consumption
- Built call graphs for all 27 external entry points with guard conditions, commit points, and lock/freeze reachability annotations
- Created cross-reference matrix enabling Phase 14 to analyze manipulation windows without re-reading contracts

## Task Commits

Each task was committed atomically:

1. **Task 1: VRF callback data flow diagrams** - `c0c197ff` (feat)
2. **Task 2: External entry point call graphs to RNG mutations** - `5bb0bce8` (feat)

## Files Created/Modified
- `audit/v1.2-rng-data-flow.md` - Complete data flow document with 5 sections: daily RNG flow, lootbox RNG flow, mid-day ticket flow, entry point call graphs, cross-reference matrix

## Decisions Made
- Documented the stale-word recycling path as a separate flow diagram since it represents a non-obvious cross-path interaction between daily and lootbox RNG streams
- Identified and documented the piggyback pattern where `_finalizeLootboxRng` writes the daily finalized word to any pending lootbox index during daily processing
- Classified all 27 entry points into 4 RNG roles (producers, consumers, influencers, guards) matching the Plan 02 function catalogue categories

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- All three Phase 12 plans complete; the combined variable inventory, function catalogue, and data flow document provide a comprehensive RNG system map
- Phase 13 (delta verification) can cross-check v1.0 findings against the v1.2 inventory
- Phase 14 (manipulation window analysis) can use the cross-reference matrix directly to identify time windows where entry points can influence RNG outcomes

---
*Phase: 12-rng-state-function-inventory*
*Completed: 2026-03-14*
