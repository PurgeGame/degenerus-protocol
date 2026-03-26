---
phase: 30-payout-specification-document
plan: 04
subsystem: documentation
tags: [html, svg, payout-specification, ancillary-payouts, token-burns, yield-distribution]

# Dependency graph
requires:
  - phase: 30-payout-specification-document
    provides: HTML scaffold with CSS design system, section stubs, SVG visual language (30-01)
  - phase: 27-payout-claim-path-audit
    provides: verified audit verdicts for PAY-09 through PAY-15 and PAY-17
provides:
  - Ancillary payouts section with 5 system cards (PAY-09, PAY-10, PAY-11, PAY-12/13, PAY-17)
  - Token burns section with 1 combined system card (PAY-14/15)
  - Inline SVG flow diagrams for all 8 payout systems
affects: [30-06]

# Tech tracking
tech-stack:
  added: []
  patterns: [combined-system-card-for-connected-systems, html-entity-escaping-in-pre-blocks]

key-files:
  created: []
  modified:
    - audit/PAYOUT-SPECIFICATION.html

key-decisions:
  - "PAY-12/PAY-13 combined into one card since yield distribution and accumulator milestones are connected systems (46% of yield feeds accumulator, x00 milestones release from accumulator)"
  - "PAY-14/PAY-15 combined into one card since DGNRS wrapper burn delegates to sDGNRS burn (identical formula path)"
  - "Used HTML entities (&gt; &lt;) inside pre/code blocks for safe rendering of comparison operators"
  - "ADVANCE_BOUNTY formula uses exact contract expression (ADVANCE_BOUNTY_ETH * PRICE_COIN_UNIT / price) rather than simplified version from plan"

patterns-established:
  - "Combined system card pattern: sub-sections with h4 headings for closely-related PAY IDs sharing code paths"
  - "Arrow marker scoping: unique marker IDs per section (arrow-anc, arrow-burn) to avoid SVG ID conflicts across sections"

requirements-completed: [SPEC-02, SPEC-03, SPEC-04, SPEC-05, SPEC-06]

# Metrics
duration: 12min
completed: 2026-03-18
---

# Phase 30 Plan 04: Ancillary Payouts and Token Burns Summary

**5 ancillary system cards (lootbox/quest/affiliate/yield/bounty) and 1 token burn card with SVG flow diagrams, exact contract formulas, and edge cases covering PAY-09 through PAY-15 and PAY-17**

## Performance

- **Duration:** 12 min
- **Started:** 2026-03-18T08:55:37Z
- **Completed:** 2026-03-18T09:07:51Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Populated cat-ancillary section with 5 system cards covering 6 PAY requirements (PAY-09, PAY-10, PAY-11, PAY-12/13 combined, PAY-17)
- Populated cat-burns section with 1 combined system card covering PAY-14/15 token burn redemption
- Created 6 inline SVG flow diagrams: lootbox VRF decision tree, quest creditFlip flow, affiliate 3-tier fan-out, yield 23/23/46 split with accumulator, advance bounty escalation, and dual-entry burn delegation
- All formulas use exact contract variable names: nextEntropy, lootboxEth, creditFlip, affiliateScore, levelDgnrsAllocation, totalAffiliateScore, AFFILIATE_ETH_CAP, yieldSurplus, stakeholderShare, accumulatorShare, yieldAccumulator, halfAccumulator, poolConsolidationDone, ADVANCE_BOUNTY_ETH, totalMoney, supplyBefore, claimableEth, wrapperBurnTo
- All file:line references verified: LootboxModule.sol, DegenerusQuests.sol, DegenerusAffiliate.sol:386-623, JackpotModule.sol:928-958, JackpotModule.sol:886-924, AdvanceModule.sol:112-376, StakedDegenerusStonk.sol:373-435, DegenerusStonk.sol:164-181

## Task Commits

Each task was committed atomically:

1. **Task 1: Write Ancillary Payout system cards (PAY-09, PAY-10, PAY-11, PAY-12, PAY-13, PAY-17)** - `f89fd17c` (feat)
2. **Task 2: Write Token Burns system cards (PAY-14, PAY-15)** - `bc555922` (feat)

**Plan metadata:** pending (docs: complete plan)

## Files Created/Modified
- `audit/PAYOUT-SPECIFICATION.html` - Ancillary payouts (cat-ancillary) and token burns (cat-burns) sections populated with system cards, SVG diagrams, formulas, and edge cases

## Decisions Made
- Combined PAY-12/PAY-13 into one system card because they are connected systems (yield distribution feeds the accumulator which releases at milestones)
- Combined PAY-14/PAY-15 into one system card because DGNRS wrapper burn delegates entirely to sDGNRS burn
- Used exact contract formula for advance bounty (ADVANCE_BOUNTY_ETH * PRICE_COIN_UNIT / price) rather than simplified plan description
- Used HTML entities in pre blocks for safe rendering of comparison operators in formulas

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- File modified concurrently by parallel plans (30-02, 30-03) during Task 1 execution, requiring re-reads before successful edit. Resolved by targeting unique section markers.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- cat-ancillary section is fully populated with 5 system cards
- cat-burns section is fully populated with 1 combined system card
- Only cat-gameover (Plan 30-05) and cross-system sections (Plan 30-06) remain

## Self-Check: PASSED

- audit/PAYOUT-SPECIFICATION.html: FOUND
- Commit f89fd17c: FOUND
- Commit bc555922: FOUND
- PAY-09 through PAY-15 and PAY-17 all present in document

---
*Phase: 30-payout-specification-document*
*Completed: 2026-03-18*
