---
phase: 193-gas-ceiling-test-regression
verified: 2026-04-06T18:20:24Z
status: gaps_found
score: 0/2 must-haves verified
re_verification: false
gaps:
  - truth: "advanceGame worst-case gas ceiling measured on current codebase with safety margin >= 1.5x"
    status: failed
    reason: "Gas benchmark was run on contracts at commit 520249a2 (specialized events version). Commit 73c54315 subsequently changed 11 contract files (688 lines in JackpotModule alone), reverting the specialized events and restoring JackpotTicketWinner without awardType, restoring awardFinalDayDgnrsReward, _validateTicketBudget, _creditJackpot, _hasTraitTickets, and adding new isEthDay logic. The benchmark results in 193-01-AUDIT.md do not reflect the current codebase."
    artifacts:
      - path: ".planning/phases/193-gas-ceiling-test-regression/193-01-AUDIT.md"
        issue: "Gas measurements were taken on a different version of the contracts than what exists at HEAD. The 'contracts in scope' listed (commits 93c05869, 520249a2) do not match HEAD because commit 73c54315 substantially changed those same contracts after the benchmark was run."
      - path: "contracts/modules/DegenerusGameJackpotModule.sol"
        issue: "Current HEAD differs from the benchmarked version by 688 lines. Specialized events (JackpotEthWin, JackpotTicketWin, JackpotBurnieWin, JackpotDgnrsWin, JackpotWhalePassWin) are absent. JackpotTicketWinner has different fields (no awardType). awardFinalDayDgnrsReward, _validateTicketBudget, _creditJackpot, _hasTraitTickets all exist in current HEAD -- contra Phase 192 audit claims they were deleted."
    missing:
      - "Re-run AdvanceGameGas.test.js benchmark against current HEAD contracts and record new peak gas and safety margin"
      - "Confirm safety margin >= 1.5x against 30M block gas limit for the actual deployed code"

  - truth: "Both Foundry and Hardhat test suites show zero new regressions vs v22.0 baseline on current codebase"
    status: failed
    reason: "DELTA-03 test regression count (1232/13/3) was measured on contracts at commit 520249a2 state. The same commit (73c54315) that submitted the AUDIT.md also deleted test/unit/DgnrsSoloBucketReward.test.js (the '+1 new test' cited in the regression table) and added test/unit/WrappedWrappedXRP.test.js (855 lines, unrelated contract). The current Hardhat test count is unknown and untested against the current contract state. Additionally, several fuzz tests were modified (StorageFoundation.t.sol, TicketLifecycle.t.sol, TicketRouting.t.sol, CompositionHandler.sol, Composition.inv.t.sol) and FuturepoolSkim.t.sol was added -- Foundry baseline may also have shifted."
    artifacts:
      - path: "test/unit/DgnrsSoloBucketReward.test.js"
        issue: "File does not exist. The AUDIT.md cited this file as a new passing test contributing to the 1232 count. It was added in commit 520249a2 and deleted in commit 73c54315 (the docs commit). No test coverage of the DGNRS solo reward fold path exists in current test suite."
      - path: "test/unit/WrappedWrappedXRP.test.js"
        issue: "Added in commit 73c54315 (855 lines). Not reflected in the AUDIT.md test count. Current Hardhat passing count is unknown."
      - path: "test/fuzz/FuturepoolSkim.t.sol"
        issue: "Added in commit 73c54315 (698 lines). Not in AUDIT.md Foundry count. Current Foundry passing/failing count is unknown."
    missing:
      - "Re-run Foundry test suite (forge test) against current HEAD and document pass/fail counts"
      - "Re-run Hardhat test suite (npx hardhat test) against current HEAD and document pass/fail/pending counts"
      - "Restore or replace test coverage for DGNRS solo reward fold behavior (DgnrsSoloBucketReward.test.js was deleted without a replacement)"
      - "Verify zero new regressions relative to v22.0 baseline (commit 4282bcf8) for the current contract state"
---

# Phase 193: Gas Ceiling & Test Regression Verification Report

**Phase Goal:** The new jackpot code paths do not push advanceGame beyond safe gas limits, and both test suites confirm zero regressions
**Verified:** 2026-04-06T18:20:24Z
**Status:** GAPS FOUND
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths

Truths are derived from REQUIREMENTS.md GAS-01 and DELTA-03, the CONTEXT.md decisions (D-01 through D-06), and the phase goal statement. No PLAN.md was present; SUMMARY.md and AUDIT.md are the primary phase artifacts.

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | advanceGame worst-case gas ceiling measured on current codebase with safety margin >= 1.5x (GAS-01) | FAILED | Benchmark run on 520249a2 contract state. Commit 73c54315 changed 11 contract files including 688 lines in JackpotModule after the benchmark. Peak gas figure (6,275,799) is for a codebase that no longer exists at HEAD. |
| 2 | Foundry and Hardhat test suites show zero new regressions vs v22.0 baseline on current codebase (DELTA-03) | FAILED | Test counts (Foundry 150/28, Hardhat 1232/13/3) were measured on 520249a2 contract state. Commit 73c54315 deleted DgnrsSoloBucketReward.test.js (the cited +1 new test), added WrappedWrappedXRP.test.js (855 lines), added FuturepoolSkim.t.sol (698 lines), and modified 5 additional fuzz test files. Current test counts are unknown. |

**Score:** 0/2 truths verified

### Root Cause: "Docs" Commit Bundled Contract Changes

The fundamental problem is that commit `73c54315`, labeled "docs(193-01): gas ceiling analysis and test regression verification," made substantial changes to 11 contract and interface files, 6 fuzz test files, deleted 1 unit test, and added 2 new test files. This commit was submitted after the gas benchmark and test regression counts were recorded, creating a mismatch between what was measured and what currently exists in the codebase.

Contract changes in commit 73c54315 (relative to the benchmarked 520249a2 state):

| File | Change |
|------|--------|
| `contracts/modules/DegenerusGameJackpotModule.sol` | 688 lines changed; specialized events removed, JackpotTicketWinner restored without awardType, awardFinalDayDgnrsReward/\_creditJackpot/\_hasTraitTickets/\_validateTicketBudget restored, new JACKPOT_RESET_TIME constant added, isEthDay logic rewritten |
| `contracts/modules/DegenerusGameAdvanceModule.sol` | 153 lines changed |
| `contracts/storage/DegenerusGameStorage.sol` | 235 lines changed |
| `contracts/modules/DegenerusGameDecimatorModule.sol` | 28 lines changed |
| `contracts/DegenerusGame.sol` | 20 lines changed |
| `contracts/interfaces/IDegenerusGameModules.sol` | 12 lines changed |
| `contracts/interfaces/IBurnieCoinflip.sol` | 8 lines changed |
| `contracts/interfaces/IDegenerusGame.sol` | 4 lines changed |
| `contracts/DegenerusQuests.sol` | 5 lines changed |
| `contracts/interfaces/IDegenerusQuests.sol` | 3 lines changed |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.planning/phases/193-gas-ceiling-test-regression/193-01-AUDIT.md` | Gas benchmark results and test regression counts for current codebase | STUB | File exists and is substantive (142 lines) but documents measurements for a codebase state (commit 520249a2) that was subsequently overwritten by commit 73c54315. The benchmark table is not valid for current HEAD. |
| `test/gas/AdvanceGameGas.test.js` | Gas benchmark harness | VERIFIED | File exists (1005 lines). Substantive implementation with 17 per-stage measurements, dynamic game state progression, and summary output. The harness itself is valid -- only the recorded results in AUDIT.md are stale. |
| `test/unit/DgnrsSoloBucketReward.test.js` | Test coverage for DGNRS solo reward fold | MISSING | File was added in commit 520249a2 (cited in AUDIT.md as +1 new test) and deleted in commit 73c54315. No replacement test exists. The DGNRS solo reward fold path has no unit test coverage in the current test suite. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| Gas benchmark harness | Current contract ABI | AdvanceGameGas.test.js invokes advanceGame | NOT VERIFIED | Harness exists but was run against 520249a2 contracts. Cannot confirm results apply to current HEAD without re-running. |
| Test regression counts | Current test suite | forge test + npx hardhat test on current contracts | NOT VERIFIED | Counts in AUDIT.md reflect a snapshot that predates 73c54315 contract and test changes. |

### Data-Flow Trace (Level 4)

Not applicable. This phase produces audit documentation, not components that render dynamic data to users.

### Behavioral Spot-Checks

Step 7b is skipped for this phase per the audit-only classification (no runnable entry points beyond test harnesses that require full Hardhat/Foundry test runs). However, critical contract evidence checks were performed:

| Check | Result | Status |
|-------|--------|--------|
| Specialized events (JackpotEthWin, JackpotTicketWin, etc.) exist in current JackpotModule | Not found. Only JackpotTicketWinner, AutoRebuyProcessed, FarFutureCoinJackpotWinner, RewardJackpotsSettled exist. | FAIL (invalidates Phase 192 truth #5/#7) |
| awardFinalDayDgnrsReward deleted from JackpotModule | grep finds it at line 627. | FAIL (Phase 192 truth #5 claimed 0 grep matches) |
| _validateTicketBudget deleted from JackpotModule | grep finds it at lines 352, 492, 872, 878. | FAIL (Phase 192 truth #5 claimed 0 grep matches) |
| _creditJackpot deleted from JackpotModule | grep finds it at lines 1404, 1489, 1532, 1540. | FAIL (Phase 192 truth #5 claimed 0 grep matches) |
| _hasTraitTickets deleted from JackpotModule | grep finds it at lines 850, 878, 2149. | FAIL (Phase 192 truth #5 claimed 0 grep matches) |
| DgnrsSoloBucketReward.test.js exists | File not found. | FAIL |
| WrappedWrappedXRP.test.js reflected in AUDIT.md count | Not present in AUDIT.md. Added after benchmark run. | FAIL |
| FuturepoolSkim.t.sol reflected in AUDIT.md Foundry count | Not present in AUDIT.md. Added after benchmark run. | FAIL |

### Requirements Coverage

| Requirement | Source | Description | Status | Evidence |
|-------------|--------|-------------|--------|----------|
| GAS-01 | REQUIREMENTS.md (Phase 193) | advanceGame worst-case gas ceiling analysis with new jackpot code paths -- verify safety margin against block gas limit | BLOCKED | Benchmark exists and was run, but on contracts that were subsequently changed. Results in AUDIT.md are not valid for current HEAD. Re-run required. |
| DELTA-03 | REQUIREMENTS.md (Phase 193) | Foundry + Hardhat test suites green with zero new regressions vs v22.0 baseline | BLOCKED | Test counts measured before contract and test file changes in commit 73c54315. Current state untested. DgnrsSoloBucketReward.test.js (cited as new passing test) does not exist. Re-run required. |

**Orphaned requirements check:** REQUIREMENTS.md maps DOC-01 and DOC-02 to Phase 194. No requirements mapped to Phase 193 in REQUIREMENTS.md that were not claimed by the phase.

### Anti-Patterns Found

| File | Pattern | Severity | Impact |
|------|---------|----------|--------|
| `73c54315` (commit) | "docs" commit label on a commit that modifies 11 contract files, 6 fuzz tests, deletes 1 unit test, adds 2 test files (1553 net lines of test changes) | Blocker | Creates audit integrity gap: measurements recorded in the AUDIT.md file (added in this commit) do not reflect the contract state that also exists in this commit |
| `.planning/phases/193-gas-ceiling-test-regression/193-01-AUDIT.md` | Documents gas measurements and test counts for commit 520249a2 state while current HEAD is commit 73c54315 state | Blocker | The core deliverable of this phase is invalidated -- the audit does not cover the code that is actually in the repository |

### Human Verification Required

None. All gaps are verifiable programmatically by re-running the test harnesses and examining git history.

---

## Gaps Summary

Phase 193 has two requirement gaps that are both rooted in the same cause: commit `73c54315` bundled substantial contract changes into a commit labeled "docs," making those changes after the gas benchmark and test regression counts were recorded. The AUDIT.md documents results for a codebase state that no longer exists.

**GAS-01 (BLOCKED):** The peak gas figure of 6,275,799 gas (4.78x margin) was measured on commit 520249a2 contracts. Commit 73c54315 changed JackpotModule by 688 lines, AdvanceModule by 153 lines, and DegenerusGameStorage by 235 lines after the measurement. The safety margin threshold (>= 1.5x) may still be met, but cannot be confirmed without re-running AdvanceGameGas.test.js against the current HEAD.

**DELTA-03 (BLOCKED):** The test regression counts (Hardhat 1232/13/3, Foundry 150/28) were measured on a codebase where:
- `DgnrsSoloBucketReward.test.js` existed and passed (it was the "+1 new test" cited in the count)
- `WrappedWrappedXRP.test.js` and `FuturepoolSkim.t.sol` did not yet exist (they were added in the same commit as the AUDIT.md)
- 5 fuzz test files had different content

The current test suite has a different composition. Additionally, `DgnrsSoloBucketReward.test.js` (the test covering DGNRS solo reward fold, one of the three new v23.0 behaviors) has been deleted with no replacement, leaving the fold behavior without unit test coverage.

**Additional observation (not a Phase 193 gap, but relevant context):** The Phase 192 VERIFICATION claimed several items as verified facts about the current codebase that are contradicted by the current contract state. Specifically: (a) the specialized events (JackpotEthWin etc.) were verified as present at specific line numbers but do not exist in current HEAD; (b) awardFinalDayDgnrsReward, \_validateTicketBudget, \_creditJackpot, and \_hasTraitTickets were verified as deleted with 0 grep matches but all exist in current HEAD. This does not affect Phase 193's scope but indicates the contract revisions in 73c54315 may need a fresh Phase 192-style delta audit.

---

_Verified: 2026-04-06T18:20:24Z_
_Verifier: Claude (gsd-verifier)_
