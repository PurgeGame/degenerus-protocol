---
phase: 32
slug: game-modules-batch-a
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-18
---

# Phase 32 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual audit verification (no automated tests) |
| **Config file** | N/A |
| **Quick run command** | N/A (documentation review, not code execution) |
| **Full suite command** | N/A |
| **Estimated runtime** | N/A |

---

## Sampling Rate

- **After every task commit:** Review findings file for completeness -- every function and block comment in the target contract(s) should be covered
- **After every plan wave:** Cross-check that all 7 contracts are covered with no files missed
- **Before `/gsd:verify-work`:** CMT-02 and DRIFT-02 both have explicit verdicts; per-batch findings file exists with what/why/suggestion per item
- **Max feedback latency:** N/A (manual review)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 32-01-01 | 01 | 1 | CMT-02 | manual-only | N/A -- verify comment accuracy by reading code | N/A | pending |
| 32-01-02 | 01 | 1 | DRIFT-02 | manual-only | N/A -- verify intent alignment by reading code | N/A | pending |
| 32-02-01 | 02 | 1 | CMT-02 | manual-only | N/A -- verify comment accuracy by reading code | N/A | pending |
| 32-02-02 | 02 | 1 | DRIFT-02 | manual-only | N/A -- verify intent alignment by reading code | N/A | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. No test framework needed -- this is a documentation/findings-only audit phase.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| NatSpec accuracy across 7 contracts | CMT-02 | Requires understanding whether English descriptions would mislead a C4A warden | Read each NatSpec tag; verify against function implementation including delegatecall context |
| Intent drift detection | DRIFT-02 | Requires understanding designer intent vs actual behavior | Identify vestigial guards, unnecessary restrictions, stale conditions |

---

## Validation Sign-Off

- [x] All tasks have manual verify or Wave 0 dependencies
- [x] Sampling continuity: manual review after each task
- [x] Wave 0 covers all MISSING references (none needed)
- [x] No watch-mode flags
- [x] Feedback latency: N/A (manual)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
