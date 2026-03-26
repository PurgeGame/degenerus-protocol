---
phase: 83
slug: ticket-consumption-winner-selection
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-23
---

# Phase 83 — Validation Strategy

> Audit-only phase — deliverable is an audit document with file:line citations, not code changes.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | N/A — audit-only phase (no code changes) |
| **Config file** | N/A |
| **Quick run command** | `grep -c 'file:line\|:[0-9]' audit-doc.md` (citation count) |
| **Full suite command** | Manual review of audit document against requirements |
| **Estimated runtime** | ~5 seconds (grep) |

---

## Sampling Rate

- **After every task commit:** Verify audit document has file:line citations for each traced function
- **After every plan wave:** Cross-reference all citations against contract source
- **Before `/gsd:verify-work`:** All TCON-01 through TCON-04 requirements satisfied
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 83-01-01 | 01 | 1 | TCON-01 | grep | `grep -c 'ticketQueue' audit-doc.md` | N/A | pending |
| 83-01-02 | 01 | 1 | TCON-02 | grep | `grep -c 'traitBurnTicket' audit-doc.md` | N/A | pending |
| 83-01-03 | 01 | 1 | TCON-03 | grep | `grep -c 'winner index\|idx =' audit-doc.md` | N/A | pending |
| 83-01-04 | 01 | 1 | TCON-04 | grep | `grep -c 'DISCREPANCY\|NEW FINDING' audit-doc.md` | N/A | pending |

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. No new test stubs needed — this is an audit documentation phase.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| File:line citations accurate | All | Must verify against source | Open each cited file:line and confirm code matches description |
| Winner index formulas correct | TCON-03 | Mathematical verification | Manually verify each formula against Solidity source |
| Discrepancy detection complete | TCON-04 | Requires cross-referencing prior audits | Compare each finding against v3.8/v3.9 audit docs |

---

## Validation Sign-Off

- [x] All tasks have verification criteria
- [x] Sampling continuity maintained
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 5s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
