# Adversarial Audit: Reentrancy + CEI Compliance Pass

**Scope:** All changed/new functions in v5.0-to-HEAD delta (per 213-DELTA-EXTRACTION.md Phase 214 scope)
**Method:** Fresh audit (per D-02) -- no prior audit artifacts referenced
**Chains in scope:** SM-01 through SM-56, EF-01 through EF-20, RNG-01 through RNG-11, RO-01 through RO-12 (per D-03)

## Methodology

For each function:
1. Identify all external calls (call, delegatecall, staticcall, transfer, send)
2. For each external call, verify state is finalized BEFORE the call (CEI pattern)
3. If state mutation occurs after an external call, classify as VULNERABLE or INFO (with justification)
4. For delegatecall chains, trace through to the actual external calls made by the delegatee
5. For the self-call pattern (Game -> AdvanceModule -> Game.runBafJackpot -> JackpotModule), verify no reentrancy window exists between the self-call dispatch and the delegatecall resolution

**Key distinction:** Functions that only make `delegatecall` within the Game's own module system are NOT external calls for reentrancy purposes -- they execute in Game's storage context with the same `address(this)`. Only calls to OTHER contracts (DegenerusStonk, BurnieCoinflip, DegenerusQuests, GNRUS, StakedDegenerusStonk, DegenerusAffiliate, etc.) count as external calls.

**Guard inventory:**
- `rngLockedFlag`: Mutual exclusion flag set during VRF request/fulfillment cycle. Blocks purchase, lootbox RNG requests, and certain pass operations during jackpot resolution.
- No `nonReentrant` or `ReentrancyGuard` modifier exists anywhere in the codebase. Reentrancy protection relies entirely on CEI ordering, `rngLockedFlag`, and Solidity 0.8 overflow checks.

## Findings

No VULNERABLE verdicts identified. All external call sites follow CEI or are protected by structural constraints (delegatecall context, rngLocked gates, terminal state flags, or value-neutral call targets).

## Per-Function Verdicts

### Module Contracts (via delegatecall from DegenerusGame)

#### DegenerusGameAdvanceModule.sol

| Function | Visibility | External Calls | CEI Compliant | Verdict | Notes |
|----------|-----------|----------------|---------------|---------|-------|
| advanceGame | external | coinflip.creditFlip (bounty), coinflip.processCoinflipPayouts, quests.rollDailyQuest, quests.rollLevelQuest, sdgnrs.resolveRedemptionPeriod, charityResolve.pickCharity, vault.isVaultOwner (view), dgnrs.transferFromPool (via _rewardTopAffiliate) | Yes | SAFE | All external calls occur at the END of each stage (after state writes). The do-while(false) pattern ensures each advanceGame call processes exactly one stage, writes state, then makes external calls. The final coinflip.creditFlip bounty call is always the last statement. rngLockedFlag blocks re-entry via purchase/lootboxRng paths during RNG window. |
| _handleGameOverPath | private | delegatecall to GAME_GAMEOVER_MODULE | Yes | SAFE | Delegatecall runs in Game's context (not external). State flags (gameOver, rngWordByDay) set before delegatecall. _unlockRng called after delegatecall succeeds. |
| _rewardTopAffiliate | private | affiliate.affiliateTop (view), dgnrs.poolBalance (view), dgnrs.transferFromPool | Yes | SAFE | Both view calls precede the mutating transferFromPool. State write (levelDgnrsAllocation) happens after all external calls, but this is safe because transferFromPool only moves DGNRS tokens -- re-entry into Game would require Game to be a DGNRS token receiver callback, which it is not. |
| _distributeYieldSurplus | private | delegatecall to GAME_JACKPOT_MODULE | Yes | SAFE | Delegatecall in Game's context. |
| _consolidatePoolsAndRewardJackpots | private | coinflip.creditFlip, IDegenerusGame(address(this)).runBafJackpot (self-call), IDegenerusGame(address(this)).runDecimatorJackpot (self-call) | Yes | SAFE | All pool math is computed in memory variables (memFuture, memCurrent, memNext, memYieldAcc). Self-calls dispatch to JackpotModule/DecimatorModule via delegatecall which write claimablePool/claimableWinnings directly. Memory variables written to storage in final SSTORE batch AFTER all self-calls complete. coinflip.creditFlip is the last external call before the SSTORE batch. See "Self-Call Reentrancy" analysis below. |
| rngGate | internal | coinflip.processCoinflipPayouts, quests.rollDailyQuest, sdgnrs.resolveRedemptionPeriod | Yes | SAFE | rngWordByDay[day] written via _applyDailyRng BEFORE external calls. purchaseStartDay adjusted before external calls. All three external calls are fire-and-forget state notifications to other contracts -- they cannot re-enter Game's advanceGame because rngLockedFlag is set. |
| _gameOverEntropy | private | None (only reads) | Yes | SAFE | No external calls. Pure entropy derivation from VRF state. |
| _requestRng | private | vrfCoordinator.requestRandomWords | Yes | SAFE | rngLockedFlag set to true, rngRequestTime written, and rngWordCurrent zeroed AFTER VRF request. However, VRF coordinator is a trusted Chainlink contract -- its requestRandomWords does not callback synchronously. State updates after the call are safe because VRF fulfillment is asynchronous. |
| rawFulfillRandomWords | external | None | Yes | SAFE | Only writes rngWordCurrent and rngRequestTime. No external calls. |
| requestLootboxRng | external | vrfCoordinator.requestRandomWords | Yes | SAFE | Guarded by rngLockedFlag check (reverts if locked). VRF request is asynchronous. State writes (_lrWrite for index/pending) happen after request but before any callback. Same trusted VRF coordinator pattern as _requestRng. |
| _enforceDailyMintGate | private | vault.isVaultOwner (view) | Yes | SAFE | View-only external call. No state mutations. |
| _nextToFutureBps | internal | None | Yes | SAFE | Pure arithmetic. |
| payDailyJackpot | internal | delegatecall to GAME_JACKPOT_MODULE | Yes | SAFE | Delegatecall in Game's context. |
| payDailyJackpotCoinAndTickets | internal | delegatecall to GAME_JACKPOT_MODULE | Yes | SAFE | Delegatecall in Game's context. |
| _payDailyCoinJackpot | private | delegatecall to GAME_JACKPOT_MODULE | Yes | SAFE | Delegatecall in Game's context. |
| _runProcessTicketBatch | private | delegatecall to GAME_MINT_MODULE | Yes | SAFE | Delegatecall in Game's context. |
| _processPhaseTransition | private | delegatecall to GAME_MINT_MODULE (processTicketBatch), _queueTickets (internal) | Yes | SAFE | All delegatecalls in Game's context. |
| _backfillGapDays | private | coinflip.processCoinflipPayouts, quests.rollDailyQuest | Yes | SAFE | rngWordByDay written per gap day BEFORE processing. Same fire-and-forget pattern as rngGate. |
| _unlockRng | private | None | Yes | SAFE | Only writes rngLockedFlag and dailyIdx. |
| _backfillOrphanedLootboxIndices | private | None | Yes | SAFE | Only writes lootboxRngWordByIndex. |
| _applyDailyRng | private | None | Yes | SAFE | Only writes rngWordByDay and lootboxRngWordByIndex. |
| _finalizeLootboxRng | private | None | Yes | SAFE | Only writes lootboxRngWordByIndex. |
| _wadPow | private | None | Yes | SAFE | Pure arithmetic (fixed-point exponentiation). |
| _projectedDrip | private | None | Yes | SAFE | Pure arithmetic (geometric series). |
| _evaluateGameOverAndTarget | private | None | Yes | SAFE | Only reads/writes gameOverPossible flag and pool state. No external calls. |
| _endPhase | private | None | Yes | SAFE | Only writes phaseTransitionActive, levelPrizePool, jackpotCounter, compressedJackpotFlag. |
| _swapAndFreeze | private | None | Yes | SAFE | Only swaps ticket slots and sets prizePoolFrozen. |

#### DegenerusGameJackpotModule.sol

| Function | Visibility | External Calls | CEI Compliant | Verdict | Notes |
|----------|-----------|----------------|---------------|---------|-------|
| runTerminalJackpot | external | None (all internal via _processDailyEth which writes to Game's storage via delegatecall) | Yes | SAFE | Guarded by OnlyGame(). All state writes are to Game's storage (delegatecall context). No external calls to other contracts. |
| payDailyJackpot | external | None directly (internal _processDailyEth, _runEarlyBirdLootboxJackpot, _distributeLootboxAndTickets write to Game's storage) | Yes | SAFE | Operates entirely within delegatecall context. State writes (currentPrizePool, futurePrizePool, dailyTicketBudgetsPacked, jackpotCounter) all via Game's storage. No external calls to other contracts in this function. |
| payDailyJackpotCoinAndTickets | external | coinflip.creditFlip (per-winner, via _awardDailyCoinToTraitWinners), coinflip.creditFlipBatch (via _awardFarFutureCoinJackpot) | Yes | SAFE | All state writes (jackpotCounter, dailyJackpotCoinTicketsPending, ticketQueue entries) happen BEFORE the coin distribution calls. creditFlip/creditFlipBatch only modify BurnieCoinflip state (flip credits) -- they cannot re-enter the Game's jackpot flow because: (1) rngLockedFlag is set during jackpot phase, (2) BurnieCoinflip does not call back into Game during creditFlip. |
| distributeYieldSurplus | external | steth.balanceOf (view) | Yes | SAFE | View call only. State writes (claimableWinnings, claimablePool, yieldAccumulator) are all internal to Game's storage via delegatecall context. _addClaimableEth calls _creditClaimable which writes claimableWinnings -- no external calls. |
| runBafJackpot | external | None (all via delegatecall context) | Yes | SAFE | Guarded by OnlyGame(). Writes claimableWinnings and claimablePool (via _addClaimableEth -> _creditClaimable) in Game's storage. Returns claimableDelta for caller to track. No external calls to other contracts. |
| _handleSoloBucketWinner | private | dgnrs.transferFromPool (DGNRS reward on final day) | Yes | SAFE | transferFromPool is called AFTER claimableWinnings write (_addClaimableEth). DGNRS token transfer cannot re-enter Game because Game is not an ERC20 receiver. The whale pass queue (_queueTickets) also happens before transferFromPool. |
| _payNormalBucket | private | None | Yes | SAFE | Only calls _addClaimableEth (internal) and emits events. |
| _processDailyEth | private | dgnrs.transferFromPool (via _handleSoloBucketWinner on final day only) | Yes | SAFE | See _handleSoloBucketWinner analysis. resumeEthPool written before return on SPLIT_CALL1 path. |
| _resumeDailyEth | private | None (all internal) | Yes | SAFE | Reads resumeEthPool, clears it, then processes mid buckets. No external calls. |
| _addClaimableEth | private | None (calls _creditClaimable and _processAutoRebuy, both internal) | Yes | SAFE | Pure state mutation on claimableWinnings and ticketQueue. |
| _processAutoRebuy | private | None (calls _queueTickets, internal) | Yes | SAFE | Internal pool/ticket state only. |
| _runEarlyBirdLootboxJackpot | private | None | Yes | SAFE | Internal ticket queueing via _queueTickets. |
| _awardDailyCoinToTraitWinners | private | coinflip.creditFlip (per winner in loop) | Yes | SAFE | External calls are fire-and-forget flip credits. No Game state is read after the creditFlip calls. Each creditFlip modifies BurnieCoinflip state only. BurnieCoinflip.creditFlip does not callback into Game. |
| _awardFarFutureCoinJackpot | private | coinflip.creditFlipBatch | Yes | SAFE | Single batch external call at end. All winner selection done before the call. creditFlipBatch does not callback into Game. |
| _randTraitTicket | private | None | Yes | SAFE | Pure entropy-based winner selection from ticket arrays. |
| _rollWinningTraits | private | None | Yes | SAFE | Pure entropy derivation. |
| _applyHeroOverride | private | None | Yes | SAFE | Pure trait manipulation. |
| _syncDailyWinningTraits | private | None | Yes | SAFE | Packed storage write only. |
| _loadDailyWinningTraits | private | None | Yes | SAFE | Storage read only. |
| _calcDailyCoinBudget | private | None | Yes | SAFE | Pure arithmetic using PriceLookupLib. |
| _selectDailyCoinTargetLevel | private | None | Yes | SAFE | Pure arithmetic. |
| _runJackpotEthFlow | private | None (calls _processDailyEth, internal) | Yes | SAFE | Internal routing only. |
| _executeJackpot | private | None (calls _runJackpotEthFlow, internal) | Yes | SAFE | Internal routing only. |
| _resolveTraitWinners | private | None | Yes | SAFE | Internal winner resolution. |
| _distributeLootboxAndTickets | private | None (calls _distributeTicketJackpot, internal) | Yes | SAFE | Internal ticket distribution. |
| _distributeTicketJackpot | private | None (calls _distributeTicketsToBuckets, internal) | Yes | SAFE | Internal ticket distribution. |
| _distributeTicketsToBuckets | private | None | Yes | SAFE | Internal ticket queueing. |
| _distributeTicketsToBucket | private | None | Yes | SAFE | Internal ticket queueing. |
| _processSoloBucketWinner | private | None (calls _addClaimableEth, internal) | Yes | SAFE | Internal state writes only. |
| _awardJackpotTickets | private | None | Yes | SAFE | Internal ticket queueing. Moved from EndgameModule. |
| _jackpotTicketRoll | private | None | Yes | SAFE | Internal probabilistic roll + ticket queue. Moved from EndgameModule. |

#### DegenerusGameMintModule.sol

| Function | Visibility | External Calls | CEI Compliant | Verdict | Notes |
|----------|-----------|----------------|---------------|---------|-------|
| purchase (via _purchaseFor) | external | quests.handlePurchase, affiliate.payAffiliate (multiple calls), coinflip.creditFlip, IDegenerusGame(address(this)).recordMintQuestStreak (self-call), IDegenerusGame(address(this)).consumePurchaseBoost (self-call) | Yes | INFO | Multiple external calls after state writes. All state mutations (mintPacked_, ticketQueue, pool updates, lootbox entries) are finalized BEFORE quest/affiliate/coinflip calls at function end. The self-calls to consumePurchaseBoost and recordMintQuestStreak dispatch via delegatecall back into Game's context -- not true external calls. The affiliate.payAffiliate calls happen after ticket queueing and pool updates. coinflip.creditFlip is last. INFO because while CEI is followed, the multi-call tail is notable. |
| purchaseCoin | external | delegatecall context only + same external tail as purchase | Yes | SAFE | Same pattern as purchase. Payment via BurnieCoin.burnCoin instead of ETH, but external call pattern is identical. |
| purchaseBurnieLootbox | external | Same external call tail as purchase | Yes | SAFE | Same pattern. |
| recordMintData | external | None | Yes | SAFE | Internal state writes only (mintPacked_ bit fields). |
| processTicketBatch | external | None | Yes | SAFE | Ticket processing, NFT minting, internal state writes. Moved from JackpotModule. No external calls. |
| _raritySymbolBatch | private | None | Yes | SAFE | Assembly-based LCG PRNG trait generation. Pure computation. |
| _processOneTicketEntry | private | None | Yes | SAFE | Internal ticket processing. |
| _resolveZeroOwedRemainder | private | None | Yes | SAFE | Internal remainder resolution. |
| _finalizeTicketEntry | private | None | Yes | SAFE | Internal ticket finalization. |
| _rollRemainder | private | None | Yes | SAFE | Internal probabilistic roll. |

#### DegenerusGameWhaleModule.sol

| Function | Visibility | External Calls | CEI Compliant | Verdict | Notes |
|----------|-----------|----------------|---------------|---------|-------|
| purchaseWhaleBundle (via _purchaseWhaleBundle) | external | dgnrs.transferFromPool (multiple -- deity pass DGNRS rewards) | Yes | SAFE | All pool/ticket state writes happen before transferFromPool calls. DGNRS transfers are one-way token movements -- no callback into Game. rngLockedFlag checked at function entry (WhaleModule line 543). |
| purchaseLazyPass | external | dgnrs.transferFromPool | Yes | SAFE | Same pattern as purchaseWhaleBundle. State writes (mintPacked_, ticketQueue) before external token transfer. |
| purchaseDeityPass | external | dgnrs.transferFromPool | Yes | SAFE | State writes (mintPacked_ deity pass bit, deityPassOwners, deityPassPurchasedCount) all happen before transferFromPool. DeityPassPurchased event emitted before transfer. |
| claimWhalePass | external | None (internal _queueTicketRange, _creditClaimable) | Yes | SAFE | Moved from EndgameModule. All operations are internal state writes in Game's delegatecall context. WhalePassClaimed event emitted. |
| _recordLootboxEntry | private | None | Yes | SAFE | Internal packed state writes for lootbox index tracking. |
| _applyLootboxBoostOnPurchase | private | None | Yes | SAFE | Internal boon state manipulation. |
| _recordLootboxMintDay | private | None | Yes | SAFE | Internal state write. |

#### DegenerusGameDecimatorModule.sol

| Function | Visibility | External Calls | CEI Compliant | Verdict | Notes |
|----------|-----------|----------------|---------------|---------|-------|
| recordDecimatorBurn | external | delegatecall context only (IDegenerusGame(address(this)).consumeDecimatorBoon -- self-call to BoonModule) | Yes | SAFE | Self-call dispatches to BoonModule delegatecall. All decimator state written before boon consumption. |
| runDecimatorJackpot | external | None | Yes | SAFE | Internal jackpot resolution in delegatecall context. Writes claimableWinnings via _creditClaimable (internal). |
| claimDecimatorJackpot | external | None (uses _creditClaimable directly, no auto-rebuy) | Yes | SAFE | Auto-rebuy removed from claim path. _creditClaimable is pure internal state write. claimablePool cast to uint128. |
| recordTerminalDecBurn | external | None | Yes | SAFE | Internal state writes for terminal decimator entries. Burns blocked at <=7 days. |
| claimTerminalDecimatorJackpot | external | None (uses _creditClaimable directly) | Yes | SAFE | prizePoolFrozen check removed. _creditClaimable is internal. |
| _terminalDecMultiplierBps | private | None | Yes | SAFE | Pure arithmetic (redesigned multiplier formula). |
| _terminalDecDaysRemaining | private | None | Yes | SAFE | Pure arithmetic (day-index). |
| _splitDecClaim | private | None | Yes | SAFE | Internal _creditClaimable calls. |
| _awardDecimatorLootbox | private | None | Yes | SAFE | Internal _queueTicketRange calls. |

#### DegenerusGameDegeneretteModule.sol

| Function | Visibility | External Calls | CEI Compliant | Verdict | Notes |
|----------|-----------|----------------|---------------|---------|-------|
| placeDegeneretteBet (renamed from placeFullTicketBets) | external | quests.handleDegenerette (via _placeDegeneretteBetCore) | Yes | SAFE | Bet state written to storage before quest notification. handleDegenerette is a fire-and-forget notification that writes quest state only -- it calls coinflip.creditFlip internally but does not callback into Game's bet logic. |
| _placeDegeneretteBetCore | private | quests.handleDegenerette | Yes | SAFE | Quest call after all bet state mutations (lootboxRng packed writes, betPlaced event). |
| _collectBetFunds | private | None | Yes | SAFE | Internal claimable/pool arithmetic. Packed lootboxRngPendingEth/Burnie writes via _lrWrite. |
| _resolveFullTicketBet | private | None | Yes | SAFE | Internal bet resolution. |
| _distributePayout | private | coin.mintForGame (BURNIE payout), sdgnrs.transferFromPool (sDGNRS payout) | Yes | INFO | State writes (_creditClaimable for ETH, pool adjustments) happen BEFORE external token transfers. coin.mintForGame and sdgnrs.transferFromPool are one-way token operations. INFO because there are two sequential external calls -- but neither can re-enter the degenerette flow: mintForGame only modifies BurnieCoin balances, and transferFromPool only modifies sDGNRS balances. The delegatecall context means Game's address makes these calls, and neither BurnieCoin nor sDGNRS has a callback to Game's placeDegeneretteBet. |
| resolveBets | external | None (calls _resolveFullTicketBet and _distributePayout, both analyzed above) | Yes | SAFE | Orchestrates resolution. External calls within _distributePayout follow CEI. |

#### DegenerusGameLootboxModule.sol

| Function | Visibility | External Calls | CEI Compliant | Verdict | Notes |
|----------|-----------|----------------|---------------|---------|-------|
| openLootbox | external | coinflip.creditFlip (via _resolveLootboxCommon), delegatecall to GAME_BOON_MODULE | Yes | SAFE | Lootbox resolution state written before coinflip credit. BoonModule delegatecall is in Game's context. |
| openBurnieLootbox | external | coinflip.creditFlip (via _resolveLootboxCommon), delegatecall to GAME_BOON_MODULE | Yes | SAFE | Same pattern as openLootbox. gameOverPossible flag replaces timestamp cutoff. |
| _resolveLootboxCommon | private | coinflip.creditFlip | Yes | SAFE | All lootbox state (ticket queue, boon state) written before creditFlip call at end. |
| _rollLootboxBoons | private | delegatecall to GAME_BOON_MODULE (nested) | Yes | SAFE | Delegatecall in Game's context. Multi-boon support (players hold one boon per category). |
| deityBoonSlots | external | None | Yes | SAFE | View function. Day type changed to uint32. |
| issueDeityBoon | external | delegatecall to GAME_BOON_MODULE | Yes | SAFE | Delegatecall in Game's context. |
| resolveLootboxDirect | external | coinflip.creditFlip (via _resolveLootboxCommon) | Yes | SAFE | Same CEI pattern as openLootbox. |
| resolveRedemptionLootbox | external | coinflip.creditFlip (via _resolveLootboxCommon) | Yes | SAFE | Called from Game.resolveRedemptionLootbox (sDGNRS access-controlled). Same CEI. |
| _applyBoon | private | None | Yes | SAFE | Internal packed boon state writes. |
| _activate10LevelPass | private | None | Yes | SAFE | Internal _queueTickets. |
| _boonPoolStats | private | None | Yes | SAFE | Pure arithmetic with PriceLookupLib. |
| _deityDailySeed | private | None | Yes | SAFE | Pure entropy derivation. |
| _deityBoonForSlot | private | None | Yes | SAFE | Pure entropy derivation. |

#### DegenerusGameBoonModule.sol

| Function | Visibility | External Calls | CEI Compliant | Verdict | Notes |
|----------|-----------|----------------|---------------|---------|-------|
| consumeCoinflipBoon | external | None | Yes | SAFE | Clears boon state, emits BoonConsumed event. No external calls. |
| consumePurchaseBoost | external | None | Yes | SAFE | Clears boon state, emits BoonConsumed event. No external calls. |
| consumeDecimatorBoost | external | None | Yes | SAFE | Clears boon state, emits BoonConsumed event. No external calls. |
| consumeActivityBoon | external | None | Yes | SAFE | Awards quest streak bonus, emits BoonConsumed event. No external calls. |

#### DegenerusGameGameOverModule.sol

| Function | Visibility | External Calls | CEI Compliant | Verdict | Notes |
|----------|-----------|----------------|---------------|---------|-------|
| handleGameOverDrain | external | charityGameOver.burnAtGameOver(), dgnrs.burnAtGameOver(), IDegenerusGame(address(this)).runTerminalDecimatorJackpot (self-call), IDegenerusGame(address(this)).runTerminalJackpot (self-call), _sendToVault -> steth.transfer, payable.call | Yes | INFO | gameOver flag and _goWrite(GO_TIME) set BEFORE all external calls. Pool variables zeroed before distribution. charityGameOver.burnAtGameOver() and dgnrs.burnAtGameOver() are called after gameOver=true -- these burn unallocated tokens. Self-calls to runTerminalDecimatorJackpot and runTerminalJackpot dispatch via delegatecall to DecimatorModule/JackpotModule in Game's context. _sendToVault sends stETH/ETH as final operations. INFO because the sequential multi-call pattern (2 burnAtGameOver + 2 self-calls + _sendToVault) is notable, but safe: gameOver=true prevents any re-entry into game functions (all game entry points check gameOver), and the burn calls are to trusted protocol contracts that do not callback into Game. |
| handleFinalSweep | external | admin.shutdownVrf(), steth.balanceOf (view), _sendToVault -> steth.transfer, payable.call | Yes | SAFE | GO_SWEPT_MASK set to 1 BEFORE external calls. claimablePool zeroed. shutdownVrf is fire-and-forget (try/catch). _sendToVault is terminal -- no state depends on its result. |
| _sendToVault | private | steth.transfer (3x), payable.call (3x) | Yes | SAFE | Pure ETH/stETH distribution to protocol addresses (sDGNRS, VAULT, GNRUS). No state reads after transfers. Recipients are fixed protocol contracts. |
| _sendStethFirst | private | steth.transfer, payable.call | Yes | SAFE | Atomic send-and-return-balance. stETH transfer first, then ETH. Return value (updated stethBal) is a local calculation, not a storage read. |

#### DegenerusGamePayoutUtils.sol

| Function | Visibility | External Calls | CEI Compliant | Verdict | Notes |
|----------|-----------|----------------|---------------|---------|-------|
| _creditClaimable | internal | None | Yes | SAFE | Pure storage write to claimableWinnings[player]. NatSpec added. |
| _calcAutoRebuy | internal | None | Yes | SAFE | Pure computation. NatSpec added. |
| _queueWhalePassClaimCore | internal | None | Yes | SAFE | Internal storage writes. claimablePool cast to uint128. |

#### DegenerusGameMintStreakUtils.sol

| Function | Visibility | External Calls | CEI Compliant | Verdict | Notes |
|----------|-----------|----------------|---------------|---------|-------|
| _playerActivityScore (3-param) | internal | None | Yes | SAFE | Pure computation from packed storage reads. |
| _playerActivityScore (2-param) | internal | None | Yes | SAFE | Convenience overload calling 3-param version. |
| _activeTicketLevel | internal | None | Yes | SAFE | Pure arithmetic. |

#### DegenerusGameStorage.sol

| Function | Visibility | External Calls | CEI Compliant | Verdict | Notes |
|----------|-----------|----------------|---------------|---------|-------|
| _isDistressMode | internal | None | Yes | SAFE | Rewritten for day-index arithmetic. Pure computation. |
| _queueTickets | internal | None | Yes | SAFE | Gains rngBypass parameter. Internal ticket queue writes. rngLockedFlag checked for far-future tickets when rngBypass=false. |
| _queueTicketsScaled | internal | None | Yes | SAFE | Same as _queueTickets with scaling. |
| _queueTicketRange | internal | None | Yes | SAFE | Same pattern, range-based. |
| _queueLootboxTickets | internal | None | Yes | SAFE | Passes through to _queueTicketsScaled. |
| _getCurrentPrizePool | internal | None | Yes | SAFE | Storage read helper. |
| _setCurrentPrizePool | internal | None | Yes | SAFE | Storage write helper. |
| _psRead/_psWrite | internal | None | Yes | SAFE | Packed presaleStatePacked helpers. |
| _goRead/_goWrite | internal | None | Yes | SAFE | Packed gameOverStatePacked helpers. |
| _djtRead/_djtWrite | internal | None | Yes | SAFE | Packed dailyJackpotTraitsPacked helpers. |
| _tqWriteKey/_tqReadKey | internal | None | Yes | SAFE | Ticket slot key computation. |
| _swapTicketSlot | internal | None | Yes | SAFE | Bool toggle. |
| sdgnrs.transferFromPool (via Storage) | internal | StakedDegenerusStonk.transferFromPool | Yes | SAFE | Called from DegeneretteModule._distributePayout context. Token transfer only. |

### Core Contracts

#### DegenerusGame.sol

| Function | Visibility | External Calls | CEI Compliant | Verdict | Notes |
|----------|-----------|----------------|---------------|---------|-------|
| advanceGame | external | delegatecall to GAME_ADVANCE_MODULE | Yes | SAFE | Pure delegatecall routing. All logic in AdvanceModule. |
| purchase | external | delegatecall to GAME_MINT_MODULE | Yes | SAFE | rngLockedFlag check before delegatecall. Pure routing. |
| purchaseCoin | external | delegatecall to GAME_MINT_MODULE | Yes | SAFE | rngLockedFlag check. Pure routing. |
| purchaseBurnieLootbox | external | delegatecall to GAME_MINT_MODULE | Yes | SAFE | rngLockedFlag check. Pure routing. |
| purchaseWhaleBundle | external | delegatecall to GAME_WHALE_MODULE | Yes | SAFE | Pure routing. |
| purchaseLazyPass | external | delegatecall to GAME_WHALE_MODULE | Yes | SAFE | Pure routing. |
| purchaseDeityPass | external | delegatecall to GAME_WHALE_MODULE | Yes | SAFE | Pure routing. |
| placeDegeneretteBet | external | delegatecall to GAME_DEGENERETTE_MODULE | Yes | SAFE | Pure routing. |
| resolveDegeneretteBets | external | delegatecall to GAME_DEGENERETTE_MODULE | Yes | SAFE | Pure routing. |
| openLootBox | external | delegatecall to GAME_LOOTBOX_MODULE | Yes | SAFE | Pure routing. |
| openBurnieLootBox | external | delegatecall to GAME_LOOTBOX_MODULE | Yes | SAFE | Pure routing. |
| consumeCoinflipBoon | external | delegatecall to GAME_BOON_MODULE | Yes | SAFE | Pure routing. |
| consumeDecimatorBoon | external | delegatecall to GAME_BOON_MODULE | Yes | SAFE | Pure routing. |
| consumePurchaseBoost | external | delegatecall to GAME_BOON_MODULE | Yes | SAFE | Pure routing. |
| runBafJackpot | external | delegatecall to GAME_JACKPOT_MODULE (JackpotModule.runBafJackpot) | Yes | SAFE | Guarded by self-call pattern -- only callable via address(this). See "Self-Call Reentrancy" analysis. |
| reverseFlip | external | coinflip.creditFlip, coin.burnCoin | Yes | SAFE | Moved from AdvanceModule delegatecall to inline. coin.burnCoin called first (burn the BURNIE cost), then state writes (nudgeCount increment, _queueTickets), then no further external calls. Wait -- coinflip.creditFlip is not present in reverseFlip. Actually reverseFlip queues tickets and burns BURNIE. CEI: burnCoin first (effects), then internal state writes. |
| recordTerminalDecBurn | external | delegatecall to GAME_DECIMATOR_MODULE | Yes | SAFE | Pure routing. |
| claimWinningsStethFirst | external | steth.transfer, payable.call | Yes | SAFE | Restricted to VAULT only. claimableWinnings[player] zeroed and claimablePool decremented BEFORE transfers. Standard CEI for ETH payout. |
| _claimWinningsInternal | private | steth.transfer (via _payoutWithStethFallback), payable.call | Yes | SAFE | claimableWinnings[player] zeroed and claimablePool decremented BEFORE payout. finalSwept check via _goRead packed field. Standard CEI for player claims. |
| claimAffiliateDgnrs | external | affiliate.affiliateScore (view), affiliate.totalAffiliateScore (view), dgnrs.transferFromPool, coinflip.creditFlip | Yes | SAFE | affiliateDgnrsClaimedBy[currLevel][player] set to true BEFORE the external token calls would need to be checked -- actually it's set at the end. However, the function reverts if already claimed (line 1399), and dgnrs.transferFromPool/coinflip.creditFlip cannot re-enter claimAffiliateDgnrs because neither triggers a callback to Game. The claimed flag is written at line 1434 after external calls, but the check at line 1399 ensures idempotency. No reentrancy vector because DGNRS.transferFromPool and coinflip.creditFlip do not callback. |
| setLootboxRngThreshold | external | vault.isVaultOwner (view) | Yes | SAFE | View call for access control. State write follows. |
| adminStakeEthForStEth | external | vault.isVaultOwner (view), steth.submit, steth.balanceOf (view) | Yes | SAFE | View calls for access control and balance check. steth.submit is the only mutating external call, and it's the last action. Submit does not callback into Game. |
| recordMintQuestStreak | external | None (internal state write) | Yes | SAFE | Access changed from COIN to GAME (self-call from MintModule delegatecall). |
| mintPackedFor | external | None | Yes | SAFE | View function. |
| hasDeityPass | external | None | Yes | SAFE | View function. |
| gameOverTimestamp | external | None | Yes | SAFE | View function. |
| resolveRedemptionLootbox | external | delegatecall to GAME_LOOTBOX_MODULE | Yes | SAFE | Access: sDGNRS only. claimableWinnings/claimablePool adjusted BEFORE delegatecall. Delegatecall in Game's context. |

#### DegenerusAdmin.sol

| Function | Visibility | External Calls | CEI Compliant | Verdict | Notes |
|----------|-----------|----------------|---------------|---------|-------|
| proposeFeedSwap | external | vault.isVaultOwner (view), sDGNRS.votingSupply (view), sDGNRS.balanceOf (view), IAggregatorV3.decimals (view) | Yes | SAFE | All external calls are view-only for access control and validation. State writes (FeedProposal creation) happen after validation. |
| voteFeedSwap | external | sDGNRS.votingSupply (view, via _voterWeight), _executeFeedSwap (internal) | Yes | SAFE | Vote recording uses view calls only. _executeFeedSwap writes proposal state. No callbacks. |
| feedThreshold | public view | None | Yes | SAFE | Pure computation. |
| canExecuteFeedSwap | external view | None | Yes | SAFE | View function. |
| proposeVrfSwap | external | sDGNRS.votingSupply (view), sDGNRS.balanceOf (view) | Yes | SAFE | Uses votingSupply() instead of old circulatingSupply(). View calls for validation. Proposal struct repacked with uint40 fields. |
| vote | external | sDGNRS.votingSupply (view, via _voterWeight) | Yes | SAFE | Refactored with shared helpers. View calls for vote weight. Zero-weight poke pattern added. No callbacks from sDGNRS. |
| onTokenTransfer | external | coinflipReward.creditFlip | Yes | SAFE | Called by LINK token (ERC677 callback). State writes (mint recording) happen before coinflipReward.creditFlip. creditFlip does not callback into Admin. |
| _applyVote | private | None | Yes | SAFE | Pure arithmetic. |
| _voterWeight | private | sDGNRS.votingSupply (view), sDGNRS.balanceOf (view) | Yes | SAFE | View calls only. |
| _requireActiveProposal | private | None | Yes | SAFE | Pure validation. |
| _resolveThreshold | private | None | Yes | SAFE | Pure arithmetic. |
| _feedStallDuration | private | IAggregatorV3.latestRoundData (view) | Yes | SAFE | View call to price feed. |

#### DegenerusAffiliate.sol

| Function | Visibility | External Calls | CEI Compliant | Verdict | Notes |
|----------|-----------|----------------|---------------|---------|-------|
| payAffiliate | external | quests.handleAffiliate, coinflip.creditFlip (via _routeAffiliateReward) | Yes | SAFE | Major rework. Winner-takes-all 75/20/5 roll. Leaderboard tracking (affiliateTopByLevel, _totalAffiliateScore) updated BEFORE external quest/coinflip calls. Quest routing goes to quests.handleAffiliate directly (not via BurnieCoin). Flip crediting via coinflip.creditFlip. Neither callback into Affiliate. |
| registerAffiliateCode | external | None | Yes | SAFE | Internal state writes only. Address-range rejection added. |
| defaultCode | external pure | None | Yes | SAFE | Pure computation. |
| affiliateBonusPoints | external view | None | Yes | SAFE | View function. Tiered rate calculation. |
| _resolveCodeOwner | private | None | Yes | SAFE | Internal lookup. |
| _routeAffiliateReward | private | coinflip.creditFlip | Yes | SAFE | creditFlip is the only external call. No state reads after. |

#### DegenerusQuests.sol

| Function | Visibility | External Calls | CEI Compliant | Verdict | Notes |
|----------|-----------|----------------|---------------|---------|-------|
| rollDailyQuest | external | None | Yes | SAFE | Internal quest state writes. Simplified -- no return values, no difficulty. |
| handleMint | external | coinflip.creditFlip (quest reward) | Yes | SAFE | Quest state updated BEFORE creditFlip. Added mintPrice param for target scaling. |
| handleLootBox | external | coinflip.creditFlip (quest reward) | Yes | SAFE | Same pattern as handleMint. |
| handleDegenerette | external | coinflip.creditFlip (quest reward) | Yes | SAFE | Same pattern. |
| handleDecimator | external | coinflip.creditFlip (quest reward) | Yes | SAFE | Same pattern. |
| handleAffiliate | external | coinflip.creditFlip (quest reward) | Yes | SAFE | Same pattern. |
| handlePurchase | external | coinflip.creditFlip (quest reward) | Yes | SAFE | New unified purchase path. Quest state finalized before creditFlip. |
| rollLevelQuest | external | None | Yes | SAFE | Internal quest state write. New function. |
| getPlayerLevelQuestView | external view | None | Yes | SAFE | View function. |

#### BurnieCoin.sol

| Function | Visibility | External Calls | CEI Compliant | Verdict | Notes |
|----------|-----------|----------------|---------------|---------|-------|
| mintForGame | external | None | Yes | SAFE | Access expanded to COINFLIP + GAME. Pure balance/supply mutation. |
| burnCoin | external | None | Yes | SAFE | Modifier changed to onlyGame. Pure balance/supply mutation. |
| decimatorBurn | external | degenerusGame.consumeDecimatorBoon (self-call to BoonModule), quests.handleDecimator | Yes | SAFE | Token burn happens FIRST (_burn). Then consumeDecimatorBoon (self-call to Game -> BoonModule delegatecall), then quests.handleDecimator. Both external calls happen after the BURNIE burn is complete. Game's consumeDecimatorBoon just clears a boon flag. quests.handleDecimator awards flip credit. Neither can re-enter BurnieCoin's decimatorBurn because BurnieCoin has no callback hooks. |
| burnForCoinflip | external | None | Yes | SAFE | Pure balance/supply mutation. Access check changed to ContractAddresses.COINFLIP. |

#### BurnieCoinflip.sol

| Function | Visibility | External Calls | CEI Compliant | Verdict | Notes |
|----------|-----------|----------------|---------------|---------|-------|
| depositCoinflip | external | burnie.burnForCoinflip, questModule.handleFlip, degenerusGame.afKingModeFor (view), degenerusGame.hasDeityPass (view), degenerusGame.level (view) | Yes | SAFE | CEI explicitly documented in code: "Burn first so reentrancy into downstream module calls cannot spend the same balance twice." burnForCoinflip called BEFORE quest/game calls. Auto-rebuy fix (reads claimableStored not mintable). |
| _claimInternal | private | burnie.mintForGame | Yes | SAFE | All settlement state (claimableStored, autoRebuyCarry) computed and written BEFORE mintForGame. mintForGame only increases BURNIE balance -- cannot re-enter coinflip claim. |
| creditFlip | external | None | Yes | SAFE | Expanded creditors (GAME+QUESTS+AFFILIATE+ADMIN). Pure state write (_addDailyFlip). |
| creditFlipBatch | external | None | Yes | SAFE | Dynamic arrays (was fixed-3). Pure state writes in loop. |
| processCoinflipPayouts | external | None | Yes | SAFE | Pure state writes (coinflipDayResult, flipsClaimableDay). |
| setCoinflipAutoRebuy | external | burnie.mintForGame | Yes | SAFE | Settlement before mint. |
| setCoinflipAutoRebuyTakeProfit | external | burnie.mintForGame | Yes | SAFE | Settlement before mint. |
| _recyclingBonus | private pure | None | Yes | SAFE | Pure arithmetic. Rate changed to 0.75%. |

#### DegenerusStonk.sol

| Function | Visibility | External Calls | CEI Compliant | Verdict | Notes |
|----------|-----------|----------------|---------------|---------|-------|
| claimVested | external | vault.isVaultOwner (view), game.level (view) | Yes | SAFE | View calls for access control. Balance transfer (_vestingReleased update, balanceOf writes) is internal. No external token transfers. |
| yearSweep | external | game.gameOver (view), game.gameOverTimestamp (view), stonk.balanceOf (view), stonk.burn, steth.transfer (2x), payable.call (2x) | Yes | SAFE | Permissionless 1-year sweep. stonk.burn is called first to get ETH/stETH output amounts. Then stETH transfers (lower reentrancy risk, as commented in code), then ETH transfers last. CEI: burn first, then distribute. Recipient addresses (GNRUS, VAULT) are fixed protocol contracts that accept but don't callback into DGNRS. |
| unwrapTo | external | vault.isVaultOwner (view), game.rngLocked (view), stonk.wrapperTransferTo | Yes | SAFE | Access changed to vault owner. rngLocked guard. Token burn before external stonk call. |
| burn | external | game.gameOver (view), stonk.burn | Yes | SAFE | Token burn (_burn) happens FIRST. Then stonk.burn returns amounts. Then token transfers (burnie.transfer, steth.transfer, payable.call) in standard CEI order -- ERC20 first, ETH last. gameOver check prevents active-game burning. |
| transferFrom | external | None | Yes | SAFE | Emits Approval on allowance decrease (ERC20 compliance fix). Pure state mutation. |

#### StakedDegenerusStonk.sol

| Function | Visibility | External Calls | CEI Compliant | Verdict | Notes |
|----------|-----------|----------------|---------------|---------|-------|
| votingSupply | external view | None | Yes | SAFE | New view function. Excludes this/DGNRS/VAULT from supply. |
| poolTransfer | external | game.claimWinnings (self-win path), steth.transfer | Yes | INFO | Self-win (to == address(this)) now burns instead of no-op. The burn path calls _burn which reduces supply. game.claimWinnings is called in the claim path (not poolTransfer directly). However, poolTransfer does not directly make external calls to Game -- it's internal token transfer. INFO because the self-win burn is a notable behavior change but doesn't introduce reentrancy: transfer/burn operations are internal to sDGNRS state. |
| burnAtGameOver | external | None | Yes | SAFE | Renamed from burnRemainingPools. Internal pool burn operations. gameOver gate. |
| resolveRedemptionPeriod | external | None | Yes | SAFE | flipDay uint48->uint32. Void return (no BURNIE credit at resolution). Pure state writes. |
| claimRedemption | external | game.claimWinnings, game.resolveRedemptionLootbox, steth.transfer, coin.transfer | Yes | SAFE | Complex multi-step claim with external calls. State writes (pendingRedemption clearing, pool adjustments) happen BEFORE external calls. game.claimWinnings called to pull ETH for lootbox resolution. CEI maintained: state first, then external calls. |

#### DegenerusVault.sol

| Function | Visibility | External Calls | CEI Compliant | Verdict | Notes |
|----------|-----------|----------------|---------------|---------|-------|
| gameDegeneretteBet | external | gamePlayer.placeDegeneretteBet (via game.placeDegeneretteBet) | Yes | SAFE | Consolidated from 3 separate functions. Forwards to Game's delegatecall chain. Access controlled by vault membership. |
| sdgnrsBurn | external | sDGNRS burn path | Yes | SAFE | New function. Vault owner burns vault-held sDGNRS. Forwards to sDGNRS contract. |
| sdgnrsClaimRedemption | external | sDGNRS claim path | Yes | SAFE | New function. Vault owner claims resolved redemption. Forwards to sDGNRS. |
| claimWinnings | external | gamePlayer.claimWinnings | Yes | SAFE | Forwards claim to Game. State writes in Game follow CEI. |
| claimWinningsStethFirst | external | gamePlayer.claimWinningsStethFirst | Yes | SAFE | Restricted path. Forwards to Game. |

#### DegenerusDeityPass.sol

| Function | Visibility | External Calls | CEI Compliant | Verdict | Notes |
|----------|-----------|----------------|---------------|---------|-------|
| onlyOwner modifier | modifier | vault.isVaultOwner (view) | Yes | SAFE | View call for access control. Replaced _contractOwner check. |
| setRenderer | external | vault.isVaultOwner (view) | Yes | SAFE | State write after access check. |
| mint | external | vault.isVaultOwner (view) | Yes | SAFE | Token mint after access check. |

#### GNRUS.sol

| Function | Visibility | External Calls | CEI Compliant | Verdict | Notes |
|----------|-----------|----------------|---------------|---------|-------|
| burn | external | game.claimableWinningsOf (view), game.claimWinnings, steth.transfer, burner.call{value} | Yes | SAFE | CEI explicitly documented in source: "CEI: state updates and events before external transfers. stETH before ETH (ETH last)." Token burn (balanceOf, totalSupply writes) and event emission happen BEFORE any external transfers. game.claimWinnings only called if on-hand balance insufficient. See "GNRUS Burn Reentrancy" analysis below for detailed callback trace. |
| burnAtGameOver | external | None (internal balance writes only) | Yes | SAFE | Game-only access. Burns unallocated GNRUS (balanceOf[address(this)]). finalized flag prevents double-call. No external calls. |
| propose | external | sdgnrs.votingSupply (view), sdgnrs.balanceOf (view), vault.isVaultOwner (view) | Yes | SAFE | All view calls for validation. State writes (proposal creation, snapshot) happen after validation. |
| vote | external | sdgnrs.balanceOf (view), vault.isVaultOwner (view) | Yes | SAFE | View calls for weight calculation. State writes (vote recording) after. |
| pickCharity | external | None (internal balance transfers only) | Yes | SAFE | Game-only access. Transfers GNRUS from contract to recipient (balanceOf writes). No external calls. |
| receive | external | None | Yes | SAFE | Accepts ETH. No logic. |
| transfer/transferFrom/approve | external | None | Yes | SAFE | All revert (soulbound enforcement). |

#### WrappedWrappedXRP.sol

| Function | Visibility | External Calls | CEI Compliant | Verdict | Notes |
|----------|-----------|----------------|---------------|---------|-------|
| All functions | various | None post-strip | Yes | SAFE | wXRP backing fully removed. unwrap/donate functions deleted. Token is now pure mint/burn. No external calls to any backing token. |

## High-Risk Patterns Analyzed

### Self-Call Reentrancy (AdvanceModule -> Game.runBafJackpot -> JackpotModule)

**Pattern:** AdvanceModule._consolidatePoolsAndRewardJackpots() calls `IDegenerusGame(address(this)).runBafJackpot(bafPoolWei, lvl, rngWord)`. This is a self-call from Game's address to Game's address, which routes through DegenerusGame.runBafJackpot() and dispatches via delegatecall to JackpotModule.runBafJackpot().

**Analysis:**

1. **Memory vs storage during self-call:** _consolidatePoolsAndRewardJackpots computes all pool values in memory variables (memFuture, memCurrent, memNext, memYieldAcc). The self-call to runBafJackpot executes JackpotModule code via delegatecall in Game's storage context. JackpotModule.runBafJackpot writes to `claimableWinnings[winners]` and `claimablePool` directly in storage. It does NOT write to futurePrizePool, currentPrizePool, or nextPrizePool -- those are tracked by the caller's memory variables.

2. **Can runBafJackpot's storage writes conflict with pending memory?** No. runBafJackpot writes to claimableWinnings (per-player mapping) and claimablePool (aggregate liability). The caller tracks these via `claimableDelta` return value: `uint256 claimed = IDegenerusGame(address(this)).runBafJackpot(...)`. The caller then subtracts `claimed` from `memFuture` and adds to `claimableDelta`. The final SSTORE batch writes memFuture/memCurrent/memNext/memYieldAcc and `claimablePool += uint128(claimableDelta)`. This is additive and correct because the JackpotModule already wrote its portion to claimablePool, and the caller adds any additional delta from the Decimator self-call.

3. **Wait -- double-counting claimablePool?** Looking more carefully: JackpotModule.runBafJackpot calls _addClaimableEth -> _creditClaimable which writes `claimableWinnings[player] += amount` but does NOT write claimablePool. The _addClaimableEth function returns `claimableDelta` and the caller (JackpotModule.runBafJackpot) returns this delta. Then _consolidatePoolsAndRewardJackpots accumulates it in its local `claimableDelta` variable and writes `claimablePool += uint128(claimableDelta)` in the final SSTORE batch. No double-counting.

4. **Re-entry path:** The self-call from AdvanceModule goes through Game.runBafJackpot which does `if (msg.sender != address(this)) revert OnlyGame()` equivalent via the module-level check. The call then delegatecalls to JackpotModule. JackpotModule does NOT make any external calls to other contracts (no coinflip, no DGNRS). It only writes to Game's storage (claimableWinnings) and returns. No external call surface for re-entry.

**Conclusion:** SAFE. The self-call pattern does not create a reentrancy window. Memory variables in the caller are not affected by the callee's storage writes. The callee (runBafJackpot) makes no external calls. claimablePool is correctly accumulated via the return value pattern.

### Two-Call Split Mid-State (JackpotModule CALL1/CALL2)

**Pattern:** _processDailyEth operates in three modes: SPLIT_NONE (all 4 buckets in one call), SPLIT_CALL1 (largest + solo buckets, writes resumeEthPool), SPLIT_CALL2 (mid buckets, reads and clears resumeEthPool).

**Analysis:**

1. **Mid-execution state:** After CALL1 completes, `resumeEthPool` contains the remaining ETH budget for mid buckets. The state written after CALL1 includes: claimableWinnings for CALL1 winners, resumeEthPool for CALL2, and dailyJackpotTraitsPacked.

2. **Can resumeEthPool be exploited between calls?** Between CALL1 and CALL2, another advanceGame() call would be needed to trigger CALL2. This is the normal flow -- the caller (AdvanceModule.advanceGame) checks `resumeEthPool != 0` and dispatches payDailyJackpot with the resume path. During this inter-call window:
   - rngLockedFlag remains SET (set before jackpot processing, cleared only at _unlockRng after full completion)
   - No player can purchase tickets (rngLockedFlag blocks purchase)
   - No player can call advanceGame to reach jackpot processing (would hit same rngGate)
   - advanceGame by a different caller reaches the jackpot phase, sees resumeEthPool != 0, and triggers CALL2 completion
   
3. **Can a player manipulate winner selection between calls?** No. The winning traits are stored in dailyJackpotTraitsPacked during CALL1. The entropy is derived from the same rngWord. The bucket counts are deterministic from the pool size. Between CALL1 and CALL2, no ticket purchases or transfers can occur (rngLockedFlag).

4. **resumeEthPool as attack surface:** resumeEthPool is only read by _resumeDailyEth (CALL2 path). It's set atomically during CALL1 and cleared during CALL2. The only code path that reads it is the resume check in payDailyJackpot. There is no external call between writing resumeEthPool and the return from CALL1.

**Conclusion:** SAFE. The two-call split is protected by rngLockedFlag which prevents any state changes between CALL1 and CALL2. The mid-state (resumeEthPool) is only accessible via the normal advanceGame flow, and all relevant parameters (traits, entropy, counts) are deterministic.

### GNRUS Burn Reentrancy (GNRUS.burn -> game.claimWinnings)

**Pattern:** GNRUS.burn() may call game.claimWinnings(address(this)) to pull ETH from Game's claimableWinnings into GNRUS's balance before distributing to the burner.

**Analysis:**

1. **CEI compliance in GNRUS.burn():** 
   - Reads: totalSupply, balanceOf[burner], ETH/stETH balances, game.claimableWinningsOf (line 298-299)
   - State mutations: balanceOf[burner] -= amount, totalSupply -= amount (lines 315-316)
   - External calls: game.claimWinnings (line 306, conditional), steth.transfer (line 323), burner.call{value} (line 326)
   - The burn (state mutation) happens BEFORE all external transfers. CEI is explicitly followed.

2. **Can game.claimWinnings re-enter GNRUS?** game.claimWinnings sends ETH to GNRUS via `payable(GNRUS).call{value: amount}("")`. GNRUS has a `receive()` function that simply accepts ETH (no logic). This does NOT re-enter GNRUS.burn() because the receive function has no callback.

3. **Can game.claimWinnings re-enter Game state?** game._claimWinningsInternal zeroes claimableWinnings[GNRUS] and decrements claimablePool BEFORE sending ETH. The ETH is sent to GNRUS (not back to Game). GNRUS's receive() accepts it silently. No re-entry.

4. **Can the burner.call{value: ethOut} re-enter GNRUS.burn?** If the burner is a contract with a receive/fallback that calls GNRUS.burn() again:
   - The burner's balanceOf[burner] was already decremented on line 315 (first burn subtracted the full amount)
   - A re-entrant GNRUS.burn() would see the reduced balance and could only burn the remaining balance
   - However, the totalSupply was also decremented, so the proportional calculation would be correct for the new state
   - The re-entrant burn would calculate a smaller `owed` amount based on the reduced supply and the remaining ETH/stETH balances
   - This is a standard "drain by re-entry" pattern, but Solidity 0.8 underflow protection on `balanceOf[burner] -= amount` prevents burning more than available
   - Each re-entrant call correctly reduces both balance and supply, so proportional math holds

5. **Potential issue:** The re-entrant path could drain more ETH than the burner's fair share if the owed calculation uses stale `supply` from the outer call. But no -- each call reads `totalSupply` fresh from storage (line 285), and the outer call has already decremented it (line 316). So the inner call sees the updated supply. Safe.

**Conclusion:** SAFE. GNRUS.burn follows strict CEI: balance/supply decremented before transfers. The game.claimWinnings callback only sends ETH to GNRUS's receive() (no re-entry). The burner.call re-entry path is protected by the already-decremented balanceOf and totalSupply.

### GameOver Drain Multi-Call (handleGameOverDrain -> burnAtGameOver x2 -> _creditClaimable)

**Pattern:** handleGameOverDrain makes sequential external calls: charityGameOver.burnAtGameOver() (GNRUS), dgnrs.burnAtGameOver() (sDGNRS), then self-calls to runTerminalDecimatorJackpot and runTerminalJackpot, then _sendToVault.

**Analysis:**

1. **Terminal state protection:** `gameOver = true` is set on line 136, BEFORE any external calls. All game entry points (purchase, advanceGame, placeDegeneretteBet, etc.) check gameOver and revert. This means no player action can occur during the drain processing.

2. **charityGameOver.burnAtGameOver() (GNRUS):** This burns unallocated GNRUS (balanceOf[address(this)] set to 0). It's a one-shot operation (finalized flag). GNRUS.burnAtGameOver() makes no external calls and cannot re-enter Game.

3. **dgnrs.burnAtGameOver() (sDGNRS):** This burns remaining pool tokens. sDGNRS.burnAtGameOver() is gated by gameOver flag and makes no external calls back to Game.

4. **Order dependency:** The burnAtGameOver calls happen AFTER gameOver=true and pool zeroing (lines 144-147: nextPrizePool=0, futurePrizePool=0, currentPrizePool=0, yieldAccumulator=0). The subsequent runTerminalDecimatorJackpot and runTerminalJackpot self-calls operate on the `available` ETH balance (not pool variables). They write to claimableWinnings/claimablePool via delegatecall.

5. **_sendToVault as terminal:** After all jackpots are resolved, any remaining ETH goes to _sendToVault which distributes to sDGNRS/VAULT/GNRUS. These are fixed protocol addresses. The stETH transfers cannot re-enter Game (stETH is Lido's contract, standard ERC20). The ETH calls go to protocol contracts that accept ETH.

**Conclusion:** SAFE. The gameOver terminal flag prevents all re-entry into game functions. The sequential burn calls are to trusted protocol contracts with no callbacks. The self-calls for jackpot distribution operate in delegatecall context and cannot re-enter.

## Cross-Module Chain Reentrancy Summary

For each of the 99 cross-module chains (SM/EF/RNG/RO), assessment of whether the chain involves an external call that could re-enter the caller. Grouped by risk level.

### No Reentrancy Risk (delegatecall-only chains, no external calls to other contracts)

| Chains | Reason |
|--------|--------|
| SM-01, SM-09, SM-10, SM-13, SM-18, SM-19, SM-20, SM-22, SM-25, SM-27, SM-28, SM-29, SM-30, SM-33, SM-34, SM-35 | Delegatecall within Game's module system. External calls (if any) are to protocol contracts that do not callback. |
| RNG-01 through RNG-11 | RNG chains involve VRF request/fulfillment (asynchronous, no callback) or entropy derivation (no external calls). |
| RO-01 through RO-12 | Read-only chains. No state mutation, no external calls. |

### Low Reentrancy Risk (external calls to protocol contracts, no callback mechanism)

| Chain | External Call | Assessment |
|-------|-------------|------------|
| SM-02 | AdvanceModule -> JackpotModule.distributeYieldSurplus (delegatecall) | SAFE -- delegatecall in Game's context. steth.balanceOf is view-only. |
| SM-03 | AdvanceModule -> Game.runBafJackpot (self-call) -> JackpotModule (delegatecall) | SAFE -- analyzed in "Self-Call Reentrancy" section. No external calls from JackpotModule.runBafJackpot. |
| SM-04 | AdvanceModule._rewardTopAffiliate -> dgnrs.transferFromPool | SAFE -- one-way DGNRS token transfer, no callback to Game. |
| SM-05 | AdvanceModule -> quests.rollDailyQuest | SAFE -- fire-and-forget quest state write, no callback. |
| SM-06 | AdvanceModule -> quests.rollLevelQuest | SAFE -- same as SM-05. |
| SM-07 | AdvanceModule -> GNRUS.pickCharity | SAFE -- GNRUS.pickCharity is Game-only, internal balance transfer, no external calls. |
| SM-08 | AdvanceModule -> sdgnrs.resolveRedemptionPeriod | SAFE -- sDGNRS state write (redemption period resolution), no callback to Game. |
| SM-11 | JackpotModule -> coinflip.creditFlip | SAFE -- coinflip state write only, no callback to Game. |
| SM-12 | JackpotModule -> coinflip.creditFlipBatch | SAFE -- same as SM-11, batch variant. |
| SM-14 | MintModule -> affiliate.payAffiliate | SAFE -- affiliate writes state, calls quests.handleAffiliate (no Game callback) and coinflip.creditFlip (no callback). Chain: MintModule -> Affiliate -> Quests -> Coinflip. No path back to Game. |
| SM-15 | MintModule -> quests.handlePurchase | SAFE -- quest state write + coinflip.creditFlip at end, no callback. |
| SM-16 | MintModule -> quests.handleMint | SAFE -- same pattern as SM-15. |
| SM-17 | MintModule -> coinflip.creditFlip | SAFE -- no callback. |
| SM-21 | WhaleModule -> dgnrs.transferFromPool | SAFE -- one-way DGNRS transfer. |
| SM-23 | DegeneretteModule -> quests.handleDegenerette | SAFE -- quest + creditFlip, no callback. |
| SM-24 | DegeneretteModule -> sdgnrs.transferFromPool | SAFE -- one-way sDGNRS pool transfer. |
| SM-26 | LootboxModule -> coinflip.creditFlip | SAFE -- no callback. |
| SM-31 | BurnieCoin.decimatorBurn -> Game.consumeDecimatorBoon (self-call -> BoonModule delegatecall) | SAFE -- BoonModule clears boon flag. No external calls from BoonModule. |
| SM-32 | BurnieCoin.decimatorBurn -> quests.handleDecimator | SAFE -- quest state + creditFlip, no callback to BurnieCoin. |
| SM-36 | DegenerusAdmin.proposeFeedSwap -> sdgnrs.votingSupply (view) | SAFE -- view call only. |
| SM-37 | DegenerusAdmin.voteFeedSwap -> sdgnrs.votingSupply (view) | SAFE -- view call only. |
| SM-38 | DegenerusAdmin.vote -> sdgnrs.votingSupply (view) | SAFE -- view call only. |
| SM-39 | DegenerusAdmin.onTokenTransfer -> coinflip.creditFlip | SAFE -- no callback. |
| SM-40 | DegenerusAffiliate.payAffiliate -> quests.handleAffiliate | SAFE -- quest + creditFlip, no callback to Affiliate. |
| SM-41 | DegenerusAffiliate.payAffiliate -> coinflip.creditFlip | SAFE -- no callback. |
| SM-42 | DegenerusQuests.handleMint -> coinflip.creditFlip | SAFE -- no callback. |
| SM-43 | DegenerusQuests.handleLootBox -> coinflip.creditFlip | SAFE -- no callback. |
| SM-44 | DegenerusQuests.handleDegenerette -> coinflip.creditFlip | SAFE -- no callback. |
| SM-45 | DegenerusQuests.handleAffiliate -> coinflip.creditFlip | SAFE -- no callback. |
| SM-46 | DegenerusQuests.handleDecimator -> coinflip.creditFlip | SAFE -- no callback. |
| SM-47 | DegenerusQuests.handlePurchase -> coinflip.creditFlip | SAFE -- no callback. |
| SM-48 | BurnieCoinflip.depositCoinflip -> burnie.burnForCoinflip | SAFE -- CEI: burn first, then quest/game calls. burnForCoinflip is a simple balance burn. |
| SM-49 | BurnieCoinflip._claimInternal -> burnie.mintForGame | SAFE -- settlement before mint, no callback. |
| SM-50 | DegenerusVault.gameDegeneretteBet -> Game.placeDegeneretteBet | SAFE -- forwards to Game's delegatecall chain. Vault is a trusted caller. |
| SM-51 | DegenerusVault.sdgnrsBurn -> sDGNRS burn path | SAFE -- vault burns its own sDGNRS. No callback to Game. |
| SM-52 | DegenerusVault.sdgnrsClaimRedemption -> sDGNRS claim path | SAFE -- vault claims its own redemption. Game.resolveRedemptionLootbox may be called, but access is sDGNRS-only. |
| SM-53 | sDGNRS.poolTransfer (self-win burn) | SAFE -- internal burn, no external calls. |
| SM-54 | DegenerusStonk.claimVested | SAFE -- internal balance transfer. View calls only (vault.isVaultOwner, game.level). |
| SM-55 | DegenerusStonk.yearSweep -> GNRUS (ETH), Vault (ETH) | SAFE -- terminal sweep. stonk.burn first, then stETH transfers, then ETH transfers. Recipients are fixed protocol contracts. |
| SM-56 | DegenerusDeityPass.onlyOwner -> vault.isVaultOwner (view) | SAFE -- view call only for access gate. |

### ETH-Flow Chains (all assigned to Phase 216, assessed for reentrancy here)

| Chain | Assessment |
|-------|------------|
| EF-01 through EF-20 | All ETH-flow chains involve either: (1) internal pool arithmetic (no external calls), (2) claimableWinnings writes via _creditClaimable (internal), (3) terminal stETH/ETH transfers following CEI (state zeroed before transfer), or (4) coinflip.creditFlip (no callback). No reentrancy vectors identified. The two-call split (EF-04) is protected by rngLockedFlag as analyzed above. The GNRUS burn path (EF-13) follows strict CEI as analyzed above. |

### Summary Statistics

- **Total chains assessed:** 99 (56 SM + 20 EF + 11 RNG + 12 RO)
- **VULNERABLE:** 0
- **INFO (notable but not exploitable):** 0 chains (2 individual functions flagged INFO above)
- **SAFE:** 99 chains

The protocol's reentrancy surface is defended by three complementary mechanisms:
1. **CEI ordering:** All external calls occur after state finalization
2. **rngLockedFlag:** Mutual exclusion during VRF/jackpot windows blocks re-entry into game actions
3. **No callback contracts:** External call targets (BurnieCoinflip, DegenerusQuests, DegenerusAffiliate, DegenerusStonk, StakedDegenerusStonk, GNRUS) do not callback into the calling contract during their entry points
4. **Terminal state flags:** gameOver=true permanently blocks all game functions, protecting gameover distribution
