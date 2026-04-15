# Phase 228 Context: Cursor, Reorg & View Refresh State Machines

**Milestone:** v28.0 Database & API Intent Alignment Audit
**Phase number:** 228
**Phase name:** Cursor, Reorg & View Refresh State Machines
**Requirements:** IDX-04, IDX-05
**Depends on:** Phase 227 (event-processor correctness locked; state-machine audit can assume handler correctness)
**Date:** 2026-04-15

## Phase Boundary

**In scope:**

- **IDX-04** — `cursor-manager.ts` + `reorg-detector.ts` behave as documented. State transitions: `advance`, `gap`, `reorg-detect`, `recovery-after-stall`. Block-ordering guarantees, maximum reorg depth, stall-recovery semantics, cursor-rewind guardrails.
- **IDX-05** — `view-refresh.ts` triggers match the staleness model documented in both the file's own comments AND the schema view definitions (`database/src/db/schema/views.ts`). Debounce, failure handling, staleness bounds, trigger conditions.
- **Absorb 4 Phase 227 deferrals** (D-227-10 handoff): cursor rewind guardrails (cursor-manager.ts:45), reorg overwrite ordering (reorg-detector.ts:33), refresh-failure alerting policy (view-refresh.ts:5), backfill-gate boundary `<=` vs `<` (main.ts:211).

**Explicitly NOT in scope:**

- Event-processor correctness (Phase 227, locked).
- Schema structural correctness (Phase 226, locked).
- Performance / latency / throughput audit of the state machines.
- Alternative state-machine architecture proposals — this is an AUDIT phase, not a redesign.
- Runtime replay / simulation harness — out of milestone scope.

## Inherited Decisions

- **D-228-01 (inherits D-227-01):** Cross-repo READ-only. Reads target `/home/zak/Dev/PurgeGame/database/`. Zero writes there. Artifacts live in `.planning/phases/228-cursor-reorg-view-refresh-state-machines/`.
- **D-228-02 (inherits D-227-02):** Catalog-only. No runtime gate, no CI.
- **D-228-03 (inherits D-225-04):** Tier A/B comment-drift threshold applies when findings are comment-side. IDX-04/05 findings also include behavior-side findings (documented invariant violated) which use INFO / LOW / MEDIUM severity.
- **D-228-04 (inherits D-226-09):** Finding IDs `F-28-228-NN` fresh counter from 01. Phase 229 consolidates.
- **D-228-05 (inherits D-226-05):** Direction defaults — `comment→code` for comment drift; `docs→code` for state-machine invariant violations against ROADMAP/REQUIREMENTS claims; `schema↔view` for view-definition drift.

## Decisions (this phase)

### D-228-06: Two plans mirroring the two requirements

| Plan | Requirement | Deliverable |
|---|---|---|
| 228-01 | IDX-04 | `228-01-CURSOR-REORG-TRACE.md` — per-state-transition PASS/FAIL for cursor-manager.ts + reorg-detector.ts; absorbs 227 deferrals #1, #2, #4 |
| 228-02 | IDX-05 | `228-02-VIEW-REFRESH-AUDIT.md` — per-trigger staleness-model verdict (view-refresh.ts ↔ comments ↔ schema views.ts); absorbs 227 deferral #3 |

### D-228-07: State-machine trace depth — enumerate every transition

For IDX-04, enumerate every state transition observable in the code (advance, gap, reorg-detect, recovery-after-stall, cursor-rewind, block-overwrite path, etc.) with an explicit PASS/FAIL verdict. Do NOT limit to documented invariants — documented AND undocumented transitions both appear in the trace; undocumented transitions produce `docs→code` gap findings.

### D-228-08: View staleness cross-reference source

IDX-05 compares `view-refresh.ts` against TWO sources, both required:

1. In-source comments inside `view-refresh.ts` AND referring files in `database/src/indexer/*.ts`.
2. Schema view definitions in `/home/zak/Dev/PurgeGame/database/src/db/schema/views.ts`.

Downstream API consumers are OUT OF SCOPE (Phase 224 already audited API routes; if a consumer mismatch is obvious it may be noted as INFO context, not a standalone 228 finding).

### D-228-09: Absorb 227 deferrals into 228 plans

The 4 deferrals from `227-03-SUMMARY.md` Phase 228 Handoff section are each assigned a specific 228 plan:

| # | 227 deferral | Assigned to |
|---|---|---|
| 1 | `cursor-manager.ts:45` — `initializeCursor` rewind guardrail | 228-01 (IDX-04 cursor advance/init state) |
| 2 | `reorg-detector.ts:33` — `storeBlock` ON CONFLICT ordering | 228-01 (IDX-04 reorg-detect state) |
| 3 | `view-refresh.ts:5` — refresh-failure alerting policy | 228-02 (IDX-05 failure-handling semantics) |
| 4 | `main.ts:211` — backfill gate `<=` boundary | 228-01 (IDX-04 recovery-after-stall state; backfill-to-tip is a recovery transition) |

Each deferral becomes a pre-assigned audit row in its plan's deliverable — NOT a pre-assigned finding ID (finding emission depends on the verdict). If the behavior is verified correct, the row is PASS with rationale; if not, emit a finding in the plan's reserved block.

### D-228-10: Finding ID reservation blocks

- 228-01 (IDX-04): `F-28-228-01` onward.
- 228-02 (IDX-05): `F-28-228-101` onward (reserved for parallel-Wave-2 safety).

### D-228-11: Severity taxonomy for behavioral findings

| Severity | Threshold |
|---|---|
| INFO | Documented behavior matches; minor comment drift (Tier B equivalent). |
| LOW | Behavior diverges from comment but no data integrity risk. |
| MEDIUM | Behavior diverges in a way that could cause silent data corruption or missed reorg recovery. |

HIGH/CRITICAL reserved for Phase 229 promotion if cross-phase analysis elevates them.

### Claude's Discretion

- Wave structure — recommended 228-01 + 228-02 both Wave 1 (independent, cursor/reorg and view-refresh touch different code). If researcher finds coupling, planner may sequence them.
- Exact state-transition enumeration strategy (control-flow trace, comment-first, invariant-first).
- Whether to introduce a third plan for the "all 9 indexer files audit-touched" SC-4 coverage sweep, or satisfy it via 228-01/02 coverage check — default: satisfy via the existing two plans' file-touch evidence.

## Canonical References

### Upstream audit context

- `.planning/ROADMAP.md` § Phase 228 (4 success criteria)
- `.planning/REQUIREMENTS.md` § IDX-04..05
- `.planning/phases/227-indexer-event-processing-correctness/227-CONTEXT.md` (D-227-01..11 — inherited patterns)
- `.planning/phases/227-indexer-event-processing-correctness/227-03-SUMMARY.md` § "Phase 228 Handoff" (4 deferrals with file:line + suggested angle)
- `.planning/phases/227-indexer-event-processing-correctness/227-03-INDEXER-COMMENT-AUDIT.md` (full comment-claim catalog — context for behavioral verification)
- `.planning/phases/226-schema-migration-orphan-audit/226-01-SCHEMA-MIGRATION-DIFF.md` (schema model — views.ts in scope)

### Audit targets

- `/home/zak/Dev/PurgeGame/database/src/indexer/cursor-manager.ts` — IDX-04 primary
- `/home/zak/Dev/PurgeGame/database/src/indexer/reorg-detector.ts` — IDX-04 primary
- `/home/zak/Dev/PurgeGame/database/src/indexer/view-refresh.ts` — IDX-05 primary
- `/home/zak/Dev/PurgeGame/database/src/indexer/main.ts` — orchestrator, calls into all three
- `/home/zak/Dev/PurgeGame/database/src/indexer/block-fetcher.ts` — upstream of cursor advance
- `/home/zak/Dev/PurgeGame/database/src/indexer/purge-block-range.ts` — reorg rollback executor
- `/home/zak/Dev/PurgeGame/database/src/indexer/event-processor.ts` — referenced for cursor-advance correctness
- `/home/zak/Dev/PurgeGame/database/src/db/schema/views.ts` — view staleness model (IDX-05)

## Existing Code Insights

### Reusable Assets

- Catalog markdown format + finding-stub header (from 225/226/227).
- 227-03 already audited view-refresh.ts comments — reuse its seed claims where behavioral check is the next step.
- 226-04 confirmed `views.ts` has 4 pgMaterializedView entries — these are IDX-05's target.

### Established Patterns

- Catalog-only; cross-repo READ-only; Tier A/B comment + LOW/MEDIUM behavioral severity; reserved-block finding IDs; plans-mirror-requirements.

### Integration Points

- **Phase 227 (upstream)** — comment-claim catalog is the starting point; behavioral audit extends it.
- **Phase 229** — consolidates `F-28-228-NN` into `F-28-NN` flat namespace; closes the milestone.

## Specific Ideas

- **`reorg-detector.ts:33` storeBlock ON CONFLICT** (227 deferral #2) — key behavioral question: does the rollback happen BEFORE any storeBlock call that would overwrite a canonical record? Needs control-flow trace from `main.ts` through `reorg-detector.handleReorg` → `purge-block-range` → subsequent `storeBlock`.
- **`view-refresh.ts:5` swallowed errors** (227 deferral #3) — staleness policy: is there any observability (metric, alert, gauge) beyond log.error? If none, that's a LOW INFO finding documenting the operational gap.
- **`main.ts:211` backfill gate `<=`** (227 deferral #4) — concrete numerical boundary check: construct the edge-case `(cursor, tip)` and trace whether `<=` or `<` is intended.
- **4 pgMaterializedViews in views.ts** (from 226-04 scan) — each must have at least one refresh trigger in view-refresh.ts, or be justified as read-on-demand.

## Deferred Ideas

- Runtime state-machine simulation / property tests — future milestone.
- Alternative reorg-depth / backfill-batch-size tuning recommendations — out of audit scope.
- Observability / alerting build-out for swallowed refresh errors — fix proposal, not an audit finding. Document as an INFO finding with `Resolution: RESOLVED-CODE-FUTURE` and let downstream triage decide.

---

*Phase: 228-cursor-reorg-view-refresh-state-machines*
*Context gathered: 2026-04-15 (user selected "absorb 227 deferrals"; all other defaults inherited from 224/225/226/227)*
