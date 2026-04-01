---
phase: 50-skim-redesign-audit
plan: 01
subsystem: audit
tags: [solidity, arithmetic, overflow, underflow, vrf, bit-field, futurepool, skim]

# Dependency graph
requires:
  - phase: none
    provides: n/a
provides:
  - "Line-by-line arithmetic verdicts for all 5 skim pipeline steps (SKIM-01 through SKIM-05)"
  - "Monotonicity proof for overshoot surcharge formula"
  - "Underflow safety proof for triangular variance subtraction path"
  - "INFO finding on bit-field consumption vs documented design"
affects: [50-02-PLAN, 50-03-PLAN, documentation-sync]

# Tech tracking
tech-stack:
  added: []
  patterns: [step-by-step verdict document with calculus proofs and fuzz cross-references]

key-files:
  created:
    - ".planning/phases/50-skim-redesign-audit/50-01-pipeline-arithmetic.md"
  modified: []

key-decisions:
  - "SKIM-03 classified as INFO (not LOW): bit-field overlap is not exploitable due to modulo independence"
  - "Division-by-zero in ratio calculation (L1001) classified as SAFE: calling context guarantees nextPoolBefore > 0"

patterns-established:
  - "Verdict format: requirement ID, lines, code block, arithmetic analysis, cross-reference, verdict"

requirements-completed: [SKIM-01, SKIM-02, SKIM-03, SKIM-04, SKIM-05]

# Metrics
duration: 4min
completed: 2026-03-21
---

# Phase 50 Plan 01: Pipeline Arithmetic Summary

**5 arithmetic verdicts (4 SAFE, 1 INFO) for futurepool skim pipeline: overshoot surcharge monotonicity proven, ratio adjustment bounded +/-400 bps, bit-field overlap documented as INFO, triangular variance underflow-safe via halfWidth clamp, 80% take cap confirmed post-variance**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-21T19:54:40Z
- **Completed:** 2026-03-21T19:58:48Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- SKIM-01 SAFE: Overshoot surcharge formula f(x)=4000x/(x+10000) proven monotonically increasing via calculus (f'(x)>0), capped at 3500 bps by explicit clamp, all 5 spot-check values verified
- SKIM-02 SAFE: Ratio adjustment bounded +/-400 bps with underflow prevention via `penalty >= bps ? 0 : bps - penalty` ternary floor; division-by-zero unreachable due to calling context
- SKIM-03 INFO: Additive random step uses all 256 bits via `rngWord % 1001` (not isolated [0:63]); roll1/roll2 share bits [192:255]; functionally independent via modulo but does not match documented bit-window design
- SKIM-04 SAFE: Triangular variance subtraction path proven safe via bounds chain -- `halfWidth > take` clamp at L1033 guarantees subtraction amount <= halfWidth <= take
- SKIM-05 SAFE: 80% take cap applied after all variance operations; combined with 1% insurance skim, nextPool retains >= 19%

## Task Commits

Each task was committed atomically:

1. **Task 1: Overshoot surcharge + ratio adjustment + bit-field verdicts (SKIM-01, SKIM-02, SKIM-03)** - `8ade5e32` (feat)
2. **Task 2: Triangular variance safety + take cap verdicts (SKIM-04, SKIM-05)** - `5e1ded52` (feat)

## Files Created/Modified
- `.planning/phases/50-skim-redesign-audit/50-01-pipeline-arithmetic.md` - Line-by-line arithmetic verdicts for all 5 pipeline steps with calculus proofs, bounds analysis, and fuzz test cross-references

## Decisions Made
- SKIM-03 bit-field overlap classified as INFO severity rather than LOW: modulo arithmetic makes outputs functionally independent even with bit overlap, and VRF word is not attacker-controlled. Recommendation to update NatSpec or add masking.
- Division-by-zero risk in ratio calculation (L1001) classified as SAFE: calling context at L314-315 guarantees nextPoolBefore > 0 because level transitions require player purchases that add ETH.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Known Stubs
None - this plan produces audit documentation only, no code stubs.

## Next Phase Readiness
- Pipeline arithmetic verdicts complete for all 5 steps
- Ready for Plan 02 (ETH conservation + insurance skim proof covering SKIM-06, SKIM-07)
- Ready for Plan 03 (economic analysis covering ECON-01, ECON-02, ECON-03)

## Self-Check: PASSED

- [x] `.planning/phases/50-skim-redesign-audit/50-01-pipeline-arithmetic.md` exists
- [x] `.planning/phases/50-skim-redesign-audit/50-01-SUMMARY.md` exists
- [x] Commit `8ade5e32` found in git log
- [x] Commit `5e1ded52` found in git log
- [x] All 22 fuzz tests pass (no regressions)

---
*Phase: 50-skim-redesign-audit*
*Completed: 2026-03-21*
