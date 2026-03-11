---
phase: 03
slug: prize-pool-freeze
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-11
---

# Phase 03 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (forge-std Test.sol) |
| **Config file** | `foundry.toml` |
| **Quick run command** | `forge test --match-path "test/fuzz/PrizePoolFreeze.t.sol" -vvv` |
| **Full suite command** | `forge test` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `forge test --match-path "test/fuzz/PrizePoolFreeze.t.sol" -vvv`
- **After every plan wave:** Run `forge test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 03-01-01 | 01 | 1 | FREEZE-02, FREEZE-04 | unit | `forge test --match-path "test/fuzz/PrizePoolFreeze.t.sol" -vvv` | No -- Wave 0 | ⬜ pending |
| 03-02-01 | 02 | 1 | FREEZE-02 | unit | `forge test --match-path "test/fuzz/PrizePoolFreeze.t.sol" --match-test "Frozen\|Unfrozen" -vvv` | ⬜ depends W0 | ⬜ pending |
| 03-02-02 | 02 | 1 | FREEZE-01 | grep | `grep -rn '_swapAndFreeze' contracts/modules/` (expect 1 call site) | N/A | ⬜ pending |
| 03-02-03 | 02 | 1 | FREEZE-03 | grep | `grep -n 'prizePoolFrozen = false' contracts/` (expect 0 direct assignments) | N/A | ⬜ pending |
| 03-02-04 | 02 | 1 | FREEZE-04 | unit | `forge test --match-path "test/fuzz/PrizePoolFreeze.t.sol" --match-test "Persist" -vvv` | ⬜ depends W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/fuzz/PrizePoolFreeze.t.sol` — FreezeHarness + freeze lifecycle tests for FREEZE-02 and FREEZE-04

*Existing `test/fuzz/StorageFoundation.t.sol` StorageHarness already exposes `_swapAndFreeze`, `_unfreezePool`, `prizePoolFrozen`. Extend or reuse.*

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
