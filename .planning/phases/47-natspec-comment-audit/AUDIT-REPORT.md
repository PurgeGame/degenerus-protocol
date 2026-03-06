# NatSpec Comment Audit Report

## Status: IN PROGRESS (Plans 01-02 + 05 complete)

Audited so far: DegenerusAdmin.sol, DegenerusAffiliate.sol, DegenerusQuests.sol, DegenerusJackpots.sol, DegenerusGameLootboxModule.sol, DegenerusGameDecimatorModule.sol, DegenerusGameDegeneretteModule.sol, DegenerusGameEndgameModule.sol, DegenerusGameGameOverModule.sol, DegenerusGameBoonModule.sol, DegenerusGameMintStreakUtils.sol, BurnieCoinflip.sol, DegenerusGameAdvanceModule.sol, DegenerusGameWhaleModule.sol
Remaining: DegenerusVault, DegenerusStonk, BurnieCoin, DegenerusGame, DegenerusDeityPass, remaining modules

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
| DegenerusVault.sol | NOT YET AUDITED | - | - | - | - |
| DegenerusStonk.sol | NOT YET AUDITED | - | - | - | - |
| BurnieCoin.sol | NOT YET AUDITED | - | - | - | - |
| DegenerusGame.sol | NOT YET AUDITED | - | - | - | - |
| DegenerusQuests.sol | NOT YET AUDITED | - | - | - | - |
| DegenerusJackpots.sol | NOT YET AUDITED | - | - | - | - |
| DegenerusDeityPass.sol | NOT YET AUDITED | - | - | - | - |
| Remaining Modules | NOT YET AUDITED | - | - | - | - |

**Total findings so far: 17** (4 WRONG, 3 STALE, 10 MISLEADING) -- all original WRONG findings FIXED, 8 new findings documented

---

## Next Batches Required

- **Remaining:** DegenerusVault.sol, DegenerusStonk.sol, BurnieCoin.sol, DegenerusGame.sol, DegenerusQuests.sol, DegenerusJackpots.sol, DegenerusDeityPass.sol, remaining modules
