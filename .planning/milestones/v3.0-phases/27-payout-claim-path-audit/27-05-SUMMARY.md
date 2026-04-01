---
phase: 27-payout-claim-path-audit
plan: 05
subsystem: audit
tags: [steth-yield, accumulator, advance-bounty, sdgnrs-burn, dgnrs-burn, proportional-redemption]

# Dependency graph
requires:
  - phase: 27-01
    provides: "shared payout infrastructure (_addClaimableEth, _creditClaimable, pool transition chain)"
  - phase: 27-02
    provides: "scatter/decimator pool source patterns for cross-reference"
provides:
  - "PAY-12 PASS verdict: stETH yield distribution 23%/23%/46% split"
  - "PAY-13 PASS verdict: accumulator x00 milestone 50% release"
  - "PAY-17 PASS verdict: advance bounty 0.01 ETH base, 1x/2x/3x escalation"
  - "PAY-14 PASS verdict: sDGNRS burn proportional redemption with CP-04 defense"
  - "PAY-15 PASS verdict: DGNRS wrapper burn delegation with complete forwarding"
affects: [27-06-consolidation, findings-report, known-issues]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "lazy-claim pattern: include claimable in formula, claim only when needed for payout"
    - "ETH-preferred ordering for sDGNRS burn payout"

key-files:
  created:
    - "audit/v3.0-payout-yield-burns.md"
  modified: []

key-decisions:
  - "v1.1 yield split is 23%/23%/46% with ~8% buffer (not 50/25/25 as approximated in overview)"
  - "sDGNRS burn uses lazy-claim CP-04 defense: claimable included in totalMoney, claimed only when ETH insufficient"
  - "Advance bounty multipliers are time-based (1h/2h elapsed), not phase-based as research suggested"

patterns-established:
  - "Lazy claim-then-compute: include pending claims in proportional formula, materialize only when needed"

requirements-completed: [PAY-12, PAY-13, PAY-17, PAY-14, PAY-15]

# Metrics
duration: 7min
completed: 2026-03-18
---

# Phase 27 Plan 05: Yield, Burns, and Advance Bounty Summary

**stETH yield 23/23/46 split, accumulator x00 milestone 50% release, advance bounty 0.01 ETH with time escalation, sDGNRS/DGNRS burn proportional redemption with lazy-claim CP-04 defense**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-18T05:36:29Z
- **Completed:** 2026-03-18T05:44:01Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- PAY-12 PASS: stETH yield surplus formula verified rate-independent; 23%/23%/46% split confirmed against code; insurance skim 1% of nextPool prioritized over future-take
- PAY-13 PASS: Accumulator grows from 46% yield + 1% skim; x00 milestone releases 50% to futurePrizePool before keep-roll; rounding favors retention
- PAY-17 PASS: Advance bounty 0.01 ETH in BURNIE, division-by-zero impossible (price always non-zero), time-based 1x/2x/3x escalation, creditFlip delivery, no griefing vector
- PAY-14 PASS: sDGNRS burn includes claimableEth in totalMoney (CP-04 defense); proportional formula with supplyBefore; ETH-preferred payout; BURNIE component; sequential burn correctness; CEI ordering verified
- PAY-15 PASS: DGNRS wrapper burns DGNRS, delegates to sDGNRS.burn(), forwards all assets to caller; unwrapTo is one-way creator-only conversion

## Task Commits

Each task was committed atomically:

1. **Task 1: Audit stETH yield, accumulator milestones, and advance bounty (PAY-12, PAY-13, PAY-17)** - `d6bc2a03` (feat)
2. **Task 2: Audit sDGNRS and DGNRS burn redemption (PAY-14, PAY-15)** - `a461ef17` (feat)

## Files Created/Modified
- `audit/v3.0-payout-yield-burns.md` - Full audit report covering PAY-12, PAY-13, PAY-17, PAY-14, PAY-15 with line-referenced verdicts

## Decisions Made
- v1.1 yield split confirmed as 23%/23%/46% (code: 2300/2300/4600 BPS), not 50/25/25 as approximate overview stated
- sDGNRS burn uses lazy-claim pattern for CP-04 defense: totalMoney includes claimableEth at computation time, actual claimWinnings() only called when ETH balance is insufficient for payout
- Advance bounty multipliers are purely time-based (1h/2h after day start), not tied to jackpot/transition phase as research notes suggested
- DGNRS unwrapTo blocked during VRF stall (>20h) as anti vote-stacking measure -- documented as correct access control

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All 17 of 19 PAY requirements now have verdicts (PAY-01 through PAY-15, PAY-16 through PAY-19)
- Plan 27-06 (consolidation) can proceed with full findings aggregation
- No new findings above INFORMATIONAL severity in this plan

## Self-Check: PASSED

- audit/v3.0-payout-yield-burns.md: FOUND
- 27-05-SUMMARY.md: FOUND
- Commit d6bc2a03: FOUND
- Commit a461ef17: FOUND
- PAY-12 PASS: FOUND
- PAY-13 PASS: FOUND
- PAY-17 PASS: FOUND
- PAY-14 PASS: FOUND
- PAY-15 PASS: FOUND

---
*Phase: 27-payout-claim-path-audit*
*Completed: 2026-03-18*
