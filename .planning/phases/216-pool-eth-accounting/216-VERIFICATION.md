---
phase: 216-pool-eth-accounting
verified: 2026-04-10T22:30:00Z
status: passed
score: 16/16 must-haves verified
overrides_applied: 0
re_verification: null
gaps: []
deferred: []
human_verification: []
---

# Phase 216: Pool & ETH Accounting Verification Report

**Phase Goal:** ETH conservation is proven across the entire restructured pool architecture — no ETH can be created, destroyed, or misrouted
**Verified:** 2026-04-10T22:30:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Algebraic ETH conservation proof covers the consolidated pool architecture (all ETH in = all ETH out + all ETH held) | VERIFIED | 216-01-ETH-CONSERVATION.md Sections 0-5: 20/20 EF chains CONSERVED, global equation SUM(I)=SUM(O)+H with 154 line-level references, symbolic variables I_purchase/I_whale/I_bet and O_daily/O_claim/O_sweep/etc |
| 2 | Every ETH inflow path (purchase, whale passes, degenerette bets) is algebraically accounted with code-level proof showing exact Solidity lines | VERIFIED | 216-01 Section 1: EF-01 (I_purchase, ticket 10/90 split), EF-16 (I_whale, 3 sub-paths with BPS constants), EF-17 (I_bet, 100% to futurePool). Line numbers and code snippets for all |
| 3 | Every ETH outflow path (jackpots, claims, redemption, sweep, drain) is algebraically accounted with code-level proof | VERIFIED | 216-01 Section 3: EF-04 through EF-19, all 13 outflow chains with symbolic equations, pool deductions identified, CONSERVED verdicts |
| 4 | Every internal ETH transfer (pool consolidation, yield distribution, resumeEthPool carry) is traced with conservation proven at each step | VERIFIED | 216-01 Section 2: EF-02 (8-step zero-sum algebraic proof for consolidation), EF-03 (yield surplus from balance excess), EF-14/EF-20 (token-only, no ETH) |
| 5 | The two-call split (SPLIT_NONE/CALL1/CALL2) is proven to neither create nor destroy ETH across the split boundary | VERIFIED | 216-01 Section 2 "Two-Call Split Conservation Proof": resumeEthPool is a transient memo (starts 0, set CALL1, cleared CALL2), pool deductions happen via currentPrizePool not resumeEthPool |
| 6 | The batched-SSTORE pool consolidation is proven to neither create nor destroy ETH during memory-to-storage writeback | VERIFIED | 216-01 EF-02: S=memFuture+memCurrent+memNext+memYieldAcc+claimableDelta proven invariant across all 8 arithmetic steps; batch writeback at L789-L795 writes exactly the computed values |
| 7 | Every SSTORE site that writes to prizePoolsPacked, currentPrizePool, claimablePool/claimableWinnings, futurePool, resumeEthPool, and yieldAccumulator is catalogued with function name, line number, mutation direction, and guard conditions | VERIFIED | 216-02-POOL-MUTATION-SSTORE.md: 75 sites across 9 contracts (sections 2.1-2.10), each with Line/Variable/Direction/AmountSource/Guard/Verdict columns |
| 8 | Intermediary variables (memory locals, packed fields) that hold ETH amounts during computation are identified and traced | VERIFIED | 216-02 Section 3: 5 memory locals in _consolidatePoolsAndRewardJackpots (memFuture, memNext, memCurrent, memYieldAcc, claimableDelta), 6 return values, 5 uint128 narrowings |
| 9 | Each SSTORE site has a verdict: SAFE or VULNERABLE | VERIFIED | 216-02 Section 4 Master Table: 75/75 SAFE, 0 VULNERABLE. Counts explicitly listed in the verdict summary |
| 10 | Jackpot payout flows (daily, solo bucket, BAF) are traced end-to-end from pool deduction through _addClaimableEth to eventual player claim, with ETH amounts verified at each handoff | VERIFIED | 216-03 Sections 2-3: daily jackpot EF-04/05 (5-step trace from advanceGame to claimableWinnings), BAF EF-06 (claimableDelta return from self-call to memFuture deduction), SSTORE cross-references at each step |
| 11 | Redemption flow (GNRUS.burn) is traced from burn call through proportional calculation to ETH+stETH transfer, with amounts verified | VERIFIED | 216-03 Section 6: 4-step trace (L296-L328), proportional calculation T-216-10 MITIGATED, CEI ordering confirmed via 214-01 |
| 12 | Sweep flows (handleFinalSweep 33/33/34 split, yearSweep 50/50 split) are traced from pool drain to external transfer, with amounts verified | VERIFIED | 216-03 Sections 7-8: final sweep thirdShare+thirdShare+gnrusAmount=totalFunds by construction (T-216-11), year sweep ethToGnrus+ethToVault=ethOut by construction |
| 13 | Gameover drain (handleGameOverDrain) is traced through terminal jackpots, BAF, decimator to final _creditClaimable, with ETH amounts verified at each step | VERIFIED | 216-03 Section 5: 6-step trace, totalFunds=claimablePool_final+vault_remainder accounting, all pool variables zeroed |
| 14 | Every cross-module handoff has an ETH amount verification: amount leaving module A = amount entering module B | VERIFIED | 216-03 Section 10.1: 20-row handoff verification matrix, all rows VERIFIED, 60 SSTORE catalogue cross-references |
| 15 | The SSTORE catalogue from Plan 02 is referenced to confirm each write in the flow matches the catalogue | VERIFIED | 216-03 contains 60 SSTORE # references; Section 10.1 lists catalogue entries for each flow in the handoff matrix |
| 16 | User decisions D-01 through D-05 honored | VERIFIED | D-01: zero references to prior pool audit phases (183-187, 199-200) confirmed; D-02: Phase 214 cited 10+ times per document; D-03: algebraic proof with symbolic variables and code traces; D-04: intermediary variables tracked in Section 3 of 216-02; D-05: three plans 1:1 to requirements |

**Score:** 16/16 truths verified

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.planning/phases/216-pool-eth-accounting/216-01-ETH-CONSERVATION.md` | Algebraic ETH conservation proof covering all 20 EF chains | VERIFIED | 55,149 bytes, 6 sections (0-5), 20/20 EF chains, 154 line references, 83 symbolic equations, global verdict CONSERVED |
| `.planning/phases/216-pool-eth-accounting/216-02-POOL-MUTATION-SSTORE.md` | Complete SSTORE catalogue for all ETH-touching state | VERIFIED | 45,286 bytes, 4 sections, 9 storage variables, 10 contract subsections (2.1-2.10), 75 sites, Section 3 intermediary tracking |
| `.planning/phases/216-pool-eth-accounting/216-03-CROSS-MODULE-FLOWS.md` | Cross-module ETH flow verification for jackpot, redemption, and sweep paths | VERIFIED | 49,555 bytes, 10 sections, all 20 EF chains accounted, 17 inter-contract calls catalogued, overall verdict SOUND |
| `.planning/phases/216-pool-eth-accounting/216-01-SUMMARY.md` | Plan 01 execution summary | VERIFIED | Documents 2 tasks, commits e5c2b342 and 288c6c45 (both confirmed in git log) |
| `.planning/phases/216-pool-eth-accounting/216-02-SUMMARY.md` | Plan 02 execution summary | VERIFIED | Documents 1 task, commit cd348f67 (confirmed in git log) |
| `.planning/phases/216-pool-eth-accounting/216-03-SUMMARY.md` | Plan 03 execution summary | VERIFIED | Documents 2 tasks, commits 1e846df2 and 254da592 (both confirmed in git log) |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `MintModule._purchaseFor()` | `futurePool / currentPrizePool` | pool allocation splits | VERIFIED | 216-01 EF-01: exact futureShare/nextShare split with BPS constants, line numbers L365-L380, L1052-L1068 |
| `AdvanceModule._consolidatePoolsAndRewardJackpots()` | `prizePoolsPacked SSTORE` | memory batch writeback | VERIFIED | 216-01 EF-02 and 216-02 Section 2.2.1: batch writeback at L789-L795, memFuture/memNext/memCurrent/memYieldAcc all written back |
| `JackpotModule._addClaimableEth()` | `claimableWinnings mapping` | pool deduction + claimable credit | VERIFIED | 216-01 EF-04/06, 216-02 Section 2.3.2, 216-03 Steps 3/Section 3: SSTORE #74 confirmed for claimableWinnings write |
| `Game._claimWinningsInternal()` | ETH transfer to player | claimableWinnings deduction + send | VERIFIED | 216-01 EF-12, 216-02 Section 2.9.1, 216-03 Section 9 EF-12: CEI ordering, sentinel 1 wei, payout=amount-1, SSTORE #65/#66 |
| `AdvanceModule._consolidatePoolsAndRewardJackpots()` | `JackpotModule.payDailyJackpot()` | delegatecall after pool consolidation | VERIFIED | 216-03 Section 2 Step 1: delegatecall mechanism documented, stage STAGE_JACKPOT_DAILY_STARTED = 11 |
| `JackpotModule._addClaimableEth()` | `Game._claimWinningsInternal()` | claimableWinnings mapping bridge | VERIFIED | 216-03 Section 10.1: mapping bridge handoff type confirmed; deferred claim model explained in Section 1 |
| `GNRUS.burn()` | `Game.claimWinnings(address(this))` | external call from GNRUS to Game | VERIFIED | 216-03 Section 6 Step 2: conditional external call at L306, triggers standard _claimWinningsInternal path |
| `GameOverModule.handleFinalSweep()` | `_sendToVault() / _sendStethFirst()` | 33/33/34 split | VERIFIED | 216-03 Section 7: gnrusAmount=amount-2*thirdShare by construction, SSTORE #64, stETH-first cascade |

---

## Data-Flow Trace (Level 4)

This is a pure audit phase — no components render dynamic data from a UI/API perspective. All "data flow" is ETH value flowing through Solidity state variables, which was the subject of the audit itself. Level 4 data-flow trace is satisfied by the cross-module ETH amount verification in Section 10.1 of 216-03-CROSS-MODULE-FLOWS.md: every module boundary crossing records the exact ETH amount on both sides (source and destination) confirming amounts match and are not lost.

---

## Behavioral Spot-Checks

Step 7b: SKIPPED — this is a pure audit/documentation phase with no new runnable code. The three deliverable files are analysis documents, not executable artifacts.

All 5 task commits (e5c2b342, 288c6c45, cd348f67, 1e846df2, 254da592) exist in git history and correspond to the deliverable files.

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| POOL-01 | 216-01-PLAN.md | ETH conservation proof across the restructured pool architecture (consolidated pools, write batching, two-call split) | SATISFIED | 216-01-ETH-CONSERVATION.md contains POOL-01 tag; 20/20 EF chains CONSERVED; global equation proven; per-chain verdict table |
| POOL-02 | 216-02-PLAN.md | Pool mutation audit of all SSTORE sites touching prize pool / claimable pool / future pool | SATISFIED | 216-02-POOL-MUTATION-SSTORE.md contains POOL-02 tag; 75 SSTORE sites; 0 VULNERABLE; intermediary tracking per D-04; 216-02-SUMMARY.md declares requirements-completed: [POOL-02] |
| POOL-03 | 216-03-PLAN.md | Cross-module flow verification for jackpot payouts, redemption, and sweep paths | SATISFIED | 216-03-CROSS-MODULE-FLOWS.md contains POOL-03 tag; all 20 EF chains traced; handoff matrix with SSTORE cross-references; 216-03-SUMMARY.md declares requirements-completed: [POOL-03] |

REQUIREMENTS.md traceability table marks POOL-01, POOL-02, POOL-03 all as Complete mapped to Phase 216. No orphaned requirements.

---

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | — | — | — |

No anti-patterns found. These are analysis documents, not executable code. Scanned all three audit documents for placeholder/stub indicators (TODO, FIXME, "not yet implemented", empty section bodies) — none found. All sections contain substantive analysis with code-level evidence.

---

## Human Verification Required

None. This is a pure audit/documentation phase. All verification criteria are programmatically checkable:
- File existence and size: confirmed
- Required section structure: confirmed (grep for ## Section headers)
- EF chain coverage (all 20): confirmed (grep per chain, all present)
- VULNERABLE count = 0: confirmed (master table and section 10.3)
- CONSERVED/VERIFIED verdicts: confirmed for all chains
- SSTORE site count = 75 and all SAFE: confirmed from master table
- Commits exist in git history: confirmed (all 5 commits)
- D-01 compliance (no prior phase references): confirmed (zero matches for phase 183-187/199-200 paths)
- D-02 compliance (Phase 214 cited): confirmed (10+ citations per document)
- Requirements marked complete in REQUIREMENTS.md: confirmed

---

## Deferred Items

None. Phase 217 (Findings Consolidation) will severity-classify findings from this and other audit phases, but there are no gaps from Phase 216 being deferred to 217. The 8 INFO findings (3 from Plan 01, 5 from Plan 02) are explicitly documented in the audit documents and will flow into Phase 217 as inputs.

---

## Gaps Summary

No gaps. All 16 must-have truths verified. All three POOL requirements satisfied. All required artifacts exist and are substantive. All key links traced. All user decisions honored. Zero VULNERABLE findings. Zero unresolved issues.

---

_Verified: 2026-04-10T22:30:00Z_
_Verifier: Claude (gsd-verifier)_
