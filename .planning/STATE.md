---
gsd_state_version: 1.0
milestone: v3.0
milestone_name: Full Contract Audit + Payout Specification
status: in-progress
stopped_at: Completed 27-02-PLAN.md
last_updated: "2026-03-18T05:13:45.386Z"
last_activity: 2026-03-18 -- Completed 27-02 Scatter and Decimator Payout Audit (PAY-03, PAY-04, PAY-05, PAY-06 all PASS)
progress:
  total_phases: 5
  completed_phases: 1
  total_plans: 10
  completed_plans: 6
  percent: 60
---

# State

## Current Position

Phase: 27 of 30 (Payout/Claim Path Audit)
Plan: 2 of 6
Status: 27-02 complete (PAY-03, PAY-04, PAY-05, PAY-06), 4 plans remaining
Last activity: 2026-03-18 -- Completed 27-02 Scatter and Decimator Payout Audit (PAY-03, PAY-04, PAY-05, PAY-06 all PASS)

Progress: [██████░░░░] 60%

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-17)

**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Current focus:** Phase 27 — Payout/Claim Path Audit (19 normal-gameplay distribution systems)

## Decisions

- All 4 ancillary GAMEOVER paths PASS -- no findings above INFO severity (26-03)
- Unchecked arithmetic in deity refund loop provably safe -- Research Q3 resolved (26-03)
- Stale test comments (912d vs 365d) classified as FINDING-INFO, defer to Phase 29 (26-03)
- Safety valve can indefinitely defer GAMEOVER -- by design, requires ongoing economic activity (26-03)
- [Phase 26-02]: GO-05 FINDING-MEDIUM: _sendToVault hard reverts could block terminal distribution; accepted risk for immutable protocol-owned recipients
- [Phase 26-02]: GO-06 PASS and GO-09 PASS: reentrancy/CEI ordering and VRF fallback verified safe
- [Phase 26-01]: GO-08 PASS and GO-01 PASS: terminal decimator integration and handleGameOverDrain distribution both verified correct
- [Phase 26-01]: decBucketOffsetPacked collision impossible -- GAMEOVER and normal level completion mutually exclusive for same level (Q1)
- [Phase 26-01]: stBal not stale in handleGameOverDrain -- no delegatecall module transfers stETH (Q2)
- [Phase 26-04]: Overall GAMEOVER assessment: SOUND (conditional on GO-05 FINDING-MEDIUM)
- [Phase 26-04]: claimablePool invariant verified consistent across all 3 partial reports at all 6 mutation sites -- no inconsistencies
- [Phase 26-04]: FINAL-FINDINGS-REPORT.md updated to 91 plans, 99 requirements, 16 phases; KNOWN-ISSUES.md updated with GO-05-F01

- [Phase 27-01]: PAY-01 PASS: 1% futurePrizePool drip, 75/25 lootbox/ETH split, VRF entropy, batched claimablePool liability
- [Phase 27-01]: PAY-02 PASS: 6-14% BPS days 1-4, 100% day 5, 60/13/13/13 shares, compressed/turbo modes verified
- [Phase 27-01]: PAY-16 PASS: 2x over-collateralization via _budgetToTicketUnits, pool transition chain verified, prizePoolFrozen guard
- [Phase 27-01]: Auto-rebuy 130%/145% bonus absorbed by structural over-collateralization (net 1.38x-1.54x)

- [Phase 27-02]: PAY-03 PASS: BAF normal scatter at 10% baseFuturePool (20% at L50), 7-category prize split, whale pass queueing
- [Phase 27-02]: PAY-04 PASS: BAF century scatter at 20% baseFuturePool, distinct scatter sampling 4+4+4+38 rounds
- [Phase 27-02]: PAY-05 PASS: Decimator normal claims pro-rata formula, 50/50 ETH/lootbox, lastDecClaimRound expiry by-design
- [Phase 27-02]: PAY-06 PASS: Decimator x00 claims at 30% baseFuturePool, shared resolution/claim with normal decimator
- [Phase 27-02]: BAF always uses baseFuturePool (snapshot) not futurePoolLocal -- code is explicit
- [Phase 27-02]: lastDecClaimRound overwrite expiry classified as by-design per v1.1 spec Section 8

## Accumulated Context

- v1.0-v3.0 audit complete (phases 1-26): RNG, economic flow, delta, novel attacks, warden sim, gas optimization, VRF governance, GAMEOVER path
- Terminal decimator (490 lines, 7 files) now fully audited -- GO-08 PASS, all research questions resolved
- GAMEOVER path fully audited (9/9 requirements): 8 PASS, 1 FINDING-MEDIUM (GO-05 _sendToVault hard reverts)
- claimablePool invariant verified at all 6 mutation sites on GAMEOVER path -- consistent across all partial reports
- Jackpot distribution paths (PAY-01, PAY-02, PAY-16) all PASS -- no findings above INFORMATIONAL severity
- Shared payout infrastructure documented: _addClaimableEth, _creditClaimable, _calcAutoRebuy (see audit/v3.0-payout-jackpot-distribution.md)
- claimablePool mutation trace at 4 sites across jackpot paths verified consistent with GAMEOVER-path trace
- Scatter/decimator paths (PAY-03/04/05/06) all PASS -- pool source summary in audit/v3.0-payout-scatter-decimator.md
- Pool source distinction verified: baseFuturePool (snapshot) for BAF+x00 decimator, futurePoolLocal (running total) for normal decimator
- claimablePool invariant extended to scatter/decimator paths -- pre-reserve then deduct pattern verified correct
- Contracts source of truth: /home/zak/Dev/PurgeGame/degenerus-audit/contracts/
- Economics primer: audit/v1.1-ECONOMICS-PRIMER.md
- Parameter reference: audit/v1.1-parameter-reference.md

## Session Continuity

Last session: 2026-03-18T05:13:45.384Z
Stopped at: Completed 27-02-PLAN.md
Resume file: None
