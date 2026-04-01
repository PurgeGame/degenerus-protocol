---
phase: 71
slug: advancegame-day-rng-window
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-22
---

# Phase 71 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | N/A — audit-only phase (no code changes) |
| **Config file** | N/A |
| **Quick run command** | N/A |
| **Full suite command** | N/A |
| **Estimated runtime** | N/A |

---

## Sampling Rate

- **After every task commit:** Verify audit document cites correct contract lines and logic is sound
- **After every plan wave:** Verify cross-references between sections are consistent
- **Before `/gsd:verify-work`:** All three DAYRNG requirements must be satisfied in audit document
- **Max feedback latency:** N/A (document review, not test execution)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 71-01-01 | 01 | 1 | DAYRNG-01 | manual-only | N/A — audit document | N/A | pending |
| 71-01-02 | 01 | 1 | DAYRNG-02 | manual-only | N/A — audit document | N/A | pending |
| 71-02-01 | 02 | 1 | DAYRNG-03 | manual-only | N/A — audit document | N/A | pending |

*Status: pending · green · red · flaky*

**Justification for manual-only:** This is an audit/analysis phase. The deliverable is a markdown document containing traced analysis with code citations. No code is modified. Verification means checking that the document correctly cites contract code and the logic chains are sound.

---

## Wave 0 Requirements

None — existing test infrastructure covers code correctness. This phase produces documentation, not code changes.
