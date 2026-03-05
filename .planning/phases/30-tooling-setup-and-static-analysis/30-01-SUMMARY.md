---
phase: 30-tooling-setup-and-static-analysis
plan: 01
subsystem: infra
tags: [foundry, fuzzing, coverage, tooling]

requires:
  - phase: none
    provides: N/A (first v5.0 phase)
provides:
  - Foundry deep profile with 10K fuzz / 1K invariant runs
  - Coverage baseline files for Phase 35 delta measurement
  - Documented viaIR/coverage limitation for future reference
affects: [31, 32, 33, 34, 35]

tech-stack:
  added: []
  patterns:
    - "FOUNDRY_PROFILE=deep for intensive fuzzing"
    - "Coverage baseline via test counts, not lcov (viaIR limitation)"

key-files:
  created:
    - .planning/phases/30-tooling-setup-and-static-analysis/deep-profile-results.txt
    - .planning/phases/30-tooling-setup-and-static-analysis/coverage-baseline.txt
    - .planning/phases/30-tooling-setup-and-static-analysis/lcov-baseline.info
  modified:
    - foundry.toml

key-decisions:
  - "Use --ir-minimum for coverage (stack depth requires viaIR)"
  - "Document testFuzz_weaklyMonotonicInCycle vm.assume limitation as test harness issue, not protocol bug"
  - "Phase 35 delta measurement uses test counts, not lcov line coverage due to address patching incompatibility"

patterns-established:
  - "Deep profile configuration for v5.0 phases: 10K fuzz runs, 1K invariant runs, 256 depth"

requirements-completed: [TOOL-01, TOOL-04]

duration: 8min
completed: 2026-03-05
---

# Phase 30 Plan 01: Foundry Deep Profile and Coverage Baseline Summary

**Configured Foundry deep fuzzing profile (10K/1K/256) and captured coverage baseline with documented viaIR/patching limitations**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-05T13:14:27Z
- **Completed:** 2026-03-05T13:22:52Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Added `[profile.deep.fuzz]` and `[profile.deep.invariant]` sections to foundry.toml
- Ran all 68 tests at 10K fuzz runs / 1K invariant runs: 67/68 passed
- Captured coverage baseline (24/35 tests in coverage mode due to viaIR limitation)
- Documented limitation for Phase 35 delta measurement approach

## Task Commits

1. **Task 1: Add deep profile and run fuzzing** - `f70739f` (feat)
2. **Task 2: Capture coverage baseline** - `627021e` (feat)

## Files Created/Modified

- `foundry.toml` - Added [profile.deep.fuzz] and [profile.deep.invariant] sections
- `.planning/phases/30-tooling-setup-and-static-analysis/deep-profile-results.txt` - Full test output at deep settings
- `.planning/phases/30-tooling-setup-and-static-analysis/coverage-baseline.txt` - forge coverage summary output
- `.planning/phases/30-tooling-setup-and-static-analysis/lcov-baseline.info` - LCOV format with limitation documentation

## Decisions Made

1. **Deep fuzzing at 10K/1K/256:** Matches research recommendation. Default profile unchanged for fast iteration.
2. **testFuzz_weaklyMonotonicInCycle failure:** At 10K runs, vm.assume rejects too many inputs (>131K). This is a test harness constraint issue (multiple vm.assume with narrow ranges), not a protocol bug. The property itself is valid.
3. **Coverage viaIR limitation:** forge coverage disables viaIR by default, causing stack-too-deep errors. Using `--ir-minimum` changes bytecode, breaking ContractAddresses patching. Phase 35 delta measurement should use test pass/fail counts as baseline, not lcov line coverage.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] CLI flag correction**
- **Found during:** Task 1 (deep profile run)
- **Issue:** `--invariant-runs` is not a valid forge test flag
- **Fix:** Removed flag; invariant runs controlled by [profile.deep.invariant] in foundry.toml
- **Files modified:** N/A (command-line only)
- **Verification:** Test run completed successfully
- **Committed in:** Part of f70739f

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Minor CLI syntax correction. No scope creep.

## Issues Encountered

1. **forge coverage viaIR incompatibility:** Without viaIR, contracts hit "stack too deep" errors. With `--ir-minimum`, bytecode changes cause address prediction mismatch. This is a known Foundry limitation. Documented for Phase 35 to use test counts as baseline metric.

2. **testFuzz_weaklyMonotonicInCycle vm.assume rejection:** At 10K runs, the narrow constraints (`baseLevel <= 10_000` from uint24 space, plus offset constraints) reject more than 131,072 inputs. This is expected behavior for tests with restrictive assumptions - consider using `bound()` instead of `vm.assume()` in future harness updates (out of scope for Phase 30).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Deep profile configured and validated
- Coverage baseline captured with documented limitations
- Ready for Plan 30-02 (Slither triage) or parallel Phase 31/32 work

---
*Phase: 30-tooling-setup-and-static-analysis*
*Completed: 2026-03-05*
