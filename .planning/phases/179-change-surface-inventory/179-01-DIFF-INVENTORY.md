# Phase 179: Change Surface Inventory -- Full Diff

**Baseline:** e2cd1b2b (v15.0 Phase 167 final)
**HEAD:** df283518 (chore: clean up archived planning phases and update project state)
**Scope:** contracts/ directory only (33 files, 766 added / 1002 deleted)

## Summary

| Category | Files | Lines Changed (added+deleted) |
|----------|-------|-------------------------------|
| HEAVY (>50 lines) | 4 | 1353 |
| MEDIUM (10-50 lines) | 14 | 359 |
| LIGHT (<10 lines) | 15 | 56 |
| **Total** | **33** | **1768 (766+, 1002-)** |

## Milestone Attribution Key

| Tag | Description | Commits |
|-----|-------------|---------|
| v16.0-repack | Storage slots 0-2 repack, currentPrizePool helpers | ed057810, 622cc1ae |
| v16.0-endgame-delete | EndgameModule elimination, functions moved to JackpotModule/WhaleModule/AdvanceModule | 4f13ab83, 0009d207 |
| v17.0-affiliate-cache | Affiliate bonus cache, decimator rescale, gameover RNG fix | f730bc0c, f76473d6, 32b36e4f, fc703475, 76ea45d1, 3c3245d5, 08e80cef |
| v17.1-comments | Comment correctness sweep (56 fixes, 29 contracts) | 9c3e31bd |
| rngBypass-refactor | rngBypass parameter replaces phaseTransitionActive guard | f750be67, 56869a24, d8fa9f33 |
| pre-v16.0-manual | Vestigial removal, carryover gas, gameover revert fix | cdac1bed, 3ff2977c, e2f5f30f |

## Per-Contract Diff Inventory

---

### DegenerusGameEndgameModule.sol
**Path:** contracts/modules/DegenerusGameEndgameModule.sol
**Lines:** +0 / -571
**Attribution:** v16.0-endgame-delete

**ENTIRE FILE DELETED** (571 lines removed)

Functions removed vs migrated:
| Function | Disposition | Destination |
|----------|------------|-------------|
| `rewardTopAffiliate(uint24)` | Inlined | AdvanceModule._rewardTopAffiliate |
| `runRewardJackpots(uint24,uint256)` | Migrated | JackpotModule.runRewardJackpots |
| `_runBafJackpot(...)` | Migrated | JackpotModule._runBafJackpot |
| `_addClaimableEth(...)` | Migrated | JackpotModule (absorbed into reward logic) |
| `_awardJackpotTickets(...)` | Migrated | JackpotModule._awardJackpotTickets |
| `_jackpotTicketRoll(...)` | Migrated | JackpotModule._jackpotTicketRoll |
| `claimWhalePass(address)` | Migrated | WhaleModule.claimWhalePass |

---

### DegenerusGameJackpotModule.sol
**Path:** contracts/modules/DegenerusGameJackpotModule.sol
**Lines:** +363 / -140
**Attribution:** v16.0-endgame-delete, v16.0-repack, rngBypass-refactor, v17.1-comments, pre-v16.0-manual

**Changes by function/section:**

**Imports (v16.0-endgame-delete):**
```diff
+import {IDegenerusJackpots} from "../interfaces/IDegenerusJackpots.sol";
+import {IDegenerusGame} from "../interfaces/IDegenerusGame.sol";
```

**NatSpec header (v17.1-comments):**
```diff
+ *      3. `payDailyCoinJackpot` -- BURNIE jackpot distribution to near-future ticket holders.
```

**New event RewardJackpotsSettled (v16.0-endgame-delete):**
```diff
+    event RewardJackpotsSettled(
+        uint24 indexed lvl,
+        uint256 futurePool,
+        uint256 claimableDelta
+    );
```

**New constants (v16.0-endgame-delete):**
```diff
+    IDegenerusJackpots internal constant jackpots = IDegenerusJackpots(ContractAddresses.JACKPOTS);
+    uint256 private constant SMALL_LOOTBOX_THRESHOLD = 0.5 ether;
```

**runTerminalJackpot NatSpec (v17.1-comments):**
```diff
-    /// @dev Called via IDegenerusGame(address(this)) from EndgameModule and GameOverModule.
+    /// @dev Called via IDegenerusGame(address(this)) from JackpotModule (runRewardJackpots) and GameOverModule.
```

**payDailyJackpot NatSpec (v17.1-comments):**
```diff
-    ///      - Day 1 of each level: BURNIE-only distribution via _executeJackpot.
-    ///      - Rolls daily quest at the end.
+    ///      - Day 1 of each level: no early-burn distribution (ethDaySlice=0, _executeJackpot no-ops on empty pool).
```

**payDailyJackpot body (v16.0-repack):**
All `currentPrizePool` direct reads replaced with `_getCurrentPrizePool()` helper:
```diff
-                uint256 poolSnapshot = currentPrizePool;
+                uint256 poolSnapshot = _getCurrentPrizePool();
-                currentPrizePool -= dailyLootboxBudget;
+                _setCurrentPrizePool(_getCurrentPrizePool() - dailyLootboxBudget);
-                currentPrizePool -= paidDailyEth;
+                _setCurrentPrizePool(_getCurrentPrizePool() - paidDailyEth);
```

**Carryover source offset (pre-v16.0-manual / carryover gas):**
Removed `_selectCarryoverSourceOffset`, `_highestCarryoverSourceOffset`, `_hasActualTraitTickets` (82 lines deleted). Replaced with inline random offset calculation:
```diff
-                    initCarryoverSourceOffset = _selectCarryoverSourceOffset(lvl, winningTraitsPacked, randWord, counter);
-                    if (initCarryoverSourceOffset != 0) { carryoverSourceLevel = lvl + uint24(initCarryoverSourceOffset); }
+                    sourceLevelOffset = uint8((uint256(keccak256(abi.encodePacked(randWord, DAILY_CARRYOVER_SOURCE_TAG, counter))) % DAILY_CARRYOVER_MAX_OFFSET) + 1);
+                    sourceLevel = lvl + uint24(sourceLevelOffset);
```
Reserve slice logic simplified (moved inside `!isEarlyBirdDay` block, removed conditional on offset != 0).

**payDailyCoinJackpotAndTickets (rngBypass-refactor):**
```diff
-            _queueTickets(winner, baseLevel + levelOffset, ticketCount);
+            _queueTickets(winner, baseLevel + levelOffset, ticketCount, true);
```
All `_queueTickets` calls updated with `rngBypass` parameter (`true` for jackpot awards during RNG-locked window).

**consolidatePrizePools (v16.0-repack):**
```diff
-        currentPrizePool += _getNextPrizePool();
+        _setCurrentPrizePool(_getCurrentPrizePool() + _getNextPrizePool());
-                    currentPrizePool += moveWei;
+                    _setCurrentPrizePool(_getCurrentPrizePool() + moveWei);
-        _creditDgnrsCoinflip(currentPrizePool);
+        _creditDgnrsCoinflip(_getCurrentPrizePool());
```

**_distributeYieldSurplus NatSpec (v17.1-comments):**
```diff
-    ///      23% each to DGNRS, vault, and charity claimable, 23% yield accumulator (~8% buffer).
+    ///      23% each to sDGNRS, vault, and charity (GNRUS) claimable, 23% yield accumulator (~8% buffer).
```

**_distributeYieldSurplus body (v16.0-repack):**
```diff
-        uint256 obligations = currentPrizePool +
+        uint256 obligations = _getCurrentPrizePool() +
```

**processTicketBatch (rngBypass-refactor):**
```diff
-                _queueTickets(winner, queueLvl, uint32(units));
+                _queueTickets(winner, queueLvl, uint32(units), true);
-        _queueTickets(player, calc.targetLevel, calc.ticketCount);
+        _queueTickets(player, calc.targetLevel, calc.ticketCount, true);
```

**Stale NatSpec removal (v17.1-comments):**
```diff
-    /// @dev Distributes jackpot loot box rewards to winners based on trait buckets.
-    ///      Awards tickets only (no BURNIE) using jackpot loot box mechanics.
```

**traitBurnTicket layout comment (v17.1-comments):**
```diff
-        // Layout assumption: traitBurnTicket is mapping(uint24 => address[256]).
+        // Layout assumption: traitBurnTicket is mapping(uint24 => address[][256]).
```

**Deleted functions (pre-v16.0-manual / carryover gas):**
- `_hasActualTraitTickets(uint24, uint32)` -- 82 lines removed
- `_highestCarryoverSourceOffset(uint24, uint32)` -- included above
- `_selectCarryoverSourceOffset(uint24, uint32, uint256, uint8)` -- included above

**New: runRewardJackpots + _runBafJackpot (v16.0-endgame-delete):**
~305 lines added. Migrated from EndgameModule with RewardJackpotsSettled event, auto-rebuy reconciliation, and BAF large/small winner split payout logic.

---

### DegenerusGameAdvanceModule.sol
**Path:** contracts/modules/DegenerusGameAdvanceModule.sol
**Lines:** +95 / -46
**Attribution:** v16.0-endgame-delete, v16.0-repack, rngBypass-refactor, v17.0-affiliate-cache, v17.1-comments, pre-v16.0-manual

**Changes by function/section:**

**Imports (v16.0-endgame-delete):**
```diff
-    IDegenerusGameEndgameModule,
```

**New event AffiliateDgnrsReward (v16.0-endgame-delete):**
```diff
+    event AffiliateDgnrsReward(address indexed affiliate, uint24 indexed level, uint256 dgnrsAmount);
```

**DEPLOY_IDLE_TIMEOUT_DAYS comment (v17.1-comments):**
```diff
-    uint48 private constant DEPLOY_IDLE_TIMEOUT_DAYS = 365;
+    uint48 private constant DEPLOY_IDLE_TIMEOUT_DAYS = 365; // Level-0 only; level 1+ uses hardcoded 120 days
```

**New constants (v16.0-endgame-delete):**
```diff
+    uint16 private constant AFFILIATE_POOL_REWARD_BPS = 100;
+    uint16 private constant AFFILIATE_DGNRS_LEVEL_BPS = 500;
```

**advanceGame NatSpec (v17.1-comments):**
```diff
-    ///         Caller receives ~0.01 ETH worth of BURNIE as flip credit.
+    ///         Caller receives ~0.005 ETH worth of BURNIE as flip credit.
```

**advanceGame formatting (v17.1-comments):**
Long line splits for `PriceLookupLib.priceForLevel(lvl)` in 3 locations (4 hunks).

**advanceGame level transition flow (v16.0-endgame-delete + rngBypass-refactor):**
```diff
-                if (!poolConsolidationDone) {
-                    levelPrizePool[purchaseLevel] = _getNextPrizePool();
-                    _applyTimeBasedFutureTake(ts, purchaseLevel, rngWord);
-                    _consolidatePrizePools(purchaseLevel, rngWord);
-                    poolConsolidationDone = true;
-                }
+                levelPrizePool[purchaseLevel] = _getNextPrizePool();
+                _applyTimeBasedFutureTake(ts, purchaseLevel, rngWord);
+                _consolidatePrizePools(purchaseLevel, rngWord);
+                _runRewardJackpots(lvl, rngWord);
```
Removed `poolConsolidationDone` guard; added `_runRewardJackpots` at consolidation point (moved from jackpot phase end).

**jackpot phase end (v16.0-endgame-delete):**
```diff
-                    _rewardTopAffiliate(lvl);
-                    _runRewardJackpots(lvl, rngWord);
```
Both calls moved earlier in the flow (to level transition).

**questEntropy formatting (v17.1-comments):**
```diff
-                uint256 questEntropy = uint256(keccak256(abi.encodePacked(rngWordByDay[day], "LEVEL_QUEST")));
+                uint256 questEntropy = uint256(keccak256(abi.encodePacked(rngWordByDay[day], "LEVEL_QUEST")));
```
(Reformatted to multi-line)

**Module table (v16.0-endgame-delete + v17.1-comments):**
```diff
-      |  * ContractAddresses.GAME_ENDGAME_MODULE  - Endgame settlement (payouts, wipes, ContractAddresses.JACKPOTS)
-      |  * ContractAddresses.GAME_WHALE_MODULE    - Whale bundle purchases
+      |  * ContractAddresses.GAME_WHALE_MODULE    - Whale bundle purchases and whale pass claims
```

**_rewardTopAffiliate inlined (v16.0-endgame-delete):**
Was delegatecall to EndgameModule, now inlined with full logic:
```diff
-        (bool ok, bytes memory data) = ContractAddresses.GAME_ENDGAME_MODULE.delegatecall(
-            abi.encodeWithSelector(IDegenerusGameEndgameModule.rewardTopAffiliate.selector, lvl)
-        );
-        if (!ok) _revertDelegate(data);
+        (address top, ) = affiliate.affiliateTop(lvl);
+        if (top != address(0)) { ... dgnrs.transferFromPool ... }
+        levelDgnrsAllocation[lvl] = (remainingPool * AFFILIATE_DGNRS_LEVEL_BPS) / 10_000;
```
New NatSpec explains the level snapshot and per-level DGNRS allocation mechanics.

**_runRewardJackpots target (v16.0-endgame-delete):**
```diff
-            .GAME_ENDGAME_MODULE
+            .GAME_JACKPOT_MODULE
-                    IDegenerusGameEndgameModule.runRewardJackpots.selector,
+                    IDegenerusGameJackpotModule.runRewardJackpots.selector,
```

**_payDailyCoinJackpot NatSpec (v17.1-comments):**
```diff
-    ///      Awards 0.5% of prize pool target in BURNIE to current and future ticket holders.
+    ///      Awards 0.5% of prize pool target in BURNIE to one randomly selected near-future level [lvl, lvl+4].
```

**rngGate deity pass formatting (v17.1-comments):**
```diff
-            if (mintData >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 != 0) return;
+            if ((mintData >> BitPackingLib.HAS_DEITY_PASS_SHIFT) & 1 != 0) return;
```

**RNG Word Usage Table (v17.1-comments):**
File:line citations replaced with function-name references:
```diff
-    // 0        Coinflip win/loss           rngWord & 1                       BurnieCoinflip.sol:809
+    // 0        Coinflip win/loss           rngWord & 1                       BurnieCoinflip._resolveDay
```
(7 line references updated)

**_applyDailyRng revert comment (v17.1-comments):**
```diff
-            // Resolve gambling burn period if pending (mirrors rngGate lines 792-802)
+            // Resolve gambling burn period if pending (mirrors rngGate redemption resolution)
```
(2 locations)

**_applyDailyRng return (pre-v16.0-manual / gameover revert):**
```diff
-            return 0;
+            revert RngNotReady();
```

**_processPhaseTransition NatSpec (v17.1-comments):**
```diff
-    ///      Deity pass holders get virtual trait-targeted tickets at jackpot resolution time
-    ///      (zero gas cost here). Vault addresses (DGNRS, VAULT) get generic queued tickets.
+    ///      Vault addresses (SDGNRS, VAULT) get generic queued tickets.
```

**_processPhaseTransition rngBypass (rngBypass-refactor):**
```diff
-            VAULT_PERPETUAL_TICKETS
+            VAULT_PERPETUAL_TICKETS,
+            true
```
(2 calls to _queueTickets updated)

**_rewardTopAffiliate moved (v16.0-endgame-delete):**
```diff
+            _rewardTopAffiliate(lvl);
             level = lvl;
```
Called before `level = lvl` at RNG request point.

**_evaluateGameOverPossible formatting (v17.1-comments):**
Function signature and body reformatted for line length.

---

### DegenerusGameStorage.sol
**Path:** contracts/storage/DegenerusGameStorage.sol
**Lines:** +78 / -60
**Attribution:** v16.0-repack, v16.0-endgame-delete, rngBypass-refactor, v17.1-comments

**Changes by section:**

**NatSpec header (v16.0-endgame-delete + v17.1-comments):**
```diff
- *   - DegenerusGameEndgameModule (delegatecall module)
+ *   - DegenerusGameAdvanceModule (delegatecall module)
+   (plus 5 additional modules listed)
```

**Slot 0 layout (v16.0-repack):**
`poolConsolidationDone` removed, `ticketsFullyProcessed` and `gameOverPossible` moved from Slot 1 to Slot 0:
```diff
- * | [23:24] poolConsolidationDone    bool     Pool consolidation executed flag   |
- * | [24:25] lastPurchaseDay          bool     Prize target met flag              |
- * | [25:26] decWindowOpen            bool     Decimator window latch             |
- * | [26:27] rngLockedFlag            bool     Daily RNG lock (jackpot window)    |
- * | [27:28] phaseTransitionActive    bool     Level transition in progress       |
- * | [28:29] gameOver                 bool     Terminal state flag                |
- * | [29:30] dailyJackpotCoinTicketsPending bool Split jackpot pending flag       |
- * | [30:31] compressedJackpotFlag    uint8    0=normal, 1=compressed, 2=turbo    |
+ * | [23:24] lastPurchaseDay          bool     Prize target met flag              |
+ * | [24:25] decWindowOpen            bool     Decimator window latch             |
+ * | [25:26] rngLockedFlag            bool     Daily RNG lock (jackpot window)    |
+ * | [26:27] phaseTransitionActive    bool     Level transition in progress       |
+ * | [27:28] gameOver                 bool     Terminal state flag                |
+ * | [28:29] dailyJackpotCoinTicketsPending bool Split jackpot pending flag       |
+ * | [29:30] compressedJackpotFlag    uint8    0=normal, 1=compressed, 2=turbo    |
+ * | [30:31] ticketsFullyProcessed    bool     Read slot fully drained flag       |
+ * | [31:32] gameOverPossible         bool     Drip projection endgame flag       |
```
Slot 0 now full: 32/32 bytes used.

**Slot 1 layout (v16.0-repack):**
```diff
- * | EVM SLOT 1 (32 bytes) -- Double-Buffer Fields
+ * | EVM SLOT 1 (32 bytes) -- Double-Buffer Fields + Current Prize Pool
- * | [7:8]   ticketsFullyProcessed    bool     Read slot fully drained flag
- * | [8:9]   prizePoolFrozen          bool     Prize pool freeze active flag
- * | [9:32]  <padding>                         23 bytes unused
+ * | [7:8]   prizePoolFrozen          bool     Prize pool freeze active flag
+ * | [8:24]  currentPrizePool         uint128  Active prize pool for current level
+ * | [24:32] <padding>                         8 bytes unused
```
`ticketsFullyProcessed` moved to Slot 0; `currentPrizePool` packed in (uint256 -> uint128).

**Slot 2 removed (v16.0-repack):**
```diff
- * | EVM SLOT 2 (32 bytes) -- Current Prize Pool
- * | [0:32]  currentPrizePool         uint256  Active prize pool for current level
-
- * SLOTS 3+ -- Full-width variables, arrays, and mappings
+ * SLOTS 2+ -- Full-width variables, arrays, and mappings
```

**Storage variable declarations (v16.0-repack):**
- `poolConsolidationDone` removed (6 lines)
- `ticketsFullyProcessed` moved after `compressedJackpotFlag` (with updated NatSpec)
- `gameOverPossible` moved after `ticketsFullyProcessed`
- `currentPrizePool` changed from `uint256` to `uint128`, moved after `prizePoolFrozen`

**mintPacked_ NatSpec (v17.1-comments):**
```diff
-    ///      Layout defined by ETH_* constants in DegenerusGame:
-    ///      - Tracks mint counts, bonuses, and eligibility flags.
+    ///      Layout defined by constants in BitPackingLib and MintStreakUtils.
+    ///      Tracks mint counts, bonuses, eligibility flags, deity pass, and affiliate bonus cache.
-    ///      Bit manipulation requires careful masking (done in DegenerusGame).
+    ///      Bit manipulation requires careful masking (done via BitPackingLib shifts and masks).
```

**_queueTickets rngBypass (rngBypass-refactor):**
```diff
-        uint32 quantity
+        uint32 quantity,
+        bool rngBypass
-        if (isFarFuture && rngLockedFlag && !phaseTransitionActive) revert RngLocked();
+        if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked();
```
(Applied to `_queueTickets`, `_queueTicketsScaled`, `_queueTicketRange`, `_queueLootboxTickets` -- 4 functions)

**Slot 1 section comment (v16.0-repack):**
```diff
-    // EVM SLOT 1: Price and Double-Buffer Fields
+    // EVM SLOT 1: Double-Buffer Fields + Current Prize Pool
```

**New helpers (v16.0-repack):**
```diff
+    function _getCurrentPrizePool() internal view returns (uint256)
+    function _setCurrentPrizePool(uint256 val) internal
```

**_callRecordTicketPurchase (rngBypass-refactor):**
```diff
-        _queueTicketRange(player, ticketStartLevel, 10, ticketsPerLevel);
+        _queueTicketRange(player, ticketStartLevel, 10, ticketsPerLevel, false);
```

---

### DegenerusGameWhaleModule.sol
**Path:** contracts/modules/DegenerusGameWhaleModule.sol
**Lines:** +44 / -4
**Attribution:** v16.0-endgame-delete, rngBypass-refactor, v17.1-comments

**New event WhalePassClaimed (v16.0-endgame-delete):**
```diff
+    event WhalePassClaimed(address indexed player, address indexed caller, uint256 halfPasses, uint24 startLevel);
```

**Ticket queue comment (v17.1-comments):**
```diff
-        // Queue tickets: 40/lvl for bonus levels (passLevel to 10), 2/lvl for the rest
+        // Queue tickets: 40*quantity/lvl for bonus levels (passLevel to 10), 2*quantity/lvl for the rest
```

**_queueTickets rngBypass (rngBypass-refactor):**
All 4 calls updated: `_queueTickets(buyer, lvl, ..., false)` in purchaseWhaleBundle, _claimWhalePassTickets, purchaseDeityPass.

**New: claimWhalePass (v16.0-endgame-delete):**
33 lines added. Migrated from EndgameModule:
```solidity
function claimWhalePass(address player) external {
    if (gameOver) revert E();
    uint256 halfPasses = whalePassClaims[player];
    if (halfPasses == 0) return;
    whalePassClaims[player] = 0;
    uint24 startLevel = level + 1;
    _applyWhalePassStats(player, startLevel);
    emit WhalePassClaimed(player, msg.sender, halfPasses, startLevel);
    _queueTicketRange(player, startLevel, 100, uint32(halfPasses), false);
}
```

---

### BurnieCoin.sol
**Path:** contracts/BurnieCoin.sol
**Lines:** +3 / -35
**Attribution:** v17.1-comments

**Removed stale struct NatSpec (8 lines):**
Deleted orphan `@notice` for Leaderboard entry and Outcome record structs that no longer exist in this contract.

**Removed stale BOUNTY STATE block (24 lines):**
Deleted storage layout table and variable NatSpec for `currentBounty`, `biggestFlipEver`, `bountyOwedTo` -- these variables live in BurnieCoinflip.

**vaultEscrow NatSpec:**
```diff
-    /// @dev Called by game contract and modules to credit virtual BURNIE to the vault.
+    /// @dev Called by GAME (delegatecall modules) or VAULT to credit virtual BURNIE to the vault.
```

**burnFromForGame NatSpec:**
```diff
-    /// @dev Access: DegenerusGame, game, or affiliate.
+    /// @dev Access: GAME only (onlyGame modifier).
```

---

### ContractAddresses.sol
**Path:** contracts/ContractAddresses.sol
**Lines:** +18 / -18
**Attribution:** v16.0-endgame-delete, rngBypass-refactor

Address values shuffled for redeployment. `GAME_ENDGAME_MODULE` address updated (module still declared but points to new deploy address). All other contract addresses changed to new deployment values.

---

### WrappedWrappedXRP.sol
**Path:** contracts/WrappedWrappedXRP.sol
**Lines:** +21 / -12
**Attribution:** v17.1-comments

**decimals NatSpec:**
```diff
-    /// @notice Number of decimals (matching wXRP standard)
+    /// @notice Number of decimals
```

**New constant WXRP_SCALING:**
```diff
+    uint256 private constant WXRP_SCALING = 1e12;
```

**wXRPReserves NatSpec:**
```diff
-    /// @notice Actual wXRP reserves held by this contract
+    /// @notice Actual wXRP reserves held by this contract (in WWXRP-equivalent 18-decimal units)
```

**unwrap function:**
Updated NatSpec to describe 18->6 decimal conversion. Added `wXRPAmount = amount / WXRP_SCALING` conversion and zero-check before transfer.

**donate function:**
Updated NatSpec to specify 6-decimal input. Added `amount * WXRP_SCALING` scaling on reserve update.

---

### DegenerusGameMintModule.sol
**Path:** contracts/modules/DegenerusGameMintModule.sol
**Lines:** +21 / -9
**Attribution:** v17.0-affiliate-cache, rngBypass-refactor, v17.1-comments

**mintPacked_ bit layout NatSpec (v17.0-affiliate-cache + v17.1-comments):**
Updated to show bits 185-214 for affiliate bonus cache fields.

**recordMintData NatSpec (v17.1-comments):**
Updated parameter, state update, and level transition documentation.

**recordMintData body (v17.0-affiliate-cache):**
Added affiliate bonus cache write (piggybacks on existing SSTORE):
```diff
+        {
+            uint256 affPoints = affiliate.affiliateBonusPointsBest(lvl, player);
+            data = BitPackingLib.setPacked(data, BitPackingLib.AFFILIATE_BONUS_LEVEL_SHIFT, BitPackingLib.MASK_24, lvl);
+            data = BitPackingLib.setPacked(data, BitPackingLib.AFFILIATE_BONUS_POINTS_SHIFT, BitPackingLib.MASK_6, affPoints);
+        }
```

**purchaseBurnie NatSpec (v17.1-comments):**
```diff
-    /// @dev BURNIE ticket and loot box purchases are allowed whenever RNG is unlocked.
+    /// @dev BURNIE ticket purchases require RNG unlocked and gameOverPossible=false.
+    ///      BURNIE loot boxes require RNG unlocked only.
```

**_queueTicketsScaled rngBypass (rngBypass-refactor):**
```diff
-            _queueTicketsScaled(buyer, targetLevel, adjustedQty);
+            _queueTicketsScaled(buyer, targetLevel, adjustedQty, false);
```

---

### DegenerusGameDecimatorModule.sol
**Path:** contracts/modules/DegenerusGameDecimatorModule.sol
**Lines:** +12 / -13
**Attribution:** v17.0-affiliate-cache, rngBypass-refactor, v17.1-comments

**burnDecimatorsForEth NatSpec (v17.1-comments):**
```diff
-    ///      is removed from old aggregate, player burn resets, and entry migrates.
+    ///      is removed from old aggregate, carried over to the new bucket, and entry migrates.
```

**_queueTickets rngBypass (rngBypass-refactor):**
```diff
-        _queueTickets(beneficiary, calc.targetLevel, calc.ticketCount);
+        _queueTickets(beneficiary, calc.targetLevel, calc.ticketCount, false);
```

**Terminal decimator NatSpec (v17.0-affiliate-cache / 08e80cef):**
```diff
-      |  Always-open burn for GAMEOVER. Time multiplier rewards early
+      |  Burn for GAMEOVER (blocked within 7 days of death clock).
+      |  Time multiplier rewards early
```

**Terminal decimator guard (v17.0-affiliate-cache / 08e80cef):**
```diff
-    ///      Burns blocked when <= 1 day remains (24h cooldown before termination).
+    ///      Burns blocked when <= 7 days remain (7-day cooldown before termination).
-        if (daysRemaining <= 1) revert TerminalDecDeadlinePassed();
+        if (daysRemaining <= 7) revert TerminalDecDeadlinePassed();
```

**_terminalDecMultiplierBps rescaled (v17.0-affiliate-cache / 08e80cef):**
```diff
-    ///      > 10 days: daysRemaining / 4 (30x at 120 days, 2.75x at 11 days)
-    ///      <= 10 days: linear 2x (day 10) to 1x (day 2), burns blocked at day 1
-    ///      Intentional discontinuity at day 10 (2.75x to 2x regime change).
+    ///      > 10 days: linear 20x (day 120) to 1x (day 10)
+    ///      7-10 days: flat 1x
+    ///      <= 7 days: blocked by caller
     function _terminalDecMultiplierBps(uint256 daysRemaining) private pure returns (uint256) {
-        if (daysRemaining > 10) { return daysRemaining * 2500; }
-        return 10000 + ((daysRemaining - 2) * 10000) / 8;
+        if (daysRemaining <= 10) return 10000;
+        return 10000 + ((daysRemaining - 10) * 190000) / 110;
     }
```

---

### DegenerusGame.sol
**Path:** contracts/DegenerusGame.sol
**Lines:** +15 / -14
**Attribution:** v16.0-endgame-delete, v16.0-repack, rngBypass-refactor, v17.1-comments

**Module list NatSpec (v16.0-endgame-delete + v17.1-comments):**
```diff
- *      - Delegatecall modules: endgame, jackpot, mint (must inherit DegenerusGameStorage)
+ *      - Delegatecall modules: advance, boon, decimator, degenerette, jackpot, lootbox, mint, whale (must inherit DegenerusGameStorage)
```

**Removed import (v16.0-endgame-delete):**
```diff
-    IDegenerusGameEndgameModule,
```

**Contract NatSpec (v16.0-endgame-delete):**
```diff
- *      Uses delegatecall pattern for complex logic (endgame, jackpot, mint modules).
+ *      Uses delegatecall pattern for complex logic (8 modules: advance, boon, decimator, degenerette, jackpot, lootbox, mint, whale).
```

**mintPacked_ bit layout (v17.0-affiliate-cache):**
Added bits 184-214 documentation (hasDeityPass, affBonusLevel, affBonusPoints).

**constructor _queueTickets rngBypass (rngBypass-refactor):**
```diff
-            _queueTickets(ContractAddresses.SDGNRS, i, 16);
-            _queueTickets(ContractAddresses.VAULT, i, 16);
+            _queueTickets(ContractAddresses.SDGNRS, i, 16, false);
+            _queueTickets(ContractAddresses.VAULT, i, 16, false);
```

**RNG timeout NatSpec (v17.1-comments):**
```diff
-      |  * RNG must be ready (not locked) or recently stale (18h timeout)
+      |  * RNG must be ready (not locked) or recently stale (12h timeout)
```

**Module table (v16.0-endgame-delete + v17.1-comments):**
```diff
-      |  * GAME_ENDGAME_MODULE      - Endgame settlement (payouts, wipes, jackpots)
-      |  * GAME_WHALE_MODULE        - Whale bundle purchases
+      |  * GAME_WHALE_MODULE        - Whale bundle purchases and whale pass claims
```

**claimWhalePass NatSpec + delegatecall target (v16.0-endgame-delete):**
```diff
-    ///      Delegates to endgame module which uses whale pass pricing.
+    ///      Delegates to whale module for deferred whale pass ticket awards.
-            .GAME_ENDGAME_MODULE
+            .GAME_WHALE_MODULE
-                    IDegenerusGameEndgameModule.claimWhalePass.selector,
+                    IDegenerusGameWhaleModule.claimWhalePass.selector,
```

**currentPrizePoolView (v16.0-repack):**
```diff
-        return currentPrizePool;
+        return _getCurrentPrizePool();
```

**yieldPoolView (v16.0-repack):**
```diff
-        uint256 obligations = currentPrizePool +
+        uint256 obligations = _getCurrentPrizePool() +
```

---

### DegenerusQuests.sol
**Path:** contracts/DegenerusQuests.sol
**Lines:** +11 / -12
**Attribution:** v17.1-comments, pre-v16.0-manual

**OnlyCoin error NatSpec (v17.1-comments):**
```diff
-    /// @notice Thrown when caller is not the authorized COIN or COINFLIP contract.
+    /// @notice Thrown when caller is not an authorized contract (COIN, COINFLIP, GAME, or AFFILIATE).
```

**QuestSlotRolled event (pre-v16.0-manual / cdac1bed):**
```diff
-        uint24 version,
-        uint16 difficulty
+        uint24 version
```
Removed `difficulty` parameter from event.

**Quest struct (pre-v16.0-manual / cdac1bed):**
```diff
-        uint16 difficulty;  // Unused (fixed to 0); retained for storage compatibility
+        // 16 bits free
```

**Quest layout comment (pre-v16.0-manual / cdac1bed):**
Removed `difficulty (16b)` from memory layout diagram.

**rollDailyQuest emit (pre-v16.0-manual / cdac1bed):**
```diff
-        emit QuestSlotRolled(day, 0, QUEST_TYPE_MINT_ETH, 0, quests[0].version, 0);
-        emit QuestSlotRolled(day, 1, bonusType, 0, quests[1].version, 0);
+        emit QuestSlotRolled(day, 0, QUEST_TYPE_MINT_ETH, 0, quests[0].version);
+        emit QuestSlotRolled(day, 1, bonusType, 0, quests[1].version);
```

**Lootbox reward routing comment (v17.1-comments):**
```diff
-        // - Lootbox rewards: creditFlip internally (handleLootBox behavior)
+        // - Lootbox rewards: creditFlip internally AND returned to caller (caller adds to lootboxFlipCredit)
```

**levelQuestGlobal variable name in NatSpec (v17.1-comments):**
```diff
-    ///      Reads levelQuestGlobal (single SLOAD, shares slot with questVersionCounter)
+    ///      Reads levelQuestType and levelQuestVersion (share slot with questVersionCounter)
```
(2 locations)

---

### DegenerusGameMintStreakUtils.sol
**Path:** contracts/modules/DegenerusGameMintStreakUtils.sol
**Lines:** +14 / -5
**Attribution:** v17.0-affiliate-cache, v17.1-comments

**Contract NatSpec (v17.1-comments):**
```diff
-/// @dev Shared mint streak helpers (credits on completed 1x price ETH quest).
+/// @dev Shared mint streak and activity score utilities. Contains _playerActivityScore
+///      (5-component scoring: mint streak, mint count, quest streak, affiliate bonus, deity/whale pass)
+///      and mint streak helpers (credits on completed 1x price ETH quest).
```

**_playerActivityScore affiliate bonus (v17.0-affiliate-cache):**
```diff
-            // Affiliate bonus
-            bonusBps += affiliate.affiliateBonusPointsBest(currLevel, player) * 100;
+            // Affiliate bonus (cached in mintPacked_ on level transitions)
+            {
+                uint256 cachedLevel = (packed >> BitPackingLib.AFFILIATE_BONUS_LEVEL_SHIFT) & BitPackingLib.MASK_24;
+                uint256 affPoints;
+                if (cachedLevel == uint256(currLevel)) {
+                    affPoints = (packed >> BitPackingLib.AFFILIATE_BONUS_POINTS_SHIFT) & BitPackingLib.MASK_6;
+                } else {
+                    affPoints = affiliate.affiliateBonusPointsBest(currLevel, player);
+                }
+                bonusBps += affPoints * 100;
+            }
```

---

### BitPackingLib.sol
**Path:** contracts/libraries/BitPackingLib.sol
**Lines:** +16 / -1
**Attribution:** v17.0-affiliate-cache, v17.1-comments

**Bit layout NatSpec (v17.0-affiliate-cache):**
```diff
- *      [185-227] (unused)
+ *      [185-208] AFFILIATE_BONUS_LEVEL_SHIFT - Cached affiliate bonus level (24 bits)
+ *      [209-214] AFFILIATE_BONUS_POINTS_SHIFT - Cached affiliate bonus points (6 bits)
+ *      [215-227] (unused)
```

**New constants (v17.0-affiliate-cache):**
```diff
+    uint256 internal constant MASK_6 = (uint256(1) << 6) - 1;
+    uint256 internal constant MASK_2 = 0x3;
+    uint256 internal constant MASK_1 = 0x1;
+    uint256 internal constant AFFILIATE_BONUS_LEVEL_SHIFT = 185;
+    uint256 internal constant AFFILIATE_BONUS_POINTS_SHIFT = 209;
```

---

### IDegenerusGameModules.sol
**Path:** contracts/interfaces/IDegenerusGameModules.sol
**Lines:** +8 / -17
**Attribution:** v16.0-endgame-delete

**Deleted IDegenerusGameEndgameModule interface (17 lines):**
```diff
-interface IDegenerusGameEndgameModule {
-    function runRewardJackpots(uint24 lvl, uint256 rngWord) external;
-    function rewardTopAffiliate(uint24 lvl) external;
-    function claimWhalePass(address player) external;
-}
```

**Added runRewardJackpots to IDegenerusGameJackpotModule:**
```diff
+    function runRewardJackpots(uint24 lvl, uint256 rngWord) external;
```

**Added claimWhalePass to IDegenerusGameWhaleModule:**
```diff
+    function claimWhalePass(address player) external;
```

---

### DegenerusGameGameOverModule.sol
**Path:** contracts/modules/DegenerusGameGameOverModule.sol
**Lines:** +7 / -7
**Attribution:** v16.0-repack, v17.1-comments

**handleGameOverDrain NatSpec (v17.1-comments):**
```diff
-    ///      - Any uncredited remainder swept to vault and DGNRS
+    ///      - Any uncredited remainder swept to vault and sDGNRS
-    ///      VRF fallback: Uses rngWordByDay which may use historical VRF word as secure
-    ///      fallback if Chainlink VRF is stalled (after 3 day wait period).
+    ///      Reads rngWordByDay[day] for entropy; returns early if word is not yet available.
+    ///      VRF fallback logic (historical word, stall timeout) is in AdvanceModule._gameOverEntropy.
```

**currentPrizePool access (v16.0-repack):**
```diff
-        currentPrizePool = 0;
+        _setCurrentPrizePool(0);
```
(2 locations)

**handleFinalSweep NatSpec (v17.1-comments):**
```diff
-    ///      Funds are split 33% DGNRS / 33% vault / 34% GNRUS.
+    ///      Funds are split 33% sDGNRS / 33% vault / 34% GNRUS.
```

**_sendToVault NatSpec (v17.1-comments):**
```diff
-    /// @dev Send funds to DGNRS (33%), vault (33%), and GNRUS (34%), stETH-first for all.
+    /// @dev Send funds to sDGNRS (33%), vault (33%), and GNRUS (34%), stETH-first for all.
```

---

### DegenerusGameLootboxModule.sol
**Path:** contracts/modules/DegenerusGameLootboxModule.sol
**Lines:** +5 / -7
**Attribution:** rngBypass-refactor, v17.1-comments

**Removed stale event NatSpec (v17.1-comments):**
```diff
-    /// @notice Emitted when a lootbox awards a lazy pass
-    /// @param player The player who received the lazy pass
```

**LootBoxReward NatSpec (v17.1-comments):**
```diff
-    /// @param rewardType The type of reward (2=CoinflipBoon, 4=Boost5, 5=Boost15, 6=Boost25/Purchase, 8=DecimatorBoost, 9=WhaleBoon, 10=ActivityBoon/DeityPassBoon)
+    /// @param rewardType The type of reward (2=CoinflipBoon, 4=Boost5, 5=Boost15, 6=Boost25/Purchase, 8=DecimatorBoost, 9=WhaleBoon, 10=ActivityBoon/DeityPassBoon, 11=LazyPassBoon)
```

**LOOTBOX_EV_MAX_BPS comment (v17.1-comments):**
```diff
-    /// @dev Maximum EV at 260%+ activity (135%)
+    /// @dev Maximum EV at 255%+ activity (135%)
```

**_queueTicketsScaled rngBypass (rngBypass-refactor):**
```diff
-            _queueTicketsScaled(player, targetLevel, futureTickets);
+            _queueTicketsScaled(player, targetLevel, futureTickets, false);
-                isBonus ? WHALE_PASS_BONUS_TICKETS_PER_LEVEL : WHALE_PASS_TICKETS_PER_LEVEL
+                isBonus ? WHALE_PASS_BONUS_TICKETS_PER_LEVEL : WHALE_PASS_TICKETS_PER_LEVEL,
+                false
```

---

### DegenerusAffiliate.sol
**Path:** contracts/DegenerusAffiliate.sol
**Lines:** +7 / -3
**Attribution:** v17.0-affiliate-cache

**affiliateBonusPointsBest NatSpec (v17.0-affiliate-cache / 3c3245d5):**
```diff
-     *      Awards 1 point (1%) per 1 ETH of summed score, capped at 50.
+     *      Tiered rate: 4 points per ETH for the first 5 ETH (20 pts),
+     *      then 1.5 points per ETH for the next 20 ETH (30 pts). Cap: 50 at 25 ETH.
```

**affiliateBonusPointsBest body (v17.0-affiliate-cache / 3c3245d5):**
```diff
-        uint256 ethUnit = 1 ether;
-        points = sum / ethUnit;
+        if (sum <= 5 ether) {
+            points = (sum * 4) / 1 ether;
+        } else {
+            points = 20 + ((sum - 5 ether) * 3) / 2 ether;
+        }
```

---

### IStakedDegenerusStonk.sol
**Path:** contracts/interfaces/IStakedDegenerusStonk.sol
**Lines:** +5 / -4
**Attribution:** v17.1-comments

**burn NatSpec updated:**
```diff
-    /// @notice Burn sDGNRS to claim proportional share of backing assets
+    /// @notice Burn sDGNRS. Post-gameOver: immediate proportional payout. During game: enters
+    ///         gambling claim queue (returns 0,0,0) -- call claimRedemption() after resolution.
-    /// @return ethOut ETH received
+    /// @return ethOut ETH received (0 during active game)
```
(All 3 return values updated with "(0 during active game)")

---

### GNRUS.sol
**Path:** contracts/GNRUS.sol
**Lines:** +4 / -4
**Attribution:** v17.1-comments

4 comment corrections across the file (exact line diffs are single-line NatSpec fixes). All changes are comment-only.

---

### DegenerusGameDegeneretteModule.sol
**Path:** contracts/modules/DegenerusGameDegeneretteModule.sol
**Lines:** +3 / -4
**Attribution:** v17.1-comments

**Payout table reference (v17.1-comments):**
```diff
-    // and the new payout table (0, 0, 1.78x, 4.75x, 15x, 54x, 248x, 1280x, 100000x).
+    // and the payout table (0, 0, 1.90x, 4.75x, 15x, 54x, 248x, 1280x, 100000x).
```

**Removed duplicate NatSpec (v17.1-comments):**
```diff
-    /// @notice Places Full Ticket bets using pending affiliate Degenerette credit.
     /// @notice Resolves one or more pending bets for a player.
```

**Spin 0 comment (v17.1-comments):**
```diff
-            // For backwards compatibility, spin 0 uses the legacy seed (no spinIdx mixed in).
+            // Spin 0 uses a shorter preimage (no spinIdx mixed in) to produce a distinct seed.
```

**basePayout centi-x reference (v17.1-comments):**
```diff
-        // basePayout is in "centi-x" (178 = 1.78x), roiBps is in bps (9000 = 90%)
+        // basePayout is in "centi-x" (190 = 1.90x), roiBps is in bps (9000 = 90%)
```

---

### DegenerusGameBoonModule.sol
**Path:** contracts/modules/DegenerusGameBoonModule.sol
**Lines:** +2 / -2
**Attribution:** v17.1-comments

```diff
- * @notice Delegatecall module for boon consumption and lootbox view functions.
+ * @notice Delegatecall module for boon consumption.
- * @dev Split from DegenerusGameLootboxModule to stay under EIP-170 size limit.
+ * @dev Boon consumption logic for coinflip, purchase, decimator, activity, and deity pass boons.
```

---

### DegenerusJackpots.sol
**Path:** contracts/DegenerusJackpots.sol
**Lines:** +2 / -2
**Attribution:** v17.1-comments

```diff
-    /// @dev Called by coin contract on every manual coinflip. Silently ignores vault address.
+    /// @dev Called by COIN or COINFLIP contract on every manual coinflip. Silently ignores vault address.
-    /// @custom:access Restricted to coin contract via onlyCoin modifier.
+    /// @custom:access Restricted to COIN or COINFLIP via onlyCoin modifier.
```

---

### BurnieCoinflip.sol
**Path:** contracts/BurnieCoinflip.sol
**Lines:** +3 / -3
**Attribution:** v17.1-comments

```diff
-    /// @dev Allowed callers: GAME (delegatecall modules), BURNIE, AFFILIATE, ADMIN, QUESTS (level quest rewards).
+    /// @dev Allowed callers: GAME (delegatecall modules), QUESTS (level quest rewards), AFFILIATE, ADMIN.
-    /// @notice Credit flip to a player (called directly by GAME modules, AFFILIATE, or ADMIN).
+    /// @notice Credit flip to a player (called by GAME modules, QUESTS, AFFILIATE, or ADMIN).
-    /// @notice Credit flips to multiple players (called directly by GAME modules, AFFILIATE, or ADMIN).
+    /// @notice Credit flips to multiple players (called by GAME modules, QUESTS, AFFILIATE, or ADMIN).
```

---

### DegenerusAdmin.sol
**Path:** contracts/DegenerusAdmin.sol
**Lines:** +1 / -1
**Attribution:** v17.1-comments

```diff
-    ///      Returns (newApprove, newReject, scaledWeight) -- caller applies to storage.
+    ///      Returns (newApprove, newReject) -- caller applies to storage.
```

---

### DegenerusVault.sol
**Path:** contracts/DegenerusVault.sol
**Lines:** +1 / -1
**Attribution:** v17.1-comments

Single NatSpec correction (1 line).

---

### Icons32Data.sol
**Path:** contracts/Icons32Data.sol
**Lines:** +1 / -1
**Attribution:** v17.1-comments

Single NatSpec correction (1 line).

---

### StakedDegenerusStonk.sol
**Path:** contracts/StakedDegenerusStonk.sol
**Lines:** +1 / -1
**Attribution:** v17.1-comments

Single NatSpec correction (1 line).

---

### MockWXRP.sol
**Path:** contracts/mocks/MockWXRP.sol
**Lines:** +1 / -1
**Attribution:** v17.1-comments

```diff
-    uint8 public constant decimals = 18;
+    uint8 public constant decimals = 6;
```
Mock aligned with production wXRP decimal count.

---

### IBurnieCoinflip.sol
**Path:** contracts/interfaces/IBurnieCoinflip.sol
**Lines:** +1 / -1
**Attribution:** v17.1-comments

```diff
-    /// @dev Called by authorized creditors (LazyPass, DegenerusGame, or BurnieCoin) for rewards.
+    /// @dev Called by authorized creditors (GAME, QUESTS, AFFILIATE, ADMIN) for rewards.
```

---

### IDegenerusAffiliate.sol
**Path:** contracts/interfaces/IDegenerusAffiliate.sol
**Lines:** +1 / -1
**Attribution:** v17.1-comments

```diff
-    ///      Awards 1 point (1%) per 1 ETH of summed score, capped at 50.
+    ///      Awards 4 points per ETH for the first 5 ETH, 1.5 points per ETH for the next 20 ETH, capped at 50.
```

---

### IDegenerusGame.sol
**Path:** contracts/interfaces/IDegenerusGame.sol
**Lines:** +1 / -1
**Attribution:** v17.1-comments

```diff
-    /// @dev Access restricted to authorized contracts (COIN or GAME self-call).
+    /// @dev Access restricted to GAME self-call only (delegatecall modules via address(this)).
```

---

### IDegenerusQuests.sol
**Path:** contracts/interfaces/IDegenerusQuests.sol
**Lines:** +1 / -1
**Attribution:** v17.1-comments

```diff
-    /// @dev Called by JackpotModule (via GAME delegatecall) to determine which quests are active.
+    /// @dev Called by AdvanceModule (via GAME delegatecall) to determine which quests are active.
```

---

## Completeness Verification

Total files in `git diff --stat`: 33
Files documented above: 33
Missing: 0

Total lines added: 766
Total lines deleted: 1002
Net change: -236

Category breakdown:
- HEAVY (4 files): EndgameModule(571), JackpotModule(503), AdvanceModule(141), Storage(138) = 1353
- MEDIUM (14 files): WhaleModule(48), BurnieCoin(38), ContractAddresses(36), WrappedWrappedXRP(33), MintModule(30), DegenerusGame(29), DecimatorModule(25), IDegenerusGameModules(25), DegenerusQuests(23), MintStreakUtils(19), BitPackingLib(17), GameOverModule(14), LootboxModule(12), DegenerusAffiliate(10) = 359
- LIGHT (15 files): IStakedDegenerusStonk(9), GNRUS(8), DegeneretteModule(7), BurnieCoinflip(6), BoonModule(4), DegenerusJackpots(4), DegenerusAdmin(2), DegenerusVault(2), Icons32Data(2), StakedDegenerusStonk(2), MockWXRP(2), IBurnieCoinflip(2), IDegenerusAffiliate(2), IDegenerusGame(2), IDegenerusQuests(2) = 56

Grand total: 1353 + 359 + 56 = 1768 = 766 + 1002 (verified)
