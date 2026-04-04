# Phase 182: v15.0 Adversarial Regression Check

**Baseline:** v15.0 Phase 165 -- 76 functions, 76 SAFE, 0 VULNERABLE
**Change surface:** v16.0-v17.1 (Phase 179 inventory)
**Method:** Cross-reference each v15.0 verdict against current code via 179-01 diff inventory and 179-02 function verdicts

## Summary

| Risk Category | Functions | Regressions |
|---------------|-----------|-------------|
| HIGH RISK (logic changed) | 17 | 0 |
| LOW RISK (mechanical/comment) | 26 | 0 |
| NO RISK (untouched) | 33 | 0 |
| **Total** | **76** | **0** |

---

## HIGH RISK Functions (detailed re-validation)

These 17 functions appear in both the v15.0 master table AND the 179-02 change surface with logic-level changes (not comment-only).

---

### HR-01. AdvanceModule._evaluateGameOverPossible (v15.0 #3, 179-02 #15)

**v15.0 verdict:** SAFE -- sets/clears gameOverPossible based on projected drip vs deficit. No external calls, private. Three call sites verified (FLAG-01, FLAG-02, FLAG-03).

**v16.0-v17.1 change:** 179-02 #15 says "no code change -- logic unchanged, only callers changed." Attribution: v16.0-repack (contextual). The function body is identical. The two call sites pass `(lvl, purchaseLevel)` correctly. The drip projection math (_projectedDrip, _wadPow) is identical to v15.0.

**Re-validation:** Original SAFE reasoning (underflow protection, call-site correctness, edge cases) is completely unaffected. The caller change (poolConsolidationDone guard removal, _runRewardJackpots moved) does not alter the arguments or context of either call site.

**Regression verdict: NO REGRESSION**

---

### HR-02. AdvanceModule._processPhaseTransition (v15.0 #5, 179-02 #13)

**v15.0 verdict:** SAFE -- queues 16 perpetual vault tickets to SDGNRS and VAULT at purchaseLevel+99, then auto-stakes excess ETH. Returns true unconditionally. Private, no reentrancy.

**v16.0-v17.1 change:** rngBypass parameter added. Both _queueTickets calls now pass `true` as rngBypass. 179-02 #13 confirms: "These queue perpetual vault tickets at `purchaseLevel + 99` (far-future level). Since this runs during the phase transition when rngLockedFlag is set and phaseTransitionActive is true, the bypass is required to prevent false RngLocked reverts."

**Re-validation:** The rngBypass=true is semantically equivalent to the old `!phaseTransitionActive` guard (which was also true during phase transition). The vault ticket queuing logic, purchaseLevel+99 target, _autoStakeExcessEth try/catch -- all unchanged. Access control (private, advanceGame-only) unchanged.

**Regression verdict: NO REGRESSION**

---

### HR-03. MintModule._purchaseFor (v15.0 #20, 179-02 #31 via recordMintData)

**v15.0 verdict:** SAFE across 8 sub-items (purchaseLevel ternary, PriceLookupLib.priceForLevel, lootbox base level, single handlePurchase call, compute-once activity score, batched creditFlip, claimableWinnings read-once, ticket queuing moved).

**v16.0-v17.1 change:** 179-02 #31 adds affiliate bonus cache write to recordMintData (called from _callTicketPurchase which is called from _purchaseFor). Lines 277-281 in MintModule write cached affiliate bonus points to mintPacked_ bits [185-214]. This piggybacks on the existing SSTORE.

**Re-validation:** The _purchaseFor function itself is not changed. The recordMintData change adds a cache write that does not affect the _purchaseFor flow (no new branches, no new reverts, no change to return values). The 8 sub-items from v15.0 audit remain valid:
- purchaseLevel ternary: unchanged
- PriceLookupLib.priceForLevel: unchanged
- lootbox base level: unchanged
- handlePurchase call: unchanged (6 args match)
- compute-once activity score: unchanged (score computed after state mutations, before consumers)
- batched creditFlip: unchanged
- claimableWinnings read-once: unchanged
- ticket queuing: unchanged

The affiliate cache write is purely additive (extra bits packed into mintPacked_) and occurs inside recordMintData before _purchaseFor's score computation. The activity score now reads from the cache (in MintStreakUtils) instead of making a cold SLOAD -- but this is transparent to _purchaseFor.

**Regression verdict: NO REGRESSION**

---

### HR-04. MintStreakUtils._playerActivityScore (v15.0 #23/#24, 179-02 #43)

**v15.0 verdict:** SAFE -- computes activity score from mintPacked_ fields (level streak, units, quest streak) plus affiliate bonus via external call to affiliate.affiliateBonusPointsBest.

**v16.0-v17.1 change:** 179-02 #43 adds affiliate bonus cache read. Lines 139-148: reads from mintPacked_ cache when `cachedLevel == currLevel`, falling back to `affiliate.affiliateBonusPointsBest(currLevel, player)` when stale. MASK_6 (6-bit) and MASK_24 (24-bit) reads match the write in MintModule.recordMintData. Points multiplied by 100 for bps conversion -- same as before.

**Re-validation:** The function now has a fast path (cache hit) and a slow path (cache miss = original external call). Both paths produce the same result: affiliate bonus points * 100. The cache correctness was verified in 179-02 #43 (bit masks match, fallback ensures fresh-level correctness). The non-affiliate components of the score (level streak, units, quest streak) are completely untouched. Access control, overflow safety, and return value semantics are identical.

**Regression verdict: NO REGRESSION**

---

### HR-05. LootboxModule.openBurnieLootBox (v15.0 #25, rngBypass threading)

**v15.0 verdict:** SAFE -- opens lootbox, awards boon/tickets/BURNIE based on entropy. Correct level targeting, gameOverPossible redirect for far-future tickets.

**v16.0-v17.1 change:** 179-02 #47 (_handleLootboxTickets): _queueTicketsScaled at line 974 and _queueTickets at line 1097 now pass `false` as rngBypass. Both are player-initiated lootbox paths.

**Re-validation:** rngBypass=false is correct for player-initiated paths (they should respect RNG lock). The openBurnieLootBox function itself has no logic change -- only its downstream ticket queuing calls received the new boolean parameter. The original SAFE reasoning (entropy consumption, boon award logic, level targeting, far-future redirect) is entirely unaffected by the parameter addition.

**Regression verdict: NO REGRESSION**

---

### HR-06. LootboxModule._maybeAwardBoon (v15.0 #26, rngBypass threading)

**v15.0 verdict:** SAFE -- deity pass check, boon pool stats, probability calculation, boon award. CEI compliant.

**v16.0-v17.1 change:** Same rngBypass threading as HR-05. The _maybeAwardBoon function routes through _handleLootboxTickets which gained rngBypass=false. The _maybeAwardBoon function itself is unchanged in logic.

**Re-validation:** The deity pass check, boon probability math, pool stats, and award logic are all untouched. The rngBypass=false on downstream ticket calls is correct (player-initiated). The v15.0 SAFE reasoning (access control, overflow, CEI) remains fully valid.

**Regression verdict: NO REGRESSION**

---

### HR-07. DegenerusAffiliate.payAffiliate (v15.0 #52, 179-02 #49)

**v15.0 verdict:** SAFE -- 75/20/5 weighted roll (mod 20), leaderboard after taper, quest call routing, no-referrer path, CEI compliant. Known PRNG tradeoff documented.

**v16.0-v17.1 change:** 179-02 #49 changes the bonus rate formula from flat (1 point/ETH) to tiered (4 points/ETH for first 5 ETH, 1.5 points/ETH for remaining, cap 50). This is in affiliateBonusPointsBest, which is called by MintStreakUtils._playerActivityScore, NOT by payAffiliate directly.

**Re-validation:** The payAffiliate function itself is NOT modified in v16.0-v17.1. The tiered rate change in affiliateBonusPointsBest only affects the activity score calculation, which is consumed by MintModule and DegeneretteModule during purchase flows -- not by payAffiliate. The v15.0 SAFE reasoning (mod 20 correctness, leaderboard ordering, CEI, quest routing) is completely unaffected by the affiliate bonus formula change.

**Regression verdict: NO REGRESSION**

---

### HR-08. JackpotModule._distributeTicketJackpot (v15.0 #56, repack)

**v15.0 verdict:** SAFE -- delegates to _distributeTicketsToBuckets with correct lvl parameter. Single lvl parameter, tickets queued at lvl+1 via hardcoded pattern.

**v16.0-v17.1 change:** No direct change to this function in 179-02. The function's callers (payDailyJackpotCoinAndTickets) have rngBypass changes, but _distributeTicketJackpot itself delegates to _distributeTicketsToBucket which calls _queueTickets(winner, lvl+1, ..., true). The rngBypass=true is threaded through the callers.

**Re-validation:** The function signature and body are unchanged. The lvl parameter semantics (source for winner selection at lvl, queue at lvl+1) remain identical. The downstream _queueTickets rngBypass=true is correct for jackpot-context ticket distribution. v15.0 SAFE reasoning (loop iteration, entropy domain separation, per-bucket fair distribution) intact.

**Regression verdict: NO REGRESSION**

---

### HR-09. JackpotModule.payDailyJackpot (v15.0 #61, 179-02 #5)

**v15.0 verdict:** SAFE -- full state machine for daily ETH distribution (phase 0 current, phase 1 carryover), quest rolling, STAGE_JACKPOT_ETH_RESUME, future ticket prep guard.

**v16.0-v17.1 change:** 179-02 #5 documents two changes: (1) All currentPrizePool direct reads replaced with _getCurrentPrizePool() and writes with _setCurrentPrizePool() for uint128 repack. (2) Carryover source selection simplified from 82-line _selectCarryoverSourceOffset/_highestCarryoverSourceOffset/_hasActualTraitTickets to inline keccak256-based random offset.

**Re-validation:**
- Storage repack helpers: _getCurrentPrizePool() returns uint256(currentPrizePool) -- widens uint128 to uint256, identical semantics to prior direct read. _setCurrentPrizePool(val) writes uint128(val) -- safe because pool values cannot exceed uint128 max (~3.4e38 wei). 179-02 #5 confirms: "The helpers correctly widen/narrow between uint256 and uint128."
- Carryover simplification: replaces 82 lines of exhaustive trait-ticket checking with a single keccak256 random offset in [1, DAILY_CARRYOVER_MAX_OFFSET]. 179-02 #5 confirms: "The new approach is simpler and deterministic... This may occasionally select source levels with empty trait buckets, but the downstream _distributeTicketsToBucket handles empty winners gracefully."
- v15.0 SAFE reasoning on ETH distribution budgets, bucket splits, currentPrizePool decrement, quest rolling: all preserved. The helper calls are transparent wrappers.

**Regression verdict: NO REGRESSION**

---

### HR-10. JackpotModule.payDailyJackpotCoinAndTickets (v15.0 #62, 179-02 #6)

**v15.0 verdict:** SAFE -- daily ticket distribution routes tickets to lvl+1, coin jackpot budget computation, no duplicate quest rolling.

**v16.0-v17.1 change:** 179-02 #6 confirms rngBypass parameter threading. All _queueTickets calls at lines 590, 604, 613, 621 now pass `true` as rngBypass. This function runs during jackpot phase when rngLockedFlag may be set.

**Re-validation:** rngBypass=true is correct -- these are internal jackpot distribution operations, not player-initiated. The function signature is unchanged. Daily ticket distribution logic (lvl parameter to _distributeTicketJackpot), coin budget computation (_calcDailyCoinBudget), and coin distribution paths are all untouched. v15.0 SAFE reasoning (ticket routing, coin split 25/75%, no duplicate quest call) fully intact.

**Regression verdict: NO REGRESSION**

---

### HR-11. WhaleModule.purchaseDeityPass (v15.0 #63, 179-02 #24)

**v15.0 verdict:** SAFE -- duplicate purchase check (deityPassCount[buyer] != 0), boon discount consumption, CEI-compliant deityPassCount write, msg.value check after boon consumption.

**v16.0-v17.1 change:** 179-02 #24 confirms rngBypass=false threading. The _queueTickets call at line 625 now passes `false` as rngBypass. Correct: deity pass purchases are player-initiated.

**Re-validation:** The function logic (duplicate check, boon consumption, CEI ordering, msg.value validation) is entirely unchanged. Only the downstream _queueTickets call gained rngBypass=false, which is the correct semantic for a player-initiated purchase. v15.0 SAFE reasoning intact.

**Regression verdict: NO REGRESSION**

---

### HR-12. WhaleModule.purchaseLazyPass (v15.0 #64, 179-02 #25)

**v15.0 verdict:** SAFE -- deity pass check prevents lazy purchase by deity holders, pass renewal window (8+ levels remaining blocks rebuy), correct polarity.

**v16.0-v17.1 change:** 179-02 #25 (_claimWhalePassTickets) confirms rngBypass=false threading. The _queueTickets call at line 482 passes false. Correct: lazy pass ticket claims are player-initiated.

**Re-validation:** The purchase guard logic (deity pass check polarity, frozenUntilLevel renewal window), boon interactions, and ticket queuing are all unchanged except for the rngBypass parameter. v15.0 SAFE reasoning (access checks, polarity, renewal window) intact.

**Regression verdict: NO REGRESSION**

---

### HR-13. WhaleModule.consolidatePrizePools (v15.0 #65, 179-02 #7)

**v15.0 verdict:** SAFE (formatting-only per changelog; function actually in JackpotModule, not WhaleModule).

**v16.0-v17.1 change:** 179-02 #7 documents storage repack helpers. All direct currentPrizePool reads/writes replaced with _getCurrentPrizePool()/_setCurrentPrizePool(). The yield accumulator dump logic (50% of yieldAccumulator into futurePool at x00 levels) unchanged. _distributeYieldSurplus reads _getCurrentPrizePool() which returns the consolidated value.

**Re-validation:** The function's pool merging logic (next into current, future-to-current transfer at x00), _creditDgnrsCoinflip call, and yield distribution are unchanged. The helper calls are transparent wrappers for the uint128 repack. 179-02 #7 confirms: "All arithmetic is safe: pool values cannot exceed total contract balance which fits in uint128." v15.0 SAFE reasoning (pool arithmetic, safe-from-overflow) intact.

**Regression verdict: NO REGRESSION**

---

### HR-14. DegenerusQuests.rollDailyQuest (v15.0 #35, 179-02 #41/#42)

**v15.0 verdict:** SAFE -- onlyGame access control (narrowed from onlyCoin), idempotent per day, slot 0 always MINT_ETH, slot 1 weighted random.

**v16.0-v17.1 change:** 179-02 #41/#42 documents QuestSlotRolled event change (removed `difficulty` parameter) and Quest struct `difficulty` field removal (changed to "16 bits free" comment). Storage layout preserved. Difficulty was always 0 and never read.

**Re-validation:** The event ABI change is a pre-launch indexer concern (no production indexers exist). The Quest struct storage layout is preserved (16 bits remain allocated but unused). The function's access control (onlyGame), idempotency guard, and quest type selection logic are completely untouched. v15.0 SAFE reasoning intact.

**Regression verdict: NO REGRESSION**

---

### HR-15. DegenerusGame.constructor (v15.0 #10, 179-02 #33)

**v15.0 verdict:** SAFE -- initial setup, level 0 configuration, vault perpetual ticket queuing.

**v16.0-v17.1 change:** 179-02 #33 adds rngBypass=false to the two _queueTickets calls at lines 213-214 (vault perpetual tickets in constructor loop). At construction time, rngLockedFlag is false (default), so the bypass is irrelevant, but false is the correct semantic value for non-jackpot context.

**Re-validation:** Constructor logic is unchanged. The rngBypass=false is correct and irrelevant (rngLockedFlag is false at deploy). v15.0 SAFE reasoning (initial state setup, deployment-time safety) intact.

**Regression verdict: NO REGRESSION**

---

### HR-16. DegenerusGame.claimAffiliateDgnrs (v15.0 #12, 179-02 via module list)

**v15.0 verdict:** SAFE -- claims DGNRS allocation for affiliates, reads levelDgnrsAllocation, transfers via dgnrs.transferFromPool.

**v16.0-v17.1 change:** The contract (DegenerusGame.sol) was modified for delegatecall target changes (GAME_ENDGAME_MODULE to GAME_WHALE_MODULE for claimWhalePass, GAME_JACKPOT_MODULE for runRewardJackpots) and storage repack helpers. However, claimAffiliateDgnrs itself is not in the 179-02 function list -- it was not modified.

**Re-validation:** The function reads levelDgnrsAllocation (set by _rewardTopAffiliate) and transfers DGNRS. The _rewardTopAffiliate function was inlined from EndgameModule into AdvanceModule (179-02 #11), but its write to levelDgnrsAllocation is semantically identical. The claimAffiliateDgnrs function itself has no code changes. v15.0 SAFE reasoning (allocation read, transfer, access control) intact.

**Regression verdict: NO REGRESSION**

---

### HR-17. AdvanceModule.advanceGame main loop (v15.0 #4)

**v15.0 verdict:** SAFE -- gameOverPossible integration (FLAG-01/02/03), state machine integrity (do-while(false) loop), PriceLookupLib, bounty calculation, reentrancy.

**v16.0-v17.1 change:** Multiple changes documented in 179-01:
- poolConsolidationDone guard removed; consolidation + _runRewardJackpots now atomic (lines 370-374)
- _rewardTopAffiliate moved from jackpot phase end to level transition point (before level=lvl)
- _runRewardJackpots delegatecall target changed from GAME_ENDGAME_MODULE to GAME_JACKPOT_MODULE
- NatSpec and formatting updates (v17.1-comments)
- rngBypass threading in _processPhaseTransition (covered in HR-02)
- _applyDailyRng changed `return 0` to `revert RngNotReady()` (179-02 #14)

**Re-validation:**
- poolConsolidationDone removal: The old guard prevented double-consolidation across multi-call state machine steps. The new code makes consolidation + reward jackpots a single atomic block at level transition, eliminating the need for the guard. 179-02 storage layout verification confirms the bool was safely removed from Slot 0.
- _rewardTopAffiliate moved: Now called at line 1416 during _requestRng when `isTicketJackpotDay && !isRetry` -- before `level = lvl`. This timing is correct: affiliate scores routed to lvl are frozen at this point. 179-02 #11 confirms SAFE.
- _runRewardJackpots target change: Selector and module are correct (identical function signature). 179-02 #12 confirms SAFE.
- _applyDailyRng revert: 179-02 #14 confirms this is a correctness improvement -- prevents zero-entropy propagation through jackpot system. The caller receives RngNotReady which maps to NotTimeYet-equivalent behavior.
- v15.0 SAFE reasoning (state machine integrity, FLAG-01/02/03 locations, bounty arithmetic, reentrancy via creditFlip) remains valid. The state machine do-while(false) structure is unchanged.

**Regression verdict: NO REGRESSION**

---

## LOW RISK Functions (brief confirmation)

These 26 functions had only rngBypass parameter additions (mechanical -- adds bool to signature, passes through to _queueTickets) or comment-only changes. The existing SAFE reasoning (reentrancy, access control, overflow, state corruption) is unaffected by these mechanical additions.

---

### LR-01. AdvanceModule._enforceDailyMintGate (v15.0 #6)
**Contract change:** AdvanceModule had v16.0-v17.1 changes, but this function is untouched (no rngBypass, no repack). NatSpec formatting only (v17.1).
**Verdict: NO REGRESSION** -- function body identical.

### LR-02. AdvanceModule.requestLootboxRng (v15.0 #7)
**Contract change:** AdvanceModule had changes, but this function is untouched in v16.0-v17.1. The price gate logic using `price` storage variable is unchanged.
**Verdict: NO REGRESSION** -- function body identical.

### LR-03. DegenerusGame.hasDeityPass (v15.0 #8)
**Contract change:** DegenerusGame had repack/module changes, but hasDeityPass is a simple view reading mintPacked_ bit 184. No changes.
**Verdict: NO REGRESSION** -- function body identical.

### LR-04. DegenerusGame.mintPackedFor (v15.0 #9)
**Contract change:** DegenerusGame had changes. mintPackedFor is a trivial view returning mintPacked_[player]. No changes.
**Verdict: NO REGRESSION** -- function body identical.

### LR-05. DegenerusGame.recordMintQuestStreak (v15.0 #11)
**Contract change:** DegenerusGame had changes, but this function is an internal delegatecall target for quest streak recording. No v16.0-v17.1 modifications.
**Verdict: NO REGRESSION** -- function body identical.

### LR-06. DegenerusGame._hasAnyLazyPass (v15.0 #13)
**Contract change:** DegenerusGame had changes. _hasAnyLazyPass reads mintPacked_ frozen bits. No modifications.
**Verdict: NO REGRESSION** -- function body identical.

### LR-07. DegenerusGame.mintPrice (v15.0 #14)
**Contract change:** DegenerusGame had changes. mintPrice is a view returning PriceLookupLib.priceForLevel(level+1). No modifications.
**Verdict: NO REGRESSION** -- function body identical.

### LR-08. DegenerusGame.decWindow (v15.0 #15)
**Contract change:** DegenerusGame had changes. decWindow returns bool based on decWindowOpen flag and level conditions. No modifications.
**Verdict: NO REGRESSION** -- function body identical.

### LR-09. DegenerusGame.playerActivityScore (v15.0 #16)
**Contract change:** The underlying _playerActivityScore (HR-04) gained cache read, but the DegenerusGame.playerActivityScore view wrapper is unchanged in signature and semantics. Cache-or-fallback is transparent.
**Verdict: NO REGRESSION** -- wrapper unchanged, underlying change verified in HR-04.

### LR-10. DegenerusGame.processPayment (v15.0 #17)
**Contract change:** DegenerusGame had changes. processPayment routes to MintModule delegatecall. No modifications to this function.
**Verdict: NO REGRESSION** -- function body identical.

### LR-11. MintModule._questMint (v15.0 #18)
**Contract change:** MintModule had affiliate cache and rngBypass changes. _questMint itself is unchanged (private, routes to quests.handleMint).
**Verdict: NO REGRESSION** -- function body identical.

### LR-12. MintModule._purchaseCoinFor (v15.0 #19)
**Contract change:** MintModule had changes. _purchaseCoinFor calls _callTicketPurchase (which now has rngBypass threading) and _purchaseBurnieLootboxFor. The function itself passes through to these calls with identical arguments except the new rngBypass parameter propagated internally.
**Verdict: NO REGRESSION** -- gameOverPossible guard, ticket path, lootbox bypass all unchanged.

### LR-13. MintModule._callTicketPurchase (v15.0 #21)
**Contract change:** MintModule had changes. The function internally calls _queueTicketsScaled (or downstream via _purchaseFor) which gained rngBypass parameter. The _callTicketPurchase function no longer calls _queueTicketsScaled directly (ticket queuing was moved to _purchaseFor in v14.0). No v16.0-v17.1 changes to this function.
**Verdict: NO REGRESSION** -- function body identical.

### LR-14. MintStreakUtils._activeTicketLevel (v15.0 #22)
**Contract change:** MintStreakUtils had affiliate cache read change (#43), but _activeTicketLevel is a separate function reading mintPacked_ ticket level bits. No modifications.
**Verdict: NO REGRESSION** -- function body identical.

### LR-15. LootboxModule._boonPoolStats (v15.0 #27)
**Contract change:** LootboxModule had rngBypass and comment changes. _boonPoolStats is a view function computing boon pool statistics. Comment-only changes (v17.1).
**Verdict: NO REGRESSION** -- logic identical, comment corrections only.

### LR-16. DegenerusQuests.handlePurchase (v15.0 #28)
**Contract change:** DegenerusQuests had difficulty removal. handlePurchase is unaffected (no difficulty field usage in this function).
**Verdict: NO REGRESSION** -- function body identical.

### LR-17. DegenerusQuests.rollLevelQuest (v15.0 #29)
**Contract change:** DegenerusQuests difficulty removal. rollLevelQuest does not use difficulty. No changes.
**Verdict: NO REGRESSION** -- function body identical.

### LR-18. DegenerusQuests.clearLevelQuest (v15.0 #30)
**Contract change:** DegenerusQuests difficulty removal. clearLevelQuest sets levelQuestType=0. No changes.
**Verdict: NO REGRESSION** -- function body identical.

### LR-19. DegenerusQuests._isLevelQuestEligible (v15.0 #31)
**Contract change:** No changes to this view function.
**Verdict: NO REGRESSION** -- function body identical.

### LR-20. DegenerusQuests._levelQuestTargetValue (v15.0 #32)
**Contract change:** No changes to this pure function.
**Verdict: NO REGRESSION** -- function body identical.

### LR-21. DegenerusQuests._handleLevelQuestProgress (v15.0 #33)
**Contract change:** No changes to this function.
**Verdict: NO REGRESSION** -- function body identical.

### LR-22. DegenerusQuests.getPlayerLevelQuestView (v15.0 #34)
**Contract change:** No changes to this view function.
**Verdict: NO REGRESSION** -- function body identical.

### LR-23. JackpotModule._distributeTicketsToBuckets (v15.0 #57)
**Contract change:** JackpotModule had major changes. This function is not directly modified -- it delegates to _distributeTicketsToBucket which gained rngBypass=true on downstream _queueTickets. Entropy step and per-bucket loop unchanged.
**Verdict: NO REGRESSION** -- function body identical, downstream rngBypass=true correct.

### LR-24. JackpotModule._distributeTicketsToBucket (v15.0 #58)
**Contract change:** JackpotModule had changes. The _queueTickets call at line 1188 now passes rngBypass=true. The function is called during jackpot distribution (RNG-locked window), so bypass is correct.
**Verdict: NO REGRESSION** -- only rngBypass mechanical addition, logic path unchanged.

### LR-25. JackpotModule._creditDgnrsCoinflip (v15.0 #59)
**Contract change:** JackpotModule had changes. _creditDgnrsCoinflip reads `price` and calls coinflip.creditFlip. No v16.0-v17.1 modifications to this function.
**Verdict: NO REGRESSION** -- function body identical.

### LR-26. JackpotModule._calcDailyCoinBudget (v15.0 #60)
**Contract change:** JackpotModule had changes. _calcDailyCoinBudget reads `price` and `levelPrizePool[lvl-1]`. No v16.0-v17.1 modifications.
**Verdict: NO REGRESSION** -- function body identical.

---

## NO RISK Functions (unchanged confirmation)

These 33 functions are in contracts that either had NO v16.0-v17.1 changes or had only comment-only changes (v17.1-comments). The function code is identical to v15.0.

---

### AdvanceModule

| # | Function | v15.0 ID | Status |
|---|----------|----------|--------|
| 1 | _wadPow | #1 | NO CHANGE -- pure math, no contract modifications affect this function |
| 2 | _projectedDrip | #2 | NO CHANGE -- pure math, calls _wadPow only |

### DegenerusQuests

| # | Function | v15.0 ID | Status |
|---|----------|----------|--------|
| 3 | handleMint | #36 | NO CHANGE -- handler logic unaffected by difficulty removal |
| 4 | handleFlip | #37 | NO CHANGE -- handler logic untouched |
| 5 | handleDecimator | #38 | NO CHANGE -- handler logic untouched |
| 6 | handleAffiliate | #39 | NO CHANGE -- handler logic untouched |
| 7 | handleLootBox | #40 | NO CHANGE -- handler logic untouched |
| 8 | handleDegenerette | #41 | NO CHANGE -- handler logic untouched |
| 9 | _questHandleProgressSlot | #42 | NO CHANGE -- progress slot handling untouched |
| 10 | _canRollDecimatorQuest | #43 | NO CHANGE -- view function untouched |
| 11 | _bonusQuestType | #44 | NO CHANGE -- bonus selection loop untouched |
| 12 | onlyCoin modifier | #45 | NO CHANGE -- access control list untouched |

### BurnieCoin (COMMENT-ONLY in v17.1)

| # | Function | v15.0 ID | Status |
|---|----------|----------|--------|
| 13 | burnCoin | #46 | COMMENT-ONLY -- NatSpec corrections, logic identical |
| 14 | decimatorBurn | #47 | COMMENT-ONLY -- NatSpec corrections, logic identical |
| 15 | onlyGame modifier | #48 | COMMENT-ONLY -- no modifier logic change |

### BurnieCoinflip (COMMENT-ONLY in v17.1)

| # | Function | v15.0 ID | Status |
|---|----------|----------|--------|
| 16 | onlyFlipCreditors modifier | #49 | COMMENT-ONLY -- no modifier logic change |
| 17 | _resolveRecycleRebet | #50 | COMMENT-ONLY -- no logic change |
| 18 | _resolveRecycleBatch | #51 | COMMENT-ONLY -- no logic change |

### DegeneretteModule (COMMENT-ONLY in v17.1)

| # | Function | v15.0 ID | Status |
|---|----------|----------|--------|
| 19 | _placeBet | #53 | COMMENT-ONLY -- no logic change |
| 20 | _createCustomTickets | #54 | COMMENT-ONLY -- no logic change |
| 21 | _resolvePayout | #55 | COMMENT-ONLY -- no logic change |

### Phase 164 Carryover Functions (JackpotModule)

Note: These 11 functions were audited in Phase 164 (not Phase 165 plans 01-04), but are included in the 76-function master table. The v16.0-v17.1 changes to JackpotModule affected these functions as follows:

| # | Function | Phase 164 | Status |
|---|----------|-----------|--------|
| 22 | payDailyJackpot (carryover path) | JM 357-407 | CHANGED -- covered by HR-09 (storage repack helpers + carryover source simplification). NO REGRESSION. |
| 23 | _selectCarryoverSourceOffset | JM 2513-2556 | DELETED -- replaced by inline keccak256 offset in HR-09. Simplification is safe per 179-02 #5. |
| 24 | _highestCarryoverSourceOffset | JM 2495-2508 | DELETED -- part of 82-line removal in HR-09. |
| 25 | _budgetToTicketUnits | JM 915-922 | NO CHANGE -- formula and div-by-zero guard unchanged. |
| 26 | _packDailyTicketBudgets | JM 2558-2569 | NO CHANGE -- 144-bit layout packing unchanged. |
| 27 | _unpackDailyTicketBudgets | JM 2571-2587 | NO CHANGE -- round-trip unpacking unchanged. |
| 28 | payDailyJackpotCoinAndTickets (carryover) | JM 588-601 | CHANGED -- rngBypass threading (covered by HR-10). NO REGRESSION. |
| 29 | Final-day detection (isFinalDay) | JM 591 | NO CHANGE -- formula unchanged. |
| 30 | Final-day carryover routing | JM 592-600 | NO CHANGE -- lvl+1 routing unchanged. |
| 31 | lastPurchaseDay lifecycle | AM 144-377 | CHANGED -- poolConsolidationDone removal affects surrounding code, but lastPurchaseDay set/consume/reset is unchanged (covered in HR-17). |
| 32 | Level increment timing | AM 1370-1374 | NO CHANGE -- level = lvl at RNG request point, before jackpot. Timing unchanged. |

### DecimatorModule (not in v15.0 76 but referenced in plan)

The plan references DecimatorModule functions #53-55 from v15.0 as potentially affected by the _terminalDecMultiplierBps rescale (179-02 #38). However, DecimatorModule functions in the v15.0 audit are only from Phase 164 coverage or are not in the 76-function master table. The _terminalDecMultiplierBps change is a formula rescale (reviewed in 179-02 #38 as SAFE) that does not affect the access control, overflow, or reentrancy properties of any v15.0-audited DecimatorModule function.

### JackpotModule _distributeYieldSurplus

| # | Function | 179-02 | Status |
|---|----------|--------|--------|
| 33 | _distributeYieldSurplus | #8 | CHANGED -- single line: `obligations` reads _getCurrentPrizePool() instead of direct currentPrizePool. Helper returns uint256(currentPrizePool) -- identical widening semantics. NO REGRESSION. |

---

## Cross-Reference Verification

### All 12 contracts from v15.0 master table confirmed present:

| Contract | v15.0 Functions | Regression Check Coverage |
|----------|-----------------|---------------------------|
| AdvanceModule | 7 (#1-#7) | 2 HIGH (HR-01, HR-02, HR-17) + 2 LOW (LR-01, LR-02) + 2 NO RISK + 1 overlap |
| DegenerusGame | 10 (#8-#17) | 2 HIGH (HR-15, HR-16) + 8 LOW (LR-03 through LR-10) |
| MintModule | 4 (#18-#21) | 1 HIGH (HR-03) + 3 LOW (LR-11, LR-12, LR-13) |
| MintStreakUtils | 3 (#22-#24) | 1 HIGH (HR-04) + 1 LOW (LR-14) + 1 overlap |
| LootboxModule | 3 (#25-#27) | 2 HIGH (HR-05, HR-06) + 1 LOW (LR-15) |
| DegenerusQuests | 18 (#28-#45) | 1 HIGH (HR-14) + 7 LOW (LR-16 through LR-22) + 10 NO RISK |
| BurnieCoin | 3 (#46-#48) | 3 NO RISK (comment-only) |
| BurnieCoinflip | 3 (#49-#51) | 3 NO RISK (comment-only) |
| DegenerusAffiliate | 1 (#52) | 1 HIGH (HR-07) |
| DegeneretteModule | 3 (#53-#55) | 3 NO RISK (comment-only) |
| JackpotModule | 7 (#56-#62) | 4 HIGH (HR-08, HR-09, HR-10, HR-13) + 3 LOW (LR-23, LR-24, LR-25, LR-26) |
| WhaleModule | 3 (#63-#65) | 2 HIGH (HR-11, HR-12) + 1 HIGH (HR-13) |

Phase 164: 11 carryover functions covered in NO RISK section (items 22-32).

**Total: 17 HIGH + 26 LOW + 33 NO RISK = 76 functions.**

---

## Regression Verdict

**ZERO REGRESSIONS FOUND.**

All 76 v15.0 adversarial SAFE verdicts remain intact against the current codebase (post v16.0-v17.1 refactors).

The v16.0-v17.1 changes fall into three categories, all confirmed non-regressing:

1. **Storage repack (v16.0):** currentPrizePool uint256-to-uint128 with transparent getter/setter helpers. Widening/narrowing is lossless within economic bounds. poolConsolidationDone removal is safe because consolidation is now atomic.

2. **rngBypass refactor:** Mechanical parameter addition replacing the `!phaseTransitionActive` global guard with explicit per-call-site `rngBypass` boolean. All call sites pass the correct boolean (true for jackpot/transition contexts, false for player-initiated).

3. **EndgameModule deletion (v16.0):** Functions migrated to JackpotModule and WhaleModule with identical logic. Delegatecall targets updated correctly. _rewardTopAffiliate inlined with identical semantics.

4. **Affiliate bonus cache (v17.0):** Additive cache in mintPacked_ bits [185-214]. Cache-or-fallback pattern ensures correctness. No existing bit fields affected.

5. **Comment sweep (v17.1):** NatSpec corrections only. Zero logic changes.

No v15.0 SAFE assertion was invalidated by any of these changes.
