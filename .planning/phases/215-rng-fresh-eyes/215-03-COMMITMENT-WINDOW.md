# Commitment Window Analysis (RNG-03)

**Audit date:** 2026-04-11
**Source:** contracts at current HEAD
**Methodology:** Per D-06 -- think like an attacker who sees the VRF request tx and asks "what can I change before fulfillment lands?"

---

## Section 1: Daily VRF Window

### Window Definition

- **OPENS:** `_requestRng()` sets `rngLockedFlag = true` (AdvanceModule line 1442) and calls `vrfCoordinator.requestRandomWords()` (line 1388). Simultaneously advances lootbox index (line 1432), zeros pending counters (lines 1433-1434), records `rngRequestTime = block.timestamp` (line 1441).
- **CLOSES:** `rawFulfillRandomWords()` stores word to `rngWordCurrent` (AdvanceModule line 1542) when `rngLockedFlag == true`. The flag remains true until `_unlockRng()` (line 1515) sets `rngLockedFlag = false` after daily processing completes.
- **Duration:** Minimum 10 blocks (`VRF_REQUEST_CONFIRMATIONS = 10`, line 118). Typically 30-120 seconds on Ethereum mainnet at 12s blocks.

### rngLockedFlag Guard Site Inventory

All sites where `rngLockedFlag` is checked as a revert guard:

| Guard Site | File | Line | Revert | Blocks |
|-----------|------|------|--------|--------|
| `_setAutoRebuy` | DegenerusGame.sol | 1480 | `RngLocked()` | Auto-rebuy toggle |
| `_setAutoRebuyTakeProfit` | DegenerusGame.sol | 1495 | `RngLocked()` | Take profit config |
| `_setAfKingMode` | DegenerusGame.sol | 1542 | `RngLocked()` | AfKing mode toggle |
| `reverseFlip` | DegenerusGame.sol | 1882 | `RngLocked()` | RNG nudge (BURNIE burn) |
| `_queueTickets` (far-future only) | DegenerusGameStorage.sol | 566 | `RngLocked()` | Far-future ticket queue writes |
| `_queueTicketsScaled` (far-future only) | DegenerusGameStorage.sol | 596 | `RngLocked()` | Far-future scaled ticket queue writes |
| `_queueTicketRange` (far-future only) | DegenerusGameStorage.sol | 650 | `RngLocked()` | Far-future ticket range writes |
| `_purchaseDeityPass` | DegenerusGameWhaleModule.sol | 543 | `RngLocked()` | Deity pass purchase |
| `requestLootboxRng` | DegenerusGameAdvanceModule.sol | 908 | `RngLocked()` | Mid-day lootbox RNG request |

Additional non-revert `rngLockedFlag` references:

| Site | File | Line | Effect |
|------|------|------|--------|
| `_callTicketPurchase` routing | DegenerusGameMintModule.sol | 1231 | Redirects last-jackpot-day ticket routing to `level+1` (not a revert -- routing adjustment) |
| `rawFulfillRandomWords` branch | DegenerusGameAdvanceModule.sol | 1540 | `true` => daily path (store to `rngWordCurrent`); `false` => mid-day path (store to `lootboxRngWordByIndex`) |
| `advanceGame` purchaseLevel calc | DegenerusGameAdvanceModule.sol | 177 | `lastPurchase && rngLockedFlag` => use `lvl` not `lvl+1` |

### Per-Function Classification During Daily VRF Window

Every external/public function on DegenerusGame.sol, classified:

#### BLOCKED by rngLockedFlag

| Function | Guard Site | What is Blocked |
|----------|-----------|-----------------|
| `setAutoRebuy(player, enabled)` | Game L1480 | Auto-rebuy toggle that affects whether player receives rebuy on next payout |
| `setAutoRebuyTakeProfit(player, takeProfit)` | Game L1495 | Take-profit config that affects payout amount on next rebuy |
| `setAfKingMode(player, enabled, ethTP, coinTP)` | Game L1542 | Combined rebuy + lazy pass mode toggle |
| `reverseFlip()` | Game L1882 | RNG nudge -- burns BURNIE to add +1 to VRF word. Blocked to prevent nudging AFTER seeing the VRF request (and potentially the VRF fulfillment tx in mempool) |
| `purchaseDeityPass(buyer, symbolId)` | Whale L543 | Deity pass purchase. Blocked to prevent acquiring deity status during jackpot resolution |
| `requestLootboxRng()` | Advance L908 | Mid-day lootbox RNG request. Blocked because daily VRF is in-flight |
| `purchaseWhaleBundle` (far-future tickets only) | Storage L650 | Whale bundle queues 100 levels of tickets via `_queueTicketRange`. Only far-future keys (level > current + 5) are blocked; near-future keys proceed normally |
| `purchase / purchaseCoin / purchaseBurnieLootbox` (far-future tickets only) | Storage L566/596 | Ticket purchase with far-future routing (level > current + 5). Near-future and current-level tickets proceed |

#### NOT BLOCKED -- Does Not Affect RNG Outcomes

| Function | Rationale |
|----------|-----------|
| `claimWinnings(player)` | Reads `claimableWinnings[player]`, transfers ETH. No RNG state interaction. Pull-pattern claim of already-determined amounts. |
| `claimWinningsStethFirst()` | Same as `claimWinnings` but vault-only and stETH-first. No RNG interaction. |
| `claimAffiliateDgnrs(player)` | Claims DGNRS from affiliate score. Reads per-level affiliate data, mints DGNRS. No RNG dependency. |
| `claimDecimatorJackpot(lvl)` | Claims from decimator pool. The winning sub-bucket was already determined by prior RNG. No further RNG resolution. |
| `claimWhalePass(player)` | Deferred whale pass ticket awards. Routes to `_queueTicketRange` but uses `rngBypass=true` (WhaleModule delegatecall), so the rngLockedFlag check at Storage L650 is bypassed. Does not affect RNG outcomes -- tickets go to future levels. |
| `openLootBox(player, index)` | Opens a lootbox using `lootboxRngWordByIndex[index]`. The word was written before the current daily window opened (word is for a prior index). Opening consumes the stored word -- does not change any pending RNG state. |
| `openBurnieLootBox(player, index)` | Same as `openLootBox` for BURNIE lootboxes. Consumes existing stored word. |
| `resolveDegeneretteBets(player, betIds)` | Resolves bets using `lootboxRngWordByIndex[index]` where index was recorded at bet placement time. Word was committed before this window. Resolution does not change pending RNG state. |
| `setOperatorApproval(operator, approved)` | Writes `operatorApprovals` mapping. Authorization-only; no game state or RNG interaction. |
| `advanceGame()` | During the daily VRF window, `advanceGame` either (a) processes tickets on mid-day path (day == dailyIdx), or (b) waits for VRF word on new-day path (reverts `RngNotReady()` at line 1153 if VRF request pending but no word yet). When the word arrives, `advanceGame` consumes it in `rngGate` and proceeds to daily processing. This is the INTENDED consumer of the word. |
| `deactivateAfKingFromCoin(player)` | Access: COIN or COINFLIP only. Deactivation of afKing mode. No RNG interaction. |
| `syncAfKingLazyPassFromCoin(player)` | Access: COINFLIP only. Status sync. No RNG interaction. |
| `recordMintQuestStreak(player)` | Access: GAME self-call only. Quest tracking. No RNG interaction. |
| `payCoinflipBountyDgnrs(...)` | Access: COIN or COINFLIP only. DGNRS bounty for flip record. No RNG interaction. |
| `consumeCoinflipBoon(player)` | Access: COIN or COINFLIP only. Boon consumption. No RNG interaction. |
| `consumeDecimatorBoon(player)` | Access: COIN only. Boon consumption. No RNG interaction. |
| `consumePurchaseBoost(player)` | Access: self-call only. Boost consumption. No RNG interaction. |
| `wireVrf(...)` | Access: ADMIN only. VRF config setup. Admin-gated. |
| `updateVrfCoordinatorAndSub(...)` | Access: ADMIN only. Emergency VRF rotation. Admin-gated, sets `rngLockedFlag = false` (line 1492). |
| `adminStakeEthForStEth(amount)` | Access: vault owner only. ETH staking into stETH. No RNG interaction. |
| `adminSwapStethForEth(recipient, amount)` | Access: vault owner only. stETH to ETH swap. No RNG interaction. |
| `setLootboxRngThreshold(newThreshold)` | Access: vault owner only. Updates lootbox RNG trigger threshold. No RNG outcome interaction. |
| All `*View()` / `view` functions | Read-only. Cannot change state. |

#### NOT BLOCKED -- Could Affect RNG-Adjacent State (DETAILED ANALYSIS)

| Function | State Changed | Affects RNG Outcome? | Risk |
|----------|--------------|---------------------|------|
| `purchase(buyer, ticketQty, lootBoxAmt, ...)` | Ticket queue, lootbox amounts, pool balances, quest state, affiliate scores | **Ticket queue:** writes to `_tqWriteKey()` (current write slot). The read slot was frozen by `_swapAndFreeze` (line 275) at VRF request time. New tickets go to the write slot, which will not be processed until the NEXT VRF cycle. **Lootbox amounts:** writes to `lootboxEth[index][player]` where `index` is the NEW index (incremented at line 1432). This index targets the NEXT VRF word, not the pending one. **Pool balances:** writes to pending accumulators when `prizePoolFrozen == true` (set by `_swapAndFreeze` at Storage L760-766). Pool reads during jackpot processing use the frozen snapshot. | SAFE -- all writes target post-window state |
| `purchaseCoin(buyer, ticketQty, lootBoxBurnieAmt)` | Same as `purchase` but BURNIE-funded | Same analysis as `purchase`. Ticket routing to write slot, lootbox to new index, pools frozen. | SAFE |
| `purchaseBurnieLootbox(buyer, burnieAmt)` | Lootbox BURNIE amount at current index | Writes `lootboxBurnie[index][player]` where `index` is the NEW index (post-increment). Cannot be resolved by the pending word. | SAFE |
| `purchaseWhaleBundle(buyer, quantity)` | Ticket range (100 levels), lootbox amounts, DGNRS rewards, mintPacked stats | **Near-future tickets:** write to `_tqWriteKey()` for levels within +5 of current. These are write-slot targets, frozen for current cycle. **Far-future tickets:** BLOCKED by `rngLockedFlag` at Storage L650, reverts `RngLocked()`. **Lootbox:** writes to `lootboxEth[index]` at new index (WhaleModule L876). | SAFE |
| `purchaseLazyPass(buyer)` | Lazy pass state, DGNRS rewards, lootbox amounts | Lazy pass is a 10-level ticket grant. Routes through WhaleModule. No direct rngLockedFlag check on lazy pass entry, but all ticket queuing goes through `_queueTicketRange` which blocks far-future during rngLocked. Lootbox writes to new index. | SAFE |
| `placeDegeneretteBet(player, currency, ...)` | `degeneretteBets[player][nonce]`, `dailyHeroWagers`, `playerDegeneretteEthWagered`, lootbox pending counters, pool balances | **Bet recording:** stores current `lootboxRngIndex` in packed bet (DegeneretteModule L446). **Guard at line 430:** `if (lootboxRngWordByIndex[index] != 0) revert RngNotReady()` -- ensures word for current index is NOT yet available. During daily VRF window, the current index was just incremented (AdvanceModule L1432), so `lootboxRngWordByIndex[newIndex]` is 0. Bets placed during the window target this new index, whose word does not exist. **Hero wagers:** writes `dailyHeroWagers[day][quadrant]` which affects `_applyHeroOverride` -- but the hero override for this day's jackpot already happened before the window opened (daily jackpot runs before `_requestRng`). Hero wagers during the window affect the NEXT day's hero selection. **Pool balances:** ETH bets write to `futurePrizePool` (or pending accumulators when frozen). Lootbox pending counters update for the new index. | SAFE |
| `issueDeityBoon(deity, recipient, slot)` | Boon state for recipient | Deity boon issuance. The boon types for today are determined by `_deityDailySeed(day)` which reads `rngWordByDay[day]` -- during the daily window, `rngWordByDay[day]` for the CURRENT day may not yet be written (it is written during the rngGate processing). However, the boon issuance reads the word for the CALL day, not the pending day. If the word exists, the boon type is deterministic. If it does not exist yet, the fallback chain in `_deityDailySeed` (LootboxModule L1743-1750) uses `rngWordCurrent` or deterministic fallback. This boon does not affect any RNG outcome -- it gives the recipient a consumable bonus (purchase boost, decimator boost, etc.). | SAFE -- boons are consumable bonuses, not RNG inputs |

### Daily VRF Window Summary

**rngLockedFlag provides effective mutual exclusion** for the daily VRF window. The critical protections are:

1. **Ticket queue double-buffer:** `_swapAndFreeze` (line 275) flips write/read slots at VRF request time. All purchases during the window write to the NEW write slot. Daily processing reads from the frozen read slot. New tickets cannot contaminate the current draw.

2. **Lootbox index advance:** `_finalizeRngRequest` (line 1432) increments `lootboxRngIndex` at VRF request time. All lootbox purchases during the window target `index+1`. The pending VRF word will be stored at `lootboxRngWordByIndex[index]` (the OLD index). Purchases at the new index await a future VRF delivery.

3. **Prize pool freeze:** `_swapAndFreeze` sets `prizePoolFrozen = true` (Storage line 762). Pool writes during the window go to pending accumulators. Jackpot distribution reads the frozen snapshot.

4. **Nudge blocking:** `reverseFlip()` is blocked by rngLockedFlag (Game L1882). Players cannot add nudges after seeing the VRF request.

5. **Degenerette bet isolation:** `_placeDegeneretteBetCore` checks `lootboxRngWordByIndex[index] != 0` (line 430), ensuring bets target an index whose word does not yet exist.

---

## Section 2: Lootbox VRF Window

### Window Definition

- **OPENS:** `requestLootboxRng()` calls `vrfCoordinator.requestRandomWords()` (AdvanceModule line 959) with `VRF_MIDDAY_CONFIRMATIONS = 4` (line 119). Advances lootbox index (line 971), zeros pending counters (lines 972-973), records `vrfRequestId` and `rngRequestTime` (lines 974-976).
- **CLOSES:** `rawFulfillRandomWords()` stores word directly to `lootboxRngWordByIndex[index]` (AdvanceModule line 1546) when `rngLockedFlag == false`. Clears `vrfRequestId` and `rngRequestTime` (lines 1548-1549).
- **Duration:** Minimum 4 blocks (~48 seconds on Ethereum).

### Key Difference from Daily Window

`requestLootboxRng` does NOT set `rngLockedFlag = true`. The flag remains false throughout the lootbox VRF window. This is documented in Storage line 277: "Mid-day lootbox RNG does NOT set this flag."

### What is Protected

1. **Lootbox index advance (line 971):** New purchases after the request target `index+1`. The pending word resolves `index` (purchases made before the request).

2. **Ticket buffer swap (lines 949-956):** If tickets are pending, `_swapTicketSlot` is called and `midDayTicketRngPending` flag is set. This prevents the swapped tickets from being processed until the lootbox VRF word arrives (enforced at AdvanceModule line 190-193: reverts `NotTimeYet()` if mid-day flag is set and word is zero).

3. **Re-request prevention (line 911):** `if (_lrRead(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK) != 0) revert E()` blocks re-requesting while mid-day ticket processing is pending. Also, `if (rngRequestTime != 0) revert E()` at line 921 blocks if any VRF request is in-flight.

### What is NOT Protected (by rngLockedFlag)

Since `rngLockedFlag` remains false during the lootbox window, ALL functions that check only `rngLockedFlag` are available:

| Function | Can Execute? | State Changed | Impact on Lootbox RNG? |
|----------|-------------|---------------|----------------------|
| `setAutoRebuy` | Yes | Auto-rebuy toggle | None -- does not affect lootbox outcomes |
| `setAutoRebuyTakeProfit` | Yes | Take-profit config | None |
| `setAfKingMode` | Yes | AfKing mode | None |
| `reverseFlip` | Yes | `totalFlipReversals += 1` | **INFO** -- nudges affect the DAILY word, not the lootbox word. Lootbox VRF fulfillment stores directly to `lootboxRngWordByIndex` (line 1546) without applying nudges. Nudges are only applied via `_applyDailyRng` (line 1617-1624) on the daily path. |
| `purchaseDeityPass` | Yes | Deity pass state | None -- deity boons are consumables, not lootbox RNG inputs |
| `purchase / purchaseCoin` | Yes | Lootbox amounts at `index+1`, tickets to write slot | **SAFE** -- new lootbox purchases target `index+1` (after the advance at line 971). Pool writes go through normal path (not frozen unless daily window also open, which is structurally impossible since `requestLootboxRng` requires `rngLockedFlag == false` at line 908 and daily processing requires `rngLockedFlag == true`). |
| `purchaseWhaleBundle` | Yes (including far-future) | Ticket range, lootbox at `index+1` | SAFE -- far-future tickets are unblocked. Lootbox at new index. |
| `placeDegeneretteBet` | Yes | Bet at current index | **SAFE** -- the guard at DegeneretteModule L430 (`lootboxRngWordByIndex[index] != 0 revert RngNotReady()`) checks the current index. During the lootbox window, the current index was just incremented (line 971). `lootboxRngWordByIndex[newIndex]` is 0, so bets CAN be placed and they target the new index whose word does not yet exist. |

### Lootbox Window Summary

The lootbox VRF window relies on **index advance isolation** rather than `rngLockedFlag` mutual exclusion. The design is sound because:

1. Index advance at request time (line 971) ensures new purchases and bets target `index+1`.
2. The pending word resolves purchases/bets at the old index, all committed before the request.
3. `midDayTicketRngPending` flag prevents ticket processing race conditions.
4. The windows are structurally non-overlapping with daily windows (lootbox requires `rngLockedFlag == false`; daily sets it `true`).

---

## Section 3: Between-Day Window (advanceGame to next advanceGame)

### Window Definition

- **OPENS:** `rngGate()` delivers the daily VRF word. `_applyDailyRng()` (AdvanceModule line 1613) stores to `rngWordByDay[day]` (line 1626). The word is now on-chain and visible.
- **CLOSES:** `_requestRng()` (line 1386) sends the next VRF request and sets `rngLockedFlag = true` at the end of the same `advanceGame()` call (or at the end of the next day's call).
- **Duration:** This is the longest window -- from when the daily word is applied until the next VRF request fires. During jackpot phase, this can be minutes (within a single `advanceGame` execution). During purchase phase, this can be hours to days.

### On-Chain Word Visibility

After `_applyDailyRng` writes `rngWordByDay[day]` at line 1626, the word is on-chain. However, this write occurs WITHIN the same `advanceGame()` transaction that processes all daily jackpots. The sequence within a single `advanceGame` call is:

1. `rngGate()` delivers word (line 266-272)
2. If `rngWord == 1`: VRF request just sent, break with `STAGE_RNG_REQUESTED` (line 276)
3. If word available: proceed to daily processing in same tx
4. Purchase phase: `payDailyJackpot()` (line 340), `_payDailyCoinJackpot()` (line 341), then `_unlockRng()` (line 353)
5. Jackpot phase: `payDailyJackpot()` (line 407), then `_unlockRng()` (line 408)

**The word is consumed and all jackpot distributions are determined atomically within the same transaction that reveals the word.** There is no window between word revelation and consumption for an attacker to intervene.

### What State Gets Resolved by This Word

All of the following are resolved within the same `advanceGame()` call:

| Consumer | Data Resolved | State Committed Before Word? |
|----------|--------------|------------------------------|
| `payDailyJackpot` (JackpotModule L310) | Winning traits, bucket rotation, ETH distribution, ticket distribution, carryover | Yes -- ticket holders committed via `_swapAndFreeze` at VRF request (prior `advanceGame`). Trait bucket populations built from frozen read slot tickets. |
| `_payDailyCoinJackpot` | BURNIE/ticket distribution | Yes -- same commitment as above |
| `coinflip.processCoinflipPayouts` (via rngGate L1032) | Coinflip win/loss for today | Yes -- bets placed during purchase phase before VRF request |
| `resolveRedemptionPeriod` (via rngGate L1041-1049) | Redemption roll [25, 175] | Yes -- redemption requests submitted before VRF request |
| `_finalizeLootboxRng` (via rngGate L1052) | Lootbox word for current index | Yes -- lootbox purchases committed at prior index |

### Between-Day Risk Assessment

**No exploitable window exists.** The daily VRF word is consumed atomically within the same transaction that reveals it. All inputs (ticket holders, coinflip bets, redemption requests, lootbox purchases) were committed before the VRF request fired in a prior `advanceGame` call.

The word IS visible on-chain after the transaction, but by that point all outcomes have been determined. Future purchases and bets target the NEXT cycle (new write slot, new lootbox index).

---

## Section 4: Gameover Window

### Window Definition

`_gameOverEntropy()` (AdvanceModule line 1083) fires when:
1. Liveness guard triggers (level 0: `DEPLOY_IDLE_TIMEOUT_DAYS = 365`; level 1+: 120 days without target met)
2. VRF is stalled (rngRequestTime set, no word delivered, elapsed >= `GAMEOVER_RNG_FALLBACK_DELAY = 3 days`, line 1123)

### prevrandao Source Analysis

`_getHistoricalRngFallback()` (line 1177) constructs:
```
word = keccak256(combined_historical_words, currentDay, block.prevrandao)
```

Where:
- `combined_historical_words`: up to 5 early `rngWordByDay[searchDay]` entries (lines 1183-1195), hashed sequentially
- `currentDay`: deterministic from block.timestamp
- `block.prevrandao`: the only source of unpredictability in the fallback

### Validator/Proposer Attack Model

A block proposer who calls `advanceGame()` triggering the gameover path knows `block.prevrandao` for their block. They can:

1. **Choose to include or exclude** the `advanceGame()` transaction (1-bit manipulation)
2. They CANNOT choose an arbitrary `prevrandao` value (it is derived from the beacon chain RANDAO)
3. They CANNOT see future `prevrandao` values for blocks they do not produce

**Practical impact:** The proposer could decide "is the gameover outcome favorable to me?" and choose to include or skip the transaction. This gives at most 1-bit of bias.

### What State Gets Resolved by prevrandao

| Consumer | Data Resolved | Committed Before Gameover? |
|----------|--------------|---------------------------|
| `handleGameOverDrain` (GameOverModule L97) | Terminal jackpot: 10% decimator, 90% next-level ticket holders | Yes -- all ticket holders and decimator claims committed during purchase phase, potentially months before gameover triggers |
| `coinflip.processCoinflipPayouts` (line 1128) | Coinflip resolution for gameover day | Yes -- bets placed during active game |
| `resolveRedemptionPeriod` (line 1144) | Pending redemption resolution | Yes -- redemption requests submitted during active game |
| `_finalizeLootboxRng` (line 1150) | Lootbox word for pending index | Yes -- lootbox purchases committed during active game |

### Gameover Risk Assessment

**prevrandao is known to the block proposer** at the time they construct the block containing the gameover `advanceGame` call. The historical VRF words are also known (they are on-chain). Therefore:

- **If historical words exist (level 1+):** The combined hash mixes committed VRF entropy with `prevrandao`. The proposer can compute the outcome but can only choose include/exclude (1-bit).
- **If no historical words exist (level 0):** `combined` is 0, making the hash `keccak256(0, currentDay, block.prevrandao)`. This is purely `prevrandao`-dependent. However, at level 0 the distributable funds are minimal (no completed purchase phases), making the 1-bit bias economically irrelevant.

**Risk: INFO** -- The gameover fallback is a terminal one-time event that only fires after VRF has been dead for 3+ days. The 1-bit proposer bias is an accepted tradeoff documented in the code comments (lines 1168-1174).

---

## Overall Risk Matrix

| Window | Duration | How It Opens | Controllable State During Window | Risk Level | Rationale |
|--------|----------|-------------|----------------------------------|------------|-----------|
| Daily VRF | ~10 blocks (~120s) | `_requestRng()` sets `rngLockedFlag = true` (L1442) | Purchases (write slot only), lootbox (new index only), bets (new index only). Auto-rebuy, nudge, deity pass BLOCKED. | SAFE | Double-buffer + index advance + pool freeze isolate all pending RNG state from new writes. rngLockedFlag blocks all functions that could influence pending outcomes. |
| Lootbox VRF | ~4 blocks (~48s) | `requestLootboxRng()` sends request, advances index (L971) | Everything -- rngLockedFlag is NOT set. All functions available. | SAFE | Index advance isolates pending purchases. Bets check word existence (L430). Nudges only affect daily word (not lootbox). No function can change state that the pending lootbox word will resolve. |
| Between-Day | Same tx as word delivery | `_applyDailyRng()` stores word to `rngWordByDay[day]` (L1626) | None during consumption -- word consumed atomically in same tx | SAFE | No window exists between word revelation and consumption. All inputs committed before VRF request. |
| Gameover | 1 block (proposer knowledge) | `_gameOverEntropy()` fallback after 3-day VRF stall (L1123) | Block proposer knows `prevrandao` for their block | INFO | 1-bit proposer bias (include/exclude tx). Terminal one-time event. At level 0: no meaningful funds. At level 1+: historical VRF words add entropy beyond prevrandao. Accepted tradeoff per code comments. |

**Aggregate:** 3 SAFE windows, 1 INFO (gameover prevrandao -- accepted design tradeoff). Zero VULNERABLE windows. Zero CONCERN classifications.

### Threat Register Disposition

| Threat ID | Disposition | Evidence |
|-----------|-------------|---------|
| T-215-07 (State changes during rngLocked window) | **MITIGATED** | 9 guard sites block all functions that could change RNG-affecting state. Double-buffer, index advance, and pool freeze provide defense-in-depth. Purchase/bet writes target post-window state exclusively. |
| T-215-08 (Lootbox purchase during lootbox VRF window) | **MITIGATED** | Index advance at line 971 ensures new purchases target `index+1`. Pending word resolves prior-index purchases only. Bet guard at DegeneretteModule L430 independently verifies word absence. |
| T-215-09 (prevrandao known to proposer) | **ACCEPTED** | 1-bit bias in gameover-only fallback path. VRF stall 3+ days required. Level 0: minimal funds. Level 1+: historical VRF words dilute bias. Documented in code comments. |
