---
phase: 05-economic-attack-surface
plan: 02
subsystem: economic-security
tags: [activity-score, lootbox-ev, quest-streak, affiliate, whale-bundle, deity-pass, sybil]

requires:
  - phase: 03b-vrf-dependent-modules
    provides: Lootbox EV model (80-135% with 10 ETH cap)
  - phase: 03c-supporting-mechanics-modules
    provides: Whale bundle pricing verification, activity score max 30500 BPS
provides:
  - Complete activity score inflation vector enumeration with cost-per-EV-unit ratios
  - ECON-02 PASS verdict with numeric evidence
  - Self-referral prevention confirmation with code line references
  - Lootbox EV score-lock mechanism documentation
affects: [05-economic-attack-surface, 05-06-whale-bundle]

tech-stack:
  added: []
  patterns: [cost-per-EV-unit analysis, break-even level computation]

key-files:
  created:
    - .planning/phases/05-economic-attack-surface/05-02-FINDINGS-activity-score-inflation.md
  modified: []

key-decisions:
  - "ECON-02 PASS: No activity score inflation vector produces cost-to-inflate less than EV-benefit-unlocked"
  - "Quest streak is cheapest vector (0.25 ETH / 100 days) but requires sustained daily commitment and additional lootbox investment to realize benefit"
  - "Affiliate self-referral confirmed blocked at two code paths (referPlayer revert + payAffiliate VAULT lock)"
  - "Coordinated affiliate chains require 200+ ETH for maximum 5,000 BPS; 282-level break-even makes exploitation infeasible"

patterns-established:
  - "Activity score cost-per-BPS modeling: investment / BPS_gained = cost efficiency ratio"
  - "Break-even level computation: investment / (EV_surplus * cap) = levels to recoup"

requirements-completed: [ECON-02]

duration: 5min
completed: 2026-03-01
---

# Phase 05 Plan 02: Activity Score Inflation Summary

**All 7 activity score inflation vectors enumerated with cost-per-EV-unit ratios; ECON-02 PASS -- no vector enables cheap extraction above investment cost**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-01T12:42:39Z
- **Completed:** 2026-03-01T12:47:39Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Enumerated all 7 activity score components with exact BPS values, caps, and minimum ETH costs
- Computed cost-per-EV-unit for each inflation vector: quest streak (0.25 ETH / 5.71% EV), affiliate chains (200+ ETH / 7.14% EV), whale bundle (2.4 ETH / 7.9% EV), deity pass (24 ETH / 13.6% EV)
- Confirmed self-referral prevention with exact code evidence (DegenerusAffiliate.sol lines 532-540 and 397)
- Documented lootbox EV score-lock mechanism as defensive (prevents retroactive inflation)
- Composite break-even analysis at 5 activity tiers showing all require multi-level commitment

## Task Commits

Each task was committed atomically:

1. **Task 1: Enumerate all inflation vectors and compute cost-per-EV-unit** - `53aac70` (feat)

## Files Created/Modified
- `.planning/phases/05-economic-attack-surface/05-02-FINDINGS-activity-score-inflation.md` - Complete activity score inflation vector analysis with ECON-02 verdict

## Decisions Made
- ECON-02 rated PASS: all inflation vectors either require sustained time commitment (quest streak: 100 days), large capital (whale bundle: 2.4 ETH, deity pass: 24 ETH), or are blocked (self-referral)
- Quest streak identified as cheapest vector (0.25 ETH over 100 days for 10,000 BPS) but classified as intended engagement reward, not exploit
- Coordinated affiliate chains classified as economically infeasible (200+ ETH for maximum 5,000 BPS with 282-level break-even)
- Score-lock mechanism documented as defensive by design, not exploitable

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- ECON-02 complete; activity score model available for cross-reference in ECON-06 (whale bundle + lootbox extraction)
- Whale bundle activity score boost (11,500 BPS at 2.4 ETH) is a key input for 05-06

---
*Phase: 05-economic-attack-surface*
*Completed: 2026-03-01*
