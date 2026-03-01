---
phase: 03b-vrf-dependent-modules
plan: 03
subsystem: security-audit
tags: [lootbox, ev-model, activity-score, extraction-cap, game-theory, math-verification]

# Dependency graph
requires:
  - phase: 02-core-state-machine
    provides: VRF lifecycle and EntropyLib validation (RNG derivation confirmed secure)
  - phase: 03b-vrf-dependent-modules
    provides: 03b-RESEARCH.md pre-computed EV values and activity score component enumeration
provides:
  - Complete mathematical EV model for all four lootbox reward paths
  - Per-level cap extraction limit analysis (3.5 ETH max benefit at 135% EV)
  - Activity score cost analysis with minimum investment for each tier
  - MATH-05 verdict (PASS) with full mathematical reasoning
affects: [05-economic-attack-surface, 04-accounting-integrity]

# Tech tracking
tech-stack:
  added: []
  patterns: [ev-model-with-exact-bps-constants, cap-tracking-raw-input-conservative]

key-files:
  created:
    - .planning/phases/03b-vrf-dependent-modules/03b-03-FINDINGS-lootbox-ev-model.md
  modified: []

key-decisions:
  - "MATH-05 rated PASS: no activity score creates guaranteed positive-EV extraction exceeding investment cost"
  - "Cap tracks raw input (not benefit delta) -- confirmed as intentionally conservative design, 2.86x faster depletion than benefit-tracking"
  - "Only deity pass holders (24+ ETH) can reach 305% activity / 135% EV; non-deity max is 265% / ~129% EV"
  - "Break-even on deity pass via lootbox EV alone requires 7+ levels of max cap extraction (probabilistic, not guaranteed)"

patterns-established:
  - "EV analysis with exact BPS constants extracted from contract source"
  - "Denomination-aware modeling: ticket value in price-curve ETH, BURNIE/DGNRS/WWXRP in token-market value"

requirements-completed: [MATH-05]

# Metrics
duration: 8min
completed: 2026-03-01
---

# Phase 03b Plan 03: Lootbox EV Model Summary

**Complete mathematical EV model proving 3.5 ETH max extraction per level at 135% EV cap; MATH-05 PASS -- no guaranteed positive-EV extraction path exists**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-01T07:01:46Z
- **Completed:** 2026-03-01T07:10:00Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Computed exact per-path EV for all four lootbox reward paths (tickets 69.6%, BURNIE 41.2%, DGNRS pool-dependent, WWXRP market-dependent) using BPS constants extracted directly from contract source
- Verified composite EV at neutral activity score (60%) is ~99.7% from deterministic paths alone (ticket + BURNIE), confirming the ~100% break-even design
- Modeled per-level cap extraction: raw-input tracking limits benefit to exactly 3.5 ETH per level at max 135% EV, regardless of lootbox size distribution
- Enumerated all activity score components with investment costs: deity pass (24+ ETH, 15500 BPS), quest streak (10000 BPS, 100 days), affiliate (5000 BPS, ~50 ETH referred volume)
- Confirmed MATH-05 PASS: 7+ levels of probabilistic max extraction needed to recoup deity pass cost, with ongoing ticket purchases required

## Task Commits

Each task was committed atomically:

1. **Task 1: Compute exact EV for each reward path; build composite EV model** - `e9303db` (feat)
2. **Task 2: Model per-level cap extraction limit and activity score cost; write MATH-05 verdict** - included in `e9303db` (complete findings document written in single pass)

## Files Created/Modified
- `.planning/phases/03b-vrf-dependent-modules/03b-03-FINDINGS-lootbox-ev-model.md` - Complete EV model with 8 sections: per-path computation, composite model, cap extraction analysis, activity score costs, extraction vs investment, level-advance reset, MATH-05 verdict, findings (4 informational)

## Decisions Made
- MATH-05 rated unconditional PASS: the 10 ETH per-level cap (tracking raw input, not benefit) limits maximum extraction to 3.5 ETH per level. Reaching 305% activity requires 24+ ETH deity pass plus 100+ days of quests. Break-even requires 7+ levels of probabilistic max extraction with ongoing ticket purchase costs.
- Cap tracking raw input confirmed as intentionally conservative: cap depletes 2.86x faster than benefit-tracking alternative.
- Sub-100% EV players also benefit from cap: after 10 ETH of reduced-EV lootboxes, they revert to 100% EV (informational, prevents excessive casual player punishment).

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- MATH-05 verdict available for cross-referencing in Phase 5 (Economic Attack Surface)
- Activity score cost analysis provides foundation for Phase 5 inflation vector analysis (05-02)
- Per-level cap extraction model informs whale bundle + lootbox EV analysis (05-06)

## Self-Check: PASSED

- FOUND: `.planning/phases/03b-vrf-dependent-modules/03b-03-FINDINGS-lootbox-ev-model.md`
- FOUND: `.planning/phases/03b-vrf-dependent-modules/03b-03-SUMMARY.md`
- FOUND: commit `e9303db`
- Contract files modified: 0 (READ-ONLY audit confirmed)

---
*Phase: 03b-vrf-dependent-modules*
*Completed: 2026-03-01*
