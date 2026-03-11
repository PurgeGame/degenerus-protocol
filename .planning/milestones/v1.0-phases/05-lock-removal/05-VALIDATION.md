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
| 05-01-01 | 01 | 1 | LOCK-01 | unit | `forge test --match-test test_purchaseDuringRngLock -vvv` | W0 | pending |
| 05-01-02 | 01 | 1 | LOCK-02 | unit | `forge test --match-test test_lootboxPurchaseDuringJackpot -vvv` | W0 | pending |
| 05-01-03 | 01 | 1 | LOCK-03 | unit | `forge test --match-test test_openLootBoxDuringLock -vvv` | W0 | pending |
| 05-01-04 | 01 | 1 | LOCK-04 | unit | `forge test --match-test test_openBurnieLootBoxDuringLock -vvv` | W0 | pending |
| 05-01-05 | 01 | 1 | LOCK-05 | unit | `forge test --match-test test_degeneretteDuringJackpot -vvv` | W0 | pending |
| 05-01-06 | 01 | 1 | LOCK-06 | unit | `forge test --match-test test_lootboxRngGate -vvv` | W0 | pending |

---

## Wave 0 Requirements

- [ ] `test/fuzz/LockRemoval.t.sol` — test file covering LOCK-01 through LOCK-06
- [ ] LockRemovalHarness in same file — extends DegenerusGameStorage for storage manipulation

*Existing infrastructure covers framework/fixture requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Grep zero rngLockedFlag in purchase paths | SC-2 | Shell command verification | `grep -c rngLockedFlag` in MintModule and LootboxModule — expect 0 |
| Gas snapshot SSTORE reduction | SC-4 | Requires before/after comparison | `forge snapshot` and diff against baseline |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
