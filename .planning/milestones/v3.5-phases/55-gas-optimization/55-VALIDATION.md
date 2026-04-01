---
phase: 55
slug: gas-optimization
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-21
---

# Phase 55 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hardhat + Foundry (dual stack) |
| **Config file** | `foundry.toml` (Foundry), `hardhat.config.js` (Hardhat) |
| **Quick run command** | `forge test --match-path 'test/fuzz/*' -vv` |
| **Full suite command** | `npm test` (1,463 tests) |
| **Estimated runtime** | ~120 seconds |

---

## Sampling Rate

- **After every task commit:** Visual review of findings document completeness
- **After every plan wave:** Cross-reference findings against contract list (all 34 covered?)
- **Before `/gsd:verify-work`:** All 4 requirements addressed with documented evidence
- **Max feedback latency:** N/A (audit analysis phase, no runtime tests)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 55-01-01 | 01 | 1 | GAS-01 | manual-only | `forge inspect <Contract> storageLayout` + `rg` reference counting | N/A | pending |
| 55-02-01 | 02 | 1 | GAS-02 | manual-only | `rg` for unused errors/events + branch analysis | N/A | pending |
| 55-03-01 | 03 | 1 | GAS-03 | manual-only | `forge inspect` storage layout analysis | N/A | pending |
| 55-04-01 | 04 | 1 | GAS-04 | manual-only | document review | N/A | pending |

*Status: pending*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. This is an audit analysis phase — the requirements are about identifying and documenting findings, not about runtime behavior.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| All storage vars confirmed alive | GAS-01 | Audit analysis — requires human judgment on reachability | Trace each var's declaration, write sites, read sites across all contracts |
| No redundant checks/dead branches | GAS-02 | Audit analysis — dead branch detection requires control flow understanding | Search for unused errors, events, unreachable conditions |
| Storage packing opportunities | GAS-03 | Audit analysis — requires storage layout + co-access pattern analysis | Use forge inspect, identify consecutive scalar types with wasted bytes |
| All findings documented | GAS-04 | Document review — verify completeness and format | Check each finding has contract, line ref, and estimated impact |

---

## Validation Sign-Off

- [x] All tasks have manual verification procedures
- [x] Sampling continuity: manual review after each task
- [x] Wave 0 covers all MISSING references (none needed)
- [x] No watch-mode flags
- [x] Feedback latency: N/A (audit analysis)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
