---
phase: 77
slug: jackpot-combined-pool-tq-01-fix
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-22
---

# Phase 77 — Validation Strategy

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
- **After every plan wave:** Run `forge test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 77-01-01 | 01 | 1 | JACK-01, JACK-02, EDGE-03 | unit | `forge test --match-contract JackpotCombinedPoolTest -vv` | ❌ W0 | ⬜ pending |
| 77-01-02 | 01 | 1 | JACK-01, JACK-02, EDGE-03 | unit | `forge test --match-contract JackpotCombinedPoolTest -vv` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/fuzz/JackpotCombinedPool.t.sol` — harness replicating combined pool selection logic with controllable ticketQueue state
- [ ] Tests: combined pool reads both queues (JACK-01), winner index routing (JACK-02), no _tqWriteKey usage (EDGE-03)
- [ ] Boundary tests: readLen=0, ffLen=0, both=0, winner at boundary index

*Existing Foundry infrastructure covers all framework requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| _tqWriteKey not present in _awardFarFutureCoinJackpot | EDGE-03 | Bytecode/source check | `grep _tqWriteKey contracts/modules/DegenerusGameJackpotModule.sol` should NOT match within _awardFarFutureCoinJackpot |

---

## Regression Scope

| Existing Test | Command | Why It Matters |
|---------------|---------|----------------|
| TicketRoutingTest | `forge test --match-contract TicketRoutingTest -vv` | Phase 75 routing unchanged |
| TicketProcessingFFTest | `forge test --match-contract TicketProcessingFFTest -vv` | Phase 76 processing unchanged |
| Full Foundry suite | `forge test` | No regression across all contracts |

---

*Phase: 77-jackpot-combined-pool-tq-01-fix*
*Validation strategy created: 2026-03-22*
