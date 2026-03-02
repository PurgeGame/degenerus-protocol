---
phase: 03c-supporting-mechanics-modules
plan: 05
subsystem: audit
tags: [coinflip, bonus-range, payout-formula, EV-adjustment, reward-percent]

# Dependency graph
requires:
  - phase: 02-core-state-machine-vrf
    provides: VRF lifecycle and RNG distribution understanding
provides:
  - BurnieCoinflip bonus range boundary analysis with 14 findings
  - Payout formula verification at all boundary rewardPercent values
  - View/claim consistency confirmation
  - Unresolved day sentinel collision-free proof
affects: [04-eth-token-accounting, 05-economic-attack-surface]

# Tech tracking
tech-stack:
  added: []
  patterns: [read-only static analysis, boundary value enumeration, probability distribution verification]

key-files:
  created:
    - .planning/phases/03c-supporting-mechanics-modules/03c-05-FINDINGS-coinflip-bonus-range.md
  modified: []

key-decisions:
  - "MATH-07 rated PASS conditional: base range [50,150] verified correct; presale +6 and EV adjustment can push to 156/159 but are intentional separate mechanics"
  - "Presale bonus exceeding 150% rated INFORMATIONAL: time-limited promotional feature with minimal economic impact (2.56x vs 2.5x)"
  - "View/claim divergence on auto-rebuy carry is by design, not a bug"

patterns-established:
  - "Coinflip audit pattern: trace processCoinflipPayouts -> CoinflipDayResult storage -> claim loop and view function for formula consistency"

requirements-completed: [MATH-07]

# Metrics
duration: 3min
completed: 2026-03-01
---

# Phase 03c Plan 05: BurnieCoinflip Bonus Range Audit Summary

**Verified coinflip [50,150]% base range with 14 findings (all INFORMATIONAL/PASS), confirmed payout formula correctness, and proved unresolved-day sentinel is collision-free**

## Performance

- **Duration:** 3min
- **Started:** 2026-03-01T07:02:25Z
- **Completed:** 2026-03-01T07:05:25Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Base rewardPercent range [50, 150] verified correct with exact probability distribution (5%/5%/90%) and mean = 96.85 matching COINFLIP_REWARD_MEAN_BPS = 9685
- Presale +6 and EV adjustment edge cases documented: max final rewardPercent is 156 (presale) or 159 (EV adjustment), both intentional mechanics
- _applyEvToRewardPercent boundary values computed at all 4 corners (evBps={0,300} x rewardPercent={50,150}); adjustedBps cannot go negative with current params
- Payout formula verified at rewardPercent = 0, 50, 78, 96, 115, 150, 156, 159
- Unresolved day sentinel (rewardPercent==0 && !win) proved collision-free: no resolved day can have rewardPercent < 50
- View and claim paths use identical payout formula; auto-rebuy carry divergence is by design
- Win/loss determination (VRF LSB) confirmed independent from reward percent (keccak hash)
- Seed reuse bias (mod 20 then mod 38) mathematically proven to be zero

## Task Commits

Each task was committed atomically:

1. **Task 1: Trace processCoinflipPayouts reward generation and verify boundary behavior** - `8efa5cb` (feat)

**Plan metadata:** `e9c0b39` (docs: complete plan)

## Files Created/Modified
- `.planning/phases/03c-supporting-mechanics-modules/03c-05-FINDINGS-coinflip-bonus-range.md` - Complete audit findings with 5 sections, 14 findings, boundary value tables

## Decisions Made
- MATH-07 rated PASS conditional: base range [50,150] verified correct; presale/EV adjustments can exceed 150% but are intentional separate mechanics rated INFORMATIONAL
- Presale 156% treated as INFORMATIONAL (not LOW) because NatSpec documents 50-150% as base range, and presale is a clearly separate time-limited bonus
- View/claim auto-rebuy carry divergence classified as expected behavior, not a bug

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- MATH-07 requirement complete; findings available for cross-reference in Phase 4 (accounting) and Phase 5 (economic attack surface)
- The presale +6 overshoot and EV adjustment +9 overshoot are documented for economic modeling if needed

## Self-Check: PASSED

- FOUND: 03c-05-FINDINGS-coinflip-bonus-range.md (412 lines)
- FOUND: 03c-05-SUMMARY.md
- FOUND: commit 8efa5cb

---
*Phase: 03c-supporting-mechanics-modules*
*Completed: 2026-03-01*
