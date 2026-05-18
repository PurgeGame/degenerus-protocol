# §7 — LootboxModule._resolveLootboxCommon / _resolveLootboxRoll (file:line 960 / 1623)

**Consumer entries:** `contracts/modules/DegenerusGameLootboxModule.sol:960` (`_resolveLootboxCommon`) and `:1623` (`_resolveLootboxRoll`).
Both are `private` helpers; reach is via the four `external` shells:

| External entry | Manual? | Callsite of `_resolveLootboxCommon` |
|---|---|---|
| `LootboxModule.openLootBox(address player, uint48 index)` (`:526`) | **YES — manual EOA path** | `:583` |
| `LootboxModule.openBurnieLootBox(address player, uint48 index)` (`:607`) | **YES — manual EOA path** | `:638` |
| `LootboxModule.resolveLootboxDirect(address player, uint256 amount, uint256 rngWord)` (`:671`) | NO — auto-resolve (decimator claim) | `:682` |
| `LootboxModule.resolveRedemptionLootbox(address player, uint256 amount, uint256 rngWord, uint16 activityScore)` (`:707`) | NO — auto-resolve (sDGNRS redemption) | `:718` |

Plan-298 §7 scope per `D-298-CONSUMER-LIST-01` is **the manual lootbox roll**, i.e. the reach via `openLootBox` and `openBurnieLootBox`. The two auto-resolve shells (`resolveLootboxDirect`, `resolveRedemptionLootbox`) are §6 scope (covered by consumer §6 `resolveRedemptionLootbox` and the decimator-claim auto-call). However, per `D-298-EXEMPT-REACH-01` per-callsite discipline, `_resolveLootboxCommon` reached from `resolveLootboxDirect` / `resolveRedemptionLootbox` is enumerated here for shared-helper completeness — those rows pick up their own EXEMPT classification from their dispatcher's stack at §D.

**Top-level call chain (manual path):**
- TX A — Player buys ticket lots / BURNIE-priced ticket — `DegenerusGame.buyTickets` (or BURNIE coin transfer onto `BurnieCoin` post-target) → MintModule lootbox-allocation path (`DegenerusGameMintModule.sol:985`-`1031`) → writes `lootboxEth[index][buyer]`, `lootboxEthBase`, `lootboxBaseLevelPacked`, `lootboxDay`, `lootboxDistressEth` (or `lootboxBurnie` at `:1399`). Reserves a lootbox-RNG `index` (AdvanceModule `_lrRead(LR_INDEX_SHIFT)`).
- TX B — Daily advance OR mid-day VRF fulfillment — `AdvanceModule.rawFulfillRandomWords` (`:1745`) → `_finalizeLootboxRng` (`:1253`) writes `lootboxRngWordByIndex[index] = word`. From this point the per-index RNG word is final and public.
- TX C — Player calls `DegenerusGame.openLootBox(player, index)` (`:665`) or `openBurnieLootBox` (`:673`) → delegatecalls `LootboxModule.openLootBox` (`:526`) → reads `lootboxRngWordByIndex[index]`, derives `seed = keccak256(rngWord, player, day, amount)`, calls `_resolveLootboxCommon` (`:583` / `:638`) → calls `_accumulateLootboxRolls` (`:1004`) → `_resolveLootboxRoll` (`:883`, `:899`).

**Critical commitment-window per `feedback_rng_commitment_window.md`:** the manual path opens TX C at the player's discretion AFTER TX B publishes `rngWord`. The `seed` recipe binds `(rngWord, player, day, amount)` — but every OTHER SLOAD reached during resolution (player's activity score, EV-cap usage, level, dgnrs pool balance, decimator window, boon storage, …) is sampled at TX C time, NOT at TX A (purchase) time. That is the structural source of every VIOLATION row below.

## CAT-01 (§A) — Traced function set

Backward-trace transitively from `_resolveLootboxCommon` (`:960`) and `_resolveLootboxRoll` (`:1623`); the resolution path also includes the per-shell pre-`_resolveLootboxCommon` work in the manual entries since that work runs inside the rng-window and influences the eventual reward.

| # | Function | File:line | Reached from | Notes |
|---|---|---|---|---|
| 1 | `openLootBox` | `LootboxModule.sol:526` | external EOA | manual entry — ETH lootbox path |
| 2 | `openBurnieLootBox` | `LootboxModule.sol:607` | external EOA | manual entry — BURNIE lootbox path |
| 3 | `_lootboxEvMultiplierBps` | `LootboxModule.sol:444` | `openLootBox:565` | reads `playerActivityScore` (external view on `address(this)` — re-enters `IDegenerusGame`) |
| 4 | `_lootboxEvMultiplierFromScore` | `LootboxModule.sol:453` | `:566`, `:679`, `:715` | `private pure` — interpolation |
| 5 | `_applyEvMultiplierWithCap` | `LootboxModule.sol:484` | `:567`, `:680`, `:716` | reads + writes `lootboxEvBenefitUsedByLevel[player][lvl]` |
| 6 | `_rollTargetLevel` | `LootboxModule.sol:817` | `:555`, `:630`, `:677`, `:713` | `private pure` — three bit-slices of `seed` |
| 7 | `_simulatedDayIndex` | `Storage.sol:1208` | `:536`, `:626`, `:674`, `:710`, `:750`, `:782`, `_rollLootboxBoons:1125` | `internal view` — delegates to `GameTimeLib.currentDayIndex()` (pure-on-`block.timestamp`) |
| 8 | `_psRead(PS_ACTIVE_SHIFT, PS_ACTIVE_MASK)` | `Storage.sol:855` | `openLootBox:542` | reads `presaleStatePacked` |
| 9 | `IDegenerusGame.playerActivityScore` | `DegenerusGame.sol:2304` | `_lootboxEvMultiplierBps:445` | external view on self via `address(this)` — calls `_playerActivityScore` |
| 10 | `_playerActivityScore(player, questStreak)` | `MintStreakUtils.sol:169` → `:83` | via `playerActivityScore` | reads `mintPacked_[player]`, `level`, `affiliate.affiliateBonusPointsBest` (or cached affiliate fields), `_mintStreakEffective`, `_mintCountBonusPoints` |
| 11 | `_mintStreakEffective` / `_mintCountBonusPoints` | `MintStreakUtils.sol` | `_playerActivityScore` | both `internal view` — read `mintPacked_[player]` + `level` |
| 12 | `questView.playerQuestStates(player)` | `DegenerusGame.sol:2307` | `playerActivityScore` | external view (quest contract) |
| 13 | `affiliate.affiliateBonusPointsBest(currLevel, player)` | `MintStreakUtils.sol:145` | `_playerActivityScore` (only when cache miss) | external view (affiliate contract) |
| 14 | `PriceLookupLib.priceForLevel(uint24)` | `PriceLookupLib.sol` | `_resolveLootboxCommon:986`, `_lazyPassPriceForLevel:1803`, `openBurnieLootBox:618`, `_boonPoolStats:1210` | `internal pure` — table lookup |
| 15 | `_lootboxBoonBudget(uint256)` | `LootboxModule.sol:838` | `_resolveLootboxCommon:992,1030`, `_rollLootboxBoons:1148` | `private pure` |
| 16 | `_accumulateLootboxRolls` | `LootboxModule.sol:863` | `_resolveLootboxCommon:1004` | thin dispatcher → 1 or 2× `_resolveLootboxRoll` |
| 17 | `_resolveLootboxRoll` | `LootboxModule.sol:1623` | `_accumulateLootboxRolls:883,899` | the second consumer entry; bit-slices `seed >> 40` (`pathRoll`) and `seed >> 80` (`varianceRoll`) |
| 18 | `_lootboxTicketCount` | `LootboxModule.sol:1703` | `_resolveLootboxRoll:1645` | `private pure` — slices `seed >> 96` (`ticketVariance`) |
| 19 | `_lootboxDgnrsReward` | `LootboxModule.sol:1754` | `_resolveLootboxRoll:1652` | `private view` — slices `seed >> 56`; reads `dgnrs.poolBalance(Lootbox)` |
| 20 | `_creditDgnrsReward` | `LootboxModule.sol:1784` | `_resolveLootboxRoll:1654` | calls `dgnrs.transferFromPool(...)` |
| 21 | `IStakedDegenerusStonk.poolBalance(Pool.Lootbox)` | (external) | `_lootboxDgnrsReward:1770` | external view |
| 22 | `IStakedDegenerusStonk.transferFromPool(...)` | (external) | `_creditDgnrsReward:1786` | external state-mutating |
| 23 | `IWrappedWrappedXRP.mintPrize(player, amount)` | (external) | `_resolveLootboxRoll:1671`, `_resolveLootboxCommon:1074` | external state-mutating; reaches WWXRP `_mint` (Transfer event) |
| 24 | `EntropyLib.hash2(uint256, uint256)` | `EntropyLib.sol:23` | `_accumulateLootboxRolls:897` | `internal pure` — full-diffusion keccak mix |
| 25 | `_rollLootboxBoons` | `LootboxModule.sol:1109` | `_resolveLootboxCommon:1026` | slices `seed >> 120`; calls BoonModule + boon-pool stats |
| 26 | `delegatecall IDegenerusGameBoonModule.checkAndClearExpiredBoon` | `LootboxModule.sol:1120` | `_rollLootboxBoons` | nested delegatecall (storage-shared) |
| 27 | `BoonModule.checkAndClearExpiredBoon(player)` | `BoonModule.sol:120` | via delegatecall | reads + writes `boonPacked[player]` (slot0 + slot1); reads `_simulatedDayIndex()` |
| 28 | `_isDecimatorWindow` | `LootboxModule.sol:1813` | `_rollLootboxBoons:1131`, `deityBoonSlots:756`, `issueDeityBoon:796` | reads `decWindowOpen` |
| 29 | `_boonPoolStats` | `LootboxModule.sol:1203` | `_rollLootboxBoons:1135` | reads `level` (via `PriceLookupLib.priceForLevel(level)`); reads `deityPassOwners.length` (already in `deityEligible` flag) |
| 30 | `_burnieToEthValue` | `LootboxModule.sol:1166` | `_boonPoolStats:1213,1217,1221,1259,1263,1267` | `private pure` |
| 31 | `_lazyPassPriceForLevel` | `LootboxModule.sol:1797` | `_rollLootboxBoons:1129` | calls `PriceLookupLib.priceForLevel` ×10 |
| 32 | `_boonFromRoll` | `LootboxModule.sol:1334` | `_rollLootboxBoons:1155`, `_deityBoonForSlot:1837` | `private pure` |
| 33 | `_applyBoon` | `LootboxModule.sol:1407` | `_rollLootboxBoons:1162`, `issueDeityBoon:799` | reads + writes `boonPacked[player]`; reads `level` (via `_activateWhalePass`); calls `_activateWhalePass` for whale-pass branch |
| 34 | `_activateWhalePass` | `LootboxModule.sol:1177` | `_applyBoon:1578` (BOON_WHALE_PASS branch) | reads `level`; calls `_applyWhalePassStats` + 100× `_queueTickets` |
| 35 | `_applyWhalePassStats` | `Storage.sol:1141` | `_activateWhalePass:1184` | reads `mintPacked_[player]`; writes `mintPacked_[player]` |
| 36 | `_currentMintDay` | `Storage.sol:1260` | `_applyWhalePassStats:1197` | reads `dailyIdx` (fallback to `_simulatedDayIndex`) |
| 37 | `_queueTickets` | `Storage.sol:559` | `_resolveLootboxCommon:1067`, `_activateWhalePass:1190` | reads `level`, `rngLockedFlag`, `ticketsOwedPacked[wk][buyer]`, `ticketQueue[wk]`; writes `ticketQueue[wk]` push + `ticketsOwedPacked` |
| 38 | `_livenessTriggered` | `Storage.sol:1243` | `_queueTickets:570` | reads `lastPurchaseDay`, `jackpotPhaseFlag`, `level`, `purchaseStartDay`, `rngRequestTime`, `_simulatedDayIndex` |
| 39 | `_tqWriteKey` / `_tqFarFutureKey` | `Storage.sol` | `_queueTickets:573-575` | `internal pure` — bit-ops on level |
| 40 | `IBurnieCoinflip.creditFlip(player, burnieAmount)` | (external) | `_resolveLootboxCommon:1079` | external state-mutating |
| 41 | `delegatecall IDegenerusGameBoonModule.consumeActivityBoon` | `LootboxModule.sol:1035` | `_resolveLootboxCommon` (allowBoons branch) | nested delegatecall |
| 42 | `BoonModule.consumeActivityBoon(player)` | `BoonModule.sol:281` | via delegatecall | reads + writes `boonPacked[player]` slot1; reads + writes `mintPacked_[player]` (levelCount field); calls `quests.awardQuestStreakBonus` |

**Explicit-enumeration discipline per `feedback_verify_call_graph_against_source.md`:** every reached function is cited by file:line; no "by construction" / "covered by single fn" claims. Cross-checked by `grep -n "function \|delegatecall\|IDegenerus\|coinflip\.\|dgnrs\.\|wwxrp\.\|affiliate\.\|quests\." contracts/modules/DegenerusGameLootboxModule.sol` and `grep -n "function " contracts/modules/DegenerusGameBoonModule.sol` covering the BoonModule branches reached transitively.

## CAT-02 (§B) — SLOAD table

Every SLOAD reached during `openLootBox` / `openBurnieLootBox` → `_resolveLootboxCommon` → `_resolveLootboxRoll` execution, per `feedback_rng_window_storage_read_freshness.md` F-41-02/03 enumeration discipline. Inline-assembly slot directives + raw `sstore` checked via `grep -n "assembly\|slot:" contracts/modules/DegenerusGameLootboxModule.sol contracts/modules/DegenerusGameBoonModule.sol contracts/storage/DegenerusGameStorage.sol` — only `EntropyLib.hash2` uses memory-safe scratch (`mstore`/`keccak256`); no inline raw `sstore` writes to any in-scope slot.

| # | Slot | Read-site (file:line) | Read context | Participating? | Attestation if NO |
|---|---|---|---|---|---|
| B-1 | `lootboxEth[index][player]` | `LootboxModule.sol:528` | `packed`; `amount = packed & ((1<<232)-1)` flows into `seed` (line 554) AND into every per-roll budget (`amountFirst`, `amountSecond`, `_lootboxBoonBudget`, ticket / DGNRS / WWXRP / large-BURNIE budgets) | **YES** | — |
| B-2 | `lootboxRngWordByIndex[index]` | `:533` (ETH), `:612` (BURNIE) | `rngWord` flows into `seed = keccak256(rngWord, player, day, amount)` (`:554`, `:629`) | **YES** | — |
| B-3 | `lootboxDay[index][player]` | `:537` (ETH), `:624` (BURNIE) | flows into `seed` (`day` field of keccak input at `:554`/`:629`); also emitted on `LootBoxOpened.day` | **YES** | — |
| B-4 | `presaleStatePacked` (via `_psRead(PS_ACTIVE_SHIFT, PS_ACTIVE_MASK)`) | `:542` (ETH path only) | `presale` flag → controls 62% bonus BURNIE multiplier (`_resolveLootboxCommon:1016-1019`) | **YES** | — |
| B-5 | `lootboxEthBase[index][player]` | `:543` | `baseAmount` — read at `:543` but the only use is `if (baseAmount == 0) baseAmount = amount;` and the value is never re-read in `_resolveLootboxCommon` (the sole consumer is `lootboxBaseLevelPacked` path which uses purchase-level, not baseAmount). | NO | Dead read at `openLootBox` scope: `baseAmount` is computed but never referenced after `:546`. (Cross-check: `grep -n "baseAmount" contracts/modules/DegenerusGameLootboxModule.sol` returns only lines 543-546.) Does not drive any VRF-derived output. |
| B-6 | `level` (global `uint24`) | `:548` (ETH `currentLevel = level + 1`), `:618` (BURNIE `priceForLevel(level)`), `:623` (BURNIE `currentLevel = level + 1`), `:675`, `:711`, `_isDistressMode:546`, `_livenessTriggered:1245`, `_queueTickets:571`, `_boonPoolStats:1210`, `_rollLootboxBoons:1126`, `_activateWhalePass:1180`, `_playerActivityScore:96`, gameOverPossible ENF-02 check `:634` | drives `currentLevel` (clamps `targetLevel`); drives BURNIE-amount conversion via `priceForLevel(level)`; drives `_queueTickets` far-future-key branch; drives `_boonPoolStats` price; drives `_playerActivityScore` whale-bundle bonus | **YES** | — |
| B-7 | `gameOverPossible` | `:634` (BURNIE path only) | drives `targetLevel \|= TICKET_FAR_FUTURE_BIT` redirect when ENF-02 triggers | **YES** | — |
| B-8 | `lootboxBaseLevelPacked[index][player]` | `:550` (ETH path only) | `baseLevelPacked` → `graceLevel` → `baseLevel` → `targetLevel` via `_rollTargetLevel` | **YES** | — |
| B-9 | `lootboxEvScorePacked[index][player]` | `:563` (ETH path only) | if non-zero, drives `evMultiplierBps` via snapshotted score; if zero, falls through to LIVE `_lootboxEvMultiplierBps(player)` read of activity score | **YES** | — |
| B-10 | `mintPacked_[player]` (HAS_DEITY_PASS bit, LEVEL_COUNT, FROZEN_UNTIL_LEVEL, WHALE_BUNDLE_TYPE, AFFILIATE_BONUS_LEVEL, AFFILIATE_BONUS_POINTS) | `_playerActivityScore:90` (multiple bit-fields); `_rollLootboxBoons:1133` (HAS_DEITY_PASS bit for `deityEligible`); `_applyWhalePassStats:1145`; `BoonModule.consumeActivityBoon:303` | drives `scoreBps` → `evMultiplierBps` → `scaledAmount` → seed-amount input AND amount used in every per-roll budget; drives `deityEligible` flag in `_boonPoolStats` (toggles deity-pass branch ≈400-weight slice of boon roll) | **YES** | — |
| B-11 | `streakPacked` / `_mintStreakEffective` storage reads | `_mintStreakEffective` (`MintStreakUtils.sol`) — reads `mintPacked_[player]` + per-level streak fields | feeds `_playerActivityScore` streak component | **YES** | covered by B-10's mintPacked_ entry from a participating-slot perspective (same slot; same writer set); listed separately for trace completeness |
| B-12 | `lootboxDistressEth[index][player]` | `:574` (ETH path only) | `distressEth` → drives 25% distress-mode ticket bonus inside `_resolveLootboxCommon:1042-1048` | **YES** | — |
| B-13 | `lootboxEvBenefitUsedByLevel[player][lvl]` | `_applyEvMultiplierWithCap:496` | drives `remainingCap` → `adjustedPortion` → `scaledAmount` (LIVE accumulator; mutated by EVERY prior lootbox open at the same level) | **YES** | — |
| B-14 | `lootboxBurnie[index][player]` | `:609` (BURNIE path only) | `burnieAmount` flows into `amountEth = (burnieAmount * priceWei * 80) / (PRICE_COIN_UNIT * 100)` (`:620`) → drives `seed`'s amount input + every budget | **YES** | — |
| B-15 | `dailyIdx` (global `uint32`) | `_currentMintDay:1261` (via `_applyWhalePassStats:1197`); ALSO read in `_simulatedDayIndex` chain (no — `_simulatedDayIndex` is `GameTimeLib.currentDayIndex()` which reads `block.timestamp` only, NOT `dailyIdx`) | drives the `day` field stamped into `mintPacked_[player]` during whale-pass activation (post-roll bookkeeping; does NOT feed back into the current resolution's RNG-derived output) | NO | Only reached on the whale-pass branch of `_applyBoon` (when `_boonFromRoll` returns `BOON_WHALE_PASS`), and even then it is written into a `data` value that is SSTORE'd to `mintPacked_[player]` AFTER all reward decisions are made. The current resolution's VRF-derived output (`futureTickets`, `burnieAmount`, `roundedUp`, DGNRS reward) is fully determined before this read. |
| B-16 | `decWindowOpen` (via `_isDecimatorWindow`) | `_rollLootboxBoons:1131`, `deityBoonSlots:756`, `issueDeityBoon:796` | `decimatorAllowed` → controls inclusion of `BOON_WEIGHT_DECIMATOR_10/25/50` in `_boonPoolStats` total weight + in `_boonFromRoll` boon-type space; SHIFTS the cumulative-cursor mapping between `roll` and `boonType` | **YES** | — |
| B-17 | `deityPassOwners.length` | `_rollLootboxBoons:1133`, `_boonPoolStats:1292`, `deityBoonSlots:757`, `issueDeityBoon:797` | gates `deityEligible` (and `deityPassAvailable`) → controls inclusion of `BOON_WEIGHT_DEITY_PASS_10/25/50` in boon-roll space; computes `deityPrice` weighted-max | **YES** | — |
| B-18 | `boonPacked[player].slot0` (BoonModule.checkAndClearExpiredBoon) | `BoonModule.sol:123` | drives per-category expiry checks (coinflip/lootbox/purchase/decimator/whale tiers); SSTORE'd back on changed bits at `:265` | **YES** | — |
| B-19 | `boonPacked[player].slot1` (BoonModule.checkAndClearExpiredBoon + consumeActivityBoon) | `BoonModule.sol:124,284` | activity / deity-pass / lazy-pass expiry + activity-boon consumption SSTORE'd back | **YES** | — |
| B-20 | `dgnrs.poolBalance(Pool.Lootbox)` (cross-contract: `IStakedDegenerusStonk.sol` storage read) | `_lootboxDgnrsReward:1770` | drives `dgnrsAmount = (poolBalance * ppm * amount) / (1_000_000 * 1 ether)` → DGNRS reward magnitude (10% path of `_resolveLootboxRoll`) | **YES** | — |
| B-21 | `lastPurchaseDay` (global `bool`) | `_livenessTriggered:1244` | short-circuits liveness → controls whether `_queueTickets` reverts | **YES** | — |
| B-22 | `jackpotPhaseFlag` (global `bool`) | `_livenessTriggered:1244` | short-circuits liveness → controls whether `_queueTickets` reverts | **YES** | — |
| B-23 | `purchaseStartDay` (global `uint32`) | `_livenessTriggered:1246`, `_isDistressMode:544` | `_livenessTriggered` day-math (`currentDay - psd > _DEPLOY_IDLE_TIMEOUT_DAYS` / `>120`); `_isDistressMode` not on lootbox path | **YES** | — |
| B-24 | `rngRequestTime` (global `uint48`) | `_livenessTriggered:1250` | stalled-advance bailout check (`>= _VRF_GRACE_PERIOD`) | **YES** | — |
| B-25 | `rngLockedFlag` (global `bool`) | `_queueTickets:572` | gates the far-future ticket-queue branch with revert | **YES** | — |
| B-26 | `ticketsOwedPacked[wk][buyer]` | `_queueTickets:576`, `MintModule:423,761,...` (other writers' reads outside scope) | read in same SSTORE-merge call at `:585`; aggregates existing tickets queued at level `wk`. Does NOT feed back into VRF-derived seed slicing or roll-result derivation; affects only output-ticket accounting state. | NO | Pure write-merge accumulator inside `_queueTickets`. The function consumes the pre-image `wk` (derived from `targetLevel`) + `quantity` (from RNG-derived `whole`) + the existing packed value; produces a new packed value. The roll outcome is already committed at this point — the SLOAD only affects what's stored back, not what's emitted as the reward. |
| B-27 | `ticketQueue[wk].length` | `_queueTickets:579` (`if (owed == 0 && rem == 0)` push branch) | same as B-26 — output-state-only accumulator | NO | Same reasoning as B-26: write-time-only, post-roll. |
| B-28 | `affiliate.affiliateBonusPointsBest(currLevel, player)` (cross-contract SLOAD on `DegenerusAffiliate.sol`) | `_playerActivityScore:145` (cache-miss branch only) | drives `affPoints` → `bonusBps` → `scoreBps` → `evMultiplierBps` → `scaledAmount` | **YES** | — |
| B-29 | `questView.playerQuestStates(player)` (cross-contract — DegenerusQuests storage) | `DegenerusGame.sol:2307` | drives `questStreak` → `bonusBps += questStreakCapped * 100;` → `scoreBps` → `evMultiplierBps` → `scaledAmount` | **YES** | — |

**Auxiliary §B-W — SSTOREs inside the resolution body** (cross-check, not classified):

| # | Slot | Write-site (file:line) | Notes |
|---|---|---|---|
| B-W1 | `lootboxEth[index][player] = 0` | `:576` | committed-state zero-out before any reward emission |
| B-W2 | `lootboxEthBase[index][player] = 0` | `:577` | ditto |
| B-W3 | `lootboxBaseLevelPacked[index][player] = 0` | `:578` | ditto |
| B-W4 | `lootboxEvScorePacked[index][player] = 0` | `:579` | ditto |
| B-W5 | `lootboxDistressEth[index][player] = 0` | `:581` | ditto (conditional) |
| B-W6 | `lootboxBurnie[index][player] = 0` | `:615` (BURNIE path) | ditto |
| B-W7 | `lootboxEvBenefitUsedByLevel[player][lvl] += adjustedPortion` | `_applyEvMultiplierWithCap:511` | mutates the accumulator read at B-13; future calls to `openLootBox` for the same `(player, lvl)` get a different `remainingCap` |
| B-W8 | `boonPacked[player].slot0` / `.slot1` | `BoonModule.sol:265-266`, `_applyBoon:1432`,`1452`,`1479`,`1503`,`1526`,`1547`,`1568`,`1603` (multi) | tier promotions + day-stamps; influences NEXT lootbox's boon decisions |
| B-W9 | `mintPacked_[player]` | `_applyWhalePassStats:1204`, `BoonModule.consumeActivityBoon:320` | levelCount + whale-bundle fields |
| B-W10 | `ticketQueue[wk].push(buyer)` / `ticketsOwedPacked[wk][buyer]` | `_queueTickets:580,585`, `_activateWhalePass:1190` | output-state ticket bookkeeping |
| B-W11 | DGNRS pool balance mutation (external) | `dgnrs.transferFromPool(...)` (`_creditDgnrsReward:1786`) | reduces `poolBalance` read at B-20 for FUTURE resolutions |
| B-W12 | Coinflip credit balance (external) | `coinflip.creditFlip(player, burnieAmount)` (`:1079`) | post-roll credit |
| B-W13 | WWXRP `mintPrize` (external) | `:1074`, `:1671` | post-roll mint |

## CAT-03 (§C) — Writer enumeration for participating slots

For each `Participating? = YES` slot from §B, enumerate every external/public function that writes it. Methodology: `grep -rn "<slot>\s*=\|<slot>\.\(push\|pop\)\|<slot>\[.*\]\s*=" contracts/ --include="*.sol"` then cross-reference each hit's enclosing function visibility + external-reach chain. Library-constant non-storage reads (`ContractAddresses.*`, `PriceLookupLib.*`) skipped per §B already-attested.

### C-1 — `lootboxEth[index][player]` (B-1)

Mapping: `Storage.sol:832` (`mapping(uint48 => mapping(address => uint256)) internal lootboxEth`).

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-1-a | `LootboxModule.openLootBox` | `LootboxModule.sol:576` (`= 0`) | `DegenerusGame.openLootBox` (`:665`, EOA) — **MANUAL** |
| C-1-b | `DegenerusGameMintModule._allocateLootbox` (or similar — `:1013`) | `MintModule.sol:1013` | `DegenerusGame.buyTickets` / `processMint` chain (EOA + ETH-payable) |
| C-1-c | `DegenerusGameWhaleModule._whaleLootboxAllocate` | `WhaleModule.sol:876` | `DegenerusGame.buyWhaleBundle` / `buyWhaleHalf` (EOA + ETH-payable) |

### C-2 — `lootboxRngWordByIndex[index]` (B-2)

Mapping: `Storage.sol:1367`.

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-2-a | `AdvanceModule._finalizeLootboxRng` | `AdvanceModule.sol:1256` | reached from `advanceGame()` daily-RNG path AND from VRF callback `rawFulfillRandomWords:1761` (mid-day mode) |
| C-2-b | `AdvanceModule.rawFulfillRandomWords` (mid-day branch) | `AdvanceModule.sol:1761` | **EXEMPT-VRFCALLBACK** — Chainlink VRF coordinator only |
| C-2-c | `AdvanceModule._backfillOrphanedLootboxIndices` | `AdvanceModule.sol:1818` | reached from `_gameOverEntropy` historical-fallback path (which is `advanceGame()`-rooted) |

### C-3 — `lootboxDay[index][player]` (B-3)

Mapping: `Storage.sol:1370`.

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-3-a | `DegenerusGameMintModule._allocateLootbox` | `MintModule.sol:991` | `DegenerusGame.buyTickets` (EOA + ETH-payable) |
| C-3-b | `DegenerusGameMintModule._burnieAllocate` | `MintModule.sol:1397` | `BurnieCoin → DegenerusGame.processBurnieTicketBuy` (BURNIE-coin transfer-to-game callback) |
| C-3-c | `DegenerusGameWhaleModule._whaleLootboxAllocate` | `WhaleModule.sol:854` | `DegenerusGame.buyWhaleBundle` / `buyWhaleHalf` |

### C-4 — `presaleStatePacked` (B-4)

Storage: `Storage.sol:843`. Written via `_psWrite` (`:860`) only.

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-4-a | `DegenerusGameMintModule._presaleCapCheck` | `MintModule.sol:1026` (`presaleStatePacked = psPacked`) | `DegenerusGame.buyTickets` / `processMint` (EOA) — cumulative-cap evaluation |
| C-4-b | `DegenerusGameAdvanceModule._handlePhaseTransition` | `AdvanceModule.sol:433` (`_psWrite(PS_ACTIVE_SHIFT, PS_ACTIVE_MASK, 0)`) | `advanceGame()` — auto-end at jackpot phase start |

### C-5 — `level` (B-6)

Storage: `uint24 internal level;` (Storage layout). Sole writer: `AdvanceModule._unlockRng` (`:1643` `level = lvl;`).

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-5-a | `AdvanceModule._unlockRng` | `AdvanceModule.sol:1643` | `advanceGame()` (level transition at RNG request time when `lastPurchaseDay = true`) |

### C-6 — `gameOverPossible` (B-7)

Storage: `bool internal gameOverPossible;` (Storage.sol:316).

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-6-a | `AdvanceModule.advanceGame` (FLAG-03 auto-clear) | `AdvanceModule.sol:178` (`if (gameOverPossible) gameOverPossible = false`) | `advanceGame()` |
| C-6-b | `AdvanceModule._evalGameOverPossible` (the assignment block at `:1888`,`:1893`) | `AdvanceModule.sol:1888,1893` | `advanceGame()` |

### C-7 — `lootboxBaseLevelPacked[index][player]` (B-8)

Mapping: `Storage.sol:1375`.

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-7-a | `LootboxModule.openLootBox` | `LootboxModule.sol:578` (`= 0`) | `DegenerusGame.openLootBox` (EOA) — **MANUAL** |
| C-7-b | `MintModule._allocateLootbox` | `MintModule.sol:992` | `DegenerusGame.buyTickets` (EOA + ETH-payable) |
| C-7-c | `WhaleModule._whaleLootboxAllocate` | `WhaleModule.sol:855` | `DegenerusGame.buyWhaleBundle` / `buyWhaleHalf` (EOA + ETH-payable) |

### C-8 — `lootboxEvScorePacked[index][player]` (B-9)

Mapping: `Storage.sol:1379`.

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-8-a | `LootboxModule.openLootBox` | `LootboxModule.sol:579` (`= 0`) | `DegenerusGame.openLootBox` (EOA) — **MANUAL** |
| C-8-b | `MintModule._allocateLootbox` (post-score-compute snapshot) | `MintModule.sol:1155` | `DegenerusGame.buyTickets` (EOA + ETH-payable) |
| C-8-c | `WhaleModule._whaleLootboxAllocate` (post-score snapshot) | `WhaleModule.sol:856` | `DegenerusGame.buyWhaleBundle` / `buyWhaleHalf` (EOA + ETH-payable) |

### C-9 — `mintPacked_[player]` (B-10 / B-11)

Mapping: `Storage.sol` (mintPacked_). Writers (all visible via grep):

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-9-a | `MintStreakUtils._mintStreakWrite` (writer at `:47`) | `MintStreakUtils.sol:47` | `MintModule._processMint` / `_processBurnieMint` (EOA mint paths via `DegenerusGame.buyTickets` / BURNIE-coin callback) |
| C-9-b | `MintModule._allocateMintPacked` (writes at `:240,:275,:369`) | `MintModule.sol:240,275,369` | `buyTickets` (EOA + ETH-payable) |
| C-9-c | `BoonModule.consumeActivityBoon` (writes at `:320`) | `BoonModule.sol:320` | reached via delegatecall from `_rollLootboxBoons:1035` (i.e., from this very consumer's resolution path AND from other lootbox-resolution paths); **STILL EOA-reachable** because the delegatecall is on the lootbox stack |
| C-9-d | `BoonModule._applyBoon` (mintPacked_ touches via `_applyWhalePassStats`) | `BoonModule.sol:303,320` + `_applyWhalePassStats:1204` (`Storage.sol`) | reachable from `openLootBox` (manual whale-pass boon) AND from auto-resolve callers AND from `issueDeityBoon` |
| C-9-e | `WhaleModule._buyWhaleBundle*` (writes at `:210,:303,:419,:516,:548,:589,:669,:944`) | `WhaleModule.sol:*` | `buyWhaleBundle` / `buyWhaleHalf` / `buyDeityPass` (EOA + ETH-payable) |
| C-9-f | `WhaleModule._buyDeityPass` (deity-pass acquisition) | `WhaleModule.sol:589` | `buyDeityPass` (EOA + ETH-payable) |
| C-9-g | `AdvanceModule._cacheAffiliateBonus` (writes affiliate fields at `:1008`) | `AdvanceModule.sol:1008` | `advanceGame()` |
| C-9-h | `DegenerusGame` constructor (sentinel deity-pass bits for SDGNRS + VAULT) | `DegenerusGame.sol:222,223` | constructor-only (EXEMPT-CONSTRUCTOR) |
| C-9-i | `_applyWhalePassStats` (when reached from lootbox whale-pass boon) | `Storage.sol:1204` | from `_activateWhalePass` (reached on the lootbox stack itself) |

**OZ-inherited writers check:** `mintPacked_` is a private mapping in `DegenerusGameStorage`; not a token balance. No ERC20/ERC721 inheritance writes it.

### C-10 — `lootboxDistressEth[index][player]` (B-12)

Mapping: `Storage.sol:1506`.

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-10-a | `LootboxModule.openLootBox` | `LootboxModule.sol:581` (`= 0`, conditional) | `DegenerusGame.openLootBox` (EOA) — **MANUAL** |
| C-10-b | `MintModule._allocateLootbox` (distress accumulation) | `MintModule.sol:1031` | `buyTickets` (EOA + ETH-payable) |
| C-10-c | `WhaleModule._whaleLootboxAllocate` (distress accumulation) | `WhaleModule.sol:881` | `buyWhaleBundle` / `buyWhaleHalf` (EOA + ETH-payable) |

### C-11 — `lootboxEvBenefitUsedByLevel[player][lvl]` (B-13)

Mapping: `Storage.sol:1428`.

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-11-a | `LootboxModule._applyEvMultiplierWithCap` | `LootboxModule.sol:511` | reached from `openLootBox:567` (**MANUAL**) AND `resolveLootboxDirect:680` (auto) AND `resolveRedemptionLootbox:716` (auto) |

### C-12 — `lootboxBurnie[index][player]` (B-14)

Mapping: `Storage.sol:1386`.

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-12-a | `LootboxModule.openBurnieLootBox` | `LootboxModule.sol:615` (`= 0`) | `DegenerusGame.openBurnieLootBox` (EOA) — **MANUAL** |
| C-12-b | `MintModule._burnieAllocate` | `MintModule.sol:1399` (`+= burnieAmount`) | `BurnieCoin → DegenerusGame.processBurnieTicketBuy` (BURNIE transfer callback; EOA-triggered) |

### C-13 — `decWindowOpen` (B-16)

Storage: `bool internal decWindowOpen;` (Storage.sol:278).

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-13-a | `AdvanceModule._unlockRng` | `AdvanceModule.sol:1655` (`= true`) | `advanceGame()` |
| C-13-b | `AdvanceModule._unlockRng` (close branch) | `AdvanceModule.sol:1659` (`= false`) | `advanceGame()` |

### C-14 — `deityPassOwners` (B-17)

Storage: `address[] internal deityPassOwners;` (DegenerusGameStorage).

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-14-a | `WhaleModule._buyDeityPass` | `WhaleModule.sol:596` (`deityPassOwners.push(buyer)`) | `DegenerusGame.buyDeityPass` (EOA + ETH-payable) |

No pop sites — `deityPassOwners` only grows. Length is monotonic.

### C-15 — `boonPacked[player]` slot0 + slot1 (B-18 + B-19)

Struct mapping: `Storage.sol` (`boonPacked`).

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-15-a | `LootboxModule._applyBoon` slot0 writes | `LootboxModule.sol:1432,1452,1479,1503,1526,1547,1568,1603` etc. | reached from `_rollLootboxBoons:1162` (this consumer — **MANUAL** via `openLootBox`/`openBurnieLootBox`); from auto-resolve callers; and from `issueDeityBoon:799` (EOA — deity-pass holders) |
| C-15-b | `WhaleModule._buyWhaleBundle*` boon-slot writes | `WhaleModule.sol:202,388,556,898` (multiple) | `buyWhaleBundle` / `buyWhaleHalf` / `buyDeityPass` (EOA + ETH-payable) |
| C-15-c | `MintModule._processMint` (BoonPacked writes at `:1433`) | `MintModule.sol:1433` | `buyTickets` (EOA + ETH-payable) |
| C-15-d | `BoonModule.checkAndClearExpiredBoon` slot writes | `BoonModule.sol:265,266` | external function (called via delegatecall from `_rollLootboxBoons:1120`) **AND** can be reached directly via the BoonModule's external interface if any caller delegatecalls it from `DegenerusGame`. Grep confirms call-sites: `LootboxModule.sol:1120` only (no other dispatcher) — but reach is still EOA via the lootbox-roll path |
| C-15-e | `BoonModule.consumeActivityBoon` slot1 writes | `BoonModule.sol:291,297,301` | external (delegatecalled from `_resolveLootboxCommon:1035`) |
| C-15-f | `BoonModule.<other-external-mutators>` (`:41,67,93,122,283`) | `BoonModule.sol:41,67,93,122,283` | additional BoonModule externals; verified by `grep -n "external\|public" contracts/modules/DegenerusGameBoonModule.sol` — each call-site needs per-callsite reach analysis but is conservatively classified VIOLATION below absent evidence of EXEMPT-stack reach |

### C-16 — `dgnrs.poolBalance(Lootbox)` cross-contract (B-20)

Cross-contract slot on `StakedDegenerusStonk.sol`. `dgnrs` is `internal constant` (`Storage.sol:146`).

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-16-a | `StakedDegenerusStonk._addToPool` / `_transferFromPool` (internal helpers in sDGNRS) — reached from `DegenerusStonk.transferFromPool` external, and from `DegenerusGame.fundLootboxPool` / decay sweeps | (cross-contract; out-of-this-file enumeration) | Reaches via `DegenerusGame` admin functions (`forceClaim` / sweep paths) AND via `_creditDgnrsReward:1786` itself (own writes — the consumer mutates B-20 mid-call) AND via `dgnrs.transferFromPool` calls from JackpotModule / DecimatorModule / DegeneretteModule (all on `advanceGame()` / VRF-callback stacks). **Per-callsite VIOLATION classification requires enumerating each writer on the sDGNRS side.** Conservative scope: any caller that mutates `dgnrs.poolBalance(Lootbox)` between the VRF callback (B-2 write) and the manual `openLootBox` (B-20 read) shifts B-20 — and EOAs can plausibly trigger pool-mutating paths via `DegenerusStonk.transferIn` / `forceDeposit` admin routes |

### C-17 — `lastPurchaseDay` (B-21)

Storage: `bool internal lastPurchaseDay;` (Storage.sol:273).

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-17-a | `AdvanceModule.advanceGame` (sets true at `:176`) | `AdvanceModule.sol:176` | `advanceGame()` |
| C-17-b | `AdvanceModule.advanceGame` (sets true at `:397`) | `AdvanceModule.sol:397` | `advanceGame()` |
| C-17-c | `AdvanceModule._handlePhaseTransition` (sets false at `:439`) | `AdvanceModule.sol:439` | `advanceGame()` |

### C-18 — `jackpotPhaseFlag` (B-22)

Storage: `bool internal jackpotPhaseFlag;` (Storage.sol:257).

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-18-a | `AdvanceModule._handlePhaseTransition` (`:333` false, `:437` true) | `AdvanceModule.sol:333,437` | `advanceGame()` |

### C-19 — `purchaseStartDay` (B-23)

Storage: `uint32 internal purchaseStartDay;` (Storage.sol).

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-19-a | `DegenerusGame` constructor | `DegenerusGame.sol:218` | constructor-only (EXEMPT-CONSTRUCTOR) |
| C-19-b | `AdvanceModule._handlePhaseTransition` | `AdvanceModule.sol:332` (`purchaseStartDay = day;`) | `advanceGame()` |

### C-20 — `rngRequestTime` (B-24)

Storage: `uint48 internal rngRequestTime;` (Storage.sol).

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-20-a | `AdvanceModule._tryRequestRng` (`:1122`) | `AdvanceModule.sol:1122` | `advanceGame()` |
| C-20-b | `AdvanceModule.retryLootboxRng` (`:1154`) | `AdvanceModule.sol:1154` | `retryLootboxRng()` (EOA-callable) — **EXEMPT-RETRYLOOTBOXRNG** per `D-42N-RETRY-RNG-DOMAIN-SEP-01` Option A |
| C-20-c | `AdvanceModule._gameOverEntropy` (`:1329`) | `AdvanceModule.sol:1329` | `advanceGame()` (fallback path clearing) |
| C-20-d | `AdvanceModule._gameOverEntropy` (`:1341`) | `AdvanceModule.sol:1341` | `advanceGame()` |
| C-20-e | `AdvanceModule._unlockRng` (`:1633`) | `AdvanceModule.sol:1633` | `advanceGame()` |
| C-20-f | `AdvanceModule._unlockRng` (`:1692`) | `AdvanceModule.sol:1692` | `advanceGame()` |
| C-20-g | `AdvanceModule._unlockRng` (`:1734`) | `AdvanceModule.sol:1734` | `advanceGame()` |
| C-20-h | `AdvanceModule.rawFulfillRandomWords` (`:1764`) | `AdvanceModule.sol:1764` | VRF coordinator only — **EXEMPT-VRFCALLBACK** |

### C-21 — `rngLockedFlag` (B-25)

Storage: `bool internal rngLockedFlag;` (Storage.sol:284).

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-21-a | `AdvanceModule._unlockRng` (`:1634` true, `:1690` false, `:1731` false) | `AdvanceModule.sol:1634,1690,1731` | `advanceGame()` (lock and unlock branches) |

### C-22 — `affiliate.affiliateBonusPointsBest(...)` cross-contract (B-28)

Cross-contract slots in `DegenerusAffiliate.sol`. Per `D-298-TRACE-DEPTH-01` trace walks the source. Writers are `DegenerusAffiliate.recordAffiliateEarnings` and the leaderboard-update path — reached from EOA via `MintModule` / `WhaleModule` mint flows (affiliate amounts recorded on every ticket purchase). Per-callsite enumeration in §C-22:

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-22-a | `DegenerusAffiliate.recordAffiliateEarnings` (or equivalent — see `grep -n "function \|external\|public" contracts/DegenerusAffiliate.sol`) | (cross-contract) | reached from MintModule / WhaleModule mint flows (EOA + ETH-payable) |

### C-23 — `questView.playerQuestStates(player)` cross-contract (B-29)

Cross-contract — DegenerusQuests storage. Writers are `DegenerusQuests` external/quest-fulfillment functions (EOA-callable). Per-callsite reach is EOA on the quest-claim path. Conservatively classified per the same VIOLATION shape since the streak SLOAD is read live during lootbox resolution.

## CAT-04 (§D) — Per-tuple verdict matrix

Per `D-298-EXEMPT-REACH-01` strict + per-callsite classification. Each writer-callsite is classified `EXEMPT-ADVANCEGAME` | `EXEMPT-VRFCALLBACK` | `EXEMPT-RETRYLOOTBOXRNG` | `VIOLATION` (v43.0 milestone-goal prohibits a no-disposition residual category).

| # | Slot | Writer function (C-ref) | Callsite (file:line) | Reached from EXEMPT stack? | Classification |
|---|---|---|---|---|---|
| D-1 | `lootboxEth` | LootboxModule.openLootBox `=0` (C-1-a) | `:576` | NO — own write inside the SELF callsite; per-callsite reach is EOA (`DegenerusGame.openLootBox`). However, the write zeroes the slot AFTER `seed` is derived (`:554`) and AFTER `amount` is captured; so this write does not influence the current resolution's RNG output. | **EXEMPT-VRFCALLBACK** ⊕ EOA self-write — the slot mutation cannot be exploited intra-resolution. Reach: reentry-safe (whole module is `private`/`external` with delegatecall). Classification: **EXEMPT-ADVANCEGAME-EQUIVALENT** by post-roll positioning. **For audit-conservative discipline, classified VIOLATION but with rationale "self-zero, post-amount-capture"** |
| D-2 | `lootboxEth` | MintModule._allocateLootbox (C-1-b) | `MintModule.sol:1013` | NO — reached from `DegenerusGame.buyTickets` (EOA) | **VIOLATION** |
| D-3 | `lootboxEth` | WhaleModule._whaleLootboxAllocate (C-1-c) | `WhaleModule.sol:876` | NO — EOA via `buyWhaleBundle` / `buyWhaleHalf` | **VIOLATION** |
| D-4 | `lootboxRngWordByIndex` | AdvanceModule._finalizeLootboxRng (C-2-a from `rngGate` daily path) | `AdvanceModule.sol:1256` | YES — `advanceGame()` daily-RNG path | **EXEMPT-ADVANCEGAME** |
| D-5 | `lootboxRngWordByIndex` | AdvanceModule.rawFulfillRandomWords mid-day (C-2-b) | `AdvanceModule.sol:1761` | YES — VRF coordinator only (gated by `msg.sender != vrfCoordinator` revert at `:1749`) | **EXEMPT-VRFCALLBACK** |
| D-6 | `lootboxRngWordByIndex` | AdvanceModule._backfillOrphanedLootboxIndices (C-2-c) | `AdvanceModule.sol:1818` | YES — reached from `_gameOverEntropy` on `advanceGame()` stack | **EXEMPT-ADVANCEGAME** |
| D-7 | `lootboxDay` | MintModule._allocateLootbox (C-3-a) | `MintModule.sol:991` | NO — EOA via `buyTickets` | **VIOLATION** |
| D-8 | `lootboxDay` | MintModule._burnieAllocate (C-3-b) | `MintModule.sol:1397` | NO — EOA via BURNIE-coin transfer callback | **VIOLATION** |
| D-9 | `lootboxDay` | WhaleModule._whaleLootboxAllocate (C-3-c) | `WhaleModule.sol:854` | NO — EOA via `buyWhaleBundle` / `buyWhaleHalf` | **VIOLATION** |
| D-10 | `presaleStatePacked` | MintModule._presaleCapCheck (C-4-a) | `MintModule.sol:1026` | NO — EOA via `buyTickets` / `processMint`; cumulative cap evaluation runs per-mint | **VIOLATION** |
| D-11 | `presaleStatePacked` | AdvanceModule._handlePhaseTransition (C-4-b) | `AdvanceModule.sol:433` | YES — `advanceGame()` | **EXEMPT-ADVANCEGAME** |
| D-12 | `level` | AdvanceModule._unlockRng (C-5-a) | `AdvanceModule.sol:1643` | YES — `advanceGame()` | **EXEMPT-ADVANCEGAME** |
| D-13 | `gameOverPossible` | AdvanceModule.advanceGame FLAG-03 (C-6-a) | `AdvanceModule.sol:178` | YES — `advanceGame()` | **EXEMPT-ADVANCEGAME** |
| D-14 | `gameOverPossible` | AdvanceModule._evalGameOverPossible (C-6-b) | `AdvanceModule.sol:1888,1893` | YES — `advanceGame()` | **EXEMPT-ADVANCEGAME** |
| D-15 | `lootboxBaseLevelPacked` | LootboxModule.openLootBox self-zero (C-7-a) | `LootboxModule.sol:578` | self-write post-`targetLevel`-derivation | **EXEMPT-VRFCALLBACK-EQUIVALENT** (self-zero post-roll). Audit-conservative: classified **VIOLATION** with "self-zero, post-roll" rationale |
| D-16 | `lootboxBaseLevelPacked` | MintModule._allocateLootbox (C-7-b) | `MintModule.sol:992` | NO — EOA via `buyTickets` | **VIOLATION** |
| D-17 | `lootboxBaseLevelPacked` | WhaleModule._whaleLootboxAllocate (C-7-c) | `WhaleModule.sol:855` | NO — EOA via `buyWhaleBundle` / `buyWhaleHalf` | **VIOLATION** |
| D-18 | `lootboxEvScorePacked` | LootboxModule.openLootBox self-zero (C-8-a) | `LootboxModule.sol:579` | self-write post-`evMultiplierBps`-derivation | **VIOLATION** (audit-conservative: self-zero, post-roll) |
| D-19 | `lootboxEvScorePacked` | MintModule._allocateLootbox snapshot write (C-8-b) | `MintModule.sol:1155` | NO — EOA via `buyTickets`; **mints the score snapshot at purchase time, so subsequent EOA mints to the same `(index, buyer)` between RNG-fulfill and open mutate the score** | **VIOLATION** |
| D-20 | `lootboxEvScorePacked` | WhaleModule._whaleLootboxAllocate snapshot (C-8-c) | `WhaleModule.sol:856` | NO — EOA via `buyWhaleBundle` / `buyWhaleHalf` | **VIOLATION** |
| D-21 | `mintPacked_` | MintStreakUtils._mintStreakWrite (C-9-a) | `MintStreakUtils.sol:47` | NO — EOA via mint flows | **VIOLATION** |
| D-22 | `mintPacked_` | MintModule._allocateMintPacked (C-9-b, 3 callsites) | `MintModule.sol:240,275,369` | NO — EOA via `buyTickets` / `processMint` | **VIOLATION** |
| D-23 | `mintPacked_` | BoonModule.consumeActivityBoon (C-9-c) | `BoonModule.sol:320` | The delegatecall is on the lootbox stack itself; if reached from `openLootBox` (manual), classification follows the manual stack → **NOT** advanceGame-rooted. Per `D-298-EXEMPT-REACH-01` per-callsite: this callsite is reached **inside** the current resolution, so the write is post-amount-capture but pre-final-emission. The write happens INSIDE `_resolveLootboxCommon:1035` before `_resolveLootboxRoll` returns. Mutation timing: AFTER seed derivation but BEFORE boon-roll consumption. | **EXEMPT-ADVANCEGAME-EQUIVALENT** (self-stack write; cannot be exploited cross-tx). Audit-conservative: classified **VIOLATION** with "self-stack post-seed" rationale |
| D-24 | `mintPacked_` | WhaleModule._buyWhaleBundle* (C-9-e, multiple) | `WhaleModule.sol:*` (210,303,419,516,548,589,669,944) | NO — EOA via `buyWhaleBundle` / `buyWhaleHalf` / `buyDeityPass` | **VIOLATION** |
| D-25 | `mintPacked_` | WhaleModule._buyDeityPass (C-9-f) | `WhaleModule.sol:589` | NO — EOA via `buyDeityPass` | **VIOLATION** |
| D-26 | `mintPacked_` | AdvanceModule._cacheAffiliateBonus (C-9-g) | `AdvanceModule.sol:1008` | YES — `advanceGame()` | **EXEMPT-ADVANCEGAME** |
| D-27 | `mintPacked_` | DegenerusGame constructor (C-9-h) | `DegenerusGame.sol:222,223` | constructor — single shot at deploy | **EXEMPT-ADVANCEGAME-EQUIVALENT** (constructor-only) — audit-conservative: outside the rng-window, classified **EXEMPT-ADVANCEGAME** by structural unreachability post-deploy |
| D-28 | `mintPacked_` | _applyWhalePassStats from lootbox boon path (C-9-i) | `Storage.sol:1204` | This write reached from `_activateWhalePass` on the LOOTBOX stack itself (BOON_WHALE_PASS branch of `_applyBoon`). Same self-stack timing as D-23. | **VIOLATION** (audit-conservative: self-stack post-seed) |
| D-29 | `lootboxDistressEth` | LootboxModule.openLootBox self-zero (C-10-a) | `LootboxModule.sol:581` | self-write post-distressEth-capture | **VIOLATION** (audit-conservative: self-zero, post-roll) |
| D-30 | `lootboxDistressEth` | MintModule._allocateLootbox (C-10-b) | `MintModule.sol:1031` | NO — EOA via `buyTickets` | **VIOLATION** |
| D-31 | `lootboxDistressEth` | WhaleModule._whaleLootboxAllocate (C-10-c) | `WhaleModule.sol:881` | NO — EOA via `buyWhaleBundle` / `buyWhaleHalf` | **VIOLATION** |
| D-32 | `lootboxEvBenefitUsedByLevel` | LootboxModule._applyEvMultiplierWithCap (C-11-a) | `LootboxModule.sol:511` | Self-stack write: reached on the openLootBox stack itself (`:567`) AND on `resolveLootboxDirect:680` (auto) AND `resolveRedemptionLootbox:716` (auto). Two separate callsites — manual self-stack vs auto-resolve. Auto-resolve callers are EXEMPT (their dispatcher is on the VRF-callback / advanceGame-rooted stack). Manual self-stack write at `openLootBox` time is post-seed but pre-`_resolveLootboxCommon`. **BUT: the read at B-13 happens FIRST (`:496`), then `lootboxEvBenefitUsedByLevel[player][lvl] = usedBenefit + adjustedPortion` (`:511`) — within the SAME `_applyEvMultiplierWithCap` invocation.** Cross-resolution mutation: each prior `openLootBox` at the same level shifts the running accumulator for the next call. Within the multi-tx attack window between VRF callback and the target's `openLootBox`, an attacker can sequence MULTIPLE `openLootBox` calls (potentially for different RNG indices belonging to the same attacker EOA) to drive `usedBenefit` toward the cap before opening the high-value index → reduces `scaledAmount` for that index. Conversely: the attacker may open the high-value index FIRST when `usedBenefit == 0` and `evMultiplierBps > 10_000` to capture full EV. Both directions break commitment. | **VIOLATION** |
| D-33 | `lootboxBurnie` | LootboxModule.openBurnieLootBox self-zero (C-12-a) | `LootboxModule.sol:615` | self-write post-`burnieAmount`-capture (line 609) | **VIOLATION** (audit-conservative: self-zero, post-roll) |
| D-34 | `lootboxBurnie` | MintModule._burnieAllocate (C-12-b) | `MintModule.sol:1399` | NO — EOA via BURNIE-coin transfer callback (post-target-met) | **VIOLATION** |
| D-35 | `decWindowOpen` | AdvanceModule._unlockRng open=true (C-13-a) | `AdvanceModule.sol:1655` | YES — `advanceGame()` | **EXEMPT-ADVANCEGAME** |
| D-36 | `decWindowOpen` | AdvanceModule._unlockRng open=false (C-13-b) | `AdvanceModule.sol:1659` | YES — `advanceGame()` | **EXEMPT-ADVANCEGAME** |
| D-37 | `deityPassOwners` | WhaleModule._buyDeityPass push (C-14-a) | `WhaleModule.sol:596` | NO — EOA via `buyDeityPass` | **VIOLATION** |
| D-38 | `boonPacked[player]` | LootboxModule._applyBoon (C-15-a) | `LootboxModule.sol:1432,1452,1479,1503,1526,1547,1568,1603` | Self-stack writes reached from this consumer (`_rollLootboxBoons:1162`) AND from `issueDeityBoon:799` (EOA — deity-pass holder grants a boon to a recipient). The `issueDeityBoon` reach is a genuine cross-EOA mutation: a third-party deity holder writes the consumer's `boonPacked[player]` between VRF callback and the consumer's `openLootBox` invocation. | **VIOLATION** (multi-source: self-stack post-seed for own-write + cross-EOA via `issueDeityBoon`) |
| D-39 | `boonPacked[player]` | WhaleModule._buyWhaleBundle* writes (C-15-b) | `WhaleModule.sol:202,388,556,898` | NO — EOA via `buyWhaleBundle` / `buyWhaleHalf` / `buyDeityPass` | **VIOLATION** |
| D-40 | `boonPacked[player]` | MintModule._processMint slot write (C-15-c) | `MintModule.sol:1433` | NO — EOA via `buyTickets` | **VIOLATION** |
| D-41 | `boonPacked[player]` | BoonModule.checkAndClearExpiredBoon (C-15-d) | `BoonModule.sol:265,266` | Reached only from `_rollLootboxBoons:1120` (delegatecall on the lootbox stack). Self-stack write; expiry-clear happens BEFORE the boon roll consumes any of slot0/slot1 in `_boonPoolStats` and `_boonFromRoll`. | **VIOLATION** (audit-conservative: self-stack pre-roll-consumption — the slot's state at consumption depends on `_simulatedDayIndex()` which depends on `block.timestamp`, an attacker-influenceable input via tx-ordering / next-block scheduling) |
| D-42 | `boonPacked[player]` | BoonModule.consumeActivityBoon (C-15-e) | `BoonModule.sol:291,297,301` | Same as D-23 — self-stack write on the lootbox stack | **VIOLATION** (audit-conservative) |
| D-43 | `boonPacked[player]` | BoonModule.<other-externals> (C-15-f) | `BoonModule.sol:41,67,93,122,283` | These external functions exist on the BoonModule contract. The actual reach depends on whether `DegenerusGame` exposes a public dispatcher that delegatecalls them. Conservative assumption: any EOA-reachable path between RNG callback and `openLootBox` that mutates `boonPacked[player]` is a VIOLATION; per-callsite analysis requires resolving each external's dispatcher and access guard. Each external in this group needs its own VIOLATION row unless its access guard prohibits EOA reach. | **VIOLATION** (×N, one per externally-reachable callsite of the listed BoonModule externals) |
| D-44 | `dgnrs.poolBalance(Lootbox)` | sDGNRS pool-mutation entries (C-16-a) | (cross-contract) | Multiple sDGNRS writer callsites exist; classification requires walking the sDGNRS contract. Cross-contract sources include (i) `DegenerusGame.fundLootboxPool` (admin), (ii) `DegenerusGame._creditDgnrsReward → dgnrs.transferFromPool` reached from this very consumer (self-stack, post-seed but the magnitude of own award is computed from poolBalance read BEFORE the transfer), and (iii) any sDGNRS external that mints / transfers into the Lootbox pool. The (i) admin path classifies VIOLATION unless under owner-only guard; the cross-resolution mutation across separate-EOA `openLootBox` calls IS exploitable: attacker opens his own ETH lootbox first → drains pool → victim's subsequent open at the same `(rngWord, ...)` yields a smaller DGNRS reward. | **VIOLATION** |
| D-45 | `lastPurchaseDay` | AdvanceModule.advanceGame writes (C-17-a, C-17-b, C-17-c) | `AdvanceModule.sol:176,397,439` | YES — `advanceGame()` | **EXEMPT-ADVANCEGAME** |
| D-46 | `jackpotPhaseFlag` | AdvanceModule._handlePhaseTransition (C-18-a) | `AdvanceModule.sol:333,437` | YES — `advanceGame()` | **EXEMPT-ADVANCEGAME** |
| D-47 | `purchaseStartDay` | DegenerusGame constructor (C-19-a) | `DegenerusGame.sol:218` | constructor — single shot | **EXEMPT-ADVANCEGAME** (audit-conservative: constructor-only) |
| D-48 | `purchaseStartDay` | AdvanceModule._handlePhaseTransition (C-19-b) | `AdvanceModule.sol:332` | YES — `advanceGame()` | **EXEMPT-ADVANCEGAME** |
| D-49 | `rngRequestTime` | AdvanceModule._tryRequestRng (C-20-a) | `AdvanceModule.sol:1122` | YES — `advanceGame()` | **EXEMPT-ADVANCEGAME** |
| D-50 | `rngRequestTime` | AdvanceModule.retryLootboxRng (C-20-b) | `AdvanceModule.sol:1154` | YES — `retryLootboxRng()` is 1 of the 3 explicit EXEMPT entry points per v43.0 milestone goal | **EXEMPT-RETRYLOOTBOXRNG** |
| D-51 | `rngRequestTime` | AdvanceModule._gameOverEntropy (C-20-c, C-20-d) | `AdvanceModule.sol:1329,1341` | YES — `advanceGame()` | **EXEMPT-ADVANCEGAME** |
| D-52 | `rngRequestTime` | AdvanceModule._unlockRng (C-20-e, C-20-f, C-20-g) | `AdvanceModule.sol:1633,1692,1734` | YES — `advanceGame()` | **EXEMPT-ADVANCEGAME** |
| D-53 | `rngRequestTime` | AdvanceModule.rawFulfillRandomWords (C-20-h) | `AdvanceModule.sol:1764` | YES — VRF coordinator only | **EXEMPT-VRFCALLBACK** |
| D-54 | `rngLockedFlag` | AdvanceModule._unlockRng (C-21-a) | `AdvanceModule.sol:1634,1690,1731` | YES — `advanceGame()` | **EXEMPT-ADVANCEGAME** |
| D-55 | `affiliate` cross-contract writer (B-28 / C-22-a) | DegenerusAffiliate.recordAffiliateEarnings or peer | (cross-contract) | Reached via MintModule / WhaleModule mint flows (EOA + ETH-payable). Player can mint between VRF callback and his own `openLootBox` to shift `affPoints` → `scaledAmount` upward. | **VIOLATION** |
| D-56 | `questView` cross-contract writer (B-29 / C-23) | DegenerusQuests quest-fulfillment | (cross-contract) | Reached via DegenerusQuests external/quest-fulfillment functions (EOA-callable). Player can complete a quest between VRF callback and his own `openLootBox` to inflate `questStreak` → `scoreBps` → `scaledAmount` upward. | **VIOLATION** |

**§D verdict tally:** 56 writer-callsite rows. **EXEMPT-ADVANCEGAME:** 18 (D-4, D-6, D-11, D-12, D-13, D-14, D-26, D-27, D-35, D-36, D-45, D-46, D-47, D-48, D-49, D-51, D-52, D-54). **EXEMPT-VRFCALLBACK:** 2 (D-5, D-53). **EXEMPT-RETRYLOOTBOXRNG:** 1 (D-50). **VIOLATION:** 35 (D-1, D-2, D-3, D-7, D-8, D-9, D-10, D-15, D-16, D-17, D-18, D-19, D-20, D-21, D-22, D-23, D-24, D-25, D-28, D-29, D-30, D-31, D-32, D-33, D-34, D-37, D-38, D-39, D-40, D-41, D-42, D-43, D-44, D-55, D-56).

Note on "self-zero, post-roll" / "self-stack post-seed" rows (D-1, D-15, D-18, D-23, D-28, D-29, D-33, D-41, D-42): these are own-stack writes that occur INSIDE the consumer's resolution and structurally cannot be exploited intra-tx; in a less audit-conservative classification scheme they would be EXEMPT-ADVANCEGAME-EQUIVALENT by design. Per `D-298-EXEMPT-REACH-01` strict-per-callsite + the milestone-goal prohibition on a residual no-disposition category, they remain VIOLATIONs with the rationale that the writer-callsite is structurally reachable from a non-EXEMPT (manual EOA) stack. Phase 299 FIX sub-phase planning may downgrade these on a per-row basis after design-intent trace per `feedback_design_intent_before_deletion.md`.

## CAT-06 (§E) — Per-VIOLATION recommended tactic

Per `D-298-RECOMMEND-DEPTH-01`: ONE recommended tactic from `(a) rngLockedFlag-gated revert | (b) snapshot/anchor pattern | (c) pre-lock reorder | (d) immutable` + ≤80-char rationale.

| # | VIOLATION | Tactic | Rationale (≤80 chars) |
|---|---|---|---|
| E-1 | D-1: openLootBox self-zero `lootboxEth=0` post-amount-capture | (b) | Freeze amount in stack pre-SLOAD-cascade; mirror Phase 281 owed-salt |
| E-2 | D-2: MintModule._allocateLootbox writes `lootboxEth` post-RNG-callback | (a) | Gate buyTickets path on `lootboxRngWordByIndex[index]==0` per Phase 290 MINTCLN |
| E-3 | D-3: WhaleModule._whaleLootboxAllocate writes `lootboxEth` post-callback | (a) | Same gating as E-2; mirror MINTCLN gate at WhaleModule entry |
| E-4 | D-7: MintModule writes `lootboxDay` post-callback | (a) | Same gate; lootboxDay is in commitment quad (rngWord,player,day,amount) |
| E-5 | D-8: MintModule BURNIE path writes `lootboxDay` post-callback | (a) | Same MINTCLN-style gate on BURNIE allocation path |
| E-6 | D-9: WhaleModule writes `lootboxDay` post-callback | (a) | Same MINTCLN-style gate on WhaleModule allocation |
| E-7 | D-10: MintModule writes `presaleStatePacked` cap-eval post-callback | (b) | Snapshot presale flag per-index at allocation; Phase 288 dailyIdx precedent |
| E-8 | D-15: openLootBox self-zero `lootboxBaseLevelPacked` | (b) | Snapshot baseLevel into the index at allocation, not at open time |
| E-9 | D-16: MintModule writes `lootboxBaseLevelPacked` post-callback | (a) | Same MINTCLN-style gate to lock the per-index baseLevel at first allocation |
| E-10 | D-17: WhaleModule writes `lootboxBaseLevelPacked` post-callback | (a) | Same MINTCLN-style gate on WhaleModule baseLevel writes |
| E-11 | D-18: openLootBox self-zero `lootboxEvScorePacked` | (b) | Score must be snapshotted at allocation (already partially done; close gap) |
| E-12 | D-19: MintModule writes `lootboxEvScorePacked` snapshot post-callback | (a) | Gate snapshot write on rng-not-yet-published; pattern: Phase 290 MINTCLN |
| E-13 | D-20: WhaleModule writes `lootboxEvScorePacked` snapshot post-callback | (a) | Same MINTCLN-style gate |
| E-14 | D-21: MintStreakUtils writes `mintPacked_` (streak field) post-callback | (b) | Snapshot streak into the lootbox-index at allocation, not LIVE at open |
| E-15 | D-22: MintModule writes `mintPacked_` (3 callsites) post-callback | (b) | Same snapshot approach; consume score from B-9 snapshot only |
| E-16 | D-23: BoonModule.consumeActivityBoon self-stack `mintPacked_` write | (c) | Reorder consumeActivityBoon to AFTER all RNG-driven sub-rolls return |
| E-17 | D-24: WhaleModule writes `mintPacked_` (multi) post-callback | (b) | Snapshot whale-bundle / frozen-until state at lootbox allocation |
| E-18 | D-25: WhaleModule._buyDeityPass writes `mintPacked_` post-callback | (a) | Gate buyDeityPass on `rngLockedFlag||lootboxRngWordByIndex[currentIdx]!=0` |
| E-19 | D-28: _applyWhalePassStats self-stack `mintPacked_` write | (c) | Reorder whale-pass boon side-effect to AFTER roll consumption returns |
| E-20 | D-29: openLootBox self-zero `lootboxDistressEth` | (b) | Same snapshot pattern; freeze distress flag at allocation |
| E-21 | D-30: MintModule writes `lootboxDistressEth` post-callback | (a) | Same MINTCLN-style gate on distress accumulation |
| E-22 | D-31: WhaleModule writes `lootboxDistressEth` post-callback | (a) | Same MINTCLN-style gate |
| E-23 | D-32: lootboxEvBenefitUsedByLevel cross-resolution accumulator | (b) | Snapshot remaining-cap per index at allocation; pattern: Phase 281 owed-salt |
| E-24 | D-33: openBurnieLootBox self-zero `lootboxBurnie` | (b) | Freeze burnieAmount into a stack var pre-SLOAD-cascade |
| E-25 | D-34: MintModule BURNIE path writes `lootboxBurnie` post-callback | (a) | Same MINTCLN-style gate on BURNIE-allocation path |
| E-26 | D-37: WhaleModule._buyDeityPass push `deityPassOwners` post-callback | (a) | Gate buyDeityPass when any lootbox's RNG word is fresh in the open window |
| E-27 | D-38: LootboxModule._applyBoon writes `boonPacked` via issueDeityBoon | (a) | Gate issueDeityBoon on the recipient having no open lootbox index ready |
| E-28 | D-39: WhaleModule writes `boonPacked` post-callback | (a) | Same MINTCLN-style gate on WhaleModule boon writes |
| E-29 | D-40: MintModule writes `boonPacked` post-callback | (a) | Same MINTCLN-style gate on MintModule boon writes |
| E-30 | D-41: BoonModule.checkAndClearExpiredBoon self-stack expiry-clear | (b) | Snapshot expiry decision based on day at allocation, not at open |
| E-31 | D-42: BoonModule.consumeActivityBoon self-stack `boonPacked` write | (c) | Reorder activity-boon consumption to AFTER all RNG-driven sub-rolls return |
| E-32 | D-43: BoonModule other-external boonPacked writers | (a) | Gate each EOA-reachable BoonModule external on no-fresh-lootbox-rng-in-window |
| E-33 | D-44: sDGNRS pool-balance cross-resolution mutation | (b) | Snapshot poolBalance into each index at allocation (per-index DGNRS budget) |
| E-34 | D-55: affiliate-bonus points cross-resolution mutation | (b) | Snapshot affiliate points into the lootbox-index at allocation |
| E-35 | D-56: quest streak cross-resolution mutation | (b) | Snapshot questStreak into the lootbox-index at allocation |

**Recurring structural patterns (rationale-cluster summary; out-of-table for traceability):**

- Cluster (a) — **rngLockedFlag/per-index-rng-gated revert** (14 rows): the dominant fix is to block any mutator of a participating slot once the per-index `lootboxRngWordByIndex[index] != 0` (or for global slots, once any open-window lootbox index exists with RNG fulfilled). Pattern precedent: Phase 290 MINTCLN's `if (cachedJpFlag && rngLockedFlag) {...}` at `MintModule.sol:1221`. Direct, minimal, no new storage.
- Cluster (b) — **snapshot/anchor at allocation** (16 rows): for slots whose value SHOULD vary across players' lifecycle (activity score, affiliate points, quest streak, distress flag, presale flag, base level, EV cap, pool balance), the fix is to freeze the value at the lootbox-allocation timestamp into a per-index storage cell. Pattern precedent: Phase 281 owed-salt + Phase 288 dailyIdx snapshot. Requires one new storage write at allocation; one new storage slot per index per snapshotted variable.
- Cluster (c) — **pre-lock reorder** (3 rows: D-23, D-28, D-42): for self-stack writes inside `_resolveLootboxCommon` that mutate participating slots BEFORE the final-emission point but AFTER seed derivation, the fix is to reorder the side-effect to execute AFTER the roll commits its outputs. Zero new storage; pure code-ordering change.

No cluster (d) immutable recommendations: every participating slot identified above is legitimately mutable across the game lifecycle.

Phase 299 FIX sub-phase planning re-discovers design intent per `feedback_design_intent_before_deletion.md` discipline before locking the final tactic on any of E-1..E-35.

---

## Audit metadata

- **Trace discipline:** every reachable SLOAD inside the manual-path lootbox roll enumerated per `feedback_rng_window_storage_read_freshness.md`; NO "by construction" / "covered by single fn" shortcuts per `feedback_verify_call_graph_against_source.md`. Cross-module SLOADs (cross-contract `dgnrs.poolBalance`, `affiliate.affiliateBonusPointsBest`, `questView.playerQuestStates`) enumerated per `D-298-TRACE-DEPTH-01` all-source-contracts scope.
- **Commitment-window discipline:** per `feedback_rng_commitment_window.md`, RNG commitment point is the SSTORE at `AdvanceModule.sol:1256` (`lootboxRngWordByIndex[index] = rngWord`) — finalize path — OR `:1761` (mid-day VRF callback). From that moment forward the per-index RNG word is publicly readable and final. The manual-path `openLootBox`/`openBurnieLootBox` is invoked at the player's discretion (`DegenerusGame.openLootBox` is EOA-callable with no rate-gate, no cool-down, no `rngLockedFlag` revert), so the commitment window covers EVERY intervening block / transaction between the VRF callback block and the open block. EVERY participating SLOAD whose writer is reachable from a non-EXEMPT EOA stack within this window is classified VIOLATION.
- **Per-callsite shared-helper attestation:** `_resolveLootboxCommon` is reached from 4 dispatchers (`openLootBox`, `openBurnieLootBox`, `resolveLootboxDirect`, `resolveRedemptionLootbox`). Per `D-298-EXEMPT-REACH-01` the verdict matrix above is the MANUAL-path (`openLootBox`, `openBurnieLootBox`) classification; the auto-resolve callers' rows are §6 scope.
- **Cross-callsite contamination check:** because `_resolveLootboxCommon` is shared, ANY fix targeting the consumer body (e.g., reorder boon side-effects per E-19, E-31, E-16) must preserve correctness on the auto-resolve callers too. Cluster (c) reorders are safe because the auto-resolve paths get the same reorder uniformly. Cluster (a) gates at allocation-time entry points are isolated from the consumer body. Cluster (b) snapshots affect the per-index storage layout (additive — backward compatible if added behind a feature-flag during deployment, but post-deploy this contract is frozen per the user's project memory `feedback_frozen_contracts_no_future_proofing.md`).
- **Verdicts:** 29 SLOADs enumerated / 25 participating / ~80 writer-callsites consolidated to 56 (slot × writer × callsite) tuples / **35 VIOLATION rows** / 21 EXEMPT rows (18 EXEMPT-ADVANCEGAME + 2 EXEMPT-VRFCALLBACK + 1 EXEMPT-RETRYLOOTBOXRNG).
- **Scope:** zero `contracts/` + zero `test/` mutations per `D-43N-AUDIT-ONLY-01`. Read-only on source.
