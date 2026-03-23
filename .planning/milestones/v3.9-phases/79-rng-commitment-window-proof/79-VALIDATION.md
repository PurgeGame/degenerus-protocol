---
phase: 79
slug: rng-commitment-window-proof
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-22
---

# Phase 79 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (forge) |
| **Config file** | foundry.toml |
| **Quick run command** | `forge test --match-contract JackpotCombinedPoolTest -vv` |
| **Full suite command** | `forge test` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** N/A — document output, not code changes
- **After every plan wave:** `forge test` (verify no regression from any accidental edits)
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** N/A — analytical proof phase

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 79-01-01 | 01 | 1 | RNG-01 | manual-only (audit proof document) | N/A | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. Phase 79 produces a proof document, not new code or tests.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| No permissionless action during VRF commitment window can influence far-future coin jackpot winner | RNG-01 | Analytical proof — requires backward-trace from outcome to committed inputs | Review proof document for completeness: all mutation paths enumerated, all verdicts justified with code line references |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < N/A (document phase)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
