---
phase: 30-payout-specification-document
plan: 01
subsystem: documentation
tags: [html, css, svg, payout-specification, self-contained]

# Dependency graph
requires:
  - phase: 29-comment-documentation-correctness
    provides: verified audit verdicts for all 28 requirements (19 PAY + 9 GO)
provides:
  - Self-contained HTML scaffold at audit/PAYOUT-SPECIFICATION.html with CSS design system, header, TOC, pool overview SVG, and empty section stubs
affects: [30-02, 30-03, 30-04, 30-05, 30-06]

# Tech tracking
tech-stack:
  added: []
  patterns: [self-contained-html, inline-svg-diagrams, css-custom-properties-design-system]

key-files:
  created:
    - audit/PAYOUT-SPECIFICATION.html
  modified: []

key-decisions:
  - "SVG pool overview uses dashed arrow for scatter/decimator path to visually distinguish indirect flows from direct pool-to-pool transitions"

patterns-established:
  - "CSS design system: all colors, fonts, and component styles defined via custom properties in single style block"
  - "SVG visual language: pools as rounded-rect with .pool class, contracts as rect with .contract class, recipients as pill with .recipient class, arrows with #arrow marker"
  - "Section stub pattern: <section id='cat-XXX'><h2>Title</h2><!-- Plan 30-0N --></section> for subsequent plan population"

requirements-completed: [SPEC-01]

# Metrics
duration: 2min
completed: 2026-03-18
---

# Phase 30 Plan 01: HTML Scaffold Summary

**Self-contained HTML scaffold with CSS design system, pool architecture SVG, linked TOC, and 8 empty section stubs for the payout specification document**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-18T08:50:38Z
- **Completed:** 2026-03-18T08:53:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Created audit/PAYOUT-SPECIFICATION.html as a zero-dependency, self-contained HTML file (13KB)
- Complete CSS design system with 14 custom properties, 15+ component classes, currency badge variants, and print media query
- Pool architecture overview SVG diagram (viewBox 900x500) showing all 4 core ETH pools, yieldAccumulator, stETH yield source, and fund flow arrows
- Document header with summary stats grid (23 systems, 28 requirements verified, 1 medium, 0 critical/high)
- Linked table of contents with anchor links to all 8 sections (6 categories + 2 cross-system)
- 8 empty section stubs ready for content population by Plans 30-02 through 30-06

## Task Commits

Each task was committed atomically:

1. **Task 1: Create self-contained HTML scaffold with CSS design system** - `936664d5` (feat)

**Plan metadata:** pending (docs: complete plan)

## Files Created/Modified
- `audit/PAYOUT-SPECIFICATION.html` - Self-contained HTML specification scaffold with CSS, header, TOC, pool SVG, and section stubs

## Decisions Made
- Used dashed stroke for scatter/decimator arrow in pool overview SVG to distinguish indirect fund flows from direct transitions
- Placed summary stats as a CSS grid of stat-cards for visual impact at document top
- Kept SVG pool layout with futurePrizePool/nextPrizePool at top, currentPrizePool/claimablePool at bottom, yieldAccumulator at center-right

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- HTML scaffold is ready for Plan 30-02 (jackpot distribution system cards) to populate the cat-jackpot section
- All section stubs have correct IDs matching the TOC anchor links
- CSS classes for system-card, info-table, formula-block, edge-cases, badge variants, and flow-svg are all defined and ready for use

---
*Phase: 30-payout-specification-document*
*Completed: 2026-03-18*
