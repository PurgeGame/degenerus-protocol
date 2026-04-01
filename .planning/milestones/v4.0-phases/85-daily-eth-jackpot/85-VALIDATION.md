---
phase: 85
slug: daily-eth-jackpot
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-23
---

# Phase 85 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (forge) + Hardhat |
| **Config file** | `foundry.toml` |
| **Quick run command** | `forge test --match-contract Jackpot -vvv` |
| **Full suite command** | `forge test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** N/A (audit-only phase, no code changes)
- **After every plan wave:** Verify audit doc completeness against requirements
- **Before `/gsd:verify-work`:** All requirements have file:line citations in audit doc
- **Max feedback latency:** N/A (manual audit verification)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 85-01-01 | 01 | 1 | DETH-01 | manual audit | N/A (audit doc review) | N/A | pending |
| 85-01-02 | 01 | 1 | DETH-02 | manual audit | N/A (audit doc review) | N/A | pending |
| 85-01-03 | 01 | 1 | DETH-03 | manual audit | N/A (audit doc review) | N/A | pending |
| 85-01-04 | 01 | 1 | DETH-04 | manual audit | N/A (audit doc review) | N/A | pending |
| 85-01-05 | 01 | 1 | DETH-05 | manual audit | N/A (cross-reference check) | N/A | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. This is an audit-only phase (no code changes). Deliverables are audit documents, not code.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| currentPrizePool source and BPS allocation | DETH-01 | Audit document review — no code to test | Verify BPS constants, split logic, and all writers documented with file:line |
| Phase 0 vs Phase 1 behavior | DETH-02 | Audit document review | Verify both phases documented with source pool, level selection, winner cap, share packing differences |
| Bucket/cursor winner selection | DETH-03 | Audit document review | Verify _processDailyEthChunk algorithm traced with bucket sizing, cursor resume, winner selection file:line |
| Carryover mechanics | DETH-04 | Audit document review | Verify unfilled bucket handling, excess rollover, day-to-day state reset documented |
| Discrepancies and new findings | DETH-05 | Cross-reference check | Verify every prior audit claim checked; all new findings have [DISCREPANCY] or [NEW FINDING] tags |

---

## Validation Sign-Off

- [ ] All tasks have manual verification criteria defined
- [ ] Each requirement has file:line citations in audit doc
- [ ] Cross-reference against v3.2 jackpot audit completed
- [ ] No watch-mode flags
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
