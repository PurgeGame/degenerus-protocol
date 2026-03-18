---
phase: 23
slug: gas-optimization-dead-code-removal
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-17
---

# Phase 23 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hardhat (Mocha/Chai) + Foundry (forge) |
| **Config file** | hardhat.config.js, foundry.toml |
| **Quick run command** | `npx hardhat test --grep "DGNRS\|Stonk"` |
| **Full suite command** | `npx hardhat test` |
| **Estimated runtime** | ~90 seconds |

---

## Sampling Rate

- **After every task commit:** Run `npx hardhat test --grep "DGNRS\|Stonk"`
- **After every plan wave:** Run `npx hardhat test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 90 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 23-01-01 | 01 | 1 | GAS-01,02,03,04 | analysis | `/gas-audit` skill invocation | N/A | ⬜ pending |
| 23-01-02 | 01 | 1 | GAS-01,02,03,04 | validation | `/gas-skeptic` review of candidates | N/A | ⬜ pending |
| 23-02-01 | 02 | 2 | GAS-01,02,03 | regression | `npx hardhat test` | ✅ | ⬜ pending |
| 23-02-02 | 02 | 2 | ALL | compilation | `npx hardhat compile` + `forge build` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. Hardhat and Foundry test suites already exist and cover all contract functionality. No new test framework or stubs needed for the analysis phase.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Storage slot layout preserved | GAS-02 | delegatecall slot corruption risk | Verify no storage variable reordering in DegenerusGameStorage.sol |
| Bytecode size check | GAS-03 | Size limit proximity | `forge build --sizes` to verify JackpotModule < 24,576 bytes |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 90s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
