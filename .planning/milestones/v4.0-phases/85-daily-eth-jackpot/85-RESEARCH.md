# Phase 85: Daily ETH Jackpot - Research

**Researched:** 2026-03-23
**Domain:** Solidity smart contract audit -- daily ETH jackpot mechanics in Degenerus Protocol
**Confidence:** HIGH

## Summary

Phase 85 audits the daily ETH jackpot distribution system within DegenerusGameJackpotModule.sol. This is a read-only audit phase producing a document with file:line citations -- no code modifications.

The daily ETH jackpot is implemented as a two-phase chunked distribution system. Phase 0 distributes ETH from `currentPrizePool` to winners at the current jackpot level. Phase 1 distributes a carryover portion sourced from `futurePrizePool` (1% drip) to winners at a randomly-selected future level. The system uses a bucket/cursor mechanism with gas-bounded iteration that can resume across multiple `advanceGame` calls. There is additionally a separate early-burn path that operates during the purchase phase (not during jackpot phase), drawing from `futurePrizePool` with a different BPS split.

The audit must trace five requirements: (DETH-01) the BPS allocation table and split logic from `currentPrizePool`, (DETH-02) Phase 0 vs Phase 1 behavioral differences, (DETH-03) the bucket/cursor winner selection algorithm, (DETH-04) carryover mechanics including unfilled buckets and rollover, and (DETH-05) tagging all discrepancies against prior audit prose.

**Primary recommendation:** Structure the audit as a linear trace through `payDailyJackpot` (JM:323), covering the daily path fresh-start budget calculation, then Phase 0 chunk processing, then Phase 1 carryover chunk processing, then the early-burn path, documenting BPS allocations and winner selection at each step. Reference JackpotBucketLib for bucket sizing/share math.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DETH-01 | currentPrizePool source, BPS allocation table, and split logic documented with file:line | Budget calculation at JM:365-376, _dailyCurrentPoolBps at JM:2656-2668, share packing constants at JM:114-125, split into lootbox/ETH at JM:385-404. Early-burn path at JM:629-633. |
| DETH-02 | Phase 0 vs Phase 1 jackpot behavior documented | Phase 0 block at JM:488-556, Phase 1 block at JM:559-606. Key differences: source pool, level selection, winner cap derivation, bucket sizing entropy, share packing. |
| DETH-03 | Bucket/cursor winner selection algorithm documented with file:line | _processDailyEthChunk at JM:1387-1509, dailyEthBucketCursor/dailyEthWinnerCursor resume logic, JackpotBucketLib.bucketCountsForPoolCap, bucketShares, soloBucketIndex, bucketOrderLargestFirst. Winner selection via _randTraitTicketWithIndices at JM:2283. |
| DETH-04 | Carryover mechanics (unfilled buckets, excess, rollover) documented | Carryover source selection at JM:2708-2750, carryover pool calculation at JM:423-467, dailyCarryoverWinnerCap at JM:530-543, _clearDailyEthState at JM:2785-2793. Day-to-day state reset behavior. |
| DETH-05 | Every discrepancy and new finding tagged | Cross-reference against v3.2 jackpot module audit findings (CMT-V32-001, CMT-V32-002), v3.8 commitment window inventory Section 1.7, and PAYOUT-SPECIFICATION.html PAY-01/PAY-02 entries. |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- Only read contracts from `contracts/` directory; stale copies exist elsewhere
- Present fix and wait for explicit approval before editing code (not applicable -- audit phase, no code changes)
- NEVER commit contracts/ or test/ changes without explicit user approval (not applicable -- audit phase)
- Every RNG audit must trace BACKWARD from each consumer to verify word was unknown at input commitment time
- Every RNG audit must check what player-controllable state can change between VRF request and fulfillment

## Key Contract Files and Line Ranges

All file:line citations verified against current working tree as of 2026-03-23.

### Primary: DegenerusGameJackpotModule.sol (JM)
**Path:** `contracts/modules/DegenerusGameJackpotModule.sol` (2794 lines)

| Function/Constant | Lines | Purpose |
|---|---|---|
| Constants (timing, shares, caps) | JM:104-224 | JACKPOT_RESET_TIME, JACKPOT_LEVEL_CAP, FINAL_DAY_SHARES_PACKED, DAILY_JACKPOT_SHARES_PACKED, DAILY_ETH_MAX_WINNERS, DAILY_CARRYOVER_MIN_WINNERS, all BPS constants |
| `payDailyJackpot` | JM:323-667 | Main entry point -- daily path (JM:331-607), early-burn path (JM:609-667) |
| `payDailyJackpotCoinAndTickets` | JM:681-766 | Phase 2: coin + ticket distribution (increments jackpotCounter) |
| `awardFinalDayDgnrsReward` | JM:773-798 | Day-5 DGNRS reward to solo bucket winner |
| `_runEarlyBirdLootboxJackpot` | JM:801-864 | Day-1 early-bird lootbox from 3% futurePrizePool |
| `consolidatePrizePools` | JM:879-908 | Pool merging at level transition |
| `_addClaimableEth` | JM:957-978 | ETH crediting with auto-rebuy |
| `_processAutoRebuy` | JM:988-1028 | Auto-rebuy conversion |
| `_validateTicketBudget` | JM:1053-1060 | Zero budget if no trait tickets exist |
| `_budgetToTicketUnits` | JM:1063-1070 | ETH to ticket unit conversion |
| `_distributeLootboxAndTickets` | JM:1079-1102 | Lootbox budget distribution |
| `_executeJackpot` | JM:1309-1323 | Early-burn path jackpot execution |
| `_runJackpotEthFlow` | JM:1326-1351 | Simple ETH flow for non-daily jackpots |
| `_winnerUnits` | JM:1358-1364 | Gas cost per winner (auto-rebuy = 3x) |
| `_skipEntropyToBucket` | JM:1367-1384 | Resume entropy state for mid-bucket resume |
| `_processDailyEthChunk` | JM:1387-1509 | **Core chunked distribution** -- Phase 0 and Phase 1 shared logic |
| `_distributeJackpotEth` | JM:1512-1551 | Non-chunked ETH distribution (early-burn/terminal) |
| `_processOneBucket` | JM:1554-1581 | Single bucket processing for non-chunked path |
| `_resolveTraitWinners` | JM:1605-1731 | Winner resolution per trait bucket |
| `_processSoloBucketWinner` | JM:1761-1793 | Solo bucket 75/25 ETH/whale-pass split |
| `_randTraitTicket` | JM:2237-2280 | Winner selection from traitBurnTicket |
| `_randTraitTicketWithIndices` | JM:2283-2336 | Winner selection with ticket index tracking |
| `_rollWinningTraits` | JM:2610-2625 | Trait derivation (burn-weighted vs random) |
| `_syncDailyWinningTraits` | JM:2627-2635 | Store winning traits for resume |
| `_dailyCurrentPoolBps` | JM:2656-2668 | Random 6-14% BPS for days 1-4 |
| `_selectCarryoverSourceOffset` | JM:2708-2750 | Random source level for carryover |
| `_highestCarryoverSourceOffset` | JM:2690-2702 | Highest level with actual trait tickets |
| `_hasActualTraitTickets` | JM:2672-2685 | Check for non-virtual trait tickets at level |
| `_packDailyTicketBudgets` | JM:2753-2764 | Pack counter step + ticket budgets |
| `_unpackDailyTicketBudgets` | JM:2766-2782 | Unpack stored ticket budgets |
| `_clearDailyEthState` | JM:2785-2793 | Reset all daily ETH state, set coinTicketsPending |

### Supporting: JackpotBucketLib.sol (JBL)
**Path:** `contracts/libraries/JackpotBucketLib.sol` (307 lines)

| Function | Lines | Purpose |
|---|---|---|
| `traitBucketCounts` | JBL:36-51 | Base counts [25, 15, 8, 1] with rotation |
| `scaleTraitBucketCountsWithCap` | JBL:55-95 | Scale by pool size (1x/2x/4x/6.67x) |
| `bucketCountsForPoolCap` | JBL:98-107 | Combined base + scale + cap |
| `capBucketCounts` | JBL:115-203 | Cap total winners, preserve solo bucket |
| `bucketShares` | JBL:211-237 | ETH share per bucket with remainder to solo |
| `soloBucketIndex` | JBL:240-242 | Solo bucket index from entropy |
| `shareBpsByBucket` | JBL:251-257 | Unpack + rotate share BPS |
| `bucketOrderLargestFirst` | JBL:290-306 | Ordering for chunked processing |

### Supporting: DegenerusGameStorage.sol (GS)
**Path:** `contracts/storage/DegenerusGameStorage.sol` (1622 lines)

| Variable | Storage Slot | Offset | Type | Purpose |
|---|---|---|---|---|
| `jackpotCounter` | Slot 0 | 22:23 | uint8 | Days processed this level (0-5) |
| `dailyEthBucketCursor` | Slot 0 | 30:31 | uint8 | Bucket cursor for chunked distribution |
| `dailyEthPhase` | Slot 1 | 0:1 | uint8 | 0 = current level, 1 = carryover |
| `compressedJackpotFlag` | Slot 1 | 1:2 | uint8 | 0=normal, 1=compressed(3d), 2=turbo(1d) |
| `prizePoolFrozen` | Slot 1 | 26:27 | bool | Pool freeze during jackpot phase |
| `currentPrizePool` | Slot 2 | 0:32 | uint256 | Active prize pool |
| `prizePoolsPacked` | Slot 3 | 0:32 | uint256 | Packed [future|next] pools |
| `dailyTicketBudgetsPacked` | Slot 7 | 0:32 | uint256 | Packed ticket budgets for phase 2 |
| `dailyEthPoolBudget` | Slot 8 | 0:32 | uint256 | Stored ETH budget for resume |
| `dailyEthWinnerCursor` | Slot 17 | 0:2 | uint16 | Winner cursor within bucket |
| `dailyCarryoverEthPool` | Slot 18 | 0:32 | uint256 | Carryover ETH reserved |
| `dailyCarryoverWinnerCap` | Slot 19 | 0:2 | uint16 | Max carryover winners |
| `lastDailyJackpotWinningTraits` | (later slot) | — | uint32 | Stored winning traits for resume |
| `lastDailyJackpotLevel` | (later slot) | — | uint24 | Stored level for resume |

### Supporting: DegenerusGameAdvanceModule.sol (AM)
**Path:** `contracts/modules/DegenerusGameAdvanceModule.sol`

| Call Site | Line | Context |
|---|---|---|
| `payDailyJackpot(false, purchaseLevel, rngWord)` | AM:282 | Purchase phase early-burn |
| `payDailyJackpot(true, lastDailyJackpotLevel, rngWord)` | AM:356 | Jackpot phase resume |
| `payDailyJackpotCoinAndTickets(rngWord)` | AM:363 | Coin+ticket phase 2 |
| `payDailyJackpot(true, lvl, rngWord)` | AM:379 | Jackpot phase fresh start |
| Resume detection condition | AM:350-354 | Matches JM isResuming logic |

## Architecture Patterns

### Daily ETH Jackpot Flow (Two-Phase Chunked)

```
advanceGame()
  |
  +-- PURCHASE PHASE: payDailyJackpot(isDaily=false)  [AM:282]
  |     Early-burn path: 1% futurePrizePool drip -> _executeJackpot
  |
  +-- JACKPOT PHASE:
        |
        +-- Resume check [AM:350-354]
        |     If dailyEthBucketCursor/dailyEthPhase/dailyEthPoolBudget/dailyEthWinnerCursor != 0
        |     -> payDailyJackpot(true, lastDailyJackpotLevel, rngWord)  [AM:356]
        |
        +-- Coin+ticket pending check [AM:362]
        |     If dailyJackpotCoinTicketsPending
        |     -> payDailyJackpotCoinAndTickets(rngWord)  [AM:363]
        |
        +-- Fresh daily jackpot [AM:379]
              payDailyJackpot(true, lvl, rngWord)
              |
              +-- Fresh Start (isResuming=false):
              |     1. Roll winning traits [JM:344]
              |     2. Calculate budget: currentPrizePool * dailyBps [JM:365-376]
              |     3. Early-bird lootbox on day 1 [JM:380-382]
              |     4. Split: 20% lootbox budget, 80% ETH budget [JM:384-394]
              |     5. Carryover: 1% futurePrizePool (days 2-5) [JM:423-431]
              |     6. Store all state for resume [JM:459-471]
              |
              +-- Phase 0: Current level ETH distribution
              |     _processDailyEthChunk(lvl, ...) [JM:513-526]
              |     - Iterate buckets largest-first
              |     - Gas-bounded by unitsBudget
              |     - May return incomplete (save cursor, return)
              |     - On complete: derive carryover winner cap [JM:528-543]
              |     - Transition to Phase 1 [JM:553-556]
              |
              +-- Phase 1: Carryover ETH distribution
                    _processDailyEthChunk(carryoverSourceLevel, ...) [JM:590-598]
                    - Uses dailyCarryoverEthPool
                    - Uses dailyCarryoverWinnerCap
                    - On complete: _clearDailyEthState() [JM:604]
                    - Sets dailyJackpotCoinTicketsPending = true
```

### BPS Allocation Table

| Day | Counter | currentPrizePool BPS | Share Packing | Source |
|-----|---------|---------------------|---------------|--------|
| Day 1 | 0 | Random 6-14% (600-1400 BPS) | DAILY_JACKPOT_SHARES_PACKED (20/20/20/20+remainder) | JM:370, JM:503 |
| Day 2 | 1 | Random 6-14% | DAILY_JACKPOT_SHARES_PACKED | JM:370, JM:503 |
| Day 3 | 2 | Random 6-14% | DAILY_JACKPOT_SHARES_PACKED | JM:370, JM:503 |
| Day 4 | 3 | Random 6-14% | DAILY_JACKPOT_SHARES_PACKED | JM:370, JM:503 |
| Day 5 | 4 | 100% (10000 BPS) | FINAL_DAY_SHARES_PACKED (60/13/13/13+remainder) | JM:368, JM:501 |

**Compressed mode (flag=1):** counterStep=2 on days 2-4, dailyBps doubled (JM:372-374). Five logical days in three physical days.

**Turbo mode (flag=2):** counterStep=5 on day 1, all five logical days in one physical day (JM:353-354).

### Budget Split Within Each Day

| Slice | Source | BPS | Destination |
|-------|--------|-----|-------------|
| Main ETH budget | currentPrizePool * dailyBps | 80% (budget - lootboxBudget) | _processDailyEthChunk -> claimableWinnings |
| Daily lootbox budget | currentPrizePool * dailyBps | 20% (budget/5) | nextPrizePool + ticket distribution |
| Carryover ETH (days 2-5) | futurePrizePool * 1% | Varies (50% lootbox, 50% ETH) | _processDailyEthChunk -> claimableWinnings |
| Carryover lootbox | carryover pool * 5000 BPS | 50% of carryover | nextPrizePool + ticket distribution |

### Bucket/Cursor Winner Selection Algorithm

1. **Bucket sizing:** `JackpotBucketLib.bucketCountsForPoolCap(ethPool, entropy, maxWinners, maxScaleBps)` computes base counts [25, 15, 8, 1], scales by pool size (1x < 10 ETH, 2x at 50 ETH, 4x/6.67x at 200+ ETH), caps total to DAILY_ETH_MAX_WINNERS (321).

2. **Share allocation:** `JackpotBucketLib.bucketShares(ethPool, shareBps, bucketCounts, remainderIdx, unit)` splits ETH. Non-solo buckets are rounded to `unit * count`. Solo bucket (remainderIdx) gets all remainder.

3. **Bucket ordering:** `JackpotBucketLib.bucketOrderLargestFirst(bucketCounts)` -- process largest bucket first.

4. **Iteration (JM:1427-1502):**
   - For each bucket in order: derive sub-entropy, select winners from `traitBurnTicket[lvl]` via `_randTraitTicketWithIndices`
   - Per winner: check gas budget (`unitsUsed + cost > unitsBudget`), if exceeded: save `dailyEthBucketCursor` and `dailyEthWinnerCursor`, return `complete=false`
   - Credit ETH via `_addClaimableEth` (which may trigger auto-rebuy)
   - Emit `JackpotTicketWinner` events

5. **Resume logic:** On next `advanceGame` call, `_processDailyEthChunk` restores cursor state. `_skipEntropyToBucket` (JM:1367) fast-forwards entropy to the saved bucket position. Winner loop resumes at saved `startWinnerIdx`.

### Phase 0 vs Phase 1 Differences

| Property | Phase 0 (dailyEthPhase=0) | Phase 1 (dailyEthPhase=1) |
|----------|--------------------------|--------------------------|
| Source pool | currentPrizePool (via dailyEthPoolBudget) | futurePrizePool 1% drip (via dailyCarryoverEthPool) |
| Target level | Current jackpot level (lvl) | Random future level (lvl + carryoverSourceOffset, 1-5) |
| Winner cap | DAILY_ETH_MAX_WINNERS (321) | dailyCarryoverWinnerCap (321 - Phase 0 winners, min 20) |
| Entropy derivation | `randWord ^ (uint256(lvl) << 192)` | `randWord ^ (uint256(carryoverSourceLevel) << 192)` |
| Share packing | Final day: FINAL_DAY, else: DAILY_JACKPOT | Same as Phase 0 (same day) |
| Pool deduction | `currentPrizePool -= paidDailyEth` (JM:522) | No deduction -- pool pre-deducted at JM:430 |
| Triggered when | dailyEthPhase == 0 and budget != 0 | dailyEthPhase == 1 |
| On completion | Sets dailyEthPhase = 1 (JM:553) | Calls _clearDailyEthState (JM:604) |
| Skipped when | budget == 0 (goes straight to Phase 1 check) | dailyCarryoverEthPool == 0 or dailyCarryoverWinnerCap == 0 |
| Day 1 behavior | Normal distribution | Skipped (no carryover; early-bird lootbox instead) |

### Carryover Mechanics

1. **Source selection (JM:2708-2750):** `_selectCarryoverSourceOffset` finds the highest level in [lvl+1..lvl+5] with actual non-virtual trait tickets (`_hasActualTraitTickets`), then picks a random offset in [1..highestEligible] starting from a deterministic random start point. Returns 0 if no eligible levels exist.

2. **Pool calculation (JM:423-431):** `reserveSlice = _getFuturePrizePool() / 100` (1% flat drip). Deducted immediately from futurePrizePool.

3. **Lootbox split (JM:434-448):** `carryoverLootboxBps = DAILY_REWARD_JACKPOT_LOOTBOX_BPS (5000)` -- 50% of carryover pool goes to lootbox budget (tickets to nextPrizePool).

4. **Unfilled buckets:** When `_processDailyEthChunk` finds empty trait pools (winners.length == 0 at JM:1454), it skips the bucket with zero winners emitted. The share for that bucket is never paid out -- it remains in the pool as undistributed ETH. Since Phase 0 deducts `paidDailyEth` (only actually paid) from `currentPrizePool` (JM:522), unfilled bucket ETH stays in currentPrizePool.

5. **Excess / dust:** `perWinner = share / totalCount` at JM:1459 -- integer division dust stays in the share but is never credited. For Phase 0, this dust remains in currentPrizePool (since only paidEth is deducted). For Phase 1 carryover, the pool was pre-deducted from futurePrizePool at JM:430, so unpaid carryover ETH effectively becomes untracked -- it stays in the contract's ETH balance but is not attributed to any named pool.

6. **Day-to-day rollover:** `_clearDailyEthState` (JM:2785-2793) zeros all daily state and sets `dailyJackpotCoinTicketsPending = true`. There is no explicit rollover of unpaid ETH to the next day -- currentPrizePool simply retains what was not deducted. The next day's budget is calculated fresh from the (now-larger) remaining currentPrizePool.

7. **Winner cap derivation (JM:528-543):** After Phase 0 completes, if total daily winners >= DAILY_ETH_MAX_WINNERS (321), carryover cap is 0 (no carryover). Otherwise, cap = max(DAILY_ETH_MAX_WINNERS - totalDailyWinners, DAILY_CARRYOVER_MIN_WINNERS (20)). When cap is 0 and carryover pool is nonzero, carryover is skipped and the pre-deducted futurePrizePool slice is lost (see finding area below).

### Early-Burn Path (Purchase Phase)

Separate from the daily jackpot. Called with `isDaily=false` at AM:282.

| Property | Value |
|----------|-------|
| Source | futurePrizePool * 1% (100 BPS) at JM:629-630 |
| When | Every purchase day after day 1 of each level, lvl > 1 (JM:622-624) |
| Lootbox split | 75% ticket conversion (PURCHASE_REWARD_JACKPOT_LOOTBOX_BPS = 7500) at JM:640 |
| ETH distribution | Via _executeJackpot -> _runJackpotEthFlow -> _distributeJackpotEth (non-chunked) |
| Bucket sizing | JACKPOT_MAX_WINNERS (300), JACKPOT_SCALE_MAX_BPS (40000) -- different from daily |
| Share packing | DAILY_JACKPOT_SHARES_PACKED (20/20/20/20) always |

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Bucket share calculation | Manual BPS division | JackpotBucketLib.bucketShares | Handles remainder routing to solo bucket, unit rounding |
| Winner selection | Manual random index | _randTraitTicket / _randTraitTicketWithIndices | Handles virtual deity entries, entropy derivation, salt |
| Bucket scaling | Manual scale factors | scaleTraitBucketCountsWithCap | Piecewise linear scaling with cap preservation |

## Common Pitfalls

### Pitfall 1: Confusing the Three Distribution Paths
**What goes wrong:** Treating early-burn, Phase 0 daily, and Phase 1 carryover as the same flow
**Why it happens:** All three call into bucket distribution logic, but with different source pools, BPS, and caps
**How to avoid:** Trace each path separately with its own parameter table
**Warning signs:** Citing JACKPOT_MAX_WINNERS for daily path (should be DAILY_ETH_MAX_WINNERS)

### Pitfall 2: Missing the Pre-Deduction Model for Carryover
**What goes wrong:** Assuming carryover ETH is deducted on payout (like Phase 0)
**Why it happens:** Phase 0 deducts `currentPrizePool -= paidDailyEth` after distribution, but carryover deducts futurePrizePool upfront at JM:430
**How to avoid:** Note that Phase 1's _processDailyEthChunk return value for paidEth is ignored (assigned to `_` at JM:590)
**Warning signs:** Looking for a `futurePrizePool -= paidCarryoverEth` that does not exist

### Pitfall 3: Compressed/Turbo Mode Doubling
**What goes wrong:** Missing that compressed mode doubles the BPS (JM:372-374)
**Why it happens:** `counterStep` is packed in dailyTicketBudgetsPacked and only visible via unpacking
**How to avoid:** Document all three modes (normal/compressed/turbo) explicitly

### Pitfall 4: Resume Entropy Determinism
**What goes wrong:** Assuming resumed chunks use different randomness
**Why it happens:** The resume path restores `lastDailyJackpotWinningTraits` and `lastDailyJackpotLevel` (JM:340-341), and _skipEntropyToBucket reconstructs entropy state
**How to avoid:** Verify entropy is deterministic across resume boundaries

### Pitfall 5: Carryover Pool Pre-Deduction Loss
**What goes wrong:** Missing that when dailyCarryoverWinnerCap = 0, the pre-deducted futurePrizePool slice is effectively lost
**Why it happens:** JM:430 deducts from futurePrizePool, but JM:547 skips distribution when cap is 0 or pool is 0
**How to avoid:** Flag this as an area to investigate -- is the undistributed carryover ETH tracked anywhere?

## Prior Audit Cross-Reference Points

The audit must cross-reference these prior documents for discrepancy detection (DETH-05):

| Document | Relevant Sections | What to Cross-Check |
|----------|-------------------|---------------------|
| `audit/v3.2-findings-39-jackpot-module.md` | CMT-V32-001 (ticketSpent NatSpec), CMT-V32-002 (inline comment "BURNIE only") | Verify whether these findings were fixed or remain |
| `audit/v3.8-commitment-window-inventory.md` | Section 1.7 (payDailyJackpot R/W inventory) | Verify storage variables listed match current code |
| `audit/PAYOUT-SPECIFICATION.html` | PAY-01 (purchase-phase daily), PAY-02 (jackpot-phase daily) | Verify BPS values, source pools, share splits match code |
| `audit/v4.0-ticket-creation-queue-mechanics.md` | Any references to jackpot ticket distribution | Verify consistency with ticket queue mechanics findings |

### v3.8 Commitment Window Variables to Re-Verify

From Section 1.7 of the commitment window inventory, these variables are read/written during payDailyJackpot:

| Variable | Slot | Claimed Purpose | Re-verify |
|----------|------|-----------------|-----------|
| currentPrizePool | 2 | Snapshot pool, deduct daily budget | Confirm R/W pattern |
| jackpotCounter | 0:22 | Day index within jackpot phase | Confirm read-only in payDailyJackpot (write is in payDailyJackpotCoinAndTickets) |
| compressedJackpotFlag | 1:0 | Turbo/compressed mode | Confirm read-only |
| dailyEthPoolBudget | 8 | Store/read daily ETH budget | Confirm R/W pattern |
| dailyEthPhase | 1:0 | Phase 0/Phase 1 state | Confirm R/W pattern |
| dailyEthBucketCursor | 0:30 | Bucket progress | Confirm R/W pattern |

## RNG-Dependent Variables in Daily ETH Jackpot

These variables consume VRF entropy during daily ETH jackpot execution:

| Variable/Function | Source | How RNG is Used |
|---|---|---|
| `_dailyCurrentPoolBps` | JM:2656 | `keccak256(randWord, DAILY_CURRENT_BPS_TAG, counter)` determines 6-14% slice |
| `_rollWinningTraits` | JM:2610 | VRF word determines winning trait IDs via `_getWinningTraits` |
| `_selectCarryoverSourceOffset` | JM:2708 | `keccak256(randWord, DAILY_CARRYOVER_SOURCE_TAG, counter)` selects source level |
| `_processDailyEthChunk` entropy | JM:474 | `randWord ^ (uint256(lvl) << 192)` seeds all winner selection |
| `_randTraitTicketWithIndices` | JM:2283 | Entropy modulo effectiveLen selects winner indices |
| Bucket rotation | JBL:44 | `entropy & 3` rotates base bucket assignments |
| Solo bucket index | JBL:241 | `(3 - (entropy & 3)) & 3` selects which bucket gets remainder |

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Foundry (forge) |
| Config file | `foundry.toml` |
| Quick run command | `forge test --match-contract JackpotModule -x` |
| Full suite command | `forge test` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DETH-01 | BPS allocation table matches code | manual-only | N/A -- audit document verification | N/A |
| DETH-02 | Phase 0 vs Phase 1 differences documented | manual-only | N/A -- audit document verification | N/A |
| DETH-03 | Bucket/cursor algorithm documented | manual-only | N/A -- audit document verification | N/A |
| DETH-04 | Carryover mechanics documented | manual-only | N/A -- audit document verification | N/A |
| DETH-05 | Discrepancies tagged | manual-only | N/A -- audit document verification | N/A |

**Justification for manual-only:** This is an audit documentation phase. The deliverable is a markdown document with file:line citations. Automated tests validate code behavior, not audit document accuracy.

### Sampling Rate
- **Per task commit:** Verify file:line citations against current code
- **Per wave merge:** Cross-reference against prior audit documents
- **Phase gate:** All 5 DETH requirements marked with [VERIFIED] in audit document

### Wave 0 Gaps
None -- existing test infrastructure covers contract behavior. This phase produces documentation only.

## Areas Requiring Deep Investigation

These are specific areas the audit plan should allocate dedicated attention to:

1. **Carryover pre-deduction loss path:** When Phase 0 uses all 321 winners, dailyCarryoverWinnerCap becomes 0 (JM:531), and the 1% futurePrizePool slice deducted at JM:430 is not returned. This ETH sits in the contract balance but is not attributed to any pool. Audit should confirm whether this is intentional (effectively a contribution to contract solvency buffer) or a bug.

2. **CMT-V32-002 status:** The v3.2 finding flagged the inline comment at JM:609 as inaccurate ("BURNIE only, no ETH bonuses"). Current code at JM:609 reads "Non-daily (early-burn) path - BURNIE and ETH bonuses on non-day-1 levels" -- this appears to have been updated. Audit should confirm.

3. **dailyEthPhase storage slot packing:** dailyEthPhase (uint8) is at Slot 1, offset 0. compressedJackpotFlag (uint8) is at Slot 1, offset 1. These share a storage slot. The audit should verify no cross-contamination during concurrent reads/writes.

4. **Entropy determinism across resume:** When _processDailyEthChunk returns incomplete, the next call must reproduce identical bucket sizing and entropy state. Verify that all inputs to bucketCountsForPoolCap and bucketShares are stored or deterministically re-derivable.

## Sources

### Primary (HIGH confidence)
- `contracts/modules/DegenerusGameJackpotModule.sol` -- direct code reading, all line numbers verified
- `contracts/libraries/JackpotBucketLib.sol` -- direct code reading
- `contracts/storage/DegenerusGameStorage.sol` -- storage layout verified
- `contracts/modules/DegenerusGameAdvanceModule.sol` -- call sites verified

### Secondary (MEDIUM confidence)
- `audit/v3.2-findings-39-jackpot-module.md` -- prior audit findings (may reflect pre-fix code)
- `audit/v3.8-commitment-window-inventory.md` -- prior variable catalog (line numbers may drift)
- `audit/PAYOUT-SPECIFICATION.html` -- documentation (may not reflect latest code changes)

### Tertiary (LOW confidence)
- None. All findings based on direct code reading.

## Metadata

**Confidence breakdown:**
- Key code paths: HIGH -- all functions read directly from current Solidity source
- Storage layout: HIGH -- verified against DegenerusGameStorage.sol slot comments
- BPS allocation: HIGH -- constants read directly from JM:114-224
- Prior audit cross-references: MEDIUM -- line numbers may have drifted since v3.2/v3.8
- Carryover loss path analysis: MEDIUM -- needs deeper investigation during audit execution

**Research date:** 2026-03-23
**Valid until:** 2026-04-23 (stable -- contracts are not being modified during v4.0 audit milestone)
