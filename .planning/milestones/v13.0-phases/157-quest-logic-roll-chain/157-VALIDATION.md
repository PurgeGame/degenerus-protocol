---
phase: 157
slug: quest-logic-roll-chain
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-31
---

# Phase 157 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hardhat (Mocha + Chai) + Foundry (forge test) |
| **Config file** | `hardhat.config.ts` / `foundry.toml` |
| **Quick run command** | `npx hardhat compile --force` |
| **Full suite command** | `npx hardhat compile --force` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `npx hardhat compile --force`
- **After every plan wave:** Run `npx hardhat compile --force`
- **Before `/gsd:verify-work`:** Full compilation must succeed (0 errors)
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 157-01-01 | 01 | 1 | QUEST-02 | compile | `npx hardhat compile --force` | N/A | ⬜ pending |
| 157-01-02 | 01 | 1 | QUEST-03 | compile | `npx hardhat compile --force` | N/A | ⬜ pending |
| 157-01-03 | 01 | 1 | QUEST-04 | compile | `npx hardhat compile --force` | N/A | ⬜ pending |
| 157-01-04 | 01 | 1 | QUEST-06 | compile | `npx hardhat compile --force` | N/A | ⬜ pending |
| 157-01-05 | 01 | 1 | ROLL-01 | compile | `npx hardhat compile --force` | N/A | ⬜ pending |
| 157-01-06 | 01 | 1 | ROLL-02 | compile | `npx hardhat compile --force` | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. No new test framework setup needed — this phase adds Solidity functions that must compile cleanly.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Quest type distribution | QUEST-02 | Weight table correctness requires statistical analysis | Verify `_bonusQuestType` is called with `type(uint8).max` sentinel — grep confirms call pattern |
| Eligibility logic | QUEST-03 | Requires reading packed bit fields — compile-only at this phase | Verify function reads correct bit positions from spec |
| AdvanceModule insertion point | ROLL-02 | Insertion correctness requires code review | Verify call is between FF drain completion and `phaseTransitionActive = false` |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
