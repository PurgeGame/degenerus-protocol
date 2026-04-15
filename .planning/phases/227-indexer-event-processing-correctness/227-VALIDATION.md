---
phase: 227
slug: indexer-event-processing-correctness
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-15
---

# Phase 227 — Validation Strategy

> Catalog-only audit. "Validation" = independent spot re-check of findings via ripgrep against the audit-target repos. No runtime test suite introduced.

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | none — pure-file audit |
| **Config file** | none |
| **Quick run command** | `rg` against `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/` and `/home/zak/Dev/PurgeGame/database/` |
| **Full suite command** | per-plan spot-check (see map below) |
| **Estimated runtime** | < 30 seconds per spot-check |

## Sampling Rate

- **After every task commit:** Re-verify 2 random findings against live files.
- **After every plan wave:** Full re-grep of finding `File:line` citations.
- **Before `/gsd-verify-work`:** every finding's `File:line` must still resolve to the cited content.

## Per-Task Verification Map

| Task | Plan | Requirement | Verification |
|------|------|-------------|--------------|
| 227-01-* | 01 | IDX-01 | Pick 3 events from matrix; regrep `event FooBar(` in contracts/ + registry key in event-processor.ts; classifications must match. |
| 227-02-* | 02 | IDX-02 | Pick 3 case handlers; re-derive arg→field mapping against Phase 226 schema model; verdict must match. |
| 227-03-* | 03 | IDX-03 | Pick 3 Tier A/B comment findings; regrep cited line; comment text + code behavior must match finding claim. |

## Wave 0 Requirements

None — audit uses existing ripgrep/Read tools.

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Severity promotion INFO→LOW (silent data corruption vs safe drift) | IDX-02 | Subjective threshold | Reviewer agrees/disagrees per finding. |
| Tier A vs B comment-drift classification | IDX-03 | Subjective | Reviewer agrees/disagrees per finding. |

## Validation Sign-Off

- [ ] Every finding has a `File:line` resolving in the current audit-target repos
- [ ] Spot-sample per plan passes (≥ 90% agreement)
- [ ] `(contract, event)` keying honored in 227-01 (shared-name events: Transfer, Approval, Burn, Claim, Deposit, QuestCompleted)
- [ ] `nyquist_compliant: true` once sign-off complete

**Approval:** pending
