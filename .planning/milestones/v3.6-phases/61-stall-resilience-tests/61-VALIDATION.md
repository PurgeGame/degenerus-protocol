---
phase: 61
slug: stall-resilience-tests
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-22
---

# Phase 61 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (forge) with forge-std |
| **Config file** | `foundry.toml` (test root: `test/fuzz/`) |
| **Quick run command** | `forge test --match-contract StallResilience -vvv` |
| **Full suite command** | `make invariant-test` |
| **Estimated runtime** | ~30 seconds (targeted), ~120 seconds (full) |

---

## Sampling Rate

- **After every task commit:** Run `forge test --match-contract StallResilience -vvv`
- **After every plan wave:** Run `make invariant-test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 61-01-01 | 01 | 1 | TEST-01 | integration | `forge test --match-test test_stallSwapResume -vvv` | ❌ W0 | ⬜ pending |
| 61-01-02 | 01 | 1 | TEST-02 | integration | `forge test --match-test test_coinflipClaimsAcrossGapDays -vvv` | ❌ W0 | ⬜ pending |
| 61-01-03 | 01 | 1 | TEST-03 | integration | `forge test --match-test test_lootboxOpenAfterOrphanedIndexBackfill -vvv` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/fuzz/StallResilience.t.sol` — all three test functions for TEST-01, TEST-02, TEST-03

*Existing infrastructure (DeployProtocol, MockVRFCoordinator, VRFHandler) covers all base requirements.*

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
