---
phase: 96
slug: gas-ceiling-optimization
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-24
---

# Phase 96 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (forge) 1.5.1-stable, Solidity 0.8.34, via_ir=true, optimizer_runs=2 |
| **Config file** | foundry.toml |
| **Quick run command** | `npx hardhat test test/gas/AdvanceGameGas.test.js` |
| **Full suite command** | `forge test -vv && npx hardhat test` |
| **Estimated runtime** | ~120 seconds |

---

## Sampling Rate

- **After every task commit:** Run `forge test -vv` (if code changes)
- **After every plan wave:** Run full Hardhat + Foundry suite
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 96-01-01 | 01 | 1 | CEIL-01 | empirical | `npx hardhat test test/gas/AdvanceGameGas.test.js` | Yes | ⬜ pending |
| 96-01-02 | 01 | 1 | CEIL-02 | empirical | `npx hardhat test test/gas/AdvanceGameGas.test.js` | Yes | ⬜ pending |
| 96-01-03 | 01 | 1 | CEIL-03 | analysis | N/A (analysis output) | N/A | ⬜ pending |
| 96-02-01 | 02 | 1 | GOPT-01 | manual review | N/A (audit document) | N/A | ⬜ pending |
| 96-02-02 | 02 | 1 | GOPT-02 | manual review | N/A (audit document) | N/A | ⬜ pending |
| 96-02-03 | 02 | 2 | GOPT-03 | code + regression | `forge test -vv && npx hardhat test` | Depends | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements:
- `test/gas/AdvanceGameGas.test.js` — Hardhat gas measurement harness (existing)
- Foundry test suite — regression coverage (existing)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| SLOAD identification | GOPT-01 | Requires reading compiled bytecode / source analysis | Trace all storage reads in daily jackpot path, document each |
| Loop hoisting audit | GOPT-02 | Requires human judgment on code structure | Identify invariant expressions inside loops |
| 14M ceiling verdict | CEIL-03 | Aggregation of empirical data | Compare all measurements against 14M threshold |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
