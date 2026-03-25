# Unit 6: Whale Purchases -- Attack Report

**Agent:** Mad Genius (Attacker)
**Contract:** DegenerusGameWhaleModule.sol (817 lines)
**Date:** 2026-03-25

---

## Findings Summary

| ID | Function | Verdict | Severity | Title |
|----|----------|---------|----------|-------|
| F-01 | purchaseWhaleBundle | INVESTIGATE | INFO | Boon discount uses WHALE_BUNDLE_STANDARD_PRICE as base even at early levels (0-3) where unit price is 2.4 ETH |
| F-02 | purchaseWhaleBundle | INVESTIGATE | LOW | DGNRS reward loop reads fresh poolBalance each iteration -- diminishing returns per bundle in multi-quantity purchase |
| F-03 | purchaseLazyPass | INVESTIGATE | INFO | _recordLootboxMintDay receives cachedPacked parameter that may overwrite _activate10LevelPass's mintPacked_ write |
| F-04 | purchaseDeityPass | INVESTIGATE | INFO | ERC721 mint callback could re-enter but deity state written before mint prevents re-purchase |
| F-05 | purchaseDeityPass | INVESTIGATE | INFO | Ticket start level calculation at L536 uses different formula than whale bundle -- potential gap in coverage at high levels |
| F-06 | _recordLootboxEntry | INVESTIGATE | INFO | lootboxEvScorePacked reads playerActivityScore via self-delegatecall -- score could be stale if activity changed same tx |

**All 3 Category B functions and 9 Category C helpers analyzed. 2 MULTI-PARENT functions received cross-parent scrutiny. No VULNERABLE findings. 6 INVESTIGATE findings (5 INFO, 1 LOW). No BAF-class cache-overwrite bugs found.**

---

## Part 1: Category B Functions -- Full Attack Analysis

---

## DegenerusGameWhaleModule::purchaseWhaleBundle() (lines 183-310) [B1]

### Call Tree
```
purchaseWhaleBundle(buyer, quantity) [line 183] -- external payable
  +-- _purchaseWhaleBundle(buyer, quantity) [line 184] -- private
       +-- gameOver check [line 191] -- reverts if gameOver == true
       +-- passLevel = level + 1 [line 192] -- CACHE of storage `level`
       +-- quantity bounds check [line 194] -- reverts if 0 or >100
       +-- boonPacked[buyer].slot0 read [line 198-199] -- CACHE of boon state
       |    +-- _simulatedDayIndex() [Storage L1134] -- view, pure time computation
       |    +-- hasValidBoon = currentDay <= boonDay + 4 [line 203]
       +-- mintPacked_[buyer] read [line 206] -- CACHE as prevData
       |    +-- unpack frozenUntilLevel [line 209]
       |    +-- unpack levelCount [line 210]
       +-- freeze extension calculation [lines 216-226] -- pure math on locals
       +-- price calculation [lines 230-244]
       |    +-- if hasValidBoon: _whaleTierToBps(wTier) [Storage L1551] -- pure
       |    |    +-- discountedPrice on first bundle, standard for rest [line 238]
       |    |    +-- bp.slot0 = s0 & BP_WHALE_CLEAR [line 237] -- STORAGE WRITE: clears boon
       |    +-- else: x99 check (passLevel % 100 == 0 && quantity < 2) [line 241]
       |    +-- unitPrice = early (2.4) or standard (4.0) [line 242]
       +-- msg.value == totalPrice check [line 246] -- reverts if mismatch
       +-- _awardEarlybirdDgnrs(buyer, totalPrice, passLevel) [Storage L914] -- INHERITED
       |    +-- may write earlybirdDgnrsPoolStart, earlybirdEthIn [Storage L948,966]
       |    +-- external: dgnrs.transferFromPool(Earlybird, buyer, payout) [Storage L969]
       |    +-- external: dgnrs.transferBetweenPools(Earlybird, Lootbox, remaining) [Storage L932]
       +-- data = prevData (local copy) [line 252]
       +-- BitPackingLib.setPacked x4 [lines 253-256] -- pure transforms on local `data`
       +-- _currentMintDay() [Storage L1144] -- view
       +-- _setMintDay(data, day, ...) [Storage L1153] -- pure transform on local `data`
       +-- mintPacked_[buyer] = data [line 262] -- STORAGE WRITE: full mintPacked_ update
       +-- ticket queuing loop (100 iterations) [lines 267-272]
       |    +-- _queueTickets(buyer, lvl, tickets) [Storage L528] -- per iteration
       |         +-- ticketQueue[wk].push(buyer) [Storage L542] -- if new
       |         +-- ticketsOwedPacked[wk][buyer] update [Storage L547] -- STORAGE WRITE
       +-- affiliate.getReferrer(buyer) [line 274] -- EXTERNAL VIEW
       |    +-- affiliate.getReferrer(affiliateAddr) [line 278] -- upline
       |    +-- affiliate.getReferrer(upline) [line 280] -- upline2
       +-- DGNRS reward loop (quantity iterations) [lines 284-287]
       |    +-- _rewardWhaleBundleDgnrs(buyer, ...) [line 285] -- per iteration
       |         +-- dgnrs.poolBalance(Whale) [line 593] -- EXTERNAL VIEW
       |         +-- dgnrs.transferFromPool(Whale, buyer, minterShare) [line 598] -- EXTERNAL
       |         +-- dgnrs.poolBalance(Affiliate) [line 606] -- EXTERNAL VIEW
       |         +-- levelDgnrsAllocation[level] - levelDgnrsClaimed[level] [line 610] -- STORAGE READ
       |         +-- dgnrs.transferFromPool(Affiliate, affiliateAddr, share) [line 619] -- EXTERNAL
       |         +-- dgnrs.transferFromPool(Affiliate, upline, share) [line 632] -- EXTERNAL
       |         +-- dgnrs.transferFromPool(Affiliate, upline2, share/2) [line 640] -- EXTERNAL
       +-- prize pool split [lines 289-304]
       |    +-- level read [line 292] -- STORAGE READ (not cached local)
       |    +-- prizePoolFrozen read [line 298] -- STORAGE READ
       |    +-- _getPendingPools() or _getPrizePools() [Storage L655/665] -- STORAGE READ
       |    +-- _setPendingPools() or _setPrizePools() [Storage L651/661] -- STORAGE WRITE
       +-- lootbox recording [lines 306-309]
            +-- _recordLootboxEntry(buyer, lootboxAmount, passLevel, data) [line 309]
                 +-- [traced below in C6 standalone section]
```

### Storage Writes (Full Tree)

| Variable | Location | Written By |
|----------|----------|-----------|
| `boonPacked[buyer].slot0` | WhaleModule L237 | C1 (_purchaseWhaleBundle) -- whale boon fields cleared |
| `mintPacked_[buyer]` | WhaleModule L262 | C1 -- full packed data update |
| `ticketsOwedPacked[wk][buyer]` | Storage L547 | _queueTickets (100 iterations) |
| `ticketQueue[wk]` | Storage L542 | _queueTickets (array push, conditional) |
| `earlybirdDgnrsPoolStart` | Storage L924,948 | _awardEarlybirdDgnrs (conditional) |
| `earlybirdEthIn` | Storage L966 | _awardEarlybirdDgnrs |
| `prizePoolsPacked` | Storage L652 | _setPrizePools (if !frozen) |
| `prizePoolPendingPacked` | Storage L662 | _setPendingPools (if frozen) |
| `lootboxDay[idx][buyer]` | WhaleModule L730 | _recordLootboxEntry (if new) |
| `lootboxBaseLevelPacked[idx][buyer]` | WhaleModule L731 | _recordLootboxEntry (if new) |
| `lootboxEvScorePacked[idx][buyer]` | WhaleModule L732 | _recordLootboxEntry (if new) |
| `lootboxEthBase[idx][buyer]` | WhaleModule L748 | _recordLootboxEntry |
| `lootboxEth[idx][buyer]` | WhaleModule L751 | _recordLootboxEntry |
| `lootboxRngPendingEth` | WhaleModule L763 | _maybeRequestLootboxRng |
| `lootboxDistressEth[idx][buyer]` | WhaleModule L756 | _recordLootboxEntry (if distress) |
| `boonPacked[buyer].slot0` | WhaleModule L799 | _applyLootboxBoostOnPurchase (lootbox boost cleared) |
| `mintPacked_[buyer]` | WhaleModule L814 | _recordLootboxMintDay (day field only, conditional) |
| External: dgnrs.transferFromPool | Storage L969, WhaleModule L598,619,632,640 | _awardEarlybirdDgnrs, _rewardWhaleBundleDgnrs |
| External: dgnrs.transferBetweenPools | Storage L932 | _awardEarlybirdDgnrs (one-shot) |

### Cached-Local-vs-Storage Check

| Ancestor Local | Cached At | Descendant Write | Write Location | Verdict |
|---------------|-----------|-----------------|----------------|---------|
| `passLevel = level + 1` | L192 | `level` not written by any descendant in this call tree | N/A | **SAFE** -- `level` is only modified by advanceGame (different module) |
| `s0 = bp.slot0` | L199 | `bp.slot0` written at L237 | L237 (same function) | **SAFE** -- `s0` is used only for boon check (lines 200-203) and tier read (line 232). The write at L237 uses `s0 & BP_WHALE_CLEAR` which operates on the cached value, so no stale writeback. |
| `prevData = mintPacked_[buyer]` | L206 | `mintPacked_[buyer]` written at L262 | L262 (same function) | **SAFE** -- `data` is derived from `prevData` with incremental updates via setPacked. The write at L262 is the authoritative write of the modified local. No descendant writes to mintPacked_ between L206 and L262. |
| `mintPacked_[buyer] = data` at L262 | L262 | `mintPacked_[buyer]` written at L814 | _recordLootboxMintDay L814 | **INVESTIGATE (F-03 pattern)** -- After L262 writes the complete `data` to mintPacked_, `_recordLootboxEntry` is called at L309 with `data` as cachedPacked. Inside, `_recordLootboxMintDay` at L808 receives this `data`. At L810 it checks if prevDay == day. If they match, it returns (no write). If they don't match, L813-814 clears the day field from `cachedPacked` and sets the new day. **BUT** the `data` passed from L309 already has the correct day set by `_setMintDay` at L260. So `prevDay` at L809 will equal `day` from `_simulatedDayIndex` (L720 cast to uint32), and the function returns without writing. **SAFE** -- the cachedPacked parameter has the current day already set. |

**Summary:** No BAF-class cache-overwrite bugs in purchaseWhaleBundle. All cached locals are either not overwritten by descendants, or the descendant write uses the same value.

### Attack Analysis

**1. State Coherence (BAF Pattern):**
SAFE. Traced above -- no ancestor caches a value that a descendant overwrites with different data.

**2. Access Control:**
SAFE. Called via delegatecall from router. The router resolves `buyer` via operator approval (Game.sol L632-638: `_purchaseWhaleBundleFor` calls `_resolvePlayer`). The module function itself has no additional modifier -- it relies on the router to provide a valid `buyer`. An attacker cannot call the module directly (only the router's Game.sol contract has the module address wired). The delegatecall context ensures `msg.sender` and `msg.value` are preserved from the original call to Game.sol.

**3. RNG Manipulation:**
SAFE. No RNG consumed in this function. `_queueTickets` checks `rngLockedFlag` for far-future tickets (Storage L536) but only to prevent queuing during RNG lock, not to consume RNG. No VRF words used.

**4. Cross-Contract State Desync:**
SAFE. External calls to `affiliate.getReferrer` are view-only (read referrer mapping). External calls to `dgnrs.transferFromPool` and `dgnrs.poolBalance` are sequential -- each iteration of the reward loop reads a fresh balance that reflects prior transfers. No assumption of stale external state.

**5. Edge Cases:**
- `quantity == 0`: Reverts at L194. SAFE.
- `quantity == 100`: Allowed. bonusTickets = 40*100 = 4000, standardTickets = 2*100 = 200. uint32 can hold these. SAFE.
- `passLevel == 1` (level 0, first-ever game level): unitPrice = 2.4 ETH (early price). SAFE.
- `passLevel % 100 == 0` (x99 level): Requires quantity >= 2 at L241 (without boon). With boon, the x99 check is bypassed (boon path at L231). SAFE -- the x99 gate only applies to non-boon purchases.
- `frozenUntilLevel > targetFrozenLevel`: deltaFreeze = 0, levelsToAdd = 0, newLevelCount = levelCount (no stat boost). Tickets still queued. SAFE -- player gets tickets but no stat boost if already frozen beyond target.

**FINDING F-01:** When `hasValidBoon == true`, the discounted price at L235 is based on `WHALE_BUNDLE_STANDARD_PRICE` (4 ETH), not the early-level price (2.4 ETH). If `passLevel <= 4`, a non-boon purchase costs 2.4 ETH, but a boon purchase at tier 1 (10% off) costs 3.6 ETH per bundle. This means a boon at early levels is WORSE than no boon.
**Verdict: INVESTIGATE (INFO)** -- This is a design choice, not a vulnerability. The boon always applies to the 4 ETH standard price. At early levels without a boon, the 2.4 ETH price is better. Players would simply not use their boon at early levels. No loss of funds -- the price check at L246 ensures `msg.value == totalPrice`, so the player explicitly agrees to the price.

**6. Conditional Paths:**
- Boon path (hasValidBoon): Discount first bundle at standard price, clear boon. Remaining bundles at standard price.
- Non-boon path: Early price at levels 0-3, standard otherwise. x99 guard.
- prizePoolFrozen path: Uses pending pools instead of active pools. Both paths write to different packed slots.
All paths traced. SAFE.

**7. Economic Attacks:**
**FINDING F-02:** The DGNRS reward loop at L284-287 calls `_rewardWhaleBundleDgnrs` once per quantity. Each iteration reads `dgnrs.poolBalance(Whale)` fresh, computes 1% minter share, transfers it, then the next iteration sees a reduced pool. For quantity=100, the first iteration gets 1% of pool, the second gets 1% of (pool - first transfer), etc. This creates diminishing returns -- the total minter reward is less than 100% of the pool. This is not an exploit -- it's by-design economic diminishment. An attacker buying 100 bundles gets significant DGNRS but cannot drain the entire whale pool.
**Verdict: INVESTIGATE (LOW)** -- The per-iteration diminishing return means the total DGNRS reward is less than `quantity * (whaleReserve * 1%)`. The affiliate pool has the additional `reserved` subtraction (L610-612) that prevents drain below the level allocation. This bounds the total drain.

**8. Griefing:**
SAFE. The function requires payment (msg.value). An attacker griefing by buying whale bundles just... buys whale bundles. No permanent state corruption. The x99 minimum-2-bundles check prevents cheap century bonus farming.

**9. Ordering/Sequencing:**
SAFE. Purchasing whale bundles in any order doesn't produce unexpected state. Each purchase is independent -- the freeze extension is delta-based (no double dipping).

**10. Silent Failures:**
SAFE. `_queueTickets` returns silently if quantity == 0 (Storage L533), but bonusTickets and standardTickets are never 0 (WHALE_BONUS_TICKETS_PER_LEVEL=40, WHALE_STANDARD_TICKETS_PER_LEVEL=2, quantity >= 1). `_awardEarlybirdDgnrs` returns silently if purchaseWei is 0 or currentLevel >= EARLYBIRD_END_LEVEL -- these are correct no-op paths, not bugs.

---

## DegenerusGameWhaleModule::purchaseLazyPass() (lines 325-450) [B2]

### Call Tree
```
purchaseLazyPass(buyer) [line 325] -- external payable
  +-- _purchaseLazyPass(buyer) [line 326] -- private
       +-- gameOver check [line 330] -- reverts if true
       +-- currentLevel = level [line 331] -- CACHE of storage `level`
       +-- boonPacked[buyer].slot1 read [line 333-334] -- CACHE as s1
       |    +-- lazyTier = uint8(s1 >> BP_LAZY_PASS_TIER_SHIFT) [line 335]
       |    +-- _lazyPassTierToBps(lazyTier) [Storage L1559] -- pure
       |    +-- boonDay = uint24(s1 >> BP_LAZY_PASS_DAY_SHIFT) [line 337]
       |    +-- deity-day cross-check [lines 340-344]
       |    |    +-- deityDay = uint24(s1 >> BP_DEITY_LAZY_PASS_DAY_SHIFT) [line 340]
       |    |    +-- if deity expired: clear boon [line 342] -- STORAGE WRITE: bpLazy.slot1
       |    +-- expiry check [line 345]
       |    |    +-- if expired: clear boon [line 348] -- STORAGE WRITE: bpLazy.slot1
       |    +-- stale tier clear [lines 352-356] -- STORAGE WRITE: bpLazy.slot1
       +-- level gate [line 357] -- revert if level > 2 and not x9 (excl x99) and no boon
       +-- deity pass check [line 360] -- revert if deityPassCount[buyer] != 0
       +-- mintPacked_[buyer] read [line 361] -- CACHE as prevData
       |    +-- unpack frozenUntilLevel [lines 362-365]
       +-- renewal window check [line 367] -- revert if frozenUntilLevel > currentLevel + 7
       +-- startLevel computation [line 369]
       +-- _lazyPassCost(startLevel) [line 370] -- pure, D1
       +-- price calculation [lines 377-407] -- multiple paths
       |    +-- levels 0-2: flat 0.24 ETH, bonus tickets from balance
       |    |    +-- PriceLookupLib.priceForLevel(startLevel) [line 384] -- pure
       |    +-- levels 3+: baseCost, boon discount
       +-- boon consumption [lines 408-412]
       |    +-- s1 re-read [line 410] -- fresh STORAGE READ
       |    +-- bpLazy.slot1 = s1 & BP_LAZY_PASS_CLEAR [line 411] -- STORAGE WRITE
       +-- msg.value == totalPrice check [line 413] -- reverts if mismatch
       +-- _awardEarlybirdDgnrs(buyer, benefitValue, startLevel) [Storage L914] -- INHERITED
       |    +-- [same subtree as B1]
       +-- _activate10LevelPass(buyer, startLevel, LAZY_PASS_TICKETS_PER_LEVEL) [Storage L982]
       |    +-- mintPacked_[player] read [Storage L987] -- FRESH STORAGE READ
       |    +-- unpack frozenUntilLevel, lastLevel, levelCount [Storage L989-999]
       |    +-- freeze/stat calculation [Storage L1000-1012]
       |    +-- BitPackingLib.setPacked x4 [Storage L1024-1049]
       |    +-- _currentMintDay() [Storage L1144] -- view
       |    +-- _setMintDay() [Storage L1153] -- pure transform
       |    +-- mintPacked_[player] = data [Storage L1059] -- STORAGE WRITE
       |    +-- _queueTicketRange(player, startLevel, 10, 4) [Storage ~L1061]
       |         +-- _queueTickets per level (10 iterations) [Storage L528]
       +-- bonus ticket queuing [lines 424-426]
       |    +-- _queueTickets(buyer, startLevel, bonusTickets) [Storage L528] -- if bonusTickets != 0
       +-- prize pool split [lines 428-440]
       |    +-- prizePoolFrozen read [line 434] -- STORAGE READ
       |    +-- _getPendingPools() or _getPrizePools() -- STORAGE READ
       |    +-- _setPendingPools() or _setPrizePools() -- STORAGE WRITE
       +-- lootbox recording [lines 442-449]
            +-- lootboxPresaleActive read [line 443] -- STORAGE READ
            +-- lootboxAmount = (benefitValue * lootboxBps) / 10_000 [line 446]
            +-- if lootboxAmount == 0: return [line 447]
            +-- _recordLootboxEntry(buyer, lootboxAmount, currentLevel + 1, mintPacked_[buyer]) [line 449]
                 +-- NOTE: mintPacked_[buyer] is read FRESH here (not cached prevData)
                 +-- [traced below in C6 standalone section]
```

### Storage Writes (Full Tree)

| Variable | Location | Written By |
|----------|----------|-----------|
| `boonPacked[buyer].slot1` | WhaleModule L342,348,354,411 | C2 -- boon cleared on various paths |
| `earlybirdDgnrsPoolStart` | Storage L924,948 | _awardEarlybirdDgnrs (conditional) |
| `earlybirdEthIn` | Storage L966 | _awardEarlybirdDgnrs |
| `mintPacked_[buyer]` | Storage L1059 | _activate10LevelPass -- **KEY WRITE** |
| `ticketsOwedPacked[wk][buyer]` | Storage L547 | _queueTickets (10 iterations + possible bonus) |
| `ticketQueue[wk]` | Storage L542 | _queueTickets (array push, conditional) |
| `prizePoolsPacked` | Storage L652 | _setPrizePools (if !frozen) |
| `prizePoolPendingPacked` | Storage L662 | _setPendingPools (if frozen) |
| `lootboxDay[idx][buyer]` | WhaleModule L730 | _recordLootboxEntry (if new) |
| `lootboxBaseLevelPacked[idx][buyer]` | WhaleModule L731 | _recordLootboxEntry (if new) |
| `lootboxEvScorePacked[idx][buyer]` | WhaleModule L732 | _recordLootboxEntry (if new) |
| `lootboxEthBase[idx][buyer]` | WhaleModule L748 | _recordLootboxEntry |
| `lootboxEth[idx][buyer]` | WhaleModule L751 | _recordLootboxEntry |
| `lootboxRngPendingEth` | WhaleModule L763 | _maybeRequestLootboxRng |
| `lootboxDistressEth[idx][buyer]` | WhaleModule L756 | _recordLootboxEntry (if distress) |
| `boonPacked[buyer].slot0` | WhaleModule L799 | _applyLootboxBoostOnPurchase (lootbox boost cleared) |
| `mintPacked_[buyer]` | WhaleModule L814 | _recordLootboxMintDay (day field only, conditional) |
| External: dgnrs.transferFromPool | Storage L969 | _awardEarlybirdDgnrs |
| External: dgnrs.transferBetweenPools | Storage L932 | _awardEarlybirdDgnrs (one-shot) |

### Cached-Local-vs-Storage Check

| Ancestor Local | Cached At | Descendant Write | Write Location | Verdict |
|---------------|-----------|-----------------|----------------|---------|
| `currentLevel = level` | L331 | `level` not written by any descendant | N/A | **SAFE** -- `level` only modified by advanceGame |
| `s1 = bpLazy.slot1` | L334 | `bpLazy.slot1` written at L342,348,354 | L342/348/354 | **SAFE** -- after potential clearing at L342/348/354, the `s1` variable is NOT reused for further computation. At L410, a FRESH `s1 = bpLazy.slot1` read occurs. |
| `prevData = mintPacked_[buyer]` | L361 | `mintPacked_[buyer]` written at Storage L1059 | _activate10LevelPass | **SAFE** -- `prevData` is used ONLY to unpack `frozenUntilLevel` at L362-365 for the renewal window check at L367. After the checks pass, `prevData` is never used again. The `_activate10LevelPass` call at L417 reads mintPacked_ fresh at Storage L987. |

**FINDING F-03:** At L449, `_recordLootboxEntry` is called with `mintPacked_[buyer]` as the 4th argument. This is a FRESH read from storage (not the stale `prevData`). Inside `_recordLootboxEntry` (L714), the `cachedPacked` parameter is passed to `_recordLootboxMintDay` (L723). At L808-815, `_recordLootboxMintDay` checks if the day in `cachedPacked` matches the current day. If not, it writes a modified version of `cachedPacked` back to `mintPacked_[player]`. The `cachedPacked` value at L449 is the FRESH value written by `_activate10LevelPass` at Storage L1059, which includes the day set by `_setMintDay` at Storage L1052-1057. So the day should match, and `_recordLootboxMintDay` returns without writing.

**BUT:** There is a subtle issue. `_activate10LevelPass` calls `_currentMintDay()` at Storage L1051, which returns `uint32(_simulatedDayIndex())` at Storage L1145. Meanwhile, `_recordLootboxMintDay` at L809 reads `prevDay = uint32((cachedPacked >> BitPackingLib.DAY_SHIFT) & BitPackingLib.MASK_32)`. Then `_recordLootboxEntry` at L720 computes `dayIndex = _simulatedDayIndex()` as uint48, and passes `uint32(dayIndex)` to `_recordLootboxMintDay` at L723. These should be identical (both derived from `_simulatedDayIndex` in the same transaction). So the day matches and no write occurs.

**Verdict: INVESTIGATE (INFO)** -- The fresh read at L449 and the consistent day derivation make this safe. The `cachedPacked` parameter at L449 reflects the `_activate10LevelPass` write, so there is no stale data. The `_recordLootboxMintDay` write path is a no-op because the day already matches.

**Summary:** No BAF-class cache-overwrite bugs in purchaseLazyPass. The key concern (mintPacked_ cache) is safe because: (a) prevData is only used for the frozenUntilLevel check and never written back, (b) _activate10LevelPass reads/writes mintPacked_ fresh, (c) the lootbox call reads mintPacked_ fresh.

### Attack Analysis

**1. State Coherence (BAF Pattern):**
SAFE. Traced above. prevData is read-only for validation. _activate10LevelPass does its own fresh read/write cycle. Lootbox call reads fresh mintPacked_.

**2. Access Control:**
SAFE. Same delegatecall pattern as B1. Router resolves buyer via operator approval.

**3. RNG Manipulation:**
SAFE. No RNG consumed. `_queueTickets` checks rngLockedFlag for far-future tickets but this is a guard, not RNG consumption.

**4. Cross-Contract State Desync:**
SAFE. The only external call is `_awardEarlybirdDgnrs` to the sDGNRS contract. Sequential, no stale assumption.

**5. Edge Cases:**
- `currentLevel == 0`: startLevel = 1 (L369, special case). benefitValue = 0.24 ETH. baseCost = _lazyPassCost(1). balance = 0.24 ETH - baseCost. bonusTickets calculated from balance. SAFE.
- `currentLevel == 2`: Still in flat-price range. SAFE.
- `currentLevel == 3`: First computed-price level. baseCost = sum of 10 level prices starting at level 4. SAFE.
- `currentLevel == 9`: x9 gate passes (9 % 10 == 9). SAFE.
- `currentLevel == 99`: x99 exclusion (99 % 100 == 99) without boon. Reverts at L357. With boon, allowed. SAFE.
- `frozenUntilLevel == currentLevel + 7`: Passes renewal check (L367: > currentLevel + 7 reverts). SAFE.
- `frozenUntilLevel == currentLevel + 8`: Reverts -- 8 > 7. SAFE.
- `deityPassCount[buyer] != 0`: Reverts at L360. Deity pass holders cannot buy lazy pass. SAFE.
- `lootboxAmount == 0`: Returns at L447 without recording lootbox. This can happen if benefitValue is very small and lootboxBps rounds down. SAFE -- no-op is correct.

**6. Conditional Paths:**
- Deity-day cross-check (L340-344): If deity boon day exists but doesn't match current day, lazy boon is cleared. This prevents cross-contamination between deity-granted and lootbox-rolled boons.
- Boon expiry (L345-351): Expired boon cleared, hasValidBoon stays false.
- Stale tier (L352-356): Tier without day cleared.
- Level 0-2 flat price vs level 3+ computed price: Both paths traced. SAFE.
All conditional paths traced. No silent skip.

**7. Economic Attacks:**
SAFE. Price is deterministic based on level and boon state. No MEV opportunity -- the price is fixed for the current state. An attacker cannot manipulate the price by front-running (level changes require advanceGame which is gated by its own timing).

**8. Griefing:**
SAFE. Requires payment. Cannot grief without spending ETH.

**9. Ordering/Sequencing:**
SAFE. Lazy pass purchase is independent. The deity pass block (L360) prevents lazy+deity overlap. The renewal window (L367) prevents stacking.

**10. Silent Failures:**
SAFE. All revert conditions are explicit. The lootboxAmount == 0 return at L447 is intentional.

---

## DegenerusGameWhaleModule::purchaseDeityPass() (lines 470-565) [B3]

### Call Tree
```
purchaseDeityPass(buyer, symbolId) [line 470] -- external payable
  +-- _purchaseDeityPass(buyer, symbolId) [line 471] -- private
       +-- rngLockedFlag check [line 475] -- reverts RngLocked if true
       +-- gameOver check [line 476] -- reverts if true
       +-- symbolId >= 32 check [line 477] -- reverts if out of range
       +-- deityBySymbol[symbolId] != address(0) check [line 478] -- reverts if symbol taken
       +-- deityPassCount[buyer] != 0 check [line 479] -- reverts if already owns pass
       +-- k = deityPassOwners.length [line 481] -- STORAGE READ
       +-- basePrice = DEITY_PASS_BASE + (k * (k+1) * 1 ether) / 2 [line 482]
       +-- boon discount [lines 484-505]
       |    +-- boonPacked[buyer].slot1 read [line 487] -- CACHE as s1Deity
       |    +-- boonTier = uint8(s1Deity >> BP_DEITY_PASS_TIER_SHIFT) [line 488]
       |    +-- if boonTier != 0:
       |    |    +-- deity-day expiry check [lines 492-498]
       |    |    +-- if !expired: compute discountBps from tier [line 500]
       |    |    +-- totalPrice = basePrice * (10_000 - discountBps) / 10_000 [line 501]
       |    +-- bpDeity.slot1 = s1Deity & BP_DEITY_PASS_CLEAR [line 504] -- STORAGE WRITE (always)
       +-- msg.value == totalPrice check [line 506] -- reverts if mismatch
       +-- passLevel = level + 1 [line 508] -- CACHE of storage `level`
       +-- deityPassPaidTotal[buyer] += totalPrice [line 511] -- STORAGE WRITE
       +-- _awardEarlybirdDgnrs(buyer, totalPrice, passLevel) [Storage L914] -- INHERITED
       +-- deityPassCount[buyer] = 1 [line 514] -- STORAGE WRITE
       +-- deityPassPurchasedCount[buyer] += 1 [line 515] -- STORAGE WRITE
       +-- deityPassOwners.push(buyer) [line 516] -- STORAGE WRITE (array extend)
       +-- deityPassSymbol[buyer] = symbolId [line 517] -- STORAGE WRITE
       +-- deityBySymbol[symbolId] = buyer [line 518] -- STORAGE WRITE
       +-- IDegenerusDeityPassMint.mint(buyer, symbolId) [line 521] -- EXTERNAL CALL
       +-- affiliate lookup [lines 524-532] -- EXTERNAL VIEW x3
       +-- _rewardDeityPassDgnrs(buyer, affiliateAddr, upline, upline2) [line 533]
       |    +-- dgnrs.poolBalance(Whale) [line 658] -- EXTERNAL VIEW
       |    +-- dgnrs.transferFromPool(Whale, buyer, totalReward) [line 662] -- EXTERNAL
       |    +-- dgnrs.poolBalance(Affiliate) [line 673] -- EXTERNAL VIEW
       |    +-- reserved = levelDgnrsAllocation[level] - levelDgnrsClaimed[level] [line 677]
       |    +-- dgnrs.transferFromPool(Affiliate, affiliateAddr, share) [line 686] -- EXTERNAL
       |    +-- dgnrs.transferFromPool(Affiliate, upline, share) [line 699] -- EXTERNAL
       |    +-- dgnrs.transferFromPool(Affiliate, upline2, share/2) [line 705] -- EXTERNAL
       +-- ticket queuing loop (100 iterations) [lines 536-542]
       |    +-- ticketStartLevel = passLevel <= 4 ? 1 : uint24(((passLevel+1)/50)*50+1) [line 536]
       |    +-- _queueTickets(buyer, lvl, 40 or 2) [Storage L528] -- per iteration
       +-- prize pool split [lines 544-557]
       |    +-- level read [line 546] -- STORAGE READ
       |    +-- _getPendingPools() or _getPrizePools() -- STORAGE READ
       |    +-- _setPendingPools() or _setPrizePools() -- STORAGE WRITE
       +-- lootbox recording [lines 559-564]
            +-- lootboxPresaleActive read [line 560] -- STORAGE READ
            +-- if lootboxAmount != 0:
                 +-- _recordLootboxEntry(buyer, lootboxAmount, passLevel, mintPacked_[buyer]) [line 563]
                      +-- NOTE: mintPacked_[buyer] is read FRESH here
```

### Storage Writes (Full Tree)

| Variable | Location | Written By |
|----------|----------|-----------|
| `boonPacked[buyer].slot1` | WhaleModule L504 | C3 -- deity pass boon fields cleared (always) |
| `deityPassPaidTotal[buyer]` | WhaleModule L511 | C3 -- cumulative payment |
| `deityPassCount[buyer]` | WhaleModule L514 | C3 -- set to 1 |
| `deityPassPurchasedCount[buyer]` | WhaleModule L515 | C3 -- incremented |
| `deityPassOwners` | WhaleModule L516 | C3 -- array push |
| `deityPassSymbol[buyer]` | WhaleModule L517 | C3 -- symbol assignment |
| `deityBySymbol[symbolId]` | WhaleModule L518 | C3 -- symbol->owner mapping |
| `earlybirdDgnrsPoolStart` | Storage L924,948 | _awardEarlybirdDgnrs |
| `earlybirdEthIn` | Storage L966 | _awardEarlybirdDgnrs |
| `ticketsOwedPacked[wk][buyer]` | Storage L547 | _queueTickets (100 iterations) |
| `ticketQueue[wk]` | Storage L542 | _queueTickets |
| `prizePoolsPacked` | Storage L652 | _setPrizePools |
| `prizePoolPendingPacked` | Storage L662 | _setPendingPools |
| `lootboxDay[idx][buyer]` | WhaleModule L730 | _recordLootboxEntry |
| `lootboxBaseLevelPacked[idx][buyer]` | WhaleModule L731 | _recordLootboxEntry |
| `lootboxEvScorePacked[idx][buyer]` | WhaleModule L732 | _recordLootboxEntry |
| `lootboxEthBase[idx][buyer]` | WhaleModule L748 | _recordLootboxEntry |
| `lootboxEth[idx][buyer]` | WhaleModule L751 | _recordLootboxEntry |
| `lootboxRngPendingEth` | WhaleModule L763 | _maybeRequestLootboxRng |
| `lootboxDistressEth[idx][buyer]` | WhaleModule L756 | _recordLootboxEntry |
| `boonPacked[buyer].slot0` | WhaleModule L799 | _applyLootboxBoostOnPurchase |
| `mintPacked_[buyer]` | WhaleModule L814 | _recordLootboxMintDay (conditional) |
| External: IDegenerusDeityPassMint.mint | WhaleModule L521 | C3 -- ERC721 mint |
| External: dgnrs.transferFromPool | Storage L969, WhaleModule L662,686,699,705 | _awardEarlybirdDgnrs, _rewardDeityPassDgnrs |

### Cached-Local-vs-Storage Check

| Ancestor Local | Cached At | Descendant Write | Write Location | Verdict |
|---------------|-----------|-----------------|----------------|---------|
| `k = deityPassOwners.length` | L481 | `deityPassOwners.push(buyer)` at L516 | L516 | **SAFE** -- `k` is used only for price calculation at L482. The push at L516 happens AFTER price validation (L506). The price is locked before the array grows. No stale use of `k` after L516. |
| `s1Deity = bpDeity.slot1` | L487 | `bpDeity.slot1` written at L504 | L504 | **SAFE** -- `s1Deity` used for tier extraction at L488 and expiry check at L492-498. The write at L504 uses `s1Deity & BP_DEITY_PASS_CLEAR` which operates on the cached value. No stale writeback concern. |
| `passLevel = level + 1` | L508 | `level` not written by any descendant | N/A | **SAFE** |

**Summary:** No BAF-class cache-overwrite bugs in purchaseDeityPass.

### Attack Analysis

**1. State Coherence (BAF Pattern):**
SAFE. No ancestor caches a value that a descendant overwrites with different data.

**2. Access Control:**
SAFE. Delegatecall from router with operator approval. Additional guards: rngLockedFlag (L475), gameOver (L476), symbolId range (L477), symbol uniqueness (L478), one-per-player (L479).

**3. RNG Manipulation:**
SAFE. No RNG consumed. The `rngLockedFlag` check at L475 is a GUARD (prevents purchase during RNG lock), not RNG consumption. This is unique to deity pass -- whale bundle and lazy pass don't have this check. The reason: deity pass affects the jackpot distribution (virtual trait entries), so purchasing during RNG resolution could create inconsistency.

**4. Cross-Contract State Desync:**
**FINDING F-04:** The ERC721 mint at L521 calls `IDegenerusDeityPassMint(ContractAddresses.DEITY_PASS).mint(buyer, symbolId)`. If the DeityPass contract uses OpenZeppelin's `_safeMint`, the `onERC721Received` callback would execute on the `buyer` address if it's a contract. At this point, all deity-specific state has been written (L514-518: deityPassCount=1, deityBySymbol set, etc.). If the buyer's `onERC721Received` callback re-enters `purchaseDeityPass`, it would fail at L479 (`deityPassCount[buyer] != 0`). If it re-enters other purchase functions (whaleBundle, lazyPass), those don't check deityPassCount, but the lazy pass check at L360 (`deityPassCount[buyer] != 0`) would block re-entry into lazy pass.
**Verdict: INVESTIGATE (INFO)** -- Re-entry is prevented by state being set before the external call. The deity pass mint is the only external call before the function completes. Post-mint logic (affiliate lookup, DGNRS rewards, ticket queuing, pool split, lootbox) would not be affected by re-entry because the function is already in progress. Solidity 0.8.34 with no low-level calls makes classic reentrancy impossible. The `onERC721Received` callback, if triggered, would execute in a CALL context (not DELEGATECALL), so it would hit the Game.sol router, which would delegatecall to modules -- but the module code is not reentrant-vulnerable because all state is written before the external call.

**5. Edge Cases:**
- `symbolId == 31`: Last valid symbol. k = 31 (if all others taken). basePrice = 24 + (31*32*1)/2 = 24 + 496 = 520 ETH. SAFE.
- `symbolId == 32`: Reverts at L477. SAFE.
- `k == 0` (first deity pass): basePrice = 24 + 0 = 24 ETH. SAFE.
- `boonTier == 3`: 50% discount. totalPrice = basePrice / 2. SAFE.
- `boonTier != 0` but expired: `expired = true`, no discount applied. Boon cleared anyway (L504). totalPrice = basePrice. SAFE.

**FINDING F-05:** The ticket start level for deity pass at L536 uses a different formula than whale bundle. Whale bundle: `ticketStartLevel = passLevel` (L213). Deity pass: `ticketStartLevel = passLevel <= 4 ? 1 : uint24(((passLevel+1)/50)*50+1)`. This snaps the start to 50-level boundaries at higher levels. For example, at passLevel=47, ticketStartLevel = 1. At passLevel=50, ticketStartLevel = ((51)/50)*50+1 = 51. This means deity pass tickets may start at different levels than whale bundle tickets for the same purchase level.
**Verdict: INVESTIGATE (INFO)** -- This is by design: deity pass tickets cover a 100-level range starting from a 50-level-aligned boundary, ensuring coverage across phase transitions. Not a vulnerability.

**6. Conditional Paths:**
- Boon path: deity-day expiry vs lootbox-day expiry logic.
- Pre-game vs post-game pool split.
- lootboxAmount == 0 check (skip recording if zero).
All paths traced. SAFE.

**7. Economic Attacks:**
SAFE. Triangular pricing ensures each successive deity pass is more expensive. An attacker cannot manipulate `k` (deityPassOwners.length) between the price calculation (L482) and the array push (L516) within the same transaction. Front-running another buyer's deity pass to claim a desired symbol is possible but this is expected first-come-first-served behavior, not an exploit.

**8. Griefing:**
SAFE. Requires 24+ ETH. Symbol squatting (buying pass for a symbol to block others) is possible but each pass grants real game benefits -- this is intended competitive behavior.

**9. Ordering/Sequencing:**
SAFE. One-per-player limit (L479) prevents stacking. No ordering dependency.

**10. Silent Failures:**
SAFE. All revert conditions explicit. `lootboxAmount != 0` check at L562 correctly skips zero-amount recording.

---

## Part 2: Category C Helpers -- Call Tree Analysis

The Category C helpers are traced within their parent's call trees above. Per D-03, standalone analysis is provided only for MULTI-PARENT helpers.

---

## _recordLootboxEntry (C6) [MULTI-PARENT] -- Standalone Analysis

**Called by:** C1 (purchaseWhaleBundle at L309), C2 (purchaseLazyPass at L449), C3 (purchaseDeityPass at L563)

### Call Tree
```
_recordLootboxEntry(buyer, lootboxAmount, purchaseLevel, cachedPacked) [line 714] -- private
  +-- dayIndex = _simulatedDayIndex() [line 720] -- view
  +-- index = lootboxRngIndex [line 721] -- STORAGE READ
  +-- _recordLootboxMintDay(buyer, uint32(dayIndex), cachedPacked) [line 723]
  |    +-- prevDay = uint32(cachedPacked >> DAY_SHIFT) [line 809]
  |    +-- if prevDay == day: return (no write) [line 810-812]
  |    +-- else: clear day from cachedPacked and set new day [line 813-814]
  |         +-- mintPacked_[player] = modified cachedPacked [line 814] -- STORAGE WRITE
  +-- packed = lootboxEth[index][buyer] [line 725] -- STORAGE READ
  +-- existingAmount = packed & ((1<<232)-1) [line 726]
  +-- storedDay = lootboxDay[index][buyer] [line 727] -- STORAGE READ
  +-- if existingAmount == 0 (first entry for this index):
  |    +-- lootboxDay[index][buyer] = dayIndex [line 730] -- STORAGE WRITE
  |    +-- lootboxBaseLevelPacked[index][buyer] = uint24(level+2) [line 731] -- STORAGE WRITE
  |    +-- lootboxEvScorePacked[index][buyer] = playerActivityScore+1 [line 732-733] -- STORAGE WRITE + EXTERNAL VIEW
  |    +-- emit LootBoxIndexAssigned
  +-- else if storedDay != dayIndex: revert E() [line 736]
  +-- _applyLootboxBoostOnPurchase(buyer, dayIndex, lootboxAmount) [line 739] -- C8
  |    +-- boonPacked[player].slot0 read [line 780]
  |    +-- if tier != 0:
  |    |    +-- expiry check [line 786]
  |    |    +-- if expired: bp.slot0 = s0 & BP_LOOTBOX_CLEAR [line 788] -- STORAGE WRITE
  |    |    +-- else: compute boost, clear lootbox fields [line 799] -- STORAGE WRITE
  +-- existingBase = lootboxEthBase[index][buyer] [line 744] -- STORAGE READ
  +-- if existingAmount != 0 && existingBase == 0: existingBase = existingAmount [line 745-747]
  +-- lootboxEthBase[index][buyer] = existingBase + lootboxAmount [line 748] -- STORAGE WRITE
  +-- newAmount = existingAmount + boostedAmount [line 750]
  +-- lootboxEth[index][buyer] = (purchaseLevel << 232) | newAmount [line 751] -- STORAGE WRITE
  +-- _maybeRequestLootboxRng(lootboxAmount) [line 752] -- C7
  |    +-- lootboxRngPendingEth += lootboxAmount [line 763] -- STORAGE WRITE
  +-- if _isDistressMode() [line 755]: -- view
       +-- lootboxDistressEth[index][buyer] += boostedAmount [line 756] -- STORAGE WRITE
```

### Cross-Parent Analysis

**From C1 (whale bundle):** Called at L309 with `(buyer, lootboxAmount, passLevel, data)`. The `data` variable was written to `mintPacked_[buyer]` at L262 and reflects the current state. The `cachedPacked` parameter is current. `_recordLootboxMintDay` will find the day matches and return without writing. **SAFE.**

**From C2 (lazy pass):** Called at L449 with `(buyer, lootboxAmount, currentLevel+1, mintPacked_[buyer])`. The `mintPacked_[buyer]` is a FRESH storage read. `_activate10LevelPass` wrote to mintPacked_ at Storage L1059, so the fresh read at L449 reflects that write. **SAFE.**

**From C3 (deity pass):** Called at L563 with `(buyer, lootboxAmount, passLevel, mintPacked_[buyer])`. The only prior write to mintPacked_ in C3 is via `_awardEarlybirdDgnrs` which may write `earlybirdEthIn` but does NOT write to mintPacked_ (it writes to `earlybirdDgnrsPoolStart` and `earlybirdEthIn`). Wait -- let me re-check. `_awardEarlybirdDgnrs` at Storage L914 does NOT write to `mintPacked_[buyer]`. It writes to `earlybirdDgnrsPoolStart` (L924/948) and `earlybirdEthIn` (L966). So `mintPacked_[buyer]` at L563 reflects whatever state existed before the deity pass purchase (no deity-pass-specific write to mintPacked_). **SAFE** -- no stale cache concern because deity pass doesn't modify mintPacked_ before reading it for lootbox.

**FINDING F-06:** At L732-733, `lootboxEvScorePacked[index][buyer]` is set to `uint16(IDegenerusGame(address(this)).playerActivityScore(buyer) + 1)`. This reads the activity score via a self-call in the delegatecall context. The score reflects the player's state at the time of this transaction. If the purchase itself modified the activity score (e.g., through ticket queuing or purchase tracking), the score read here would reflect the POST-purchase state, not the pre-purchase state. This means the lootbox EV score is based on the player's activity AFTER the current purchase, which may be slightly inflated.
**Verdict: INVESTIGATE (INFO)** -- The activity score is used for lootbox resolution weighting. A slightly inflated score from the current purchase's state changes is negligible and not exploitable for material gain. The score difference between pre- and post-purchase would be minimal (one purchase event).

---

## _recordLootboxMintDay (C9) [MULTI-PARENT] -- Standalone Analysis

**Called by:** C6 (which is called by C1, C2, C3)

### Analysis

```solidity
function _recordLootboxMintDay(address player, uint32 day, uint256 cachedPacked) private {
    uint32 prevDay = uint32((cachedPacked >> BitPackingLib.DAY_SHIFT) & BitPackingLib.MASK_32);
    if (prevDay == day) {
        return;
    }
    uint256 clearedDay = cachedPacked & ~(BitPackingLib.MASK_32 << BitPackingLib.DAY_SHIFT);
    mintPacked_[player] = clearedDay | (uint256(day) << BitPackingLib.DAY_SHIFT);
}
```

**Critical concern:** If `cachedPacked` is stale (from before another write to mintPacked_), the write at L814 would overwrite ALL fields of mintPacked_ (not just the day), because it takes the full `cachedPacked` value, clears the day bits, and sets new day bits. All other fields come from `cachedPacked`.

**From C1 (whale):** `cachedPacked = data` which was just written at L262. Current. Day already set by `_setMintDay` at L260. prevDay == day -> return. No write. **SAFE.**

**From C2 (lazy):** `cachedPacked = mintPacked_[buyer]` (fresh read at L449). `_activate10LevelPass` already wrote the current day at Storage L1052-1057. prevDay == day -> return. No write. **SAFE.**

**From C3 (deity):** `cachedPacked = mintPacked_[buyer]` (fresh read at L563). Deity pass does NOT write to mintPacked_ before this point. So the day in cachedPacked is whatever was set by the player's most recent activity. If the player has never purchased anything, the day could be 0. If they purchased earlier today, the day matches. If they haven't purchased today, the day doesn't match and `_recordLootboxMintDay` writes the new day along with ALL other fields from the stale(ish) cachedPacked. **BUT** deity pass doesn't modify any mintPacked_ fields itself (no levelCount, frozenUntilLevel changes from deity pass). The only mintPacked_ write before L563 is `_awardEarlybirdDgnrs` which does NOT write mintPacked_. So `cachedPacked` at L563 IS the current mintPacked_ state. **SAFE.**

---

## Part 3: Remaining Category C Helpers

### C1: _purchaseWhaleBundle -- Traced fully in B1 call tree above.
### C2: _purchaseLazyPass -- Traced fully in B2 call tree above.
### C3: _purchaseDeityPass -- Traced fully in B3 call tree above.

### C4: _rewardWhaleBundleDgnrs (lines 587-644)

Called by C1 in a loop (once per quantity). Each iteration:
1. Reads `dgnrs.poolBalance(Whale)` -- external view, fresh each iteration.
2. Computes minterShare = (whaleReserve * 10_000) / 1_000_000 = 1% of whale pool.
3. Transfers minterShare to buyer.
4. Reads `dgnrs.poolBalance(Affiliate)` -- external view, fresh each iteration.
5. Subtracts reserved allocation: `levelDgnrsAllocation[level] - levelDgnrsClaimed[level]`.
6. If reserved >= affiliateReserve, returns early (protects allocation).
7. Computes affiliate/upline/upline2 shares from remaining affiliateReserve.
8. Transfers shares.

**Storage writes:** External only (dgnrs.transferFromPool). No Game storage writes.
**Cache check:** `level` storage variable used at L610 for reserved calculation. `level` is not written by this function or its callers within the same call context. SAFE.

### C5: _rewardDeityPassDgnrs (lines 652-712)

Identical pattern to C4 but with deity-specific PPM values (5% whale pool, 0.5% affiliate direct, 0.1% upline). Called once (not in a loop). Returns `buyerDgnrs` (uint96) for the buyer's reward amount.

**Storage writes:** External only.
**Cache check:** Same `level` usage as C4. SAFE.

### C7: _maybeRequestLootboxRng (lines 762-764)

Single-line accumulator: `lootboxRngPendingEth += lootboxAmount`.
**Storage writes:** `lootboxRngPendingEth`.
**Cache check:** No cached locals. SAFE.

### C8: _applyLootboxBoostOnPurchase (lines 773-802)

Reads boonPacked[player].slot0, checks lootbox boost tier, checks expiry, applies boost percentage (5/15/25%), clears boost fields.
**Storage writes:** `boonPacked[player].slot0` (lootbox fields cleared on consume/expiry).
**Cache check:** `s0` cached at L780, written at L788 or L799 using `s0 & BP_LOOTBOX_CLEAR`. The cached value is the basis for the clear operation. SAFE.

---

## Part 4: Category D Functions

### D1: _lazyPassCost (lines 573-580)
Pure function. Sums `PriceLookupLib.priceForLevel(startLevel + i)` for i=0..9. No storage reads or writes. Overflow: 10 levels x max price (bounded by PriceLookupLib's return range). No concern.

### D2: _whaleTierToBps (Storage L1551-1557)
Pure mapping: tier 1->1000 (10%), 2->2500 (25%), 3->5000 (50%), 0->0. Correct per specification.

### D3: _lazyPassTierToBps (Storage L1559-1565)
Pure mapping: same as D2. Correct per specification.

### D4: _lootboxTierToBps (Storage L1527-1533)
Pure mapping: tier 1->500 (5%), 2->1500 (15%), 3->2500 (25%), 0->0. Correct per specification.

---

## Part 5: Findings Detail

### F-01: Whale Boon Discount Based on Standard Price at Early Levels
**Function:** purchaseWhaleBundle (B1/C1)
**Lines:** 235-238
**Verdict:** INVESTIGATE (INFO)
**Description:** When `hasValidBoon == true`, the discounted price is calculated as `(WHALE_BUNDLE_STANDARD_PRICE * (10_000 - discountBps)) / 10_000`. WHALE_BUNDLE_STANDARD_PRICE is 4 ETH. At levels 0-3, the non-boon price is 2.4 ETH (WHALE_BUNDLE_EARLY_PRICE). A tier 1 boon (10% off standard) yields 3.6 ETH -- more expensive than the non-boon early price. Players at early levels would be better off NOT using their boon.
**Impact:** No loss of funds -- the player explicitly agrees to the price via msg.value. Economically suboptimal for boon holders at early levels but not exploitable.
**Recommendation:** Document this behavior or adjust boon pricing to use `max(discountedStandard, earlyPrice)`.

### F-02: DGNRS Reward Diminishing Returns in Multi-Quantity Purchase
**Function:** purchaseWhaleBundle (B1/C1), _rewardWhaleBundleDgnrs (C4)
**Lines:** 284-287 (loop), 593-603 (pool read + transfer)
**Verdict:** INVESTIGATE (LOW)
**Description:** The DGNRS reward loop at L284 calls `_rewardWhaleBundleDgnrs` once per `quantity`. Each iteration reads a FRESH `dgnrs.poolBalance(Whale)` and computes 1% minter share. After each transfer, the pool balance decreases. For quantity=100, the cumulative reward is less than `100 * 1%_of_initial_pool` due to diminishing returns. A buyer splitting 100 bundles across 100 separate transactions would get a higher total DGNRS reward because each transaction reads the independently-restored pool balance (if other activity deposits into the pool between transactions). However, in practice, the pool balance doesn't change between iterations within a single transaction -- the diminishment is real and per-iteration.
**Impact:** Economic suboptimality for multi-quantity buyers. Not exploitable by attackers. The affiliate pool has the additional `reserved` guard (L610-612) that caps drain.
**Recommendation:** Consider computing total reward as `whaleReserve * quantity * PPM / SCALE` in a single calculation to give consistent per-unit rewards regardless of quantity.

### F-03: Lazy Pass cachedPacked in _recordLootboxMintDay
**Function:** purchaseLazyPass (B2/C2), _recordLootboxEntry (C6), _recordLootboxMintDay (C9)
**Lines:** 449 (fresh read), 723 (pass to _recordLootboxMintDay), 808-815 (conditional write)
**Verdict:** INVESTIGATE (INFO)
**Description:** `_purchaseLazyPass` at L449 passes `mintPacked_[buyer]` (fresh read) to `_recordLootboxEntry`. Inside, `_recordLootboxMintDay` checks if the day in the cached value matches the current day. Since `_activate10LevelPass` (called at L417) already set the day in mintPacked_ via `_setMintDay` at Storage L1052-1057, the fresh read at L449 has the current day. The `prevDay == day` check at L810-812 returns true, so no write occurs.
**Impact:** No state corruption. The function is a no-op in this context.
**Recommendation:** None needed. The code is correct.

### F-04: ERC721 Mint Callback Re-entry
**Function:** purchaseDeityPass (B3/C3)
**Lines:** 521 (mint call), 514-518 (state writes before mint)
**Verdict:** INVESTIGATE (INFO)
**Description:** The ERC721 mint at L521 could trigger `onERC721Received` if the DeityPass contract uses `_safeMint`. However, all deity-specific state is written before the call (L514-518). Re-entry into purchaseDeityPass fails at L479 (deityPassCount check). Re-entry into purchaseLazyPass fails at L360 (deityPassCount check). Re-entry into purchaseWhaleBundle has no deity check but requires fresh msg.value, which is not available in a callback.
**Impact:** No exploitable re-entry path. Solidity 0.8.34 with typed external calls (not raw `.call`) prevents classic reentrancy.
**Recommendation:** If the DeityPass contract is under protocol control, consider using plain `_mint` instead of `_safeMint` to eliminate the callback entirely.

### F-05: Deity Pass Ticket Start Level Formula
**Function:** purchaseDeityPass (B3/C3)
**Lines:** 536
**Verdict:** INVESTIGATE (INFO)
**Description:** Deity pass ticket start level uses `passLevel <= 4 ? 1 : uint24(((passLevel+1)/50)*50+1)` while whale bundle uses `passLevel` directly. At high levels, deity pass tickets snap to 50-level boundaries. For example, at passLevel=51, deity tickets start at level 51, but at passLevel=99, deity tickets start at level 51 (covering 51-150). This is different from whale bundle which would start at level 99 (covering 99-198).
**Impact:** By design -- deity pass provides broader coverage anchored to phase boundaries. Not a vulnerability.
**Recommendation:** None -- document this distinction in player-facing documentation.

### F-06: Lootbox EV Score Reflects Post-Purchase State
**Function:** _recordLootboxEntry (C6)
**Lines:** 732-733
**Verdict:** INVESTIGATE (INFO)
**Description:** `lootboxEvScorePacked[index][buyer]` is set to `playerActivityScore(buyer) + 1` at lootbox entry time. If the purchase itself modified the player's activity score (via ticket queuing or mint data updates), the score reflects post-purchase state. This gives a marginally inflated EV score for the lootbox.
**Impact:** Negligible. The score difference from a single purchase is minimal. Not exploitable for material gain.
**Recommendation:** None -- the marginal inflation is inconsequential.

---

*Attack report complete: 2026-03-25*
*Mad Genius: All 3 Category B, 9 Category C, and 4 Category D functions analyzed. 0 VULNERABLE, 6 INVESTIGATE (5 INFO + 1 LOW). No BAF-class bugs found.*
