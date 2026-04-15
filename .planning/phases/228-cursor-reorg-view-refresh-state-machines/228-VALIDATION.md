---
phase: 228
slug: cursor-reorg-view-refresh-state-machines
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-15
---

# Phase 228 — Validation Strategy

> Catalog-only behavioral audit. Validation = independent spot re-check via ripgrep + control-flow re-read.

## Test Infrastructure

| Property | Value |
|----------|-------|
| Framework | none — file + control-flow audit |
| Quick run command | `rg` against `database/src/indexer/` + `database/src/db/schema/views.ts` |
| Estimated runtime | < 30 seconds per re-check |

## Sampling Rate

- Spot-re-verify 2 random M-rows per plan after execution.
- Confirm every finding's `File:line` resolves in the live file.
- All 4 Phase 227 deferrals have an explicit verdict row in the deliverables.

## Per-Task Verification Map

| Task | Plan | Requirement | Verification |
|------|------|-------------|--------------|
| 228-01-* | 01 | IDX-04 | Pick 3 M-rows (cursor or reorg); re-trace control flow; verdict must match. |
| 228-02-* | 02 | IDX-05 | Pick 2 M-rows; re-grep view-refresh.ts trigger + views.ts mat-view defs; verdict must match. |

## Validation Sign-Off

- [ ] All 14 M-matrix rows have PASS/FAIL verdicts
- [ ] All 4 Phase 227 deferrals explicitly addressed
- [ ] Every finding's File:line resolves
- [ ] Severity taxonomy (INFO/LOW/MEDIUM) applied consistently

**Approval:** pending
