---
phase: 226
slug: schema-migration-orphan-audit
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-15
---

# Phase 226 — Validation Strategy

> Catalog-only audit phase. "Validation" = independent spot re-check of findings, not code tests. No runtime test suite is introduced; feedback comes from re-grepping the audit target repo.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | none — pure-file audit |
| **Config file** | none |
| **Quick run command** | `rg` / `grep` against `/home/zak/Dev/PurgeGame/database/` (cross-repo READ-only per D-226-08) |
| **Full suite command** | per-plan spot-check script (see Per-Task Verification Map) |
| **Estimated runtime** | < 30 seconds per spot-check |

---

## Sampling Rate

- **After every task commit:** Spot-re-verify 2 random findings from the task's catalog against the live files.
- **After every plan wave:** Full re-grep of the finding File:line citations (all must still resolve to the cited line).
- **Before `/gsd-verify-work`:** Every finding must have a current `File:line` citation that matches live file content.
- **Max feedback latency:** ~30 seconds (ripgrep pass).

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Verification |
|---------|------|------|-------------|-------------|
| 226-01-* | 01 | — | SCHEMA-01 | Re-run cumulative `.sql` → schema TS diff on 3 random tables from the catalog; verdicts must match. |
| 226-02-* | 02 | — | SCHEMA-03 | Re-walk 2 random migration-to-migration diffs; rationale column must still match. 0007 anomaly must still be present. |
| 226-03-* | 03 | — | SCHEMA-02 | Pick 3 Tier A/B comment findings; regrep the cited column; comment text must match finding quote. |
| 226-04-* | 04 | — | SCHEMA-04 | Pick 2 orphan-finding tables; confirm still zero references across handlers/indexer/routes/views. |

*Plan-checker fills in concrete task IDs when PLAN.md files are written.*

---

## Wave 0 Requirements

None — catalog audit uses existing ripgrep + Read tools. No test scaffolding introduced.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Finding severity judgment (Tier A vs B for comments; INFO vs LOW for schema drift) | SCHEMA-01..03 | Subjective threshold (D-225-04 heuristic) | Reviewer re-reads drift + finding, agrees/disagrees on tier. |

---

## Validation Sign-Off

- [ ] Every finding has a `File:line` that resolves in the current audit-target repo
- [ ] Spot-sample per plan passes (≥ 90% of re-checks agree with original verdict)
- [ ] `F-28-226-01` (0007 snapshot anomaly) confirmed present
- [ ] `nyquist_compliant: true` set in frontmatter once sign-off complete

**Approval:** pending
