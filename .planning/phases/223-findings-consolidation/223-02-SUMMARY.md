---
phase: 223-findings-consolidation
plan: 02
subsystem: audit-docs
tags: [known-issues, milestones, project, requirements, v27.0, findings-consolidation]

requires:
  - phase: 223-01
    provides: "audit/FINDINGS-v27.0.md with stable F-27-01..F-27-16 IDs; 223-01-SUMMARY.md handoff table identifying D-08 KNOWN-ISSUES promotion candidates (F-27-12, F-27-05, F-27-13 + F-27-14, F-27-15)"
  - phase: 220-222
    provides: "7 plan SUMMARYs feeding MILESTONES.md accomplishments bullets (delegatecall gate, raw-selector gate, 308-function coverage matrix, coverage-check gate, CoverageGap222.t.sol integration tests)"
provides:
  - "KNOWN-ISSUES.md with 3 new v27.0 design-decision entries referencing F-27-05, F-27-12, F-27-13 + F-27-14"
  - ".planning/MILESTONES.md v27.0 Call-Site Integrity Audit retrospective entry (7 accomplishments bullets, 4 phases / 9 plans / 23 tasks)"
  - ".planning/PROJECT.md v27.0 moved from Current Milestone to Completed Milestone with Goal / Target scope / Incident context narrative preserved"
  - ".planning/REQUIREMENTS.md all 14 CSI-NN checkboxes flipped to [x] and traceability Status column flipped to Complete"
affects: []

tech-stack:
  added: []
  patterns:
    - "Migrate-don't-delete pattern: when moving a milestone from Current to Completed in PROJECT.md, substantive narrative (Goal / Target scope / Incident context) is migrated under an explicit label rather than dropped"
    - "Count-wording consistency rule: `177+1 CRITICAL_GAP` expression used in BOTH MILESTONES and PROJECT; bare `178 CRITICAL_GAP` form prohibited to keep the derivation (177 non-admin + 1 admin-boundary) visible across both files"

key-files:
  created:
    - .planning/phases/223-findings-consolidation/223-02-SUMMARY.md
  modified:
    - KNOWN-ISSUES.md
    - .planning/MILESTONES.md
    - .planning/PROJECT.md
    - .planning/REQUIREMENTS.md

key-decisions:
  - "Promoted 3 entries to KNOWN-ISSUES.md (not 1 and not 4): F-27-12 (VRF_KEY_HASH deploy-pipeline regex), F-27-05 (parallel-make race), and combined F-27-13 + F-27-14 (VERIFICATION gap closures summary). F-27-15 deferred because its value is forward-looking gate-enhancement proposal rather than design-decision / accepted trade-off"
  - "Combined F-27-13 and F-27-14 into a single KNOWN-ISSUES entry per plan option c — both gaps were closed in-cycle by Plan 222-03 and an external reader benefits from seeing the pair in one place rather than two"
  - "Preserved v27.0 Goal / Target scope / Incident context narrative verbatim when migrating from Current Milestone to Completed Milestone in PROJECT.md — zero substantive content dropped"
  - "CONTEXT D-09 stale counts (4 phases / 7 plans / ~15 tasks) superseded by actuals from SUMMARY performance blocks: 4 phases / 9 plans / 23 tasks. Plan 222-03 was a Wave 2 gap-closure plan not anticipated in D-09; other task counts ran higher than the rough ~15 estimate."

patterns-established:
  - "Per-file staged commit via `git add -f` for .planning/*.md files that are tracked but live under a .gitignored directory — `gsd-tools commit` returns `skipped_gitignored` for these paths so explicit `git add -f` is the correct handoff pattern when the files are pre-existing tracked artifacts"

requirements-completed: [CSI-13, CSI-14]

# Metrics
duration: 7min
completed: 2026-04-13
---

# Phase 223 Plan 02: v27.0 Milestone Close-Out Summary

**v27.0 Call-Site Integrity Audit SHIPPED — 3 KNOWN-ISSUES entries added, MILESTONES retrospective written, PROJECT.md migrated v27.0 to Completed Milestone with narrative preserved, all 14/14 CSI requirements Complete.**

## Performance

- **Duration:** 7 min
- **Started:** 2026-04-13T02:22:51Z
- **Completed:** 2026-04-13T02:29:19Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- **KNOWN-ISSUES.md (CSI-13):** Appended 3 new Design Decisions entries at end of section, each referencing an F-27-NN ID from `audit/FINDINGS-v27.0.md` and following the existing bolded-title + paragraph + parenthetical reference pattern. Pre-edit bolded entry count: 34; post-edit: 37. Section headings unchanged.
- **MILESTONES.md (CSI-14 part 1):** Inserted `## v27.0 Call-Site Integrity Audit (Shipped: 2026-04-13)` block above the v26.0 entry (most-recent-first ordering). Header: `**Phases completed:** 4 phases, 9 plans, 23 tasks`. Seven accomplishment bullets covering delegatecall gate, raw-selector gate, 308-function coverage matrix, coverage-check gate, CoverageGap222.t.sol tests, FINDINGS-v27.0.md consolidation, and KNOWN-ISSUES update.
- **PROJECT.md (CSI-14 part 2):** Replaced `## Current Milestone: v27.0 Call-Site Integrity Audit` with `## Current Milestone: TBD — pending roadmap planning` (per D-10; no v28.0 defined in ROADMAP.md). Added `## Completed Milestone: v27.0 Call-Site Integrity Audit` immediately after, containing the migrated Goal / Target scope / Incident context narrative under an explicit label and a Result block using the `177+1 CRITICAL_GAP` wording.
- **REQUIREMENTS.md (CSI-08..10 + CSI-12..14 close-out):** Flipped six CSI-NN checkboxes from `[ ]` to `[x]` (CSI-08, CSI-09, CSI-10, CSI-12, CSI-13, CSI-14) and the corresponding traceability table rows from `Pending` to `Complete`. Final state: 14/14 CSI-NN items Complete, 0 Pending.

## Task Commits

Each task was committed atomically:

1. **Task 1: Promote D-08-qualifying items to KNOWN-ISSUES.md** - `3d798794` (docs)
2. **Task 2: Write v27.0 MILESTONES entry + move v27.0 in PROJECT.md + flip CSI checkboxes** - `5408f745` (docs)

## Files Created/Modified

- `KNOWN-ISSUES.md` — appended 3 new Design Decisions entries (F-27-12 VRF_KEY_HASH regex, F-27-05 parallel-make race, combined F-27-13 + F-27-14 VERIFICATION gap closures). All 3 entries inserted at the end of the `## Design Decisions` section (between the F-25-12 decimator entry and the `---` + `## Automated Tool Findings` divider). Commit `3d798794`.
- `.planning/MILESTONES.md` — inserted v27.0 entry at line 3 (above v26.0 at line 19). 7 accomplishments bullets. Uses `177+1 CRITICAL_GAP` and `16 INFO findings` wording. Commit `5408f745`.
- `.planning/PROJECT.md` — Current Milestone v27.0 block (lines 11-21) replaced with TBD block and a new Completed Milestone v27.0 block containing the preserved narrative under `**Goal / Target scope / Incident context:**`. v27.0 Completed Milestone now at line 15; v26.0 Completed Milestone at line 33 (most-recent-first preserved). Commit `5408f745`.
- `.planning/REQUIREMENTS.md` — six CSI-NN checkboxes and six traceability rows flipped. Final state: 14 `[x]` / 0 `[ ]`, 14 `| Complete |` / 0 `| Pending |`. Commit `5408f745`.

**Plan metadata commit:** This SUMMARY.md + STATE.md + ROADMAP.md update is captured in the final docs commit (see Final Metadata Commit section below).

## Plan-Specific Data Points

### KNOWN-ISSUES.md new-entry count and F-27-NN references

**New-entry count:** 3 (minimum 1 per plan; maximum 4; this execution chose 3 per the D-08 evaluation below).

| Entry | Title | F-27-NN | Source item(s) |
|-------|-------|---------|----------------|
| 1 | Deploy-pipeline VRF_KEY_HASH regex is single-line only | F-27-12 | Phase 222 WR-222-01 |
| 2 | Parallel `make -j test` mutates `ContractAddresses.sol` concurrently | F-27-05 | Phase 220 IN-220-03 |
| 3 | v27.0 Phase 222 VERIFICATION gap closures (in-cycle) | F-27-13 + F-27-14 | Phase 222 WR-222-02 + WR-222-04 + Gap 1 (F-27-13); Phase 222 WR-222-03 + Gap 2 (F-27-14) |

**F-27-15 (IN-222-01 gate enhancement) NOT promoted:** Evaluated per D-08 criteria and determined it is a forward-looking gate enhancement proposal (extending `check-delegatecall-alignment.sh` to flag `OnlyGame()` direct delegatecalls) rather than a design-decision or accepted trade-off. Full detail is retained in `audit/FINDINGS-v27.0.md` for external auditors.

### MILESTONES.md insertion point

- **Insertion line:** line 2 (between the `# Milestones` header at line 1 and the pre-existing `## v26.0 Bonus Jackpot Split (Shipped: 2026-04-12)` entry which moved from line 3 to line 19 post-insert).
- **v27.0 entry first line (post-insert):** line 3 (`## v27.0 Call-Site Integrity Audit (Shipped: 2026-04-13)`).
- **v26.0 entry first line (post-insert):** line 19 (moved down 16 lines by the new v27.0 block).

### PROJECT.md section moves executed

- **Pre-edit Current Milestone v27.0 section:** lines 11-21 (header `## Current Milestone: v27.0 Call-Site Integrity Audit` + Goal paragraph + Target scope bulleted list + Prior incident context paragraph).
- **Post-edit:**
  - New `## Current Milestone: TBD — pending roadmap planning` block at line 11 (2 lines including the Status pointer).
  - New `## Completed Milestone: v27.0 Call-Site Integrity Audit` block starting at line 15, containing:
    - Status line: `**Status:** Complete (2026-04-13)`
    - `**Goal / Target scope / Incident context:**` label
    - Migrated Goal paragraph (verbatim from pre-edit line 13)
    - Migrated Target scope bulleted list (verbatim from pre-edit lines 15-19)
    - Migrated Prior incident context paragraph (verbatim from pre-edit line 21)
    - New Result block with concrete phase/plan/finding counts matching MILESTONES
  - Pre-existing `## Completed Milestone: v26.0 Bonus Jackpot Split` section unchanged, now at line 33 (pushed down by the new v27.0 completed block).

### Narrative-preservation record

**Pre-edit v27.0 Goal / Target scope / Incident context narrative** was migrated VERBATIM into the new `## Completed Milestone: v27.0` block under an explicit `**Goal / Target scope / Incident context:**` label. Zero substantive content dropped.

**Verification:**

- `grep -c 'Systematically surface runtime call-site-to-implementation mismatches' .planning/PROJECT.md` → `1` (Goal opening sentence present post-edit).
- `grep -cE '^- Delegatecall target alignment across all' .planning/PROJECT.md` → `1` (Target scope bullet 1 present).
- `grep -c 'mintPackedFor(address)..was declared' .planning/PROJECT.md` → `1` (Incident context opening sentence present).

Only the `## Current Milestone:` header line and the implicit "Started / Target" stub fields were replaced with the TBD header — no pre-edit substantive content was lost.

### CONTEXT D-09 reconciliation note

CONTEXT D-09 stated: *"Expected totals: 4 phases, 7 plans, ~15 tasks"*.

**Actuals used in MILESTONES (re-derived from plan PLAN.md task-tag counts and phase SUMMARY performance blocks):**

| Phase | Plans | Tasks (from `<task` tag count) |
|-------|-------|--------------------------------|
| 220 | 2 (220-01, 220-02) | 3 + 2 = 5 |
| 221 | 2 (221-01, 221-02) | 3 + 1 = 4 |
| 222 | 3 (222-01, 222-02, 222-03) | 3 + 5 + 3 = 11 |
| 223 | 2 (223-01, 223-02) | 1 + 2 = 3 |
| **Total** | **9** | **23** |

**Divergence cause:** CONTEXT D-09 predated Plan 222-03 (gap-closure plan added post-222-02 VERIFICATION). Task counts ran higher than the rough ~15 estimate because individual plans ranged from 1 to 5 tasks. This reconciliation is informational; the actuals in MILESTONES are authoritative.

### Count-wording verification

| File | `177+1 CRITICAL_GAP` | bare `178 CRITICAL_GAP` |
|------|----------------------|-------------------------|
| `.planning/MILESTONES.md` | 1 | 0 |
| `.planning/PROJECT.md` | 1 | 0 |

Both files use the `177+1 CRITICAL_GAP` expression exactly once (in their respective v27.0 retrospective blocks). The bare `178 CRITICAL_GAP` form appears in NEITHER file.

### FINDING_COUNT cross-validation

- `grep -c '^#### F-27-' audit/FINDINGS-v27.0.md` → **16** (F-27-01 through F-27-16).
- `grep -c '16 INFO findings' .planning/MILESTONES.md` → **1** (v27.0 retrospective bullet).
- `grep -c '16 INFO findings' .planning/PROJECT.md` → **1** (v27.0 Completed Milestone Result block).

MILESTONES and PROJECT agree on the F-27-NN finding count; both cite `16 INFO findings` matching the FINDINGS-v27.0.md header count.

### REQUIREMENTS.md checkbox flips

**CSI-NN items changed from `[ ]` to `[x]` by this plan:**

| ID | Section | Pre-edit | Post-edit |
|----|---------|----------|-----------|
| CSI-08 | Phase 222 | `[ ]` | `[x]` |
| CSI-09 | Phase 222 | `[ ]` | `[x]` |
| CSI-10 | Phase 222 | `[ ]` | `[x]` |
| CSI-12 | Phase 223 | `[ ]` (pre-edit state per plan read_first; actually already committed post-223-01 per git history — re-flipped here for final consistency) | `[x]` |
| CSI-13 | Phase 223 | `[ ]` | `[x]` |
| CSI-14 | Phase 223 | `[ ]` | `[x]` |

**Traceability table rows changed from `Pending` to `Complete`:** CSI-08, CSI-09, CSI-10, CSI-13, CSI-14 (CSI-12 was already flipped by Plan 223-01's 0110b44b commit).

**Final state:** 14 `[x] **CSI-**` / 0 `[ ] **CSI-**`; 14 `| Complete |` / 0 `| Pending |`.

## Decisions Made

- **3 KNOWN-ISSUES entries (not 1, not 4):** F-27-12 and F-27-05 are both strong individual candidates with substantive external-auditor value (one deploy-tooling robustness, one pre-existing parallel-make footgun). The F-27-13 + F-27-14 combined entry captures the VERIFICATION gap-closure historical record in summary form, pointing readers to FINDINGS-v27.0.md for full detail. F-27-15 was evaluated and deferred because it is a forward-looking gate enhancement suggestion rather than a design-decision.
- **Preserve (don't rewrite) the Goal/Target-scope/Incident-context narrative in PROJECT.md.** The plan required migration rather than regeneration. All three narrative pieces were copied verbatim from the pre-edit Current Milestone block into the new Completed Milestone block under an explicit label.
- **Combined F-27-13 and F-27-14 into a single KNOWN-ISSUES entry (option c in the plan).** External readers benefit from seeing both gap closures together (same cycle, same Plan 222-03, shared context) rather than in two separate entries.
- **Per-file `git add -f` for .planning/*.md.** `gsd-tools commit` returned `skipped_gitignored` because the parent `.planning/` directory is gitignored. The four target files ARE tracked (`git ls-files` confirms), so the correct handoff is `git add -f <specific file>` rather than the gsd-tools wrapper or `-f` on directory globs.

## Deviations from Plan

None — plan executed exactly as written.

The `gsd-tools commit` tool returning `skipped_gitignored` required a fallback to `git add -f` + standard `git commit`, but this is an established pattern used by Plan 223-01's final metadata commit (`0110b44b`) and earlier `.planning/` commits throughout the repository. Not a deviation — the plan only specified content requirements, not the exact commit-tool invocation.

## Issues Encountered

- **`.planning/` is gitignored but its contents are tracked.** First `git add .planning/MILESTONES.md ...` invocation failed with `The following paths are ignored by one of your .gitignore files`. Resolved by using `git add -f`. Pattern confirmed via `git ls-files` + history of prior `.planning/*.md` commits (e.g., commit `0110b44b` for Plan 223-01).

## Next Phase Readiness

- **v27.0 Call-Site Integrity Audit is SHIPPED.** All 4/4 ROADMAP success criteria met, all 14/14 CSI-NN requirements Complete, all 4 phase verifications passed (220 9/9, 221 13/13, 222 4/4 after Plan 222-03 gap closure, 223 2/2 plans).
- **Future cycle planning is unblocked.** `.planning/PROJECT.md` points future discussions at `.planning/ROADMAP.md` as the intake point for the next milestone. No outstanding blockers from v27.0 work.
- **Handoff artifacts:** `audit/FINDINGS-v27.0.md` (16 F-27-NN INFO findings + v25.0 regression appendix), updated `KNOWN-ISSUES.md` (37 bolded entries, 3 new v27.0 design decisions), v27.0 retrospective in `.planning/MILESTONES.md` (7 accomplishments bullets), and `.planning/PROJECT.md` Completed Milestone block with narrative preserved.
- **Audit-trail continuity:** Every WR-* / IN-* / Gap item from the three source phases (220/221/222) is now traceable through F-27-NN in FINDINGS-v27.0.md; KNOWN-ISSUES.md entries point readers at the three most externally-relevant items (F-27-05, F-27-12, F-27-13 + F-27-14).

## Self-Check: PASSED

Claim verification after SUMMARY authoring:

- `.planning/phases/223-findings-consolidation/223-02-SUMMARY.md` exists (verified via `[ -f ... ]`).
- Task 1 commit `3d798794` exists in `git log --oneline --all`.
- Task 2 commit `5408f745` exists in `git log --oneline --all`.
- Final metadata commit `7f8cff7d` exists in `git log --oneline --all`.
- All 4 target files exist and are tracked: `KNOWN-ISSUES.md`, `.planning/MILESTONES.md`, `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`.
- STATE.md `completed_plans: 9`, `percent: 100`, Stopped-at set to Plan 223-02 completion.
- ROADMAP Phase 223 row: `2/2 | Complete | 2026-04-13` with `[x]` flag.
- REQUIREMENTS.md: CSI-13 and CSI-14 both show `[x]` checkboxes and traceability row `Complete`.
- Sibling Makefile gates (`make check-interfaces`, `make check-delegatecall`, `make check-raw-selectors`) all exit 0 on this tree.
- `audit/FINDINGS-v27.0.md` byte-unchanged (`git diff HEAD~3..HEAD audit/FINDINGS-v27.0.md` returns empty).
- No contracts/ edits this plan (`git diff --name-only HEAD~3..HEAD contracts/` returns empty).
- No test/ edits this plan (the three pre-existing dirty files — `DeployCanary.t.sol`, `DeployProtocol.sol`, `deployFixture.js` — are documented in STATE.md blockers and were not staged or modified by this plan).
- Cross-file consistency passes: MILESTONES and PROJECT both cite `16 INFO findings` and `177+1 CRITICAL_GAP`; bare `178 CRITICAL_GAP` absent from both.

---
*Phase: 223-findings-consolidation*
*Completed: 2026-04-13*
