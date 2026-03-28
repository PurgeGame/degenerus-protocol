# RNG/VRF Warden Audit Report

**Auditor:** Fresh-eyes RNG/VRF specialist warden
**Scope:** All VRF integration, commitment windows, RNG consumers, and cross-contract RNG flows
**Methodology:** Backward trace from every RNG consumer to VRF origin; forward trace from every VRF request to all downstream effects; commitment window analysis for every player-controllable state change between request and fulfillment

## Executive Summary

The Degenerus protocol uses Chainlink VRF V2.5 as its sole randomness source, with two distinct VRF request paths: daily RNG (via `advanceGame` in AdvanceModule) and mid-day lootbox RNG (via `requestLootboxRng`). A single VRF callback entry point (`rawFulfillRandomWords`) routes to the AdvanceModule via delegatecall.

After systematic analysis of every VRF commitment window, request-to-fulfillment path, and RNG consumer chain, **zero Medium+ vulnerabilities were found**. The protocol implements a rigorous commitment-before-randomness architecture: all player inputs are committed before VRF requests, the `rngLockedFlag` prevents state mutation during the VRF window, prize pool freezing isolates accounting, and ticket queue double-buffering prevents post-request ticket manipulation. The nudge mechanism (`reverseFlip`) is correctly gated by `rngLockedFlag`, preventing post-request influence. Three INFO-level observations are documented below.

## Methodology

1. **Identified all VRF request sites:** `_requestRng` (daily), `_tryRequestRng` (gameover fallback), `requestLootboxRng` (mid-day lootbox)
2. **Traced backward** from every RNG consumer to verify the random word was unknown at input commitment time
3. **Mapped all player-controllable state** that could change between VRF request and fulfillment
4. **Verified fulfillment routing:** `rawFulfillRandomWords` request ID validation, coordinator check, word storage
5. **Analyzed all downstream consumers:** coinflip, jackpot selection, lootbox resolution, gambling burn redemption, future take variance, nudges
6. **Checked stall resilience:** 12h timeout retry, 3-day gameover fallback, gap day backfill, orphaned lootbox recovery
7. **Verified cross-contract RNG flows:** sDGNRS gambling burn resolution, BurnieCoinflip payout processing, lootbox opening from StakedDegenerusStonk

## Findings

### INFO-01: Nudge Mechanism Allows Marginal RNG Influence (Accepted Design)

**Severity:** INFO (by design, documented in KNOWN-ISSUES as "Design Decision")
**Affected contracts:** DegenerusGameAdvanceModule.sol
**Description:** The `reverseFlip()` function allows players to spend BURNIE to increment the VRF word by 1 per nudge before VRF request. The nudge count (`totalFlipReversals`) accumulates while `rngLockedFlag == false` and is applied to the raw VRF word in `_applyDailyRng()` (line 1553: `finalWord += nudges`).

**Assessment:** This is explicitly designed and documented. The nudge is applied AFTER VRF delivery but BEFORE any consumer reads the word. Critically, nudges are purchased BEFORE the VRF request (`reverseFlip` reverts if `rngLockedFlag` is true, line 1451), so the player cannot see the VRF word and then decide to nudge. The nudge cost compounds at 50% per queued nudge (100 BURNIE base), making large nudge counts economically impractical. A player nudging N times shifts the word by N, changing bit 0 (coinflip) by flipping it N times -- but since the base word is unknown, this is equivalent to a random coinflip. No exploit path exists.

**Disposition:** SAFE -- accepted design with correct economic gating.

### INFO-02: Gameover Fallback Uses prevrandao with 1-Bit Validator Bias

**Severity:** INFO (documented in KNOWN-ISSUES)
**Affected contracts:** DegenerusGameAdvanceModule.sol, `_getHistoricalRngFallback` (line 982)
**Description:** When VRF is dead for 3+ days during gameover, the fallback entropy combines up to 5 historical VRF words with `block.prevrandao`. A block proposer can bias prevrandao by 1 bit (propose or skip).

**Assessment:** This is a triple-edge-case: gameover + VRF dead 3+ days + validator manipulation. The 5 historical VRF words provide 256 bits of committed entropy each. The prevrandao contribution adds unpredictability but is the only biasable component. The 1-bit bias affects the coinflip (bit 0) outcome at most, and only in this extreme scenario. At level 0 (no VRF history), it falls through to prevrandao-only, but at level 0 there is nothing meaningful to manipulate.

**Disposition:** SAFE -- documented edge case, impact negligible.

### INFO-03: EntropyLib XOR-Shift is Not Cryptographically Uniform

**Severity:** INFO
**Affected contracts:** EntropyLib.sol, DegenerusGameLootboxModule.sol
**Description:** `EntropyLib.entropyStep()` uses a 256-bit XOR-shift PRNG (shift 7, shift-right 9, shift 8). XOR-shift PRNGs have known weaknesses: they cannot produce the zero state, they have a fixed cycle length, and consecutive outputs are correlated. The library is used for lootbox outcome rolls (target level, ticket counts, BURNIE amounts, boons).

**Assessment:** The PRNG is seeded from VRF via `keccak256(abi.encode(rngWord, player, day, amount))` -- a per-player, per-day, per-amount unique seed. The seed is unpredictable (VRF-derived) and the number of `entropyStep` calls per resolution is small (typically 5-10 steps). For this use case, the XOR-shift bias is astronomically small and not exploitable: a player would need to predict the specific VRF word AND control their address/amount/day to hit a specific seed that produces a favorable XOR-shift trajectory. The modular arithmetic over small ranges (e.g., `% 100`, `% 5`, `% 46`) further masks any statistical non-uniformity.

**Disposition:** SAFE -- VRF seed makes exploitation infeasible despite theoretical PRNG weakness.

## SAFE Proofs

### SAFE-01: Daily RNG Commitment Window (advanceGame -> _requestRng)

**Attack surface:** Player-controllable state changes between VRF request and fulfillment that could influence RNG-dependent outcomes.

**Trace:**

1. **VRF Request:** `advanceGame()` calls `rngGate()` (AdvanceModule.sol:789), which calls `_requestRng()` (line 1281) when no word exists for the day.

2. **State frozen at request time:**
   - `_finalizeRngRequest` (line 1325) sets `rngLockedFlag = true` (line 1345)
   - `_swapAndFreeze(purchaseLevel)` called before rngGate (line 239): freezes prize pools (`prizePoolFrozen = true`, `prizePoolPendingPacked = 0`) and swaps ticket queue buffer (`ticketWriteSlot ^= 1`)
   - Level may be incremented at request time when `isTicketJackpotDay == true` (line 1356: `level = lvl`)

3. **What is locked during VRF window (rngLockedFlag == true):**
   - `reverseFlip()` reverts with `RngLocked()` (AdvanceModule.sol:1451)
   - `sDGNRS.burn()` and `burnWrapped()` revert with `BurnsBlockedDuringRng` (StakedDegenerusStonk.sol:468,487)
   - `DGNRS.unwrapTo()` reverts with `Unauthorized()` (DegenerusStonk.sol:190)
   - Far-future ticket writes revert with `RngLocked()` (DegenerusGameStorage.sol:554,582,631)
   - `requestLootboxRng()` reverts with `RngLocked()` (AdvanceModule.sol:696)

4. **What CAN change during VRF window:**
   - New ticket purchases route to the WRITE slot (post-swap), not the READ slot being processed
   - New lootbox purchases target the incremented `lootboxRngIndex` (next RNG, not current)
   - Prize pool additions go to `prizePoolPendingPacked` (frozen; merged on unfreeze after processing)
   - Coinflip deposits target future days (not the day being resolved)

5. **Fulfillment:** `rawFulfillRandomWords` (AdvanceModule.sol:1467) validates `msg.sender == vrfCoordinator` and `requestId == vrfRequestId`, stores `rngWordCurrent = word`.

6. **Consumption:** Next `advanceGame()` call enters `rngGate()`, finds `currentWord != 0 && rngRequestTime != 0`, processes: `_applyDailyRng` (nudges applied, word stored in `rngWordByDay`), then `coinflip.processCoinflipPayouts`, gambling burn resolution, lootbox RNG finalization.

**Conclusion:** All player inputs committed before VRF request. Prize pools frozen. Ticket buffers swapped. Nudges locked. Burns locked. No mutable state read during fulfillment is settable after request. **SAFE.**

### SAFE-02: Mid-Day Lootbox RNG Commitment Window (requestLootboxRng)

**Attack surface:** Player manipulates lootbox inputs after seeing mid-day VRF word.

**Trace:**

1. **VRF Request:** `requestLootboxRng()` (AdvanceModule.sol:695) fires when lootbox activity threshold met.

2. **State frozen at request time:**
   - `lootboxRngIndex++` (line 759) -- new purchases target the NEXT index
   - `lootboxRngPendingEth = 0`, `lootboxRngPendingBurnie = 0` (lines 760-761) -- accumulators reset
   - `vrfRequestId = id` (line 762), `rngWordCurrent = 0` (line 763)
   - Ticket buffer swap: if write queue has entries AND tickets already processed, `_swapTicketSlot` is called and `midDayTicketRngPending = true` (lines 738-743)
   - Precondition: `rngLockedFlag` must be false (line 696), daily RNG already consumed (`rngWordByDay[currentDay] != 0`, line 707)

3. **Fulfillment:** `rawFulfillRandomWords` detects `rngLockedFlag == false` (line 1477), directly stores `lootboxRngWordByIndex[index] = word` (line 1483), clears `vrfRequestId` and `rngRequestTime`.

4. **Lootbox resolution:** Players call `openEthLootBox(player, index)` (LootboxModule.sol:537). The `index` was recorded at purchase time (MintModule.sol:696: `uint48 index = lootboxRngIndex`). Entropy derived from `keccak256(abi.encode(rngWord, player, day, amount))` -- all inputs committed at purchase time before the VRF request for that index.

5. **Can a player purchase a lootbox after seeing the mid-day VRF word?** No for the resolved index. After `requestLootboxRng()` increments `lootboxRngIndex`, new purchases target `lootboxRngIndex` (the new value), which has no word yet. The resolved word goes to `lootboxRngIndex - 1` (the old value). Purchases committed to the old index happened BEFORE the request.

**Conclusion:** Lootbox inputs committed at purchase time (before VRF request for that index). Index increment at request time isolates future purchases. **SAFE.**

### SAFE-03: Coinflip Resolution Path

**Attack surface:** Player manipulates coinflip outcome by controlling state between VRF request and coinflip resolution.

**Trace:**

1. **Coinflip deposits:** `_addDailyFlip()` in BurnieCoinflip.sol records stakes to `coinflipBalance[day][player]`. Deposits target future days (day + 1 or later). The day being resolved is always in the past relative to deposits.

2. **Resolution:** `processCoinflipPayouts(bonusFlip, rngWord, epoch)` (BurnieCoinflip.sol:797) called from `rngGate()` in AdvanceModule.sol (line 820) with the daily VRF word.

3. **Win/loss determination:** `win = (rngWord & 1) == 1` (line 829). Bit 0 of the VRF word. Player cannot influence this -- the word is the nudge-adjusted VRF output, and nudges were committed before VRF request.

4. **Reward percent:** `seedWord = keccak256(rngWord, epoch)` (line 803), then `roll = seedWord % 20` (line 808). Mixing with epoch provides per-day uniqueness. Both rngWord and epoch are committed before fulfillment.

5. **Bounty system:** `bountyOwedTo` is set by calling `armBounty()` before the resolution day. It records the address of who armed the bounty. Resolution reads `bountyOwedTo` which was committed before the VRF request for the resolution day.

**Conclusion:** All coinflip inputs (stakes, bounty) committed on prior days. VRF word committed via Chainlink. Nudges committed before VRF request. **SAFE.**

### SAFE-04: Gambling Burn Redemption Resolution

**Attack surface:** Player manipulates gambling burn outcome by controlling state between VRF request and redemption roll.

**Trace:**

1. **Gambling burn submission:** `sDGNRS.burn(amount)` (StakedDegenerusStonk.sol:463) calls `_submitGamblingClaim()` during active game. This reverts if `game.rngLocked()` is true (line 468). The claim records `ethValueOwed`, `burnieOwed` in `pendingRedemptions[player]`.

2. **Resolution:** `resolveRedemptionPeriod(roll, flipDay)` called from `rngGate()` (AdvanceModule.sol:822-843). The roll is `((currentWord >> 8) % 151) + 25` -- range [25, 175]. The `currentWord` is the nudge-adjusted VRF output.

3. **Can a player submit a gambling burn after the VRF request?** No. `burn()` checks `game.rngLocked()` and reverts if true. The gambling claim must be submitted before the next VRF request, and the resolution uses the RNG from that next request.

4. **Claim resolution:** `claimRedemption()` (StakedDegenerusStonk.sol:593) reads the stored roll from `redemptionPeriods[claim.periodIndex]`. The period index was recorded at submission time, the roll was recorded at resolution time (from VRF), and the coinflip outcome for BURNIE portion comes from BurnieCoinflip (also VRF-derived).

**Conclusion:** Gambling burns committed before VRF request (rngLocked gate). Roll derived from VRF word. Period binding prevents replay. **SAFE.**

### SAFE-05: VRF Request ID Validation and Fulfillment Routing

**Attack surface:** Replay attacks, stale fulfillments, wrong coordinator callbacks.

**Trace:**

1. **Request ID tracking:** `_finalizeRngRequest` stores `vrfRequestId = requestId` (AdvanceModule.sol:1342).

2. **Fulfillment validation:** `rawFulfillRandomWords` (line 1467-1488):
   - `msg.sender != address(vrfCoordinator)` -> revert (line 1471)
   - `requestId != vrfRequestId || rngWordCurrent != 0` -> silent return (line 1472)
   - The silent return on `rngWordCurrent != 0` prevents double-fulfillment.
   - The silent return on wrong `requestId` prevents stale fulfillments.

3. **Coordinator swap:** `updateVrfCoordinatorAndSub()` (AdvanceModule.sol:1402) resets all VRF state: `rngLockedFlag = false`, `vrfRequestId = 0`, `rngRequestTime = 0`, `rngWordCurrent = 0`, `midDayTicketRngPending = false`. After swap, the old coordinator's callback would fail the `msg.sender` check (now points to new coordinator).

4. **Retry path:** After 12h timeout, `_requestRng` is called again. `_finalizeRngRequest` detects retry (`isRetry = vrfRequestId != 0 && rngRequestTime != 0 && rngWordCurrent == 0`, line 1330-1332). On retry, `lootboxRngIndex` is NOT incremented again (line 1333-1338), preserving lootbox bindings. New `vrfRequestId` replaces old one, so old callback becomes a no-op.

**Conclusion:** Strict coordinator validation. Request ID matching prevents replay and stale fulfillment. Double-fulfillment prevented by `rngWordCurrent != 0` check. Coordinator swap cleanly resets state. **SAFE.**

### SAFE-06: Lootbox RNG Consumer Chain (VRF -> Storage -> Lootbox Open)

**Attack surface:** Same RNG word consumed twice, stale word used, or predictable word substituted.

**Trace:**

1. **Word storage:** Daily RNG: `_finalizeLootboxRng(currentWord)` (AdvanceModule.sol:864-868) stores `lootboxRngWordByIndex[index] = rngWord` only if `lootboxRngWordByIndex[index] == 0` (line 866 guard). Mid-day RNG: `rawFulfillRandomWords` directly stores at the index (line 1483).

2. **Word consumption:** `openEthLootBox(player, index)` reads `lootboxRngWordByIndex[index]` (LootboxModule.sol:545). If zero, reverts with `RngNotReady()`. The word is mixed with `player`, `day`, `amount` via `keccak256` to produce per-player entropy (line 566).

3. **Can the same word be used for two different lootbox openings?** Yes, but this is by design. Multiple players purchase lootboxes at the same `lootboxRngIndex` and all use the same base RNG word. Per-player uniqueness comes from the `keccak256(rngWord, player, day, amount)` mixing. Two players with the same day and amount would still have different `player` addresses, producing unique entropy.

4. **Stale word:** Impossible. The `lootboxRngIndex` increments at each VRF request (daily or mid-day). Each purchase records the current index. The index-to-word mapping is immutable once set (guard on line 866). A player opening at index N gets word N, which was derived from the VRF request that advanced past index N.

5. **Orphaned lootbox backfill:** `_backfillOrphanedLootboxIndices(vrfWord)` (AdvanceModule.sol:1525) fills any index that has word == 0, scanning backwards from `lootboxRngIndex - 1`. Uses `keccak256(vrfWord, i)` for per-index uniqueness from the post-gap VRF word.

**Conclusion:** 1:1 index-to-word mapping. Per-player entropy via keccak mixing. No double-consumption. No stale words. Orphan backfill uses VRF-derived entropy. **SAFE.**

### SAFE-07: rngLockedFlag Mutual Exclusion

**Attack surface:** Concurrent VRF requests or state corruption from overlapping RNG operations.

**Trace:**

1. **Lock acquisition:** `_finalizeRngRequest` sets `rngLockedFlag = true` (AdvanceModule.sol:1345). Called from `_requestRng` and `_tryRequestRng`.

2. **Lock release:** `_unlockRng(day)` sets `rngLockedFlag = false` (AdvanceModule.sol:1438). Called after daily RNG is fully consumed and all downstream processing complete (coinflip, gambling burn, lootbox finalization, jackpots, phase transition).

3. **Mid-day lootbox path:** `requestLootboxRng()` checks `rngLockedFlag` (line 696). When `rngLockedFlag == false`, it does NOT set `rngLockedFlag` -- the fulfillment path (line 1477-1487) detects `!rngLockedFlag` and directly finalizes the lootbox word without storing in `rngWordCurrent`.

4. **Exclusion guarantee:** Only one daily VRF request can be in-flight at a time (rngLockedFlag prevents `requestLootboxRng` and `advanceGame` won't re-request while locked). The mid-day lootbox path can only fire when daily RNG is unlocked AND consumed (checked via `rngWordByDay[currentDay] != 0` on line 707 and `rngRequestTime == 0` on line 709).

5. **rngLockedFlag gates:** Burns (sDGNRS.burn, burnWrapped), unwrapTo (DGNRS), far-future ticket writes, requestLootboxRng, reverseFlip -- all correctly check the flag.

**Conclusion:** Strict mutual exclusion between daily and mid-day VRF paths. No concurrent request possible. All side-channel operations correctly gated. **SAFE.**

### SAFE-08: Ticket Queue Double-Buffer Integrity

**Attack surface:** Tickets purchased after VRF request resolved using the pre-request RNG word.

**Trace:**

1. **Buffer swap:** `_swapAndFreeze(purchaseLevel)` (GameStorage.sol:728) called before RNG request in `advanceGame()` (AdvanceModule.sol:239). Swaps `ticketWriteSlot ^= 1` (line 721). New purchases go to write slot, processing reads from read slot.

2. **Read/write key mapping:** `_tqWriteKey(lvl)` returns `lvl | TICKET_SLOT_BIT` when `ticketWriteSlot != 0`, else `lvl` (GameStorage.sol:696). `_tqReadKey(lvl)` returns the opposite. After swap, new purchases target the new write key while processing targets the old write key (now read key).

3. **Mid-day ticket swap:** `requestLootboxRng()` also swaps the ticket buffer when appropriate (AdvanceModule.sol:738-743), setting `midDayTicketRngPending = true` to signal that processing should wait for the mid-day VRF word.

4. **Processing guard:** During mid-day path (AdvanceModule.sol:164-168), if `midDayTicketRngPending` is true, checks `lootboxRngWordByIndex[lootboxRngIndex - 1]` -- reverts with `NotTimeYet()` if word is zero, ensuring processing only occurs after VRF delivery.

**Conclusion:** Double-buffer ensures temporal isolation. Tickets purchased after VRF request are in the write buffer, not processed until the next cycle. **SAFE.**

### SAFE-09: Gap Day Backfill Entropy Independence

**Attack surface:** Predictable entropy for gap days allows manipulation of backfilled coinflip outcomes.

**Trace:**

1. **Gap detection:** `rngGate()` detects `day > dailyIdx + 1` (AdvanceModule.sol:805).

2. **Backfill entropy:** `_backfillGapDays(currentWord, idx+1, day, bonusFlip)` (line 807). For each gap day: `derivedWord = keccak256(vrfWord, gapDay)` (lines 1508-1509). The `vrfWord` is the first post-gap VRF word -- unknown to any player before delivery.

3. **Per-day uniqueness:** The `gapDay` index differentiates each day's entropy. Combined with the VRF word preimage, this provides 256-bit unique entropy per gap day.

4. **Gap day nudges:** Explicitly documented: "Gap days get zero nudges (totalFlipReversals not consumed)" (line 1493). The nudge count carries forward to the current day's application, not applied to backfilled days.

**Conclusion:** Gap day entropy derived from VRF word (unpredictable) + day index (unique). No player input can influence backfilled outcomes. **SAFE.**

## Cross-Domain Findings

### CROSS-01: Lootbox EV Multiplier Snapshot Timing (INFO)

**Domain:** Money/Composition
**Affected:** DegenerusGameMintModule.sol:706-707, DegenerusGameLootboxModule.sol:576-578

**Observation:** At lootbox purchase time, `playerActivityScore` is snapshotted and stored in `lootboxEvScorePacked` (MintModule.sol:706-707). At open time, if the score was snapshotted, it's used; otherwise, the live score is queried (LootboxModule.sol:576-578). This means a player who purchases before their activity score improves gets the lower multiplier, even if they open much later. This is likely intentional (snapshot at commitment time), but the fallback to live score for `evScorePacked == 0` entries (legacy/pre-feature purchases) creates a minor inconsistency. No exploit path -- the multiplier only scales the existing lootbox amount within capped bounds (80%-135%, capped at 10 ETH per account per level).

### CROSS-02: Charity Governance Resolution at Level Increment (INFO)

**Domain:** Admin/Composition
**Affected:** DegenerusGameAdvanceModule.sol:1364

**Observation:** `charityResolve.pickCharity(lvl - 1)` is called during `_finalizeRngRequest` when `isTicketJackpotDay && !isRetry`. This external call to the GNRUS contract occurs during level increment processing. If GNRUS.pickCharity reverts, the entire VRF request reverts, stalling the game. The GNRUS contract is a known, immutable, compile-time constant address, so this is acceptable trust.

## Attack Surface Inventory

| # | Attack Surface | Contract(s) | VRF Path | Disposition | Reference |
|---|---------------|-------------|----------|-------------|-----------|
| 1 | Daily RNG commitment window | AdvanceModule | _requestRng | **SAFE** | SAFE-01 |
| 2 | Mid-day lootbox RNG commitment window | AdvanceModule | requestLootboxRng | **SAFE** | SAFE-02 |
| 3 | Coinflip win/loss determination | BurnieCoinflip, AdvanceModule | processCoinflipPayouts | **SAFE** | SAFE-03 |
| 4 | Gambling burn redemption roll | StakedDegenerusStonk, AdvanceModule | resolveRedemptionPeriod | **SAFE** | SAFE-04 |
| 5 | VRF request ID replay/stale fulfillment | AdvanceModule, DegenerusGame | rawFulfillRandomWords | **SAFE** | SAFE-05 |
| 6 | Lootbox RNG word double-use/staleness | AdvanceModule, LootboxModule | lootboxRngWordByIndex | **SAFE** | SAFE-06 |
| 7 | rngLockedFlag mutual exclusion | AdvanceModule, multiple consumers | all VRF paths | **SAFE** | SAFE-07 |
| 8 | Ticket queue double-buffer bypass | GameStorage, AdvanceModule | _swapAndFreeze | **SAFE** | SAFE-08 |
| 9 | Gap day backfill entropy predictability | AdvanceModule | _backfillGapDays | **SAFE** | SAFE-09 |
| 10 | Nudge (reverseFlip) post-request manipulation | AdvanceModule | reverseFlip | **SAFE** | INFO-01 / SAFE-01 |
| 11 | Gameover prevrandao fallback bias | AdvanceModule | _getHistoricalRngFallback | **SAFE** (INFO) | INFO-02 |
| 12 | EntropyLib XOR-shift statistical bias | EntropyLib, LootboxModule | entropyStep | **SAFE** (INFO) | INFO-03 |
| 13 | VRF coordinator swap state reset | AdvanceModule | updateVrfCoordinatorAndSub | **SAFE** | SAFE-05 |
| 14 | VRF 12h timeout retry | AdvanceModule | rngGate | **SAFE** | SAFE-05 |
| 15 | Orphaned lootbox backfill | AdvanceModule | _backfillOrphanedLootboxIndices | **SAFE** | SAFE-06 |
| 16 | sDGNRS burn during VRF window | StakedDegenerusStonk | burn/burnWrapped | **SAFE** | SAFE-04 |
| 17 | DGNRS unwrapTo during VRF window | DegenerusStonk | unwrapTo | **SAFE** | SAFE-07 |
| 18 | Daily jackpot winner selection with RNG | JackpotModule (delegatecall) | payDailyJackpot | **SAFE** | SAFE-01 |
| 19 | Future take variance with RNG | AdvanceModule | _applyTimeBasedFutureTake | **SAFE** | SAFE-01 |
| 20 | Prize pool consolidation with RNG | JackpotModule (delegatecall) | consolidatePrizePools | **SAFE** | SAFE-01 |
| 21 | Mid-day ticket processing RNG gate | AdvanceModule | midDayTicketRngPending | **SAFE** | SAFE-08 |
| 22 | Lootbox target level roll | LootboxModule | _rollTargetLevel (EntropyLib) | **SAFE** | SAFE-06, INFO-03 |
| 23 | Redemption lootbox from sDGNRS claim | StakedDegenerusStonk, LootboxModule | claimRedemption -> resolveRedemptionLootbox | **SAFE** | SAFE-04 |
| 24 | Deity boon RNG consumption | LootboxModule | issueDeityBoon | **SAFE** | Uses rngWordByDay (already committed) |
