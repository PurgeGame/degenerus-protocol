---
phase: 200-payout-reference-rewrite
plan: 02
subsystem: docs
tags: [events, solidity, jackpot, catalog, indexing]

# Dependency graph
requires:
  - phase: 199-delta-audit-skip-split-gas
    provides: audit findings F-01, F-04, F-05 identifying stale references
provides:
  - Accurate event catalog for all jackpot operations at commit fa2b9c39
  - Correct event names, signatures, emitting paths with verified line numbers
affects: [payout-reference, event-indexing, frontend-integration]

# Tech tracking
tech-stack:
  added: []
  patterns: [event catalog with cross-consistency check against payout reference]

key-files:
  created: []
  modified:
    - docs/JACKPOT-EVENT-CATALOG.md

key-decisions:
  - "Removed Section D (RewardJackpotsSettled duplicate declaration in JackpotModule) -- declaration no longer exists in JackpotModule, only in AdvanceModule"
  - "AutoRebuyProcessed removed from JackpotModule sections -- auto-rebuy info now embedded in JackpotEthWin via rebuyLevel/rebuyTickets fields"
  - "Added STAGE_JACKPOT_ETH_RESUME (8) to Advance stage constants table -- new constant for two-call ETH distribution resume"

patterns-established:
  - "Event catalog sections labeled A-K with JackpotModule first, then AdvanceModule, then DecimatorModule"

requirements-completed: [DOC-04]

# Metrics
duration: 7min
completed: 2026-04-08
---

# Phase 200 Plan 02: Event Catalog Update Summary

**Rewrote JACKPOT-EVENT-CATALOG.md with correct event names (JackpotTicketWin not JackpotTicketWinner), all 6 JackpotModule events cataloged, dead code paths purged, and line numbers verified against fa2b9c39**

## Performance

- **Duration:** 7 min
- **Started:** 2026-04-08T23:29:42Z
- **Completed:** 2026-04-08T23:36:57Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Verified audit findings F-01 (fixed), F-04/F-05 (not yet fixed -- test file, requires user approval)
- Rewrote event catalog with all 6 JackpotModule events: JackpotEthWin, JackpotTicketWin, JackpotBurnieWin, JackpotDgnrsWin, JackpotWhalePassWin, FarFutureCoinJackpotWinner
- Removed stale AutoRebuyProcessed section from JackpotModule (only DecimatorModule retains it)
- Removed stale RewardJackpotsSettled duplicate declaration section from JackpotModule
- Purged all dead code references (_resolveTraitWinners) from emitting paths
- Updated Event-to-Path Matrix to 11 rows covering all cataloged events
- Verified all emit line numbers against current source

## Task Commits

Each task was committed atomically:

1. **Task 1: Verify stale reference findings F-01, F-04, F-05** - (verification only, no files changed)
2. **Task 2: Rewrite JACKPOT-EVENT-CATALOG.md** - `39b6b20e` (docs)

## Files Created/Modified
- `docs/JACKPOT-EVENT-CATALOG.md` - Complete event catalog for jackpot operations, 11 events across 3 modules

## Decisions Made
- Removed Section D (RewardJackpotsSettled duplicate in JackpotModule) because the declaration no longer exists there
- AutoRebuyProcessed purged from JackpotModule sections; auto-rebuy is now embedded in JackpotEthWin
- Added STAGE_JACKPOT_ETH_RESUME (8) to Advance stage constants

## Deviations from Plan

### Stale Test References (F-04, F-05 NOT fixed)

Task 1 found that audit findings F-04 and F-05 from 199-02-AUDIT.md are NOT yet resolved:
- **F-04:** `test/gas/AdvanceGameGas.test.js` line 1053 still says `_distributeJackpotEth` (should be `_processDailyEth(SPLIT_NONE)`)
- **F-05:** `test/gas/AdvanceGameGas.test.js` line 1054 still says `_distributeJackpotEth` (should be `_processDailyEth(SPLIT_NONE)`)

Per project rules (NEVER commit test file changes without explicit user approval), these were documented but NOT edited.

F-01 (GameOverModule.sol line 170) IS correctly fixed in the working tree.

---

**Total deviations:** 0 auto-fixed. 2 unfixed items documented for user approval.
**Impact on plan:** Documentation plan unaffected; test comment fixes deferred.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Event catalog is complete and accurate for commit fa2b9c39
- F-04/F-05 test comment fixes still need user approval and separate commit
