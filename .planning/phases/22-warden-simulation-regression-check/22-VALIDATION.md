---
phase: 22
slug: warden-simulation-regression-check
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-17
---

# Phase 22 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hardhat + Foundry (dual framework) |
| **Config file** | `hardhat.config.js` (Hardhat), `foundry.toml` (Foundry) |
| **Quick run command** | `npx hardhat test test/edge/DGNRSLiquid.test.js` |
| **Full suite command** | `npx hardhat test` |
| **Estimated runtime** | ~120 seconds |

---

## Sampling Rate

- **After every task commit:** No code changes expected — analysis-only phase
- **After every plan wave:** `npx hardhat test` if ANY code changes are made (regression fix)
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 22-01-XX | 01 | 1 | NOVEL-07 | manual-only | N/A — agent analysis output | N/A | ⬜ pending |
| 22-02-XX | 02 | 1 | NOVEL-08 | manual + spot-check | `npx hardhat test` | Existing suite | ⬜ pending |
| 22-03-XX | 03 | 2 | NOVEL-07, NOVEL-08 | manual-only | N/A — consolidation report | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. Phase 22 is primarily analysis and documentation, not code changes. If any fix is needed (unlikely given prior audit results), existing test infrastructure is sufficient.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Multi-agent warden simulation produces independent findings | NOVEL-07 | Analysis output, not code behavior | Verify 3+ agent reports exist with distinct findings |
| Regression check against all prior findings | NOVEL-08 | Finding-by-finding manual verification against current code | Verify each prior finding has verdict (valid/fixed/N-A) |
| Cross-reference deduplication | NOVEL-07 | Requires human judgment on finding equivalence | Verify consolidated report has no duplicate findings |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
