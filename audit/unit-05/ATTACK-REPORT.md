# Unit 5: Mint + Purchase Flow -- Attack Report

**Agent:** Mad Genius (Attacker)
**Contracts:** DegenerusGameMintModule.sol (~1,167 lines), DegenerusGameMintStreakUtils.sol (62 lines)
**Date:** 2026-03-25

---

## Findings Summary

| ID | Function | Verdict | Severity | Title |
|----|----------|---------|----------|-------|
| F-01 | purchase -> _purchaseFor | INVESTIGATE | INFO | `purchaseLevel = level + 1` cached at line 636, then self-call chain through recordMint -- but recordMintData does NOT write to `level`, so cache is safe |
| F-02 | purchase -> _purchaseFor | INVESTIGATE | INFO | `claimableWinnings[buyer]` read at line 650 for initialClaimable, then read again at line 669 inside lootbox shortfall -- two reads of same slot, no external call between them that could change it |
| F-03 | _callTicketPurchase | INVESTIGATE | INFO | Century bonus `maxBonus = (20 ether) / (priceWei >> 2)` -- if `priceWei` is 1 wei (minimum), `priceWei >> 2 = 0`, causing division by zero revert. But `priceWei == 0` is guarded at line 856-858 and minimum ticket price is 0.0025 ETH, so `priceWei >= 0.01 ether` in practice. |
| F-04 | _callTicketPurchase | INVESTIGATE | INFO | Ticket level routing at lines 842-851: when `jackpotPhaseFlag == true && rngLockedFlag == false`, tickets route to `level` (current). These tickets are for the CURRENT jackpot phase and get processed by processFutureTicketBatch during the current jackpot phase's ticket drain. Not stranded. |
| F-05 | processFutureTicketBatch | INVESTIGATE | INFO | Write budget `writesBudget -= (writesBudget * 35) / 100` on first batch (idx==0) reduces from 550 to 357. A queue with many zero-owed entries consumes 1 budget unit each (skip cost at line 346). With 357 budget, max 357 skips per call. A griefing vector exists: attacker queues hundreds of zero-ticket entries to slow processing. But each queue entry requires a purchase transaction (non-free), limiting the attack economics. |
| F-06 | _raritySymbolBatch | INVESTIGATE | INFO | LCG seed construction: `seed = (baseKey + groupIdx) ^ entropyWord` at line 467. For the same player at the same level, `baseKey` is fixed. `groupIdx = i >> 4` changes every 16 symbols. If `entropyWord` (rngWordCurrent) is known, an observer can predict all trait assignments. But rngWordCurrent is a VRF word unknown at purchase commitment time, and trait assignment happens during batch processing (after VRF fulfillment), so this is by-design deterministic generation, not a manipulable RNG. |

**All 5 Category B functions and 11 Category C helpers analyzed. 3 MULTI-PARENT functions received cross-parent scrutiny. 1 ASSEMBLY function verified. No VULNERABLE findings. 6 INVESTIGATE findings (all INFO). Self-call re-entry: SAFE. Assembly: CORRECT.**

---

## Part 1: Category B Functions -- Full Attack Analysis

---

## MintModule::purchase() (lines 560-574) [B3] -- via _purchaseFor() (lines 628-829) [C1]

### Call Tree
```
purchase(buyer, ticketQuantity, lootBoxAmount, affiliateCode, payKind) [line 560] -- external payable
  +-- _purchaseFor(buyer, ticketQuantity, lootBoxAmount, affiliateCode, payKind) [line 567] -- C1
      +-- gameOver check [line 635] -- revert E()
      +-- purchaseLevel = level + 1 [line 636] -- CACHE of storage `level`
      +-- priceWei = price [line 637] -- CACHE of storage `price`
      +-- lootBoxAmount minimum check [line 639]
      +-- ticketCost = (priceWei * ticketQuantity) / (4 * TICKET_SCALE) [line 644]
      +-- totalCost check [line 648]
      +-- initialClaimable = claimableWinnings[buyer] [line 650] -- CACHE of storage
      +-- Lootbox payment routing [lines 652-677]:
      |   +-- If remainingEth >= lootBoxAmount: lootboxFreshEth = lootBoxAmount [line 658]
      |   +-- Else: claimable shortfall path [lines 664-677]
      |       +-- claimableWinnings[buyer] -= shortfall [line 673] -- STORAGE WRITE
      |       +-- claimablePool -= shortfall [line 675] -- STORAGE WRITE
      +-- If ticketCost != 0: _callTicketPurchase(...) [line 681] -- C3
      |   +-- (see C3 analysis below -- full call tree)
      +-- If lootBoxAmount != 0: Lootbox logic [lines 692-812]
      |   +-- day = _simulatedDayIndex() [line 693]
      |   +-- index = lootboxRngIndex [line 694]
      |   +-- presale = lootboxPresaleActive [line 695]
      |   +-- packed = lootboxEth[index][buyer] [line 697]
      |   +-- If existingAmount == 0: first lootbox this index [lines 701-706]
      |   |   +-- lootboxDay[index][buyer] = day [line 702] -- STORAGE WRITE
      |   |   +-- lootboxBaseLevelPacked[index][buyer] = uint24(level + 2) [line 703] -- STORAGE WRITE
      |   |   +-- lootboxEvScorePacked[index][buyer] = uint16(playerActivityScore(buyer) + 1) [line 704-705] -- STORAGE WRITE + SELF-CALL
      |   |   +-- emit LootBoxIdx [line 706]
      |   +-- Else: storedDay check [line 708]
      |   +-- boostedAmount = _applyLootboxBoostOnPurchase(buyer, day, lootBoxAmount) [line 711] -- C7
      |   |   +-- boonPacked[player].slot0 read/write [lines 1091-1109] -- STORAGE WRITE
      |   +-- lootboxEthBase[index][buyer] update [lines 716-720] -- STORAGE WRITE
      |   +-- lootboxEth[index][buyer] = packed amount [line 724] -- STORAGE WRITE
      |   +-- _maybeRequestLootboxRng(lootBoxAmount) [line 725] -- C6
      |   |   +-- lootboxRngPendingEth += lootBoxAmount [line 1074] -- STORAGE WRITE
      |   +-- If presale: lootboxPresaleMintEth += lootBoxAmount [line 729] -- STORAGE WRITE
      |   +-- distress = _isDistressMode() [line 732]
      |   +-- If distress: lootboxDistressEth[index][buyer] += boostedAmount [line 736] -- STORAGE WRITE
      |   +-- Pool split calculation [lines 738-753]
      |   +-- If prizePoolFrozen: _setPendingPools(...) [line 759] -- STORAGE WRITE (prizePoolPendingPacked)
      |   +-- Else: _setPrizePools(...) [line 762] -- STORAGE WRITE (prizePoolsPacked)
      |   +-- If vaultShare != 0: payable(VAULT).call{value}("") [line 765] -- EXTERNAL CALL
      |   +-- affiliate.payAffiliate(...) calls [lines 772-790] -- EXTERNAL CALL x2
      |   +-- coin.creditFlip(buyer, lootboxKickback) [line 792] -- EXTERNAL CALL
      |   +-- emit LootBoxBuy [line 795]
      |   +-- coin.notifyQuestMint(buyer, scaled, true) [line 804] -- EXTERNAL CALL
      |   +-- coin.notifyQuestLootBox(buyer, lootBoxAmount) [line 810] -- EXTERNAL CALL
      |   +-- _awardEarlybirdDgnrs(buyer, lootboxFreshEth, purchaseLevel) [line 811] -- C11
      |       +-- earlybirdDgnrsPoolStart / earlybirdEthIn writes [lines 924-966] -- STORAGE WRITE
      |       +-- sDGNRS.transferFromPool / transferBetweenPools [lines 932, 969] -- EXTERNAL CALL
      +-- Claimable bonus calculation [lines 814-828]
      |   +-- coin.creditFlip(buyer, bonusAmount) [line 826] -- EXTERNAL CALL
```

### Storage Writes (Full Tree)

| Variable | Written By | Line(s) |
|----------|-----------|---------|
| `claimableWinnings[buyer]` | C1 (_purchaseFor) | 673 |
| `claimablePool` | C1 (_purchaseFor) | 675 |
| `lootboxDay[index][buyer]` | C1 (_purchaseFor) | 702 |
| `lootboxBaseLevelPacked[index][buyer]` | C1 (_purchaseFor) | 703 |
| `lootboxEvScorePacked[index][buyer]` | C1 (_purchaseFor) | 704-705 |
| `boonPacked[player].slot0` | C7 (_applyLootboxBoostOnPurchase) | 1100, 1109 |
| `lootboxEthBase[index][buyer]` | C1 (_purchaseFor) | 720 |
| `lootboxEth[index][buyer]` | C1 (_purchaseFor) | 724 |
| `lootboxRngPendingEth` | C6 (_maybeRequestLootboxRng) | 1074 |
| `lootboxPresaleMintEth` | C1 (_purchaseFor) | 729 |
| `lootboxDistressEth[index][buyer]` | C1 (_purchaseFor) | 736 |
| `prizePoolsPacked` or `prizePoolPendingPacked` | C1 (_purchaseFor) | 759 or 762 |
| `earlybirdDgnrsPoolStart` | C11 (_awardEarlybirdDgnrs) | 924, 948 |
| `earlybirdEthIn` | C11 (_awardEarlybirdDgnrs) | 966 |
| `centuryBonusLevel` | C3 (_callTicketPurchase) | 894 |
| `centuryBonusUsed[buyer]` | C3 (_callTicketPurchase) | 895 |
| `ticketQueue[wk]` | C10 (_queueTicketsScaled) | 570 |
| `ticketsOwedPacked[wk][buyer]` | C10 (_queueTicketsScaled) | 592 |
| `mintPacked_[player]` | recordMintData (via self-call) | 217, 237, 281 |

### Cached-Local-vs-Storage Check

| Ancestor Local | Cached At | Descendant Write | Written At | Verdict |
|---------------|-----------|-----------------|-----------|---------|
| `purchaseLevel = level + 1` | C1 L636 | `level` | NOT written by any descendant | **SAFE** -- `recordMintData` writes only `mintPacked_[player]`, not `level`. No descendant in this tree writes `level`. |
| `priceWei = price` | C1 L637 | `price` | NOT written by any descendant | **SAFE** -- No descendant writes `price`. It is only written by `advanceGame` (different module). |
| `initialClaimable = claimableWinnings[buyer]` | C1 L650 | `claimableWinnings[buyer]` | C1 L673 (lootbox shortfall deduction) | **SAFE** -- `initialClaimable` is used at lines 814-817 to compute `totalClaimableUsed`. The write at L673 happens BEFORE `_callTicketPurchase` at L681. At L816, `finalClaimable` re-reads `claimableWinnings[buyer]` from storage (or uses `initialClaimable` if DirectEth). The self-call through `recordMint` does NOT write `claimableWinnings`. The `_callTicketPurchase` path through `IDegenerusGame.recordMint{value}` calls `Game.recordMint()` which handles ETH routing by calling `_callMintModule(data)` and the ETH split logic -- but `recordMint` in Game writes to `currentPrizePool`, `prizePoolsPacked`, `claimableWinnings` (for claimable payment deduction), and `claimablePool`. **WAIT** -- `recordMint` in Game DOES write `claimableWinnings[buyer]` for the Claimable and Combined payment kinds. Let me trace this carefully. |

**DEEP TRACE: Does `IDegenerusGame(address(this)).recordMint{value}()` write `claimableWinnings[buyer]`?**

Looking at the self-call flow: `_callTicketPurchase` at line 918 calls `IDegenerusGame(address(this)).recordMint{value: value}(payer, targetLevel, costWei, mintUnits, payKind)`. This is a regular CALL to `DegenerusGame.recordMint()`. Inside `recordMint`, the Game contract:
1. Deducts from `claimableWinnings[payer]` and `claimablePool` for Claimable/Combined payment kinds
2. Routes ETH to `currentPrizePool` and `prizePoolsPacked`
3. Delegatecalls to `MintModule.recordMintData()` for mint tracking

So YES, `recordMint` writes `claimableWinnings[buyer]` when `payKind` is `Claimable` or `Combined`. But at line 814-817 in `_purchaseFor`, we have:
```solidity
uint256 finalClaimable = payKind == MintPaymentKind.DirectEth
    ? initialClaimable
    : claimableWinnings[buyer];
```

When `payKind != DirectEth`, `finalClaimable` re-reads from storage (not the stale cache). When `payKind == DirectEth`, it uses `initialClaimable` which is correct because `recordMint` with DirectEth does NOT deduct from claimable. **SAFE** -- the code explicitly handles this case by re-reading storage for non-DirectEth paths.

**F-01 (INVESTIGATE/INFO):** The `purchaseLevel` local is computed as `level + 1` at line 636. The self-call chain through `recordMint` does NOT write `level` (only `mintPacked_`). The `level` variable is only written by `advanceGame` in the AdvanceModule. Cache is safe. However, the code makes an implicit assumption: `level` does not change mid-transaction. Since all purchase functions are delegatecalled from Game (which is non-reentrant for state-changing calls), this assumption holds.

**F-02 (INVESTIGATE/INFO):** `claimableWinnings[buyer]` is read at line 650 and again at line 669. Between these two reads (lines 650-669), no external call occurs -- the code is purely local arithmetic and conditional checks. The second read at 669 is `uint256 claimable = claimableWinnings[buyer]` which is a fresh SLOAD. Safe.

### Attack Analysis

**1. State coherence (BAF pattern):** SAFE. As traced above, `purchaseLevel` and `priceWei` caches are not written by any descendant. `initialClaimable` is handled correctly with a conditional re-read at line 814-816. The self-call through `recordMint` writes only `mintPacked_[player]`, `currentPrizePool`, `prizePoolsPacked`, and `claimableWinnings` -- but `_purchaseFor` does not cache `currentPrizePool` or `prizePoolsPacked` locally.

**2. Access control:** SAFE. Function is `external payable`, accessible only via delegatecall from DegenerusGame. Game controls access via its routing logic (only callable through Game's `buyTickets`/`buyLootbox` entry points which require the caller to be the operator or the player).

**3. RNG manipulation:** SAFE. No RNG consumption in this function. Lootbox ETH is accumulated for future RNG resolution.

**4. Cross-contract state desync:** SAFE. External calls to `affiliate.payAffiliate` and `coin.creditFlip` operate on their own storage. The Vault ETH transfer at line 765 is a simple value transfer with success check. `sDGNRS.transferFromPool` in the earlybird path operates on sDGNRS storage. None of these affect Game storage variables.

**5. Edge cases:**
- **Zero `lootBoxAmount`:** Skips entire lootbox section. Only ticket path runs. SAFE.
- **Zero `ticketQuantity`:** Skips ticket path. Only lootbox path runs. `totalCost` check at line 648 ensures at least one is non-zero.
- **First-ever lootbox purchase (existingAmount == 0):** Initializes all lootbox metadata. Second purchase same index: `storedDay != day` reverts (prevents cross-day accumulation). SAFE.
- **Game over:** Reverts at line 635. SAFE.

**6. Conditional paths:**
- **Distress mode:** All lootbox ETH goes to nextPool (100%). No future/vault split. Distress ETH tracked separately for ticket bonus. SAFE.
- **Presale split:** 50/30/20 to future/next/vault. Extra 20% to vault via raw `.call`. SAFE.
- **prizePoolFrozen:** Uses pending pool accumulators. Unfrozen when jackpot phase completes. SAFE.

**7. Economic attacks:** The lootbox boost application at C7 consumes the boost (clears boon fields at line 1109). Cannot be double-consumed in the same transaction. The boost is capped at LOOTBOX_BOOST_MAX_VALUE (10 ETH). No economic amplification. SAFE.

**8. Griefing:** The claimable shortfall path at lines 664-677 could temporarily reduce `claimablePool`. But the deduction is exact and paired with `claimableWinnings[buyer]` deduction. No pool accounting drift. SAFE.

**9. Ordering/Sequencing:** Lootbox processing happens before ticket processing in `_purchaseFor`. The lootbox may write `claimableWinnings[buyer]` (shortfall deduction) before `_callTicketPurchase` reads it (but `_callTicketPurchase` does not read `claimableWinnings` -- it gets payment info via `payKind` and `value`). SAFE.

**10. Silent failures:** Vault transfer at line 765 checks success and reverts on failure. Affiliate calls return values that are used for kickback. No silent no-ops. SAFE.

---

## MintModule::processFutureTicketBatch() (lines 295-434) [B2]

### Call Tree
```
processFutureTicketBatch(lvl) [line 295] -- external
  +-- entropy = rngWordCurrent [line 298] -- CACHE of storage (read once, used throughout)
  +-- inFarFuture = (ticketLevel == (lvl | TICKET_FAR_FUTURE_BIT)) [line 299]
  +-- rk = inFarFuture ? _tqFarFutureKey(lvl) : _tqReadKey(lvl) [line 300]
  +-- queue = ticketQueue[rk] [line 301] -- storage array reference
  +-- Empty queue path [lines 303-307]:
  |   +-- ticketCursor = 0 [line 304] -- STORAGE WRITE
  |   +-- ticketLevel = 0 [line 305] -- STORAGE WRITE
  +-- Level mismatch reset [lines 309-312]:
  |   +-- ticketLevel = lvl [line 310] -- STORAGE WRITE
  |   +-- ticketCursor = 0 [line 311] -- STORAGE WRITE
  +-- Cursor past end check [lines 315-320]:
  |   +-- delete ticketQueue[rk] [line 316] -- STORAGE WRITE
  |   +-- ticketCursor = 0 [line 317] -- STORAGE WRITE
  |   +-- ticketLevel = 0 [line 318] -- STORAGE WRITE
  +-- Write budget setup [lines 323-326]:
  |   +-- writesBudget = WRITES_BUDGET_SAFE (550) [line 323]
  |   +-- If idx == 0: writesBudget -= (writesBudget * 35) / 100 [line 325] -- 35% reduction = 357
  +-- Main processing loop [lines 331-411]:
  |   +-- player = queue[idx] [line 332]
  |   +-- packed = ticketsOwedPacked[rk][player] [line 336]
  |   +-- Zero-owed skip path [lines 339-363]:
  |   |   +-- If owed == 0 && rem == 0: cleanup [lines 340-348]
  |   |   |   +-- ticketsOwedPacked[rk][player] = 0 [line 342] -- STORAGE WRITE
  |   |   +-- If rem != 0: _rollRemainder [line 350] -- D1
  |   |       +-- If win: owed = 1, rem = 0 [lines 356-362]
  |   |       +-- ticketsOwedPacked[rk][player] updated [line 351 or 358] -- STORAGE WRITE
  |   +-- Budget check for processing [lines 364-371]
  |   +-- _raritySymbolBatch(player, baseKey, processed, take, entropy) [line 373] -- C8 [ASSEMBLY]
  |   |   +-- traitBurnTicket[lvl][traitId] writes [lines 502-536] -- STORAGE WRITE (assembly)
  |   +-- emit TraitsGenerated [line 374]
  |   +-- Remaining owed calculation [lines 388-397]:
  |   |   +-- If remainingOwed == 0 && rem != 0: _rollRemainder [line 393] -- D1
  |   |   +-- ticketsOwedPacked[rk][player] updated [line 399-401] -- STORAGE WRITE
  |   +-- Cursor advancement [lines 402-410]
  +-- Post-loop state [lines 413-433]:
      +-- ticketCursor = uint32(idx) [line 415] -- STORAGE WRITE
      +-- finished = (idx >= total) [line 416]
      +-- If finished: delete ticketQueue[rk] [line 418] -- STORAGE WRITE
      |   +-- If !inFarFuture && far-future queue exists [lines 420-424]:
      |       +-- ticketLevel = lvl | TICKET_FAR_FUTURE_BIT [line 422] -- STORAGE WRITE
      |       +-- ticketCursor = 0 [line 423] -- STORAGE WRITE
      +-- Else: ticketCursor = 0, ticketLevel = 0 [lines 426-428] -- STORAGE WRITE
```

### Storage Writes (Full Tree)

| Variable | Written By | Line(s) |
|----------|-----------|---------|
| `ticketCursor` | B2 | 304, 311, 317, 415, 423, 427 |
| `ticketLevel` | B2 | 305, 310, 318, 422, 428 |
| `ticketQueue[rk]` | B2 | 316, 418 (delete) |
| `ticketsOwedPacked[rk][player]` | B2 | 342, 351, 358, 399-401 |
| `traitBurnTicket[lvl][traitId]` | C8 (_raritySymbolBatch) | 516-531 (assembly) |

### Cached-Local-vs-Storage Check

| Ancestor Local | Cached At | Descendant Write | Verdict |
|---------------|-----------|-----------------|---------|
| `entropy = rngWordCurrent` | L298 | `rngWordCurrent` | **SAFE** -- No descendant writes `rngWordCurrent`. It is only written by VRF callback (different transaction). |
| `total = queue.length` | L302 | `ticketQueue[rk]` | **SAFE** -- `total` is the array length cached at entry. The delete at L316/L418 only happens AFTER the loop finishes (cursor past end or all processed). During the loop, no new entries are pushed to `queue`. |

### Attack Analysis

**1. State coherence:** SAFE. `entropy` is cached once and used throughout. No descendant writes `rngWordCurrent`. Queue length is read once and loop iterates up to that bound.

**2. Access control:** SAFE. External function accessible only via delegatecall from Game. Called by `advanceGame` flow.

**3. RNG manipulation:** The `entropy` word comes from `rngWordCurrent` which is a VRF word. Trait generation is deterministic given this word. An attacker cannot influence trait assignment because: (a) VRF word is unknown at ticket purchase time, (b) trait generation happens during batch processing triggered by `advanceGame`, (c) the LCG seed includes `baseKey` (level, index, player) and `entropyWord` -- player cannot control `entropyWord`. **F-06 (INVESTIGATE/INFO):** An observer knowing `rngWordCurrent` can predict trait assignments. But this is deterministic-by-design: traits are assigned post-VRF, and the VRF word was unknown at purchase commitment time.

**4. Cross-contract state desync:** SAFE. No external calls. All operations are on local storage.

**5. Edge cases:**
- **Empty queue:** Returns (false, true, 0) immediately. SAFE.
- **Cursor past end (idx >= total):** Deletes queue, resets cursor/level. SAFE.
- **All entries have owed==0, rem==0:** Each consumes 1 budget unit (skip cost). Max 357 or 550 skips per call. Multiple calls drain the queue. SAFE.
- **Single player with very large owed count:** `take = owed > maxT ? maxT : owed` caps at budget-limited batch size. Resumes on next call. SAFE.

**F-05 (INVESTIGATE/INFO):** Write budget griefing: An attacker could queue hundreds of zero-ticket entries (by purchasing with very small amounts, getting rounded to 0 whole tickets and some remainder that rolls to 0). Each zero entry costs 1 budget unit to skip. But creating each entry requires a purchase transaction (with gas cost + minimum ticket buy-in of 0.0025 ETH). The economic cost to the attacker far exceeds the processing delay caused. Additionally, `_queueTicketsScaled` only adds to the queue if `owed == 0 && rem == 0` initially (line 569), meaning only first-time queue entries for a player at that level. Re-purchases by the same player at the same level update the existing packed entry.

**6. Conditional paths:**
- **Far-future path (`inFarFuture`):** Uses `_tqFarFutureKey` instead of `_tqReadKey`. After draining the normal read queue, checks for far-future queue at lines 420-424. Transitions correctly between key spaces. SAFE.
- **Remainder rolling:** `_rollRemainder` at lines 350 and 393 uses `EntropyLib.entropyStep(entropy ^ rollSalt) % TICKET_SCALE`. `TICKET_SCALE = 100` divides `2^256` evenly (no modulo bias). SAFE.

**7. Economic attacks:** No ETH flows in this function. It only generates trait tickets. No economic extraction possible.

**8. Griefing:** See F-05 above. Limited by purchase economics.

**9. Ordering/Sequencing:** Cursor state (`ticketCursor`, `ticketLevel`) persists across calls. If called with a different `lvl` while processing is in progress, the level mismatch reset at lines 309-312 starts fresh for the new level. The old level's partial progress is lost (cursor resets to 0), but no data corruption occurs -- the queue array is still intact. SAFE.

**10. Silent failures:** No silent no-ops. Every path either processes tickets, skips entries (with budget cost), or returns finished/empty status.

---

## MintModule::recordMintData() (lines 175-284) [B1]

### Call Tree
```
recordMintData(player, lvl, mintUnits) [line 175] -- external payable
  +-- prevData = mintPacked_[player] [line 181] -- STORAGE READ
  +-- Unpack: prevLevel, total, unitsLevel [lines 188-190]
  +-- levelUnitsBefore computation [line 200]
  +-- levelUnitsAfter = levelUnitsBefore + mintUnits, capped [lines 203-206]
  +-- Early exit path: !sameLevel && levelUnitsAfter < 4 [lines 212-220]
  |   +-- mintPacked_[player] = data [line 217] -- STORAGE WRITE (conditional)
  +-- _currentMintDay() [line 226] -- reads dailyIdx or _simulatedDayIndex()
  +-- _setMintDay(prevData, day, ...) [line 227] -- pure computation
  +-- Same level path [lines 233-240]:
  |   +-- mintPacked_[player] = data [line 237] -- STORAGE WRITE (conditional)
  +-- New level path [lines 246-283]:
      +-- frozenUntilLevel extraction [line 247]
      +-- Frozen state handling [lines 252-258]:
      |   +-- If lvl >= frozenUntilLevel: clear frozen flag and bundle type
      +-- total increment [lines 260-267]: unchecked total + 1
      +-- Pack all fields [lines 270-273]
      +-- mintPacked_[player] = data [line 281] -- STORAGE WRITE (conditional)
```

### Storage Writes (Full Tree)

| Variable | Written By | Line(s) |
|----------|-----------|---------|
| `mintPacked_[player]` | B1 | 217, 237, 281 (conditional: only if data != prevData) |

### Cached-Local-vs-Storage Check

| Ancestor Local | Descendant Write | Verdict |
|---------------|-----------------|---------|
| `prevData = mintPacked_[player]` | `mintPacked_[player]` | **SAFE** -- `prevData` is used for comparison to avoid unnecessary writes. The write overwrites it. No stale-cache writeback issue because `data` is derived from `prevData` with modifications. |

No external calls. No cross-function cache issues.

### Attack Analysis

**1. State coherence:** SAFE. Single function, no subordinate calls that modify storage.

**2. Access control:** SAFE. External payable, accessible only via delegatecall from Game (called through `recordMint`).

**3. Edge cases:**
- **lvl == 0:** `sameLevel` and `sameUnitsLevel` comparisons work correctly. `prevLevel == 0` is the initial state.
- **mintUnits == 0:** `levelUnitsAfter = levelUnitsBefore + 0 = levelUnitsBefore`. Same level path: data unchanged, no write. Early exit: `levelUnitsAfter < 4` might trigger for new level. SAFE.
- **total == type(uint24).max (16,777,215):** Increment skipped. Capped. SAFE.
- **Whale bundle frozen state (frozenUntilLevel > 0):** When `lvl < frozenUntilLevel`, `isFrozen = true`, total not incremented. When `lvl >= frozenUntilLevel`, frozen flag and bundle type cleared, total incremented normally. SAFE.

**4. Bit-packing correctness:** Uses `BitPackingLib.setPacked` for all field writes. The shifts and masks are defined as constants in BitPackingLib. Each field occupies its documented bit range. No field overlap. SAFE.

**5. Unchecked arithmetic:** `total = uint24(total + 1)` in unchecked block at line 264. Guarded by `total < type(uint24).max` check at line 262. SAFE.

---

## MintModule::purchaseCoin() (lines 581-591) [B4] -- via _purchaseCoinFor() (lines 600-626) [C2]

### Call Tree
```
purchaseCoin(buyer, ticketQuantity, lootBoxBurnieAmount) [line 581] -- external
  +-- _purchaseCoinFor(buyer, ticketQuantity, lootBoxBurnieAmount) [line 586] -- C2
      +-- gameOver check [line 605] -- revert E()
      +-- payer = msg.sender [line 606]
      +-- If ticketQuantity != 0 [line 608]:
      |   +-- Coin purchase cutoff check [lines 610-611]:
      |   |   +-- elapsed = block.timestamp - levelStartTime [line 610]
      |   |   +-- level == 0 ? elapsed > 335 days : elapsed > 90 days [line 611]
      |   |   +-- revert CoinPurchaseCutoff() if exceeded
      |   +-- _callTicketPurchase(buyer, payer, ticketQuantity, DirectEth, true, bytes32(0), 0) [line 612] -- C3
      |       +-- (see C3 analysis -- payInCoin=true path)
      +-- If lootBoxBurnieAmount != 0 [line 623]:
          +-- _purchaseBurnieLootboxFor(buyer, lootBoxBurnieAmount) [line 624] -- C5
```

### Storage Writes (Full Tree)

Via C3 (payInCoin=true path): `centuryBonusLevel`, `centuryBonusUsed[buyer]`, `ticketQueue[wk]`, `ticketsOwedPacked[wk][buyer]`. External: `coin.burnCoin`, `coin.notifyQuestMint`, `coin.creditFlip`.
Via C5: `lootboxBurnie`, `lootboxDay`, `lootboxRngPendingBurnie`, `lootboxRngPendingEth`.

### Cached-Local-vs-Storage Check

| Ancestor Local | Descendant Write | Verdict |
|---------------|-----------------|---------|
| `payer = msg.sender` | N/A | **SAFE** -- `msg.sender` is a transaction-level constant, cannot be modified. |
| `elapsed = block.timestamp - levelStartTime` | `levelStartTime` | **SAFE** -- No descendant writes `levelStartTime`. |

### Attack Analysis

**1. State coherence:** SAFE. No cached storage values that could go stale.

**2. Access control:** SAFE. Delegatecall from Game.

**3. Edge cases:**
- **Coin purchase cutoff:** `level == 0 ? 335 days : 90 days` from `levelStartTime`. At level 0, the 365-day liveness guard gives 30 days buffer. At level 1+, the 120-day guard gives 30 days buffer. The cutoff prevents cheap BURNIE positioning near game-over. Correctly prevents both `purchaseCoin` with tickets AND `purchaseBurnieLootbox` (via separate path). SAFE.
- **buyer == address(0):** Not checked in `purchaseCoin` or `_purchaseCoinFor`. However, `_callTicketPurchase` calls `IDegenerusGame.recordMint(payer, ...)` where `payer = msg.sender` (never zero). The `_queueTicketsScaled` function at GameStorage L561 has `if (quantityScaled == 0) return` but no zero-address check. Tickets could be queued for `buyer = address(0)`. However, DegenerusGame's entry point (`buyTicketsCoin`) validates the buyer before delegatecalling. SAFE (at the Game level, not at the module level).

**4. Ordering:** Ticket purchase happens before lootbox purchase. No interaction between the two paths. SAFE.

---

## MintModule::purchaseBurnieLootbox() (lines 595-598) [B5] -- via _purchaseBurnieLootboxFor() (lines 1039-1071) [C5]

### Call Tree
```
purchaseBurnieLootbox(buyer, burnieAmount) [line 595] -- external
  +-- buyer == address(0) check [line 596] -- revert E()
  +-- _purchaseBurnieLootboxFor(buyer, burnieAmount) [line 597] -- C5
      +-- gameOver check [line 1040] -- revert E()
      +-- burnieAmount < BURNIE_LOOTBOX_MIN check [line 1041] -- revert E()
      +-- index = lootboxRngIndex [line 1042]
      +-- index == 0 check [line 1043] -- revert E()
      +-- coin.burnCoin(buyer, burnieAmount) [line 1045] -- EXTERNAL CALL
      +-- questUnitsRaw = burnieAmount / PRICE_COIN_UNIT [line 1048]
      +-- coin.notifyQuestMint(buyer, uint32(questUnitsRaw), false) [line 1050] -- EXTERNAL CALL
      +-- existingAmount = lootboxBurnie[index][buyer] [line 1054]
      +-- If lootboxDay[index][buyer] == 0: set day [line 1055-1057]
      |   +-- lootboxDay[index][buyer] = _simulatedDayIndex() [line 1056] -- STORAGE WRITE
      +-- lootboxBurnie[index][buyer] += burnieAmount [line 1058] -- STORAGE WRITE
      +-- lootboxRngPendingBurnie += burnieAmount [line 1060] -- STORAGE WRITE
      +-- virtualEth = (burnieAmount * price) / PRICE_COIN_UNIT [lines 1062-1064]
      +-- _maybeRequestLootboxRng(virtualEth) [line 1066] -- C6
      |   +-- lootboxRngPendingEth += virtualEth [line 1074] -- STORAGE WRITE
      +-- emit BurnieLootBuy [line 1070]
```

### Storage Writes (Full Tree)

| Variable | Written By | Line(s) |
|----------|-----------|---------|
| `lootboxDay[index][buyer]` | C5 | 1056 |
| `lootboxBurnie[index][buyer]` | C5 | 1058 |
| `lootboxRngPendingBurnie` | C5 | 1060 |
| `lootboxRngPendingEth` | C6 | 1074 |

### Cached-Local-vs-Storage Check

| Ancestor Local | Descendant Write | Verdict |
|---------------|-----------------|---------|
| `index = lootboxRngIndex` | `lootboxRngIndex` | **SAFE** -- No descendant writes `lootboxRngIndex`. |

### Attack Analysis

All angles: **SAFE**. Simple function with no complex state interactions. BURNIE burn is atomic (external call to BurnieCoin which checks balance and reverts on insufficient). No cached-local issues.

---

## Part 2: MULTI-PARENT Category C Functions -- Standalone Analysis

---

## MintModule::_callTicketPurchase() (lines 831-1024) [C3] [MULTI-PARENT]

**Called from:** C1 (_purchaseFor, payInCoin=false) and C2 (_purchaseCoinFor, payInCoin=true)

### Call Tree (both contexts)
```
_callTicketPurchase(buyer, payer, quantity, payKind, payInCoin, affiliateCode, value) [line 831]
  +-- quantity == 0 check [line 840] -- revert
  +-- gameOver check [line 841] -- revert
  +-- targetLevel routing [lines 842-851]:
  |   +-- targetLevel = jackpotPhaseFlag ? level : level + 1 [line 842]
  |   +-- Last jackpot day fix [lines 845-851]
  +-- affiliateLevel = level + 1 [line 854]
  +-- priceWei = price [line 856] -- CACHE of storage
  +-- costWei = (priceWei * quantity) / (4 * TICKET_SCALE) [line 857]
  +-- costWei validation [lines 858-859]
  +-- Boost application (ETH path only) [lines 862-876]:
  |   +-- IDegenerusGame(address(this)).consumePurchaseBoost(payer) [line 863] -- SELF-CALL
  |   +-- adjustedQuantity += (cappedQty * boostBps) / 10_000 [line 874]
  +-- Century bonus [lines 880-900]:
  |   +-- IDegenerusGame(address(this)).playerActivityScore(buyer) [line 881] -- SELF-CALL (view)
  |   +-- centuryBonusLevel = targetLevel [line 894] -- STORAGE WRITE
  |   +-- centuryBonusUsed[buyer] += bonusQty [line 895] -- STORAGE WRITE
  +-- payInCoin path [lines 903-914]:
  |   +-- _coinReceive(payer, coinCost) [line 905] -- C4 (coin.burnCoin)
  |   +-- coin.notifyQuestMint(payer, questQty, false) [line 910] -- EXTERNAL CALL
  |   +-- bonusCredit = coinCost / 10 [line 914]
  +-- ETH path [lines 915-1012]:
  |   +-- IDegenerusGame(address(this)).recordMint{value: value}(...) [line 918] -- SELF-CALL
  |   +-- Payment kind validation [lines 927-938]
  |   +-- coin.notifyQuestMint(payer, scaled, true) [line 943-944] -- EXTERNAL CALL
  |   +-- freshBurnie inflation for last jackpot day [lines 950-962]
  |   +-- affiliate.payAffiliate(...) [lines 964-1003] -- EXTERNAL CALL (multiple paths)
  |   +-- bonusCredit calculation [lines 1005-1010]
  +-- coin.creditFlip(buyer, bonusCredit) [line 1015] -- EXTERNAL CALL
  +-- _queueTicketsScaled(buyer, ticketLevel, adjustedQty32) [line 1022] -- C10
```

### Cross-Parent Analysis

**Context 1: Called from C1 (_purchaseFor) with payInCoin=false:**
- `payer = buyer` (set at C1 line 682)
- `value = remainingEth` (leftover ETH after lootbox)
- `payKind` = user-specified (DirectEth, Claimable, or Combined)
- Boost is applied (consumePurchaseBoost self-call)
- ETH path: recordMint self-call with value forwarding
- Affiliate payments with fresh BURNIE basis

**Context 2: Called from C2 (_purchaseCoinFor) with payInCoin=true:**
- `payer = msg.sender` (set at C2 line 606)
- `value = 0`
- `payKind = MintPaymentKind.DirectEth` (set at C2 line 616)
- Boost is NOT applied (payInCoin=true skips lines 862-876)
- BURNIE path: coin.burnCoin, no recordMint self-call
- No affiliate payments (affiliateCode = bytes32(0))

**F-03 (INVESTIGATE/INFO):** Century bonus at line 888: `maxBonus = (20 ether) / (priceWei >> 2)`. If `priceWei` is very small (but price minimum is 0.01 ether from level 0), `priceWei >> 2 = 0.0025 ether >> 2` which is non-zero. At `priceWei = 0.01 ether`, `priceWei >> 2 = 2,500,000,000,000,000` (0.0025 ETH). `maxBonus = 20e18 / 2.5e15 = 8000`. Safe. The only concern would be `priceWei < 4` (causing `priceWei >> 2 = 0`), but price is always >= 0.01 ether.

**F-04 (INVESTIGATE/INFO):** Ticket level routing: When `jackpotPhaseFlag == true && rngLockedFlag == false`, `targetLevel = level`. This means tickets are for the current level's jackpot phase. The question is: can these tickets be processed? Yes -- `processFutureTicketBatch` is called with the level being processed, and the read key points to the correct queue. During jackpot phase, `advanceGame` drains the ticket queue for the current level. SAFE.

### Cached-Local-vs-Storage Check

| Ancestor Local | Descendant Write | Verdict |
|---------------|-----------------|---------|
| `priceWei = price` (L856) | `price` | **SAFE** -- No descendant writes `price`. The self-call to `recordMint` handles ETH routing but does not modify `price`. |
| `targetLevel` (L842) | `level` | **SAFE** -- No descendant writes `level`. `recordMintData` only writes `mintPacked_[player]`. |

---

## MintModule::_purchaseBurnieLootboxFor() (lines 1039-1071) [C5] [MULTI-PARENT]

**Called from:** B5 (purchaseBurnieLootbox) and C2 (_purchaseCoinFor)

Both calling contexts are equivalent -- the function receives `buyer` and `burnieAmount`. B5 adds a zero-address check before calling. C2 does not, but Game entry points validate buyer. No cross-parent cache interaction. SAFE.

---

## MintModule::_maybeRequestLootboxRng() (lines 1073-1075) [C6] [MULTI-PARENT]

**Called from:** C1 (_purchaseFor, lootbox path) and C5 (_purchaseBurnieLootboxFor)

Simple accumulator: `lootboxRngPendingEth += lootBoxAmount`. No complex state. Both callers pass the appropriate amount (ETH amount or virtual ETH equivalent). No cross-parent cache issues. SAFE.

---

## Part 3: Assembly Verification

---

## MintModule::_raritySymbolBatch() (lines 443-537) [C8] [ASSEMBLY]

### Inline Yul Assembly Analysis (lines 502-536)

**Storage Slot Derivation:**

```solidity
assembly ("memory-safe") {
    mstore(0x00, lvl)                     // key = lvl
    mstore(0x20, traitBurnTicket.slot)    // slot = mapping slot number
    levelSlot := keccak256(0x00, 0x40)    // keccak256(lvl . slot)
}
```

**Verification:** For a `mapping(uint24 => address[256])`, Solidity computes the base slot for key `lvl` as `keccak256(abi.encode(lvl, mappingSlot))`. Since `lvl` is `uint24`, `mstore(0x00, lvl)` zero-pads to 32 bytes. `traitBurnTicket.slot` is the storage slot number of the mapping. `keccak256(0x00, 0x40)` hashes the 64-byte concatenation. This matches Solidity's standard layout. **CORRECT.**

**Array Element Access:**

```solidity
let elem := add(levelSlot, traitId)   // Fixed array: slot = base + index
let len := sload(elem)                // Array length at this slot
```

**Wait** -- this is treating `traitBurnTicket[lvl]` as a fixed-size array of 256 elements, each being a dynamic array (`address[]`). For `mapping(uint24 => address[][256])` (or similar), `levelSlot + traitId` gives the length slot for the `traitId`-th dynamic array within the fixed-size outer array. Since `traitId` is `uint8` (0-255), `add(levelSlot, traitId)` correctly indexes into the 256-element fixed array. Each element is a dynamic `address[]` array whose length is at this slot. **CORRECT.**

**Data Slot and Write:**

```solidity
mstore(0x00, elem)
let data := keccak256(0x00, 0x20)     // Data start = keccak256(length_slot)
let dst := add(data, len)              // Next write position = data + current length
for { let k := 0 } lt(k, occurrences) { k := add(k, 1) } {
    sstore(dst, player)               // Write player address
    dst := add(dst, 1)
}
```

**Verification:** For a dynamic array, data starts at `keccak256(length_slot)`. Elements are at `keccak256(length_slot) + index`. Writing at `data + len` (current length) is the first free slot. Writing `occurrences` times fills slots `len` through `len + occurrences - 1`. Then `sstore(elem, newLen)` at line 518 updates the length to `len + occurrences`. **CORRECT.**

**Length Update:**

```solidity
let newLen := add(len, occurrences)
sstore(elem, newLen)
```

**Verification:** Length is updated BEFORE the data writes (line 518 before the for loop at line 524). This means if the transaction reverts mid-write, the length would be updated but data would be partial. However, in Solidity 0.8+, a revert rolls back ALL state changes including the length update. The pre-update ordering is a gas optimization (avoiding a second SSTORE) and is safe because the entire assembly block is within a non-reentrant delegatecall context. **CORRECT.**

**LCG Period:**

`TICKET_LCG_MULT = 6364136223846793005` is the multiplier from Knuth's MMIX LCG. With modulus `2^64` (implicit in uint64 overflow) and increment 1 (line 477: `s = s * TICKET_LCG_MULT + 1`), this LCG has full period `2^64`. The seed initialization at line 469 ensures `s` is odd (`| 1`), and the modified multiplier at line 472 (`TICKET_LCG_MULT + uint64(offset)`) does not break the period as long as `s` is odd (which it is). **VALID.**

**Trait Distribution:**

`DegenerusTraitUtils.traitFromWord(s)` uses weighted grid distribution. The quadrant offset `(uint8(i & 3) << 6)` maps each of 4 consecutive traits to different quadrants (0-63, 64-127, 128-191, 192-255). This ensures each ticket gets traits from all 4 quadrants. **CORRECT.**

### Assembly Verdict: CORRECT -- Storage slot derivation matches Solidity layout. Array length accounting is correct. Data slot calculation is correct. LCG has full 2^64 period.

---

## Part 4: Self-Call Re-Entry Analysis

---

### recordMint Self-Call Pattern (C3 line 918)

**Flow:**
```
DegenerusGame (caller) -> delegatecall -> MintModule._callTicketPurchase()
  -> CALL -> DegenerusGame.recordMint{value}(payer, targetLevel, costWei, mintUnits, payKind)
    -> DegenerusGame handles ETH routing (pool splits, claimable deduction)
    -> delegatecall -> MintModule.recordMintData(payer, targetLevel, mintUnits)
      -> writes mintPacked_[payer]
    -> DegenerusGame returns
  -> _callTicketPurchase continues with post-recordMint logic
```

**State Coherence Check:**

What does `recordMint` in DegenerusGame write?
1. `mintPacked_[payer]` (via recordMintData delegatecall)
2. `currentPrizePool` += fresh ETH share
3. `prizePoolsPacked` (future/next pool updates)
4. `claimableWinnings[payer]` -= claimable amount (for Claimable/Combined)
5. `claimablePool` -= claimable amount

After the self-call returns, `_callTicketPurchase` continues at line 927+ with:
- `value` (parameter, not storage) -- SAFE
- `payKind` (parameter) -- SAFE
- `costWei` (local, computed from `priceWei`) -- `priceWei` not written by recordMint. SAFE.
- `freshEth` (computed from `payKind` and `value`) -- SAFE
- `freshBurnie` (computed from `freshEth` and `priceWei`) -- SAFE

No local variable in `_callTicketPurchase` caches a value that `recordMint` writes. **SAFE.**

### consumePurchaseBoost Self-Call (C3 line 863)

**Flow:**
```
MintModule._callTicketPurchase() [delegatecall context]
  -> CALL -> DegenerusGame.consumePurchaseBoost(payer)
    -> reads boonPacked[payer].slot0 (purchase boost fields)
    -> clears boost fields
    -> returns boostBps
  -> _callTicketPurchase uses boostBps for adjustedQuantity
```

**Can boost be double-consumed?** The boost is cleared in `consumePurchaseBoost` before returning. If the same player calls `purchase` twice in the same block, the second call gets `boostBps = 0` because the fields are already cleared. **SAFE.**

---

## Part 5: Inherited Helpers Analysis

---

## GameStorage::_queueTicketsScaled() (lines 556-594) [C10] [INHERITED]

**Analysis within MintModule call context:**

Called from C3 at line 1022 with `(buyer, ticketLevel, adjustedQty32)`.

- `quantityScaled == 0`: returns immediately (line 561). SAFE.
- `isFarFuture = targetLevel > level + 5`: Far-future tickets use separate key space. SAFE.
- `rngLockedFlag` check for far-future (line 564): Prevents queue writes during VRF commitment window. SAFE.
- `ticketQueue[wk].push(buyer)` only if first entry (owed==0 && rem==0). No duplicate queue entries. SAFE.
- Fractional ticket handling: `whole = quantityScaled / 100`, `frac = quantityScaled % 100`. Remainder accumulation with overflow to whole ticket at >= 100. SAFE.
- `unchecked { owed += whole }`: Could overflow uint32 if a player queues > 4.29 billion tickets. At 0.0025 ETH minimum per ticket unit, this would require > 10M ETH. Economically infeasible. SAFE.

## GameStorage::_awardEarlybirdDgnrs() (lines 914-974) [C11] [INHERITED]

**Analysis within _purchaseFor call context:**

Called from C1 at line 811 with `(buyer, lootboxFreshEth, purchaseLevel)`.

- `purchaseWei == 0` or `buyer == address(0)`: returns immediately. SAFE.
- `currentLevel >= EARLYBIRD_END_LEVEL (3)`: One-shot pool dump to lootbox pool, then return. Idempotent (sentinel `type(uint256).max`). SAFE.
- Quadratic emission curve: `payout = (poolStart * (d2 - d1)) / denom`. No overflow for realistic values (`d2 - d1` bounded by `totalEth^2 = (1000 ETH)^2 = 10^42`, and `poolStart` is a sDGNRS balance). SAFE.
- External calls to sDGNRS: `transferFromPool` and `transferBetweenPools` operate on sDGNRS storage only. SAFE for Game storage coherence.

## MintStreakUtils::_recordMintStreakForLevel() (lines 17-46) [C9] [INHERITED]

**Analysis:**

- `player == address(0)`: returns. SAFE.
- Idempotent per level: `lastCompleted == mintLevel -> return`. SAFE.
- Streak logic: consecutive levels increment streak, non-consecutive reset to 1. Streak capped at `type(uint24).max`. SAFE.
- `unchecked { newStreak = streak + 1 }`: Guarded by `streak < type(uint24).max`. SAFE.

---

## Part 6: Category D Functions

---

**D1 `_rollRemainder()`:** Pure. `EntropyLib.entropyStep(entropy ^ rollSalt) % TICKET_SCALE`. TICKET_SCALE=100 divides 2^256 evenly. No modulo bias. SAFE.

**D2 `_ethToBurnieValue()`:** Pure. Division by zero guarded (`priceWei == 0 -> return 0`). SAFE.

**D3 `_calculateBoost()`:** Pure. Unchecked but bounded: `cappedAmount <= 10 ether`, `bonusBps <= 2500`. Product = 25e21, fits in uint256. SAFE.

**D4 `_mintStreakEffective()`:** View. Returns streak or 0 based on level gap. No state change. SAFE.
