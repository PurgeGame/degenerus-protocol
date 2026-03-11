---
phase: 2
slug: queue-double-buffer
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-11
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry forge-std (Test.sol), Solidity 0.8.34, via_ir=true |
| **Config file** | `foundry.toml` |
| **Quick run command** | `forge test --match-path "test/fuzz/QueueDoubleBuffer.t.sol" -vvv` |
| **Full suite command** | `forge test` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `forge clean && forge build`
- **After every plan wave:** Run `forge test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 02-01-01 | 01 | 1 | QUEUE-01 | unit | `forge test --match-test "testQueueTicketsUsesWriteKey" -vvv` | No - Wave 0 | pending |
| 02-01-02 | 01 | 1 | QUEUE-01 | unit | `forge test --match-test "testQueueTicketsScaledUsesWriteKey" -vvv` | No - Wave 0 | pending |
| 02-01-03 | 01 | 1 | QUEUE-01 | unit | `forge test --match-test "testQueueTicketRangeUsesWriteKey" -vvv` | No - Wave 0 | pending |
| 02-01-04 | 01 | 1 | QUEUE-01 | smoke | `grep -c 'ticketQueue\[targetLevel\]\|ticketQueue\[lvl\]' contracts/storage/DegenerusGameStorage.sol` returns 0 | N/A (CLI) | pending |
| 02-01-05 | 01 | 1 | QUEUE-02 | unit | `forge test --match-test "testProcessTicketBatchUsesReadKey" -vvv` | No - Wave 0 | pending |
| 02-01-06 | 01 | 1 | QUEUE-02 | unit | `forge test --match-test "testProcessFutureTicketBatchUsesReadKey" -vvv` | No - Wave 0 | pending |
| 02-01-07 | 01 | 1 | QUEUE-02 | smoke | grep check on JackpotModule + MintModule | N/A (CLI) | pending |
| 02-01-08 | 01 | 1 | QUEUE-03 | unit | `forge test --match-test "testSwapTicketSlotRevertsNonEmpty" -vvv` | YES - Phase 1 | pending |
| 02-02-01 | 02 | 1 | QUEUE-04 | unit | `forge test --match-test "testMidDaySwapAtThreshold" -vvv` | No - Wave 0 | pending |
| 02-02-02 | 02 | 1 | QUEUE-04 | unit | `forge test --match-test "testMidDaySwapJackpotPhase" -vvv` | No - Wave 0 | pending |
| 02-02-03 | 02 | 1 | QUEUE-04 | unit | `forge test --match-test "testMidDayRevertsNotTimeYet" -vvv` | No - Wave 0 | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [ ] `test/fuzz/QueueDoubleBuffer.t.sol` -- new test file covering QUEUE-01 through QUEUE-04
- [ ] Test harness extending StorageHarness to expose queue helpers with key verification
- [ ] For QUEUE-04 mid-day tests: harness that can simulate advanceGame state (day, dailyIdx, jackpotPhaseFlag)

*Existing infrastructure covers QUEUE-03 (Phase 1 test already exists).*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| grep verification: no direct mapping key in write functions | QUEUE-01 | CLI grep check | `grep -c 'ticketQueue\[targetLevel\]' contracts/storage/DegenerusGameStorage.sol` returns 0 |
| grep verification: no direct mapping key in processing | QUEUE-02 | CLI grep check | `grep -c 'ticketQueue\[lvl\]' contracts/modules/DegenerusGameJackpotModule.sol contracts/modules/DegenerusGameMintModule.sol` returns 0 |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
