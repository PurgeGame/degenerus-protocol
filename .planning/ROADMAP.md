# Roadmap: v2.1 VRF Governance Audit + Doc Sync

**Milestone:** v2.1
**Phases:** 24-25 (continuing from v2.0 phase 23)
**Requirements:** 33

<details>
<summary>v2.0 C4A Audit Prep (Phases 19-23) -- SHIPPED 2026-03-17</summary>

- [x] **Phase 19: Delta Security Audit -- sDGNRS/DGNRS Split** (completed 2026-03-16)
- [x] **Phase 20: Correctness Verification -- Docs, Comments, Tests** (completed 2026-03-16)
- [x] **Phase 21: Novel Attack Surface -- Deep Creative Analysis** (completed 2026-03-17)
- [x] **Phase 22: Warden Simulation + Regression Check** (completed 2026-03-17)
- [x] **Phase 23: Gas Optimization -- Dead Code Removal** (completed 2026-03-17)

</details>

## Phases

- [x] **Phase 24: Core Governance Security Audit** - Adversarial security audit of VRF governance (propose/vote/execute), cross-contract interactions, vote integrity, war-game scenarios, and M-02 closure verification (completed 2026-03-17)
- [ ] **Phase 25: Audit Doc Sync** - Update all audit documentation to reflect governance changes, new findings, and M-02 closure

## Phase Details

### Phase 24: Core Governance Security Audit
**Goal**: Every governance attack vector a C4A warden could find is identified -- storage layout, access control, vote arithmetic, reentrancy, cross-contract side effects, and adversarial scenarios are all verified secure or documented as known issues
**Depends on**: Phase 23 (v2.0 complete)
**Requirements**: GOV-01, GOV-02, GOV-03, GOV-04, GOV-05, GOV-06, GOV-07, GOV-08, GOV-09, GOV-10, XCON-01, XCON-02, XCON-03, XCON-04, XCON-05, VOTE-01, VOTE-02, VOTE-03, WAR-01, WAR-02, WAR-03, WAR-04, WAR-05, WAR-06, M02-01, M02-02
**Success Criteria** (what must be TRUE):
  1. Storage layout for `lastVrfProcessedTimestamp` is verified collision-free via slot computation, and every governance-touched storage variable is mapped to its slot
  2. Every governance function (propose, vote, execute, kill, void, expiry) has a written audit verdict covering access control, arithmetic correctness, state transitions, and CEI compliance
  3. All cross-contract interaction paths between DegenerusAdmin, AdvanceModule, GameStorage, Game, and DegenerusStonk are traced and verified -- no manipulation vector exists for `lastVrfProcessedTimestamp`, death clock, unwrapTo stall, or VRF retry timeout
  4. All six war-game scenarios (compromised admin, colluding cartel, VRF oscillation, unwrapTo timing attack, post-execute governance loop, admin spam-propose) have written assessments with exploit feasibility and severity ratings
  5. M-02 (admin key compromise + VRF death = RNG control) is verified as mitigated by governance, with explicit residual risk documentation
**Plans**: 8 plans

**Constraint**: Self-audit confirmation bias (CP-01) -- this codebase was written by the same team auditing it. Phase 24 plans must apply adversarial persona protocol: assume the code is wrong, attempt to break it before concluding it is correct.

Plans:
- [ ] 24-01-PLAN.md -- Storage layout verification (GOV-01)
- [ ] 24-02-PLAN.md -- Propose access control + vote arithmetic (GOV-02, GOV-03)
- [ ] 24-03-PLAN.md -- Threshold decay + execute/kill conditions (GOV-04, GOV-05, GOV-06)
- [ ] 24-04-PLAN.md -- _executeSwap CEI + _voidAllActive (GOV-07, GOV-08)
- [ ] 24-05-PLAN.md -- Expiry + circulatingSupply + vote integrity (GOV-09, GOV-10, VOTE-01, VOTE-02, VOTE-03)
- [ ] 24-06-PLAN.md -- Cross-contract interaction traces (XCON-01, XCON-02, XCON-03, XCON-04, XCON-05)
- [ ] 24-07-PLAN.md -- War-game scenarios (WAR-01, WAR-02, WAR-03, WAR-04, WAR-05, WAR-06)
- [ ] 24-08-PLAN.md -- M-02 closure verification (M02-01, M02-02)

### Phase 25: Audit Doc Sync
**Goal**: Every audit document accurately reflects the current codebase -- no stale references to `emergencyRecover`, old VRF timeouts, or pre-governance security model remain, and all governance findings from Phase 24 are integrated
**Depends on**: Phase 24 (needs finding IDs, requirement verdicts, severity assessments)
**Requirements**: DOCS-01, DOCS-02, DOCS-03, DOCS-04, DOCS-05, DOCS-06, DOCS-07
**Success Criteria** (what must be TRUE):
  1. FINAL-FINDINGS-REPORT.md has M-02 status updated with governance mitigation rationale, all new governance findings added with finding IDs and severity, and plan/phase counts reflect v2.1
  2. KNOWN-ISSUES.md has all `emergencyRecover` references replaced with governance equivalents, and governance-specific known issues (e.g., uint8 overflow, threshold decay tradeoffs) are documented
  3. state-changing-function-audits.md has entries for all new governance functions (~8 new), updated entries for modified functions (~7 updated), and verification notes for unchanged functions (~5 verified)
  4. parameter-reference.md includes all governance constants (thresholds, timeouts, BPS values, decay schedule, stall durations)
  5. Zero stale references remain in any audit doc -- grep for `emergencyRecover`, `EmergencyRecovered`, `_threeDayRngGap`, and `18 hours` returns no hits in audit documentation
**Plans**: TBD

Plans:
- [ ] 25-01: TBD
- [ ] 25-02: TBD
- [ ] 25-03: TBD
- [ ] 25-04: TBD
- [ ] 25-05: TBD
- [ ] 25-06: TBD
- [ ] 25-07: TBD

## Progress

**Execution Order:** Phase 24 (core audit) must complete before Phase 25 (doc sync depends on audit finding IDs).

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 24. Core Governance Security Audit | 8/8 | Complete   | 2026-03-17 | - |
| 25. Audit Doc Sync | v2.1 | 0/7 | Not started | - |

---
*Roadmap created: 2026-03-17*
