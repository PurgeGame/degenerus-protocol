---
phase: 42
slug: governance-fresh-eyes
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-19
---

# Phase 42 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hardhat (JS tests) + Foundry (Solidity fuzz/invariant) |
| **Config file** | `hardhat.config.js` + `foundry.toml` |
| **Quick run command** | `npx hardhat test test/unit/DegenerusGame.test.js` |
| **Full suite command** | `npm test` |
| **Estimated runtime** | ~120 seconds |

---

## Sampling Rate

- **After every task commit:** Verify audit document covers all required attack surfaces
- **After every plan wave:** Cross-reference findings against all 3 requirement IDs (GOV-01, GOV-02, GOV-03)
- **Before `/gsd:verify-work`:** All GOV-01 through GOV-03 have explicit verdicts, WAR-01/02/06 re-verified
- **Max feedback latency:** N/A (manual audit phase)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 42-01-01 | 01 | 1 | GOV-01 | manual-only | N/A -- attack surface catalogue | N/A | pending |
| 42-01-02 | 01 | 1 | GOV-02 | manual-only | N/A -- timing attack analysis | N/A | pending |
| 42-02-01 | 02 | 1 | GOV-03 | manual-only | N/A -- cross-contract state consistency | N/A | pending |

*Status: pending*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. This is a security audit producing written findings, not code changes.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Attack surface catalogue for VRF swap governance | GOV-01 | Security audit producing written analysis, not runtime test | Verify all propose/vote/execute/kill/expire paths covered with attack scenarios |
| Timing attack scenarios against current code | GOV-02 | Code trace audit with post-v2.1 change analysis | Verify threshold decay, stall timing, and proposal expiry edge cases evaluated |
| Cross-contract governance interactions | GOV-03 | State consistency trace across 5 contracts | Verify updateVrfCoordinatorAndSub state reset, unwrapTo guard, circulatingSupply accounting |

---

## Validation Sign-Off

- [ ] All tasks have manual verification criteria
- [ ] WAR-01, WAR-02, WAR-06 re-verified against current code
- [ ] GOV-07, VOTE-03 fixes confirmed still in place
- [ ] No watch-mode flags
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
