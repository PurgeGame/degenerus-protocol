---
phase: 08-burnie-economics
plan: 01
subsystem: audit
tags: [coinflip, burnie, vrf, wagering, bounty, recycling, ev-analysis]

# Dependency graph
requires: []
provides:
  - Complete BURNIE coinflip mechanics reference for game theory agents
  - Exact EV formulas across all scenarios (base, recycling, afKing, deity, boons, last-day)
  - Bounty system lifecycle documentation
affects: [09-burnie-supply, 10-strategy-profiles, 11-parameter-reference]

# Tech tracking
tech-stack:
  added: []
  patterns: [v1.1 audit document style with Solidity code blocks and line references]

key-files:
  created:
    - audit/v1.1-burnie-coinflip.md
  modified: []

key-decisions:
  - "Documented COINFLIP_REWARD_MEAN_BPS derivation: 96.5*50+5000=9685 bps, confirming ~1.575% house edge"
  - "Included half-bps unit explanation for deity recycling (each halfBps = 0.005%) to prevent agent confusion"
  - "Documented bounty payout as flip stake (not direct mint) as critical agent-facing warning"

patterns-established:
  - "EV summary table format for agent scenario comparison"
  - "Worked examples with concrete BURNIE numbers for recycling formulas"

requirements-completed: [BURN-01]

# Metrics
duration: 4min
completed: 2026-03-12
---

# Phase 08 Plan 01: BURNIE Coinflip Mechanics Summary

**Three-tier VRF coinflip with 1.575% house edge, bounty accumulator system, and compounding afKing recycling bonuses up to 3.1%**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-12T15:06:05Z
- **Completed:** 2026-03-12T15:10:30Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Documented complete coinflip lifecycle: burn-on-deposit, VRF 50/50, mint-on-win, WWXRP consolation on loss
- Three-tier payout multiplier distribution with exact probabilities (5%/5%/90%) and EV derivation
- Bounty system lifecycle: accumulation (+1000/day), arming (new record, 1% exceed threshold), win/loss resolution
- Recycling bonus formulas: normal 1% capped 1000, afKing 1.6%, deity scaling +0.01%/level capped at 3.1%
- Last purchase day EV adjustment with linear interpolation formula and worked example
- Claim window expiry mechanics as supply sink (30d first-time, 90d subsequent)
- Coinflip boons: 5%/10%/25% single-use deity lootbox rewards with 100k deposit cap
- Agent simulation notes with compound auto-rebuy modeling and EV summary table
- Constants reference table with 25 entries including source file and line numbers

## Task Commits

Each task was committed atomically:

1. **Task 1: Document BurnieCoinflip mechanics** - `7db590a1` (feat)

**Plan metadata:** pending

## Files Created/Modified
- `audit/v1.1-burnie-coinflip.md` - Complete coinflip reference document (766 lines, 10 sections)

## Decisions Made
- Derived and documented COINFLIP_REWARD_MEAN_BPS = 9685 formula to confirm house edge calculation
- Used "half bps" unit explanation to clarify the non-standard basis point scaling in deity recycling
- Documented bounty flip-stake crediting (not direct mint) prominently as agent pitfall

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Coinflip mechanics fully documented, ready for BURNIE supply flow analysis (Phase 09)
- EV formulas and constants ready for parameter reference consolidation (Phase 11)

---
*Phase: 08-burnie-economics*
*Completed: 2026-03-12*

## Self-Check: PASSED
- audit/v1.1-burnie-coinflip.md: FOUND
- Commit 7db590a1: FOUND
