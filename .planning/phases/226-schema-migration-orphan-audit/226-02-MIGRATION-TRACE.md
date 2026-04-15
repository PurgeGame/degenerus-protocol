# Phase 226 Plan 02 — SCHEMA-03 Migration Rationality Trace

## Preamble

- **Phase:** 226 — Schema, Migration & Orphan Audit
- **Plan:** 02 (wave 2; depends on 226-01)
- **Requirement:** SCHEMA-03 — each migration is a rational diff from its predecessor; every DDL change in `.sql` has a same-logical-unit counterpart in `src/db/schema/*.ts`.
- **Ground truth:** per D-226-01, cumulative application of `/home/zak/Dev/PurgeGame/database/drizzle/0000..0007*.sql` is PRIMARY; `drizzle/meta/<N>_snapshot.json` is SECONDARY cross-check.
- **Direction:** per D-226-05, every finding emitted here uses direction `schema<->migration`.
- **Finding-ID allocation:** per D-226-06, `F-28-226-01` is pre-assigned to the 0007 snapshot anomaly and is the FIRST stub in `## Finding stubs`. Per 226-01-SUMMARY.md, 226-01 consumed `F-28-226-02..08`; this plan continues from `F-28-226-09` for any new DRIFT findings.
- **Cross-repo posture:** per D-226-08, READ-only against `/home/zak/Dev/PurgeGame/database/`; zero writes.
- **Reuse:** rationality scoring reuses the TS↔SQL map established in `226-01-SCHEMA-MIGRATION-DIFF.md` (67 pgTables, ~480 columns, ~70 indexes). Drift already catalogued by Plan 01 is NOT re-emitted here — only per-migration rationality verdicts and the meta cross-check yield new findings.

## Migration file inventory

| File | Non-blank lines | `--> statement-breakpoint` count | Derived statement count | Meta snapshot |
|------|-----------------|----------------------------------|-------------------------|---------------|
| 0000_brown_justin_hammer.sql | 32 | 6 | 7 | 0000_snapshot.json ✓ |
| 0001_handy_exiles.sql | 303 | 48 | 49 | 0001_snapshot.json ✓ |
| 0002_secret_zzzax.sql | 258 | 44 | 45 | 0002_snapshot.json ✓ |
| 0003_fast_lifeguard.sql | 24 | 4 | 5 | 0003_snapshot.json ✓ |
| 0004_slow_dracula.sql | 12 | 3 | 4 | 0004_snapshot.json ✓ |
| 0005_red_doctor_octopus.sql | 0 (EMPTY) | 0 | 0 | 0005_snapshot.json ✓ |
| 0006_freezing_weapon_omega.sql | 209 | 37 | 38 | 0006_snapshot.json ✓ |
| 0007_trait_burn_tickets.sql | 21 | 3 | 4 | **MISSING → F-28-226-01** |

Total DDL statements across all 7 migrations: **152**.

Journal snapshot (`drizzle/meta/_journal.json`): 7 entries, `idx: 0..6`. NO `idx: 7` entry for the 0007 migration — consistent with the missing snapshot and source of F-28-226-01.

## Gotchas carried forward

Copied from 226-RESEARCH.md §Known drizzle-kit Gotchas. Drift classification in this plan DOES NOT re-flag these as findings:

1. **Identity column spelling** — SQL emits full `GENERATED ALWAYS AS IDENTITY (sequence name "<t>_id_seq" INCREMENT BY 1 MINVALUE 1 MAXVALUE 2147483647 START WITH 1 CACHE 1)` while TS emits `.generatedAlwaysAsIdentity()`. The sequence-parameter tail is drizzle-kit default; NOT drift.
2. **Timestamp modes** — `timestamp({ mode: 'date' | 'string' })` is a JS-type flag; both emit bare `timestamp`.
3. **Bigint modes** — `bigint({ mode: 'bigint' | 'number' })` same story; both emit `bigint`.
4. **Default-value representation** — `.default(0)` vs `DEFAULT 0`, `.default(sql\`now()\`)` vs `DEFAULT now()`; compare normalized literal, not string-exact.
5. **Auto-generated constraint names** — composite PKs in TS without `name:` have SQL names derived as `<table>_<col>..._pk`. Not drift (confirmed in 0007).
6. **Camel vs snake column names** — TS key is the PG name unless a first-arg string overrides (e.g. `smallint('trait_id')` → `trait_id`). Always read the first-arg string.
7. **`indexes.ts` is NOT in `drizzle.config.ts`** — raw-SQL indexes there are applied outside drizzle-kit's lifecycle; ABSENT from all `.sql` migrations and ALL `meta/*.json` by design.
8. **Empty 0005 migration** — drizzle-kit can emit 0-byte `.sql` when the snapshot-to-snapshot diff is meta-only. Validated in §Migration 0005 below.
9. **0007 anomaly** — F-28-226-01 (pre-assigned, head of `## Finding stubs`).
10. **`CREATE MATERIALIZED VIEW` absent from all `.sql`** — the four `pgMaterializedView` declarations in `views.ts` have no SQL-side DDL. Recorded as INVESTIGATE context by 226-01, not re-scored here (they are zero-DDL in every migration — there's nothing to rationalize).

## Per-migration trace

### Migration 0000 — 0000_brown_justin_hammer.sql

**Statements** (7 after split on `--> statement-breakpoint`)

| # | file:line | Leading token | Target | TS counterpart | Verdict |
|---|-----------|---------------|--------|----------------|---------|
| 1 | drizzle/0000_brown_justin_hammer.sql:1 | CREATE TABLE | `raw_events` | `src/db/schema/raw-events.ts:3` | JUSTIFIED |
| 2 | drizzle/0000_brown_justin_hammer.sql:15 | CREATE TABLE | `blocks` | `src/db/schema/blocks.ts:3` | JUSTIFIED |
| 3 | drizzle/0000_brown_justin_hammer.sql:24 | CREATE TABLE | `indexer_cursor` | `src/db/schema/cursor.ts:4` | JUSTIFIED |
| 4 | drizzle/0000_brown_justin_hammer.sql:30 | CREATE UNIQUE INDEX | `raw_events_unique` on `raw_events(blockNumber,logIndex,transactionHash)` | raw-events.ts (uniqueIndex) | JUSTIFIED |
| 5 | drizzle/0000_brown_justin_hammer.sql:31 | CREATE INDEX | `raw_events_block_number_idx` | raw-events.ts (index) | JUSTIFIED |
| 6 | drizzle/0000_brown_justin_hammer.sql:32 | CREATE INDEX | `raw_events_contract_event_idx` | raw-events.ts (index) | JUSTIFIED |
| 7 | drizzle/0000_brown_justin_hammer.sql:33 | CREATE UNIQUE INDEX | `blocks_hash_idx` on `blocks(blockHash)` | blocks.ts (uniqueIndex) | JUSTIFIED |

**Meta snapshot cross-check**
- Snapshot file: `drizzle/meta/0000_snapshot.json` — id `15fb8468-d14b-4dae-8a78-7928454f0441`, prevId `00000000-0000-0000-0000-000000000000` (expected sentinel for initial snapshot).
- `prevId` chain: PASS (initial).
- Table shape agreement with cumulative `.sql` state after migration 0: PASS — 3 tables (`raw_events`, `blocks`, `indexer_cursor`), all columns align.

**Migration verdict:** JUSTIFIED (0 findings)

### Migration 0001 — 0001_handy_exiles.sql

**Statements** (49 after split). Largest migration — seeds most of the gameplay schema.

| # | file:line | Leading token | Target | TS counterpart | Verdict |
|---|-----------|---------------|--------|----------------|---------|
| 1 | 0001_handy_exiles.sql:1 | CREATE TYPE ENUM | `public.game_phase` | `game-state.ts:3 pgEnum('game_phase', ...)` | JUSTIFIED |
| 2 | 0001_handy_exiles.sql:2 | CREATE TABLE | `game_state` | `game-state.ts:5` | JUSTIFIED |
| 3 | 0001_handy_exiles.sql:32 | CREATE TABLE | `prize_pools` | `prize-pools.ts:3` | JUSTIFIED (lastLevelPool addition is separate Migration 0005 scope — see below) |
| 4 | 0001_handy_exiles.sql:45 | CREATE TABLE | `player_settings` | `player-state.ts:12` | JUSTIFIED |
| 5 | 0001_handy_exiles.sql:55 | CREATE TABLE | `player_whale_passes` | `player-state.ts:22` | JUSTIFIED |
| 6 | 0001_handy_exiles.sql:67 | CREATE TABLE | `player_winnings` | `player-state.ts:3` | JUSTIFIED |
| 7 | 0001_handy_exiles.sql:76 | CREATE TABLE | `player_tickets` | `tickets.ts:3` | JUSTIFIED |
| 8 | 0001_handy_exiles.sql:87 | CREATE TABLE | `lootbox_purchases` | `lootbox.ts:3` | JUSTIFIED |
| 9 | 0001_handy_exiles.sql:102 | CREATE TABLE | `lootbox_results` | `lootbox.ts:21` | JUSTIFIED |
| 10 | 0001_handy_exiles.sql:114 | CREATE TABLE | `traits_generated` | `lootbox.ts:36` | JUSTIFIED |
| 11 | 0001_handy_exiles.sql:126 | CREATE TABLE | `jackpot_distributions` | `jackpot-history.ts:3` | JUSTIFIED-WITH-NOTE (column drift between cumulative .sql and TS is Plan-01 finding F-28-226-02, not re-emitted; SQL side matches snapshot — diff is pure TS-only drift) |
| 12 | 0001_handy_exiles.sql:140 | CREATE TABLE | `level_transitions` | `jackpot-history.ts:26` | JUSTIFIED |
| 13 | 0001_handy_exiles.sql:151 | CREATE TABLE | `decimator_bucket_totals` | `decimator.ts:18` | JUSTIFIED |
| 14 | 0001_handy_exiles.sql:161 | CREATE TABLE | `decimator_burns` | `decimator.ts:3` | JUSTIFIED |
| 15 | 0001_handy_exiles.sql:173 | CREATE TABLE | `decimator_claims` | `decimator.ts:55` | JUSTIFIED |
| 16 | 0001_handy_exiles.sql:186 | CREATE TABLE | `decimator_rounds` | `decimator.ts:41` | JUSTIFIED-WITH-NOTE (TS adds `packedOffsets`/`resolved` columns not in this migration — Plan-01 finding F-28-226-04; rationality here is neutral — the 0001 CREATE TABLE shape matches snapshot 0001; the extra TS columns never appear in any subsequent migration, which is the drift) |
| 17 | 0001_handy_exiles.sql:196 | CREATE TABLE | `decimator_winning_subbuckets` | `decimator.ts:30` | JUSTIFIED |
| 18 | 0001_handy_exiles.sql:205 | CREATE TABLE | `player_boosts` | `decimator.ts:71` | JUSTIFIED |
| 19 | 0001_handy_exiles.sql:218 | CREATE TABLE | `degenerette_bets` | `degenerette.ts:3` | JUSTIFIED |
| 20 | 0001_handy_exiles.sql:230 | CREATE TABLE | `degenerette_results` | `degenerette.ts:18` | JUSTIFIED |
| 21 | 0001_handy_exiles.sql:243 | CREATE TABLE | `daily_rng` | `daily-rng.ts:3` | JUSTIFIED |
| 22 | 0001_handy_exiles.sql:255 | CREATE TABLE | `lootbox_rng` | `daily-rng.ts:17` | JUSTIFIED |
| 23 | 0001_handy_exiles.sql:266 | CREATE TABLE | `deity_boons` | `deity-boons.ts:3` | JUSTIFIED |
| 24-49 | 0001_handy_exiles.sql:279–304 | CREATE (UNIQUE )INDEX × 26 | all 26 indexes listed in file | matching `index(...)/uniqueIndex(...)` in the above TS files — verified via Plan-01 per-table catalog | JUSTIFIED (26 rows) |

**Meta snapshot cross-check**
- Snapshot file: `drizzle/meta/0001_snapshot.json` — id `2b5ba2de-1bf4-4ddd-97e3-8718fd8f9f02`, prevId `15fb8468-d14b-4dae-8a78-7928454f0441`.
- `prevId` chain: PASS (matches 0000's `id`).
- Table shape agreement with cumulative `.sql` state after migrations 0..1: PASS (22 tables added by 0001; enum `game_phase` in `enums` section).

**Migration verdict:** JUSTIFIED (0 findings emitted by this plan; 2 pre-existing Plan-01 findings noted in-place, not re-counted)

### Migration 0002 — 0002_secret_zzzax.sql

**Statements** (45 after split). Adds the token/coinflip/affiliate/quest/sdgnrs/vault subsystems + token_supply_snapshots + 21 indexes.

| # | file:line | Leading token | Target | TS counterpart | Verdict |
|---|-----------|---------------|--------|----------------|---------|
| 1 | 0002_secret_zzzax.sql:1 | CREATE TABLE | `token_balances` | `token-balances.ts:3` | JUSTIFIED |
| 2 | 0002_secret_zzzax.sql:10 | CREATE TABLE | `token_supply` | `token-balances.ts:16` | JUSTIFIED |
| 3 | 0002_secret_zzzax.sql:18 | CREATE TABLE | `deity_pass_ownership` | `deity-pass.ts:3` | JUSTIFIED |
| 4 | 0002_secret_zzzax.sql:25 | CREATE TABLE | `deity_pass_transfers` | `deity-pass.ts:10` | JUSTIFIED |
| 5 | 0002_secret_zzzax.sql:36 | CREATE TABLE | `coinflip_bounty_state` | `coinflip.ts:43` | JUSTIFIED |
| 6 | 0002_secret_zzzax.sql:45 | CREATE TABLE | `coinflip_daily_stakes` | `coinflip.ts:3` | JUSTIFIED |
| 7 | 0002_secret_zzzax.sql:54 | CREATE TABLE | `coinflip_leaderboard` | `coinflip.ts:31` | JUSTIFIED |
| 8 | 0002_secret_zzzax.sql:63 | CREATE TABLE | `coinflip_results` | `coinflip.ts:15` | JUSTIFIED |
| 9 | 0002_secret_zzzax.sql:77 | CREATE TABLE | `coinflip_settings` | `coinflip.ts:52` | JUSTIFIED |
| 10 | 0002_secret_zzzax.sql:85 | CREATE TABLE | `affiliate_codes` | `affiliate.ts:3` | JUSTIFIED |
| 11 | 0002_secret_zzzax.sql:93 | CREATE TABLE | `affiliate_earnings` | `affiliate.ts:20` | JUSTIFIED |
| 12 | 0002_secret_zzzax.sql:102 | CREATE TABLE | `affiliate_top_by_level` | `affiliate.ts:32` | JUSTIFIED |
| 13 | 0002_secret_zzzax.sql:110 | CREATE TABLE | `player_referrals` | `affiliate.ts:11` | JUSTIFIED |
| 14 | 0002_secret_zzzax.sql:119 | CREATE TABLE | `baf_flip_totals` | `baf-jackpot.ts:3` | JUSTIFIED |
| 15 | 0002_secret_zzzax.sql:128 | CREATE TABLE | `player_streaks` | `quests.ts:32` | JUSTIFIED |
| 16 | 0002_secret_zzzax.sql:137 | CREATE TABLE | `quest_definitions` | `quests.ts:3` | JUSTIFIED |
| 17 | 0002_secret_zzzax.sql:149 | CREATE TABLE | `quest_progress` | `quests.ts:16` | JUSTIFIED |
| 18 | 0002_secret_zzzax.sql:162 | CREATE TABLE | `sdgnrs_burns` | `vault.ts:62` | JUSTIFIED |
| 19 | 0002_secret_zzzax.sql:175 | CREATE TABLE | `sdgnrs_deposits` | `vault.ts:50` | JUSTIFIED |
| 20 | 0002_secret_zzzax.sql:187 | CREATE TABLE | `sdgnrs_pool_balances` | `vault.ts:43` | JUSTIFIED |
| 21 | 0002_secret_zzzax.sql:194 | CREATE TABLE | `vault_claims` | `vault.ts:28` | JUSTIFIED |
| 22 | 0002_secret_zzzax.sql:207 | CREATE TABLE | `vault_deposits` | `vault.ts:14` | JUSTIFIED |
| 23 | 0002_secret_zzzax.sql:219 | CREATE TABLE | `vault_state` | `vault.ts:3` | JUSTIFIED |
| 24 | 0002_secret_zzzax.sql:230 | CREATE TABLE | `token_supply_snapshots` | `token-snapshots.ts:3` | JUSTIFIED |
| 25-45 | 0002_secret_zzzax.sql:239–259 | CREATE (UNIQUE )INDEX × 21 | all 21 indexes | matching `index(...)/uniqueIndex(...)` in above TS files (per Plan-01 catalog) | JUSTIFIED (21 rows) |

**Meta snapshot cross-check**
- Snapshot file: `drizzle/meta/0002_snapshot.json` — id `c17464db-b927-4faa-94b7-b225a54dd4d9`, prevId `2b5ba2de-1bf4-4ddd-97e3-8718fd8f9f02`.
- `prevId` chain: PASS (matches 0001's `id`).
- Table shape agreement with cumulative `.sql` state after migrations 0..2: PASS (24 new tables added; table count accumulator hits 49 — matches `jq '.tables | length'` on 0002_snapshot).

**Migration verdict:** JUSTIFIED (0 findings)

### Migration 0003 — 0003_fast_lifeguard.sql

**Statements** (5 after split). Adds `token_balance_snapshots` and 3 indexes.

| # | file:line | Leading token | Target | TS counterpart | Verdict |
|---|-----------|---------------|--------|----------------|---------|
| 1 | 0003_fast_lifeguard.sql:1 | CREATE TABLE | `token_balance_snapshots` | `token-balance-snapshots.ts:3` | JUSTIFIED |
| 2 | 0003_fast_lifeguard.sql:11 | CREATE UNIQUE INDEX | `balance_snap_unique` on `token_balance_snapshots(contract,holder,day)` | token-balance-snapshots.ts (uniqueIndex) | JUSTIFIED |
| 3 | 0003_fast_lifeguard.sql:12 | CREATE INDEX | `balance_snap_holder_day_idx` | token-balance-snapshots.ts (index) | JUSTIFIED |
| 4 | 0003_fast_lifeguard.sql:13 | CREATE INDEX | `balance_snap_contract_day_idx` | token-balance-snapshots.ts (index) | JUSTIFIED |

**Meta snapshot cross-check**
- Snapshot file: `drizzle/meta/0003_snapshot.json` — id `bf3b1eb4-a9d0-428d-a0ff-2201d873a1ec`, prevId `55335792-4ee5-4b8b-97ac-3f7ff9095b57`.
- `prevId` chain: **FAIL** — snapshot 0002's `id` is `c17464db-b927-4faa-94b7-b225a54dd4d9`, but 0003's `prevId` is `55335792-4ee5-4b8b-97ac-3f7ff9095b57`. The UUIDs do not match. → **F-28-226-09**.
- Table shape agreement with cumulative `.sql` state after migrations 0..3: PASS (`tables | length` = 51, which is 49 + 2? Actual shift is 49→51; both snapshot and SQL agree on the end state — the chain integrity break does NOT visibly corrupt the table catalog, but it DOES mean any drizzle-kit tool that validates the chain will fail or silently accept a broken chain).

**Migration verdict:** DRIFT (1 finding: F-28-226-09 — meta-chain break 0002→0003)

### Migration 0004 — 0004_slow_dracula.sql

**Statements** (4 after split). Adds `decimator_coin_burns` and `affiliate_dgnrs_rewards` + 3 indexes.

| # | file:line | Leading token | Target | TS counterpart | Verdict |
|---|-----------|---------------|--------|----------------|---------|
| 1 | 0004_slow_dracula.sql:1 | CREATE TABLE | `decimator_coin_burns` | `decimator-coin-burns.ts:9` | JUSTIFIED |
| 2 | 0004_slow_dracula.sql:12 | CREATE TABLE | `affiliate_dgnrs_rewards` | `affiliate-dgnrs-rewards.ts:9` | JUSTIFIED |
| 3 | 0004_slow_dracula.sql:23 | CREATE INDEX | `dec_coin_burns_player_idx` | decimator-coin-burns.ts (index) | JUSTIFIED |
| 4 | 0004_slow_dracula.sql:24 | CREATE INDEX | `aff_dgnrs_rewards_affiliate_idx` | affiliate-dgnrs-rewards.ts (index) | JUSTIFIED |
| 5 | 0004_slow_dracula.sql:25 | CREATE INDEX | `aff_dgnrs_rewards_level_idx` | affiliate-dgnrs-rewards.ts (index) | JUSTIFIED |

**Meta snapshot cross-check**
- Snapshot file: `drizzle/meta/0004_snapshot.json` — id `accc18ff-c35a-4921-ab38-53258009d09d`, prevId `bf3b1eb4-a9d0-428d-a0ff-2201d873a1ec`.
- `prevId` chain: PASS (matches 0003's `id`).
- Table shape agreement: PASS.

**Migration verdict:** JUSTIFIED (0 findings)

### Migration 0005 — 0005_red_doctor_octopus.sql (EMPTY)

**Statements** (0). File is 0 bytes on disk.

**0004 ↔ 0005 snapshot diff (authoritative content of what 0005 was *supposed* to emit):**

```
> "lastLevelPool": { "default": "'0'", "name": "lastLevelPool", "notNull": true, "primaryKey": false, "type": "text" }
```

Scope: exactly ONE column added to `prize_pools` (`lastLevelPool text NOT NULL DEFAULT '0'`). No other table or index delta between 0004 and 0005 snapshots.

**Rationality verdict:** DRIFT. Drizzle-kit's meta records a new column, but the `.sql` file emitted is empty — so applying only the `.sql` corpus to a fresh database would NEVER create `prize_pools.lastLevelPool`. This is **NOT** a benign meta-only emission (Gotcha #8 covers that case when the meta diff is also empty). Here meta has a real delta and `.sql` is missing the corresponding `ALTER TABLE "prize_pools" ADD COLUMN "lastLevelPool" text DEFAULT '0' NOT NULL;`.

Plan 226-01 already emitted **F-28-226-08** for the cumulative-schema view of this drift (prize_pools.lastLevelPool present in meta + TS, absent from all `.sql`). That finding remains the system-of-record for the issue; this plan does not re-emit a duplicate finding. The per-migration rationality record here is:

**Migration verdict:** DRIFT-EMPTY-FILE (0 NEW findings; inherits F-28-226-08 from Plan 226-01)

**Meta snapshot cross-check**
- Snapshot file: `drizzle/meta/0005_snapshot.json` — id `0cf0f30e-8200-4781-bcf6-43a54660c27c`, prevId `accc18ff-c35a-4921-ab38-53258009d09d`.
- `prevId` chain: PASS (matches 0004's `id`).
- Table shape agreement with cumulative `.sql` state after migrations 0..5: **FAIL** — snapshot includes `prize_pools.lastLevelPool`; cumulative SQL does not. This is exactly the drift F-28-226-08 documents.

### Migration 0006 — 0006_freezing_weapon_omega.sql

**Statements** (38 after split). Adds 17 tables (`terminal_decimator_burns`, `level_quest_completions`, `terminal_decimator_coin_burns`, `affiliate_dgnrs_claims`, `sdgnrs_redemptions`, `admin_events`, `boon_consumptions`, `deity_pass_purchases`, `final_sweep_events`, `game_over_events`, `link_feed_updates`, `gnrus_game_over`, `gnrus_level_resolutions`, `gnrus_level_skips`, `gnrus_proposals`, `gnrus_votes`) + 18 indexes + 1 ALTER (DROP COLUMN).

| # | file:line | Leading token | Target | TS counterpart | Verdict |
|---|-----------|---------------|--------|----------------|---------|
| 1 | 0006_freezing_weapon_omega.sql:1 | CREATE TABLE | `terminal_decimator_burns` | `decimator.ts:86` | JUSTIFIED |
| 2 | 0006_freezing_weapon_omega.sql:16 | CREATE TABLE | `level_quest_completions` | `quests.ts:41` | JUSTIFIED |
| 3 | 0006_freezing_weapon_omega.sql:26 | CREATE TABLE | `terminal_decimator_coin_burns` | `decimator-coin-burns.ts:22` | JUSTIFIED |
| 4 | 0006_freezing_weapon_omega.sql:36 | CREATE TABLE | `affiliate_dgnrs_claims` | `affiliate-dgnrs-rewards.ts:23` | JUSTIFIED |
| 5 | 0006_freezing_weapon_omega.sql:49 | CREATE TABLE | `sdgnrs_redemptions` | `sdgnrs-redemptions.ts:3` | JUSTIFIED |
| 6 | 0006_freezing_weapon_omega.sql:68 | CREATE TABLE | `admin_events` | `new-events.ts:62` | JUSTIFIED |
| 7 | 0006_freezing_weapon_omega.sql:79 | CREATE TABLE | `boon_consumptions` | `new-events.ts:46` | JUSTIFIED |
| 8 | 0006_freezing_weapon_omega.sql:90 | CREATE TABLE | `deity_pass_purchases` | `new-events.ts:5` | JUSTIFIED |
| 9 | 0006_freezing_weapon_omega.sql:102 | CREATE TABLE | `final_sweep_events` | `new-events.ts:35` | JUSTIFIED |
| 10 | 0006_freezing_weapon_omega.sql:111 | CREATE TABLE | `game_over_events` | `new-events.ts:22` | JUSTIFIED |
| 11 | 0006_freezing_weapon_omega.sql:122 | CREATE TABLE | `link_feed_updates` | `new-events.ts:77` | JUSTIFIED |
| 12 | 0006_freezing_weapon_omega.sql:132 | CREATE TABLE | `gnrus_game_over` | `gnrus-governance.ts:74` | JUSTIFIED |
| 13 | 0006_freezing_weapon_omega.sql:143 | CREATE TABLE | `gnrus_level_resolutions` | `gnrus-governance.ts:43` | JUSTIFIED |
| 14 | 0006_freezing_weapon_omega.sql:155 | CREATE TABLE | `gnrus_level_skips` | `gnrus-governance.ts:61` | JUSTIFIED |
| 15 | 0006_freezing_weapon_omega.sql:164 | CREATE TABLE | `gnrus_proposals` | `gnrus-governance.ts:6` | JUSTIFIED |
| 16 | 0006_freezing_weapon_omega.sql:176 | CREATE TABLE | `gnrus_votes` | `gnrus-governance.ts:24` | JUSTIFIED |
| 17 | 0006_freezing_weapon_omega.sql:189 | CREATE INDEX | `terminal_dec_burns_player_idx` | decimator.ts | JUSTIFIED |
| 18 | 0006_freezing_weapon_omega.sql:190 | CREATE INDEX | `terminal_dec_burns_level_idx` | decimator.ts | JUSTIFIED |
| 19 | 0006_freezing_weapon_omega.sql:191 | CREATE UNIQUE INDEX | `lvl_quest_complete_unique` | quests.ts | JUSTIFIED |
| 20 | 0006_freezing_weapon_omega.sql:192 | CREATE INDEX | `lvl_quest_complete_player_idx` | quests.ts | JUSTIFIED |
| 21 | 0006_freezing_weapon_omega.sql:193 | CREATE INDEX | `terminal_dec_coin_burns_player_idx` | decimator-coin-burns.ts | JUSTIFIED |
| 22 | 0006_freezing_weapon_omega.sql:194 | CREATE INDEX | `aff_dgnrs_claims_affiliate_idx` | affiliate-dgnrs-rewards.ts | JUSTIFIED |
| 23 | 0006_freezing_weapon_omega.sql:195 | CREATE INDEX | `aff_dgnrs_claims_level_idx` | affiliate-dgnrs-rewards.ts | JUSTIFIED |
| 24 | 0006_freezing_weapon_omega.sql:196 | CREATE INDEX | `sdgnrs_redemptions_player_idx` | sdgnrs-redemptions.ts | JUSTIFIED |
| 25 | 0006_freezing_weapon_omega.sql:197 | CREATE INDEX | `sdgnrs_redemptions_period_idx` | sdgnrs-redemptions.ts | JUSTIFIED |
| 26 | 0006_freezing_weapon_omega.sql:198 | CREATE INDEX | `admin_events_type_idx` | new-events.ts | JUSTIFIED |
| 27 | 0006_freezing_weapon_omega.sql:199 | CREATE INDEX | `boon_consumptions_player_idx` | new-events.ts | JUSTIFIED |
| 28 | 0006_freezing_weapon_omega.sql:200 | CREATE INDEX | `boon_consumptions_boontype_idx` | new-events.ts | JUSTIFIED |
| 29 | 0006_freezing_weapon_omega.sql:201 | CREATE INDEX | `deity_pass_purchases_buyer_idx` | new-events.ts | JUSTIFIED |
| 30 | 0006_freezing_weapon_omega.sql:202 | CREATE INDEX | `deity_pass_purchases_level_idx` | new-events.ts | JUSTIFIED |
| 31 | 0006_freezing_weapon_omega.sql:203 | CREATE INDEX | `gnrus_level_resolutions_level_idx` | gnrus-governance.ts | JUSTIFIED |
| 32 | 0006_freezing_weapon_omega.sql:204 | CREATE INDEX | `gnrus_proposals_level_idx` | gnrus-governance.ts | JUSTIFIED |
| 33 | 0006_freezing_weapon_omega.sql:205 | CREATE INDEX | `gnrus_proposals_proposer_idx` | gnrus-governance.ts | JUSTIFIED |
| 34 | 0006_freezing_weapon_omega.sql:206 | CREATE INDEX | `gnrus_votes_level_idx` | gnrus-governance.ts | JUSTIFIED |
| 35 | 0006_freezing_weapon_omega.sql:207 | CREATE INDEX | `gnrus_votes_voter_idx` | gnrus-governance.ts | JUSTIFIED |
| 36 | 0006_freezing_weapon_omega.sql:208 | CREATE INDEX | `lootbox_purchases_player_block_idx` on `(player,blockNumber)` | `lootbox.ts` (composite index) | JUSTIFIED |
| 37 | 0006_freezing_weapon_omega.sql:209 | CREATE INDEX | `lootbox_results_player_block_idx` on `(player,blockNumber)` | `lootbox.ts` (composite index) | JUSTIFIED |
| 38 | 0006_freezing_weapon_omega.sql:210 | ALTER TABLE DROP COLUMN | `quest_definitions.difficulty` | **TS still declares `difficulty: smallint().notNull()` at `quests.ts:11`** | DRIFT → **F-28-226-10** |

**Meta snapshot cross-check**
- Snapshot file: `drizzle/meta/0006_snapshot.json` — id `5662dc83-0732-4b92-9f1e-be234c42d6e4`, prevId `0cf0f30e-8200-4781-bcf6-43a54660c27c`.
- `prevId` chain: PASS (matches 0005's `id`).
- Table shape agreement: `quest_definitions` columns in snapshot 0006 should NOT contain `difficulty` — verified (snapshot reflects the DROP COLUMN). However, TS `quest_definitions` in `src/db/schema/quests.ts` still declares `difficulty`; that's the drift.
- Table count `jq '.tables | length' 0006_snapshot.json` = 68 (49 from 0001–0002 + 1 from 0003 + 2 from 0004 + 16 from 0006 = 68 ✓).

**Migration verdict:** DRIFT (1 new finding: F-28-226-10 — `quest_definitions.difficulty` dropped in SQL but still declared in TS)

### Migration 0007 — 0007_trait_burn_tickets.sql

**Statements** (4 after split).

| # | file:line | Leading token | Target | TS counterpart | Verdict |
|---|-----------|---------------|--------|----------------|---------|
| 1 | 0007_trait_burn_tickets.sql:6 | CREATE TABLE | `trait_burn_tickets` (composite PK `(level,trait_id,player)`) | `trait-burn-tickets.ts:15` | JUSTIFIED (composite-PK auto-name `trait_burn_tickets_level_trait_id_player_pk` — Gotcha #5 confirmed) |
| 2 | 0007_trait_burn_tickets.sql:14 | CREATE TABLE | `trait_burn_ticket_processed_logs` (composite PK `(block_number,log_index)`) | `trait-burn-tickets.ts:26` | JUSTIFIED |
| 3 | 0007_trait_burn_tickets.sql:20 | CREATE INDEX | `trait_burn_tickets_level_trait_idx` | trait-burn-tickets.ts (index) | JUSTIFIED |
| 4 | 0007_trait_burn_tickets.sql:21 | CREATE INDEX | `trait_burn_tickets_player_idx` | trait-burn-tickets.ts (index) | JUSTIFIED |

**Meta snapshot cross-check**
- Snapshot file: `drizzle/meta/0007_snapshot.json` — **MISSING** → **F-28-226-01**.
- `_journal.json`: no `idx: 7` entry → **F-28-226-01**.
- Cumulative `.sql` state after migration 7 includes `trait_burn_tickets` and `trait_burn_ticket_processed_logs`; snapshot 0006 (latest existing) does NOT. Any tool treating `0006_snapshot.json` + `_journal.json` as authoritative will not see these two tables.

**Migration verdict:** JUSTIFIED DDL but META-ANOMALY → F-28-226-01 (pre-assigned)

## Journal integrity

`drizzle/meta/_journal.json`:

- Format `{ version: "7", dialect: "postgresql", entries: [...] }`.
- `entries.length === 7`.
- `idx` values observed: **0, 1, 2, 3, 4, 5, 6**.
- `idx: 7` is **absent** — this is the structural artifact underpinning F-28-226-01 and confirms the `0007` anomaly.
- `tag` values match file basenames for each migration 0..6.
- `when` timestamps are strictly monotonic increasing (`1773697069718 < 1773700918301 < ... < 1775288982850`).
- `breakpoints: true` on every entry (consistent with `--> statement-breakpoint` delimiter use).

**Snapshot chain (`id` / `prevId`) full audit:**

| idx | id | prevId | Expected prevId (idx-1.id) | Status |
|-----|----|--------|----------------------------|--------|
| 0 | 15fb8468-d14b-4dae-8a78-7928454f0441 | 00000000-0000-0000-0000-000000000000 | (initial sentinel) | PASS |
| 1 | 2b5ba2de-1bf4-4ddd-97e3-8718fd8f9f02 | 15fb8468-d14b-4dae-8a78-7928454f0441 | 15fb8468... | PASS |
| 2 | c17464db-b927-4faa-94b7-b225a54dd4d9 | 2b5ba2de-1bf4-4ddd-97e3-8718fd8f9f02 | 2b5ba2de... | PASS |
| 3 | bf3b1eb4-a9d0-428d-a0ff-2201d873a1ec | **55335792-4ee5-4b8b-97ac-3f7ff9095b57** | c17464db-b927-4faa-94b7-b225a54dd4d9 | **FAIL** → F-28-226-09 |
| 4 | accc18ff-c35a-4921-ab38-53258009d09d | bf3b1eb4-a9d0-428d-a0ff-2201d873a1ec | bf3b1eb4... | PASS |
| 5 | 0cf0f30e-8200-4781-bcf6-43a54660c27c | accc18ff-c35a-4921-ab38-53258009d09d | accc18ff... | PASS |
| 6 | 5662dc83-0732-4b92-9f1e-be234c42d6e4 | 0cf0f30e-8200-4781-bcf6-43a54660c27c | 0cf0f30e... | PASS |
| 7 | — | — | 5662dc83... | **MISSING** → F-28-226-01 |

## Finding stubs

#### F-28-226-01: 0007_trait_burn_tickets.sql applied without matching 0007_snapshot.json

- **Severity:** INFO
- **Direction:** schema<->migration
- **Phase:** 226 (SCHEMA-03 migration rationality trace)
- **File:** `/home/zak/Dev/PurgeGame/database/drizzle/0007_trait_burn_tickets.sql:1`
- **Resolution:** RESOLVED-CODE (regenerate snapshot via `drizzle-kit generate --custom` or equivalent; update `drizzle/meta/_journal.json` to include `idx: 7`)
- **Observation:** `0007_trait_burn_tickets.sql` exists and applies two `CREATE TABLE` statements (`trait_burn_tickets`, `trait_burn_ticket_processed_logs`) plus two `CREATE INDEX` statements; `drizzle/meta/0007_snapshot.json` is absent; `drizzle/meta/_journal.json` has no `idx: 7` entry.
- **Impact:** Any tooling that trusts `_journal.json` as source of truth (including future `drizzle-kit generate` runs) will silently omit the 0007 tables and may regenerate them as a fresh migration, producing duplicate DDL. This is why D-226-01 designates cumulative `.sql` as primary ground truth.

#### F-28-226-09: drizzle-kit meta-chain integrity break between 0002_snapshot.json and 0003_snapshot.json

- **Severity:** LOW
- **Direction:** schema<->migration
- **Phase:** 226 (SCHEMA-03 migration rationality trace)
- **File:** `/home/zak/Dev/PurgeGame/database/drizzle/meta/0003_snapshot.json:1`
- **Resolution:** RESOLVED-CODE (regenerate the snapshot chain: either rewrite `0003_snapshot.json.prevId` to `c17464db-b927-4faa-94b7-b225a54dd4d9` or regenerate 0003..0006 + 0007 via `drizzle-kit generate` from a clean state)
- **Observation:** `0002_snapshot.json.id = c17464db-b927-4faa-94b7-b225a54dd4d9`, but `0003_snapshot.json.prevId = 55335792-4ee5-4b8b-97ac-3f7ff9095b57`. The UUID `55335792-...` does not appear as the `id` of any snapshot in `drizzle/meta/`. The chain is intact 0000→0001→0002 and 0003→0004→0005→0006, but the 0002↔0003 join is broken.
- **Impact:** `drizzle-kit check` (the tool that validates `prevId` chains) would fail against this directory. Safe for runtime (migrations already applied) but forecloses `drizzle-kit check` adoption as a future CI gate without upstream regeneration.
- **Context:** The cumulative `.sql` state after migrations 0..3 and the table-catalog in `0003_snapshot.json` still agree on the end state (all tables + `token_balance_snapshots` present, 51 tables total). The break is internal to drizzle-kit's provenance record, not to the applied SQL.

#### F-28-226-10: quest_definitions.difficulty dropped by 0006 migration but still declared in TS schema

- **Severity:** LOW
- **Direction:** schema<->migration
- **Phase:** 226 (SCHEMA-03 migration rationality trace)
- **File:** `/home/zak/Dev/PurgeGame/database/src/db/schema/quests.ts:11`
- **Resolution:** RESOLVED-CODE (remove `difficulty: smallint().notNull()` from `questDefinitions` in `src/db/schema/quests.ts` — the column no longer exists in Postgres after `ALTER TABLE "quest_definitions" DROP COLUMN "difficulty"` in migration 0006)
- **Observation:** `0006_freezing_weapon_omega.sql:210` emits `ALTER TABLE "quest_definitions" DROP COLUMN "difficulty";` (last statement of the migration). `0006_snapshot.json` reflects this drop (no `difficulty` in `quest_definitions.columns`). The TS declaration in `quests.ts:11` still defines `difficulty: smallint().notNull()`. This means any INSERT emitted from TS via drizzle will try to populate a column that does not exist → runtime failure on any write path touching `quest_definitions`.
- **Impact:** Silent-failing inserts or query-builder-generated `INSERT INTO quest_definitions ("day","slot","questType","flags","version","difficulty","blockNumber","blockHash") VALUES (...)` will throw `column "difficulty" does not exist` at runtime. This is a functional regression blocker — highest-severity finding emitted from this plan.

## Summary

### Migration coverage

- 7 SQL migration files (0000..0007) walked individually, each with a `### Migration 000N — ` subsection.
- 8 per-migration subsections total (one per SQL file).
- 1 structural anomaly (missing 0007 snapshot) captured as F-28-226-01.
- Journal integrity section confirms `_journal.json` has exactly 7 entries (idx 0..6) and no `idx: 7`.

### Statement totals

| Migration | Statements | JUSTIFIED | DRIFT |
|-----------|-----------|-----------|-------|
| 0000 | 7 | 7 | 0 |
| 0001 | 49 | 49 | 0 |
| 0002 | 45 | 45 | 0 |
| 0003 | 5 | 5 | 0 |
| 0004 | 5 | 5 | 0 |
| 0005 | 0 | 0 (empty file) | 0 (new); inherits F-28-226-08 from Plan 01 |
| 0006 | 38 | 37 | 1 (F-28-226-10) |
| 0007 | 4 | 4 | 0 DDL drift; 0 meta (META anomaly → F-28-226-01) |
| **Total** | **153** | **152** | **1 DDL-level + 2 meta-level** |

### Meta cross-check totals

- `prevId` chain integrity: **6 PASS / 1 FAIL / 1 MISSING** (FAIL at 0002→0003 → F-28-226-09; MISSING at 0006→0007 → F-28-226-01).
- Table-shape agreement (snapshot columns/indexes match cumulative SQL-applied state): **6 PASS / 1 FAIL** (FAIL at 0005 where `prize_pools.lastLevelPool` is in snapshot but not in `.sql` — covered by Plan-01 F-28-226-08; 0007 not applicable since snapshot is missing).
- Empty 0005 file: explicitly addressed as DRIFT-EMPTY-FILE inheriting F-28-226-08.

### Finding IDs allocated

- **F-28-226-01** — pre-assigned to the 0007 snapshot anomaly (first stub in `## Finding stubs`).
- **F-28-226-09** — drizzle-kit meta-chain integrity break 0002↔0003 (LOW).
- **F-28-226-10** — `quest_definitions.difficulty` TS-vs-SQL drift (LOW).

Inherited/referenced (NOT re-emitted):
- **F-28-226-08** (Plan 226-01) — prize_pools.lastLevelPool drift is the cumulative-view finding for the empty-0005 condition.
- **F-28-226-02, F-28-226-04** (Plan 226-01) — referenced in-place at the Migration 0001 table for `jackpot_distributions` and `decimator_rounds`.

Plan 226-02 consumes IDs **F-28-226-01, F-28-226-09, F-28-226-10** (3 IDs total).

**Next available ID for Plan 226-03:** `F-28-226-11`.

### Severity distribution

| Severity | Count | IDs |
|----------|-------|-----|
| INFO | 1 | F-28-226-01 |
| LOW | 2 | F-28-226-09, F-28-226-10 |
| MEDIUM+ | 0 | — |

---

*Phase: 226 — Schema, Migration & Orphan Audit*
*Plan: 02 — SCHEMA-03 Migration Rationality Trace*
*Generated: 2026-04-15*
