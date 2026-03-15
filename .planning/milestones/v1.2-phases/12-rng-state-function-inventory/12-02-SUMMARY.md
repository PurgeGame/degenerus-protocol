---
phase: 12-rng-state-function-inventory
plan: 02
subsystem: audit
tags: [rng, vrf, chainlink, solidity, security-audit, guard-analysis]

requires:
  - phase: 12-01
    provides: RNG storage variable inventory with lifecycle traces

provides:
  - Complete catalogue of 60+ RNG-touching functions across all modules
  - 27 external entry points with access control and lock/freeze callability
  - Guard condition analysis for rngLockedFlag (19 sites), prizePoolFrozen (11 sites), and 5 other guard types
  - v1.0 audit cross-reference with delta analysis

affects: [12-03, 13-rng-attack-surface-mapping, 14-rng-adversarial-analysis]

tech-stack:
  added: []
  patterns: [function-catalogue-with-access-patterns, guard-condition-matrix]

key-files:
  created:
    - audit/v1.2-rng-functions.md
  modified: []

key-decisions:
  - "Catalogued BurnieCoinflip guards as external-call pattern (reads rngLockedFlag via view function, not direct storage access)"
  - "Counted 19 rngLockedFlag check sites vs v1.0 audit's 3 -- gap due to v1.0 scoping only to changed code, not pre-existing guards"

patterns-established:
  - "Guard analysis format: per-guard subsection with check sites table, assessment, and cross-reference"

requirements-completed: [RFN-01, RFN-02, RFN-04]

duration: 7min
completed: 2026-03-14
---

# Phase 12 Plan 02: RNG Function Catalogue Summary

**60+ RNG-touching functions catalogued with access patterns, 27 external entry points mapped, guard analysis covering 19 rngLockedFlag sites and 11 prizePoolFrozen sites with v1.0 cross-reference**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-14T17:25:27Z
- **Completed:** 2026-03-14T17:31:58Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Complete function catalogue across all 12 modules, main contract, storage, and BurnieCoinflip with exact line numbers, visibility, and access patterns
- 27 external entry points identified with access control details and lock/freeze callability matrix
- Guard condition analysis for 7 guard types: rngLockedFlag (19 sites), prizePoolFrozen (11 sites), rngRequestTime (8 sites), ticketsFullyProcessed (7 sites), midDayTicketRngPending (3 sites), lootboxRngWordByIndex zero-check (5 sites), and LINK/threshold gates (2 sites)
- Delta analysis against v1.0 audit: confirmed all lock removals still removed, identified new BurnieCoinflip guards not in v1.0 scope

## Task Commits

Each task was committed atomically:

1. **Task 1: Catalogue all RNG-touching functions and external entry points** - `d0b4f1b9` (feat)
2. **Task 2: Guard condition analysis** - `9ac9dacc` (feat)

## Files Created/Modified
- `audit/v1.2-rng-functions.md` - Complete RNG function catalogue with three sections: function catalogue, external entry points, guard analysis

## Decisions Made
- Included BurnieCoinflip external-call guards (reads rngLockedFlag via degenerusGame.rngLocked() view function) in the guard inventory since they are functionally equivalent to direct storage guards
- Documented 19 total rngLockedFlag check sites vs v1.0 audit's count of 3 -- the delta is due to v1.0 scoping only to code changed in that milestone, while this inventory is comprehensive

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Function catalogue and guard analysis complete, ready for Plan 03 (cross-reference matrix)
- All downstream phases (13-15) have the function-side inventory they need

---
*Phase: 12-rng-state-function-inventory*
*Completed: 2026-03-14*
