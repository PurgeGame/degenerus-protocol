---
phase: 10-reward-systems-and-modifiers
plan: 03
subsystem: affiliate
tags: [affiliate, referral, burnie, kickback, taper, dgnrs, leaderboard, lottery]

requires:
  - phase: 08-coinflip-and-burnie
    provides: BURNIE coinflip credit mechanics (creditFlip, creditCoin)
provides:
  - Affiliate reward rate table by ETH type and level
  - 3-tier weighted random lottery distribution model
  - Lootbox activity taper formula and breakpoints
  - Per-referrer commission cap mechanics
  - Kickback buyer-facing discount model
  - Affiliate bonus points calculation
  - claimAffiliateDgnrs endgame formula with deity bonus
  - Agent simulation pseudocode for affiliate EV computation
affects: [11-parameter-reference]

tech-stack:
  added: []
  patterns: [EV-equivalence proof for lottery mechanics, taper breakpoint tables]

key-files:
  created: [audit/v1.1-affiliate-system.md]
  modified: []

key-decisions:
  - "Documented weighted random lottery with full EV-equivalence proof showing P(win_i) = amount_i / totalAmount"
  - "Included determinism note: same-day, same-sender, same-code always selects same winner"
  - "Flagged SplitCoinflipCoin mode as half-EV (50% discarded) for agent awareness"

patterns-established:
  - "EV-equivalence proof pattern: show lottery preserves expected value with concrete numerical example"

requirements-completed: [AFFL-01, AFFL-02, AFFL-03]

duration: 3min
completed: 2026-03-12
---

# Phase 10 Plan 03: Affiliate System Summary

**3-tier affiliate referral system with ETH-type-dependent rates (25%/20%/5%), per-referrer commission caps, weighted random lottery distribution, lootbox taper, and per-level DGNRS endgame claims**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-12T16:09:02Z
- **Completed:** 2026-03-12T16:12:40Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Comprehensive affiliate reward reference document covering all AFFL-01/02/03 requirements
- Exact Solidity extracts for every computation: scaledAmount, commission cap, taper, kickback, weighted random lottery, claimAffiliateDgnrs
- EV-equivalence proof demonstrating lottery preserves deterministic split expected values
- Agent simulation pseudocode with taper-adjusted EV tables and cap breakpoints

## Task Commits

Each task was committed atomically:

1. **Task 1: Create affiliate system reference document** - `2b0610ab` (feat)

## Files Created/Modified
- `audit/v1.1-affiliate-system.md` - Complete affiliate referral system reference (686 lines): reward rates, commission cap, 3-tier lottery, taper, payout modes, kickback, bonus points, DGNRS claims, constants table, agent pseudocode

## Decisions Made
- Documented weighted random lottery with full EV-equivalence proof (numerical example with 3-tier chain at level 5) to prevent agent confusion about non-deterministic splits
- Noted entropy determinism: same (day, sender, code) tuple always selects same winner -- agents can predict lottery outcomes for repeated purchases
- Flagged SplitCoinflipCoin mode 2 as half-EV (50% discarded) so rational agents can evaluate mode selection

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Affiliate system fully documented, ready for parameter reference consolidation (Phase 11)
- Cross-referenced to DGNRS tokenomics for pool balance context

---
*Phase: 10-reward-systems-and-modifiers*
*Completed: 2026-03-12*
