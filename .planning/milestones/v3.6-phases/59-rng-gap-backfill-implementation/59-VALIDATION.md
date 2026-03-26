---
phase: 59
slug: rng-gap-backfill-implementation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-22
---

# Phase 59 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (forge test) |
| **Config file** | foundry.toml |
| **Quick run command** | `forge test --match-contract RngGapBackfill -vvv` |
| **Full suite command** | `forge test -vvv` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `forge test --match-contract RngGapBackfill -vvv`
- **After every plan wave:** Run `forge test -vvv`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 59-01-01 | 01 | 1 | GAP-01 | unit | `forge test --match-test testBackfillRngWordByDay -vvv` | ❌ W0 | ⬜ pending |
| 59-01-02 | 01 | 1 | GAP-02 | unit | `forge test --match-test testBackfillLootboxRng -vvv` | ❌ W0 | ⬜ pending |
| 59-01-03 | 01 | 1 | GAP-03 | unit | `forge test --match-test testMidDayTicketRngPending -vvv` | ❌ W0 | ⬜ pending |
| 59-01-04 | 01 | 1 | GAP-04 | integration | `forge test --match-test testCoinflipClaimGapDay -vvv` | ❌ W0 | ⬜ pending |
| 59-01-05 | 01 | 1 | GAP-05 | integration | `forge test --match-test testLootboxOpenOrphanedIndex -vvv` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/RngGapBackfill.t.sol` — test stubs for GAP-01 through GAP-05
- [ ] Foundry test fixtures for simulating VRF stall and gap day scenarios

*Existing Foundry infrastructure covers framework requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Gas ceiling compliance with max realistic gap | GAP-01 | Gas profiling needed | Run `forge test --gas-report --match-test testBackfillGas` and verify < 14M |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
