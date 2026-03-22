---
phase: 63
slug: vrf-request-fulfillment-core
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-22
---

# Phase 63 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (forge) with Solidity 0.8.34 |
| **Config file** | foundry.toml |
| **Quick run command** | `forge test --match-path test/fuzz/VRFCore.t.sol -vvv` |
| **Full suite command** | `forge test --fuzz-runs 1000 -vvv` |
| **Estimated runtime** | ~30 seconds (quick), ~120 seconds (full fuzz) |

---

## Sampling Rate

- **After every task commit:** Run `forge test --match-path test/fuzz/VRFCore.t.sol -vvv`
- **After every plan wave:** Run `forge test --fuzz-runs 1000 -vvv`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 63-01-01 | 01 | 1 | VRFC-01 | fuzz + gas | `forge test --match-test test_callbackNeverReverts --gas-report -vvv` | ❌ W0 | ⬜ pending |
| 63-01-02 | 01 | 1 | VRFC-02 | fuzz | `forge test --match-test test_vrfRequestIdLifecycle -vvv` | ❌ W0 | ⬜ pending |
| 63-01-03 | 01 | 1 | VRFC-03 | unit + fuzz | `forge test --match-test test_rngLockedMutualExclusion -vvv` | ❌ W0 | ⬜ pending |
| 63-01-04 | 01 | 1 | VRFC-04 | fuzz | `forge test --match-test test_timeoutRetry -vvv` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/fuzz/VRFCore.t.sol` — new test file covering VRFC-01 through VRFC-04
- [ ] No new framework install needed (Foundry already configured)
- [ ] No new helpers needed (VRFHandler + DeployProtocol already exist)

*Existing infrastructure covers framework and helper requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Slot 0 assembly access | VRFC-01 | grep-based code audit | `grep -rn "assembly" contracts/ \| grep -i "slot\|sstore\|sload"` — verify no raw Slot 0 writes |

*All other phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
