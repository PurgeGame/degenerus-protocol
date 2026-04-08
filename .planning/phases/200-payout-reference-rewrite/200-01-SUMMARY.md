---
phase: 200-payout-reference-rewrite
plan: 01
subsystem: docs
tags: [jackpot, payout, skip-split, _processDailyEth, gas-safety]

# Dependency graph
requires:
  - phase: 199-delta-audit-skip-split-gas
    provides: "Verified caller paths, parity analysis, gas derivation figures"
provides:
  - "Fully rewritten JACKPOT-PAYOUT-REFERENCE.md with unified _processDailyEth and skip-split architecture"
affects: [200-02, event-catalog]

# Tech tracking
tech-stack:
  added: []
  patterns: []

key-files:
  created: []
  modified:
    - docs/JACKPOT-PAYOUT-REFERENCE.md

key-decisions:
  - "Preserved section numbering 1-13 to avoid breaking cross-references from JACKPOT-EVENT-CATALOG.md"
  - "Gas safety margins table uses exact figures from 199-01-GAS-DERIVATION.md (not rounded)"
  - "Added isJackpotPhase gating subsection to section 13 (not in original document) for completeness"

patterns-established:
  - "Split behavior documented as conditional paths within each jackpot type section, not as separate sections"

requirements-completed: [DOC-01, DOC-02, DOC-03]

# Metrics
duration: 4min
completed: 2026-04-08
---

# Phase 200 Plan 01: Payout Reference Rewrite Summary

**JACKPOT-PAYOUT-REFERENCE.md rewritten for unified _processDailyEth with conditional SPLIT_NONE / SPLIT_CALL1+SPLIT_CALL2 architecture, zero stale references to deleted code**

## Performance

- **Duration:** 4 min
- **Started:** 2026-04-08T23:30:11Z
- **Completed:** 2026-04-08T23:34:23Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Rewrote all 13 sections of JACKPOT-PAYOUT-REFERENCE.md to reflect the unified `_processDailyEth` with conditional skip-split architecture from Phase 198
- Documented both SPLIT_NONE (single call, totalWinners <= 160) and SPLIT_CALL1+SPLIT_CALL2 (two calls, totalWinners > 160) as conditional paths in sections 3, 5, and 13
- Eliminated all references to deleted `_distributeJackpotEth`, `_processOneBucket`, and `JackpotEthCtx` (0 matches verified via grep)
- Updated sections 6 (early-burn) and 8 (terminal) to reference `_runJackpotEthFlow` and `runTerminalJackpot` with correct `splitMode=SPLIT_NONE, isJackpotPhase=false` parameters
- Added gas safety margins table with 5 rows from 199-01-GAS-DERIVATION.md (skip-split, call 1, call 2, early-burn, terminal)
- Added SPLIT_NONE/SPLIT_CALL1/SPLIT_CALL2 constants to Key Constants table (section 2)
- Added isJackpotPhase gating documentation explaining whale pass and DGNRS control
- Set verified-against commit hash to `fa2b9c39`

## Task Commits

Each task was committed atomically:

1. **Task 1: Rewrite JACKPOT-PAYOUT-REFERENCE.md from scratch** - `530ab52b` (docs)

## Files Created/Modified

- `docs/JACKPOT-PAYOUT-REFERENCE.md` - Complete payout reference for all 8 jackpot types with current function names, conditional split architecture, and gas safety margins

## Decisions Made

- Preserved section numbering (1-13) to avoid breaking any cross-references from JACKPOT-EVENT-CATALOG.md
- Gas figures taken directly from 199-01-GAS-DERIVATION.md without additional rounding (source already uses conservative ceilings)
- Added isJackpotPhase gating as a subsection of section 13 (Conditional Split Details) since it is integral to understanding how split behavior differs across caller paths

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - documentation-only changes.

## Next Phase Readiness

- JACKPOT-PAYOUT-REFERENCE.md is complete and verified against current contract code
- Ready for plan 200-02 (JACKPOT-EVENT-CATALOG.md update)

## Self-Check: PASSED

- docs/JACKPOT-PAYOUT-REFERENCE.md: FOUND
- .planning/phases/200-payout-reference-rewrite/200-01-SUMMARY.md: FOUND
- Commit 530ab52b: FOUND
- SPLIT_NONE count: 16 (>= 5)
- SPLIT_CALL1 count: 9 (>= 3)
- _processDailyEth count: 7 (>= 5)
- _distributeJackpotEth count: 0
- _processOneBucket count: 0
- JackpotEthCtx count: 0
- isJackpotPhase count: 6 (>= 3)
- Verified-against: fa2b9c39

---
*Phase: 200-payout-reference-rewrite*
*Completed: 2026-04-08*
