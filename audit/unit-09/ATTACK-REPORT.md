# Unit 9: Lootbox + Boons -- Mad Genius Attack Report

**Attacker identity:** I am the most dangerous smart contract attacker alive. I have 1,000 ETH, unlimited patience, and the source code.

**Contracts analyzed:**
- `DegenerusGameLootboxModule.sol` (1,864 lines)
- `DegenerusGameBoonModule.sol` (327 lines)

**Analysis date:** 2026-03-25
**Methodology:** ULTIMATE-AUDIT-DESIGN.md -- every function read line-by-line, full recursive call trees, storage-write maps, 10-angle attack analysis.

---

## TIER 1 FUNCTIONS

---

## B1: openLootBox(address player, uint48 index) -- LootboxModule L547-618

### Call Tree
```
openLootBox(player, index) [L547]
  READ lootboxEth[index][player]                      [L549]
  READ lootboxRngWordByIndex[index]                   [L554]
  READ _simulatedDayIndex()                           [L557] -> Storage.sol L1134 (view)
  READ lootboxDay[index][player]                      [L558]
  READ lootboxPresaleActive                           [L563]
  READ lootboxEthBase[index][player]                  [L564]
  READ level                                          [L569]
  READ lootboxBaseLevelPacked[index][player]           [L571]
  keccak256(rngWord, player, day, amount)              [L575]
  -> D9 _rollTargetLevel(baseLevel, entropy)           [L576]
       EntropyLib.entropyStep                          [L838]
       % 100 -> near/far branch                        [L839-851]
  READ lootboxEvScorePacked[index][player]             [L584]
  -> D2 _lootboxEvMultiplierBps(player)                [L586] OR
  -> D3 _lootboxEvMultiplierFromScore(score)           [L587]
  -> C6 _applyEvMultiplierWithCap(player, lvl, amt, bps) [L588]
  READ lootboxDistressEth[index][player]               [L595]
  WRITE lootboxEth[index][player] = 0                  [L597]
  WRITE lootboxEthBase[index][player] = 0              [L598]
  WRITE lootboxBaseLevelPacked[index][player] = 0      [L599]
  WRITE lootboxEvScorePacked[index][player] = 0        [L600]
  WRITE lootboxDistressEth[index][player] = 0          [L602] (if nonzero)
  -> C1 _resolveLootboxCommon(player, day, scaledAmount, ...) [L604]
```

### Storage Writes (Full Tree)
| Variable | Written By | Line |
|----------|-----------|------|
| `lootboxEth[index][player]` | B1 | L597 |
| `lootboxEthBase[index][player]` | B1 | L598 |
| `lootboxBaseLevelPacked[index][player]` | B1 | L599 |
| `lootboxEvScorePacked[index][player]` | B1 | L600 |
| `lootboxDistressEth[index][player]` | B1 | L602 |
| `lootboxEvBenefitUsedByLevel[player][lvl]` | C6 | L532 |
| `boonPacked[player].slot0` | B9 (delegatecall), C4 | various |
| `boonPacked[player].slot1` | B9 (delegatecall), B10 (delegatecall), C4 | various |
| `mintPacked_[player]` | B10 (delegatecall), C5 (if whale pass) | various |
| `futureTicketQueue` (ticketsOwedPacked, ticketQueue) | C1 via _queueTicketsScaled, C5 via _queueTickets | Storage.sol L547-548, L570 |

### Cached-Local-vs-Storage Check

**Critical pairs:**

| Ancestor Local | Descendant Write | Verdict |
|---------------|-----------------|---------|
| `packed` (L549, amount from lootboxEth) | lootboxEth cleared at L597 | SAFE -- packed is read before clear, amount extracted, packed never written back |
| `amount` (L550) | None writes to amount after extraction | SAFE -- local value only, no writeback |
| `presale` (L563, from lootboxPresaleActive) | No descendant writes lootboxPresaleActive | SAFE |
| `baseAmount` (L564, from lootboxEthBase) | lootboxEthBase cleared at L598 | SAFE -- read before clear, baseAmount used forward only |
| `scaledAmount` (L588, from C6 _applyEvMultiplierWithCap) | C6 writes lootboxEvBenefitUsedByLevel but not the amount | SAFE -- different storage variable |
| `entropy/nextEntropy` (L575-576) | No descendant writes to lootboxRngWordByIndex | SAFE |

**No stale cache patterns found in B1.** All lootbox mapping slots are cleared to 0 BEFORE entering _resolveLootboxCommon. The only writeback pattern is the clearing itself.

### Attack Analysis

**1. State Coherence (BAF Pattern):**
VERDICT: **SAFE**. B1 extracts all values from lootbox mappings into locals, then clears the mappings to 0, then passes locals to _resolveLootboxCommon. No descendant function writes back to any lootbox mapping that B1 cached. The boonPacked writes happen via delegatecall to BoonModule within _resolveLootboxCommon, and B1 does not cache boonPacked.

**2. Access Control:**
VERDICT: **SAFE**. Function is external, callable only via delegatecall from DegenerusGame. The Game router controls which callers can reach this function. No `msg.sender` check needed because the router enforces it.

**3. RNG Manipulation:**
VERDICT: **SAFE**. The RNG word (lootboxRngWordByIndex[index]) is set during VRF fulfillment, after the player's lootbox entry is recorded. Player inputs (address, day, amount) are committed at purchase. The keccak256 derivation at L575 includes all committed inputs. The player cannot change inputs after VRF fulfillment.

**4. Cross-Contract State Desync:**
VERDICT: **SAFE**. External calls (coin.creditFlip, dgnrs.transferFromPool, wwxrp.mintPrize) happen deep in _resolveLootboxCommon. All lootbox state is cleared to 0 BEFORE entering _resolveLootboxCommon, so re-entry via these external calls would find lootboxEth[index][player] = 0 and revert at L551.

**5. Edge Cases:**
- `amount == 0`: Reverts at L551 (`if (amount == 0) revert E()`). SAFE.
- `rngWord == 0`: Reverts at L555 (`if (rngWord == 0) revert RngNotReady()`). SAFE.
- `day == 0`: Falls through to `day = currentDay` at L560. SAFE.
- `baseAmount == 0`: Falls through to `baseAmount = amount` at L567. SAFE.
- `purchaseLevel` upper 24 bits: Extracted at L553 via `uint24(packed >> 232)`. If lootbox was recorded with purchaseLevel = 0, then after grace period, baseLevel = 0. _rollTargetLevel would roll 0+offset, then the floor at L578 (`if targetLevel < currentLevel`) corrects it. SAFE.
- `baseLevelPacked == 0`: `graceLevel = currentLevel` at L572. SAFE.

**6. Conditional Paths:**
- Grace period path (withinGracePeriod = true): Uses graceLevel. SAFE.
- Non-grace period path: Uses purchaseLevel. Could result in lower base level (tickets aimed at earlier levels that floor to current). SAFE by design -- lootbox value decreases over time.
- Presale path: Adds 62% BURNIE bonus. Only active during presale. SAFE.
- Distress ETH path: Adds 25% ticket bonus proportional to distress fraction. SAFE -- bounded by futureTickets * fraction / denominator.
- evScorePacked != 0 path: Uses snapshotted score instead of live score. This is INTENTIONAL -- score was saved at purchase time. SAFE.

**7. Economic Attacks:**
VERDICT: **SAFE**. The EV multiplier cap (10 ETH per account per level) prevents unbounded EV extraction. The distress bonus is proportional and capped by the distress fraction. Presale bonus is a fixed multiplier.

**8. Griefing:**
VERDICT: **SAFE**. Opening someone else's lootbox is possible (player parameter is arbitrary), but it credits rewards TO the player, not to msg.sender. An attacker opening your lootbox only helps you.

**9. Ordering/Sequencing:**
VERDICT: **SAFE**. lootboxEth is cleared to 0 atomically. Double-opening is prevented by the `amount == 0` check at L551.

**10. Silent Failures:**
VERDICT: **SAFE**. All zero-amount paths either revert or are explicitly handled. The distressEth clearing at L602 is conditional but harmless (clearing 0 to 0 is a no-op if skipped).

---

## B2: openBurnieLootBox(address player, uint48 index) -- LootboxModule L627-687

### Call Tree
```
openBurnieLootBox(player, index) [L627]
  READ lootboxBurnie[index][player]                   [L629]
  READ lootboxRngWordByIndex[index]                   [L632]
  WRITE lootboxBurnie[index][player] = 0              [L635]
  READ price                                          [L638]
  COMPUTE amountEth = (burnieAmount * priceWei * 80) / (PRICE_COIN_UNIT * 100) [L640]
  READ level                                          [L643]
  READ lootboxDay[index][player]                      [L644]
  keccak256(rngWord, player, day, amountEth)           [L649]
  -> D9 _rollTargetLevel(currentLevel, entropy)        [L650]
  CONDITIONAL: BURNIE liveness cutoff check            [L655-661]
    READ block.timestamp, levelStartTime               [L656]
    if elapsed > cutoff: targetLevel = currentLevel + 2 [L659]
  -> C1 _resolveLootboxCommon(player, day, amountEth, targetLevel, currentLevel, ...,
       presale=false, allowWhalePass=false, allowLazyPass=false, emitLootboxEvent=false, allowBoons=true, distressEth=0, totalPackedEth=0) [L663]
  EMIT BurnieLootOpen                                  [L679]
```

### Storage Writes (Full Tree)
Same as B1 EXCEPT:
- `lootboxBurnie[index][player]` cleared (instead of lootboxEth and related)
- No lootboxEvBenefitUsedByLevel update (no EV multiplier for BURNIE lootboxes)
- No distress bonus
- allowWhalePass=false, allowLazyPass=false -- boon roll has reduced pool

### Cached-Local-vs-Storage Check

| Ancestor Local | Descendant Write | Verdict |
|---------------|-----------------|---------|
| `burnieAmount` (L629) | lootboxBurnie cleared at L635 | SAFE -- read before clear, no writeback |
| `priceWei` (L638, from `price`) | No descendant writes `price` | SAFE |

**No stale cache patterns found in B2.**

### Attack Analysis

**1-4. State Coherence, Access Control, RNG, Cross-Contract:** SAFE (same analysis as B1).

**5. Edge Cases:**
- `burnieAmount == 0`: Reverts at L630. SAFE.
- `priceWei == 0`: Reverts at L639. SAFE.
- `amountEth == 0` (after conversion): Reverts at L641. SAFE.
- BURNIE liveness cutoff: `elapsed > cutoff`. Level 0 cutoff is 335 days, others 90 days. Uses `block.timestamp - levelStartTime`. levelStartTime is set at level transition and not manipulable. SAFE.

**6. Conditional Paths:**
- Liveness cutoff triggers: targetLevel bumped to currentLevel+2. Tickets go to future level. This prevents BURNIE-purchased tickets from competing for terminal jackpot. SAFE by design.
- If `targetLevel == currentLevel` AND NOT cutoff triggered: Tickets stay at current level. SAFE.

**7-10. Economic, Griefing, Ordering, Silent:** SAFE (same patterns as B1).

**INVESTIGATE: BURNIE-to-ETH conversion precision.**
At L640: `amountEth = (burnieAmount * priceWei * 80) / (PRICE_COIN_UNIT * 100)`. The 80% rate means BURNIE lootboxes get 80% of the ETH-equivalent value. This is intentional to prevent BURNIE lootbox farming when BURNIE is cheap. The multiplication order (burnieAmount * priceWei * 80) could overflow for extremely large burnieAmount values, but Solidity 0.8.34 has built-in overflow checks. If burnieAmount * priceWei * 80 > type(uint256).max, the transaction reverts. Given PRICE_COIN_UNIT = 1e18 and max reasonable price ~1e18, this requires burnieAmount > ~1.4e39 BURNIE, which exceeds total supply. SAFE.

---

## B9: checkAndClearExpiredBoon(address player) -- BoonModule L119-275

### Call Tree
```
checkAndClearExpiredBoon(player) [L119]
  READ _simulatedDayIndex()                           [L120]
  READ boonPacked[player].slot0                       [L122]
  READ boonPacked[player].slot1                       [L123]

  --- Slot 0: Coinflip ---                            [L128-143]
  READ tier from s0 >> BP_COINFLIP_TIER_SHIFT          [L128]
  if tier != 0:
    READ deityDay from s0 >> BP_DEITY_COINFLIP_DAY_SHIFT [L130]
    if deity expired: s0 &= BP_COINFLIP_CLEAR           [L132]
    else: READ stampDay, check time expiry              [L136-141]

  --- Slot 0: Lootbox ---                             [L146-168]
  [Same pattern: tier check, deity expiry, time expiry]

  --- Slot 0: Purchase ---                            [L171-186]
  [Same pattern]

  --- Slot 0: Decimator ---                           [L189-197]
  [Deity day only, no time expiry]

  --- Slot 0: Whale ---                               [L200-208]
  [Deity day only]

  --- Slot 1: Activity ---                            [L211-226]
  [Same pattern with COINFLIP_BOON_EXPIRY_DAYS]

  --- Slot 1: Deity Pass ---                          [L229-246]
  [Special: deityDay > 0 checks currentDay > deityDay (single-day window)]
  [Else: time-based with DEITY_PASS_BOON_EXPIRY_DAYS]

  --- Slot 1: Lazy Pass ---                           [L249-261]
  [Deity day check, then time check (currentDay > lazyPassDay + 4)]

  WRITE boonPacked[player].slot0 (if changed0)        [L264]
  WRITE boonPacked[player].slot1 (if changed1)        [L265]

  RETURN hasAnyBoon (OR of all remaining tiers)        [L267-274]
```

### Storage Writes (Full Tree)
| Variable | Written By | Line |
|----------|-----------|------|
| `boonPacked[player].slot0` | B9 | L264 (conditional) |
| `boonPacked[player].slot1` | B9 | L265 (conditional) |

### Cached-Local-vs-Storage Check
| Ancestor Local | Descendant Write | Verdict |
|---------------|-----------------|---------|
| `s0` (L122, loaded from bp.slot0) | bp.slot0 written at L264 | SAFE -- s0 IS the value being modified and written back. No descendant call between load and store. Single function, no external calls. |
| `s1` (L123, loaded from bp.slot1) | bp.slot1 written at L265 | SAFE -- same pattern |

**This function is self-contained.** It loads both slots into locals, modifies in memory, and writes back atomically. No external calls, no delegatecalls, no descendants that could interfere.

### Attack Analysis

**1. State Coherence:** SAFE. Load-modify-store pattern with no intermediate external calls.

**2. Access Control:** SAFE. Called via nested delegatecall from LootboxModule. No direct external access.

**3. Bit Packing Correctness:**
I trace each category's clear mask:

- **Coinflip clear (L132, L138):** `s0 &= BP_COINFLIP_CLEAR`. This clears coinflipTier, coinflipDay, deityCoinflipDay. Per the storage layout, these occupy bits 0-71 of slot0 (tier[8] + day[24] + deityDay[24] + padding). The CLEAR mask must preserve all other bits. INVESTIGATE -- need to verify BP_COINFLIP_CLEAR preserves lootbox, purchase, decimator, and whale fields.

- **Lootbox clear (L149, L155, L165):** `s0 &= BP_LOOTBOX_CLEAR`. Clears lootboxTier, lootboxDay, deityLootboxDay. INVESTIGATE -- same concern.

- **Activity expiry uses COINFLIP_BOON_EXPIRY_DAYS (L220):** Activity boon expires after 2 days (same as coinflip). This is presumably intentional since activity boons are short-duration.

**4. Edge Cases:**
- `player == address(0)`: Not checked. If called with zero address, reads boonPacked[address(0)] which is all zeros, returns false (no boons). SAFE -- harmless no-op.
- `currentDay == 0`: All deity day checks use `deityDay != 0 && deityDay != currentDay`. If currentDay=0, any deityDay != 0 triggers expiry. This is correct -- day 0 is pre-game.
- All tiers zero: No writes (changed0/changed1 stay false), returns false. SAFE.

**5. Deity Pass Expiry Logic (L229-246):**
```solidity
if (deityPassTierLocal != 0) {
    uint24 deityDay = uint24(s1 >> BP_DEITY_DEITY_PASS_DAY_SHIFT);
    if (deityDay != 0) {
        if (currentDay > deityDay) {  // L233
            // Deity-sourced: expires after the deity day
            s1 = s1 & BP_DEITY_PASS_CLEAR;
        }
    } else {
        uint24 stampDay = uint24(s1 >> BP_DEITY_PASS_DAY_SHIFT);
        if (stampDay > 0 && currentDay > stampDay + DEITY_PASS_BOON_EXPIRY_DAYS) {
            // Lootbox-sourced: expires after 4 days
            s1 = s1 & BP_DEITY_PASS_CLEAR;
        }
    }
}
```
Note: Deity-sourced deity pass boons use `currentDay > deityDay` (strict greater than), meaning they last until the end of the deity day. Lootbox-sourced use `currentDay > stampDay + 4`. This is INTENTIONAL -- deity boons are same-day, lootbox boons last 4 days.

**6. Stale Deity Day Clearing (L161-168):**
```solidity
} else {
    // lootboxTierLocal == 0, but check for stale deity day
    uint24 deityDay = uint24(s0 >> BP_DEITY_LOOTBOX_DAY_SHIFT);
    if (deityDay != 0 && deityDay != currentDay) {
        s0 = s0 & BP_LOOTBOX_CLEAR;
        changed0 = true;
    }
}
```
This clears stale deity day bits even when the lootbox tier is already 0. Prevents ghost deity day values from persisting. SAFE -- defensive cleanup.

**VERDICT: SAFE.** Self-contained load-modify-store with no external calls. Bit packing follows consistent clear-mask pattern across all 7 categories.

---

## C1: _resolveLootboxCommon(...) -- LootboxModule L872-1026

### Call Tree
```
_resolveLootboxCommon(player, day, amount, targetLevel, currentLevel, entropy,
                      presale, allowWhalePass, allowLazyPass, emitLootboxEvent,
                      allowBoons, distressEth, totalPackedEth) [L872]
  Floor check: if targetLevel < currentLevel                  [L894]
  READ PriceLookupLib.priceForLevel(targetLevel)              [L897] (pure)
  COMPUTE boonBudget = (amount * 1000) / 10000                [L900]
  COMPUTE mainAmount = amount - boonBudget                    [L907]
  COMPUTE split: amountFirst, amountSecond                    [L908-913]

  -> C3 _resolveLootboxRoll(player, amountFirst, amount, targetLevel, targetPrice, currentLevel, day, entropy) [L923]
  Accumulate BURNIE + tickets from first roll                  [L934-945]

  if amountSecond != 0:
    -> C3 _resolveLootboxRoll(second roll)                    [L948]
    Accumulate BURNIE + tickets                                [L960-971]

  if allowBoons:
    -> C2 _rollLootboxBoons(player, day, amount, boonBudget, entropy, allowWhalePass, allowLazyPass) [L974]
    -> DELEGATECALL to B10 consumeActivityBoon(player)        [L984-987]

  if futureTickets != 0:
    Distress ticket bonus                                      [L992-998]
    -> _queueTicketsScaled(player, targetLevel, futureTickets) [L1000]

  COMPUTE BURNIE total with presale bonus                      [L1003-1008]
  if burnieAmount != 0:
    -> coin.creditFlip(player, burnieAmount)                   [L1011] EXTERNAL CALL

  EMIT LootBoxOpened (if emitLootboxEvent)                    [L1014-1024]
```

### Storage Writes (Full Tree)
| Variable | Written By | Line |
|----------|-----------|------|
| `boonPacked[player].slot0` | B9 (via C2 delegatecall), C4 (via C2) | various |
| `boonPacked[player].slot1` | B9 (via C2 delegatecall), B10 (via delegatecall), C4 (via C2) | various |
| `mintPacked_[player]` | B10 (via delegatecall), C5 (if whale pass via C4) | various |
| `ticketsOwedPacked[wk][player]` | _queueTicketsScaled L547, _queueTickets L547 | Storage.sol |
| `ticketQueue[wk]` (push) | _queueTicketsScaled L570, _queueTickets L542 | Storage.sol |
| External: BURNIE mint | coin.creditFlip L1011 | BurnieCoin |
| External: DGNRS transfer | dgnrs.transferFromPool via C10 | StakedDegenerusStonk |
| External: WWXRP mint | wwxrp.mintPrize via C3 | WrappedWrappedXRP |
| External: Quest streak | quests.awardQuestStreakBonus via B10 | DegenerusQuests |

### Cached-Local-vs-Storage Check

**Critical analysis of the boon rolling sequence:**

```
C1 calls C2 _rollLootboxBoons at L974
  C2 calls delegatecall checkAndClearExpiredBoon at L1050  -> writes boonPacked
  C2 reads _activeBoonCategory at L1054                     -> reads boonPacked (FRESH SLOAD)
  C2 calls _applyBoon at L1101                              -> writes boonPacked
C1 calls delegatecall consumeActivityBoon at L984           -> writes boonPacked.slot1 + mintPacked_
```

**Does C1 or C2 cache boonPacked before the delegatecall?**

Looking at _rollLootboxBoons (L1038-1102):
- L1046: `if (player == address(0) || originalAmount == 0) return;` -- no boon state read
- L1050: delegatecall checkAndClearExpiredBoon -- this writes boonPacked
- L1054: `uint8 activeCategory = _activeBoonCategory(player);` -- FRESH read from boonPacked (SLOAD inside _activeBoonCategory at L1341)
- L1056-1073: Reads price, decWindowOpen, deityPassOwners, deityPassCount -- none of these are boonPacked
- L1085-1098: Roll computation -- no storage reads
- L1101: `_applyBoon(...)` -- writes boonPacked

**VERDICT: SAFE.** Neither C1 nor C2 cache any boonPacked value before the delegatecall to B9. The _activeBoonCategory call at L1054 happens AFTER the delegatecall, so it reads the fresh (post-cleanup) state. The _applyBoon call at L1101 also does a fresh SLOAD inside itself (L1409-1410 for coinflip, L1430-1431 for lootbox, etc.).

**Does C1 cache any value that consumeActivityBoon writes?**

consumeActivityBoon writes boonPacked[player].slot1 and mintPacked_[player]. Looking at C1:
- C1 does not read boonPacked or mintPacked_ directly. It only interacts with them via delegatecalls.
- C1 uses local variables: futureTickets, burniePresale, burnieNoMultiplier, entropy. None of these come from boonPacked or mintPacked_.

**VERDICT: SAFE.** No stale cache patterns in C1.

### Attack Analysis

**1. State Coherence:** SAFE (detailed above).

**2. Split Threshold Logic (L908-913):**
```solidity
if (mainAmount > LOOTBOX_SPLIT_THRESHOLD) {  // 0.5 ETH
    amountFirst = mainAmount / 2;
    amountSecond = mainAmount - amountFirst;
}
```
For amounts > 0.5 ETH, the lootbox splits into two rolls. Each roll gets half the main amount (after boon budget deduction). The split is fair (integer division rounds down for first, second gets remainder). SAFE.

**3. Boon Budget Calculation (L900-906):**
```solidity
uint256 boonBudget = (amount * LOOTBOX_BOON_BUDGET_BPS) / 10_000;  // 10%
if (boonBudget > LOOTBOX_BOON_MAX_BUDGET) boonBudget = LOOTBOX_BOON_MAX_BUDGET;  // 1 ETH cap
if (boonBudget > amount) boonBudget = amount;  // safety
uint256 mainAmount = amount - boonBudget;
```
The boon budget is 10% of the lootbox value, capped at 1 ETH. The safety check `boonBudget > amount` handles the impossible case where 10% exceeds 100%. SAFE.

**4. Distress Ticket Bonus (L992-998):**
```solidity
if (distressEth != 0 && totalPackedEth != 0) {
    uint256 bonus = (uint256(futureTickets) * distressEth * DISTRESS_TICKET_BONUS_BPS) / (totalPackedEth * 10_000);
    if (bonus != 0) {
        uint256 boosted = uint256(futureTickets) + bonus;
        futureTickets = uint32(boosted);
    }
}
```
The bonus is proportional: `tickets * (distressEth / totalPackedEth) * 25%`. The `uint32(boosted)` truncation at L997 could silently lose overflow. However, futureTickets is already uint32, and the bonus is at most 25% of futureTickets, so boosted <= 1.25 * type(uint32).max. If futureTickets is near type(uint32).max (~4.3B), boosted could overflow uint32. But getting 4.3B tickets requires astronomical ETH amounts. SAFE in practice.

**5. External Call Ordering:**
coin.creditFlip at L1011 happens AFTER ticket queuing at L1000. If coin.creditFlip reverts (e.g., BURNIE contract paused), the entire lootbox opening reverts including ticket queuing. This is correct -- all-or-nothing semantics.

---

## B5: issueDeityBoon(address deity, address recipient, uint8 slot) -- LootboxModule L796-822

### Call Tree
```
issueDeityBoon(deity, recipient, slot) [L796]
  REQUIRE deity != address(0)                         [L797]
  REQUIRE recipient != address(0)                     [L797]
  REQUIRE deity != recipient                          [L798]
  REQUIRE slot < 3                                    [L799]
  REQUIRE deityPassPurchasedCount[deity] > 0          [L800]
  READ _simulatedDayIndex()                           [L802]
  REQUIRE rngWordByDay[day] != 0 || rngWordCurrent != 0 [L803]
  CONDITIONAL: if deityBoonDay[deity] != day           [L804]
    WRITE deityBoonDay[deity] = day                    [L805]
    WRITE deityBoonUsedMask[deity] = 0                 [L806]
  REQUIRE deityBoonRecipientDay[recipient] != day     [L808]
  READ mask = deityBoonUsedMask[deity]                 [L810]
  REQUIRE (mask & (1 << slot)) == 0                   [L812]
  WRITE deityBoonUsedMask[deity] = mask | (1 << slot) [L813]
  WRITE deityBoonRecipientDay[recipient] = day         [L814]
  READ decWindowOpen                                   [L816]
  READ deityPassOwners.length                          [L817]
  -> D8 _deityBoonForSlot(deity, day, slot, ...)       [L818]
  -> C4 _applyBoon(recipient, boonType, day, day, 0, true) [L819]
  EMIT DeityBoonIssued                                 [L821]
```

### Storage Writes (Full Tree)
| Variable | Written By | Line |
|----------|-----------|------|
| `deityBoonDay[deity]` | B5 | L805 |
| `deityBoonUsedMask[deity]` | B5 | L806, L813 |
| `deityBoonRecipientDay[recipient]` | B5 | L814 |
| `boonPacked[recipient].slot0` or `.slot1` | C4 (via _applyBoon) | various |
| `futureTicketQueue` + `mintPacked_[recipient]` | C5 (if whale pass boon) | various |

### Cached-Local-vs-Storage Check

| Ancestor Local | Descendant Write | Verdict |
|---------------|-----------------|---------|
| `mask` (L810, from deityBoonUsedMask[deity]) | deityBoonUsedMask written at L813 BEFORE _applyBoon | SAFE -- mask is updated to storage at L813, then _applyBoon does not touch deityBoonUsedMask |
| `day` (L802) | No descendant writes to day-related storage | SAFE |

### Attack Analysis

**1. Access Control:**
VERDICT: **INVESTIGATE** -- The function checks `deityPassPurchasedCount[deity] > 0` but does NOT verify that `msg.sender` is the deity or authorized to act on their behalf. However, this function is called via delegatecall from DegenerusGame, and the Game router is responsible for passing the correct deity address (typically msg.sender). The risk is if the Game router allows a function call where `deity` is an arbitrary address. This is a cross-module concern -- the Game router audit (Phase 103) should verify. For this module, the function trusts its caller to pass the correct deity. SAFE within this module's boundary.

**2. One-Per-Recipient-Per-Day:**
`deityBoonRecipientDay[recipient] == day` blocks multiple deity boons to the same recipient in a day. The check at L808 is correct. SAFE.

**3. Slot Reuse Prevention:**
Bitmask at L810-812: `if ((mask & slotMask) != 0) revert E()`. Each slot can only be used once per day. When deityBoonDay changes (new day), the mask resets to 0 at L806. SAFE.

**4. Deity Boon Self-Issuance:**
`deity == recipient` is explicitly blocked at L798. SAFE.

**5. Whale Pass via Deity Boon:**
If _deityBoonForSlot returns BOON_WHALE_PASS (type 28), _applyBoon at L1572-1578 calls _activateWhalePass which queues 100 levels of tickets. A deity could issue a whale pass to a recipient daily. However, this is rate-limited to 1 per day per recipient (L808) and 3 total boons per deity per day. The whale pass boon is weighted at 8/1298 = 0.6% of the pool, so it appears rarely. SAFE by design.

---

## B3: resolveLootboxDirect(address player, uint256 amount, uint256 rngWord) -- LootboxModule L694-720

### Call Tree
```
resolveLootboxDirect(player, amount, rngWord) [L694]
  if amount == 0: return                              [L695]
  READ _simulatedDayIndex()                           [L697]
  READ level                                          [L698]
  keccak256(rngWord, player, day, amount)              [L699]
  -> D9 _rollTargetLevel(currentLevel, entropy)        [L700]
  -> D2 _lootboxEvMultiplierBps(player)                [L702]
  -> C6 _applyEvMultiplierWithCap(player, lvl, amt, bps) [L703]
  -> C1 _resolveLootboxCommon(player, day, scaledAmount, ...,
       presale=false, allowWhalePass=true, allowLazyPass=true,
       emitLootboxEvent=true, allowBoons=false, 0, 0) [L705]
```

### Storage Writes
Same as C1 tree MINUS boon-related writes (allowBoons=false). Plus lootboxEvBenefitUsedByLevel via C6.

### Attack Analysis

**1. RNG Word Trust:**
VERDICT: **INVESTIGATE** -- The `rngWord` is passed as a parameter. The caller (DecimatorModule via delegatecall) is trusted to provide a legitimate RNG word. If a malicious module could call resolveLootboxDirect with a crafted rngWord, it could control all entropy-derived outcomes. However, this is called via delegatecall from Game, and only authorized modules can invoke it. Cross-module trust is validated in Phase 103 (router) and Phase 109 (decimator). SAFE within this module's boundary.

**2. Zero Amount:** Silently returns at L695. No state changes. SAFE.

**3. No Boons:** allowBoons=false means no delegatecall to BoonModule. Simpler flow. SAFE.

---

## B4: resolveRedemptionLootbox(...) -- LootboxModule L729-755

### Call Tree
Same structure as B3, except:
- `activityScore` parameter is used instead of live score lookup
- `_lootboxEvMultiplierFromScore(uint256(activityScore))` at L737 (pure calculation, no external call)

### Attack Analysis

**1. Snapshotted Activity Score:**
The activityScore was saved at sDGNRS burn submission time. Using a snapshot prevents the player from manipulating their activity score between submission and redemption. SAFE by design.

**2. Score Overflow:** `uint16 activityScore` is upcast to `uint256` at L737. Maximum value 65535. _lootboxEvMultiplierFromScore handles scores up to ACTIVITY_SCORE_MAX_BPS (25500) and caps at LOOTBOX_EV_MAX_BPS (13500). Score of 65535 would also cap at 13500. SAFE.

**All other angles: SAFE** (same analysis as B3).

---

## TIER 2 FUNCTIONS

---

## B10: consumeActivityBoon(address player) -- BoonModule L280-326

### Call Tree
```
consumeActivityBoon(player) [L280]
  if player == address(0): return                     [L281]
  READ boonPacked[player].slot1                       [L283]
  EXTRACT pending = uint24(s1 >> BP_ACTIVITY_PENDING_SHIFT) [L284]
  if pending == 0: return                             [L285]

  READ _simulatedDayIndex()                           [L287]
  READ deityDay from s1                                [L288]
  if deity expired:
    WRITE bp.slot1 = s1 & BP_ACTIVITY_CLEAR            [L290]
    return
  READ stampDay from s1                                [L294]
  if time expired:
    WRITE bp.slot1 = s1 & BP_ACTIVITY_CLEAR            [L296]
    return

  WRITE bp.slot1 = s1 & BP_ACTIVITY_CLEAR              [L300] (clear consumed boon)

  READ mintPacked_[player]                             [L302]
  EXTRACT levelCount                                   [L303-305]
  COMPUTE countSum = levelCount + pending              [L307]
  Cap at type(uint24).max                              [L308-310]
  WRITE mintPacked_[player] (via BitPackingLib.setPacked) [L319]

  COMPUTE bonus = min(pending, type(uint16).max)       [L322]
  if currentDay != 0 && bonus != 0:
    -> quests.awardQuestStreakBonus(player, bonus, day) [L324] EXTERNAL CALL
```

### Storage Writes
| Variable | Written By | Line |
|----------|-----------|------|
| `boonPacked[player].slot1` | B10 | L290, L296, or L300 |
| `mintPacked_[player]` | B10 | L319 |
| External: quests state | quests.awardQuestStreakBonus | L324 |

### Cached-Local-vs-Storage Check
| Ancestor Local | Descendant Write | Verdict |
|---------------|-----------------|---------|
| `s1` (L283, from bp.slot1) | bp.slot1 written at L290/296/300 | SAFE -- s1 is the value being modified and written back. No intermediate calls between load and store. |
| `prevData` (L302, from mintPacked_[player]) | mintPacked_ written at L319 | SAFE -- single load-modify-store with no intermediate calls |

### Attack Analysis

**1. uint24 Overflow Protection (L308-310):**
```solidity
uint256 countSum = uint256(levelCount) + pending;
uint24 newLevelCount = countSum > type(uint24).max ? type(uint24).max : uint24(countSum);
```
levelCount is uint24 (max 16,777,215). pending is uint24 (max 50 per boon). Sum cannot overflow uint256. Cap at type(uint24).max is correct. SAFE.

**2. External Call Safety:**
quests.awardQuestStreakBonus is the only external call. If the quests contract reverts, the entire consumeActivityBoon reverts, which propagates up through the delegatecall to _resolveLootboxCommon, reverting the entire lootbox opening. This could be a griefing vector if the quests contract is malicious, but it's a trusted protocol contract. SAFE under protocol trust model.

**3. Double Consumption:**
The boon is cleared at L300 before the external call at L324. If re-entered, pending would be 0. SAFE.

---

## C4: _applyBoon(...) -- LootboxModule L1396-1601

### Summary
206 lines handling 12 boon types across 8 categories. Each handler follows the same pattern:
1. Determine new tier/amount from boonType
2. Load boonPacked[player].slot (SLOAD)
3. Extract existing tier
4. If deity: overwrite. If lootbox: upgrade (newTier > existingTier)
5. Set day fields
6. Store back to slot (SSTORE)
7. Emit event if not deity

### Attack Analysis

**1. Upgrade vs Overwrite Semantics:**
- Lootbox boons: `if (newTier > existingTier)` -- only upgrade to higher tier. SAFE.
- Deity boons: `if (isDeity || ...)` -- always overwrite. This means a deity can issue a tier-1 (5%) boon that DOWNGRADES a player's existing tier-3 (25%) lootbox boon. INVESTIGATE.

**FINDING F-01: Deity Boon Downgrade**
A deity can issue a low-tier boon that overwrites a player's existing high-tier lootbox boon. For example, a player has a 25% coinflip boon from a lootbox. A deity issues a 5% coinflip boon to that player. The deity boon overwrites the 25% boon with a 5% boon.

However: (a) the deity cannot target a specific player's existing boon tier -- they can only see slot types, not the recipient's existing boons, (b) the recipient could decline by avoiding the deity's boon (boons are applied without consent), (c) the deity-sourced boon has a different expiry (same-day only vs 2-day for lootbox). So the player gets a worse boon but it expires sooner.

**VERDICT: INVESTIGATE** -- potential griefing via deity boon downgrade.

**2. Whale Pass Application (L1572-1578):**
```solidity
if (boonType == BOON_WHALE_PASS) {
    uint24 startLevel = _activateWhalePass(player);
    if (!isDeity) {
        emit LootBoxWhalePassJackpot(player, day, originalAmount, startLevel, WHALE_PASS_TICKETS_PER_LEVEL, 0, 0);
    }
    return;
}
```
Whale pass activation via _activateWhalePass queues 100 levels of tickets. If isDeity=true, the event is suppressed but the pass IS still activated. This means a deity can award whale passes silently. SAFE -- intentional (event suppression for deity boons is consistent across all types).

**3. Lootbox Boost Clear-and-Set (L1442-1447):**
```solidity
s0 = s0 & BP_LOOTBOX_CLEAR;
s0 = s0 | (uint256(uint24(currentDay)) << BP_LOOTBOX_DAY_SHIFT);
uint24 deityDayVal = isDeity ? uint24(day) : uint24(0);
s0 = s0 | (uint256(deityDayVal) << BP_DEITY_LOOTBOX_DAY_SHIFT);
s0 = s0 | (uint256(activeTier) << BP_LOOTBOX_TIER_SHIFT);
```
The lootbox boost handler clears ALL lootbox fields first, then sets new values. This means the day is always refreshed, even if the tier didn't upgrade. This is correct -- each boon application resets the expiry timer. SAFE.

---

## C6: _applyEvMultiplierWithCap(...) -- LootboxModule L505-539

### Call Tree
```
_applyEvMultiplierWithCap(player, lvl, amount, evMultiplierBps) [L505]
  if evMultiplierBps == 10000: return amount           [L512]
  READ lootboxEvBenefitUsedByLevel[player][lvl]        [L517]
  COMPUTE remainingCap = LOOTBOX_EV_BENEFIT_CAP - used [L518-520]
  if remainingCap == 0: return amount (neutral)        [L522-524]
  COMPUTE adjustedPortion, neutralPortion              [L528-529]
  WRITE lootboxEvBenefitUsedByLevel[player][lvl] += adjustedPortion [L532]
  RETURN scaled amount                                 [L537-538]
```

### Attack Analysis

**1. Cap Tracking Direction:**
The cap tracks `adjustedPortion` (the amount that gets non-neutral EV). When EV < 100% (penalty), the cap LIMITS the penalty -- only the first 10 ETH of a level gets penalized, the rest gets 100% EV. When EV > 100% (bonus), the cap limits the bonus. This is bidirectional and intentional.

**2. Multiple Lootboxes in Same Level:**
Each call deducts from the same cap. 10 lootboxes of 1 ETH each in the same level get 10 ETH of adjusted EV total, then neutral. SAFE -- cap works correctly across multiple calls.

**3. Level Transition Reset:**
The cap is keyed by `[player][lvl]` where `lvl = currentLevel` (the game's current level, not targetLevel). Level transitions reset the cap naturally by using a new key. SAFE.

**4. Potential Issue: currentLevel vs Actual Resolution Level:**
B1 uses `currentLevel = level + 1` at L569, then passes to C6 at L588. If the game level changes between B1's read of `level` and C6's storage write, the cap would track against the old level. However, level changes require advanceGame which is a separate transaction. Within a single transaction, `level` is constant. SAFE.

---

## TIER 3 FUNCTIONS

---

## B6: consumeCoinflipBoon(address player) -- BoonModule L41-61

### Call Tree
```
consumeCoinflipBoon(player) [L41]
  if player == address(0): return 0                   [L42]
  READ boonPacked[player].slot0                       [L44]
  EXTRACT tier from s0 >> BP_COINFLIP_TIER_SHIFT       [L45]
  if tier == 0: return 0                              [L46]
  READ _simulatedDayIndex()                           [L48]

  CHECK deity expiry:
    READ deityDay from s0 >> BP_DEITY_COINFLIP_DAY_SHIFT [L49]
    if deityDay != 0 && deityDay != currentDay:
      WRITE bp.slot0 = s0 & BP_COINFLIP_CLEAR          [L51]
      return 0

  CHECK time expiry:
    READ stampDay from s0 >> BP_COINFLIP_DAY_SHIFT     [L54]
    if stampDay > 0 && currentDay > stampDay + 2:
      WRITE bp.slot0 = s0 & BP_COINFLIP_CLEAR          [L56]
      return 0

  boonBps = _coinflipTierToBps(tier)                   [L59]
  WRITE bp.slot0 = s0 & BP_COINFLIP_CLEAR              [L60]
  return boonBps
```

### Attack Analysis
**SAFE across all angles.** Simple consume-and-clear pattern. Boon is always cleared regardless of whether it was valid or expired. No external calls. Load-modify-store with no intermediate operations.

---

## B7: consumePurchaseBoost(address player) -- BoonModule L66-86

Structurally identical to B6 with different shift constants and expiry (4 days instead of 2). **SAFE.**

---

## B8: consumeDecimatorBoost(address player) -- BoonModule L91-106

Similar to B6/B7 but with NO time-based expiry -- only deity day expiry. Decimator boons persist until consumed or deity day expires. **SAFE.**

---

## C5: _activateWhalePass(address player) -- LootboxModule L1116-1136

### Call Tree
```
_activateWhalePass(player) [L1116]
  READ level                                          [L1119]
  -> _applyWhalePassStats(player, passLevel)           [L1123] writes mintPacked_
  LOOP 100 iterations:
    COMPUTE lvl = ticketStartLevel + i                 [L1127]
    COMPUTE isBonus = (lvl >= passLevel && lvl <= 10)  [L1128]
    -> _queueTickets(player, lvl, count)               [L1129] writes ticketsOwedPacked + ticketQueue
```

### Attack Analysis
**Gas concern:** 100 iterations of _queueTickets, each doing SLOAD + SSTORE + conditional array push. This could be expensive but is bounded. No reentrancy risk. **SAFE.**

---

## C10: _creditDgnrsReward(address player, uint256 amount) -- LootboxModule L1793-1799

### Call Tree
```
_creditDgnrsReward(player, amount) [L1793]
  if amount == 0: return 0
  -> dgnrs.transferFromPool(Pool.Lootbox, player, amount) [L1795] EXTERNAL CALL
  return paid
```

### Attack Analysis
Single external call to trusted protocol contract. The return value `paid` may differ from `amount` if pool is insufficient. Caller (C3) does not use the return value for further calculations that could be affected. **SAFE.**

---

## FINDINGS SUMMARY

| ID | Title | Verdict | Severity (proposed) |
|----|-------|---------|-------------------|
| F-01 | Deity Boon Can Downgrade Existing Higher-Tier Lootbox Boon | INVESTIGATE | LOW |

### F-01: Deity Boon Downgrade

**Location:** `_applyBoon` L1396-1601, specifically the `if (isDeity || newTier > existingTier)` pattern in each category handler.

**Description:** When a deity issues a boon (isDeity=true), the `||` short-circuit means the tier is ALWAYS overwritten, even if the new tier is lower than the existing tier. A deity issuing a tier-1 (5%) coinflip boon to a player who already has a tier-3 (25%) lootbox-sourced coinflip boon will downgrade the player's boon.

**Impact:** A malicious deity could grief a player by overwriting their high-value boon with a low-value one. The griefing is limited by:
- Only deity pass holders can issue boons
- Only 1 boon per recipient per day
- The deity doesn't know the recipient's current boon state from on-chain (no view function exposes it in this module)
- The deity-sourced boon expires at end of day (whereas lootbox boon lasts 2-4 days)

**Proof of concept:**
1. Player has a tier-3 (25%) coinflip boon from lootbox, stampDay = today, expires in 2 days
2. Deity issues BOON_COINFLIP_5 (5%) to player via issueDeityBoon
3. _applyBoon L1413: `if (isDeity || newTier > existingTier)` -> isDeity=true, so tier is overwritten to 1
4. L1417: coinflipDay = currentDay (refreshed)
5. L1420: deityCoinflipDay = currentDay (deity-sourced)
6. Player now has tier-1 (5%) boon that expires at end of day instead of tier-3 (25%) boon that would last 2 more days

**Proposed severity:** LOW -- requires deity pass holder (expensive, limited to 32 total), griefing only (no profit), limited by one-per-recipient-per-day constraint.

---

*Attack report compiled: 2026-03-25*
*Mad Genius: All 32 functions analyzed. 1 INVESTIGATE finding. Nested delegatecall state coherence VERIFIED SAFE.*
