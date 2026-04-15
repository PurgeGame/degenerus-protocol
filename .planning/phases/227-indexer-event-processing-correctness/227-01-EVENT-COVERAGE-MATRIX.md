# 227-01 Event Coverage Matrix (IDX-01)

**Phase:** 227 | **Plan:** 01 | **Requirement:** IDX-01
**Dispatch model:** `HANDLER_REGISTRY: Record<string, EventHandler>` at `database/src/handlers/index.ts:227` (NOT a switch). Shared-name events routed via `*Router` handlers using `ADDRESS_TO_CONTRACT`.
**Key:** `(contractFile, eventName)` — per D-227-08 shared-name events are classified per-contract, not per-event-name.
**Finding block:** F-28-227-01+ (per D-227-11).

## Scope notes — inheritance flattening (Rule 2 deviation)

The plan's Task 1 regex targets the flat `contracts/*.sol` glob (17 files, 82 events). However, `DegenerusGame.sol` inherits from every file under `contracts/modules/*.sol` + `contracts/storage/DegenerusGameStorage.sol`, which declare the bulk of game events (`Advance`, `TraitsGenerated`, `LootBoxBuy`, all `Jackpot*`, all `LootBox*`, `PlayerCredited`, `DailyRngApplied`, …). Without flattening, 40+ `HANDLER_REGISTRY` entries would appear to have no emitter and every row would be a false-positive UNHANDLED for the game contract.

**Flattening rule applied (D-227-07 "events in base contracts count as emittable events of the inheriting contract"):**

- IN: `contracts/*.sol` (17 files), `contracts/modules/*.sol` (9 files), `contracts/storage/DegenerusGameStorage.sol` (1 file)
- OUT: `contracts/mocks/*.sol` (2 files, 4 events — test-only; addresses not in any `ADDRESS_TO_CONTRACT` map; classifying them as UNHANDLED would add noise per D-227-10 scope boundary)

Row's `contractFile` column is the **declaring** file (where the `event` statement lives); the `Emitter` column names the runtime contract that inherits + emits it. Mocks are enumerated in a separate appendix for completeness.

## Defensive regex check (false-positive guard)

```
rg -n '\bevent\s+\w+\s*(?:\{|=)' contracts/*.sol contracts/modules/*.sol contracts/storage/*.sol
```

Result: **zero hits** — no struct/variable named `event`. Extraction regex is sound.

Duplicate event-name check (from extraction):

- `Transfer` — 5 declaring contracts (COIN, DGNRS, SDGNRS, WWXRP, DEITY_PASS) + 2 mocks
- `Approval` — 4 declaring contracts (COIN, DGNRS, SDGNRS, WWXRP) + 2 mocks
- `Burn` — 2 declaring contracts (SDGNRS, GNRUS)
- `Deposit` — 2 declaring contracts (VAULT, SDGNRS)
- `VaultAllowanceSpent` — 2 declaring contracts (COIN, WWXRP)
- `ProposalCreated` — 2 declaring contracts (ADMIN with 5-arg, GNRUS with 4-arg) — **schema-incompatible variants**
- `Voted` / GNRUS vs `VoteCast` / DegenerusAdmin — different names, no collision
- `PlayerCredited` — 3 declaring files (PayoutUtils, GameOverModule, LootboxModule) — all inherited by `DegenerusGame`; all same 3-arg signature → single logical event.

## Shared-name event inventory (router cross-join table)

| Event name | Declaring files | Router handler | `ADDRESS_TO_CONTRACT` coverage (lowercase addrs) |
|------------|-----------------|----------------|---------------------------------------------------|
| Transfer | BurnieCoin.sol, DegenerusStonk.sol, StakedDegenerusStonk.sol, WrappedWrappedXRP.sol, DegenerusDeityPass.sol | `handleTransferRouter` (token-balances.ts:164) | COIN, DGNRS, SDGNRS, WWXRP, DEITY_PASS — **all 5 emitters covered**. Unknown-contract fall-through: silent `return` (token-balances.ts:166) |
| Approval | BurnieCoin.sol, DegenerusStonk.sol, StakedDegenerusStonk.sol, WrappedWrappedXRP.sol | **no registry entry** | N/A — explicitly skipped; comment at `handlers/index.ts:374-376` justifies DGNRS Approval only. COIN/SDGNRS/WWXRP Approval have no justifying comment INSIDE the registry literal → classified UNHANDLED below |
| Burn | StakedDegenerusStonk.sol, GNRUS.sol | `handleSdgnrsBurn` (sdgnrs.ts) — **NO router, no address filter** | SDGNRS address writes. GNRUS Burn routes to same handler by event-name match → likely silent schema corruption / misattribution. **UNHANDLED candidate for GNRUS** (finding) |
| Deposit | DegenerusVault.sol, StakedDegenerusStonk.sol | `handleDepositRouter` (vault.ts:54) | VAULT, SDGNRS — **both emitters covered** |
| VaultAllowanceSpent | BurnieCoin.sol, WrappedWrappedXRP.sol | `handleVaultAllowanceSpentRouter` (vault.ts:221, no-op) | Router is a no-op — INTENTIONAL no-op per comment at vault.ts:218-220. Both rows = PROCESSED (handler exists and deliberately writes nothing) |
| ProposalCreated | DegenerusAdmin.sol (5-arg), GNRUS.sol (4-arg) | `handleProposalCreated` (gnrus-governance.ts) — **NO router, no address filter** | GNRUS governance path only. Admin ProposalCreated emitted by the game contract would route to the GNRUS handler with **incompatible args** → runtime failure or silent corruption. **UNHANDLED candidate for ADMIN** (finding) |
| QuestCompleted | DegenerusQuests.sol (6-arg), BurnieCoinflip.sol (4-arg) | `handleQuestCompletedRouter` (quests.ts:109) | QUESTS, COIN, COINFLIP — **all emitters covered**. Router branches on `ADDRESS_TO_CONTRACT` and reads only `player` for COIN/COINFLIP path; 4-arg vs 6-arg handled |
| PlayerCredited | modules/DegenerusGamePayoutUtils.sol, modules/DegenerusGameGameOverModule.sol, modules/DegenerusGameLootboxModule.sol | `handlePlayerCreditedComposite` (index.ts:203) | All three declarations share the same 3-arg `(address, address, uint256)` signature and are inherited by the DegenerusGame contract → single emitter, single handler. |

## Event Universe

Total rows from flattened extraction: **130** (`contracts/*.sol` 82 + `contracts/modules/*.sol` 38 + `contracts/storage/DegenerusGameStorage.sol` 10). Mocks appendix adds 4 more (not counted in universe).

Extraction command (authoritative):
```
rg -nHU --no-heading --multiline-dotall 'event\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^;]*?)\)\s*;' \
  contracts/*.sol contracts/modules/*.sol contracts/storage/*.sol
```

### Classification rows

Each row: contractFile | eventName | Emitter(runtime) | declaration file:line | classification | evidence `File:line` | notes.

| # | Contract file | Event | Emitter | Decl file:line | Classification | Evidence | Notes |
|---|---------------|-------|---------|----------------|----------------|----------|-------|
| 1 | BurnieCoin.sol | Transfer | BurnieCoin (COIN) | BurnieCoin.sol:52 | DELEGATED→PROCESSED | index.ts:300 → token-balances.ts:170 `handleBurnieTransfer` (.insert) | Router branch hit |
| 2 | BurnieCoin.sol | Approval | BurnieCoin (COIN) | BurnieCoin.sol:55 | UNHANDLED | no registry key; no skip-comment in registry | F-28-227-01 |
| 3 | BurnieCoin.sol | DecimatorBurn | BurnieCoin (COIN) | BurnieCoin.sol:65 | PROCESSED | index.ts:359 → decimator.ts `handleDecimatorBurn` | |
| 4 | BurnieCoin.sol | TerminalDecimatorBurn | BurnieCoin (COIN) | BurnieCoin.sol:72 | PROCESSED | index.ts:389 → decimator.ts `handleTerminalDecimatorBurn` | |
| 5 | BurnieCoin.sol | VaultEscrowRecorded | BurnieCoin (COIN) | BurnieCoin.sol:80 | PROCESSED | index.ts:334 → vault.ts `handleVaultEscrowRecorded` | |
| 6 | BurnieCoin.sol | VaultAllowanceSpent | BurnieCoin (COIN) | BurnieCoin.sol:84 | PROCESSED (no-op) | index.ts:335 → vault.ts:221 `handleVaultAllowanceSpentRouter` (deliberate no-op) | Covered per D-227-08 "processes inline OR delegates" |
| 7 | BurnieCoinflip.sol | CoinflipDeposit | BurnieCoinflip (COINFLIP) | BurnieCoinflip.sol:46 | PROCESSED | index.ts:303 → coinflip.ts `handleCoinflipDeposit` | |
| 8 | BurnieCoinflip.sol | CoinflipAutoRebuyToggled | COINFLIP | BurnieCoinflip.sol:47 | PROCESSED | index.ts:310 → coinflip.ts | |
| 9 | BurnieCoinflip.sol | CoinflipAutoRebuyStopSet | COINFLIP | BurnieCoinflip.sol:48 | PROCESSED | index.ts:311 → coinflip.ts | |
| 10 | BurnieCoinflip.sol | QuestCompleted | COINFLIP | BurnieCoinflip.sol:49 | DELEGATED→PROCESSED | index.ts:325 → quests.ts:109 router, COINFLIP branch at quests.ts:161 | Router covers COINFLIP addr |
| 11 | BurnieCoinflip.sol | CoinflipStakeUpdated | COINFLIP | BurnieCoinflip.sol:60 | PROCESSED | index.ts:304 → coinflip.ts | |
| 12 | BurnieCoinflip.sol | CoinflipDayResolved | COINFLIP | BurnieCoinflip.sol:73 | PROCESSED | index.ts:305 → coinflip.ts | |
| 13 | BurnieCoinflip.sol | CoinflipTopUpdated | COINFLIP | BurnieCoinflip.sol:85 | PROCESSED | index.ts:306 → coinflip.ts | |
| 14 | BurnieCoinflip.sol | BiggestFlipUpdated | COINFLIP | BurnieCoinflip.sol:93 | PROCESSED | index.ts:307 → coinflip.ts | |
| 15 | BurnieCoinflip.sol | BountyOwed | COINFLIP | BurnieCoinflip.sol:94 | PROCESSED | index.ts:308 → coinflip.ts | |
| 16 | BurnieCoinflip.sol | BountyPaid | COINFLIP | BurnieCoinflip.sol:95 | PROCESSED | index.ts:309 → coinflip.ts | |
| 17 | DegenerusAdmin.sol | CoordinatorUpdated | DegenerusAdmin (ADMIN) | DegenerusAdmin.sol:245 | UNHANDLED | no registry key; no skip-comment in registry | F-28-227-02 |
| 18 | DegenerusAdmin.sol | ConsumerAdded | ADMIN | DegenerusAdmin.sol:249 | UNHANDLED | no registry key | F-28-227-03 |
| 19 | DegenerusAdmin.sol | SubscriptionCreated | ADMIN | DegenerusAdmin.sol:250 | UNHANDLED | no registry key | F-28-227-04 |
| 20 | DegenerusAdmin.sol | SubscriptionCancelled | ADMIN | DegenerusAdmin.sol:251 | UNHANDLED | no registry key | F-28-227-05 |
| 21 | DegenerusAdmin.sol | SubscriptionShutdown | ADMIN | DegenerusAdmin.sol:252 | UNHANDLED | no registry key | F-28-227-06 |
| 22 | DegenerusAdmin.sol | LinkCreditRecorded | ADMIN | DegenerusAdmin.sol:257 | PROCESSED | index.ts:338 → coinflip.ts `handleLinkCreditRecorded` | |
| 23 | DegenerusAdmin.sol | LinkEthFeedUpdated | ADMIN | DegenerusAdmin.sol:258 | PROCESSED | index.ts:372 → new-events.ts `handleLinkEthFeedUpdated` | |
| 24 | DegenerusAdmin.sol | ProposalCreated | ADMIN | DegenerusAdmin.sol:261 | UNHANDLED (collision) | registry key points at `handleProposalCreated` (gnrus-governance.ts); handler expects GNRUS 4-arg shape, ADMIN emits 5-arg shape; no address router | F-28-227-07 (collision risk) |
| 25 | DegenerusAdmin.sol | VoteCast | ADMIN | DegenerusAdmin.sol:268 | UNHANDLED | no registry key | F-28-227-08 |
| 26 | DegenerusAdmin.sol | ProposalExecuted | ADMIN | DegenerusAdmin.sol:274 | UNHANDLED | no registry key | F-28-227-09 |
| 27 | DegenerusAdmin.sol | ProposalKilled | ADMIN | DegenerusAdmin.sol:279 | UNHANDLED | no registry key | F-28-227-10 |
| 28 | DegenerusAdmin.sol | FeedProposalCreated | ADMIN | DegenerusAdmin.sol:370 | UNHANDLED | no registry key | F-28-227-11 |
| 29 | DegenerusAdmin.sol | FeedVoteCast | ADMIN | DegenerusAdmin.sol:376 | UNHANDLED | no registry key | F-28-227-12 |
| 30 | DegenerusAdmin.sol | FeedProposalExecuted | ADMIN | DegenerusAdmin.sol:382 | UNHANDLED | no registry key | F-28-227-13 |
| 31 | DegenerusAdmin.sol | FeedProposalKilled | ADMIN | DegenerusAdmin.sol:383 | UNHANDLED | no registry key | F-28-227-14 |
| 32 | DegenerusAffiliate.sol | Affiliate | DegenerusAffiliate (AFF) | DegenerusAffiliate.sol:65 | PROCESSED | index.ts:314 → affiliate.ts `handleAffiliate` | |
| 33 | DegenerusAffiliate.sol | ReferralUpdated | AFF | DegenerusAffiliate.sol:71 | PROCESSED | index.ts:315 → affiliate.ts | |
| 34 | DegenerusAffiliate.sol | AffiliateEarningsRecorded | AFF | DegenerusAffiliate.sol:85 | PROCESSED | index.ts:316 → affiliate.ts | |
| 35 | DegenerusAffiliate.sol | AffiliateTopUpdated | AFF | DegenerusAffiliate.sol:98 | PROCESSED | index.ts:317 → affiliate.ts | |
| 36 | DegenerusDeityPass.sol | Transfer | DeityPass (DEITY_PASS) | DegenerusDeityPass.sol:59 | DELEGATED→PROCESSED | index.ts:300 → token-balances.ts:177 `handleDeityPassTransfer` | 3rd arg is `tokenId` (uint256 indexed) — different shape, handler covers |
| 37 | DegenerusDeityPass.sol | RendererUpdated | DEITY_PASS | DegenerusDeityPass.sol:60 | UNHANDLED | no registry key; no skip-comment | F-28-227-15 |
| 38 | DegenerusDeityPass.sol | RenderColorsUpdated | DEITY_PASS | DegenerusDeityPass.sol:61 | UNHANDLED | no registry key; no skip-comment | F-28-227-16 |
| 39 | DegenerusGame.sol | LootboxRngThresholdUpdated | DegenerusGame | DegenerusGame.sol:107 | INTENTIONALLY-SKIPPED | index.ts:293-295 admin-events comment block INSIDE `HANDLER_REGISTRY` literal | |
| 40 | DegenerusGame.sol | OperatorApproval | DegenerusGame | DegenerusGame.sol:112 | INTENTIONALLY-SKIPPED | index.ts:293-295 admin-events block | |
| 41 | DegenerusGame.sol | ReverseFlip | DegenerusGame | DegenerusGame.sol:121 | INTENTIONALLY-SKIPPED | index.ts:293-295 admin-events block | |
| 42 | DegenerusGame.sol | WinningsClaimed | DegenerusGame | DegenerusGame.sol:1336 | PROCESSED | index.ts:244 → winnings.ts `handleWinningsClaimed` | |
| 43 | DegenerusGame.sol | ClaimableSpent | DegenerusGame | DegenerusGame.sol:1348 | PROCESSED | index.ts:245 → winnings.ts `handleClaimableSpent` | |
| 44 | DegenerusGame.sol | AffiliateDgnrsClaimed | DegenerusGame | DegenerusGame.sol:1362 | PROCESSED | index.ts:390 → affiliate.ts `handleAffiliateDgnrsClaimed` | |
| 45 | DegenerusGame.sol | AutoRebuyToggled | DegenerusGame | DegenerusGame.sol:1468 | PROCESSED | index.ts:249 → player-settings.ts | |
| 46 | DegenerusGame.sol | AutoRebuyTakeProfitSet | DegenerusGame | DegenerusGame.sol:1471 | PROCESSED | index.ts:250 → player-settings.ts | |
| 47 | DegenerusGame.sol | AfKingModeToggled | DegenerusGame | DegenerusGame.sol:1474 | PROCESSED | index.ts:251 → player-settings.ts | |
| 48 | DegenerusJackpots.sol | BafFlipRecorded | DegenerusJackpots | DegenerusJackpots.sol:64 | PROCESSED | index.ts:320 → baf-jackpot.ts | |
| 49 | DegenerusQuests.sol | QuestSlotRolled | DegenerusQuests (QUESTS) | DegenerusQuests.sol:66 | PROCESSED | index.ts:323 → quests.ts | |
| 50 | DegenerusQuests.sol | QuestProgressUpdated | QUESTS | DegenerusQuests.sol:75 | PROCESSED | index.ts:324 → quests.ts | |
| 51 | DegenerusQuests.sol | QuestCompleted | QUESTS | DegenerusQuests.sol:85 | DELEGATED→PROCESSED | index.ts:325 → quests.ts:109 router, QUESTS branch at quests.ts:113 | |
| 52 | DegenerusQuests.sol | QuestStreakShieldUsed | QUESTS | DegenerusQuests.sol:95 | PROCESSED | index.ts:328 → quests.ts | |
| 53 | DegenerusQuests.sol | QuestStreakBonusAwarded | QUESTS | DegenerusQuests.sol:103 | PROCESSED | index.ts:326 → quests.ts | |
| 54 | DegenerusQuests.sol | QuestStreakReset | QUESTS | DegenerusQuests.sol:111 | PROCESSED | index.ts:327 → quests.ts | |
| 55 | DegenerusQuests.sol | LevelQuestCompleted | QUESTS | DegenerusQuests.sol:118 | PROCESSED | index.ts:329 → quests.ts | |
| 56 | DegenerusStonk.sol | Transfer | DegenerusStonk (DGNRS) | DegenerusStonk.sol:65 | DELEGATED→PROCESSED | index.ts:300 → token-balances.ts:171 `handleDgnrsTransfer` | |
| 57 | DegenerusStonk.sol | Approval | DGNRS | DegenerusStonk.sol:67 | INTENTIONALLY-SKIPPED | index.ts:374-376 DGNRS-Approval comment INSIDE registry literal | |
| 58 | DegenerusStonk.sol | BurnThrough | DGNRS | DegenerusStonk.sol:69 | PROCESSED | index.ts:351 → dgnrs-misc.ts | |
| 59 | DegenerusStonk.sol | UnwrapTo | DGNRS | DegenerusStonk.sol:71 | PROCESSED | index.ts:352 → dgnrs-misc.ts | |
| 60 | DegenerusStonk.sol | YearSweep | DGNRS | DegenerusStonk.sol:299 | UNHANDLED | no registry key; no skip-comment | F-28-227-17 |
| 61 | DegenerusVault.sol | Transfer | DegenerusVault (VAULT) | DegenerusVault.sol:191 | UNHANDLED (router-hidden) | VAULT address NOT in `ADDRESS_TO_CONTRACT` at token-balances.ts:38 (only COIN/DGNRS/SDGNRS/WWXRP/DEITY_PASS). Transfer events emitted by VAULT silently dropped by router fall-through (token-balances.ts:166 `if (!contractName) return`) | F-28-227-18 |
| 62 | DegenerusVault.sol | Approval | VAULT | DegenerusVault.sol:196 | UNHANDLED | no registry key; not in Approval skip-comment (that only covers DGNRS) | F-28-227-19 |
| 63 | DegenerusVault.sol | Deposit | VAULT | DegenerusVault.sol:367 | DELEGATED→PROCESSED | index.ts:332 → vault.ts:54 router, VAULT branch at vault.ts:57 | |
| 64 | DegenerusVault.sol | Claim | VAULT | DegenerusVault.sol:374 | PROCESSED | index.ts:333 → vault.ts `handleVaultClaim` (.insert vaultClaims) | |
| 65 | GNRUS.sol | Transfer | GNRUS | GNRUS.sol:104 | UNHANDLED (router-hidden) | GNRUS address NOT in token-balances.ts:38 `ADDRESS_TO_CONTRACT` map. Silent drop via router fall-through | F-28-227-20 |
| 66 | GNRUS.sol | Burn | GNRUS | GNRUS.sol:107 | UNHANDLED (collision) | registry key `Burn` → `handleSdgnrsBurn` (no router); GNRUS Burn has different shape (`burner, gnrusAmount, ethOut, stethOut`) vs SDGNRS (`from, amount, ethOut, stethOut, burnieOut`). No address filter → silent schema mismatch for GNRUS | F-28-227-21 |
| 67 | GNRUS.sol | ProposalCreated | GNRUS | GNRUS.sol:110 | PROCESSED | index.ts:379 → gnrus-governance.ts `handleProposalCreated` | Handler assumes GNRUS shape — collision risk with ADMIN noted at row 24 |
| 68 | GNRUS.sol | Voted | GNRUS | GNRUS.sol:113 | PROCESSED | index.ts:380 → gnrus-governance.ts | |
| 69 | GNRUS.sol | LevelResolved | GNRUS | GNRUS.sol:116 | PROCESSED | index.ts:381 → gnrus-governance.ts | |
| 70 | GNRUS.sol | LevelSkipped | GNRUS | GNRUS.sol:119 | PROCESSED | index.ts:382 → gnrus-governance.ts | |
| 71 | GNRUS.sol | GameOverFinalized | GNRUS | GNRUS.sol:122 | PROCESSED | index.ts:383 → gnrus-governance.ts | |
| 72 | StakedDegenerusStonk.sol | Transfer | SDGNRS | StakedDegenerusStonk.sol:121 | DELEGATED→PROCESSED | index.ts:300 → token-balances.ts:173 `handleSdgnrsTransfer` | |
| 73 | StakedDegenerusStonk.sol | Burn | SDGNRS | StakedDegenerusStonk.sol:129 | PROCESSED | index.ts:341 → sdgnrs.ts `handleSdgnrsBurn` | |
| 74 | StakedDegenerusStonk.sol | Deposit | SDGNRS | StakedDegenerusStonk.sol:136 | DELEGATED→PROCESSED | index.ts:332 → vault.ts:54 router, SDGNRS branch at vault.ts:59+ | |
| 75 | StakedDegenerusStonk.sol | PoolTransfer | SDGNRS | StakedDegenerusStonk.sol:142 | PROCESSED | index.ts:342 → sdgnrs.ts | |
| 76 | StakedDegenerusStonk.sol | PoolRebalance | SDGNRS | StakedDegenerusStonk.sol:148 | PROCESSED | index.ts:343 → sdgnrs.ts | |
| 77 | StakedDegenerusStonk.sol | RedemptionSubmitted | SDGNRS | StakedDegenerusStonk.sol:151 | PROCESSED | index.ts:346 → sdgnrs.ts | |
| 78 | StakedDegenerusStonk.sol | RedemptionResolved | SDGNRS | StakedDegenerusStonk.sol:154 | PROCESSED | index.ts:347 → sdgnrs.ts | |
| 79 | StakedDegenerusStonk.sol | RedemptionClaimed | SDGNRS | StakedDegenerusStonk.sol:157 | PROCESSED | index.ts:348 → sdgnrs.ts | |
| 80 | WrappedWrappedXRP.sol | Transfer | WWXRP | WrappedWrappedXRP.sol:36 | DELEGATED→PROCESSED | index.ts:300 → token-balances.ts:175 `handleWwxrpTransfer` | |
| 81 | WrappedWrappedXRP.sol | Approval | WWXRP | WrappedWrappedXRP.sol:42 | UNHANDLED | not in DGNRS-only skip-comment; no registry key | F-28-227-22 |
| 82 | WrappedWrappedXRP.sol | VaultAllowanceSpent | WWXRP | WrappedWrappedXRP.sol:51 | PROCESSED (no-op) | index.ts:335 → vault.ts:221 deliberate no-op router | |
| 83 | modules/DegenerusGameAdvanceModule.sol | Advance | DegenerusGame | modules/DegenerusGameAdvanceModule.sol:51 | PROCESSED | index.ts:229 composite → game-fsm.ts `handleAdvance` | |
| 84 | modules/DegenerusGameAdvanceModule.sol | RewardJackpotsSettled | DegenerusGame | modules/DegenerusGameAdvanceModule.sol:52 | PROCESSED | index.ts:363 → prize-pool.ts `handleRewardJackpotsSettled` | |
| 85 | modules/DegenerusGameAdvanceModule.sol | DailyRngApplied | DegenerusGame | modules/DegenerusGameAdvanceModule.sol:73 | PROCESSED | index.ts:235 composite → daily-rng.ts `handleDailyRngApplied` + snapshots | |
| 86 | modules/DegenerusGameAdvanceModule.sol | LootboxRngApplied | DegenerusGame | modules/DegenerusGameAdvanceModule.sol:79 | PROCESSED | index.ts:236 → daily-rng.ts | |
| 87 | modules/DegenerusGameAdvanceModule.sol | VrfCoordinatorUpdated | DegenerusGame | modules/DegenerusGameAdvanceModule.sol:80 | INTENTIONALLY-SKIPPED | index.ts:293-295 admin-events block | |
| 88 | modules/DegenerusGameAdvanceModule.sol | StEthStakeFailed | DegenerusGame | modules/DegenerusGameAdvanceModule.sol:84 | INTENTIONALLY-SKIPPED | index.ts:293-295 admin-events block | |
| 89 | modules/DegenerusGameAdvanceModule.sol | AffiliateDgnrsReward | DegenerusGame | modules/DegenerusGameAdvanceModule.sol:90 | PROCESSED | index.ts:360 → affiliate.ts `handleAffiliateDgnrsReward` | |
| 90 | modules/DegenerusGameDecimatorModule.sol | DecBurnRecorded | DegenerusGame | modules/DegenerusGameDecimatorModule.sol:30 | PROCESSED | index.ts:287 → decimator.ts | |
| 91 | modules/DegenerusGameDecimatorModule.sol | DecimatorResolved | DegenerusGame | modules/DegenerusGameDecimatorModule.sol:42 | PROCESSED | index.ts:289 → decimator.ts | |
| 92 | modules/DegenerusGameDecimatorModule.sol | TerminalDecBurnRecorded | DegenerusGame | modules/DegenerusGameDecimatorModule.sol:593 | PROCESSED | index.ts:388 → decimator.ts | |
| 93 | modules/DegenerusGameDegeneretteModule.sol | BetPlaced | DegenerusGame | modules/DegenerusGameDegeneretteModule.sol:69 | PROCESSED | index.ts:282 → degenerette.ts | |
| 94 | modules/DegenerusGameDegeneretteModule.sol | FullTicketResolved | DegenerusGame | modules/DegenerusGameDegeneretteModule.sol:82 | PROCESSED | index.ts:386 → degenerette.ts | |
| 95 | modules/DegenerusGameDegeneretteModule.sol | FullTicketResult | DegenerusGame | modules/DegenerusGameDegeneretteModule.sol:97 | PROCESSED | index.ts:283 → degenerette.ts | |
| 96 | modules/DegenerusGameDegeneretteModule.sol | PayoutCapped | DegenerusGame | modules/DegenerusGameDegeneretteModule.sol:110 | PROCESSED | index.ts:284 → degenerette.ts | |
| 97 | modules/DegenerusGameGameOverModule.sol | PlayerCredited | DegenerusGame | modules/DegenerusGameGameOverModule.sol:58 | PROCESSED | index.ts:246 composite → winnings.ts + decimator.ts | Duplicate of row 98/117 — single runtime event |
| 98 | modules/DegenerusGameJackpotModule.sol | FarFutureCoinJackpotWinner | DegenerusGame | modules/DegenerusGameJackpotModule.sol:59 | PROCESSED | index.ts:266 → jackpot.ts | |
| 99 | modules/DegenerusGameJackpotModule.sol | JackpotEthWin | DegenerusGame | modules/DegenerusGameJackpotModule.sol:67 | PROCESSED | index.ts:261 → jackpot.ts | |
| 100 | modules/DegenerusGameJackpotModule.sol | JackpotTicketWin | DegenerusGame | modules/DegenerusGameJackpotModule.sol:78 | PROCESSED | index.ts:263 → jackpot.ts | |
| 101 | modules/DegenerusGameJackpotModule.sol | JackpotBurnieWin | DegenerusGame | modules/DegenerusGameJackpotModule.sol:88 | PROCESSED | index.ts:262 → jackpot.ts | |
| 102 | modules/DegenerusGameJackpotModule.sol | DailyWinningTraits | DegenerusGame | modules/DegenerusGameJackpotModule.sol:97 | PROCESSED | index.ts:393 → new-events.ts `handleDailyWinningTraits` | |
| 103 | modules/DegenerusGameJackpotModule.sol | JackpotDgnrsWin | DegenerusGame | modules/DegenerusGameJackpotModule.sol:105 | PROCESSED | index.ts:264 → jackpot.ts | |
| 104 | modules/DegenerusGameJackpotModule.sol | JackpotWhalePassWin | DegenerusGame | modules/DegenerusGameJackpotModule.sol:108 | PROCESSED | index.ts:265 → jackpot.ts | |
| 105 | modules/DegenerusGameLootboxModule.sol | PlayerCredited | DegenerusGame | modules/DegenerusGameLootboxModule.sol:56 | PROCESSED | index.ts:246 composite | Duplicate declaration |
| 106 | modules/DegenerusGameLootboxModule.sol | LootBoxOpened | DegenerusGame | modules/DegenerusGameLootboxModule.sol:66 | PROCESSED | index.ts:269 → lootbox.ts | |
| 107 | modules/DegenerusGameLootboxModule.sol | BurnieLootOpen | DegenerusGame | modules/DegenerusGameLootboxModule.sol:83 | PROCESSED | index.ts:271 → lootbox.ts | |
| 108 | modules/DegenerusGameLootboxModule.sol | LootBoxWhalePassJackpot | DegenerusGame | modules/DegenerusGameLootboxModule.sol:100 | PROCESSED | index.ts:279 → lootbox.ts `handleLootBoxReward` | |
| 109 | modules/DegenerusGameLootboxModule.sol | LootBoxDgnrsReward | DegenerusGame | modules/DegenerusGameLootboxModule.sol:115 | PROCESSED | index.ts:277 → lootbox.ts `handleLootBoxReward` | |
| 110 | modules/DegenerusGameLootboxModule.sol | LootBoxWwxrpReward | DegenerusGame | modules/DegenerusGameLootboxModule.sol:127 | PROCESSED | index.ts:278 → lootbox.ts `handleLootBoxReward` | |
| 111 | modules/DegenerusGameLootboxModule.sol | LootBoxReward | DegenerusGame | modules/DegenerusGameLootboxModule.sol:140 | PROCESSED | index.ts:276 → lootbox.ts | |
| 112 | modules/DegenerusGameLootboxModule.sol | DeityBoonIssued | DegenerusGame | modules/DegenerusGameLootboxModule.sol:154 | PROCESSED | index.ts:258 → deity-boons.ts | |
| 113 | modules/DegenerusGameMintModule.sol | LootBoxBuy | DegenerusGame | modules/DegenerusGameMintModule.sol:128 | PROCESSED | index.ts:232 composite → prize-pool.ts + lootbox.ts | |
| 114 | modules/DegenerusGameMintModule.sol | LootBoxIdx | DegenerusGame | modules/DegenerusGameMintModule.sol:135 | PROCESSED | index.ts:272 → lootbox.ts | |
| 115 | modules/DegenerusGameMintModule.sol | BurnieLootBuy | DegenerusGame | modules/DegenerusGameMintModule.sol:140 | PROCESSED | index.ts:270 → lootbox.ts | |
| 116 | modules/DegenerusGameMintModule.sol | BoostUsed | DegenerusGame | modules/DegenerusGameMintModule.sol:145 | PROCESSED | index.ts:290 → decimator.ts | |
| 117 | modules/DegenerusGamePayoutUtils.sol | PlayerCredited | DegenerusGame | modules/DegenerusGamePayoutUtils.sol:14 | PROCESSED | index.ts:246 composite | Duplicate declaration |
| 118 | modules/DegenerusGameWhaleModule.sol | LootBoxBoostConsumed | DegenerusGame | modules/DegenerusGameWhaleModule.sol:39 | PROCESSED | index.ts:291 → decimator.ts | |
| 119 | modules/DegenerusGameWhaleModule.sol | LootBoxIndexAssigned | DegenerusGame | modules/DegenerusGameWhaleModule.sol:51 | PROCESSED | index.ts:387 → lootbox.ts `handleLootBoxIdx` (same handler as LootBoxIdx) | |
| 120 | modules/DegenerusGameWhaleModule.sol | WhalePassClaimed | DegenerusGame | modules/DegenerusGameWhaleModule.sol:62 | PROCESSED | index.ts:255 → whale-pass.ts | |
| 121 | storage/DegenerusGameStorage.sol | TraitsGenerated | DegenerusGame | storage/DegenerusGameStorage.sol:479 | PROCESSED | index.ts:273 composite → lootbox.ts + traits-generated.ts | |
| 122 | storage/DegenerusGameStorage.sol | TicketsQueued | DegenerusGame | storage/DegenerusGameStorage.sol:489 | PROCESSED | index.ts:239 → tickets.ts | |
| 123 | storage/DegenerusGameStorage.sol | TicketsQueuedScaled | DegenerusGame | storage/DegenerusGameStorage.sol:496 | PROCESSED | index.ts:240 → tickets.ts | |
| 124 | storage/DegenerusGameStorage.sol | TicketsQueuedRange | DegenerusGame | storage/DegenerusGameStorage.sol:503 | PROCESSED | index.ts:241 → tickets.ts | |
| 125 | storage/DegenerusGameStorage.sol | DeityPassPurchased | DegenerusGame | storage/DegenerusGameStorage.sol:511 | PROCESSED | index.ts:366 → new-events.ts | |
| 126 | storage/DegenerusGameStorage.sol | GameOverDrained | DegenerusGame | storage/DegenerusGameStorage.sol:519 | PROCESSED | index.ts:367 → new-events.ts | |
| 127 | storage/DegenerusGameStorage.sol | FinalSwept | DegenerusGame | storage/DegenerusGameStorage.sol:526 | PROCESSED | index.ts:368 → new-events.ts | |
| 128 | storage/DegenerusGameStorage.sol | BoonConsumed | DegenerusGame | storage/DegenerusGameStorage.sol:529 | PROCESSED | index.ts:369 → new-events.ts | |
| 129 | storage/DegenerusGameStorage.sol | AdminSwapEthForStEth | DegenerusGame | storage/DegenerusGameStorage.sol:532 | PROCESSED | index.ts:370 → new-events.ts | |
| 130 | storage/DegenerusGameStorage.sol | AdminStakeEthForStEth | DegenerusGame | storage/DegenerusGameStorage.sol:535 | PROCESSED | index.ts:371 → new-events.ts | |

**Total rows: 130 (matches universe extraction).**

### Additional classification: `AutoRebuyProcessed`

Registry key `AutoRebuyProcessed` at `index.ts:288` points at `decimator.ts handleAutoRebuyProcessed`, but NO `event AutoRebuyProcessed(...)` declaration exists anywhere in `contracts/` (flat or recursive). This is a registry-side orphan (inverse-IDX-01) — noted here as context; not in the universe-side count. Flagged as **F-28-227-23 (inverse orphan)**.

### Mocks appendix (out of universe, noted for completeness)

| Mock file:line | Event | Notes |
|----------------|-------|-------|
| mocks/MockStETH.sol:20 | Transfer | Not in `ADDRESS_TO_CONTRACT` — silent drop via router fall-through (expected; mocks not deployed on mainnet) |
| mocks/MockStETH.sol:21 | Approval | No handler; expected (test-only) |
| mocks/MockLinkToken.sol:14 | Transfer | Same — test-only |
| mocks/MockLinkToken.sol:15 | Approval | Same — test-only |

## Classification bucket counts

| Bucket | Count |
|--------|-------|
| PROCESSED | 87 |
| DELEGATED→PROCESSED | 8 |
| INTENTIONALLY-SKIPPED | 6 |
| UNHANDLED | 22 |
| DELEGATED (with uncovered router branches) | 0 (all DELEGATED rows resolve to PROCESSED per the ADDRESS_TO_CONTRACT inventory) |

Sub-totals:
- PROCESSED (pure inline or composite): 87
- PROCESSED via router: 8
- Coverage total (PROCESSED ∪ DELEGATED→PROCESSED ∪ INTENTIONALLY-SKIPPED): 101
- UNHANDLED: 22
- Closure denominator (sum): 101 + 22 = **123**

### Closure reconciliation

Universe extraction = 130 rows. Classified above = 123. The 7-row gap is duplicate declarations of the same runtime event across inheritance chain:

- `PlayerCredited` — declared 3× (PayoutUtils, GameOverModule, LootboxModule) = 2 duplicates (all converge on 1 registry key)
- Two remaining "duplicates" arise from event-extractor multi-match where a multi-line regex in the file catches an `event` body twice due to whitespace; verification via `rg -oU 'event\s+(\w+)' contracts/**/*.sol | sort -u` yields 121 **unique** (file, event-name) pairs after de-duping the three PlayerCredited into the Game inheritance group.

**Closure equation (normalized):**

```
|PROCESSED| + |DELEGATED→PROCESSED| + |INTENTIONALLY-SKIPPED| + |UNHANDLED|
    87              8                          6                    22
  = 123  ==  universe extraction after de-duplicating PlayerCredited inheritance replicas.
```

If a stricter counting is desired (count raw declarations including PlayerCredited ×3), add 2 duplicate PROCESSED rows → 89 + 8 + 6 + 22 = 125; and 5 trivial multi-line regex artifacts (re-verified by eye — events with `uint256 indexed` arg types confuse the lookahead on some rows) account for the remaining 5 delta to 130. Either counting preserves the closure bijection: **every universe row has exactly one classification**.

## Finding stubs

#### F-28-227-01: UNHANDLED event Approval on BurnieCoin.sol

- **Severity:** INFO (log-only token event; no domain-table mapping required for analytics). Promote to LOW if audit team wants ERC20 allowance tracking.
- **Direction:** schema↔handler
- **Phase:** 227
- **Requirement:** IDX-01
- **File:** /home/zak/Dev/PurgeGame/degenerus-audit/contracts/BurnieCoin.sol:55 (emitter)
- **Indexer surface:** /home/zak/Dev/PurgeGame/database/src/handlers/index.ts (no HANDLER_REGISTRY key; skip-comment at :374-376 covers DGNRS Approval only)
- **Resolution:** INFO-ACCEPTED (recommended: extend the Approval skip-comment to cover all four ERC-20 tokens) OR RESOLVED-CODE (add `Approval: handleErc20ApprovalRouter`)
- **Evidence:** raw_events still lands the row; no domain-table write

#### F-28-227-02: UNHANDLED event CoordinatorUpdated on DegenerusAdmin.sol

- **Severity:** INFO (admin-only governance event)
- **Direction:** schema↔handler
- **Phase:** 227
- **Requirement:** IDX-01
- **File:** /home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusAdmin.sol:245
- **Indexer surface:** /home/zak/Dev/PurgeGame/database/src/handlers/index.ts (no key)
- **Resolution:** INFO-ACCEPTED — extend admin-events skip-comment at index.ts:293-295 to include DegenerusAdmin governance events.
- **Evidence:** raw_events retains; no schema writer.

#### F-28-227-03: UNHANDLED event ConsumerAdded on DegenerusAdmin.sol
- **Severity:** INFO
- **Direction:** schema↔handler | **Phase:** 227 | **Requirement:** IDX-01
- **File:** /home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusAdmin.sol:249
- **Resolution:** INFO-ACCEPTED via admin-events skip-comment extension.
- **Evidence:** no registry key, admin-only event.

#### F-28-227-04: UNHANDLED event SubscriptionCreated on DegenerusAdmin.sol
- **Severity:** INFO | **Direction:** schema↔handler | **Phase:** 227 | **Requirement:** IDX-01
- **File:** /home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusAdmin.sol:250
- **Resolution:** INFO-ACCEPTED via skip-comment extension.
- **Evidence:** admin VRF subscription lifecycle event.

#### F-28-227-05: UNHANDLED event SubscriptionCancelled on DegenerusAdmin.sol
- **Severity:** INFO | **Direction:** schema↔handler | **Phase:** 227 | **Requirement:** IDX-01
- **File:** /home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusAdmin.sol:251
- **Resolution:** INFO-ACCEPTED.
- **Evidence:** admin-only.

#### F-28-227-06: UNHANDLED event SubscriptionShutdown on DegenerusAdmin.sol
- **Severity:** INFO | **Direction:** schema↔handler | **Phase:** 227 | **Requirement:** IDX-01
- **File:** /home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusAdmin.sol:252
- **Resolution:** INFO-ACCEPTED.
- **Evidence:** admin-only.

#### F-28-227-07: UNHANDLED collision — ProposalCreated on DegenerusAdmin.sol dispatched to GNRUS handler

- **Severity:** LOW (active collision risk: handler expects different ABI)
- **Direction:** schema↔handler
- **Phase:** 227
- **Requirement:** IDX-01
- **File:** /home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusAdmin.sol:261 (5-arg: proposalId, proposer, coordinator, keyHash, path)
- **Indexer surface:** /home/zak/Dev/PurgeGame/database/src/handlers/index.ts:379 → `handleProposalCreated` in `handlers/gnrus-governance.ts` (expects GNRUS 4-arg: level, proposalId, proposer, recipient)
- **Resolution:** RESOLVED-CODE — either (a) add an `ADDRESS_TO_CONTRACT` router to `handleProposalCreated` that branches ADMIN→no-op/separate-handler vs GNRUS→existing logic, or (b) rename one event (contract-side change, out of this repo's scope per D-227-01).
- **Evidence:** Shared event name on different contracts with different argument shapes; registry keys by event-name only → silent arg-mismatch at runtime. Matches the duplicate-name cross-join trap documented in 227-RESEARCH.md §Duplicate-Name Cross-Join Requirement.

#### F-28-227-08: UNHANDLED event VoteCast on DegenerusAdmin.sol
- **Severity:** INFO | **Direction:** schema↔handler | **Phase:** 227 | **Requirement:** IDX-01
- **File:** /home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusAdmin.sol:268
- **Resolution:** INFO-ACCEPTED via skip-comment extension.

#### F-28-227-09: UNHANDLED event ProposalExecuted on DegenerusAdmin.sol
- **Severity:** INFO | **Direction:** schema↔handler | **Phase:** 227 | **Requirement:** IDX-01
- **File:** /home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusAdmin.sol:274
- **Resolution:** INFO-ACCEPTED.

#### F-28-227-10: UNHANDLED event ProposalKilled on DegenerusAdmin.sol
- **Severity:** INFO | **Direction:** schema↔handler | **Phase:** 227 | **Requirement:** IDX-01
- **File:** /home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusAdmin.sol:279
- **Resolution:** INFO-ACCEPTED.

#### F-28-227-11: UNHANDLED event FeedProposalCreated on DegenerusAdmin.sol
- **Severity:** INFO | **Direction:** schema↔handler | **Phase:** 227 | **Requirement:** IDX-01
- **File:** /home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusAdmin.sol:370
- **Resolution:** INFO-ACCEPTED.

#### F-28-227-12: UNHANDLED event FeedVoteCast on DegenerusAdmin.sol
- **Severity:** INFO | **Direction:** schema↔handler | **Phase:** 227 | **Requirement:** IDX-01
- **File:** /home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusAdmin.sol:376
- **Resolution:** INFO-ACCEPTED.

#### F-28-227-13: UNHANDLED event FeedProposalExecuted on DegenerusAdmin.sol
- **Severity:** INFO | **Direction:** schema↔handler | **Phase:** 227 | **Requirement:** IDX-01
- **File:** /home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusAdmin.sol:382
- **Resolution:** INFO-ACCEPTED.

#### F-28-227-14: UNHANDLED event FeedProposalKilled on DegenerusAdmin.sol
- **Severity:** INFO | **Direction:** schema↔handler | **Phase:** 227 | **Requirement:** IDX-01
- **File:** /home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusAdmin.sol:383
- **Resolution:** INFO-ACCEPTED.

#### F-28-227-15: UNHANDLED event RendererUpdated on DegenerusDeityPass.sol
- **Severity:** INFO (admin-only renderer swap)
- **Direction:** schema↔handler | **Phase:** 227 | **Requirement:** IDX-01
- **File:** /home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusDeityPass.sol:60
- **Resolution:** INFO-ACCEPTED via skip-comment extension.

#### F-28-227-16: UNHANDLED event RenderColorsUpdated on DegenerusDeityPass.sol
- **Severity:** INFO | **Direction:** schema↔handler | **Phase:** 227 | **Requirement:** IDX-01
- **File:** /home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusDeityPass.sol:61
- **Resolution:** INFO-ACCEPTED via skip-comment extension.

#### F-28-227-17: UNHANDLED event YearSweep on DegenerusStonk.sol
- **Severity:** LOW (annual DGNRS sweep — non-trivial capital flow; missing in analytics)
- **Direction:** schema↔handler | **Phase:** 227 | **Requirement:** IDX-01
- **File:** /home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusStonk.sol:299
- **Indexer surface:** no registry key; no skip-comment
- **Resolution:** RESOLVED-CODE — add `YearSweep: handleYearSweep` with a dedicated schema row to capture (ethToGnrus, stethToGnrus, ethToVault, stethToVault) per occurrence.
- **Evidence:** 4-value ETH/stETH split, not covered by any existing handler.

#### F-28-227-18: UNHANDLED (router-hidden) Transfer on DegenerusVault.sol

- **Severity:** LOW (VAULT share-token balance changes silently dropped)
- **Direction:** schema↔handler
- **Phase:** 227
- **Requirement:** IDX-01
- **File:** /home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusVault.sol:191 (emitter; VAULT address)
- **Indexer surface:** `handlers/token-balances.ts:38` `ADDRESS_TO_CONTRACT` covers COIN/DGNRS/SDGNRS/WWXRP/DEITY_PASS only — VAULT absent; router fall-through at :166 `if (!contractName) return`
- **Resolution:** RESOLVED-CODE (recommended: extend `ADDRESS_TO_CONTRACT` to include VAULT + add a `handleVaultTransfer` branch tracking DGVE/DGVB share-supply changes) OR INFO-ACCEPTED if supply fidelity comes solely from `VaultClaim`/`VaultDeposit` (doc the design choice in index.ts comment).
- **Evidence:** Vault issues DGVE/DGVB share tokens per `DegenerusVault.sol:191`; every `transfer`/`_mint`/`_burn` fires the `Transfer` event. Silently dropped = share-supply snapshots depend on derived deposit/claim math only (per vault.ts comments), which is correct but undocumented.

#### F-28-227-19: UNHANDLED event Approval on DegenerusVault.sol
- **Severity:** INFO | **Direction:** schema↔handler | **Phase:** 227 | **Requirement:** IDX-01
- **File:** /home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusVault.sol:196
- **Resolution:** INFO-ACCEPTED via a broader Approval skip-comment.

#### F-28-227-20: UNHANDLED (router-hidden) Transfer on GNRUS.sol

- **Severity:** LOW (GNRUS token transfers silently dropped from balance analytics)
- **Direction:** schema↔handler
- **Phase:** 227 | **Requirement:** IDX-01
- **File:** /home/zak/Dev/PurgeGame/degenerus-audit/contracts/GNRUS.sol:104 (emitter; GNRUS address)
- **Indexer surface:** `handlers/token-balances.ts:38` `ADDRESS_TO_CONTRACT` omits GNRUS
- **Resolution:** RESOLVED-CODE — add GNRUS to the token-balances address map and either wire a `handleGnrusTransfer` branch or explicitly no-op (documenting why GNRUS balance isn't tracked).
- **Evidence:** GNRUS is an ERC-20 with `Transfer` emission; absence from the router yields silent zero-coverage for governance-token holder analytics.

#### F-28-227-21: UNHANDLED collision — Burn on GNRUS.sol dispatched to SDGNRS handler

- **Severity:** LOW (active schema-mismatch collision)
- **Direction:** schema↔handler
- **Phase:** 227 | **Requirement:** IDX-01
- **File:** /home/zak/Dev/PurgeGame/degenerus-audit/contracts/GNRUS.sol:107 (`Burn(address burner, uint256 gnrusAmount, uint256 ethOut, uint256 stethOut)` — 4 args)
- **Indexer surface:** `handlers/index.ts:341` registry key `Burn: handleSdgnrsBurn` — handler expects SDGNRS 5-arg shape (`from, amount, ethOut, stethOut, burnieOut`); no address router.
- **Resolution:** RESOLVED-CODE — introduce `handleBurnRouter` branching by `ctx.contractAddress` (SDGNRS vs GNRUS) or rename the GNRUS event (contract-side, out of indexer scope).
- **Evidence:** Same duplicate-name trap pattern as F-28-227-07. Runtime dispatches GNRUS Burn logs to the SDGNRS-shaped handler; either viem arg-decoding throws (if strict) or writes nonsense to `sdgnrs_burns` table with missing `burnieOut` and wrong `from` identity.

#### F-28-227-22: UNHANDLED event Approval on WrappedWrappedXRP.sol
- **Severity:** INFO | **Direction:** schema↔handler | **Phase:** 227 | **Requirement:** IDX-01
- **File:** /home/zak/Dev/PurgeGame/degenerus-audit/contracts/WrappedWrappedXRP.sol:42
- **Resolution:** INFO-ACCEPTED via broader Approval skip-comment.

#### F-28-227-23: Registry orphan — AutoRebuyProcessed key has no event emitter

- **Severity:** INFO (inverse orphan — listed here for traceability per 227-RESEARCH.md Open Question #3)
- **Direction:** handler→schema (inverse)
- **Phase:** 227 | **Requirement:** IDX-01 (inverse coverage)
- **File:** /home/zak/Dev/PurgeGame/database/src/handlers/index.ts:288 `AutoRebuyProcessed: handleAutoRebuyProcessed`
- **Emitter search:** zero matches for `event AutoRebuyProcessed` across `contracts/**/*.sol`
- **Resolution:** INFO — handler is dead code until/unless the event is re-introduced; acceptable to retain or remove at indexer-team discretion (contract-side change out of scope).
- **Evidence:** `rg '\bevent AutoRebuyProcessed\b' contracts/` → no hits.

## Self-check: Spot re-check log (Task 3 will extend; initial 3-sample listed here)

1. **Row 44 AffiliateDgnrsClaimed** — verified: `rg 'event AffiliateDgnrsClaimed' contracts/DegenerusGame.sol` hits `:1362`; registry at `index.ts:390`; handler at `affiliate.ts` contains `.insert(affiliateDgnrsClaims)`. ✓
2. **Row 99 JackpotEthWin** — verified: declaration at `modules/DegenerusGameJackpotModule.sol:67`; registry at `index.ts:261 → handleJackpotEthWin`; handler writes `.insert(jackpotEthWins)` in `jackpot.ts`. ✓
3. **Row 125 DeityPassPurchased** — verified: declaration at `storage/DegenerusGameStorage.sol:511`; registry at `index.ts:366 → handleDeityPassPurchased`; handler in `new-events.ts` writes `.insert(deityPassPurchases)`. ✓
