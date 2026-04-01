---
phase: 69
slug: mutation-verdicts
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-22
---

# Phase 69 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual audit verification (analytical phase — no runnable code produced) |
| **Config file** | none |
| **Quick run command** | `grep -c "SAFE\|VULNERABLE" audit/v3.8-commitment-window-inventory.md` |
| **Full suite command** | `grep -c "SAFE\|VULNERABLE" audit/v3.8-commitment-window-inventory.md` |
| **Estimated runtime** | ~1 second |

---

## Sampling Rate

- **After every task commit:** Verify contract line references cited in verdicts still match source
- **After every plan wave:** Full cross-reference check of all verdicts against Phase 68 mutation surface summary table
- **Before `/gsd:verify-work`:** All 51 variables have verdicts, all VULNERABLE variables have fixes, CW-04 proof is complete
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 69-01-01 | 01 | 1 | CW-04, MUT-01 | manual | Cross-reference verdicts against Phase 68 mutation surface | N/A | pending |
| 69-01-02 | 01 | 1 | MUT-02 | manual | Verify every VULNERABLE entry has fix recommendation | N/A | pending |
| 69-02-01 | 02 | 1 | MUT-03, CW-04 | manual | Verify call-graph depth coverage and cross-reference proof | N/A | pending |

*Status: pending · green · red · flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. This is a purely analytical phase that produces audit documentation — no test stubs or framework installation needed. Verdicts are verified by cross-referencing contract source against the Phase 68 inventory.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Every variable has SAFE/VULNERABLE verdict | MUT-01 | Verdicts are analytical, not runnable code | Count verdict entries; compare against Phase 68 variable count (51) |
| VULNERABLE variables have fix recommendations | MUT-02 | Fix recommendations are text artifacts | Search for VULNERABLE entries and verify each has fix section |
| Cross-reference proof completeness | CW-04 | Proof is a logical argument, not testable code | Verify every permissionless mutation path appears in the proof |
| Call-graph depth >= 3 levels | MUT-03 | Depth tracking is in the document, not code | Verify Phase 68 D0-D3+ coverage is referenced and any gaps filled |

---

## Validation Sign-Off

- [x] All tasks have manual verify or Wave 0 dependencies
- [x] Sampling continuity: cross-reference check after each task commit
- [x] Wave 0 covers all MISSING references (none — existing infrastructure sufficient)
- [x] No watch-mode flags
- [x] Feedback latency < 5s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending