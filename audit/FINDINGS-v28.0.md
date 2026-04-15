# Degenerus Protocol -- Delta Findings Report (v28.0 Database & API Intent Alignment Audit)

**Audit Date:** 2026-04-15
**Methodology:** Five-phase database/API intent-alignment audit covering (224) API route ↔ OpenAPI alignment, (225) API handler behavior + request/response schema alignment, (226) Drizzle schema ↔ SQL migration orphan audit, (227) indexer event processing correctness (coverage, arg mapping, comment audit), and (228) cursor/reorg/view-refresh state machines. Each phase executed by Claude (claude-opus-4-6) with structured reasoning, per-plan acceptance-criteria grep gates, and gsd-verifier re-checks. Phase 229 consolidates findings; consolidation notes with ID-mapping table live at `.planning/phases/229-findings-consolidation/229-01-CONSOLIDATION-NOTES.md`.
**Scope:** Database and indexer repository (`database/src/api/routes/`, `database/src/api/schemas/`, `database/docs/openapi.yaml`, `database/src/db/schema/`, `database/drizzle/`, `database/src/handlers/`, `database/src/indexer/`) against the contracts-side event interface in `contracts/*.sol`. This is a sim/database/indexer audit — the contracts themselves are NOT re-audited here (v25.0/v27.0 handle that scope). Delta supplement to `audit/FINDINGS-v25.0.md` (Master Delta, 13 INFO) and `audit/FINDINGS-v27.0.md` (Call-Site Integrity, 16 INFO). No `FINDINGS-v26.0.md` exists (v26.0 was a design milestone; see `.planning/MILESTONES.md`).
**In-scope artifacts:** `database/src/api/routes/*.ts` (8 files, 27 endpoints), `database/src/api/schemas/*.ts` (6 files), `database/docs/openapi.yaml`, `database/src/db/schema/*.ts` (31 files), `database/drizzle/*.sql` + `drizzle/meta/*.json`, `database/src/handlers/*.ts` (30 files), `database/src/indexer/*.ts` (cursor-manager, reorg-detector, event-processor, view-refresh, main). Contracts-side event declarations consulted read-only for event-shape cross-reference.

---

## Executive Summary

| Severity | Count |
|----------|-------|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 0 |
| LOW | 27 |
| INFO | 42 |
| **Total** | **69** |

**Overall Assessment:** Zero CRITICAL, HIGH, or MEDIUM findings. 27 LOW findings distributed across Phase 225 (7 — API Zod↔OpenAPI contract drift with caller-observable impact), Phase 226 (7 — Drizzle-schema-vs-applied-SQL drift with silent-wrong-result risk on specific write paths), Phase 227 (10 — 4 handler-router collisions or orphaned-event patterns + 6 silent-truncation sites where `Number(parseBigInt(...))` narrows `uint256` to a JS float), and Phase 228 (3 — cursor-manager docstring drift, reorg edge case on anvil, view-refresh sustained-failure staleness bound). 42 INFO findings cover documentation lag, admin/governance unhandled events (intentional skip-comment convention), null/rescinded IDs preserved for sequential allocation, and code-hygiene observations.

Per-phase verdicts from VERIFICATION artifacts:

- **Phase 224 — PASS (7/7 must-have truths, 2/2 requirements):** 27/27 endpoints triple-aligned across `openapi.yaml` + route code + `API.md`. Single meta-observational stub recorded for traceability (scouting count vs reality in `health.ts`).
- **Phase 225 — PASS (API-03/API-04/API-05 all satisfied):** 27/27 handler JSDoc audits (4 Tier-A/B drift findings), 27/27 response-shape comparisons (9 Zod↔OpenAPI findings; 3 fully PASS, 24 carry at least one systemic pattern), 14/14 request-side Zod schemas compared against all 28 OpenAPI parameters (9 findings; zero orphan-in-OpenAPI, 100% name-level coverage).
- **Phase 226 — PASS (SCHEMA-01..04 satisfied):** 67 Drizzle pgTables vs 65 SQL `CREATE TABLE` statements across 7 migrations — 4 FAIL tables (10 findings), 0 orphan tables, 0 missing-in-schema references, ~470/480 column rows PASS.
- **Phase 227 — PASS (IDX-01..03 satisfied):** 123 universe rows (87 PROCESSED + 8 DELEGATED→PROCESSED + 6 INTENTIONALLY-SKIPPED + 22 UNHANDLED) with per-row closure, 23 UNHANDLED coverage-gap findings, 6 silent-truncation arg-mapping findings (2 of which — `DailyRngApplied.nudges` and `TerminalDecBurnRecorded.timeMultBps` — hit 225-CONTEXT.md "caller-observable numeric precision" bar), 2 handler-comment Tier-B drifts.
- **Phase 228 — PASS (IDX-04..05 satisfied):** cursor/reorg state machine traced end-to-end with same-iteration ordering invariant confirmed; view-refresh isolation from event-write tx confirmed; 5 findings covering docstring overclaims (cursor-manager, view-refresh), ROADMAP-vs-code gap on "recovery-after-stall", and the anvil-only intra-batch reorg edge (self-healing via reorg-detector walk-back within one batch; LOW because transient, not permanent).

Elevated-severity items of note per 229-CONTEXT.md: (a) the 228 reorg edge case (F-28-68) and (b) the 227-02 silent-truncation sites on domain values (F-28-57, F-28-59, F-28-61, F-28-62 — all LOW, all flagged as RESOLVED-CODE candidates in their originating phases). No cross-phase amplification rationale was identified that would warrant HIGH promotion (D-229-05); severities preserved from each originating phase.

v28.0 is a **catalog audit** — most findings carry `Resolution: DEFERRED` per D-229-07. Per the v28.0 scope directive (D-229-10), no findings are promoted to `audit/KNOWN-ISSUES.md` this milestone; all INFO-ACCEPTED items live here in `FINDINGS-v28.0.md` and nowhere else. This report is a delta supplement to `FINDINGS-v25.0.md` and `FINDINGS-v27.0.md`; external auditors should read all three together.

---

## Findings

### Phase 224: API Route & OpenAPI Alignment (1 finding)

#### F-28-01: health.ts scouting-estimate count reconciliation stub

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 224 (`224-01-API-ROUTE-MAP.md` finding-candidate pool) |
| **Direction** | code→docs |
| **File** | `/home/zak/Dev/PurgeGame/database/src/api/routes/health.ts:13` |
| **Resolution** | INFO-ACCEPTED |

The Phase 224 plan's scouting estimate for `health.ts` reported `~2` route registrations; the measured count is `1` (a single `fastify.get('/')` at line 13). All other metrics — 27 OpenAPI paths, 27 route registrations, 27 API.md headings, path-normalized `{name}` ≡ `:name`, zero method/path/param/body drift — reconcile exactly. The "drift" is confined to a planning-scout approximation and is not a code or docs defect.

**Severity justification:** INFO because there is no functional drift on `database/` code or on `openapi.yaml`/`API.md`. The 27/27/27 triple-alignment is confirmed; this stub exists only to satisfy the plan's "at-least-one-finding-stub" acceptance criterion while honestly recording a scouting-vs-reality delta. No production risk.

**Resolution rationale:** INFO-ACCEPTED — scouting estimates are explicitly approximations; no fix required. Promotion to `audit/KNOWN-ISSUES.md` suppressed per v28.0 scope directive D-229-10.

---

### Phase 225: API Handler Behavior, Validation & Schema Alignment (22 findings)

#### F-28-02: `/game/jackpot/earliest-day` comment claims "any distributions" but code excludes `dgnrs`

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 225 (`225-01-HANDLER-COMMENT-AUDIT.md`, Tier A) |
| **Direction** | comment→code |
| **File** | `/home/zak/Dev/PurgeGame/database/src/api/routes/game.ts:1236` (comment block `:1235-1238`; registration `:1239`; filter `:1254`) |
| **Resolution** | DEFERRED |

The handler comment reads "Returns the lowest day that has any jackpot distributions" but the SQL predicate at line 1254 is `jd."awardType" <> 'dgnrs'`, meaning days whose distributions are entirely `dgnrs`-typed are silently skipped. The sibling `/game/jackpot/latest-day` at `:1214` carries no such filter, creating a latent asymmetry the comment does not acknowledge. The UI scrubber (documented caller on line 1237) would position its lower bound above such a day.

**Severity justification:** INFO per 225-CONTEXT.md severity rules — no Zod type mismatch, no required-parameter drift, no documented-but-unemitted response field. Documentation-drift only; 225-CONTEXT.md explicitly caps this class of finding at LOW maximum, and the filter does not cause a documented response field to be missing.

**Resolution rationale:** DEFERRED to v29+ remediation milestone — fix requires writes to `database/src/api/routes/game.ts` which is out of v28 scope.

---

#### F-28-03: `/game/jackpot/day/:day/roll1` comment omits the 404 branch on empty-day

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 225 (`225-01-HANDLER-COMMENT-AUDIT.md`, Tier B) |
| **Direction** | comment→code |
| **File** | `/home/zak/Dev/PurgeGame/database/src/api/routes/game.ts:920` (comment `:920-922`; registration `:923`; 404 return `:1007-1009`) |
| **Resolution** | DEFERRED |

The handler returns HTTP 404 (via `reply.notFound("No roll1 distributions for day {day}")`) when the query yields zero rows. Neither the comment nor the Fastify `response:` schema (`{200: rollResponseSchema}` only) mentions the 404 branch. A caller reading the comment expects an empty-array fallback, not a 404; distinguishing "day is invalid" from "day exists but has no Roll 1 payouts" is impossible without consulting the code.

**Severity justification:** INFO — status-code/comment drift; no type mismatch or missing-field crash. The 200 response shape is fully emitted when 200 returns.

**Resolution rationale:** DEFERRED to v29+ (update comment + add `404: errorResponseSchema` to the Fastify registration, matching the precedent in `player.ts:22` and `viewer.ts:172`).

---

#### F-28-04: `/game/jackpot/day/:day/roll2` comment omits two 404 branches on empty-day

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 225 (`225-01-HANDLER-COMMENT-AUDIT.md`, Tier B) |
| **Direction** | comment→code |
| **File** | `/home/zak/Dev/PurgeGame/database/src/api/routes/game.ts:1034` (comment `:1034-1036`; registration `:1037`; raw-empty 404 `:1141-1143`; post-filter 404 `:1203-1205`) |
| **Resolution** | DEFERRED |

Identical shape to F-28-03 with an additional subtlety: roll2 has two 404 return sites — one when the raw query is empty, and one after JS-level bonusTraits filtering (`isBonusTrait` / `isFarFutureBurnie` / `isNearFutureBurnie`) returns an empty set. The post-filter 404 depends on `daily_winning_traits.bonusTraitsPacked` indexer state, so the same day can 404 or 200 depending on indexer progress.

**Severity justification:** INFO — status-code/comment drift; no type mismatch. The post-filter 404 path adds diagnostic difficulty but does not change the severity class.

**Resolution rationale:** DEFERRED — same fix shape as F-28-03, extended to document both 404 paths.

---

#### F-28-05: `/replay/day/:day` JSDoc omits the winning-trait-and-transaction filter applied to distributions

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 225 (`225-01-HANDLER-COMMENT-AUDIT.md`, Tier B) |
| **Direction** | comment→code |
| **File** | `/home/zak/Dev/PurgeGame/database/src/api/routes/replay.ts:69` (JSDoc `:69-71`; registration `:72`; filter `:139-161`) |
| **Resolution** | DEFERRED |

The JSDoc reads "RNG word + jackpot distributions for a specific game day" but the handler applies a non-trivial post-fetch filter: only ETH rows whose `traitId` is in the day's four winning traits are kept; `tickets`/`burnie` rows are kept whole; `dgnrs`/`whale_pass` rows are kept only if their `transactionHash` matches a winning-trait ETH distribution in the same transaction. Callers reconstructing day totals from this endpoint would under-count.

**Severity justification:** INFO — filter affects rows returned, not field types; no response-field mismatch or missing-field crash. Documentation-drift only.

**Resolution rationale:** DEFERRED — lift the existing inline comment at `:139-146` into the public JSDoc.

---

#### F-28-06: Systemic — Zod `z.number()` (non-int) vs OpenAPI `type: integer` (58 sites, 22 endpoints)

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 225 (`225-02-RESPONSE-SHAPE-AUDIT.md`, systemic consolidation) |
| **Direction** | code→docs |
| **File** | Systemic — 58 occurrences across `/home/zak/Dev/PurgeGame/database/src/api/schemas/*.ts`, `/home/zak/Dev/PurgeGame/database/src/api/routes/*.ts` (health, replay, viewer) ↔ `/home/zak/Dev/PurgeGame/database/docs/openapi.yaml` (representative lines `:66-78, :513-562, :709-736, :1422-1550`) |
| **Resolution** | DEFERRED |

Across 58 field paths in 22 endpoints, Zod declares `z.number()` (JSON-schema equivalent `type: number`) where OpenAPI declares `type: integer`. Representative examples: `health.indexedBlock/chainTip/lagBlocks/lagSeconds`, `game.level/quadrant/winnerCount`, `viewer.ts` ~20 fields. Per the Zod-to-OpenAPI mapping table in 225-CONTEXT.md D-225-02, this is a literal type-map disagreement.

**Severity justification:** INFO — JSON numbers serialize/deserialize identically whether intent is integer or float; TypeScript consumers generated from OpenAPI infer `number` for both. Formally recordable but not caller-breaking. The 225 auditor recommended `RESOLVED-CODE` (tighten Zod to `.int()`) as the lower-friction fix.

**Resolution rationale:** DEFERRED — 58 sites across `database/src/api/schemas/` require coordinated update; recommended approach is to add `.int()` to Zod at each declaration, which is out of v28 write scope.

---

#### F-28-07: `jackpotOverviewRowSchema.ticketSubRow` absent from OpenAPI `JackpotTraitRow` + inline `/overview`

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 225 (`225-02-RESPONSE-SHAPE-AUDIT.md`) |
| **Direction** | code→docs |
| **File** | `/home/zak/Dev/PurgeGame/database/src/api/schemas/game.ts:37-42` ↔ `/home/zak/Dev/PurgeGame/database/docs/openapi.yaml:524-571` (inline `/overview.rows[]`) + `:1681-1708` (`JackpotTraitRow` reusable component) |
| **Resolution** | DEFERRED |

Zod declares `ticketSubRow: z.object({wins: z.number().int(), amountPerWin: z.string()}).nullable().optional()` on `jackpotOverviewRowSchema`. The inline OpenAPI `/overview.rows[]` and the shared `JackpotTraitRow` component (used by `/game/jackpot/{level}/player/{addr}` via `$ref`) both omit the field.

**Severity justification:** INFO — optional+nullable field; callers that do not depend on it see no impact. Field is tree-shakeable for consumers that ignore it.

**Resolution rationale:** DEFERRED — add `ticketSubRow` to both OpenAPI sites with matching `.nullable().optional()` semantics.

---

#### F-28-08: Systemic — OpenAPI omits `required:` arrays on inner object schemas (~25 sites)

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 225 (`225-02-RESPONSE-SHAPE-AUDIT.md`, systemic consolidation) |
| **Direction** | code→docs |
| **File** | Systemic — `/home/zak/Dev/PurgeGame/database/docs/openapi.yaml` inner objects at `:720, :750, :761, :781, :795, :896, :914, :1007, :1042, :1117, :1150, :1186, :1236, :1285, :1331, :1370, :1425-1552` |
| **Resolution** | DEFERRED |

Zod `z.object({...})` makes every field required by default; OpenAPI declares top-level `required:` arrays but consistently omits them on inner object schemas. 4 of ~22 sampled inner-object sites correctly declare `required:` (`prizePools:154`, `winners[]:236`, `breakdown[]:268`, `RollResponse:1659`, `RollWinRow:1617`); 18+ do not.

**Severity justification:** INFO — handler always emits the required fields; defensive codegen consumers add unused null-checks rather than crash. Documentation-lag only.

**Resolution rationale:** DEFERRED — add `required:` arrays to ~25 inner-object sites in `database/docs/openapi.yaml`, following the existing precedent.

---

#### F-28-09: `/player/{address}` + `/game/state` top-level `required:` arrays too short

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Source** | Phase 225 (`225-02-RESPONSE-SHAPE-AUDIT.md`) |
| **Direction** | code→docs |
| **File** | `/home/zak/Dev/PurgeGame/database/docs/openapi.yaml:100` (game.state, 4 of 15 fields required) and `:680` (player, 5 of 20 fields required) ↔ `/home/zak/Dev/PurgeGame/database/src/api/schemas/{game,player}.ts` |
| **Resolution** | DEFERRED |

OpenAPI `/player/{address}.required` = `[player, claimableEth, totalClaimed, burnieBalance, tickets]` — only 5 of Zod's 20 non-optional top-level fields. `/game/state.required` = `[level, phase, jackpotPhaseFlag, gameOver]` — only 4 of Zod's 15 non-optional fields. 15 + 11 = 26 fields that the handler always emits but OpenAPI advertises as optional.

**Severity justification:** LOW per 225-CONTEXT.md — strict response-validating codegen consumers would type these as `field?: T | undefined` and either accept over-strict responses or misclassify them as invalid. Non-nullable scalars like `currentStreak` and `shields` are omitted from required, which is the inverse of the "documented-but-not-emitted" criterion and materially mis-describes the contract.

**Resolution rationale:** DEFERRED — expand the two top-level `required:` arrays to match Zod's 20 + 15 field sets.

---

#### F-28-10: `/player/{address}` — three top-level response sub-trees missing from OpenAPI

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Source** | Phase 225 (`225-02-RESPONSE-SHAPE-AUDIT.md`) |
| **Direction** | code→docs |
| **File** | `/home/zak/Dev/PurgeGame/database/src/api/schemas/player.ts:45-70` ↔ `/home/zak/Dev/PurgeGame/database/docs/openapi.yaml:657-807` |
| **Resolution** | DEFERRED |

Zod declares three non-optional (but `.nullable()`) object properties on `playerDashboardResponseSchema`: `decimator` (6 nested fields + `claimablePerLevel[]` sub-array), `terminal` (5 fields under `burns[]`), `degenerette` (4 fields + `pendingBets[]`). Handler at `player.ts:121-170` unconditionally constructs and returns all three; OpenAPI documents none of them. 17 leaf fields undocumented.

**Severity justification:** LOW — caller-breaking for OpenAPI-typed consumers: TypeScript types generated from OpenAPI would not surface these fields at all; attempting to read `.decimator.windowOpen` would be a compile-time error, forcing consumers to augment type defs or abandon strict typing.

**Resolution rationale:** DEFERRED — add three top-level `properties` blocks to OpenAPI matching the Zod shapes with `nullable: true` on the outer objects.

---

#### F-28-11: `/player/{address}.affiliate` — OpenAPI declares non-nullable but Zod is nullable

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 225 (`225-02-RESPONSE-SHAPE-AUDIT.md`) |
| **Direction** | code→docs |
| **File** | `/home/zak/Dev/PurgeGame/database/src/api/schemas/player.ts:71-76` ↔ `/home/zak/Dev/PurgeGame/database/docs/openapi.yaml:779-792` |
| **Resolution** | DEFERRED |

Zod declares `affiliate: z.object({...}).nullable()` but the handler at `player.ts:187-193` unconditionally constructs `affiliateData = {referrer: ... ?? null, code: ... ?? null, ...}` — the object is never null. OpenAPI's non-nullable stance is empirically correct; Zod is too loose.

**Severity justification:** INFO — no caller impact in practice (handler never emits null). Zod is over-loose; OpenAPI is accurate. 225-02 recommended `RESOLVED-CODE` (remove `.nullable()`) as the inverted remediation.

**Resolution rationale:** DEFERRED — `RESOLVED-CODE` candidate (one-line change to Zod); Phase 229 makes no remediation decision this milestone.

---

#### F-28-12: `/game/state.phase` — OpenAPI `integer` vs Zod string enum

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Source** | Phase 225 (`225-02-RESPONSE-SHAPE-AUDIT.md`) |
| **Direction** | code→docs |
| **File** | `/home/zak/Dev/PurgeGame/database/src/api/schemas/game.ts:75` ↔ `/home/zak/Dev/PurgeGame/database/docs/openapi.yaml:107-109` |
| **Resolution** | DEFERRED |

Zod: `phase: z.enum(['PURCHASE', 'JACKPOT', 'GAMEOVER'])`. OpenAPI: `phase: type: integer, example: 2`. Handler emits the string enum; OpenAPI-typed consumers parse as integer, then any `if (phase === 0)` branch silently fails to match `"PURCHASE"`.

**Severity justification:** LOW per 225-CONTEXT.md severity rule #1 (type mismatch that breaks JSON-schema-typed consumers). The OpenAPI example `2` is nonsensical given the actual handler behavior.

**Resolution rationale:** DEFERRED — update OpenAPI to `type: string, enum: [PURCHASE, JACKPOT, GAMEOVER], example: PURCHASE`.

---

#### F-28-13: `awardType` / `currency` — OpenAPI tighter than Zod enum

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 225 (`225-02-RESPONSE-SHAPE-AUDIT.md`) |
| **Direction** | code→docs |
| **File** | Multi-site — `/home/zak/Dev/PurgeGame/database/src/api/routes/{game,replay}.ts`, `/home/zak/Dev/PurgeGame/database/src/api/schemas/{game,history,player}.ts` ↔ `/home/zak/Dev/PurgeGame/database/docs/openapi.yaml:272,1059,1625` |
| **Resolution** | DEFERRED |

OpenAPI documents tight enums at `breakdown[].awardType`, `RollWinRow.awardType`, and `distributions[].currency`. Zod uses bare `z.string()` at ≥7 sites. Handler always emits values in the OpenAPI enum set.

**Severity justification:** INFO — OpenAPI is empirically accurate; Zod is too loose. Caller impact is zero (handler never emits outside the enum). 225-02 recommended `RESOLVED-CODE` (add `z.enum([...])` to Zod, not strip OpenAPI enums).

**Resolution rationale:** DEFERRED — `RESOLVED-CODE` candidate; align Zod to OpenAPI.

---

#### F-28-14: `/history/levels.items[].phase` — OpenAPI `integer` vs Zod `string`

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Source** | Phase 225 (`225-02-RESPONSE-SHAPE-AUDIT.md`) |
| **Direction** | code→docs |
| **File** | `/home/zak/Dev/PurgeGame/database/src/api/schemas/history.ts:16` ↔ `/home/zak/Dev/PurgeGame/database/docs/openapi.yaml:1291-1292` |
| **Resolution** | DEFERRED |

Same failure mode as F-28-12 on a different endpoint: OpenAPI `phase: type: integer`, Zod `phase: z.string()`. Handler at `history.ts:107,121` selects `levelTransitions.phase` from the DB and emits it as string. OpenAPI-typed consumers would parse as integer and fail on string input.

**Severity justification:** LOW per severity rule #1 (caller-breaking type mismatch).

**Resolution rationale:** DEFERRED — update OpenAPI to `type: string` with an enum if the phase column has a finite value domain.

---

#### F-28-15: `addressParamSchema` on `/history/player/{address}` — initial over-flag (rescinded)

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 225 (`225-03-REQUEST-SCHEMA-AUDIT.md`, null / rescinded) |
| **Direction** | code→docs |
| **File** | `/home/zak/Dev/PurgeGame/database/docs/openapi.yaml:1305-1310` |
| **Resolution** | INFO-ACCEPTED |

Initial comparison table flagged `/history/player/:address` as missing `required: true` on its address path parameter. Re-read confirmed `required: true` is present at line 1308; alignment is exact with Zod's non-`.optional()` `addressParamSchema.address`. ID preserved per D-225-06 sequential-allocation rule to avoid downstream traceability drift.

**Severity justification:** INFO — null entry; no defect exists.

**Resolution rationale:** INFO-ACCEPTED — rescinded on re-read; no remediation action.

---

#### F-28-16: OpenAPI lacks `pattern: "^0x[a-fA-F0-9]{40}$"` on 6 address-family path parameters (systemic)

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Source** | Phase 225 (`225-03-REQUEST-SCHEMA-AUDIT.md`, systemic consolidation) |
| **Direction** | code→docs |
| **File** | 6 sites in `/home/zak/Dev/PurgeGame/database/docs/openapi.yaml`: `:599-605, :666-672, :815-821, :1305-1310, :1350-1355, :1398-1403` ↔ Zod `/home/zak/Dev/PurgeGame/database/src/api/schemas/common.ts:5` |
| **Resolution** | DEFERRED |

Zod's `addressParamSchema` enforces `/^0x[a-fA-F0-9]{40}$/` at runtime on 6 address-family path parameters. OpenAPI declares only `type: string` with no `pattern:` at any of the 6 sites. Clients generated from OpenAPI emit no format validation; a consumer submitting `"not-an-address"` passes generated-client validation and fails at the server with a Zod 400.

**Severity justification:** LOW per 225-CONTEXT.md severity rule 4 — regex/format that Zod enforces but OpenAPI does not document; compliant OpenAPI-generated clients can crash at runtime.

**Resolution rationale:** DEFERRED — add `pattern:` to each of the 6 OpenAPI parameter blocks.

---

#### F-28-17: `limit` query parameter default mismatch — OpenAPI `default: 50` vs Zod `.default(20)` (systemic, 3 endpoints)

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Source** | Phase 225 (`225-03-REQUEST-SCHEMA-AUDIT.md`, systemic consolidation) |
| **Direction** | code→docs |
| **File** | `/home/zak/Dev/PurgeGame/database/docs/openapi.yaml:1218-1222, :1268-1272, :1315-1319` ↔ `/home/zak/Dev/PurgeGame/database/src/api/schemas/common.ts:17` + `/home/zak/Dev/PurgeGame/database/src/api/schemas/history.ts:39,44` |
| **Resolution** | DEFERRED |

All three Zod schemas declare `limit: z.coerce.number().int().min(1).max(100).default(20)`. All three OpenAPI blocks declare `type: integer, default: 50` (no `minimum:`, no `maximum:`). Caller omitting `?limit=` gets 20 items at runtime, not the documented 50 — caller-observable pagination page-size drift of 60%. Additionally, `min(1)` and `max(100)` are not reflected in OpenAPI: compliant consumers submitting `limit=500` get a 400.

**Severity justification:** LOW — caller-observable in happy-path traffic; paginating UIs that allocate based on OpenAPI's `default: 50` would mis-label cursor boundaries.

**Resolution rationale:** DEFERRED — update OpenAPI to `default: 20, minimum: 1, maximum: 100` on all 3 sites.

---

#### F-28-18: OpenAPI declares `minimum:` on 4 optional query parameters that Zod does not enforce

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 225 (`225-03-REQUEST-SCHEMA-AUDIT.md`, systemic consolidation) |
| **Direction** | code→docs |
| **File** | `/home/zak/Dev/PurgeGame/database/docs/openapi.yaml:1099-1104, :1135-1140, :1171-1176, :1207-1212` ↔ `/home/zak/Dev/PurgeGame/database/src/api/schemas/{leaderboard,history}.ts` |
| **Resolution** | DEFERRED |

OpenAPI blocks declare `minimum: 0` or `minimum: 1` on `day`/`level` query params; Zod uses `z.coerce.number().int().optional()` with no `.min(...)`. A caller submitting `day=-1` or `level=-5` passes Zod validation and the SQL runs with a silent no-result filter.

**Severity justification:** INFO — no crash, no 400; silent "no data found" for typos. Not directly caller-breaking on happy paths.

**Resolution rationale:** DEFERRED — 225-03 recommended `RESOLVED-CODE` (add `.min(0)`/`.min(1)` to Zod, tightens the contract).

---

#### F-28-19: `/leaderboards/coinflip?day` alignment confirmed — initial over-flag (rescinded)

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 225 (`225-03-REQUEST-SCHEMA-AUDIT.md`, null / rescinded) |
| **Direction** | code→docs |
| **File** | `/home/zak/Dev/PurgeGame/database/docs/openapi.yaml:1098-1104` ↔ `/home/zak/Dev/PurgeGame/database/src/api/schemas/leaderboard.ts:22` |
| **Resolution** | INFO-ACCEPTED |

Initial pass flagged this as a canonical "required parameter documented optional" case; re-read confirmed OpenAPI declares the param optional (no `required: true`) and Zod declares `.optional()` — alignment is exact. ID preserved per D-225-06.

**Severity justification:** INFO — null entry; no defect exists.

**Resolution rationale:** INFO-ACCEPTED — rescinded on re-read; no remediation.

---

#### F-28-20: `errorResponseSchema` dead import in `routes/game.ts`

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 225 (`225-03-REQUEST-SCHEMA-AUDIT.md`, code-only) |
| **Direction** | code→docs |
| **File** | `/home/zak/Dev/PurgeGame/database/src/api/routes/game.ts:9` |
| **Resolution** | DEFERRED |

`errorResponseSchema` is imported but never attached to any `response[...]` block in `game.ts`. The 4 handlers that emit 404 (`/game/jackpot/:level`, `/roll1`, `/roll2`, `/earliest-day`) call `reply.notFound(...)` in their bodies but do not register `404: errorResponseSchema` in their Fastify schemas — unlike `player.ts:22,230` and `viewer.ts:172,323` which do register it.

**Severity justification:** INFO — dead import; tree-shakeable; no runtime impact. Maintainability / cleanup candidate.

**Resolution rationale:** DEFERRED — either remove the import or register `404: errorResponseSchema` on the 4 game.ts handlers (preferred — closes the gap highlighted by F-28-03/F-28-04).

---

#### F-28-21: Regex character-class drift between `addressParamSchema` and `jackpotPlayerParamsSchema.addr`

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 225 (`225-03-REQUEST-SCHEMA-AUDIT.md`, code-only) |
| **Direction** | code→docs |
| **File** | `/home/zak/Dev/PurgeGame/database/src/api/schemas/common.ts:5` and `/home/zak/Dev/PurgeGame/database/src/api/schemas/game.ts:58` |
| **Resolution** | DEFERRED |

Two address regexes with different character-class orderings: `/^0x[a-fA-F0-9]{40}$/` (common.ts) vs `/^0x[0-9a-fA-F]{40}$/` (game.ts). JavaScript regex engines treat both as identical sets; the divergence is cosmetic only.

**Severity justification:** INFO — zero caller impact; cosmetic DRY violation.

**Resolution rationale:** DEFERRED — consolidate to a single exported `ETH_ADDRESS_REGEX` constant.

---

#### F-28-22: `playerAddressParamSchema` in `routes/replay.ts` lacks the 0x-format regex

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Source** | Phase 225 (`225-03-REQUEST-SCHEMA-AUDIT.md`) |
| **Direction** | code→docs |
| **File** | `/home/zak/Dev/PurgeGame/database/src/api/routes/replay.ts:56-58` (used at `:327` for `GET /replay/player-traits/:address`) |
| **Resolution** | DEFERRED |

`playerAddressParamSchema = z.object({ address: z.string().min(1) })` — accepts any non-empty string. Every other address-accepting endpoint uses `addressParamSchema` with the 0x-hex regex. Handler at `replay.ts:332` lowercases the input and queries `traits_generated WHERE player = '<value>'` — submitting `"hello-world"` returns an empty success.

**Severity justification:** LOW per severity rule 4 — security/type-safety adjacent; uniform-client consumers expecting consistent address validation across the API are surprised silently.

**Resolution rationale:** DEFERRED — `RESOLVED-CODE` candidate: replace inline schema with a reference to `addressParamSchema` from `common.ts`.

---

#### F-28-23: Intra-code schema-name drift — `dayParamSchema`, `levelParamSchema`, `levelQuerySchema` defined differently across files

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 225 (`225-03-REQUEST-SCHEMA-AUDIT.md`, code-only) |
| **Direction** | code→docs |
| **File** | `/home/zak/Dev/PurgeGame/database/src/api/routes/game.ts:14` vs `routes/replay.ts:11`; `/home/zak/Dev/PurgeGame/database/src/api/schemas/game.ts:23` vs `routes/replay.ts:32`; `/home/zak/Dev/PurgeGame/database/src/api/schemas/history.ts:42` vs `schemas/leaderboard.ts:25` |
| **Resolution** | DEFERRED |

Three name-collision groups: (1) `dayParamSchema` — bounded `.max(100000)` in game.ts vs unbounded in replay.ts (intentional per T-39-04 but not a shared constant); (2) `levelParamSchema` — identical shapes in two locations (DRY violation); (3) `levelQuerySchema` — `{cursor, limit}` in history.ts vs `{level}` in leaderboard.ts (shape collision on the same import name). Case 1 is a real intra-API behavior difference: `/replay/day/:day` accepts `day=999999999` where `/game/jackpot/day/:day/winners` rejects it.

**Severity justification:** INFO — maintainability gap; TypeScript disambiguates by import path so no compile-time conflict, but reader cognitive load is non-trivial.

**Resolution rationale:** DEFERRED — consolidate into a single declaration site (e.g., a new `src/api/schemas/params.ts`).

---

### Phase 226: Schema ↔ Migration Orphan Audit (10 findings)

#### F-28-24: `0007_trait_burn_tickets.sql` applied without matching `0007_snapshot.json`

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 226 (`226-02-MIGRATION-TRACE.md`) |
| **Direction** | schema↔migration |
| **File** | `/home/zak/Dev/PurgeGame/database/drizzle/0007_trait_burn_tickets.sql:1` + `database/drizzle/meta/_journal.json` (no `idx: 7`) |
| **Resolution** | DEFERRED |

`0007_trait_burn_tickets.sql` exists (2 `CREATE TABLE` + 2 `CREATE INDEX` statements) but the drizzle-kit meta snapshot `0007_snapshot.json` is absent and `_journal.json` has no `idx: 7` entry. Tooling that trusts `_journal.json` as source of truth (including future `drizzle-kit generate`) will silently omit these tables and may regenerate them as a fresh migration, producing duplicate DDL.

**Severity justification:** INFO — safe at runtime (migration already applied); impact is on future tooling runs. D-226-01 designates cumulative `.sql` as primary ground truth, so current audit coverage is intact.

**Resolution rationale:** DEFERRED — regenerate snapshot via `drizzle-kit generate --custom` or equivalent; update `_journal.json` to include `idx: 7`.

---

#### F-28-25: `jackpot_distributions` TS schema carries 6 extra columns + column rename not in any migration

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Source** | Phase 226 (`226-01-SCHEMA-MIGRATION-DIFF.md`) |
| **Direction** | schema↔migration |
| **File** | `/home/zak/Dev/PurgeGame/database/src/db/schema/jackpot-history.ts:3-24` ↔ `database/drizzle/0001_handy_exiles.sql:126-138` |
| **Resolution** | DEFERRED |

TS declares `sourceLevel`, `winnerLevel`, `awardType text().notNull().default('eth')`, `rebuyLevel`, `rebuyTickets`, `halfPassCount` plus renames `distributionType` → `awardType`. The SQL created `jackpot_distributions` with `distributionType text DEFAULT 'ticket' NOT NULL`; no subsequent migration adds the extras or performs the rename. Any INSERT from TS that omits the column writes `'ticket'` not `'eth'` — silent wrong-result.

**Severity justification:** LOW — silent wrong-result risk on any insert path that relies on the Drizzle-declared default. Next `drizzle-kit generate` could DROP+ADD the column and change the default in-flight.

**Resolution rationale:** DEFERRED — next migration must ADD the six columns and RENAME `distributionType` → `awardType` with the correct default semantics.

---

#### F-28-26: `jackpot_distributions` extra TS index not in any migration

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Source** | Phase 226 (`226-01-SCHEMA-MIGRATION-DIFF.md`) |
| **Direction** | schema↔migration |
| **File** | `/home/zak/Dev/PurgeGame/database/src/db/schema/jackpot-history.ts:23` (double-declared at `database/src/db/schema/indexes.ts:14`) |
| **Resolution** | DEFERRED |

`index('jackpot_dist_level_block_log_idx').on(table.level, table.blockNumber, table.logIndex)` is declared in the Drizzle `pgTable` second-arg AND as a raw-SQL `CREATE INDEX IF NOT EXISTS` in `indexes.ts:14`, but no `.sql` migration creates it. Double-declaration risks drizzle-kit CREATE/DROP cycles depending on whether `indexes.ts` bootstrap runs first.

**Severity justification:** LOW — a future `drizzle-kit generate` run without the `indexes.ts` bootstrap could emit conflicting DDL.

**Resolution rationale:** DEFERRED — dedupe by keeping the TS `index(...)` declaration and removing from `indexes.ts`, then regenerate the migration.

---

#### F-28-27: `decimator_rounds` TS schema has `packedOffsets` and `resolved` columns not in any migration

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Source** | Phase 226 (`226-01-SCHEMA-MIGRATION-DIFF.md`) |
| **Direction** | schema↔migration |
| **File** | `/home/zak/Dev/PurgeGame/database/src/db/schema/decimator.ts:47-48` ↔ `database/drizzle/0001_handy_exiles.sql:186-194` |
| **Resolution** | DEFERRED |

TS declares `packedOffsets: text()` and `resolved: boolean().notNull().default(false)`. Neither column exists in the applied SQL. Any drizzle client `SELECT packedOffsets, resolved FROM decimator_rounds` fails at runtime.

**Severity justification:** LOW — silent wrong-result / runtime error on read paths that reference these columns.

**Resolution rationale:** DEFERRED — next migration ADDs the two columns.

---

#### F-28-28: `daily_winning_traits` entire table missing from migrations

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Source** | Phase 226 (`226-01-SCHEMA-MIGRATION-DIFF.md`) |
| **Direction** | schema↔migration |
| **File** | `/home/zak/Dev/PurgeGame/database/src/db/schema/new-events.ts:89-104` ↔ no `.sql` migration creates it |
| **Resolution** | DEFERRED |

TS declares `dailyWinningTraits = pgTable('daily_winning_traits', {...})`; no `CREATE TABLE "daily_winning_traits"` appears in any of `0000..0007*.sql`, and `0006_snapshot.json` also lacks the table. Any read/write to this table via drizzle raises `relation "daily_winning_traits" does not exist`.

**Severity justification:** LOW — runtime failure on any dependent code path. In practice the existing call sites in API handlers (per 226-04 orphan scan: 1 write + 3 reads from `api/routes/game.ts`) would fail.

**Resolution rationale:** DEFERRED — next migration CREATEs the table + its `daily_winning_traits_day_idx` index (F-28-29).

---

#### F-28-29: `daily_winning_traits_day_idx` missing from migrations

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 226 (`226-01-SCHEMA-MIGRATION-DIFF.md`) |
| **Direction** | schema↔migration |
| **File** | `/home/zak/Dev/PurgeGame/database/src/db/schema/new-events.ts:103` |
| **Resolution** | DEFERRED |

Follows from F-28-28: if the table does not exist, its index does not exist either. Recorded as a distinct stub so index-count tallies stay consistent.

**Severity justification:** INFO — consequential to F-28-28; fixes together.

**Resolution rationale:** DEFERRED — generated with the missing table in the same migration.

---

#### F-28-30: `indexes.ts` duplicates TS-declared `jackpot_dist_level_block_log_idx`

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 226 (`226-01-SCHEMA-MIGRATION-DIFF.md`) |
| **Direction** | schema↔migration |
| **File** | `/home/zak/Dev/PurgeGame/database/src/db/schema/indexes.ts:14` + `/home/zak/Dev/PurgeGame/database/src/db/schema/jackpot-history.ts:23` |
| **Resolution** | INFO-ACCEPTED |

The same index is declared in two code paths (raw-SQL bootstrap + Drizzle `pgTable` second-arg). Harmless at runtime (the bootstrap uses `IF NOT EXISTS`); muddles provenance for future tooling.

**Severity justification:** INFO — no runtime impact; maintainability observation.

**Resolution rationale:** INFO-ACCEPTED — promotion to KNOWN-ISSUES suppressed per v28.0 scope directive D-229-10. Dedupe at author discretion.

---

#### F-28-31: `prize_pools.lastLevelPool` column present in meta/TS but the `.sql` file for its migration is empty

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Source** | Phase 226 (`226-01-SCHEMA-MIGRATION-DIFF.md`) |
| **Direction** | schema↔migration |
| **File** | `/home/zak/Dev/PurgeGame/database/drizzle/0005_red_doctor_octopus.sql` (0 bytes) + `database/drizzle/meta/0005_snapshot.json` |
| **Resolution** | DEFERRED |

TS schema declares `lastLevelPool: text().notNull().default('0')` on `prize_pools`; `meta/0005_snapshot.json` includes the column; but `0005_red_doctor_octopus.sql` is 0 bytes on disk. At live-DB migrate time drizzle-kit reconstructs the DDL from the meta chain, but any DBA replaying `.sql` files directly would miss this column.

**Severity justification:** LOW — silent schema-apply mismatch if someone executes `.sql` files one by one, leading to a broken DB state.

**Resolution rationale:** DEFERRED — regenerate the 0005 `.sql` body OR add a new migration and mark 0005 superseded.

---

#### F-28-32: drizzle-kit meta-chain integrity break between `0002_snapshot.json` and `0003_snapshot.json`

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Source** | Phase 226 (`226-02-MIGRATION-TRACE.md`) |
| **Direction** | schema↔migration |
| **File** | `/home/zak/Dev/PurgeGame/database/drizzle/meta/0003_snapshot.json:1` |
| **Resolution** | DEFERRED |

`0002_snapshot.json.id = c17464db-b927-4faa-94b7-b225a54dd4d9`; `0003_snapshot.json.prevId = 55335792-...`. The `55335792-...` UUID does not appear as the `id` of any snapshot in `drizzle/meta/`. Chain is intact 0000→0001→0002 and 0003→0004→0005→0006, but the 0002↔0003 join is broken.

**Severity justification:** LOW — safe for runtime (migrations already applied); forecloses `drizzle-kit check` adoption as a future CI gate without regeneration.

**Resolution rationale:** DEFERRED — regenerate the snapshot chain or rewrite `0003_snapshot.json.prevId`.

---

#### F-28-33: `quest_definitions.difficulty` dropped by 0006 migration but still declared in TS schema

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Source** | Phase 226 (`226-02-MIGRATION-TRACE.md`) |
| **Direction** | schema↔migration |
| **File** | `/home/zak/Dev/PurgeGame/database/src/db/schema/quests.ts:11` ↔ `database/drizzle/0006_freezing_weapon_omega.sql:210` |
| **Resolution** | DEFERRED |

Migration 0006 emits `ALTER TABLE "quest_definitions" DROP COLUMN "difficulty";` and `0006_snapshot.json` reflects the drop. TS declaration in `quests.ts:11` still defines `difficulty: smallint().notNull()`. Any drizzle-generated INSERT against `quest_definitions` will try to populate a column that does not exist → runtime failure on any write path.

**Severity justification:** LOW — functional regression blocker on write paths that reach `quest_definitions`. Highest-severity finding from Phase 226.

**Resolution rationale:** DEFERRED — remove `difficulty` from `quests.ts:11`.

---

### Phase 227: Indexer Event Processing Correctness (31 findings)

#### F-28-34: UNHANDLED event `Approval` on BurnieCoin

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 227 (`227-01-EVENT-COVERAGE-MATRIX.md`) |
| **Direction** | schema↔handler |
| **File** | `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/BurnieCoin.sol:55` ↔ `database/src/handlers/index.ts` (no registry key; skip-comment at `:374-376` covers DGNRS Approval only) |
| **Resolution** | INFO-ACCEPTED |

ERC-20 `Approval` log-only event; no domain-table mapping required for analytics. `raw_events` still lands the row.

**Severity justification:** INFO — log-only token event; no production impact.

**Resolution rationale:** INFO-ACCEPTED — extend the Approval skip-comment to cover all four ERC-20 tokens. Promotion to KNOWN-ISSUES suppressed per D-229-10.

---

#### F-28-35: UNHANDLED event `CoordinatorUpdated` on DegenerusAdmin

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 227 (`227-01-EVENT-COVERAGE-MATRIX.md`) |
| **Direction** | schema↔handler |
| **File** | `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusAdmin.sol:245` |
| **Resolution** | INFO-ACCEPTED |

Admin-only governance event. `raw_events` retains; no schema writer.

**Severity justification:** INFO — admin governance; no gameplay/analytics impact.

**Resolution rationale:** INFO-ACCEPTED — extend admin-events skip-comment at `handlers/index.ts:293-295`.

---

#### F-28-36: UNHANDLED event `ConsumerAdded` on DegenerusAdmin

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 227 (`227-01-EVENT-COVERAGE-MATRIX.md`) |
| **Direction** | schema↔handler |
| **File** | `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusAdmin.sol:249` |
| **Resolution** | INFO-ACCEPTED |

Admin-only event; no registry key.

**Severity justification:** INFO — admin only.

**Resolution rationale:** INFO-ACCEPTED via skip-comment extension.

---

#### F-28-37: UNHANDLED event `SubscriptionCreated` on DegenerusAdmin

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 227 (`227-01-EVENT-COVERAGE-MATRIX.md`) |
| **Direction** | schema↔handler |
| **File** | `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusAdmin.sol:250` |
| **Resolution** | INFO-ACCEPTED |

Admin VRF subscription lifecycle event.

**Severity justification:** INFO — admin only.

**Resolution rationale:** INFO-ACCEPTED via skip-comment extension.

---

#### F-28-38: UNHANDLED event `SubscriptionCancelled` on DegenerusAdmin

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 227 (`227-01-EVENT-COVERAGE-MATRIX.md`) |
| **Direction** | schema↔handler |
| **File** | `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusAdmin.sol:251` |
| **Resolution** | INFO-ACCEPTED |

Admin-only subscription-lifecycle event.

**Severity justification:** INFO — admin only.

**Resolution rationale:** INFO-ACCEPTED.

---

#### F-28-39: UNHANDLED event `SubscriptionShutdown` on DegenerusAdmin

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 227 (`227-01-EVENT-COVERAGE-MATRIX.md`) |
| **Direction** | schema↔handler |
| **File** | `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusAdmin.sol:252` |
| **Resolution** | INFO-ACCEPTED |

Admin-only event.

**Severity justification:** INFO — admin only.

**Resolution rationale:** INFO-ACCEPTED.

---

#### F-28-40: UNHANDLED collision — `ProposalCreated` on DegenerusAdmin dispatched to GNRUS handler

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Source** | Phase 227 (`227-01-EVENT-COVERAGE-MATRIX.md`) |
| **Direction** | schema↔handler |
| **File** | `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusAdmin.sol:261` (5-arg: `proposalId, proposer, coordinator, keyHash, path`) ↔ `database/src/handlers/index.ts:379` → `handleProposalCreated` in `handlers/gnrus-governance.ts` (expects GNRUS 4-arg: `level, proposalId, proposer, recipient`) |
| **Resolution** | DEFERRED |

Shared event name on different contracts with different argument shapes; registry keys by event-name only. Runtime dispatches ADMIN `ProposalCreated` logs to the GNRUS-shaped handler → silent arg-mismatch (either viem decoding throws or the handler writes nonsense to `gnrus_proposals`).

**Severity justification:** LOW — active handler-router collision risk. Matches the duplicate-name cross-join trap in 227-RESEARCH.md.

**Resolution rationale:** DEFERRED — add an `ADDRESS_TO_CONTRACT` router to `handleProposalCreated` that branches ADMIN vs GNRUS; contract-side rename is out of this phase's scope per D-227-01.

---

#### F-28-41: UNHANDLED event `VoteCast` on DegenerusAdmin

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 227 (`227-01-EVENT-COVERAGE-MATRIX.md`) |
| **Direction** | schema↔handler |
| **File** | `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusAdmin.sol:268` |
| **Resolution** | INFO-ACCEPTED |

Admin governance voting event.

**Severity justification:** INFO — admin only.

**Resolution rationale:** INFO-ACCEPTED via skip-comment extension.

---

#### F-28-42: UNHANDLED event `ProposalExecuted` on DegenerusAdmin

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 227 (`227-01-EVENT-COVERAGE-MATRIX.md`) |
| **Direction** | schema↔handler |
| **File** | `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusAdmin.sol:274` |
| **Resolution** | INFO-ACCEPTED |

Admin governance lifecycle.

**Severity justification:** INFO — admin only.

**Resolution rationale:** INFO-ACCEPTED.

---

#### F-28-43: UNHANDLED event `ProposalKilled` on DegenerusAdmin

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 227 (`227-01-EVENT-COVERAGE-MATRIX.md`) |
| **Direction** | schema↔handler |
| **File** | `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusAdmin.sol:279` |
| **Resolution** | INFO-ACCEPTED |

Admin governance lifecycle.

**Severity justification:** INFO — admin only.

**Resolution rationale:** INFO-ACCEPTED.

---

#### F-28-44: UNHANDLED event `FeedProposalCreated` on DegenerusAdmin

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 227 (`227-01-EVENT-COVERAGE-MATRIX.md`) |
| **Direction** | schema↔handler |
| **File** | `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusAdmin.sol:370` |
| **Resolution** | INFO-ACCEPTED |

Admin feed-governance lifecycle.

**Severity justification:** INFO — admin only.

**Resolution rationale:** INFO-ACCEPTED.

---

#### F-28-45: UNHANDLED event `FeedVoteCast` on DegenerusAdmin

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 227 (`227-01-EVENT-COVERAGE-MATRIX.md`) |
| **Direction** | schema↔handler |
| **File** | `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusAdmin.sol:376` |
| **Resolution** | INFO-ACCEPTED |

Admin feed-governance lifecycle.

**Severity justification:** INFO — admin only.

**Resolution rationale:** INFO-ACCEPTED.

---

#### F-28-46: UNHANDLED event `FeedProposalExecuted` on DegenerusAdmin

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 227 (`227-01-EVENT-COVERAGE-MATRIX.md`) |
| **Direction** | schema↔handler |
| **File** | `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusAdmin.sol:382` |
| **Resolution** | INFO-ACCEPTED |

Admin feed-governance lifecycle.

**Severity justification:** INFO — admin only.

**Resolution rationale:** INFO-ACCEPTED.

---

#### F-28-47: UNHANDLED event `FeedProposalKilled` on DegenerusAdmin

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 227 (`227-01-EVENT-COVERAGE-MATRIX.md`) |
| **Direction** | schema↔handler |
| **File** | `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusAdmin.sol:383` |
| **Resolution** | INFO-ACCEPTED |

Admin feed-governance lifecycle.

**Severity justification:** INFO — admin only.

**Resolution rationale:** INFO-ACCEPTED.

---

#### F-28-48: UNHANDLED event `RendererUpdated` on DegenerusDeityPass

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 227 (`227-01-EVENT-COVERAGE-MATRIX.md`) |
| **Direction** | schema↔handler |
| **File** | `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusDeityPass.sol:60` |
| **Resolution** | INFO-ACCEPTED |

Admin-only renderer swap event.

**Severity justification:** INFO — admin only; cosmetic.

**Resolution rationale:** INFO-ACCEPTED via skip-comment extension.

---

#### F-28-49: UNHANDLED event `RenderColorsUpdated` on DegenerusDeityPass

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 227 (`227-01-EVENT-COVERAGE-MATRIX.md`) |
| **Direction** | schema↔handler |
| **File** | `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusDeityPass.sol:61` |
| **Resolution** | INFO-ACCEPTED |

Admin-only render-config event.

**Severity justification:** INFO — admin only; cosmetic.

**Resolution rationale:** INFO-ACCEPTED via skip-comment extension.

---

#### F-28-50: UNHANDLED event `YearSweep` on DegenerusStonk

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Source** | Phase 227 (`227-01-EVENT-COVERAGE-MATRIX.md`) |
| **Direction** | schema↔handler |
| **File** | `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusStonk.sol:299` |
| **Resolution** | DEFERRED |

Annual DGNRS sweep event carries 4 values (`ethToGnrus, stethToGnrus, ethToVault, stethToVault`) — a non-trivial capital flow. No registry key, no skip-comment. Missing from analytics.

**Severity justification:** LOW — non-trivial capital flow currently undocumented in domain-table writes.

**Resolution rationale:** DEFERRED — add `YearSweep: handleYearSweep` with a dedicated schema row.

---

#### F-28-51: UNHANDLED (router-hidden) `Transfer` on DegenerusVault

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Source** | Phase 227 (`227-01-EVENT-COVERAGE-MATRIX.md`) |
| **Direction** | schema↔handler |
| **File** | `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusVault.sol:191` ↔ `database/src/handlers/token-balances.ts:38` (`ADDRESS_TO_CONTRACT` omits VAULT) |
| **Resolution** | DEFERRED |

Vault issues DGVE/DGVB share tokens; every transfer/mint/burn fires `Transfer`. The token-balances router covers COIN/DGNRS/SDGNRS/WWXRP/DEITY_PASS but not VAULT, so transfers are silently dropped via `if (!contractName) return` at `:166`. Share-supply snapshots currently rely on derived deposit/claim math (correct but undocumented).

**Severity justification:** LOW — silently-dropped balance events; analytics completeness gap.

**Resolution rationale:** DEFERRED — extend `ADDRESS_TO_CONTRACT` to include VAULT + add `handleVaultTransfer`, OR document the design choice in `index.ts` comments with an explicit skip.

---

#### F-28-52: UNHANDLED event `Approval` on DegenerusVault

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 227 (`227-01-EVENT-COVERAGE-MATRIX.md`) |
| **Direction** | schema↔handler |
| **File** | `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusVault.sol:196` |
| **Resolution** | INFO-ACCEPTED |

Log-only token event; no analytics requirement.

**Severity justification:** INFO — same class as F-28-34.

**Resolution rationale:** INFO-ACCEPTED via broader Approval skip-comment.

---

#### F-28-53: UNHANDLED (router-hidden) `Transfer` on GNRUS

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Source** | Phase 227 (`227-01-EVENT-COVERAGE-MATRIX.md`) |
| **Direction** | schema↔handler |
| **File** | `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/GNRUS.sol:104` ↔ `database/src/handlers/token-balances.ts:38` |
| **Resolution** | DEFERRED |

GNRUS is an ERC-20 with `Transfer` emission; `ADDRESS_TO_CONTRACT` omits GNRUS → governance-token holder analytics has silent zero coverage.

**Severity justification:** LOW — analytics gap on governance token.

**Resolution rationale:** DEFERRED — add GNRUS to the token-balances address map; either wire a `handleGnrusTransfer` branch or explicitly no-op with documentation.

---

#### F-28-54: UNHANDLED collision — `Burn` on GNRUS dispatched to SDGNRS handler

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Source** | Phase 227 (`227-01-EVENT-COVERAGE-MATRIX.md`) |
| **Direction** | schema↔handler |
| **File** | `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/GNRUS.sol:107` (`Burn(burner, gnrusAmount, ethOut, stethOut)` — 4 args) ↔ `database/src/handlers/index.ts:341` (`Burn: handleSdgnrsBurn`, expects SDGNRS 5-arg `from, amount, ethOut, stethOut, burnieOut`) |
| **Resolution** | DEFERRED |

Same duplicate-name trap as F-28-40. Runtime dispatches GNRUS `Burn` logs to the SDGNRS-shaped handler; either viem decoding throws or the handler writes nonsense to `sdgnrs_burns` with wrong `from` identity and missing `burnieOut`.

**Severity justification:** LOW — active schema-mismatch collision.

**Resolution rationale:** DEFERRED — introduce `handleBurnRouter` branching by `ctx.contractAddress`.

---

#### F-28-55: UNHANDLED event `Approval` on WrappedWrappedXRP

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 227 (`227-01-EVENT-COVERAGE-MATRIX.md`) |
| **Direction** | schema↔handler |
| **File** | `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/WrappedWrappedXRP.sol:42` |
| **Resolution** | INFO-ACCEPTED |

Log-only ERC-20 event.

**Severity justification:** INFO — same class as F-28-34.

**Resolution rationale:** INFO-ACCEPTED via broader Approval skip-comment.

---

#### F-28-56: Registry orphan — `AutoRebuyProcessed` key has no event emitter

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 227 (`227-01-EVENT-COVERAGE-MATRIX.md`, inverse orphan) |
| **Direction** | code↔schema |
| **File** | `/home/zak/Dev/PurgeGame/database/src/handlers/index.ts:288` (`AutoRebuyProcessed: handleAutoRebuyProcessed`); zero matches for `event AutoRebuyProcessed` across `contracts/**/*.sol` |
| **Resolution** | INFO-ACCEPTED |

Handler registry references an event name no contract emits. The handler is dead code until/unless the event is re-introduced.

**Severity justification:** INFO — no runtime impact (zero dispatches); dead code only. Notable pattern worth carrying into future milestones (inverse orphan).

**Resolution rationale:** INFO-ACCEPTED — retain or remove at indexer-team discretion. Promotion to KNOWN-ISSUES suppressed per D-229-10.

---

#### F-28-57: `DailyRngApplied.nudges` silent truncation via `Number(parseBigInt(...))`

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Source** | Phase 227 (`227-02-EVENT-ARG-MAPPING.md`) |
| **Direction** | schema↔handler |
| **File** | `/home/zak/Dev/PurgeGame/database/src/handlers/daily-rng.ts:22` ↔ `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/modules/DegenerusGameAdvanceModule.sol:76` (`uint256 nudges`) |
| **Resolution** | DEFERRED |

Handler: `const nudges = Number(parseBigInt(ctx.args.nudges));`. Solidity arg type is `uint256` → narrowing to a JS `number` (max safe integer 2^53) silently truncates values >2^53.

**Severity justification:** LOW — runtime range is empirically small today, but the type-surface leak admits silent wrong-result if runtime values ever approach 2^53.

**Resolution rationale:** DEFERRED — `RESOLVED-CODE` candidate: replace with `parseBigInt(...).toString()` and widen the column to `numeric`/`text`, OR narrow the Solidity arg to `uint32`.

---

#### F-28-58: `LootboxRngApplied.index` uint48 narrowed to JS number

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 227 (`227-02-EVENT-ARG-MAPPING.md`) |
| **Direction** | schema↔handler |
| **File** | `/home/zak/Dev/PurgeGame/database/src/handlers/daily-rng.ts:42` |
| **Resolution** | INFO-ACCEPTED |

Handler: `const lootboxIndex = Number(parseBigInt(ctx.args.index));`. Solidity arg is `uint48` — max value ≈ 2.8×10^14, well below `Number.MAX_SAFE_INTEGER` (2^53 ≈ 9×10^15). No runtime overflow possible.

**Severity justification:** INFO — type-surface leak only; no runtime truncation risk.

**Resolution rationale:** INFO-ACCEPTED — optional `RESOLVED-CODE` for uniformity. Promotion to KNOWN-ISSUES suppressed per D-229-10.

---

#### F-28-59: `TerminalDecBurnRecorded.timeMultBps` silent truncation

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Source** | Phase 227 (`227-02-EVENT-ARG-MAPPING.md`) |
| **Direction** | schema↔handler |
| **File** | `/home/zak/Dev/PurgeGame/database/src/handlers/decimator.ts:465` ↔ `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/modules/DegenerusGameDecimatorModule.sol:600` (`uint256 timeMultBps`) |
| **Resolution** | DEFERRED |

Handler: `const timeMultBps = Number(parseBigInt(ctx.args.timeMultBps));`. `uint256` narrowed to JS number.

**Severity justification:** LOW — realistic runtime range for a bps multiplier is ≤2^32, but the contract arg type admits wider values.

**Resolution rationale:** DEFERRED — narrow contract arg to `uint32` OR widen DB column + `parseBigInt(.).toString()`.

---

#### F-28-60: DeityPass `Transfer.tokenId` uint256 narrowed to JS number

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Source** | Phase 227 (`227-02-EVENT-ARG-MAPPING.md`) |
| **Direction** | schema↔handler |
| **File** | `/home/zak/Dev/PurgeGame/database/src/handlers/deity-pass.ts:64` ↔ `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusDeityPass.sol:59` (ERC-721 `uint256 indexed tokenId`) |
| **Resolution** | DEFERRED |

Handler: `const tokenId = Number(parseBigInt(ctx.args.tokenId ?? ctx.args.value));`. ERC-721 tokenIds are canonically uint256 and best handled as strings/numeric.

**Severity justification:** LOW — standard ERC-721 practice is `parseBigInt(.).toString()` + `numeric`/`text` column.

**Resolution rationale:** DEFERRED — `RESOLVED-CODE` per standard practice.

---

#### F-28-61: `JackpotWhalePassWin.halfPassCount` silent truncation

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Source** | Phase 227 (`227-02-EVENT-ARG-MAPPING.md`) |
| **Direction** | schema↔handler |
| **File** | `/home/zak/Dev/PurgeGame/database/src/handlers/jackpot.ts:112` ↔ `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/modules/DegenerusGameJackpotModule.sol:111` (`uint256 halfPassCount`) |
| **Resolution** | DEFERRED |

Handler: `const halfPassCount = Number(parseBigInt(ctx.args.halfPassCount));`. Realistic cap is small but the contract arg type is `uint256`.

**Severity justification:** LOW — type-surface leak on a domain-critical count.

**Resolution rationale:** DEFERRED — narrow Solidity arg to `uint32` OR widen DB column.

---

#### F-28-62: `WhalePassClaimed.halfPasses` silent truncation

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Source** | Phase 227 (`227-02-EVENT-ARG-MAPPING.md`) |
| **Direction** | schema↔handler |
| **File** | `/home/zak/Dev/PurgeGame/database/src/handlers/whale-pass.ts:19` ↔ `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/modules/DegenerusGameWhaleModule.sol:65` (`uint256 halfPasses`) |
| **Resolution** | DEFERRED |

Handler: `const halfPasses = Number(parseBigInt(ctx.args.halfPasses));`. Same class as F-28-61.

**Severity justification:** LOW — type-surface leak on a domain-critical count.

**Resolution rationale:** DEFERRED — same remediation shape as F-28-61.

---

#### F-28-63: `new-events.ts` file header claims "No upsert" but `handleGameOverDrained` upserts `prize_pools`

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 227 (`227-03-INDEXER-COMMENT-AUDIT.md`, Tier B) |
| **Direction** | comment→code |
| **File** | `/home/zak/Dev/PurgeGame/database/src/handlers/new-events.ts:4-5` (comment); `:67-96` (upsert site) |
| **Resolution** | DEFERRED |

File header: "All handlers are simple append-only inserts ... No upsert, no composite logic." `handleGameOverDrained` performs `.onConflictDoUpdate` on `prize_pools` (singleton `id=1`), zeroing pool fields when a `GameOverDrained` event fires — both an upsert AND a composite side-effect on a table outside the event's primary target.

**Severity justification:** INFO — Tier B comment drift; no behavior defect (the upsert is presumably intentional per on-chain semantics). Per D-227-10, whether zeroing pools on `GameOverDrained` is the correct state-machine action is out of 227 scope.

**Resolution rationale:** DEFERRED — patch the header comment to note the `GameOverDrained` upsert branch, or split the file into pure-append vs composite.

---

#### F-28-64: `lootbox.ts` file header claims "All handlers are append-only" but `handleTraitsGenerated` composite path upserts `trait_burn_tickets`

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 227 (`227-03-INDEXER-COMMENT-AUDIT.md`, Tier B) |
| **Direction** | comment→code |
| **File** | `/home/zak/Dev/PurgeGame/database/src/handlers/lootbox.ts:5` (comment); `handlers/index.ts:191-194` (composite wiring); `handlers/traits-generated.ts:46-56` (`.onConflictDoUpdate` site) |
| **Resolution** | DEFERRED |

`handleTraitsGenerated` is listed in `lootbox.ts`'s file docstring as a lootbox handler, but its registry entry wraps it in `handleTraitsGeneratedComposite`, which invokes `handleTraitsGeneratedBuckets` — performing `.onConflictDoUpdate` on `trait_burn_tickets` with SQL-side `ticket_count` addition. The file header misstates the full dispatch surface.

**Severity justification:** INFO — Tier B comment drift; correctness of the running-sum semantics is 228/replay-layer territory per D-227-10.

**Resolution rationale:** DEFERRED — add a caveat line scoping the "all handlers append-only" claim to exclude `handleTraitsGenerated`.

---

### Phase 228: Cursor Reorg & View Refresh State Machines (5 findings)

#### F-28-65: `initializeCursor` "safely" docstring overclaims — no runtime rewind guard

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Source** | Phase 228 (`228-01-CURSOR-REORG-TRACE.md`, origin row M1) |
| **Direction** | comment→code |
| **File** | `/home/zak/Dev/PurgeGame/database/src/indexer/cursor-manager.ts:45` (docstring); `:50-65` (behavior) |
| **Resolution** | DEFERRED |

Docstring claims `initializeCursor` handles "re-initialization safely", but the `.onConflictDoUpdate` unconditionally overwrites `lastProcessedBlock = startBlock`. No live caller triggers silent rewind (main.ts:103/133/225 trace confirms), but the risk is latent: a future caller that inadvertently re-invokes against a healthy cursor would silently truncate progress.

**Severity justification:** LOW — latent risk, not an active bug. Caller-breaking only if re-invocation happens on a running cursor.

**Resolution rationale:** DEFERRED — `RESOLVED-DOC` (retitle "handle re-initialization idempotently") OR `RESOLVED-CODE-FUTURE` (add `WHERE lastProcessedBlock IS NULL OR lastProcessedBlock < excluded.lastProcessedBlock` guard).

---

#### F-28-66: `advanceCursor` transactional requirement unenforced at runtime

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 228 (`228-01-CURSOR-REORG-TRACE.md`, origin row M2) |
| **Direction** | comment→code |
| **File** | `/home/zak/Dev/PurgeGame/database/src/indexer/cursor-manager.ts:70` + type union `:15-19` + signature `:75-83` |
| **Resolution** | INFO-ACCEPTED |

Docstring states `advanceCursor` "requires a transaction" but the `DbOrTx` type union accepts either a `db` or a `tx`. Convention holds today — the only live call at `event-processor.ts:161` passes the tx from `main.ts:188 db.transaction(async (tx) => ...)` — but there is no type-system enforcement.

**Severity justification:** INFO — convention-only is standard in the codebase; duck-typed `DbOrTx` is a deliberate design choice throughout.

**Resolution rationale:** INFO-ACCEPTED — no action required. Promotion to KNOWN-ISSUES suppressed per D-229-10. Future option: split into `advanceCursorInTx(tx: Tx)` with a distinct type.

---

#### F-28-67: ROADMAP IDX-04 "recovery-after-stall" requirement unbacked by code

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 228 (`228-01-CURSOR-REORG-TRACE.md`, origin row M13) |
| **Direction** | docs→code |
| **File** | `/home/zak/Dev/PurgeGame/database/src/indexer/main.ts:216-220` (site of the only "recovery-like" mechanism — a 5-second catch-retry) |
| **Resolution** | DEFERRED |

ROADMAP IDX-04 mentions "recovery-after-stall"; no `stall`, `watchdog`, `deadCursor`, or `timeout` detector exists anywhere in `src/indexer/`. The `try/catch` at `main.ts:216-220` handles thrown errors only, not hangs.

**Severity justification:** INFO — documentation-vs-code gap on an operational concern; no active bug since stalls manifest as the 5s backoff loop rather than permanent failure.

**Resolution rationale:** DEFERRED — `RESOLVED-DOC` (narrow ROADMAP to "5-second error backoff") OR `RESOLVED-CODE-FUTURE` (add watchdog/dead-cursor detector).

---

#### F-28-68: Intra-batch reorg edge case — unmitigated on anvil (`confirmations=0`)

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Source** | Phase 228 (`228-01-CURSOR-REORG-TRACE.md`, origin row E1) |
| **Direction** | docs→code |
| **File** | `/home/zak/Dev/PurgeGame/database/src/indexer/main.ts:155` (`detectReorg` only checks `batchStart`, not the full range) + `/home/zak/Dev/PurgeGame/database/src/config/chains.ts:13` (anvil `confirmations: 0`) |
| **Resolution** | DEFERRED |

Race window: a reorg at `batchStart + k` (k>0) between `detectReorg` at `:155` and the block-header fetch at `:178` would `storeBlock` a pre-reorg hash. Self-healing is confirmed via walk-back in the next iteration (`reorg-detector.ts:113-137`), but the transient stale-hash exists for one batch cycle.

**Severity justification:** LOW — self-healing, no permanent divergence; impact bounded to dev-chain (mainnet `confirmations=64` closes the race).

**Resolution rationale:** DEFERRED — `RESOLVED-CODE-FUTURE` (either reduce `batchSize` when `confirmations=0`, or run `detectReorg` against `batchEnd` after block-header fetch) OR `INFO-ACCEPTED` for dev-chain configs.

---

#### F-28-69: Comment "stale view for one block is acceptable" misrepresents the sustained-failure staleness bound

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Source** | Phase 228 (`228-02-VIEW-REFRESH-AUDIT.md`, origin row M9 / 227-deferral-3) |
| **Direction** | comment→code |
| **File** | `/home/zak/Dev/PurgeGame/database/src/indexer/view-refresh.ts:4-5` (comment); `:28-32, :30-32` (per-view try/catch behavior) |
| **Resolution** | DEFERRED |

The per-view try/catch swallows refresh errors with only `log.error` as signal — no metric counter, no retry, no backoff, no DB staleness timestamp, no alert surface (5 of 6 observability channels absent). Under sustained refresh failure the staleness bound becomes indefinite, not "one block". Resolves a Phase 227 deferral.

**Severity justification:** LOW — operational gap; per 228-CONTEXT.md Deferred Ideas, alerting build-out is explicitly out of audit scope. Comment misleads operators about the true staleness bound under failure.

**Resolution rationale:** DEFERRED — `RESOLVED-CODE-FUTURE` — add refresh-failure metrics/alerts and/or rewrite the comment to describe the sustained-failure bound accurately.

---

*Phase: 229-findings-consolidation, Plan: 01*
*Consolidated by: gsd-executor (claude-opus-4-6)*
*Completed: 2026-04-15*
