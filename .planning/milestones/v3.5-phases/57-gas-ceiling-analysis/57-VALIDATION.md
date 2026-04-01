---
phase: 57
slug: gas-ceiling-analysis
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-21
---

# Phase 57 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (forge) 0.8.34 via solc, via_ir=true, optimizer_runs=2 |
| **Config file** | foundry.toml |
| **Quick run command** | `forge test --gas-report --match-contract AdvanceGas -vv` |
| **Full suite command** | `forge test -vv` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** N/A (analysis phase — no code changes)
- **After every plan wave:** Review gas numbers against 14M ceiling
- **Before `/gsd:verify-work`:** All 5 CEIL requirements documented with evidence
- **Max feedback latency:** N/A (manual analysis)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 57-01-01 | 01 | 1 | CEIL-01 | manual + gas-report | `forge test --gas-report` | N/A | ⬜ pending |
| 57-01-02 | 01 | 1 | CEIL-02 | manual analysis | N/A — static analysis | N/A | ⬜ pending |
| 57-01-03 | 01 | 1 | CEIL-05 | manual analysis | N/A — document output | N/A | ⬜ pending |
| 57-02-01 | 02 | 1 | CEIL-03 | manual + gas-report | `forge test --gas-report` | N/A | ⬜ pending |
| 57-02-02 | 02 | 1 | CEIL-04 | manual analysis | N/A — static analysis | N/A | ⬜ pending |
| 57-02-03 | 02 | 1 | CEIL-05 | manual analysis | N/A — document output | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. This is a pure analysis phase — no code is modified. Foundry gas reports and static code analysis provide all necessary evidence.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| advanceGame worst-case gas per path | CEIL-01 | Requires tracing all 12 stage paths and computing gas from EVM op costs | Trace each stage, sum SSTOREs, external calls, loops |
| Max jackpot payouts under 14M | CEIL-02 | Static analysis of loop bounds and gas budgets | Compute max iterations at WRITES_BUDGET_SAFE=550 |
| purchase worst-case gas | CEIL-03 | Requires analyzing constant-overhead external calls | Trace purchase, sum all external calls and storage writes |
| Max ticket batch under 14M | CEIL-04 | Static analysis of per-ticket gas × batch size | Compute: 14M / per-ticket-gas |
| Headroom documentation | CEIL-05 | Aggregation of CEIL-01 through CEIL-04 results | Compile table with (14M - worst_case) per path |

---

## Validation Sign-Off

- [ ] All tasks have manual verification with documented evidence
- [ ] Sampling continuity: each requirement has traced evidence from source code
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < N/A (analysis phase)
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
