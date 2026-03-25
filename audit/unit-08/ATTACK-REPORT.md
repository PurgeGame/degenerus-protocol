# Unit 8: Degenerette Betting -- Attack Report

**Agent:** Mad Genius
**Target:** DegenerusGameDegeneretteModule.sol (1,179 lines)
**Methodology:** Per ULTIMATE-AUDIT-DESIGN.md -- full call tree, storage write map, cached-local-vs-storage check, 10-angle attack analysis per function.

---

## B1: DegeneretteModule::placeFullTicketBets (lines 388-404)

### Call Tree
```
placeFullTicketBets(player, currency, amountPerTicket, ticketCount, customTicket, heroQuadrant)  [L388]
  -> _resolvePlayer(player)  [L396, private view L160]
       -> if player == address(0): return msg.sender  [L161]
       -> if player != msg.sender: _requireApproved(player)  [L162-163]
            -> reads operatorApprovals[player][msg.sender]  [L151]
            -> reverts NotApproved() if false  [L152]
  -> _placeFullTicketBets(resolved_player, currency, amountPerTicket, ticketCount, customTicket, heroQuadrant)  [L396-403, private L430]
       -> _placeFullTicketBetsCore(...)  [L438-445, private L462]
            -> validates ticketCount (0 < count <= 10)  [L470]
            -> validates amountPerTicket != 0  [L471]
            -> reads lootboxRngIndex  [L473]
            -> reads lootboxRngWordByIndex[index], requires == 0 (RNG not yet fulfilled)  [L475]
            -> _validateMinBet(currency, amountPerTicket)  [L477, pure L528]
            -> computes totalBet = amountPerTicket * ticketCount  [L479]
            -> _playerActivityScoreInternal(player)  [L480, view L1005]
                 -> reads deityPassCount[player]  [L1010]
                 -> reads mintPacked_[player]  [L1011]
                 -> reads level  [L1016]
                 -> _mintStreakEffective(player, level+1)  [L1015, MintStreakUtils L49]
                      -> reads mintPacked_[player]  [L53]
                 -> external: questView.playerQuestStates(player)  [L1054]
                 -> external: affiliate.affiliateBonusPointsBest(level, player)  [L1062]
            -> _packFullTicketBet(...)  [L483-487, pure L764]
            -> reads degeneretteBetNonce[player]  [L489]
            -> WRITES degeneretteBetNonce[player] = nonce+1  [L491]
            -> WRITES degeneretteBets[player][nonce] = packed  [L493]
            -> emit BetPlaced  [L494]
            -> if currency == ETH:
                 -> if heroQuadrant < 4:  [L499]
                      -> reads _simulatedDayIndex()  [L500]
                      -> computes heroSymbol from customTicket  [L501]
                      -> computes wagerUnit = totalBet / 1e12  [L502]
                      -> reads dailyHeroWagers[day][heroQuadrant]  [L504]
                      -> WRITES dailyHeroWagers[day][heroQuadrant] (packed update)  [L510]
                 -> reads level  [L515]
                 -> reads playerDegeneretteEthWagered[player][level]  [L516]
                 -> WRITES playerDegeneretteEthWagered[player][level]  [L517]
                 -> reads topDegeneretteByLevel[level]  [L518]
                 -> conditionally WRITES topDegeneretteByLevel[level]  [L522]
       -> _collectBetFunds(player, currency, totalBet, msg.value)  [L447-451, private L541]
            -> if ETH:
                 -> if ethPaid > totalBet: revert  [L549]
                 -> if ethPaid < totalBet:
                      -> reads claimableWinnings[player]  [L552]
                      -> if claimableWinnings <= fromClaimable: revert  [L552]
                      -> WRITES claimableWinnings[player] -= fromClaimable  [L553]
                      -> WRITES claimablePool -= fromClaimable  [L554]
                 -> if prizePoolFrozen:
                      -> reads _getPendingPools()  [L559]
                      -> WRITES _setPendingPools(pNext, pFuture + totalBet)  [L560]
                 -> else:
                      -> reads _getPrizePools()  [L562]
                      -> WRITES _setPrizePools(next, future + totalBet)  [L563]
                 -> WRITES lootboxRngPendingEth += totalBet  [L565]
            -> if BURNIE:
                 -> external: coin.burnCoin(player, totalBet)  [L569]
                 -> WRITES lootboxRngPendingBurnie += totalBet  [L570]
            -> if WWXRP:
                 -> external: wwxrp.burnForGame(player, totalBet)  [L572]
       -> if currency == ETH:
            -> external: coin.notifyQuestDegenerette(player, totalBet, true)  [L456]
       -> if currency == BURNIE:
            -> external: coin.notifyQuestDegenerette(player, totalBet, false)  [L458]
```

### Storage Writes (Full Tree)
| Variable | Location | Condition |
|----------|----------|-----------|
| `degeneretteBetNonce[player]` | L491 | Always |
| `degeneretteBets[player][nonce]` | L493 | Always |
| `dailyHeroWagers[day][quadrant]` | L510 | ETH + heroQuadrant < 4 + wagerUnit > 0 |
| `playerDegeneretteEthWagered[player][level]` | L517 | ETH only |
| `topDegeneretteByLevel[level]` | L522 | ETH + playerScaled > topAmount |
| `claimableWinnings[player]` | L553 | ETH + ethPaid < totalBet |
| `claimablePool` | L554 | ETH + ethPaid < totalBet |
| `prizePoolsPacked` | L563 (via _setPrizePools) | ETH + !prizePoolFrozen |
| `pendingPoolsPacked` | L560 (via _setPendingPools) | ETH + prizePoolFrozen |
| `lootboxRngPendingEth` | L565 | ETH |
| `lootboxRngPendingBurnie` | L570 | BURNIE |

### Cached-Local-vs-Storage Check

| Ancestor Local | Descendant Write | Verdict |
|----------------|------------------|---------|
| `index` (L473, from lootboxRngIndex) | No descendant writes lootboxRngIndex | SAFE |
| `totalBet` (L479, computed) | N/A (computed from parameters) | SAFE |
| `activityScore` (L480) | No descendant writes mintPacked_/deityPassCount/level | SAFE: all reads happen before any writes |
| `packed` (L483, computed) | N/A (pure computation) | SAFE |
| `nonce` (L489, from degeneretteBetNonce) | degeneretteBetNonce written at L491 | SAFE: nonce incremented THEN written. Stale local `nonce` is the pre-increment value used as the bet key, which is correct |
| No local cache of prizePoolsPacked | _setPrizePools writes prizePoolsPacked at L563 | SAFE: fresh read at L562 immediately before write at L563 |
| No local cache of claimableWinnings | Written at L553 | SAFE: fresh read at L552 immediately before write at L553 |

**Verdict: NO BAF-CLASS CACHE OVERWRITES in B1.**

### Attack Analysis

**1. State Coherence (BAF Pattern):** SAFE. All storage reads are immediately followed by writes without intervening calls that could modify the same slot. The activity score computation (D13) is view-only -- no state changes. Fund collection (C3) does fresh reads for every storage variable before writing. No ancestor caches a value that a descendant later overwrites.

**2. Access Control:** SAFE. Entry is via delegatecall from Game router, which provides the `msg.sender` context. `_resolvePlayer` checks `operatorApprovals[player][msg.sender]` if player != msg.sender. An unapproved third party cannot place bets on behalf of a player. Address(0) defaults to msg.sender.

**3. RNG Manipulation:** SAFE for bet placement. The function REQUIRES `lootboxRngWordByIndex[index] == 0` at L475 -- the RNG word is not yet fulfilled. The bet is placed before the RNG word exists. Player's ticket choice is committed before the random outcome is determined. Per backward-trace methodology: the RNG word will be set later by VRF fulfillment. No player-controllable state that changes between VRF request and fulfillment affects the bet outcome -- the bet parameters (ticket, amount, activity score) are all locked at placement time.

**4. Cross-Contract State Desync:** SAFE. External calls (`coin.burnCoin`, `wwxrp.burnForGame`, `coin.notifyQuestDegenerette`) are called AFTER all storage writes for the bet (nonce, bet data, hero wagers, leaderboard, pool accounting). If these external calls revert, the entire transaction reverts. No inconsistent state.

**5. Edge Cases:**

- **ticketCount = 0:** Caught at L470 (`revert InvalidBet()`). SAFE.
- **amountPerTicket = 0:** Caught at L471 (`revert InvalidBet()`). SAFE.
- **lootboxRngIndex = 0:** Caught at L474 (`revert E()`). SAFE (no index 0 bets).
- **RNG already fulfilled:** Caught at L475 (`revert RngNotReady()`). SAFE.
- **Max values:** `amountPerTicket` is uint128 (max ~3.4e38). `ticketCount` max 10. `totalBet` max ~3.4e39 which fits in uint256. No overflow.
- **Hero wager overflow at L508:** Capped at 0xFFFFFFFF. SAFE.

**6. Conditional Paths:**

- **ETH with full msg.value:** `ethPaid >= totalBet` case. If `ethPaid == totalBet`, the claimable deduction is skipped (L550 check `ethPaid < totalBet` is false). If `ethPaid > totalBet`, reverts at L549. SAFE: no excess ETH handling needed because the router handles msg.value forwarding.
- **ETH with partial claimable pull:** INVESTIGATE. See Finding F-01 below.
- **Frozen pools:** ETH bets route to pendingPoolsPacked instead of prizePoolsPacked. Both paths read-then-write atomically. SAFE.

**7. Economic Attacks:** SAFE. Bet placement is commitment. No MEV advantage from front-running a bet placement -- the outcome depends on future RNG fulfillment.

**8. Griefing:** SAFE. Each bet placement is independent. One player's bet cannot corrupt another's state.

**9. Ordering/Sequencing:** SAFE. Bet nonce is monotonically incremented. Cannot replay or reorder bet IDs.

**10. Silent Failures:**

- **WWXRP path does NOT update lootboxRngPendingEth or lootboxRngPendingBurnie:** INVESTIGATE. See Finding F-02 below.
- **Quest notification only for ETH and BURNIE, not WWXRP (L455-459):** By design -- WWXRP bets don't count toward quests. Not a bug.

### Findings

**F-01: ETH Claimable Pull Uses Strict Inequality (`<=`) Instead of `<`**
- **Location:** L552
- **Code:** `if (claimableWinnings[player] <= fromClaimable) revert InvalidBet();`
- **Issue:** If a player has exactly `fromClaimable` wei in claimableWinnings, the bet reverts. The player cannot use their EXACT full claimable balance for a bet. They need at least 1 wei more than the shortfall.
- **Example:** Player has 0.1 ETH claimable, sends 0 ETH msg.value, tries to place 0.1 ETH bet. `fromClaimable = 0.1 ETH`. `claimableWinnings[player] = 0.1 ETH`. `0.1 <= 0.1` is TRUE -> reverts.
- **Impact:** Minor UX issue. Player must send at least 1 wei or have 1 wei more claimable than needed.
- **Verdict:** INVESTIGATE (LOW) -- likely intentional to prevent zero-balance claimable (avoids dust), but the `<=` vs `<` distinction affects the exact-amount edge case.

**F-02: WWXRP Bets Do Not Track Pending Amounts**
- **Location:** L571-573
- **Code:** WWXRP path only calls `wwxrp.burnForGame(player, totalBet)` with no `lootboxRngPendingWwxrp` tracking.
- **Context:** ETH bets track `lootboxRngPendingEth += totalBet` (L565). BURNIE bets track `lootboxRngPendingBurnie += totalBet` (L570). WWXRP bets have no equivalent tracking.
- **Analysis:** The `lootboxRngPending*` variables are used by AdvanceModule to determine when to request lootbox RNG. WWXRP bets are burned externally (no ETH or BURNIE held by the game contract), and WWXRP payouts are minted (not paid from a pool). The pending tracking is only needed for currencies that affect the game's internal pool solvency.
- **Verdict:** SAFE -- by design. WWXRP is a burn/mint token; no pool solvency tracking needed.

---

## B2: DegeneretteModule::resolveBets (lines 411-423)

### Call Tree
```
resolveBets(player, betIds)  [L411]
  -> _resolvePlayer(player)  [L415, private view L160]
       -> (same as B1)
  -> for each betId in betIds:  [L417-422]
       -> _resolveBet(player, betIds[i])  [L418, private L577]
            -> reads degeneretteBets[player][betId]  [L578]
            -> if packed == 0: revert InvalidBet()  [L579]
            -> _resolveFullTicketBet(player, betId, packed)  [L581, private L585]
                 -> decode packed: customTicket, ticketCount, currency, amountPerTicket, index, activityScore, heroEnabled, heroQuadrant  [L587-595]
                 -> reads lootboxRngWordByIndex[index]  [L597]
                 -> if rngWord == 0: revert RngNotReady()  [L598]
                 -> WRITES delete degeneretteBets[player][betId]  [L600]
                 -> _roiBpsFromScore(activityScore)  [L602, pure L1098]
                 -> _wwxrpHighValueRoi(activityScore) if WWXRP  [L604-606, pure L1135]
                 -> for each spinIdx 0..ticketCount-1:  [L613-664]
                      -> compute resultSeed via keccak256(rngWord, index [, spinIdx], QUICK_PLAY_SALT)  [L616-618]
                      -> DegenerusTraitUtils.packedTraitsFromSeed(resultSeed)  [L619]
                      -> _countMatches(playerTicket, resultTicket)  [L625, pure L852]
                      -> _fullTicketPayout(...)  [L628-638, pure L912]
                           -> _getBasePayoutBps(matches)  [L923, pure L990]
                           -> _wwxrpBonusBucket(matches)  [L928/L935, pure L880]
                           -> _wwxrpBonusRoiForBucket(bucket, bonusRoi)  [L931/L937-939, pure L888]
                           -> _evNormalizationRatio(playerTicket, resultTicket)  [L952, pure L803]
                           -> _applyHeroMultiplier(payout, ...) if heroEnabled && 2<=M<8  [L959, pure L966]
                      -> emit FullTicketResult  [L640-643]
                      -> if payout != 0:
                           -> totalPayout += payout  [L646]
                           -> compute lootboxWord  [L650-652]
                           -> _distributePayout(player, currency, payout, lootboxWord)  [L653, private L680]
                                -> if ETH:
                                     -> if prizePoolFrozen: revert E()  [L685]
                                     -> reads _getFuturePrizePool()  [L687]
                                     -> ethPortion = payout / 4  [L690]
                                     -> lootboxPortion = payout - ethPortion  [L691]
                                     -> maxEth = pool * ETH_WIN_CAP_BPS / 10000  [L695]
                                     -> if ethPortion > maxEth: redistribute excess  [L696-700]
                                     -> unchecked { pool -= ethPortion }  [L702]
                                     -> WRITES _setFuturePrizePool(pool)  [L703]
                                     -> _addClaimableEth(player, ethPortion)  [L704, private L1153]
                                          -> WRITES claimablePool += weiAmount  [L1158]
                                          -> _creditClaimable(beneficiary, weiAmount)  [L1159, PayoutUtils L30]
                                               -> WRITES claimableWinnings[beneficiary] += weiAmount  [L33]
                                               -> emit PlayerCredited  [L35]
                                     -> if lootboxPortion > 0:
                                          -> _resolveLootboxDirect(player, lootboxPortion, rngWord)  [L708, private L741]
                                               -> delegatecall to LootboxModule.resolveLootboxDirect  [L746-756]
                                               -> LootboxModule WRITES: lootbox-specific storage (details in Phase 111)
                                               -> LootboxModule does NOT write: prizePoolsPacked, claimableWinnings, claimablePool
                                -> if BURNIE:
                                     -> external: coin.mintForGame(player, payout)  [L711]
                                -> if WWXRP:
                                     -> external: wwxrp.mintPrize(player, payout)  [L713]
                      -> if ETH && matches >= 6:
                           -> _awardDegeneretteDgnrs(player, amountPerTicket, matches)  [L658, private L1164]
                                -> reads bps from match tier (6->400, 7->800, 8->1500)  [L1166-1168]
                                -> external: sdgnrs.poolBalance(Pool.Reward)  [L1170]
                                -> if poolBalance == 0: return  [L1171]
                                -> cappedBet = min(betWei, 1 ether)  [L1173]
                                -> reward = poolBalance * bps * cappedBet / (10000 * 1e18)  [L1174]
                                -> if reward == 0: return  [L1175]
                                -> external: sdgnrs.transferFromPool(Pool.Reward, player, reward)  [L1177]
                 -> emit FullTicketResolved  [L666]
                 -> if totalPayout == 0:
                      -> _maybeAwardConsolation(player, currency, amountPerTicket)  [L670, private L722]
                           -> checks currency-specific minimum thresholds  [L724-730]
                           -> if qualifies: external wwxrp.mintPrize(player, 1 ether)  [L734]
                           -> emit ConsolationPrize  [L735]
```

### Storage Writes (Full Tree)
| Variable | Location | Condition |
|----------|----------|-----------|
| `degeneretteBets[player][betId]` | L600 (delete) | Always (per bet) |
| `prizePoolsPacked` (futurePrizePool) | L703 (via _setFuturePrizePool) | ETH + payout > 0 (per winning spin) |
| `claimablePool` | L1158 (via _addClaimableEth) | ETH + payout > 0 + ethPortion > 0 (per winning spin) |
| `claimableWinnings[player]` | L33 PayoutUtils (via _creditClaimable) | ETH + payout > 0 + ethPortion > 0 (per winning spin) |
| LootboxModule storage (various) | via delegatecall L746-756 | ETH + lootboxPortion > 0 (per winning spin) |

**External state changes (not Game storage):**
| External Call | Condition |
|--------------|-----------|
| coin.mintForGame (BURNIE mint) | BURNIE + payout > 0 |
| wwxrp.mintPrize (WWXRP mint) | WWXRP + payout > 0 |
| wwxrp.mintPrize (consolation) | totalPayout == 0 + qualifying bet |
| sdgnrs.transferFromPool (sDGNRS reward) | ETH + matches >= 6 + poolBalance > 0 + reward > 0 |

### Cached-Local-vs-Storage Check

**CRITICAL ANALYSIS:** The resolution loop (L613-664) calls `_distributePayout` once per winning spin. Each call to `_distributePayout` for ETH:
1. Reads `_getFuturePrizePool()` -- FRESH read each call (not cached across spins)
2. Writes `_setFuturePrizePool(pool - ethPortion)` -- committed before next iteration
3. Writes `_addClaimableEth` -- committed before next iteration
4. Calls `_resolveLootboxDirect` (delegatecall) -- executed AFTER pool and claimable writes

| Ancestor Local | Descendant Write | Verdict |
|----------------|------------------|---------|
| `packed` (L578, from degeneretteBets) | degeneretteBets deleted at L600 | SAFE: packed is a decoded copy used for the entire resolution. Delete is intentional cleanup |
| `rngWord` (L597, from lootboxRngWordByIndex) | No function in the tree writes lootboxRngWordByIndex | SAFE |
| `roiBps` (L602) | N/A (pure computation from stored activityScore) | SAFE |
| `pool` (L687, from _getFuturePrizePool) | _setFuturePrizePool at L703 | SAFE: read-then-modify-write within same call frame. No intervening call modifies prizePoolsPacked before L703 |
| No local cache of claimableWinnings | _creditClaimable writes at PayoutUtils L33 | SAFE: no ancestor caches this |
| `pool` after L703 write | LootboxModule delegatecall at L708 | SAFE: I verified LootboxModule.resolveLootboxDirect does NOT write to prizePoolsPacked. It writes to lootbox-specific storage (lootbox entries, amounts, etc.) |

**Multi-spin iteration analysis:**
- Spin 0: reads futurePrizePool as X, writes X-ethPortion0. Pool is now X-ethPortion0 in storage.
- Spin 1: reads futurePrizePool as X-ethPortion0 (FRESH read), writes X-ethPortion0-ethPortion1. Correct.
- Each iteration gets a fresh pool read. NO stale cache across spins.

**Verdict: NO BAF-CLASS CACHE OVERWRITES in B2.**

### Attack Analysis

**1. State Coherence (BAF Pattern):** SAFE. Detailed analysis above. Each spin reads fresh pool state. The delegatecall to LootboxModule does not touch the parent's cached variables.

**2. Access Control:** SAFE. Same as B1 -- `_resolvePlayer` checks operator approval.

**3. RNG Manipulation:** SAFE. The bet was placed BEFORE the RNG word was fulfilled (L475 check during placement). At resolution time, the RNG word is read from `lootboxRngWordByIndex[index]` which was set by VRF fulfillment. The player's ticket (customTicket) was committed at placement time and stored in the packed bet. Player cannot change their ticket after seeing the RNG word.

**Commitment window check:** Between bet placement and resolution, what player-controllable state changes affect the outcome?
- `customTicket` -- locked in packed bet at placement. SAFE.
- `amountPerTicket` -- locked in packed bet. SAFE.
- `activityScore` -- LOCKED at placement time (L480, stored in packed bet). Resolution uses the stored score (L592), NOT a recomputed one. SAFE.
- `heroQuadrant` -- locked in packed bet. SAFE.
- Only the `resultSeed` depends on the `rngWord` which the player cannot control (VRF).

**4. Cross-Contract State Desync:** SAFE. The delegatecall to LootboxModule executes in Game's storage context. All Game storage reads/writes before and after the delegatecall are in the same storage context. External calls (coin.mintForGame, wwxrp.mintPrize, sdgnrs.transferFromPool) are called AFTER all Game storage writes for that spin iteration.

**5. Edge Cases:**

- **betIds array empty:** Loop body never executes. No-op. SAFE.
- **betIds contains invalid/already-resolved ID:** `packed == 0` check at L579 reverts. SAFE.
- **betIds contains duplicate:** First resolution deletes the bet (L600). Second attempt reads 0, reverts at L579. SAFE.
- **ticketCount = 0 in packed bet:** Impossible -- validated at placement (L470). If somehow stored, the spin loop (L613) would not execute. totalPayout remains 0. Consolation check runs. SAFE.
- **All spins lose (totalPayout == 0):** Consolation prize awarded if qualifying. SAFE.
- **All spins win:** Each spin's payout distributed independently. SAFE.
- **Jackpot (8 matches) with ETH:** Payout = betAmount * 10_000_000 * roiBps / 1_000_000. For betAmount = 5e15 (min ETH), roiBps = 9000: payout = 5e15 * 10_000_000 * 9000 / 1_000_000 = 4.5e17 = 0.45 ETH. ETH portion = 0.1125 ETH, capped at 10% of pool. SAFE: cap mechanism prevents pool drain.

**6. Conditional Paths:**

- **prizePoolFrozen during resolution:** ETH payouts revert at L685. BURNIE/WWXRP payouts proceed normally (no pool interaction). A player with pending ETH bets during a freeze cannot resolve until unfreeze. INVESTIGATE: is this a griefing vector? See F-03.
- **Pool near zero:** If futurePrizePool is very small, ethPortion is capped at 10% of pool. `unchecked { pool -= ethPortion }` at L702: since ethPortion <= pool * 10%, this cannot underflow. SAFE.
- **sDGNRS Reward pool empty:** `if (poolBalance == 0) return` at L1171. No revert, graceful skip. SAFE.
- **sDGNRS reward = 0 after calculation:** `if (reward == 0) return` at L1175. Graceful skip. SAFE.
- **Consolation prize path (WWXRP mint):** Always mints exactly 1 WWXRP. External call. If WWXRP contract is paused/broken, the entire resolveBets tx reverts. Griefing concern: if WWXRP is down, no bets can resolve for qualifying losers. Extremely edge-case.

**7. Economic Attacks:**

- **Front-running resolution:** A player could front-run another player's resolution to drain the futurePrizePool before their resolution. Impact: the other player's ethPortion would be capped lower. But this is a natural pool depletion mechanism, not an exploit -- cap at 10% means no single resolution can drain the pool.
- **Sandwich attack on resolution:** No benefit -- payout is deterministic from the RNG word and bet parameters.

**8. Griefing:** INVESTIGATE. See F-03 below (prizePoolFrozen blocks ETH resolution).

**9. Ordering/Sequencing:** SAFE. Bets are resolved independently. Order of betIds in the array does not affect outcomes (each bet has its own packed data).

**10. Silent Failures:**

- **_awardDegeneretteDgnrs with zero pool:** Returns silently, no revert. Player misses sDGNRS reward. SAFE by design -- reward is a bonus, not an entitlement.
- **_maybeAwardConsolation with below-threshold bet:** Returns without minting. SAFE by design.
- **LootboxModule delegatecall failure:** `if (!ok) _revertDelegate(data)` at L756. Reverts propagated. SAFE.

### Findings

**F-03: ETH Bet Resolution Blocked During prizePoolFrozen**
- **Location:** L685
- **Code:** `if (prizePoolFrozen) revert E();`
- **Issue:** When advanceGame is processing (prizePoolFrozen = true), ETH Degenerette bet resolutions revert. BURNIE and WWXRP resolutions succeed because they don't touch prize pools.
- **Impact:** Temporary DoS on ETH bet resolution during day advancement. Freeze duration is bounded by advanceGame execution (single transaction). Players must wait until the freeze ends.
- **Verdict:** INVESTIGATE (INFO) -- by design to protect pool integrity during jackpot math. Not exploitable, just a UX note.

**F-04: Unchecked `pool -= ethPortion` May Underflow If Pool Depleted Across Spins**
- **Location:** L702
- **Code:** `unchecked { pool -= ethPortion; }`
- **Analysis:** Within a SINGLE call to `_distributePayout`, ethPortion <= maxEth = pool * 10% < pool. So pool - ethPortion >= 0. But across MULTIPLE spins in the same resolution, `_distributePayout` is called multiple times. Each call reads a FRESH pool value via `_getFuturePrizePool()`. Spin N reads the pool value AFTER spin N-1 deducted. Each spin's ethPortion is capped at 10% of the CURRENT pool. So spin 0: deducts up to 10% of P. Spin 1: deducts up to 10% of (P - deduction0). And so on. After 10 spins: worst case ~65% of original pool remains (0.9^10 = 0.349). No underflow possible.
- **Verdict:** SAFE -- fresh reads per spin plus 10% cap guarantee no underflow.

**F-05: totalBet Cast to uint128 in _collectBetFunds Pool Addition**
- **Location:** L560, L563
- **Code:** `_setPendingPools(pNext, pFuture + uint128(totalBet));`
- **Analysis:** `totalBet = amountPerTicket * ticketCount`. amountPerTicket is uint128. ticketCount max 10. So totalBet max = uint128.max * 10 which EXCEEDS uint128.max. The cast `uint128(totalBet)` would truncate.
- **Concrete check:** uint128.max = ~3.4e38. Multiplied by 10 = ~3.4e39. Cast to uint128 truncates to lower 128 bits. However: amountPerTicket is supplied as uint128 by the caller. For ETH: realistic max is ~1e24 (1M ETH) * 10 = 1e25, well within uint128. For BURNIE: similar. The cast truncation would only occur with amountPerTicket > uint128.max / 10 which is ~3.4e37 or ~3.4e19 ETH -- impossible in practice.
- **Verdict:** INVESTIGATE (INFO) -- theoretical truncation but economically impossible. The protocol would need >3.4e19 ETH per ticket to trigger.

**F-06: ETH Payout 75/25 Split With Lootbox Delegatecall -- Coherence Check**
- **Location:** L687-709
- **Sequence:** Read pool (L687) -> Compute split (L690-700) -> Write pool (L703) -> Credit ETH (L704) -> Delegatecall lootbox (L708)
- **Analysis:** The critical question: does the delegatecall to LootboxModule modify prizePoolsPacked or claimablePool/claimableWinnings?
- **Verification:** I read LootboxModule.resolveLootboxDirect (L694-720). It calls `_resolveLootboxCommon` which writes to lootbox-specific storage: lootboxEntries, lootboxAmounts, etc. It does NOT write to prizePoolsPacked, claimablePool, or claimableWinnings.
- **Verdict:** SAFE -- no state coherence violation across the delegatecall boundary.

---

## Category C Analysis

### C6: _distributePayout [MULTI-PARENT] (lines 680-715)

Standalone analysis because C6 is called once per winning spin within the C5 loop. Each invocation is independent.

**Calling contexts:**
- C5 (_resolveFullTicketBet) calls C6 for each winning spin (payout != 0) at L653
- Always called with fresh parameters (player, currency, payout from current spin, lootboxWord from current spin)

**State written per call (ETH path):**
1. prizePoolsPacked (futurePrizePool -= ethPortion)
2. claimablePool += ethPortion
3. claimableWinnings[player] += ethPortion
4. LootboxModule storage (via delegatecall, for lootboxPortion)

**Cross-call coherence:** Each call reads fresh `_getFuturePrizePool()` at L687. No stale cache from previous call. SAFE.

**ETH path lootbox conversion:** The `lootboxPortion` amount (75% of payout + any cap excess) is passed to LootboxModule via delegatecall. This amount does NOT come from the game contract's ETH balance -- it represents a "virtual ETH" value that LootboxModule uses to determine lootbox reward tiers. The ETH was already in the futurePrizePool which was added during bet placement. The pool deduction is the ethPortion (25% or less), not the full payout. The lootbox conversion does not need additional ETH movement -- it's an internal accounting conversion.

### C3: _collectBetFunds (lines 541-574)

Key analysis already in B1 call tree above. Additional notes:

**Claimable pull logic (L549-555):**
- `ethPaid > totalBet` -> revert (overpayment protection)
- `ethPaid < totalBet` -> pull `fromClaimable = totalBet - ethPaid` from claimableWinnings
- `ethPaid == totalBet` -> no claimable pull needed, skip the block
- The `<=` check at L552 means exact claimable match reverts. See F-01.

**Underflow risk on claimablePool (L554):**
- `claimablePool -= fromClaimable` is checked subtraction (Solidity 0.8.34 default). If claimablePool < fromClaimable, tx reverts. This is a safety invariant: claimablePool should always be >= sum of all claimableWinnings[]. If this invariant holds, and claimableWinnings[player] > fromClaimable (checked at L552), then claimablePool >= claimableWinnings[player] > fromClaimable. SAFE if invariant holds.

### C7: _resolveLootboxDirect (lines 741-757)

**Delegatecall analysis:**
- Target: `ContractAddresses.GAME_LOOTBOX_MODULE` (compile-time constant)
- Selector: `IDegenerusGameLootboxModule.resolveLootboxDirect.selector`
- Parameters: player, amount, rngWord
- On failure: `_revertDelegate(data)` propagates revert reason
- On success: all LootboxModule storage writes persisted in Game's storage context

**Storage safety:** LootboxModule.resolveLootboxDirect (verified at LootboxModule L694-720) writes to:
- Lootbox entry data (per-player lootbox arrays/mappings)
- Level-specific lootbox counters
- Activity score multiplier tracking

It does NOT write to: prizePoolsPacked, claimablePool, claimableWinnings, degeneretteBets, or any Degenerette-specific storage. SAFE.

### C9: _awardDegeneretteDgnrs (lines 1164-1178)

**sDGNRS reward from Reward pool:**
- Reads sdgnrs.poolBalance(Pool.Reward) -- external view call
- Computes reward = poolBalance * bps * cappedBet / (10000 * 1 ether)
- BPS: 400 (6 matches), 800 (7 matches), 1500 (8 matches)
- cappedBet = min(betWei, 1 ether) -- caps per-ticket exposure
- Calls sdgnrs.transferFromPool(Pool.Reward, player, reward)

**Diminishing returns across spins:** If multiple spins in the same resolution achieve 6+ matches, each call to _awardDegeneretteDgnrs reads a FRESH poolBalance. After the first transfer, the pool decreases, so subsequent rewards are slightly smaller. Same pattern as F-02 in Unit 6 (whale purchases). By design.

**External call ordering:** _awardDegeneretteDgnrs is called at L658 WITHIN the spin loop, AFTER _distributePayout for that spin. If the sDGNRS transfer reverts (e.g., insufficient pool balance despite check), the entire resolution tx reverts. This is a potential griefing vector if sDGNRS pool is manipulated between poolBalance check and transferFromPool. But: poolBalance is view-only and the transfer is immediate -- no MEV window between the two calls within the same transaction.

### C10: _maybeAwardConsolation (lines 722-737)

**Consolation prize for total-loss bets:**
- Only called if totalPayout == 0 (ALL spins lost)
- Checks per-currency minimum thresholds: ETH >= 0.01, BURNIE >= 500, WWXRP >= 20
- Awards 1 WWXRP via wwxrp.mintPrize
- If WWXRP minting fails, entire resolution reverts

**Edge case:** A player with currency=2 (unsupported but let through somehow) reaches this function. The `if` chain falls through without setting `qualifies = true`. No consolation awarded. SAFE -- but currency=2 should have reverted earlier at _validateMinBet (L536: `revert UnsupportedCurrency()`).

---

## Category D Security Verification

### D5: _packFullTicketBet -- Bit Field Overlap Check

Layout verification:
| Field | Bits | Shift | Width | Range |
|-------|------|-------|-------|-------|
| mode | 0 | 0 | 1 | Fixed: 1 |
| isRandom | 1 | -- | 1 | Always 0 (not used) |
| customTicket | 2-33 | 2 | 32 | packed traits |
| ticketCount | 34-41 | 34 | 8 | 1-10 |
| currency | 42-43 | 42 | 2 | 0-3 |
| amountPerTicket | 44-171 | 44 | 128 | uint128 |
| index | 172-219 | 172 | 48 | uint48 |
| activityScore | 220-235 | 220 | 16 | uint16 |
| hasCustom | 236 | 236 | 1 | Fixed: 1 |
| hero | 237-239 | 237 | 3 | [0]=enabled, [1..2]=quadrant |

Total: 240 bits. Fits within uint256 (256 bits). **No overlap.** 16 bits unused (240-255). SAFE.

### D6: _evNormalizationRatio -- Overflow Check

Per-quadrant multiplication:
- num starts at 1, multiplied by 100, 1300, or 4225 per quadrant
- den starts at 1, multiplied by wC*wS, 75*(wC+wS)-2*wC*wS, or (75-wC)*(75-wS)

Worst case for num: 4 quadrants all "no match" -> num = 4225^4 = 3.18e14. Fits uint256.
Worst case for den: 4 quadrants with smallest denominators. wC=wS=8 (bucket 7), no match: (75-8)*(75-8) = 4489. Min possible: 4 quadrants all "both match" with wC=wS=10: 100^4 = 1e8. den = 100^4 = 1e8. Max ratio: 4225^4 / 100^4 = 31,817x. Applied to payout: betAmount * basePayout * roi * 31817 / 1_000_000. For 8-match jackpot: 5e15 * 10_000_000 * 9990 * 31817 / 1_000_000 = 1.59e25. Fits uint256. SAFE.

### D7: _countMatches -- Bit Extraction

Color: `(pQuad >> 3) & 7` extracts bits 5-3. Symbol: `pQuad & 7` extracts bits 2-0. Per quadrant, pQuad = uint8 from packed uint32. Bits 7-6 are quadrant identifier (ignored by masking with 7). SAFE.

### D8: _fullTicketPayout -- Overflow Check

Multiplication chain: `betAmount * basePayoutBps * effectiveRoi / 1_000_000`
- betAmount: uint128 (max 3.4e38)
- basePayoutBps: max 10_000_000 (8-match jackpot)
- effectiveRoi: max ~11_000 (WWXRP high ROI)
- Product before division: 3.4e38 * 1e7 * 1.1e4 = 3.74e49. Fits uint256 (max ~1.16e77). SAFE.

Then: `payout * evNum / evDen`
- evNum max: 4225^4 = 3.18e14
- payout max from above: 3.74e49 / 1e6 = 3.74e43
- Product: 3.74e43 * 3.18e14 = 1.19e58. Fits uint256. SAFE.

Then: hero multiplier: `payout * multiplier / HERO_SCALE`
- multiplier max: 23500 (M=2 boost)
- payout from above: 1.19e58 (theoretical max, extremely unlikely)
- Product: 1.19e58 * 23500 = 2.8e62. Fits uint256. SAFE.

### D14: _roiBpsFromScore -- Continuity Check

At score = 7500 (ACTIVITY_SCORE_MID_BPS):
- Quadratic: ROI_MIN_BPS + 1000 * 7500/7500 - 500 * 7500^2/7500^2 = 9000 + 1000 - 500 = 9500. Matches ROI_MID_BPS.

At score = 25500 (ACTIVITY_SCORE_HIGH_BPS):
- Linear from 7500: ROI_MID_BPS + (25500-7500) * (ROI_HIGH_BPS - ROI_MID_BPS) / (25500-7500) = 9500 + 450 = 9950. Matches ROI_HIGH_BPS.

At score = 30500 (ACTIVITY_SCORE_MAX_BPS):
- Linear from 25500: ROI_HIGH_BPS + (30500-25500) * (ROI_MAX_BPS - ROI_HIGH_BPS) / (30500-25500) = 9950 + 40 = 9990. Matches ROI_MAX_BPS.

**Continuity verified at all breakpoints. Quadratic term overflow:** 500 * 7500^2 / 7500^2 = 500. Intermediate: 500 * 56_250_000 = 28_125_000_000. / 56_250_000 = 500. All fit uint256. SAFE.

---

## Findings Summary

| ID | Title | Severity | Verdict |
|----|-------|----------|---------|
| F-01 | ETH claimable pull uses `<=` instead of `<` | LOW | INVESTIGATE |
| F-02 | WWXRP bets do not track pending amounts | -- | SAFE (by design) |
| F-03 | ETH bet resolution blocked during prizePoolFrozen | INFO | INVESTIGATE |
| F-04 | Unchecked pool subtraction across multi-spin | -- | SAFE (fresh reads + 10% cap) |
| F-05 | uint128 cast truncation on totalBet pool addition | INFO | INVESTIGATE |
| F-06 | Delegatecall to LootboxModule state coherence | -- | SAFE (verified) |
