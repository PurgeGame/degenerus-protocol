# Phase 226 Plan 04 — SCHEMA-04 Orphan Table + Code-Reference Scan

## Preamble

- **Phase:** 226 — Schema, Migration & Orphan Audit
- **Plan:** 04
- **Requirement:** SCHEMA-04 — bidirectional orphan + code-reference scan across the Drizzle schema and the five consumer surfaces.
- **Decisions honored:**
  - **D-226-03** — orphan scan is bidirectional and covers handlers, indexer, routes, `views.ts`, and `indexes.ts`.
  - **D-226-05** — orphan-class findings default to direction `code<->schema`.
  - **D-226-07** — `views.ts` materialized views are in scope (treated as tables for orphan purposes); view-refresh semantics deferred to Phase 228 / SCHEMA-05.
  - **D-226-08** — cross-repo READ-only on `/home/zak/Dev/PurgeGame/database/`; zero writes to the database repo.
  - **D-226-09** / **D-226-10** — fresh finding-ID counter; catalog-only, no runtime gate.
- **Finding-ID block reserved for Plan 226-04:** `F-28-226-301..` (disjoint from 226-01/02/03 under wave-2 parallelism).
- **Scan date:** 2026-04-15.

## Scope surfaces

The five code surfaces scanned (from `<interfaces>` / D-226-03):

1. `/home/zak/Dev/PurgeGame/database/src/handlers/*.ts` — 27 indexer event-handler files (handler bodies and co-located test files under `__tests__/` are ignored for orphan-scan counting; only production source is authoritative, but tests are noted where they are the sole consumer).
2. `/home/zak/Dev/PurgeGame/database/src/indexer/*.ts` — indexer core (9 files: `block-fetcher.ts`, `cursor-manager.ts`, `event-processor.ts`, `index.ts`, `main.ts`, `purge-block-range.ts`, `reorg-detector.ts`, `trait-derivation.ts`, `view-refresh.ts`).
3. `/home/zak/Dev/PurgeGame/database/src/api/routes/*.ts` — 8 route files (`game.ts`, `health.ts`, `history.ts`, `leaderboards.ts`, `player.ts`, `replay.ts`, `tokens.ts`, `viewer.ts`).
4. `/home/zak/Dev/PurgeGame/database/src/db/schema/views.ts` — raw-SQL `sql\`...\`` template strings reference tables by PG name (legitimate usage per trap #2).
5. `/home/zak/Dev/PurgeGame/database/src/db/schema/indexes.ts` — `ADDITIONAL_INDEXES` raw-SQL strings reference tables by PG name (legitimate usage per trap #1).

Out of scope: `src/cli/**`, `src/api/plugins/**`, and all `__tests__/**` directories are NOT part of the five scoped surfaces and are not counted here. They are cross-checked where a binding has suspiciously few in-scope hits, but are never the sole source of a "referenced" verdict for orphan-scan purposes.

## False-positive traps handled

The six traps from 226-RESEARCH.md §Orphan Scan — each traversed and respected:

1. **`indexes.ts` `ADDITIONAL_INDEXES` raw-SQL strings** — treated as **LEGITIMATE references**. Pattern (3) was applied to the nine PG table names appearing in `ADDITIONAL_INDEXES` (`coinflip_leaderboard`, `affiliate_earnings`, `baf_flip_totals`, `jackpot_distributions`, `level_transitions`, `degenerette_bets`, `decimator_claims`, `vault_deposits`, `vault_claims`) and each match counts toward its table's total reference count.
2. **`views.ts` raw-SQL JOINs** — treated as **LEGITIMATE references**. Pattern (3) catches `player_winnings`, `token_balances`, `player_streaks`, `affiliate_earnings`, `coinflip_leaderboard`, `baf_flip_totals` inside the four `pgMaterializedView(...).as(...)` blocks and counts each as a reference to the underlying table.
3. **Block / line comments** — filtered. The binding-use scan uses `rg -w` word-boundary; matches inside JSDoc or `//` comments were visually re-inspected and excluded when the match was the only hit (no such cases surfaced — every binding also has a non-comment hit).
4. **Barrel import without downstream use** — mitigated by counting binding USE sites (pattern 4 word-boundary) rather than import lines. A file that imports but never uses a binding produces an extra pattern-4 hit on the import line plus zero other hits; every binding in the universe cleared this bar with multiple non-import use sites.
5. **Enum / non-table exports** — excluded from the universe. `gamePhaseEnum` (from `game-state.ts`), `ALL_VIEWS`, `VIEW_UNIQUE_INDEXES` (from `views.ts`), and `ADDITIONAL_INDEXES` (from `indexes.ts`) are re-exported through `index.ts` but are NOT `pgTable`/`pgMaterializedView` declarations and are omitted.
6. **`indexes.ts` is a legitimate orphan-scan source** — per D-226-03, its raw-SQL references DO count as code usage of the target table names, even though `indexes.ts` is not listed in `drizzle.config.ts`. This scan honors that. The `drizzle.config.ts`-omission itself is a 226-01/226-02 concern, not an orphan-scan finding.

## Table universe

Derived from `src/db/schema/index.ts` re-exports (filtered to `pgTable` + `pgMaterializedView` only). 69 tables + 4 materialized views = **73 entries**.

| # | jsBinding | pgName | source file:line | kind |
|---|-----------|--------|------------------|------|
| 1 | rawEvents | raw_events | src/db/schema/raw-events.ts:3 | table |
| 2 | blocks | blocks | src/db/schema/blocks.ts:3 | table |
| 3 | indexerCursor | indexer_cursor | src/db/schema/cursor.ts:4 | table |
| 4 | gameState | game_state | src/db/schema/game-state.ts:5 | table |
| 5 | prizePools | prize_pools | src/db/schema/prize-pools.ts:3 | table |
| 6 | playerWinnings | player_winnings | src/db/schema/player-state.ts:3 | table |
| 7 | playerSettings | player_settings | src/db/schema/player-state.ts:12 | table |
| 8 | playerWhalePasses | player_whale_passes | src/db/schema/player-state.ts:22 | table |
| 9 | playerTickets | player_tickets | src/db/schema/tickets.ts:3 | table |
| 10 | lootboxPurchases | lootbox_purchases | src/db/schema/lootbox.ts:3 | table |
| 11 | lootboxResults | lootbox_results | src/db/schema/lootbox.ts:21 | table |
| 12 | traitsGenerated | traits_generated | src/db/schema/lootbox.ts:36 | table |
| 13 | jackpotDistributions | jackpot_distributions | src/db/schema/jackpot-history.ts:3 | table |
| 14 | levelTransitions | level_transitions | src/db/schema/jackpot-history.ts:26 | table |
| 15 | decimatorBurns | decimator_burns | src/db/schema/decimator.ts:3 | table |
| 16 | decimatorBucketTotals | decimator_bucket_totals | src/db/schema/decimator.ts:18 | table |
| 17 | decimatorWinningSubbuckets | decimator_winning_subbuckets | src/db/schema/decimator.ts:30 | table |
| 18 | decimatorRounds | decimator_rounds | src/db/schema/decimator.ts:41 | table |
| 19 | decimatorClaims | decimator_claims | src/db/schema/decimator.ts:55 | table |
| 20 | playerBoosts | player_boosts | src/db/schema/decimator.ts:71 | table |
| 21 | terminalDecimatorBurns | terminal_decimator_burns | src/db/schema/decimator.ts:86 | table |
| 22 | degeneretteBets | degenerette_bets | src/db/schema/degenerette.ts:3 | table |
| 23 | degeneretteResults | degenerette_results | src/db/schema/degenerette.ts:18 | table |
| 24 | dailyRng | daily_rng | src/db/schema/daily-rng.ts:3 | table |
| 25 | lootboxRng | lootbox_rng | src/db/schema/daily-rng.ts:17 | table |
| 26 | deityBoons | deity_boons | src/db/schema/deity-boons.ts:3 | table |
| 27 | tokenBalances | token_balances | src/db/schema/token-balances.ts:3 | table |
| 28 | tokenSupply | token_supply | src/db/schema/token-balances.ts:16 | table |
| 29 | deityPassOwnership | deity_pass_ownership | src/db/schema/deity-pass.ts:3 | table |
| 30 | deityPassTransfers | deity_pass_transfers | src/db/schema/deity-pass.ts:10 | table |
| 31 | coinflipDailyStakes | coinflip_daily_stakes | src/db/schema/coinflip.ts:3 | table |
| 32 | coinflipResults | coinflip_results | src/db/schema/coinflip.ts:15 | table |
| 33 | coinflipLeaderboard | coinflip_leaderboard | src/db/schema/coinflip.ts:31 | table |
| 34 | coinflipBountyState | coinflip_bounty_state | src/db/schema/coinflip.ts:43 | table |
| 35 | coinflipSettings | coinflip_settings | src/db/schema/coinflip.ts:52 | table |
| 36 | affiliateCodes | affiliate_codes | src/db/schema/affiliate.ts:3 | table |
| 37 | playerReferrals | player_referrals | src/db/schema/affiliate.ts:11 | table |
| 38 | affiliateEarnings | affiliate_earnings | src/db/schema/affiliate.ts:20 | table |
| 39 | affiliateTopByLevel | affiliate_top_by_level | src/db/schema/affiliate.ts:32 | table |
| 40 | bafFlipTotals | baf_flip_totals | src/db/schema/baf-jackpot.ts:3 | table |
| 41 | questDefinitions | quest_definitions | src/db/schema/quests.ts:3 | table |
| 42 | questProgress | quest_progress | src/db/schema/quests.ts:16 | table |
| 43 | playerStreaks | player_streaks | src/db/schema/quests.ts:32 | table |
| 44 | levelQuestCompletions | level_quest_completions | src/db/schema/quests.ts:41 | table |
| 45 | vaultState | vault_state | src/db/schema/vault.ts:3 | table |
| 46 | vaultDeposits | vault_deposits | src/db/schema/vault.ts:14 | table |
| 47 | vaultClaims | vault_claims | src/db/schema/vault.ts:28 | table |
| 48 | sdgnrsPoolBalances | sdgnrs_pool_balances | src/db/schema/vault.ts:43 | table |
| 49 | sdgnrsDeposits | sdgnrs_deposits | src/db/schema/vault.ts:50 | table |
| 50 | sdgnrsBurns | sdgnrs_burns | src/db/schema/vault.ts:62 | table |
| 51 | tokenSupplySnapshots | token_supply_snapshots | src/db/schema/token-snapshots.ts:3 | table |
| 52 | tokenBalanceSnapshots | token_balance_snapshots | src/db/schema/token-balance-snapshots.ts:3 | table |
| 53 | decimatorCoinBurns | decimator_coin_burns | src/db/schema/decimator-coin-burns.ts:9 | table |
| 54 | terminalDecimatorCoinBurns | terminal_decimator_coin_burns | src/db/schema/decimator-coin-burns.ts:22 | table |
| 55 | affiliateDgnrsRewards | affiliate_dgnrs_rewards | src/db/schema/affiliate-dgnrs-rewards.ts:9 | table |
| 56 | affiliateDgnrsClaims | affiliate_dgnrs_claims | src/db/schema/affiliate-dgnrs-rewards.ts:23 | table |
| 57 | sdgnrsRedemptions | sdgnrs_redemptions | src/db/schema/sdgnrs-redemptions.ts:3 | table |
| 58 | deityPassPurchases | deity_pass_purchases | src/db/schema/new-events.ts:5 | table |
| 59 | gameOverEvents | game_over_events | src/db/schema/new-events.ts:22 | table |
| 60 | finalSweepEvents | final_sweep_events | src/db/schema/new-events.ts:35 | table |
| 61 | boonConsumptions | boon_consumptions | src/db/schema/new-events.ts:46 | table |
| 62 | adminEvents | admin_events | src/db/schema/new-events.ts:62 | table |
| 63 | linkFeedUpdates | link_feed_updates | src/db/schema/new-events.ts:77 | table |
| 64 | dailyWinningTraits | daily_winning_traits | src/db/schema/new-events.ts:89 | table |
| 65 | gnrusProposals | gnrus_proposals | src/db/schema/gnrus-governance.ts:6 | table |
| 66 | gnrusVotes | gnrus_votes | src/db/schema/gnrus-governance.ts:24 | table |
| 67 | gnrusLevelResolutions | gnrus_level_resolutions | src/db/schema/gnrus-governance.ts:43 | table |
| 68 | gnrusLevelSkips | gnrus_level_skips | src/db/schema/gnrus-governance.ts:61 | table |
| 69 | gnrusGameOver | gnrus_game_over | src/db/schema/gnrus-governance.ts:74 | table |
| 70 | traitBurnTickets | trait_burn_tickets | src/db/schema/trait-burn-tickets.ts:15 | table |
| 71 | traitBurnTicketProcessedLogs | trait_burn_ticket_processed_logs | src/db/schema/trait-burn-tickets.ts:26 | table |
| 72 | playerSummary | mv_player_summary | src/db/schema/views.ts:16 | view |
| 73 | coinflipTop10 | mv_coinflip_top10 | src/db/schema/views.ts:45 | view |
| 74 | affiliateLeaderboard | mv_affiliate_leaderboard | src/db/schema/views.ts:61 | view |
| 75 | bafTop4 | mv_baf_top4 | src/db/schema/views.ts:77 | view |

Note: Rows 1–71 are 71 `pgTable` entries and rows 72–75 are 4 `pgMaterializedView` entries. The `pgTable` grep reports 71 `= pgTable(` hits; `index.ts` re-exports 69 of them — the two not re-exported through the barrel are `gnrusLevelResolutions` and `gnrusLevelSkips` (**correction:** a re-inspection shows all 71 `pgTable` exports ARE re-exported via `index.ts` lines 29 (`gnrus-governance.ts`) and 30 (`trait-burn-tickets.ts`)). Final universe size = **75 entries (71 tables + 4 views)**.

## Schema → code references

Counts below are from pattern (4) word-boundary searches (`rg -nw <binding>`) across the 5 scoped surfaces only (handlers + indexer + routes + `views.ts` + `indexes.ts`). Pattern (3) raw-SQL PG-name matches in `views.ts` and `indexes.ts` are added into the `pattern(3)` column for the tables those raw-SQL strings reference. Values exclude `__tests__/`, `cli/`, and `api/plugins/`.

| # | jsBinding / pgName | p4 hits (files) | p4 hits (total) | p3 hits (raw SQL) | total refs | referring files (sample) | Orphan? |
|---|--------------------|-----------------|-----------------|--------------------|------------|---------------------------|---------|
| 1 | rawEvents / raw_events | 7 | 15 | 0 | 15 | src/indexer/event-processor.ts, src/indexer/purge-block-range.ts | NO |
| 2 | blocks / blocks | 16 | 60 | 0 | 60 | src/handlers/coinflip.ts, src/handlers/game-fsm.ts, src/indexer/reorg-detector.ts | NO |
| 3 | indexerCursor / indexer_cursor | 4 | 13 | 0 | 13 | src/indexer/cursor-manager.ts, src/indexer/reorg-detector.ts | NO |
| 4 | gameState / game_state | 10 | 35 | 0 | 35 | src/handlers/game-fsm.ts, src/handlers/decimator.ts, src/api/routes/game.ts | NO |
| 5 | prizePools / prize_pools | 10 | 55 | 0 | 55 | src/handlers/prize-pool.ts, src/handlers/new-events.ts, src/api/routes/game.ts | NO |
| 6 | playerWinnings / player_winnings | 5 | 20 | 1 (views.ts) | 21 | src/handlers/winnings.ts, src/handlers/new-events.ts, src/db/schema/views.ts | NO |
| 7 | playerSettings / player_settings | 4 | 25 | 0 | 25 | src/handlers/player-settings.ts | NO |
| 8 | playerWhalePasses / player_whale_passes | 4 | 9 | 0 | 9 | src/handlers/whale-pass.ts | NO |
| 9 | playerTickets / player_tickets | 7 | 38 | 0 | 38 | src/handlers/tickets.ts, src/api/routes/viewer.ts, src/api/routes/replay.ts | NO |
| 10 | lootboxPurchases / lootbox_purchases | 5 | 25 | 0 | 25 | src/handlers/lootbox.ts, src/api/routes/viewer.ts | NO |
| 11 | lootboxResults / lootbox_results | 5 | 30 | 0 | 30 | src/handlers/lootbox.ts, src/api/routes/viewer.ts | NO |
| 12 | traitsGenerated / traits_generated | 5 | 11 | 0 | 11 | src/handlers/lootbox.ts, src/api/routes/replay.ts | NO |
| 13 | jackpotDistributions / jackpot_distributions | 8 | 66 | 1 (indexes.ts) | 67 | src/handlers/jackpot.ts, src/api/routes/game.ts, src/db/schema/indexes.ts | NO |
| 14 | levelTransitions / level_transitions | 7 | 44 | 1 (indexes.ts) | 45 | src/handlers/game-fsm.ts, src/api/routes/viewer.ts, src/db/schema/indexes.ts | NO |
| 15 | decimatorBurns / decimator_burns | 5 | 15 | 0 | 15 | src/handlers/decimator.ts, src/api/routes/player.ts | NO |
| 16 | decimatorBucketTotals / decimator_bucket_totals | 4 | 11 | 0 | 11 | src/handlers/decimator.ts | NO |
| 17 | decimatorWinningSubbuckets / decimator_winning_subbuckets | 3 | 11 | 0 | 11 | src/handlers/decimator.ts | NO |
| 18 | decimatorRounds / decimator_rounds | 3 | 16 | 0 | 16 | src/handlers/decimator.ts | NO |
| 19 | decimatorClaims / decimator_claims | 5 | 22 | 1 (indexes.ts) | 23 | src/handlers/decimator.ts, src/api/routes/player.ts, src/db/schema/indexes.ts | NO |
| 20 | playerBoosts / player_boosts | 4 | 12 | 0 | 12 | src/handlers/decimator.ts | NO |
| 21 | terminalDecimatorBurns / terminal_decimator_burns | 4 | 12 | 0 | 12 | src/handlers/decimator.ts, src/api/routes/player.ts | NO |
| 22 | degeneretteBets / degenerette_bets | 7 | 30 | 1 (indexes.ts) | 31 | src/handlers/degenerette.ts, src/api/routes/viewer.ts, src/db/schema/indexes.ts | NO |
| 23 | degeneretteResults / degenerette_results | 6 | 24 | 0 | 24 | src/handlers/degenerette.ts, src/api/routes/viewer.ts | NO |
| 24 | dailyRng / daily_rng | 11 | 69 | 0 | 69 | src/handlers/daily-rng.ts, src/api/routes/game.ts, src/api/routes/viewer.ts | NO |
| 25 | lootboxRng / lootbox_rng | 4 | 8 | 0 | 8 | src/handlers/daily-rng.ts | NO |
| 26 | deityBoons / deity_boons | 4 | 9 | 0 | 9 | src/handlers/deity-boons.ts | NO |
| 27 | tokenBalances / token_balances | 5 | 23 | 4 (views.ts + indexer/view-refresh — raw SQL JOINs against token_balances) | 27 | src/handlers/token-balances.ts, src/api/routes/tokens.ts, src/db/schema/views.ts | NO |
| 28 | tokenSupply / token_supply | 4 | 20 | 0 | 20 | src/handlers/token-balances.ts, src/api/routes/tokens.ts | NO |
| 29 | deityPassOwnership / deity_pass_ownership | 3 | 8 | 0 | 8 | src/handlers/deity-pass.ts | NO |
| 30 | deityPassTransfers / deity_pass_transfers | 3 | 7 | 0 | 7 | src/handlers/deity-pass.ts | NO |
| 31 | coinflipDailyStakes / coinflip_daily_stakes | 6 | 34 | 0 | 34 | src/handlers/coinflip.ts, src/api/routes/viewer.ts, src/api/routes/player.ts | NO |
| 32 | coinflipResults / coinflip_results | 5 | 15 | 0 | 15 | src/handlers/coinflip.ts, src/api/routes/viewer.ts | NO |
| 33 | coinflipLeaderboard / coinflip_leaderboard | 4 | 9 | 2 (views.ts + indexes.ts) | 11 | src/handlers/coinflip.ts, src/db/schema/views.ts, src/db/schema/indexes.ts | NO |
| 34 | coinflipBountyState / coinflip_bounty_state | 5 | 20 | 0 | 20 | src/handlers/coinflip.ts, src/api/routes/player.ts | NO |
| 35 | coinflipSettings / coinflip_settings | 5 | 19 | 0 | 19 | src/handlers/coinflip.ts, src/api/routes/player.ts | NO |
| 36 | affiliateCodes / affiliate_codes | 5 | 13 | 0 | 13 | src/handlers/affiliate.ts, src/api/routes/player.ts | NO |
| 37 | playerReferrals / player_referrals | 5 | 15 | 0 | 15 | src/handlers/affiliate.ts, src/api/routes/player.ts | NO |
| 38 | affiliateEarnings / affiliate_earnings | 5 | 19 | 2 (views.ts + indexes.ts) | 21 | src/handlers/affiliate.ts, src/api/routes/viewer.ts, src/db/schema/indexes.ts | NO |
| 39 | affiliateTopByLevel / affiliate_top_by_level | 4 | 9 | 0 | 9 | src/handlers/affiliate.ts | NO |
| 40 | bafFlipTotals / baf_flip_totals | 4 | 12 | 2 (views.ts + indexes.ts) | 14 | src/handlers/baf-jackpot.ts, src/db/schema/views.ts, src/db/schema/indexes.ts | NO |
| 41 | questDefinitions / quest_definitions | 4 | 9 | 0 | 9 | src/handlers/quests.ts | NO |
| 42 | questProgress / quest_progress | 6 | 40 | 0 | 40 | src/handlers/quests.ts, src/api/routes/player.ts, src/api/routes/viewer.ts | NO |
| 43 | playerStreaks / player_streaks | 5 | 41 | 1 (views.ts) | 42 | src/handlers/quests.ts, src/api/routes/player.ts, src/db/schema/views.ts | NO |
| 44 | levelQuestCompletions / level_quest_completions | 3 | 8 | 0 | 8 | src/handlers/quests.ts | NO |
| 45 | vaultState / vault_state | 5 | 49 | 0 | 49 | src/handlers/vault.ts, src/api/routes/tokens.ts | NO |
| 46 | vaultDeposits / vault_deposits | 4 | 12 | 1 (indexes.ts) | 13 | src/handlers/vault.ts, src/db/schema/indexes.ts | NO |
| 47 | vaultClaims / vault_claims | 4 | 10 | 1 (indexes.ts) | 11 | src/handlers/vault.ts, src/db/schema/indexes.ts | NO |
| 48 | sdgnrsPoolBalances / sdgnrs_pool_balances | 4 | 19 | 0 | 19 | src/handlers/sdgnrs.ts | NO |
| 49 | sdgnrsDeposits / sdgnrs_deposits | 3 | 9 | 0 | 9 | src/handlers/sdgnrs.ts | NO |
| 50 | sdgnrsBurns / sdgnrs_burns | 4 | 8 | 0 | 8 | src/handlers/sdgnrs.ts | NO |
| 51 | tokenSupplySnapshots / token_supply_snapshots | 3 | 8 | 0 | 8 | src/handlers/token-balances.ts | NO |
| 52 | tokenBalanceSnapshots / token_balance_snapshots | 2 | 10 | 1 (handlers/token-balances.ts raw SQL INSERT) | 11 | src/api/routes/viewer.ts, src/indexer/purge-block-range.ts, src/handlers/token-balances.ts | NO |
| 53 | decimatorCoinBurns / decimator_coin_burns | 4 | 8 | 0 | 8 | src/handlers/decimator.ts | NO |
| 54 | terminalDecimatorCoinBurns / terminal_decimator_coin_burns | 3 | 5 | 0 | 5 | src/handlers/decimator.ts | NO |
| 55 | affiliateDgnrsRewards / affiliate_dgnrs_rewards | 4 | 8 | 0 | 8 | src/handlers/affiliate.ts | NO |
| 56 | affiliateDgnrsClaims / affiliate_dgnrs_claims | 3 | 5 | 0 | 5 | src/handlers/affiliate.ts | NO |
| 57 | sdgnrsRedemptions / sdgnrs_redemptions | 5 | 17 | 0 | 17 | src/handlers/sdgnrs.ts | NO |
| 58 | deityPassPurchases / deity_pass_purchases | 4 | 20 | 0 | 20 | src/handlers/new-events.ts, src/api/routes/viewer.ts | NO |
| 59 | gameOverEvents / game_over_events | 3 | 5 | 0 | 5 | src/handlers/new-events.ts | NO |
| 60 | finalSweepEvents / final_sweep_events | 3 | 5 | 0 | 5 | src/handlers/new-events.ts | NO |
| 61 | boonConsumptions / boon_consumptions | 3 | 5 | 0 | 5 | src/handlers/new-events.ts | NO |
| 62 | adminEvents / admin_events | 3 | 7 | 0 | 7 | src/handlers/new-events.ts | NO |
| 63 | linkFeedUpdates / link_feed_updates | 3 | 5 | 0 | 5 | src/handlers/new-events.ts | NO |
| 64 | dailyWinningTraits / daily_winning_traits | 1 | 2 | 3 (api/routes/game.ts raw SQL FROM) | 5 | src/handlers/new-events.ts:207 (insert), src/api/routes/game.ts (raw SQL reads) | NO |
| 65 | gnrusProposals / gnrus_proposals | 3 | 5 | 0 | 5 | src/handlers/gnrus-governance.ts | NO |
| 66 | gnrusVotes / gnrus_votes | 3 | 5 | 0 | 5 | src/handlers/gnrus-governance.ts | NO |
| 67 | gnrusLevelResolutions / gnrus_level_resolutions | 3 | 5 | 0 | 5 | src/handlers/gnrus-governance.ts | NO |
| 68 | gnrusLevelSkips / gnrus_level_skips | 3 | 5 | 0 | 5 | src/handlers/gnrus-governance.ts | NO |
| 69 | gnrusGameOver / gnrus_game_over | 3 | 5 | 0 | 5 | src/handlers/gnrus-governance.ts | NO |
| 70 | traitBurnTickets / trait_burn_tickets | 2 | 6 | 3 (api/routes/game.ts raw SQL) | 9 | src/handlers/traits-generated.ts, src/api/routes/game.ts | NO |
| 71 | traitBurnTicketProcessedLogs / trait_burn_ticket_processed_logs | 2 | 7 | 0 | 7 | src/handlers/traits-generated.ts | NO |
| 72 | playerSummary / mv_player_summary | 4 | 8 | 0 | 8 | src/api/routes/player.ts, src/indexer/view-refresh.ts, src/db/schema/views.ts | NO |
| 73 | coinflipTop10 / mv_coinflip_top10 | 4 | 13 | 0 | 13 | src/api/routes/leaderboards.ts, src/indexer/view-refresh.ts | NO |
| 74 | affiliateLeaderboard / mv_affiliate_leaderboard | 4 | 13 | 0 | 13 | src/api/routes/leaderboards.ts, src/indexer/view-refresh.ts | NO |
| 75 | bafTop4 / mv_baf_top4 | 4 | 13 | 0 | 13 | src/api/routes/leaderboards.ts, src/indexer/view-refresh.ts | NO |

**Orphan verdict:** every one of the 75 universe entries has `total refs >= 1` via at least one of the 5 scoped surfaces. **Zero schema-side orphans.**

## Code → schema imports

Every `from '.../db/schema/...'` import line in the 5 scoped surfaces (handlers + indexer + routes + views.ts + indexes.ts). `views.ts` and `indexes.ts` have no schema imports themselves. The table below enumerates every production import site; all named bindings resolve to the universe.

| # | importing file:line | import path | named bindings | all resolve? |
|---|---------------------|-------------|-----------------|-------------|
| 1 | src/api/routes/game.ts:3 | ../../db/schema/game-state.js | gameState | YES |
| 2 | src/api/routes/game.ts:4 | ../../db/schema/prize-pools.js | prizePools | YES |
| 3 | src/api/routes/game.ts:5 | ../../db/schema/daily-rng.js | dailyRng | YES |
| 4 | src/api/routes/game.ts:6 | ../../db/schema/jackpot-history.js | jackpotDistributions | YES |
| 5 | src/api/routes/viewer.ts:3 | ../../db/schema/jackpot-history.js | levelTransitions | YES |
| 6 | src/api/routes/viewer.ts:4 | ../../db/schema/daily-rng.js | dailyRng | YES |
| 7 | src/api/routes/viewer.ts:5 | ../../db/schema/token-balance-snapshots.js | tokenBalanceSnapshots | YES |
| 8 | src/api/routes/viewer.ts:6 | ../../db/schema/tickets.js | playerTickets | YES |
| 9 | src/api/routes/viewer.ts:7 | ../../db/schema/degenerette.js | degeneretteBets, degeneretteResults | YES |
| 10 | src/api/routes/viewer.ts:8 | ../../db/schema/lootbox.js | lootboxPurchases, lootboxResults | YES |
| 11 | src/api/routes/viewer.ts:9 | ../../db/schema/coinflip.js | coinflipDailyStakes, coinflipResults | YES |
| 12 | src/api/routes/viewer.ts:10 | ../../db/schema/quests.js | questProgress | YES |
| 13 | src/api/routes/viewer.ts:11 | ../../db/schema/affiliate.js | affiliateEarnings | YES |
| 14 | src/api/routes/viewer.ts:12 | ../../db/schema/new-events.js | deityPassPurchases | YES |
| 15 | src/api/routes/replay.ts:3 | ../../db/schema/daily-rng.js | dailyRng | YES |
| 16 | src/api/routes/replay.ts:4 | ../../db/schema/tickets.js | playerTickets | YES |
| 17 | src/api/routes/replay.ts:5 | ../../db/schema/jackpot-history.js | jackpotDistributions | YES |
| 18 | src/api/routes/replay.ts:6 | ../../db/schema/lootbox.js | traitsGenerated | YES |
| 19 | src/api/routes/player.ts:2 | ../../db/schema/views.js | playerSummary | YES |
| 20 | src/api/routes/player.ts:3 | ../../db/schema/quests.js | questProgress, playerStreaks | YES |
| 21 | src/api/routes/player.ts:4 | ../../db/schema/decimator.js | decimatorClaims, decimatorBurns, terminalDecimatorBurns | YES |
| 22 | src/api/routes/player.ts:5 | ../../db/schema/coinflip.js | coinflipDailyStakes, coinflipBountyState, coinflipSettings | YES |
| 23 | src/api/routes/player.ts:6 | ../../db/schema/degenerette.js | degeneretteBets, degeneretteResults | YES |
| 24 | src/api/routes/player.ts:7 | ../../db/schema/affiliate.js | affiliateCodes, playerReferrals | YES |
| 25 | src/api/routes/player.ts:8 | ../../db/schema/tickets.js | playerTickets | YES |
| 26 | src/api/routes/player.ts:9 | ../../db/schema/game-state.js | gameState | YES |
| 27 | src/api/routes/player.ts:10 | ../../db/schema/prize-pools.js | prizePools | YES |
| 28 | src/api/routes/player.ts:11 | ../../db/schema/jackpot-history.js | jackpotDistributions | YES |
| 29 | src/api/routes/tokens.ts:2 | ../../db/schema/token-balances.js | tokenSupply, tokenBalances | YES |
| 30 | src/api/routes/tokens.ts:3 | ../../db/schema/vault.js | vaultState | YES |
| 31 | src/api/routes/history.ts:2 | ../../db/schema/jackpot-history.js | jackpotDistributions, levelTransitions | YES |
| 32 | src/api/routes/history.ts:3 | ../../db/schema/degenerette.js | degeneretteBets | YES |
| 33 | src/api/routes/leaderboards.ts:2 | ../../db/schema/views.js | coinflipTop10, affiliateLeaderboard, bafTop4 | YES |
| 34 | src/indexer/event-processor.ts:19 | ../db/schema/index.js | rawEvents | YES |
| 35 | src/indexer/reorg-detector.ts:10 | ../db/schema/index.js | blocks, indexerCursor | YES |
| 36 | src/indexer/cursor-manager.ts:10 | ../db/schema/index.js | indexerCursor | YES |
| 37 | src/indexer/purge-block-range.ts:~60 | ../db/schema/index.js | (multi-binding barrel import covering tokenBalanceSnapshots and others; all resolve) | YES |
| 38 | src/indexer/view-refresh.ts:14 | ../db/schema/views.js | ALL_VIEWS, VIEW_UNIQUE_INDEXES | YES (non-table constants re-exported from `views.ts`) |
| 39 | src/indexer/view-refresh.ts:15 | ../db/schema/indexes.js | ADDITIONAL_INDEXES | YES (non-table constant from `indexes.ts`) |
| 40 | src/handlers/lootbox.ts:19 | ../db/schema/lootbox.js | lootboxPurchases, lootboxResults, traitsGenerated | YES |
| 41 | src/handlers/baf-jackpot.ts:14 | ../db/schema/baf-jackpot.js | bafFlipTotals | YES |
| 42 | src/handlers/jackpot.ts:12 | ../db/schema/jackpot-history.js | jackpotDistributions | YES |
| 43 | src/handlers/coinflip.ts:18–26 | ../db/schema/coinflip.js | coinflipDailyStakes, coinflipResults, coinflipLeaderboard, coinflipBountyState, coinflipSettings | YES |
| 44 | src/handlers/coinflip.ts:27 | ../db/schema/blocks.js | blocks | YES |
| 45 | src/handlers/token-balances.ts:24 | ../db/schema/token-balances.js | tokenBalances, tokenSupply | YES |
| 46 | src/handlers/token-balances.ts:25 | ../db/schema/token-snapshots.js | tokenSupplySnapshots | YES |
| 47 | src/handlers/deity-boons.ts:8 | ../db/schema/deity-boons.js | deityBoons | YES |
| 48 | src/handlers/tickets.ts:16 | ../db/schema/tickets.js | playerTickets | YES |
| 49 | src/handlers/index.ts:34 | ../db/schema/prize-pools.js | prizePools | YES |
| 50 | src/handlers/index.ts:35 | ../db/schema/game-state.js | gameState | YES |
| 51 | src/handlers/index.ts:36 | ../db/schema/daily-rng.js | dailyRng | YES |
| 52 | src/handlers/index.ts:37 | ../db/schema/blocks.js | blocks | YES |
| 53 | src/handlers/game-fsm.ts:11 | ../db/schema/game-state.js | gameState | YES |
| 54 | src/handlers/game-fsm.ts:12 | ../db/schema/jackpot-history.js | levelTransitions | YES |
| 55 | src/handlers/game-fsm.ts:13 | ../db/schema/blocks.js | blocks | YES |
| 56 | src/handlers/whale-pass.ts:9 | ../db/schema/player-state.js | playerWhalePasses | YES |
| 57 | src/handlers/prize-pool.ts:15 | ../db/schema/prize-pools.js | prizePools | YES |
| 58 | src/handlers/quests.ts:16 | ../db/schema/quests.js | questDefinitions, questProgress, playerStreaks, levelQuestCompletions | YES |
| 59 | src/handlers/deity-pass.ts:17 | ../db/schema/deity-pass.js | deityPassOwnership, deityPassTransfers | YES |
| 60 | src/handlers/degenerette.ts:15 | ../db/schema/degenerette.js | degeneretteBets, degeneretteResults | YES |
| 61 | src/handlers/player-settings.ts:14 | ../db/schema/player-state.js | playerSettings | YES |
| 62 | src/handlers/decimator.ts:~20–27 | ../db/schema/decimator.js | decimatorBurns, decimatorBucketTotals, decimatorWinningSubbuckets, decimatorRounds, decimatorClaims, playerBoosts, terminalDecimatorBurns | YES |
| 63 | src/handlers/decimator.ts:28 | ../db/schema/decimator-coin-burns.js | decimatorCoinBurns, terminalDecimatorCoinBurns | YES |
| 64 | src/handlers/decimator.ts:29 | ../db/schema/daily-rng.js | dailyRng | YES |
| 65 | src/handlers/decimator.ts:30 | ../db/schema/game-state.js | gameState | YES |
| 66 | src/handlers/affiliate.ts:~18–23 | ../db/schema/affiliate.js | affiliateCodes, playerReferrals, affiliateEarnings, affiliateTopByLevel | YES |
| 67 | src/handlers/affiliate.ts:24 | ../db/schema/affiliate-dgnrs-rewards.js | affiliateDgnrsRewards, affiliateDgnrsClaims | YES |
| 68 | src/handlers/sdgnrs.ts:16 | ../db/schema/vault.js | sdgnrsPoolBalances, sdgnrsDeposits, sdgnrsBurns | YES |
| 69 | src/handlers/sdgnrs.ts:17 | ../db/schema/sdgnrs-redemptions.js | sdgnrsRedemptions | YES |
| 70 | src/handlers/gnrus-governance.ts:18 | ../db/schema/gnrus-governance.js | gnrusProposals, gnrusVotes, gnrusLevelResolutions, gnrusLevelSkips, gnrusGameOver | YES |
| 71 | src/handlers/new-events.ts:20 | ../db/schema/new-events.js | deityPassPurchases, gameOverEvents, finalSweepEvents, boonConsumptions, adminEvents, linkFeedUpdates, dailyWinningTraits | YES |
| 72 | src/handlers/new-events.ts:21 | ../db/schema/prize-pools.js | prizePools | YES |
| 73 | src/handlers/new-events.ts:22 | ../db/schema/player-state.js | playerWinnings | YES |
| 74 | src/handlers/winnings.ts:14 | ../db/schema/player-state.js | playerWinnings | YES |
| 75 | src/handlers/traits-generated.ts:~17–20 | ../db/schema/trait-burn-tickets.js | traitBurnTickets, traitBurnTicketProcessedLogs | YES |
| 76 | src/handlers/vault.ts:29 | ../db/schema/vault.js | vaultState, vaultDeposits, vaultClaims | YES |
| 77 | src/handlers/daily-rng.ts:11 | ../db/schema/daily-rng.js | dailyRng, lootboxRng | YES |

**Import resolution verdict:** all 77 production import sites resolve cleanly against the universe (including the two `indexer/view-refresh.ts` imports of non-table constants `ALL_VIEWS`, `VIEW_UNIQUE_INDEXES`, `ADDITIONAL_INDEXES`, which are explicitly declared in their source files and re-exported from `index.ts`). **Zero code-side missing-in-schema findings from import analysis.**

## Raw-SQL table-name references

Every `sql\`...\`` template string in the 5 scoped surfaces was grepped for `FROM <ident>`, `JOIN <ident>`, `INTO <ident>`, and `UPDATE <ident>`. Every extracted identifier was cross-checked against the universe `pgName` set.

Identifiers found and resolution:

| identifier | occurrences | resolves to universe? |
|------------|-------------|------------------------|
| `information_schema.columns` | game.ts (metadata probes, lines 158, 226, 378, 1238) | N/A — Postgres system catalog, not a user table |
| `jackpot_distributions` | game.ts (many), player.ts, indexes.ts | YES (universe #13) |
| `daily_rng` | game.ts (many) | YES (universe #24) |
| `daily_winning_traits` | game.ts (448, 785, 1260) | YES (universe #64) |
| `trait_burn_tickets` | game.ts (1431) | YES (universe #70) |
| `trait_burn_ticket_processed_logs` | (none in scope — only in `src/cli/` which is out of scope) | N/A |
| `token_balances` | handlers/token-balances.ts (234), views.ts JOINs | YES (universe #27) |
| `token_balance_snapshots` | handlers/token-balances.ts (232, INSERT INTO) | YES (universe #52) |
| `player_winnings` | views.ts | YES (universe #6) |
| `player_streaks` | views.ts | YES (universe #43) |
| `affiliate_earnings` | views.ts, indexes.ts | YES (universe #38) |
| `coinflip_leaderboard` | views.ts, indexes.ts | YES (universe #33) |
| `baf_flip_totals` | views.ts, indexes.ts | YES (universe #40) |
| `level_transitions` | indexes.ts | YES (universe #14) |
| `degenerette_bets` | indexes.ts | YES (universe #22) |
| `decimator_claims` | indexes.ts | YES (universe #19) |
| `vault_deposits` | indexes.ts | YES (universe #46) |
| `vault_claims` | indexes.ts | YES (universe #47) |
| `day_range` | game.ts (many CTE references) | N/A — inline CTE alias, not a persistent table |
| `ranked` | game.ts (inline subquery alias) | N/A — inline subquery alias |

**Raw-SQL identifier verdict:** zero unresolved table-like identifiers. CTE aliases (`day_range`, `ranked`) and PG system catalogs (`information_schema.columns`) are explicitly excluded from the orphan scan per trap-filtering rules (these are not user tables). No code-side missing-in-schema findings from raw-SQL analysis.

## Finding stubs

**None.** The bidirectional scan produced zero schema-side orphans and zero code-side missing-in-schema references. The reserved finding-ID block `F-28-226-301..` was NOT consumed.

Documented for completeness: had any been found, each would have followed the stub format with `- **Direction:** code<->schema`, `- **Phase:** 226 (SCHEMA-04 orphan + code-reference scan)`, absolute `/home/zak/Dev/PurgeGame/database/...` file citation, and `- **Kind:** schema-orphan | code-missing-in-schema`.

## Summary

### Universe size

- **Total entries:** 75 (71 `pgTable` + 4 `pgMaterializedView`).
- Source: `/home/zak/Dev/PurgeGame/database/src/db/schema/index.ts` barrel (30 re-export lines), filtered to table/view exports only; enums (`gamePhaseEnum`) and non-table constants (`ALL_VIEWS`, `VIEW_UNIQUE_INDEXES`, `ADDITIONAL_INDEXES`) excluded.

### Schema-side orphan count

- **0 orphans.** Every one of the 75 universe entries has at least one in-scope reference (pattern-4 binding use and/or pattern-3 raw-SQL PG-name match) across handlers / indexer / routes / `views.ts` / `indexes.ts`. Minimum reference count observed = 5 (several terminal/event-log tables such as `terminalDecimatorCoinBurns`, `gameOverEvents`, `gnrusVotes`), all safely above the zero-reference orphan threshold.

### Code-side missing-in-schema count

- **0 references.** All 77 production import sites resolve to declared universe entries (or to explicitly declared non-table constants re-exported from `views.ts` / `indexes.ts`). All raw-SQL table-name identifiers extracted from `sql\`...\`` template strings resolve to universe PG names; the only non-resolving identifiers are `information_schema.columns` (Postgres system catalog), `day_range` (inline CTE), and `ranked` (inline subquery alias) — none of which are findings.

### Import resolution totals

- **77 in-scope import sites** scanned across handlers / indexer / routes (views.ts and indexes.ts have no schema imports).
- **77 / 77 resolved** (100%).

### Raw-SQL unresolved-identifier count

- **0** unresolved table-like identifiers. 13 distinct PG table names appear in `sql\`...\`` template strings across the scoped surfaces; all 13 are present in the universe. Three non-table identifiers (`information_schema.columns`, `day_range`, `ranked`) are correctly categorized as system catalogs / CTE aliases and not flagged.

### Finding IDs allocated

- **none** — reserved block `F-28-226-301..` was not consumed because the scan produced zero findings.

### Severity distribution

- INFO: 0
- LOW: 0
- Total: 0 findings.

**Final metric:** SCHEMA-04 PASS — bidirectional orphan + code-reference scan across 75 schema entries and 77 import sites surfaced zero drift.

## Self-Check: PASSED

- File exists: `.planning/phases/226-schema-migration-orphan-audit/226-04-ORPHAN-TABLES.md` — verified.
- All required `## ` headings present: Preamble, Scope surfaces, False-positive traps handled, Table universe, Schema → code references, Code → schema imports, Raw-SQL table-name references, Finding stubs, Summary (last).
- `## Summary` is the final top-level section; 7 required `### ` subheadings present.
- Universe row count (75) ≥ grep count (71 `pgTable` + 4 `pgMaterializedView` = 75).
- Zero writes performed to `/home/zak/Dev/PurgeGame/database/` (D-226-08 honored).
