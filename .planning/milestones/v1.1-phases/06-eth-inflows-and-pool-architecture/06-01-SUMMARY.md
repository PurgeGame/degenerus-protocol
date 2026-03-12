---
phase: 06-eth-inflows-and-pool-architecture
plan: 01
subsystem: audit
tags: [solidity, eth-inflows, pool-splits, bps-constants, purchase-paths, presale]

# Dependency graph
requires: []
provides:
  - "Complete ETH inflow documentation for all purchase types with exact Solidity cost formulas"
  - "Pool split summary table with BPS values for every purchase type and condition"
  - "Presale vs post-presale feature comparison with toggle conditions"
  - "27 contract constants cross-referenced with source file and line number"
affects: [06-02-pool-architecture, 07-rng-and-lootbox, 11-parameter-reference]

# Tech tracking
tech-stack:
  added: []
  patterns: [constant-cross-reference-table, pitfall-callout-boxes]

key-files:
  created:
    - audit/06-eth-inflows.md
  modified: []

key-decisions:
  - "Structured document by purchase type (9 sections) for agent consumption rather than by contract file"
  - "Added constant cross-reference table with exact source file and line numbers for every BPS value"
  - "Included 14-row pool split summary table covering all conditions including distress mode"

patterns-established:
  - "Constant cross-reference: every numeric constant includes source file and line for verification"
  - "Pitfall callout boxes: common misunderstandings highlighted in blockquote format"

requirements-completed: [INFLOW-01, INFLOW-02, INFLOW-03, INFLOW-04]

# Metrics
duration: 3min
completed: 2026-03-12
---

# Phase 6 Plan 01: ETH Inflows Summary

**Complete ETH inflow reference documenting all 6 purchase types, BURNIE conversion paths, degenerette wagers, and presale/post-presale differences with 27 verified BPS constants**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-12T14:09:26Z
- **Completed:** 2026-03-12T14:12:46Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Documented all 6 ETH purchase paths (ticket, lootbox, whale bundle, lazy pass, deity pass, degenerette) with exact Solidity cost formulas
- Documented BURNIE-to-ticket and BURNIE-lootbox paths showing zero ETH pool contribution and virtual ETH formula for RNG threshold
- Created pool split summary table with 14 rows covering all purchase types, presale/post-presale, and distress conditions
- Cross-referenced 27 BPS constants against contract source with exact file and line numbers
- Documented presale vs post-presale feature comparison with auto-end toggle conditions

## Task Commits

Each task was committed atomically:

1. **Task 1: Document all ETH purchase paths with exact cost formulas** - `c58a8c5b` (feat)

**Plan metadata:** [pending]

## Files Created/Modified

- `audit/06-eth-inflows.md` - Complete ETH inflow reference with cost formulas, pool splits, presale comparison, and constant cross-reference

## Decisions Made

- Structured document by purchase type (9 sections) for agent consumption rather than by contract file
- Added a dedicated constant cross-reference table (27 entries) with source file and line numbers for auditability
- Included 14-row pool split summary table covering all purchase type + condition combinations including distress mode

## Deviations from Plan

None -- plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None -- documentation-only phase, no external service configuration required.

## Next Phase Readiness

- ETH inflow documentation complete, ready for Plan 02 (Pool Architecture and Lifecycle)
- All pool split BPS values documented and available for cross-reference by pool lifecycle analysis

---
*Phase: 06-eth-inflows-and-pool-architecture*
*Completed: 2026-03-12*

## Self-Check: PASSED
