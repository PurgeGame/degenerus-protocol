---
phase: 50
slug: skim-redesign-audit
status: draft
nyquist_compliant: false
wave_0_complete: true
created: 2026-03-21
---

# Phase 50 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (forge) with Solidity 0.8.34 |
| **Config file** | foundry.toml |
| **Quick run command** | `forge test --match-contract FuturepoolSkimTest -x` |
| **Full suite command** | `forge test --match-contract FuturepoolSkimTest -vvv` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `forge test --match-contract FuturepoolSkimTest -x`
- **After every plan wave:** Run `forge test --match-contract FuturepoolSkimTest -vvv`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 50-01-01 | 01 | 1 | SKIM-01 | unit | `forge test --match-test test_overshootSurcharge_spotValues -x` | ✅ | ⬜ pending |
| 50-01-02 | 01 | 1 | SKIM-02 | unit | `forge test --match-test test_ratioAdjust_cappedAt400 -x` | ✅ | ⬜ pending |
| 50-01-03 | 01 | 1 | SKIM-03 | unit | `forge test --match-test test_vrf_bitWindows_independent -x` | ✅ | ⬜ pending |
| 50-01-04 | 01 | 1 | SKIM-04 | fuzz | `forge test --match-test testFuzz_G2_takeCapped -x` | ✅ | ⬜ pending |
| 50-01-05 | 01 | 1 | SKIM-05 | fuzz | `forge test --match-test testFuzz_G2_takeCapped -x` | ✅ | ⬜ pending |
| 50-02-01 | 02 | 1 | SKIM-06 | fuzz | `forge test --match-test testFuzz_conservation -x` | ✅ | ⬜ pending |
| 50-02-02 | 02 | 1 | SKIM-07 | fuzz | `forge test --match-test testFuzz_insuranceAlways1Pct -x` | ✅ | ⬜ pending |
| 50-03-01 | 03 | 2 | ECON-01 | unit | `forge test --match-test test_B_fastOvershoot_R3 -x` | ✅ | ⬜ pending |
| 50-03-02 | 03 | 2 | ECON-02 | unit | `forge test --match-test test_D_stall_60day -x` | ✅ | ⬜ pending |
| 50-03-03 | 03 | 2 | ECON-03 | unit | `forge test --match-test test_level1_overshootDormant -x` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. The 22-test FuturepoolSkim.t.sol suite provides complete fuzz and unit test coverage. This audit phase produces verdict documents, not new code.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Algebraic conservation proof | SKIM-06 | Formal proof requires mathematical reasoning, not just test execution | Verify algebraic derivation in verdict document against actual code lines |
| Bit-field isolation vs independence assessment | SKIM-03 | Requires semantic judgment about requirement intent | Review verdict rationale: does modulo satisfy "isolation" or only "independence"? |
| Level-1 overshoot intent assessment | ECON-03 | Design intent question, not testable property | Verify verdict addresses both lastPool=0 guard AND production bootstrap scenario |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
