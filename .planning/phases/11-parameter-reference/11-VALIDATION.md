---
phase: 11
slug: parameter-reference
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-12
---

# Phase 11 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual verification against contract source |
| **Config file** | N/A (documentation phase) |
| **Quick run command** | `grep -rc "private constant\|internal constant" contracts/ \| awk -F: '{s+=$2}END{print s}'` |
| **Full suite command** | N/A |
| **Estimated runtime** | ~2 seconds |

---

## Sampling Rate

- **After every task commit:** Verify constant count matches grep baseline
- **After every plan wave:** N/A (single-wave phase)
- **Before `/gsd:verify-work`:** All constants from research inventory appear in output document
- **Max feedback latency:** 2 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 11-01-01 | 01 | 1 | PARM-01, PARM-02, PARM-03 | manual | Verify all constants from research appear in output | N/A | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| BPS constants completeness | PARM-01 | Documentation output review | Compare output BPS table row count against research inventory |
| ETH thresholds completeness | PARM-02 | Documentation output review | Compare output ETH table row count against research inventory |
| Timing constants completeness | PARM-03 | Documentation output review | Compare output timing table row count against research inventory |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 2s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
