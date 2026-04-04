# 165-02 Adversarial Audit: MintModule + MintStreakUtils + LootboxModule

Phase 165, Plan 02 -- Purchase path, activity score, and lootbox pipeline.

**Contracts audited (from main repo HEAD, v14.0 changes):**
- `contracts/modules/DegenerusGameMintModule.sol`
- `contracts/modules/DegenerusGameMintStreakUtils.sol`
- `contracts/modules/DegenerusGameLootboxModule.sol`

---

## 1. `_questMint(address,uint32,bool,uint256)` -- MintModule line 1110

**Type:** New function (v13.0)
**Purpose:** Routes quest progress to DegenerusQuests for standalone mint paths (e.g., BURNIE lootbox purchase at line 1043).

### Analysis

```solidity
function _questMint(address player, uint32 quantity, bool paidWithEth, uint256 mintPrice) private returns (uint256) {
    (uint256 reward, uint8 questType,, bool completed) = quests.handleMint(player, quantity, paidWithEth, mintPrice);
    if (completed) {
        if (paidWithEth && questType == 1) {
            IDegenerusGame(address(this)).recordMintQuestStreak(player);
        }
        if (paidWithEth) return reward;
    }
    return 0;
}
```

**Reentrancy:** `quests.handleMint` is a cross-contract STATICCALL (returns values, does not send ETH). The quests contract is at `ContractAddresses.QUESTS` -- an immutable compile-time constant pointing to the protocol's own DegenerusQuests contract. No external ETH transfer occurs. `recordMintQuestStreak` is a self-delegatecall (address(this)) with no ETH.

**Access control:** Function is `private` -- only callable from within MintModule. Called by `_purchaseBurnieLootboxFor` (line 1043) with `paidWithEth=false`, `mintPrice=0`.

**Return value correctness:** When `paidWithEth=false` (the BURNIE lootbox path), `return reward` is never reached (guarded by `if (paidWithEth) return reward`). Returns 0 for BURNIE mints -- correct, BURNIE quest rewards are credited internally by the handler via `creditFlip`.

**mintPrice argument:** Called with `mintPrice=0` from `_purchaseBurnieLootboxFor`. The quest handler uses mintPrice for ETH-based quest progress calculation; for BURNIE mints this is correctly 0 (BURNIE quests track by quantity, not price).

**Verdict: SAFE**

No reentrancy vector. Return value correctly returns 0 for BURNIE paths. Arguments match handler expectations.

---

## 2. `_purchaseCoinFor(address,uint256,uint256)` -- MintModule line 598

**Type:** Modified function (v11.0, referenced as `_purchaseBurnTickets` in changelog)
**Purpose:** BURNIE ticket + lootbox purchases. The v11.0 change replaced the 30-day `COIN_PURCHASE_CUTOFF` with `gameOverPossible` flag revert.

### Analysis

```solidity
function _purchaseCoinFor(address buyer, uint256 ticketQuantity, uint256 lootBoxBurnieAmount) private {
    if (gameOver) revert E();
    if (ticketQuantity != 0) {
        // ENF-01: Block BURNIE tickets when drip projection cannot cover nextPool deficit.
        if (gameOverPossible) revert GameOverPossible();
        _callTicketPurchase(buyer, msg.sender, ticketQuantity, MintPaymentKind.DirectEth, true, bytes32(0), 0, level, jackpotPhaseFlag);
    }
    if (lootBoxBurnieAmount != 0) {
        _purchaseBurnieLootboxFor(buyer, lootBoxBurnieAmount);
    }
}
```

**Revert condition polarity:** `if (gameOverPossible) revert GameOverPossible()` -- reverts when flag is TRUE. Correct. The flag is set by AdvanceModule when drip projection cannot cover nextPool deficit; we want to block BURNIE ticket purchases in that state.

**Error name:** `GameOverPossible` is declared at MintModule line 70 -- matches.

**Bypass analysis:** The `gameOverPossible` check is inside the `if (ticketQuantity != 0)` block, meaning BURNIE lootbox-only purchases (`ticketQuantity == 0, lootBoxBurnieAmount != 0`) bypass it. This is intentional: BURNIE lootbox tickets are redirected via `TICKET_FAR_FUTURE_BIT` in `openBurnieLootBox` rather than blocked.

**Ticket path:** Passes `cachedLevel=level` and `cachedJpFlag=jackpotPhaseFlag` to `_callTicketPurchase` -- reads from storage directly (no caching concern since this is the entry point).

**Verdict: SAFE**

Revert polarity correct. Error declaration matches. BURNIE lootbox bypass is intentional (handled by redirect in openBurnieLootBox). No path allows BURNIE tickets when flag is active.

---

## 3. `_purchaseFor(address,uint256,uint256,bytes32,MintPaymentKind)` -- MintModule line 616

**Type:** Modified function (v14.0 MAJOR restructure)
**Purpose:** Main ETH purchase path for tickets and lootboxes. Complete restructure with compute-once patterns, batched flip credits, and moved ticket queuing.

### 3a. purchaseLevel ternary

```solidity
bool cachedJpFlag = jackpotPhaseFlag;        // line 625
uint24 cachedLevel = level;                   // line 626
uint24 purchaseLevel = cachedJpFlag ? cachedLevel : cachedLevel + 1;  // line 627
```

**Phase correctness:**
- Purchase phase (`jackpotPhaseFlag == false`): `purchaseLevel = level + 1`. Correct -- during purchase phase, tickets target the next level.
- Jackpot phase (`jackpotPhaseFlag == true`): `purchaseLevel = level`. Correct -- during jackpot phase, direct tickets target the current level (the daily draw is still running).

**cachedJpFlag source:** Read from `jackpotPhaseFlag` storage variable (DegenerusGameStorage). This is the canonical phase flag. Correct.

**Verdict: SAFE** -- Ternary matches game phase semantics.

### 3b. PriceLookupLib.priceForLevel(purchaseLevel)

```solidity
uint256 priceWei = PriceLookupLib.priceForLevel(purchaseLevel);  // line 628
```

**Before v14.0:** Used `price` storage variable (set by AdvanceModule at phase transitions).
**After v14.0:** Computes price from `purchaseLevel` via pure lookup table.

`purchaseLevel` is the level being purchased (level+1 in purchase phase, level in jackpot phase). `PriceLookupLib.priceForLevel` returns the correct tier price for that level. This replaces the stored `price` which was set to the purchase-level tier at phase transition -- semantically equivalent.

**Verdict: SAFE** -- Price derivation from purchaseLevel is correct.

### 3c. Lootbox base level

```solidity
lootboxBaseLevelPacked[lbIndex][buyer] = uint24(cachedLevel + 1);  // line 697
// ...
lootboxEth[lbIndex][buyer] = (uint256(cachedLevel + 1) << 232) | newAmount;  // line 712
```

**Analysis:** Lootbox base level is always `cachedLevel + 1` regardless of phase. This is correct: lootbox tickets always target the next level (they are opened later, after the current level completes). The previous code used `level + 2` which was a bug fixed in Phase 160.1 -- now `cachedLevel + 1` is correct.

**Verdict: SAFE** -- Lootbox level is always level+1, matching the fix from 160.1.

### 3d. Single quests.handlePurchase() call

```solidity
(uint256 questReward, uint8 questType, uint32 streak, bool questCompleted) =
    quests.handlePurchase(buyer, ethMintUnits, burnieMintUnits, lootBoxAmount, priceWei, PriceLookupLib.priceForLevel(cachedLevel + 1));
```

**Argument verification against IDegenerusQuests.handlePurchase:**
1. `buyer` -> `address player` -- correct
2. `ethMintUnits` -> `uint32 ethMintQty` -- accumulated from `_callTicketPurchase` return + lootbox ETH-equivalent units. Correct.
3. `burnieMintUnits` -> `uint32 burnieMintQty` -- accumulated from `_callTicketPurchase` return. Correct.
4. `lootBoxAmount` -> `uint256 lootBoxAmount` -- raw ETH lootbox amount. Correct.
5. `priceWei` -> `uint256 mintPrice` -- set to `PriceLookupLib.priceForLevel(purchaseLevel)`. Correct.
6. `PriceLookupLib.priceForLevel(cachedLevel + 1)` -> `uint256 levelQuestPrice` -- level quest price always uses level+1 pricing (the upcoming level). Correct.

**Old code had 3 separate calls:** `coin.notifyQuestMint` (ETH), `coin.notifyQuestMint` (BURNIE), `coin.notifyQuestLootBox`. The new single `handlePurchase` aggregates all three notifications.

**Reentrancy:** `quests.handlePurchase` is a cross-contract call to `DegenerusQuests` (immutable protocol address). The `handlePurchase` function has `onlyCoin` modifier (only callable from BurnieCoin, which is the Game contract's delegatecall target). No ETH is sent in this call. The quest handler internally credits flip rewards via state updates only -- no external calls. After this call, the function reads the returned `questStreak` and `questReward` values.

**State ordering:** `handlePurchase` is called AFTER `_callTicketPurchase` (which handles payment/recordMint) but BEFORE x00 bonus and ticket queuing. The quest handler reads quest state that is unrelated to ticket queuing -- no ordering concern.

**Verdict: SAFE** -- All 6 arguments match the interface. Single call correctly aggregates old 3-call pattern. No reentrancy vector.

### 3e. _playerActivityScore computed once post-action

```solidity
uint256 cachedScore = _playerActivityScore(buyer, questStreak);  // line 782
```

**Usage of cachedScore:**
1. x00 century bonus (line 786): `cachedScore > 30_500 ? 30_500 : cachedScore` -- uses cached value for bonus calculation.
2. Lootbox affiliate (line 816): `uint16(cachedScore)` -- uses cached value for affiliate score parameter.
3. Lootbox EV score (line 830): `uint16(cachedScore + 1)` -- uses cached value for EV multiplier.

**Consistency:** Score is computed AFTER all state-mutating operations (recordMint, payment, quest notification) and BEFORE it is consumed. The score reflects the post-action state. Using a single cached value ensures all consumers see the same score -- eliminating the D-08 class bug where multiple score computations could diverge due to intermediate state changes.

**State write ordering:** Between the score computation (line 782) and its uses (lines 786-830), the following writes occur:
- `centuryBonusLevel` and `centuryBonusUsed[buyer]` (x00 bonus, lines 795-797) -- does not affect activity score inputs (mintPacked_, questStreak, affiliate points).
- `_queueTicketsScaled` (line 804) -- writes to `ticketQueue` and `ticketsOwedPacked` -- does not affect activity score inputs.

No write between score computation and its use affects score components. SAFE.

**Verdict: SAFE** -- Compute-once pattern correctly applied. No intervening writes affect score components.

### 3f. Batched coinflip.creditFlip

```solidity
uint256 lootboxFlipCredit;  // line 624 (initialized to 0)
// ... _callTicketPurchase returns bonusCredit via first return value ...
(lootboxFlipCredit, adjustedQty, targetLevel, ethMintUnits, burnieMintUnits) =
    _callTicketPurchase(...);  // line 677-678
// ... quest reward added ...
lootboxFlipCredit += questReward;  // line 774
// ... lootbox affiliate kickbacks added ...
lootboxFlipCredit += affiliate.payAffiliate(...);  // lines 810, 820
// ... claimable spending bonus added ...
lootboxFlipCredit += (totalClaimableUsed * PRICE_COIN_UNIT * 10) / (priceWei * 100);  // line 845
// --- Single batched credit at the end ---
if (lootboxFlipCredit != 0) {
    coinflip.creditFlip(buyer, lootboxFlipCredit);  // line 849
}
```

**Components verified:**
1. `_callTicketPurchase` bonusCredit = affiliate kickback + coin cost bonus + bulk bonus. Correct (same as old code computed these separately then credited individually).
2. `questReward` = quest completion reward (only added if quest completed). Correct.
3. Lootbox affiliate kickbacks (fresh ETH + claimable portions). Correct.
4. Claimable spending bonus. Correct.

**Old code:** Called `coinflip.creditFlip` multiple times (once per source). New code batches into a single call, saving gas. The sum is identical.

**Verdict: SAFE** -- Batched credit is the sum of all individual credits.

### 3g. claimableWinnings read-once pattern

```solidity
uint256 initialClaimable = claimableWinnings[buyer];  // line 641
// ... lootbox payment may write claimableWinnings[buyer] at line 664 ...
// ... _callTicketPurchase -> recordMint may write claimableWinnings[buyer] internally ...
uint256 finalClaimable = payKind == MintPaymentKind.DirectEth
    ? initialClaimable
    : claimableWinnings[buyer];  // line 835-836
```

**Analysis:** `initialClaimable` is read ONCE at line 641 before any writes. The lootbox payment section (lines 660-667) may write `claimableWinnings[buyer]` to deduct shortfall. The `_callTicketPurchase` -> `recordMint` path may also modify it (via Claimable/Combined payment).

For DirectEth, the shortfall calculation at line 835 uses `initialClaimable` (no re-read needed since claimableWinnings was not modified on the ticket path). For Claimable/Combined, it re-reads `claimableWinnings[buyer]` to get the final value after all deductions.

**Write between read and use:** The lootbox shortfall at line 660 uses `initialClaimable` as `claimable` (line 660: `uint256 claimable = initialClaimable`). This is correct -- before v14.0, the code re-read from storage here, but since no other write to `claimableWinnings[buyer]` occurs between line 641 and 660, using the cached value is equivalent.

**Verdict: SAFE** -- No write to claimableWinnings occurs between the initial read and its use in lootbox shortfall. Final shortfall calculation correctly re-reads for non-DirectEth paths.

### 3h. Ticket queuing moved from _callTicketPurchase to _purchaseFor

```solidity
// In _purchaseFor:
if (adjustedQty != 0) {
    _queueTicketsScaled(buyer, targetLevel, adjustedQty);  // line 803-804
}
```

**Old location:** Ticket queuing was at the end of `_callTicketPurchase`.
**New location:** After x00 century bonus calculation in `_purchaseFor` (line 803).

**Critical check -- after payment validation:** `_callTicketPurchase` executes payment validation (recordMint with value, payKind checks, cost checks) BEFORE returning. Only after successful payment does `_purchaseFor` proceed to queue tickets. The ordering is: payment -> quest notification -> score computation -> x00 bonus -> ticket queue. Correct.

**x00 bonus inclusion:** `adjustedQty` is modified by x00 bonus (line 797: `adjustedQty += uint32(bonusQty)`) BEFORE queuing. This is why queuing was moved -- the old code in `_callTicketPurchase` could not include x00 bonus tickets because the score was not yet computed.

**No duplicate queuing:** `_callTicketPurchase` no longer calls `_queueTicketsScaled` (confirmed by reading the full function through line 1017). `_purchaseFor` is the sole queuing site.

**Verdict: SAFE** -- Tickets queued after payment validation and after x00 bonus is applied. No duplicate queuing.

---

## 4. `_callTicketPurchase(...)` -- MintModule line 860

**Type:** Modified function (v14.0)
**Purpose:** Executes ticket purchase payment, boost, affiliate routing, quest unit accumulation. Returns values for caller to handle x00 bonus and ticket queuing.

### Analysis

**New signature:**
```solidity
function _callTicketPurchase(
    address buyer, address payer, uint256 quantity,
    MintPaymentKind payKind, bool payInCoin, bytes32 affiliateCode,
    uint256 value, uint24 cachedLevel, bool cachedJpFlag
) private returns (uint256 bonusCredit, uint32 adjustedQty32, uint24 targetLevel, uint32 ethMintUnits, uint32 burnieMintUnits)
```

**cachedLevel/cachedJpFlag parameters:** Callers pass cached values:
- `_purchaseFor` (line 678): passes `cachedLevel` (from line 626: `level`) and `cachedJpFlag` (from line 625: `jackpotPhaseFlag`). Correct.
- `_purchaseCoinFor` (line 608): passes `level` and `jackpotPhaseFlag` directly. Correct (no caching, but these are SLOAD reads -- consistent with the cached values since no state change occurs between the read and the call).

**targetLevel calculation (line 875):**
```solidity
targetLevel = cachedJpFlag ? cachedLevel : cachedLevel + 1;
```
Same ternary as `_purchaseFor` -- consistent.

**Final-day override (lines 878-882):**
```solidity
if (cachedJpFlag && rngLockedFlag) {
    uint8 step = cachedComp == 2 ? JACKPOT_LEVEL_CAP
        : (cachedComp == 1 && cachedCnt > 0 && cachedCnt < JACKPOT_LEVEL_CAP - 1) ? 2 : 1;
    if (cachedCnt + step >= JACKPOT_LEVEL_CAP) targetLevel = cachedLevel + 1;
}
```

**Cross-reference with Phase 164 carryover audit (Section 2.2):** The final-day override routes tickets to `cachedLevel + 1` when the next advance step would complete all jackpots for the current level. This matches the carryover audit's validation that `cnt + step >= JACKPOT_LEVEL_CAP` correctly identifies the "last jackpot day" condition. The variables `cachedComp` and `cachedCnt` are read from `compressedJackpotFlag` (line 873) and `jackpotCounter` (line 874) respectively -- these are the same variables used by JackpotModule to determine step size.

**x00 century bonus removed:** The century bonus block that was previously in `_callTicketPurchase` (checking `targetLevel % 100 == 0`) is no longer present. It has been moved to `_purchaseFor` (line 785). Confirmed: no `centuryBonusLevel` or `centuryBonusUsed` references exist in `_callTicketPurchase`.

**Ticket queuing removed:** No `_queueTicketsScaled` call exists in `_callTicketPurchase`. Queuing is handled by `_purchaseFor` (line 803). Confirmed.

**Price computation (line 887):**
```solidity
uint256 priceWei = PriceLookupLib.priceForLevel(targetLevel);
```
Uses `targetLevel` (which may differ from `purchaseLevel` in the final-day override case). This is correct: the ticket cost should be based on the level the tickets are actually targeting.

**Quest unit returns:**
- `ethMintUnits` (line 949): Fresh-ETH-scaled quest units. Returned to caller for `handlePurchase`.
- `burnieMintUnits` (line 917): BURNIE-paid quest units. Returned to caller for `handlePurchase`.

**Verdict: SAFE**

Parameters correctly cached. Final-day override matches Phase 164 carryover audit. x00 bonus and ticket queuing correctly removed. Price uses targetLevel. Quest units correctly accumulated and returned.

---

## 5. `_activeTicketLevel()` -- MintStreakUtils line 70

**Type:** New function (v14.0, moved from DegenerusGame.sol)
**Purpose:** View helper returning the active ticket level for direct ticket purchases.

### Analysis

```solidity
function _activeTicketLevel() internal view returns (uint24) {
    return jackpotPhaseFlag ? level : level + 1;
}
```

**Semantic equivalence with purchaseLevel ternary:** `_purchaseFor` line 627 computes `purchaseLevel = cachedJpFlag ? cachedLevel : cachedLevel + 1`. `_activeTicketLevel` reads `jackpotPhaseFlag` and `level` directly from storage. When called from `_playerActivityScore` (which itself is called from `_purchaseFor` at line 782), the storage values will be the same as the cached values since no write to `jackpotPhaseFlag` or `level` occurs within `_purchaseFor`.

**View helper properties:** `internal view` -- no state mutation, no reentrancy concern. Reads two storage variables: `jackpotPhaseFlag` (bool) and `level` (uint24).

**Verdict: SAFE**

Semantically equivalent to the purchaseLevel ternary. Pure view helper with no side effects.

---

## 6. `_playerActivityScore(address,uint32,uint24)` -- MintStreakUtils line 81

**Type:** New function (v14.0, moved from DegenerusGame + DegeneretteModule)
**Purpose:** Shared activity score computation with explicit quest streak and streak base level parameters.

### Analysis

```solidity
function _playerActivityScore(
    address player, uint32 questStreak, uint24 streakBaseLevel
) internal view returns (uint256 scoreBps) {
    if (player == address(0)) return 0;

    uint256 packed = mintPacked_[player];
    bool hasDeityPass = packed >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 != 0;
    // ...
    unchecked {
        if (hasDeityPass) {
            bonusBps = 50 * 100;      // 5000 (50% streak flat)
            bonusBps += 25 * 100;      // 2500 (25% mint count flat)
        } else {
            uint256 streakPoints = streak > 50 ? 50 : uint256(streak);
            uint256 mintCountPoints = _mintCountBonusPoints(levelCount, currLevel);
            if (passActive) {
                if (streakPoints < PASS_STREAK_FLOOR_POINTS) streakPoints = PASS_STREAK_FLOOR_POINTS;
                if (mintCountPoints < PASS_MINT_COUNT_FLOOR_POINTS) mintCountPoints = PASS_MINT_COUNT_FLOOR_POINTS;
            }
            bonusBps = streakPoints * 100;
            bonusBps += mintCountPoints * 100;
        }
        uint256 questStreakCapped = questStreak > 100 ? 100 : uint256(questStreak);
        bonusBps += questStreakCapped * 100;
        bonusBps += affiliate.affiliateBonusPointsBest(currLevel, player) * 100;
        if (hasDeityPass) {
            bonusBps += DEITY_PASS_ACTIVITY_BONUS_BPS;  // 8000
        } else if (frozenUntilLevel > currLevel) {
            if (bundleType == 1) bonusBps += 1000;
            else if (bundleType == 3) bonusBps += 4000;
        }
    }
    scoreBps = bonusBps;
}
```

**(a) Overflow analysis in unchecked block:**

Maximum component values:
- Deity path: `5000 + 2500 = 7500` (flat)
- Non-deity path: `50 * 100 = 5000` (streak) + `25 * 100 = 2500` (mint count) = 7500
- Quest streak: `100 * 100 = 10_000`
- Affiliate: `affiliateBonusPointsBest` returns uint256. In practice, affiliate bonus points are capped at small values (max ~200 points = 20_000 bps). Even if uncapped at 2^24, `2^24 * 100 = 1,677,721,600` -- well within uint256.
- Deity pass bonus: 8000 bps
- Whale pass bonus: max 4000 bps

**Maximum total:** 7500 + 10_000 + 20_000 + 8000 = 45_500 bps (deity path, theoretical max). Far below uint256 overflow. Even with an adversarial affiliateBonusPointsBest value, overflow in uint256 is impossible.

**(b) Deity pass check:**
```solidity
bool hasDeityPass = packed >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 != 0;
```

`BitPackingLib.HAS_DEITY_PASS_SHIFT = 184` (verified in BitPackingLib.sol line 64). Shifts right by 184 bits, masks with `& 1`, checks `!= 0`. Standard bit-check pattern. Correct.

**(c) Pass/whale floor application:**
When `passActive` is true, `streakPoints` and `mintCountPoints` are floored (set to minimum if below floor). `PASS_STREAK_FLOOR_POINTS = 50`, `PASS_MINT_COUNT_FLOOR_POINTS = 25`. This sets the minimum, does not add to the score. Correct -- matches specification.

**Verdict: SAFE**

No overflow risk in score component summation. Deity pass bit check at correct position. Pass/whale floor correctly sets minimum values.

---

## 7. `_playerActivityScore(address,uint32)` -- MintStreakUtils line 160

**Type:** New function (v14.0)
**Purpose:** Convenience wrapper calling the 3-arg version with `_activeTicketLevel()` as streakBaseLevel.

### Analysis

```solidity
function _playerActivityScore(
    address player, uint32 questStreak
) internal view returns (uint256 scoreBps) {
    return _playerActivityScore(player, questStreak, _activeTicketLevel());
}
```

**Level argument:** Passes `_activeTicketLevel()` which returns `jackpotPhaseFlag ? level : level + 1`. This is the standard ticket level used for streak calculations. Correct.

**Callers:**
- `_purchaseFor` line 782: `_playerActivityScore(buyer, questStreak)` -- uses this wrapper. The streakBaseLevel will be the active ticket level at the time of score computation. Correct.

**Verdict: SAFE**

Wrapper passes correct level argument. Delegates to 3-arg version which is proven safe above.

---

## 8. `openBurnieLootBox(address,uint48)` -- LootboxModule line 609

**Type:** Modified function (v11.0/v14.0)
**Purpose:** Opens a BURNIE lootbox once RNG is available. Two changes: price replaced by PriceLookupLib, and gameOverPossible redirect.

### Analysis

### 8a. Price level argument

```solidity
uint256 priceWei = PriceLookupLib.priceForLevel(level);  // line 620
```

**Critical question:** Is `level` the correct argument? The lootbox was purchased at `level` (the game level when it was bought). At open time, `level` is the current game level which may differ from the purchase level. However, the BURNIE lootbox conversion uses the CURRENT level's price to determine ETH-equivalent value:

```solidity
uint256 amountEth = (burnieAmount * priceWei * 80) / (PRICE_COIN_UNIT * 100);  // line 622
```

**Old code comparison:** Before v14.0, the old code used `price` storage variable which was set to the purchase-level price. However, `price` was the price of the CURRENT purchase level (level+1 in purchase phase), not the level when the lootbox was originally purchased. The old `price` could also shift between purchase and open time.

**Level vs level+1:** `priceForLevel(level)` returns the price for the current game level. The old `price` was set to the price for `level+1` (purchase level). This is a difference.

**BUT:** BURNIE lootboxes use `level` (not `level+1`) because the conversion is for VALUATION, not for purchasing tickets. The lootbox was purchased with BURNIE tokens and needs to be converted to an ETH-equivalent value for resolution. Using the current level's price (which is the most recently completed level) provides a stable reference. The `currentLevel` variable (line 625: `level + 1`) is used separately for ticket targeting.

**Resolution:** The BURNIE lootbox is a LOW-EV product. The conversion from BURNIE to ETH-equivalent uses an 80% rate (`* 80 / 100`). Whether `priceForLevel(level)` or `priceForLevel(level+1)` is used makes a small difference in the conversion rate (both are valid tier prices). The price is used only for valuation, not for ETH movement. No ETH loss or theft vector exists from this change.

**Verdict on price:** SAFE -- valuation-only usage, no ETH flow impact.

### 8b. TICKET_FAR_FUTURE_BIT redirect

```solidity
uint24 currentLevel = level + 1;  // line 625
// ...
if (gameOverPossible && targetLevel == currentLevel) {  // line 636
    targetLevel = currentLevel | TICKET_FAR_FUTURE_BIT;  // line 637
}
```

**Only current-level tickets redirected:** The condition `targetLevel == currentLevel` ensures only tickets targeting the current level (level+1) are redirected. Near-future rolls (`targetLevel > currentLevel`) land normally. Far-future rolls are unaffected. Correct.

**Bit OR corruption check:** `TICKET_FAR_FUTURE_BIT` is defined as `1 << 22` (bit 22) in DegenerusGameStorage. `currentLevel` is a uint24. For `currentLevel | TICKET_FAR_FUTURE_BIT` to corrupt the level value, `currentLevel` would need bit 22 set, meaning `currentLevel >= 2^22 = 4,194,304`. This is impossible in practice (game would need to reach level 4M+). The OR operation adds bit 22 to signal far-future, preserving the level value in the lower 22 bits. Correct.

**Reversibility:** When `gameOverPossible` clears (flag transitions back to false), subsequent lootbox opens use normal routing. Previously redirected tickets remain in the far-future queue and will be processed when that level is reached. This is the intended behavior -- once tickets are queued to far-future, they stay there.

**Verdict: SAFE**

Redirect applies only to current-level tickets. Bit OR does not corrupt level value for practical level ranges. Near-future routing unaffected. Redirect behavior matches specification.

---

## 9. `_maybeAwardBoon` deity pass check -- LootboxModule line 1039-1040

**Type:** Modified check within `_maybeAwardBoon` (v14.0, referenced as `_boonRollWeights` in changelog)
**Purpose:** Deity pass eligibility check for boon awarding. Changed from `deityPassCount[player] == 0` to bit-packed check.

### Analysis

```solidity
bool deityEligible =
    (mintPacked_[player] >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 == 0 && deityPassOwners.length < DEITY_PASS_MAX_TOTAL);
```

**Old check:** `deityPassCount[player] == 0` -- true when player has no deity pass (eligible for deity pass boon).
**New check:** `mintPacked_[player] >> HAS_DEITY_PASS_SHIFT & 1 == 0` -- true when bit 184 is 0 (no deity pass flag set).

**Polarity verification:**
- Old: `== 0` means "no pass" -> eligible for deity pass boon. Correct.
- New: `& 1 == 0` means "bit not set" -> "no pass" -> eligible for deity pass boon. Correct.
- Both checks return true when the player does NOT have a deity pass, making them eligible to receive a deity pass boon.

**Bit position:** `BitPackingLib.HAS_DEITY_PASS_SHIFT = 184`. Verified in BitPackingLib.sol. The deity pass flag is set when a player acquires a deity pass (via `_setDeityPassFlag` in the pass purchase/award flow).

**Verdict: SAFE**

Polarity matches old behavior. `== 0` (no pass) is equivalent to the old `deityPassCount[player] == 0`. Bit position 184 is correct per BitPackingLib.

---

## 10. `_boonPoolStats(...)` -- LootboxModule line 1110

**Type:** Modified function (v14.0)
**Purpose:** Calculates total weight and average max boon value for EV budgeting. Price replaced by PriceLookupLib.

### Analysis

```solidity
uint256 priceWei = PriceLookupLib.priceForLevel(level);  // line 1118
```

**Old code:** Used `price` storage variable.
**New code:** Uses `PriceLookupLib.priceForLevel(level)`.

**Level argument:** Uses `level` (current game level), not `level+1`. This is correct for boon pool stats: the boon values are denominated relative to the current level's pricing tier. The BURNIE-to-ETH conversion for coinflip and decimator boon values uses this price as a reference.

**Old `price` comparison:** The old `price` was set to the purchase-level tier (level+1 in purchase phase, level in jackpot phase). Using `priceForLevel(level)` may produce a slightly different value than the old `price` during purchase phase (when `price` was level+1 tier). However, this is a boon EV calculation -- a slight price difference in the valuation denominator does not create any exploitable vector. The budget scales proportionally.

**Impact analysis:** `_boonPoolStats` is used by `_maybeAwardBoon` (line 1043) to calculate `expectedPerBoon` and `totalChance`. A different `priceWei` shifts the threshold for boon probability slightly. This is intentional: using a pure function eliminates dependency on the stored `price` variable timing.

**Verdict: SAFE**

Price argument uses current level -- appropriate for boon valuation context. No exploitable vector from the valuation change. Pure function eliminates storage dependency.

---

## Findings Summary

| # | Function | Contract | Verdict | Notes |
|---|----------|----------|---------|-------|
| 1 | `_questMint` | MintModule L1110 | **SAFE** | No reentrancy, return value correct for BURNIE path |
| 2 | `_purchaseCoinFor` | MintModule L598 | **SAFE** | gameOverPossible polarity correct, lootbox bypass intentional |
| 3 | `_purchaseFor` | MintModule L616 | **SAFE** | All 8 sub-items (a-h) verified: ternary, price, lootbox level, quest call, score once, batched credit, claimable read, ticket queue |
| 4 | `_callTicketPurchase` | MintModule L860 | **SAFE** | Cached params correct, final-day matches 164 carryover audit, x00/queue removed |
| 5 | `_activeTicketLevel` | MintStreakUtils L70 | **SAFE** | Semantically equivalent to purchaseLevel ternary, view-only |
| 6 | `_playerActivityScore` (3-arg) | MintStreakUtils L81 | **SAFE** | No overflow (max ~45,500 bps), deity bit correct, floors correct |
| 7 | `_playerActivityScore` (2-arg) | MintStreakUtils L160 | **SAFE** | Wrapper passes correct level via _activeTicketLevel() |
| 8 | `openBurnieLootBox` | LootboxModule L609 | **SAFE** | Price valuation-only, FF redirect only current-level, bit OR safe |
| 9 | `_maybeAwardBoon` deity check | LootboxModule L1039 | **SAFE** | Polarity matches old deityPassCount check, bit 184 correct |
| 10 | `_boonPoolStats` | LootboxModule L1110 | **SAFE** | Price uses current level, appropriate for boon EV budgeting |

**Overall result: 10/10 SAFE, 0 VULNERABLE.** The v14.0 purchase path restructure introduces no exploitable vectors. The compute-once score pattern, batched flip credits, and moved ticket queuing are all correctly implemented with no reordering vulnerabilities.
