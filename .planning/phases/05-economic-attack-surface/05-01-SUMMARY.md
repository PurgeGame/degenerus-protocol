---
phase: 05-economic-attack-surface
plan: 01
subsystem: security-audit
tags: [solidity, sybil, expected-value, prize-distribution, activity-score, trait-ticket, jackpot, lootbox, economic-modeling]

requires:
  - phase: 03a-core-eth-flow-modules
    provides: Prize pool splits (90/10), jackpot distribution mechanics, ticket cost formula
  - phase: 03b-vrf-dependent-modules
    provides: Lootbox EV model (80-135%), per-account 10 ETH cap, activity score formula
  - phase: 02-core-state-machine-vrf
    provides: VRF integrity (unmanipulable randomness)

provides:
  - Complete Sybil EV model with per-channel proportionality analysis
  - Activity score dilution quantification at multiple deposit levels
  - ECON-01 verdict (PASS) with mathematical proof
  - Three informational findings (lootbox cap, deity virtual entries, affiliate entropy)

affects: [05-02-activity-score-inflation, 05-06-whale-lootbox-extraction]

tech-stack:
  added: []
  patterns: [proportionality-test-per-channel, zero-sum-baseline-proof]

key-files:
  created:
    - .planning/phases/05-economic-attack-surface/05-01-FINDINGS-sybil-ev-model.md
  modified: []

key-decisions:
  - "All 6 prize distribution channels proven at most proportional to ticket ownership; no super-proportional returns exist"
  - "BAF leaderboard channels (25% of BAF pool) are strictly sub-proportional, penalizing Sybil splitting"
  - "Lootbox per-account cap expansion via multi-account splitting is irrelevant because total lootbox volume is bounded by total deposit"
  - "Activity score dilution (streak, levelCount, affiliate bonus) provides natural anti-Sybil resistance"

patterns-established:
  - "Zero-sum baseline: prove total payout <= total deposit minus retention before analyzing individual channels"
  - "Proportionality test: for each channel, determine if E[group_payout] is proportional, sub-proportional, or super-proportional to ownership fraction F"

requirements-completed: [ECON-01]

duration: 5min
completed: 2026-03-01
---

# Phase 05 Plan 01: Sybil EV Model Summary

**Mathematical proof that all 6 prize channels provide at most proportional returns to ticket ownership -- ECON-01 PASS with zero super-proportional channels and activity score dilution as natural anti-Sybil defense**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-01T12:42:38Z
- **Completed:** 2026-03-01T12:48:12Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Built complete per-channel Sybil EV model covering scatter jackpot, daily jackpot, BAF leaderboard, affiliate draw, lootbox, and decimator
- Proved mathematically that every channel provides at most proportional returns to ticket fraction F, with BAF leaderboard strictly sub-proportional
- Quantified activity score dilution at D=10/50/100 ETH comparing 1 vs 5 vs 10 accounts, showing EV multiplier drops from ~129% to ~108% at 10 accounts
- Demonstrated lootbox cap expansion via multi-account splitting is irrelevant because total lootbox volume is proportional to total deposit, not account count
- Rendered ECON-01 PASS verdict with complete mathematical reasoning

## Task Commits

1. **Task 1: Model per-channel Sybil EV and compute group payout fraction vs ownership fraction** - `227232d` (feat)

## Files Created/Modified

- `.planning/phases/05-economic-attack-surface/05-01-FINDINGS-sybil-ev-model.md` - Complete Sybil EV model: 10 sections covering per-channel analysis, composite model, activity score dilution, ECON-01 verdict, and 3 informational findings

## Decisions Made

- All 6 prize distribution channels proven at most proportional to ticket ownership fraction F; no super-proportional channel exists
- BAF leaderboard channels (top BAF bettor, top coinflip bettor, random pick = 25% of BAF pool) are strictly sub-proportional, meaning Sybil splitting actively reduces returns in these channels
- Lootbox per-account 10 ETH cap expansion via multi-account splitting is a theoretical advantage that is neutralized in practice because total lootbox volume is proportional to total deposit, not account count
- Activity score dilution under splitting reduces lootbox EV from ~129% (concentrated) to ~108% (10 accounts at 5 ETH each), providing strong natural anti-Sybil resistance
- Deity pass virtual entries (2% of trait bucket, min 2) are intentional game design and do not create super-proportional returns at the pool level

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## Next Phase Readiness

- ECON-01 verdict established; Sybil EV model provides baseline for ECON-02 (activity score inflation) analysis
- Activity score dilution quantification from Section 8 directly feeds into 05-02 plan
- Lootbox EV analysis from Phase 3b-03 confirmed consistent with Sybil model assumptions

---
*Phase: 05-economic-attack-surface*
*Completed: 2026-03-01*
