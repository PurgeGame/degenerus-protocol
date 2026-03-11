---
phase: 5
slug: lock-removal
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-11
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (forge test) -- Solidity 0.8.34 |
| **Config file** | `foundry.toml` |
| **Quick run command** | `forge test --match-path test/fuzz/LockRemoval.t.sol -vvv` |
| **Full suite command** | `forge test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `forge test --match-path test/fuzz/LockRemoval.t.sol -vvv`
- **After every plan wave:** Run `forge test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 05-01-01 | 01 | 1 | LOCK-01..06 | unit | `forge test --match-path test/fuzz/LockRemoval.t.sol -vvv` | No -- Wave 0 | ⬜ pending |
| 05-01-02 | 01 | 1 | LOCK-01..06 | grep | `grep -n rngLockedFlag` across 4 modules | N/A | ⬜ pending |
| 05-01-03 | 01 | 1 | SC-3 | fuzz+invariant | `forge test` | Existing suite | ⬜ pending |
| 05-01-04 | 01 | 1 | SC-4 | snapshot | `forge snapshot --diff` | Needs baseline | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/fuzz/LockRemoval.t.sol` — LockRemovalHarness + guard-logic tests for LOCK-01 through LOCK-06
- [ ] Gas baseline: `forge snapshot > .gas-snapshot-pre-lock-removal` before code changes

*Existing Foundry infrastructure covers framework needs.*

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
