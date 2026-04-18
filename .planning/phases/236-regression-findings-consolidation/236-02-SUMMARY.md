---
phase: 236-regression-findings-consolidation
plan: 02
subsystem: audit-regression-appendix
tags: [regression, appendix, audit, v29.0]
requires: [audit/FINDINGS-v29.0.md, audit/FINDINGS-v27.0.md, audit/FINDINGS-v25.0.md, KNOWN-ISSUES.md, .planning/MILESTONES.md]
provides: ["audit/FINDINGS-v29.0.md §Regression Appendix with 32 per-item rows + v26.0 note + Regression Summary"]
affects: [audit/FINDINGS-v29.0.md]
key-files-modified: [audit/FINDINGS-v29.0.md]
decisions:
  - "All 32 per-item rows authored verbatim from 236-02-PLAN.md Task 1 authoritative row contents (13 v25.0 + 16 v27.0 + 3 KI)"
  - "Status taxonomy per D-03: PASS / SUPERSEDED / REGRESSED (only); no other vocabulary used"
  - "v29.0 regression result: 31 PASS + 1 SUPERSEDED (F-25-09) + 0 REGRESSED — no regressions detected"
  - "HEAD 1646d5af cited as the locked re-verification baseline (even though doc-only commits have advanced HEAD to 11739687); per CONTEXT D-17 audit baseline semantics"
  - "Tracking sync (PROJECT.md / MILESTONES.md / REQUIREMENTS.md) explicitly deferred to /gsd-complete-milestone per CONTEXT §Claude's Discretion"
  - "Plan 01 content (Executive Summary, 4 F-29-NN INFO blocks, Summary Statistics, Audit Trail) preserved byte-unchanged — append-only mode per File-append discipline directive"
metrics:
  tasks: 1
  commits: 1
  files_created: 0
  files_modified: 1
  lines_added: 102
  regression_rows_v25: 13
  regression_rows_v27: 16
  regression_rows_ki: 3
  regression_rows_total: 32
  status_pass: 31
  status_superseded: 1
  status_regressed: 0
  duration_minutes: 3
  completed: 2026-04-18
---

# Phase 236 Plan 02: Regression Appendix Summary

One-liner: Appended `## Regression Appendix` to `audit/FINDINGS-v29.0.md` with 32 per-item regression rows (13 v25.0 + 16 v27.0 + 3 v27.0 KNOWN-ISSUES) re-verified at HEAD `1646d5af` under the PASS / SUPERSEDED / REGRESSED taxonomy, plus a v26.0 design-only milestone sub-section and a final Regression Summary reporting 31 PASS + 1 SUPERSEDED (F-25-09 deity-boon fallback relocation) + 0 REGRESSED — no regressions detected across the 10-commit post-v27 contract-side delta.

## What Shipped

### Files Modified

| File | Change | Commit |
|------|--------|--------|
| `audit/FINDINGS-v29.0.md` | +102 lines — appended `## Regression Appendix` top-level section with four level-3 sub-sections (v25.0 Findings / v26.0 Milestone (design-only) / v27.0 Findings / v27.0 KNOWN-ISSUES Entries) + `### Regression Summary` final sub-section. Plan 01 sections (Executive Summary, Findings, Summary Statistics, Audit Trail, 4 F-29-NN INFO blocks) preserved byte-unchanged. | `3a553329` |

### Row-Count Breakdown (per sub-section)

| Sub-section | Expected | Actual | Status taxonomy |
|-------------|----------|--------|-----------------|
| `### v25.0 Findings (F-25-01 through F-25-13)` | 13 rows | 13 rows ✓ | 12 PASS + 1 SUPERSEDED (F-25-09) + 0 REGRESSED |
| `### v26.0 Milestone (design-only)` | 0 rows (one paragraph) | one paragraph ✓ | N/A — design-only |
| `### v27.0 Findings (F-27-01 through F-27-16)` | 16 rows | 16 rows ✓ | 16 PASS + 0 REGRESSED |
| `### v27.0 KNOWN-ISSUES Entries (3 design-decision entries citing F-27-NN)` | 3 rows | 3 rows ✓ | 3 PASS + 0 REGRESSED |
| **Total per-item rows** | **32** | **32 ✓** | **31 PASS + 1 SUPERSEDED + 0 REGRESSED** |

Section-scoped row counts verified programmatically:

```
awk '/^### v25.0 Findings/,/^### v26.0 Milestone/' audit/FINDINGS-v29.0.md | grep -cE '^\| F-25-[0-9]+'  → 13
awk '/^### v27.0 Findings/,/^### v27.0 KNOWN-ISSUES Entries/' audit/FINDINGS-v29.0.md | grep -cE '^\| F-27-[0-9]+'  → 16
awk '/^### v27.0 KNOWN-ISSUES Entries/,/^### Regression Summary/' audit/FINDINGS-v29.0.md | grep -cE '^\| "'  → 3
```

(Note: the plan's automated verify-gate regex `\| F-27-[0-9]+ \|` matches 18 file-wide lines because the KI table's `Cites` column also contains F-27-NN IDs for two of its three rows — F-27-12 and F-27-05 match the single-ID pattern; F-27-13/F-27-14 is a compound cite that does not match. The acceptance-criterion intent — 16 rows in the v27.0 Findings table — is satisfied by the section-scoped count.)

### Regression Summary Block (authored into the file)

- **Total items checked:** 32
- **PASS:** 31 — F-25-01..F-25-08, F-25-10..F-25-13 (12 v25.0) + F-27-01..F-27-16 (16 v27.0) + 3 KI entries
- **SUPERSEDED:** 1 — F-25-09 (deity-boon fallback relocation from AdvanceModule into `DegenerusGame.deityBoonData`; graded at v27.0 cycle; conclusion stands unchanged at HEAD `1646d5af`)
- **REGRESSED:** 0
- **Verdict:** No regressions detected. The 10-commit post-v27 contract-side delta (plus 2 post-Phase-230 RNG-hardening addendum commits `314443af` + `c2e5e0a9`) introduced zero regressions on any v25.0 or v27.0 observation.

### HEAD 1646d5af Anchor Confirmed

Every regression table's `Evidence` column cites HEAD `1646d5af` as the re-verification baseline:

- v25.0 table: 13/13 rows reference `HEAD 1646d5af` (header) and/or cite `1646d5af` explicitly in the evidence body text (F-25-05, F-25-07, F-25-08, F-25-09, F-25-12, F-25-13 cite it explicitly; others cite downstream Phase 23X AUDITs that were themselves locked to the HEAD 1646d5af baseline)
- v27.0 table: 16/16 rows reference `HEAD 1646d5af` (header)
- KI table: 3/3 rows reference `HEAD 1646d5af` (header)
- Regression Summary verdict explicitly states `HEAD 1646d5af`

`grep -c "1646d5af" audit/FINDINGS-v29.0.md` confirms the anchor appears throughout (exec summary + four regression sub-sections + summary).

Baseline-vs-worktree note: git HEAD at commit time was `11739687` (Plan 236-01 docs-only commits have advanced the branch tip beyond the audit baseline). Per `236-CONTEXT.md` and Phase 235 locked-baseline semantics, `1646d5af` remains the authoritative code-baseline SHA for v29.0 audit conclusions — subsequent docs-only commits do not invalidate the baseline. `git diff --stat 1646d5af..HEAD -- contracts/ test/` returns empty, confirming the audit baseline and code-worktree contract/test surface remain identical.

### Plan 01 Content Preservation (Confirmed)

| Plan 01 anchor | Present at HEAD | Method |
|----------------|-----------------|--------|
| `## Executive Summary` | ✓ | `grep -q "^## Executive Summary" audit/FINDINGS-v29.0.md` → match |
| `#### F-29-01:` | ✓ | `grep -q "F-29-01" audit/FINDINGS-v29.0.md` → match |
| `#### F-29-04:` | ✓ | `grep -q "F-29-04" audit/FINDINGS-v29.0.md` → match |
| `## Findings` root | ✓ | header present |
| `## Summary Statistics` | ✓ | header present |
| `## Audit Trail` | ✓ | header present |
| 4 F-29-NN INFO blocks | ✓ | `grep -c "^#### F-29-" audit/FINDINGS-v29.0.md` → 4 |
| Plan 01 cross-reference placeholder paragraph | ✓ | unchanged; appendix appended AFTER it |

No Plan 01 section was re-opened or modified. Append-only discipline held.

### Write-Target Gate Held

```
git diff --name-only HEAD~1 HEAD
  → audit/FINDINGS-v29.0.md   (single file, as required)

git diff --name-only HEAD~1 HEAD -- contracts/ test/
  → (empty)

git diff --name-only HEAD~1 HEAD -- KNOWN-ISSUES.md .planning/PROJECT.md .planning/MILESTONES.md .planning/REQUIREMENTS.md
  → (empty)
```

- Zero `contracts/` writes.
- Zero `test/` writes.
- Zero `KNOWN-ISSUES.md` writes (Plan 01 owned that file; Plan 02 only READS for the 3-row KI regression table evidence).
- Zero tracking-doc writes (`PROJECT.md`, `MILESTONES.md`, `REQUIREMENTS.md`) — explicitly deferred to `/gsd-complete-milestone` per `236-CONTEXT.md` §Claude's Discretion.

## Tracking Sync Deferral Note

Per `236-02-PLAN.md` <action> directive and `236-CONTEXT.md` §Claude's Discretion ("Tracking sync timing: Lean: fold into Plan 236-02's SUMMARY.md closing block ... OR defer entirely to /gsd-complete-milestone run."), this plan **explicitly defers** all tracking sync to the milestone-close workflow:

- `.planning/PROJECT.md` — NOT modified (no milestone close flip)
- `.planning/MILESTONES.md` — NOT modified (no v29.0 Complete flip)
- `.planning/REQUIREMENTS.md` — NOT modified (REG-01, REG-02, FIND-03 requirement-flip deferred)

Rationale: matches the v28.0 229-02 scope-guard precedent of keeping the terminal-plan close within budget; `/gsd-complete-milestone` is the designated owner for the v29.0 milestone-close flip and will process all three tracking documents as one coherent batch.

## Milestone-Closure Readiness Statement

`audit/FINDINGS-v29.0.md` is now **COMPLETE** as the v29.0 combined deliverable:

- **Executive Summary** — published (Plan 236-01) — severity 0/0/0/0/4, overall SAFE assessment
- **Per-Phase Findings Sections** — published (Plan 236-01) — 231→232→232.1→233→234→235 coverage with 4 F-29-NN INFO blocks
- **Summary Statistics + Audit Trail** — published (Plan 236-01)
- **Regression Appendix** — published (this plan) — 32 per-item rows + v26.0 design-only note + Regression Summary

All five v29.0 findings-group requirements are now **logically satisfied** (pending the formal tracking-flip at `/gsd-complete-milestone`):

| Req | Status | Satisfied by |
|-----|--------|--------------|
| FIND-01 | Complete | Plan 236-01 — 4 F-29-NN INFO blocks in v27.0-style per-finding format |
| FIND-02 | Complete | Plan 236-01 — 2 new KNOWN-ISSUES.md entries + 3 v29.0 back-refs |
| FIND-03 | Complete | Plan 236-01 (Executive Summary) + Plan 236-02 (Regression Appendix) — combined deliverable published |
| REG-01 | Complete | Plan 236-02 — 16 v27.0 INFO + 3 v27.0 KI entries re-verified PASS |
| REG-02 | Complete | Plan 236-02 — 13 v25.0 findings re-verified (12 PASS + 1 SUPERSEDED) + v26.0 design-only note |

**Ready for `/gsd-verify-work` and `/gsd-complete-milestone`.**

## Deviations from Plan

None — plan executed exactly as written. All 32 authoritative row contents from `236-02-PLAN.md` Task 1 `<action>` block were appended verbatim. Single task landed on its first attempt; all automated gates (structural headers present, row counts per section, HEAD anchor, SUPERSEDED taxonomy, Plan 01 preservation, write-target isolation) passed.

## Commits

| Task | Commit | Subject |
|------|--------|---------|
| Task 1 | `3a553329` | `docs(236-02): append Regression Appendix to audit/FINDINGS-v29.0.md` |

## Self-Check: PASSED

- `audit/FINDINGS-v29.0.md` exists and contains `## Regression Appendix` with four level-3 sub-sections (`### v25.0 Findings`, `### v26.0 Milestone`, `### v27.0 Findings`, `### v27.0 KNOWN-ISSUES Entries`) + `### Regression Summary` — all grep anchors match.
- Section-scoped row counts verified: 13 v25.0 + 16 v27.0 + 3 KI = 32.
- Status taxonomy vocabulary — only PASS / SUPERSEDED / REGRESSED appear as status values; F-25-09 classified SUPERSEDED; all others F-25-NN + F-27-NN + KI classified PASS.
- Regression Summary block states Total=32, PASS=31, SUPERSEDED=1, REGRESSED=0, verdict "No regressions detected".
- HEAD anchor `1646d5af` appears throughout — baseline unchanged at code layer.
- Plan 01 sections preserved byte-unchanged (Executive Summary, 4 F-29-NN INFO blocks F-29-01..04, Summary Statistics, Audit Trail).
- `git diff --name-only HEAD~1 HEAD` returns only `audit/FINDINGS-v29.0.md`.
- `git diff --name-only HEAD~1 HEAD -- contracts/ test/ KNOWN-ISSUES.md .planning/PROJECT.md .planning/MILESTONES.md .planning/REQUIREMENTS.md` returns empty.
- Commit `3a553329` reachable from HEAD.
