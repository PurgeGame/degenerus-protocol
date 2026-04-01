---
phase: 47
slug: gas-optimization
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-20
---

# Phase 47 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (forge test) + Hardhat |
| **Config file** | foundry.toml / hardhat.config.ts |
| **Quick run command** | `forge test --match-path 'test/fuzz/Redemption*' -vv` |
| **Full suite command** | `forge test --match-path 'test/fuzz/Redemption*' -vvv` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `forge test --match-path 'test/fuzz/Redemption*' -vv`
- **After every plan wave:** Run `forge test --match-path 'test/fuzz/Redemption*' -vvv`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 47-01-01 | 01 | 1 | GAS-01 | analysis | `grep -c 'NEEDED\|DEAD' 47-GAS-ANALYSIS.md` | ❌ W0 | ⬜ pending |
| 47-02-01 | 02 | 1 | GAS-02 | analysis | `grep -c 'PACK\|SLOT' 47-STORAGE-PACKING.md` | ❌ W0 | ⬜ pending |
| 47-03-01 | 03 | 1 | GAS-03 | snapshot | `forge snapshot --match-path 'test/fuzz/Redemption*'` | ❌ W0 | ⬜ pending |
| 47-04-01 | 04 | 2 | GAS-04 | compile+test | `forge build && forge test` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Gas analysis document stubs for GAS-01 and GAS-02
- [ ] Foundry test file for gas snapshot baseline (GAS-03)

*Existing Foundry infrastructure covers compilation and test needs.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Storage packing recommendations | GAS-02 | Requires human review of risk/reward tradeoff | Review packing doc for correctness |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
