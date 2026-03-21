---
phase: 46-adversarial-sweep-economic-analysis
plan: 03
subsystem: security-audit
tags: [solidity, economics, game-theory, rational-actor, bank-run, solvency, EV-analysis]

# Dependency graph
requires:
  - phase: 44-03
    provides: solvency proof (contraction mapping P_new = 0.125*P_old + 0.875*H), accounting reconciliation, rounding analysis
  - phase: 44-02
    provides: full redemption lifecycle trace with 176 line references, period state machine proofs
provides:
  - "Rational actor strategy catalog: 4 strategies analyzed with cost-benefit and EV calculations"
  - "ETH EV derivation: proven EV-neutral (E[payout] = ethValueOwed)"
  - "BURNIE EV derivation: 1.575% house edge (E[payout] = 0.98425 * burnieOwed)"
  - "Bank-run scenario analysis: 4 sub-scenarios proving solvency under adversarial conditions"
  - "Worst-case all-max-rolls proof: 1.75 * P <= 0.875 * H < H"
affects: [adversarial-sweep-final-report, c4a-submission]

# Tech tracking
tech-stack:
  added: []
  patterns: [EV-derivation-methodology, rational-actor-strategy-catalog-format, bank-run-scenario-modeling]

key-files:
  created:
    - .planning/phases/46-adversarial-sweep-economic-analysis/46-03-economic-analysis.md
  modified: []

key-decisions:
  - "ETH payout EV-neutral: roll distribution [25,175] with E[roll]=100 yields E[payout]=ethValueOwed"
  - "BURNIE payout has 1.575% house edge: E[rewardPercent]=96.85 < 100 due to normal band midpoint"
  - "No positive-EV exploits: all 4 strategies verdict UNPROFITABLE or NEUTRAL"
  - "Bank-run worst case (all max rolls): 1.75 * P <= 0.875 * H < H -- always solvent"
  - "Wrote complete document atomically (Tasks 1+2 share single output file)"

patterns-established:
  - "EV derivation format: formula chain with exact file:line citations, step-by-step calculation, conclusion"
  - "Strategy catalog format: description, steps, cost, expected return, repeatability, verdict, evidence, detail"
  - "Bank-run modeling: sub-scenarios (single-period, multi-period, cumulative reservation, claim phase)"

requirements-completed: [ECON-01, ECON-02]

# Metrics
duration: 3min
completed: 2026-03-21
---

# Phase 46 Plan 03: Economic Analysis Summary

**Rational actor strategy catalog (4 strategies, all UNPROFITABLE/NEUTRAL) with ETH EV-neutral proof, BURNIE 1.575% house-edge derivation, and bank-run solvency proof under worst-case all-max-rolls scenario**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-21T05:26:47Z
- **Completed:** 2026-03-21T05:30:12Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- ETH payout proven EV-neutral: roll [25,175] with E[roll]=100, so E[ethPayout] = ethValueOwed (100% of fair value)
- BURNIE payout EV computed exactly: E[burniePayout] = 0.98425 * burnieOwed (1.575% house edge from E[rewardPercent]=96.85)
- 4 rational actor strategies analyzed with file:line evidence: timing attack (UNPROFITABLE -- rngLocked guard), cap manipulation (NEUTRAL -- proportional share is linear), stale accumulation (UNPROFITABLE -- self-DoS via UnresolvedClaim), multi-address splitting (UNPROFITABLE -- global cap accumulator)
- Bank-run solvency proven for all 4 sub-scenarios: single-period max burn (50% cap circuit breaker), sequential exhaustion (geometric S/2^K decay), cumulative reservation (P_after = P/2 + H/2 < H by induction), worst-case all-max-rolls (1.75 * H/2 = 0.875H < H)
- Phase 44 contraction mapping validated as holding under adversarial conditions

## Task Commits

Each task was committed atomically:

1. **Task 1: Rational Actor Strategy Catalog with EV Calculations** - `7768e323` (feat)
2. **Task 2: Bank-Run Scenario Analysis** - content included in Task 1 commit (single-file document written atomically)

## Files Created/Modified

- `.planning/phases/46-adversarial-sweep-economic-analysis/46-03-economic-analysis.md` - Complete economic analysis: ETH/BURNIE EV derivations, 4-strategy rational actor catalog, 4-sub-scenario bank-run analysis, combined summary

## Decisions Made

- Wrote the complete document (EV derivations + strategy catalog + bank-run analysis + summary) atomically in Task 1 rather than appending in Task 2, since both tasks target the same output file and the bank-run analysis depends on the EV derivation context
- Used simplified solvency bound (P/2 + H/2) for bank-run proof rather than the Phase 44 tighter contraction mapping, since both yield the same conclusion and the simpler form is more intuitive
- Documented the rewardPercent distribution using the non-presale case (presale bonus adds +6pp but is temporary and makes the system more generous to players, not less)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None - this is an analysis-only plan producing audit documentation.

## Next Phase Readiness

- Economic analysis complete: all rational actor strategies analyzed, bank-run scenario modeled
- No positive-EV exploits found -- the system is economically fair (ETH neutral, BURNIE slight house edge)
- System proven bank-run resilient under worst-case conditions
- Ready for Phase 46 completion and adversarial sweep final report

## Self-Check: PASSED

- [x] 46-03-economic-analysis.md exists
- [x] 46-03-SUMMARY.md exists
- [x] Commit 7768e323 exists in git log

---
*Phase: 46-adversarial-sweep-economic-analysis*
*Completed: 2026-03-21*
