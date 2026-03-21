---
phase: 47-gas-optimization
plan: 01
subsystem: audit
tags: [solidity, storage-layout, gas-optimization, evm, sdgnrs]

# Dependency graph
requires:
  - phase: 44-delta-audit
    provides: "Gambling burn system code changes and finding verdicts"
provides:
  - "Variable liveness verdicts for all 7 gambling burn state variables"
  - "Storage packing analysis with 3 opportunities and bit-width safety proofs"
  - "GAS-04 formal closure (no dead variables)"
affects: [47-02-gas-snapshot]

# Tech tracking
tech-stack:
  added: []
  patterns: ["Variable liveness trace with write/read/delete site enumeration", "Bit-width safety proof for storage packing proposals"]

key-files:
  created: [".planning/phases/47-gas-optimization/47-01-gas-analysis.md"]
  modified: []

key-decisions:
  - "All 7 gambling burn state variables confirmed ALIVE -- GAS-04 closed as no-op"
  - "3 packing opportunities identified: index+burned (LOW), ethBase+burnieBase (LOW-MED), struct (LOW-MED)"
  - "Implementation order: Opp 1 first (lowest risk), then Opp 2, then Opp 3"

patterns-established:
  - "Liveness analysis pattern: declaration, write sites, read sites, delete sites, verdict"
  - "Packing proposal pattern: current layout, proposed layout, bit-width safety proof, co-access pattern, gas savings, risk, code change"

requirements-completed: [GAS-01, GAS-02, GAS-04]

# Metrics
duration: 4min
completed: 2026-03-21
---

# Phase 47 Plan 01: Gas Analysis Summary

**Variable liveness analysis confirming all 7 sDGNRS gambling burn variables ALIVE, with 3 storage packing opportunities saving up to 66,300 gas per call**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-21T04:44:11Z
- **Completed:** 2026-03-21T04:48:46Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Traced all 7 new state variables with 70 line references across 42 read/write/delete sites, confirming every variable is actively used in the gambling burn lifecycle
- Documented 3 storage packing opportunities with concrete bit-width safety proofs: pack index+burned (save 1 slot, LOW risk), pack ethBase+burnieBase (save 1 slot, LOW-MED risk), pack PendingRedemption struct (save 1 slot per user, LOW-MED risk)
- Formally closed GAS-04 (dead variable elimination) as no-op -- all 7 variables are ALIVE with no candidates for removal
- Documented full storage layout (16 slots), struct layouts (PendingRedemption: 3 slots, RedemptionPeriod: 1 slot), and via_ir optimizer interaction caveat

## Task Commits

Each task was committed atomically:

1. **Task 1: Variable Liveness Analysis (GAS-01) + Dead Variable Elimination (GAS-04)** - `e39f51ad` (feat)
2. **Task 2: Storage Packing Analysis (GAS-02)** - `1e3bea0a` (feat)

## Files Created/Modified
- `.planning/phases/47-gas-optimization/47-01-gas-analysis.md` - Comprehensive gas analysis document covering GAS-01 (liveness), GAS-02 (packing), and GAS-04 (dead variable elimination)

## Decisions Made
- All 7 variables confirmed ALIVE -- no dead variable elimination possible (GAS-04 closed)
- 3 packing opportunities identified with ordered implementation recommendation (1 -> 2 -> 3 by ascending risk)
- uint208 chosen for redemptionPeriodBurned (108 bits headroom) over uint128 (28 bits) for extra safety since it packs with uint48 into exactly 256 bits
- via_ir optimizer caveat documented: forge snapshot diff is authoritative, theoretical savings may not fully materialize

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Gas analysis document ready for GAS-03 (forge snapshot baseline) in Plan 02
- Implementation order documented for the 3 packing changes that Plan 02 can reference
- Liveness verdicts confirm no variables need removal, simplifying the implementation plan

## Self-Check: PASSED

- [x] 47-01-gas-analysis.md exists
- [x] 47-01-SUMMARY.md exists
- [x] Commit e39f51ad (Task 1) exists
- [x] Commit 1e3bea0a (Task 2) exists

---
*Phase: 47-gas-optimization*
*Completed: 2026-03-21*
