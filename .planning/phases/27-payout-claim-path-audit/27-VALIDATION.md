---
phase: 27
slug: payout-claim-path-audit
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-17
---

# Phase 27 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual code audit (no automated test framework — this is a security audit phase) |
| **Config file** | none |
| **Quick run command** | `grep -c "PASS\|FINDING" .planning/phases/27-payout-claim-path-audit/*-PLAN.md` |
| **Full suite command** | Review all audit verdicts in partial reports |
| **Estimated runtime** | N/A (manual review) |

---

## Sampling Rate

- **After every task commit:** Verify audit verdicts are internally consistent (no contradictions with prior findings)
- **After every plan wave:** Cross-reference claimablePool mutations across all requirements in the wave
- **Before `/gsd:verify-work`:** All 19 requirements have PASS/FINDING verdicts; claimablePool invariant verified across all normal-gameplay mutation sites
- **Max feedback latency:** N/A (manual audit)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 27-01-xx | 01 | 1 | PAY-01, PAY-02 | manual audit | N/A (code review) | N/A | ⬜ pending |
| 27-02-xx | 02 | 2 | PAY-03 through PAY-06 | manual audit | N/A (code review) | N/A | ⬜ pending |
| 27-03-xx | 03 | 3 | PAY-07 through PAY-11 | manual audit | N/A (code review) | N/A | ⬜ pending |
| 27-04-xx | 04 | 4 | PAY-12 through PAY-19 | manual audit | N/A (code review) | N/A | ⬜ pending |
| 27-05-xx | 05 | 5 | ALL | cross-wave verification | N/A (code review) | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. This is a manual security audit — no test framework needed.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| All 19 payout paths | PAY-01 through PAY-19 | Security audit — requires human code review and reasoning about invariants | Read contract code, trace fund flows, verify CEI ordering, check claimablePool pairing, confirm no extraction beyond intended amounts |

---

## Validation Sign-Off

- [ ] All tasks have manual audit verdicts (PASS / FINDING-severity)
- [ ] claimablePool invariant verified at all normal-gameplay mutation sites
- [ ] No contradictions with Phase 26 GAMEOVER findings
- [ ] All 19 PAY requirements covered
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
