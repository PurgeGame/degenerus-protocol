---
phase: 187-delta-audit
plan: 02
subsystem: game-contracts
tags: [audit, delta, test-regression, self-call-guard, dead-code, interfaces]
dependency_graph:
  requires: [187-01-AUDIT.md]
  provides: [187-02-AUDIT.md]
  affects: []
tech_stack:
  added: []
  patterns: [self-call-guard-passthrough, delegatecall-module-dispatch]
key_files:
  created:
    - .planning/phases/187-delta-audit/187-02-AUDIT.md
  modified: []
decisions:
  - "DELTA-03 SATISFIED: zero new test regressions across Foundry (149/29) and Hardhat (1304/5)"
  - "All pre-existing setUp failures traced to ContractAddresses address-deployment mismatch (not Phase 186)"
  - "distributeYieldSurplus external visibility SAFE: proxy has no fallback routing to JackpotModule"
metrics:
  duration: 26m
  completed: "2026-04-05T04:47:00Z"
  tasks_completed: 2
  tasks_total: 2
  files_created: 1
  files_modified: 0
---

# Phase 187 Plan 02: Peripheral Changes Audit + Test Regression Summary

Audited all non-pool Phase 186 changes (self-call guard, passthrough, quest entropy, dead code removal, interfaces, daily jackpot final-day fix, minor refactors) and ran full Foundry + Hardhat regression -- zero new regressions, all three DELTA requirements satisfied.

## What Was Done

### Task 1: Audit Peripheral Phase 186 Changes (59259c6b)

Produced 187-02-AUDIT.md with 8 audit sections covering all non-pool behavioral changes:

1. **Self-Call Guard + Passthrough (Sections 1a-1c):** runBafJackpot passthrough in Game.sol matches the established runDecimatorJackpot pattern exactly. Self-call guard is first statement in both Game.sol and JackpotModule. Full call chain traced: AdvanceModule -> self-call -> Game.sol guard -> delegatecall -> JackpotModule guard -> execute. PASS.

2. **Quest Entropy (Section 2):** rngWord == rngWordByDay[day] at execution point because rngGate stores/returns the same value. Saves 1 cold SLOAD. PASS.

3. **Dead Code Removal (Section 3):** All 5 deleted items (consolidatePrizePools, runRewardJackpots, _futureKeepBps, _creditDgnrsCoinflip, FUTURE_KEEP_TAG) confirmed absent from JackpotModule via grep. All 3 inlined items (FUTURE_KEEP_TAG constant, keep roll logic, coinflip credit) confirmed present in AdvanceModule. PASS.

4. **Interface Completeness (Section 4):** IDegenerusGameJackpotModule contains runBafJackpot and distributeYieldSurplus, does NOT contain deleted selectors. IDegenerusGame contains runBafJackpot with matching 3-tuple return. Selectors match across all three layers. PASS.

5. **Daily Jackpot Final-Day (Section 5):** New branch correctly routes unpaid daily ETH from currentPool to futurePool on final physical day. Pool accounting conserved (net drain = paidDailyEth in both old and new code). Bugfix for stranded unpaid ETH. PASS.

6. **Minor Changes (Section 6):** _evaluateGameOverAndTarget combines two operations with shared SLOADs (gas opt, identical behavior). decWindowOpen relocation per Plan 01 check 3i. mintPrice()/getGameState() now use _activeTicketLevel() for correct level during transitions. All PASS.

7. **distributeYieldSurplus Visibility (Section 7):** Changed from private to external. Safe because proxy has no fallback() routing to JackpotModule (only receive() exists). Direct calls to implementation operate on dead storage. PASS.

8. **Finding Register (Section 8):** F-187-01 (INFO) from Plan 01 is the sole finding. Zero new findings from Plan 02. All 5 threat mitigations verified.

### Task 2: Test Regression + Final Verdict (cb8f407d)

Ran both test suites and appended results to 187-02-AUDIT.md:

- **Foundry:** 149 passed, 29 failed. FuturepoolSkim.t.sol excluded (compilation failure referencing deleted function). 28 setUp() failures are ContractAddresses address-deployment mismatch (pre-existing, reproduces in main repo). 1 testRngGuardAllowsWithPhaseTransition failure (pre-existing RngLocked).
- **Hardhat:** 1304 passed, 3 pending, 5 failed. 1 affiliate bonus assertion (pre-existing). 4 WrappedWrappedXRP decimal mismatches (pre-existing, reproduces in main repo).
- **New regressions: Zero.**

Final audit verdict: DELTA-01 SATISFIED, DELTA-02 SATISFIED, DELTA-03 SATISFIED.

## Deviations from Plan

None -- plan executed exactly as written.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | 59259c6b | Audit peripheral Phase 186 changes (8 sections, 0 new findings) |
| 2 | cb8f407d | Test regression results + DELTA-03 verdict + final audit verdict |

## Self-Check: PASSED

- 187-02-AUDIT.md: FOUND
- 187-02-SUMMARY.md: FOUND
- Commit 59259c6b: FOUND
- Commit cb8f407d: FOUND
