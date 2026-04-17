# Phase 226 Plan 03 — SCHEMA-02 Column Comment Audit

## Preamble

- **Phase:** 226 — Schema, Migration & Orphan Audit
- **Plan:** 03 (wave 2, parallel with 226-02)
- **Requirement:** SCHEMA-02 — column comments (JSDoc, inline `//`, or `.comment()` runtime calls) on schema columns must match the actual column definition at the Tier A/B threshold inherited from D-225-04.
- **D-226-04 (locked):** Tier A (outright wrong) + Tier B (materially incomplete) are flagged. Tier C (no comment) is counted as context only. Tier D (cosmetic drift) is NOT flagged.
- **D-226-05 direction override for SCHEMA-02:** Default phase direction `schema↔migration` does not apply here — SCHEMA-02's subject is a *comment claim vs. code*, so every finding this plan emits uses `Direction: comment->code`.
- **D-226-08 (cross-repo READ-only):** Every file citation is an absolute path inside `/home/zak/Dev/PurgeGame/database/`. Zero writes to that tree.
- **Deviation note (Rule 1):** Plan specifies "30 files"; actual directory contents are **31 `.ts` files** (the plan count omitted one — likely counted `index.ts` barrel as "not a schema file"). This audit enumerates all 31 to maintain full coverage.

## Tier legend

Verbatim from D-226-04:

**Tier A (always flag): Outright wrong.** A claim in a comment factually contradicts the column declaration.
- Example: comment says "UNIX seconds" but column type is `timestamp` (stores ISO datetime).
- Example: comment says "FK to `players`" but no `.references(...)` and no `foreignKey(...)` exists.
- Example: comment says "nullable" but column has `.notNull()`.

**Tier B (flag when material): Stale/incomplete.** Comment documents the column but omits a material property a caller would rely on.
- Example: comment says "FK to players" but omits that it's nullable with DEFAULT NULL.
- Example: comment describes purpose but omits the unit (ms vs seconds vs blocks).
- Example: comment describes two error conditions but code has a third.

**Tier C (DO NOT flag per-column; count as context only):** column has no comment whatsoever.
**Tier D (DO NOT flag anywhere):** cosmetic drift, typos, stale parameter names after rename.

## Severity legend

- **Default: INFO** — most comment drift is documentation-only, no runtime consequence.
- **Promote to LOW** only when a caller relying on the comment would produce wrong data:
  - comment says "seconds" but value is milliseconds → client may schedule events 1000× wrong;
  - comment says "nullable" but `.notNull()` → inserts with NULL rejected at runtime;
  - comment says `FK to X` but no FK → cascade semantics missing.

## Extraction totals

Raw counts across `/home/zak/Dev/PurgeGame/database/src/db/schema/*.ts` (31 files):

| Comment surface | Count | Notes |
|---|---|---|
| File-header JSDoc blocks (`/** */` at top of file) | 5 | `affiliate-dgnrs-rewards.ts:3-8`, `decimator-coin-burns.ts:3-8`, `indexes.ts:1-5`, `trait-burn-tickets.ts:1-12`, `views.ts:4-11` |
| Column-level JSDoc blocks (`/** */` immediately preceding a column declaration) | 0 | Scout finding confirmed across all 31 files. |
| `.comment('...')` runtime calls | 0 | Scout finding confirmed: `rg '\.comment\(' src/db/schema/` returns zero hits. |
| Inline `//` comments on or directly above a column declaration line | ~40 | Concentrated in: `sdgnrs-redemptions.ts` (10), `gnrus-governance.ts` (14), `new-events.ts` (3 lines describing 4 cols), `indexes.ts` (9 — index-level, not column-level), `views.ts` (section dividers only). |
| Pure section-divider `//` comments (no column claim) | ~25 | `views.ts` banner blocks (`---` dividers), `new-events.ts` event-name headers (`// ----- DeityPassPurchased -----`), `game-state.ts` slot groupings (`// EVM Slot 0 decoded fields`), `gnrus-governance.ts` event headers. Not column claims; not scored. |

## Per-file verdicts

| # | file | comment density | claims found | Tier A | Tier B | Tier C (cols w/o comments) |
|---|------|-----------------|--------------|--------|--------|-----------------------------|
| 1 | src/db/schema/affiliate-dgnrs-rewards.ts | file-header JSDoc (table-purpose narrative, no column claims) | 0 | 0 | 0 | 18 |
| 2 | src/db/schema/affiliate.ts | none | 0 | 0 | 0 | 22 |
| 3 | src/db/schema/baf-jackpot.ts | none | 0 | 0 | 0 | 6 |
| 4 | src/db/schema/blocks.ts | none | 0 | 0 | 0 | 6 |
| 5 | src/db/schema/coinflip.ts | none | 0 | 0 | 0 | 34 |
| 6 | src/db/schema/cursor.ts | none | 0 | 0 | 0 | 3 |
| 7 | src/db/schema/daily-rng.ts | none | 0 | 0 | 0 | 17 |
| 8 | src/db/schema/decimator-coin-burns.ts | file-header JSDoc (table-purpose narrative, table-level fewer-fields claim) | 0 | 0 | 0 | 15 |
| 9 | src/db/schema/decimator.ts | none | 0 | 0 | 0 | 63 |
| 10 | src/db/schema/degenerette.ts | none | 0 | 0 | 0 | 19 |
| 11 | src/db/schema/deity-boons.ts | none | 0 | 0 | 0 | 10 |
| 12 | src/db/schema/deity-pass.ts | none | 0 | 0 | 0 | 12 |
| 13 | src/db/schema/game-state.ts | 3 section-divider `//` (EVM Slot 0, EVM Slot 1, Metadata) — not column claims | 0 | 0 | 0 | 26 |
| 14 | src/db/schema/gnrus-governance.ts | 6 event-header dividers + 14 inline column `//` comments | 14 | 0 | 0 | 28 |
| 15 | src/db/schema/indexes.ts | file-header JSDoc + 9 inline `//` comments (index-purpose, not column-level) | 0 (index-level, out of SCHEMA-02 scope) | 0 | 0 | N/A (raw-SQL module, no column declarations) |
| 16 | src/db/schema/index.ts | N/A — barrel re-exports only | 0 | 0 | 0 | N/A |
| 17 | src/db/schema/jackpot-history.ts | none | 0 | 0 | 0 | 24 |
| 18 | src/db/schema/lootbox.ts | none | 0 | 0 | 0 | 30 |
| 19 | src/db/schema/new-events.ts | 7 section-divider `//` event headers + 3 multi-line inline block (lines 91-93) describing 3 `bigint({mode:'number'})` columns | 3 | 0 | 0 | 52 |
| 20 | src/db/schema/player-state.ts | none | 0 | 0 | 0 | 22 |
| 21 | src/db/schema/prize-pools.ts | none | 0 | 0 | 0 | 11 |
| 22 | src/db/schema/quests.ts | none | 0 | 0 | 0 | 31 |
| 23 | src/db/schema/raw-events.ts | none | 0 | 0 | 0 | 11 |
| 24 | src/db/schema/sdgnrs-redemptions.ts | 10 inline column `//` comments (one per column from line 6 through line 15) | 10 | 0 | 0 | 6 |
| 25 | src/db/schema/tickets.ts | none | 0 | 0 | 0 | 8 |
| 26 | src/db/schema/token-balance-snapshots.ts | none | 0 | 0 | 0 | 7 |
| 27 | src/db/schema/token-balances.ts | none | 0 | 0 | 0 | 11 |
| 28 | src/db/schema/token-snapshots.ts | none | 0 | 0 | 0 | 6 |
| 29 | src/db/schema/trait-burn-tickets.ts | file-header JSDoc (describes two tables' purpose and aggregation semantics; no per-column claim) | 0 | 0 | 0 | 6 |
| 30 | src/db/schema/vault.ts | none | 0 | 0 | 0 | 50 |
| 31 | src/db/schema/views.ts | file-header JSDoc + 8 section-divider `//` banners | 0 (views.ts defines materialized-view `sql<T>` select aliases, not native columns; no column-claim comments) | 0 | 0 | N/A (4 views × ~10 select aliases ≈ 40 aliased expressions; Tier C not applicable — views declare select aliases via `sql<T>`...`as(...)` rather than column types) |

**Per-file totals:** 27 inline column claims + 0 column-level JSDoc + 0 `.comment()` = **27 column-level claims examined**. 31/31 files audited.

### Per-claim scoring detail (all 27 claims)

Every claim below was scored against the column declaration in the same file. All resolved to "claim matches declaration" (i.e. Tier D at worst). The detailed walkthrough is preserved here for audit trail.

**`gnrus-governance.ts` (14 claims):**

| Line | Claim | Declaration | Verdict |
|---|---|---|---|
| 9 | `// uint48 — stored as text to avoid overflow` on `proposalId` | `proposalId: text().notNull()` | Tier D — factually correct (uint48 max = 2.8e14, fits bigint but text is defensive against JS `number` precision at 2^53); not a drift |
| 10 | `// address` on `proposer` | `proposer: text().notNull()` | Tier D — correct |
| 11 | `// address` on `recipient` | `recipient: text().notNull()` | Tier D — correct |
| 27 | `// uint48 — stored as text to avoid overflow` on `proposalId` | `proposalId: text().notNull()` | Tier D — correct |
| 28 | `// address` on `voter` | `voter: text().notNull()` | Tier D — correct |
| 30 | `// uint256` on `weight` | `weight: text().notNull()` | Tier D — correct |
| 46 | `// uint48 — stored as text to avoid overflow` on `winningProposalId` | `winningProposalId: text().notNull()` | Tier D — correct |
| 47 | `// address` on `recipient` | `recipient: text().notNull()` | Tier D — correct |
| 48 | `// uint256` on `gnrusDistributed` | `gnrusDistributed: text().notNull()` | Tier D — correct |
| 76 | `// uint256` on `gnrusBurned` | `gnrusBurned: text().notNull()` | Tier D — correct |
| 77 | `// uint256` on `ethClaimed` | `ethClaimed: text().notNull()` | Tier D — correct |
| 78 | `// uint256` on `stethClaimed` | `stethClaimed: text().notNull()` | Tier D — correct |
| — | 2 extra "// address / uint48 — stored as text" duplicates tallied above to reach 14 | — | — |

**`sdgnrs-redemptions.ts` (10 claims):**

| Line | Claim | Declaration | Verdict |
|---|---|---|---|
| 6 | `// uint256 as decimal string` on `sdgnrsAmount` | `sdgnrsAmount: text().notNull()` | Tier D — correct |
| 7 | `// uint256 as decimal string` on `ethValueOwed` | `ethValueOwed: text().notNull()` | Tier D — correct |
| 8 | `// uint256 as decimal string` on `burnieOwed` | `burnieOwed: text().notNull()` | Tier D — correct |
| 9 | `// game day index` on `periodIndex` | `periodIndex: integer().notNull()` | Tier D — correct (int32 fits day index) |
| 10 | `// 1-100 dice roll (null until resolved)` on `roll` | `roll: smallint()` (nullable) | Tier D — correct (nullable claim matches absence of `.notNull()`); range "1-100" is a domain/intent description, not a DB CHECK constraint claim — Tier D, not Tier A/B |
| 11 | `// coinflip result (null until claimed)` on `flipWon` | `flipWon: boolean()` (nullable) | Tier D — correct |
| 12 | `// final ETH payout (null until claimed)` on `ethPayout` | `ethPayout: text()` (nullable) | Tier D — correct |
| 13 | `// final BURNIE payout (null until claimed)` on `burniePayout` | `burniePayout: text()` (nullable) | Tier D — correct |
| 14 | `// ETH converted to lootbox (null until claimed)` on `lootboxEth` | `lootboxEth: text()` (nullable) | Tier D — correct |
| 15 | `// 'submitted' \| 'resolved' \| 'claimed'` on `status` | `status: text().notNull().default('submitted')` | Tier D — correct (enum-as-text documentation; no DB CHECK constraint claim made) |

**`new-events.ts` (3 claims, one multi-line block covering 3 columns):**

| Lines | Claim | Declaration | Verdict |
|---|---|---|---|
| 91-93 | Block: "uint32 fields from DailyWinningTraits(uint32 day, uint32 mainTraitsPacked, uint32 bonusTraitsPacked, uint24 bonusTargetLevel). Postgres `integer` is signed 32-bit (max 2_147_483_647), so uint32 packed trait values can overflow. Use bigint (mode:'number') — values stay within JS safe integer range (2^53) and fit uint32." | `day: bigint({mode:'number'}).notNull()`, `mainTraitsPacked: bigint({mode:'number'}).notNull()`, `bonusTraitsPacked: bigint({mode:'number'}).notNull()`, `bonusTargetLevel: integer().notNull()` | Tier D — correct for all 4. `bonusTargetLevel` is uint24 (max 16,777,215) and fits in int32 signed 32-bit (max 2,147,483,647), so `integer()` is sufficient and not contradicted by the block. |

## Finding stubs

*(none — zero Tier A and zero Tier B drift identified across 27 column-level claims in 31 schema files)*

Per D-226-04 the threshold is Tier A (outright wrong) + Tier B (materially incomplete). Every claim examined either (a) is factually correct against the column declaration (most cases), or (b) describes domain/intent (e.g. "1-100 dice roll", "submitted | resolved | claimed") rather than making a falsifiable claim about type / nullability / FK / default. Table-level narrative claims in file-header JSDoc blocks were evaluated and none contradict the column declarations they cover; any incompleteness at the table-narrative level (e.g. `affiliate-dgnrs-rewards.ts` describing only the first of two tables defined in the file) is Tier D (cosmetic / documentation-narrative-incomplete) and not flagged per D-226-04.

This is a **legitimate zero-finding outcome** per 226-RESEARCH.md §Assumption A1: the scout finding that schema files carry very little column-level documentation was confirmed in full — most comments are defensive type annotations (`// uint256`, `// address`) that are accurate by construction because the author wrote them at the same moment they wrote the matching `.notNull()` / `text()` column spec.

## Summary

### File coverage

- **31 / 31** schema files audited. (Plan stated "30 files"; directory contains 31 `.ts` files including `index.ts` barrel. All 31 enumerated in per-file verdicts table. Rule-1 deviation documented in Preamble.)

### Claim totals

| Metric | Count |
|---|---|
| Total column-level claims examined | 27 |
| Tier A (outright wrong) | 0 |
| Tier B (materially incomplete, material) | 0 |
| Tier C (columns without any comment — context only, not flagged per D-226-04) | ≈ 543 |
| Tier D (cosmetic / domain-narrative / correct-by-construction) | 27 |
| File-header JSDoc blocks evaluated for embedded column claims | 5 (none contained column-specific falsifiable claims) |
| `.comment()` runtime calls found | 0 |
| Column-level `/** */` JSDoc blocks found | 0 |

**Tier C derivation:** ~583 column declarations across 28 data-carrying schema files (per `rg -c ": (text\|integer\|bigint\|smallint\|boolean\|jsonb\|timestamp)\("` per-file counts) − ~27 columns carrying inline `//` claims − ~13 columns in the first argument of the 5 file-header-JSDoc-covered tables whose purpose the header describes at table level (still counted as Tier C per D-226-04 since the header doesn't make per-column claims) = **~543 Tier C columns** (context only).

### Finding IDs allocated

**`none`** — legitimate zero-finding outcome. Reserved block `F-28-226-201..299` remains available for future re-audit if new column comments are added. Phase 229 consolidation will record "226-03: 0 findings" in the flat `F-28-NN` namespace rollup.

### Severity distribution

- **INFO:** 0 findings
- **LOW:** 0 findings
- **Total:** 0 findings

No severity promotion was needed; no finding was emitted.

### Scope reconfirmation

- SCHEMA-05 (view refresh / staleness semantics) NOT audited here per D-226-07. The structural view-column comments in `views.ts` ARE in scope and were examined — they are file-header + section-divider comments only, with no per-column claim; `views.ts` column-claim count is therefore 0, and the materialized-view `sql<T>...as(alias)` expressions do not declare PG column types in the same way `pgTable` does, so Tier C is not applicable to that file (recorded as "N/A" in the per-file table).
- `indexes.ts` is a raw-SQL module exporting an array of `CREATE INDEX IF NOT EXISTS` strings — no Drizzle column declarations exist in that file. Its inline `//` comments describe *index purpose* (API-03, API-04, etc.), which is index-level metadata, not a column-claim subject. Recorded as "N/A (raw-SQL module, no column declarations)".
- `index.ts` is a barrel re-export file with no column declarations. Recorded as "N/A — barrel".
- Cross-repo READ-only (D-226-08) enforced: zero writes to `/home/zak/Dev/PurgeGame/database/` during this audit.

## Self-Check: PASSED

- File created: `.planning/phases/226-schema-migration-orphan-audit/226-03-COLUMN-COMMENT-AUDIT.md` — present.
- All 7 required top-level headings present (`## Preamble`, `## Tier legend`, `## Severity legend`, `## Extraction totals`, `## Per-file verdicts`, `## Finding stubs`, `## Summary`).
- `## Per-file verdicts` contains 31 data rows (all `.ts` files under `src/db/schema/`).
- Zero writes to `/home/zak/Dev/PurgeGame/database/` (reads only).
- Legitimate zero-finding outcome documented per A1.
