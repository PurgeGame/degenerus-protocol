---
phase: 66
slug: vrf-path-test-coverage
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-22
---

# Phase 66 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry 1.5.1 + Halmos 0.3.3 |
| **Config file** | foundry.toml (existing, no changes needed) |
| **Quick run command** | `forge test --match-path test/fuzz/invariant/VRFPathInvariants.inv.t.sol -vvv` |
| **Full suite command** | `forge test -vvv --fuzz-runs 1000 && halmos --contract RedemptionRollSymbolicTest --forge-build-out forge-out --solver-timeout-assertion 60000` |
| **Estimated runtime** | ~120 seconds |

---

## Sampling Rate

- **After every task commit:** Run `forge test --match-path test/fuzz/invariant/VRFPathInvariants.inv.t.sol -vvv && forge test --match-path test/fuzz/VRFPathCoverage.t.sol -vvv`
- **After every plan wave:** Run `forge test -vvv --fuzz-runs 1000 && halmos --contract RedemptionRollSymbolicTest --forge-build-out forge-out --solver-timeout-assertion 60000`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 66-01-01 | 01 | 1 | TEST-01 | invariant | `forge test --match-contract VRFPathInvariants --match-test invariant_index -vvv` | ❌ W0 | ⬜ pending |
| 66-01-02 | 01 | 1 | TEST-02 | invariant | `forge test --match-contract VRFPathInvariants --match-test invariant_stall -vvv` | ❌ W0 | ⬜ pending |
| 66-01-03 | 01 | 1 | TEST-03 | fuzz+invariant | `forge test --match-path test/fuzz/VRFPathCoverage.t.sol -vvv --fuzz-runs 1000` | ❌ W0 | ⬜ pending |
| 66-02-01 | 02 | 1 | TEST-04 | symbolic | `halmos --contract RedemptionRollSymbolicTest --forge-build-out forge-out --solver-timeout-assertion 60000` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/fuzz/handlers/VRFPathHandler.sol` — handler for VRF path invariant testing
- [ ] `test/fuzz/invariant/VRFPathInvariants.inv.t.sol` — invariant assertions for TEST-01, TEST-02, TEST-03
- [ ] `test/fuzz/VRFPathCoverage.t.sol` — parametric fuzz tests for gap backfill edge cases (TEST-03)
- [ ] `test/halmos/RedemptionRoll.t.sol` — Halmos symbolic test for TEST-04

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
