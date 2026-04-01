---
phase: 78
slug: edge-case-handling
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-22
---

# Phase 78 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (forge test) |
| **Config file** | foundry.toml |
| **Quick run command** | `forge test --match-contract TicketEdgeCases` |
| **Full suite command** | `forge test --match-contract TicketEdgeCases -vvv` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `forge test --match-contract TicketEdgeCases`
- **After every plan wave:** Run `forge test --match-contract TicketEdgeCases -vvv`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 78-01-01 | 01 | 1 | EDGE-01 | proof + unit | `forge test --match-test testEdge01` | ❌ W0 | ⬜ pending |
| 78-01-02 | 01 | 1 | EDGE-02 | proof + unit | `forge test --match-test testEdge02` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/TicketEdgeCases.t.sol` — stubs for EDGE-01, EDGE-02
- [ ] Shared test fixtures from existing ticket queue test infrastructure

*Existing infrastructure covers framework installation.*

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
