---
phase: 12-rng-state-function-inventory
plan: 01
subsystem: audit
tags: [rng, vrf, storage-layout, evm-slots, chainlink, security-audit]

# Dependency graph
requires: []
provides:
  - "Complete catalogue of 8 direct RNG storage variables with EVM slot numbers, types, and full writer/reader traces"
  - "Complete catalogue of 19+ RNG-influencing storage variables across 6 categories"
  - "Detailed lifecycle traces for lastLootboxRngWord and midDayTicketRngPending with state machine diagrams"
  - "Cross-reference table linking all v1.0 audit variables to this inventory"
affects: [12-02-PLAN, 12-03-PLAN, 13-rng-delta-verification, 14-manipulation-window-analysis]

# Tech tracking
tech-stack:
  added: []
  patterns: [storage-slot-counting, variable-lifecycle-tracing, state-machine-diagramming]

key-files:
  created: [audit/v1.2-rng-storage-variables.md]
  modified: []

key-decisions:
  - "Included lastDecClaimRound.rngWord as additional direct RNG variable (struct field holding VRF copy)"
  - "Organized RNG-influencing variables into 6 subcategories: gates, queues, buckets, thresholds, nudge, decimator"
  - "Documented readKey/writeKey double-buffer mechanism explicitly for downstream analysis"

patterns-established:
  - "Variable lifecycle trace format: declaration, write sites table, read sites table, clear behavior, state machine diagram"
  - "Cross-reference table linking v1.0 audit findings to v1.2 inventory entries"

requirements-completed: [RVAR-01, RVAR-02, RVAR-04]

# Metrics
duration: 6min
completed: 2026-03-14
---

# Phase 12 Plan 01: RNG Storage Variable Inventory Summary

**Complete catalogue of 9 direct VRF entropy variables and 19+ RNG-influencing variables with EVM slot numbers, writer/reader traces, and lifecycle state machines for lastLootboxRngWord and midDayTicketRngPending**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-14T17:25:23Z
- **Completed:** 2026-03-14T17:31:28Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Catalogued all 9 direct RNG storage variables (rngWordCurrent, rngWordByDay, vrfRequestId, lootboxRngWordByIndex, lootboxRngRequestIndexById, lootboxRngIndex, lastLootboxRngWord, midDayTicketRngPending, lastDecClaimRound.rngWord) with precise EVM slot numbers and complete writer/reader/lifecycle analysis
- Catalogued 19+ RNG-influencing variables across gates (rngLockedFlag, rngRequestTime, ticketsFullyProcessed, prizePoolFrozen, jackpotPhaseFlag), double-buffer state (ticketWriteSlot, ticketQueue, ticketCursor, ticketLevel, ticketsOwedPacked), bucket composition (traitBurnTicket, deityPassOwners, deityBySymbol, dailyHeroWagers), thresholds (lootboxRngPendingEth, lootboxRngPendingBurnie, lootboxRngThreshold, lootboxRngMinLinkBalance), nudge (totalFlipReversals), and decimator (decBucketBurnTotal, decBucketOffsetPacked, decBurn)
- Created detailed lifecycle traces with state machine diagrams for lastLootboxRngWord and midDayTicketRngPending

## Task Commits

Each task was committed atomically:

1. **Task 1: Catalogue direct RNG storage variables** - `a4b003a7` (feat)
2. **Task 2: Catalogue RNG-influencing variables and lifecycle traces** - `06780825` (feat)

## Files Created/Modified
- `audit/v1.2-rng-storage-variables.md` - Complete RNG storage variable inventory with 3 sections: direct RNG vars, RNG-influencing vars, lifecycle traces

## Decisions Made
- Included `lastDecClaimRound.rngWord` as a 9th direct RNG variable since the struct field holds a copy of the VRF word used for decimator claim lootbox entropy derivation
- Organized RNG-influencing variables into 6 subcategories for clarity: gates/sequencing, double-buffer state, jackpot bucket composition, lootbox thresholds, nudge state, and decimator bucket state
- Documented the readKey/writeKey double-buffer encoding (bit 23 toggle via ticketWriteSlot) explicitly for downstream manipulation analysis

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- RNG storage variable inventory complete; provides the authoritative reference for Phase 12 Plans 02-03 (function inventory, call graph)
- All variables needed for Phase 13 (delta verification) and Phase 14 (manipulation window analysis) are documented with slot numbers and lifecycle traces
- No blockers

---
*Phase: 12-rng-state-function-inventory*
*Completed: 2026-03-14*
