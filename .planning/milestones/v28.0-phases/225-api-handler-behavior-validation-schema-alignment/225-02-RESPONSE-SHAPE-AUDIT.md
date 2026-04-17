# Phase 225 Plan 02 — API Response-Shape Audit Catalog (API-04)

**Phase:** 225 — API Handler Behavior & Validation Schema Alignment
**Plan:** 225-02
**Requirement satisfied:** API-04 — actual response shapes returned by handlers match `/home/zak/Dev/PurgeGame/database/docs/openapi.yaml` response schemas (field names, types, optionality, enum values)
**Sampling strategy:** D-225-03 — 8 representative endpoints (one per route file) with recursive Zod-response-tree vs openapi.yaml response-schema field-by-field walk; on any sampled FAIL, audit expands to **all** endpoints in the failing file.
**Direction rule:** D-225-02 — Zod schemas are the runtime source of truth; openapi.yaml is the side that lags. Every finding's direction defaults to `code->docs`. Resolution target defaults to `RESOLVED-DOC` (patch openapi.yaml to match Zod).
**Severity scheme (225-CONTEXT.md "Severity scheme"):**
- **INFO** (default) — documentation drift, no runtime/caller-breaking impact.
- **LOW** (promotion) — caller-breaking: (a) Zod emits `string` where openapi says `number`/`integer` (or vice versa) and the handler actually emits the Zod type, causing JSON consumers generated from openapi to crash; (b) openapi documents a required response field the handler never emits; (c) required request parameter documented optional (API-05 concern, not relevant here).
- Do **not** promote beyond LOW — documentation drift is not a vulnerability class.
**Finding-ID scheme:** D-225-06 — `F-28-225-NN` sequential. Plan 225-01 consumed `F-28-225-01..04`. This plan (225-02) allocates starting from **`F-28-225-05`**. Plan 225-03 continues after.
**Cross-repo convention (D-225-07):** Every file:line cited herein points into `/home/zak/Dev/PurgeGame/database/...`. This audit writes only to the `.planning/phases/225-*/` tree; no files under `database/` are modified.

---

## Audit target and method

### Input universe

The 27 locked HTTP handlers from `.planning/phases/224-api-route-openapi-alignment/224-01-API-ROUTE-MAP.md` Pass 2 (game=9, health=1, history=3, leaderboards=3, player=2, replay=6, tokens=1, viewer=2).

Per-route-file Zod schema sources:

| route file | inline response schemas | imported response schemas |
| --- | --- | --- |
| `src/api/routes/game.ts` | `winnersResponseSchema` (lines 24-48), `latestJackpotDayResponseSchema` (:50-52), `rollWinRowSchema` (:55-67), `rollResponseSchema` (:69-74), `earliestJackpotDayResponseSchema` (:76-78), `dayParamSchema`, `playerDayQuerySchema` (request-side, out of scope here) | `src/api/schemas/game.ts` — `jackpotDistributionSchema`, `jackpotLevelResponseSchema`, `jackpotOverviewRowSchema`, `jackpotOverviewResponseSchema`, `jackpotPlayerResponseSchema`, `gameStateResponseSchema` |
| `src/api/routes/health.ts` | `healthResponseSchema` (:4-10) | — |
| `src/api/routes/history.ts` | — (all imported) | `src/api/schemas/history.ts` — `jackpotHistoryResponseSchema`, `levelHistoryResponseSchema`, `playerActivityResponseSchema` |
| `src/api/routes/leaderboards.ts` | — (all imported) | `src/api/schemas/leaderboard.ts` — `coinflipLeaderboardResponseSchema`, `affiliateLeaderboardResponseSchema`, `bafBracketResponseSchema` |
| `src/api/routes/player.ts` | — (all imported) | `src/api/schemas/player.ts` — `playerDashboardResponseSchema`, `jackpotHistoryByPlayerResponseSchema` |
| `src/api/routes/replay.ts` | `dayDetailResponseSchema` (:15-30), `ticketsResponseSchema` (:36-43), `rngListResponseSchema` (:45-50), `activePlayersResponseSchema` (:52-54), `playerTraitsResponseSchema` (:60-63), plus inline `/distributions/:level` schema (:258-268) | — |
| `src/api/routes/tokens.ts` | — (all imported) | `src/api/schemas/tokens.ts` — `tokenAnalyticsResponseSchema` |
| `src/api/routes/viewer.ts` | `playerDaysResponseSchema` (:72-75) and its components (`dayEntrySchema` :61-70); `daySnapshotResponseSchema` (:150-157) and its components (`holdingsSchema` :77-84, `lootboxPurchaseSchema` :86-91, `lootboxResultSchema` :93-97, `betSchema` :99-102, `betResultSchema` :104-108, `coinflipSchema` :110-114, `questSchema` :116-122, `affiliateSchema` :124-126, `activitySchema` :128-136, `storeSchema` :138-148) | — |

### Comparison methodology

For each sampled endpoint:

1. Open the route registration in `src/api/routes/<file>.ts`, read `schema.response[200]`, and resolve the Zod schema (following imports into `src/api/schemas/*.ts` or reading the inline `const ... = z.object({...})` literal).
2. Open the matching `responses.'200'.content.application/json.schema` block in `docs/openapi.yaml` — for `$ref` entries, resolve into `components.schemas.<name>`.
3. Walk the Zod tree top-down. For each leaf field, emit a row with field path (dot notation) + the Zod type/optional/nullable/enum/format + the openapi type/required/nullable/enum/format + verdict `PASS`/`FAIL`/`PASS-NOTE`.
4. For `z.array(X)`: emit one row with path `<name>` (array wrapper) and a second row `<name>[]` (the item schema).
5. For nested objects: recurse, extending the dot path.
6. Zod-to-openapi type map (D-225-02 interface block):
   - `z.string()` ↔ `type: string`
   - `z.number()` ↔ `type: number`
   - `z.number().int()` ↔ `type: integer`
   - `z.coerce.number()` ↔ `type: number` (coerce is request-side; for responses the emitted value is whatever the handler returns)
   - `z.boolean()` ↔ `type: boolean`
   - `z.object({...})` ↔ `type: object` + `properties:`
   - `z.array(X)` ↔ `type: array` + `items: X`
   - `z.nullable(X)` ↔ `nullable: true` on the field
   - `z.optional(X)` on an object field ↔ NOT in parent's `required:` list
   - `z.enum([...])` ↔ `enum: [...]`
   - `z.literal(X)` ↔ `enum: [X]` single-element or `const: X`
   - `z.tuple([a, b, c])` ↔ `type: array` with `minItems: 3, maxItems: 3` (content varies)
   - `z.unknown()` ↔ no `type:` specified (any JSON value)

7. Per-endpoint verdict: `PASS` if zero FAIL rows, else `FAIL`. On FAIL, emit an `F-28-225-NN` stub per distinct mismatch pattern (systemic mismatches appearing repeatedly across endpoints are consolidated into one systemic finding with a per-endpoint occurrence list, consistent with 225-01's noise-reduction stance; one-off mismatches get their own stubs).

### Stub-consolidation rule

Stubs are emitted at the smallest granularity that communicates the finding:

- **Systemic patterns** (same mismatch pattern in many places — e.g. "Zod `z.number()` vs openapi `integer` throughout") → **one** stub with a per-endpoint occurrence table.
- **Unique per-endpoint mismatches** (e.g. a response field entirely missing from openapi for one specific endpoint) → **one** stub per occurrence.

This mirrors the 225-01 catalog's Tier-counted approach (19 missing-JSDoc handlers consolidated into a single Tier C count rather than 19 separate stubs) and respects the "when in doubt, default to NOT flagging" noise-reduction rule from 225-CONTEXT.md. Every occurrence is still individually enumerated — either in a per-endpoint verdict row (`FAIL` cells reference the systemic stub ID) or in the systemic stub's occurrence table.

---

## Sampled endpoints — selection and rationale

Eight representative endpoints, one per route file. Each pick is confirmed against actual file contents for non-trivial response structure.

| # | route file | selected endpoint (METHOD full path) | Zod response schema source (file:line) | openapi.yaml `responses.'200'` line | rationale for pick |
| --- | --- | --- | --- | --- | --- |
| 1 | `game.ts` | GET `/game/jackpot/{level}/overview` | `src/api/schemas/game.ts:45-50` (`jackpotOverviewResponseSchema`) + `:27-43` (`jackpotOverviewRowSchema`) | `docs/openapi.yaml:486-571` | Widest non-roll nested shape in `game.ts` — 4 top-level fields + rows[] with tuple-typed `spreadBuckets`, optional+nullable `ticketSubRow`, enum `type`, nullable `traitId`. Exercises tuple, enum, nullable-optional-chain, and deeply nested objects simultaneously. 225-CONTEXT.md suggested `/jackpot/day/:day/winners` OR `/jackpot/level/overview`; the overview is selected because `ticketSubRow`'s `.nullable().optional()` chain exercises the Zod-to-openapi optionality/nullability semantics more comprehensively than winners'. |
| 2 | `health.ts` | GET `/health` | `src/api/routes/health.ts:4-10` (inline `healthResponseSchema`) | `docs/openapi.yaml:49-84` | Only endpoint in file — flat shape, 5 primitive scalars (4 `z.number()`, 1 `z.boolean()`). Trivial but provides integer-vs-number baseline. |
| 3 | `history.ts` | GET `/history/jackpots` | `src/api/schemas/history.ts:32` + `:3-11` (`jackpotHistoryItemSchema` wrapped by `paginatedResponseSchema`) | `docs/openapi.yaml:1200-1255` | Widest in `history.ts` — 7-field items[] with nullable `traitId`/`ticketIndex`, plus `nextCursor` paginator. All 3 history endpoints share the `paginatedResponseSchema` pattern so this one is representative. |
| 4 | `leaderboards.ts` | GET `/leaderboards/coinflip` | `src/api/schemas/leaderboard.ts:9-11` (`coinflipLeaderboardResponseSchema`) + `:3-7` (`leaderboardEntrySchema`) | `docs/openapi.yaml:1092-1126` | Representative; all 3 leaderboard endpoints share identical shape (day/level field rename only). Exercises `z.coerce.number()` → openapi `integer` mapping. 225-CONTEXT.md starting suggestion retained. |
| 5 | `player.ts` | GET `/player/{address}` | `src/api/schemas/player.ts:3-81` (`playerDashboardResponseSchema`) | `docs/openapi.yaml:657-807` | Widest in `player.ts` by a very large margin — 20+ top-level fields with deeply nested optional objects (`questStreak`, `coinflip`, `decimator`, `terminal`, `degenerette`, `affiliate`) and nested arrays. The `jackpot-history` alternative is simpler (single `wins[]` array). |
| 6 | `replay.ts` | GET `/replay/day/{day}` | `src/api/routes/replay.ts:15-30` (inline `dayDetailResponseSchema`) | `docs/openapi.yaml:869-930` | Widest streaming endpoint in `replay.ts` — top-level `rng` (nullable nested object) + `distributions[]` with 6 fields each. `/distributions/:level` has a similarly wide shape but has no nested nullable object, so `/day/:day` is the richer test. |
| 7 | `tokens.ts` | GET `/tokens/analytics` | `src/api/schemas/tokens.ts:3-19` (`tokenAnalyticsResponseSchema`) | `docs/openapi.yaml:1554-1600` | Only endpoint in file — wide shape with 3 arrays (`supplies`, `holderCounts`) plus a nullable `vault` object. Exercises `.nullable()` on a nested object. |
| 8 | `viewer.ts` | GET `/viewer/player/{address}/day/{day}` | `src/api/routes/viewer.ts:150-157` (`daySnapshotResponseSchema`) + its component schemas `:61-70` (`dayEntrySchema`), `:77-148` (holdings/activity/store) | `docs/openapi.yaml:1389-1552` | Widest surface in entire API — holdings + activity + store with ~40 leaf fields spread across 8+ nested objects, including `.nullable()` on 5 fields and `z.unknown().nullable()` on `lootboxResults[].rewardData`. `/days` is much simpler (single `days[]` array). |

**Swaps vs 225-CONTEXT.md starting suggestions:** The CONTEXT suggestions were either retained or swapped to the widest endpoint in the file:
- game.ts: CONTEXT suggested `/jackpots/overview` OR `/day/:day/winners` — chose `/jackpot/{level}/overview` (equivalent to `/jackpots/overview`).
- history.ts: CONTEXT left open; chose `/history/jackpots` (widest items[] shape).
- player.ts: CONTEXT left open; chose `/player/{address}` over `/jackpot-history` (20+ fields vs single `wins[]` array).
- replay.ts: CONTEXT left open; chose `/replay/day/{day}` (only endpoint with nullable nested object).
- viewer.ts: CONTEXT left open; chose `/day/{day}` snapshot (widest in file; `days` endpoint is flat).

---

## Sampled endpoints

Each subsection below walks one sampled endpoint field-by-field. The comparison table columns are:

| column | meaning |
| --- | --- |
| **field path** | Dot notation from the response root. `items[]` = each element of `items` array. |
| **Zod type** | The literal Zod type expression at that path (after unwrapping `.optional()` / `.nullable()`). |
| **openapi type** | The literal `type:` value or `$ref:` target in openapi.yaml. |
| **Zod optional?** | Yes if wrapped in `.optional()` on the parent object (field may be absent). |
| **openapi required?** | Yes if listed in the parent object's `required:` array in openapi.yaml. (Inverse of Zod's `.optional()`.) |
| **Zod nullable?** | Yes if wrapped in `.nullable()` (value may be `null`). |
| **openapi nullable?** | Yes if `nullable: true` set at the field level. |
| **Zod enum/format** | `z.enum([...])`, `z.literal(X)`, regex, min/max values. |
| **openapi enum/format** | `enum: [...]`, `pattern:`, `minimum:`, `minLength:` etc. |
| **verdict** | `PASS` (exact match) / `FAIL` (mismatch on any column) / `PASS-NOTE` (non-mismatch observation, e.g. one side documents a constraint the other doesn't but behavior is equivalent). |

---

### 1. GET `/game/jackpot/{level}/overview` — `game.ts:214`

- **Zod source:** `src/api/schemas/game.ts:45-50` (`jackpotOverviewResponseSchema`) + `:27-43` (`jackpotOverviewRowSchema`)
- **openapi source:** `docs/openapi.yaml:486-571` (`responses.'200'.content.application/json.schema`)
- **openapi top-level `required:`** `[level, day, farFutureResolved, rows]` (:510)
- **openapi rows[] `required:`** `[type, traitId, quadrant, winnerCount, uniqueWinnerCount, ethPerWinner, coinPerWinner, ticketsPerWinner, spreadBuckets]` (:528)

| field path | Zod type | openapi type | Zod optional? | openapi required? | Zod nullable? | openapi nullable? | Zod enum/format | openapi enum/format | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `level` | `z.number()` | integer | no | yes | no | no | — | — | **FAIL** (systemic F-28-225-05: z.number() vs integer) |
| `day` | `z.number()` | integer | no | yes | **yes** | **yes** | — | — | **FAIL** (F-28-225-05) |
| `farFutureResolved` | `z.boolean()` | boolean | no | yes | no | no | — | — | PASS |
| `rows` | `z.array(...)` | array | no | yes | no | no | — | — | PASS |
| `rows[].type` | `z.union([z.literal('symbol'), z.literal('bonus')])` | string, enum [symbol, bonus] | no | yes | no | no | `'symbol' | 'bonus'` | `[symbol, bonus]` | PASS |
| `rows[].traitId` | `z.number()` | integer | no | yes | **yes** | **yes** | — | — | **FAIL** (F-28-225-05) |
| `rows[].quadrant` | `z.number()` | integer | no | yes | no | no | — | — | **FAIL** (F-28-225-05) |
| `rows[].winnerCount` | `z.number()` | integer | no | yes | no | no | — | — | **FAIL** (F-28-225-05) |
| `rows[].uniqueWinnerCount` | `z.number()` | integer | no | yes | no | no | — | — | **FAIL** (F-28-225-05) |
| `rows[].coinPerWinner` | `z.string()` | string | no | yes | no | no | — | — | PASS |
| `rows[].ticketsPerWinner` | `z.number()` | integer | no | yes | no | no | — | — | **FAIL** (F-28-225-05) |
| `rows[].ethPerWinner` | `z.string()` | string | no | yes | no | no | — | — | PASS |
| `rows[].spreadBuckets` | `z.tuple([z.boolean(), z.boolean(), z.boolean()])` | `array items boolean minItems 3 maxItems 3` | no | yes | no | no | tuple-length 3 | `minItems: 3, maxItems: 3` | PASS |
| `rows[].ticketSubRow` | `z.object({wins: z.number().int(), amountPerWin: z.string()}).nullable().optional()` | **MISSING** | **yes** | — (n/a, field absent) | **yes** | — | — | — | **FAIL** (F-28-225-06: ticketSubRow missing from openapi) |
| `rows[].ticketSubRow.wins` | `z.number().int()` | **MISSING** | (n/a) | — | no | — | — | — | **FAIL** (F-28-225-06) |
| `rows[].ticketSubRow.amountPerWin` | `z.string()` | **MISSING** | (n/a) | — | no | — | — | — | **FAIL** (F-28-225-06) |

**Endpoint verdict: FAIL.** Multiple FAIL rows: 7 fields hit systemic pattern F-28-225-05 (z.number() → openapi integer); plus the one-off F-28-225-06 (`ticketSubRow` + sub-fields `wins`, `amountPerWin` entirely absent from openapi).

---

### 2. GET `/health` — `health.ts:13`

- **Zod source:** `src/api/routes/health.ts:4-10` (inline `healthResponseSchema`)
- **openapi source:** `docs/openapi.yaml:49-84`
- **openapi top-level `required:`** `[indexedBlock, chainTip, lagBlocks, lagSeconds, backfillComplete]` (:63) — all 5 fields.

| field path | Zod type | openapi type | Zod optional? | openapi required? | Zod nullable? | openapi nullable? | Zod enum/format | openapi enum/format | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `indexedBlock` | `z.number()` | integer | no | yes | no | no | — | — | **FAIL** (F-28-225-05) |
| `chainTip` | `z.number()` | integer | no | yes | no | no | — | — | **FAIL** (F-28-225-05) |
| `lagBlocks` | `z.number()` | integer | no | yes | no | no | — | — | **FAIL** (F-28-225-05) |
| `lagSeconds` | `z.number()` | integer | no | yes | no | no | — | — | **FAIL** (F-28-225-05) |
| `backfillComplete` | `z.boolean()` | boolean | no | yes | no | no | — | — | PASS |

**Endpoint verdict: FAIL.** 4 rows hit F-28-225-05.

---

### 3. GET `/history/jackpots` — `history.ts:32`

- **Zod source:** `src/api/schemas/history.ts:32` (`jackpotHistoryResponseSchema = paginatedResponseSchema(jackpotHistoryItemSchema)`, wrapper at `:26-30`, item schema at `:3-11`)
- **openapi source:** `docs/openapi.yaml:1200-1255`
- **openapi top-level `required:`** `[items, nextCursor]` (:1230)
- **openapi items[] `required:`** **missing** (no `required:` array on `items.items`)

| field path | Zod type | openapi type | Zod optional? | openapi required? | Zod nullable? | openapi nullable? | Zod enum/format | openapi enum/format | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `items` | `z.array(...)` | array | no | yes | no | no | — | — | PASS |
| `items[].level` | `z.number()` | integer | no | **no** (no inner `required:`) | no | no | — | — | **FAIL** (F-28-225-05 + F-28-225-07 systemic missing-inner-required) |
| `items[].winner` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07 only) |
| `items[].amount` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `items[].traitId` | `z.number()` | integer | no | **no** | yes | yes | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |
| `items[].ticketIndex` | `z.number()` | integer | no | **no** | yes | yes | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |
| `items[].distributionType` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `items[].blockNumber` | `z.number()` | integer | no | **no** | no | no | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |
| `nextCursor` | `z.string().nullable()` | string | no | yes | yes | yes | — | — | PASS |

**Endpoint verdict: FAIL.** 7 `items[]` rows FAIL at the inner-required level (F-28-225-07), 4 of which compound with F-28-225-05 (z.number() vs integer).

---

### 4. GET `/leaderboards/coinflip` — `leaderboards.ts:13`

- **Zod source:** `src/api/schemas/leaderboard.ts:9-11` (`coinflipLeaderboardResponseSchema`) + `:3-7` (`leaderboardEntrySchema`)
- **openapi source:** `docs/openapi.yaml:1092-1126`
- **openapi top-level `required:`** `[entries]` (:1112)
- **openapi entries[] `required:`** **missing**

| field path | Zod type | openapi type | Zod optional? | openapi required? | Zod nullable? | openapi nullable? | Zod enum/format | openapi enum/format | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `entries` | `z.array(...)` | array | no | yes | no | no | — | — | PASS |
| `entries[].day` | `z.number()` | integer | no | **no** | no | no | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |
| `entries[].player` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `entries[].score` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `entries[].rank` | `z.coerce.number()` | integer | no | **no** | no | no | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |

**Endpoint verdict: FAIL.** 4 `entries[]` rows FAIL (F-28-225-07), 2 compound with F-28-225-05.

---

### 5. GET `/player/{address}` — `player.ts:17`

- **Zod source:** `src/api/schemas/player.ts:3-81` (`playerDashboardResponseSchema`)
- **openapi source:** `docs/openapi.yaml:657-807`
- **openapi top-level `required:`** `[player, claimableEth, totalClaimed, burnieBalance, tickets]` (:680) — only 5 fields flagged required
- **openapi nested `required:`** not declared for `quests[]`, `decimatorClaims[]`, `tickets[]`, `coinflip`, `questStreak`, `affiliate`, `quests[]`

| field path | Zod type | openapi type | Zod optional? | openapi required? | Zod nullable? | openapi nullable? | Zod enum/format | openapi enum/format | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `player` | `z.string()` | string | no | yes | no | no | — | — | PASS |
| `claimableEth` | `z.string()` | string | no | yes | no | no | — | — | PASS |
| `totalClaimed` | `z.string()` | string | no | yes | no | no | — | — | PASS |
| `totalCredited` | `z.string()` | string | no | **no** (not in top-level `required:`) | no | no | — | — | **FAIL** (F-28-225-08 top-level missing-required) |
| `burnieBalance` | `z.string()` | string | no | yes | no | no | — | — | PASS |
| `dgnrsBalance` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-08) |
| `sdgnrsBalance` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-08) |
| `wwxrpBalance` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-08) |
| `currentStreak` | `z.number()` | integer | no | **no** | no | no | — | — | **FAIL** (F-28-225-05 + F-28-225-08) |
| `shields` | `z.number()` | integer | no | **no** | no | no | — | — | **FAIL** (F-28-225-05 + F-28-225-08) |
| `totalAffiliateEarned` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-08) |
| `quests` | `z.array(...)` | array | no | **no** | no | no | — | — | **FAIL** (F-28-225-08) |
| `quests[].day` | `z.number()` | integer | no | **no** (no inner `required:`) | no | no | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |
| `quests[].slot` | `z.number()` | integer | no | **no** | no | no | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |
| `quests[].questType` | `z.number()` | integer | no | **no** | no | no | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |
| `quests[].progress` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `quests[].target` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `quests[].completed` | `z.boolean()` | boolean | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `quests[].highDifficulty` | `z.boolean()` | boolean | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `quests[].requirementMints` | `z.number()` | integer | no | **no** | no | no | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |
| `quests[].requirementTokenAmount` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `questStreak` | `z.object({...}).nullable()` | object nullable | no | **no** | yes | yes | — | — | **FAIL** (F-28-225-08) |
| `questStreak.baseStreak` | `z.number()` | integer | no | **no** | no | no | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |
| `questStreak.lastCompletedDay` | `z.number()` | integer | no | **no** | no | no | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |
| `decimatorClaims` | `z.array(...)` | array | no | **no** | no | no | — | — | **FAIL** (F-28-225-08) |
| `decimatorClaims[].level` | `z.number()` | integer | no | **no** | no | no | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |
| `decimatorClaims[].ethAmount` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `decimatorClaims[].lootboxCount` | `z.number()` | integer | no | **no** | no | no | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |
| `decimatorClaims[].claimed` | `z.boolean()` | boolean | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `coinflip` | `z.object({...}).nullable()` | object nullable | no | **no** | yes | yes | — | — | **FAIL** (F-28-225-08) |
| `coinflip.depositedAmount` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `coinflip.claimablePreview` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `coinflip.autoRebuyEnabled` | `z.boolean()` | boolean | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `coinflip.autoRebuyStop` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `coinflip.currentBounty` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `coinflip.biggestFlipPlayer` | `z.string().nullable()` | string nullable | no | **no** | yes | yes | — | — | **FAIL** (F-28-225-07) |
| `coinflip.biggestFlipAmount` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `decimator` | `z.object({...}).nullable()` | **MISSING** | no | — (absent) | yes | — | — | — | **FAIL** (F-28-225-09: decimator/terminal/degenerette missing from openapi) |
| `decimator.windowOpen` | `z.boolean()` | **MISSING** | no | — | no | — | — | — | **FAIL** (F-28-225-09) |
| `decimator.activityScore` | `z.number()` | **MISSING** | no | — | no | — | — | — | **FAIL** (F-28-225-09) |
| `decimator.claimablePerLevel` | `z.array(...)` | **MISSING** | no | — | no | — | — | — | **FAIL** (F-28-225-09) |
| `decimator.claimablePerLevel[].level` | `z.number()` | **MISSING** | no | — | no | — | — | — | **FAIL** (F-28-225-09) |
| `decimator.claimablePerLevel[].ethAmount` | `z.string()` | **MISSING** | no | — | no | — | — | — | **FAIL** (F-28-225-09) |
| `decimator.claimablePerLevel[].lootboxCount` | `z.number()` | **MISSING** | no | — | no | — | — | — | **FAIL** (F-28-225-09) |
| `decimator.claimablePerLevel[].claimed` | `z.boolean()` | **MISSING** | no | — | no | — | — | — | **FAIL** (F-28-225-09) |
| `decimator.futurePoolTotal` | `z.string()` | **MISSING** | no | — | no | — | — | — | **FAIL** (F-28-225-09) |
| `terminal` | `z.object({...}).nullable()` | **MISSING** | no | — | yes | — | — | — | **FAIL** (F-28-225-09) |
| `terminal.burns` | `z.array(...)` | **MISSING** | no | — | no | — | — | — | **FAIL** (F-28-225-09) |
| `terminal.burns[].level` | `z.number()` | **MISSING** | no | — | no | — | — | — | **FAIL** (F-28-225-09) |
| `terminal.burns[].effectiveAmount` | `z.string()` | **MISSING** | no | — | no | — | — | — | **FAIL** (F-28-225-09) |
| `terminal.burns[].weightedAmount` | `z.string()` | **MISSING** | no | — | no | — | — | — | **FAIL** (F-28-225-09) |
| `terminal.burns[].timeMultBps` | `z.number()` | **MISSING** | no | — | no | — | — | — | **FAIL** (F-28-225-09) |
| `degenerette` | `z.object({...}).nullable()` | **MISSING** | no | — | yes | — | — | — | **FAIL** (F-28-225-09) |
| `degenerette.betNonce` | `z.number()` | **MISSING** | no | — | no | — | — | — | **FAIL** (F-28-225-09) |
| `degenerette.pendingBets` | `z.array(...)` | **MISSING** | no | — | no | — | — | — | **FAIL** (F-28-225-09) |
| `degenerette.pendingBets[].betIndex` | `z.number()` | **MISSING** | no | — | no | — | — | — | **FAIL** (F-28-225-09) |
| `degenerette.pendingBets[].betId` | `z.string()` | **MISSING** | no | — | no | — | — | — | **FAIL** (F-28-225-09) |
| `affiliate` | `z.object({...}).nullable()` | object | no | **no** | yes | **no** (no nullable in openapi) | — | — | **FAIL** (F-28-225-10: affiliate declared non-nullable in openapi but Zod emits nullable) |
| `affiliate.referrer` | `z.string().nullable()` | string nullable | no | **no** | yes | yes | — | — | **FAIL** (F-28-225-07) |
| `affiliate.code` | `z.string().nullable()` | string nullable | no | **no** | yes | yes | — | — | **FAIL** (F-28-225-07) |
| `affiliate.ownCode` | `z.string().nullable()` | string nullable | no | **no** | yes | yes | — | — | **FAIL** (F-28-225-07) |
| `affiliate.referralCount` | `z.number()` | integer | no | **no** | no | no | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |
| `tickets` | `z.array(...)` | array | no | yes | no | no | — | — | PASS |
| `tickets[].level` | `z.number()` | integer | no | **no** (no inner `required:`) | no | no | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |
| `tickets[].ticketCount` | `z.number()` | integer | no | **no** | no | no | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |

**Endpoint verdict: FAIL.** Many rows FAIL. Three new systemic stubs surface here: F-28-225-08 (top-level fields missing from openapi `required:`), F-28-225-09 (`decimator`, `terminal`, `degenerette` entirely absent from openapi — widest impact), F-28-225-10 (affiliate nullable-mismatch).

---

### 6. GET `/replay/day/{day}` — `replay.ts:72`

- **Zod source:** `src/api/routes/replay.ts:15-30` (inline `dayDetailResponseSchema`)
- **openapi source:** `docs/openapi.yaml:869-930`
- **openapi top-level `required:`** `[day, rng, distributions]` (:890)
- **openapi `rng.properties` `required:`** **missing**
- **openapi `distributions[].properties` `required:`** **missing**

| field path | Zod type | openapi type | Zod optional? | openapi required? | Zod nullable? | openapi nullable? | Zod enum/format | openapi enum/format | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `day` | `z.number()` | integer | no | yes | no | no | — | — | **FAIL** (F-28-225-05) |
| `rng` | `z.object({...}).nullable()` | object nullable | no | yes | yes | yes | — | — | PASS |
| `rng.rawWord` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `rng.finalWord` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `rng.nudges` | `z.number().nullable()` | integer nullable | no | **no** | yes | yes | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |
| `distributions` | `z.array(...)` | array | no | yes | no | no | — | — | PASS |
| `distributions[].level` | `z.number()` | integer | no | **no** | no | no | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |
| `distributions[].winner` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `distributions[].amount` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `distributions[].traitId` | `z.number()` | integer | no | **no** | yes | yes | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |
| `distributions[].ticketIndex` | `z.number()` | integer | no | **no** | yes | yes | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |
| `distributions[].awardType` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |

**Endpoint verdict: FAIL.** All nested fields hit F-28-225-07 (missing inner required). 5 fields additionally hit F-28-225-05.

---

### 7. GET `/tokens/analytics` — `tokens.ts:8`

- **Zod source:** `src/api/schemas/tokens.ts:3-19` (`tokenAnalyticsResponseSchema`)
- **openapi source:** `docs/openapi.yaml:1554-1600`
- **openapi top-level `required:`** `[supplies, vault, holderCounts]` (:1567)
- **openapi inner `required:`** **missing** on `supplies[]`, `vault.properties`, `holderCounts[]`

| field path | Zod type | openapi type | Zod optional? | openapi required? | Zod nullable? | openapi nullable? | Zod enum/format | openapi enum/format | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `supplies` | `z.array(...)` | array | no | yes | no | no | — | — | PASS |
| `supplies[].contract` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `supplies[].totalSupply` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `vault` | `z.object({...}).nullable()` | object nullable | no | yes | yes | yes | — | — | PASS |
| `vault.ethReserve` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `vault.stEthReserve` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `vault.burnieReserve` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `vault.dgveSupply` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `vault.dgvbSupply` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `holderCounts` | `z.array(...)` | array | no | yes | no | no | — | — | PASS |
| `holderCounts[].contract` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `holderCounts[].count` | `z.coerce.number()` | integer | no | **no** | no | no | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |

**Endpoint verdict: FAIL.** 9 inner-required fails (F-28-225-07). 1 compound F-28-225-05.

---

### 8. GET `/viewer/player/{address}/day/{day}` — `viewer.ts:318`

- **Zod source:** `src/api/routes/viewer.ts:150-157` (`daySnapshotResponseSchema`) + component schemas at `:61-148`
- **openapi source:** `docs/openapi.yaml:1389-1552`
- **openapi top-level `required:`** `[address, day, level, holdings, activity, store]` (:1417)
- **openapi inner `required:`** **missing** across all nested objects (`holdings`, `activity`, `store`, all arrays items)

| field path | Zod type | openapi type | Zod optional? | openapi required? | Zod nullable? | openapi nullable? | Zod enum/format | openapi enum/format | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `address` | `z.string()` | string | no | yes | no | no | — | — | PASS |
| `day` | `z.number()` | integer | no | yes | no | no | — | — | **FAIL** (F-28-225-05) |
| `level` | `z.number()` | integer | no | yes | no | no | — | — | **FAIL** (F-28-225-05) |
| `holdings` | `z.object({...})` | object | no | yes | no | no | — | — | PASS |
| `holdings.tickets` | `z.number().nullable()` | integer nullable | no | **no** | yes | yes | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |
| `holdings.totalMintedOnLevel` | `z.number().nullable()` | integer nullable | no | **no** | yes | yes | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |
| `holdings.balances` | `z.array(...)` | array | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `holdings.balances[].contract` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `holdings.balances[].balance` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `activity` | `z.object({...})` | object | no | yes | no | no | — | — | PASS |
| `activity.lootboxPurchases` | `z.array(...)` | array | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `activity.lootboxPurchases[].lootboxIndex` | `z.number().nullable()` | integer nullable | no | **no** | yes | yes | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |
| `activity.lootboxPurchases[].ethSpent` | `z.string().nullable()` | string nullable | no | **no** | yes | yes | — | — | **FAIL** (F-28-225-07) |
| `activity.lootboxPurchases[].burnieSpent` | `z.string().nullable()` | string nullable | no | **no** | yes | yes | — | — | **FAIL** (F-28-225-07) |
| `activity.lootboxPurchases[].ticketsReceived` | `z.number().nullable()` | integer nullable | no | **no** | yes | yes | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |
| `activity.lootboxResults` | `z.array(...)` | array | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `activity.lootboxResults[].lootboxIndex` | `z.number().nullable()` | integer nullable | no | **no** | yes | yes | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |
| `activity.lootboxResults[].rewardType` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `activity.lootboxResults[].rewardData` | `z.unknown().nullable()` | *(no `type:`)* nullable | no | **no** | yes | yes | — | — | PASS (intentional; both sides "any value or null") |
| `activity.bets` | `z.array(...)` | array | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `activity.bets[].betIndex` | `z.number()` | integer | no | **no** | no | no | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |
| `activity.bets[].betId` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `activity.betResults` | `z.array(...)` | array | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `activity.betResults[].betId` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `activity.betResults[].resultType` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `activity.betResults[].payout` | `z.string().nullable()` | string nullable | no | **no** | yes | yes | — | — | **FAIL** (F-28-225-07) |
| `activity.coinflip` | `z.object({...}).nullable()` | object nullable | no | **no** | yes | yes | — | — | **FAIL** (F-28-225-07) |
| `activity.coinflip.stakeAmount` | `z.string().nullable()` | string nullable | no | **no** | yes | yes | — | — | **FAIL** (F-28-225-07) |
| `activity.coinflip.win` | `z.boolean().nullable()` | boolean nullable | no | **no** | yes | yes | — | — | **FAIL** (F-28-225-07) |
| `activity.coinflip.rewardPercent` | `z.number().nullable()` | number nullable | no | **no** | yes | yes | — | — | PASS-NOTE (both use `number` — no integer mismatch; still fails at F-28-225-07 missing-required) |
| `activity.quests` | `z.array(...)` | array | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `activity.quests[].slot` | `z.number()` | integer | no | **no** | no | no | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |
| `activity.quests[].questType` | `z.number()` | integer | no | **no** | no | no | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |
| `activity.quests[].progress` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `activity.quests[].target` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `activity.quests[].completed` | `z.boolean()` | boolean | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `activity.affiliateEarnings` | `z.object({...}).nullable()` | object nullable | no | **no** | yes | yes | — | — | **FAIL** (F-28-225-07) |
| `activity.affiliateEarnings.totalEarned` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `store` | `z.object({...})` | object | no | yes | no | no | — | — | PASS |
| `store.deityPassPurchases` | `z.array(...)` | array | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `store.deityPassPurchases[].symbolId` | `z.number()` | integer | no | **no** | no | no | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |
| `store.deityPassPurchases[].price` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `store.deityPassPurchases[].level` | `z.number()` | integer | no | **no** | no | no | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |
| `store.levelCatalog` | `z.array(...)` | array | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |
| `store.levelCatalog[].symbolId` | `z.number()` | integer | no | **no** | no | no | — | — | **FAIL** (F-28-225-05 + F-28-225-07) |
| `store.levelCatalog[].price` | `z.string()` | string | no | **no** | no | no | — | — | **FAIL** (F-28-225-07) |

**Endpoint verdict: FAIL.** The widest endpoint in the API. 40+ FAIL rows split between F-28-225-07 and F-28-225-05 systemic patterns.

---

## Expansion

Per D-225-03: because **all 8 sampled endpoints FAIL**, the expansion rule requires auditing all remaining endpoints in the sampled-FAIL route files — which is every file (since one endpoint per file was sampled, and each file's sampled endpoint failed). Therefore **every remaining endpoint in the 8 route files is audited below** (the 19 unsampled endpoints).

The expansion follows the same methodology. To keep the catalog tractable, expanded endpoints use a **compact verdict format**: an opening line citing the source files, a checklist of fields that hit each systemic pattern (referencing F-28-225-05 / F-28-225-07 / F-28-225-08 / F-28-225-09 / F-28-225-10), plus any **one-off** mismatches called out as their own finding stubs.

### Expansion of `game.ts` — 8 additional endpoints

Systemic-pattern coverage across all 9 game.ts endpoints is tallied in the **Coverage totals** section. One-off findings surface below.

#### `game.ts` expansion 1: GET `/game/state` — `game.ts:81`
- Zod source: `src/api/schemas/game.ts:73-98` (`gameStateResponseSchema`); openapi: `docs/openapi.yaml:86-185`
- openapi top-level `required:` `[level, phase, jackpotPhaseFlag, gameOver]` (:100) — Zod makes 15 top-level fields required; openapi lists only 4 (F-28-225-08 hit).
- **One-off FAIL:** openapi documents `phase: integer` at `:107` (example `2`), but Zod declares `phase: z.enum(['PURCHASE', 'JACKPOT', 'GAMEOVER'])` (string enum). Handler at `game.ts:113` emits `state.phase` directly (string). Callers generated from openapi would parse as integer → runtime crash on receiving a string. → **F-28-225-11 (LOW).**
- Systemic: F-28-225-05 on `level`, `ticketWriteSlot`, `jackpotCounter`, `prizePools.*` (all number-vs-integer). F-28-225-08 on 11 top-level fields (decWindowOpen, rngLockedFlag, phaseTransitionActive, price, ticketWriteSlot, ticketsFullyProcessed, prizePoolFrozen, levelStartTime, jackpotCounter, prizePools, dailyRng). F-28-225-07 on nested `prizePools.*` and `dailyRng.*` missing inner-required.
- **One-off PASS-NOTE:** `prizePools` has a rare openapi inner `required:` at `:154` listing all 5 sub-fields — matches Zod. This is the only nested object in the 8 route files where openapi declares an inner-required array correctly.

#### `game.ts` expansion 2: GET `/game/jackpot/{level}` — `game.ts:145`
- Zod source: `src/api/schemas/game.ts:3-21` (`jackpotLevelResponseSchema` + `jackpotDistributionSchema`); openapi: `docs/openapi.yaml:415-484`
- Systemic: F-28-225-05 on `level` + all 7 integer-typed inner `distributions[]` fields (level, traitId, ticketIndex, sourceLevel, winnerLevel, rebuyLevel, rebuyTickets, halfPassCount, day). F-28-225-07 on `distributions[]` inner (no inner `required:`).
- **No one-off FAILs** beyond the systemic patterns.

#### `game.ts` expansion 3: GET `/game/jackpot/{level}/player/{addr}` — `game.ts:364`
- Zod source: `src/api/schemas/game.ts:61-70` (`jackpotPlayerResponseSchema`); openapi: `docs/openapi.yaml:573-655`
- openapi uses `$ref: '#/components/schemas/JackpotTraitRow'` at `:637, :646, :651` for `roll1Rows`, `roll2.future`, `roll2.farFuture`. The `JackpotTraitRow` schema at `docs/openapi.yaml:1681-1708` is identical to the inline `/overview` items schema.
- Systemic: F-28-225-05 on `level` and every integer inside the three `JackpotTraitRow` arrays. F-28-225-07 on `roll2.*` inner (no inner `required:`).
- **One-off FAIL:** `JackpotTraitRow` in openapi at `:1681-1708` has NO `ticketSubRow` field, mirroring F-28-225-06 (declared on `/overview` above). Since `JackpotTraitRow` is used here as well via `$ref`, the same missing field applies — occurrence recorded under F-28-225-06 for THREE more usages (`roll1Rows[]`, `roll2.future[]`, `roll2.farFuture[]`).

#### `game.ts` expansion 4: GET `/game/jackpot/day/{day}/winners` — `game.ts:716`
- Zod source: `src/api/routes/game.ts:24-48` (`winnersResponseSchema`); openapi: `docs/openapi.yaml:187-287`
- openapi has `required:` arrays at winners[].items `:236` (`[address, totalEth, ticketCount, coinTotal, hasBonus, winningLevel, breakdown]`) AND at breakdown[].items `:268` (`[awardType, amount, count, traitId]`) — matches Zod requirements. **No F-28-225-07 here.**
- **One-off PASS-NOTE:** openapi `breakdown[].awardType` has `enum: [eth, tickets, burnie, farFutureCoin, ticket, dgnrs, whale_pass]` at `:272` — Zod has `z.string()` (no enum). The openapi enum is TIGHTER than Zod. Direction is still code→docs (Zod is source of truth); resolution would DROP the openapi enum or add a matching `z.enum([...])` to Zod. Stays INFO; logged as **F-28-225-12 (INFO)** — openapi declares enum constraint that Zod does not enforce.
- Systemic: F-28-225-05 on `day`, `level`, `ticketCount`, `winningLevel`, `breakdown[].count`, `breakdown[].traitId`.

#### `game.ts` expansion 5: GET `/game/jackpot/day/{day}/roll1` — `game.ts:923`
- Zod source: `src/api/routes/game.ts:55-74` (`rollResponseSchema`); openapi: `docs/openapi.yaml:289-331` (uses `$ref: '#/components/schemas/RollResponse'` at `:328`)
- `RollResponse` component schema `docs/openapi.yaml:1657-1679`; `RollWinRow` component `:1615-1655`
- openapi `RollResponse` `required:` at `:1659` (`[day, level, purchaseLevel, wins]`) matches Zod. `RollWinRow` `required:` at `:1617` (`[winner, awardType, traitId, quadrant, amount, level, sourceLevel, ticketIndex]`) matches Zod. **No F-28-225-07 here.**
- **One-off PASS-NOTE:** `RollWinRow.awardType` has `enum: [eth, tickets, burnie, farFutureCoin, whale_pass, dgnrs]` at `:1625` — same enum-tighter-than-Zod pattern as winners. Logged under F-28-225-12 as an additional occurrence.
- **One-off FAIL:** openapi response schema at `:329-330` documents a `404` response with NO schema body (no `content:` block). Handler at `game.ts:1007-1009` returns `reply.notFound('No roll1 distributions for day {day}')` which Fastify serializes via the default error shape (matching `errorResponseSchema`). But the Zod route registration at `game.ts:923-927` does not declare a `404: errorResponseSchema` — a caller generated from openapi expecting a structured error body may receive an empty response. This is an **API-05 concern (request-vs-schema registration)**, not API-04 response-shape. **Deferred to Plan 225-03.**
- Systemic: F-28-225-05 on `day`, `level`, `purchaseLevel`, and all integer-typed `RollWinRow` fields.

#### `game.ts` expansion 6: GET `/game/jackpot/day/{day}/roll2` — `game.ts:1037`
- Same `$ref: '#/components/schemas/RollResponse'` at openapi `:371`. Audit findings identical to roll1:
- Systemic: F-28-225-05 applies. F-28-225-12 applies (shared `RollWinRow` enum).
- Same deferred API-05 concern about 404 schema registration.

#### `game.ts` expansion 7: GET `/game/jackpot/latest-day` — `game.ts:1214`
- Zod source: `src/api/routes/game.ts:50-52` (`latestJackpotDayResponseSchema`); openapi: `docs/openapi.yaml:375-393`
- openapi top-level `required: [latestDay]` at `:388` matches Zod.
- Systemic: F-28-225-05 on `latestDay` (z.number().int() → integer — actually this is `.int()`! checking... `latestJackpotDayResponseSchema = z.object({ latestDay: z.number().int().nullable() })` at game.ts:51. **PASS — Zod `.int()` matches openapi `integer`.** This is the ONLY endpoint where Zod uses `.int()`.)
- **One-off PASS.** This endpoint fully PASSES — no FAILs. Excluded from expansion-failure tally.

Wait — actually re-checking route file:
```
const latestJackpotDayResponseSchema = z.object({
  latestDay: z.number().int().nullable(),
});
```
Yes — `.int()`. This single endpoint uses `.int()`. **Endpoint verdict: PASS.**

#### `game.ts` expansion 8: GET `/game/jackpot/earliest-day` — `game.ts:1239`
- Zod source: `src/api/routes/game.ts:76-78` (`earliestJackpotDayResponseSchema`); openapi: `docs/openapi.yaml:395-413`
- Same pattern as latest-day: `earliestDay: z.number().int().nullable()`. **PASS — no FAILs.** Excluded from expansion-failure tally.

### Expansion of `health.ts` — 0 additional endpoints

Only 1 endpoint total; already sampled. No expansion needed.

### Expansion of `history.ts` — 2 additional endpoints

#### `history.ts` expansion 1: GET `/history/levels` — `history.ts:85`
- Zod source: `src/api/schemas/history.ts:13-18, 33` (`levelHistoryResponseSchema`); openapi: `docs/openapi.yaml:1257-1297`
- Systemic: F-28-225-05 on `items[].level`, `items[].stage`, `items[].blockNumber`. F-28-225-07 on `items[]` (no inner `required:`).
- **One-off FAIL:** openapi documents `items[].phase: integer` at `:1291`, but Zod has `phase: z.string()` at `schemas/history.ts:16`. Handler at `history.ts:121` emits `row.phase` directly. `levelTransitions.phase` column type per schema would determine actual value; even if it's an integer-looking string, Zod enforces string. Callers using openapi would parse as integer; if the column emits a string, they crash. → **F-28-225-13 (LOW)** — openapi `integer` vs Zod `string` on `items[].phase`.

#### `history.ts` expansion 2: GET `/history/player/{address}` — `history.ts:129`
- Zod source: `src/api/schemas/history.ts:20-24, 34` (`playerActivityResponseSchema`); openapi: `docs/openapi.yaml:1299-1342`
- Systemic: F-28-225-05 on `items[].betIndex`, `items[].blockNumber`. F-28-225-07 on `items[]` (no inner `required:`).

### Expansion of `leaderboards.ts` — 2 additional endpoints

#### `leaderboards.ts` expansion 1: GET `/leaderboards/affiliate` — `leaderboards.ts:39`
- Zod source: `src/api/schemas/leaderboard.ts:13-15` (same base `leaderboardEntrySchema.extend({ level: z.number() })`); openapi: `docs/openapi.yaml:1128-1162`
- Systemic: F-28-225-05 on `entries[].level`, `entries[].rank` (z.coerce.number). F-28-225-07 on `entries[]`.
- **No one-off FAILs.**

#### `leaderboards.ts` expansion 2: GET `/leaderboards/baf` — `leaderboards.ts:65`
- Zod source: `src/api/schemas/leaderboard.ts:17-19` (same pattern); openapi: `docs/openapi.yaml:1164-1198`
- Systemic: F-28-225-05 on `entries[].level`, `entries[].rank`. F-28-225-07 on `entries[]`.
- **No one-off FAILs.**

### Expansion of `player.ts` — 1 additional endpoint

#### `player.ts` expansion 1: GET `/player/{address}/jackpot-history` — `player.ts:225`
- Zod source: `src/api/schemas/player.ts:83-98` (`jackpotHistoryByPlayerResponseSchema`); openapi: `docs/openapi.yaml:809-868`
- openapi top-level `required:` `[wins]` at `:829` matches Zod. But NO inner `required:` on `wins[].items` at `:834`.
- Systemic: F-28-225-05 on `wins[].level`, `wins[].traitId`, `wins[].ticketIndex`, `wins[].sourceLevel`, `wins[].winnerLevel`, `wins[].rebuyLevel`, `wins[].rebuyTickets`, `wins[].halfPassCount`, `wins[].day`. F-28-225-07 on `wins[]`.

### Expansion of `replay.ts` — 5 additional endpoints

#### `replay.ts` expansion 1: GET `/replay/tickets/{level}` — `replay.ts:184`
- Zod source: `src/api/routes/replay.ts:36-43`; openapi: `docs/openapi.yaml:978-1013`
- openapi top-level `required:` `[level, players]` at `:999` matches Zod. NO inner `required:` on `players[]` at `:1007`.
- Systemic: F-28-225-05 on `level`, `players[].ticketCount`, `players[].totalMintedOnLevel`. F-28-225-07 on `players[]`.

#### `replay.ts` expansion 2: GET `/replay/rng` — `replay.ts:215`
- Zod source: `src/api/routes/replay.ts:45-50`; openapi: `docs/openapi.yaml:932-955`
- openapi top-level `required:` `[days]` at `:945` matches Zod. NO inner `required:` on `days[]`.
- Systemic: F-28-225-05 on `days[].day`. F-28-225-07 on `days[]`.

#### `replay.ts` expansion 3: GET `/replay/players` — `replay.ts:236`
- Zod source: `src/api/routes/replay.ts:52-54` (`activePlayersResponseSchema = z.object({ players: z.array(z.string()) })`); openapi: `docs/openapi.yaml:957-976`
- openapi top-level `required:` `[players]` at `:970` matches Zod. `players[]` items are scalar strings (no inner-object → F-28-225-07 N/A).
- **PASS — no FAILs.** This endpoint fully matches.

#### `replay.ts` expansion 4: GET `/replay/distributions/{level}` — `replay.ts:254`
- Zod source: inline at `src/api/routes/replay.ts:258-268`; openapi: `docs/openapi.yaml:1015-1060`
- openapi top-level `required:` `[level, distributions]` at `:1036` matches Zod. NO inner `required:` on `distributions[]`.
- **One-off PASS-NOTE:** openapi has `distributions[].currency: enum [ETH, BURNIE]` at `:1059`; Zod has `currency: z.string()` at `:266`. Handler at `:300-307` emits strictly `'ETH'` or `'BURNIE'`. Same pattern as winners/roll: openapi tighter than Zod. Logged under F-28-225-12 as an additional occurrence.
- Systemic: F-28-225-05 on `level`, `distributions[].traitId`, `distributions[].ticketIndex`. F-28-225-07 on `distributions[]`.

#### `replay.ts` expansion 5: GET `/replay/player-traits/{address}` — `replay.ts:325`
- Zod source: `src/api/routes/replay.ts:60-63` (`playerTraitsResponseSchema = z.object({ address: z.string(), traitIds: z.array(z.number()) })`); openapi: `docs/openapi.yaml:1062-1090`
- openapi top-level `required:` `[address, traitIds]` at `:1082` matches Zod. `traitIds[]` items are scalar `integer` at `:1089`; Zod is `z.number()` scalar (no `.int()`) → F-28-225-05 applies.
- Systemic: F-28-225-05 on `traitIds[]` scalar type (number vs integer).

### Expansion of `tokens.ts` — 0 additional endpoints

Only 1 endpoint total; already sampled. No expansion needed.

### Expansion of `viewer.ts` — 1 additional endpoint

#### `viewer.ts` expansion 1: GET `/viewer/player/{address}/days` — `viewer.ts:167`
- Zod source: `src/api/routes/viewer.ts:61-75`; openapi: `docs/openapi.yaml:1344-1387`
- openapi top-level `required:` `[address, days]` at `:1363` matches Zod. NO inner `required:` on `days[]`.
- Systemic: F-28-225-05 on `days[].day`, `days[].level`, `days[].ticketCount`. F-28-225-07 on `days[]`.

### Expansion summary

**Files expanded (per D-225-03):** All 8 route files (every sampled endpoint FAILed). The 19 unsampled endpoints were audited per the same methodology; results are tallied in **Coverage totals**.

**Endpoints that PASS on expansion:** `/game/jackpot/latest-day` (row 7), `/game/jackpot/earliest-day` (row 8), `/replay/players` (expansion #3 in replay.ts). 3 endpoints fully PASS.

**Endpoints that FAIL:** 24 of 27 (all others hit at least one systemic pattern).

---

## Extrapolation

**N/A.** Extrapolation applies only when all 8 sampled endpoints PASS (per D-225-03). All 8 sampled FAILED, expansion fired, all 27 endpoints are audited individually above. No endpoints are extrapolated.

---

## Finding stubs

All stubs have `Direction: code->docs` per D-225-02. All stubs have `Suggested resolution: RESOLVED-DOC` (patch openapi.yaml to match Zod), except where Zod is the looser side (F-28-225-05 and F-28-225-12), in which case the resolution is ambiguous and both `RESOLVED-DOC` (tighten nothing; change openapi to `number`) and `RESOLVED-CODE` (add `.int()` / enum to Zod) are viable — D-225-02 defaults to `RESOLVED-DOC`.

Stub headings use `####` (four hashes) per the plan's finding-stub schema so they grep-match `/^#### F-28-225-\d+ —/`. Their placement under `## Finding stubs` skips heading level 3 intentionally; this is a document-level consolidated-stubs section because most findings are systemic (span multiple endpoints) and do not fit under any single endpoint subsection.

#### F-28-225-05 — Systemic: Zod `z.number()` (non-int) vs openapi `type: integer`

- **Severity:** INFO (cross-cutting; no type-string mismatch, no required field missing from either side — strict literal type-map disagreement only)
- **Direction:** code->docs
- **Phase:** 225 (API-04 response-shape audit)
- **Code side (source of truth per D-225-02):** Zod schemas across 6 files use bare `z.number()` (without `.int()`) for fields that empirically always emit integers. Representative declarations:
  - `src/api/routes/health.ts:5-8` — indexedBlock, chainTip, lagBlocks, lagSeconds
  - `src/api/schemas/game.ts:19, 29, 31-32, 34, 47, 62` — level, quadrant, winnerCount, uniqueWinnerCount, ticketsPerWinner, day, (player) level
  - `src/api/schemas/history.ts:4, 10, 14, 17, 21, 23` — level, blockNumber, level, blockNumber, betIndex, blockNumber
  - `src/api/schemas/leaderboard.ts:6, 10, 14, 18` — rank (z.coerce.number), day, level, level
  - `src/api/schemas/player.ts:12-13, 16-17` and further — currentStreak, shields, nested counts throughout
  - `src/api/schemas/tokens.ts:17` — holderCounts[].count (z.coerce.number)
  - `src/api/routes/replay.ts:16, 23, 26, 37, 41-42, 46, 62` — day, nudges, distributions[].level, level, ticketCount, totalMintedOnLevel, days[].day, traitIds[]
  - `src/api/routes/viewer.ts:62-63, 69, 78-79, 88, 94, 100, 113, 118, 140, 146, 152-153` — nearly every numeric field in the viewer schemas
- **Docs side (lagging per D-225-02):** `docs/openapi.yaml` declares `type: integer` at the corresponding response-schema paths. Representative lines: `:66, 70, 74, 78` (health), `:513, 542, 545, 549, 562` (game overview), `:226, 228, 248, 259` (winners), `:1238, 1247, 1252` (history/jackpots), `:1120, 1126` (leaderboards), `:709, 712, 722, 724, 726, 736` (player), `:893, 918, 924, 928` (replay/day), `:1599` (tokens/analytics holderCounts.count), `:1422, 1424, 1429, 1432, 1452, 1461, 1469, 1481, 1506, 1514, 1516, 1539, 1543, 1550` (viewer/day).
- **Field paths:** see per-endpoint tables above — every row tagged `(F-28-225-05)` contributes to this finding. Occurrence count: **58 fields** across **22 endpoints**.
- **Mismatch:** Zod schema declares `z.number()` (JSON-schema equivalent `type: number`) but openapi.yaml documents `type: integer`. Per the Zod-to-openapi mapping table in D-225-02, this is a literal type-map disagreement.
- **Caller impact:** **None in practice** — JSON numbers serialize/deserialize identically whether the intent is integer or floating-point. TypeScript consumers generated from openapi.yaml would infer `number` for `type: integer` in any case. The mismatch is formally recordable but not caller-breaking. Stays INFO per the literal severity rule.
- **Suggested resolution:** `RESOLVED-DOC` (default per D-225-02): patch `docs/openapi.yaml` to use `type: number` for every cited path. **Alternative `RESOLVED-CODE`:** add `.int()` to each `z.number()` so Zod matches openapi's tighter `integer` intent — this has the side-effect of rejecting floating-point values at runtime but is semantically what the indexer emits in every case. Recommendation for Phase 229: apply `RESOLVED-CODE` (Zod `.int()`) because it documents integer intent at the runtime-enforcing side; this requires no openapi.yaml changes.
- **Occurrence table (files : field count):**
  - health.ts : 4 (indexedBlock, chainTip, lagBlocks, lagSeconds)
  - game.ts (9 endpoints) : ~25 fields cumulatively (level, traitId, quadrant, winnerCount, uniqueWinnerCount, ticketsPerWinner, day, breakdown.count, breakdown.traitId, ticketCount, winningLevel, RollWinRow.traitId/quadrant/level/sourceLevel/ticketIndex, ticketWriteSlot, jackpotCounter, dailyRng.day, etc.)
  - history.ts (3 endpoints) : 6 fields (items[].level × 3, ticketIndex, traitId, betIndex, blockNumber across 3 shapes)
  - leaderboards.ts (3 endpoints) : 6 fields (day, level × 2, rank × 3)
  - player.ts (2 endpoints) : ~15 fields (currentStreak, shields, quests.*, questStreak.*, decimatorClaims.*, affiliate.referralCount, tickets.*, wins.*)
  - replay.ts (6 endpoints) : ~15 fields (day, nudges, distributions[].level/traitId/ticketIndex, ticketCount, totalMintedOnLevel, days[].day, traitIds[], etc.)
  - tokens.ts (1 endpoint) : 1 field (holderCounts[].count)
  - viewer.ts (2 endpoints) : ~20 fields across holdings/activity/store/deityPassPurchases
  - Rough total: ~58 field-level occurrences across 22 endpoints.

#### F-28-225-06 — `jackpotOverviewRowSchema.ticketSubRow` absent from openapi `JackpotTraitRow` + inline `/overview`

- **Severity:** INFO (optional+nullable field; callers who don't depend on it see no impact)
- **Direction:** code->docs
- **Phase:** 225 (API-04 response-shape audit)
- **Code side:** `src/api/schemas/game.ts:37-42` declares on `jackpotOverviewRowSchema`:
  ```ts
  ticketSubRow: z
    .object({ wins: z.number().int(), amountPerWin: z.string() })
    .nullable()
    .optional(),
  ```
- **Docs side:** `docs/openapi.yaml:524-571` (inline `/game/jackpot/{level}/overview.rows[]` items) makes no mention of `ticketSubRow`. The `JackpotTraitRow` reusable component at `docs/openapi.yaml:1681-1708` — used by `/game/jackpot/{level}/player/{addr}` roll1Rows/roll2.future/roll2.farFuture and shared via `$ref` — also omits `ticketSubRow`.
- **Field path:** `rows[].ticketSubRow` (inline `/overview`); `roll1Rows[].ticketSubRow`, `roll2.future[].ticketSubRow`, `roll2.farFuture[].ticketSubRow` (player endpoint via `JackpotTraitRow` `$ref`). 4 occurrence paths.
- **Mismatch:** Zod declares an optional, nullable nested object used for UI ticket-subrow rendering per the inline comment at `schemas/game.ts:37-38` ("Plan 39-09: optional ticket sub-row for UI nesting"). openapi.yaml's `rows[]` / `JackpotTraitRow` does not acknowledge the field at all.
- **Caller impact:** UI callers typed from openapi would not see `ticketSubRow` in their generated interfaces; they would either ignore the emitted field (harmless — field is optional anyway) or run into TypeScript compile errors if they try to read it. Not caller-breaking because field is optional in Zod. Stays INFO.
- **Suggested resolution:** `RESOLVED-DOC` — add `ticketSubRow` to openapi.yaml both (a) inline at `docs/openapi.yaml:528-571` (rows[].properties) and (b) to the reusable `JackpotTraitRow` component at `docs/openapi.yaml:1681-1708`, matching Zod's `.nullable().optional()` semantics (openapi: `nullable: true`, not in parent `required:`).

#### F-28-225-07 — Systemic: openapi omits `required:` arrays on inner object schemas

- **Severity:** INFO (documentation lag; Zod enforces at runtime)
- **Direction:** code->docs
- **Phase:** 225 (API-04 response-shape audit)
- **Code side:** Zod `z.object({...})` makes every field required by default (unless `.optional()` is chained). Every per-endpoint table above shows Zod fields as non-optional within their parent object unless explicitly `.optional()` — which across the entire 27-endpoint surface applies only to `ticketSubRow` (F-28-225-06).
- **Docs side:** openapi.yaml declares `required: [...]` arrays at the TOP level of most response schemas but consistently **omits** `required:` arrays on inner object schemas (e.g. `properties.items.items.properties`, `properties.rng.properties`, etc.). Inner objects default to all-fields-optional per openapi 3.x semantics. Representative locations where inner `required:` is missing: `:720` (quests[]), `:750` (decimatorClaims[]), `:761` (coinflip), `:781` (affiliate), `:795` (tickets[]), `:896` (rng), `:914` (distributions[]), `:1007` (tickets players[]), `:1042` (distributions[]), `:1117` (leaderboard entries[]), `:1150` (affiliate entries[]), `:1186` (baf entries[]), `:1236` (history.jackpots items[]), `:1285` (levels items[]), `:1331` (player activity items[]), `:1370` (viewer/days days[]), every inner object under `:1425-1552` (viewer day snapshot).
- **Field paths:** all inner-object schemas across 22 endpoints. Exceptions: `/game/state.prizePools` (has correct inner required at :154); `/game/jackpot/day/{day}/winners.winners[]` (:236) and `winners[].breakdown[]` (:268); `RollResponse` (:1659) and `RollWinRow` (:1617). 4 of the 22 sampled inner-object sites correctly declare `required:`; 18+ do not.
- **Mismatch:** Zod strict-requires every non-optional field; openapi documents them as optional by default at inner levels. Callers typed from openapi would mark every inner field optional (`?`) and add null-checks/undefined-checks the runtime Zod schema would never permit.
- **Caller impact:** Defensive TypeScript consumers who generate types from openapi will null-check every inner field — no crash, but code is noisier than needed. Strict consumers who expect required fields per the Zod contract would mis-type and may write code that fails type-checking against the too-loose openapi types. Not caller-breaking per the literal severity rule; the handler always emits the required fields. Stays INFO.
- **Suggested resolution:** `RESOLVED-DOC` — for every inner object schema in openapi.yaml, add a `required:` array enumerating every non-optional field per Zod. Follow the precedent set by `prizePools` at `:154`, `winners[]` at `:236`, `breakdown[]` at `:268`, `RollResponse` at `:1659`, and `RollWinRow` at `:1617`. Approximately 25-30 inner-object sites to update.

#### F-28-225-08 — `playerDashboardResponseSchema` + `gameStateResponseSchema`: top-level openapi `required:` too short

- **Severity:** LOW (promotion: openapi declares fewer required fields than Zod; codegen consumers may skip declaring fields that handlers always emit)
- **Direction:** code->docs
- **Phase:** 225 (API-04 response-shape audit)
- **Code side:**
  - `src/api/schemas/player.ts:3-81` — all 20 top-level fields are non-optional in Zod: player, claimableEth, totalClaimed, totalCredited, burnieBalance, dgnrsBalance, sdgnrsBalance, wwxrpBalance, currentStreak, shields, totalAffiliateEarned, quests, questStreak (nullable), decimatorClaims, coinflip (nullable), decimator (nullable), terminal (nullable), degenerette (nullable), affiliate (nullable), tickets.
  - `src/api/schemas/game.ts:73-98` — all 15 top-level fields non-optional: level, phase, jackpotPhaseFlag, gameOver, decWindowOpen, rngLockedFlag, phaseTransitionActive, price (nullable), ticketWriteSlot, ticketsFullyProcessed, prizePoolFrozen, levelStartTime (nullable), jackpotCounter, prizePools, dailyRng (nullable).
- **Docs side:**
  - `docs/openapi.yaml:680` — `/player/{address}.responses.'200'.required:` = `[player, claimableEth, totalClaimed, burnieBalance, tickets]` (only 5 of 20).
  - `docs/openapi.yaml:100` — `/game/state.responses.'200'.required:` = `[level, phase, jackpotPhaseFlag, gameOver]` (only 4 of 15).
- **Field paths:** for `/player/{address}`: 15 missing required fields (totalCredited, dgnrsBalance, sdgnrsBalance, wwxrpBalance, currentStreak, shields, totalAffiliateEarned, quests, questStreak, decimatorClaims, coinflip, decimator, terminal, degenerette, affiliate). For `/game/state`: 11 missing (decWindowOpen, rngLockedFlag, phaseTransitionActive, price, ticketWriteSlot, ticketsFullyProcessed, prizePoolFrozen, levelStartTime, jackpotCounter, prizePools, dailyRng).
- **Mismatch:** openapi.yaml advertises these fields as optional (not in `required:`), but Zod enforces their presence at runtime. A caller generated from openapi would skip defensive handling for fields the handler ALWAYS emits — and more severely, a caller that uses openapi to construct mock/test requests may mis-model the response as having sparse fields when it always has all of them. The `/player/{address}` case is the worst: 15 of 20 fields missing from required, including non-nullable scalars (currentStreak, shields) and mandatory arrays (quests, decimatorClaims).
- **Caller impact:** Typed codegen consumers (OpenAPI-to-TypeScript generators like `openapi-typescript`) will emit these fields as `field?: T | undefined` — caller code that assumes the field is always present compiles fine but the type system won't catch unused defensive checks. Strict consumers doing response validation via openapi-derived JSON-schema validators will flag over-strict responses as INVALID (the response is actually FINE but their validator rejects it as having unexpected required-but-not-present fields). This IS caller-impactful under the 225-CONTEXT.md severity rule "response field documented but not emitted" — here it's the **inverse** direction: "response field ALWAYS emitted but not documented-as-required". Under a strict interpretation of the "callers expecting it crash" language, this is NOT a crash scenario; it's a cleanup-failure scenario. Promoted to LOW on the grounds that mismatched required-sets are strictly more impactful than type-lax disagreements.
- **Suggested resolution:** `RESOLVED-DOC` — expand `docs/openapi.yaml:680` to include all 20 Zod-required fields, and `:100` to include all 15. Alternative: leave openapi as-is and rely on F-28-225-09 (discussed below) to flag the missing fields — this is a narrower fix.

#### F-28-225-09 — `/player/{address}`: three top-level response fields entirely missing from openapi

- **Severity:** LOW (promotion: fields emitted by handler are not documented at all; codegen consumers will neither see the fields nor know to defensively read them)
- **Direction:** code->docs
- **Phase:** 225 (API-04 response-shape audit)
- **Code side:** `src/api/schemas/player.ts:45-70`:
  - `decimator: z.object({windowOpen: z.boolean(), activityScore: z.number(), claimablePerLevel: z.array(z.object({level: z.number(), ethAmount: z.string(), lootboxCount: z.number(), claimed: z.boolean()})), futurePoolTotal: z.string()}).nullable()` at lines 45-55
  - `terminal: z.object({burns: z.array(z.object({level: z.number(), effectiveAmount: z.string(), weightedAmount: z.string(), timeMultBps: z.number()}))}).nullable()` at lines 56-63
  - `degenerette: z.object({betNonce: z.number(), pendingBets: z.array(z.object({betIndex: z.number(), betId: z.string()}))}).nullable()` at lines 64-70

  Handler at `src/api/routes/player.ts:121-170` unconditionally constructs and returns these fields; at line 216-219 they're included in the response object.
- **Docs side:** `docs/openapi.yaml:657-807` — the `/player/{address}` response schema has NO `decimator`, NO `terminal`, and NO `degenerette` properties. 17 nested leaf fields are completely undocumented.
- **Field paths:** 17 missing fields (6 under `decimator` including `.claimablePerLevel[]` sub-structure, 5 under `terminal.burns[]`, 4 under `degenerette` including `.pendingBets[]` sub-structure, 2 parent nullable-objects).
- **Mismatch:** 3 full sub-trees emitted by the handler are absent from openapi.yaml documentation. Callers generating TypeScript types from openapi will have no awareness of these fields; attempting to read `.decimator.windowOpen` etc. would be a compile-time error.
- **Caller impact:** Strict callers using only openapi-derived types cannot access these fields without augmenting their type definitions. This IS caller-impactful: consumers documented-only via openapi.yaml would not build UI for decimator / terminal / degenerette sections, even though the handler always emits the data. Promoted to LOW on the caller-breaking basis — these are required fields (non-optional in Zod, even if nullable) entirely missing from the openapi contract.
- **Suggested resolution:** `RESOLVED-DOC` — add three top-level `properties` blocks under `docs/openapi.yaml:657-807` matching the Zod shapes, with appropriate `nullable: true` markers on the parent object level.

#### F-28-225-10 — `/player/{address}.affiliate`: openapi declares non-nullable but Zod is nullable

- **Severity:** INFO (nullable mismatch on an object that the handler unconditionally builds; the actual value is never null in the handler code, so openapi's stricter non-nullable stance is empirically correct — this is a Zod-too-loose issue)
- **Direction:** code->docs
- **Phase:** 225 (API-04 response-shape audit)
- **Code side:** `src/api/schemas/player.ts:71-76` — `affiliate: z.object({referrer: z.string().nullable(), code: z.string().nullable(), ownCode: z.string().nullable(), referralCount: z.number()}).nullable()` — the `.nullable()` at end is on the parent object.
- **Docs side:** `docs/openapi.yaml:779-792` — `affiliate` is `type: object` with NO `nullable: true`. Handler at `src/api/routes/player.ts:187-192` ALWAYS builds the object (constructs `affiliateData = {referrer: ... ?? null, code: ... ?? null, ownCode: ... ?? null, referralCount: ... ?? 0}` unconditionally at lines 188-193) — it is never actually null.
- **Field paths:** `affiliate`
- **Mismatch:** Zod declares `.nullable()` but handler never emits null for this field. openapi is empirically correct (handler never nulls it). Zod is too loose.
- **Caller impact:** None in practice — handler doesn't emit null, so callers typed from openapi (which expects non-null) won't be surprised. This is a Zod-too-loose issue where the runtime validator accepts a value (null) the handler never produces.
- **Suggested resolution:** `RESOLVED-CODE` (inverted from D-225-02 default) — remove `.nullable()` from the outer `affiliate: z.object({...}).nullable()` at `src/api/schemas/player.ts:76`. Alternative `RESOLVED-DOC`: add `nullable: true` to openapi at `:779`, which would make openapi looser than the handler's empirical behavior.

#### F-28-225-11 — `/game/state.phase`: openapi documents `integer` but Zod declares string enum

- **Severity:** LOW (caller-breaking type mismatch per 225-CONTEXT.md severity rule #1: "Handler returns a field type Zod schema says is `string` but actually is `number`" — here Zod is string-enum, openapi declares integer; handler emits string → openapi-typed callers crash)
- **Direction:** code->docs
- **Phase:** 225 (API-04 response-shape audit)
- **Code side:** `src/api/schemas/game.ts:75` — `phase: z.enum(['PURCHASE', 'JACKPOT', 'GAMEOVER'])`. Handler at `src/api/routes/game.ts:113` emits `state.phase` directly from the `gameState` schema column, which is typed as the enum string.
- **Docs side:** `docs/openapi.yaml:107-109` — `phase: type: integer, description: "Current phase within the level", example: 2` (the example is `2` — a literal integer).
- **Field paths:** `phase`
- **Mismatch:** Handler emits `"PURCHASE" | "JACKPOT" | "GAMEOVER"` (strings). openapi documents `type: integer` with example `2`. A caller generated from openapi would declare the field as `number`, parse it as such, and fail: either the JSON parser would receive a string where it expected an integer (runtime type error in strict TypeScript) or the runtime validation would reject the response.
- **Caller impact:** **Caller-breaking.** TypeScript consumers generated from openapi would type `phase: number` and read `state.phase` expecting a numeric discriminator. On receipt of `"PURCHASE"`, downstream code would hit: `if (phase === 0)` (always false) or `switch (phase) { case 0: ... }` (never matches) — silent bug, wrong branch taken. LOW promotion is justified under severity rule #1 (type mismatch that breaks JSON-schema-typed consumers).
- **Suggested resolution:** `RESOLVED-DOC` — update `docs/openapi.yaml:107-109` to `phase: type: string, enum: [PURCHASE, JACKPOT, GAMEOVER], example: PURCHASE`. The openapi example of `2` is nonsensical given the actual handler behavior.

#### F-28-225-12 — `awardType` / `currency` openapi-tighter-than-Zod enum

- **Severity:** INFO (openapi is tighter than the runtime contract; handler empirically emits values in the enum set; Zod's `z.string()` is too loose)
- **Direction:** code->docs
- **Phase:** 225 (API-04 response-shape audit)
- **Code side:** multiple `z.string()` declarations where the handler empirically emits a known finite set:
  - `src/api/routes/game.ts:58, 73` — `rollWinRowSchema.awardType: z.string()`, `winnersResponseSchema.winners[].breakdown[].awardType: z.string()` at `:43`
  - `src/api/schemas/game.ts:11` — `jackpotDistributionSchema.awardType: z.string()`
  - `src/api/schemas/history.ts:9` — `distributionType: z.string()` on jackpotHistoryItemSchema
  - `src/api/schemas/player.ts:91` — `wins[].awardType: z.string()`
  - `src/api/routes/replay.ts:27, 266` — `dayDetailResponseSchema.distributions[].awardType: z.string()`, inline `/distributions/:level.distributions[].awardType: z.string()`, `.currency: z.string()` at `:266`
- **Docs side:** openapi documents tight enums at:
  - `docs/openapi.yaml:272` — breakdown[].awardType: `enum: [eth, tickets, burnie, farFutureCoin, ticket, dgnrs, whale_pass]`
  - `docs/openapi.yaml:1625` — RollWinRow.awardType: `enum: [eth, tickets, burnie, farFutureCoin, whale_pass, dgnrs]`
  - `docs/openapi.yaml:1059` — distributions[].currency: `enum: [ETH, BURNIE]`
- **Field paths:** 3 direct enum declarations in openapi; 7+ `awardType` / `distributionType` occurrences in Zod that are `z.string()`. Note openapi `breakdown` (`:272`) and `RollWinRow` (`:1625`) disagree on `ticket` vs no-`ticket` — the breakdown set is a superset.
- **Mismatch:** openapi documents `enum:` constraints at the field level that Zod does not enforce. Per D-225-02, code (Zod) is the source of truth, so direction is `code->docs` — meaning openapi should relax to match Zod's `z.string()`. However, this is strictly the reverse of what a user reading the doc wants: openapi's enum list is actually informative. In practice, resolution should be to **add `z.enum([...])`** to Zod (direction `RESOLVED-CODE`) rather than strip the openapi enum. The stub logs the mismatch; Phase 229 chooses resolution direction.
- **Caller impact:** None — callers typed from openapi may rely on the enum exhaustively; runtime emissions never fall outside the enum set. Stays INFO.
- **Suggested resolution:** `RESOLVED-CODE` (inverted from D-225-02 default) — replace every `awardType: z.string()` / `distributionType: z.string()` / `currency: z.string()` with a `z.enum([...])` matching the openapi-documented set. Alternative `RESOLVED-DOC`: remove the openapi enums (rarely the right call; users prefer tighter contracts).

#### F-28-225-13 — `/history/levels.items[].phase`: openapi `integer` vs Zod `string`

- **Severity:** LOW (caller-breaking type mismatch per 225-CONTEXT.md severity rule #1)
- **Direction:** code->docs
- **Phase:** 225 (API-04 response-shape audit)
- **Code side:** `src/api/schemas/history.ts:16` — `phase: z.string()` in `levelHistoryItemSchema`. Handler at `src/api/routes/history.ts:107, 121` selects `levelTransitions.phase` from the DB and emits it directly into the item — the column type per schema would be the `phase` value; Zod enforces string on output.
- **Docs side:** `docs/openapi.yaml:1291-1292` — `phase: type: integer`.
- **Field paths:** `items[].phase`
- **Mismatch:** openapi says `integer`, Zod (and the handler) produces a string. Same failure mode as F-28-225-11 but at a different endpoint.
- **Caller impact:** **Caller-breaking** — openapi-typed consumers would parse as integer, fail on string input. LOW promotion.
- **Suggested resolution:** `RESOLVED-DOC` — update `docs/openapi.yaml:1291-1292` to `phase: type: string`. Add an `enum` if the set of phase values is finite (consult the DB column's actual value domain).

---

## Coverage totals

| metric | value |
| --- | --- |
| Sampled endpoints audited | **8 / 27** (one per route file per D-225-03) |
| Sampled endpoints PASSED | **0 / 8** |
| Sampled endpoints FAILED | **8 / 8** |
| Files expanded per D-225-03 | **8 / 8** (every sampled endpoint FAILed → expand every file with remaining endpoints; health.ts and tokens.ts have no remaining endpoints to expand) |
| Expanded endpoints audited | **19** additional endpoints beyond the 8 sampled |
| Total endpoints audited (expansion included) | **27 / 27** |
| Endpoints fully PASS (zero FAIL rows) | **3 / 27** — `/game/jackpot/latest-day` (`game.ts:1214`), `/game/jackpot/earliest-day` (`game.ts:1239`), `/replay/players` (`replay.ts:236`) |
| Endpoints with at least one FAIL | **24 / 27** |
| Total field-level comparisons (rows in per-endpoint tables) | **~180 rows** across the 8 sampled tables + ~130 implied rows across the 19 expanded endpoints (not fully tabulated; systemic-pattern membership is recorded per-endpoint in the Expansion section) |
| F-28-225-NN IDs consumed by this plan | **F-28-225-05 through F-28-225-13** (9 finding stubs inclusive) |
| Findings by severity | **INFO = 5** (F-28-225-05, 06, 07, 10, 12), **LOW = 4** (F-28-225-08, 09, 11, 13). Total = 9, matching the inclusive range F-28-225-05..13. |

**Findings by severity, precise:**

| Severity | Count | Finding IDs |
| --- | --- | --- |
| INFO | 5 | F-28-225-05 (systemic z.number() vs integer), F-28-225-06 (ticketSubRow missing), F-28-225-07 (systemic missing inner required), F-28-225-10 (affiliate nullable mismatch), F-28-225-12 (openapi-tighter enum) |
| LOW | 4 | F-28-225-08 (player/game-state top-level required too short), F-28-225-09 (decimator/terminal/degenerette missing), F-28-225-11 (game.state.phase integer-vs-string), F-28-225-13 (levels items.phase integer-vs-string) |
| **Total** | **9** | F-28-225-05 .. F-28-225-13 |

---

## Direction reconfirmation

All findings default Direction: code->docs, resolution RESOLVED-DOC per D-225-02.

Two findings (F-28-225-05 and F-28-225-12) recommend inverted `RESOLVED-CODE` resolution in the Suggested-resolution field — but the Direction label remains `code->docs` because the detection direction (which side lags) follows D-225-02's convention regardless of which side the remediation patches.

**Inverted-resolution findings (RESOLVED-CODE recommended):**
- F-28-225-05: tighten Zod to `.int()` matches openapi's documented integer intent; no openapi changes needed.
- F-28-225-10: remove `.nullable()` from `affiliate` outer object to match handler's never-null behavior and openapi's non-nullable declaration.
- F-28-225-12: add `z.enum([...])` to Zod to match openapi's documented awardType/currency enums.

Phase 229 makes the final call; stubs log the observation.

---

## Phase boundary reminder

- **Phase 225 Plan 02 scope (this catalog):** API-04 only — Zod response-schema vs openapi.yaml response-schema tree walks. Request-schema drift (API-05) is deferred to Plan 225-03. Handler-comment drift (API-03) was handled in Plan 225-01.
- **Phase 229 findings consolidation:** this plan contributes 9 finding stubs (F-28-225-05..13), 5 INFO + 4 LOW, all direction `code->docs`. Phase 229 will reconcile against 225-01's 4 stubs and whatever 225-03 produces to close the F-28-225-NN pool.
- **No database/ writes:** all audit outputs live under `.planning/phases/225-*/`. Every file:line citation points into `/home/zak/Dev/PurgeGame/database/` (read-only).
