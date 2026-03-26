---
phase: 84
slug: prize-pool-flow-currentprizepool-deep-dive
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-23
---

# Phase 84 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (forge) + Hardhat |
| **Config file** | `foundry.toml` |
| **Quick run command** | `forge test --match-contract PrizePoolFreeze -vvv` |
| **Full suite command** | `forge test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** N/A — audit-only phase, no code changes
- **After every plan wave:** Verify existing tests still pass: `forge test --match-contract PrizePoolFreeze -vvv`
- **Before `/gsd:verify-work`:** All existing Foundry tests pass
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 84-01-01 | 01 | 1 | PPF-01 | manual audit | N/A (code trace) | N/A | pending |
| 84-01-02 | 01 | 1 | PPF-02 | manual audit + storage inspect | `forge inspect DegenerusGame storage-layout` | N/A | pending |
| 84-01-03 | 01 | 1 | PPF-03 | manual audit | N/A (code trace) | N/A | pending |
| 84-01-04 | 01 | 1 | PPF-04 | manual audit | N/A (code trace) | N/A | pending |
| 84-01-05 | 01 | 1 | PPF-05 | manual audit | N/A (code trace + v3.8 cross-ref) | N/A | pending |
| 84-01-06 | 01 | 1 | PPF-06 | manual audit | N/A (doc review) | N/A | pending |

*Status: pending · green · red · flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. This is an audit-only phase — no code changes, no new test stubs needed.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| currentPrizePool writers enumerated | PPF-01 | Code trace audit — requires human/agent reading | Grep `currentPrizePool` across all contracts, enumerate every write site with file:line |
| prizePoolsPacked layout documented | PPF-02 | Storage layout audit — requires reading packed field helpers | Read `_getPrizePools`/`_setPrizePools` and verify bit positions |
| prizePoolFrozen lifecycle traced | PPF-03 | Freeze lifecycle audit — requires tracing all check sites | Grep `prizePoolFrozen` across all contracts, classify each as redirect or revert |
| Consolidation mechanics documented | PPF-04 | Multi-step consolidation flow — requires step-by-step reading | Read `consolidatePrizePools` and pre/post-consolidation steps in AdvanceModule |
| VRF-dependent readers documented | PPF-05 | VRF safety audit — requires backward trace from consumers | Identify all readers of `currentPrizePool` during VRF commitment window |
| Discrepancies flagged | PPF-06 | Cross-reference with prior audit prose | Compare findings against v3.5 and v3.8 documentation |

---

## Validation Sign-Off

- [x] All tasks have manual verification procedures defined
- [x] Sampling continuity: audit-only phase, no automated test gaps
- [x] Wave 0 covers all MISSING references (none needed)
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
