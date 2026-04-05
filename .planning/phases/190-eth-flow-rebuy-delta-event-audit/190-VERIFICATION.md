---
phase: 190-eth-flow-rebuy-delta-event-audit
verified: 2026-04-05T00:00:00Z
status: passed
score: 8/8 must-haves verified
deferred:
  - truth: "Storage layout identical across all changed contracts via forge inspect"
    addressed_in: "Phase 191"
    evidence: "Phase 191 success criteria: 'forge inspect output for every changed contract shows identical storage slot assignments'"
  - truth: "Foundry test suite green with zero new failures"
    addressed_in: "Phase 191"
    evidence: "Phase 191 success criteria: 'Foundry test suite runs to completion with zero new failures'"
  - truth: "Hardhat test suite green with zero new failures"
    addressed_in: "Phase 191"
    evidence: "Phase 191 success criteria: 'Hardhat test suite runs to completion with zero new failures'"
---

# Phase 190: ETH Flow + Rebuy Delta + Event Audit Verification Report

**Phase Goal:** Every ETH flow path through the simplified BAF produces identical outcomes to the pre-simplification code -- claimable amounts, ticket counts, pool balances, whale pass claims, and event emissions are all behaviorally equivalent
**Verified:** 2026-04-05
**Status:** passed
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Non-auto-rebuy claimableDelta is algebraically identical between old 3-return and new 1-return code | VERIFIED | 190-01-SUMMARY.md FLOW-01 section; master identity proven: -bafPoolWei + (bafPoolWei - netSpend) + lootboxToFuture = -claimableDelta |
| 2 | Auto-rebuy ticket count and pool state after _setPrizePools are identical | VERIFIED | FLOW-02 (claimable portion equivalent) + DELTA-01 (storage overwrite safe): _processAutoRebuy line 839 write overwritten by _setPrizePools line 788 |
| 3 | Lootbox ticket entries are unchanged -- ETH stays in futurePool implicitly | VERIFIED | 190-01-SUMMARY.md FLOW-03; _awardJackpotTickets/_queueLootboxTickets confirmed no prizePoolsPacked write; net memFuture change = 0 in both versions |
| 4 | Whale pass claims and dust remainders are unchanged | VERIFIED | 190-01-SUMMARY.md FLOW-04; _queueWhalePassClaimCore unchanged; writes to whalePassClaims and claimablePool (dust) identical in both versions |
| 5 | Refund ETH stays in futurePool correctly under the simplified deduction | VERIFIED | 190-01-SUMMARY.md FLOW-05; old explicit add-back = new implicit retention proven algebraically |
| 6 | Auto-rebuy _setFuturePrizePool writes during BAF are provably overwritten by _setPrizePools at function end | VERIFIED | 190-02-SUMMARY.md DELTA-01; 5-step write chain traced: memFuture load -> self-call write -> stale memFuture math -> _setPrizePools overwrite; algebraic proof F-T = F-T |
| 7 | No other futurePool storage writes in the BAF/decimator self-call chain depended on the removed rebuy delta | VERIFIED | 190-02-SUMMARY.md DELTA-02; all _setFuturePrizePool call sites enumerated (12 total in codebase, only line 839 reachable from BAF self-call, 0 from decimator self-call); _processSoloBucketWinner confirmed unreachable from runBafJackpot |
| 8 | No on-chain consumer depends on the conditional emission pattern of RewardJackpotsSettled | VERIFIED | 190-02-SUMMARY.md EVT-01; emit is unconditional at line 794 (confirmed in current code); grep shows 0 on-chain consumers; test/ has 1 comment reference, no assertions on conditionality |

**Score:** 8/8 truths verified

### Deferred Items

Items not yet met but explicitly addressed in later milestone phases.

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | LAYOUT-01: Storage layout identical across all changed contracts via forge inspect | Phase 191 | Phase 191 success criteria #1: forge inspect output for every changed contract shows identical storage slot assignments |
| 2 | TEST-01: Foundry test suite green with zero new failures | Phase 191 | Phase 191 success criteria #2: Foundry test suite runs to completion with zero new failures |
| 3 | TEST-02: Hardhat test suite green with zero new failures | Phase 191 | Phase 191 success criteria #3: Hardhat test suite runs to completion with zero new failures |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.planning/phases/190-eth-flow-rebuy-delta-event-audit/190-01-SUMMARY.md` | ETH flow path equivalence audit with per-requirement verdicts containing "EQUIVALENT" | VERIFIED | File exists; 5 FLOW-XX sections; 5 Verdict: EQUIVALENT entries; master algebraic identity present; commit 6bf900d5 confirmed |
| `.planning/phases/190-eth-flow-rebuy-delta-event-audit/190-02-SUMMARY.md` | Rebuy delta removal + event audit with per-requirement verdicts containing "EQUIVALENT" | VERIFIED | File exists; DELTA-01, DELTA-02, EVT-01 sections; 3 Verdict: EQUIVALENT entries; write chain trace and grep evidence present; commit f40b2a25 confirmed |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| DegenerusGameAdvanceModule._consolidatePoolsAndRewardJackpots | DegenerusGameJackpotModule.runBafJackpot | self-call returning claimableDelta | VERIFIED | Line 717-724 in AdvanceModule: `uint256 claimed = IDegenerusGame(address(this)).runBafJackpot(...); memFuture -= claimed;` -- no longer deducts full bafPoolWei |
| _processAutoRebuy | _setFuturePrizePool | direct storage write during BAF execution | VERIFIED | Line 839 in JackpotModule: `_setFuturePrizePool(_getFuturePrizePool() + calc.ethSpent)` -- confirmed present |
| _consolidatePoolsAndRewardJackpots | _setPrizePools | batched SSTORE at function end | VERIFIED | Line 788 in AdvanceModule: `_setPrizePools(uint128(memNext), uint128(memFuture))` -- overwrites line 839's write |

### Data-Flow Trace (Level 4)

Not applicable -- this phase produces audit documentation, not runnable code components rendering dynamic data.

### Behavioral Spot-Checks

Step 7b: SKIPPED (audit-only phase; output is documentation, not runnable code). Algebraic proofs verified against contract source instead.

**Code-level spot-checks performed in lieu of behavioral tests:**

| Claim | Code Evidence | Status |
|-------|--------------|--------|
| emit RewardJackpotsSettled is unconditional | AdvanceModule line 794: `emit RewardJackpotsSettled(lvl, memFuture, claimableDelta);` -- no if-guard around emit | PASS |
| memFuture -= claimed (not -= bafPoolWei) | AdvanceModule line 722: `memFuture -= claimed;` -- confirmed via diff and current code | PASS |
| _processAutoRebuy line 839 writes _setFuturePrizePool | JackpotModule line 839: `_setFuturePrizePool(_getFuturePrizePool() + calc.ethSpent);` -- confirmed | PASS |
| _setPrizePools overwrites at line 788 | AdvanceModule line 788: `_setPrizePools(uint128(memNext), uint128(memFuture));` -- confirmed | PASS |
| _awardJackpotTickets does not write prizePoolsPacked | Grep of lines 2568-2700 in JackpotModule: zero _setFuturePrizePool/_setPrizePools calls | PASS |
| runDecimatorJackpot does not write futurePool | DecimatorModule lines 215-267: writes only decBucketOffsetPacked and decClaimRounds; returns 0 or poolWei | PASS |
| RewardJackpotsSettled has no test assertions on conditionality | test/ grep: single reference at BafRebuyReconciliation.t.sol line 27 -- comment only, no vm.expectEmit | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| FLOW-01 | 190-01-PLAN.md | BAF claimable path identical for non-auto-rebuy winners | SATISFIED | 190-01-SUMMARY.md FLOW-01: EQUIVALENT verdict with concrete trace (winner amount X, claimableDelta_total unchanged) |
| FLOW-02 | 190-01-PLAN.md | BAF auto-rebuy path identical ticket counts and pool state post-_setPrizePools | SATISFIED | 190-01-SUMMARY.md FLOW-02 (claimable portion) + 190-02-SUMMARY.md DELTA-01 (storage overwrite): together prove full equivalence |
| FLOW-03 | 190-01-PLAN.md | BAF lootbox ticket path identical (ETH stays in futurePool implicitly) | SATISFIED | 190-01-SUMMARY.md FLOW-03: EQUIVALENT verdict; no prizePoolsPacked write confirmed by code scan |
| FLOW-04 | 190-01-PLAN.md | BAF whale pass path identical whalePassClaims and dust remainder | SATISFIED | 190-01-SUMMARY.md FLOW-04: EQUIVALENT verdict; _queueWhalePassClaimCore unchanged per code |
| FLOW-05 | 190-01-PLAN.md | BAF refund path -- unused ETH stays in futurePool correctly | SATISFIED | 190-01-SUMMARY.md FLOW-05: EQUIVALENT verdict; refund is 3rd return value discarded (`,`) in new code |
| DELTA-01 | 190-02-PLAN.md | Auto-rebuy storage write safely overwritten by _setPrizePools | SATISFIED | 190-02-SUMMARY.md DELTA-01: EQUIVALENT verdict; 5-step chain traced; algebraic proof memFuture_final = F-T in both versions |
| DELTA-02 | 190-02-PLAN.md | No other futurePool writes in BAF/decimator self-call chain depend on removed delta | SATISFIED | 190-02-SUMMARY.md DELTA-02: EQUIVALENT verdict; complete enumeration table (12 _setFuturePrizePool sites; only line 839 in BAF path; 0 in decimator path) |
| EVT-01 | 190-02-PLAN.md | Unconditional RewardJackpotsSettled has no conditional consumers | SATISFIED | 190-02-SUMMARY.md EVT-01: EQUIVALENT verdict; grep evidence in both contracts/ and test/; off-chain scope noted per D-04 |
| LAYOUT-01 | (Phase 191) | Storage layout identical via forge inspect | DEFERRED | Assigned to Phase 191 per REQUIREMENTS.md traceability table |
| TEST-01 | (Phase 191) | Foundry test suite green | DEFERRED | Assigned to Phase 191 per REQUIREMENTS.md traceability table |
| TEST-02 | (Phase 191) | Hardhat test suite green | DEFERRED | Assigned to Phase 191 per REQUIREMENTS.md traceability table |

**Orphaned requirements check:** LAYOUT-01, TEST-01, TEST-02 appear in REQUIREMENTS.md mapped to Phase 191 -- correctly out of scope for Phase 190.

### Anti-Patterns Found

No anti-patterns found. The phase produced read-only audit documentation. The contracts were not modified.

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| -- | -- | None | -- | -- |

### Human Verification Required

None. All truths are verifiable from contract source and audit documentation without running the application.

### Gaps Summary

No gaps. All 8 must-have truths are verified. The three REQUIREMENTS.md items not covered (LAYOUT-01, TEST-01, TEST-02) are explicitly assigned to Phase 191 and are not within Phase 190's declared scope.

One scoping note (informational, not a gap): ROADMAP SC-1 mentions "trait jackpot, decimator payout" as prize tier contexts for FLOW-01 non-auto-rebuy equivalence. The trait jackpot (`_executeJackpot`) and decimator (`runDecimatorJackpot`) paths were not modified by commit `a2d1c585` -- only `runBafJackpot` and its caller were changed. The plans correctly scoped FLOW-01 through FLOW-05 to the BAF path only. The DELTA-02 section additionally confirms the decimator self-call path makes zero futurePool writes, resolving any concern about decimator interaction with the removed rebuy delta.

---

_Verified: 2026-04-05_
_Verifier: Claude (gsd-verifier)_
