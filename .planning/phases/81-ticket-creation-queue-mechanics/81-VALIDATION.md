---
phase: 81
slug: ticket-creation-queue-mechanics
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-23
---

# Phase 81 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (forge) + Hardhat |
| **Config file** | `foundry.toml` |
| **Quick run command** | `forge test --match-contract QueueDoubleBuffer -vvv` |
| **Full suite command** | `forge test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** `forge test --match-contract QueueDoubleBuffer -vvv`
- **After every plan wave:** `forge test` (full suite)
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 81-01-01 | 01 | 1 | TKT-01 | manual audit | N/A (audit doc review) | N/A | ⬜ pending |
| 81-01-02 | 01 | 1 | TKT-02 | manual audit | N/A (audit doc review) | N/A | ⬜ pending |
| 81-01-03 | 01 | 1 | TKT-03 | manual audit | N/A (audit doc review) | N/A | ⬜ pending |
| 81-01-04 | 01 | 1 | TKT-04 | manual audit | N/A (code trace) | N/A | ⬜ pending |
| 81-01-05 | 01 | 1 | TKT-05 | manual audit + existing test | `forge test --match-contract QueueDoubleBuffer -vvv` | Yes | ⬜ pending |
| 81-01-06 | 01 | 1 | TKT-06 | manual audit + existing test | `forge test --match-contract PrizePoolFreeze -vvv` | Yes | ⬜ pending |
| 81-01-07 | 01 | 1 | DSC-01 | manual audit | N/A (doc review) | N/A | ⬜ pending |
| 81-01-08 | 01 | 1 | DSC-02 | manual audit | N/A (doc review) | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. This is an audit-only phase (no code changes). Deliverables are audit documents, not code.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| All external ticket creation functions identified | TKT-01 | Audit document review — no code to test | Verify every `external` function creating tickets is listed with file:line |
| Ticket count/level/key selection documented | TKT-02 | Audit document review | Verify each entry point has count determination, target level, and queue key |
| rngLockedFlag/prizePoolFrozen behavior | TKT-03 | Audit document review | Verify guards documented for each queue helper caller |
| All queue callers enumerated | TKT-04 | Code trace — manual | Verify grep results match documented callers |
| Double-buffer formulas documented | TKT-05 | Partial — existing tests cover mechanics | Verify _tqReadKey/_tqWriteKey/_tqFarFutureKey formulas documented |
| Swap trigger conditions documented | TKT-06 | Partial — existing tests cover freeze | Verify _swapAndFreeze/_swapTicketSlot conditions listed |
| Discrepancies flagged | DSC-01 | Audit document review | Verify every prior claim checked against code |
| New findings flagged | DSC-02 | Audit document review | Verify novel findings have file:line citations |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending