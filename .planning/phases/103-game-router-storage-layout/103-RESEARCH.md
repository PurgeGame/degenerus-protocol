# Phase 103: Game Router + Storage Layout - Research

**Researched:** 2026-03-25
**Domain:** Solidity smart contract audit -- delegatecall router + shared storage layout
**Confidence:** HIGH

## Summary

DegenerusGame.sol is a 2,848-line router contract that dispatches to 10 delegatecall modules while also containing significant direct logic (claim flows, auto-rebuy, admin functions, payment processing, activity scoring). DegenerusGameStorage.sol is a 1,613-line abstract contract defining the canonical storage layout for the entire module ecosystem. Together these two files contain **139 functions** that need categorization and analysis.

The contract is structured as: `DegenerusGame` inherits `DegenerusGameMintStreakUtils` inherits `DegenerusGameStorage`. All 10 delegatecall modules also inherit from `DegenerusGameStorage` (some via `DegenerusGamePayoutUtils` or `DegenerusGameMintStreakUtils`, which themselves inherit `DegenerusGameStorage`). No module adds its own storage variables -- verified by grep. All non-constant declarations live exclusively in `DegenerusGameStorage.sol`.

**Primary recommendation:** Split the Taskmaster checklist into 4 functional groups (delegatecall dispatchers, direct state-changing functions, internal helpers, and view functions), then have the Mad Genius focus deep analysis exclusively on direct state-changing functions and non-trivial internal helpers. Delegatecall dispatchers need dispatch-correctness verification only (selector matches, module address is correct, return value decoded correctly). View functions need minimal analysis (no state changes).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Audit the router's own logic (delegatecall dispatch, access control, direct state-changing functions) thoroughly. For delegatecall targets, trace only far enough to verify the dispatch reaches the correct module function -- full module internals are audited in their respective phases.
- **D-02:** Functions that live directly in DegenerusGame.sol (not delegated) get full Mad Genius treatment: call tree, storage writes, cache checks, all attack angles.
- **D-03:** Use `forge inspect DegenerusGame storage-layout` to get authoritative slot assignments. Cross-reference against the manual slot comments in DegenerusGameStorage.sol.
- **D-04:** Verify all modules that inherit DegenerusGameStorage use the exact same base contract (no rogue storage variables added by any module).
- **D-05:** Follow the ULTIMATE-AUDIT-DESIGN.md format: per-function sections with call tree, storage-write map, cached-local-vs-storage check, attack analysis with verdicts.
- **D-06:** This phase proves the storage layout is correct and that DegenerusGameStorage is the single source of truth. Per-module alignment verification is deferred to Phase 118 (Cross-Contract Integration Sweep).

### Claude's Discretion
- Ordering of function analysis within the report
- Level of detail in delegatecall dispatch traces (enough to prove correctness, no more)

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| UNIT-01 | Unit 1 -- Game Router + Storage Layout complete (DegenerusGame, DegenerusGameStorage) | This research identifies all 139 functions across both contracts, categorizes them by type (delegatecall/direct/view), and defines the work chunking strategy |
| COV-01 | Every state-changing function has a Taskmaster-built checklist entry | Function inventory below identifies 49 state-changing functions (30 delegatecall dispatchers + 19 direct) that must appear on the checklist |
| COV-02 | Every function checklist entry signed off with analyzed/call-tree/storage-writes/cache-check | Research defines what "complete" means for each function category (dispatch verification vs full analysis) |
| COV-03 | No unit advances to Skeptic until Taskmaster gives PASS with 100% coverage | Checklist must cover all 49 state-changing + the `receive()` fallback |
| ATK-01 | Fully-expanded recursive call tree for every function | Direct functions (19) need full expansion; dispatchers (30) need dispatch-correctness proof only per D-01 |
| ATK-02 | Complete storage-write map for every function | Critical for 19 direct functions; dispatchers write nothing themselves (module writes are in scope of their respective phases) |
| ATK-03 | Cached-local-vs-storage check for every function | Applies to all 19 direct state-changing functions plus `receive()` |
| ATK-04 | Attack from all applicable angles | State coherence, access control, RNG manipulation, cross-contract desync, edge cases, rare paths, economic/MEV, griefing, ordering, silent failures |
| ATK-05 | VULNERABLE/INVESTIGATE findings include line numbers, attack scenario, PoC | Research identifies which functions have the highest risk surface area |
| VAL-01 | Every VULNERABLE/INVESTIGATE finding has Skeptic verdict | Skeptic reviews all findings from Mad Genius |
| VAL-02 | Every FALSE POSITIVE cites specific preventing line(s) | Standard Skeptic protocol |
| VAL-03 | Every CONFIRMED finding gets severity rating | Standard Skeptic protocol |
| VAL-04 | Skeptic independently verifies Taskmaster's function checklist | Skeptic confirms no state-changing functions were omitted |
</phase_requirements>

## Function Inventory

### DegenerusGame.sol -- Complete Function Census (119 functions)

#### Category A: Delegatecall Dispatchers (30 functions)

These functions do nothing except encode a selector, delegatecall to a module address, and bubble up the revert/return. They need dispatch-correctness verification only.

| # | Function | Visibility | Module Target | Interface Selector |
|---|----------|------------|---------------|-------------------|
| 1 | `advanceGame()` | external | GAME_ADVANCE_MODULE | `advanceGame.selector` |
| 2 | `wireVrf()` | external | GAME_ADVANCE_MODULE | `wireVrf.selector` |
| 3 | `updateVrfCoordinatorAndSub()` | external | GAME_ADVANCE_MODULE | `updateVrfCoordinatorAndSub.selector` |
| 4 | `requestLootboxRng()` | external | GAME_ADVANCE_MODULE | `requestLootboxRng.selector` |
| 5 | `reverseFlip()` | external | GAME_ADVANCE_MODULE | `reverseFlip.selector` |
| 6 | `rawFulfillRandomWords()` | external | GAME_ADVANCE_MODULE | `rawFulfillRandomWords.selector` |
| 7 | `purchase()` | external payable | GAME_MINT_MODULE (via `_purchaseFor`) | `purchase.selector` |
| 8 | `purchaseCoin()` | external | GAME_MINT_MODULE | `purchaseCoin.selector` |
| 9 | `purchaseBurnieLootbox()` | external | GAME_MINT_MODULE | `purchaseBurnieLootbox.selector` |
| 10 | `purchaseWhaleBundle()` | external payable | GAME_WHALE_MODULE (via `_purchaseWhaleBundleFor`) | `purchaseWhaleBundle.selector` |
| 11 | `purchaseLazyPass()` | external payable | GAME_WHALE_MODULE (via `_purchaseLazyPassFor`) | `purchaseLazyPass.selector` |
| 12 | `purchaseDeityPass()` | external payable | GAME_WHALE_MODULE (via `_purchaseDeityPassFor`) | `purchaseDeityPass.selector` |
| 13 | `openLootBox()` | external | GAME_LOOTBOX_MODULE (via `_openLootBoxFor`) | `openLootBox.selector` |
| 14 | `openBurnieLootBox()` | external | GAME_LOOTBOX_MODULE (via `_openBurnieLootBoxFor`) | `openBurnieLootBox.selector` |
| 15 | `placeFullTicketBets()` | external payable | GAME_DEGENERETTE_MODULE | `placeFullTicketBets.selector` |
| 16 | `resolveDegeneretteBets()` | external | GAME_DEGENERETTE_MODULE | `resolveBets.selector` |
| 17 | `consumeCoinflipBoon()` | external | GAME_BOON_MODULE | `consumeCoinflipBoon.selector` |
| 18 | `consumeDecimatorBoon()` | external | GAME_BOON_MODULE | `consumeDecimatorBoost.selector` |
| 19 | `consumePurchaseBoost()` | external | GAME_BOON_MODULE | `consumePurchaseBoost.selector` |
| 20 | `issueDeityBoon()` | external | GAME_LOOTBOX_MODULE | `issueDeityBoon.selector` |
| 21 | `recordDecBurn()` | external | GAME_DECIMATOR_MODULE | `recordDecBurn.selector` |
| 22 | `runDecimatorJackpot()` | external | GAME_DECIMATOR_MODULE | `runDecimatorJackpot.selector` |
| 23 | `recordTerminalDecBurn()` | external | GAME_DECIMATOR_MODULE | `recordTerminalDecBurn.selector` |
| 24 | `runTerminalDecimatorJackpot()` | external | GAME_DECIMATOR_MODULE | `runTerminalDecimatorJackpot.selector` |
| 25 | `runTerminalJackpot()` | external | GAME_JACKPOT_MODULE | `runTerminalJackpot.selector` |
| 26 | `consumeDecClaim()` | external | GAME_DECIMATOR_MODULE | `consumeDecClaim.selector` |
| 27 | `claimDecimatorJackpot()` | external | GAME_DECIMATOR_MODULE | `claimDecimatorJackpot.selector` |
| 28 | `claimWhalePass()` | external | GAME_ENDGAME_MODULE (via `_claimWhalePassFor`) | `claimWhalePass.selector` |
| 29 | `_recordMintDataModule()` | private | GAME_MINT_MODULE | `recordMintData.selector` |
| 30 | `resolveRedemptionLootbox()` | external | GAME_LOOTBOX_MODULE (in loop) | `resolveRedemptionLootbox.selector` |

**Notes on dispatch verification:**
- Item 18 (`consumeDecimatorBoon`) dispatches to `consumeDecimatorBoost.selector` -- the function name vs selector name mismatch is a deliberate remapping worth verifying.
- Item 30 (`resolveRedemptionLootbox`) is hybrid: it performs direct state changes (claimableWinnings debit, claimablePool decrement, prize pool credit) BEFORE the delegatecall loop. This function needs FULL analysis, not just dispatch verification.

#### Category B: Direct State-Changing Functions (19 functions)

These functions execute logic directly in DegenerusGame.sol without delegating. They get FULL Mad Genius treatment per D-02.

| # | Function | Visibility | Access Control | Primary Storage Writes |
|---|----------|------------|---------------|----------------------|
| 1 | `constructor()` | -- | deploy-only | `levelStartTime`, `levelPrizePool[0]`, `deityPassCount[SDGNRS,VAULT]`, `ticketQueue` (200 entries) |
| 2 | `recordMint()` | external payable | `msg.sender == address(this)` | `claimableWinnings`, `claimablePool`, `prizePoolsPacked` or `prizePoolPendingPacked`, `mintPacked_`, earlybird state |
| 3 | `recordMintQuestStreak()` | external | `msg.sender == COIN` | `mintPacked_` |
| 4 | `payCoinflipBountyDgnrs()` | external | `msg.sender == COIN or COINFLIP` | None direct (external call to `dgnrs.transferFromPool`) |
| 5 | `setOperatorApproval()` | external | any (msg.sender is owner) | `operatorApprovals[msg.sender][operator]` |
| 6 | `setLootboxRngThreshold()` | external | `msg.sender == ADMIN` | `lootboxRngThreshold` |
| 7 | `claimWinnings()` | external | operator-approved | `claimableWinnings[player]`, `claimablePool` |
| 8 | `claimWinningsStethFirst()` | external | `msg.sender == VAULT or SDGNRS` | `claimableWinnings[player]`, `claimablePool` |
| 9 | `claimAffiliateDgnrs()` | external | operator-approved | `affiliateDgnrsClaimedBy`, `levelDgnrsClaimed` |
| 10 | `setAutoRebuy()` | external | operator-approved | `autoRebuyState[player]` |
| 11 | `setDecimatorAutoRebuy()` | external | operator-approved | `decimatorAutoRebuyDisabled[player]` |
| 12 | `setAutoRebuyTakeProfit()` | external | operator-approved | `autoRebuyState[player].takeProfit` |
| 13 | `setAfKingMode()` | external | operator-approved | `autoRebuyState[player]` (multiple fields), external call to `coinflip` |
| 14 | `deactivateAfKingFromCoin()` | external | `msg.sender == COIN or COINFLIP` | `autoRebuyState[player]` |
| 15 | `syncAfKingLazyPassFromCoin()` | external | `msg.sender == COINFLIP` | `autoRebuyState[player]` |
| 16 | `resolveRedemptionLootbox()` | external | `msg.sender == SDGNRS` | `claimableWinnings[SDGNRS]`, `claimablePool`, `prizePoolsPacked` or `prizePoolPendingPacked` (+ delegatecall) |
| 17 | `adminSwapEthForStEth()` | external payable | `msg.sender == ADMIN` | None (external transfers only) |
| 18 | `adminStakeEthForStEth()` | external | `msg.sender == ADMIN` | None (external call to steth.submit) |
| 19 | `receive()` | external payable | any | `prizePoolsPacked` or `prizePoolPendingPacked` |

#### Category C: Private/Internal Helpers (21 functions in DegenerusGame.sol)

| # | Function | Visibility | Called By |
|---|----------|------------|-----------|
| 1 | `_requireApproved()` | private view | `_resolvePlayer` |
| 2 | `_resolvePlayer()` | private view | All operator-gated externals |
| 3 | `_purchaseFor()` | private | `purchase()` |
| 4 | `_purchaseWhaleBundleFor()` | private | `purchaseWhaleBundle()` |
| 5 | `_purchaseLazyPassFor()` | private | `purchaseLazyPass()` |
| 6 | `_purchaseDeityPassFor()` | private | `purchaseDeityPass()` |
| 7 | `_openLootBoxFor()` | private | `openLootBox()` |
| 8 | `_openBurnieLootBoxFor()` | private | `openBurnieLootBox()` |
| 9 | `_processMintPayment()` | private | `recordMint()` |
| 10 | `_revertDelegate()` | private pure | All delegatecall functions |
| 11 | `_recordMintDataModule()` | private | `recordMint()` |
| 12 | `_unpackDecWinningSubbucket()` | private pure | `decClaimable()` |
| 13 | `_claimWinningsInternal()` | private | `claimWinnings()`, `claimWinningsStethFirst()` |
| 14 | `_setAutoRebuy()` | private | `setAutoRebuy()` |
| 15 | `_setAutoRebuyTakeProfit()` | private | `setAutoRebuyTakeProfit()` |
| 16 | `_setAfKingMode()` | private | `setAfKingMode()` |
| 17 | `_hasAnyLazyPass()` | private view | `_setAfKingMode()`, `syncAfKingLazyPassFromCoin()` |
| 18 | `_deactivateAfKing()` | private | `_setAutoRebuy()`, `_setAutoRebuyTakeProfit()`, `deactivateAfKingFromCoin()` |
| 19 | `_claimWhalePassFor()` | private | `claimWhalePass()` |
| 20 | `_transferSteth()` | private | `_payoutWithStethFallback()`, `_payoutWithEthFallback()` |
| 21 | `_payoutWithStethFallback()` | private | `_claimWinningsInternal()` |
| 22 | `_payoutWithEthFallback()` | private | `_claimWinningsInternal()` |
| 23 | `_threeDayRngGap()` | private view | `rngStalledForThreeDays()` |
| 24 | `_isGameoverImminent()` | private view | `decWindow()`, `decWindowOpenFlag()` |
| 25 | `_activeTicketLevel()` | private view | Multiple functions |
| 26 | `_playerActivityScore()` | internal view | `playerActivityScore()` |
| 27 | `_mintCountBonusPoints()` | private pure | `_playerActivityScore()` |

#### Category D: View/Pure Functions (42 functions in DegenerusGame.sol)

These are read-only -- no state changes. Minimal audit scope (verify they don't expose sensitive internal state unsafely).

`currentDayView`, `isOperatorApproved`, `autoRebuyEnabledFor`, `decimatorAutoRebuyEnabledFor`, `autoRebuyTakeProfitFor`, `hasActiveLazyPass`, `afKingModeFor`, `afKingActivatedLevelFor`, `terminalDecWindow`, `decClaimable`, `deityBoonData`, `prizePoolTargetView`, `nextPrizePoolView`, `futurePrizePoolView`, `futurePrizePoolTotalView`, `ticketsOwedView`, `lootboxStatus`, `degeneretteBetInfo`, `lootboxPresaleActiveFlag`, `lootboxRngIndexView`, `lootboxRngWord`, `lootboxRngThresholdView`, `lootboxRngMinLinkBalanceView`, `currentPrizePoolView`, `rewardPoolView`, `claimablePoolView`, `isFinalSwept`, `yieldPoolView`, `yieldAccumulatorView`, `mintPrice`, `rngWordForDay`, `lastRngWord`, `rngLocked`, `isRngFulfilled`, `rngStalledForThreeDays`, `lastVrfProcessed`, `decWindow`, `decWindowOpenFlag`, `jackpotCompressionTier`, `jackpotPhase`, `purchaseInfo`, `ethMintLastLevel`, `ethMintLevelCount`, `ethMintStreakCount`, `ethMintStats`, `playerActivityScore`, `getWinnings`, `claimableWinningsOf`, `whalePassClaimAmount`, `deityPassCountFor`, `deityPassPurchasedCountFor`, `deityPassTotalIssuedCount`, `sampleTraitTickets`, `sampleTraitTicketsAtLevel`, `sampleFarFutureTickets`, `getTickets`, `getPlayerPurchases`, `getDailyHeroWager`, `getDailyHeroWinner`, `getPlayerDegeneretteWager`, `getTopDegenerette`

### DegenerusGameStorage.sol -- Function Census (38 functions)

All internal/pure. No external entry points.

| Category | Count | Functions |
|----------|-------|-----------|
| Internal view helpers | 6 | `_isDistressMode`, `_getPrizePools`, `_getPendingPools`, `_getNextPrizePool`, `_getFuturePrizePool`, `_simulatedDayIndex` |
| Internal state-changing helpers | 15 | `_queueTickets`, `_queueTicketsScaled`, `_queueTicketRange`, `_queueLootboxTickets`, `_setPrizePools`, `_setPendingPools`, `_swapTicketSlot`, `_swapAndFreeze`, `_unfreezePool`, `_setNextPrizePool`, `_setFuturePrizePool`, `_awardEarlybirdDgnrs`, `_activate10LevelPass`, `_applyWhalePassStats`, `_recordMintStreakForLevel` (via MintStreakUtils) |
| Internal pure helpers | 5 | `_tqFarFutureKey`, `_simulatedDayIndexAt`, `_setMintDay`, `_currentMintDay` (view), `_mintStreakEffective` (view, via MintStreakUtils) |
| Tier encode/decode (pure) | 12 | `_coinflipTierToBps`, `_lootboxTierToBps`, `_purchaseTierToBps`, `_decimatorTierToBps`, `_whaleTierToBps`, `_lazyPassTierToBps`, `_coinflipBpsToTier`, `_lootboxBpsToTier`, `_purchaseBpsToTier`, `_decimatorBpsToTier`, `_whaleBpsToTier`, `_lazyPassBpsToTier` |

### MintStreakUtils.sol -- Function Census (2 functions)

| Function | Visibility | Purpose |
|----------|------------|---------|
| `_recordMintStreakForLevel` | internal | Updates `mintPacked_` streak fields |
| `_mintStreakEffective` | internal view | Reads streak with gap-reset logic |

## Architecture Patterns

### Inheritance Chain

```
DegenerusGameStorage (abstract, defines all storage)
  |-- DegenerusGamePayoutUtils (abstract, adds _addClaimableEth helper)
  |     |-- DegenerusGameEndgameModule
  |     |-- DegenerusGameJackpotModule
  |     |-- DegenerusGameDecimatorModule
  |     |-- DegenerusGameDegeneretteModule (also inherits MintStreakUtils)
  |
  |-- DegenerusGameMintStreakUtils (abstract, adds streak helpers)
  |     |-- DegenerusGame (THE ROUTER -- inherits MintStreakUtils -> Storage)
  |     |-- DegenerusGameWhaleModule
  |     |-- DegenerusGameDegeneretteModule (diamond: also PayoutUtils)
  |
  |-- DegenerusGameAdvanceModule
  |-- DegenerusGameMintModule
  |-- DegenerusGameGameOverModule
  |-- DegenerusGameBoonModule
  |-- DegenerusGameLootboxModule
```

### Module Addresses (Constant, Baked at Compile Time)

| Module | Address Constant | Functions Delegated |
|--------|-----------------|---------------------|
| GAME_ADVANCE_MODULE | `0xA4AD...828c` | advanceGame, wireVrf, updateVrfCoordinatorAndSub, requestLootboxRng, reverseFlip, rawFulfillRandomWords |
| GAME_MINT_MODULE | `0x1d14...f211` | purchase, purchaseCoin, purchaseBurnieLootbox, recordMintData |
| GAME_WHALE_MODULE | `0x03A6...2aAb` | purchaseWhaleBundle, purchaseLazyPass, purchaseDeityPass |
| GAME_JACKPOT_MODULE | `0xD6Bb...FBfF` | runTerminalJackpot |
| GAME_DECIMATOR_MODULE | `0x15cF...27b9` | recordDecBurn, runDecimatorJackpot, recordTerminalDecBurn, runTerminalDecimatorJackpot, consumeDecClaim, claimDecimatorJackpot |
| GAME_ENDGAME_MODULE | `0x2122...bA3C` | claimWhalePass |
| GAME_GAMEOVER_MODULE | `0x2a07...afe3` | (not called from Game.sol directly -- called via AdvanceModule) |
| GAME_LOOTBOX_MODULE | `0x3D7E...90d7` | openLootBox, openBurnieLootBox, issueDeityBoon, resolveRedemptionLootbox |
| GAME_BOON_MODULE | `0xD16d...d70` | consumeCoinflipBoon, consumeDecimatorBoost, consumePurchaseBoost |
| GAME_DEGENERETTE_MODULE | `0x96d3...9758` | placeFullTicketBets, resolveBets |

### Storage Layout Structure

DegenerusGameStorage defines storage in the following slot regions:

| Slot Range | Contents | Packing |
|------------|----------|---------|
| Slot 0 | FSM state: levelStartTime, dailyIdx, rngRequestTime, level, jackpotPhaseFlag, jackpotCounter, poolConsolidationDone, lastPurchaseDay, decWindowOpen, rngLockedFlag, phaseTransitionActive, gameOver, dailyJackpotCoinTicketsPending, dailyEthPhase, compressedJackpotFlag | 32 bytes fully packed |
| Slot 1 | purchaseStartDay, price, ticketWriteSlot, ticketsFullyProcessed, prizePoolFrozen | 25 bytes used, 7 padding |
| Slot 2 | currentPrizePool (uint256) | Full width |
| Slot 3 | prizePoolsPacked (nextPrizePool[128] + futurePrizePool[128]) | Full width, packed pair |
| Slot 4 | rngWordCurrent | Full width |
| Slot 5 | vrfRequestId | Full width |
| Slot 6 | totalFlipReversals | Full width |
| Slot 7 | dailyTicketBudgetsPacked | Full width, packed |
| Slot 8 | dailyEthPoolBudget | Full width |
| Slots 9+ | Mappings and dynamic arrays (claimableWinnings, claimablePool, traitBurnTicket, mintPacked_, rngWordByDay, etc.) | Each mapping/array root gets its own slot |

**Critical audit note:** The manual slot comments in the source describe slots 0-1 in detail. Slots 2+ are sequential uint256s, mappings, and arrays. The `forge inspect` output (D-03) is needed to verify exact slot numbers for all variables.

### Access Control Matrix (Router Entry Points)

| Access Gate | Functions |
|-------------|-----------|
| No restriction (any caller) | `advanceGame`, `requestLootboxRng`, `reverseFlip`, `purchase`, `purchaseCoin`, `purchaseBurnieLootbox`, `purchaseWhaleBundle`, `purchaseLazyPass`, `purchaseDeityPass`, `openLootBox`, `openBurnieLootBox`, `placeFullTicketBets`, `resolveDegeneretteBets`, `setOperatorApproval`, `claimDecimatorJackpot`, `receive()` |
| Operator-approved | `claimWinnings`, `claimAffiliateDgnrs`, `setAutoRebuy`, `setDecimatorAutoRebuy`, `setAutoRebuyTakeProfit`, `setAfKingMode`, `claimWhalePass`, `issueDeityBoon` |
| `msg.sender == address(this)` (self-call) | `recordMint`, `runDecimatorJackpot`, `runTerminalDecimatorJackpot`, `runTerminalJackpot`, `consumeDecClaim`, `consumePurchaseBoost` |
| `msg.sender == COIN` | `recordMintQuestStreak` |
| `msg.sender == COIN or COINFLIP` | `payCoinflipBountyDgnrs`, `consumeCoinflipBoon`, `deactivateAfKingFromCoin` |
| `msg.sender == COINFLIP` | `syncAfKingLazyPassFromCoin`, `consumeDecimatorBoon` (only COIN) |
| `msg.sender == SDGNRS` | `resolveRedemptionLootbox` |
| `msg.sender == VAULT or SDGNRS` | `claimWinningsStethFirst` |
| `msg.sender == ADMIN` | `wireVrf`, `updateVrfCoordinatorAndSub`, `setLootboxRngThreshold`, `adminSwapEthForStEth`, `adminStakeEthForStEth` |

**Note on access control:** The "no restriction" functions delegate to modules which enforce their own access control internally (e.g., `advanceGame` delegates to AdvanceModule which checks daily gate). The router does NOT add access control for these -- it trusts the module. This is an audit point: verify the module actually checks.

### Module Storage Safety (D-04 -- Verified)

All 10 modules inherit DegenerusGameStorage through one of three paths:
1. Direct: `is DegenerusGameStorage` (AdvanceModule, MintModule, GameOverModule, BoonModule, LootboxModule)
2. Via PayoutUtils: `is DegenerusGamePayoutUtils` -> `is DegenerusGameStorage` (EndgameModule, JackpotModule, DecimatorModule)
3. Via MintStreakUtils: `is DegenerusGameMintStreakUtils` -> `is DegenerusGameStorage` (WhaleModule)
4. Diamond (both): DegeneretteModule `is DegenerusGamePayoutUtils, DegenerusGameMintStreakUtils`

**No module adds non-constant state variables.** Verified by grep: all module-level declarations are `private constant` or `internal constant`, which do not occupy storage slots. This means the delegatecall storage layout is safe from module-introduced slot collisions.

## High-Risk Functions for Mad Genius

### Tier 1: Highest Risk (Complex Direct State Changes)

1. **`recordMint()` (lines 374-419)** -- Multiple payment paths (DirectEth/Claimable/Combined), writes to claimableWinnings, claimablePool, prize pools (respects freeze state), calls `_recordMintDataModule` (delegatecall), calls `_awardEarlybirdDgnrs`. This is the BAF-class risk area: caches a local prize contribution, then calls a delegatecall that could modify the same pools.

2. **`resolveRedemptionLootbox()` (lines 1729-1779)** -- Hybrid function. Debits `claimableWinnings[SDGNRS]` with unchecked arithmetic ("SAFETY" comment claims mutual exclusivity with gameOver path). Credits prize pool (respects freeze). Then loops delegatecall to lootbox module. The unchecked subtraction on line 1744 is the highest-risk single line.

3. **`_claimWinningsInternal()` (lines 1361-1377)** -- CEI pattern for ETH payouts. Writes `claimableWinnings[player] = 1` (sentinel), decrements `claimablePool`, then makes external `.call{value}`. Fallback to stETH adds complexity.

4. **`claimAffiliateDgnrs()` (lines 1388-1431)** -- Reads from affiliate contract, computes pro-rata share from segregated allocation, calls `dgnrs.transferFromPool`, credits deity bonus via `coin.creditFlip`. Multiple external calls. Deity pass bonus path needs careful examination.

5. **`_setAfKingMode()` (lines 1566-1605)** -- Writes multiple fields on `autoRebuyState`, makes external call to `coinflip.setCoinflipAutoRebuy` and `coinflip.settleFlipModeChange`. Cross-contract state sync risk.

### Tier 2: Medium Risk

6. **`receive()` (line 2838-2847)** -- Accepts ETH and routes to prize pools. Respects freeze state. Risk: does `uint128(msg.value)` silently truncate values > 2^128?

7. **`adminStakeEthForStEth()` (lines 1833-1853)** -- Reserve calculation excludes vault/SDGNRS claimable. Risk: if claimablePool < stethSettleable, reserve becomes 0, allowing staking all ETH.

8. **`adminSwapEthForStEth()` (lines 1813-1824)** -- Value-neutral swap. Risk: stETH transfer rounding could leave game short.

9. **`setDecimatorAutoRebuy()` (lines 1469-1477)** -- RNG-locked guard. Simple but needs verification that state writes are correct.

10. **`setLootboxRngThreshold()` (lines 512-522)** -- ADMIN-only setter. Emits event even when value unchanged (line 517). Trivial but needs checklist entry.

### Tier 3: Dispatch Verification Focus

All 30 delegatecall dispatchers need:
- Correct module address from ContractAddresses
- Correct selector encoding (function name on interface matches)
- Correct parameter forwarding (all params passed through)
- Correct return value decoding (if any)
- No state changes before/after the delegatecall (pure dispatch)

**Notable dispatch anomaly:** `consumeDecimatorBoon()` (line 821) dispatches to `consumeDecimatorBoost.selector` -- different function name. This is a deliberate interface choice (the boon module exposes it as "boost") but must be verified as intentional and correctly wired.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Storage layout verification | Manual slot counting | `forge inspect DegenerusGame storage-layout` | Compiler output is authoritative; manual counting errors are the exact bug class we're auditing for |
| Function enumeration | Manual reading | grep + `forge inspect` ABI | Ensures completeness |
| Cross-module storage alignment | Compare source by eye | Compare `forge inspect` output across all module contracts | Exact slot numbers must match |

## Common Pitfalls

### Pitfall 1: Assuming Delegatecall-Only Functions Are Harmless
**What goes wrong:** Auditor marks all delegatecall dispatchers as "simple wrapper, no analysis needed" and misses that some wrappers do work before/after the delegatecall.
**Why it happens:** The majority of dispatchers ARE pure wrappers, creating a pattern that lulls the auditor.
**How to avoid:** `resolveRedemptionLootbox()` is NOT a pure wrapper -- it performs claimableWinnings debit, claimablePool decrement, and prize pool credit BEFORE the delegatecall loop. Flag every function that has code besides the standard dispatch-and-revert pattern.
**Warning signs:** Code between the function signature and the `.delegatecall(` call, or after the `if (!ok)` check.

### Pitfall 2: Selector Mismatch Between Router and Module Interface
**What goes wrong:** Router encodes one selector but module exposes a different function name. The delegatecall silently falls through to fallback or reverts with unhelpful error.
**Why it happens:** Interface renaming during development. The `consumeDecimatorBoon` -> `consumeDecimatorBoost` mismatch is a real example.
**How to avoid:** For every dispatch, verify: (1) the interface declares the function with that exact name, (2) the module contract implements a function matching that selector.
**Warning signs:** Function name in router doesn't match the selector's source interface function name.

### Pitfall 3: Missing Access Control on Delegatecall Dispatchers
**What goes wrong:** Router dispatches to module without checking who called. If the module also doesn't check (assuming the router checked), anyone can call a privileged function.
**Why it happens:** Split responsibility: "the module checks access" vs "the router checks access." Neither checks.
**How to avoid:** For each external dispatcher, verify either (1) the router checks `msg.sender` before delegating, OR (2) the module checks `msg.sender` as its first operation. Document which layer owns the check.
**Warning signs:** External function with no `require`/`revert` before `delegatecall`, AND the module interface doesn't document access control.

### Pitfall 4: uint128 Truncation on Prize Pool Writes
**What goes wrong:** `prizePoolsPacked` stores next and future pools as uint128. If a value exceeds 2^128, the cast `uint128(value)` silently truncates.
**Why it happens:** uint128 max is ~3.4e20 ETH (340 quintillion ETH), so this is theoretically impossible with real ETH supply. But if the game logic accumulates values through multiplication, intermediate results could overflow.
**How to avoid:** Verify no code path can produce values > uint128.max before the cast. Document as INFO if analysis shows it's unreachable.
**Warning signs:** `uint128(someUint256)` casts on computed values rather than direct amounts.

### Pitfall 5: Prize Pool Freeze State Inconsistency
**What goes wrong:** Code path writes to `prizePoolsPacked` when `prizePoolFrozen == true`, or to `prizePoolPendingPacked` when `prizePoolFrozen == false`. This would either corrupt frozen values or lose pending revenue.
**Why it happens:** Multiple entry points (recordMint, resolveRedemptionLootbox, receive) all need to respect freeze state independently.
**How to avoid:** Verify every function that writes to either pool variable checks `prizePoolFrozen` and routes to the correct accumulator.
**Warning signs:** Direct writes to `prizePoolsPacked` without checking `prizePoolFrozen` first.

## Work Chunking Strategy for Three Agents

### Recommended Splits

The total work for this unit breaks into 3 natural waves:

**Wave 1 -- Taskmaster + Storage Layout Verification:**
1. Build complete function checklist (use inventory from this research)
2. Run `forge inspect DegenerusGame storage-layout` and cross-reference against manual comments
3. Run `forge inspect` on all 10 module contracts and verify slot alignment
4. Verify no module adds non-constant state variables (already confirmed by grep, but Taskmaster should independently verify)

**Wave 2 -- Mad Genius Attack (split into 2 sub-waves):**
- **Wave 2a: Direct State-Changing Functions** (19 functions, high depth)
  - Tier 1 functions: recordMint, resolveRedemptionLootbox, _claimWinningsInternal, claimAffiliateDgnrs, _setAfKingMode
  - Tier 2 functions: receive, admin functions, auto-rebuy setters
  - Each gets full call tree, storage-write map, cache check, all attack angles

- **Wave 2b: Delegatecall Dispatch Verification** (30 functions, lower depth)
  - For each: verify module address, selector, parameter forwarding, return decoding
  - Flag any that perform pre/post-delegatecall logic (resolveRedemptionLootbox already identified)
  - Verify access control ownership (router vs module)

**Wave 3 -- Coverage Review + Skeptic:**
- Taskmaster reviews coverage, interrogates gaps
- Skeptic validates all VULNERABLE/INVESTIGATE findings

### Estimated Function Counts for Checklist

| Category | Count | Depth |
|----------|-------|-------|
| External state-changing (direct) | 19 | Full analysis |
| External state-changing (dispatch) | 30 | Dispatch verification |
| View/Pure (external) | ~60 | Minimal (verify no side effects) |
| Internal helpers (state-changing) | 15 (Storage) + 2 (MintStreak) | Analyzed as part of caller's call tree |
| Internal helpers (view/pure) | ~13 | Analyzed as part of caller's call tree |

**Total checklist entries needed:** At minimum 49 state-changing external functions + `receive()` = 50 entries. Internal helpers are analyzed transitively through their callers.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge) 1.5.1-stable |
| Config file | `foundry.toml` (assumed -- standard for forge projects) |
| Quick run command | `forge test --match-contract DegenerusGameTest -x` |
| Full suite command | `forge test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| UNIT-01 | Game Router + Storage Layout audit complete | manual | N/A -- audit deliverables, not runnable tests | N/A |
| COV-01 | Function checklist covers all state-changing functions | manual | Compare checklist against `forge inspect --json` ABI output | N/A |
| COV-02 | Every checklist entry fully analyzed | manual | Review ATTACK-REPORT.md sections | N/A |
| COV-03 | 100% coverage before Skeptic | manual | Taskmaster COVERAGE-REVIEW.md verdict | N/A |
| ATK-01-05 | Attack analysis quality | manual | Review ATTACK-REPORT.md per function | N/A |
| VAL-01-04 | Skeptic validation quality | manual | Review SKEPTIC-REVIEW.md verdicts | N/A |

### Sampling Rate
- **Per task commit:** Verify deliverable file exists and follows format
- **Per wave merge:** Cross-reference checklist completeness
- **Phase gate:** All 3 agent deliverables (COVERAGE-CHECKLIST.md, ATTACK-REPORT.md, SKEPTIC-REVIEW.md) complete with PASS verdicts

### Wave 0 Gaps
This phase is a manual audit, not a code-change phase. No automated test infrastructure is needed. The "tests" are the three-agent review cycle itself.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| forge | Storage layout inspection (D-03) | Yes | 1.5.1-stable | -- |

**Missing dependencies:** None.

## Open Questions

1. **Exact slot numbers for all 50+ storage variables**
   - What we know: Slots 0-1 are documented in source comments. Slots 2+ are sequential but slot numbers depend on declaration order.
   - What's unclear: Exact slot number for every variable from slot 9 onward (mappings, arrays, structs).
   - Recommendation: Run `forge inspect DegenerusGame storage-layout` during Wave 1 to get authoritative mapping. This is a required step per D-03.

2. **DegeneretteModule diamond inheritance**
   - What we know: `DegenerusGameDegeneretteModule is DegenerusGamePayoutUtils, DegenerusGameMintStreakUtils`. Both inherit `DegenerusGameStorage`.
   - What's unclear: Solidity linearization resolves this via C3, but worth verifying no duplicate storage slots result.
   - Recommendation: Verify via `forge inspect DegenerusGameDegeneretteModule storage-layout` that slot layout matches `DegenerusGame`.

3. **GAME_GAMEOVER_MODULE never called from Game.sol directly**
   - What we know: `ContractAddresses.GAME_GAMEOVER_MODULE` exists but DegenerusGame.sol has no delegatecall to it.
   - What's unclear: How does game-over drain logic get invoked?
   - Recommendation: Likely called from AdvanceModule (which this phase does NOT audit internally per D-01). Verify the dispatch chain exists but defer internal analysis to the AdvanceModule phase (104).

## Sources

### Primary (HIGH confidence)
- `contracts/DegenerusGame.sol` -- Full source read (2,848 lines)
- `contracts/storage/DegenerusGameStorage.sol` -- Full source read (1,613 lines)
- `contracts/interfaces/IDegenerusGameModules.sol` -- Full source read (394 lines)
- `contracts/interfaces/IDegenerusGame.sol` -- Full source read (444 lines)
- `contracts/modules/DegenerusGameMintStreakUtils.sol` -- Full source read
- `contracts/ContractAddresses.sol` -- Full source read (38 lines)
- `.planning/ULTIMATE-AUDIT-DESIGN.md` -- Three-agent system design
- `.planning/REQUIREMENTS.md` -- v5.0 audit requirements
- `audit/KNOWN-ISSUES.md` -- Known issues list

### Secondary (MEDIUM confidence)
- Module inheritance verified by grep across all 12 module files
- Storage variable absence in modules verified by grep (no non-constant state vars)

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Function inventory: HIGH -- complete source read of both contracts, grep-verified
- Architecture patterns: HIGH -- inheritance chain and module wiring directly verified from source
- Storage layout: MEDIUM -- slot comments verified for slots 0-1, slots 2+ need `forge inspect` confirmation (Wave 1 task)
- Pitfalls: HIGH -- based on known BAF bug pattern and direct source analysis
- Work chunking: HIGH -- derived from function categorization and ULTIMATE-AUDIT-DESIGN.md workflow

**Research date:** 2026-03-25
**Valid until:** Indefinite (auditing static source code, no external dependencies that change)
