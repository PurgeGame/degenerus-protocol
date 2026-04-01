---
phase: 73
slug: boon-storage-packing
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-22
---

# Phase 73 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hardhat (Mocha/Chai) + Foundry (forge test) |
| **Config file** | `hardhat.config.js` / `foundry.toml` |
| **Quick run command** | `npx hardhat test --grep "boon\|Boon\|lootbox boost"` |
| **Full suite command** | `npx hardhat test && forge test` |
| **Estimated runtime** | ~120 seconds |

---

## Sampling Rate

- **After every task commit:** Run `npx hardhat test --grep "boon\|Boon\|lootbox boost"`
- **After every plan wave:** Run `npx hardhat test && forge test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 73-01-01 | 01 | 1 | BOON-01 | unit | `npx hardhat test` | existing | pending |
| 73-01-02 | 01 | 1 | BOON-02 | unit | `npx hardhat test --grep "checkAndClear"` | existing | pending |
| 73-01-03 | 01 | 1 | BOON-03 | unit | `npx hardhat test --grep "applyBoon"` | existing | pending |
| 73-02-01 | 02 | 1 | BOON-04 | unit | `npx hardhat test --grep "consume"` | existing | pending |
| 73-02-02 | 02 | 1 | BOON-05 | unit | `npx hardhat test --grep "lootbox"` | existing | pending |
| 73-03-01 | 03 | 2 | BOON-06 | integration | `npx hardhat test && forge test` | existing | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. Both Hardhat and Foundry test suites already exercise boon functionality.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Storage slot layout | BOON-01 | Requires forge inspect | Run `forge inspect DegenerusGameStorage storage --pretty` and verify BoonPacked mapping slot |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
