---
phase: 3
slug: prize-pool-freeze
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-11
---

# Phase 3 — Validation Strategy

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
| 03-01-01 | 01 | 1 | FREEZE-01 | unit + grep | `grep -rn '_swapAndFreeze' contracts/modules/ \| wc -l` | ❌ W0 | ⬜ pending |
| 03-01-02 | 01 | 1 | FREEZE-02 | unit | `forge test --match-path "test/fuzz/PrizePoolFreeze.t.sol" --match-test "testFrozen" -vvv` | ❌ W0 | ⬜ pending |
| 03-01-03 | 01 | 1 | FREEZE-03 | grep + unit | `grep -n 'prizePoolFrozen = false' contracts/` | ❌ W0 | ⬜ pending |
| 03-01-04 | 01 | 1 | FREEZE-04 | integration | `forge test --match-path "test/fuzz/PrizePoolFreeze.t.sol" --match-test "testJackpotPersistence" -vvv` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/fuzz/PrizePoolFreeze.t.sol` — FreezeHarness + freeze lifecycle tests for FREEZE-01 through FREEZE-04
- [ ] Extend existing QueueHarness if freeze-related internals needed

*Existing infrastructure covers build tooling. Only test file creation needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| _swapAndFreeze call site count | FREEZE-01 | Grep verification | `grep -rn '_swapAndFreeze' contracts/modules/` — expect exactly 1 call site |
| No direct prizePoolFrozen = false | FREEZE-03 | Grep verification | `grep -n 'prizePoolFrozen = false' contracts/` — expect 1 result in _unfreezePool only |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
