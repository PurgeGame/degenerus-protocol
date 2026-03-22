---
phase: 67
slug: verification-doc-sync
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-22
---

# Phase 67 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry 1.5.1 + Halmos 0.3.3 |
| **Config file** | foundry.toml (existing) |
| **Quick run command** | `forge test --match-contract VRFPathInvariants -vvv` |
| **Full suite command** | `forge test -vvv --fuzz-runs 1000 && FOUNDRY_TEST=test/halmos forge build --build-info && halmos --contract RedemptionRollSymbolicTest --forge-build-out forge-out --solver-timeout-assertion 60000` |
| **Estimated runtime** | ~120 seconds |

---

## Sampling Rate

- **After every task commit:** Run `forge test --match-contract VRFPathInvariants -vvv`
- **After every plan wave:** Run `forge test -vvv --fuzz-runs 1000`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 67-01-01 | 01 | 1 | TEST-01, TEST-02, TEST-03, TEST-04 | verification | `forge test -vvv --fuzz-runs 1000 && halmos --contract RedemptionRollSymbolicTest` | Existing | pending |
| 67-02-01 | 02 | 1 | TEST-01, TEST-02, TEST-03, TEST-04 | doc-sync | `grep -c "Phase 66" audit/v3.7-vrf-core-findings.md audit/v3.7-lootbox-rng-findings.md audit/v3.7-vrf-stall-findings.md` | Existing | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. No new test files needed — Phase 67 is verification and documentation only.

---

## Manual-Only Verifications

All phase behaviors have automated verification.

---

## Validation Sign-Off

- [x] All tasks have automated verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 120s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-03-22
