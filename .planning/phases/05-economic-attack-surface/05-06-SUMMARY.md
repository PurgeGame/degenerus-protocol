---
phase: 05-economic-attack-surface
plan: 06
subsystem: economic-analysis
tags: [whale-bundle, lootbox, ticket-pricing, extraction-model, econ-06]

# Dependency graph
requires:
  - phase: 03c-supporting-mechanics-modules
    provides: F01 HIGH whale bundle level guard finding, pricing formula verification
  - phase: 03b-vrf-dependent-modules
    provides: Lootbox EV multiplier model (MATH-05), per-level cap mechanics
provides:
  - Whale bundle economic extraction model with ticket face value at 5 level tiers
  - F01 economic impact classification (INFORMATIONAL, not exploitable)
  - ECON-06 verdict (PASS) with quantitative justification
affects: [05-economic-attack-surface, remediation-planning]

# Tech tracking
tech-stack:
  added: []
  patterns: [face-value-vs-liquid-value distinction, full-cycle price sum invariant]

key-files:
  created:
    - .planning/phases/05-economic-attack-surface/05-06-FINDINGS-whale-bundle-ev.md
  modified: []

key-decisions:
  - "Ticket face value is NOT liquid ETH -- 18.00 ETH nominal across 100 levels represents participation rights, not extractable value"
  - "Full-cycle face value sum is invariant at 18.00 ETH (4.50x) for all levels 10+; no level produces higher extraction ratio"
  - "F01 level guard absence reclassified from economic HIGH to INFORMATIONAL -- no economic impact"
  - "ECON-06 PASS: no bundle+lootbox sequence can extract more than deposited"

patterns-established:
  - "Full-cycle invariant: PriceLookupLib produces constant face value sum across any 100-level window for post-intro levels"
  - "Deposit circularity: 100% of whale bundle price enters prize pools; tickets claim FROM those pools"

requirements-completed: [ECON-06]

# Metrics
duration: 4min
completed: 2026-03-01
---

# Phase 05 Plan 06: Whale Bundle EV Summary

**Whale bundle extraction model proves no level produces extractable value exceeding deposit; F01 level guard absence economically benign; ECON-06 PASS**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-01T12:47:07Z
- **Completed:** 2026-03-01T12:51:30Z
- **Tasks:** 1
- **Files created:** 1

## Accomplishments
- Computed ticket face value at levels 0 (24.40 ETH / 10.17x), 10, 50, 100, 200 (all 18.00 ETH / 4.50x)
- Proved full-cycle price sum invariant: any 100-level window from level 10+ sums to exactly 9.00 ETH per ticket * 2 tickets = 18.00 ETH
- Quantified lootbox EV component: max 0.14 ETH benefit per 4 ETH bundle (3.5% of cost)
- Quantified activity boost marginal value: ~0.57 ETH/level requiring 10 ETH lootbox input per level
- Assessed F01 (level guard absence) economic impact: zero -- constant extraction ratio at all levels
- Rendered ECON-06 verdict: PASS with 5-factor justification

## Task Commits

Each task was committed atomically:

1. **Task 1: Compute whale bundle ticket face value and extraction model** - `7440137` (feat)

**Plan metadata:** Pending

## Files Created/Modified
- `.planning/phases/05-economic-attack-surface/05-06-FINDINGS-whale-bundle-ev.md` - Complete extraction model with ECON-06 verdict

## Decisions Made
- Ticket face value (18-24 ETH) greatly exceeds bundle cost (2.4-4 ETH) in nominal terms, but tickets are non-liquid participation rights, not extractable value
- The full 100-level price cycle produces a constant face value sum, so no level is more favorable than any other (beyond the intro tier at levels 0-3)
- F01 level guard absence does not change economics -- the issue is a specification/documentation mismatch, not an economic vulnerability
- ECON-06 PASS: 100% of bundle price enters prize pools; lootbox return is a fraction of deposit; activity boost requires massive ongoing investment

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- ECON-06 requirement satisfied
- F01 economic assessment complete; can inform remediation decisions (specification update vs. code change)
- Whale bundle economics documented for cross-reference by remaining ECON requirements

## Self-Check: PASSED

- [x] FOUND: 05-06-FINDINGS-whale-bundle-ev.md
- [x] FOUND: 05-06-SUMMARY.md
- [x] FOUND: commit 7440137

---
*Phase: 05-economic-attack-surface*
*Completed: 2026-03-01*
