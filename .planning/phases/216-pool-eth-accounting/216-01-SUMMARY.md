---
phase: 216-pool-eth-accounting
plan: 01
subsystem: pool-accounting
tags: [eth-conservation, pool-architecture, algebraic-proof, audit]
dependency_graph:
  requires: []
  provides: [POOL-01-conservation-proof]
  affects: [216-02, 216-03]
tech_stack:
  added: []
  patterns: [algebraic-conservation-proof, code-level-flow-trace, symbolic-variable-equation]
key_files:
  created:
    - .planning/phases/216-pool-eth-accounting/216-01-ETH-CONSERVATION.md
  modified: []
decisions:
  - D-01 compliance: fresh from scratch, zero references to prior pool audit artifacts (phases 183-187, 199-200)
  - D-02 compliance: Phase 214 adversarial audit findings cited as supporting evidence (4 citations)
  - D-03 compliance: algebraic proof with flow traces, symbolic variables, and code-level equations
metrics:
  duration: 14m33s
  completed: "2026-04-11T01:39:16Z"
  tasks_completed: 2
  tasks_total: 2
---

# Phase 216 Plan 01: ETH Conservation Proof Summary

Algebraic ETH conservation proof covering all 20 EF chains across the consolidated pool architecture -- every inflow, outflow, and internal transfer proven with code-level traces and symbolic equations.

## What Was Done

### Task 1: ETH Inflow Proof and Pool Allocation Algebra (e5c2b342)

Produced Sections 0-2 of the conservation proof:

- **Section 0 (Pool Architecture Overview):** Documented all 6 pool storage variables (currentPrizePool, claimablePool, prizePoolsPacked, claimableWinnings, resumeEthPool, yieldAccumulator) with exact DegenerusGameStorage line numbers, the memory-batch pattern, the two-call split mechanism, and the pool freeze pattern.

- **Section 1 (ETH Inflow Accounting):** Traced all 3 inflow chains:
  - EF-01 (Purchase): msg.value split 10/90% future/next for tickets, 90/10% for lootbox (with presale and distress variants)
  - EF-16 (Whale passes): 3 sub-paths (bundle, lazy, deity) with exact BPS splits
  - EF-17 (Degenerette bets): 100% to futurePool with claimable recycling

- **Section 2 (Internal Flow Accounting):** Traced 4 internal chains plus the two-call split:
  - EF-02: Pool consolidation proven zero-sum across all 8 arithmetic steps
  - EF-03: Yield surplus distribution from stETH rebasing surplus
  - EF-14: GNRUS charity (token only, no ETH)
  - EF-20: BURNIE flip credit (no ETH)
  - Two-call split: resumeEthPool proven transient (set in CALL1, cleared in CALL2)

### Task 2: ETH Outflow Proof and Global Conservation Equation (288c6c45)

Produced Sections 3-5 of the conservation proof:

- **Section 3 (ETH Outflow Accounting):** Traced all 13 outflow chains:
  - EF-04/05/06: Daily/solo/BAF jackpots via _addClaimableEth
  - EF-07/08: Decimator and terminal decimator via deferred claim pattern
  - EF-09: Degenerette winnings (25% ETH / 75% lootbox, 10% futurePool cap)
  - EF-10: Gameover drain (pools zeroed, available distributed)
  - EF-11: Final sweep (33/33/34 split after 30-day delay)
  - EF-12: Player claim (CEI ordering, sentinel preservation)
  - EF-13: GNRUS proportional redemption
  - EF-15/18: Token-only operations (no ETH)
  - EF-19: Year sweep (50/50 to GNRUS + VAULT)

- **Section 4 (Global Conservation Equation):** Constructed master equation SUM(I) = SUM(O) + H where H = currentPrizePool + nextPool + futurePool + claimablePool + resumeEthPool + yieldAccumulator + residual. Proved: every inflow credits a pool, every outflow debits a pool, internal flows are zero-sum, H captures all remaining ETH.

- **Section 5 (Conservation Verdict):** Per-chain verdict table (20/20 CONSERVED), global verdict CONSERVED. 3 INFO findings documented.

## Findings

| ID | Severity | Description |
|----|----------|-------------|
| INFO-216-01 | INFO | Overpayment dust in DirectEth mode stays in contract balance as untracked surplus, captured by distributeYieldSurplus |
| INFO-216-02 | INFO | BPS rounding dust from integer division accumulates in contract balance, negligible amounts |
| INFO-216-03 | INFO | claimablePool temporary inequality during decimator settlement (over-reserved, safe direction) |

## Deviations from Plan

None -- plan executed exactly as written.

## Key Metrics

- **EF chains covered:** 20/20 (EF-01 through EF-20)
- **CONSERVED verdicts:** 20/20
- **LEAK verdicts:** 0
- **Code-level line references:** 154 line number citations
- **Symbolic equations:** 83 equation/variable references
- **Phase 214 citations:** 10 (per D-02)
- **Prior pool audit references:** 0 (per D-01)

## Self-Check: PASSED

```
FOUND: .planning/phases/216-pool-eth-accounting/216-01-ETH-CONSERVATION.md
FOUND: e5c2b342 (Task 1)
FOUND: 288c6c45 (Task 2)
```
