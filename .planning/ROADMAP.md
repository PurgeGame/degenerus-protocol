# Roadmap: v2.0 C4A Audit Prep

**Milestone:** v2.0
**Phases:** 19-23 (continuing from v1.2 phase 18)
**Requirements:** 27

- [x] **Phase 19: Delta Security Audit — sDGNRS/DGNRS Split** (completed 2026-03-16)
- [x] **Phase 20: Correctness Verification — Docs, Comments, Tests** (completed 2026-03-16)
- [x] **Phase 21: Novel Attack Surface — Deep Creative Analysis** (completed 2026-03-17)
- [x] **Phase 22: Warden Simulation + Regression Check** (completed 2026-03-17)
- [ ] **Phase 23: Gas Optimization — Dead Code Removal**

---

## Phase 19: Delta Security Audit — sDGNRS/DGNRS Split

**Goal:** Adversarial security review of all code changed in the sDGNRS/DGNRS split.

**Requirements:** DELTA-01, DELTA-02, DELTA-03, DELTA-04, DELTA-05, DELTA-06, DELTA-07, DELTA-08

**Plans:** 2/2 plans complete

Plans:
- [x] 19-01-PLAN.md — Core contract audit: sDGNRS + DGNRS line-by-line review + supply invariant proof (2/2 tasks, DELTA-01/02/03 PASS)
- [x] 19-02-PLAN.md — Consumer callsite audit + reward math + BPS verification + consolidated report

**Success Criteria:**
1. StakedDegenerusStonk.sol reviewed line-by-line: reentrancy, access control, reserve math, burn accounting
2. DegenerusStonk.sol reviewed: ERC20 compliance, allowance edge cases, burn delegation, unwrapTo auth
3. Supply invariant verified: DGNRS.totalSupply + unwrapped sDGNRS == sDGNRS.balanceOf(DGNRS wrapper)
4. Every game->sDGNRS callsite audited for correct Pool enum, address, and return value handling
5. payCoinflipBountyDgnrs threshold gating verified (min bet 50k, min pool 20k, BPS=20)
6. Degenerette reward math verified (cappedBet, tier BPS, pool percentage)
7. Earlybird->Lootbox dump verified (was Reward), no Reward pool reference remains
8. Written audit report with findings and severity ratings

## Phase 20: Correctness Verification — Docs, Comments, Tests

**Goal:** Ensure all documentation, NatDoc comments, and test coverage are accurate and complete.

**Requirements:** CORR-01, CORR-02, CORR-03, CORR-04

**Plans:** 3/3 plans complete

Plans:
- [ ] 20-01-PLAN.md — NatDoc fixes for DegenerusStonk.sol + stale comment fix + parameter reference + KNOWN-ISSUES + EXTERNAL-AUDIT-PROMPT corrections
- [ ] 20-02-PLAN.md — Add StakedDegenerusStonk.sol section to state-changing-function-audits.md + update FINAL-FINDINGS-REPORT.md with v2.0 delta findings
- [ ] 20-03-PLAN.md — Test coverage gap analysis + edge case tests + fuzz test compilation verification

**Success Criteria:**
1. Every NatDoc comment in changed contracts matches the actual implementation
2. All 10 audit docs verified: no stale IDegenerusStonk, ContractAddresses.DGNRS, old BPS values, burnForGame refs
3. New test file (DGNRSLiquid.test.js) covers all DGNRS wrapper functions
4. Fuzz tests compile and reference correct contract names/interfaces
5. No undocumented external/public function in new contracts

## Phase 21: Novel Attack Surface — Deep Creative Analysis

**Goal:** Find attack vectors that conventional auditing missed across 10+ prior passes.

**Requirements:** NOVEL-01, NOVEL-02, NOVEL-03, NOVEL-04, NOVEL-05, NOVEL-09, NOVEL-10, NOVEL-11, NOVEL-12

**Plans:** 4/4 plans complete

Plans:
- [ ] 21-01-PLAN.md — Economic attack modeling (MEV, flash loan, sandwich, selfdestruct) + DGNRS-as-amplifier analysis
- [ ] 21-02-PLAN.md — Composition attack mapping + griefing vector enumeration + edge case matrix
- [ ] 21-03-PLAN.md — Supply conservation invariant proofs + privilege escalation audit
- [ ] 21-04-PLAN.md — stETH rebasing timing analysis + game-over race condition analysis

**Success Criteria:**
1. Economic attack report: MEV/sandwich/flash-loan vectors on transferable DGNRS
2. Composition attack map: all cross-contract call chains involving sDGNRS+DGNRS+game+coinflip
3. Griefing vector enumeration with severity and mitigation status
4. Edge case matrix: zero amounts, max uint, dust, rounding across all new functions
5. Supply conservation invariant formally stated and verified
6. Privilege escalation audit: every address that can trigger state changes in sDGNRS
7. stETH rebasing interaction with burn timing analyzed
8. Game-over race condition analysis (concurrent burns, sweep timing)
9. DGNRS-as-attack-amplifier analysis (what's possible now that wasn't with soulbound?)

## Phase 22: Warden Simulation + Regression Check

**Goal:** Multi-agent adversarial simulation and regression verification against all prior findings.

**Requirements:** NOVEL-07, NOVEL-08

**Plans:** 3/3 plans complete

Plans:
- [ ] 22-01-PLAN.md — Three independent warden agent simulations (contract auditor, zero-day hunter, economic analyst) producing blind C4A-format reports
- [ ] 22-02-PLAN.md — Comprehensive regression verification of all prior findings (14 formal + 9 v1.0 attacks + v1.2 surfaces + Phase 21 NOVEL)
- [ ] 22-03-PLAN.md — Cross-reference deduplication of warden findings + update FINAL-FINDINGS-REPORT.md with Phase 22 results

**Success Criteria:**
1. 3+ independent adversarial agents (contract-auditor, zero-day-hunter, economic-analyst) run against current code
2. All findings cross-referenced and deduplicated
3. Every prior audit finding (v1.0-v1.2) verified against current code — still valid, fixed, or N/A
4. Any regressions flagged and fixed
5. Consolidated findings report with severity ratings

## Phase 23: Gas Optimization — Dead Code Removal

**Goal:** Identify and remove dead code, unused variables, and redundant checks without changing behavior.

**Requirements:** GAS-01, GAS-02, GAS-03, GAS-04

**Success Criteria:**
1. All unreachable zero-checks identified (guards on values that can never be zero)
2. All dead storage variables identified across all contracts
3. All dead code paths and unreachable branches identified
4. All redundant external calls and cacheable storage reads identified
5. Scavenger/Skeptic dual-agent gas audit with approved/rejected verdicts
6. Only behavior-preserving removals — all tests still pass after changes

---
*Roadmap created: 2026-03-16*
