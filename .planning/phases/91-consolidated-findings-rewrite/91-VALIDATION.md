---
phase: 91
slug: consolidated-findings-rewrite
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-23
---

# Phase 91 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | N/A (documentation-only phase) |
| **Config file** | none |
| **Quick run command** | `grep -c "DEC-01" audit/v4.0-findings-consolidated.md` |
| **Full suite command** | See per-requirement checks below |
| **Estimated runtime** | ~2 seconds |

---

## Sampling Rate

- **After every task commit:** Run grep checks for key finding IDs and section headers
- **After every plan wave:** Full document review for structural completeness
- **Before `/gsd:verify-work`:** All 3 requirement checks pass before verification
- **Max feedback latency:** 2 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 91-01-01 | 01 | 1 | CFND-01 | smoke | `grep -c "DEC-01" audit/v4.0-findings-consolidated.md && grep -c "DGN-01" audit/v4.0-findings-consolidated.md` | N/A (creates doc) | pending |
| 91-02-01 | 02 | 1 | CFND-02 | smoke | `grep -c "DEC-01" audit/KNOWN-ISSUES.md && grep -c "DGN-01" audit/KNOWN-ISSUES.md` | N/A (updates doc) | pending |
| 91-03-01 | 03 | 2 | CFND-03 | smoke | `ls .planning/phases/89-consolidated-findings/89-VERIFICATION.md` | N/A (creates doc) | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements. No test framework needed for documentation-only phase.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Finding dedup correctness | CFND-01 | Cross-reference requires human judgment on edge cases | Verify DSC-02 counted once, RESOLVED items noted separately |
| Consistency check thoroughness | CFND-03 | Cross-phase contradiction detection requires reading context | Review 89-VERIFICATION.md for coverage completeness |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 2s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
