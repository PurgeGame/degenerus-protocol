---
phase: 104
slug: day-advancement-vrf
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-25
---

# Phase 104 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual audit verification (three-agent adversarial system) |
| **Config file** | `.planning/ULTIMATE-AUDIT-DESIGN.md` |
| **Quick run command** | `grep -c "##.*::" audit/unit-02/ATTACK-REPORT.md` (count function sections) |
| **Full suite command** | `grep -c "VERDICT:" audit/unit-02/ATTACK-REPORT.md && grep "PASS\|FAIL" audit/unit-02/COVERAGE-REVIEW.md` |
| **Estimated runtime** | ~5 seconds (grep verification) |

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
| 104-01-01 | 01 | 1 | COV-01 | grep | `grep -c "Category B\|Category C\|Category D" audit/unit-02/COVERAGE-CHECKLIST.md` | ❌ W0 | ⬜ pending |
| 104-02-01 | 02 | 2 | ATK-01..ATK-05 | grep | `grep -c "### Call Tree\|### Storage Writes\|### Attack Analysis" audit/unit-02/ATTACK-REPORT.md` | ❌ W0 | ⬜ pending |
| 104-03-01 | 03 | 3 | VAL-01..VAL-04 | grep | `grep -c "CONFIRMED\|FALSE POSITIVE\|DOWNGRADE" audit/unit-02/SKEPTIC-REVIEW.md` | ❌ W0 | ⬜ pending |
| 104-04-01 | 04 | 4 | UNIT-02 | grep | `test -f audit/unit-02/FINDINGS.md && grep -c "severity" audit/unit-02/FINDINGS.md` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `audit/unit-02/` — directory creation for all audit output files

*Existing infrastructure covers all phase requirements — audit outputs are markdown documents verified by grep.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Call tree completeness | ATK-01 | Requires human review of recursive expansion depth | Verify every function in call tree has line numbers and no "..." shortcuts |
| Cached-local-vs-storage correctness | ATK-03 | Requires semantic understanding of variable aliasing | Verify every (ancestor_local, descendant_write) pair listed with evidence |
| Skeptic verdict quality | VAL-01,02 | Requires domain expertise to evaluate dismissals | Verify FALSE POSITIVE dismissals cite specific preventing lines |
| Ticket queue drain verdict | UNIT-02 SC5 | Requires end-to-end trace of queue mechanics | Verify trace covers full lifecycle: write → batch → consumption |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
