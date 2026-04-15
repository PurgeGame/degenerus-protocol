# Phase 229 Context: Findings Consolidation

**Milestone:** v28.0 Database & API Intent Alignment Audit (finale)
**Phase number:** 229
**Phase name:** Findings Consolidation
**Requirements:** FIND-01, FIND-02, FIND-03
**Depends on:** Phases 224, 225, 226, 227, 228 (all complete)
**Date:** 2026-04-15

## Phase Boundary

**In scope:**

- **FIND-01** — Consolidate every finding from Phases 224–228 into `audit/FINDINGS-v28.0.md` with severity (HIGH/MEDIUM/LOW/INFO), direction label, source reference.
- **FIND-02** — Each finding traceable to originating phase + specific `database/` (or `contracts/` event + `database/src/db/schema/` pair) file:line.
- **FIND-03** — Every finding has a resolution status: `RESOLVED-DOC` / `RESOLVED-CODE` / `DEFERRED` / `INFO-ACCEPTED` with a one-sentence rationale.
- Sync tracking docs: `PROJECT.md` (move v28.0 Current → Completed), `MILESTONES.md` (retrospective entry in v25/v26/v27 format), `REQUIREMENTS.md` (flip traceability `[x]` for every satisfied REQ-ID).

**Explicitly NOT in scope (user directive — this milestone):**

- **DO NOT touch `audit/KNOWN-ISSUES.md`** — per user: "don't change any known issues here this is just docs testing my sim not the contracts". v28.0 audits the simulation/database/indexer layer against contracts, not the contracts themselves. KNOWN-ISSUES.md tracks contract-side items and remains untouched.
- No code changes to contracts/ or test/ (standing policy).
- No resolution actions (patches, fixes) inside the database/ repo — findings are documented; resolution outside v28.0 scope. Where a v28 plan committed a fix in-cycle to its own artifacts (.planning/), the finding is `RESOLVED-DOC` or `INFO-ACCEPTED` as appropriate.
- No re-audit of prior phases.

## Inherited Decisions

- **D-229-01:** Consolidation target is `audit/FINDINGS-v28.0.md` — same structure as `audit/FINDINGS-v27.0.md` (Executive Summary table, per-phase sections, per-finding tables with Severity/Source/Contract-or-File/Function fields, severity-justification paragraph).
- **D-229-02:** This phase writes to the audit repo itself (NOT cross-repo READ-only). Writes allowed: `audit/FINDINGS-v28.0.md` (new), `.planning/PROJECT.md`, `.planning/MILESTONES.md`, `.planning/REQUIREMENTS.md`. All other directories remain READ-only per project policy.
- **D-229-03:** Finding ID scheme — flatten per-phase `F-28-227-NN` into canonical `F-28-NN` numbering. Ordering: Phase 224 first, then 225, 226, 227, 228 — stable within-phase order preserved from each phase's deliverable.

## Decisions (this phase)

### D-229-04: Two plans mirroring the two consolidation axes

| Plan | Scope | Deliverable |
|---|---|---|
| 229-01 | FINDINGS consolidation | `audit/FINDINGS-v28.0.md` (new) + consolidation notes in `.planning/phases/229-findings-consolidation/229-01-CONSOLIDATION-NOTES.md` |
| 229-02 | Tracking sync | Updates to `.planning/PROJECT.md`, `.planning/MILESTONES.md`, `.planning/REQUIREMENTS.md` + SUMMARY documenting the delta |

Matches Phase 217 + Phase 223 precedent.

### D-229-05: Severity preservation + promotion policy

- **Preserve severity** assigned by originating phase unless cross-phase analysis reveals amplification.
- **Promotion to HIGH** only if a cross-phase pattern shows material production risk (e.g., a 227 silent-truncation bug combined with a 226 schema mismatch on the same column would amplify; a standalone LOW stays LOW).
- **No retroactive downgrade** — if a phase said LOW, consolidator cannot promote to INFO without explicit rationale.
- Expected severity counts (from phase SUMMARYs):
  - 224: TBD (single-plan phase; count from 224-SUMMARY + 224-REVIEW)
  - 225: 22 findings (F-28-225-01..22 per STATE.md)
  - 226: 10 findings (F-28-226-01..10)
  - 227: 31 findings (F-28-227-01..23 + 101..106 + 201..202)
  - 228: 5 findings (F-28-228-01..04 + 101)
  - **Projected total:** ~68 findings + 224's count; final number confirmed during consolidation.

### D-229-06: Direction label taxonomy (explicit)

| Direction | Meaning | Common in |
|---|---|---|
| `docs→code` | Documented behavior (ROADMAP / REQUIREMENTS / spec) diverges from code | 224 API alignment |
| `code→docs` | Code behavior not reflected in docs | rare |
| `comment→code` | In-source comment diverges from actual code behavior | 225, 227-03, 228 |
| `schema↔migration` | Drizzle schema TS ↔ SQL migration drift | 226 |
| `schema↔handler` | Event arg-to-field mapping drift | 227-02 |
| `code↔schema` | Orphan / missing-in-schema | 226-04 |

Findings with ambiguous direction get an explanatory note in the consolidation entry.

### D-229-07: Resolution status policy

- **RESOLVED-DOC:** finding addressed by updating documentation / comments / planning artifacts within v28.0 (no code change).
- **RESOLVED-CODE:** finding addressed by a code change (in the audit-target repo, whether applied during v28 or clearly queued for immediate fix). For v28 most findings are `DEFERRED` since v28 is catalog-only across 224-228.
- **DEFERRED:** no action this milestone; must name a target milestone (or explicit "future backlog").
- **INFO-ACCEPTED:** intentional design; no action needed. Promotion to `KNOWN-ISSUES.md` **disabled this milestone** per user directive — INFO-ACCEPTED items live only in FINDINGS-v28.0.md.

### D-229-08: MILESTONES.md retrospective shape

Follow `MILESTONES.md` v25.0/v26.0/v27.0 format:
- Milestone header (v28.0 name, dates, phase count, total findings by severity)
- Per-phase one-paragraph summary with finding count
- Key takeaways / methodology notes
- Link to `audit/FINDINGS-v28.0.md`

### D-229-09: REQUIREMENTS.md traceability flip

For each REQ-ID satisfied by a verified phase, flip `[ ] **REQ-XX**` → `[x] **REQ-XX**` in REQUIREMENTS.md. The right edge of REQUIREMENTS.md contains a status table — update status column to `Satisfied (Phase NNN)`.

REQ-IDs to flip:
- 224: API-01..04 (check 224 verdict for exact list)
- 225: API-05..08 (per STATE.md)
- 226: SCHEMA-01..04
- 227: IDX-01..03
- 228: IDX-04, IDX-05
- 229 itself: FIND-01..03 (flipped on completion by Phase 229's own verify step)

### D-229-10: KNOWN-ISSUES.md untouched (user directive)

Per user: "don't change any known issues here this is just docs testing my sim not the contracts". v28.0 audits the sim/database/indexer layer against contracts; KNOWN-ISSUES.md is a contract-side registry and remains unmodified. Deferred items stay in `FINDINGS-v28.0.md` under their original status — NOT promoted to KNOWN-ISSUES.

### Claude's Discretion

- Wave structure — recommended 229-01 (FINDINGS) Wave 1 → 229-02 (tracking sync) Wave 2 (depends on finalized finding counts for MILESTONES retrospective).
- Exact format of `229-01-CONSOLIDATION-NOTES.md` (planning-side record of the build).
- Whether to group per-phase sections by severity descending or preserve phase order (default: phase order per v27 precedent).

## Canonical References

### Upstream inputs (per-phase deliverables)

- **Phase 224:** `.planning/phases/224-api-route-openapi-alignment/*` — single-plan phase; 224 SUMMARY + any REVIEW.
- **Phase 225:** `.planning/phases/225-api-handler-behavior-validation-schema-alignment/225-0N-SUMMARY.md` (4 plans; 22 findings F-28-225-01..22).
- **Phase 226:** `.planning/phases/226-schema-migration-orphan-audit/226-0N-*.md` (4 plans; 10 findings F-28-226-01..10).
- **Phase 227:** `.planning/phases/227-indexer-event-processing-correctness/227-0N-*.md` (3 plans; 31 findings F-28-227-01..23, 101..106, 201..202).
- **Phase 228:** `.planning/phases/228-cursor-reorg-view-refresh-state-machines/228-0N-*.md` (2 plans; 5 findings F-28-228-01..04, 101).

### Structural precedent

- `audit/FINDINGS-v27.0.md` — structure to mirror (executive summary table, per-phase sections, per-finding table format).
- `audit/FINDINGS-v25.0.md` — older precedent.
- `.planning/MILESTONES.md` — retrospective format.
- `.planning/phases/223-*` (Phase 223 v27.0 consolidation) — most recent consolidation-phase precedent.
- `.planning/phases/217-*` (Phase 217 v25.0 consolidation) — older consolidation-phase precedent.

### Writable targets

- `audit/FINDINGS-v28.0.md` (new)
- `.planning/PROJECT.md`
- `.planning/MILESTONES.md`
- `.planning/REQUIREMENTS.md`
- `.planning/phases/229-findings-consolidation/229-*.md` (own plan artifacts)

## Existing Code Insights

### Reusable Assets

- v27.0 consolidation structure — reuse exactly.
- Per-phase SUMMARY.md files contain finding lists, counts, resolutions in the exact shape needed for consolidation.
- STATE.md already tracks per-phase last_activity including finding counts.

### Integration Points

- No code integration — documentation-only phase.
- Phase 230+ (future milestone) reads `FINDINGS-v28.0.md` to drive any in-code remediation.

## Specific Ideas

- Executive summary table should surface MEDIUM cap across v28 — 228's reorg edge case + 227-02's silent-truncation candidates are the most elevated severities this milestone.
- 227's inverse orphan (`AutoRebuyProcessed` registry key with no event declaration) is a notable finding that deserves explicit callout in the retrospective — pattern worth carrying into future milestones.
- 228 absorbed 4 Phase 227 deferrals and resolved them — demonstrate the scope-guard pattern (D-227-10) worked and note in retrospective.

## Deferred Ideas

- **KNOWN-ISSUES.md promotion** — DEFERRED per user directive (this milestone only; future milestones may revisit).
- **In-code remediation of v28 findings** — future milestone; v28 is a catalog audit + consolidation, not a fix cycle.
- **Cross-milestone trend analysis** (e.g., comment-drift rate across v25–v28) — nice-to-have; not required by FIND-01..03.

---

*Phase: 229-findings-consolidation*
*Context gathered: 2026-04-15 — user scoped out KNOWN-ISSUES.md per explicit directive; all other defaults inherited from 217/223 consolidation precedent*
