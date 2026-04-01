---
phase: 151
slug: endgame-flag-implementation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-31
---

# Phase 151 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (forge) with Solidity 0.8.34 |
| **Config file** | `foundry.toml` |
| **Quick run command** | `forge test --match-contract EndgameFlag -vv` |
| **Full suite command** | `forge test -vv` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `forge test --match-contract EndgameFlag -vv`
- **After every plan wave:** Run `forge test -vv`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 151-01-01 | 01 | 1 | REM-01 | unit | `forge test --match-test testNoBanConstants -vv` | Wave 0 | ⬜ pending |
| 151-01-02 | 01 | 1 | FLAG-01 | unit | `forge test --match-test testEndgameFlagSet -vv` | Wave 0 | ⬜ pending |
| 151-01-03 | 01 | 1 | FLAG-02 | unit | `forge test --match-test testEndgameFlagClears -vv` | Wave 0 | ⬜ pending |
| 151-01-04 | 01 | 1 | FLAG-03 | unit | `forge test --match-test testFlagClearsAtLastPurchaseDay -vv` | Wave 0 | ⬜ pending |
| 151-01-05 | 01 | 1 | FLAG-04 | unit | `forge test --match-test testNoFlagBelowL10 -vv` | Wave 0 | ⬜ pending |
| 151-01-06 | 01 | 1 | DRIP-01 | unit | `forge test --match-test testDripProjection -vv` | Wave 0 | ⬜ pending |
| 151-01-07 | 01 | 1 | DRIP-02 | unit | `forge test --match-test testDeficitComparison -vv` | Wave 0 | ⬜ pending |
| 151-01-08 | 01 | 1 | ENF-01 | unit | `forge test --match-test testBurnieRevertWhenFlagged -vv` | Wave 0 | ⬜ pending |
| 151-01-09 | 01 | 1 | ENF-02 | unit | `forge test --match-test testBurnieLootboxRedirect -vv` | Wave 0 | ⬜ pending |
| 151-01-10 | 01 | 1 | ENF-03 | unit | `forge test --match-test testEthUnaffected -vv` | Wave 0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/unit/EndgameFlag.t.sol` — stubs for all 10 requirements (REM-01, FLAG-01-04, DRIP-01-02, ENF-01-03)
- [ ] Test harness helper to fast-forward game to L10+ purchase phase

*Existing infrastructure (Foundry + full protocol deployment) covers framework needs.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| No other "30 days" references related to BURNIE ban | REM-01 | Code audit / grep | `grep -rn "30 days\|30days\|CUTOFF" contracts/ --include="*.sol"` — verify only GameOverModule final sweep remains |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
