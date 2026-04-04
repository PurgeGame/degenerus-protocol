# Phase 182: v15.0 Adversarial Regression Check

**Baseline:** v15.0 Phase 165 -- 76 functions, 76 SAFE, 0 VULNERABLE
**Change surface:** v16.0-v17.1 (Phase 179 inventory)
**Method:** Cross-reference each v15.0 verdict against current code via 179-01 diff inventory and 179-02 function verdicts

## Summary

| Risk Category | Functions | Regressions |
|---------------|-----------|-------------|
| HIGH RISK (logic changed) | 17 | 0 |
| LOW RISK (mechanical/comment) | 25 | 0 |
| NO RISK (untouched) | 34 | 0 |
| **Total** | **76** | **0** |

---

## HIGH RISK Functions (detailed re-validation)

These 17 functions appear in BOTH the v15.0 master table AND the 179-02 function verdicts with logic changes (not comment-only or rngBypass-only).

---

### HR-01. AdvanceModule._evaluateGameOverPossible (#3 in v15.0, 179-02 #15)

**v15.0 reasoning (165-01 #3):** SAFE -- sets/clears gameOverPossible flag based on projected drip vs deficit. Protected from underflow by early returns. Three call sites verified (FLAG-01, FLAG-02, FLAG-03). No external calls. Private function.

**v16.0-v17.1 change (179-02 #15):** Function body unchanged. Only callers changed -- called from new locations after endgame module elimination. Both call sites pass `(lvl, purchaseLevel)` correctly.

**Re-validation:** The function's own logic is identical. The original SAFE reasoning (underflow protection, no external calls, correct deficit math) applies without modification. New caller locations are verified safe in 179-02.

**Regression verdict: NO REGRESSION**

---

### HR-02. AdvanceModule._processPhaseTransition (#5 in v15.0, 179-02 #13)

**v15.0 reasoning (165-01 #5):** SAFE -- queues vault perpetual tickets at purchaseLevel+99 for SDGNRS and VAULT. _autoStakeExcessEth uses try/catch. Trivially safe. Private function.

**v16.0-v17.1 change (179-02 #13):** Both `_queueTickets` calls now pass `rngBypass=true` as fourth parameter. This replaces the prior reliance on `!phaseTransitionActive` guard in `_queueTickets`.

**Re-validation:** The rngBypass=true is correct because this runs during phase transition when rngLockedFlag is set. The original SAFE reasoning (no overflow, try/catch on external call, correct level argument) is entirely unaffected by the mechanical boolean parameter addition. The semantic behavior -- allowing far-future ticket queuing during phase transition -- is preserved.

**Regression verdict: NO REGRESSION**

---

### HR-03. MintModule._purchaseFor (#20 in v15.0, 179-02 #31 indirectly via recordMintData)

**v15.0 reasoning (165-02 #3, sub-items 3a-3h):** SAFE -- 8 sub-items verified: purchaseLevel ternary correct, PriceLookupLib correct, lootbox base level correct, handlePurchase arguments correct, compute-once activity score correct, batched creditFlip correct, claimableWinnings read-once correct, ticket queuing moved from _callTicketPurchase (no duplicate).

**v16.0-v17.1 change (179-02 #31):** The v17.0 affiliate cache added a write to mintPacked_ bits [185-214] in recordMintData (called from within _purchaseFor flow). This caches the affiliate bonus level and points to eliminate a cold SLOAD from _playerActivityScore.

**Re-validation:** The affiliate cache write piggybacks on the existing mintPacked_ SSTORE (zero additional gas). The write occurs in recordMintData, which runs before _playerActivityScore is called (line 782). The cached value is read by _playerActivityScore only when `cachedLevel == currLevel` (stale cache falls back to live read). The original 8 SAFE sub-items are unaffected: the cache is a pure gas optimization that does not alter score values, ticket routing, payment validation, or creditFlip batching.

**Regression verdict: NO REGRESSION**

---

### HR-04. MintStreakUtils._playerActivityScore 3-arg (#23 in v15.0, 179-02 #43)

**v15.0 reasoning (165-02 #6):** SAFE -- overflow analysis: max total ~45,500 bps, far below uint256. Deity pass bit check at position 184 correct. Pass/whale floor correctly sets minimums. Private view function.

**v16.0-v17.1 change (179-02 #43):** Lines 139-148: affiliate bonus now reads from mintPacked_ cache when `cachedLevel == currLevel`, falling back to `affiliate.affiliateBonusPointsBest(currLevel, player)` when stale. MASK_6 (6-bit) and MASK_24 (24-bit) reads match the write in MintModule.recordMintData.

**Re-validation:** The cache read produces the same value as the live read (the cache is populated from the same `affiliateBonusPointsBest` call during recordMintData). The 6-bit points field (max 63) accommodates the max 50 bonus points. The fallback path preserves the original behavior for first-mint-at-new-level. The original overflow analysis is unaffected (affiliate bonus component unchanged in magnitude). The original SAFE reasoning holds.

**Regression verdict: NO REGRESSION**

---

### HR-05. MintStreakUtils._playerActivityScore 2-arg (#24 in v15.0, 179-02 #43 indirectly)

**v15.0 reasoning (165-02 #7):** SAFE -- convenience wrapper calling 3-arg version with _activeTicketLevel(). Delegates to proven-safe 3-arg version.

**v16.0-v17.1 change:** No direct change to this wrapper. The underlying 3-arg version changed (HR-04 above).

**Re-validation:** Since the 3-arg version is confirmed NO REGRESSION (HR-04), and this wrapper is unchanged, the wrapper remains SAFE.

**Regression verdict: NO REGRESSION**

---

### HR-06. LootboxModule.openBurnieLootBox (#25 in v15.0, 179-02 #47 via rngBypass)

**v15.0 reasoning (165-02 #8, sub-items 8a-8b):** SAFE -- price level argument correct for valuation (not ETH flow). TICKET_FAR_FUTURE_BIT redirect only affects current-level tickets. Bit OR does not corrupt level for practical ranges. Near-future routing unaffected.

**v16.0-v17.1 change (179-02 #47):** `_queueTicketsScaled` call now passes `false` as rngBypass. Lootbox opens are player-initiated external transactions that should respect the RNG lock.

**Re-validation:** The rngBypass=false is correct for the player-initiated lootbox path. The original SAFE reasoning (price valuation correctness, bit-OR safety, gameOverPossible redirect) is unaffected by the boolean parameter addition. No new branches or conditions introduced beyond the rngBypass threading.

**Regression verdict: NO REGRESSION**

---

### HR-07. LootboxModule._maybeAwardBoon (#26 in v15.0, 179-02 #47 via rngBypass indirectly)

**v15.0 reasoning (165-02 #9):** SAFE -- deity pass check polarity verified: `& 1 == 0` means "no pass" -> eligible for deity pass boon. Matches old `deityPassCount[player] == 0` semantics. Bit position 184 correct.

**v16.0-v17.1 change:** The rngBypass parameter threads through `_handleLootboxTickets` (179-02 #47) which is called from lootbox paths but does not change `_maybeAwardBoon` itself. The boon awarding logic is unmodified.

**Re-validation:** `_maybeAwardBoon`'s deity eligibility check, boon roll weights, and award paths are untouched by v16.0-v17.1. The original polarity verification and bit position analysis remain valid.

**Regression verdict: NO REGRESSION**

---

### HR-08. DegenerusAffiliate.payAffiliate (#52 in v15.0, 179-02 #49)

**v15.0 reasoning (165-03 #25):** SAFE -- leaderboard after taper (correct ordering), 75/20/5 roll math verified (15/20, 4/20, 1/20), quest call routing via handleAffiliate correct, no-referrer 50/50 path correct, CEI compliant (state finalized before external calls), known PRNG documented.

**v16.0-v17.1 change (179-02 #49):** Tiered rate formula in `affiliateBonusPointsBest` -- 4pt/ETH for first 5 ETH, 1.5pt/ETH for next 20 ETH (was flat 1pt/ETH). Cap at 50 still applies. Continuous at boundary (20 points at 5 ETH in both branches).

**Re-validation:** The tiered rate change is in `affiliateBonusPointsBest` (a view function called by _playerActivityScore), NOT in `payAffiliate` itself. The payAffiliate function's own logic -- 75/20/5 roll, leaderboard recording, taper application, CEI ordering -- is unchanged. The original SAFE reasoning for payAffiliate holds completely. The tiered rate change affects activity score magnitude (more points at low volumes, same cap at high), which is a game design parameter, not a security vector.

**Regression verdict: NO REGRESSION**

---

### HR-09. JackpotModule._distributeTicketJackpot (#56 in v15.0, 179-02 via repack indirectly)

**v15.0 reasoning (165-04 #1):** SAFE -- delegates to _distributeTicketsToBuckets which delegates to _distributeTicketsToBucket. Single `lvl` parameter with hardcoded `lvl + 1` queuing. Callers pass correct levels. No behavioral regression in current state.

**v16.0-v17.1 change:** The downstream `_queueTickets` calls now pass `rngBypass=true` (since this runs during jackpot phase). The `currentPrizePool` helpers are used in the enclosing payDailyJackpot. `_distributeTicketJackpot` itself has no direct code change -- the rngBypass threads through the `_distributeTicketsToBucket` -> `_queueTickets` chain.

**Re-validation:** The function body is unchanged. The rngBypass parameter is threaded through calls below it (correct for jackpot-phase context). The original SAFE reasoning (correct level routing, entropy domain separation, extra-ticket fairness) remains valid.

**Regression verdict: NO REGRESSION**

---

### HR-10. JackpotModule.payDailyJackpot (#61 in v15.0, 179-02 #5)

**v15.0 reasoning (165-04 #6):** SAFE -- daily ETH distribution budget reads correct, carryover ETH path correct, quest rolling routed through BurnieCoin (v13.0 state), STAGE_JACKPOT_ETH_RESUME state machine present. Future ticket prep guard correct.

**v16.0-v17.1 change (179-02 #5):** Two changes: (1) All `currentPrizePool` direct reads replaced with `_getCurrentPrizePool()` and writes with `_setCurrentPrizePool()` for uint128 repack. Helpers correctly widen/narrow. (2) Carryover source selection simplified from 82-line deletion/probing algorithm to inline `keccak256(...) % DAILY_CARRYOVER_MAX_OFFSET + 1`. Simpler, deterministic, handles empty trait buckets gracefully downstream.

**Re-validation:** (1) The currentPrizePool helpers are verified safe in 179-02 -- widening/narrowing between uint128 and uint256 is lossless for pool values bounded by total contract balance. The original budget, distribution, and guard logic is semantically identical. (2) The carryover simplification removes complexity but maintains the invariant that a random source offset in [1, MAX_OFFSET] is selected. Empty-bucket handling was already present in _distributeTicketsToBucket (zero tickets queued). The original SAFE reasoning (budget correctness, guard logic, quest routing) holds.

**Regression verdict: NO REGRESSION**

---

### HR-11. JackpotModule.payDailyJackpotCoinAndTickets (#62 in v15.0, 179-02 #6)

**v15.0 reasoning (165-04 #7):** SAFE -- daily tickets route to lvl+1 via _distributeTicketJackpot. Coin jackpot splits 25% far-future / 75% near-future correctly. Quest rolling not in this function. No duplicate call.

**v16.0-v17.1 change (179-02 #6):** `_queueTickets` calls at lines 590, 604, 613, 621 now pass `rngBypass=true`. Correct: runs during jackpot phase when rngLockedFlag may be set. Internal jackpot distribution should not trigger RngLocked reverts.

**Re-validation:** The rngBypass=true prevents false reverts during internal jackpot processing. No other logic changes. The original SAFE reasoning (correct level routing, coin budget split, no duplicate quest calls) is entirely unaffected.

**Regression verdict: NO REGRESSION**

---

### HR-12. WhaleModule.purchaseDeityPass (#63 in v15.0, 179-02 #24)

**v15.0 reasoning (165-04 #8):** SAFE -- duplicate purchase check via `deityPassCount[buyer] != 0` (correct polarity). Write path after all reverts. Boon consumption before msg.value check (correct: reverts rollback storage). CEI-compliant.

**v16.0-v17.1 change (179-02 #24):** `_queueTickets` call now passes `false` as rngBypass. Deity pass purchases are player-initiated external transactions.

**Re-validation:** rngBypass=false is correct for player-initiated purchases. The original SAFE reasoning (duplicate check polarity, write ordering, boon consumption, CEI compliance) is unaffected. The deity pass check mechanism itself (deityPassCount mapping vs mintPacked_ bit) was already verified equivalent in v15.0 analysis.

**Regression verdict: NO REGRESSION**

---

### HR-13. WhaleModule.purchaseLazyPass (#64 in v15.0, 179-02 #25)

**v15.0 reasoning (165-04 #9):** SAFE -- deity pass check prevents lazy pass purchase by deity pass holders (correct polarity). Pass renewal guard at 8+ levels remaining. Correct.

**v16.0-v17.1 change (179-02 #25):** `_queueTickets` call now passes `false` as rngBypass. Player-initiated purchase.

**Re-validation:** Same as HR-12. rngBypass=false is correct. Original SAFE reasoning (deity check polarity, renewal guard) unaffected.

**Regression verdict: NO REGRESSION**

---

### HR-14. WhaleModule.consolidatePrizePools (#65 in v15.0, 179-02 #7)

**v15.0 reasoning (165-04 #10):** SAFE -- formatting-only change per changelog. Function attributed to WhaleModule but actually in JackpotModule (misattribution noted).

**v16.0-v17.1 change (179-02 #7):** All direct `currentPrizePool` reads/writes replaced with helper calls. `_getCurrentPrizePool() + _getNextPrizePool()` correctly merges next into current. Yield accumulator dump logic unchanged.

**Re-validation:** The currentPrizePool helper substitution is mechanical and verified safe (179-02 confirms widening/narrowing is lossless). The pool arithmetic is unchanged. The original SAFE reasoning holds.

**Regression verdict: NO REGRESSION**

---

### HR-15. DegenerusQuests.rollDailyQuest (#35 in v15.0, 179-02 #41/#42)

**v15.0 reasoning (165-03 #8):** SAFE -- access control changed to onlyGame (correct, called from AdvanceModule). Idempotent per day. Events emitted directly. Slot 0 always MINT_ETH, slot 1 weighted random.

**v16.0-v17.1 change (179-02 #41/#42):** `difficulty` parameter removed from QuestSlotRolled event. Quest struct `uint16 difficulty` field replaced with "16 bits free" comment. Storage layout preserved (16 bits remain allocated but unused). Difficulty was always 0 and never read.

**Re-validation:** The difficulty removal is a vestigial cleanup. The field was always 0 (confirmed in v15.0 analysis). Removing it from the event is a breaking ABI change for indexers, but acceptable for pre-launch contract. The original SAFE reasoning (access control, idempotency, quest type selection) is unaffected.

**Regression verdict: NO REGRESSION**

---

### HR-16. DegenerusGame.constructor (#10 in v15.0, 179-02 #33)

**v15.0 reasoning (165-01 #10, referenced in master table):** SAFE -- constructor sets up initial state. Verified in v14.0 context.

**v16.0-v17.1 change (179-02 #33):** Two `_queueTickets` calls in the constructor loop now pass `false` as rngBypass. At construction time, rngLockedFlag is false (default), so the bypass is irrelevant, but `false` is the correct semantic value.

**Re-validation:** The rngBypass=false parameter is a no-op at construction time (rngLockedFlag defaults to false). Original constructor safety reasoning unaffected.

**Regression verdict: NO REGRESSION**

---

### HR-17. DegenerusGame.claimAffiliateDgnrs (#12 in v15.0, 179-02 #34 indirectly via module list)

**v15.0 reasoning (165-01 #12, referenced in master table):** SAFE -- verified in v14.0 context. Claims affiliate DGNRS allocation.

**v16.0-v17.1 change (179-02 #34):** DegenerusGame.claimWhalePass delegatecall target changed from GAME_ENDGAME_MODULE to GAME_WHALE_MODULE. claimAffiliateDgnrs itself is unchanged -- the "module list" change refers to the DegenerusGame facade routing, not claimAffiliateDgnrs logic.

**Re-validation:** claimAffiliateDgnrs function body is untouched by v16.0-v17.1. The module list change only affects claimWhalePass routing. Original SAFE reasoning holds.

**Regression verdict: NO REGRESSION**

---

## LOW RISK Functions (brief confirmation)

These 25 functions are in contracts touched by v16.0-v17.1 but the function itself had only rngBypass parameter addition (mechanical, no logic change) or comment-only changes.

---

### LR-01. AdvanceModule.advanceGame main loop (#4) -- rngBypass threading

rngBypass parameters thread through `_queueTickets` calls within the advanceGame flow. The advanceGame loop structure, stage machine, bounty calculations, and gameOverPossible integration are unchanged. Original SAFE reasoning (correct state machine, no double-processing, CEI on creditFlip) intact. **NO REGRESSION.**

### LR-02. AdvanceModule._enforceDailyMintGate (#6) -- unchanged

Function not directly modified by v16.0-v17.1. AdvanceModule had changes to other functions (endgame inline, rngBypass), but _enforceDailyMintGate's deity pass check, time calculations, and pass bypass logic are untouched. **NO REGRESSION.**

### LR-03. AdvanceModule.requestLootboxRng (#7) -- unchanged

Function not directly modified. The rngBypass changes affect _queueTickets (which requestLootboxRng does not call directly). **NO REGRESSION.**

### LR-04. DegenerusGame.hasDeityPass (#8) -- unchanged

Pure view function reading mintPacked_ bit 184. No v16.0-v17.1 changes. **NO REGRESSION.**

### LR-05. DegenerusGame.mintPackedFor (#9) -- unchanged

Pure view function returning mintPacked_ for a player. No v16.0-v17.1 changes to the function itself; the mintPacked_ layout was extended with affiliate cache bits [185-214] but the view function returns the raw packed value regardless. **NO REGRESSION.**

### LR-06. DegenerusGame.recordMintQuestStreak (#11) -- unchanged

No v16.0-v17.1 changes to this function. **NO REGRESSION.**

### LR-07. DegenerusGame._hasAnyLazyPass (#13) -- unchanged

No v16.0-v17.1 changes. **NO REGRESSION.**

### LR-08. DegenerusGame.mintPrice (#14) -- unchanged

PriceLookupLib view. No v16.0-v17.1 changes. **NO REGRESSION.**

### LR-09. DegenerusGame.decWindow (#15) -- unchanged

Bool return view. No v16.0-v17.1 changes. **NO REGRESSION.**

### LR-10. DegenerusGame.playerActivityScore (#16) -- unchanged

External wrapper calling _playerActivityScore. The underlying function gained affiliate cache read (HR-04 above, confirmed NO REGRESSION). The wrapper itself is unchanged. **NO REGRESSION.**

### LR-11. DegenerusGame.processPayment (#17) -- unchanged

No v16.0-v17.1 changes. **NO REGRESSION.**

### LR-12. MintModule._questMint (#18) -- unchanged

Private helper routing quest progress. No v16.0-v17.1 changes. **NO REGRESSION.**

### LR-13. MintModule._purchaseCoinFor (#19) -- unchanged

BURNIE ticket + lootbox purchase entry. gameOverPossible check logic unchanged. No v16.0-v17.1 changes to this function. **NO REGRESSION.**

### LR-14. MintModule._callTicketPurchase (#21) -- unchanged

Ticket purchase payment/boost/affiliate routing. No v16.0-v17.1 changes to the function itself. **NO REGRESSION.**

### LR-15. MintStreakUtils._activeTicketLevel (#22) -- unchanged

View helper: `jackpotPhaseFlag ? level : level + 1`. No v16.0-v17.1 changes. **NO REGRESSION.**

### LR-16. LootboxModule._boonPoolStats (#27) -- unchanged

View function. No v16.0-v17.1 changes. **NO REGRESSION.**

### LR-17. DegenerusQuests.handlePurchase (#28) -- unchanged

New in v14.0. No v16.0-v17.1 changes to this function. **NO REGRESSION.**

### LR-18. DegenerusQuests.handleMint (#36) -- unchanged

No v16.0-v17.1 changes. **NO REGRESSION.**

### LR-19. DegenerusQuests.handleFlip (#37) -- unchanged

No v16.0-v17.1 changes. **NO REGRESSION.**

### LR-20. DegenerusQuests.handleDecimator (#38) -- unchanged

No v16.0-v17.1 changes. **NO REGRESSION.**

### LR-21. DegenerusQuests.handleAffiliate (#39) -- unchanged

No v16.0-v17.1 changes. **NO REGRESSION.**

### LR-22. DegenerusQuests.handleLootBox (#40) -- unchanged

No v16.0-v17.1 changes. **NO REGRESSION.**

### LR-23. DegenerusQuests.handleDegenerette (#41) -- unchanged

No v16.0-v17.1 changes. **NO REGRESSION.**

### LR-24. DegenerusQuests._questHandleProgressSlot (#42) -- unchanged

No v16.0-v17.1 changes. **NO REGRESSION.**

### LR-25. DegenerusQuests._canRollDecimatorQuest (#43) -- unchanged

No v16.0-v17.1 changes. **NO REGRESSION.**

---

## NO RISK Functions (unchanged confirmation)

These 34 functions are in contracts that had NO v16.0-v17.1 logic changes (comment-only or entirely untouched), or the specific function was not in the change surface at all.

---

### NR-01. AdvanceModule._wadPow (#1) -- UNCHANGED
Pure math function. No v16.0-v17.1 changes. **NO REGRESSION.**

### NR-02. AdvanceModule._projectedDrip (#2) -- UNCHANGED
Pure math function. No v16.0-v17.1 changes. **NO REGRESSION.**

### NR-03. DegenerusQuests.rollLevelQuest (#29) -- UNCHANGED
No v16.0-v17.1 changes beyond the difficulty removal in rollDailyQuest (HR-15). rollLevelQuest itself is untouched. **NO REGRESSION.**

### NR-04. DegenerusQuests.clearLevelQuest (#30) -- UNCHANGED
No v16.0-v17.1 changes. **NO REGRESSION.**

### NR-05. DegenerusQuests._isLevelQuestEligible (#31) -- UNCHANGED
No v16.0-v17.1 changes. **NO REGRESSION.**

### NR-06. DegenerusQuests._levelQuestTargetValue (#32) -- UNCHANGED
No v16.0-v17.1 changes. **NO REGRESSION.**

### NR-07. DegenerusQuests._handleLevelQuestProgress (#33) -- UNCHANGED
No v16.0-v17.1 changes. **NO REGRESSION.**

### NR-08. DegenerusQuests.getPlayerLevelQuestView (#34) -- UNCHANGED
No v16.0-v17.1 changes. **NO REGRESSION.**

### NR-09. DegenerusQuests._bonusQuestType (#44) -- UNCHANGED
No v16.0-v17.1 changes. Sentinel-0 skip is pre-existing from v13.0. **NO REGRESSION.**

### NR-10. DegenerusQuests.onlyCoin modifier (#45) -- UNCHANGED
No v16.0-v17.1 changes. **NO REGRESSION.**

### NR-11. BurnieCoin.burnCoin (#46) -- COMMENT-ONLY
v17.1-comments: NatSpec corrections only. No logic changes. **NO REGRESSION.**

### NR-12. BurnieCoin.decimatorBurn (#47) -- COMMENT-ONLY
v17.1-comments: NatSpec corrections only. No logic changes. **NO REGRESSION.**

### NR-13. BurnieCoin.onlyGame modifier (#48) -- COMMENT-ONLY
v17.1-comments: NatSpec corrections only. No logic changes. **NO REGRESSION.**

### NR-14. BurnieCoinflip.onlyFlipCreditors (#49) -- COMMENT-ONLY
v17.1-comments: creditFlip caller list NatSpec reordered. No logic changes. **NO REGRESSION.**

### NR-15. BurnieCoinflip._resolveRecycleRebet (#50) -- COMMENT-ONLY
v17.1-comments: NatSpec corrections only. No logic changes. **NO REGRESSION.**

### NR-16. BurnieCoinflip._resolveRecycleBatch (#51) -- COMMENT-ONLY
v17.1-comments: NatSpec corrections only. No logic changes. **NO REGRESSION.**

### NR-17. DegeneretteModule._placeBet (#53) -- COMMENT-ONLY
v17.1-comments: NatSpec corrections only. No logic changes. **NO REGRESSION.**

### NR-18. DegeneretteModule._createCustomTickets (#54) -- COMMENT-ONLY
v17.1-comments: NatSpec corrections only. No logic changes. **NO REGRESSION.**

### NR-19. DegeneretteModule._resolvePayout (#55) -- COMMENT-ONLY
v17.1-comments: NatSpec corrections only. No logic changes. **NO REGRESSION.**

### NR-20. JackpotModule._distributeTicketsToBuckets (#57) -- UNCHANGED
No direct v16.0-v17.1 change to this function. rngBypass threads through downstream _queueTickets calls but this function itself is unchanged. **NO REGRESSION.**

### NR-21. JackpotModule._distributeTicketsToBucket (#58) -- UNCHANGED
No direct v16.0-v17.1 change to this function body (rngBypass threads through _queueTickets call but the function's own logic is unchanged). **NO REGRESSION.**

### NR-22. JackpotModule._creditDgnrsCoinflip (#59) -- UNCHANGED
No v16.0-v17.1 changes to this function. Uses `price` storage variable. **NO REGRESSION.**

### NR-23. JackpotModule._calcDailyCoinBudget (#60) -- UNCHANGED
No v16.0-v17.1 changes to this function. Uses `price` storage variable. **NO REGRESSION.**

### NR-24 through NR-34. Phase 164 Carryover Functions (11 functions) -- SUPERSEDED/SIMPLIFIED

The Phase 164 carryover-specific functions were:
1. `payDailyJackpot` carryover path -- simplified by v16.0 (carryover source selection inlined, 82 lines deleted)
2. `_selectCarryoverSourceOffset` -- DELETED in v16.0 (replaced by inline keccak256 selection)
3. `_highestCarryoverSourceOffset` -- DELETED in v16.0
4. `_budgetToTicketUnits` -- UNCHANGED
5. `_packDailyTicketBudgets` -- UNCHANGED
6. `_unpackDailyTicketBudgets` -- UNCHANGED
7. `payDailyJackpotCoinAndTickets` carryover path -- rngBypass threading only (covered in HR-11)
8. Final-day detection (`isFinalDay`) -- UNCHANGED (formula not modified)
9. Final-day carryover routing -- UNCHANGED
10. `lastPurchaseDay` lifecycle -- UNCHANGED
11. Level increment timing -- UNCHANGED

The deleted functions (_selectCarryoverSourceOffset, _highestCarryoverSourceOffset) were replaced by a simpler inline approach that 179-02 #5 verifies as safe. The replacement handles empty trait buckets gracefully downstream. The remaining Phase 164 functions are either unchanged or covered by HR-10/HR-11 re-validations.

**NO REGRESSION across all 11 Phase 164 functions.**

---

## Cross-Reference Completeness Check

### Contract coverage verification

| Contract | v15.0 Functions | Covered Above |
|----------|-----------------|---------------|
| AdvanceModule | 7 (#1-#7) | HR-01, HR-02, LR-01, LR-02, LR-03, NR-01, NR-02 |
| DegenerusGame | 10 (#8-#17) | HR-16, HR-17, LR-04 through LR-11 |
| MintModule | 4 (#18-#21) | HR-03, LR-12, LR-13, LR-14 |
| MintStreakUtils | 3 (#22-#24) | HR-04, HR-05, LR-15 |
| LootboxModule | 3 (#25-#27) | HR-06, HR-07, LR-16 |
| DegenerusQuests | 18 (#28-#45) | HR-15, LR-17 through LR-25, NR-03 through NR-10 |
| BurnieCoin | 3 (#46-#48) | NR-11, NR-12, NR-13 |
| BurnieCoinflip | 3 (#49-#51) | NR-14, NR-15, NR-16 |
| DegenerusAffiliate | 1 (#52) | HR-08 |
| DegeneretteModule | 3 (#53-#55) | NR-17, NR-18, NR-19 |
| JackpotModule | 7 (#56-#62) | HR-09, HR-10, HR-11, HR-14, NR-20, NR-21, NR-22, NR-23 |
| WhaleModule | 3 (#63-#65) | HR-12, HR-13, HR-14 |
| Phase 164 (carryover) | 11 | NR-24 through NR-34 |
| **Total** | **76** | **76** |

---

## Regression Verdict

**ZERO REGRESSIONS.** All 76 v15.0 adversarial SAFE verdicts are confirmed intact against the current codebase.

The v16.0-v17.1 changes fall into four categories, none of which invalidate any v15.0 SAFE reasoning:

1. **rngBypass parameter threading** (rngBypass-refactor): Mechanical boolean addition replacing `!phaseTransitionActive` guard. Correct values at all call sites (true for internal/jackpot, false for player-initiated).

2. **Storage repack helpers** (v16.0-repack): `_getCurrentPrizePool()` / `_setCurrentPrizePool()` widen/narrow between uint128 and uint256 losslessly. Pool arithmetic unchanged.

3. **Endgame module elimination** (v16.0-endgame-delete): Functions migrated to JackpotModule/WhaleModule/AdvanceModule with identical logic. Delegatecall targets updated. Function signatures preserved.

4. **Affiliate bonus cache** (v17.0-affiliate-cache): Gas optimization caching affiliateBonusPointsBest result in mintPacked_ bits [185-214]. Same values, fewer SLOADs. Fallback to live read when stale.

5. **Comment sweep** (v17.1-comments): NatSpec-only corrections. Zero logic impact.

The original adversarial analyses -- access control, reentrancy, overflow, state corruption, CEI compliance -- remain valid for all 76 functions.
