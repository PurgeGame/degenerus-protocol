# Phase 227 Context: Indexer Event Processing Correctness

**Milestone:** v28.0 Database & API Intent Alignment Audit
**Phase number:** 227
**Phase name:** Indexer Event Processing Correctness
**Requirements:** IDX-01, IDX-02, IDX-03
**Depends on:** Phase 226 (schema baseline locked)
**Date:** 2026-04-15

## Phase Boundary

**In scope:**

- **IDX-01** — Every event emitted by `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/*.sol` that the indexer claims to process has a registered case in `/home/zak/Dev/PurgeGame/database/src/indexer/event-processor.ts` (or an explicit delegation to a named handler in `/home/zak/Dev/PurgeGame/database/src/handlers/*.ts`). Intentionally skipped events must have a comment-justified rationale.
- **IDX-02** — Each case handler maps event args → schema fields correctly: field name, type, AND coercion semantics (`uint256` → `numeric`, `bytes32` → `text`, `address` → `text`, etc.). Uses the schema model locked by Phase 226 as ground truth.
- **IDX-03** — Indexer comments claiming idempotency, reorg safety, backfill behavior, or view-refresh trigger semantics match the actual code behavior in `event-processor.ts` and delegated handler files.

**Explicitly NOT in scope:**

- **IDX-04 / IDX-05** (cursor/reorg/view-refresh state machines) — Phase 228.
- **View-refresh behavior/trigger firing** — Phase 228. Phase 227 audits only COMMENT correctness of view-refresh claims in indexer code, not the state machine itself.
- Re-audit of schema column semantics — relies on Phase 226's locked baseline.
- Event volume / performance — out of milestone scope.
- Contract-side event correctness (whether the contract SHOULD emit that event) — Phase 220/221/222/223 territory, already audited.

## Inherited Decisions (from Phases 224/225/226)

All of the following are inherited patterns — re-stated here to feed the planner directly:

- **D-227-01 (inherits D-225-07 / D-226-08):** Cross-repo READ-only. All reads target `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/` and `/home/zak/Dev/PurgeGame/database/`. Zero writes to either. Planning artifacts and findings live in `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/phases/227-indexer-event-processing-correctness/`.
- **D-227-02 (inherits D-224-01 / D-226-10):** Catalog-only. No runtime gate, no CI, no code changes to the audit targets. Deliverables are catalog markdown + per-plan SUMMARY.md.
- **D-227-03 (inherits D-225-04 / D-226-04):** Tier A/B threshold for comment-drift findings in IDX-03. Skip Tier C (missing comments — counted, not enumerated) and Tier D (cosmetic).
- **D-227-04 (inherits D-225-06 / D-226-09):** Finding IDs `F-28-227-NN` with fresh counter from `01`. Phase 229 consolidates into the flat `F-28-NN` namespace.
- **D-227-05 (inherits D-226-05):** Default finding direction `schema↔handler` (milestone's indexer-mismatch direction); IDX-03 comment-drift uses `comment→code`. Resolution defaults to RESOLVED-CODE unless the finding is an accepted design (INFO-ACCEPTED).

## Decisions (this phase)

### D-227-06: Three plans mirroring the three requirements

| Plan | Requirement | Deliverable |
|---|---|---|
| 227-01 | IDX-01 | `227-01-EVENT-COVERAGE-MATRIX.md` — per-event classification: PROCESSED / DELEGATED / INTENTIONALLY-SKIPPED / UNHANDLED |
| 227-02 | IDX-02 | `227-02-EVENT-ARG-MAPPING.md` — per-case arg→field PASS/FAIL with name + type + coercion verdict |
| 227-03 | IDX-03 | `227-03-INDEXER-COMMENT-AUDIT.md` — Tier A/B comment drift in indexer + delegated handlers |

Same shape as Phases 224 (1 plan / 1 req because ROADMAP mapped 1 req), 225 (4 plans / 4 reqs), 226 (4 plans / 4 reqs).

### D-227-07: Event enumeration source — regex-parse contracts/*.sol directly

Build the authoritative event list by regex-grepping `event FooBar(...);` declarations from `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/*.sol` (17 contracts). Do not depend on compiled ABI JSON (may be stale / gitignored / absent). Do not depend on typegen. Pure-file audit, zero tooling.

- **Scope of contracts:** every `contracts/*.sol` file. No test/mock filtering — if a file is in `contracts/`, its events are in scope.
- **Inherited interfaces / libraries:** events declared in library or base-contract files that another contract inherits count as emittable events of the inheriting contract. Planner decides whether to flatten.

### D-227-08: Delegated-handler classification rule (IDX-01)

A case in `event-processor.ts` counts as valid coverage if it either:
1. Calls into a named function inside `/home/zak/Dev/PurgeGame/database/src/handlers/*.ts`, OR
2. Processes the event inline with schema writes in the case body itself.

Missing case in `event-processor.ts` = UNHANDLED (finding candidate). An `INTENTIONALLY-SKIPPED` classification requires a comment at the case site (or within 3 lines of where the case would sit) explaining why — absence of comment promotes it to UNHANDLED.

### D-227-09: Arg-to-field verdict depth (IDX-02)

Per-case verdict covers three dimensions, all must PASS:

1. **Field-name correctness** — event arg `tokenId` writes to schema column `token_id` (or explicit camel↔snake equivalent).
2. **Type correctness** — event arg Solidity type maps to expected Drizzle/Postgres type (uint256↔numeric/bigint, address↔text, bytes32↔text, bool↔boolean, etc.).
3. **Coercion correctness** — no silent truncation (e.g., `uint256` → JS `number` without BigInt handling), no field-swap (e.g., `from` written to `to_address`), no loss of precision.

Uses Phase 226's locked schema model as the authoritative target-column shape.

### D-227-10: Scope boundary vs Phase 228

Phase 227 audits view-refresh behavior **only as comment-drift under IDX-03**. If an indexer comment claims "refreshes view X after insert" and the code does not, that is an IDX-03 finding here. Whether the refresh ITSELF is correct (debounce, cursor alignment, reorg behavior) is Phase 228 territory and must not be expanded into a 227 finding.

### D-227-11: Finding-ID reservation blocks (parallel-Wave-2 safety)

Mirror Phase 226 scheme to prevent collision if plans 227-02 and 227-03 run in parallel:

- 227-01 consumes `F-28-227-01` onward.
- 227-02 reserves `F-28-227-101+` block.
- 227-03 reserves `F-28-227-201+` block.

Planner confirms reserved-block starting numbers; the counts may shift if 227-01 exceeds ~90 findings (unlikely).

### Claude's Discretion

- Wave structure (likely Wave 1 = 227-01 event-enumeration → builds universe for 227-02; Wave 2 = 227-02 + 227-03 in parallel).
- Exact regex patterns for event extraction; inherited-event flattening strategy.
- Whether to split IDX-02 into sub-tables per contract or single flat table.
- Severity thresholds for IDX-02 findings (default INFO; LOW if the mismatch would cause indexer to silently corrupt data).

## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Upstream audit context (this milestone)

- `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/ROADMAP.md` § Phase 227 — goal + 4 success criteria
- `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/REQUIREMENTS.md` § IDX-01..03
- `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/phases/226-schema-migration-orphan-audit/226-01-SCHEMA-MIGRATION-DIFF.md` — locked schema model (Phase 226)
- `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/phases/226-schema-migration-orphan-audit/226-CONTEXT.md` — inherited decisions D-226-04..10
- `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/phases/225-api-handler-behavior-validation-schema-alignment/225-CONTEXT.md` — Tier A/B threshold (D-225-04), finding-ID conventions

### Audit targets

- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/*.sol` — 17 contracts; primary event-declaration source (D-227-07)
- `/home/zak/Dev/PurgeGame/database/src/indexer/event-processor.ts` — registered case site for all processed events
- `/home/zak/Dev/PurgeGame/database/src/indexer/*.ts` — additional indexer core (`main.ts`, `block-fetcher.ts`, `cursor-manager.ts`, `reorg-detector.ts`, `view-refresh.ts`, `trait-derivation.ts`, `purge-block-range.ts`) for IDX-03 comment sweep
- `/home/zak/Dev/PurgeGame/database/src/handlers/*.ts` — 27 delegated handler files (e.g., `coinflip.ts`, `jackpot.ts`, `quests.ts`, `traits-generated.ts`, …)
- `/home/zak/Dev/PurgeGame/database/src/db/schema/*.ts` — schema target columns (referenced through Phase 226's locked model, not re-parsed)

## Existing Code Insights

### Reusable Assets

- **Catalog markdown format** — per-row tables + finding-stub blocks; re-use exactly from 225/226.
- **Finding-stub header** — `#### F-28-227-NN: {title}` + `- **Severity:**`, `- **Direction:**`, `- **Phase:**`, `- **File:**`, `- **Resolution:**`.
- **Phase 226 schema model** — consumed as-is for IDX-02 arg→field verdicts; do not re-derive.

### Established Patterns

- Catalog-only audit; no runtime gate; cross-repo READ-only; reserved-block finding IDs.
- Plans mirror requirements 1:1; parallel Wave 2 for independent plans.
- Tier A/B comment threshold (D-225-04).

### Integration Points

- **Phase 226** (upstream) — IDX-02 assumes Phase 226's schema model is authoritative.
- **Phase 228** — consumes 227's event-coverage matrix; adds refresh-trigger behavior on top.
- **Phase 229** — consolidates `F-28-227-NN` into `F-28-NN` flat namespace.

## Specific Ideas

- **Inherited interfaces / base contracts** — `DegenerusGame` likely inherits from common base + interfaces; flattening strategy must capture events declared in bases.
- **`new-events.ts` handler** — suggests a late-addition event batch; natural place to look for IDX-01 coverage gaps.
- **`view-refresh.ts` in indexer/** — if comments there claim behavior, those lines are IDX-03 candidates (comment-only — refresh mechanics stay 228).
- **Pre-assigned finding (optional):** if scouting during research confirms a specific event with zero coverage, planner may pre-assign `F-28-227-01` similar to how D-226-06 reserved F-28-226-01 for the 0007 snapshot anomaly.

## Deferred Ideas

- **IDX-04 / IDX-05 state-machine correctness** — Phase 228.
- **Runtime event-replay test harness** — future milestone; catalog audit is sufficient for v28.0.
- **Contract-side event-emission correctness** — already audited in prior milestones (v22–v27).
- **Indexer performance / latency audit** — out of milestone scope.

---

*Phase: 227-indexer-event-processing-correctness*
*Context gathered: 2026-04-15 (defaults inherited from 224/225/226; no open gray areas per user)*
