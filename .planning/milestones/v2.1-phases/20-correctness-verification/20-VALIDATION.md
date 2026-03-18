---
phase: 20
slug: correctness-verification
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-16
---

# Phase 20 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hardhat (Mocha/Chai) + Foundry (Forge) |
| **Config file** | hardhat.config.js + foundry.toml |
| **Quick run command** | `npx hardhat test test/unit/DegenerusStonk.test.js test/unit/DGNRSLiquid.test.js` |
| **Full suite command** | `npm test` |
| **Estimated runtime** | ~30 seconds (focused), ~120 seconds (full) |

---

## Sampling Rate

- **After every task commit:** Run `npx hardhat test test/unit/DegenerusStonk.test.js test/unit/DGNRSLiquid.test.js`
- **After every plan wave:** Run `npm test`
- **Before `/gsd:verify-work`:** Full suite must be green + `forge build --force` clean
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 20-01-01 | 01 | 1 | CORR-01 | manual + grep | `grep -n '@notice\|@dev\|@param\|@return' contracts/DegenerusStonk.sol` | N/A | ⬜ pending |
| 20-01-02 | 01 | 1 | CORR-01 | manual | visual review | N/A | ⬜ pending |
| 20-02-01 | 02 | 1 | CORR-02 | grep | `grep -rn 'IDegenerusStonk\|burnForGame' audit/` | N/A | ⬜ pending |
| 20-02-02 | 02 | 1 | CORR-02 | manual | visual review of line numbers | N/A | ⬜ pending |
| 20-03-01 | 03 | 2 | CORR-03 | unit | `npx hardhat test test/unit/DGNRSLiquid.test.js test/unit/DegenerusStonk.test.js` | ✅ | ⬜ pending |
| 20-03-02 | 03 | 2 | CORR-04 | compile | `forge build --force` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. CORR-01 and CORR-02 are documentation verification tasks (manual review + grep). CORR-03 and CORR-04 use existing test infrastructure. Any new tests extend existing files.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| NatDoc matches implementation | CORR-01 | NatDoc is a documentation convention, not runtime behavior | Read each function's NatDoc, compare against actual code logic |
| Audit docs match current code | CORR-02 | Docs are prose, not executable | Grep for stale patterns, visually verify corrections |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
