---
phase: 80
slug: test-suite
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-22
---

# Phase 80 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (forge) 1.5.1 + forge-std |
| **Config file** | foundry.toml (root) |
| **Quick run command** | `forge test --match-contract "TicketRouting\|TicketProcessingFF\|JackpotCombinedPool\|FarFutureIntegration\|TicketEdgeCases\|TqFarFutureKey" -vvv` |
| **Full suite command** | `forge test -vvv` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick run command (match Phase 80 test contracts)
- **After every plan wave:** Run full suite command
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 80-01-01 | 01 | 1 | TEST-01 | unit | `forge test --match-contract TicketRoutingTest -vvv` | Exists | pending |
| 80-01-02 | 01 | 1 | TEST-02 | unit | `forge test --match-contract TicketProcessingFFTest -vvv` | Exists | pending |
| 80-01-03 | 01 | 1 | TEST-03 | unit | `forge test --match-contract JackpotCombinedPoolTest -vvv` | Exists | pending |
| 80-01-04 | 01 | 1 | TEST-04 | unit | `forge test --match-test testRngGuard -vvv` | Exists | pending |
| 80-02-01 | 02 | 1 | TEST-05 | integration | `forge test --match-contract FarFutureIntegration -vvv` | Does NOT exist | pending |

---

## Wave 0 Requirements

- [ ] `test/fuzz/FarFutureIntegration.t.sol` — integration test for TEST-05 (multi-level lifecycle)
- [ ] Verify existing tests (TEST-01 through TEST-04) pass on current codebase

*Existing test files cover TEST-01 through TEST-04. Only TEST-05 requires new file creation.*

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
