# Delta Extraction: v5.0 to HEAD

**Diff boundary:** v5.0..HEAD (per D-01)
**Method:** Fresh git diff only (per D-02)
**Change threshold:** Semantic code changes only; comment/NatSpec-only = UNCHANGED (per D-03)
**Generated:** 2026-04-10

## Summary Statistics

- Total contract files in scope: 55 (46 in diff + 9 unchanged)
- NEW: 4 (GNRUS.sol, MockGameCharity.sol, MockSDGNRSCharity.sol, MockVaultCharity.sol)
- DELETED: 2 (DegenerusGameEndgameModule.sol, DegenerusGameModuleInterfaces.sol)
- MODIFIED: 39
- UNCHANGED: 10 (Icons32Data.sol reclassified per D-03; DegenerusTraitUtils.sol, IStETH.sol, IVaultCoin.sol, IVRFCoordinator.sol, EntropyLib.sol, PriceLookupLib.sol, MockLinkEthFeed.sol, MockLinkToken.sol, MockStETH.sol)
- Total function-level changes: ~444 entries across both changelogs (240 module + 204 core)

## Detailed Changelogs

Module and storage contracts: see [213-01-DELTA-MODULES.md](213-01-DELTA-MODULES.md)
Core contracts (main, interfaces, libraries, mocks): see [213-02-DELTA-CORE.md](213-02-DELTA-CORE.md)

## Cross-Module Interaction Map

This section maps every cross-contract call chain between changed functions. All module functions execute via `delegatecall` from DegenerusGame, meaning they run in Game's storage context and make external calls as the Game address.

### State-Mutation Chains

| Chain ID | Caller | Callee | Mechanism | State Written | Audit Phase |
|----------|--------|--------|-----------|---------------|-------------|
| SM-01 | DegenerusGame.advanceGame() | AdvanceModule.advanceGame() | delegatecall | pools (currentPrizePool, nextPrizePool, futurePrizePool), purchaseStartDay, dailyIdx, gameOverPossible, level, ticketWriteSlot, presaleStatePacked, rngLockedFlag | 214 |
| SM-02 | AdvanceModule._consolidatePoolsAndRewardJackpots() | JackpotModule.distributeYieldSurplus() | delegatecall (nested from AdvanceModule) | claimableWinnings[sDGNRS], claimableWinnings[VAULT], claimableWinnings[GNRUS] | 216 |
| SM-03 | AdvanceModule._consolidatePoolsAndRewardJackpots() | DegenerusGame.runBafJackpot() -> JackpotModule.runBafJackpot() | self-call + delegatecall | claimableWinnings[winners], futurePool (lootbox/refund), ticketQueue entries | 216 |
| SM-04 | AdvanceModule._rewardTopAffiliate() | DegenerusStonk.transferFromPool() | external call | DGNRS balances, pool balances, levelDgnrsAllocation | 214 |
| SM-05 | AdvanceModule.advanceGame() | DegenerusQuests.rollDailyQuest() | external call | quest state (daily slot, roll, target) | 214 |
| SM-06 | AdvanceModule.advanceGame() | DegenerusQuests.rollLevelQuest() | external call | quest state (level quest slot, target) | 214 |
| SM-07 | AdvanceModule.advanceGame() | GNRUS.pickCharity() | external call | GNRUS balances (charity distribution), levelCharityRecipient | 214 |
| SM-08 | AdvanceModule.advanceGame() | StakedDegenerusStonk.resolveRedemptionPeriod() | external call | redemption period state (resolved flag, flipDay) | 214 |
| SM-09 | AdvanceModule.payDailyJackpot() -> JackpotModule.payDailyJackpot() | delegatecall | claimableWinnings[winners], futurePool, resumeEthPool, dailyJackpotTraitsPacked, ticketQueue entries | 216 |
| SM-10 | AdvanceModule.payDailyJackpotCoinAndTickets() -> JackpotModule.payDailyJackpotCoinAndTickets() | delegatecall | ticketQueue entries, dailyJackpotTraitsPacked | 216 |
| SM-11 | JackpotModule._awardDailyCoinToTraitWinners() | BurnieCoinflip.creditFlip() | external call (as Game) | coinflip state (pending flips per player) | 216 |
| SM-12 | JackpotModule._awardDailyCoinToTraitWinners() | BurnieCoinflip.creditFlipBatch() | external call (as Game) | coinflip state (pending flips per player, batch) | 216 |
| SM-13 | DegenerusGame.purchase() -> MintModule.purchase() | delegatecall | mintPacked_, nextPrizePool, futurePrizePool, ticketQueue entries, lootboxRng packed state | 214 |
| SM-14 | MintModule.purchase() | DegenerusAffiliate.payAffiliate() | external call (as Game) | affiliate balances, leaderboard, referral state | 214 |
| SM-15 | MintModule.purchase() | DegenerusQuests.handlePurchase() | external call (as Game) | quest progress (mint + lootbox paths combined) | 214 |
| SM-16 | MintModule.purchase() | DegenerusQuests.handleMint() | external call (as Game) | quest progress (mint path) | 214 |
| SM-17 | MintModule.purchase() | BurnieCoinflip.creditFlip() | external call (as Game) | coinflip state (lootbox flip credit) | 214 |
| SM-18 | MintModule.processTicketBatch() (moved from JackpotModule) | Game storage | delegatecall | NFT minting, ticketQueue cursor, remainder tracking | 214 |
| SM-19 | DegenerusGame.purchaseWhaleBundle() -> WhaleModule.purchaseWhaleBundle() | delegatecall | mintPacked_ (deity pass bit), ticketQueue entries (100-level range), lootboxRng packed state, presaleStatePacked | 214 |
| SM-20 | WhaleModule.claimWhalePass() (moved from EndgameModule) | Game storage | delegatecall | claimableWinnings, ticketQueue entries (range), mintPacked_ | 214 |
| SM-21 | WhaleModule.purchaseDeityPass() | DegenerusStonk.transferFromPool() | external call (as Game) | DGNRS balances, mintPacked_ (HAS_DEITY_PASS_SHIFT) | 214 |
| SM-22 | DegenerusGame.placeDegeneretteBet() -> DegeneretteModule.placeDegeneretteBet() | delegatecall | bet state, claimablePool, lootboxRng packed state, pending pools | 214 |
| SM-23 | DegeneretteModule._placeDegeneretteBetCore() | DegenerusQuests.handleDegenerette() | external call (as Game) | quest progress (degenerette path) | 214 |
| SM-24 | DegeneretteModule._distributePayout() | StakedDegenerusStonk.transferFromPool() | external call (as Game) | sDGNRS pool balances | 216 |
| SM-25 | DegenerusGame.openLootBox() -> LootboxModule.openLootbox() | delegatecall | boon state (multi-boon), ticketQueue entries, presaleStatePacked | 214 |
| SM-26 | LootboxModule._resolveLootboxCommon() | BurnieCoinflip.creditFlip() | external call (as Game) | coinflip state (lootbox BURNIE reward) | 214 |
| SM-27 | LootboxModule._rollLootboxBoons() -> BoonModule (nested delegatecall) | delegatecall | boon packed state (per-player deity/lootbox boons) | 214 |
| SM-28 | DegenerusGame.consumeCoinflipBoon() -> BoonModule.consumeCoinflipBoon() | delegatecall | boon packed state (clears coinflip boon) | 214 |
| SM-29 | DegenerusGame.consumeDecimatorBoon() -> BoonModule.consumeDecimatorBoost() | delegatecall | boon packed state (clears decimator boon) | 214 |
| SM-30 | DegenerusGame.consumePurchaseBoost() -> BoonModule.consumePurchaseBoost() | delegatecall | boon packed state (clears purchase boon) | 214 |
| SM-31 | BurnieCoin.decimatorBurn() | DegenerusGame.consumeDecimatorBoon() -> BoonModule | external call + delegatecall | boon packed state, BURNIE balances, decimator state | 214 |
| SM-32 | BurnieCoin.decimatorBurn() | DegenerusQuests.handleDecimator() | external call | quest progress (decimator path) | 214 |
| SM-33 | DegenerusGame.recordTerminalDecBurn() -> DecimatorModule.recordTerminalDecBurn() | delegatecall | terminal decimator entries (burn records) | 214 |
| SM-34 | DecimatorModule.claimDecimatorJackpot() | Game storage (_creditClaimable) | delegatecall | claimableWinnings[winner], claimablePool (uint128) | 216 |
| SM-35 | DecimatorModule._awardDecimatorLootbox() | Game storage (_queueTicketRange) | delegatecall | ticketQueue entries | 214 |
| SM-36 | DegenerusAdmin.proposeFeedSwap() | StakedDegenerusStonk.votingSupply() | external call | FeedProposal state (votingSnapshot) | 214 |
| SM-37 | DegenerusAdmin.voteFeedSwap() | StakedDegenerusStonk.votingSupply() | external call | FeedProposal votes, execution (VRF coordinator swap) | 214 |
| SM-38 | DegenerusAdmin.vote() (VRF swap) | StakedDegenerusStonk.votingSupply() | external call | Proposal votes (repacked struct) | 214 |
| SM-39 | DegenerusAdmin.onTokenTransfer() | BurnieCoinflip.creditFlip() (via coinflipReward) | external call | coinflip state (LINK purchase reward) | 214 |
| SM-40 | DegenerusAffiliate.payAffiliate() | DegenerusQuests.handleAffiliate() | external call | quest progress (affiliate path) | 214 |
| SM-41 | DegenerusAffiliate.payAffiliate() | BurnieCoinflip.creditFlip() | external call | coinflip state (affiliate reward) | 214 |
| SM-42 | DegenerusQuests.handleMint() | BurnieCoinflip.creditFlip() | external call | coinflip state (quest reward) | 214 |
| SM-43 | DegenerusQuests.handleLootBox() | BurnieCoinflip.creditFlip() | external call | coinflip state (quest reward) | 214 |
| SM-44 | DegenerusQuests.handleDegenerette() | BurnieCoinflip.creditFlip() | external call | coinflip state (quest reward) | 214 |
| SM-45 | DegenerusQuests.handleAffiliate() | BurnieCoinflip.creditFlip() | external call | coinflip state (quest reward) | 214 |
| SM-46 | DegenerusQuests.handleDecimator() | BurnieCoinflip.creditFlip() | external call | coinflip state (quest reward) | 214 |
| SM-47 | DegenerusQuests.handlePurchase() | BurnieCoinflip.creditFlip() | external call | coinflip state (unified purchase quest reward) | 214 |
| SM-48 | BurnieCoinflip.depositCoinflip() | BurnieCoin.burnForCoinflip() | external call | BURNIE balances (burn) | 214 |
| SM-49 | BurnieCoinflip._claimInternal() | BurnieCoin.mintForGame() | external call | BURNIE balances (mint) | 214 |
| SM-50 | DegenerusVault.gameDegeneretteBet() | DegenerusGame.placeDegeneretteBet() | external call | bet state (via delegatecall chain to DegeneretteModule) | 214 |
| SM-51 | DegenerusVault.sdgnrsBurn() | StakedDegenerusStonk (burn path) | external call | sDGNRS balances, backing assets | 214 |
| SM-52 | DegenerusVault.sdgnrsClaimRedemption() | StakedDegenerusStonk (claim path) | external call | redemption claims, sDGNRS state | 214 |
| SM-53 | StakedDegenerusStonk.poolTransfer() (self-win burn) | internal | burns sDGNRS on self-win instead of no-op | 214 |
| SM-54 | DegenerusStonk.claimVested() | internal | DGNRS balances (vested allocation release) | 214 |
| SM-55 | DegenerusStonk.yearSweep() | GNRUS (ETH transfer) + DegenerusVault (ETH transfer) | external call | DGNRS/sDGNRS balances (burns remaining), ETH splits | 216 |
| SM-56 | DegenerusDeityPass.onlyOwner | DegenerusVault.isVaultOwner() | external call | none (read-only guard, but gate for state-mutating setRenderer/mint) | 214 |

### ETH-Flow Chains

| Chain ID | Path | ETH Direction | Guard | Audit Phase |
|----------|------|---------------|-------|-------------|
| EF-01 | Game.purchase() -> MintModule -> recordMint -> _processMintPayment | in (player ETH) | rngLocked gate, level/price validation | 216 |
| EF-02 | AdvanceModule._consolidatePoolsAndRewardJackpots() -> pools | internal (futurePool -> nextPool -> currentPrizePool consolidation, yield dump, drawdown) | single-SSTORE batch, batched pool math in memory | 216 |
| EF-03 | AdvanceModule -> JackpotModule.distributeYieldSurplus() -> claimableWinnings[sDGNRS, VAULT, GNRUS] | out (yield to protocol recipients) | 23% each + 23% accumulator + 8% buffer | 216 |
| EF-04 | JackpotModule.payDailyJackpot() -> _processDailyEth() -> _addClaimableEth() | out (jackpot to winners) | two-call split (SPLIT_NONE / CALL1 / CALL2), resumeEthPool | 216 |
| EF-05 | JackpotModule._handleSoloBucketWinner() -> _addClaimableEth() + whale pass + DGNRS reward | out (solo bucket winner) | final-day check for whale pass and DGNRS | 216 |
| EF-06 | JackpotModule.runBafJackpot() (moved from EndgameModule) -> _addClaimableEth() | out (BAF jackpot to winners) | self-call guard, returns claimableDelta | 216 |
| EF-07 | DecimatorModule.claimDecimatorJackpot() -> _creditClaimable() | out (decimator payout) | claimablePool cast to uint128, no auto-rebuy | 216 |
| EF-08 | DecimatorModule.claimTerminalDecimatorJackpot() -> _creditClaimable() | out (terminal decimator payout) | <=7 days blocked, multiplier redesigned | 216 |
| EF-09 | DegeneretteModule._distributePayout() -> _creditClaimable() | out (degenerette winnings) | claimablePool narrowed uint128 | 216 |
| EF-10 | GameOverModule.handleGameOverDrain() -> terminal jackpots + BAF + decimator + _creditClaimable() | out (gameover payouts) | RNG gate defense-in-depth, gameOverStatePacked | 216 |
| EF-11 | GameOverModule.handleFinalSweep() -> _sendToVault() -> _sendStethFirst() | out (33/33/34 split: sDGNRS / VAULT / GNRUS) | 30-day delay, stETH-first, gameOverStatePacked | 216 |
| EF-12 | Game._claimWinningsInternal() | out (player claim) | claimablePool uint128, _goRead packed field for finalSwept | 216 |
| EF-13 | GNRUS.burn() -> game.claimWinnings(address(this)) | out (GNRUS redemption, proportional ETH+stETH) | proportional to caller's GNRUS balance | 216 |
| EF-14 | GNRUS.pickCharity() -> GNRUS distribution | internal (2% of unallocated per level) | sDGNRS-weighted governance vote | 216 |
| EF-15 | Game.claimAffiliateDgnrs() -> coinflip.creditFlip() | out (DGNRS affiliate claim + flip credit) | PriceLookupLib for price, mintPacked_ for deity pass | 216 |
| EF-16 | WhaleModule.purchaseWhaleBundle() / purchaseLazyPass() / purchaseDeityPass() | in (player ETH for passes) | presaleStatePacked, mintPacked_ deity bit | 216 |
| EF-17 | DegeneretteModule._collectBetFunds() | in (degenerette bet funds) | lootboxRngPendingEth packed milli-ETH encoding | 216 |
| EF-18 | StakedDegenerusStonk.burnAtGameOver() (renamed from burnRemainingPools) | out (burns remaining pools at gameover) | gameOver gate | 216 |
| EF-19 | DegenerusStonk.yearSweep() -> 50/50 GNRUS + VAULT | out (1-year post-gameover sweep) | SweepNotReady / NothingToSweep guards | 216 |
| EF-20 | AdvanceModule.advanceGame() -> coinflip.creditFlip() (pool consolidation BURNIE credit) | out (BURNIE flip credit during consolidation) | inlined from _creditDgnrsCoinflip | 216 |

### RNG Chains

| Chain ID | Request Origin | Fulfillment Handler | Word Consumers | Audit Phase |
|----------|---------------|--------------------|--------------------|-------------|
| RNG-01 | AdvanceModule._requestRng() (VRF coordinator) | DegenerusGame.rawFulfillRandomWords() -> AdvanceModule.rawFulfillRandomWords() (delegatecall) | rngGate (daily word), advanceGame (all daily processing), _backfillGapDays (gap entropy via keccak) | 215 |
| RNG-02 | AdvanceModule.requestLootboxRng() (VRF coordinator) | AdvanceModule._finalizeLootboxRng() | lootboxRngWordByIndex (per-index words), LootboxModule.openLootbox/openBurnieLootbox (lootbox resolution), _rollLootboxBoons (boon RNG) | 215 |
| RNG-03 | JackpotModule._randTraitTicket() (merged with _randTraitTicketWithIndices) | n/a (derives from daily word) | keccak256(abi.encode(randomWord, trait, salt, i)) per winner -- used in payDailyJackpot, _awardDailyCoinToTraitWinners, _runEarlyBirdLootboxJackpot | 215 |
| RNG-04 | JackpotModule._runJackpotEthFlow() | n/a (derives from daily word) | entropy rotation across [20, 12, 6, 1] = 39 fixed bucket counts, _processDailyEth winner selection | 215 |
| RNG-05 | JackpotModule.payDailyJackpot() carryover | n/a (derives from daily word) | 0.5% futurePool as tickets, keccak256 modulo for source offset [1..4] | 215 |
| RNG-06 | DegeneretteModule._placeDegeneretteBetCore() | resolved via daily RNG word | bet resolution using _resolveFullTicketBet, lootboxRngIndex via _lrRead for activity score | 215 |
| RNG-07 | MintModule._raritySymbolBatch() (moved from JackpotModule) | n/a (derives from lootboxRngWord) | LCG PRNG assembly-based bulk trait generation for ticket processing | 215 |
| RNG-08 | AdvanceModule._gameOverEntropy() | n/a (fallback prevrandao) | gameover path entropy when VRF word unavailable, reverts RngNotReady() instead of returning 0 | 215 |
| RNG-09 | GameOverModule.handleGameOverDrain() | daily word or _gameOverEntropy | terminal jackpot resolution, BAF resolution at gameover | 215 |
| RNG-10 | LootboxModule._deityDailySeed() / _deityBoonForSlot() | n/a (derives from daily word) | deity boon generation, day parameter uint32 | 215 |
| RNG-11 | JackpotModule._rollWinningTraits() / _applyHeroOverride() (renamed from _getWinningTraits) | n/a (derives from daily word) | daily winning trait selection, hero override application | 215 |

### Read-Only Chains

| Chain ID | Caller | Callee | Mechanism | Data Read |
|----------|--------|--------|-----------|-----------|
| RO-01 | AdvanceModule._enforceDailyMintGate() | mintPacked_ (via BitPackingLib) | internal read | deity pass check (HAS_DEITY_PASS_SHIFT replaces deityPassCount mapping) |
| RO-02 | AdvanceModule.advanceGame() | PriceLookupLib.priceForLevel() | library call (pure) | price for current level (replaces price storage variable) |
| RO-03 | JackpotModule._calcDailyCoinBudget() | PriceLookupLib.priceForLevel() | library call (pure) | level price for coin budget calculation |
| RO-04 | MintModule.recordMintData() | BitPackingLib (mintPacked_ affiliate bonus cache) | library call | cached affiliate bonus in bits 185-214 |
| RO-05 | WhaleModule._purchaseWhaleBundle() | _psRead (presaleStatePacked) | internal read | presale active state (replaces lootboxPresaleActive bool) |
| RO-06 | LootboxModule.openBurnieLootbox() | gameOverPossible flag | internal read | endgame gate (replaces timestamp-based BURNIE_LOOT_CUTOFF) |
| RO-07 | DegenerusAdmin.proposeVrfSwap() / vote() | StakedDegenerusStonk.votingSupply() | external call | circulating supply for governance threshold (replaces circulatingSupply()) |
| RO-08 | GNRUS.propose() / vote() | StakedDegenerusStonk.votingSupply() | external call | sDGNRS voting weight for charity governance |
| RO-09 | BurnieCoinflip.depositCoinflip() | DegenerusGame.hasDeityPass() | external call | deity pass status (replaces deityPassCountFor) |
| RO-10 | DecimatorModule._terminalDecDaysRemaining() | purchaseStartDay + deadline | internal read | day-index arithmetic (replaces timestamp) |
| RO-11 | DegenerusGame.claimAffiliateDgnrs() | PriceLookupLib.priceForLevel() + mintPacked_ | library call + internal read | price + deity pass for DGNRS claim calculation |
| RO-12 | GameTimeLib.currentDayIndex() / currentDayIndexAt() | internal | library call (view) | uint32 day index (narrowed from uint48) |

## Architectural Change Impact Summary

The v5.0-to-HEAD delta introduces five major architectural shifts that restructure the protocol's interaction topology:

**EndgameModule elimination and function redistribution.** The DegenerusGameEndgameModule was fully deleted. Its functions were redistributed: `rewardTopAffiliate` was inlined into AdvanceModule as a private function (no longer a delegatecall hop), `runRewardJackpots` was absorbed into the new `_consolidatePoolsAndRewardJackpots` batched flow, `claimWhalePass` was moved to WhaleModule, and `runBafJackpot` was moved to JackpotModule as an external function called via self-call from AdvanceModule. This elimination removes one contract from the delegatecall chain but creates a new self-call pattern (Game -> AdvanceModule delegatecall -> Game.runBafJackpot() self-call -> JackpotModule delegatecall) that must be audited for reentrancy and state consistency.

**Pool consolidation inlining and write batching.** The separate `consolidatePrizePools` and `runRewardJackpots` delegatecalls were replaced by a single `_consolidatePoolsAndRewardJackpots` function that computes all pool math in memory and writes with a single SSTORE batch. This fundamentally changes the pool mutation pattern from multiple sequential reads-and-writes to a compute-then-store model. The yield surplus distribution now includes GNRUS as a third recipient (23% each to sDGNRS, vault, GNRUS; 23% accumulator; 8% buffer).

**Jackpot two-call split.** The daily ETH jackpot processing was split into two calls (CALL1/CALL2) via a `splitMode` parameter and `resumeEthPool` state variable to avoid hitting the block gas limit. `_processDailyEth` now handles both call phases, and `_resumeDailyEth` reconstructs state for the second call. This introduces a new mid-execution state (between CALL1 and CALL2) that downstream audit phases must verify cannot be exploited.

**WXRP removal.** WrappedWrappedXRP was stripped of its wXRP backing entirely -- `unwrap`, `donate`, `wXRPReserves`, and all related state were removed. The token is now a pure mint/burn game reward with no redemption path. MockWXRP decimals changed from 18 to 6.

**Quest routing consolidation and GNRUS addition.** Quest notifications that previously routed through BurnieCoin (coin.notifyQuestMint, etc.) now go directly from modules to DegenerusQuests (quests.handleMint, quests.handlePurchase, etc.). BurnieCoinflip.creditFlip replaced coin.creditFlip/creditFlipBatch everywhere. A new unified `handlePurchase` combines mint and lootbox quest paths. The new GNRUS soulbound donation token adds governance (propose/vote/pickCharity), burn-for-redemption of proportional ETH+stETH, and gameover finalization. GNRUS interacts with DegenerusGame (claimWinnings), StakedDegenerusStonk (votingSupply), and DegenerusVault (isVaultOwner).

## Scope Definition for Downstream Phases

### Phase 214 (Adversarial Audit) Scope

**Changed/new external/public functions requiring adversarial analysis:**

*DegenerusGame (entry contract):*
- advanceGame, purchase, purchaseCoin, purchaseBurnieLootbox, purchaseWhaleBundle, purchaseLazyPass, purchaseDeityPass, placeDegeneretteBet, resolveDegeneretteBets, openLootBox, openBurnieLootBox, consumeCoinflipBoon, consumeDecimatorBoon, consumePurchaseBoost, runBafJackpot, reverseFlip, recordTerminalDecBurn, claimWinningsStethFirst, setLootboxRngThreshold, adminStakeEthForStEth, claimAffiliateDgnrs, recordMintQuestStreak, mintPackedFor, hasDeityPass, gameOverTimestamp

*AdvanceModule (via delegatecall):*
- advanceGame, rngGate, requestLootboxRng, rawFulfillRandomWords
- NEW: _consolidatePoolsAndRewardJackpots, _rewardTopAffiliate (inlined), _distributeYieldSurplus (wrapper), _wadPow, _projectedDrip, _evaluateGameOverAndTarget

*JackpotModule (via delegatecall):*
- payDailyJackpot (param renamed), payDailyJackpotCoinAndTickets, distributeYieldSurplus (made external)
- NEW: runBafJackpot (moved from EndgameModule), _handleSoloBucketWinner, _payNormalBucket, _resumeDailyEth
- MODIFIED: _processDailyEth (major rewrite with splitMode), _addClaimableEth (3-return tuple), _randTraitTicket (merged)

*MintModule (via delegatecall):*
- purchase, purchaseCoin, purchaseBurnieLootbox, recordMintData
- NEW: processTicketBatch, _raritySymbolBatch (moved from JackpotModule)

*WhaleModule (via delegatecall):*
- purchaseWhaleBundle, purchaseLazyPass, purchaseDeityPass
- NEW: claimWhalePass (moved from EndgameModule)

*DecimatorModule (via delegatecall):*
- recordDecimatorBurn, runDecimatorJackpot, claimDecimatorJackpot, recordTerminalDecBurn, claimTerminalDecimatorJackpot
- MODIFIED: _terminalDecMultiplierBps (redesigned), _terminalDecDaysRemaining (day-index)

*GameOverModule (via delegatecall):*
- handleGameOverDrain (day uint32, defense-in-depth), handleFinalSweep (packed state)
- NEW: _sendStethFirst, _sendToVault (33/33/34 split with GNRUS)

*LootboxModule (via delegatecall):*
- openLootbox, openBurnieLootbox, deityBoonSlots, issueDeityBoon
- REMOVED: _activeBoonCategory, _boonCategory (multi-boon support)

*BoonModule (via delegatecall):*
- consumeCoinflipBoon, consumePurchaseBoost, consumeDecimatorBoost, consumeActivityBoon (all emit BoonConsumed)

*DegeneretteModule (via delegatecall):*
- placeDegeneretteBet (renamed from placeFullTicketBets), resolveBets
- REMOVED: consolation prizes

*External contracts:*
- DegenerusAdmin: proposeFeedSwap, voteFeedSwap, feedThreshold, canExecuteFeedSwap, vote (refactored)
- DegenerusAffiliate: payAffiliate (major rework), affiliateBonusPoints (tiered), registerAffiliateCode (address-range rejection), defaultCode
- DegenerusQuests: rollDailyQuest, handleMint, handleLootBox, handleDegenerette, handleDecimator, handleAffiliate, handlePurchase (new), rollLevelQuest (new)
- BurnieCoin: mintForGame (expanded access), burnCoin (access change), decimatorBurn (decWindow simplified)
- BurnieCoinflip: creditFlip (expanded creditors), creditFlipBatch (dynamic arrays), depositCoinflip (auto-rebuy fix)
- DegenerusStonk: claimVested (new), yearSweep (new), unwrapTo (access change), burn (gameOver interface)
- StakedDegenerusStonk: votingSupply (new), poolTransfer (self-win burn), burnAtGameOver (renamed), resolveRedemptionPeriod (void return)
- DegenerusVault: gameDegeneretteBet (consolidated), sdgnrsBurn (new), sdgnrsClaimRedemption (new)
- DegenerusDeityPass: onlyOwner (vault-based), removed owner/transferOwnership
- GNRUS: all functions (entirely new contract)
- WrappedWrappedXRP: unwrap/donate removed (backing stripped)

**State-mutation chain IDs to investigate:** SM-01 through SM-56

### Phase 215 (RNG Fresh Eyes) Scope

**Functions touching RNG state or consuming random words:**

*VRF Lifecycle:*
- AdvanceModule._requestRng() -- VRF request with PriceLookupLib price, packed lootbox state
- DegenerusGame.rawFulfillRandomWords() -> AdvanceModule.rawFulfillRandomWords() -- VRF fulfillment
- AdvanceModule.rngGate() -- returns (uint256 word, uint32 gapDays) tuple
- AdvanceModule._gameOverEntropy() -- fallback, reverts RngNotReady() instead of returning 0
- AdvanceModule.requestLootboxRng() -- packed lootbox RNG state via _lrRead/_lrWrite
- AdvanceModule._finalizeLootboxRng() -- lootbox word assignment

*Word Consumers:*
- JackpotModule._randTraitTicket() -- merged, keccak per-winner indexing replaces bit-rotation
- JackpotModule._runJackpotEthFlow() -- fixed [20,12,6,1] bucket counts with entropy rotation
- JackpotModule._rollWinningTraits() / _applyHeroOverride() -- renamed, simplified
- JackpotModule.payDailyJackpot() -- carryover: 0.5% tickets, keccak modulo source offset
- JackpotModule._resolveTraitWinners() -- payCoin removed, simplified return
- MintModule._raritySymbolBatch() -- LCG PRNG assembly (moved from JackpotModule)
- DegeneretteModule._placeDegeneretteBetCore() -- activity score, bet resolution
- LootboxModule._deityDailySeed() / _deityBoonForSlot() -- deity boon generation
- AdvanceModule._backfillGapDays() -- gap day entropy, 120-day cap
- GameOverModule.handleGameOverDrain() -- gameover RNG resolution

*RNG State Variables:*
- rngLockedFlag (mutual exclusion)
- rngWordByDay mapping (key uint48->uint32)
- lootboxRngWordByIndex (via packed _lrRead/_lrWrite)
- midDayTicketRngPending (via packed field)
- dailyJackpotTraitsPacked (winning traits/level/day)
- gameOverStatePacked (gameover timing)

**RNG chain IDs to investigate:** RNG-01 through RNG-11

### Phase 216 (Pool & ETH Accounting) Scope

**Functions touching pool balances or ETH transfers:**

*Pool Mutation Sites:*
- AdvanceModule._consolidatePoolsAndRewardJackpots() -- entire pool consolidation (future -> next -> current, yield dump, drawdown) as single memory-then-SSTORE batch
- JackpotModule.distributeYieldSurplus() -- 23/23/23/23/8 split to sDGNRS/VAULT/GNRUS/accumulator/buffer
- JackpotModule._processDailyEth() / _resumeDailyEth() -- two-call ETH split model
- JackpotModule._addClaimableEth() -- returns 3-tuple (claimableDelta, rebuyLevel, rebuyTickets)
- JackpotModule._handleSoloBucketWinner() / _payNormalBucket() -- extracted from _processDailyEth
- JackpotModule.runBafJackpot() -- returns claimableDelta only (refund/lootbox stay in future)
- DecimatorModule.claimDecimatorJackpot() -- uses _creditClaimable directly (auto-rebuy removed)
- DecimatorModule._splitDecClaim() -- claimablePool uint128
- DecimatorModule.claimTerminalDecimatorJackpot() -- prizePoolFrozen check removed
- DegeneretteModule._collectBetFunds() / _distributePayout() -- claimablePool uint128
- GameOverModule.handleGameOverDrain() -- RNG defense-in-depth, GNRUS burnAtGameOver, DGNRS burnAtGameOver
- GameOverModule.handleFinalSweep() -> _sendToVault() -- 33/33/34 split (was 50/50), stETH-first
- Game._processMintPayment() -- claimablePool uint128 subtraction
- Game._claimWinningsInternal() -- finalSwept via _goRead, claimablePool uint128
- Game.poolTransferAndRecycle() -- claimablePool uint128

*Pool Storage Changes:*
- currentPrizePool: uint256 -> uint128 in slot 1
- claimablePool: uint256 -> uint128 in slot 1 (packed alongside currentPrizePool)
- futurePrizePool, nextPrizePool: unchanged type but mutation patterns changed
- _getCurrentPrizePool / _setCurrentPrizePool: new helpers for uint128 packed access
- resumeEthPool: replaces dailyEthPoolBudget/dailyEthPhase for two-call split

*External ETH Flows:*
- GNRUS.burn() -> game.claimWinnings(address(this)) -- proportional ETH+stETH redemption
- GNRUS.pickCharity() -- 2% of unallocated GNRUS distributed per level
- DegenerusStonk.yearSweep() -- 50/50 to GNRUS + VAULT, 1-year post-gameover
- StakedDegenerusStonk.burnAtGameOver() -- renamed from burnRemainingPools
- StakedDegenerusStonk.resolveRedemptionPeriod() -- void return (no BURNIE credit at resolution)
- DegenerusVault claimWinnings/claimWinningsStethFirst paths

**ETH-flow chain IDs to investigate:** EF-01 through EF-20
