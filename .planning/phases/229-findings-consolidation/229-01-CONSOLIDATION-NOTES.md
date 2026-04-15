# Phase 229-01 Consolidation Notes (v28.0 FINDINGS Rollup)

**Scope:** Consolidate every finding from Phases 224, 225, 226, 227, 228 into a flat
`F-28-NN` canonical numbering per D-229-03. Preserve per-phase severity; no cross-phase
HIGH promotions identified (D-229-05). Resolution defaults to `DEFERRED` (D-229-07) since
v28.0 is a catalog-only milestone; items explicitly flagged as `INFO-ACCEPTED` in their
originating phase stay in FINDINGS-v28.0.md and are NOT promoted to `audit/KNOWN-ISSUES.md`
(D-229-10).

## Per-Phase Raw Counts

| Phase | Source artifact(s) | Raw findings | Severity histogram |
|-------|---------------------|--------------|--------------------|
| 224 | `224-01-SUMMARY.md`, `224-01-API-ROUTE-MAP.md`, `224-VERIFICATION.md` | 1 | INFO=1 |
| 225 | `225-01-HANDLER-COMMENT-AUDIT.md` (4), `225-02-RESPONSE-SHAPE-AUDIT.md` (9), `225-03-REQUEST-SCHEMA-AUDIT.md` (9) | 22 | INFO=15, LOW=7 |
| 226 | `226-01-SCHEMA-MIGRATION-DIFF.md` (7), `226-02-MIGRATION-TRACE.md` (3); 226-03 and 226-04 produced zero findings | 10 | INFO=3, LOW=7 |
| 227 | `227-01-EVENT-COVERAGE-MATRIX.md` (23), `227-02-EVENT-ARG-MAPPING.md` (6), `227-03-INDEXER-COMMENT-AUDIT.md` (2) | 31 | INFO=21, LOW=10 |
| 228 | `228-01-CURSOR-REORG-TRACE.md` (4), `228-02-VIEW-REFRESH-AUDIT.md` (1) | 5 | INFO=2, LOW=3 |
| **Total** | — | **69** | **INFO=42, LOW=27, HIGH=0, MEDIUM=0, CRITICAL=0** |

## ID Mapping Table

Flat canonical range consumed: `F-28-01` through `F-28-69` (69 IDs, contiguous, no gaps).

| Original ID | Canonical | Phase | Severity | Direction | Resolution | Source artifact | File:Line |
|-------------|-----------|-------|----------|-----------|------------|-----------------|-----------|
| F-28-224-01 | F-28-01 | 224 | INFO | code→docs | INFO-ACCEPTED | 224-01-API-ROUTE-MAP.md | `/home/zak/Dev/PurgeGame/database/src/api/routes/health.ts:13` |
| F-28-225-01 | F-28-02 | 225 | INFO | comment→code | DEFERRED | 225-01-HANDLER-COMMENT-AUDIT.md | `database/src/api/routes/game.ts:1236` |
| F-28-225-02 | F-28-03 | 225 | INFO | comment→code | DEFERRED | 225-01-HANDLER-COMMENT-AUDIT.md | `database/src/api/routes/game.ts:920` |
| F-28-225-03 | F-28-04 | 225 | INFO | comment→code | DEFERRED | 225-01-HANDLER-COMMENT-AUDIT.md | `database/src/api/routes/game.ts:1034` |
| F-28-225-04 | F-28-05 | 225 | INFO | comment→code | DEFERRED | 225-01-HANDLER-COMMENT-AUDIT.md | `database/src/api/routes/replay.ts:69` |
| F-28-225-05 | F-28-06 | 225 | INFO | code→docs | DEFERRED | 225-02-RESPONSE-SHAPE-AUDIT.md | Systemic — 58 sites across `database/src/api/schemas/*.ts` + `database/docs/openapi.yaml` |
| F-28-225-06 | F-28-07 | 225 | INFO | code→docs | DEFERRED | 225-02-RESPONSE-SHAPE-AUDIT.md | `database/src/api/schemas/game.ts:37-42` ↔ `database/docs/openapi.yaml:1681-1708` |
| F-28-225-07 | F-28-08 | 225 | INFO | code→docs | DEFERRED | 225-02-RESPONSE-SHAPE-AUDIT.md | Systemic — ~25 inner object sites in `database/docs/openapi.yaml` |
| F-28-225-08 | F-28-09 | 225 | LOW | code→docs | DEFERRED | 225-02-RESPONSE-SHAPE-AUDIT.md | `database/docs/openapi.yaml:100,680` ↔ `database/src/api/schemas/{player,game}.ts` |
| F-28-225-09 | F-28-10 | 225 | LOW | code→docs | DEFERRED | 225-02-RESPONSE-SHAPE-AUDIT.md | `database/src/api/schemas/player.ts:45-70` ↔ `database/docs/openapi.yaml:657-807` |
| F-28-225-10 | F-28-11 | 225 | INFO | code→docs | DEFERRED | 225-02-RESPONSE-SHAPE-AUDIT.md | `database/src/api/schemas/player.ts:71-76` ↔ `database/docs/openapi.yaml:779-792` |
| F-28-225-11 | F-28-12 | 225 | LOW | code→docs | DEFERRED | 225-02-RESPONSE-SHAPE-AUDIT.md | `database/src/api/schemas/game.ts:75` ↔ `database/docs/openapi.yaml:107-109` |
| F-28-225-12 | F-28-13 | 225 | INFO | code→docs | DEFERRED | 225-02-RESPONSE-SHAPE-AUDIT.md | Multi-site `awardType`/`currency` enum drift — 10+ sites |
| F-28-225-13 | F-28-14 | 225 | LOW | code→docs | DEFERRED | 225-02-RESPONSE-SHAPE-AUDIT.md | `database/src/api/schemas/history.ts:16` ↔ `database/docs/openapi.yaml:1291-1292` |
| F-28-225-14 | F-28-15 | 225 | INFO | code→docs | INFO-ACCEPTED | 225-03-REQUEST-SCHEMA-AUDIT.md | Rescinded on re-read; ID preserved for sequential allocation |
| F-28-225-15 | F-28-16 | 225 | LOW | code→docs | DEFERRED | 225-03-REQUEST-SCHEMA-AUDIT.md | 6 address-family parameter blocks in `database/docs/openapi.yaml` |
| F-28-225-16 | F-28-17 | 225 | LOW | code→docs | DEFERRED | 225-03-REQUEST-SCHEMA-AUDIT.md | `database/docs/openapi.yaml:1218,1268,1315` ↔ `database/src/api/schemas/{common,history}.ts` |
| F-28-225-17 | F-28-18 | 225 | INFO | code→docs | DEFERRED | 225-03-REQUEST-SCHEMA-AUDIT.md | 4 query parameter blocks — `database/docs/openapi.yaml:1099,1135,1171,1207` |
| F-28-225-18 | F-28-19 | 225 | INFO | code→docs | INFO-ACCEPTED | 225-03-REQUEST-SCHEMA-AUDIT.md | Rescinded on re-read; ID preserved for sequential allocation |
| F-28-225-19 | F-28-20 | 225 | INFO | code→docs | DEFERRED | 225-03-REQUEST-SCHEMA-AUDIT.md | `database/src/api/routes/game.ts:9` (dead import) |
| F-28-225-20 | F-28-21 | 225 | INFO | code→docs | DEFERRED | 225-03-REQUEST-SCHEMA-AUDIT.md | `database/src/api/schemas/common.ts:5` + `database/src/api/schemas/game.ts:58` |
| F-28-225-21 | F-28-22 | 225 | LOW | code→docs | DEFERRED | 225-03-REQUEST-SCHEMA-AUDIT.md | `database/src/api/routes/replay.ts:56-58` |
| F-28-225-22 | F-28-23 | 225 | INFO | code→docs | DEFERRED | 225-03-REQUEST-SCHEMA-AUDIT.md | `database/src/api/routes/{game,replay}.ts` + `database/src/api/schemas/{game,history,leaderboard}.ts` |
| F-28-226-01 | F-28-24 | 226 | INFO | schema↔migration | DEFERRED | 226-02-MIGRATION-TRACE.md | `database/drizzle/0007_trait_burn_tickets.sql:1` |
| F-28-226-02 | F-28-25 | 226 | LOW | schema↔migration | DEFERRED | 226-01-SCHEMA-MIGRATION-DIFF.md | `database/src/db/schema/jackpot-history.ts:3` |
| F-28-226-03 | F-28-26 | 226 | LOW | schema↔migration | DEFERRED | 226-01-SCHEMA-MIGRATION-DIFF.md | `database/src/db/schema/jackpot-history.ts:23` |
| F-28-226-04 | F-28-27 | 226 | LOW | schema↔migration | DEFERRED | 226-01-SCHEMA-MIGRATION-DIFF.md | `database/src/db/schema/decimator.ts:41` |
| F-28-226-05 | F-28-28 | 226 | LOW | schema↔migration | DEFERRED | 226-01-SCHEMA-MIGRATION-DIFF.md | `database/src/db/schema/new-events.ts:89` |
| F-28-226-06 | F-28-29 | 226 | INFO | schema↔migration | DEFERRED | 226-01-SCHEMA-MIGRATION-DIFF.md | `database/src/db/schema/new-events.ts:103` |
| F-28-226-07 | F-28-30 | 226 | INFO | schema↔migration | INFO-ACCEPTED | 226-01-SCHEMA-MIGRATION-DIFF.md | `database/src/db/schema/indexes.ts:14` + `database/src/db/schema/jackpot-history.ts:23` |
| F-28-226-08 | F-28-31 | 226 | LOW | schema↔migration | DEFERRED | 226-01-SCHEMA-MIGRATION-DIFF.md | `database/drizzle/0005_red_doctor_octopus.sql:1` |
| F-28-226-09 | F-28-32 | 226 | LOW | schema↔migration | DEFERRED | 226-02-MIGRATION-TRACE.md | `database/drizzle/meta/0003_snapshot.json:1` |
| F-28-226-10 | F-28-33 | 226 | LOW | schema↔migration | DEFERRED | 226-02-MIGRATION-TRACE.md | `database/src/db/schema/quests.ts:11` |
| F-28-227-01 | F-28-34 | 227 | INFO | schema↔handler | INFO-ACCEPTED | 227-01-EVENT-COVERAGE-MATRIX.md | `contracts/BurnieCoin.sol:55` |
| F-28-227-02 | F-28-35 | 227 | INFO | schema↔handler | INFO-ACCEPTED | 227-01-EVENT-COVERAGE-MATRIX.md | `contracts/DegenerusAdmin.sol:245` |
| F-28-227-03 | F-28-36 | 227 | INFO | schema↔handler | INFO-ACCEPTED | 227-01-EVENT-COVERAGE-MATRIX.md | `contracts/DegenerusAdmin.sol:249` |
| F-28-227-04 | F-28-37 | 227 | INFO | schema↔handler | INFO-ACCEPTED | 227-01-EVENT-COVERAGE-MATRIX.md | `contracts/DegenerusAdmin.sol:250` |
| F-28-227-05 | F-28-38 | 227 | INFO | schema↔handler | INFO-ACCEPTED | 227-01-EVENT-COVERAGE-MATRIX.md | `contracts/DegenerusAdmin.sol:251` |
| F-28-227-06 | F-28-39 | 227 | INFO | schema↔handler | INFO-ACCEPTED | 227-01-EVENT-COVERAGE-MATRIX.md | `contracts/DegenerusAdmin.sol:252` |
| F-28-227-07 | F-28-40 | 227 | LOW | schema↔handler | DEFERRED | 227-01-EVENT-COVERAGE-MATRIX.md | `contracts/DegenerusAdmin.sol:261` ↔ `database/src/handlers/index.ts:379` |
| F-28-227-08 | F-28-41 | 227 | INFO | schema↔handler | INFO-ACCEPTED | 227-01-EVENT-COVERAGE-MATRIX.md | `contracts/DegenerusAdmin.sol:268` |
| F-28-227-09 | F-28-42 | 227 | INFO | schema↔handler | INFO-ACCEPTED | 227-01-EVENT-COVERAGE-MATRIX.md | `contracts/DegenerusAdmin.sol:274` |
| F-28-227-10 | F-28-43 | 227 | INFO | schema↔handler | INFO-ACCEPTED | 227-01-EVENT-COVERAGE-MATRIX.md | `contracts/DegenerusAdmin.sol:279` |
| F-28-227-11 | F-28-44 | 227 | INFO | schema↔handler | INFO-ACCEPTED | 227-01-EVENT-COVERAGE-MATRIX.md | `contracts/DegenerusAdmin.sol:370` |
| F-28-227-12 | F-28-45 | 227 | INFO | schema↔handler | INFO-ACCEPTED | 227-01-EVENT-COVERAGE-MATRIX.md | `contracts/DegenerusAdmin.sol:376` |
| F-28-227-13 | F-28-46 | 227 | INFO | schema↔handler | INFO-ACCEPTED | 227-01-EVENT-COVERAGE-MATRIX.md | `contracts/DegenerusAdmin.sol:382` |
| F-28-227-14 | F-28-47 | 227 | INFO | schema↔handler | INFO-ACCEPTED | 227-01-EVENT-COVERAGE-MATRIX.md | `contracts/DegenerusAdmin.sol:383` |
| F-28-227-15 | F-28-48 | 227 | INFO | schema↔handler | INFO-ACCEPTED | 227-01-EVENT-COVERAGE-MATRIX.md | `contracts/DegenerusDeityPass.sol:60` |
| F-28-227-16 | F-28-49 | 227 | INFO | schema↔handler | INFO-ACCEPTED | 227-01-EVENT-COVERAGE-MATRIX.md | `contracts/DegenerusDeityPass.sol:61` |
| F-28-227-17 | F-28-50 | 227 | LOW | schema↔handler | DEFERRED | 227-01-EVENT-COVERAGE-MATRIX.md | `contracts/DegenerusStonk.sol:299` |
| F-28-227-18 | F-28-51 | 227 | LOW | schema↔handler | DEFERRED | 227-01-EVENT-COVERAGE-MATRIX.md | `contracts/DegenerusVault.sol:191` ↔ `database/src/handlers/token-balances.ts:38` |
| F-28-227-19 | F-28-52 | 227 | INFO | schema↔handler | INFO-ACCEPTED | 227-01-EVENT-COVERAGE-MATRIX.md | `contracts/DegenerusVault.sol:196` |
| F-28-227-20 | F-28-53 | 227 | LOW | schema↔handler | DEFERRED | 227-01-EVENT-COVERAGE-MATRIX.md | `contracts/GNRUS.sol:104` ↔ `database/src/handlers/token-balances.ts:38` |
| F-28-227-21 | F-28-54 | 227 | LOW | schema↔handler | DEFERRED | 227-01-EVENT-COVERAGE-MATRIX.md | `contracts/GNRUS.sol:107` ↔ `database/src/handlers/index.ts:341` |
| F-28-227-22 | F-28-55 | 227 | INFO | schema↔handler | INFO-ACCEPTED | 227-01-EVENT-COVERAGE-MATRIX.md | `contracts/WrappedWrappedXRP.sol:42` |
| F-28-227-23 | F-28-56 | 227 | INFO | code↔schema | INFO-ACCEPTED | 227-01-EVENT-COVERAGE-MATRIX.md | `database/src/handlers/index.ts:288` (inverse orphan — no emitter) |
| F-28-227-101 | F-28-57 | 227 | LOW | schema↔handler | DEFERRED | 227-02-EVENT-ARG-MAPPING.md | `database/src/handlers/daily-rng.ts:22` ↔ `contracts/modules/DegenerusGameAdvanceModule.sol:76` |
| F-28-227-102 | F-28-58 | 227 | INFO | schema↔handler | INFO-ACCEPTED | 227-02-EVENT-ARG-MAPPING.md | `database/src/handlers/daily-rng.ts:42` |
| F-28-227-103 | F-28-59 | 227 | LOW | schema↔handler | DEFERRED | 227-02-EVENT-ARG-MAPPING.md | `database/src/handlers/decimator.ts:465` ↔ `contracts/modules/DegenerusGameDecimatorModule.sol:600` |
| F-28-227-104 | F-28-60 | 227 | LOW | schema↔handler | DEFERRED | 227-02-EVENT-ARG-MAPPING.md | `database/src/handlers/deity-pass.ts:64` ↔ `contracts/DegenerusDeityPass.sol:59` |
| F-28-227-105 | F-28-61 | 227 | LOW | schema↔handler | DEFERRED | 227-02-EVENT-ARG-MAPPING.md | `database/src/handlers/jackpot.ts:112` ↔ `contracts/modules/DegenerusGameJackpotModule.sol:111` |
| F-28-227-106 | F-28-62 | 227 | LOW | schema↔handler | DEFERRED | 227-02-EVENT-ARG-MAPPING.md | `database/src/handlers/whale-pass.ts:19` ↔ `contracts/modules/DegenerusGameWhaleModule.sol:65` |
| F-28-227-201 | F-28-63 | 227 | INFO | comment→code | DEFERRED | 227-03-INDEXER-COMMENT-AUDIT.md | `database/src/handlers/new-events.ts:4-5` |
| F-28-227-202 | F-28-64 | 227 | INFO | comment→code | DEFERRED | 227-03-INDEXER-COMMENT-AUDIT.md | `database/src/handlers/lootbox.ts:5` |
| F-28-228-01 | F-28-65 | 228 | LOW | comment→code | DEFERRED | 228-01-CURSOR-REORG-TRACE.md | `database/src/indexer/cursor-manager.ts:45` |
| F-28-228-02 | F-28-66 | 228 | INFO | comment→code | INFO-ACCEPTED | 228-01-CURSOR-REORG-TRACE.md | `database/src/indexer/cursor-manager.ts:70` |
| F-28-228-03 | F-28-67 | 228 | INFO | docs→code | DEFERRED | 228-01-CURSOR-REORG-TRACE.md | `database/src/indexer/main.ts:216-220` |
| F-28-228-04 | F-28-68 | 228 | LOW | docs→code | DEFERRED | 228-01-CURSOR-REORG-TRACE.md | `database/src/indexer/main.ts:155` |
| F-28-228-101 | F-28-69 | 228 | LOW | comment→code | DEFERRED | 228-02-VIEW-REFRESH-AUDIT.md | `database/src/indexer/view-refresh.ts:4-5,30-32` |

## Severity Decisions

**No cross-phase amplification identified; all severities preserved from originating phase.**

Per D-229-05, HIGH promotion requires explicit cross-phase amplification rationale. The
elevated-severity items flagged in 229-CONTEXT.md `## Specific Ideas` were examined:

1. **228 reorg edge (F-28-68 / orig F-28-228-04):** LOW per 228. No 226 or 227 finding
   amplifies it — the `confirmations=0` window self-heals via reorg-detector walk-back
   in a single batch (per 228-01-CURSOR-REORG-TRACE.md evidence). **Severity preserved
   at LOW.**

2. **227-02 silent truncation candidates (F-28-57..F-28-62):** Each was individually
   scored LOW or INFO per 227. None share a column with a 226 schema-migration finding
   (e.g. `daily_rng.nudges` in F-28-57 has no 226 entry; `jackpot_distributions.half_pass_count`
   in F-28-61 is part of F-28-25's extra-column set but the new column matches the
   handler's current widened-TS declaration — so 226 documents the drift and 227 documents
   the truncation; they describe different aspects of the same table but no compounding
   occurs because the 226 drift is schema-vs-migration, while 227 is handler-vs-event
   type width). **Severities preserved.**

No retroactive downgrades (D-229-05 policy).

## Direction Assignments

D-229-06 labels applied per-finding:

| Label | Count | Findings |
|-------|-------|----------|
| `code→docs` | 23 | F-28-01, F-28-06..F-28-23 (22 from Phase 225) + F-28-01 from Phase 224 already counted |
| `comment→code` | 9 | F-28-02..F-28-05 (225-01), F-28-63..F-28-64 (227-03), F-28-65, F-28-66, F-28-69 (228) |
| `schema↔migration` | 10 | F-28-24..F-28-33 (all Phase 226) |
| `schema↔handler` | 22 | F-28-34..F-28-55, F-28-57..F-28-62 (Phase 227 plans 01 + 02, excl. F-28-56) |
| `code↔schema` | 1 | F-28-56 (F-28-227-23 registry orphan, inverse direction) |
| `docs→code` | 2 | F-28-67, F-28-68 (228) |
| **Total** | **69** | — |

Recount: code→docs 23 (F-28-01 + 22 from 225) = 23. comment→code 4 (225-01) + 2 (227-03) + 3 (228-01 F-28-65, 66; 228-02 F-28-69) = 9. schema↔migration 10 (all 226). schema↔handler 22 (from F-28-34..F-28-55 = 22 IDs including F-28-56? No — F-28-34..F-28-55 = 22 IDs, but F-28-56 is code↔schema so: F-28-34..F-28-55 = 22 Phase-227-01 findings minus F-28-56 which is already excluded from this range? F-28-227-01..22 → F-28-34..F-28-55 = 22 findings at schema↔handler; F-28-227-23 → F-28-56 = code↔schema; F-28-227-101..106 → F-28-57..F-28-62 = 6 at schema↔handler. Total schema↔handler = 22 + 6 = 28.) docs→code 2 (228-01 F-28-67, F-28-68).

Corrected counts:

| Label | Count | Findings |
|-------|-------|----------|
| `code→docs` | 23 | F-28-01 (224), F-28-06..F-28-23 (18 from 225-02 + 225-03), F-28-02..F-28-05 counted under `comment→code` so code→docs from 225 = 225-02 (9: F-28-06..F-28-14) + 225-03 (9: F-28-15..F-28-23) = 18; total code→docs = 1 + 18 = 19. |
| `comment→code` | 9 | F-28-02..F-28-05 (225-01, 4), F-28-63..F-28-64 (227-03, 2), F-28-65, F-28-66, F-28-69 (228, 3) = 9 |
| `schema↔migration` | 10 | F-28-24..F-28-33 (226, 10) |
| `schema↔handler` | 28 | F-28-34..F-28-55 except F-28-56 → 22 IDs (227-01 01..22); F-28-57..F-28-62 (227-02, 6) = 28 |
| `code↔schema` | 1 | F-28-56 (F-28-227-23 inverse orphan) |
| `docs→code` | 2 | F-28-67, F-28-68 (228-01) |
| **Total** | **69** | 19+9+10+28+1+2 = 69 ✓ |

Direction taxonomy follows D-229-06 exactly. No ambiguous assignments.

## Resolution Assignments

Per D-229-07, v28.0 is catalog-only → default `DEFERRED` target "future v29+ remediation
milestone (backlog)". `INFO-ACCEPTED` items remain in FINDINGS-v28.0.md only and are NOT
promoted to KNOWN-ISSUES.md (D-229-10).

| Resolution | Count | Policy per D-229-07 |
|------------|-------|---------------------|
| RESOLVED-DOC | 0 | No documentation-in-cycle fixes applied within v28.0 scope (audit repo `.planning/` artifacts document findings but do not "resolve" them — the remediation target is `database/docs/openapi.yaml`, `database/src/...` comments, etc., which are out of v28 write scope per D-229-02). |
| RESOLVED-CODE | 0 | No code changes applied within v28.0 scope (writable-targets gate forbids writes to `database/` or `contracts/`). |
| DEFERRED | 48 | Target: "v29+ remediation backlog" (fix requires writes to `database/` or `contracts/`, out of v28 scope). |
| INFO-ACCEPTED | 21 | Stays in FINDINGS-v28.0.md. NOT promoted to KNOWN-ISSUES.md per D-229-10. Rationale logged per-finding. |

**Breakdown by finding (21 INFO-ACCEPTED):**

| Canonical | Rationale |
|-----------|-----------|
| F-28-01 | Scouting estimate vs reality; zero functional drift. |
| F-28-15 | Null/rescinded F-28-225-14 — re-read confirmed openapi declares `required: true`. |
| F-28-19 | Null/rescinded F-28-225-18 — re-read confirmed alignment. |
| F-28-30 | Duplicate index declaration; harmless at runtime (`IF NOT EXISTS` raw-SQL bootstrap). |
| F-28-34..F-28-38 | ERC-20/admin log-only events — no domain-table mapping required per handler skip-comment convention. |
| F-28-41..F-28-49 | Admin/renderer events — governance + renderer-config; analytics out of scope. |
| F-28-52, F-28-55 | ERC-20 Approval events — not tracked by design. |
| F-28-56 | Inverse orphan (handler registered for an event no contract emits) — dead-code, harmless. |
| F-28-58 | uint48 fits JS number (2^48 < 2^53) — no runtime truncation risk. |
| F-28-66 | `advanceCursor` transactional convention is duck-typed by design; convention-only is standard in this codebase. |

**DEFERRED items (48):** target named as "future v29+ remediation backlog" unless a more
specific target is identified by the originating phase. None of the originating-phase
SUMMARY.md files name a specific follow-up milestone — v29+ backlog is the default.

## Writable-Targets Gate Compliance

- `git diff audit/KNOWN-ISSUES.md` must be empty (D-229-10). Verified at plan completion.
- `git diff contracts/ test/` must be empty (standing policy). Verified at plan completion.
- Writes in this plan are confined to `audit/FINDINGS-v28.0.md` (Task 2) and this notes file.

---

*Phase: 229-findings-consolidation, Plan: 01, Completed: 2026-04-15*
