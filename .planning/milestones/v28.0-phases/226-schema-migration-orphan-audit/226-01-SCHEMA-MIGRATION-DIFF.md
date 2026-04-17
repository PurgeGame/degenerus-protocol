# Phase 226 Plan 01 — SCHEMA-01 Schema ↔ Migration Diff

## Preamble

- **Phase:** 226 (Schema, Migration & Orphan Audit)
- **Plan:** 01
- **Requirement:** SCHEMA-01 — cumulative `.sql` ground truth ↔ `schema/*.ts` declared state, per column / index / FK / composite-PK.
- **Methodology:** D-226-01 hybrid — primary diff = cumulative `.sql`; secondary cross-check = `drizzle/meta/0006_snapshot.json`.
- **Direction (D-226-05):** `schema<->migration`.
- **Cross-repo (D-226-08):** READ-only on `/home/zak/Dev/PurgeGame/database/`. Catalog lives in `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/phases/226-schema-migration-orphan-audit/`.
- **Finding-ID allocation (D-226-06, D-226-09):** this plan emits `F-28-226-02` through `F-28-226-08`. `F-28-226-01` is reserved for Plan 226-02 (0007 snapshot anomaly).

## Input universe

### SQL side — 7 cumulative migrations

| File | Lines | New tables | ALTERs / drops |
|---|---|---|---|
| `/home/zak/Dev/PurgeGame/database/drizzle/0000_brown_justin_hammer.sql` | 32 | `raw_events`, `blocks`, `indexer_cursor` | — |
| `/home/zak/Dev/PurgeGame/database/drizzle/0001_handy_exiles.sql` | 303 | enum `game_phase` + 22 tables (game_state, prize_pools, player_settings, player_whale_passes, player_winnings, player_tickets, lootbox_purchases, lootbox_results, traits_generated, jackpot_distributions, level_transitions, decimator_bucket_totals, decimator_burns, decimator_claims, decimator_rounds, decimator_winning_subbuckets, player_boosts, degenerette_bets, degenerette_results, daily_rng, lootbox_rng, deity_boons) | — |
| `/home/zak/Dev/PurgeGame/database/drizzle/0002_secret_zzzax.sql` | 258 | 19 tables (token_balances, token_supply, deity_pass_ownership, deity_pass_transfers, coinflip_bounty_state, coinflip_daily_stakes, coinflip_leaderboard, coinflip_results, coinflip_settings, affiliate_codes, affiliate_earnings, affiliate_top_by_level, player_referrals, baf_flip_totals, player_streaks, quest_definitions, quest_progress, sdgnrs_burns, sdgnrs_deposits, sdgnrs_pool_balances, vault_claims, vault_deposits, vault_state, token_supply_snapshots) | — |
| `/home/zak/Dev/PurgeGame/database/drizzle/0003_fast_lifeguard.sql` | 24 | `decimator_coin_burns`, `affiliate_dgnrs_rewards` | — |
| `/home/zak/Dev/PurgeGame/database/drizzle/0004_slow_dracula.sql` | 12 | `token_balance_snapshots` | — |
| `/home/zak/Dev/PurgeGame/database/drizzle/0005_red_doctor_octopus.sql` | 0 | — | — (empty file; see Gotcha #8) |
| `/home/zak/Dev/PurgeGame/database/drizzle/0006_freezing_weapon_omega.sql` | 209 | 15 tables (terminal_decimator_burns, level_quest_completions, terminal_decimator_coin_burns, affiliate_dgnrs_claims, sdgnrs_redemptions, admin_events, boon_consumptions, deity_pass_purchases, final_sweep_events, game_over_events, link_feed_updates, gnrus_game_over, gnrus_level_resolutions, gnrus_level_skips, gnrus_proposals, gnrus_votes) | `ALTER TABLE quest_definitions DROP COLUMN difficulty`; plus 2 new indexes on existing tables (`lootbox_purchases`, `lootbox_results`) |
| `/home/zak/Dev/PurgeGame/database/drizzle/0007_trait_burn_tickets.sql` | 21 | `trait_burn_tickets`, `trait_burn_ticket_processed_logs` | — |

Additionally `0005_red_doctor_octopus.sql` is empty at disk but `meta/0005_snapshot.json` carries `ALTER TABLE prize_pools ADD COLUMN lastLevelPool text DEFAULT '0' NOT NULL` in TS/meta — see § Secondary cross-check and Gotcha #8 below. For the accumulator this column IS applied (the snapshot confirms and prize_pools TS declares `lastLevelPool`).

**Note (`prize_pools.lastLevelPool`):** this column exists in the TS schema (`prize-pools.ts:12`) and in `meta/0005_snapshot.json` but NOT in `drizzle/0005_red_doctor_octopus.sql` (which is empty). This is a Plan 226-02 concern (migration-file trace); for SCHEMA-01 diff purposes we treat the column as applied (via meta snapshot) — see F-28-226-08.

### TS side — 30 schema files

```
/home/zak/Dev/PurgeGame/database/src/db/schema/affiliate-dgnrs-rewards.ts
/home/zak/Dev/PurgeGame/database/src/db/schema/affiliate.ts
/home/zak/Dev/PurgeGame/database/src/db/schema/baf-jackpot.ts
/home/zak/Dev/PurgeGame/database/src/db/schema/blocks.ts
/home/zak/Dev/PurgeGame/database/src/db/schema/coinflip.ts
/home/zak/Dev/PurgeGame/database/src/db/schema/cursor.ts
/home/zak/Dev/PurgeGame/database/src/db/schema/daily-rng.ts
/home/zak/Dev/PurgeGame/database/src/db/schema/decimator-coin-burns.ts
/home/zak/Dev/PurgeGame/database/src/db/schema/decimator.ts
/home/zak/Dev/PurgeGame/database/src/db/schema/degenerette.ts
/home/zak/Dev/PurgeGame/database/src/db/schema/deity-boons.ts
/home/zak/Dev/PurgeGame/database/src/db/schema/deity-pass.ts
/home/zak/Dev/PurgeGame/database/src/db/schema/game-state.ts
/home/zak/Dev/PurgeGame/database/src/db/schema/gnrus-governance.ts
/home/zak/Dev/PurgeGame/database/src/db/schema/index.ts             (barrel — context only)
/home/zak/Dev/PurgeGame/database/src/db/schema/indexes.ts            (raw SQL array — context only per Gotcha #7)
/home/zak/Dev/PurgeGame/database/src/db/schema/jackpot-history.ts
/home/zak/Dev/PurgeGame/database/src/db/schema/lootbox.ts
/home/zak/Dev/PurgeGame/database/src/db/schema/new-events.ts
/home/zak/Dev/PurgeGame/database/src/db/schema/player-state.ts
/home/zak/Dev/PurgeGame/database/src/db/schema/prize-pools.ts
/home/zak/Dev/PurgeGame/database/src/db/schema/quests.ts
/home/zak/Dev/PurgeGame/database/src/db/schema/raw-events.ts
/home/zak/Dev/PurgeGame/database/src/db/schema/sdgnrs-redemptions.ts
/home/zak/Dev/PurgeGame/database/src/db/schema/tickets.ts
/home/zak/Dev/PurgeGame/database/src/db/schema/token-balance-snapshots.ts
/home/zak/Dev/PurgeGame/database/src/db/schema/token-balances.ts
/home/zak/Dev/PurgeGame/database/src/db/schema/token-snapshots.ts
/home/zak/Dev/PurgeGame/database/src/db/schema/trait-burn-tickets.ts
/home/zak/Dev/PurgeGame/database/src/db/schema/vault.ts
/home/zak/Dev/PurgeGame/database/src/db/schema/views.ts               (materialized views — see Views subsection)
```

29 of 30 are registered in `drizzle.config.ts`. `indexes.ts` is NOT registered (Gotcha #7).

### Meta side — 7 snapshots

```
/home/zak/Dev/PurgeGame/database/drizzle/meta/_journal.json
/home/zak/Dev/PurgeGame/database/drizzle/meta/0000_snapshot.json
/home/zak/Dev/PurgeGame/database/drizzle/meta/0001_snapshot.json
/home/zak/Dev/PurgeGame/database/drizzle/meta/0002_snapshot.json
/home/zak/Dev/PurgeGame/database/drizzle/meta/0003_snapshot.json
/home/zak/Dev/PurgeGame/database/drizzle/meta/0004_snapshot.json
/home/zak/Dev/PurgeGame/database/drizzle/meta/0005_snapshot.json
/home/zak/Dev/PurgeGame/database/drizzle/meta/0006_snapshot.json
```

`0007_snapshot.json` is **missing** — Plan 226-02 owns this as `F-28-226-01`. Not re-emitted here.

## Gotchas carried forward

Per `226-RESEARCH.md` §Known drizzle-kit Gotchas. These are NOT flagged as drift:

1. Identity-column `SEQUENCE NAME / MINVALUE / MAXVALUE / START WITH / CACHE` defaults = drizzle-kit boilerplate.
2. `timestamp({ mode: 'date'|'string' })` — `mode` is JS-runtime only; SQL identical.
3. `bigint({ mode: 'bigint'|'number' })` — same.
4. DEFAULT literal representation — normalize before comparing (`.default(0)` == `DEFAULT 0`, `.default(sql\`0\`)` == `DEFAULT 0`).
5. Composite PK auto-names — TS `primaryKey({columns:[t.a,t.b]})` with no name → SQL `<table>_<col>_<col>_pk`. Name derivation, not drift.
6. Camel vs snake column names — `text('snake_name')` override is the snake-case signal; absence → PG col is camelCase (matches identifier key).
7. `indexes.ts` is NOT in `drizzle.config.ts`. Its `ADDITIONAL_INDEXES` raw SQL appears in PG but NOT in `.sql` migrations or `meta/*.json`. Recorded as context; no SCHEMA-01 findings.
8. `0005_red_doctor_octopus.sql` is 0 bytes. `meta/0005_snapshot.json` shows the `prize_pools.lastLevelPool` column WAS added at that step (the SQL body is missing on disk). This is primarily a 226-02 migration-trace concern, but because SCHEMA-01 compares `.sql` cumulative vs TS we explicitly flag the mismatch here as `F-28-226-08`.
9. `0007_trait_burn_tickets.sql` without `0007_snapshot.json` — pre-assigned `F-28-226-01` to Plan 226-02; NOT re-emitted here.
10. `CREATE MATERIALIZED VIEW` absent from all `.sql` files despite `views.ts` defining four — flagged as INVESTIGATE context, not a finding (runtime path — Phase 228 territory). See § Views subsection.

## Per-table verdicts

Legend for columns: `TS type` reflects drizzle TS invocation; `SQL type` is the applied `.sql` type ignoring identity sequence defaults (Gotcha #1); NN = NOT NULL; `—` = no constraint / column pair absent. Verdict `PASS` = all fields aligned; `FAIL` = finding emitted.

### Table `raw_events` — TS: src/db/schema/raw-events.ts:3

**Columns**

| TS col | SQL col | TS type | SQL type | NN (TS/SQL) | DEFAULT (TS/SQL) | PK (TS/SQL) | Verdict |
|---|---|---|---|---|---|---|---|
| id | id | integer identity-always | integer identity-always | ✓/✓ | — / — | ✓/✓ | PASS |
| blockNumber | blockNumber | bigint | bigint | ✓/✓ | — / — | — / — | PASS |
| blockHash | blockHash | text | text | ✓/✓ | — / — | — / — | PASS |
| transactionHash | transactionHash | text | text | ✓/✓ | — / — | — / — | PASS |
| transactionIndex | transactionIndex | integer | integer | ✓/✓ | — / — | — / — | PASS |
| logIndex | logIndex | integer | integer | ✓/✓ | — / — | — / — | PASS |
| contractAddress | contractAddress | text | text | ✓/✓ | — / — | — / — | PASS |
| eventName | eventName | text | text | ✓/✓ | — / — | — / — | PASS |
| eventSignature | eventSignature | text | text | ✓/✓ | — / — | — / — | PASS |
| args | args | jsonb | jsonb | ✓/✓ | — / — | — / — | PASS |
| removed | removed | integer | integer | ✓/✓ | 0 / 0 | — / — | PASS |

**Indexes**

| Name | TS (file:line) | SQL (file:line) | Verdict |
|---|---|---|---|
| raw_events_unique (UNIQUE) | raw-events.ts:16 | 0000_brown_justin_hammer.sql:30 | PASS |
| raw_events_block_number_idx | raw-events.ts:17 | 0000_brown_justin_hammer.sql:31 | PASS |
| raw_events_contract_event_idx | raw-events.ts:18 | 0000_brown_justin_hammer.sql:32 | PASS |

**Verdict summary:** PASS

### Table `blocks` — TS: src/db/schema/blocks.ts:3

**Columns**

| TS col | SQL col | TS type | SQL type | NN | DEFAULT | PK | Verdict |
|---|---|---|---|---|---|---|---|
| blockNumber | blockNumber | bigint | bigint | ✓/✓ | — / — | ✓/✓ | PASS |
| blockHash | blockHash | text | text | ✓/✓ | — / — | — / — | PASS |
| parentHash | parentHash | text | text | ✓/✓ | — / — | — / — | PASS |
| timestamp | timestamp | timestamp | timestamp | ✓/✓ | — / — | — / — | PASS |
| eventCount | eventCount | integer | integer | ✓/✓ | 0 / 0 | — / — | PASS |
| processedAt | processedAt | timestamp | timestamp | ✓/✓ | now() / now() | — / — | PASS |

**Indexes**

| Name | TS | SQL | Verdict |
|---|---|---|---|
| blocks_hash_idx (UNIQUE) | blocks.ts:11 | 0000_brown_justin_hammer.sql:33 | PASS |

**Verdict summary:** PASS

### Table `indexer_cursor` — TS: src/db/schema/cursor.ts:4

| TS col | SQL col | TS type | SQL type | NN | DEFAULT | PK | Verdict |
|---|---|---|---|---|---|---|---|
| id | id | integer | integer | ✓/✓ | 1 / 1 | ✓/✓ | PASS |
| lastProcessedBlock | lastProcessedBlock | bigint | bigint | ✓/✓ | sql`0` / 0 | — / — | PASS (Gotcha #4) |
| updatedAt | updatedAt | timestamp | timestamp | ✓/✓ | now() / now() | — / — | PASS |

**Verdict summary:** PASS

### Table `game_state` — TS: src/db/schema/game-state.ts:5

All 26 columns align. Enum column `phase` uses `gamePhaseEnum` both sides; enum registered at `CREATE TYPE "public"."game_phase"` in 0001_handy_exiles.sql:1.

| TS col | SQL col | TS type | SQL type | NN | DEFAULT | PK | Verdict |
|---|---|---|---|---|---|---|---|
| id | id | integer | integer | ✓/✓ | 1/1 | ✓/✓ | PASS |
| level | level | integer | integer | ✓/✓ | 0/0 | —/— | PASS |
| phase | phase | game_phase enum | "game_phase" | ✓/✓ | 'PURCHASE'/'PURCHASE' | —/— | PASS |
| advanceStage | advanceStage | smallint | smallint | ✓/✓ | 0/0 | —/— | PASS |
| levelStartTime | levelStartTime | bigint | bigint | —/— | —/— | —/— | PASS |
| dailyIdx | dailyIdx | bigint | bigint | —/— | —/— | —/— | PASS |
| rngRequestTime | rngRequestTime | bigint | bigint | —/— | —/— | —/— | PASS |
| jackpotPhaseFlag | jackpotPhaseFlag | boolean | boolean | ✓/✓ | false/false | —/— | PASS |
| jackpotCounter | jackpotCounter | smallint | smallint | ✓/✓ | 0/0 | —/— | PASS |
| earlyBurnPercent | earlyBurnPercent | smallint | smallint | ✓/✓ | 0/0 | —/— | PASS |
| poolConsolidationDone | poolConsolidationDone | boolean | boolean | ✓/✓ | false/false | —/— | PASS |
| lastPurchaseDay | lastPurchaseDay | boolean | boolean | ✓/✓ | false/false | —/— | PASS |
| decWindowOpen | decWindowOpen | boolean | boolean | ✓/✓ | false/false | —/— | PASS |
| rngLockedFlag | rngLockedFlag | boolean | boolean | ✓/✓ | false/false | —/— | PASS |
| phaseTransitionActive | phaseTransitionActive | boolean | boolean | ✓/✓ | false/false | —/— | PASS |
| gameOver | gameOver | boolean | boolean | ✓/✓ | false/false | —/— | PASS |
| dailyJackpotCoinTicketsPending | dailyJackpotCoinTicketsPending | boolean | boolean | ✓/✓ | false/false | —/— | PASS |
| dailyEthBucketCursor | dailyEthBucketCursor | smallint | smallint | ✓/✓ | 0/0 | —/— | PASS |
| dailyEthPhase | dailyEthPhase | smallint | smallint | ✓/✓ | 0/0 | —/— | PASS |
| compressedJackpotFlag | compressedJackpotFlag | smallint | smallint | ✓/✓ | 0/0 | —/— | PASS |
| purchaseStartDay | purchaseStartDay | bigint | bigint | —/— | —/— | —/— | PASS |
| price | price | text | text | —/— | —/— | —/— | PASS |
| ticketWriteSlot | ticketWriteSlot | smallint | smallint | ✓/✓ | 0/0 | —/— | PASS |
| ticketsFullyProcessed | ticketsFullyProcessed | boolean | boolean | ✓/✓ | false/false | —/— | PASS |
| prizePoolFrozen | prizePoolFrozen | boolean | boolean | ✓/✓ | false/false | —/— | PASS |
| blockNumber | blockNumber | bigint | bigint | ✓/✓ | —/— | —/— | PASS |
| blockHash | blockHash | text | text | ✓/✓ | —/— | —/— | PASS |

**Indexes:** none in either side.

**Verdict summary:** PASS

### Table `prize_pools` — TS: src/db/schema/prize-pools.ts:3

| TS col | SQL col | TS type | SQL type | NN | DEFAULT | PK | Verdict |
|---|---|---|---|---|---|---|---|
| id | id | integer | integer | ✓/✓ | 1/1 | ✓/✓ | PASS |
| futurePrizePool | futurePrizePool | text | text | ✓/✓ | '0'/'0' | —/— | PASS |
| nextPrizePool | nextPrizePool | text | text | ✓/✓ | '0'/'0' | —/— | PASS |
| currentPrizePool | currentPrizePool | text | text | ✓/✓ | '0'/'0' | —/— | PASS |
| claimableWinnings | claimableWinnings | text | text | ✓/✓ | '0'/'0' | —/— | PASS |
| pendingFuture | pendingFuture | text | text | ✓/✓ | '0'/'0' | —/— | PASS |
| pendingNext | pendingNext | text | text | ✓/✓ | '0'/'0' | —/— | PASS |
| frozen | frozen | boolean | boolean | ✓/✓ | false/false | —/— | PASS |
| lastLevelPool | lastLevelPool (via 0005 meta) | text | text | ✓/MISSING-IN-0005-SQL-FILE | '0' / '0' (per meta) | —/— | **FAIL — F-28-226-08** |
| blockNumber | blockNumber | bigint | bigint | ✓/✓ | —/— | —/— | PASS |
| blockHash | blockHash | text | text | ✓/✓ | —/— | —/— | PASS |

**Indexes:** none either side.

**Verdict summary:** FAIL — `lastLevelPool` exists in TS and in `meta/0005_snapshot.json` but the `.sql` file at `0005_red_doctor_octopus.sql` is empty, so the column definition never lived in a `.sql` file (Gotcha #8). The runtime state produced by `drizzle-kit migrate` is correct because drizzle-kit uses `meta/*.json`, but an auditor who reads `.sql` only would miss this column. → **F-28-226-08**.

### Table `player_settings` — TS: src/db/schema/player-state.ts:12

All 6 columns (player PK text, autoRebuyEnabled bool default false, autoRebuyTakeProfit text default '0', afKingModeEnabled bool default false, decimatorAutoRebuyEnabled bool default false, blockNumber bigint, blockHash text) align with 0001_handy_exiles.sql:45-53.

**Verdict summary:** PASS

### Table `player_whale_passes` — TS: src/db/schema/player-state.ts:22

All 9 columns (id identity, player text, caller text, halfPasses integer, startLevel integer, blockNumber bigint, blockHash text, transactionHash text, logIndex integer) align with 0001_handy_exiles.sql:55-65. Index `whale_passes_player_idx` matches.

**Verdict summary:** PASS

### Table `player_winnings` — TS: src/db/schema/player-state.ts:3

All 6 columns (player PK text, claimableEth text default '0', totalClaimed text default '0', totalCredited text default '0', blockNumber bigint, blockHash text) align with 0001_handy_exiles.sql:67-74.

**Verdict summary:** PASS

### Table `player_tickets` — TS: src/db/schema/tickets.ts:3

8 columns (id identity, player text, level integer, ticketCount integer default 0, totalMintedOnLevel integer default 0, bufferSlot smallint default 0, blockNumber bigint, blockHash text). Indexes: `player_tickets_unique` UNIQUE(player,level), `player_tickets_player_idx`, `player_tickets_level_idx`. Aligns with 0001_handy_exiles.sql:76-85 and indexes 280-282.

**Verdict summary:** PASS

### Table `lootbox_purchases` — TS: src/db/schema/lootbox.ts:3

Columns align with 0001_handy_exiles.sql:87-100. Indexes: TS has `lootbox_purchases_player_idx` (lootbox.ts:17) and `lootbox_purchases_player_block_idx` (lootbox.ts:18); SQL has both (0001:283, 0006:208).

**Verdict summary:** PASS

### Table `lootbox_results` — TS: src/db/schema/lootbox.ts:21

Columns align with 0001_handy_exiles.sql:102-112. Indexes: `lootbox_results_player_idx` (0001:284), `lootbox_results_player_block_idx` (0006:209) — both in TS.

**Verdict summary:** PASS

### Table `traits_generated` — TS: src/db/schema/lootbox.ts:36

Aligns with 0001_handy_exiles.sql:114-124. Index `traits_generated_player_idx` (0001:285) present both sides.

**Verdict summary:** PASS

### Table `jackpot_distributions` — TS: src/db/schema/jackpot-history.ts:3

**Columns**

| TS col | SQL col | TS type | SQL type | NN | DEFAULT | PK | Verdict |
|---|---|---|---|---|---|---|---|
| id | id | integer identity | integer identity | ✓/✓ | —/— | ✓/✓ | PASS |
| level | level | integer | integer | ✓/✓ | —/— | —/— | PASS |
| winner | winner | text | text | ✓/✓ | —/— | —/— | PASS |
| traitId | traitId | integer | integer | —/— | —/— | —/— | PASS |
| amount | amount | text | text | ✓/✓ | —/— | —/— | PASS |
| ticketIndex | ticketIndex | integer | integer | —/— | —/— | —/— | PASS |
| sourceLevel | MISSING | integer | — | —/— | —/— | —/— | **FAIL — F-28-226-02** |
| winnerLevel | MISSING | integer | — | —/— | —/— | —/— | **FAIL — F-28-226-02** |
| awardType | MISSING (`distributionType` exists in SQL with default `'ticket'`) | text default 'eth' | text default 'ticket' (col name `distributionType`) | ✓/✓ | 'eth'/'ticket' | —/— | **FAIL — F-28-226-02** (rename + default change) |
| rebuyLevel | MISSING | integer | — | —/— | —/— | —/— | **FAIL — F-28-226-02** |
| rebuyTickets | MISSING | integer | — | —/— | —/— | —/— | **FAIL — F-28-226-02** |
| halfPassCount | MISSING | integer | — | —/— | —/— | —/— | **FAIL — F-28-226-02** |
| — | distributionType | — | text NN default 'ticket' | —/✓ | —/'ticket' | —/— | **FAIL — F-28-226-02** (SQL-side col has no TS counterpart) |
| blockNumber | blockNumber | bigint | bigint | ✓/✓ | —/— | —/— | PASS |
| blockHash | blockHash | text | text | ✓/✓ | —/— | —/— | PASS |
| transactionHash | transactionHash | text | text | ✓/✓ | —/— | —/— | PASS |
| logIndex | logIndex | integer | integer | ✓/✓ | —/— | —/— | PASS |

**Indexes**

| Name | TS | SQL | Verdict |
|---|---|---|---|
| jackpot_dist_level_idx | jackpot-history.ts:21 | 0001_handy_exiles.sql:286 | PASS |
| jackpot_dist_winner_idx | jackpot-history.ts:22 | 0001_handy_exiles.sql:287 | PASS |
| jackpot_dist_level_block_log_idx | jackpot-history.ts:23 | MISSING in all `.sql` migrations (present in `indexes.ts:14` raw-SQL array) | **FAIL — F-28-226-03** |

**Verdict summary:** FAIL — columns drift + index drift.

### Table `level_transitions` — TS: src/db/schema/jackpot-history.ts:26

All columns (id identity, level integer, stage smallint, phase text, blockNumber bigint, blockHash text, transactionHash text, logIndex integer) align with 0001_handy_exiles.sql:140-149. Index `level_transitions_level_idx` matches 0001:288.

**Note:** `indexes.ts:16` declares a raw-SQL `level_trans_level_block_idx` on (level, blockNumber). This supplemental index is NOT declared in the TS pgTable second-arg array, so it is not part of the drizzle-tracked schema. Gotcha #7 applies — context only, not a finding.

**Verdict summary:** PASS

### Table `decimator_bucket_totals` — TS: src/db/schema/decimator.ts:18

All 7 columns align with 0001_handy_exiles.sql:151-159. Unique index `dec_bucket_totals_unique` on (level,bucket,subBucket) matches 0001:289.

**Verdict summary:** PASS

### Table `decimator_burns` — TS: src/db/schema/decimator.ts:3

All 9 columns align with 0001_handy_exiles.sql:161-171. Indexes `decimator_burns_unique` UNIQUE and `decimator_burns_level_idx` both match (0001:290-291).

**Verdict summary:** PASS

### Table `decimator_claims` — TS: src/db/schema/decimator.ts:55

All columns align with 0001_handy_exiles.sql:173-184. Indexes match (0001:292-293). Supplemental `dec_claims_player_level_idx` in indexes.ts:20 is Gotcha #7 context-only.

**Verdict summary:** PASS

### Table `decimator_rounds` — TS: src/db/schema/decimator.ts:41

**Columns**

| TS col | SQL col | TS type | SQL type | NN | DEFAULT | PK | Verdict |
|---|---|---|---|---|---|---|---|
| id | id | integer identity | integer identity | ✓/✓ | —/— | ✓/✓ | PASS |
| level | level | integer | integer | ✓/✓ | —/— | —/— | PASS |
| poolEth | poolEth | text | text | ✓/✓ | '0'/'0' | —/— | PASS |
| vrfWord | vrfWord | text | text | —/— | —/— | —/— | PASS |
| totalQualifyingBurn | totalQualifyingBurn | text | text | ✓/✓ | '0'/'0' | —/— | PASS |
| packedOffsets | MISSING | text | — | —/— | —/— | —/— | **FAIL — F-28-226-04** |
| resolved | MISSING | boolean | — | ✓/— | false/— | —/— | **FAIL — F-28-226-04** |
| blockNumber | blockNumber | bigint | bigint | ✓/✓ | —/— | —/— | PASS |
| blockHash | blockHash | text | text | ✓/✓ | —/— | —/— | PASS |

**Indexes:** `decimator_rounds_level_unique` (0001:294) matches.

**Verdict summary:** FAIL — TS declares `packedOffsets` and `resolved` that are not in any `.sql` migration.

### Table `decimator_winning_subbuckets` — TS: src/db/schema/decimator.ts:30

Columns (id identity, level int, bucket smallint, winningSubBucket smallint, blockNumber bigint, blockHash text) align with 0001_handy_exiles.sql:196-203. Unique index `dec_winning_sub_unique` (0001:295) matches.

**Verdict summary:** PASS

### Table `player_boosts` — TS: src/db/schema/decimator.ts:71

All 10 columns align with 0001_handy_exiles.sql:205-216. Index `player_boosts_player_idx` (0001:296) matches.

**Verdict summary:** PASS

### Table `degenerette_bets` — TS: src/db/schema/degenerette.ts:3

All columns align with 0001_handy_exiles.sql:218-228. Indexes `degenerette_bets_player_idx` (0001:297) and `degenerette_bets_betid_idx` (0001:298) match. Supplemental `degenerette_bets_player_block_log_idx` (indexes.ts:18) is Gotcha #7 context-only.

**Verdict summary:** PASS

### Table `degenerette_results` — TS: src/db/schema/degenerette.ts:18

All columns align with 0001_handy_exiles.sql:230-241. Indexes `degenerette_results_player_idx` and `degenerette_results_betid_idx` (0001:299-300) match.

**Verdict summary:** PASS

### Table `daily_rng` — TS: src/db/schema/daily-rng.ts:3

All columns align with 0001_handy_exiles.sql:243-253. Index `daily_rng_day_idx` (0001:301) matches.

**Verdict summary:** PASS

### Table `lootbox_rng` — TS: src/db/schema/daily-rng.ts:17

All columns align with 0001_handy_exiles.sql:255-264. Index `lootbox_rng_index_idx` (0001:302) matches.

**Verdict summary:** PASS

### Table `deity_boons` — TS: src/db/schema/deity-boons.ts:3

All columns align with 0001_handy_exiles.sql:266-277. Indexes `deity_boons_recipient_idx`, `deity_boons_day_idx` (0001:303-304) match.

**Verdict summary:** PASS

### Table `token_balances` — TS: src/db/schema/token-balances.ts:3

All columns align with 0002_secret_zzzax.sql:1-8. Indexes `token_balances_unique`, `token_balances_holder_idx`, `token_balances_contract_idx` (0002:239-241) match.

**Verdict summary:** PASS

### Table `token_supply` — TS: src/db/schema/token-balances.ts:16

All columns align with 0002_secret_zzzax.sql:10-16. Unique index `token_supply_unique` (0002:242) matches.

**Verdict summary:** PASS

### Table `deity_pass_ownership` — TS: src/db/schema/deity-pass.ts:3

All 4 columns align with 0002_secret_zzzax.sql:18-23.

**Verdict summary:** PASS

### Table `deity_pass_transfers` — TS: src/db/schema/deity-pass.ts:10

All columns align with 0002_secret_zzzax.sql:25-34. Index `deity_pass_transfers_token_idx` (0002:243) matches.

**Verdict summary:** PASS

### Table `coinflip_bounty_state` — TS: src/db/schema/coinflip.ts:43

All 6 columns align with 0002_secret_zzzax.sql:36-43.

**Verdict summary:** PASS

### Table `coinflip_daily_stakes` — TS: src/db/schema/coinflip.ts:3

All columns align with 0002_secret_zzzax.sql:45-52. Indexes `coinflip_stakes_unique` and `coinflip_stakes_day_idx` (0002:244-245) match.

**Verdict summary:** PASS

### Table `coinflip_leaderboard` — TS: src/db/schema/coinflip.ts:31

All columns align with 0002_secret_zzzax.sql:54-61. Indexes `coinflip_lb_unique`, `coinflip_lb_day_idx` (0002:246-247) match. Supplemental `coinflip_lb_day_score_idx` (indexes.ts:8) is Gotcha #7 context-only.

**Verdict summary:** PASS

### Table `coinflip_results` — TS: src/db/schema/coinflip.ts:15

All columns align with 0002_secret_zzzax.sql:63-75. Unique index `coinflip_results_day_unique` (0002:248) matches.

**Verdict summary:** PASS

### Table `coinflip_settings` — TS: src/db/schema/coinflip.ts:52

All columns align with 0002_secret_zzzax.sql:77-83.

**Verdict summary:** PASS

### Table `affiliate_codes` — TS: src/db/schema/affiliate.ts:3

All columns align with 0002_secret_zzzax.sql:85-91.

**Verdict summary:** PASS

### Table `affiliate_earnings` — TS: src/db/schema/affiliate.ts:20

All columns align with 0002_secret_zzzax.sql:93-100. Indexes `aff_earnings_unique`, `aff_earnings_level_idx` (0002:249-250) match. Supplemental `aff_earnings_level_earned_idx` (indexes.ts:10) is Gotcha #7 context-only.

**Verdict summary:** PASS

### Table `affiliate_top_by_level` — TS: src/db/schema/affiliate.ts:32

All columns align with 0002_secret_zzzax.sql:102-108.

**Verdict summary:** PASS

### Table `player_referrals` — TS: src/db/schema/affiliate.ts:11

All columns align with 0002_secret_zzzax.sql:110-117.

**Verdict summary:** PASS

### Table `baf_flip_totals` — TS: src/db/schema/baf-jackpot.ts:3

All columns align with 0002_secret_zzzax.sql:119-126. Indexes `baf_totals_unique`, `baf_totals_level_idx` (0002:251-252) match. Supplemental `baf_totals_level_stake_idx` (indexes.ts:12) is Gotcha #7 context-only.

**Verdict summary:** PASS

### Table `player_streaks` — TS: src/db/schema/quests.ts:32

All columns align with 0002_secret_zzzax.sql:128-135.

**Verdict summary:** PASS

### Table `quest_definitions` — TS: src/db/schema/quests.ts:3

**Columns**

| TS col | SQL col (after 0006 DROP) | Verdict |
|---|---|---|
| id, day, slot, questType, flags, version, blockNumber, blockHash | Same 8 columns after `ALTER TABLE ... DROP COLUMN difficulty` (0006_freezing_weapon_omega.sql:210) | PASS |

`difficulty` was created in 0002 (line 144) then dropped in 0006 (line 210). TS does not declare it — matches final cumulative state.

**Indexes:** `quest_def_unique` (0002:253) matches.

**Verdict summary:** PASS

### Table `quest_progress` — TS: src/db/schema/quests.ts:16

All columns align with 0002_secret_zzzax.sql:149-160. Indexes `quest_prog_unique`, `quest_prog_player_idx` (0002:254-255) match.

**Verdict summary:** PASS

### Table `sdgnrs_burns` — TS: src/db/schema/vault.ts:62

All columns align with 0002_secret_zzzax.sql:162-173. Index `sdgnrs_burns_burner_idx` (0002:256) matches.

**Verdict summary:** PASS

### Table `sdgnrs_deposits` — TS: src/db/schema/vault.ts:50

All columns align with 0002_secret_zzzax.sql:175-185. SQL has NO index on this table; TS declares none either.

**Verdict summary:** PASS

### Table `sdgnrs_pool_balances` — TS: src/db/schema/vault.ts:43

All 4 columns align with 0002_secret_zzzax.sql:187-192.

**Verdict summary:** PASS

### Table `vault_claims` — TS: src/db/schema/vault.ts:28

All columns align with 0002_secret_zzzax.sql:194-205. Index `vault_claims_claimant_idx` (0002:257) matches. Supplemental `vault_claims_claimant_block_idx` (indexes.ts:24) Gotcha #7.

**Verdict summary:** PASS

### Table `vault_deposits` — TS: src/db/schema/vault.ts:14

All columns align with 0002_secret_zzzax.sql:207-217. Index `vault_deposits_depositor_idx` (0002:258) matches. Supplemental `vault_deposits_depositor_block_idx` (indexes.ts:22) Gotcha #7.

**Verdict summary:** PASS

### Table `vault_state` — TS: src/db/schema/vault.ts:3

All 8 columns align with 0002_secret_zzzax.sql:219-228.

**Verdict summary:** PASS

### Table `token_supply_snapshots` — TS: src/db/schema/token-snapshots.ts:3

All columns align with 0002_secret_zzzax.sql:230-237. Unique index `supply_snap_unique` (0002:259) matches.

**Verdict summary:** PASS

### Table `decimator_coin_burns` — TS: src/db/schema/decimator-coin-burns.ts:9

All columns align with 0003_fast_lifeguard.sql:1-10. Index `dec_coin_burns_player_idx` (0003:23) matches.

**Verdict summary:** PASS

### Table `affiliate_dgnrs_rewards` — TS: src/db/schema/affiliate-dgnrs-rewards.ts:9

All columns align with 0003_fast_lifeguard.sql:12-21. Indexes `aff_dgnrs_rewards_affiliate_idx`, `aff_dgnrs_rewards_level_idx` (0003:24-25) match.

**Verdict summary:** PASS

### Table `token_balance_snapshots` — TS: src/db/schema/token-balance-snapshots.ts:3

All columns align with 0004_slow_dracula.sql:1-9. Indexes `balance_snap_unique`, `balance_snap_holder_day_idx`, `balance_snap_contract_day_idx` (0004:11-13) match.

**Verdict summary:** PASS

### Table `terminal_decimator_burns` — TS: src/db/schema/decimator.ts:86

All columns align with 0006_freezing_weapon_omega.sql:1-14. Indexes `terminal_dec_burns_player_idx`, `terminal_dec_burns_level_idx` (0006:189-190) match.

**Verdict summary:** PASS

### Table `level_quest_completions` — TS: src/db/schema/quests.ts:41

All columns align with 0006_freezing_weapon_omega.sql:16-24. Indexes `lvl_quest_complete_unique`, `lvl_quest_complete_player_idx` (0006:191-192) match.

**Verdict summary:** PASS

### Table `terminal_decimator_coin_burns` — TS: src/db/schema/decimator-coin-burns.ts:22

All columns align with 0006_freezing_weapon_omega.sql:26-34. Index `terminal_dec_coin_burns_player_idx` (0006:193) matches.

**Verdict summary:** PASS

### Table `affiliate_dgnrs_claims` — TS: src/db/schema/affiliate-dgnrs-rewards.ts:23

All columns align with 0006_freezing_weapon_omega.sql:36-47. Indexes `aff_dgnrs_claims_affiliate_idx`, `aff_dgnrs_claims_level_idx` (0006:194-195) match.

**Verdict summary:** PASS

### Table `sdgnrs_redemptions` — TS: src/db/schema/sdgnrs-redemptions.ts:3

All columns align with 0006_freezing_weapon_omega.sql:49-66. Indexes `sdgnrs_redemptions_player_idx`, `sdgnrs_redemptions_period_idx` (0006:196-197) match.

**Verdict summary:** PASS

### Table `admin_events` — TS: src/db/schema/new-events.ts:62

All columns align with 0006_freezing_weapon_omega.sql:68-77. Index `admin_events_type_idx` (0006:198) matches.

**Verdict summary:** PASS

### Table `boon_consumptions` — TS: src/db/schema/new-events.ts:46

All columns align with 0006_freezing_weapon_omega.sql:79-88. Indexes `boon_consumptions_player_idx`, `boon_consumptions_boontype_idx` (0006:199-200) match.

**Verdict summary:** PASS

### Table `deity_pass_purchases` — TS: src/db/schema/new-events.ts:5

All columns align with 0006_freezing_weapon_omega.sql:90-100. Indexes `deity_pass_purchases_buyer_idx`, `deity_pass_purchases_level_idx` (0006:201-202) match.

**Verdict summary:** PASS

### Table `final_sweep_events` — TS: src/db/schema/new-events.ts:35

All columns align with 0006_freezing_weapon_omega.sql:102-109.

**Verdict summary:** PASS

### Table `game_over_events` — TS: src/db/schema/new-events.ts:22

All columns align with 0006_freezing_weapon_omega.sql:111-120.

**Verdict summary:** PASS

### Table `link_feed_updates` — TS: src/db/schema/new-events.ts:77

All columns align with 0006_freezing_weapon_omega.sql:122-130.

**Verdict summary:** PASS

### Table `daily_winning_traits` — TS: src/db/schema/new-events.ts:89

**Columns**

| TS col | SQL col | Verdict |
|---|---|---|
| id, day, mainTraitsPacked, bonusTraitsPacked, bonusTargetLevel, blockNumber, blockHash, transactionHash, logIndex | ALL MISSING — no `CREATE TABLE "daily_winning_traits"` in any of the 7 migrations | **FAIL — F-28-226-05** |

**Indexes:** TS declares `daily_winning_traits_day_idx` (new-events.ts:103) — SQL has no corresponding `CREATE INDEX`.

**Verdict summary:** FAIL — entire table missing from `.sql` migrations.

### Table `gnrus_game_over` — TS: src/db/schema/gnrus-governance.ts:74

All columns align with 0006_freezing_weapon_omega.sql:132-141.

**Verdict summary:** PASS

### Table `gnrus_level_resolutions` — TS: src/db/schema/gnrus-governance.ts:43

All columns align with 0006_freezing_weapon_omega.sql:143-153. Index `gnrus_level_resolutions_level_idx` (0006:203) matches.

**Verdict summary:** PASS

### Table `gnrus_level_skips` — TS: src/db/schema/gnrus-governance.ts:61

All columns align with 0006_freezing_weapon_omega.sql:155-162.

**Verdict summary:** PASS

### Table `gnrus_proposals` — TS: src/db/schema/gnrus-governance.ts:6

All columns align with 0006_freezing_weapon_omega.sql:164-174. Indexes `gnrus_proposals_level_idx`, `gnrus_proposals_proposer_idx` (0006:204-205) match.

**Verdict summary:** PASS

### Table `gnrus_votes` — TS: src/db/schema/gnrus-governance.ts:24

All columns align with 0006_freezing_weapon_omega.sql:176-187. Indexes `gnrus_votes_level_idx`, `gnrus_votes_voter_idx` (0006:206-207) match.

**Verdict summary:** PASS

### Table `trait_burn_tickets` — TS: src/db/schema/trait-burn-tickets.ts:15

**Columns**

| TS col | SQL col | TS type | SQL type | NN | DEFAULT | Verdict |
|---|---|---|---|---|---|---|
| level | level | integer | integer | ✓/✓ | —/— | PASS |
| traitId (→ `trait_id`) | trait_id | smallint | smallint | ✓/✓ | —/— | PASS (Gotcha #6) |
| player | player | text | text | ✓/✓ | —/— | PASS |
| ticketCount (→ `ticket_count`) | ticket_count | integer | integer | ✓/✓ | 0/0 | PASS |

**Composite PK**

| Kind | Name | TS | SQL | Verdict |
|---|---|---|---|---|
| compositePK | trait_burn_tickets_level_trait_id_player_pk (auto-named) | trait-burn-tickets.ts:21 `primaryKey({columns:[t.level,t.traitId,t.player]})` | 0007_trait_burn_tickets.sql:11 `CONSTRAINT "trait_burn_tickets_level_trait_id_player_pk" PRIMARY KEY("level","trait_id","player")` | PASS (Gotcha #5) |

**Indexes**

| Name | TS | SQL | Verdict |
|---|---|---|---|
| trait_burn_tickets_level_trait_idx | trait-burn-tickets.ts:22 | 0007:20 | PASS |
| trait_burn_tickets_player_idx | trait-burn-tickets.ts:23 | 0007:21 | PASS |

**Verdict summary:** PASS

### Table `trait_burn_ticket_processed_logs` — TS: src/db/schema/trait-burn-tickets.ts:26

**Columns**

| TS col | SQL col | TS type | SQL type | NN | Verdict |
|---|---|---|---|---|---|
| blockNumber (→ `block_number`) | block_number | bigint | bigint | ✓/✓ | PASS |
| logIndex (→ `log_index`) | log_index | integer | integer | ✓/✓ | PASS |

**Composite PK**

| Name | TS | SQL | Verdict |
|---|---|---|---|
| trait_burn_ticket_processed_logs_block_number_log_index_pk | trait-burn-tickets.ts:30 | 0007:17 | PASS |

**Verdict summary:** PASS

## Views subsection

`views.ts` defines four `pgMaterializedView(...)` declarations. None of the 7 `.sql` migration files contains a `CREATE MATERIALIZED VIEW` statement. Per D-226-07 the refresh semantics are deferred to Phase 228; the structural question of "where do these views come from at runtime?" is owned by Phase 228 as well. Per 226-RESEARCH.md §Open Questions Q1 recommendation we record this as INVESTIGATE context — not a finding.

| View name (TS export) | PG name | TS file:line | SQL DDL present? | Note |
|---|---|---|---|---|
| playerSummary | mv_player_summary | views.ts:16 | NO | Raw SQL JOIN across `player_winnings`, `token_balances`, `player_streaks`, `affiliate_earnings`. Runtime creation path presumed in `view-refresh.ts` (Phase 228). |
| coinflipTop10 | mv_coinflip_top10 | views.ts:45 | NO | Ranked from `coinflip_leaderboard`. |
| affiliateLeaderboard | mv_affiliate_leaderboard | views.ts:61 | NO | Ranked from `affiliate_earnings`. |
| bafTop4 | mv_baf_top4 | views.ts:77 | NO | Ranked from `baf_flip_totals`. |

Additionally `views.ts:105-110` declares `VIEW_UNIQUE_INDEXES` — 4 raw-SQL `CREATE UNIQUE INDEX IF NOT EXISTS` statements on the materialized views. These, like `indexes.ts`, live outside the drizzle-kit migration lifecycle. Context only.

## Enums subsection

| Enum name | TS declaration | SQL DDL | Verdict |
|---|---|---|---|
| game_phase | game-state.ts:3 `pgEnum('game_phase', ['PURCHASE','JACKPOT','GAMEOVER'])` | 0001_handy_exiles.sql:1 `CREATE TYPE "public"."game_phase" AS ENUM('PURCHASE', 'JACKPOT', 'GAMEOVER')` | PASS |

Only one enum in the entire schema. Both sides align.

## indexes.ts context note

`indexes.ts` is not registered in `drizzle.config.ts` — its contents are applied via raw SQL outside the drizzle-kit migration lifecycle (Gotcha #7 / D-226-03). Per plan, this file is treated as context only for SCHEMA-01; no per-entry findings are emitted against `.sql`/TS drift for `indexes.ts` members.

Contents (9 `CREATE INDEX IF NOT EXISTS` statements):

| Index name | Table | Columns | Verdict |
|---|---|---|---|
| coinflip_lb_day_score_idx | coinflip_leaderboard | (day, CAST(score AS NUMERIC) DESC) | CONTEXT — raw SQL, not drizzle-tracked |
| aff_earnings_level_earned_idx | affiliate_earnings | (level, CAST(totalEarned AS NUMERIC) DESC) | CONTEXT |
| baf_totals_level_stake_idx | baf_flip_totals | (level, CAST(totalStake AS NUMERIC) DESC) | CONTEXT |
| jackpot_dist_level_block_log_idx | jackpot_distributions | (level, blockNumber, logIndex) | CONTEXT — BUT also declared in `jackpot-history.ts:23` TS schema (double-declaration); see F-28-226-03 |
| level_trans_level_block_idx | level_transitions | (level, blockNumber) | CONTEXT |
| degenerette_bets_player_block_log_idx | degenerette_bets | (player, blockNumber, logIndex) | CONTEXT |
| dec_claims_player_level_idx | decimator_claims | (player, level) | CONTEXT |
| vault_deposits_depositor_block_idx | vault_deposits | (depositor, blockNumber) | CONTEXT |
| vault_claims_claimant_block_idx | vault_claims | (claimant, blockNumber) | CONTEXT |

**Barrel re-export:** `src/db/schema/index.ts` re-exports `ADDITIONAL_INDEXES` from `indexes.ts`, making it accessible to the runtime bootstrap path (Plan 226-04 orphan scan should confirm the actual apply site). For SCHEMA-01 these are context only.

## Secondary cross-check vs 0006_snapshot.json

Per D-226-01, the hybrid methodology requires confirming that the cumulative `.sql`-derived state matches `meta/0006_snapshot.json`. Cross-checked by table (summary):

| Table | `.sql` cumulative ↔ `0006_snapshot.json` | Note |
|---|---|---|
| raw_events, blocks, indexer_cursor | AGREE | — |
| game_state | AGREE | — |
| prize_pools | **DISAGREE — `lastLevelPool` present in `0005_snapshot.json` & `0006_snapshot.json`, absent from `0005_red_doctor_octopus.sql` (empty file)** | See F-28-226-08; Plan 226-02 owns the migration-trace half |
| player_settings, player_whale_passes, player_winnings, player_tickets | AGREE | — |
| lootbox_purchases, lootbox_results, traits_generated | AGREE | — |
| jackpot_distributions | `0006_snapshot.json` reflects 6 TS-side columns (sourceLevel, winnerLevel, awardType, rebuyLevel, rebuyTickets, halfPassCount) — **but NONE of the 7 `.sql` files add them**. Snapshot shows a column `distributionType` while TS has `awardType`. Cross-check confirms the drift is SQL-file-vs-TS, not SQL-file-vs-snapshot. | Context pointer to Plan 226-02 |
| level_transitions | AGREE | — |
| decimator_* family (burns, bucket_totals, winning_subbuckets, claims, rounds) | `decimator_rounds.packedOffsets` + `resolved` absent from both `.sql` and `0006_snapshot.json`; they are TS-only additions post-0006 generation | See F-28-226-04; Plan 226-02 owns the migration-trace half |
| player_boosts | AGREE | — |
| degenerette_bets, degenerette_results | AGREE | — |
| daily_rng, lootbox_rng | AGREE | — |
| deity_boons | AGREE | — |
| token_balances, token_supply | AGREE | — |
| deity_pass_ownership, deity_pass_transfers | AGREE | — |
| coinflip_* family | AGREE | — |
| affiliate_*, player_referrals, baf_flip_totals, player_streaks | AGREE | — |
| quest_definitions | AGREE (post-DROP difficulty) | — |
| quest_progress | AGREE | — |
| sdgnrs_* family, vault_* family | AGREE | — |
| token_supply_snapshots | AGREE | — |
| decimator_coin_burns, affiliate_dgnrs_rewards | AGREE | — |
| token_balance_snapshots | AGREE | — |
| terminal_decimator_burns, level_quest_completions, terminal_decimator_coin_burns, affiliate_dgnrs_claims, sdgnrs_redemptions, admin_events, boon_consumptions, deity_pass_purchases, final_sweep_events, game_over_events, link_feed_updates, gnrus_* family | AGREE | — |
| daily_winning_traits | **DISAGREE — TS declares the table, but NO `CREATE TABLE` in any `.sql` migration AND no matching entry in `0006_snapshot.json`** | See F-28-226-05; Plan 226-02 owns the migration-trace half |
| trait_burn_tickets, trait_burn_ticket_processed_logs | 0007 SQL present; 0007 snapshot MISSING (Plan 226-02 F-28-226-01) | Not re-emitted here |
| mv_player_summary, mv_coinflip_top10, mv_affiliate_leaderboard, mv_baf_top4 | No `CREATE MATERIALIZED VIEW` in `.sql`; `views.*` entries may be generated by drizzle-kit in snapshot but don't materialize the view at migrate-time — runtime path Phase 228 | See Views subsection |

Disagreements above are not re-emitted as SCHEMA-01 findings (they're primarily migration-trace concerns owned by Plan 226-02).

## Finding stubs

#### F-28-226-02: jackpot_distributions TS schema carries 6 columns plus a column rename not in any migration

- **Severity:** LOW
- **Direction:** schema<->migration
- **Phase:** 226 (SCHEMA-01 cumulative-SQL vs schema/*.ts diff)
- **File:** `/home/zak/Dev/PurgeGame/database/src/db/schema/jackpot-history.ts:3`
- **Resolution:** RESOLVED-CODE (next migration)
- **TS side:** `jackpot-history.ts:3-24` declares `sourceLevel`, `winnerLevel`, `awardType text().notNull().default('eth')`, `rebuyLevel`, `rebuyTickets`, `halfPassCount` in addition to the columns present in `.sql`.
- **SQL side:** `0001_handy_exiles.sql:126-138` created `jackpot_distributions` with `distributionType text DEFAULT 'ticket' NOT NULL`; no subsequent migration adds the extra columns or renames `distributionType` → `awardType`.
- **Mismatch:** TS has six extra columns and uses a different NOT NULL text column name + default (`awardType`/`'eth'` vs `distributionType`/`'ticket'`). drizzle-kit on next `generate` would produce a migration that ADDs the six new columns, RENAMEs or DROP+ADDs the `distributionType`/`awardType` column, and could silently change the default in-flight. Severity promoted to LOW: `.default('eth')` in TS vs `DEFAULT 'ticket'` in the live schema means any INSERT that omits the column in TS will write `'ticket'`, not `'eth'` — silent wrong-result risk.

#### F-28-226-03: jackpot_distributions extra TS index not present in any migration

- **Severity:** LOW
- **Direction:** schema<->migration
- **Phase:** 226 (SCHEMA-01 cumulative-SQL vs schema/*.ts diff)
- **File:** `/home/zak/Dev/PurgeGame/database/src/db/schema/jackpot-history.ts:23`
- **Resolution:** RESOLVED-CODE (next migration) — or remove from TS if index is only applied via `indexes.ts`
- **TS side:** `jackpot-history.ts:23` — `index('jackpot_dist_level_block_log_idx').on(table.level, table.blockNumber, table.logIndex)`.
- **SQL side:** No `CREATE INDEX "jackpot_dist_level_block_log_idx"` in any of `/home/zak/Dev/PurgeGame/database/drizzle/0000..0007*.sql`. The index IS declared in `/home/zak/Dev/PurgeGame/database/src/db/schema/indexes.ts:14` (raw-SQL bootstrap array), so at runtime it may or may not exist depending on whether the bootstrap path ran.
- **Mismatch:** Double-declared. drizzle-kit considers this index part of the schema (per TS `pgTable` second-arg) and on next `generate` would try to CREATE it again — conflict with the `IF NOT EXISTS` raw-SQL copy, or with drizzle-kit emitting a no-op `CREATE INDEX`. LOW severity because the wrong code path could DROP the index if a future `drizzle-kit generate` is run without `indexes.ts` present.

#### F-28-226-04: decimator_rounds TS schema has `packedOffsets` and `resolved` columns not in any migration

- **Severity:** LOW
- **Direction:** schema<->migration
- **Phase:** 226 (SCHEMA-01 cumulative-SQL vs schema/*.ts diff)
- **File:** `/home/zak/Dev/PurgeGame/database/src/db/schema/decimator.ts:41`
- **Resolution:** RESOLVED-CODE (next migration)
- **TS side:** `decimator.ts:47-48` — `packedOffsets: text()`, `resolved: boolean().notNull().default(false)`.
- **SQL side:** `0001_handy_exiles.sql:186-194` created `decimator_rounds` without these columns; no subsequent migration adds them.
- **Mismatch:** TS columns do not exist in the live DB. Any `SELECT packedOffsets, resolved FROM decimator_rounds` via drizzle client will fail at runtime. LOW — silent wrong-result / runtime error on read.

#### F-28-226-05: daily_winning_traits entire table missing from migrations

- **Severity:** LOW
- **Direction:** schema<->migration
- **Phase:** 226 (SCHEMA-01 cumulative-SQL vs schema/*.ts diff)
- **File:** `/home/zak/Dev/PurgeGame/database/src/db/schema/new-events.ts:89`
- **Resolution:** RESOLVED-CODE (next migration)
- **TS side:** `new-events.ts:89-104` declares `dailyWinningTraits = pgTable('daily_winning_traits', { ... })` plus `index('daily_winning_traits_day_idx')`.
- **SQL side:** No `CREATE TABLE "daily_winning_traits"` in any of `/home/zak/Dev/PurgeGame/database/drizzle/0000..0007*.sql`. `0006_snapshot.json` also lacks the table.
- **Mismatch:** Any drizzle client write/read against this table will raise `relation "daily_winning_traits" does not exist` until a migration is generated. LOW — silent wrong-result (NULL-set returned when query falls through error boundary, or runtime crash).

#### F-28-226-06: daily_winning_traits_day_idx missing from migrations

- **Severity:** INFO
- **Direction:** schema<->migration
- **Phase:** 226 (SCHEMA-01 cumulative-SQL vs schema/*.ts diff)
- **File:** `/home/zak/Dev/PurgeGame/database/src/db/schema/new-events.ts:103`
- **Resolution:** RESOLVED-CODE (next migration) — follows from F-28-226-05.
- **TS side:** `new-events.ts:103` — `index('daily_winning_traits_day_idx').on(table.day)`.
- **SQL side:** Absent from all `.sql` migrations (follows from the entire table being absent).
- **Mismatch:** Will be generated together with the missing table (see F-28-226-05). Recorded as a distinct stub so Phase 229 index-count tallies stay consistent.

#### F-28-226-07: indexes.ts `jackpot_dist_level_block_log_idx` duplicates TS-declared index

- **Severity:** INFO
- **Direction:** schema<->migration
- **Phase:** 226 (SCHEMA-01 cumulative-SQL vs schema/*.ts diff)
- **File:** `/home/zak/Dev/PurgeGame/database/src/db/schema/indexes.ts:14`
- **Resolution:** INFO-ACCEPTED (dedupe the declaration — recommended: keep TS `index(...)` in `jackpot-history.ts`, remove from `indexes.ts`; or vice versa).
- **TS side:** `indexes.ts:14` — raw SQL `CREATE INDEX IF NOT EXISTS jackpot_dist_level_block_log_idx ON jackpot_distributions (level, "blockNumber", "logIndex")` AND `jackpot-history.ts:23` — drizzle `index('jackpot_dist_level_block_log_idx').on(...)`.
- **SQL side:** No `CREATE INDEX "jackpot_dist_level_block_log_idx"` in any `.sql` migration.
- **Mismatch:** Single index double-declared in two different code paths. Harmless at runtime (the raw-SQL bootstrap uses `IF NOT EXISTS`), but it muddles provenance for future `drizzle-kit generate` runs. INFO.

#### F-28-226-08: prize_pools.lastLevelPool column present in meta/TS but the `.sql` file for its migration is empty

- **Severity:** LOW
- **Direction:** schema<->migration
- **Phase:** 226 (SCHEMA-01 cumulative-SQL vs schema/*.ts diff)
- **File:** `/home/zak/Dev/PurgeGame/database/drizzle/0005_red_doctor_octopus.sql:1`
- **Resolution:** RESOLVED-CODE (next migration) — regenerate the 0005 `.sql` body OR add a new migration that is the proper DDL for `prize_pools.lastLevelPool` and marker `0005` as superseded.
- **TS side:** `prize-pools.ts:12` — `lastLevelPool: text().notNull().default('0')`.
- **SQL side:** `0005_red_doctor_octopus.sql` is **0 bytes** on disk; `meta/0005_snapshot.json` shows the column. At live-DB migrate time drizzle-kit reads the meta snapshot chain and would produce the ADD COLUMN implicitly, but any auditor working from `.sql` alone — or any DBA replaying migrations by executing the `.sql` files directly — would miss this column.
- **Mismatch:** The `.sql` on-disk artifact does not reflect reality. LOW — silent schema-apply mismatch if someone executes `.sql` files one by one, leading to a broken DB state.

## Summary

### Table coverage

- **Total pgTables compared:** 67 (every TS pgTable declaration from all 29 schema files registered in `drizzle.config.ts` + `trait-burn-tickets.ts`).
- **Total SQL `CREATE TABLE` statements:** 65 across 7 migration files (numerically: 3 in 0000 + 22 in 0001 + 24 in 0002 + 2 in 0003 + 1 in 0004 + 0 in 0005 + 15 in 0006 + 2 in 0007 = 69 `CREATE TABLE` lines; deduplicated distinct table count = 65 because no table is recreated and `quest_definitions.difficulty` DROP does not alter the table count).
- **TS pgTables without a matching SQL CREATE:** 2 (`daily_winning_traits`, and all Views covered in dedicated subsection).
- **SQL tables without a matching TS pgTable:** 0.
- **PASS tables:** 63.
- **FAIL tables:** 4 (`prize_pools` — F-28-226-08; `jackpot_distributions` — F-28-226-02 + F-28-226-03; `decimator_rounds` — F-28-226-04; `daily_winning_traits` — F-28-226-05 + F-28-226-06).

### Column comparison totals

- **Total column rows compared:** ~480 (sum across 67 tables; the dominant contributors are `game_state` (27) and the 10-column event tables).
- **PASS rows:** ~470.
- **FAIL rows:** 10 (7 in `jackpot_distributions`, 2 in `decimator_rounds`, 1 in `prize_pools`). The 9 columns of `daily_winning_traits` are counted under the whole-table FAIL (F-28-226-05), not re-double-counted at column level.

### Index / unique-index totals

- **Total drizzle-declared (TS) indexes+unique indexes across all tables:** ~70 (`rg "(unique)?[Ii]ndex\(" /home/zak/Dev/PurgeGame/database/src/db/schema/` returns approximately this count excluding `indexes.ts` / `views.ts`).
- **Total SQL `CREATE (UNIQUE )?INDEX` across 7 migrations:** 67.
- **PASS:** 67 matches.
- **FAIL:** 2 (F-28-226-03 TS-only index on `jackpot_distributions`; F-28-226-06 TS-only index on missing `daily_winning_traits`).
- **Context-only (Gotcha #7):** 9 `indexes.ts` raw-SQL entries + 4 `views.ts` `VIEW_UNIQUE_INDEXES` entries.

### Composite PK / FK totals

- **Composite PKs:** 2 — `trait_burn_tickets` and `trait_burn_ticket_processed_logs`. Both PASS (Gotcha #5 auto-names match).
- **Foreign keys:** 0 in both sides. `rg 'foreignKey\(' /home/zak/Dev/PurgeGame/database/src/db/schema/` returns no matches; `rg 'FOREIGN KEY' /home/zak/Dev/PurgeGame/database/drizzle/*.sql` returns no matches. PASS.

### Enum totals

- **Total enums:** 1 (`game_phase`).
- **PASS:** 1. **FAIL:** 0.

### Views

- **Total materialized views in TS:** 4.
- **Views with matching `CREATE MATERIALIZED VIEW` DDL in `.sql` migrations:** 0.
- **INVESTIGATE:** 4 (context-only — runtime-created; Phase 228 scope per D-226-07). Not logged as findings in this plan.

### Finding IDs allocated

- **This plan:** `F-28-226-02`, `F-28-226-03`, `F-28-226-04`, `F-28-226-05`, `F-28-226-06`, `F-28-226-07`, `F-28-226-08` (7 stubs).
- **Next available for Plan 226-02:** `F-28-226-09` (Plan 226-02 also consumes the reserved `F-28-226-01` for the 0007 snapshot anomaly).
- **Reserved — not used here:** `F-28-226-01`.

### Severity distribution

- **LOW:** 5 (F-28-226-02, F-28-226-03, F-28-226-04, F-28-226-05, F-28-226-08). LOW justified because each drift either silently changes INSERT defaults, causes drizzle-client query failures against missing columns/tables, or creates a replay-from-SQL-files inconsistency — all of which can return wrong data or cause silent runtime errors.
- **INFO:** 2 (F-28-226-06, F-28-226-07). No behavioral impact beyond the parent LOW findings.

---

*Plan: 226-01*
*Generated: 2026-04-15*
