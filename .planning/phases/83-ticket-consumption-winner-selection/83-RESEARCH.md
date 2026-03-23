# Phase 83: Ticket Consumption & Winner Selection - Research

**Researched:** 2026-03-23
**Domain:** Solidity smart contract audit -- ticket consumption from queues for winner selection across all jackpot types
**Confidence:** HIGH

## Summary

Phase 83 traces the CONSUMPTION side of the ticket lifecycle -- how `ticketQueue` and `traitBurnTicket` are READ to select winners across all jackpot types. This is the complement to Phase 81 (creation) and Phase 82 (processing). The audit scope covers every function that reads from these storage structures for the purpose of determining jackpot winners, with file:line citations for each.

The protocol has five distinct jackpot types that consume tickets for winner selection: (1) Daily ETH Jackpot reads from `traitBurnTicket[lvl]` via `_randTraitTicketWithIndices` at JM:1448 and JM:1641, selecting winners from trait-matched ticket pools; (2) Daily Coin Jackpot near-future reads from `traitBurnTicket[lvl]` via `_randTraitTicketWithIndices` at JM:2459, plus far-future reads from `ticketQueue[_tqFarFutureKey(candidate)]` at JM:2543; (3) Daily Ticket Jackpot reads from `traitBurnTicket[lvl]` via `_randTraitTicket` at JM:1191; (4) Early-Bird Lootbox Jackpot reads from `traitBurnTicket[lvl]` via `_randTraitTicket` at JM:833; (5) DGNRS Final Day Reward reads from `traitBurnTicket[lvl]` via `_randTraitTicket` at JM:785. Additionally, the BAF Jackpot (in DegenerusJackpots.sol, a separate contract) reads indirectly via view functions `sampleFarFutureTickets` (DG:2681, reads `ticketQueue`) and `sampleTraitTicketsAtLevel` (DG:2647, reads `traitBurnTicket`).

Winner index computation follows a consistent pattern across jackpot types: `idx = entropy_slice % effectiveLen`, where `effectiveLen = holders.length + virtualCount` (deity virtual entries). The key finding from Phase 81 (DSC-01) remains relevant -- `_awardFarFutureCoinJackpot` reads ONLY from `_tqFarFutureKey`, not the combined pool described in the stale v3.9 proof. A new finding for Phase 83: the BAF jackpot's reliance on `sampleFarFutureTickets` means it is affected by DSC-02 (the view function reads from `_tqWriteKey` instead of `_tqFarFutureKey`), which means BAF scatter far-future draws may select from an incorrect/empty pool. This is an INFO-severity issue since the BAF jackpot is in a separate contract and uses the view function as a sampling heuristic, not a definitive winner selection.

**Primary recommendation:** Systematically enumerate every function that reads `ticketQueue` or `traitBurnTicket` for winner selection, document the winner index computation formula for each jackpot type, trace the RNG word derivation chain for each, and cross-reference against prior audit documentation (v3.8 commitment window inventory Section 4, v3.9 RNG proof).

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TCON-01 | Every function reading from ticketQueue for winner selection identified with file:line | 3 distinct read sites identified: JM:2543 (_awardFarFutureCoinJackpot reads _tqFarFutureKey), JM:1891 (processTicketBatch reads _tqReadKey -- processing not selection, included for completeness), DG:2681 (sampleFarFutureTickets reads _tqWriteKey -- view function used by BAF jackpot). Plus AdvanceModule length checks at AM:166, AM:207, AM:719. |
| TCON-02 | Every function reading traitBurnTicket for winner selection identified with file:line | 7 distinct read sites in JackpotModule: JM:785 (DGNRS reward), JM:833 (earlybird lootbox), JM:1040 (_hasTraitTickets), JM:1191 (_distributeTicketsToBucket via _randTraitTicket), JM:1231 (_computeBucketCounts), JM:1448 (_processDailyEthChunk via _randTraitTicketWithIndices), JM:1641 (coin/ETH shared path via _randTraitTicketWithIndices), JM:2459 (_awardDailyCoinToTraitWinners via _randTraitTicketWithIndices), JM:2680 (_hasActualTraitTickets). Plus DG:2618, DG:2647, DG:2730 (view functions). |
| TCON-03 | Winner index computation documented for each jackpot type (ETH, coin, ticket, FF coin) | All four winner index formulas traced: ETH uses `_randTraitTicketWithIndices` -> `slice % effectiveLen`; Coin near-future uses same; Ticket uses `_randTraitTicket` -> `slice % effectiveLen`; FF Coin uses `(entropy >> 32) % len` directly on ticketQueue. Deity virtual entries add `virtualCount` to `effectiveLen` for trait-based selection. |
| TCON-04 | Every discrepancy and new finding tagged | DSC-01 (v3.9 proof stale -- combined pool -> FF-only) re-confirmed from Phase 81. NEW FINDING: BAF jackpot (DegenerusJackpots.sol) calls `sampleFarFutureTickets` which reads from `_tqWriteKey` -- making BAF far-future scatter draws potentially incorrect post-v3.9. |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

From global CLAUDE.md:
- **Self-check before delivering results** -- after completing any substantial task, internally review for gaps, stale references, cascading changes

From project memory:
- **Only read contracts from `contracts/` directory** -- stale copies exist elsewhere
- **Present fix and wait for explicit approval before editing code** -- audit-only phase, no code changes
- **NEVER commit contracts/ or test/ changes without explicit user approval** -- N/A for audit-only phase
- **Every RNG audit must trace BACKWARD from each consumer** -- applicable to verifying RNG word derivation for each winner selection path
- **Every RNG audit must check what player-controllable state can change between VRF request and fulfillment** -- applicable to verifying traitBurnTicket and ticketQueue are not externally mutable during commitment window

From STATE.md:
- **v3.8 commitment window inventory has CONFIRMED ERRORS** -- all prior audit prose treated as unverified
- **DSC-01/DSC-02 are cross-cutting** -- apply to all phases in v4.0

## Architecture Patterns

### Ticket Consumption Architecture

There are two distinct storage structures consumed for winner selection:

**1. `traitBurnTicket[level][traitId]` (GS slot 11)** -- mapping(uint24 => address[][256])
- Populated ONLY by `processTicketBatch` via `_raritySymbolBatch` assembly writes (JM:2194-2221)
- Read by all trait-based winner selection: ETH jackpot, coin jackpot (near-future), ticket jackpot, earlybird lootbox jackpot, DGNRS reward
- Each entry is an `address[]` of ticket holders who received that trait at that level
- Deity virtual entries (floor(2% of bucket), min 2) are added logically at selection time, not stored

**2. `ticketQueue[key]` (GS slot 15)** -- mapping(uint24 => address[])
- Read by `_awardFarFutureCoinJackpot` at JM:2543 using `_tqFarFutureKey(candidate)`
- Read by `processTicketBatch` at JM:1891 using `_tqReadKey(lvl)` (processing, not winner selection)
- Read by `sampleFarFutureTickets` at DG:2681 using `_tqWriteKey(candidate)` (view function, BAF scatter)
- Contains raw ticket holder addresses BEFORE trait assignment

### Winner Selection Call Graph

```
advanceGame (AdvanceModule)
  |
  +-> payDailyJackpot (JM:323)
  |     +-> Phase 0: _processDailyEthChunk (JM:1387)
  |     |     +-> _randTraitTicketWithIndices(traitBurnTicket[lvl], ...) at JM:1448
  |     +-> Phase 1: carryover ETH distribution
  |     |     +-> _processDailyEthChunk(carryoverSourceLevel, ...) at JM:590
  |     |           +-> _randTraitTicketWithIndices(traitBurnTicket[lvl], ...) at JM:1448
  |     +-> Early-burn path: _executeJackpot -> _runJackpotEthFlow -> _distributeJackpotEth
  |     |     +-> _processJackpotBucket (JM:1607) -> _randTraitTicketWithIndices at JM:1641
  |     +-> Early-bird lootbox: _runEarlyBirdLootboxJackpot (JM:801)
  |     |     +-> _randTraitTicket(traitBurnTicket[lvl], ...) at JM:833
  |     +-> Lootbox/ticket distribution: _distributeLootboxAndTickets (JM:1079)
  |           +-> _distributeTicketJackpot -> _distributeTicketsToBucket
  |                 +-> _randTraitTicket(traitBurnTicket[lvl], ...) at JM:1191
  |
  +-> payDailyJackpotCoinAndTickets (JM:681)
  |     +-> _awardFarFutureCoinJackpot(lvl, farBudget, randWord) at JM:707
  |     |     +-> ticketQueue[_tqFarFutureKey(candidate)] at JM:2543
  |     +-> _awardDailyCoinToTraitWinners(targetLevel, ...) at JM:720
  |     |     +-> _randTraitTicketWithIndices(traitBurnTicket[lvl], ...) at JM:2459
  |     +-> _distributeTicketJackpot (daily tickets) at JM:733
  |     |     +-> _randTraitTicket(traitBurnTicket[lvl], ...) at JM:1191
  |     +-> _distributeTicketJackpot (carryover tickets) at JM:745
  |           +-> _randTraitTicket(traitBurnTicket[lvl], ...) at JM:1191
  |
  +-> payDailyCoinJackpot (JM:2360) [purchase-phase daily BURNIE]
  |     +-> _awardFarFutureCoinJackpot(lvl, farBudget, randWord) at JM:2369
  |     |     +-> ticketQueue[_tqFarFutureKey(candidate)] at JM:2543
  |     +-> _awardDailyCoinToTraitWinners(targetLevel, ...) at JM:2395
  |           +-> _randTraitTicketWithIndices(traitBurnTicket[lvl], ...) at JM:2459
  |
  +-> awardFinalDayDgnrsReward (JM:773)
  |     +-> _randTraitTicket(traitBurnTicket[lvl], ...) at JM:785
  |
  +-> _runRewardJackpots -> _runBafJackpot (EndgameModule:345)
        +-> degenerusGame.sampleFarFutureTickets(entropy) at DegenerusJackpots:298,340
        |     +-> ticketQueue[_tqWriteKey(candidate)] at DG:2681 [VIEW FUNCTION]
        +-> degenerusGame.sampleTraitTicketsAtLevel(targetLvl, entropy) at DegenerusJackpots:418
              +-> traitBurnTicket[targetLvl][traitSel] at DG:2647 [VIEW FUNCTION]
```

### Two Core Winner Selection Helpers

**`_randTraitTicket` (JM:2237-2280)** -- returns `address[] memory winners`
- Selects `numWinners` random addresses from `traitBurnTicket_[trait]`
- Adds deity virtual entries: `virtualCount = max(holders.length / 50, 2)` if deity exists for trait's symbol
- Winner index: `idx = slice % effectiveLen` where `effectiveLen = holders.length + virtualCount`
- Entropy derivation: `slice = randomWord ^ (trait << 128) ^ (salt << 192)`, then `slice = (slice >> 16) | (slice << 240)` for each subsequent winner
- Duplicates intentionally allowed
- Used by: earlybird lootbox (JM:833), ticket distribution (JM:1191), DGNRS reward (JM:785)

**`_randTraitTicketWithIndices` (JM:2283-2337)** -- returns `(address[] memory, uint256[] memory)`
- Identical selection logic to `_randTraitTicket` plus returns ticket indices
- `ticketIndex = idx` for real tickets, `type(uint256).max` for deity virtual entries
- Used by: daily ETH jackpot (JM:1448, JM:1641), daily coin jackpot (JM:2459)

### Far-Future Coin Winner Selection (JM:2521-2606)

Unlike the trait-based helpers, `_awardFarFutureCoinJackpot` has its own inline selection:

```solidity
// JM:2537-2560
for (uint8 s; s < FAR_FUTURE_COIN_SAMPLES; ) {          // 10 samples
    entropy = EntropyLib.entropyStep(entropy ^ uint256(s));
    uint24 candidate = lvl + 5 + uint24(entropy % 95);    // random level in [lvl+5, lvl+99]
    address[] storage queue = ticketQueue[_tqFarFutureKey(candidate)];  // JM:2543
    uint256 len = queue.length;
    if (len != 0) {
        address winner = queue[(entropy >> 32) % len];     // JM:2547
        // ...
    }
}
```

Winner index: `(entropy >> 32) % queue.length` -- no deity virtual entries, no trait matching, directly indexes the raw ticket queue.

## Detailed Findings: Winner Index Computation by Jackpot Type

### 1. Daily ETH Jackpot

**Entry:** `payDailyJackpot(true, lvl, randWord)` at JM:323
**Phases:** Phase 0 (current level), Phase 1 (carryover to future level)
**RNG derivation:**
- Base entropy: `entropyDaily = randWord ^ (uint256(lvl) << 192)` at JM:474
- Solo bucket: `remainderIdx = JackpotBucketLib.soloBucketIndex(entropy)` (JM:1401)
- Per-bucket: `entropyState = EntropyLib.entropyStep(entropyState ^ (uint256(traitIdx) << 64) ^ share)` at JM:1436-1438
- Winner index: `_randTraitTicketWithIndices(traitBurnTicket[lvl], entropyState, traitIds[traitIdx], ...)` at JM:1448
  - Inside helper: `slice = entropyState ^ (trait << 128) ^ (salt << 192)`, then `idx = slice % effectiveLen`

**Pool source:** `traitBurnTicket[lvl]` for current level; `traitBurnTicket[carryoverSourceLevel]` for carryover
**Winning traits:** `_rollWinningTraits(lvl, randWord, true)` -- uses burn counts and hero override
**Bucket structure:** 4 trait buckets, shares by BPS (20/20/20/20 normal, 60/13/13/13 final day), solo bucket gets remainder
**Max winners:** DAILY_ETH_MAX_WINNERS = 321 total, MAX_BUCKET_WINNERS = 250 per bucket

### 2. Daily Coin Jackpot (Near-Future)

**Entry:** `payDailyJackpotCoinAndTickets(randWord)` at JM:681 OR `payDailyCoinJackpot(lvl, randWord)` at JM:2360
**RNG derivation:**
- Coin entropy: `entropy = randWord ^ (uint256(lvl) << 192) ^ uint256(COIN_JACKPOT_TAG)` at JM:711-713
- Target level: `candidate = lvl + uint24(entropy % 5)` at JM:2410 -- random level in [lvl, lvl+4]
- Per-bucket: `entropy = EntropyLib.entropyStep(entropy ^ (uint256(traitIdx) << 64) ^ coinBudget)` at JM:2450-2451
- Winner index: `_randTraitTicketWithIndices(traitBurnTicket[lvl], entropy, traitIds[traitIdx], ...)` at JM:2459
  - Inside helper: `slice = entropy ^ (trait << 128) ^ (salt << 192)`, then `idx = slice % effectiveLen`

**Pool source:** `traitBurnTicket[targetLevel]` where targetLevel is in [lvl, lvl+4]
**Winning traits:** Same packed traits from Phase 1 (stored in `lastDailyJackpotWinningTraits`)
**Max winners:** DAILY_COIN_MAX_WINNERS (not shown in constants section; computed from budget cap), MAX_BUCKET_WINNERS = 250 per bucket

### 3. Far-Future Coin Jackpot

**Entry:** Called from `payDailyJackpotCoinAndTickets` at JM:707 OR `payDailyCoinJackpot` at JM:2369
**Function:** `_awardFarFutureCoinJackpot(lvl, farBudget, rngWord)` at JM:2521
**RNG derivation:**
- Initial entropy: `entropy = rngWord ^ (uint256(lvl) << 192) ^ uint256(FAR_FUTURE_COIN_TAG)` at JM:2528-2530
- Per-sample: `entropy = EntropyLib.entropyStep(entropy ^ uint256(s))` at JM:2538
- Level selection: `candidate = lvl + 5 + uint24(entropy % 95)` at JM:2541 -- random level in [lvl+5, lvl+99]
- Winner index: `queue[(entropy >> 32) % len]` at JM:2547 -- direct indexing, no deity virtual entries

**Pool source:** `ticketQueue[_tqFarFutureKey(candidate)]` at JM:2543
**Key difference:** This is the ONLY jackpot type that reads from `ticketQueue` rather than `traitBurnTicket`. These are pre-trait-assignment tickets (traits not yet assigned because the level hasn't been reached).
**Max samples:** FAR_FUTURE_COIN_SAMPLES = 10
**Budget split:** 25% of total coin budget (FAR_FUTURE_COIN_BPS = 2500)

### 4. Daily Ticket Jackpot

**Entry:** `payDailyJackpotCoinAndTickets(randWord)` at JM:681
**Function:** `_distributeTicketJackpot(lvl, winningTraitsPacked, ticketUnits, entropy, maxWinners, saltBase)` at JM:1105
**RNG derivation:**
- Daily entropy: `entropyDaily = randWord ^ (uint256(lvl) << 192)` at JM:695
- Per-bucket: `entropy = EntropyLib.entropyStep(entropy ^ (uint256(traitIdx) << 64) ^ ticketUnits)` at JM:1156-1157
- Winner index: `_randTraitTicket(traitBurnTicket[lvl], entropy, traitIds[traitIdx], ...)` at JM:1191
  - Inside helper: `slice = entropy ^ (trait << 128) ^ (salt << 192)`, then `idx = slice % effectiveLen`

**Pool source:** `traitBurnTicket[lvl]` for daily tickets; `traitBurnTicket[carryoverSourceLevel]` for carryover tickets
**Output:** Winners receive queued tickets (via `_queueTickets` at JM:1209), not ETH or coin
**Max winners:** LOOTBOX_MAX_WINNERS = 100

### 5. Early-Bird Lootbox Jackpot

**Entry:** `_runEarlyBirdLootboxJackpot(lvl + 1, randWord)` called from `payDailyJackpot` at JM:381 on jackpot day 1 only
**RNG derivation:**
- Raw entropy: `entropy = rngWord` (parameter) at JM:816
- Per-winner: `entropy = EntropyLib.entropyStep(entropy)` at JM:830
- Trait selection: `traitId = uint8(entropy)` at JM:831
- Winner index: `_randTraitTicket(traitBurnTicket[lvl], entropy, traitId, 1, uint8(i))` at JM:833
  - Inside helper: `slice = entropy ^ (trait << 128) ^ (salt << 192)`, then `idx = slice % effectiveLen`

**Pool source:** `traitBurnTicket[lvl]` where lvl = current_level + 1
**Output:** Winners receive queued tickets (via `_queueTickets` at JM:848)
**Max winners:** 100 iterations (JM:829: `for (uint256 i; i < maxWinners; )` where `maxWinners = 100`)

### 6. DGNRS Final Day Reward

**Entry:** `awardFinalDayDgnrsReward(lvl, rngWord)` at JM:773
**RNG derivation:**
- Entropy: `entropy = rngWord ^ (uint256(lvl) << 192)` at JM:779
- Solo bucket: `soloIdx = JackpotBucketLib.soloBucketIndex(entropy)` at JM:780
- Winner index: `_randTraitTicket(traitBurnTicket[lvl], entropy, traitIds[soloIdx], 1, 254)` at JM:785
  - Inside helper: `slice = entropy ^ (trait << 128) ^ (salt << 192)`, then `idx = slice % effectiveLen`

**Pool source:** `traitBurnTicket[lvl]` at current level
**Output:** DGNRS token transfer to winner

### 7. BAF Jackpot (External Contract)

**Entry:** `runBafJackpot(poolWei, lvl, rngWord)` in DegenerusJackpots.sol:229
**Winner selection uses VIEW FUNCTIONS on DegenerusGame:**
- Far-future: `degenerusGame.sampleFarFutureTickets(entropy)` at DegenerusJackpots:298,340
  - Reads `ticketQueue[_tqWriteKey(candidate)]` at DG:2681 [KNOWN ISSUE -- should be `_tqFarFutureKey`]
- Scatter: `degenerusGame.sampleTraitTicketsAtLevel(targetLvl, entropy)` at DegenerusJackpots:418
  - Reads `traitBurnTicket[targetLvl][traitSel]` at DG:2647

**Key difference:** BAF is in a SEPARATE contract (DegenerusJackpots.sol) that cannot access storage directly. It calls view functions on DegenerusGame to sample ticket holders. This means BAF winner selection is affected by DSC-02 (`sampleFarFutureTickets` reads from wrong key space).

### 8. Early-Burn (Non-Daily) Jackpot

**Entry:** `payDailyJackpot(false, lvl, randWord)` at JM:323 (isDaily=false path, JM:609+)
**Function:** `_executeJackpot` -> `_runJackpotEthFlow` -> `_distributeJackpotEth` at JM:1512
**RNG derivation:**
- Entropy: `entropy = randWord ^ (uint256(lvl) << 192)` at JM:650
- Per-bucket in `_distributeJackpotEth`: uses `_processJackpotBucket` at JM:1607
  - `entropyState = EntropyLib.entropyStep(entropyState ^ (uint256(traitIdx) << 64) ^ traitShare)` at JM:1634-1635
  - Winner index: `_randTraitTicketWithIndices(traitBurnTicket[lvl], entropyState, traitId, ...)` at JM:1641

**Pool source:** `traitBurnTicket[lvl]` at current level
**Also distributes lootbox tickets:** `_distributeLootboxAndTickets` at JM:658 -> `_distributeTicketJackpot` -> `_randTraitTicket(traitBurnTicket[lvl], ...)` at JM:1093-1097

## Complete Enumeration: ticketQueue Reads for Winner Selection

| # | Function | File:Line | Key Used | Purpose | Jackpot Type |
|---|----------|-----------|----------|---------|-------------|
| 1 | `_awardFarFutureCoinJackpot` | JM:2543 | `_tqFarFutureKey(candidate)` | Select FF coin jackpot winners from unprocessed tickets | FF Coin |
| 2 | `sampleFarFutureTickets` | DG:2681 | `_tqWriteKey(candidate)` | View function called by BAF jackpot in DegenerusJackpots | BAF (indirect) |

**Non-winner-selection reads (included for completeness):**

| # | Function | File:Line | Key Used | Purpose |
|---|----------|-----------|----------|---------|
| 3 | `processTicketBatch` | JM:1891 | `_tqReadKey(lvl)` | Processing/trait assignment (not winner selection) |
| 4 | `advanceGame` mid-day path | AM:166 | `_tqReadKey(purchaseLevel)` | Length check -- drain gate |
| 5 | `advanceGame` new-day path | AM:207 | `_tqReadKey(purchaseLevel)` | Length check -- drain gate |
| 6 | `advanceGame` mid-day swap | AM:719 | `_tqWriteKey` (computed as `wk`) | Length check -- swap trigger |
| 7 | `_swapTicketSlot` | GS:711 | `_tqReadKey(purchaseLevel)` | Length check -- verify read buffer drained |
| 8 | `processFutureTicketBatch` | MM:304 | `_tqReadKey(lvl)` | Processing (not winner selection) |
| 9 | `processFutureTicketBatch` | MM:309 | `_tqFarFutureKey(lvl)` | FF queue length check |

## Complete Enumeration: traitBurnTicket Reads for Winner Selection

| # | Function | File:Line | Purpose | Jackpot Type |
|---|----------|-----------|---------|-------------|
| 1 | `_randTraitTicket` -> `holders = traitBurnTicket_[trait]` | JM:2244 | Core winner selection helper | All trait-based |
| 2 | `_randTraitTicketWithIndices` -> `holders = traitBurnTicket_[trait]` | JM:2294 | Core winner selection helper (with indices) | ETH, Coin |
| 3 | `awardFinalDayDgnrsReward` -> `_randTraitTicket(traitBurnTicket[lvl], ...)` | JM:785 | DGNRS solo bucket winner | DGNRS Reward |
| 4 | `_runEarlyBirdLootboxJackpot` -> `_randTraitTicket(traitBurnTicket[lvl], ...)` | JM:833 | Earlybird lootbox winners | Earlybird |
| 5 | `_hasTraitTickets` -> `traitBurnTicket[lvl][trait].length` | JM:1040 | Eligibility check (has entries?) | ETH, Coin, Ticket |
| 6 | `_distributeTicketsToBucket` -> `_randTraitTicket(traitBurnTicket[lvl], ...)` | JM:1191 | Ticket jackpot winners | Ticket |
| 7 | `_computeBucketCounts` -> `traitBurnTicket[lvl][trait].length` | JM:1231 | Bucket sizing (has entries?) | ETH, Coin, Ticket |
| 8 | `_processDailyEthChunk` -> `_randTraitTicketWithIndices(traitBurnTicket[lvl], ...)` | JM:1448 | Daily ETH jackpot winners | ETH |
| 9 | `_processJackpotBucket` -> `_randTraitTicketWithIndices(traitBurnTicket[lvl], ...)` | JM:1641 | Early-burn ETH jackpot winners | ETH (early-burn) |
| 10 | `_awardDailyCoinToTraitWinners` -> `_randTraitTicketWithIndices(traitBurnTicket[lvl], ...)` | JM:2459 | Daily coin near-future winners | Coin (near) |
| 11 | `_hasActualTraitTickets` -> `traitBurnTicket[lvl][traitIds[i]].length` | JM:2680 | Carryover source eligibility | ETH (carryover) |
| 12 | `sampleTraitTickets` -> `traitBurnTicket[lvlSel][traitSel]` | DG:2618 | View function (sampling) | BAF scatter (indirect) |
| 13 | `sampleTraitTicketsAtLevel` -> `traitBurnTicket[targetLvl][traitSel]` | DG:2647 | View function (BAF scatter) | BAF scatter (indirect) |
| 14 | `getTickets` -> `traitBurnTicket[lvl][trait]` | DG:2730 | View function (UI query) | None (view only) |

## RNG Word Derivation Summary

All jackpot RNG words originate from the VRF callback:

```
rawFulfillRandomWords (AM:1442)
  -> rngWordCurrent = randomWords[0]    (if rngLockedFlag true -- daily RNG)
  -> lootboxRngWordByIndex[index]       (if rngLockedFlag false -- mid-day RNG)

advanceGame -> rngGate (AM:225)
  -> _applyDailyRng: finalWord = rawWord + totalFlipReversals
  -> rngWordCurrent = finalWord
  -> All jackpot functions receive `randWord` = rngWordCurrent
```

**Per-jackpot entropy derivation:**

| Jackpot | Entropy Formula | Salt/Tag |
|---------|----------------|----------|
| ETH (daily) | `randWord ^ (uint256(lvl) << 192)` | None (level only) |
| ETH (carryover) | `randWord ^ (uint256(carryoverSourceLevel) << 192)` | carryoverSourceLevel |
| ETH (early-burn) | `randWord ^ (uint256(lvl) << 192)` | None |
| Coin (near-future) | `randWord ^ (uint256(lvl) << 192) ^ uint256(COIN_JACKPOT_TAG)` | keccak256("coin-jackpot") |
| Coin (FF) | `rngWord ^ (uint256(lvl) << 192) ^ uint256(FAR_FUTURE_COIN_TAG)` | keccak256("far-future-coin") |
| Ticket (daily) | `randWord ^ (uint256(lvl) << 192)` | None (uses saltBase=241) |
| Ticket (carryover) | `randWord ^ (uint256(carryoverSourceLevel) << 192)` | Uses saltBase=240 |
| Earlybird lootbox | `rngWord` (raw, no level XOR) | Per-winner: entropyStep |
| DGNRS reward | `rngWord ^ (uint256(lvl) << 192)` | None |
| BAF | `rngWord` with keccak256 stepping | Per-round salt increment |

## Cross-Reference with Prior Audit Documentation

### v3.8 Commitment Window Inventory (audit/v3.8-commitment-window-inventory.md)

The v3.8 inventory categorizes ticket consumption correctly:

| Claim | v3.8 Reference | Current Code | Status |
|-------|----------------|--------------|--------|
| traitBurnTicket only written by processTicketBatch | Line 766 | Confirmed -- assembly writes at JM:2194-2221, no external writer | **CONFIRMED** |
| ticketQueue double-buffer protected | Lines 1416-1422 | Confirmed for processTicketBatch (uses _tqReadKey); FF coin uses _tqFarFutureKey (v3.9 fix) | **CONFIRMED (updated in v3.9)** |
| BAF uses traitBurnTicket for winner selection | Line 168 | Confirmed -- via sampleTraitTicketsAtLevel view function | **CONFIRMED** |
| Far-future coin reads from ticketQueue[_tqWriteKey] | Line 3803 | STALE -- current code reads from _tqFarFutureKey at JM:2543 (v3.9 fix) | **[DISCREPANCY] -- v3.8 documents pre-fix TQ-01 vulnerability** |

### v3.9 RNG Commitment Window Proof (audit/v3.9-rng-commitment-window-proof.md)

| Claim | v3.9 Reference | Current Code | Status |
|-------|----------------|--------------|--------|
| Combined pool (readLen + ffLen) | Lines 41-63 | No combined pool -- FF-only at JM:2543 | **[DISCREPANCY] -- same as DSC-01 from Phase 81** |
| Winner from readQueue or ffQueue | Lines 2553-2555 | Winner only from ffQueue | **[DISCREPANCY] -- DSC-01** |

### v4.0 Phase 81 Findings (Carried Forward)

| Finding | Status | Phase 83 Impact |
|---------|--------|-----------------|
| DSC-01: v3.9 proof stale (combined -> FF-only) | Confirmed | Relevant to TCON-01 (ticketQueue reads) |
| DSC-02: sampleFarFutureTickets uses _tqWriteKey | Confirmed | Relevant to TCON-01 (BAF far-future draws incorrect) |
| DSC-03: NatSpec claims cap but unchecked arithmetic | Not relevant | No impact on consumption side |

## New Findings for Phase 83

### [NEW FINDING] BAF Far-Future Scatter Uses Incorrect Key Space

**Location:** DegenerusJackpots.sol:298,340 -> DG:2681
**Impact:** INFO severity

The BAF jackpot calls `sampleFarFutureTickets(entropy)` twice (Slice D and D2 in `runBafJackpot`). This view function reads from `ticketQueue[_tqWriteKey(candidate)]` at DG:2681. Since v3.9, far-future tickets route to `_tqFarFutureKey`, not `_tqWriteKey`. This means:

1. The BAF far-future draws may find no tickets (empty write buffer at far-future levels)
2. If tickets exist in the write buffer at those levels (from near-future routing), BAF would select from those instead
3. The 10% of BAF pool allocated to far-future slices (Slice D: 5% + Slice D2: 5%) may be returned as `toReturn` (refunded) when no tickets are found

**Consequence:** BAF far-future prize allocation may be systematically refunded rather than awarded. This is a loss-of-reward issue for far-future ticket holders, not a security vulnerability.

**Relationship to DSC-02:** This is the same root cause as DSC-02 from Phase 81. Phase 83 identifies the downstream impact -- BAF jackpot far-future allocation is affected.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Winner selection tracing | Custom static analysis | Grep + manual code reading with file:line | Delegatecall patterns and assembly writes confuse automated tools |
| RNG derivation chain | Trying to track all entropy transformations mentally | Write explicit derivation chains per jackpot type | Multiple XOR/step transforms per path; easy to confuse entropy sources |
| Discrepancy detection | Copying from prior audits | Independent code trace, then cross-reference | v3.8 and v3.9 have confirmed stale claims |

## Common Pitfalls

### Pitfall 1: Confusing ticketQueue vs traitBurnTicket Consumption
**What goes wrong:** Treating ticketQueue reads and traitBurnTicket reads as equivalent
**Why it happens:** Both contain "ticket holder" addresses, but at different lifecycle stages
**How to avoid:** ticketQueue = pre-trait-assignment (raw queue); traitBurnTicket = post-trait-assignment (by trait). Only `_awardFarFutureCoinJackpot` reads from ticketQueue for winner selection; all others use traitBurnTicket.
**Warning signs:** Any claim that ETH/coin/ticket jackpot reads from ticketQueue (it reads from traitBurnTicket)

### Pitfall 2: Missing the BAF Indirect Consumption Path
**What goes wrong:** Only tracing JackpotModule for winner selection, missing DegenerusJackpots.sol
**Why it happens:** BAF jackpot is in a separate contract that uses view functions, not direct storage reads
**How to avoid:** Trace all external callers of `sampleFarFutureTickets`, `sampleTraitTickets`, `sampleTraitTicketsAtLevel`
**Warning signs:** Incomplete enumeration of ticketQueue consumers if only JackpotModule is searched

### Pitfall 3: Assuming All Jackpots Use Same Winner Index Formula
**What goes wrong:** Claiming uniform `slice % effectiveLen` for all jackpot types
**Why it happens:** Most jackpots do use the trait-based helpers which have this formula
**How to avoid:** Note that FF coin jackpot uses `(entropy >> 32) % len` (no virtual deity entries, no trait matching). The formulas are similar but not identical.

### Pitfall 4: Trusting v3.9 Proof for Current Code Behavior
**What goes wrong:** Citing the v3.9 proof for how `_awardFarFutureCoinJackpot` works
**Why it happens:** v3.9 proof describes combined pool (readLen + ffLen) which was reverted in 2bf830a2
**How to avoid:** Verify every claim against current code at JM:2543 -- FF-only read
**Warning signs:** Any reference to "combined pool", "readLen", or "readQueue" in FF coin jackpot context

### Pitfall 5: Overlooking Deity Virtual Entries in effectiveLen
**What goes wrong:** Computing winner probability as `1 / holders.length`
**Why it happens:** Virtual deity entries are not stored, only added at selection time
**How to avoid:** Always use `effectiveLen = holders.length + virtualCount` where `virtualCount = max(holders.length / 50, 2)` if deity exists for the trait's symbol
**Warning signs:** Winner probability calculations that don't account for deity dilution

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge) + Hardhat |
| Config file | `foundry.toml` |
| Quick run command | `forge test --match-contract <TestName> -vvv` |
| Full suite command | `forge test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TCON-01 | All ticketQueue readers for winner selection identified | manual audit | N/A (audit doc review) | N/A |
| TCON-02 | All traitBurnTicket readers for winner selection identified | manual audit | N/A (audit doc review) | N/A |
| TCON-03 | Winner index computation documented per jackpot type | manual audit | N/A (code trace) | N/A |
| TCON-04 | All discrepancies and new findings tagged | manual audit | N/A (doc review) | N/A |

### Sampling Rate
- **Per task commit:** `forge test --match-contract JackpotWinner -vvv` (verify no regression if such tests exist)
- **Per wave merge:** `forge test` (full suite)
- **Phase gate:** All existing Foundry tests pass before /gsd:verify-work

### Wave 0 Gaps
None -- this is an audit-only phase (no code changes). Existing test infrastructure covers jackpot mechanics. The deliverable is an audit document, not code.

## Code Examples

### Winner Index Formula: Trait-Based (JM:2237-2280)
```solidity
// Source: contracts/modules/DegenerusGameJackpotModule.sol:2237-2280
function _randTraitTicket(
    address[][256] storage traitBurnTicket_,
    uint256 randomWord,
    uint8 trait,
    uint8 numWinners,
    uint8 salt
) private view returns (address[] memory winners) {
    address[] storage holders = traitBurnTicket_[trait];
    uint256 len = holders.length;

    // Deity virtual entries
    uint8 fullSymId = (trait >> 6) * 8 + (trait & 0x07);
    address deity;
    uint256 virtualCount;
    if (fullSymId < 32) {
        deity = deityBySymbol[fullSymId];
        if (deity != address(0)) {
            virtualCount = len / 50;
            if (virtualCount < 2) virtualCount = 2;
        }
    }

    uint256 effectiveLen = len + virtualCount;
    if (effectiveLen == 0 || numWinners == 0) return new address[](0);

    winners = new address[](numWinners);
    uint256 slice = randomWord ^ (uint256(trait) << 128) ^ (uint256(salt) << 192);
    for (uint256 i; i < numWinners; ) {
        uint256 idx = slice % effectiveLen;
        winners[i] = idx < len ? holders[idx] : deity;
        unchecked {
            ++i;
            slice = (slice >> 16) | (slice << 240);  // Bit rotation for next index
        }
    }
}
```

### Winner Index Formula: Far-Future Coin (JM:2537-2560)
```solidity
// Source: contracts/modules/DegenerusGameJackpotModule.sol:2537-2560
for (uint8 s; s < FAR_FUTURE_COIN_SAMPLES; ) {
    entropy = EntropyLib.entropyStep(entropy ^ uint256(s));
    uint24 candidate = lvl + 5 + uint24(entropy % 95);  // Random level [lvl+5, lvl+99]

    address[] storage queue = ticketQueue[_tqFarFutureKey(candidate)];  // FF key only
    uint256 len = queue.length;
    if (len != 0) {
        address winner = queue[(entropy >> 32) % len];  // Direct index, no deity
        // ...
    }
    unchecked { ++s; }
}
```

### BAF Indirect Consumption via View Functions (DegenerusJackpots:298-340)
```solidity
// Source: contracts/DegenerusJackpots.sol:298 (Slice D)
address[] memory farTickets = degenerusGame.sampleFarFutureTickets(entropy);
// This calls DG:2681 which reads ticketQueue[_tqWriteKey(candidate)]
// KNOWN ISSUE: should be _tqFarFutureKey after v3.9

// Source: contracts/DegenerusJackpots.sol:418 (Scatter)
(, address[] memory tickets) = degenerusGame.sampleTraitTicketsAtLevel(targetLvl, entropy);
// This calls DG:2647 which reads traitBurnTicket[targetLvl][traitSel]
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact on Phase 83 |
|--------------|------------------|--------------|---------------------|
| FF coin reads from `_tqWriteKey` (TQ-01 vulnerability) | Reads from `_tqFarFutureKey` only | v3.9 Phase 77 + commit 2bf830a2 | TCON-01: Only FF key is consumed for FF coin |
| Combined pool (read + FF) for FF coin | FF-only read | commit 2bf830a2 | TCON-03: Simpler winner index (no combined length) |
| `sampleFarFutureTickets` reads `_tqWriteKey` | Still reads `_tqWriteKey` (UNFIXED) | N/A | TCON-04: BAF far-future draws affected (DSC-02 downstream impact) |

## Open Questions

1. **Is the BAF far-future allocation (10% of BAF pool) systematically wasted?**
   - What we know: `sampleFarFutureTickets` reads from `_tqWriteKey` which won't contain far-future tickets post-v3.9. This means Slice D and D2 in `runBafJackpot` will likely find empty arrays and refund the allocation.
   - What's unclear: Whether any near-future tickets happen to be in the write buffer at levels [lvl+5, lvl+99], which would cause BAF to select from the wrong pool rather than finding nothing.
   - Recommendation: Flag as [NEW FINDING] INFO severity. The fix is the same as DSC-02: update `sampleFarFutureTickets` to use `_tqFarFutureKey`. This affects BAF prize distribution but not security.

2. **Are the daily coin and daily ETH jackpots using the same `randWord` for entropy?**
   - What we know: Both `payDailyJackpot` and `payDailyJackpotCoinAndTickets` receive `randWord` = `rngWordCurrent`. They derive different entropy by XORing with different tags (ETH uses `lvl << 192` only; coin adds `COIN_JACKPOT_TAG`).
   - What's unclear: Nothing -- this is by design. Domain separation via tags prevents correlation.
   - Recommendation: Document as expected behavior in the audit.

3. **Does the deity virtual entry mechanism correctly account for multiple deities?**
   - What we know: Each trait's symbol maps to at most 1 deity (`deityBySymbol[fullSymId]`). Virtual count is `max(holders.length / 50, 2)`.
   - What's unclear: Whether this is a finding -- it means a deity holder gets `virtualCount` chances at each bucket draw, which could be significant for small buckets.
   - Recommendation: Not a Phase 83 finding (this is by design per JM:2229 NatSpec: "Duplicates are intentionally allowed -- more tickets = more chances to win multiple times").

## Sources

### Primary (HIGH confidence)
- `contracts/modules/DegenerusGameJackpotModule.sol` -- all winner selection functions (JM:323-2606, JM:2237-2337)
- `contracts/storage/DegenerusGameStorage.sol` -- queue key encoding (GS:686-701)
- `contracts/DegenerusGame.sol` -- view functions for BAF (DG:2595-2705)
- `contracts/DegenerusJackpots.sol` -- BAF jackpot (DegenerusJackpots:229-524)
- `contracts/modules/DegenerusGameAdvanceModule.sol` -- RNG fulfillment chain (AM:1442-1462, AM:1522-1538)

### Secondary (MEDIUM confidence)
- `audit/v3.8-commitment-window-inventory.md` -- prior audit categories for ticket consumption (cross-referenced)
- `audit/v3.9-rng-commitment-window-proof.md` -- prior proof (contains stale combined pool claims, DSC-01)
- `audit/v4.0-ticket-creation-queue-mechanics.md` -- Phase 81 findings (DSC-01, DSC-02, DSC-03)
- `audit/v4.0-ticket-queue-double-buffer.md` -- Phase 81 double-buffer documentation

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- ticketQueue consumption enumeration: HIGH -- grep across all contracts, every read site manually traced
- traitBurnTicket consumption enumeration: HIGH -- grep across all contracts, 14 distinct read sites documented
- Winner index computation: HIGH -- all 8 jackpot types traced with exact entropy derivation formulas
- RNG word derivation: HIGH -- traced from rawFulfillRandomWords through _applyDailyRng to each consumer
- Discrepancy detection: HIGH -- cross-referenced against v3.8 and v3.9 audit documents with current code
- BAF indirect consumption: HIGH -- DegenerusJackpots.sol view function calls traced to DegenerusGame

**Research date:** 2026-03-23
**Valid until:** Indefinite (audit of immutable contract code)
