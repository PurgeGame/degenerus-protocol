---
phase: 14
slug: manipulation-window-analysis
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-14
---

# Phase 14 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual document review (audit phase — no code output) |
| **Config file** | none |
| **Quick run command** | `grep -c "BLOCKED\|SAFE BY DESIGN\|EXPLOITABLE" audit/v1.1-manipulation-windows.md` |
| **Full suite command** | `grep -c "WINDOW-0" audit/v1.1-manipulation-windows.md` |
| **Estimated runtime** | ~1 second |

---

## Sampling Rate

- **After every task commit:** Verify section headers and verdict counts match expected
- **After every plan wave:** Full requirement coverage check
- **Before `/gsd:verify-work`:** All 4 WINDOW requirements addressed with evidence
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 14-01-01 | 01 | 1 | WINDOW-01 | manual | `grep "consumption point" audit/v1.1-manipulation-windows.md` | N/A W0 | pending |
| 14-01-02 | 01 | 1 | WINDOW-01 | manual | `grep "co-state" audit/v1.1-manipulation-windows.md` | N/A W0 | pending |
| 14-02-01 | 02 | 1 | WINDOW-02 | manual | `grep -i "block builder\|front-running" audit/v1.1-manipulation-windows.md` | N/A W0 | pending |
| 14-02-02 | 02 | 1 | WINDOW-03 | manual | `grep -i "inter-block\|jackpot draw" audit/v1.1-manipulation-windows.md` | N/A W0 | pending |
| 14-03-01 | 03 | 2 | WINDOW-04 | manual | `grep -c "BLOCKED\|SAFE BY DESIGN\|EXPLOITABLE" audit/v1.1-manipulation-windows.md` | N/A W0 | pending |

*Status: pending · green · red · flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements — audit output is markdown documents.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Co-state enumeration completeness | WINDOW-01 | Requires domain judgment | Cross-reference consumption points against Phase 12 inventory |
| Adversarial timeline accuracy | WINDOW-02 | Requires security reasoning | Verify block builder model matches Chainlink VRF v2 spec |
| Inter-block gap analysis | WINDOW-03 | Requires temporal reasoning | Verify advanceGame sequence against contract state machine |
| Verdict correctness | WINDOW-04 | Requires adversarial reasoning | Each verdict must cite contract code + guard mechanism |

---

## Validation Sign-Off

- [x] All tasks have manual verify criteria
- [x] Sampling continuity: document section checks after each task
- [x] Wave 0: N/A (documentation phase)
- [x] No watch-mode flags
- [x] Feedback latency < 5s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
