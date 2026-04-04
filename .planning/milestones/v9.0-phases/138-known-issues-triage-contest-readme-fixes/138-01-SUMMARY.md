---
phase: 138-known-issues-triage-contest-readme-fixes
plan: 01
subsystem: documentation
tags: [known-issues, triage, vesting, rngLocked, governance, C4A]

# Dependency graph
requires:
  - phase: 134-consolidation
    provides: "KNOWN-ISSUES.md with 34+ entries from v8.0 hardening"
provides:
  - "Triaged KNOWN-ISSUES.md with accurate bootstrap assumptions, quantified claims, vesting/rngLocked entries"
affects: [138-02, contest-readme]

# Tech tracking
tech-stack:
  added: []
  patterns: ["KNOWN-ISSUE vs DESIGN-DOC classification for audit defense documents"]

key-files:
  created: []
  modified: [KNOWN-ISSUES.md]

key-decisions:
  - "All 30 entries classified as KNOWN-ISSUE (zero DESIGN-DOC) -- every entry represents a real warden filing risk"
  - "Bootstrap assumption corrected from sDGNRS to DGNRS with full vesting schedule in both governance entries"
  - "Rounding worst-case quantified at ~25,000 wei (~0.000000000025 ETH) -- dust-level"
  - "Affiliate manipulation bound: no protocol ETH extraction possible, equivalent to choosing referral recipient"

patterns-established:
  - "Governance entries include multi-factor exploitation prerequisite list (compromised admin + Chainlink failure + community inattention)"

requirements-completed: [KI-01, KI-02, KI-03, KI-04, KI-05]

# Metrics
duration: 2min
completed: 2026-03-28
---

# Phase 138 Plan 01: KNOWN-ISSUES Triage Summary

**Triaged all 30 KNOWN-ISSUES.md entries, fixed bootstrap assumption (DGNRS not sDGNRS), quantified fuzzy claims with worst-case wei bounds, added creator vesting and rngLocked guard entries**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-28T18:38:50Z
- **Completed:** 2026-03-28T18:41:08Z
- **Tasks:** 3 (1 auto + 1 checkpoint auto-approved + 1 auto)
- **Files modified:** 1

## Accomplishments
- Classified all 30 entries as KNOWN-ISSUE (all represent real warden filing risks)
- Fixed bootstrap assumption in VRF swap and price feed swap governance entries: creator holds DGNRS (not sDGNRS), vests 50B initial + 5B/level via claimVested()
- Quantified "all rounding favors solvency" with worst-case bound: ~25,000 wei over full game lifecycle
- Quantified affiliate timing extraction: no protocol ETH extraction possible
- Added creator DGNRS vesting entry documenting claimVested() and 200B total at level 30
- Added unwrapTo rngLocked guard entry documenting replacement of 5h timestamp check

## Task Commits

Each task was committed atomically:

1. **Task 1: Triage all entries and produce classification table** - analysis only (no file changes)
2. **Task 2: User reviews classification table** - auto-approved (auto_advance=true)
3. **Task 3: Apply triage changes to KNOWN-ISSUES.md** - `a80ad651` (docs)

## Files Created/Modified
- `KNOWN-ISSUES.md` - Bootstrap assumption corrected, fuzzy claims quantified, 2 new entries added

## Decisions Made
- All 30 entries classified as KNOWN-ISSUE -- the "Design Decisions" section header is kept but every entry there is a real warden filing risk (governance scenarios, dependency risks, prevrandao bias, vesting mechanics)
- No DESIGN-DOC entries identified for relocation -- all entries serve audit defense purpose

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- KNOWN-ISSUES.md is accurate and ready for C4A audit
- Plan 138-02 (Contest README fixes) can proceed independently

---
*Phase: 138-known-issues-triage-contest-readme-fixes*
*Completed: 2026-03-28*
