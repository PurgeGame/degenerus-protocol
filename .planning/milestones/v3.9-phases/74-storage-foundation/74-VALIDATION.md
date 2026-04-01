---
phase: 74
slug: storage-foundation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-22
---

# Phase 74 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (forge test) |
| **Config file** | foundry.toml |
| **Quick run command** | `forge test --match-contract TqFarFutureKeyTest -vvv` |
| **Full suite command** | `forge test -vvv` |
| **Estimated runtime** | ~10 seconds |

---

## Sampling Rate

- **After every task commit:** Run `forge test --match-contract TqFarFutureKeyTest -vvv`
- **After every plan wave:** Run `forge test -vvv`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 74-01-01 | 01 | 1 | STORE-01 | unit | `forge test --match-test testFarFutureBitConstant -vvv` | ❌ W0 | ⬜ pending |
| 74-01-02 | 01 | 1 | STORE-02 | unit | `forge test --match-test testFarFutureKeyNoCollision -vvv` | ❌ W0 | ⬜ pending |
| 74-01-03 | 01 | 1 | STORE-01 | integration | `forge test --match-test testCompilation -vvv` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/TqFarFutureKey.t.sol` — test contract for STORE-01, STORE-02 validation
- [ ] Foundry already installed — no framework setup needed

*Existing infrastructure covers framework requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Inheritance chain compiles | STORE-01 | Compilation is automated via forge build | N/A — automated |

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
