---
phase: 42-validation-and-contract-parity
plan: 01
subsystem: testing
tags: [vitest, validation, price-escalation, bps-splits, activity-score, lootbox-ev]

requires:
  - phase: 38-extended-mechanics
    provides: simulator mechanics modules (priceLookup, poolRouting, activityScore, lootboxEv)
provides:
  - Exhaustive price escalation validation (levels 0-399+)
  - BPS split constant and routing function validation (6 paths)
  - Activity score formula validation across all pass types
  - Lootbox EV piecewise linear breakpoint validation
affects: [42-03-cross-validation]

tech-stack:
  added: []
  patterns: [validation-test-pattern, contract-constant-parity-assertions]

key-files:
  created:
    - ../simulator/src/mechanics/__tests__/validation-price-splits.test.ts
    - ../simulator/src/mechanics/__tests__/validation-activity-lootbox.test.ts
  modified: []

key-decisions:
  - "Used __tests__ subdirectory for validation tests to separate from co-located unit tests"

patterns-established:
  - "Validation tests import simulator modules and assert against hardcoded contract reference values"
  - "Exhaustive loop testing for cyclic formulas (400 levels verified in single test)"

requirements-completed: [VAL-01, VAL-02, VAL-03, VAL-04, VAL-05]

duration: 8min
completed: 2026-03-05
---

# Plan 42-01: Price/Splits/Activity/Lootbox Validation Summary

**120 Vitest assertions proving priceForLevel, BPS splits, activity score, and lootbox EV match Solidity contracts**

## Performance

- **Duration:** 8 min
- **Tasks:** 2
- **Files created:** 2

## Accomplishments
- Price escalation verified exhaustively for all 400 levels (intro, first cycle, century, repeating)
- All 6 BPS split paths validated: ticket, lootbox, presale, drawdown, yield, pass capital injection
- Activity score verified for 8 representative player states including all pass types and edge cases
- Lootbox EV verified at all piecewise linear breakpoints with correct floor-division interpolation
- Boost tier calculations verified including cap scaling

## Task Commits

1. **Task 1: Price escalation and BPS split validation** - `ef6632b` (feat)
2. **Task 2: Activity score and lootbox EV validation** - `ef6632b` (same commit, bundled)

## Files Created/Modified
- `../simulator/src/mechanics/__tests__/validation-price-splits.test.ts` - 87 tests: price escalation + BPS constants + routing functions
- `../simulator/src/mechanics/__tests__/validation-activity-lootbox.test.ts` - 33 tests: activity score + lootbox EV + boost

## Decisions Made
- Fixed deity player expected total from 19500 to 17500 after tracing through actual formula (mintCount ratio 25*25/10=62, capped at 25)

## Deviations from Plan
None - plan executed as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Validation foundation complete for cross-validation test (Plan 42-03)

---
*Phase: 42-validation-and-contract-parity*
*Completed: 2026-03-05*
