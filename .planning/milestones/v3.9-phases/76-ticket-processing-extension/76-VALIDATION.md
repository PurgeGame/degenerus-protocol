---
phase: 76
slug: ticket-processing-extension
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-22
---

# Phase 76 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (forge) + Hardhat |
| **Config file** | foundry.toml, hardhat.config.js |
| **Quick run command** | `npx hardhat compile` |
| **Full suite command** | `forge test && npx hardhat test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `npx hardhat compile`
- **After every plan wave:** Run `forge test && npx hardhat test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 76-01-01 | 01 | 1 | PROC-01, PROC-02, PROC-03 | unit | `forge test --match-test testProcessFutureTicketBatch -vv` | Wave 0 | pending |
| 76-01-02 | 01 | 1 | PROC-01 | unit | `forge test --match-test testDrainsFFAfterReadSide -vv` | Wave 0 | pending |
| 76-01-03 | 01 | 1 | PROC-02 | unit | `forge test --match-test testTicketLevelFFEncoding -vv` | Wave 0 | pending |
| 76-01-04 | 01 | 1 | PROC-03 | unit | `forge test --match-test testFinishedRequiresBothQueues -vv` | Wave 0 | pending |
| 76-01-05 | 01 | 1 | PROC-02 | unit | `forge test --match-test testPrepareFutureTicketsResumeFF -vv` | Wave 0 | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [ ] Foundry test harness exposing `processFutureTicketBatch` with controllable `ticketQueue`, `ticketLevel`, `ticketCursor`, `ticketWriteSlot`, `rngWordCurrent` state
- [ ] Test stubs for PROC-01, PROC-02, PROC-03

*Note: Comprehensive integration tests are deferred to Phase 80 (TEST-02, TEST-05). Phase 76 tests focus on dual-queue draining logic and cursor state encoding.*

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
