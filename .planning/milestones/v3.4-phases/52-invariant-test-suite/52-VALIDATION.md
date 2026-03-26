---
phase: 52
slug: invariant-test-suite
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-21
---

# Phase 52 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry forge 1.5.1-stable |
| **Config file** | `foundry.toml` |
| **Quick run command** | `forge test --match-contract FuturepoolSkimTest -vv` |
| **Full suite command** | `forge test --match-path "test/fuzz/*" -vv` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `forge test --match-contract FuturepoolSkimTest -vv && forge test --match-contract RedemptionInvariants -vv`
- **After every plan wave:** Run `forge test --match-path "test/fuzz/*" -vv`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 52-01-01 | 01 | 1 | INV-01 | fuzz | `forge test --match-test "testFuzz_INV01" -vv` | ❌ W0 | ⬜ pending |
| 52-01-02 | 01 | 1 | INV-02 | fuzz | `forge test --match-test "testFuzz_INV02" -vv` | ❌ W0 | ⬜ pending |
| 52-02-01 | 02 | 1 | INV-03 | fuzz + invariant | `forge test --match-test "testFuzz_INV03" -vv` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/fuzz/FuturepoolSkim.t.sol` — add `testFuzz_INV01_conservation` and `testFuzz_INV02_takeCap` named fuzz tests
- [ ] `test/fuzz/FuturepoolSkim.t.sol` or new file — add `testFuzz_INV03_splitConservation` (arithmetic fuzz test for 50/50 split)

*Existing infrastructure covers all phase requirements. No new framework install needed.*

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
