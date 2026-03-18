---
phase: 30-payout-specification-document
plan: 03
subsystem: documentation
tags: [html, svg, payout-specification, scatter, decimator, coinflip, burnie, wwxrp]

# Dependency graph
requires:
  - phase: 30-payout-specification-document
    plan: 01
    provides: HTML scaffold with CSS design system and section stubs
provides:
  - Scatter/Decimator system cards (PAY-03/04/05/06) with pool source distinction callout, SVG diagrams, formulas, edge cases
  - Coinflip Economy system cards (PAY-07/08/18/19) with BURNIE isolation note, SVG diagrams, formulas, edge cases
affects: [30-06]

# Tech tracking
tech-stack:
  added: []
  patterns: [combined-system-card-pattern, pool-distinction-callout, burnie-isolation-callout]

key-files:
  created: []
  modified:
    - audit/PAYOUT-SPECIFICATION.html

key-decisions:
  - "Combined PAY-03/04 into single BAF Scatter card with subsections (shared _runBafJackpot code path)"
  - "Combined PAY-05/06 into single Decimator Claims card with subsections (shared claim path)"
  - "Combined PAY-18/19 into single card covering both WWXRP consolation and recycling/boons"
  - "Added pool source distinction callout with blue highlight before scatter cards"
  - "Added BURNIE isolation callout with orange highlight before coinflip cards"

patterns-established:
  - "Pool distinction callout: blue background with left border for critical pool variable warnings"
  - "BURNIE isolation callout: orange background with left border for token isolation notes"
  - "Combined system card: single card covering related PAY IDs with subsection headers per variant"

requirements-completed: [SPEC-02, SPEC-03, SPEC-04, SPEC-05, SPEC-06]

# Metrics
duration: 8min
completed: 2026-03-18
---

# Phase 30 Plan 03: Scatter/Decimator and Coinflip Economy System Cards Summary

**5 system cards covering 8 PAY requirements (PAY-03 through PAY-08, PAY-18/19) with pool source distinction callout, BURNIE isolation note, SVG flow diagrams, exact contract formulas, and edge cases**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-18T08:55:32Z
- **Completed:** 2026-03-18T09:03:28Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Scatter/Decimator section: Pool source distinction callout (baseFuturePool vs futurePoolLocal), BAF scatter card (PAY-03/04) with 7-category split formula and SVG, Decimator claims card (PAY-05/06) with dual-pool SVG showing decRefund path
- Coinflip Economy section: BURNIE isolation callout, coinflip deposit/win/loss card (PAY-07) with variable multiplier formula and VRF SVG, bounty card (PAY-08) with DGNRS gating SVG, WWXRP/recycling/boons card (PAY-18/19) with mint authority SVG
- All 5 SVG diagrams use consistent visual language from 30-01 CSS design system (pools, contracts, decisions, recipients)
- All formulas use exact contract variable names verified against Phase 27 audit reports

## Task Commits

Each task was committed atomically:

1. **Task 1: Write BAF Scatter (PAY-03/04) and Decimator (PAY-05/06) system cards** - `2cc057b1` (feat)
2. **Task 2: Write Coinflip Economy system cards (PAY-07, PAY-08, PAY-18, PAY-19)** - `576f1471` (feat)

**Plan metadata:** pending (docs: complete plan)

## Files Created/Modified
- `audit/PAYOUT-SPECIFICATION.html` - Added scatter/decimator and coinflip economy sections with 5 system cards, 5 SVG flow diagrams, and 2 category callout boxes

## Decisions Made
- Combined closely-related PAY IDs into single system cards with subsection headers (PAY-03/04, PAY-05/06, PAY-18/19) to reduce redundancy while maintaining complete coverage
- Used blue highlighted callout for pool source distinction (critical for understanding scatter/decimator accounting)
- Used orange highlighted callout for BURNIE isolation (critical for understanding coinflip has no ETH solvency impact)
- Unique SVG marker IDs per diagram (arrow-scatter, arrow-dec, arrow-cf, arrow-bounty, arrow-wwxrp) to avoid cross-diagram rendering conflicts

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- Parallel plan 30-02 was writing to the same HTML file simultaneously, causing two stale-file retries before the scatter section edit succeeded. No content was lost.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- cat-scatter and cat-coinflip sections are fully populated
- Remaining sections (cat-ancillary, cat-burns, cat-gameover, cross-claimable, cross-issues) await Plans 30-04, 30-05, 30-06
- All SVG marker IDs are unique to avoid conflicts with subsequent plan additions

## Self-Check: PASSED

- audit/PAYOUT-SPECIFICATION.html: FOUND
- 30-03-SUMMARY.md: FOUND
- Commit 2cc057b1: FOUND
- Commit 576f1471: FOUND

---
*Phase: 30-payout-specification-document*
*Completed: 2026-03-18*
