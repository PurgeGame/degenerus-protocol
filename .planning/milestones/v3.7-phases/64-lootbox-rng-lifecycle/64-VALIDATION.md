---
phase: 64
slug: lootbox-rng-lifecycle
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-22
---

# Phase 64 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (forge) with Solidity 0.8.34 |
| **Config file** | foundry.toml |
| **Quick run command** | `forge test --match-path test/fuzz/LootboxRngLifecycle.t.sol -vvv` |
| **Full suite command** | `forge test --fuzz-runs 1000 -vvv` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `forge test --match-path test/fuzz/LootboxRngLifecycle.t.sol -vvv`
- **After every plan wave:** Run `forge test --fuzz-runs 1000 -vvv`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 64-01-01 | 01 | 1 | LBOX-01 | fuzz | `forge test --match-test test_lootboxRngIndex -vvv` | Wave 0 | pending |
| 64-01-02 | 01 | 1 | LBOX-02 | fuzz | `forge test --match-test test_lootboxWordByIndex -vvv` | Wave 0 | pending |
| 64-01-03 | 01 | 1 | LBOX-03 | unit | `forge test --match-test test_zeroStateGuard -vvv` | Wave 0 | pending |
| 64-01-04 | 01 | 1 | LBOX-04 | fuzz | `forge test --match-test test_entropyUniqueness -vvv` | Wave 0 | pending |
| 64-01-05 | 01 | 1 | LBOX-05 | integration | `forge test --match-test test_fullLifecycle -vvv` | Wave 0 | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [ ] `test/fuzz/LootboxRngLifecycle.t.sol` — new test file covering LBOX-01 through LBOX-05
- [ ] No new framework install needed (Foundry already configured)
- [ ] No new helpers needed (VRFHandler + DeployProtocol already exist)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| _getHistoricalRngFallback zero guard absence | LBOX-03 | Code review finding (2^-256 probability) | Verify line ~962 of AdvanceModule has no `if (word == 0) word = 1` guard |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
