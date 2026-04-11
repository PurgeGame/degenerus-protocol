# Backward Trace from Every RNG Consumer (RNG-02)

**Audit date:** 2026-04-11
**Source:** contracts at current HEAD
**Methodology:** Backward trace per D-05 -- start from every consumer read site, trace data backward to commitment point, prove VRF word was unknown at commitment time.

---

## Methodology

For each consumer:
1. Find the exact call site that reads `rngWordByDay`, `lootboxRngWordByIndex`, or a derivative (keccak, shift, mask, LCG seed).
2. Identify what data the word determines (winners, amounts, outcomes).
3. Trace that data backward to when it was committed (locked and immutable).
4. Verify the VRF word was NOT on-chain at the commitment point.
5. Check for seam bugs: data that reaches the consumer without passing through the VRF request barrier.

---

### RNG-01: Daily Word -- rngGate and _backfillGapDays

**Word source:** `rngWordByDay[day]` (daily VRF word, stored by `_applyDailyRng` at AdvanceModule line 1626)

#### RNG-01a: rngGate daily processing

**Read site:** DegenerusGameAdvanceModule.sol `rngGate()` line 1008 (fast path) and line 1031 (fresh word path via `_applyDailyRng`)
**Data resolved:** All daily processing -- coinflip payouts (line 1032), quest rolls (line 1033), redemption resolution (lines 1041-1049), lootbox RNG finalization (line 1052), and downstream jackpot/trait processing via `advanceGame` delegatecalls
**Input commitment point:** All daily-resolved data was committed on prior days:
- Coinflip bets: placed during purchase phase days via `BurnieCoinflip.creditFlip()`, each bet recorded before the daily RNG request
- Quest state: accumulated from player actions during prior days
- Redemption pending amounts: submitted via sDGNRS redemption request (separate transaction, prior day)
- Lootbox purchases: committed to `lootboxEth[index][player]` and `lootboxBurnie[index][player]` during purchase phase (MintModule line 1020, WhaleModule line 876, MintModule line 1418)
**Word availability at commitment:** The daily VRF word is requested at the END of the current `advanceGame` call via `_requestRng()` (line 1067) and fulfilled by VRF coordinator in a separate transaction (`rawFulfillRandomWords` line 1530). At commitment time (prior day's purchase transactions), the word does not exist -- it has not been requested yet. The VRF request fires after `rngGate` returns `(1, 0)`, and the word arrives in a future block (10 confirmation blocks minimum per `VRF_REQUEST_CONFIRMATIONS = 10` at line 118).
**Verdict:** SAFE -- word unknown at commitment time. Daily processing inputs committed during purchase phase days; VRF word requested at day boundary and delivered in a separate future transaction.
**Evidence:** _requestRng fires at line 1067 (rngGate branch 4), VRF_REQUEST_CONFIRMATIONS = 10 (line 118), rawFulfillRandomWords validates msg.sender == vrfCoordinator (line 1534). Word written to rngWordByDay at line 1626 only after VRF delivery.

#### RNG-01b: _backfillGapDays

**Read site:** DegenerusGameAdvanceModule.sol `_backfillGapDays()` line 1575: `keccak256(abi.encodePacked(vrfWord, gapDay))`
**Data resolved:** Coinflip payouts for gap days (line 1579). Each gap day gets a deterministic derived word from `keccak256(vrfWord, gapDay)`.
**Input commitment point:** Coinflip bets for gap days were placed during the purchase phase before the VRF stall began. The VRF stall means no new daily processing occurred, so no new bets could be placed for gap days (advanceGame reverts `RngNotReady()` at line 1063 during stall).
**Word availability at commitment:** The source VRF word (`vrfWord` parameter) is the first post-gap VRF delivery. During the stall, `rngLockedFlag == true` (set at line 1442), blocking all state-changing user actions. Gap day bets were placed before the stall started.
**Verdict:** SAFE -- source VRF word unknown at commitment time. Gap day bets committed before VRF stall; derived words use post-gap VRF entropy.
**Evidence:** rngLockedFlag set at line 1442 during request, blocking further state changes. _backfillGapDays called at line 1018, only after VRF delivery (branch 2 of rngGate, guarded by `currentWord != 0 && rngRequestTime != 0` at line 1013). Derived word mixes VRF with gap day index (line 1575).

---

### RNG-02: Lootbox Word -- openLootBox / openBurnieLootBox

**Word source:** `lootboxRngWordByIndex[index]` (per-index VRF word)

#### RNG-02a: openLootBox (ETH lootbox)

**Read site:** DegenerusGameLootboxModule.sol `openLootBox()` line 533: `uint256 rngWord = lootboxRngWordByIndex[index]`
**Data resolved:** Lootbox target level, ticket distribution, EV multiplier application, boon generation (line 554: `keccak256(abi.encode(rngWord, player, day, amount))` creates entropy for `_rollTargetLevel`)
**Input commitment point:** Lootbox ETH amount committed at purchase time via `lootboxEth[index][player]` writes in MintModule (line 1020) and WhaleModule (line 876). The `index` used is the current `lootboxRngIndex` at purchase time, read via `_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)`.
**Word availability at commitment:** Two VRF paths write lootbox words:
1. **Daily path:** `_finalizeLootboxRng(currentWord)` at AdvanceModule line 1052 writes `lootboxRngWordByIndex[index] = rngWord` at line 1074. This uses the daily VRF word.
2. **Mid-day path:** `rawFulfillRandomWords` line 1546 writes directly from VRF callback.
In both cases, the word is written AFTER the lootbox index was advanced by `_finalizeRngRequest` (line 1432: index incremented on fresh request). Purchases after the VRF request target the NEXT index (index + 1), so they cannot be resolved by the current word. Purchases before the request target the current index and were committed before the word existed.
**Verdict:** SAFE -- word unknown at commitment. Lootbox index advance at VRF request time (line 1432) ensures purchases committed before VRF request are resolved by a word that arrives later.
**Evidence:** `_finalizeRngRequest` line 1432 increments index before VRF delivery. `openLootBox` reads `lootboxRngWordByIndex[index]` where `index` was recorded at purchase time. VRF word written at line 1074 (daily) or line 1546 (mid-day), both after the request that advanced the index.

#### RNG-02b: openBurnieLootBox (BURNIE lootbox)

**Read site:** DegenerusGameLootboxModule.sol `openBurnieLootBox()` line 611: `uint256 rngWord = lootboxRngWordByIndex[index]`
**Data resolved:** Identical to RNG-02a -- target level, ticket distribution via `keccak256(abi.encode(rngWord, player, day, amountEth))` at line 628
**Input commitment point:** BURNIE lootbox amount committed at purchase time via `lootboxBurnie[index][player]` write in MintModule line 1418. Same index mechanism as ETH lootboxes.
**Word availability at commitment:** Same as RNG-02a. Index advance at VRF request time ensures word did not exist at purchase.
**Verdict:** SAFE -- same index isolation as RNG-02a.
**Evidence:** Same as RNG-02a. BURNIE lootbox uses identical index-keyed word storage.

---

### RNG-03: _randTraitTicket -- Winner Selection from Daily Word

**Word source:** `rngWordByDay[day]` (daily VRF word), passed through `payDailyJackpot` as `randWord` parameter, then into `_resolveTraitWinners` and `_processDailyEth` as `entropy`

**Read site:** DegenerusGameJackpotModule.sol `_randTraitTicket()` line 1640: `keccak256(abi.encode(randomWord, trait, salt, i)) % effectiveLen`
**Data resolved:** Which ticket holders win the jackpot. The modular index selects winners from `traitBurnTicket[lvl][trait]` array (line 1614: `holders = traitBurnTicket_[trait]`). Also selects virtual deity entries (lines 1620-1628).
**Input commitment point:** Ticket holders are committed to `traitBurnTicket[lvl]` during ticket processing via `_raritySymbolBatch` (MintModule line 626: assembly SSTORE of player address into trait array). Ticket processing occurs during `advanceGame` mid-day path (line 186-217) or during the daily processing flow, both BEFORE the next day's VRF request. The `ticketQueue` is populated during purchase transactions, and `_swapAndFreeze` (line 275) swaps the write buffer to read buffer at VRF request time, freezing the set of tickets to be processed.
**Word availability at commitment:** Tickets are queued during purchase phase and processed during the same day's `advanceGame` calls. The jackpot draws from `traitBurnTicket[lvl]` which was populated during ticket processing of the CURRENT level. The daily VRF word that determines winners is requested at the end of the jackpot phase's last purchase day (`_requestRng` at line 1067). All ticket holder addresses were committed before this request.
**Verdict:** SAFE -- ticket holders committed before VRF word requested. The `_swapAndFreeze` mechanism (line 275, calling `_swapTicketSlot` at Storage line 750) ensures the read buffer is frozen at VRF request time.
**Evidence:** `_swapAndFreeze(purchaseLevel)` at line 275 occurs when `rngWord == 1` (VRF just requested). `_swapTicketSlot` (Storage line 750-755) flips `ticketWriteSlot`, making current write queue the read queue. New purchases write to the new write slot. `_randTraitTicket` reads from `traitBurnTicket[lvl]` (line 1614) which was built from the frozen read queue.

**Seam check -- mid-day ticket swap:** The mid-day `requestLootboxRng` (AdvanceModule line 907) also triggers a ticket slot swap (lines 949-956: `_swapTicketSlot` + `_lrWrite(LR_MID_DAY_SHIFT, ..., 1)`). This is safe because: (a) mid-day swap only processes tickets from the frozen read slot, (b) the `LR_MID_DAY_MASK` flag blocks further `advanceGame` ticket processing until the lootbox VRF word arrives (line 190-193: reverts `NotTimeYet()` if word is 0), and (c) `requestLootboxRng` requires `rngLockedFlag == false` (line 908) and today's daily word already recorded (line 919: `rngWordByDay[currentDay] == 0` reverts), so it can only fire after daily jackpot processing is complete.

---

### RNG-04: _runJackpotEthFlow -- Entropy Rotation Across Buckets

**Word source:** `rngWordByDay[day]` (daily VRF word), passed as `randWord` through `payDailyJackpot` (line 313) -> entropy derivation at line 1100

**Read site:** DegenerusGameJackpotModule.sol `_runJackpotEthFlow()` line 1100: `uint8 offset = uint8(jp.entropy & 3)` and line 1108: `bucketCounts[i] = base[(i + offset) & 3]`
**Data resolved:** The rotation offset determines which trait bucket gets the largest (20-winner) pool vs smallest (1-winner solo) pool. This affects ETH distribution concentration. The `entropy` field flows into `_processDailyEth` (line 1112-1122) which uses it for all winner selection via `_randTraitTicket`.
**Input commitment point:** Bucket assignments derive from trait ticket populations in `traitBurnTicket[lvl]`. Ticket holder addresses and counts are committed during ticket processing (same commitment as RNG-03). The entropy rotation merely reorders which fixed bucket gets which share -- it does not change who is in each bucket.
**Word availability at commitment:** Same as RNG-03. Trait ticket arrays populated before VRF request. The `jp.entropy` is derived from `randWord ^ (uint256(lvl) << 192)` at line 426, where `randWord` is the daily VRF word.
**Verdict:** SAFE -- bucket populations committed before VRF word. The rotation only determines share distribution, not membership.
**Evidence:** `_runJackpotEthFlow` receives `jp.entropy` which is `randWord ^ (uint256(lvl) << 192)` (line 426). `traitBurnTicket[lvl]` populated by `_raritySymbolBatch` during ticket processing, prior to jackpot phase VRF request.

---

### RNG-05: payDailyJackpot Carryover -- FuturePool Tickets

**Word source:** `rngWordByDay[day]` (daily VRF word), passed as `randWord` to `payDailyJackpot` (line 313)

**Read site:** DegenerusGameJackpotModule.sol `payDailyJackpot()` lines 389-398: `keccak256(abi.encodePacked(randWord, DAILY_CARRYOVER_SOURCE_TAG, counter)) % DAILY_CARRYOVER_MAX_OFFSET + 1` to select `sourceLevelOffset`
**Data resolved:** The `sourceLevelOffset` determines which future level receives the 0.5% futurePool carryover tickets (lines 400-410). `reserveSlice = futurePoolBal / 200` is moved from futurePool to nextPool and converted to `carryoverTicketUnits`.
**Input commitment point:** The futurePool balance (`_getFuturePrizePool()` at line 403) is committed by all prior purchase/deposit transactions. The level offset determines which level's ticket queue receives the carryover. This is a protocol-internal distribution, not directly player-controlled.
**Word availability at commitment:** The daily VRF word is requested at the end of the last purchase day. The futurePool balance is the accumulation of all prior purchase contributions. Players cannot change the futurePool balance after the VRF request fires because `prizePoolFrozen == true` (set by `_swapAndFreeze` at line 762) and all pool writes during freeze go to pending accumulators (e.g., DegeneretteModule line 530-531).
**Verdict:** SAFE -- futurePool balance committed before VRF word. Level offset is protocol-internal and not player-controllable.
**Evidence:** `_swapAndFreeze` (line 760-766) sets `prizePoolFrozen = true` at VRF request time. Pool writes during freeze go to pending accumulators (`_setPendingPools` calls). `payDailyJackpot` reads `_getFuturePrizePool()` which reflects the frozen state.

---

### RNG-06: _placeDegeneretteBetCore -- Bet Resolution via Daily/Lootbox Word

**Word source:** `lootboxRngWordByIndex[index]` (lootbox VRF word)

**Read site:** DegenerusGameDegeneretteModule.sol `_resolveFullTicketBet()` line 574: `uint256 rngWord = lootboxRngWordByIndex[index]`
**Data resolved:** Bet outcome -- the RNG word determines the result ticket via `keccak256(abi.encodePacked(rngWord, index, [spinIdx,] QUICK_PLAY_SALT))` at lines 594-606. The result ticket is compared against the player's custom ticket to determine matches and payout.
**Input commitment point:** The bet is placed via `_placeDegeneretteBetCore()` which records to `degeneretteBets[player][nonce]` at line 457. The bet stores `uint32(index)` (line 446) -- the current lootbox RNG index at bet time. The custom ticket, amount, currency, and activity score are all packed into the bet and immutable after placement.
**Word availability at commitment:** At bet placement time, `_placeDegeneretteBetCore` checks `lootboxRngWordByIndex[index] != 0` and reverts `RngNotReady()` at line 430 if the word already exists. This is a CRITICAL guard: it ensures bets can only be placed when the current index's word is NOT yet available. The word arrives later via VRF callback.
**Verdict:** SAFE -- explicit guard at line 430 ensures word unknown at bet commitment. The `lootboxRngWordByIndex[index] != 0` revert prevents betting on an index whose word is already known.
**Evidence:** Line 430: `if (lootboxRngWordByIndex[index] != 0) revert RngNotReady()`. Line 446: `uint32(index)` stored in packed bet. Line 574: `lootboxRngWordByIndex[index]` read at resolution time (word must be nonzero to resolve, line 575).

---

### RNG-07: _raritySymbolBatch -- LCG PRNG Seeded from Lootbox Word (Seed Provenance Only per D-02)

**Word source:** `lootboxRngWordByIndex[index]` (lootbox VRF word), read via `lootboxRngWordByIndex[uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)) - 1]`

**Read site:** DegenerusGameMintModule.sol `processTicketBatch()` line 680: `uint256 entropy = lootboxRngWordByIndex[uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)) - 1]`, then `_raritySymbolBatch()` line 563: `seed = (baseKey + groupIdx) ^ entropyWord` and line 565: `uint64 s = uint64(seed) | 1`
**Data resolved:** Trait generation for ticket holders. The LCG PRNG generates trait IDs that determine which trait bucket each ticket goes into (`traitBurnTicket[lvl][traitId]`). This affects future jackpot winner selection (RNG-03).
**Input commitment point:** The `ticketQueue` addresses are committed during purchase transactions (queued by `_queueTicketsScaled` at MintModule line 1140). The queue is frozen at VRF request time by `_swapAndFreeze`/`_swapTicketSlot`. The `entropyWord` (lootbox VRF word) is what determines trait assignments.
**Word availability at commitment:** The lootbox VRF word is written either:
- By daily path: `_finalizeLootboxRng` (AdvanceModule line 1074) during rngGate processing
- By mid-day path: `rawFulfillRandomWords` (AdvanceModule line 1546) from VRF callback
The ticket queue was populated during the purchase phase. The ticket swap (`_swapTicketSlot` at Storage line 750) freezes the queue at VRF request time. The lootbox word used for trait generation targets the index that was current when tickets were queued.
**Verdict:** SAFE -- ticket queue committed during purchase phase before VRF request. LCG seed derives from VRF-sourced lootbox word that did not exist at queue commitment time. (Per D-02: seed provenance verified only; LCG statistical properties not analyzed.)
**Evidence:** `processTicketBatch` reads `lootboxRngWordByIndex[index - 1]` (line 680). Index was advanced at VRF request time (line 1432 in `_finalizeRngRequest`), so `index - 1` points to the word that was requested AFTER the ticket queue was frozen. `_swapAndFreeze` (line 275) fires simultaneously with VRF request.

---

### RNG-08: _gameOverEntropy -- prevrandao Fallback

**Word source:** Historical VRF words + `block.prevrandao` (fallback when VRF stalled > 3 days at gameover)

**Read site:** DegenerusGameAdvanceModule.sol `_gameOverEntropy()` lines 1123-1151 (fallback path) and `_getHistoricalRngFallback()` line 1177
**Data resolved:** When VRF is stalled during gameover, this generates a fallback entropy word used for terminal processing: coinflip payouts (line 1128), redemption resolution (lines 1136-1148), and lootbox finalization (line 1150). The fallback is `keccak256(historical VRF words, currentDay, block.prevrandao)`.
**Input commitment point:** All data resolved by this word was committed during purchase phase -- coinflip bets, redemption requests, lootbox purchases. Same commitment timeline as RNG-01.
**Word availability at commitment:** The fallback entropy uses:
1. Historical VRF words (committed on past days, immutable in `rngWordByDay`)
2. `block.prevrandao` (only known by the block producer at the block containing the gameover `advanceGame` call)
At input commitment time (purchase phase), neither the specific `prevrandao` nor the combination was knowable. Historical VRF words are deterministic but their combination with `prevrandao` adds unpredictability.
**Verdict:** INFO -- reduced security compared to fresh VRF. Historical VRF words are known, so the entropy depends on `block.prevrandao` for unpredictability (1-bit validator manipulation possible). However, this is a fallback-only path (VRF dead for 3+ days at gameover), and the comment at line 1168-1174 documents this as an acceptable trade-off. The gameover path at level 0 can have zero historical words, making it `prevrandao`-only -- but at level 0 the distributable funds are minimal.
**Evidence:** `_getHistoricalRngFallback` (line 1177) scans `rngWordByDay[i]` for up to 5 historical words within 30 days (lines 1180-1182). `GAMEOVER_RNG_FALLBACK_DELAY` triggers after 3 days (line 1123). `_tryRequestRng` (line 1156) attempts VRF first; fallback only fires on VRF failure + 3-day timeout.

---

### RNG-09: handleGameOverDrain -- Terminal Resolution

**Word source:** `rngWordByDay[day]` (daily VRF word or fallback from RNG-08)

**Read site:** DegenerusGameGameOverModule.sol `handleGameOverDrain()` line 97: `rngWord = rngWordByDay[day]`
**Data resolved:** Terminal jackpot distribution: 10% to decimator jackpot (line 162: `runTerminalDecimatorJackpot(decPool, lvl, rngWord)`), 90% to next-level ticket holders (line 174-175: `runTerminalJackpot(remaining, lvl + 1, rngWord)`). Both use the daily word for winner selection.
**Input commitment point:** Ticket holders committed during purchase phase (same as RNG-03). Decimator claims committed during purchase phase via decimator module. Pool balances committed by prior transactions.
**Word availability at commitment:** The daily word is generated via `_gameOverEntropy` (AdvanceModule line 508) or rngGate in the same `advanceGame` call that triggers gameover. The `_handleGameOverPath` function (line 474) first acquires the word (line 507-515), then calls `handleGameOverDrain` (line 517-523), then `_unlockRng` (line 524). The word was requested after all ticket holders and claims were committed.
**Verdict:** SAFE -- word acquired in gameover `advanceGame` call, after all inputs committed during purchase phase.
**Evidence:** `_handleGameOverPath` gates on `rngWordByDay[day] == 0` at line 507, acquires word via `_gameOverEntropy`, then proceeds to `handleGameOverDrain`. `handleGameOverDrain` gates on `rngWord = rngWordByDay[day]` at line 97, reverting with `E()` if zero when funds > 0 (line 98). All ticket/claim data committed before gameover trigger (liveness timeout at line 481-483).

---

### RNG-10: _deityDailySeed / _deityBoonForSlot -- Deity Boon from Daily Word

**Word source:** `rngWordByDay[day]` (daily VRF word), with fallback chain

**Read site:** DegenerusGameLootboxModule.sol `_deityDailySeed()` line 1743: `uint256 rngWord = rngWordByDay[day]`, then `_deityBoonForSlot()` line 1767: `keccak256(abi.encode(_deityDailySeed(day), deity, day, slot))`
**Data resolved:** Which boon types are available in each deity slot for the day. The seed determines the random roll that selects boon type from the weighted pool (line 1772: `roll = seed % total`).
**Input commitment point:** Deity pass ownership committed via deity pass purchase (a separate transaction on a prior day or earlier on the same day). The deity address is stored in `deityBySymbol[fullSymId]` and `deityPassOwners` array. The `day` parameter determines which daily seed is used.
**Word availability at commitment:** The daily word for day N is generated during the `advanceGame` call that processes day N. Deity pass purchases happen during the purchase phase (days before the jackpot phase begins). The word is requested at the transition to jackpot phase.

**Fallback chain in _deityDailySeed (lines 1743-1750):**
1. First tries `rngWordByDay[day]` -- if available, uses it
2. Falls back to `rngWordCurrent` -- the staging variable (only nonzero during active daily processing)
3. Falls back to `keccak256(abi.encodePacked(day, address(this)))` -- deterministic, no VRF

The third fallback is INFO-level: it uses no VRF entropy, making the boon selection deterministic and predictable. However, this only triggers when no daily word exists for the day AND no word is in staging -- meaning before the first-ever `advanceGame` or during a VRF stall. During normal operation, fallback 1 or 2 is always used.

**Verdict:** SAFE -- deity pass ownership committed before daily VRF word. Deterministic fallback (line 1748) is a design tradeoff for edge cases only.
**Evidence:** Deity passes purchased during purchase phase. `rngWordByDay[day]` written by `_applyDailyRng` (AdvanceModule line 1626) during jackpot processing. `_deityBoonForSlot` called by `getDeityDailyBoons` (line 751) and `redeemDeityBoon` (line 792) -- both are view/claim functions called after the daily word is available.

---

### RNG-11: _rollWinningTraits / _applyHeroOverride -- Winning Trait Selection

**Word source:** `rngWordByDay[day]` (daily VRF word), passed as `randWord` through `payDailyJackpot` (line 313)

#### RNG-11a: _rollWinningTraits

**Read site:** DegenerusGameJackpotModule.sol `_rollWinningTraits()` line 1864: `JackpotBucketLib.getRandomTraits(randWord)` extracts 4 winning trait IDs from the word
**Data resolved:** The 4 winning trait IDs for the daily jackpot. Each trait ID determines which bucket of ticket holders receives ETH. The traits are packed at line 1866: `JackpotBucketLib.packWinningTraits(traits)`.
**Input commitment point:** Player traits are committed when tickets are processed via `_raritySymbolBatch` (MintModule). The trait distribution is determined by the LCG PRNG (RNG-07). The winning traits are selected from the daily word -- they determine which existing trait buckets win, not which players are in those buckets.
**Word availability at commitment:** Same as RNG-03/04. Daily VRF word requested at end of last purchase day. Trait bucket populations fixed before VRF request.
**Verdict:** SAFE -- winning traits selected from daily VRF word that did not exist when trait buckets were populated.
**Evidence:** `_rollWinningTraits(randWord)` at line 1864 receives the daily VRF word via `payDailyJackpot(isJackpotPhase, lvl, randWord)` (line 313). Trait buckets populated during ticket processing before VRF request.

#### RNG-11b: _applyHeroOverride

**Read site:** DegenerusGameJackpotModule.sol `_applyHeroOverride()` lines 1550-1557: `uint8 heroColor = uint8(randomWord & 7)` (quadrant-dependent bit extraction)
**Data resolved:** The hero override replaces one winning trait's color with a VRF-derived color if a hero winner exists for the day. The hero winner is the symbol with the most wager weight (via `_topHeroSymbol` at line 1545, reading `dailyHeroWagers[day][q]`).
**Input commitment point:** Hero wagers committed during degenerette bet placement via `_placeDegeneretteBetCore` (DegeneretteModule lines 463-478: `dailyHeroWagers[day][heroQuadrant]` updated). Bets are placed during the purchase phase or while `rngLockedFlag == false`.
**Word availability at commitment:** Hero wagers are placed during the purchase phase. The daily VRF word used by `_applyHeroOverride` is the same word passed to `payDailyJackpot`. This word was requested at the end of the last purchase day (after all hero wagers were committed).
**Verdict:** SAFE -- hero wagers committed during purchase phase before daily VRF word requested.
**Evidence:** `dailyHeroWagers[day][heroQuadrant]` written at DegeneretteModule line 477 during `_placeDegeneretteBetCore`. `_applyHeroOverride` reads `randomWord` (daily VRF) at line 1539, extracting bits 0-2, 3-5, 6-8, or 9-11 depending on quadrant. VRF word requested after purchase phase ends.

---

## Summary Table

| Chain | Consumer | Read Site | Word Source | Data Resolved | Word Unknown at Commitment? | Verdict |
|-------|----------|-----------|-------------|---------------|---------------------------|---------|
| RNG-01a | rngGate daily processing | AdvanceModule L1008/L1031 | rngWordByDay[day] | Coinflip, quests, redemption, lootbox finalization | Yes -- VRF requested after inputs committed | SAFE |
| RNG-01b | _backfillGapDays | AdvanceModule L1575 | keccak(vrfWord, gapDay) | Gap day coinflip payouts | Yes -- VRF word is post-gap delivery; bets from before stall | SAFE |
| RNG-02a | openLootBox | LootboxModule L533 | lootboxRngWordByIndex[index] | Target level, tickets, boons | Yes -- index advanced at VRF request; purchases before request | SAFE |
| RNG-02b | openBurnieLootBox | LootboxModule L611 | lootboxRngWordByIndex[index] | Target level, tickets | Yes -- same index isolation as RNG-02a | SAFE |
| RNG-03 | _randTraitTicket | JackpotModule L1640 | keccak(randomWord, trait, salt, i) | Winner selection from ticket pool | Yes -- ticket holders committed before VRF request; _swapAndFreeze | SAFE |
| RNG-04 | _runJackpotEthFlow | JackpotModule L1100/L1108 | rngWordByDay[day] via jp.entropy | Bucket rotation, ETH share distribution | Yes -- bucket populations committed before VRF request | SAFE |
| RNG-05 | payDailyJackpot carryover | JackpotModule L389-398 | keccak(randWord, tag, counter) | Source level offset for futurePool tickets | Yes -- futurePool frozen at VRF request via _swapAndFreeze | SAFE |
| RNG-06 | _resolveFullTicketBet | DegeneretteModule L574 | lootboxRngWordByIndex[index] | Bet outcome (result ticket) | Yes -- explicit guard at L430 rejects bets when word exists | SAFE |
| RNG-07 | _raritySymbolBatch | MintModule L563/L680 | lootboxRngWordByIndex[index-1] | Trait generation for ticket holders (LCG seed) | Yes -- ticket queue frozen before VRF word; seed provenance clean | SAFE |
| RNG-08 | _gameOverEntropy | AdvanceModule L1123-1151 | historical VRF + prevrandao | Terminal coinflip, redemption, lootbox finalization | Partial -- historical words known; prevrandao adds 1-bit-manipulable unpredictability | INFO |
| RNG-09 | handleGameOverDrain | GameOverModule L97 | rngWordByDay[day] | Terminal jackpot (decimator + bucket distribution) | Yes -- word acquired in gameover advanceGame call after all inputs committed | SAFE |
| RNG-10 | _deityDailySeed/_deityBoonForSlot | LootboxModule L1743/L1767 | rngWordByDay[day] (with fallback) | Deity boon type selection | Yes -- deity pass purchased during purchase phase before daily VRF | SAFE |
| RNG-11a | _rollWinningTraits | JackpotModule L1864 | rngWordByDay[day] via randWord | 4 winning trait IDs | Yes -- trait buckets populated before VRF request | SAFE |
| RNG-11b | _applyHeroOverride | JackpotModule L1550-1557 | rngWordByDay[day] via randomWord | Hero color override | Yes -- hero wagers committed during purchase phase before VRF | SAFE |

**Aggregate:** 13 consumer sites across 11 RNG chains. 12 SAFE, 1 INFO (RNG-08 prevrandao fallback -- gameover-only edge case). Zero VULNERABLE findings.
