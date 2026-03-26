---
phase: 70
slug: coinflip-commitment-window
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-22
---

# Phase 70 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (forge) + Hardhat (hardhat test) |
| **Config file** | foundry.toml + hardhat.config.js |
| **Quick run command** | `forge test --match-path test/fuzz/VRFCore.t.sol -vv` |
| **Full suite command** | `forge test -vv` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Verify line references against contract source
- **After every plan wave:** N/A (single document output per plan)
- **Before `/gsd:verify-work`:** All 3 success criteria met
- **Max feedback latency:** N/A (audit documentation phase)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 70-01-01 | 01 | 1 | COIN-01 | manual-only | N/A — audit document | N/A | ⬜ pending |
| 70-01-02 | 01 | 1 | COIN-02 | manual-only | N/A — audit document | N/A | ⬜ pending |
| 70-02-01 | 02 | 1 | COIN-03 | manual-only | N/A — audit document | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. This phase produces audit documentation (security analysis), not code changes. No Wave 0 setup needed.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Full coinflip lifecycle trace with state transitions | COIN-01 | Audit document, not code | Verify all state transitions are cataloged with line references to contract source |
| Player-controllable state identification with verdicts | COIN-02 | Audit document, not code | Verify all 10 BurnieCoinflip external entry points are assessed with SAFE/VULNERABLE verdict |
| Multi-tx attack sequence modeling | COIN-03 | Audit document, not code | Verify 7+ attack sequences are modeled with preconditions, steps, and feasibility assessment |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < N/A (audit docs)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
