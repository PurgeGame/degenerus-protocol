---
phase: 4
slug: advancegame-rewrite
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-11
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (forge test) |
| **Config file** | foundry.toml |
| **Quick run command** | `forge test --match-contract AdvanceGameRewrite -vvv` |
| **Full suite command** | `forge test -vvv` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `forge test --match-contract AdvanceGameRewrite -vvv`
- **After every plan wave:** Run `forge test -vvv`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 04-01-01 | 01 | 1 | ADV-01, ADV-02, ADV-03 | unit | `forge test --match-contract AdvanceGameRewrite -vvv` | ❌ W0 | ⬜ pending |
| 04-02-01 | 02 | 1 | ADV-01 | unit | `forge test --match-test "test_midDay.*noFreeze" -vvv` | ❌ W0 | ⬜ pending |
| 04-02-02 | 02 | 1 | ADV-02 | unit | `forge test --match-test "test_dailyRng.*gated" -vvv` | ❌ W0 | ⬜ pending |
| 04-02-03 | 02 | 1 | ADV-03 | unit | `forge test --match-test "test_ticketsProcessed.*beforeJackpot" -vvv` | ❌ W0 | ⬜ pending |
| 04-02-04 | 02 | 1 | SC-4 | unit | `forge test --match-test "test_breakPath.*freeze" -vvv` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/fuzz/AdvanceGameRewrite.t.sol` — AdvanceHarness + all ADV-01/02/03/SC-4 test stubs
- [ ] Harness needs: exposed drain gate, freeze state inspection, ticket queue population, `ticketsFullyProcessed` getter/setter

*Existing infrastructure (Foundry, forge) covers framework requirements.*

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
