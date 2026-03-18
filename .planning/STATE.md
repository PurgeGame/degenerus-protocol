---
gsd_state_version: 1.0
milestone: v3.0
milestone_name: Full Contract Audit + Payout Specification
status: in-progress
stopped_at: Completed 28-01-PLAN.md
last_updated: "2026-03-18T06:52:09.135Z"
last_activity: 2026-03-18 -- Completed 28-01 Recent Changes Regression (CHG-01/02/03/04 PASS, Phase 28 Plan 1/6 COMPLETE)
progress:
  total_phases: 5
  completed_phases: 2
  total_plans: 16
  completed_plans: 11
  percent: 69
---

# State

## Current Position

Phase: 28 of 30 (Cross-Cutting Verification)
Plan: 1 of 6
Status: Phase 28 Plan 1 COMPLETE -- CHG-01/02/03/04 all PASS; regression baseline established
Last activity: 2026-03-18 -- Completed 28-01 Recent Changes Regression (CHG-01/02/03/04 PASS)

Progress: [███████░░░] 69%

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-17)

**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Current focus:** Phase 28 Plan 1 COMPLETE — CHG-01/02/03/04 regression audit done; 5 more plans remain in Phase 28

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

- [Phase 27-03]: PAY-07 PASS: Coinflip deposit/win/loss lifecycle verified; both claim paths (claimCoinflips, claimCoinflipsFromBurnie) route to identical _claimCoinflipsInternal
- [Phase 27-03]: PAY-08 PASS: Bounty 1000 BURNIE/day accumulation, DGNRS gating 50k BURNIE bet + 20k BURNIE pool, half-pool credited as flip stake
- [Phase 27-03]: PAY-18 PASS: WWXRP mintPrize restricted to GAME/COIN/COINFLIP via compile-time constants; 1 WWXRP per loss day
- [Phase 27-03]: PAY-19 PASS: Recycling 1% (normal) / 1.6% (afKing) / 3.1% (max deity), boons single-use 2-day expiry 100k cap
- [Phase 27-03]: Coinflip economy fully isolated from ETH claimablePool -- operates entirely in BURNIE burn-and-mint
- [Phase 27-03]: Claim window 30/90 day asymmetry classified as INFO (by-design per v1.1 spec, absent from natspec)

- [Phase 27-04]: PAY-09 PASS: All 5 lootbox reward types verified; only whale pass remainder mutates claimablePool
- [Phase 27-04]: PAY-10 PASS: Quest rewards 100/200 BURNIE via creditFlip; streak 100 days = 10000 BPS activity
- [Phase 27-04]: PAY-11 PASS: Affiliate DGNRS uses fixed levelDgnrsAllocation (not sequential depletion per v1.1 doc)
- [Phase 27-04]: v1.1 affiliate doc discrepancy classified as FINDING-INFO (stale docs, code uses proportional fixed allocation)

- [Phase 27-05]: PAY-12 PASS: stETH yield surplus 23%/23%/46% split with ~8% buffer; rate-independent formula; insurance skim 1% of nextPool
- [Phase 27-05]: PAY-13 PASS: Accumulator x00 milestone 50% release to futurePrizePool before keep-roll; rounding favors retention
- [Phase 27-05]: PAY-17 PASS: Advance bounty 0.01 ETH base, division-by-zero impossible, 1x/2x/3x time escalation, creditFlip delivery
- [Phase 27-05]: PAY-14 PASS: sDGNRS burn proportional formula with supplyBefore; lazy-claim CP-04 defense (claimable included in totalMoney, claimed on-demand)
- [Phase 27-05]: PAY-15 PASS: DGNRS wrapper delegates to sDGNRS.burn() with complete forwarding; unwrapTo creator-only with VRF stall guard
- [Phase 27-05]: v1.1 yield split is 23%/23%/46% with ~8% buffer, not 50/25/25 as research overview approximated
- [Phase 27-05]: Advance bounty multipliers are time-based (1h/2h elapsed), not phase-based as research suggested
- [Phase 27]: Overall Phase 27 assessment: SOUND (19/19 PASS, 0 findings above INFORMATIONAL)
- [Phase 27]: claimablePool invariant verified at all 14 unique mutation sites across GAMEOVER + normal-gameplay
- [Phase 27]: Cumulative audit totals updated to 97 plans, 118 requirements, 17 phases
- [Phase 27]: 4 design decisions added to KNOWN-ISSUES.md for C4A warden awareness
- [Phase 28-01]: All 113 post-2026-02-17 commits categorized; GOV-07/VOTE-03/WAR-06 confirmed fixed; 30 constants match; FINDING-INFO-CHG04-01 for 8 stale parameter reference entries
- [Phase 28-01]: CHG-01 PASS: No commit since 2026-02-17 invalidated a prior audit verdict; regression baseline established
- [Phase 28-01]: CHG-02 PASS: DegenerusAdmin CEI fix (73c50cb3) confirmed; GOV-07 upgraded from KNOWN-ISSUE to PASS
- [Phase 28-01]: CHG-03 PASS: DeityPass soulbound (5 functions revert); sDGNRS no public transfer; DGNRS intentionally liquid

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
- Coinflip economy (PAY-07/08/18/19) all PASS -- burn-and-mint BURNIE model, net deflationary ~1.575% house edge
- Coinflip economy isolated from ETH claimablePool -- no cross-contamination with pool accounting
- WWXRP mint authority permanently restricted to GAME/COIN/COINFLIP (compile-time constants, no admin override)
- Bounty system uses virtual pool counter (not token balance) -- half-pool resolution via creditFlip
- Lootbox rewards (PAY-09): 5 types audited -- whale pass queueing (claimablePool remainder), lazy pass discount boons, deity pass discount boons, future tickets (5-tier variance), BURNIE (creditFlip)
- Quest rewards (PAY-10): 100/200 BURNIE via creditFlip, streak up to 100 days = 10000 BPS activity, version-gated progress, per-slot completion mask
- Affiliate commissions (PAY-11): 3-tier (direct/20%/4%), weighted random lottery, DGNRS fixed allocation (not sequential depletion), 0.5 ETH cap per sender per level
- v1.1 affiliate doc describes "sequential depletion" but code uses fixed levelDgnrsAllocation with totalAffiliateScore denominator -- no first-mover advantage
- stETH yield distribution (PAY-12): 23%/23%/46% split fires at level transitions via _distributeYieldSurplus; rate-independent surplus formula; ~8% unextracted buffer
- Accumulator milestones (PAY-13): yieldAccumulator grows from 46% yield + 1% nextPool skim; x00 releases 50% to futurePrizePool before keep-roll
- Advance bounty (PAY-17): 0.01 ETH in BURNIE via creditFlip; time-based 1x/2x/3x escalation; mint-gate for caller eligibility; no griefing vector
- sDGNRS burn (PAY-14): totalMoney = ethBal + stethBal + claimableEth; proportional formula with supplyBefore; ETH-preferred payout; lazy-claim CP-04 defense
- DGNRS wrapper burn (PAY-15): _burn DGNRS then delegate to sDGNRS.burn(); forwards ETH+stETH+BURNIE to caller; unwrapTo creator-only with VRF stall guard
- Contracts source of truth: /home/zak/Dev/PurgeGame/degenerus-audit/contracts/
- Economics primer: audit/v1.1-ECONOMICS-PRIMER.md
- Parameter reference: audit/v1.1-parameter-reference.md

## Session Continuity

Last session: 2026-03-18T06:52:09.134Z
Stopped at: Completed 28-01-PLAN.md
Resume file: None
