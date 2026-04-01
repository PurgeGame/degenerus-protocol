---
phase: 54
slug: comment-correctness
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-21
---

# Phase 54 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual audit (no automated tests) |
| **Config file** | N/A |
| **Quick run command** | N/A — manual review |
| **Full suite command** | N/A — manual review |
| **Estimated runtime** | N/A |

---

## Sampling Rate

- **After every task commit:** Visual review of findings file format and deduplication against prior reports
- **After every plan wave:** Cross-reference new findings against v3.1/v3.2 consolidated findings for duplicates
- **Before `/gsd:verify-work`:** All 46 files audited, all findings documented
- **Max feedback latency:** N/A (manual audit)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 54-01-01 | 01 | 1 | CMT-01, CMT-02, CMT-03 | manual-only | N/A — semantic review | N/A | pending |
| 54-02-01 | 02 | 1 | CMT-01, CMT-02, CMT-03 | manual-only | N/A — semantic review | N/A | pending |
| 54-03-01 | 03 | 1 | CMT-01, CMT-02, CMT-03 | manual-only | N/A — semantic review | N/A | pending |
| 54-04-01 | 04 | 2 | CMT-01, CMT-02, CMT-03 | manual-only | N/A — semantic review | N/A | pending |
| 54-05-01 | 05 | 2 | CMT-01, CMT-02, CMT-03 | manual-only | N/A — semantic review | N/A | pending |
| 54-06-01 | 06 | 2 | CMT-01, CMT-02, CMT-03, CMT-04 | manual-only | N/A — semantic review | N/A | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

None — manual audit phase requires no test infrastructure.

---

## Justification for Manual-Only

Comment correctness is a semantic verification task. Automated tools cannot determine whether a comment accurately describes code behavior. The closest automated check would be NatSpec completeness (missing @param tags), but even that requires judgment about whether partial documentation is intentional.
