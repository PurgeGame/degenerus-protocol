---
phase: 60
slug: coordinator-swap-cleanup
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-22
---

# Phase 60 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (forge) + Hardhat (ethers v6) |
| **Config file** | `foundry.toml` / `hardhat.config.cjs` |
| **Quick run command** | `forge build` |
| **Full suite command** | `forge build && npx hardhat test` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `forge build`
- **After every plan wave:** Run `forge build && npx hardhat test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 60-01-01 | 01 | 1 | SWAP-01 | audit | `forge build` | N/A | ⬜ pending |
| 60-01-02 | 01 | 1 | SWAP-01 | audit | `grep LootboxRngApplied contracts/modules/DegenerusGameAdvanceModule.sol` | N/A | ⬜ pending |
| 60-02-01 | 02 | 1 | SWAP-02 | manual-only | `grep -A5 totalFlipReversals contracts/modules/DegenerusGameAdvanceModule.sol` | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| totalFlipReversals NatSpec documents carry-over decision | SWAP-02 | Documentation task — NatSpec comment correctness | `grep -B2 -A8 "totalFlipReversals" contracts/modules/DegenerusGameAdvanceModule.sol` and verify comment explains carry-over |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
