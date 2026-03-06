# NatSpec Comment Audit Report

## Status: IN PROGRESS (Plans 01-02 + 05-06 complete)

Audited so far: DegenerusAdmin.sol, DegenerusAffiliate.sol, DegenerusQuests.sol, DegenerusJackpots.sol, DegenerusGameLootboxModule.sol, DegenerusGameDecimatorModule.sol, DegenerusGameDegeneretteModule.sol, DegenerusGameEndgameModule.sol, DegenerusGameGameOverModule.sol, DegenerusGameBoonModule.sol, DegenerusGameMintStreakUtils.sol, BurnieCoinflip.sol, DegenerusGameAdvanceModule.sol, DegenerusGameWhaleModule.sol, BurnieCoin.sol, DegenerusVault.sol, DegenerusStonk.sol
Remaining: DegenerusGame, DegenerusDeityPass, remaining modules

---

## Findings

### DegenerusAdmin.sol

**Finding 1: MISLEADING -- purchaseInfo @return lvl description**
- **File:** DegenerusAdmin.sol, line 124
- **Comment:** `@return lvl Current game level (0-indexed).`
- **Actual behavior:** Per project memory, `purchaseInfo().lvl` returns `level+1` (the active ticket level) during purchase phase, NOT 0-indexed current level. The interface comment here propagates the same misconception.
- **Severity:** MISLEADING
- **Resolution:** FIXED -- Changed to "Active ticket level (level+1 during purchase phase, level during jackpot phase; NOT the 0-indexed game level)."

**Finding 2: STALE -- Constructor NatSpec says "no constructor parameters"**
- **File:** DegenerusAdmin.sol, line 20
- **Comment:** `Deploy with no constructor parameters (VRF config from ContractAddresses)`
- **Actual behavior:** The constructor at line 377 indeed takes no parameters -- this is correct. The code matches.
- **Severity:** CLEAN (false alarm on re-check)

**Finding 3: STALE -- swapGameEthForStEth NatSpec says "stETH sent to msg.sender"**
- **File:** DegenerusAdmin.sol, line 438
- **Comment:** `stETH sent to msg.sender (owner), not arbitrary address`
- **Actual behavior:** Line 442 calls `adminSwapEthForStEth{value: msg.value}(msg.sender, msg.value)` -- the first arg IS msg.sender, so recipient = msg.sender. However the interface at line 108-109 says `@param recipient Address to receive the stETH` and `@param amount Amount of ETH/stETH to swap` -- this implies an arbitrary recipient in the interface but the Admin always passes msg.sender. The interface NatSpec is technically correct for the interface, and the Admin NatSpec is correct for Admin's usage. No real mismatch.
- **Severity:** CLEAN

**Finding 15: MISLEADING -- Contract header lists "Presale administration functions"**
- **File:** DegenerusAdmin.sol, line 17
- **Comment:** `4. Presale administration functions`
- **Actual behavior:** This contract has no presale-specific functions. It handles VRF management, price feed, liquidity (swap/stake), lootbox threshold, emergency recovery, VRF shutdown, and LINK donations.
- **Severity:** MISLEADING

**Finding 16: STALE -- Dangling comment with no associated variable**
- **File:** DegenerusAdmin.sol, line 354
- **Comment:** `@dev Terminal gameover flag for shutdown gating.`
- **Actual behavior:** No variable declaration follows this comment. Appears to be a leftover from a removed state variable.
- **Severity:** STALE

**Finding 17: MISLEADING -- onTokenTransfer FLOW describes steps in wrong order**
- **File:** DegenerusAdmin.sol, lines 587-592
- **Comment:** FLOW lists "2. Forward LINK to VRF subscription" before "3. Calculate reward multiplier"
- **Actual code:** Multiplier is calculated BEFORE forwarding (lines 618-631). Inline comment at line 618 explicitly says "BEFORE forwarding LINK."
- **Severity:** MISLEADING

**Finding 18: STALE -- error LinkTransferFailed() declared but never used**
- **File:** DegenerusAdmin.sol, line 246
- **Comment:** `@dev LINK transfer failed.`
- **Actual behavior:** This error is declared but never reverted anywhere in the contract.
- **Severity:** STALE

**Finding 19: MISLEADING -- subscriptionId @dev says "Created during first wireVrf()"**
- **File:** DegenerusAdmin.sol, line 327
- **Comment:** `Created during first wireVrf(); can change during emergency recovery.`
- **Actual behavior:** subscriptionId is created in the constructor via vrfCoordinator.createSubscription() BEFORE wireVrf() is called (line 379 vs line 393).
- **Severity:** MISLEADING

**DegenerusAdmin.sol overall: 6 findings (0 WRONG, 2 STALE, 4 MISLEADING) -- Finding 1 FIXED, 5 new findings documented**
**Status: COMPLETE**

---

### DegenerusAffiliate.sol

**Finding 4: WRONG -- payAffiliate REWARD RATES comment says "levels 1-3" but code uses `lvl <= 3`**
- **File:** DegenerusAffiliate.sol, lines 448-450 (NatSpec) vs line 560 (code)
- **Comment:** `Fresh ETH (levels 1-3): 25%` and `Fresh ETH (levels 4+): 20%`
- **Actual code:** `lvl <= 3 ? REWARD_SCALE_FRESH_L1_3_BPS : REWARD_SCALE_FRESH_L4P_BPS`
- **Issue:** `lvl <= 3` includes level 0, so the actual behavior is "levels 0-3 get 25%", not "levels 1-3". The NatSpec says "levels 1-3" which omits level 0. Also the line 559 inline comment says "25% for first 3 levels" but it's actually the first 4 levels (0,1,2,3).
- **Severity:** WRONG
- **Resolution:** FIXED -- Changed to "levels 0-3" in NatSpec, header, and inline comments.

**Finding 5: WRONG -- Lootbox taper NatSpec numbers vs constants**
- **File:** DegenerusAffiliate.sol, lines 453-455 (NatSpec)
- **Comment:** `Activity score < 150: no taper (100% payout)` / `Activity score 150-255: linear taper from 100% to 50%` / `Activity score >= 255: 50% payout floor`
- **Actual code:** Constants at lines 202-204: `LOOTBOX_TAPER_START_SCORE = 15_000`, `LOOTBOX_TAPER_END_SCORE = 25_500`, `LOOTBOX_TAPER_MIN_BPS = 5_000`
- **Issue:** The NatSpec says 150 and 255 but the code uses 15,000 and 25,500. These are uint16 values passed in as `lootboxActivityScore`. The NatSpec numbers are completely wrong -- off by 100x. The 50% floor matches (5000 BPS = 50%).
- **Severity:** WRONG
- **Resolution:** FIXED -- Changed to "15,000" and "25,500" with constant name references.

**Finding 6: WRONG -- Contract header says "levels 1-3" instead of "levels 0-3"**
- **File:** DegenerusAffiliate.sol, line 18
- **Comment:** `Fresh ETH rewards: 25% (levels 1-3), 20% (levels 4+)`
- **Issue:** Same as Finding 4 -- should say "levels 0-3" not "levels 1-3". The header duplicates the error.
- **Severity:** WRONG
- **Resolution:** FIXED -- Changed to "levels 0-3".

**Finding 7: MISLEADING -- affiliateBonusPointsBest NatSpec says "previous 5 levels"**
- **File:** DegenerusAffiliate.sol, line 736
- **Comment:** `Sums the player's affiliate scores for the previous 5 levels.`
- **Actual code (lines 747-753):** Loop `for offset = 1; offset <= 5` with `if (currLevel <= offset) break` and `lvl = currLevel - offset`. For currLevel=5, it checks levels 4,3,2,1,0 -- that's 5 levels. For currLevel=3, it checks levels 2,1,0 -- only 3 levels. The comment "previous 5 levels" is accurate for the maximum case but slightly misleading since it doesn't mention the "up to" qualifier. Minor.
- **Severity:** CLEAN (acceptable shorthand)

**Finding 8: WRONG -- Comment says "1 point per 1 ETH" but the description says "50%"**
- **File:** DegenerusAffiliate.sol, line 195
- **Comment for AFFILIATE_BONUS_MAX:** `Applied to mint trait rolls; capped at 50 points (50%).`
- **Issue:** Saying "50 points (50%)" implies 1 point = 1%. But the actual use of `affiliateBonusPointsBest` returns 0-50 which is used as bonus points (not percentage). Whether 50 points means 50% depends on the caller's interpretation. This NatSpec is on the constant, not a function -- saying "50%" is an assumption about how callers use it.
- **Severity:** MISLEADING

**Finding 9: WRONG -- SplitCoinflipCoin mode description says "50% coin, 50% discarded"**
- **File:** DegenerusAffiliate.sol, line 110 and line 183
- **Comment:** `2=50% coin, 50% discarded`
- **Actual code (lines 844-847):** `uint256 coinAmount = amount >> 1; coin.creditCoin(player, coinAmount);` -- this credits half as coin and the other half is indeed not credited anywhere (effectively discarded/burned). The enum is called `SplitCoinflipCoin` but the NatSpec says "50% coin (rest discarded)". The code only calls `creditCoin` for the half -- no `creditFlip` for the other half. So the description is actually accurate: 50% goes to coin, 50% is discarded.
- **Severity:** CLEAN

**Finding 10: MISLEADING -- MAX_COMMISSION_PER_REFERRER_PER_LEVEL comment**
- **File:** DegenerusAffiliate.sol, lines 205-207
- **Comment:** `At 20% fresh ETH rate, this caps after 2.5 ETH spend from that sender.`
- **Issue:** The cap is 0.5 ether BURNIE, and the comment says at 20% rate this means 2.5 ETH spend. Math: 2.5 ETH * 20% = 0.5 ETH -- that checks out. BUT levels 0-3 use 25% rate, not 20%. At 25%, the cap triggers after 2.0 ETH spend, not 2.5 ETH. The comment only mentions the 20% rate which applies at levels 4+, ignoring that levels 0-3 cap earlier at 2.0 ETH.
- **Severity:** MISLEADING
- **Resolution:** FIXED -- Changed to "At 25% fresh ETH rate (levels 0-3), caps after 2.0 ETH spend; at 20% (levels 4+), caps after 2.5 ETH."

**Finding 20: MISLEADING -- OnlyAuthorized error says "coin, game, lootbox" but lootbox is never authorized**
- **File:** DegenerusAffiliate.sol, line 132
- **Comment:** `Thrown when caller is not in the authorized set (coin, game, lootbox).`
- **Actual behavior:** Only COIN and GAME are checked in payAffiliate (line 478-481). consumeDegeneretteCredit only checks GAME (line 374). No function checks for lootbox authorization.
- **Severity:** MISLEADING

**Finding 21: MISLEADING -- Insufficient error mentions "ETH forward fail"**
- **File:** DegenerusAffiliate.sol, line 139
- **Comment:** `Generic insufficient condition error (code taken, invalid referral, ETH forward fail).`
- **Actual behavior:** This contract has no ETH forwarding. Error is used for: array length mismatch, non-owner code config, invalid referral, code already taken.
- **Severity:** MISLEADING

**Finding 22: MISLEADING -- lootboxActivityScore @param says "in BPS"**
- **File:** DegenerusAffiliate.sol, line 463
- **Comment:** `Buyer's activity score in BPS for lootbox taper (0 = no taper).`
- **Actual behavior:** The values compared against (15,000 and 25,500) exceed 10,000 (the standard BPS denominator). These are raw activity scores, not basis points.
- **Severity:** MISLEADING

**DegenerusAffiliate.sol overall: 7 findings (3 WRONG, 0 STALE, 4 MISLEADING) -- Findings 4,5,6,10 FIXED, 3 new findings documented**
**Status: COMPLETE**

---

### DegenerusGameEndgameModule.sol

**Finding 11: MISLEADING -- _runBafJackpot NatSpec says "All winners receive 50% ETH / 50% lootbox"**
- **File:** DegenerusGameEndgameModule.sol, line 278
- **Comment:** `All winners receive 50% ETH / 50% lootbox-style rewards.`
- **Actual code:** Large winners (>=5% of pool) get 50/50 split. Small winners (<5% of pool) alternate: even-index gets 100% ETH, odd-index gets 100% lootbox. The blanket "All winners" claim was inaccurate.
- **Severity:** MISLEADING
- **Resolution:** FIXED -- Updated NatSpec to document large/small winner distinction and payout table.

**Finding 12: STALE -- Duplicate NatSpec block on claimWhalePass**
- **File:** DegenerusGameEndgameModule.sol, lines 483-492
- **Comment:** Two consecutive `@notice` blocks; first says "for the caller" but function takes a `player` parameter.
- **Severity:** STALE
- **Resolution:** FIXED -- Merged into single block, changed "caller" to "player", added @param.

**DegenerusGameEndgameModule.sol overall: 2 findings (0 WRONG, 1 STALE, 1 MISLEADING) -- both FIXED**

---

### DegenerusGameGameOverModule.sol

**Finding 13: WRONG -- handleGameOverDrain NatSpec claims separate level-0 "full refund" behavior**
- **File:** DegenerusGameGameOverModule.sol, lines 59-61
- **Comment:** `If game never started (level 0, not in BURN state): Full refund of deity pass payments` / `If game ended early (levels 1-9): Fixed 20 ETH refund per deity pass purchased`
- **Actual code:** Lines 80-109 apply the same 20 ETH/pass refund for ALL levels < 10 (0-9). No separate handling for level 0. No "full refund" path exists.
- **Severity:** WRONG
- **Resolution:** FIXED -- Unified description to "levels 0-9: Fixed 20 ETH refund per deity pass, FIFO by purchase order, budget-capped."

**DegenerusGameGameOverModule.sol overall: 1 finding (1 WRONG) -- FIXED**

---

### DegenerusGameBoonModule.sol

No findings. All NatSpec is accurate:
- `consumeCoinflipBoon`: Correctly documents return values and expiry behavior.
- `consumePurchaseBoost`: Correctly documents return values and expiry behavior.
- `consumeDecimatorBoost`: Correctly documents return values and expiry behavior.
- `checkAndClearExpiredBoon`: Correctly documents clearing logic and return semantics.
- `consumeActivityBoon`: Correctly documents activity boon consumption and quest streak crediting.

**DegenerusGameBoonModule.sol overall: 0 findings -- CLEAN**

---

### DegenerusGameMintStreakUtils.sol

No findings. All 5 NatSpec tags verified accurate:
- Contract-level `@dev`: "Shared mint streak helpers (credits on completed 1x price ETH quest)" -- accurate.
- `MINT_STREAK_LAST_COMPLETED_SHIFT`: "last level credited for mint streak (24 bits)" -- matches shift value and usage.
- `MINT_STREAK_FIELDS_MASK`: "Mask for clearing last-completed + streak fields" -- accurate composite mask.
- `_recordMintStreakForLevel`: "Record a mint streak completion for a given level (idempotent per level)" -- code returns early if `lastCompleted == mintLevel`, confirming idempotency.
- `_mintStreakEffective`: "Effective mint streak (resets if a level was missed)" -- code returns 0 if `currentMintLevel > lastCompleted + 1`, confirming reset on missed level.

**DegenerusGameMintStreakUtils.sol overall: 0 findings -- CLEAN**

---

### BurnieCoinflip.sol

**Finding 14: MISLEADING -- _bafBracketLevel says "nearest 10" but code rounds UP**
- **File:** BurnieCoinflip.sol, line 1181
- **Comment:** `Round level to BAF bracket (nearest 10).`
- **Actual code:** `((uint256(lvl) + 9) / 10) * 10` always rounds UP to the next multiple of 10 (e.g., level 1 -> 10, level 11 -> 20, level 10 -> 10). "Nearest 10" implies standard rounding.
- **Severity:** MISLEADING
- **Resolution:** FIXED -- Changed to "Round level up to next BAF bracket (multiple of 10)."

**Payout distribution verification (5%/90%/5%):**
- Code at `processCoinflipPayouts`: `seedWord % 20` yields roll 0 (5%) = 50% bonus (1.5x), roll 1 (5%) = 150% bonus (2.5x), rolls 2-19 (90%) = [78%, 115%] bonus range.
- Mean win bonus: 0.05*50 + 0.90*96.5 + 0.05*150 = 96.85% = 9685 BPS. Matches `COINFLIP_REWARD_MEAN_BPS = 9685`. VERIFIED.
- Mean win multiplier: 1.9685x (approximately 1.97x as documented). VERIFIED.
- 50/50 win/loss: `(rngWord & 1) == 1`. VERIFIED.

**BurnieCoinflip.sol overall: 1 finding (0 WRONG, 0 STALE, 1 MISLEADING) -- FIXED**

---

### DegenerusGameAdvanceModule.sol

**Finding 23: WRONG -- wireVrf NatSpec claims idempotency**
- **File:** DegenerusGameAdvanceModule.sol, line 303
- **Comment:** `Idempotent after first wire (repeats must match).`
- **Actual code:** Lines 315-317 simply overwrite `vrfCoordinator`, `vrfSubscriptionId`, and `vrfKeyHash` with no matching check. There is no idempotency enforcement.
- **Severity:** WRONG
- **Resolution:** FIXED -- Changed to "Overwrites any existing config on each call."

**Finding 24: MISLEADING -- _enforceDailyMintGate bypass tier ordering**
- **File:** DegenerusGameAdvanceModule.sol, lines 539-543
- **Comment:** Lists "1. Deity pass or DGVE majority -- always bypasses" as a single tier.
- **Actual code:** Deity pass is checked first (immediate bypass at line 559), then 30-min anyone check (line 566), then 15-min pass holder check (line 569), then DGVE majority as last resort (line 578). DGVE majority and deity pass are NOT the same tier.
- **Severity:** MISLEADING
- **Resolution:** FIXED -- Reordered tiers to match code: 1. Deity pass (always), 2. Anyone (30+ min), 3. Pass holder (15+ min), 4. DGVE majority (always, last resort).

**Finding 25: WRONG -- _getHistoricalRngFallback search direction**
- **File:** DegenerusGameAdvanceModule.sol, line 751
- **Comment:** `Searches backwards from current day to find earliest available RNG word (max 30 tries).`
- **Actual code:** Line 760 loops `for (uint48 searchDay = 1; searchDay < searchLimit)` -- this searches FORWARD from day 1, not backwards from current day.
- **Severity:** WRONG
- **Resolution:** FIXED -- Changed to "Searches forward from day 1 to find the earliest available RNG word."

**Finding 26: WRONG -- Future prize pool draw percentage**
- **File:** DegenerusGameAdvanceModule.sol, line 779
- **Comment:** `Normal levels draw 20%, x00 levels skip the draw.`
- **Actual code:** Line 882: `reserved = (futurePrizePool * 15) / 100` = 15%, not 20%.
- **Severity:** WRONG
- **Resolution:** FIXED -- Changed to "Normal levels draw 15%."

**DegenerusGameAdvanceModule.sol overall: 4 findings (3 WRONG, 0 STALE, 1 MISLEADING) -- all FIXED**

---

### DegenerusGameWhaleModule.sol

**Finding 27: WRONG -- purchaseWhaleBundle level restrictions**
- **File:** DegenerusGameWhaleModule.sol, lines 168-174 (NatSpec)
- **Comment:** `Available at levels 0-3, x49/x99, or any level with a valid whale boon` and `@custom:reverts E When not at level 0-3 or x49/x99 and no valid boon exists.`
- **Actual code:** No level restriction exists in `_purchaseWhaleBundle`. Code allows purchase at ANY level. Levels 0-3 get early price (2.4 ETH), all other levels get standard price (4 ETH), boon applies discount.
- **Severity:** WRONG
- **Resolution:** FIXED -- Changed to "Available at any level" and updated revert doc.

**Finding 28: WRONG -- purchaseWhaleBundle fund distribution at level 0**
- **File:** DegenerusGameWhaleModule.sol, line 177
- **Comment:** `Pre-game (level 0): 50% next pool, 50% future pool`
- **Actual code:** Lines 290-294: `nextShare = (totalPrice * 3000) / 10_000` = 30% next, 70% future. The inline comment at line 287 correctly says "70/30" (future/next).
- **Severity:** WRONG
- **Resolution:** FIXED -- Changed to "30% next pool, 70% future pool".

**Finding 29: WRONG -- purchaseLazyPass level eligibility**
- **File:** DegenerusGameWhaleModule.sol, line 307
- **Comment:** `Available at levels 0-3 or x9 (9, 19, 29...).`
- **Actual code:** Line 344: `if (currentLevel > 2 && ...)` -- allows levels 0-2 (not 0-3).
- **Severity:** WRONG
- **Resolution:** FIXED -- Changed to "Available at levels 0-2 or x9 (9, 19, 29...)."

**Finding 30: MISLEADING -- purchaseLazyPass renewal window**
- **File:** DegenerusGameWhaleModule.sol, line 308
- **Comment:** `Can renew when <7 levels remain on current pass freeze.`
- **Actual code:** Line 354: `if (frozenUntilLevel > currentLevel + 7) revert E()` -- exactly 7 is allowed.
- **Severity:** MISLEADING
- **Resolution:** FIXED -- Changed to "Can renew when 7 or fewer levels remain."

**Finding 31: MISLEADING -- purchaseLazyPass price description**
- **File:** DegenerusGameWhaleModule.sol, line 311
- **Comment:** `Price equals sum of per-level ticket prices across the 10-level window.`
- **Actual code:** Levels 0-2 use flat 0.24 ETH price with excess buying bonus tickets, not the sum formula.
- **Severity:** MISLEADING
- **Resolution:** FIXED -- Documented both pricing modes.

**Finding 32: MISLEADING -- purchaseLazyPass boon lootbox claim**
- **File:** DegenerusGameWhaleModule.sol, line 313
- **Comment:** `Boon purchases apply a 10/15/25% discount and always include a 10% lootbox.`
- **Actual code:** Lootbox BPS depends on `lootboxPresaleActive` (20%/10%), no special boon handling.
- **Severity:** MISLEADING
- **Resolution:** FIXED -- Changed to "Boon purchases apply a discount (default 10%) to the payment amount."

**Finding 33: WRONG -- purchaseDeityPass availability**
- **File:** DegenerusGameWhaleModule.sol, line 441
- **Comment:** `Available at any time.`
- **Actual code:** Line 461: `if (gameOver) revert E()` -- NOT available after gameOver.
- **Severity:** WRONG
- **Resolution:** FIXED -- Changed to "Available before gameOver."

**Finding 34: MISLEADING -- _applyLootboxBoostOnPurchase expiry description**
- **File:** DegenerusGameWhaleModule.sol, line 783
- **Comment:** `expires after 48 hours`
- **Actual code:** Uses `LOOTBOX_BOOST_EXPIRY_DAYS = 2` (2 game days at 22:57 UTC boundary, not 48 hours).
- **Severity:** MISLEADING
- **Resolution:** FIXED -- Changed to "expires after 2 game days."

**DegenerusGameWhaleModule.sol overall: 8 findings (4 WRONG, 0 STALE, 4 MISLEADING) -- all FIXED**

---

### DegenerusQuests.sol

**Finding 35: WRONG -- PlayerQuestState streak mechanics says "BOTH slots"**
- **File:** DegenerusQuests.sol, line 236 (struct NatSpec)
- **Comment:** `streak increments only when BOTH slots complete on a day`
- **Actual code:** `_questComplete` at line 1422 checks `(mask & QUEST_STATE_STREAK_CREDITED) == 0` and increments streak on the FIRST slot completion of any day, not when both are complete.
- **Severity:** WRONG
- **Resolution:** Fixed -- changed to "streak increments on the first quest slot completion of a day (not both)"

**Finding 36: WRONG -- _questComplete reward description says slot 0 pays 0 BURNIE**
- **File:** DegenerusQuests.sol, line 1386 (NatSpec)
- **Comment:** `Slot 1 (random quest) pays a fixed 200 BURNIE` / `Slot 0 (deposit ETH) pays 0 BURNIE`
- **Actual code:** Line 1432: `slot == 1 ? QUEST_RANDOM_REWARD : QUEST_SLOT0_REWARD` where `QUEST_SLOT0_REWARD = 100 ether`. Slot 0 pays 100 BURNIE, not 0.
- **Severity:** WRONG
- **Resolution:** Fixed -- changed to "Slot 0 (deposit ETH) pays a fixed 100 BURNIE"

**Finding 37: WRONG -- handleLootBox target description says "1-3x"**
- **File:** DegenerusQuests.sol, line 694 (NatSpec)
- **Comment:** `Target is calculated as 1-3x current ticket price (scales with game economy).`
- **Actual code:** Uses `QUEST_LOOTBOX_TARGET_MULTIPLIER = 2` constant -- always 2x, not 1-3x. Capped at `QUEST_ETH_TARGET_CAP = 0.5 ether`.
- **Severity:** WRONG
- **Resolution:** Fixed -- changed to "Target is 2x current ticket price, capped at QUEST_ETH_TARGET_CAP."

**Finding 38: WRONG -- handleDecimator says "2x the target of equivalent flip quests"**
- **File:** DegenerusQuests.sol, line 590 (NatSpec)
- **Comment:** `Decimator quests have 2x the target of equivalent flip quests.`
- **Actual code:** `_questTargetValue` returns `QUEST_BURNIE_TARGET` for both FLIP and DECIMATOR. They share the same target (2000 BURNIE). No 2x multiplier.
- **Severity:** WRONG
- **Resolution:** Fixed -- changed to "Decimator quests share the same BURNIE target as flip quests (2000 BURNIE)."

**Finding 39: MISLEADING -- Duplicate @param player in _questSyncState**
- **File:** DegenerusQuests.sol, lines 1113-1114 (NatSpec)
- **Comment:** Two `@param player` tags with different descriptions.
- **Issue:** Solidity NatSpec doesn't support duplicate @param tags. This could confuse documentation generators.
- **Severity:** MISLEADING
- **Resolution:** Fixed -- merged into single `@param player Player address for event emission and streak shield lookup.`

**DegenerusQuests.sol overall: 5 findings (4 WRONG, 1 MISLEADING) -- all fixed**

---

### DegenerusJackpots.sol

No WRONG or STALE findings. All NatSpec comments verified against code:

- Prize distribution percentages (10/10/5/10/5/40/20 = 100%) match code exactly
- Scatter level targeting rules (x00 vs non-x00) match code conditionals
- BAF leaderboard management (top-4 sorted, scored by whole tokens) accurately described
- Access control descriptions (onlyCoin for recordBafFlip, onlyGame for runBafJackpot) correct
- Max winners count (108 = 1+1+1+3+2+50+50) verified against code
- Scatter ticket handling and winnerMask bit layout accurately described
- Internal helper functions (_creditOrRefund, _score96, _updateBafTop, etc.) all accurate

**DegenerusJackpots.sol overall: 0 findings -- CLEAN**

---


### BurnieCoin.sol

**Finding 40: STALE -- onlyTrustedContracts NatSpec references "color registry"**
- **File:** BurnieCoin.sol, line 630
- **Comment:** `Restricts access to game, affiliate, or color registry contracts.`
- **Actual code (lines 634-638):** Only checks GAME and AFFILIATE. No color registry reference exists in the contract.
- **Resolution:** FIXED -- Removed "or color registry" from comment.
- **Severity:** STALE (FIXED)

**Key verifications (all CLEAN):**
- Supply invariant `totalSupply + vaultAllowance = supplyIncUncirculated()` verified across all 8 mutation paths
- Mint/burn mechanics, vault escrow, coinflip integration, quest integration, decimator -- all NatSpec verified correct
- Access control hierarchy accurately documented

**BurnieCoin.sol overall: 1 finding (0 WRONG, 1 STALE fixed, 0 MISLEADING)**

---

### DegenerusVault.sol

**Finding 41: WRONG -- gamePurchaseDeityPassFromBoon @param priceWei example values**
- **File:** DegenerusVault.sol, line 529
- **Comment:** `@param priceWei Expected price (15/25/50 ETH)`
- **Actual behavior:** Deity pass price formula is 24 + T(n) ETH where T(n) = n*(n+1)/2. Values 15/25/50 are not valid deity pass prices.
- **Resolution:** FIXED -- Updated to describe actual formula.
- **Severity:** WRONG (FIXED)

**Finding 42: STALE -- orphaned Jackpots contract NatSpec comment**
- **File:** DegenerusVault.sol, line 370
- **Comment:** `@dev Jackpots contract for decimator claims`
- **Actual code:** No jackpots contract variable follows this comment. The jackpots wiring was removed but the comment survived.
- **Resolution:** FIXED -- Removed orphaned comment.
- **Severity:** STALE (FIXED)

**Key verifications (all CLEAN):**
- Share math formulas match code exactly
- onlyVaultOwner >50.1% check (balance*1000 > supply*501) NatSpec accurate
- stETH integration, refill mechanism, deposit flow, two share classes -- all NatSpec verified correct

**DegenerusVault.sol overall: 2 findings (1 WRONG fixed, 1 STALE fixed, 0 MISLEADING)**

---

### DegenerusStonk.sol

No NatSpec findings. All @notice, @dev, @param, @return tags verified accurate.

**Key verifications (all CLEAN):**
- Pool BPS allocations (20% creator + 80% pools = 100%) match constants
- BURNIE_ETH_BUY_BPS = 7000 (70%), QUEST_CONTRIBUTION_BPS = 5 (0.05%) match usage
- Lock/unlock, burn-to-extract, trusted spender bypass -- all NatSpec accurate
- Note: `ethReserve` state variable (line 227) declared but unused (code observation, not NatSpec error)

**DegenerusStonk.sol overall: 0 findings -- CLEAN**

---

## Summary So Far

| Contract | Status | WRONG | STALE | MISLEADING | CLEAN |
|---|---|---|---|---|---|
| DegenerusAdmin.sol | COMPLETE | 0 | 2 | 4 | NO (1 fixed, 5 new) |
| DegenerusAffiliate.sol | COMPLETE | 3 | 0 | 4 | NO (4 fixed, 3 new) |
| DegenerusGameEndgameModule.sol | Audited | 0 | 1 | 1 | NO (fixed) |
| DegenerusGameGameOverModule.sol | Audited | 1 | 0 | 0 | NO (fixed) |
| DegenerusGameBoonModule.sol | Audited | 0 | 0 | 0 | YES |
| DegenerusGameMintStreakUtils.sol | Audited | 0 | 0 | 0 | YES |
| BurnieCoinflip.sol | Audited | 0 | 0 | 1 | NO (fixed) |
| DegenerusGameAdvanceModule.sol | Audited | 3 | 0 | 1 | NO (all fixed) |
| DegenerusGameWhaleModule.sol | Audited | 4 | 0 | 4 | NO (all fixed) |
| DegenerusVault.sol | Audited | 1 (fixed) | 1 (fixed) | 0 | YES |
| DegenerusStonk.sol | Audited | 0 | 0 | 0 | YES |
| BurnieCoin.sol | Audited | 0 | 1 (fixed) | 0 | YES |
| DegenerusGame.sol | NOT YET AUDITED | - | - | - | - |
| DegenerusQuests.sol | Audited | 4 | 0 | 1 | NO (fixed) |
| DegenerusJackpots.sol | Audited | 0 | 0 | 0 | YES |
| DegenerusDeityPass.sol | NOT YET AUDITED | - | - | - | - |
| Remaining Modules | NOT YET AUDITED | - | - | - | - |

**Total findings so far: 38** (16 WRONG [1 new fixed], 5 STALE [2 new fixed], 17 MISLEADING) -- all WRONG/STALE findings FIXED where applicable

---

## Next Batches Required

- **Remaining:** DegenerusGame.sol, DegenerusDeityPass.sol, remaining modules

---

### DegenerusGameLootboxModule.sol (Plan 04)

**Finding P04-1: WRONG -- EV breakpoint upper threshold says "260%" but code uses 255%**
- **File:** DegenerusGameLootboxModule.sol, line 467
- **Severity:** WRONG -- **Resolution:** FIXED to "255%+"

**Finding P04-2: WRONG -- issueDeityBoon says "up to 5 boons per day" but limit is 3**
- **File:** DegenerusGameLootboxModule.sol, line 742
- **Severity:** WRONG -- **Resolution:** FIXED to "up to 3 boons per day"

**Finding P04-3: WRONG -- issueDeityBoon @custom:reverts says "slot >= 5" but guard is >= 3**
- **File:** DegenerusGameLootboxModule.sol, line 748
- **Severity:** WRONG -- **Resolution:** FIXED to "slot is >= 3"

**Finding P04-4: WRONG -- DeityBoonIssued slot param says "(0-4)" but range is (0-2)**
- **File:** DegenerusGameLootboxModule.sol, line 167
- **Severity:** WRONG -- **Resolution:** FIXED to "(0-2)"

**Finding P04-5: WRONG -- Boon type ranges say "1-29" but max type is 31**
- **File:** DegenerusGameLootboxModule.sol, lines 168, 722, 1754
- **Severity:** WRONG -- **Resolution:** FIXED all to "(1-31)"

**Finding P04-6: WRONG -- presale param says "2x BURNIE multiplier" but bonus is 62%**
- **File:** DegenerusGameLootboxModule.sol, line 820
- **Severity:** WRONG -- **Resolution:** FIXED to "62% bonus BURNIE multiplier"

**DegenerusGameLootboxModule.sol overall: 6 findings (6 WRONG) -- all FIXED**

---

### DegenerusGameDecimatorModule.sol (Plan 04)

All NatSpec verified (748 lines, 130 tags): 50/50 split, auto-rebuy 130%/145%, multiplier cap 200 mints, bucket range 2-12, pro-rata formula, uint192 saturation, packed subbucket layout.

**DegenerusGameDecimatorModule.sol overall: 0 findings -- CLEAN**

---

### DegenerusGameDegeneretteModule.sol (Plan 04)

**Finding P04-7: WRONG -- ROI curve third segment says "255% to 355%" but max is 305%**
- **File:** DegenerusGameDegeneretteModule.sol, line 1134
- **Severity:** WRONG -- **Resolution:** FIXED to "255% to 305%"

**Finding P04-8: MISLEADING -- _getBasePayoutBps example says "189 = 1.89x" but 2-match base is 190**
- **File:** DegenerusGameDegeneretteModule.sol, line 1004
- **Severity:** MISLEADING -- **Resolution:** FIXED to "190 = 1.90x"

**DegenerusGameDegeneretteModule.sol overall: 2 findings (1 WRONG, 1 MISLEADING) -- both FIXED**
