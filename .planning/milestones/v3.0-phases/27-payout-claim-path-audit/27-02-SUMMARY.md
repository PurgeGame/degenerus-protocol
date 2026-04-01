---
phase: 27-payout-claim-path-audit
plan: 02
subsystem: audit
tags: [baf, decimator, scatter, payout, claimablePool, futurePool, whale-pass, pro-rata]

# Dependency graph
requires:
  - phase: 27-01
    provides: "Shared payout infrastructure audit (_addClaimableEth, _creditClaimable, _calcAutoRebuy)"
  - phase: 26
    provides: "GAMEOVER path audit, terminal decimator verification, claimablePool invariant at 6 mutation sites"
provides:
  - "PAY-03 PASS: BAF normal scatter audit verdict with 7-category split and whale pass verification"
  - "PAY-04 PASS: BAF century scatter audit verdict with different scatter sampling pattern"
  - "PAY-05 PASS: Decimator normal claims audit verdict with pro-rata formula and 50/50 split"
  - "PAY-06 PASS: Decimator x00 claims audit verdict with 30% baseFuturePool"
  - "Pool source summary: definitive reference for all 5 scatter/decimator pool source mappings"
  - "Cross-path claimablePool invariant verification for all 4 distribution paths"
affects: [27-consolidation, findings-report, known-issues]

# Tech tracking
tech-stack:
  added: []
  patterns: ["pool source distinction: baseFuturePool (snapshot) vs futurePoolLocal (running total)"]

key-files:
  created:
    - "audit/v3.0-payout-scatter-decimator.md"
  modified: []

key-decisions:
  - "BAF always uses baseFuturePool (not futurePoolLocal) -- code is more explicit than plan expected"
  - "lastDecClaimRound overwrite expiry classified as by-design per v1.1 spec Section 8 (not a finding)"
  - "winnerMask unused in EndgameModule -- classified as INFORMATIONAL dead code, no security impact"
  - "Unclaimed decimator ETH creates claimablePool surplus -- safe, favors protocol solvency"

patterns-established:
  - "Pool source verification: always trace which pool variable (snapshot vs running) each distribution uses"
  - "Pre-reserve then deduct pattern: decimator pre-reserves full pool in claimablePool, deducts non-ETH portions at claim time"

requirements-completed: [PAY-03, PAY-04, PAY-05, PAY-06]

# Metrics
duration: 7min
completed: 2026-03-18
---

# Phase 27 Plan 02: Scatter and Decimator Payout Audit Summary

**BAF scatter (normal+century) and decimator claims (normal+x00) all PASS with correct pool source distinction, pro-rata formula, 50/50 ETH/lootbox split, and claimablePool invariant verified across all 4 paths**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-18T05:04:46Z
- **Completed:** 2026-03-18T05:11:47Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- PAY-03 PASS: BAF normal scatter at 10% baseFuturePool (20% at L50), 7-category prize split, whale pass queueing all verified
- PAY-04 PASS: BAF century scatter at 20% baseFuturePool with distinct scatter sampling (4+4+4+38 rounds) verified
- PAY-05 PASS: Decimator normal claims with correct pro-rata formula, 50/50 ETH/lootbox split, lastDecClaimRound expiry by-design
- PAY-06 PASS: Decimator x00 claims at 30% baseFuturePool, shared resolution/claim path with normal decimator
- Pool source summary documenting all 5 distribution pool sources as definitive Phase 27 reference
- Cross-path claimablePool invariant verified consistent across all 4 distribution paths

## Task Commits

Each task was committed atomically:

1. **Task 1: Audit BAF normal and century scatter payouts (PAY-03, PAY-04)** - `e9246535` (feat)
2. **Task 2: Audit decimator normal and x00 claims (PAY-05, PAY-06)** - `b0d121eb` (feat)

**Plan metadata:** [pending] (docs: complete plan)

## Files Created/Modified
- `audit/v3.0-payout-scatter-decimator.md` - Full audit report with PAY-03/04/05/06 verdicts, pool source summary, cross-path claimablePool invariant verification

## Decisions Made
- BAF always uses `baseFuturePool` (not `futurePoolLocal`) -- the plan expected BAF normal to use `futurePoolLocal` but both variables are equal when BAF fires; code explicitly uses the snapshot variable
- `lastDecClaimRound` overwrite expiry classified as by-design per v1.1-transition-jackpots.md Section 8 (CP-02 from research) -- not a finding
- winnerMask returned by DegenerusJackpots.sol is unused in EndgameModule -- classified as INFORMATIONAL dead code with no security impact
- Unclaimed decimator ETH creates monotonically growing claimablePool surplus -- safe, favors protocol solvency

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Scatter and decimator paths fully audited, ready for Phase 27 consolidation
- Pool source summary provides definitive reference for remaining payout path audits
- claimablePool invariant now verified at scatter/decimator mutation sites, extending the invariant trace from Phase 26 (GAMEOVER) and Phase 27-01 (jackpot distribution)

## Self-Check: PASSED

- FOUND: audit/v3.0-payout-scatter-decimator.md
- FOUND: .planning/phases/27-payout-claim-path-audit/27-02-SUMMARY.md
- FOUND: e9246535 (Task 1 commit)
- FOUND: b0d121eb (Task 2 commit)

---
*Phase: 27-payout-claim-path-audit*
*Completed: 2026-03-18*
