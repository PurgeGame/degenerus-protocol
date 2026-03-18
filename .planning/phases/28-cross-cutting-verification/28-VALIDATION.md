---
phase: 28
slug: cross-cutting-verification
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-18
---

# Phase 28 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hardhat + Chai (JavaScript), Foundry for fuzz |
| **Config file** | hardhat.config.ts |
| **Quick run command** | `npx hardhat test test/edge/GameOver.test.js` |
| **Full suite command** | `npm test` |
| **Estimated runtime** | ~120 seconds |

---

## Sampling Rate

- **After every task commit:** Verify audit verdicts are internally consistent with Phases 26-27 findings (no contradictions)
- **After every plan wave:** Cross-reference all verdicts within the wave against prior phase evidence
- **Before `/gsd:verify-work`:** All 19 requirements have PASS/FINDING verdicts; FINAL-FINDINGS-REPORT.md and KNOWN-ISSUES.md updated; vulnerability ranking document produced
- **Max feedback latency:** N/A (audit phase — no automated test loop)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 28-01-xx | 01 | 1 | CHG-01..04 | manual audit | `git log --oneline --since="2026-02-17" -- contracts/` | N/A | ⬜ pending |
| 28-02-xx | 02 | 1 | INV-01..05 | manual audit | N/A (exhaustive proof) | N/A | ⬜ pending |
| 28-03-xx | 03 | 2 | EDGE-01..07 | manual audit | N/A (scenario walkthrough) | N/A | ⬜ pending |
| 28-04-xx | 04 | 2 | VULN-01..03 | manual audit | N/A (scoring + deep review) | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements. This is an audit phase — no new automated tests are deliverables. Findings may recommend new tests for deferred phases.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Commit regression review | CHG-01..04 | Requires human judgment on code diff correctness | Review each uncovered commit diff against invariant expectations |
| claimablePool solvency proof | INV-01 | Requires formal argument across all mutation sites | Enumerate all sites, prove each maintains invariant |
| Pool/supply conservation | INV-02..05 | Requires exhaustive path enumeration | Map every mutation, prove conservation holds |
| Boundary level GAMEOVER | EDGE-01..02 | Requires scenario walkthrough at specific boundaries | Walk handleGameOverDrain at level 0, 1, 100; single player |
| Griefing/timing analysis | EDGE-03..07 | Requires adversarial thinking about gas, timing, self-referral | Analyze each attack vector with explicit verdict |
| Vulnerability ranking + audit | VULN-01..03 | Requires weighted scoring and deep adversarial review | Score top 10 functions, produce ranking document |

---

## Validation Sign-Off

- [ ] All tasks have manual verification with explicit PASS/FINDING verdicts
- [ ] Sampling continuity: every plan wave has cross-reference check against prior phases
- [ ] Wave 0: N/A (audit phase)
- [ ] No watch-mode flags
- [ ] Feedback latency: N/A (audit phase)
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending