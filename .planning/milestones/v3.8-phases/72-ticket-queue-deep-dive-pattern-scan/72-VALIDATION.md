---
phase: 72
slug: ticket-queue-deep-dive-pattern-scan
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-22
---

# Phase 72 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hardhat (Mocha/Chai) + Foundry (forge test) |
| **Config file** | `hardhat.config.js` / `foundry.toml` |
| **Quick run command** | `npx hardhat test --grep "ticket\|queue\|jackpot"` |
| **Full suite command** | `npx hardhat test && forge test` |
| **Estimated runtime** | ~120 seconds |

---

## Sampling Rate

- **After every task commit:** Run `npx hardhat test --grep "ticket\|queue\|jackpot"`
- **After every plan wave:** Run `npx hardhat test && forge test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 72-01-01 | 01 | 1 | TQ-01 | manual | Contract line inspection | N/A | pending |
| 72-01-02 | 01 | 1 | TQ-02 | manual | Contract line inspection | N/A | pending |
| 72-02-01 | 02 | 2 | TQ-03 | manual | Contract + grep scan | N/A | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. This is an audit-documentation phase — no new test files needed.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Ticket queue write-vs-read buffer exploitation | TQ-01 | Requires contract source analysis, not runtime test | Verify _tqWriteKey vs _tqReadKey usage at JackpotModule:2544 |
| Fix verification for buffer read | TQ-02 | Requires contract source inspection | Verify fix addresses correct buffer key or proves unnecessary |
| Pattern scan across all contracts | TQ-03 | Requires exhaustive grep + analysis | Verify all VRF-dependent state reads cross-referenced with permissionless writers |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
