# Phase 226: Schema, Migration & Orphan Audit — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-15
**Phase:** 226-schema-migration-orphan-audit
**Areas discussed:** Comparison method (selected); Plan structure, Orphan scan scope, 0007/views handling (not selected — Claude's Discretion per user deferral)

---

## Gray Area Selection

| Option | Description | Selected |
|---|---|---|
| Comparison method | Applied-state baseline source — drizzle-kit introspect vs meta snapshots vs manual | ✓ |
| Plan structure | 4 plans vs bundled 2-3 plans | |
| Orphan scan scope | Directions + code surfaces covered | |
| 0007 anomaly + views handling | Own finding + SCHEMA-05 boundary | |

**User's choice:** Comparison method only.

---

## Comparison Method

| Option | Description | Selected |
|---|---|---|
| Cumulative .sql migrations | Parse drizzle/0000..0007.sql in order, fold into logical state, diff against .ts. Zero tooling; closest to prod. | |
| drizzle/meta snapshot JSON | Use drizzle/meta/0006_snapshot.json as applied-state model. Faster to parse but lags for 0007 bypass. | |
| Live Postgres + introspect | Spin up throwaway Postgres, apply migrations, drizzle-kit introspect, diff. Most authoritative; requires infra. | |
| Hybrid .sql + meta cross-check | Cumulative .sql as primary + drizzle/meta as cross-check. Disagreements become findings. | ✓ (Claude-picked) |

**User's response:** "I really dont know what any of this is can you just figure it out?" (Claude's Discretion granted)

**Notes:** User deferred the methodology call entirely. Claude selected Hybrid (option D) because:
1. `.sql` is the authoritative source — it's what actually ran against Postgres.
2. `drizzle/meta/*.json` snapshots provide a cheap secondary cross-check — they are drizzle-kit's own record of what state each migration should have produced.
3. The already-confirmed `0007` anomaly (SQL exists without matching snapshot) proves the two sources can diverge, so cross-checking them produces real findings rather than redundant work.
4. Hybrid stays inside the cross-repo READ-only constraint (D-225-07) — no DB spin-up, no `drizzle-kit introspect` infrastructure.
5. Pure-file audit aligns with the catalog-only precedent from Phases 224/225.

---

## Claude's Discretion (areas user did not request to discuss)

Per the user's deferral pattern, the following decisions were made using 224/225 precedent + scout observations rather than interactive Q&A. Full reasoning is captured in 226-CONTEXT.md.

- **D-226-02 Plan structure** — 4 plans mirroring the 4 ROADMAP success criteria (226-01 SCHEMA-MIGRATION-DIFF, 226-02 MIGRATION-TRACE, 226-03 COLUMN-COMMENT-AUDIT, 226-04 ORPHAN-TABLES). One plan per requirement is the shape that worked in Phase 225.
- **D-226-03 Orphan scan scope** — bidirectional (schema→code AND code→schema); code surfaces covered: handlers, indexer, routes, views.ts, indexes.ts.
- **D-226-04 Column-comment audit threshold** — inherit Phase 225's Tier A (outright wrong) + Tier B (materially incomplete) threshold.
- **D-226-05 Default finding direction** — `schema↔migration` (the milestone's 4th mismatch type); orphans default to `code↔schema`.
- **D-226-06 0007 anomaly** — explicit own finding F-28-226-01 in Plan 226-02.
- **D-226-07 views.ts** — in scope for SCHEMA-01 + SCHEMA-04; SCHEMA-05 (refresh semantics) stays deferred to future milestone.

## Deferred Ideas

None raised as scope-creep during discussion. Known deferrals inherited from milestone:
- SCHEMA-05 (view refresh/staleness semantics) — future
- Migration rollback testing — future
- Schema CI gate (`drizzle-kit check` wire-up) — future

---

*Audit trail — not for downstream agent consumption.*
