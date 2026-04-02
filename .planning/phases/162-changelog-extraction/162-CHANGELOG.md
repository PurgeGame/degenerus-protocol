# Changelog: v10.3 to HEAD (v11.0-v14.0)

**Git range:** `v10.3..HEAD`
**Commits:** 11 (excluding merges)
**Files changed:** 21
**Insertions:** 1,337 | **Deletions:** 1,542

## Milestone Summary

| Milestone | Phases | Theme |
|-----------|--------|-------|
| v11.0 | 151-152 | Endgame gate (gameOverPossible flag + drip projection) |
| v12.0 | 153-155 | Level quest design (no contract changes -- design docs only) |
| v13.0 | 156-158.1 | Level quest implementation + carryover redesign + quest routing cleanup |
| v14.0 | 159-161 | Activity score + purchase path correctness + SLOAD dedup |

## Commit-to-Milestone Mapping

| Hash | Milestone | Description |
|------|-----------|-------------|
| `19b05efb` | v11.0 | feat(151-01): add gameOverPossible flag + drip projection math |
| `fe146106` | v11.0 | feat(151-02): remove 30-day BURNIE ban, wire gameOverPossible enforcement |
| `0f8fb054` | v11.0 | spacing comment (trivial) |
| `4722dbf8` | v13.0 | remove degenerette consolation prize (WWXRP mint on loss) |
| `1019f928` | v13.0 | affiliate gas simplification |
| `9d77a2e1` | v13.0 | v13.0 level quests implementation + quest system gas optimization |
| `c782d647` | v14.0 | feat(160): score foundation + batched quest writes + interface consolidation |
| `24f0898b` | v14.0 | feat(160): handlePurchase + compute-once score + mintPrice passthrough |
| `b5b4c52d` | v14.0 | fix(160.1): purchase path correctness -- purchaseLevel, lootbox baseline, price removal, quest split |
| `6805969e` | v14.0 | fix(jackpot): carryover tickets at current level, source range 1-4, final day to lvl+1 |
| `7bb42878` | v14.0 | perf(161): cache 5 hot-path SLOADs in purchase path |

---

## Changes by Contract

### contracts/BurnieCoin.sol

**Stats:** +254 / -254 lines (net: significant removals) | Milestones: v13.0

#### New Functions

_None_

#### Modified Functions

| Function | Line | Milestone | Description | Risk |
|----------|------|-----------|-------------|------|
| `burnCoin(address,uint256)` | ~565 | v13.0 | Modifier changed from `onlyTrustedContracts` to `onlyGame` -- AFFILIATE no longer a direct caller | **Access control** |
| `burnDecimator()` | ~596 | v13.0 | `decWindow()` return changed from `(bool,uint24)` to `(bool)` -- separate `level()` call added; quest reward routing simplified (reward returned directly, creditFlip moved to DegenerusQuests internally); `_questApplyReward` inlined away; activity score bonus applied to `baseAmount` only when quest completed | **ETH flow** |
| `modifier onlyGame()` | ~555 | v13.0 | Renamed from `onlyDegenerusGameContract`; replaces `onlyTrustedContracts` (was GAME+AFFILIATE, now GAME only) | **Access control** |

#### Removed Functions

| Function | Milestone | Description |
|----------|-----------|-------------|
| `affiliateQuestReward(address,uint256)` | v13.0 | Quest reward routing moved to DegenerusAffiliate calling DegenerusQuests directly |
| `rollDailyQuest(uint48,uint256)` | v13.0 | Daily quest rolling moved from BurnieCoin to AdvanceModule calling DegenerusQuests directly |
| `notifyQuestMint(address,uint32,bool)` | v13.0 | Quest handler now called directly by MintModule via DegenerusQuests |
| `notifyQuestLootBox(address,uint256)` | v13.0 | Quest handler now called directly by MintModule/LootboxModule via DegenerusQuests |
| `notifyQuestDegenerette(address,uint256,bool)` | v13.0 | Quest handler now called directly by DegeneretteModule via DegenerusQuests |
| `_questApplyReward(address,uint256,uint8,uint32,bool)` | v13.0 | Private helper eliminated -- each quest handler now emits events and routes rewards internally |
| `modifier onlyDegenerusGameContract()` | v13.0 | Replaced by `onlyGame` |
| `modifier onlyTrustedContracts()` | v13.0 | Replaced by `onlyGame` (AFFILIATE removed as caller) |
| `event DailyQuestRolled` | v13.0 | Event moved to DegenerusQuests |
| `event QuestCompleted` | v13.0 | Event moved to DegenerusQuests |
| `error OnlyAffiliate()` | v13.0 | No longer needed -- affiliate no longer calls BurnieCoin for quest routing |
| `error OnlyTrustedContracts()` | v13.0 | Replaced by existing `OnlyGame` error |
| `constant QUEST_TYPE_MINT_ETH` | v13.0 | Quest type constant moved to DegenerusQuests |

#### Storage Changes

_None_

#### Comment-only Changes

| Location | Milestone | Description |
|----------|-----------|-------------|
| Contract-level NatSpec (access control list) | v13.0 | Updated to reflect `onlyGame, onlyVault` replacing `onlyDegenerusGame, onlyTrustedContracts, onlyVault` |
| Section header `QUEST INTEGRATION HELPERS` | v13.0 | Renamed to `DECIMATOR HELPERS` |
| `burnCoin` NatSpec | v13.0 | Updated caller description |

---

### contracts/BurnieCoinflip.sol

**Stats:** +8 / -8 lines (net: 0) | Milestones: v13.0, v14.0

#### New Functions

_None_

#### Modified Functions

| Function | Line | Milestone | Description | Risk |
|----------|------|-----------|-------------|------|
| `modifier onlyFlipCreditors()` | ~190 | v13.0 | Replaced `ContractAddresses.COIN` with `ContractAddresses.QUESTS` -- QUESTS contract now credits flips directly for level quest rewards | **Access control** |
| `_resolveRecycleRebet()` (line ~299) | ~299 | v14.0 | Changed `game.deityPassCountFor(caller) != 0` to `game.hasDeityPass(caller)` | |
| `_resolveRecycleBatch()` (line ~432) | ~432 | v14.0 | Changed `game.deityPassCountFor(player) != 0` to `game.hasDeityPass(player)` | |

#### Removed Functions

_None_

#### Storage Changes

_None_

#### Comment-only Changes

| Location | Milestone | Description |
|----------|-----------|-------------|
| `onlyFlipCreditors` NatSpec | v13.0 | Updated allowed callers list: COIN replaced by QUESTS |

---

### contracts/DegenerusAffiliate.sol

**Stats:** +155 / -155 lines (net: significant rewrite) | Milestones: v13.0, v14.0

#### New Functions

_None_

#### Modified Functions

| Function | Line | Milestone | Description | Risk |
|----------|------|-----------|-------------|------|
| `payAffiliate()` | ~360 | v13.0/v14.0 | Major rewrite: (1) leaderboard tracking moved after lootbox taper (post-taper amount); (2) 3-tier distribution replaced by winner-takes-all 75/20/5 weighted roll using mod 20; (3) quest reward call changed from `coin.affiliateQuestReward` to `quests.handleAffiliate`; (4) no-referrer path simplified to flush `affiliateShareBase` to VAULT/DGNRS coin flip | **ETH flow, RNG** |

#### Removed Functions

| Function | Milestone | Description |
|----------|-----------|-------------|
| `_rollWeightedAffiliateWinner(address[3],uint256[3],uint256,uint256,address,bytes32)` | v13.0 | Replaced by inline mod-20 roll in `payAffiliate` |
| `interface IDegenerusCoinAffiliate` | v13.0 | Replaced by `IDegenerusQuestsAffiliate` -- quest calls route to DegenerusQuests directly |

#### Storage Changes

| Variable | Type | Milestone | Description |
|----------|------|-----------|-------------|
| `coin` (constant) | Replaced | v13.0 | `IDegenerusCoinAffiliate constant coin` replaced by `IDegenerusQuestsAffiliate constant quests` (points to QUESTS address) |

#### Comment-only Changes

| Location | Milestone | Description |
|----------|-----------|-------------|
| Contract NatSpec | v13.0 | Updated tier distribution description from per-tier percentages to "75/20/5 winner-takes-all roll" |
| `payAffiliate` flow comments | v13.0 | Steps renumbered; "upline" distribution steps replaced by "roll" and "winner gets full pot" |
| Taper ordering comments | v14.0 | Updated: "leaderboard always uses full untapered amount" removed; "post-taper amount" added |

---

### contracts/DegenerusGame.sol

**Stats:** +268 / -268 lines (net: significant removals) | Milestones: v11.0, v13.0, v14.0

#### New Functions

| Function | Line | Milestone | Description | Risk |
|----------|------|-----------|-------------|------|
| `hasDeityPass(address)` | ~2251 | v14.0 | View returning bool from mintPacked_ bit 184 (replaces deityPassCountFor) | |
| `mintPackedFor(address)` (interface only -- exposed in IDegenerusGame) | -- | v14.0 | Exposes raw mintPacked_ for external callers (DegenerusQuests eligibility checks) | |

#### Modified Functions

| Function | Line | Milestone | Description | Risk |
|----------|------|-----------|-------------|------|
| `constructor` | ~204 | v14.0 | Deity pass initialization changed from `deityPassCount[addr] = 1` to `BitPackingLib.setPacked(mintPacked_, HAS_DEITY_PASS_SHIFT, 1, 1)` | |
| `processPayment()` | ~338 | v14.0 | Return type formatting only (no behavior change) | |
| `recordMintQuestStreak(address)` | ~376 | v13.0 | Access control changed from `COIN` to `GAME` (called via MintModule delegatecall now) | **Access control** |
| `recordTerminalDecBurn` delegatecall | ~1088 | v14.0 | Comment-only: formatting of selector reference (line breaks) | |
| `runTerminalDecimatorJackpot` delegatecall | ~1115 | v14.0 | Comment-only: formatting of selector reference (line breaks) | |
| `decClaimable()` (amountWei calc) | ~1233 | v14.0 | Formatting only (parentheses) | |
| `claimWinningsStethFirst()` | ~1316 | v14.0 | NatSpec updated: removed "or DGNRS contract" -- now vault only | |
| `claimAffiliateDgnrs()` | ~1358 | v14.0 | `deityPassCount[player] != 0` replaced by `mintPacked_[player] >> HAS_DEITY_PASS_SHIFT & 1 != 0`; `price` replaced by `PriceLookupLib.priceForLevel(level)` | |
| `_hasAnyLazyPass()` | ~1551 | v14.0 | Reads `mintPacked_` once into local `packed`; deity pass check via bit shift instead of `deityPassCount` | |
| `mintPrice()` | ~2079 | v14.0 | Returns `PriceLookupLib.priceForLevel(level)` instead of `price` storage variable | |
| `decWindow()` | ~2115 | v11.0/v14.0 | Signature changed from `(bool on, uint24 lvl)` to `(bool)` -- returns only `decWindowOpen` (no RNG lock check, no gameOverImminent fallback) | **Access control** |
| `purchaseState()` | ~2153 | v14.0 | `price` replaced by `PriceLookupLib.priceForLevel(level)` | |
| `ethMintStats(address)` | ~2172 | v14.0 | Deity pass check via `mintPacked_` bit shift; single SLOAD for packed data | |
| `playerActivityScore(address)` | ~2210 | v14.0 | Body replaced: now fetches questStreak from `questView.playerQuestStates` then delegates to `_playerActivityScore(player, streak)` in MintStreakUtils | |

#### Removed Functions

| Function | Milestone | Description |
|----------|-----------|-------------|
| `decWindowOpenFlag()` | v11.0 | Merged into simplified `decWindow()` |
| `_isGameoverImminent()` | v11.0 | Replaced by `gameOverPossible` flag set in AdvanceModule |
| `_activeTicketLevel()` | v14.0 | Moved to DegenerusGameMintStreakUtils (shared across modules) |
| `_threeDayRngGap(uint48)` | v14.0 | Removed entirely -- not referenced anywhere |
| `_playerActivityScore(address) internal` | v14.0 | Moved to DegenerusGameMintStreakUtils with questStreak parameter |
| `_mintCountBonusPoints(uint24,uint24)` | v14.0 | Moved to DegenerusGameStorage (shared across modules) |
| `deityPassCountFor(address)` | v14.0 | Replaced by `hasDeityPass(address)` |
| `interface IDegenerusQuestView` | v14.0 | Moved to DegenerusGameStorage |
| `constant coin` (IDegenerusCoin) | v14.0 | Moved to DegenerusGameStorage |
| `constant coinflip` (IBurnieCoinflip) | v14.0 | Moved to DegenerusGameStorage |
| `constant affiliate` (IDegenerusAffiliate) | v14.0 | Moved to DegenerusGameStorage |
| `constant dgnrs` (IStakedDegenerusStonk) | v14.0 | Moved to DegenerusGameStorage |
| `constant questView` (IDegenerusQuestView) | v14.0 | Moved to DegenerusGameStorage |
| `constant steth` (partial -- duplicate removed) | v14.0 | Kept one `steth` constant, removed duplicate |
| `constant DEITY_PASS_ACTIVITY_BONUS_BPS` | v14.0 | Moved to DegenerusGameStorage |
| `constant PASS_STREAK_FLOOR_POINTS` | v14.0 | Moved to DegenerusGameStorage |
| `constant PASS_MINT_COUNT_FLOOR_POINTS` | v14.0 | Moved to DegenerusGameStorage |

#### Storage Changes

_None (all storage changes are in DegenerusGameStorage.sol)_

#### Comment-only Changes

| Location | Milestone | Description |
|----------|-----------|-------------|
| RNG usage table (AdvanceModule ref) | v14.0 | Formatting fix: spacing alignment |

---

### contracts/DegenerusQuests.sol

**Stats:** +530 / -530 lines (net: major additions) | Milestones: v13.0, v14.0

#### New Functions

| Function | Line | Milestone | Description | Risk |
|----------|------|-----------|-------------|------|
| `handlePurchase(address,uint32,uint32,uint256,uint256,uint256)` | ~798 | v14.0 | Combined purchase-path handler: processes ETH mint + BURNIE mint + lootbox quest progress in single cross-contract call. CreditFlips internally for BURNIE/lootbox rewards; returns ETH mint reward. Returns streak for compute-once score forwarding. | **ETH flow** |
| `rollLevelQuest(uint256)` | ~1766 | v13.0 | Selects level quest type via `_bonusQuestType`, bumps `levelQuestVersion` | |
| `clearLevelQuest()` | ~1773 | v13.0 | Zeros `levelQuestType` at level transition before new RNG arrives | |
| `_isLevelQuestEligible(address)` | ~1779 | v13.0 | Checks loyalty gate (levelStreak >= 5 OR active pass) AND activity gate (4+ units minted this level) | |
| `_levelQuestTargetValue(uint8,uint256)` | ~1804 | v13.0 | Returns 10x target for level quest type: MINT_BURNIE=10, MINT_ETH=price*10, LOOTBOX/DEGEN_ETH=price*20, BURNIE types=20000 BURNIE | |
| `_handleLevelQuestProgress(address,uint8,uint256,uint256)` | ~1834 | v13.0 | Shared level quest progress handler called by all 6 daily handlers. Short-circuits on type mismatch. Credits 800 BURNIE via coinflip on completion. | **ETH flow** |
| `getPlayerLevelQuestView(address)` | ~1893 | v13.0 | View returning level quest state: questType, progress, target, completed, eligible | |
| `event LevelQuestCompleted` | ~117 | v13.0 | Emitted when player completes level quest (player, level, questType, reward) | |

#### Modified Functions

| Function | Line | Milestone | Description | Risk |
|----------|------|-----------|-------------|------|
| `rollDailyQuest(uint48,uint256)` | ~322 | v13.0/v14.0 | Simplified: made `external onlyGame` (was `onlyCoin`); inlined `_rollDailyQuest` logic; made idempotent per day; emits events directly | **Access control** |
| `handleMint(address,uint32,bool,uint256)` | ~415 | v13.0/v14.0 | Added `mintPrice` parameter; calls `_handleLevelQuestProgress` for level quest; adds `levelQuestHandled` flag to prevent double-counting across slots; BURNIE mint rewards now `creditFlip`'d internally (was returned to BurnieCoin) | **ETH flow** |
| `handleFlip(address,uint256)` | ~540 | v13.0 | Added `_handleLevelQuestProgress` call for FLIP type | |
| `handleDecimator(address,uint256)` | ~599 | v13.0/v14.0 | Added `_handleLevelQuestProgress` call; reward now `creditFlip`'d internally (was returned to BurnieCoin) | **ETH flow** |
| `handleAffiliate(address,uint256)` | ~654 | v13.0 | Added `_handleLevelQuestProgress` call for AFFILIATE type | |
| `handleLootBox(address,uint256,uint256)` | ~695 | v13.0/v14.0 | Added `mintPrice` parameter (was fetched from `questGame.mintPrice()`); added `_handleLevelQuestProgress` call; reward now `creditFlip`'d internally | **ETH flow** |
| `handleDegenerette(address,uint256,bool,uint256)` | ~909 | v13.0/v14.0 | Added `mintPrice` parameter; added `_handleLevelQuestProgress` call; reward now `creditFlip`'d internally; removed internal `questGame.mintPrice()` call | **ETH flow** |
| `_questHandleProgressSlot(...)` | ~1225 | v13.0/v14.0 | Added 3 new parameters: `handlerQuestType`, `levelDelta`, `levelQuestPrice`; calls `_handleLevelQuestProgress` internally | |
| `_canRollDecimatorQuest()` | ~1157 | v14.0 | Changed `game_.decWindowOpenFlag()` to `game_.decWindow()` (interface simplified) | |
| `_bonusQuestType()` loop | ~1476 | v13.0 | Added skip for sentinel value 0 (unrolled marker) alongside existing QUEST_TYPE_RESERVED skip | |
| `modifier onlyCoin()` | ~289 | v13.0 | Expanded: now accepts COIN, COINFLIP, GAME, and AFFILIATE (was only COIN and COINFLIP) | **Access control** |

#### Removed Functions

| Function | Milestone | Description |
|----------|-----------|-------------|
| `_rollDailyQuest(uint48,uint256)` | v13.0 | Inlined into `rollDailyQuest` |

#### Storage Changes

| Variable | Type | Milestone | Description |
|----------|------|-----------|-------------|
| `levelQuestType` | `uint8` (new) | v13.0 | Active level quest type (1-9, 0=none). Packs with `questVersionCounter` and `levelQuestVersion`. |
| `levelQuestVersion` | `uint8` (new) | v13.0 | Version counter for level quest invalidation. Bumps on each `rollLevelQuest`. |
| `levelQuestPlayerState` | `mapping(address => uint256)` (new) | v13.0 | Per-player level quest packed state: version (8b) + progress (128b) + completed (1b at bit 136). |
| `QUEST_TYPE_MINT_BURNIE` | constant changed | v13.0 | Changed from 0 to 9 to avoid collision with Solidity default mapping value (0 = "no quest rolled") |
| `QUEST_TYPE_COUNT` | constant changed | v13.0 | Changed from 9 to 10 |

---

### contracts/interfaces/DegenerusGameModuleInterfaces.sol

**Stats:** -20 lines (deleted) | Milestone: v14.0

#### Removed Functions

| Function | Milestone | Description |
|----------|-----------|-------------|
| `interface IDegenerusCoinModule` (entire file) | v14.0 | `rollDailyQuest` moved to DegenerusQuests; `vaultEscrow` inlined into IDegenerusCoin |

---

### contracts/interfaces/IDegenerusCoin.sol

**Stats:** +27 / -27 lines | Milestones: v13.0, v14.0

#### Modified Functions

| Function | Line | Milestone | Description | Risk |
|----------|------|-----------|-------------|------|
| Interface declaration | ~5 | v14.0 | No longer extends `IDegenerusCoinModule`; `vaultEscrow` moved inline |

#### Removed Functions

| Function | Milestone | Description |
|----------|-----------|-------------|
| `notifyQuestMint(address,uint32,bool)` | v13.0 | Quest routing removed from coin interface |
| `notifyQuestLootBox(address,uint256)` | v13.0 | Quest routing removed from coin interface |
| `notifyQuestDegenerette(address,uint256,bool)` | v13.0 | Quest routing removed from coin interface |
| `import IDegenerusCoinModule` | v14.0 | Import removed (file deleted) |

---

### contracts/interfaces/IDegenerusGame.sol

**Stats:** +23 / -23 lines | Milestones: v11.0, v14.0

#### New Functions

| Function | Line | Milestone | Description | Risk |
|----------|------|-----------|-------------|------|
| `hasDeityPass(address)` | ~341 | v14.0 | Returns bool instead of uint16 count | |
| `mintPackedFor(address)` | ~346 | v14.0 | Exposes raw mintPacked_ for DegenerusQuests eligibility | |

#### Modified Functions

| Function | Line | Milestone | Description | Risk |
|----------|------|-----------|-------------|------|
| `decWindow()` | ~31 | v11.0 | Signature changed from `(bool on, uint24 lvl)` to `(bool)` | |
| `recordMintQuestStreak(address)` | ~214 | v13.0 | NatSpec: caller changed from COIN to GAME | |

#### Removed Functions

| Function | Milestone | Description |
|----------|-----------|-------------|
| `decWindowOpenFlag()` | v11.0 | Merged into simplified `decWindow()` |
| `deityPassCountFor(address)` | v14.0 | Replaced by `hasDeityPass(address)` |

---

### contracts/interfaces/IDegenerusQuests.sol

**Stats:** +64 / -64 lines | Milestones: v13.0, v14.0

#### New Functions

| Function | Line | Milestone | Description | Risk |
|----------|------|-----------|-------------|------|
| `handlePurchase(address,uint32,uint32,uint256,uint256,uint256)` | ~213 | v14.0 | Combined purchase-path handler interface | |
| `rollLevelQuest(uint256)` | ~167 | v13.0 | Level quest rolling interface | |
| `clearLevelQuest()` | ~170 | v13.0 | Level quest clearing interface | |
| `getPlayerLevelQuestView(address)` | ~178 | v13.0 | Level quest state view interface | |

#### Modified Functions

| Function | Line | Milestone | Description | Risk |
|----------|------|-----------|-------------|------|
| `rollDailyQuest(uint48,uint256)` | ~42 | v13.0 | Return type removed (was `(bool,uint8[2],bool)`, now void); NatSpec updated | |
| `handleMint(address,uint32,bool,uint256)` | ~48 | v14.0 | Added `mintPrice` parameter | |
| `handleLootBox(address,uint256,uint256)` | ~99 | v14.0 | Added `mintPrice` parameter | |
| `handleDegenerette(address,uint256,bool,uint256)` | ~113 | v14.0 | Added `mintPrice` parameter | |

---

### contracts/libraries/BitPackingLib.sol

**Stats:** +6 / -6 lines | Milestone: v14.0

#### New Functions

_None_

#### Modified Functions

_None_

#### Storage Changes

| Variable | Type | Milestone | Description |
|----------|------|-----------|-------------|
| `HAS_DEITY_PASS_SHIFT` | `uint256 constant = 184` (new) | v14.0 | Bit position for deity pass flag in mintPacked_ (1 bit at position 184) |

#### Comment-only Changes

| Location | Milestone | Description |
|----------|-----------|-------------|
| Bit layout header comment | v14.0 | Added `[184] HAS_DEITY_PASS_SHIFT` to layout documentation; reduced unused range from `[184-227]` to `[185-227]` |

---

### contracts/modules/DegenerusGameAdvanceModule.sol

**Stats:** +156 / -156 lines | Milestones: v11.0, v13.0, v14.0

#### New Functions

| Function | Line | Milestone | Description | Risk |
|----------|------|-----------|-------------|------|
| `_wadPow(uint256,uint256)` | ~1571 | v11.0 | WAD-scale exponentiation via repeated squaring. Max 7 iterations for exp <= 120. ~700 gas. | |
| `_projectedDrip(uint256,uint256)` | ~1588 | v11.0 | Closed-form geometric series: `futurePool * (1 - 0.9925^n)`. Projects total drip over n days. | |
| `_evaluateGameOverPossible(uint24,uint24)` | ~1599 | v11.0 | Sets/clears `gameOverPossible` based on drip projection vs nextPool deficit at L10+. Called at purchase-phase entry (FLAG-01), daily re-check (FLAG-02), and target-met clear (FLAG-03). | **ETH flow** |

#### Modified Functions

| Function | Line | Milestone | Description | Risk |
|----------|------|-----------|-------------|------|
| `advanceGame()` main loop | ~148 | v11.0/v13.0/v14.0 | Multiple changes: (1) FLAG-03: `gameOverPossible = false` on target met; (2) `quests.clearLevelQuest()` at RNG request; (3) `quests.rollDailyQuest(day, rngWord)` called directly (was via BurnieCoin); (4) FLAG-01: `_evaluateGameOverPossible` at purchase-phase entry; (5) future ticket prep guard simplified (removed `dailyEthPhase == 0 && dailyEthPoolBudget == 0` conditions); (6) FLAG-02: re-check to clear flag after daily jackpot; (7) `quests.rollLevelQuest` at level transition; (8) carryover ETH resume block removed (STAGE_JACKPOT_ETH_RESUME eliminated); (9) all `price` references replaced by `PriceLookupLib.priceForLevel(lvl)` | **ETH flow, RNG** |
| `_processPhaseTransition()` | ~1379 | v14.0 | Removed price-setting if-else chain (levels 5/10/30/60/90/100 + cycling) -- price now computed by PriceLookupLib | |
| `_applyMintGate()` | ~682 | v14.0 | Deity pass check changed from `deityPassCount[caller] != 0` to `mintData >> HAS_DEITY_PASS_SHIFT & 1 != 0` | |
| `_coinflipRngGate()` | ~738 | v14.0 | `price` replaced by `PriceLookupLib.priceForLevel(level)` | |

#### Removed Functions

| Function | Milestone | Description |
|----------|-----------|-------------|
| `constant coin` (IDegenerusCoin) | v14.0 | Moved to DegenerusGameStorage |
| `constant coinflip` (IBurnieCoinflip) | v14.0 | Moved to DegenerusGameStorage |
| `constant STAGE_JACKPOT_ETH_RESUME = 8` | v14.0 | Stage eliminated with carryover redesign |

#### Storage Changes

| Variable | Type | Milestone | Description |
|----------|------|-----------|-------------|
| `DECAY_RATE` | `uint256 constant = 0.9925 ether` (new) | v11.0 | Daily decay factor for drip projection |

#### Comment-only Changes

| Location | Milestone | Description |
|----------|-----------|-------------|
| RNG usage table | v14.0 | Fixed spacing alignment |
| FF processing comment | v14.0 | Line break formatting |

---

### contracts/modules/DegenerusGameBoonModule.sol

**Stats:** -2 lines | Milestone: v14.0

#### Removed Functions

| Function | Milestone | Description |
|----------|-----------|-------------|
| `constant quests` (IDegenerusQuests) | v14.0 | Moved to DegenerusGameStorage (shared constant) |

---

### contracts/modules/DegenerusGameDegeneretteModule.sol

**Stats:** +203 / -203 lines (net: significant removals) | Milestones: v13.0, v14.0

#### New Functions

_None_

#### Modified Functions

| Function | Line | Milestone | Description | Risk |
|----------|------|-----------|-------------|------|
| `_placeBet()` (placeBet internal) | ~402 | v13.0 | Quest notification changed from `coin.notifyQuestDegenerette` to `quests.handleDegenerette` with mintPrice passthrough; ETH+BURNIE handled in single conditional | |
| `_createCustomTickets()` | ~431 | v14.0 | Activity score: `_playerActivityScoreInternal` replaced by `_playerActivityScore(player, questStreak, level + 1)` with explicit `questView.playerQuestStates` call | |
| `_resolvePayout()` | ~672 | v13.0 | Consolation prize block removed (no more WWXRP mint on total loss) | |

#### Removed Functions

| Function | Milestone | Description |
|----------|-----------|-------------|
| `_playerActivityScoreInternal(address)` | v14.0 | Moved to DegenerusGameMintStreakUtils as shared `_playerActivityScore(address,uint32,uint24)` |
| `_mintCountBonusPoints(uint24,uint24)` | v14.0 | Moved to DegenerusGameStorage |
| `_maybeAwardConsolation(address,uint8,uint128)` | v13.0 | Consolation prize feature removed |
| `event ConsolationPrize` | v13.0 | Removed with consolation prize |
| `constant coin` (IDegenerusCoin) | v14.0 | Moved to DegenerusGameStorage |
| `constant questView` (IDegenerusQuestView) | v14.0 | Moved to DegenerusGameStorage |
| `constant affiliate` (IDegenerusAffiliate) | v14.0 | Moved to DegenerusGameStorage |
| `interface IDegenerusQuestView` (local) | v14.0 | Moved to DegenerusGameStorage |
| `constant DEITY_PASS_ACTIVITY_BONUS_BPS` | v14.0 | Moved to DegenerusGameStorage |
| `constant WHALE_PASS_STREAK_FLOOR_POINTS` | v14.0 | Moved to DegenerusGameStorage |
| `constant WHALE_PASS_MINT_COUNT_FLOOR_POINTS` | v14.0 | Moved to DegenerusGameStorage |
| `constant CONSOLATION_MIN_ETH` | v13.0 | Removed with consolation prize |
| `constant CONSOLATION_MIN_BURNIE` | v13.0 | Removed with consolation prize |
| `constant CONSOLATION_MIN_WWXRP` | v13.0 | Removed with consolation prize |
| `constant CONSOLATION_PRIZE_WWXRP` | v13.0 | Removed with consolation prize |

---

### contracts/modules/DegenerusGameEndgameModule.sol

**Stats:** +23 / -23 lines | Milestones: v14.0

#### New Functions

_None_

#### Modified Functions

_None (only formatting changes)_

#### Removed Functions

| Function | Milestone | Description |
|----------|-----------|-------------|
| `constant affiliate` (IDegenerusAffiliate) | v14.0 | Moved to DegenerusGameStorage |
| `constant dgnrs` (IStakedDegenerusStonk) | v14.0 | Moved to DegenerusGameStorage |

#### Comment-only Changes

| Location | Milestone | Description |
|----------|-----------|-------------|
| Multiple lines | v14.0 | Formatting: long lines broken across multiple lines for readability (no logic change) |
| Trailing blank line at EOF | v14.0 | Removed |

---

### contracts/modules/DegenerusGameGameOverModule.sol

**Stats:** -3 lines | Milestone: v14.0

#### Removed Functions

| Function | Milestone | Description |
|----------|-----------|-------------|
| `constant dgnrs` (IStakedDegenerusStonk) | v14.0 | Moved to DegenerusGameStorage |

---

### contracts/modules/DegenerusGameJackpotModule.sol

**Stats:** +301 / -301 lines (net: significant restructuring) | Milestones: v13.0, v14.0

#### New Functions

_None_

#### Modified Functions

| Function | Line | Milestone | Description | Risk |
|----------|------|-----------|-------------|------|
| `payDailyJackpot()` | ~293 | v14.0 | Major restructuring: (1) carryover ETH Phase 1 distribution eliminated -- no more `dailyEthPhase` state machine, no `isResuming` path; (2) carryover reserve changed from 1% to 0.5% of futurePrizePool; (3) reserve now flows directly to nextPool (was distributed as ETH + lootbox to carryover-source-level winners); (4) ticket distribution: carryover ticket units from reserve/price, winners from source level get tickets at current level (or lvl+1 on final day); (5) `DAILY_CARRYOVER_MAX_OFFSET` reduced from 5 to 4; (6) `coin.rollDailyQuest` call removed (now in AdvanceModule) | **ETH flow, RNG** |
| `payDailyJackpotCoinAndTickets()` | ~533 | v14.0 | (1) Daily ticket distribution: added `queueLvl` parameter (lvl+1 for daily tickets); (2) carryover ticket distribution: winners from source level, tickets at current level (or lvl+1 on final day); (3) removed `coin.rollDailyQuest` call | **ETH flow** |
| `_distributeTicketJackpot()` | ~944 | v14.0 | Added `queueLvl` parameter separating source level (for winner selection) from queue level (for ticket destination) | |
| `_distributeTicketsToBuckets()` | ~994 | v14.0 | Added `queueLvl` parameter passthrough | |
| `_distributeTicketsToBucket()` | ~1033 | v14.0 | Added `queueLvl` parameter; ticket reads from `traitBurnTicket[sourceLvl]`, queues to `queueLvl` instead of `lvl + 1` | **ETH flow** |
| `_creditDgnrsCoinflip()` | ~2148 | v14.0 | `price` replaced by `PriceLookupLib.priceForLevel(level)` | |
| `_calcDailyCoinBudget()` | ~2450 | v14.0 | `price` replaced by `PriceLookupLib.priceForLevel(level)` | |
| `consolidatePrizePools()` | ~235 | v14.0 | Formatting only |

#### Removed Functions

| Function | Milestone | Description |
|----------|-----------|-------------|
| `_clearDailyEthState()` | v14.0 | Eliminated with carryover Phase 1 removal (no longer needed -- single-pass daily jackpot) |
| `event DailyCarryoverStarted` | v14.0 | Carryover ETH distribution to winners eliminated |
| `constant coin` (IDegenerusCoin) | v14.0 | Moved to DegenerusGameStorage |
| `constant coinflip` (IBurnieCoinflip) | v14.0 | Moved to DegenerusGameStorage |
| `constant dgnrs` (IStakedDegenerusStonk) | v14.0 | Moved to DegenerusGameStorage |
| `constant DAILY_REWARD_JACKPOT_LOOTBOX_BPS` | v14.0 | Carryover lootbox budget eliminated |
| `constant DAILY_CARRYOVER_MIN_WINNERS` | v14.0 | No carryover ETH winners anymore |

---

### contracts/modules/DegenerusGameLootboxModule.sol

**Stats:** +35 / -35 lines | Milestones: v11.0, v14.0

#### New Functions

_None_

#### Modified Functions

| Function | Line | Milestone | Description | Risk |
|----------|------|-----------|-------------|------|
| `openBurnieLootbox()` | ~617 | v11.0/v14.0 | (1) `price` replaced by `PriceLookupLib.priceForLevel(level)`; (2) BURNIE lootbox 30-day cutoff replaced by `gameOverPossible` flag check -- redirects current-level tickets to far-future key space via `TICKET_FAR_FUTURE_BIT` when flag active | **ETH flow** |
| `_boonRollWeights()` | ~1037 | v14.0 | Deity pass check changed from `deityPassCount[player] == 0` to `mintPacked_[player] >> HAS_DEITY_PASS_SHIFT & 1 == 0` | |
| `_boonPoolStats()` | ~1115 | v14.0 | `price` replaced by `PriceLookupLib.priceForLevel(level)` | |

#### Removed Functions

| Function | Milestone | Description |
|----------|-----------|-------------|
| `constant coin` (IDegenerusCoin) | v14.0 | Moved to DegenerusGameStorage |
| `constant coinflip` (IBurnieCoinflip) | v14.0 | Moved to DegenerusGameStorage |
| `constant dgnrs` (IStakedDegenerusStonk) | v14.0 | Moved to DegenerusGameStorage |
| `constant BURNIE_LOOT_CUTOFF` | v11.0 | Replaced by `gameOverPossible` flag |
| `constant BURNIE_LOOT_CUTOFF_LVL0` | v11.0 | Replaced by `gameOverPossible` flag |

---

### contracts/modules/DegenerusGameMintModule.sol

**Stats:** +312 / -312 lines (net: major restructuring) | Milestones: v11.0, v13.0, v14.0

#### New Functions

| Function | Line | Milestone | Description | Risk |
|----------|------|-----------|-------------|------|
| `_questMint(address,uint32,bool,uint256)` | ~1104 | v13.0 | Routes quest progress to DegenerusQuests for standalone mint path. ETH rewards returned; BURNIE rewards creditFlipped internally by handler. | **ETH flow** |

#### Modified Functions

| Function | Line | Milestone | Description | Risk |
|----------|------|-----------|-------------|------|
| `_purchaseBurnTickets()` | ~601 | v11.0 | 30-day `COIN_PURCHASE_CUTOFF` replaced by `gameOverPossible` flag revert (`GameOverPossible` error) | |
| `_purchaseFor()` | ~621 | v14.0 | Major restructuring: (1) `purchaseLevel` computed as `cachedJpFlag ? cachedLevel : cachedLevel + 1` (was always `level + 1`); (2) `price` replaced by `PriceLookupLib.priceForLevel(purchaseLevel)` (was `price` storage); (3) lootbox base level set to `cachedLevel + 1` (was `level + 2`); (4) ticket purchase, lootbox setup, quest handling, score computation, x00 bonus, and ticket queuing all reordered for compute-once pattern; (5) single `quests.handlePurchase()` call replaces separate `coin.notifyQuestMint` + `coin.notifyQuestLootBox`; (6) `_playerActivityScore` computed once post-action; (7) x00 century bonus uses cached score; (8) ticket queuing moved from `_callTicketPurchase` to `_purchaseFor` (post-score); (9) lootbox EV score written using cached score; (10) all flip credits batched into single `coinflip.creditFlip`; (11) claimable shortfall reads `initialClaimable` (was `claimableWinnings[buyer]` -- extra SLOAD) | **ETH flow** |
| `_callTicketPurchase()` | ~864 | v14.0 | Return signature added: `(bonusCredit, adjustedQty32, targetLevel, ethMintUnits, burnieMintUnits)`; x00 century bonus logic removed (moved to `_purchaseFor`); ticket queuing removed (moved to `_purchaseFor`); added `cachedLevel, cachedJpFlag` parameters to avoid re-reading storage; `price` replaced by `PriceLookupLib.priceForLevel(targetLevel)`; cached `compressedJackpotFlag` and `jackpotCounter` | |
| `_purchaseBurnieLootbox()` | ~1040 | v14.0 | `coin.notifyQuestMint` replaced by `_questMint`; `price` replaced by `PriceLookupLib.priceForLevel(level + 1)` | |

#### Removed Functions

| Function | Milestone | Description |
|----------|-----------|-------------|
| `constant coin` (IDegenerusCoin) | v14.0 | Moved to DegenerusGameStorage |
| `constant coinflip` (IBurnieCoinflip) | v14.0 | Moved to DegenerusGameStorage |
| `constant affiliate` (IDegenerusAffiliate) | v14.0 | Moved to DegenerusGameStorage |
| `constant COIN_PURCHASE_CUTOFF` | v11.0 | Replaced by `gameOverPossible` flag |
| `constant COIN_PURCHASE_CUTOFF_LVL0` | v11.0 | Replaced by `gameOverPossible` flag |
| `error CoinPurchaseCutoff()` | v11.0 | Replaced by `error GameOverPossible()` |

#### Storage Changes

_None_

#### Comment-only Changes

| Location | Milestone | Description |
|----------|-----------|-------------|
| Class declaration | v14.0 | Changed `extends DegenerusGameStorage` to `extends DegenerusGameMintStreakUtils` |
| Error `GameOverPossible` NatSpec | v11.0 | Documents drip projection semantics |

---

### contracts/modules/DegenerusGameMintStreakUtils.sol

**Stats:** +104 lines (new functions) | Milestones: v14.0

#### New Functions

| Function | Line | Milestone | Description | Risk |
|----------|------|-----------|-------------|------|
| `_activeTicketLevel()` | 70 | v14.0 | Moved from DegenerusGame.sol. Returns `jackpotPhaseFlag ? level : level + 1`. | |
| `_playerActivityScore(address,uint32,uint24)` | 81 | v14.0 | Moved from DegenerusGame.sol and DegeneretteModule. Shared activity score computation with explicit questStreak and streakBaseLevel parameters. Components: deity pass (75% flat), mint streak (max 50%), mint count (max 25%), quest streak (max 100%), affiliate bonus, pass/whale bonus. | |
| `_playerActivityScore(address,uint32)` | 160 | v14.0 | Convenience wrapper using `_activeTicketLevel()` as streakBaseLevel. | |

#### Modified Functions

_None (existing `_recordMintStreakForLevel` and `_mintStreakEffective` unchanged)_

---

### contracts/modules/DegenerusGameWhaleModule.sol

**Stats:** +276 / -276 lines | Milestones: v14.0

#### New Functions

_None_

#### Modified Functions

| Function | Line | Milestone | Description | Risk |
|----------|------|-----------|-------------|------|
| `purchaseDeityPass()` | ~532 | v14.0 | `deityPassCount[buyer] != 0` replaced by `mintPacked_[buyer] >> HAS_DEITY_PASS_SHIFT & 1 != 0`; deity pass write changed from `deityPassCount[buyer] = 1` to `BitPackingLib.setPacked(mintPacked_[buyer], HAS_DEITY_PASS_SHIFT, 1, 1)` | |
| `purchaseLazyPass()` | ~354 | v14.0 | Deity pass check changed from `deityPassCount[buyer] != 0` to `mintPacked_[buyer] >> HAS_DEITY_PASS_SHIFT & 1 != 0` | |
| `_recordLootboxEntry()` | ~840 | v14.0 | `playerActivityScore` formatting only | |
| `_applyLootboxBoostOnPurchase()` | ~895 | v14.0 | Formatting only | |
| `_recordLootboxMintDay()` | ~921 | v14.0 | Formatting only | |

#### Removed Functions

| Function | Milestone | Description |
|----------|-----------|-------------|
| `constant affiliate` (IDegenerusAffiliate) | v14.0 | Moved to DegenerusGameStorage |
| `constant dgnrs` (IStakedDegenerusStonk) | v14.0 | Moved to DegenerusGameStorage |

#### Comment-only Changes

| Location | Milestone | Description |
|----------|-----------|-------------|
| Multiple locations | v14.0 | Extensive formatting: long lines broken across multiple lines, brace styling, unchecked blocks (no logic changes) |

---

### contracts/storage/DegenerusGameStorage.sol

**Stats:** +109 / -109 lines | Milestones: v11.0, v14.0

#### New Functions

| Function | Line | Milestone | Description | Risk |
|----------|------|-----------|-------------|------|
| `_mintCountBonusPoints(uint24,uint24)` | ~1618 | v14.0 | Moved from DegenerusGame.sol and DegeneretteModule. Pure function: `(mintCount * 25) / currLevel`, capped at 25. | |
| `interface IDegenerusQuestView` | ~113 | v14.0 | Quest view interface moved from DegenerusGame.sol and DegeneretteModule | |

#### Storage Changes

| Variable | Type | Milestone | Description |
|----------|------|-----------|-------------|
| `gameOverPossible` | `bool` (new) | v11.0 | Drip projection flag. When true: BURNIE ticket purchases revert, BURNIE lootbox current-level tickets redirect to far-future. Evaluated at L10+ purchase-phase days. |
| `coin` | `IDegenerusCoin constant` (centralized) | v14.0 | Moved from DegenerusGame, AdvanceModule, JackpotModule, LootboxModule, MintModule, DegeneretteModule |
| `coinflip` | `IBurnieCoinflip constant` (centralized) | v14.0 | Moved from DegenerusGame, AdvanceModule, JackpotModule, LootboxModule, MintModule |
| `quests` | `IDegenerusQuests constant` (new) | v13.0/v14.0 | Centralized quest contract reference |
| `questView` | `IDegenerusQuestView constant` (centralized) | v14.0 | Moved from DegenerusGame and DegeneretteModule |
| `affiliate` | `IDegenerusAffiliate constant` (centralized) | v14.0 | Moved from DegenerusGame, MintModule, DegeneretteModule, WhaleModule |
| `dgnrs` | `IStakedDegenerusStonk constant` (centralized) | v14.0 | Moved from DegenerusGame, EndgameModule, JackpotModule, LootboxModule, WhaleModule, GameOverModule |
| `DEITY_PASS_ACTIVITY_BONUS_BPS` | `uint16 constant = 8000` (centralized) | v14.0 | Moved from DegenerusGame and DegeneretteModule |
| `PASS_STREAK_FLOOR_POINTS` | `uint16 constant = 50` (centralized) | v14.0 | Moved from DegenerusGame and DegeneretteModule |
| `PASS_MINT_COUNT_FLOOR_POINTS` | `uint16 constant = 25` (centralized) | v14.0 | Moved from DegenerusGame and DegeneretteModule |
| `price` | `uint128` (removed) | v14.0 | Storage variable fully removed. All pricing now deterministic from `PriceLookupLib.priceForLevel(level)`. Slot 1 layout changed. |
| `dailyEthPhase` | `uint8` (removed) | v14.0 | Carryover ETH phase state eliminated with single-pass daily jackpot. Slot 0 layout changed. |
| `dailyEthPoolBudget` | `uint256` (removed) | v14.0 | Daily ETH pool budget eliminated (no more multi-call jackpot split). |
| `dailyCarryoverEthPool` | `uint256` (removed) | v14.0 | Carryover ETH pool eliminated with redesigned carryover (tickets-only). |
| `dailyCarryoverWinnerCap` | `uint16` (removed) | v14.0 | No carryover ETH winners anymore. |
| `deityPassCount` | `mapping(address => uint16)` (removed) | v14.0 | Replaced by single bit (HAS_DEITY_PASS_SHIFT=184) in `mintPacked_`. |

#### Comment-only Changes

| Location | Milestone | Description |
|----------|-----------|-------------|
| Slot 0 layout comment | v14.0 | `dailyEthPhase` removed from byte 30; `compressedJackpotFlag` moved from byte 31 to byte 30; total updated from 32 to 31 bytes |
| Slot 1 layout comment | v14.0 | `price` removed; `ticketWriteSlot` moved from byte 22 to byte 6; total updated from 25 to 9 bytes used |
| Initial state documentation | v14.0 | `price = 0.01 ether` line removed from initialization notes |

---

## Audit Scope Summary

| Category | Count |
|----------|-------|
| New functions | 17 |
| Modified functions | 37 |
| Removed functions | 60 |
| Storage changes | 19 |
| Comment-only changes | 21 |
| **Total audit items** | **134** |

**Breakdown by milestone:**

| Milestone | New | Modified | Removed | Storage |
|-----------|-----|----------|---------|---------|
| v11.0 | 3 | 5 | 4 | 2 |
| v13.0 | 8 | 12 | 22 | 4 |
| v14.0 | 6 | 20 | 34 | 13 |

_Note: Some functions span multiple milestones (latest milestone listed as primary). The v14.0 "removed" count is high because of constant centralization into DegenerusGameStorage (functionally a refactor, not behavioral change)._

---

## High-Risk Changes

Functions touching ETH flow, RNG consumption, or access control that require priority review in Phase 165:

### ETH Flow

| # | Contract | Function | Milestone | Description |
|---|----------|----------|-----------|-------------|
| 1 | DegenerusGameAdvanceModule | `_evaluateGameOverPossible` | v11.0 | Controls whether BURNIE tickets/lootbox are gated -- affects pool composition |
| 2 | DegenerusGameAdvanceModule | `advanceGame()` loop | v11.0-v14.0 | Quest rolling, level quest lifecycle, carryover resume removal, price source change |
| 3 | DegenerusGameJackpotModule | `payDailyJackpot()` | v14.0 | Carryover ETH distribution eliminated; reserve now 0.5% (was 1%); flows to nextPool instead of trait-based ETH winners |
| 4 | DegenerusGameJackpotModule | `payDailyJackpotCoinAndTickets()` | v14.0 | Carryover tickets now queue at current level (was source+1); final day routes to lvl+1 |
| 5 | DegenerusGameJackpotModule | `_distributeTicketsToBucket()` | v14.0 | Separated source level (winner selection) from queue level (ticket destination) |
| 6 | DegenerusGameMintModule | `_purchaseFor()` | v14.0 | Complete restructure: purchaseLevel calculation, compute-once score, batched flip credits, x00 bonus with cached score |
| 7 | DegenerusGameMintModule | `_callTicketPurchase()` | v14.0 | Returns quest units; x00 bonus and ticket queuing moved to caller |
| 8 | DegenerusGameLootboxModule | `openBurnieLootbox()` | v11.0 | 30-day cutoff replaced by gameOverPossible flag redirect |
| 9 | DegenerusQuests | `_handleLevelQuestProgress()` | v13.0 | Credits 800 BURNIE via coinflip on level quest completion |
| 10 | DegenerusQuests | `handlePurchase()` | v14.0 | Combined handler routing ETH/BURNIE/lootbox rewards with internal creditFlip |
| 11 | DegenerusAffiliate | `payAffiliate()` | v13.0 | Winner-takes-all 75/20/5 roll replaces 3-tier distribution |
| 12 | BurnieCoin | `burnDecimator()` | v14.0 | Simplified quest reward flow + activity score bonus |

### RNG Consumption

| # | Contract | Function | Milestone | Description |
|---|----------|----------|-----------|-------------|
| 13 | DegenerusGameAdvanceModule | `advanceGame()` | v13.0 | `quests.rollDailyQuest` now called directly (was via BurnieCoin); `quests.rollLevelQuest` uses keccak256 of rngWord + tag |
| 14 | DegenerusAffiliate | `payAffiliate()` | v13.0 | Simplified to `mod 20` roll (was weighted cumulative distribution) |

### Access Control

| # | Contract | Function | Milestone | Description |
|---|----------|----------|-----------|-------------|
| 15 | BurnieCoin | `modifier onlyGame` | v13.0 | Replaces both `onlyDegenerusGameContract` and `onlyTrustedContracts` (AFFILIATE removed) |
| 16 | BurnieCoinflip | `modifier onlyFlipCreditors` | v13.0 | COIN replaced by QUESTS in allowed callers |
| 17 | DegenerusQuests | `modifier onlyCoin` | v13.0 | Expanded from COIN+COINFLIP to COIN+COINFLIP+GAME+AFFILIATE |
| 18 | DegenerusQuests | `rollDailyQuest()` | v13.0 | Access changed from `onlyCoin` to `onlyGame` |
| 19 | DegenerusGame | `recordMintQuestStreak()` | v13.0 | Access changed from COIN to GAME (MintModule delegatecall) |
| 20 | DegenerusGame | `decWindow()` | v11.0 | Simplified: no longer checks RNG lock or gameOverImminent; returns raw flag only |
