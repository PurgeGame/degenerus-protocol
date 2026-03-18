---
phase: 30-payout-specification-document
plan: 05
subsystem: documentation
tags: [html, svg, gameover, terminal-distribution, payout-specification]

# Dependency graph
requires:
  - phase: 30-payout-specification-document
    plan: 01
    provides: HTML scaffold with CSS design system, section stubs, SVG visual language
  - phase: 26-gameover-path-audit
    provides: GO-01/GO-02/GO-07/GO-08 audit verdicts, GO-05 FINDING-MEDIUM, formulas, edge cases
provides:
  - GAMEOVER terminal distribution section with 4 system cards, master sequence SVG, GO-05 finding callout
affects: [30-06]

# Tech tracking
tech-stack:
  added: []
  patterns: [inline-svg-flow-diagrams, finding-callout-styling, multi-level-fund-flow-diagrams]

key-files:
  created: []
  modified:
    - audit/PAYOUT-SPECIFICATION.html

key-decisions:
  - "Used unique SVG marker IDs per diagram (go-arrow, go01-arrow, etc.) to avoid ID collisions with parallel plans writing to same HTML file"
  - "GO-05-F01 callout styled with red background (#ffebee) and left border to visually distinguish from normal content"
  - "Master GAMEOVER sequence diagram uses numbered steps [1]-[3] matching formula block step numbers for cross-reference"

patterns-established:
  - "Finding callout pattern: div with background:#ffebee, border-left:4px solid #c62828 for medium-severity findings"

requirements-completed: [SPEC-02, SPEC-03, SPEC-04, SPEC-05, SPEC-06]

# Metrics
duration: 12min
completed: 2026-03-18
---

# Phase 30 Plan 05: GAMEOVER Terminal Distribution Summary

**4 GAMEOVER system cards (GO-01 terminal jackpot, GO-08 terminal decimator, GO-07 deity refunds, GO-02 final sweep) with master sequence SVG, GO-05 FINDING-MEDIUM callout, complete formulas, and edge cases**

## Performance

- **Duration:** 12 min
- **Started:** 2026-03-18T08:55:57Z
- **Completed:** 2026-03-18T09:08:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Populated cat-gameover section with category introduction documenting death clock thresholds (365d level 0, 120d level 1+) and three idempotency latches
- Added GO-05-F01 FINDING-MEDIUM callout with red styling highlighting _sendToVault hard revert risk across 7 dangerous revert sites
- Created master GAMEOVER sequence SVG (viewBox 900x600) showing complete flow from death clock expiry through deity refunds, terminal decimator/jackpot, 30-day claim window, to final sweep
- Built 4 system cards each with info table, formula block with exact contract variable names, inline SVG flow diagram, file:line references, and documented edge cases
- All 5 SVGs use consistent visual language (pools as rounded rects, contracts as rects, decisions as diamonds, recipients as pills)

## Task Commits

Each task was committed atomically:

1. **Task 1: Write GAMEOVER Terminal Distribution system cards (GO-01, GO-08, GO-07, GO-02)** - `943af848` (feat)

**Plan metadata:** pending (docs: complete plan)

## Files Created/Modified
- `audit/PAYOUT-SPECIFICATION.html` - GAMEOVER terminal distribution section with 4 system cards, master SVG, and GO-05 finding callout (569 lines added)

## Decisions Made
- Used unique SVG marker IDs per diagram (go-arrow, go01-arrow, go02-arrow, go07-arrow, go08-arrow) to avoid ID collisions with parallel plans
- Styled GO-05 callout with inline styles rather than adding a CSS class, since it is the only finding callout in the document
- Master GAMEOVER diagram uses numbered annotations [1], [2], [3] that correspond to the formula block step numbers in GO-01 for easy cross-referencing

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- File was being simultaneously modified by parallel plans (30-02, 30-03, 30-04), causing Edit tool rejections due to stale reads. Resolved by writing replacement content to a temp file and using Python for atomic section replacement.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- cat-gameover section is fully populated with all 4 system cards
- Plan 30-06 (cross-system sections) can reference GAMEOVER edge cases and claimablePool mutation sites documented here
- All GO requirement IDs (GO-01, GO-02, GO-07, GO-08) are now linked in the HTML document

## Self-Check: PASSED

- audit/PAYOUT-SPECIFICATION.html: FOUND
- GO-01 system card: FOUND
- GO-02 system card: FOUND
- GO-07 system card: FOUND
- GO-08 system card: FOUND
- GO-05-F01 FINDING-MEDIUM callout: FOUND
- Master GAMEOVER SVG: FOUND
- 5 SVGs in cat-gameover section: VERIFIED
- Commit 943af848: FOUND

---
*Phase: 30-payout-specification-document*
*Completed: 2026-03-18*
