---
phase: 19
slug: delta-security-audit
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-16
---

# Phase 19 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hardhat (Mocha/Chai) + Foundry (Forge) |
| **Config file** | hardhat.config.js + foundry.toml |
| **Quick run command** | `npx hardhat test test/unit/DegenerusStonk.test.js test/unit/DGNRSLiquid.test.js` |
| **Full suite command** | `npm test` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `npx hardhat test test/unit/DegenerusStonk.test.js test/unit/DGNRSLiquid.test.js`
- **After every plan wave:** Run `npm test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 19-01-01 | 01 | 1 | DELTA-01 | manual audit | `npx hardhat test test/unit/DegenerusStonk.test.js` | ✅ | ⬜ pending |
| 19-01-02 | 01 | 1 | DELTA-02 | manual audit | `npx hardhat test test/unit/DGNRSLiquid.test.js` | ✅ | ⬜ pending |
| 19-01-03 | 01 | 1 | DELTA-03 | manual audit | manual-only: analytical proof | N/A | ⬜ pending |
| 19-02-01 | 02 | 1 | DELTA-04 | manual audit | `npm test` | ✅ | ⬜ pending |
| 19-02-02 | 02 | 1 | DELTA-05 | manual audit | `npx hardhat test test/unit/BurnieCoinflip.test.js` | ✅ | ⬜ pending |
| 19-02-03 | 02 | 1 | DELTA-06 | manual audit | `npx hardhat test test/edge/GameOver.test.js` | Partial | ⬜ pending |
| 19-02-04 | 02 | 1 | DELTA-07 | manual audit | manual-only: visual inspection | N/A | ⬜ pending |
| 19-02-05 | 02 | 1 | DELTA-08 | manual audit | `npm test` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. This is an audit phase that produces findings reports, not new code. The existing 201 Hardhat tests and Foundry fuzz tests provide the regression baseline.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Supply invariant proof | DELTA-03 | Analytical reasoning over code paths, not runtime testable | Trace every mint/burn/transfer path proving sDGNRS.balanceOf[DGNRS] >= DGNRS.totalSupply |
| Earlybird comment mismatch | DELTA-07 | Visual code inspection | Verify DegenerusGameStorage.sol:1086 comment vs code at line 1098 |
| Reentrancy path analysis | DELTA-01 | Requires tracing external call chains | Map all external calls in sDGNRS.burn() and verify CEI pattern |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
