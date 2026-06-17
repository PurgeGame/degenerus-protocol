# 417 Column Map — SLICE: Boon + Bingo + MintStreakUtils

Subject = frozen `contracts/` tree `0dd445a6`. Read-only mechanical enumeration.
All three files are DELEGATECALL modules / abstract bases inheriting `DegenerusGameStorage`,
so every storage write lands in **DegenerusGame's** slots.

Files:
- `contracts/modules/DegenerusGameBoonModule.sol` (BoonModule — `is DegenerusGameStorage`)
- `contracts/modules/DegenerusGameBingoModule.sol` (BingoModule — `is DegenerusGameStorage`)
- `contracts/modules/DegenerusGameMintStreakUtils.sol` (abstract base — inherited INTO MintModule/Whale/Afking/Degenerette/Game)

## Frame-depth note (load-bearing for NESTED classification)
- **BoonModule** functions are entered via `delegatecall` from a dispatcher. The dispatch sites
  that matter for the column are themselves inside a module already running via delegatecall:
  - `consumePurchaseBoost` — entered from `DegenerusGameMintModule._mintTickets...` (MintModule.sol:2062) via a module→module `GAME_BOON_MODULE.delegatecall`. MintModule itself runs via delegatecall from the Game → **NESTED delegatecall**. msg.value-in-flight (purchase ETH).
  - `checkAndClearExpiredBoon` — entered from `DegenerusGameLootboxModule._...` (LootboxModule.sol:1419) via module→module delegatecall → **NESTED**. payable; sDGNRS redemption-claim ETH leg in flight.
  - `consumeActivityBoon` — entered from `DegenerusGameLootboxModule` (LootboxModule.sol:1281) via module→module delegatecall → **NESTED**. payable; sDGNRS ETH leg in flight.
  - `consumeCoinflipBoon` / `consumeDecimatorBoost` — entered from the Game's OWN dispatch stubs (`DegenerusGame.consumeCoinflipBoon` @ DegenerusGame.sol:827 forwards raw `msg.data`; `consumeDecimatorBoon` @ :846 re-encodes to `consumeDecimatorBoost`). These are single-depth Game→module delegatecalls (NOT nested), triggered by external Coinflip/Coin calls — OFF the advanceGame spine but money-path adjacent.
- **MintStreakUtils** is an abstract base; its internals execute IN-FRAME of whatever module
  inherited them (MintModule/Whale/Afking/Degenerette/Game), i.e. one delegatecall deep from the Game.
  No new call frame; storage writes are direct in the Game's slots.

---

## 1. CALL GRAPH (column-reachable functions in this slice)

### BoonModule (each entered via delegatecall — writes Game storage)
- **consumeCoinflipBoon(player)** (:39) — internal: `_simulatedDayIndex`, `_coinflipTierToBps`. No external calls. No delegatecalls. Emits `BoonConsumed`.
- **consumePurchaseBoost(player)** `payable` (:68) — internal: `_simulatedDayIndex`, `_purchaseTierToBps`. No external/delegatecall. Emits `BoonConsumed`. **(NESTED target; msg.value in flight)**
- **consumeDecimatorBoost(player)** (:94) — internal: `_simulatedDayIndex`, `_decimatorTierToBps`. No external/delegatecall. Emits `BoonConsumed`.
- **checkAndClearExpiredBoon(player)** `payable` (:125) — internal: `_simulatedDayIndex` only. No external/delegatecall. No emit. **(NESTED target; msg.value in flight)**
- **consumeActivityBoon(player)** `payable` (:288) — internal: `_simulatedDayIndex`, `BitPackingLib.setPacked`. **EXTERNAL CALL → `quests.awardQuestStreakBonus(player, bonus, currentDay)` (:331)** (DegenerusQuests, NOT in the FLIP/Coinflip/Vault/sDGNRS/Affiliate set, but a synchronous external call whose revert bubbles). Emits `BoonConsumed`. **(NESTED target; msg.value in flight)**

### BingoModule (entered via the Game's claimBingo / claimAffiliateDgnrs delegatecall stubs)
- **claimBingo(level, symbol, slots[8])** (:114) — internal: none beyond inline. Reads `traitBurnTicket`. **EXTERNAL CALLS:** `dgnrs.poolBalance(Pool.Reward)` (:188), `dgnrs.transferFromPool(Pool.Reward, msg.sender, amt)` (:189) [sDGNRS], `coinflip.creditFlip(msg.sender, flip)` (:196) [Coinflip]. Emits `FirstQuadrantBingo`/`FirstSymbolBingo`/`BingoClaimed`. **NOT on the advanceGame spine** (user claim entrypoint; reached via Game delegatecall stub @ DegenerusGame.sol:317).
- **claimAffiliateDgnrs(player)** (:220) — internal: `_resolvePlayer` (:270), `_getLevelDgnrs`, `_addLevelDgnrsClaimed`, `PriceLookupLib.priceForLevel`. **EXTERNAL CALLS:** `affiliate.affiliateScore(currLevel, player)` (:228) [Affiliate], `affiliate.totalAffiliateScore(currLevel)` (:232) [Affiliate], `dgnrs.transferFromPool(Pool.Affiliate, player, reward)` (:240) [sDGNRS], `coinflip.creditFlip(player, bonus)` (:259) [Coinflip]. Emits `AffiliateDgnrsClaimed`. **NOT on the spine** (user claim entrypoint; Game delegatecall stub @ DegenerusGame.sol:1304).
- **_resolvePlayer(player)** (:270, private view) — reads `operatorApprovals`. Reverts `NotApproved`.

### MintStreakUtils (abstract base; in-frame internals)
- **_bountyEligible(who)** (:47, view) — reads `dailyIdx`, `mintPacked_`, `level`, `_subOf`. **EXTERNAL CALL (cold path only):** `IDegenerusVaultOwner(ContractAddresses.VAULT).isVaultOwner(who)` (:79) [Vault]. Called from `GameAfkingModule.sol:1582` (advance-bounty gate) and `DegenerusGame.sol:1404`.
- **_recordMintStreakForLevel(player, mintLevel)** (:83) — writes `mintPacked_`. Emits `MintStreakRecorded`. Called from `MintModule.sol:1698`.
- **_mintStreakEffectiveFromPacked(packed, lvl)** (:119, pure) — no state.
- **_activeTicketLevel()** (:139, view) — reads `jackpotPhaseFlag`, `level`.
- **_farFutureFractionBps(d)** (:145, pure) — no state.
- **_quoteFarFutureSwap(levels, quantities, cl, oneTicketWei, seed)** (:167, view) — internal `_farFutureFractionBps`, `PriceLookupLib.priceForLevel`. Loops over `levels`. Called from `MintModule.sol:1207,1266` (cold salvage path; OFF spine).
- **_quoteFarFutureFlipSplit(cashWei, priceWei, seed, buyer)** (:223, view) — **EXTERNAL CALL:** `coin.balanceOfSpendableForSalvage(buyer)` (:240) [FLIP token = `coin`]. Called from `MintModule.sol:1218,1282` (cold salvage path).
- **_farFutureSeed(player)** (:252, view) — reads `rngWordByDay[_simulatedDayIndex() - 1]`.
- **_playerActivityScore(player, questStreak, streakBaseLevel)** (:267) / **(player, questStreak)** (:380) / **_playerActivityScoreAt(...)** (:282) — view. Reads `mintPacked_`, `level`, `jackpotPhaseFlag`. **EXTERNAL CALL:** `affiliate.affiliateBonusPointsBest(currLevel, player)` (:344) [Affiliate], only when the cached affiliate level misses. Internal: `_mintStreakEffectiveFromPacked`, `_mintCountBonusPoints`. Called from MintModule:1710, Whale:867, Afking:827/874, Degenerette:543.
- **_applyCurseStack(target)** (:403) — writes `mintPacked_` (CURSE_COUNT field). Emits `CurseChanged`. Called from Afking:1769,1804.
- **_clearCurse(target)** (:419) — writes `mintPacked_` (CURSE_COUNT field). Emits `CurseChanged`. Called from MintModule:1706, Afking:1780.
- **_recordLootboxMintDay(player, cachedPacked)** (:434) — writes `mintPacked_` (DAY_SHIFT field). Called from Whale:854, MintModule:1580.

---

## 2. REVERT-SITE INVENTORY

| fn:line | trigger | error | class |
|---|---|---|---|
| BoonModule consumeActivityBoon:331 | `quests.awardQuestStreakBonus` callee reverts (external DegenerusQuests) | bubbles callee revert | **PERMANENT-CANDIDATE** — runs NESTED inside lootbox resolution which is reachable in the afking/lootbox auto-open path; a revert here bubbles to the LootboxModule `if (!okAct) revert E()` (LootboxModule:1284) and fails that open. Gated behind a non-zero `activityPending`, so a normal box is unaffected. NOT on the core advanceGame state machine, but can brick a player's lootbox/redemption claim tx. |
| BoonModule (all consume*/checkAndClear) | arithmetic — none unchecked-prone; `s0 & MASK` only; `stampDay + EXPIRY` is uint24 + small const, no realistic overflow | n/a | TRANSIENT (no revert path) |
| consumeActivityBoon:315-318 | `levelCount + pending` saturates to uint24.max (explicit clamp, no revert); :330 uint16 clamp | n/a | TRANSIENT |
| BingoModule claimBingo:122 | `gameOver` true | `E()` | TRANSIENT (post-gameover claims close; does not wedge the spine — claim is a leaf) |
| claimBingo:123 | `symbol >= 32` | `InvalidSymbol()` | TRANSIENT (bad input) |
| claimBingo:140-142 | `slot >= holders.length` OR `holders[slot] != msg.sender` | `NotSlotOwner()` | TRANSIENT (ownership/index guard; self-gating against unresolved/future buckets) |
| claimBingo:150 | `claimedBits & qMask != 0` (already claimed this level/quadrant) | `AlreadyClaimed()` | TRANSIENT (dedup) |
| claimBingo:189 | `dgnrs.transferFromPool` callee reverts | bubbles | **callee-revert risk** — but design says empty pool is a graceful 0-return no-op. Claim leaf; not on spine. |
| claimBingo:196 | `coinflip.creditFlip` callee reverts | bubbles | **callee-revert risk** — Coinflip `creditFlip` is `onlyFlipCreditors`; outbound sender is GAME (delegatecall), so gate passes. Claim leaf; not on spine. |
| BingoModule claimAffiliateDgnrs:224 | `level == 0` | `E()` | TRANSIENT |
| :226 | already claimed (`affiliateDgnrsClaimedBy`) | `E()` | TRANSIENT (dedup) |
| :230 | not deity AND `score < MIN_SCORE` | `E()` | TRANSIENT (eligibility) |
| :233 | `totalAffiliateScore == 0` | `E()` | TRANSIENT |
| :236 | `allocation == 0` | `E()` | TRANSIENT (nothing allocated this level) |
| :238 | `reward == 0` | `E()` | TRANSIENT |
| :245 | `paid == 0` (sDGNRS paid nothing) | `E()` | TRANSIENT |
| :228 / :232 | `affiliate.*` callee reverts | bubbles | callee-revert risk; claim leaf (not spine) |
| :240 | `dgnrs.transferFromPool` callee reverts | bubbles | callee-revert risk; claim leaf |
| :259 | `coinflip.creditFlip` callee reverts | bubbles | callee-revert risk; claim leaf |
| _resolvePlayer:274-276 | `player != msg.sender && !operatorApprovals[...]` | `NotApproved()` | TRANSIENT (auth) |
| MintStreakUtils _bountyEligible:79 | `IDegenerusVaultOwner(VAULT).isVaultOwner` callee reverts | bubbles | **callee-revert risk** — reached on the advance-bounty gate (GameAfkingModule:1582) which IS in the advance chain. See risk notes: this is a `view` external call to Vault; a revert would bubble into the bounty-eligibility check. PERMANENT-CANDIDATE-adjacent. |
| _quoteFarFutureSwap:189 | `L < cl` → `uint256(L) - uint256(cl)` underflow | Panic 0x11 (checked sub) | TRANSIENT (cold salvage input; off spine) |
| :190 | `d < 6 || d > 100` | `E()` | TRANSIENT (salvage distance) |
| :192 | `n == 0 || n > uint32.max` | `E()` | TRANSIENT (salvage qty) |
| _farFutureSeed:255 | `_simulatedDayIndex() - 1` when day index == 0 → uint24 underflow | Panic 0x11 (checked sub on uint24) | **PERMANENT-CANDIDATE (narrow)** — only reachable on day-0 salvage; salvage is gated to 6..100 distance and off the advance spine. Read-only consumer; the wrap is in the `-1` BEFORE the map read. Flag for 418-423: confirm day-0 salvage is otherwise unreachable. |
| _playerActivityScore* :344 | `affiliate.affiliateBonusPointsBest` callee reverts | bubbles | **callee-revert risk** — `_playerActivityScore` is called ON the spine via Afking (827/874) and MintModule (1710). A revert here bubbles into mintFlip/afking. Only reached when the affiliate-bonus cache level misses (`cachedLevel != currLevel`). PERMANENT-CANDIDATE-adjacent. |

**No** explicit `require`/`revert` exists in `_recordMintStreakForLevel`, `_applyCurseStack`, `_clearCurse`, `_recordLootboxMintDay`, `consumeCoinflipBoon/Purchase/Decimator`, `checkAndClearExpiredBoon` — they are revert-free by construction (mask/saturate/early-return), which is the spine-safety property.

---

## 3. LOOP INVENTORY

| fn:line | bound expr | per-iter storage/gas | class |
|---|---|---|---|
| BingoModule claimBingo:137 | `c < 8` (fixed 8 colors) | 1 SLOAD of `levelBuckets[traitId]` length + 1 SLOAD `holders[slot]` (array element); reads only | **BOUNDED** (constant 8) |
| MintStreakUtils _quoteFarFutureSwap:187 | `i < levels.length` (`levels` = calldata array, caller-sized) | per-iter: `PriceLookupLib.priceForLevel(L)` (pure), `_farFutureFractionBps` (pure); NO storage writes; accumulates in memory | **INPUT-SIZED** — but OFF the advanceGame spine (cold salvage entrypoint `sellFarFutureTickets`/preview). Worst-case gas borne by the salvage caller, not the keeper advancing the game. Flag for completeness; not a spine brick. |

BoonModule `checkAndClearExpiredBoon` has NO loop (straight-line per-category checks). All MintStreakUtils scoring/curse/streak helpers are loop-free.

---

## 4. DELEGATECALL STORAGE-WRITE INVENTORY (Game slots written by this slice)

### BoonModule
- `boonPacked[player].slot0` — written in `consumeCoinflipBoon` (:49,:58), `consumePurchaseBoost` (:78,:87), `consumeDecimatorBoost` (:104,:108), `checkAndClearExpiredBoon` (:270). **PACKED slot** — fields keyed by boon category × day; clears use `BP_*_CLEAR` masks. Hotspot: multiple categories (coinflip/lootbox/purchase/decimator/whale) co-resident in slot0; the day-keyed expiry writes (`s0 & BP_*_CLEAR`) are aliasing-relevant.
- `boonPacked[player].slot1` — written in `checkAndClearExpiredBoon` (:271), `consumeActivityBoon` (:298,:308). **PACKED slot** — activity/deityPass/lazyPass fields, day-keyed.
- `mintPacked_[player]` — written in `consumeActivityBoon` (:327) — **PACKED slot**, LEVEL_COUNT field (`BitPackingLib.LEVEL_COUNT_SHIFT`), conditional on `data != prevData`.

### BingoModule
- `bingoClaimed[level][msg.sender]` (uint8) — written in `claimBingo` (:151). **level-keyed**, per-player quadrant bitmask (`| qMask`).
- `bingoFirsts[level]` (uint64) — written in `claimBingo` (:167 both-bits quadrant-first, :175 symbol-bit-only). **level-keyed PACKED** — quadrant mask in bits[32:36), symbol mask in bits[0:32). Hotspot: two distinct write shapes into the same packed word keyed by `level`.
- `affiliateDgnrsClaimedBy[currLevel][player]` (bool) — written in `claimAffiliateDgnrs` (:263). **level-keyed**.
- `levelDgnrsPacked[currLevel]` — written via `_addLevelDgnrsClaimed(currLevel, paid)` (:247 → storage helper :1179). **level-keyed PACKED** — high 128 = claimed, low 128 = allocation; adds to claimed half only.

### MintStreakUtils (in-frame, Game slots)
- `mintPacked_[player]` — written in:
  - `_recordMintStreakForLevel` (:113) — **PACKED**, MINT_STREAK_LAST_COMPLETED + LEVEL_STREAK fields (`MINT_STREAK_FIELDS_MASK`).
  - `_applyCurseStack` (:409) — **PACKED**, CURSE_COUNT field (`BitPackingLib.CURSE_COUNT_SHIFT`), saturating +2.
  - `_clearCurse` (:422) — **PACKED**, CURSE_COUNT field set to 0.
  - `_recordLootboxMintDay` (:444) — **PACKED**, DAY_SHIFT field (`MASK_32 << DAY_SHIFT`).
- All four are writes into the SAME `mintPacked_[player]` word but DISTINCT bit-fields (CURSE_COUNT @ bits 215-222 per storage comment; LEVEL_STREAK / MINT_STREAK_LAST_COMPLETED; DAY_SHIFT; LEVEL_COUNT via consumeActivityBoon). **Aliasing hotspot:** the same `mintPacked_[player]` slot is touched by this slice (curse, streak, lootbox-day, activity-level-count) AND by other modules (whale/afking/mint) — field-isolation via masked read-modify-write is the load-bearing invariant; a non-field-isolated write here would corrupt co-resident fields.

---

## 5. CROSS-REFERENCES (dispatch sites that reach this slice)
- `Coinflip.sol:660` → `game.consumeCoinflipBoon` → Game stub :827 → BoonModule (single delegatecall).
- `DegenerusGame.sol:846` `consumeDecimatorBoon` → BoonModule `consumeDecimatorBoost` (single delegatecall, COIN-gated).
- `MintModule.sol:2062` → BoonModule `consumePurchaseBoost` (**NESTED**, payable, ETH in flight).
- `LootboxModule.sol:1281` → BoonModule `consumeActivityBoon` (**NESTED**, payable).
- `LootboxModule.sol:1419` → BoonModule `checkAndClearExpiredBoon` (**NESTED**, payable).
- `DegenerusGame.sol:317` claimBingo stub → BingoModule (single delegatecall, user leaf).
- `DegenerusGame.sol:1304` claimAffiliateDgnrs stub → BingoModule (single delegatecall, user leaf).
- MintStreakUtils internals inherited & called in-frame by MintModule / Whale / Afking / Degenerette / Game (see §1 line refs).
