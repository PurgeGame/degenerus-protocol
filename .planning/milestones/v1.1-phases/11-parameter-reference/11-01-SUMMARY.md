---
phase: 11-parameter-reference
plan: 01
subsystem: documentation
tags: [solidity, constants, bps, parameter-reference, audit]

# Dependency graph
requires:
  - phase: 06-eth-flow-analysis
    provides: Pool architecture and ETH inflow constant descriptions
  - phase: 07-jackpot-mechanics
    provides: Jackpot distribution and transition constant descriptions
  - phase: 08-token-economics
    provides: BURNIE supply, coinflip, and lootbox EV constant descriptions
  - phase: 09-level-and-activity
    provides: Level progression, activity score, and endgame constant descriptions
  - phase: 10-reward-systems
    provides: DGNRS, deity, affiliate, quest, and stETH constant descriptions
provides:
  - Master lookup table for all ~200+ protocol constants with values, units, purposes, and locations
  - Alphabetical cross-reference index for instant constant lookup
  - Scale convention reference (BPS, half-BPS, PPM)
  - Deity boon probability table with 3-scenario columns
affects: [game-theory-agents, future-audits]

# Tech tracking
tech-stack:
  added: []
  patterns: [constant-lookup-table, cross-reference-index, unit-disambiguation]

key-files:
  created: [audit/v1.1-parameter-reference.md]
  modified: []

key-decisions:
  - "Separated BURNIE-denominated constants from ETH constants to prevent ether-suffix unit confusion"
  - "PPM constants in dedicated subsections with explicit scale notes"
  - "Included 3-scenario deity boon probability columns (all/no-dec/no-dec-no-deity)"

patterns-established:
  - "Constant table format: Name | Value | Human | Purpose | File:Line | Audit Ref"
  - "Scale warning callouts for non-standard units (half-BPS, PPM)"

requirements-completed: [PARM-01, PARM-02, PARM-03]

# Metrics
duration: 4min
completed: 2026-03-12
---

# Phase 11 Plan 01: Parameter Reference Summary

**Master lookup of all ~200+ Degenerus protocol constants organized by type (BPS/ETH/timing/operational) with values, units, purposes, file:line locations, and audit cross-references**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-12T16:37:33Z
- **Completed:** 2026-03-12T16:41:33Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- 731-line parameter reference document consolidating all protocol constants
- All ~60 BPS constants with half-BPS and PPM variants explicitly flagged
- All ~30 ETH/pricing constants with BURNIE-denominated values separated to prevent unit confusion
- All ~15 timing constants including implicit inline values (120-day timeout, 5-day final window)
- Complete deity boon weight table with 3-scenario probability columns
- Alphabetical cross-reference index covering every constant name

## Task Commits

Each task was committed atomically:

1. **Task 1: Write parameter reference sections 1-7** - `f5438ed5` (feat)

## Files Created/Modified
- `audit/v1.1-parameter-reference.md` - Master parameter reference for all protocol constants

## Decisions Made
- Separated BURNIE-denominated constants from ETH constants into distinct subsections to prevent ether-suffix unit confusion
- PPM constants given dedicated subsections with explicit "divide by 1,000,000" scale notes
- Included degenerette min bet summary table for quick cross-token comparison
- Packed constants documented with unpacked sub-value notes rather than full expansion

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- This is the final phase of the v1.1 milestone
- All protocol constants are now documented in a single reference document
- Game theory agents can look up any constant by name via the cross-reference index

## Self-Check: PASSED

- FOUND: audit/v1.1-parameter-reference.md
- FOUND: commit f5438ed5

---
*Phase: 11-parameter-reference*
*Completed: 2026-03-12*
