---
phase: 95
slug: delta-verification
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-24
---

# Phase 95 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hardhat (Mocha/Chai) + Foundry (forge test) |
| **Config files** | `hardhat.config.ts`, `foundry.toml` |
| **Quick run command** | `forge test --summary` |
| **Full suite command** | `npx hardhat test && forge test` |
| **Estimated runtime** | ~120 seconds (Hardhat ~60s, Foundry ~60s) |

---

## Sampling Rate

- **After every task commit:** Run `forge test --match-contract <affected> --summary`
- **After every plan wave:** Run `npx hardhat test && forge test`
- **Before `/gsd:verify-work`:** Full suite must be green (minus documented pre-existing failures)
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 95-01-01 | 01 | 1 | DELTA-01 | full suite | `npx hardhat test` | ✅ | ⬜ pending |
| 95-01-02 | 01 | 1 | DELTA-02 | grep sweep | `grep -r 'dailyEthBucketCursor\|dailyEthWinnerCursor\|_skipEntropyToBucket\|_winnerUnits\|DAILY_JACKPOT_UNITS_SAFE\|DAILY_JACKPOT_UNITS_AUTOREBUY' contracts/` | ✅ | ⬜ pending |
| 95-02-01 | 02 | 1 | DELTA-04 | foundry suite | `forge test --summary` | ✅ (needs fixes) | ⬜ pending |
| 95-03-01 | 03 | 2 | DELTA-03 | manual trace | N/A (documentation deliverable) | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Fix 14 Foundry test files with stale slot offset constants (DELTA-04)
- [ ] Write behavioral equivalence trace document (DELTA-03)

*Existing Hardhat and Foundry test infrastructure covers DELTA-01, DELTA-02, and DELTA-04.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Behavioral equivalence trace | DELTA-03 | Requires human-readable proof document showing entropy chain, winner selection, and payout amount equivalence | Review 95-BEHAVIORAL-TRACE.md for logical completeness |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
