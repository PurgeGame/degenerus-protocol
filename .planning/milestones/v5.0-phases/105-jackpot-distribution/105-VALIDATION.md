---
phase: 105
slug: jackpot-distribution
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-25
---

# Phase 105 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual audit verification (three-agent adversarial system) |
| **Config file** | `.planning/ULTIMATE-AUDIT-DESIGN.md` |
| **Quick run command** | `grep -c "##.*::" audit/unit-03/ATTACK-REPORT.md` |
| **Full suite command** | `grep -c "VERDICT:" audit/unit-03/ATTACK-REPORT.md && grep "PASS\|FAIL" audit/unit-03/COVERAGE-REVIEW.md` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Verify output file exists and has expected sections
- **After every plan wave:** Verify coverage counts match function inventory
- **Before `/gsd:verify-work`:** Full suite — all functions covered, all findings reviewed
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 105-01-01 | 01 | 1 | COV-01 | grep | `grep -c "pending" audit/unit-03/COVERAGE-CHECKLIST.md` | ❌ W0 | ⬜ pending |
| 105-02-01 | 02 | 2 | ATK-01..ATK-05 | grep | `grep -c "### Call Tree\|### Storage Writes\|### Attack Analysis" audit/unit-03/ATTACK-REPORT.md` | ❌ W0 | ⬜ pending |
| 105-03-01 | 03 | 3 | VAL-01..VAL-04 | grep | `grep -c "CONFIRMED\|FALSE POSITIVE\|DOWNGRADE" audit/unit-03/SKEPTIC-REVIEW.md` | ❌ W0 | ⬜ pending |
| 105-04-01 | 04 | 4 | UNIT-03 | grep | `test -f audit/unit-03/UNIT-03-FINDINGS.md` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `audit/unit-03/` — directory creation for all audit output files

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Call tree completeness | ATK-01 | Requires human review of recursive expansion | Verify every function has line numbers, no shortcuts |
| Cached-local-vs-storage | ATK-03 | Requires semantic understanding | Verify every pair listed with evidence |
| Skeptic verdict quality | VAL-01,02 | Requires domain expertise | Verify FP dismissals cite preventing lines |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
