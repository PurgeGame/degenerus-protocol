---
phase: 30-payout-specification-document
plan: 02
subsystem: documentation
tags: [html, svg, jackpot-distribution, payout-specification, inline-diagrams]

# Dependency graph
requires:
  - phase: 30-payout-specification-document
    plan: 01
    provides: HTML scaffold with CSS design system, pool overview SVG, and empty section stubs
  - phase: 27-payout-claim-path-audit
    provides: PAY-01, PAY-02, PAY-16 verified audit verdicts with exact formulas and file:line references
provides:
  - 3 fully populated system cards (PAY-01, PAY-02, PAY-16) in cat-jackpot section with info tables, formula blocks, SVG flow diagrams, and edge cases
affects: [30-06]

# Tech tracking
tech-stack:
  added: []
  patterns: [system-card-with-info-table-formula-svg-edgecases, unique-svg-marker-ids-per-diagram]

key-files:
  created: []
  modified:
    - audit/PAYOUT-SPECIFICATION.html

key-decisions:
  - "Used unique SVG marker IDs per diagram (arrow-j1, arrow-j2, arrow-j3) to prevent cross-diagram marker conflicts in the same HTML file"
  - "PAY-16 SVG shows pool transition chain horizontally with prizePoolFrozen as dashed-border annotation rather than a separate node"

patterns-established:
  - "System card HTML pattern: div.system-card with h3 title, system-meta badges, info-table, formula-block with pre/code, SVG flow diagram, and div.edge-cases"
  - "SVG flow diagrams use approximately 800x300-400 viewBox with pool/contract/recipient/decision shapes per RESEARCH.md visual language"
  - "Each formula block cites exact contract variable names and file:line references with commit hash"

requirements-completed: [SPEC-02, SPEC-03, SPEC-04, SPEC-05, SPEC-06]

# Metrics
duration: 3min
completed: 2026-03-18
---

# Phase 30 Plan 02: Jackpot Distribution System Cards Summary

**Three jackpot system cards (PAY-01/02/16) with exact contract formulas, inline SVG flow diagrams, and edge cases in PAYOUT-SPECIFICATION.html**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-18T08:55:30Z
- **Completed:** 2026-03-18T08:58:30Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- PAY-01 system card: purchase-phase daily jackpot with 1% futurePrizePool drip, 75/25 lootbox/ETH split, SVG showing auto-rebuy decision branch
- PAY-02 system card: jackpot-phase 5-day draws with 6-14% BPS range, 60/13/13/13 share split, compressed/turbo mode annotation
- PAY-16 system card: ticket conversion and pool transition chain (futurePrizePool -> nextPrizePool -> currentPrizePool) with 2x over-collateralization and prizePoolFrozen guard
- All 3 SVG flow diagrams using consistent visual language (pool/contract/recipient/decision shapes) with unique marker IDs
- Edge cases documented for all 3 systems from Phase 27/28 audit findings

## Task Commits

Each task was committed atomically:

1. **Task 1: Write PAY-01 and PAY-02 system cards with SVG flow diagrams** - `ae362254` (feat)
2. **Task 2: Write PAY-16 system card with SVG flow diagram** - `e819ced6` (feat)

**Plan metadata:** pending (docs: complete plan)

## Files Created/Modified
- `audit/PAYOUT-SPECIFICATION.html` - Added 3 jackpot distribution system cards (PAY-01, PAY-02, PAY-16) to the cat-jackpot section

## Decisions Made
- Used unique SVG marker IDs per diagram (arrow-j1, arrow-j2, arrow-j3) to prevent cross-diagram marker conflicts since all diagrams are in the same HTML file
- PAY-16 SVG uses horizontal pool transition chain layout with prizePoolFrozen shown as a dashed-border annotation on currentPrizePool rather than a separate decision node
- Compressed/turbo mode in PAY-02 shown as annotation box below main flow rather than branching the diagram

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- cat-jackpot section is fully populated with all 3 system cards
- Subsequent plans (30-03 through 30-06) can populate their respective sections independently
- System card HTML pattern established and ready for reuse by other plans

## Self-Check: PASSED

- audit/PAYOUT-SPECIFICATION.html: FOUND
- 3 system-card elements in cat-jackpot: VERIFIED
- 4 SVG elements total: VERIFIED
- Commit ae362254: FOUND
- Commit e819ced6: FOUND

---
*Phase: 30-payout-specification-document*
*Completed: 2026-03-18*
