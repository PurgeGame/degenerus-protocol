---
phase: 24
slug: core-governance-security-audit
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-17
---

# Phase 24 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hardhat + Mocha + Chai (project-installed) |
| **Config file** | hardhat.config.js |
| **Quick run command** | `npx hardhat test test/unit/VRFGovernance.test.js test/unit/DegenerusAdmin.test.js test/unit/GovernanceGating.test.js` |
| **Full suite command** | `npx hardhat test` |
| **Estimated runtime** | ~45 seconds |

---

## Sampling Rate

- **After every task commit:** Run `npx hardhat test test/unit/VRFGovernance.test.js test/unit/DegenerusAdmin.test.js test/unit/GovernanceGating.test.js`
- **After every plan wave:** Run `npx hardhat test test/unit/ test/access/ test/edge/RngStall.test.js test/poc/NationState.test.js test/poc/Coercion.test.js`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 24-01-01 | 01 | 1 | GOV-01 | manual | `npx hardhat compile` (inspect storageLayout JSON) | N/A | ⬜ pending |
| 24-02-01 | 02 | 2 | GOV-02 | unit | `npx hardhat test test/unit/VRFGovernance.test.js` | ✅ | ⬜ pending |
| 24-02-02 | 02 | 2 | GOV-03 | unit | `npx hardhat test test/unit/VRFGovernance.test.js` | Partial | ⬜ pending |
| 24-02-03 | 02 | 2 | GOV-04 | unit | `npx hardhat test test/unit/VRFGovernance.test.js` | ✅ | ⬜ pending |
| 24-02-04 | 02 | 2 | GOV-05 | unit | `npx hardhat test test/unit/VRFGovernance.test.js` | Partial | ⬜ pending |
| 24-02-05 | 02 | 2 | GOV-06 | unit | N/A | ❌ W0 | ⬜ pending |
| 24-02-06 | 02 | 2 | GOV-07 | unit+manual | N/A | ❌ W0 | ⬜ pending |
| 24-02-07 | 02 | 2 | GOV-08 | unit | N/A | ❌ W0 | ⬜ pending |
| 24-02-08 | 02 | 2 | GOV-09 | unit | `npx hardhat test test/unit/VRFGovernance.test.js` | ✅ | ⬜ pending |
| 24-02-09 | 02 | 2 | GOV-10 | unit | `npx hardhat test test/unit/VRFGovernance.test.js` | ✅ | ⬜ pending |
| 24-03-01 | 03 | 2 | VOTE-01 | manual+unit | Code trace + test | Partial | ⬜ pending |
| 24-03-02 | 03 | 2 | VOTE-02 | manual | Code trace | N/A | ⬜ pending |
| 24-03-03 | 03 | 2 | VOTE-03 | manual | Arithmetic analysis | N/A | ⬜ pending |
| 24-04-01 | 04 | 3 | XCON-01 | manual | Code trace | N/A | ⬜ pending |
| 24-04-02 | 04 | 3 | XCON-02 | unit+manual | `npx hardhat test test/unit/VRFGovernance.test.js` | Partial | ⬜ pending |
| 24-04-03 | 04 | 3 | XCON-03 | unit | `npx hardhat test test/unit/VRFGovernance.test.js` | ✅ | ⬜ pending |
| 24-04-04 | 04 | 3 | XCON-04 | manual | Code trace | N/A | ⬜ pending |
| 24-04-05 | 04 | 3 | XCON-05 | unit | `npx hardhat test test/edge/RngStall.test.js` | ✅ | ⬜ pending |
| 24-05-01 | 05 | 4 | WAR-01..WAR-06 | manual+POC | Written assessments | ❌ | ⬜ pending |
| 24-06-01 | 06 | 5 | M02-01 | manual | Cross-reference analysis | N/A | ⬜ pending |
| 24-06-02 | 06 | 5 | M02-02 | manual | Written analysis | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Vote execution test (GOV-05, GOV-06, GOV-07) — no execution path tests exist
- [ ] Kill condition test (GOV-06) — untested
- [ ] `_voidAllActive` with multiple proposals test (GOV-08) — untested
- [ ] VOTE-01 dedicated test (sDGNRS frozen proof) — no dedicated test

*Note: This phase is primarily audit/analysis. Missing tests will be added as evidence for verdicts. WAR-* and M02-* requirements are manual-only verdict documents.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Storage layout slot computation | GOV-01 | Requires compiler JSON inspection | Run `npx hardhat compile`, inspect build-info storageLayout for DegenerusGameStorage |
| `lastVrfProcessedTimestamp` write paths | XCON-01 | Code trace across 3 contracts | Grep for all reads/writes, verify exhaustive |
| `_threeDayRngGap` removal | XCON-04 | Code trace verification | Grep for `_threeDayRngGap` in governance paths, verify absent |
| `circulatingSnapshot` immutability | VOTE-02 | Structural code analysis | Verify no SSTORE to `circulatingSnapshot` after `propose()` |
| uint8 overflow analysis | VOTE-03 | Arithmetic analysis | Compute max values, gas costs, exploitability |
| War-game scenarios | WAR-01..WAR-06 | Scenario-based reasoning | Written assessments with exploit feasibility |
| M-02 closure | M02-01, M02-02 | Cross-reference with original finding | Compare old vs new attack surface |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
