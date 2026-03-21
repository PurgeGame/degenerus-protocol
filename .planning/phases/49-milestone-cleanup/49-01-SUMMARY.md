---
phase: 49-milestone-cleanup
plan: 01
subsystem: documentation
tags: [solidity, audit-docs, line-references, NatSpec, gas-analysis, metadata]

# Dependency graph
requires:
  - phase: 48-documentation-sync
    provides: "NatSpec additions that shifted line numbers in StakedDegenerusStonk.sol and AdvanceModule.sol"
  - phase: 47-gas-optimization
    provides: "Gas analysis document with line references needing correction"
  - phase: 46-adversarial-sweep-economic-analysis
    provides: "Warden simulation SUMMARY with spurious Phase 47 dependency"
provides:
  - "All BIT ALLOCATION MAP line refs correct for 5 non-delegatecall VRF consumers"
  - "v3.3 addendum in v3.2-rng-delta-findings.md cites correct rngGate:795 and gameOverEntropy:858/887"
  - "All ~50 line refs in 47-01-gas-analysis.md match current StakedDegenerusStonk.sol"
  - "46-01-SUMMARY.md dependency graph corrected (no spurious Phase 47 dependency)"
affects: [audit-docs, C4A-submission]

# Tech tracking
tech-stack:
  added: []
  patterns: []

key-files:
  created: []
  modified:
    - contracts/modules/DegenerusGameAdvanceModule.sol
    - audit/v3.2-rng-delta-findings.md
    - .planning/phases/47-gas-optimization/47-01-gas-analysis.md
    - .planning/phases/46-adversarial-sweep-economic-analysis/46-01-SUMMARY.md

key-decisions:
  - "48-01-SUMMARY.md already had correct requirements-completed [DOC-01, DOC-02, DOC-03] -- no change needed"
  - "INITIAL_SUPPLY reference corrected from :207 to :205 (plan did not specify this but verification caught it)"

patterns-established: []

requirements-completed: [ANOMALY-1, ANOMALY-2, ANOMALY-3]

# Metrics
duration: 6min
completed: 2026-03-21
---

# Phase 49 Plan 01: Stale Line Reference Cleanup Summary

**Corrected all stale line references across BIT ALLOCATION MAP, v3.3 addendum, and gas analysis document -- 60+ line numbers updated to match current source**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-21T12:52:54Z
- **Completed:** 2026-03-21T12:59:42Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Fixed 5 stale line references in BIT ALLOCATION MAP comment block (BurnieCoinflip.sol:809, AdvanceModule.sol:795, BurnieCoinflip.sol:783-788, AdvanceModule.sol:826, AdvanceModule.sol:1033)
- Fixed 2 cross-reference comments in _gameOverEntropy referencing rngGate lines 792-802
- Corrected v3.3 addendum to cite rngGate:795 and _gameOverEntropy:858/887
- Updated ~50 line references in 47-01-gas-analysis.md across 7 variable declarations, 8 functions, and 3 packing opportunity analyses
- Removed spurious Phase 47 dependency from 46-01-SUMMARY.md
- Verified forge build passes (comment-only changes)

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix BIT ALLOCATION MAP and v3.3 addendum line references** - `1375ac25` (fix)
2. **Task 2: Fix gas analysis line refs and SUMMARY metadata** - `cf046bc4` (fix)

## Files Created/Modified
- `contracts/modules/DegenerusGameAdvanceModule.sol` - Corrected BIT ALLOCATION MAP (5 refs), cross-reference comments (2 refs)
- `audit/v3.2-rng-delta-findings.md` - Corrected v3.3 addendum line references
- `.planning/phases/47-gas-optimization/47-01-gas-analysis.md` - Corrected ~50 stale line references across all variable/function analyses
- `.planning/phases/46-adversarial-sweep-economic-analysis/46-01-SUMMARY.md` - Removed spurious Phase 47 dependency

## Decisions Made
- 48-01-SUMMARY.md already had correct `requirements-completed: [DOC-01, DOC-02, DOC-03]` -- the milestone audit flagged it as empty but it was populated before this plan executed. No change needed.
- INITIAL_SUPPLY reference in gas analysis corrected from :207 to :205 (discovered during verification; plan correction map referenced :207 but did not include an explicit correction for it)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] INITIAL_SUPPLY line reference correction**
- **Found during:** Task 2 (gas analysis line refs)
- **Issue:** Gas analysis referenced `StakedDegenerusStonk.sol:207` for INITIAL_SUPPLY but actual location is line 205
- **Fix:** Updated both occurrences of `:207` to `:205` in the gas analysis document
- **Files modified:** `.planning/phases/47-gas-optimization/47-01-gas-analysis.md`
- **Verification:** Confirmed INITIAL_SUPPLY declared at line 205 via grep
- **Committed in:** cf046bc4 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Minor correction not in plan's explicit correction map. No scope creep.

## Issues Encountered
- `.planning/` directory is in .gitignore; required `git add -f` for planning files. Standard workflow for this repo.

## Known Stubs
None -- all changes are comment/documentation corrections with no code stubs.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All stale line references corrected across audit docs and contract comments
- Ready for 49-02 plan execution (remaining milestone cleanup tasks)
- Forge build passes, confirming comment-only changes have no compilation impact

## Self-Check: PASSED

All files verified present. All commit hashes verified in git log.

---
*Phase: 49-milestone-cleanup*
*Completed: 2026-03-21*
