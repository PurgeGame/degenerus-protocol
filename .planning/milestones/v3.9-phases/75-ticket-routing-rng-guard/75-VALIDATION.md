---
phase: 75
slug: ticket-routing-rng-guard
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-22
---

# Phase 75 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (forge 1.5.1-stable) + Hardhat 2.28.6 |
| **Config file** | foundry.toml (Foundry), hardhat.config.js (Hardhat) |
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
| 75-01-01 | 01 | 0 | ROUTE-01, ROUTE-02, ROUTE-03, RNG-02 | unit | `forge test --match-contract TicketRoutingTest -vv` | Wave 0 | pending |
| 75-01-02 | 01 | 1 | ROUTE-01 | compilation | `npx hardhat compile` | N/A | pending |
| 75-01-03 | 01 | 1 | ROUTE-02 | compilation | `npx hardhat compile` | N/A | pending |
| 75-01-04 | 01 | 1 | ROUTE-03, RNG-02 | unit | `forge test --match-test testRngGuard -vv` | Wave 0 | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [ ] `test/fuzz/TicketRouting.t.sol` — Foundry test harness exposing `_queueTickets`, `_queueTicketsScaled`, `_queueTicketRange` internals with controllable `level`, `rngLockedFlag`, `phaseTransitionActive` state
- [ ] Test: far-future ticket (targetLevel > level+6) routes to FF key
- [ ] Test: near-future ticket (targetLevel <= level+6) routes to write key
- [ ] Test: rngLocked + FF key = revert
- [ ] Test: rngLocked + FF key + phaseTransitionActive = success (exemption)
- [ ] Test: near-future tickets unaffected by rngLocked
- [ ] Test: _queueTicketRange splits range correctly (near vs far-future levels)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Constructor pre-queue routing | ROUTE-01 | Constructor context has rngLockedFlag=false; verified by code inspection | Inspect DegenerusGame.sol constructor: levels 1-100 queued at level=0, all > 0+6 so route to FF key. rngLockedFlag default false, guard never triggers. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
