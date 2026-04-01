---
phase: 48
slug: documentation-sync
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-21
---

# Phase 48 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (forge) + Hardhat |
| **Config file** | `foundry.toml` |
| **Quick run command** | `forge build` |
| **Full suite command** | `forge test` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `forge build`
- **After every plan wave:** Run `forge test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 48-01-01 | 01 | 1 | DOC-01 | manual-only | N/A — NatSpec review | N/A | ⬜ pending |
| 48-01-02 | 01 | 1 | DOC-02 | manual-only | N/A — comment review | N/A | ⬜ pending |
| 48-01-03 | 01 | 1 | DOC-03 | unit | `forge build` | ✅ | ⬜ pending |
| 48-02-01 | 02 | 2 | DOC-04 | manual-only | N/A — doc review | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. No new test files needed — DOC-03 error rename is verified by `forge build` and existing test suite.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| NatSpec accuracy | DOC-01 | NatSpec correctness is semantic — requires human comparison of comment text vs code behavior | Read each function's NatSpec, compare every @param/@return/@dev against implementation |
| Bit allocation map | DOC-02 | Comment content correctness is semantic | Verify comment block lists all VRF word consumers with correct bit ranges and operations |
| Audit doc sync | DOC-04 | Documentation accuracy requires semantic review | Check all 3 tier-1 audit docs mention gambling burn mechanism, v3.3 findings, and code fixes |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
