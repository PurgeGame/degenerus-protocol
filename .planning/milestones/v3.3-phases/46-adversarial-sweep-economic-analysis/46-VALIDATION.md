---
phase: 46
slug: adversarial-sweep-economic-analysis
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-21
---

# Phase 46 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (forge 0.8.34 compatible) |
| **Config file** | foundry.toml (invariant: 256 runs, depth 128) |
| **Quick run command** | `forge test --match-path test/fuzz/invariant/RedemptionInvariants.inv.t.sol -vvv` |
| **Full suite command** | `forge test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Review document structure and citation count
- **After every plan wave:** Cross-reference findings against prior audit corpus
- **Before `/gsd:verify-work`:** All 29 contracts have explicit verdicts; all 4 entry points verified; all 4 strategies documented; bank-run analysis complete
- **Max feedback latency:** 30 seconds (invariant tests only)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 46-01-01 | 01 | 1 | ADV-01 | manual | N/A -- document review | N/A | pending |
| 46-01-02 | 01 | 1 | ADV-01 | manual | N/A -- document review | N/A | pending |
| 46-01-03 | 01 | 1 | ADV-01 | manual | N/A -- document review | N/A | pending |
| 46-01-04 | 01 | 1 | ADV-01 | manual | N/A -- document review | N/A | pending |
| 46-02-01 | 02 | 1 | ADV-02 | manual | N/A -- code trace | N/A | pending |
| 46-02-02 | 02 | 1 | ADV-03 | manual | N/A -- code trace | N/A | pending |
| 46-03-01 | 03 | 1 | ECON-01 | manual | N/A -- EV calculations | N/A | pending |
| 46-03-02 | 03 | 1 | ECON-02 | manual | N/A -- analytical model | N/A | pending |

*Status: pending · green · red · flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. This is a pure analysis phase -- no new test files or framework changes needed. Existing invariant tests provide regression safety for any claimed violations.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Warden simulation report | ADV-01 | Pure document deliverable -- adversarial code review with structured findings | Verify all 29 contracts have explicit verdict (finding or "clean") |
| Composability attack catalog | ADV-02 | Code trace deliverable -- multi-contract interaction analysis | Verify attack sequences tested and outcomes documented |
| Access control verification | ADV-03 | Code review deliverable -- msg.sender guard verification | Verify 4 entry points have guard + caller verification |
| Rational actor strategies | ECON-01 | Economic analysis deliverable -- EV calculations | Verify 4 strategies with cost-benefit and verdict |
| Bank-run scenario | ECON-02 | Analytical modeling deliverable | Verify mass-burn scenario modeled with solvency outcome |

**Justification:** Phase 46 is a pure analysis phase producing audit documents, not code. The existing invariant test suite (Phase 45) provides automated regression safety. If any warden claims an invariant violation, run: `forge test --match-path test/fuzz/invariant/RedemptionInvariants.inv.t.sol -vvv`

---

## Validation Sign-Off

- [x] All tasks have manual verify or Wave 0 dependencies
- [x] Sampling continuity: document review after each task commit
- [x] Wave 0 covers all MISSING references (none needed)
- [x] No watch-mode flags
- [x] Feedback latency < 30s (invariant tests only)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
