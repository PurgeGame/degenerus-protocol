---
phase: 26
slug: gameover-path-audit
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-17
---

# Phase 26 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hardhat + Chai (JavaScript) |
| **Config file** | hardhat.config.ts |
| **Quick run command** | `npx hardhat test test/edge/GameOver.test.js` |
| **Full suite command** | `npm test` |
| **Estimated runtime** | ~30 seconds (edge test only) |

---

## Sampling Rate

- **After every task commit:** Verify audit findings have file:line references and PASS/FINDING verdicts
- **After every plan wave:** Cross-check claimablePool trace for consistency across all GO-xx findings
- **Before `/gsd:verify-work`:** All 9 requirements (GO-01 through GO-09) have explicit verdicts
- **Max feedback latency:** N/A (audit deliverables, not automated tests)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 26-01-01 | 01 | 1 | GO-08 | manual audit | grep for "GO-08" verdict in audit report | N/A | ⬜ pending |
| 26-01-02 | 01 | 1 | GO-01 | manual audit | grep for "GO-01" verdict in audit report | N/A | ⬜ pending |
| 26-01-03 | 01 | 1 | GO-06 | manual audit | grep for "GO-06" verdict in audit report | N/A | ⬜ pending |
| 26-01-04 | 01 | 1 | GO-05 | manual audit | grep for "GO-05" verdict in audit report | N/A | ⬜ pending |
| 26-01-05 | 01 | 1 | GO-09 | manual audit | grep for "GO-09" verdict in audit report | N/A | ⬜ pending |
| 26-02-01 | 02 | 1 | GO-07 | manual audit | grep for "GO-07" verdict in audit report | N/A | ⬜ pending |
| 26-02-02 | 02 | 1 | GO-02 | manual audit | grep for "GO-02" verdict in audit report | N/A | ⬜ pending |
| 26-02-03 | 02 | 1 | GO-03 | manual audit | grep for "GO-03" verdict in audit report | N/A | ⬜ pending |
| 26-02-04 | 02 | 1 | GO-04 | manual audit | grep for "GO-04" verdict in audit report | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. This is an audit phase — deliverables are audit reports with PASS/FINDING verdicts, not automated tests.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| handleGameOverDrain distribution flow | GO-01 | Requires line-by-line code reading and reasoning about state mutations | Read GameOverModule:68-164, trace claimablePool, verify 10%/90% split |
| handleFinalSweep claim window | GO-02 | Requires reasoning about time-dependent state transitions | Read GameOverModule:171-189, verify 30-day guard and zeroing |
| Death clock trigger conditions | GO-03 | Requires verifying constant values and conditional logic | Read AdvanceModule:421-423, verify 365d/120d thresholds |
| Distress mode effects | GO-04 | Requires cross-module reasoning about lootbox routing | Read Storage:156-174, LootboxModule:600-621 |
| Revert analysis | GO-05 | Requires reasoning about all failure paths | Enumerate every require/revert on GAMEOVER path |
| Reentrancy/CEI ordering | GO-06 | Requires reasoning about external call ordering vs state mutations | Trace state writes vs external calls in handleGameOverDrain |
| Deity pass refunds | GO-07 | Requires verifying FIFO logic and unchecked arithmetic | Read GameOverModule:78-107, verify budget cap |
| Terminal decimator integration | GO-08 | Requires deep analysis of newest code | Read DecimatorModule:749-1027, trace claim lifecycle |
| No-RNG fallback path | GO-09 | Requires verifying VRF fallback security | Read AdvanceModule:797-875, trace fallback word composition |

---

## Validation Sign-Off

- [ ] All tasks have manual audit verification criteria
- [ ] Sampling continuity: every requirement has a defined verification method
- [ ] No automated test gaps (audit phase — all verification is manual)
- [ ] Feedback latency < N/A (manual audit)
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
