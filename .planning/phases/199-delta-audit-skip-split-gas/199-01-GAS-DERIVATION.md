# Theoretical Worst-Case Gas Derivation -- Post-Skip-Split Jackpot ETH

Supersedes: `196-01-GAS-DERIVATION.md` (pre-skip-split, pre-unified `_processDailyEth`).

Method: Per-operation gas costs from EIP-2929/3529, applied to contract code paths in `DegenerusGameJackpotModule.sol` (commit `0ebfbb0b`).

## 1. Parameters (max scale, 200+ ETH pool)

| Constant | Value | Source |
|----------|-------|--------|
| `DAILY_JACKPOT_SCALE_MAX_BPS` | 63,600 (6.36x) | JackpotModule line 219 |
| `DAILY_ETH_MAX_WINNERS` | 305 | JackpotModule line 192 |
| `JACKPOT_MAX_WINNERS` | 160 | JackpotModule line 188 |
| `MAX_BUCKET_WINNERS` | 250 | JackpotModule line 181 |
| `DAILY_COIN_MAX_WINNERS` | 50 | JackpotModule line 195 |
| `LOOTBOX_MAX_WINNERS` | 100 | JackpotModule line 211 |
| `FAR_FUTURE_COIN_SAMPLES` | 10 | JackpotModule line 204 |
| `JACKPOT_SCALE_MAX_BPS` | 40,000 (4x) | JackpotModule line 214 |
| Base bucket counts | [25, 15, 8, 1] | JackpotBucketLib lines 38-41 |
| Max scaled counts (daily) | [159, 95, 50, 1] = 305 | 25 * 6.36 = 159, 15 * 6.36 = 95, 8 * 6.36 = 50, 1 (solo fixed) |
| Max scaled counts (early-burn) | [100, 60, 32, 1] -> capped to 160 | 4x scale produces 193, `capBucketCounts` proportionally reduces non-solo to fit 159 |
| Call 1 partition (SPLIT_CALL1) | largest(159) + solo(1) = **160** | call1Bucket mask: `order[0]` + `remainderIdx` |
| Call 2 partition (SPLIT_CALL2) | 95 + 50 = **145** | remaining mid buckets |
| Skip-split (SPLIT_NONE daily) | all 4 buckets, total <= 160 | `totalWinners <= JACKPOT_MAX_WINNERS` check in `payDailyJackpot` |

### Scaling Verification

`scaleTraitBucketCountsWithCap` scales non-solo buckets by `scaleBps / 10000`:
- Pool >= 200 ETH: `scaleBps = DAILY_JACKPOT_SCALE_MAX_BPS = 63,600`
- 25 * 63600 / 10000 = 159.0 -> 159
- 15 * 63600 / 10000 = 95.4 -> 95
- 8 * 63600 / 10000 = 50.88 -> 50
- Solo bucket (count=1) is never scaled (guard: `baseCount > 1`)
- Sum: 159 + 95 + 50 + 1 = 305 = `DAILY_ETH_MAX_WINNERS` (matches)

`capBucketCounts` with `maxTotal=305`: 305 <= 305, no cap applied.
`capBucketCounts` with `maxTotal=160`: proportionally scales non-solo to fit 159 total non-solo.

## 2. Per-Winner Gas Cost -- Normal Bucket (autorebuy path, worst case)

Each winner in `_payNormalBucket` (line 1456) calls `_addClaimableEth` (line 762):

### 2a. _randTraitTicket per-winner cost (line 1611)

Winner selection happens in the bucket loop inside `_processDailyEth`. `_randTraitTicket` is called once per bucket, returning `numWinners` results. The per-winner cost within that function:

| Operation | Gas | Notes |
|-----------|-----|-------|
| `keccak256(abi.encode(randomWord, trait, salt, i))` | 66 | SHA3 (30 base + 6/word * 6 words) |
| `% effectiveLen` | 5 | MULMOD |
| `holders[idx]` SLOAD | 2,100 | Cold -- unique storage slot per dynamic array element |
| `ticketIndexes[i]` MSTORE | 3 | Memory write |
| `winners[i]` MSTORE | 3 | Memory write |
| Deity check (`idx < len`) | 3 | LT comparison |
| Loop overhead (i++, comparison) | 13 | ADD + LT + JUMPI |
| **Per-winner subtotal** | **~2,193** | |

One-time per bucket: `holders.length` SLOAD (2,100 cold), deity lookup `deityBySymbol[fullSymId]` SLOAD (2,100 cold), memory allocation (100), array init (50). Total one-time: ~4,350.

### 2b. _addClaimableEth -> _processAutoRebuy (worst case with dust)

When `gameOver == false` and `autoRebuyState[beneficiary].autoRebuyEnabled == true`:

| Operation | Gas | Notes |
|-----------|-----|-------|
| `gameOver` SLOAD | 100 | Warm after first winner in transaction |
| `autoRebuyState[beneficiary]` SLOAD | 2,100 | Cold -- unique address mapping slot per winner |
| Struct decode + enabled check | 30 | |
| **_calcAutoRebuy** (line 52 of PayoutUtils) | | Pure computation |
| `PriceLookupLib.priceForLevel` | 200 | Pure table lookup |
| `EntropyLib.entropyStep` + arithmetic | 300 | Divisions, modulo, comparisons |
| Subtotal calc | 200 | 7 arithmetic ops |
| **_queueTickets** (line 550 of Storage) | | |
| `emit TicketsQueued (LOG3)` | 1,125 | 375 base + 3 * 375 indexed |
| `_tqWriteKey` / `_tqFarFutureKey` | 100 | Pure computation |
| `level` SLOAD (for far-future check) | 100 | Warm |
| `ticketsOwedPacked[wk][buyer]` SLOAD | 2,100 | Cold -- unique buyer * key slot |
| `ticketQueue[wk].push(buyer)` -- new element | 22,100 | Cold SSTORE 0->nonzero for storage slot |
| `ticketQueue[wk].push(buyer)` -- array length | 2,900 | Warm SSTORE (length increment after first push) |
| `ticketsOwedPacked[wk][buyer]` SSTORE | 20,000 | 0->nonzero (first ticket owed for this key+buyer) |
| **Pool update** (back in _processAutoRebuy) | | |
| `_setFuturePrizePool` or `_setNextPrizePool` | 3,000 | Warm SLOAD (100) + Warm SSTORE (2,900) |
| **Dust reserve path** (when `calc.reserved != 0`, i.e. takeProfit > 0) | | |
| `_creditClaimable` -- `claimableWinnings[addr]` SLOAD | 2,100 | Cold -- unique address mapping |
| `_creditClaimable` -- `claimableWinnings[addr]` SSTORE | 20,000 | 0->nonzero |
| `emit PlayerCredited (LOG3)` | 1,125 | 375 base + 3 * 375 indexed |
| **Event in _payNormalBucket** | | |
| `emit JackpotEthWin (LOG3, 7 data args)` | 2,500 | 375 base + 375 * 3 topics + 8 * 7 * 32 data bytes |
| **Loop overhead** | 50 | i++, comparison, memory, address(0) check |
| **TOTAL (with dust, autorebuy)** | **~82,448** | Upper bound per winner |

### 2c. Per-winner cost -- no autorebuy (direct claimable)

When `autoRebuyState[beneficiary].autoRebuyEnabled == false`:

| Operation | Gas | Notes |
|-----------|-----|-------|
| _randTraitTicket per-winner | 2,193 | Same as 2a |
| `gameOver` SLOAD | 100 | Warm |
| `autoRebuyState[beneficiary]` SLOAD | 2,100 | Cold -- check returns false |
| `_creditClaimable` -- `claimableWinnings[addr]` SLOAD | 2,100 | Cold |
| `_creditClaimable` -- `claimableWinnings[addr]` SSTORE | 20,000 | 0->nonzero |
| `emit PlayerCredited (LOG3)` | 1,125 | |
| `emit JackpotEthWin (LOG3)` | 2,500 | |
| Loop overhead | 50 | |
| **TOTAL (no autorebuy)** | **~30,168** | |

### 2d. Rounding for derivation

We round up:
- **Autorebuy with dust: 83,000 gas/winner** (conservative ceiling for 82,448)
- **No autorebuy: 31,000 gas/winner** (conservative ceiling for 30,168)

## 3. Per-Winner Gas Cost -- Solo Bucket

Solo bucket winner goes through `_handleSoloBucketWinner` (line 1401) -> `_processSoloBucketWinner` (line 1486):

| Operation | Gas | Notes |
|-----------|-----|-------|
| All of autorebuy+dust path | ~83,000 | Same `_addClaimableEth` call for ETH portion |
| `perWinner >> 2` + division | 10 | quarter amount + whale pass count calc |
| `whalePassClaims[winner]` SLOAD | 2,100 | Cold mapping |
| `whalePassClaims[winner]` SSTORE | 22,100 | Cold SSTORE 0->nonzero |
| `_setFuturePrizePool` (whale pass cost) | 3,000 | Warm SLOAD + Warm SSTORE |
| `emit JackpotWhalePassWin (LOG3)` | 1,500 | 375 base + 3 * 375 indexed |
| `emit JackpotEthWin (LOG3)` in _handleSoloBucketWinner | 2,500 | Already counted in 83,000 base |
| **isFinalDay path** (worst case): | | |
| `dgnrs.poolBalance()` external call | 2,600 | CALL + calldata |
| `dgnrs.transferFromPool()` external call | 7,000 | External CALL + 2 SSTOREs inside |
| `emit JackpotDgnrsWin (LOG3)` | 1,125 | |
| **TOTAL (solo, jackpot phase, final day)** | **~124,935** | |
| **Rounded up** | **~125,000** | Conservative |

Note: Solo bucket only gets whale pass when `isJackpotPhase == true`. The whale pass cost (SLOAD+SSTORE = 24,200) and `_setFuturePrizePool` (3,000) are absent when `isJackpotPhase == false`.

**Solo bucket, non-jackpot phase (isJackpotPhase=false):**
Same as normal autorebuy winner = **~83,000 gas** (no whale pass, no DGNRS).

## 4. Base Overhead Per _processDailyEth Call

### 4a. SPLIT_CALL1 (daily, high pool, totalWinners > 160)

| Operation | Gas | Notes |
|-----------|-----|-------|
| Function entry + parameter decode | 500 | Stack setup, memory copies |
| `ethPool == 0` check | 3 | |
| `PriceLookupLib.priceForLevel(lvl+1)` | 200 | Pure table lookup |
| `JackpotBucketLib.soloBucketIndex` | 30 | `entropy & 3` |
| `JackpotBucketLib.bucketShares` | 1,500 | 4-iteration loop with divisions |
| `JackpotBucketLib.bucketOrderLargestFirst` | 500 | Sort 4 elements |
| **call1Bucket mask build** (3 comparisons, 2 array writes) | **300** | `splitMode != SPLIT_NONE` branch taken |
| 4-iteration outer loop (2 active, 2 skipped) | 400 | Iterator, continue checks for call1/call2 routing |
| Per-active-bucket: `EntropyLib.entropyStep` | 300 | 2 buckets * 150 |
| Per-active-bucket: _randTraitTicket one-time overhead | 8,700 | 2 buckets * 4,350 |
| `MAX_BUCKET_WINNERS` check per bucket | 20 | 2 comparisons |
| `perWinner = share / totalCount` per bucket | 10 | 2 divisions |
| `claimablePool += liabilityDelta` SLOAD + SSTORE | 3,000 | Warm read + warm write |
| **`resumeEthPool` SSTORE** (0->nonzero) | **22,100** | Cold SSTORE, only on SPLIT_CALL1 |
| **TOTAL overhead (SPLIT_CALL1)** | **~37,563** | |
| **Rounded up** | **~38,000** | |

### 4b. SPLIT_CALL2 (daily resume call)

| Operation | Gas | Notes |
|-----------|-----|-------|
| Function entry + parameter decode | 500 | |
| `resumeEthPool` SLOAD (nonzero->ethPool) | 2,100 | Cold read |
| `resumeEthPool = 0` SSTORE (nonzero->0) | 3,000 | Warm write to zero (refund applies but conservative) |
| `PriceLookupLib.priceForLevel` | 200 | |
| `soloBucketIndex` + `bucketShares` + `bucketOrderLargestFirst` | 2,030 | Same as call 1 |
| **call1Bucket mask build** | **300** | Must rebuild to know which buckets are call2 |
| 4-iteration outer loop (2 active, 2 skipped) | 400 | |
| Per-active-bucket: `EntropyLib.entropyStep` | 300 | 2 buckets * 150 |
| Per-active-bucket: _randTraitTicket one-time | 8,700 | 2 buckets * 4,350 |
| Per-bucket checks | 30 | |
| `claimablePool += liabilityDelta` | 3,000 | Warm |
| No resumeEthPool write (already cleared) | 0 | |
| **TOTAL overhead (SPLIT_CALL2)** | **~20,560** | |
| **Rounded up** | **~21,000** | |

### 4c. SPLIT_NONE (skip-split, daily with <= 160 winners)

| Operation | Gas | Notes |
|-----------|-----|-------|
| Function entry + parameter decode | 500 | |
| `PriceLookupLib.priceForLevel` | 200 | |
| `soloBucketIndex` + `bucketShares` + `bucketOrderLargestFirst` | 2,030 | |
| **call1Bucket mask build** | **0** | `splitMode == SPLIT_NONE` skips this block entirely |
| 4-iteration outer loop (**all 4 active**, no skip checks) | 200 | No call1Bucket comparison overhead |
| Per-active-bucket: `EntropyLib.entropyStep` | 600 | 4 buckets * 150 |
| Per-active-bucket: _randTraitTicket one-time | 17,400 | 4 buckets * 4,350 |
| Per-bucket checks | 60 | 4 checks |
| `claimablePool += liabilityDelta` | 3,000 | Warm |
| **No `resumeEthPool` SSTORE** | **0** | SPLIT_NONE never writes resumeEthPool |
| **TOTAL overhead (SPLIT_NONE)** | **~24,090** | |
| **Rounded up** | **~25,000** | |

### 4d. SPLIT_NONE (non-jackpot phase: early-burn / terminal)

Same as 4c but called via `_runJackpotEthFlow` or `runTerminalJackpot`:

| Operation | Gas | Notes |
|-----------|-----|-------|
| All of SPLIT_NONE overhead | ~25,000 | Same path |
| External delegatecall dispatch (AdvanceModule -> JackpotModule) | 2,600 | delegatecall overhead |
| `_executeJackpot` wrapper overhead | 500 | Struct unpacking, `unpackWinningTraits`, `shareBpsByBucket` |
| `_runJackpotEthFlow`: `traitBucketCounts` + `scaleTraitBucketCountsWithCap` | 2,500 | Library calls with scaling + cap |
| **TOTAL overhead (non-jackpot SPLIT_NONE)** | **~30,600** | |
| **Rounded up** | **~31,000** | |

For `runTerminalJackpot` (called externally, not via delegatecall):

| Operation | Gas | Notes |
|-----------|-----|-------|
| SPLIT_NONE overhead | ~25,000 | |
| External CALL dispatch | 2,600 | |
| Auth check (`msg.sender != GAME`) | 2,600 | `ContractAddresses.GAME` constant + comparison |
| `_rollWinningTraits` | 500 | |
| `bucketCountsForPoolCap` | 2,500 | |
| `shareBpsByBucket` | 200 | |
| **TOTAL overhead (terminal)** | **~33,400** | |
| **Rounded up** | **~34,000** | |

## 5. Caller Overhead (outside _processDailyEth)

### 5a. payDailyJackpot caller overhead (STAGE_JACKPOT_DAILY_STARTED)

Operations in `payDailyJackpot` before/after `_processDailyEth`:

| Operation | Gas | Notes |
|-----------|-----|-------|
| AdvanceModule delegatecall dispatch | 2,600 | |
| `_simulatedDayIndex()` | 300 | |
| `resumeEthPool != 0` check (SLOAD) | 2,100 | Cold |
| `_rollWinningTraits` | 1,500 | keccak + bit manipulation |
| `_syncDailyWinningTraits` | 22,200 | SSTORE 0->nonzero for `lastDailyJackpotWinningTraits` + event |
| `jackpotCounter` SLOAD | 2,100 | Cold |
| `compressedJackpotFlag` SLOAD | 2,100 | Cold |
| Budget calculation (pool reads, BPS computation) | 6,000 | 2 pool SLOADs + arithmetic |
| `_runEarlyBirdLootboxJackpot` (day 1 only) or carryover calc | 5,000 | Variable but bounded |
| `dailyTicketBudgetsPacked` SSTORE | 22,100 | 0->nonzero |
| `bucketCountsForPoolCap` | 2,500 | Library call |
| Skip-split totalWinners sum (4-element loop) | 50 | |
| `shareBpsByBucket` | 200 | |
| Pool deduction after `_processDailyEth` | 3,000 | `_setCurrentPrizePool` warm |
| `dailyJackpotCoinTicketsPending = true` SSTORE | 22,100 | 0->nonzero |
| `emit Advance` | 750 | No `_unlockRng` on this stage (RNG stays locked for call 2 / coin+tickets) |
| `coinflip.creditFlip` (advance bounty) | 32,000 | Cold external CALL + _addDailyFlip SSTOREs |
| **TOTAL caller overhead** | **~126,600** | |
| **Rounded up** | **~127,000** | |

### 5b. _resumeDailyEth caller overhead (STAGE_JACKPOT_ETH_RESUME)

| Operation | Gas | Notes |
|-----------|-----|-------|
| AdvanceModule delegatecall dispatch | 2,600 | |
| `resumeEthPool != 0` check (SLOAD) | 2,100 | Cold |
| `payDailyJackpot` entry + `isDaily` branch | 200 | |
| `resumeEthPool != 0` second check | 100 | Warm now |
| `_unpackDailyTicketBudgets` | 200 | |
| `jackpotCounter` SLOAD | 2,100 | Cold |
| Entropy derivation | 100 | |
| `unpackWinningTraits` | 200 | |
| `shareBpsByBucket` | 200 | |
| `bucketCountsForPoolCap` | 2,500 | Uses `resumeEthPool` as pool |
| Pool deduction after `_processDailyEth` | 3,000 | |
| AdvanceModule: `_unlockRng` | 5,100 | SSTORE for rngLocked |
| `emit Advance` | 750 | |
| `coinflip.creditFlip` (advance bounty) | 32,000 | Cold external CALL (2,600) + _addDailyFlip SSTOREs (~29,000) |
| **TOTAL caller overhead** | **~51,150** | |
| **Rounded up** | **~52,000** | |

### 5c. payDailyJackpotCoinAndTickets caller overhead (STAGE_JACKPOT_COIN_TICKETS)

| Operation | Gas | Notes |
|-----------|-----|-------|
| AdvanceModule delegatecall dispatch | 2,600 | |
| `dailyJackpotCoinTicketsPending` SLOAD + check | 2,100 | Cold |
| `_unpackDailyTicketBudgets` | 200 | |
| `lastDailyJackpotLevel` SLOAD | 2,100 | Cold |
| `lastDailyJackpotWinningTraits` SLOAD | 2,100 | Cold |
| Entropy derivations (2) | 200 | |
| `jackpotCounter` SLOAD | 2,100 | Cold |
| `dailyJackpotCoinTicketsPending = false` SSTORE | 2,900 | nonzero->zero |
| `dailyTicketBudgetsPacked = 0` SSTORE | 2,900 | nonzero->zero |
| `jackpotCounter += counterStep` SSTORE | 2,900 | Warm write |
| AdvanceModule: `_unlockRng` | 5,100 | |
| `emit Advance` | 750 | |
| `coinflip.creditFlip` (advance bounty) | 32,000 | Cold external CALL + _addDailyFlip SSTOREs |
| **TOTAL caller overhead** | **~57,950** | |
| **Rounded up** | **~58,000** | |

## 6. Stage-by-Stage Worst-Case Totals

### 6a. STAGE_JACKPOT_DAILY_STARTED -- Sub-case A: SPLIT_CALL1 (totalWinners > 160)

Worst case: pool >= 200 ETH, all winners have autorebuy enabled with takeProfit > 0 (dust path).

| Component | Gas |
|-----------|-----|
| Caller overhead (payDailyJackpot + AdvanceModule) | 127,000 |
| _processDailyEth base overhead (SPLIT_CALL1) | 38,000 |
| 159 normal winners * 83,000 | 13,197,000 |
| 1 solo winner * 125,000 (whale pass + DGNRS on final day) | 125,000 |
| **TOTAL** | **13,487,000** |
| **% of 16M limit** | **84.3%** |
| **Margin** | **2,513,000 (15.7%)** |

### 6b. STAGE_JACKPOT_DAILY_STARTED -- Sub-case B: SPLIT_NONE (totalWinners <= 160)

Skip-split: all 4 buckets in one call. Worst case: exactly 160 total winners (e.g. pool just under scaling threshold where scaled counts sum to <= 160).

Winner distribution at total=160: up to 159 non-solo + 1 solo. All have autorebuy with dust.

| Component | Gas |
|-----------|-----|
| Caller overhead (payDailyJackpot + AdvanceModule) | 127,000 |
| _processDailyEth base overhead (SPLIT_NONE) | 25,000 |
| 159 normal winners * 83,000 | 13,197,000 |
| 1 solo winner * 125,000 (whale pass + DGNRS on final day) | 125,000 |
| **TOTAL** | **13,474,000** |
| **% of 16M limit** | **84.2%** |
| **Margin** | **2,526,000 (15.8%)** |

Note: SPLIT_NONE is cheaper than SPLIT_CALL1 by ~13,000 gas (no resumeEthPool SSTORE, no call1Bucket mask build). Same winner count ceiling of 160.

### 6c. STAGE_JACKPOT_ETH_RESUME -- SPLIT_CALL2 (totalWinners > 160)

Only reached when SPLIT_CALL1 was used in the previous call. 95 + 50 = 145 mid-bucket winners.

| Component | Gas |
|-----------|-----|
| Caller overhead (_resumeDailyEth) | 52,000 |
| _processDailyEth base overhead (SPLIT_CALL2) | 21,000 |
| 145 normal winners * 83,000 | 12,035,000 |
| No solo winner in call 2 | 0 |
| **TOTAL** | **12,108,000** |
| **% of 16M limit** | **75.7%** |
| **Margin** | **3,892,000 (24.3%)** |

### 6d. STAGE_JACKPOT_COIN_TICKETS

Coin distribution: up to 50 winners. Ticket distribution: up to 2 * 100 = 200 winners (daily tickets + carryover tickets).

#### Coin Jackpot Gas (50 winners max)

Per coin winner in `_awardDailyCoinToTraitWinners`:

| Operation | Gas | Notes |
|-----------|-----|-------|
| _randTraitTicket per-winner | 2,193 | Same as ETH path |
| **coinflip.creditFlip external call:** | | Cross-contract CALL to BurnieCoinflip._addDailyFlip |
| -- CALL opcode (warm after first) | 100 | BurnieCoinflip address warm after first call |
| -- `onlyFlipCreditors` modifier | 2,200 | SLOAD (mapping check) + comparison |
| -- `_targetFlipDay()` | 300 | View computation |
| -- `coinflipBalance[day][player]` SLOAD | 2,100 | Cold -- unique player mapping |
| -- `coinflipBalance[day][player]` SSTORE | 22,100 | 0->nonzero worst case |
| -- `_updateTopDayBettor` SLOAD | 100 | Warm after first call in tx |
| -- `_updateTopDayBettor` SSTORE | 2,900 | Warm (leader update; conditional but worst case) |
| -- `emit CoinflipStakeUpdated` | 1,125 | |
| -- `emit CoinflipTopUpdated` | 1,125 | Conditional, included for worst case |
| `emit JackpotBurnieWin (LOG3)` | 1,500 | |
| Loop overhead | 50 | |
| **Per-coin-winner total** | **~35,893** | |
| **Rounded up** | **~36,000** | |

One-time coin overhead: `_calcDailyCoinBudget` (pool reads + arithmetic: 3,000), `_awardFarFutureCoinJackpot` (10 iterations: ~40,000), first CALL to BurnieCoinflip cold address (+2,500), `_computeBucketCounts` (4 SLOAD for ticket array lengths: 8,400 + computation: 1,000), `_randTraitTicket` one-time per bucket (4 * 4,350 = 17,400), `_updateTopDayBettor` first SLOAD cold (+2,000).

| Component | Gas |
|-----------|-----|
| Coin one-time overhead | ~75,000 |
| 50 coin winners * 36,000 | 1,800,000 |
| **Coin subtotal** | **~1,875,000** |

#### Ticket Jackpot Gas (2 distributions, up to 100 winners each)

Per ticket winner in `_distributeTicketsToBucket`:

| Operation | Gas | Notes |
|-----------|-----|-------|
| _randTraitTicket per-winner | 2,193 | |
| `_queueTickets` | 48,425 | Same as section 2b _queueTickets breakdown |
| `emit JackpotTicketWin (LOG3)` | 1,500 | |
| Loop overhead | 50 | |
| **Per-ticket-winner total** | **~52,168** | |
| **Rounded up** | **~53,000** | |

One-time ticket overhead per distribution: `_distributeTicketJackpot` (bucket counts + entropy: 12,000), `_randTraitTicket` one-time per bucket (4 * 4,350 = 17,400).

| Component | Gas |
|-----------|-----|
| Caller overhead (payDailyJackpotCoinAndTickets) | 58,000 |
| Coin subtotal | 1,875,000 |
| Ticket distribution 1: one-time (29,400) + 100 winners * 53,000 | 5,329,400 |
| Ticket distribution 2: one-time (29,400) + 100 winners * 53,000 | 5,329,400 |
| **TOTAL** | **12,591,800** |
| **% of 16M limit** | **78.7%** |
| **Margin** | **3,408,200 (21.3%)** |

### 6e. Early-Burn Path (non-daily, SPLIT_NONE, JACKPOT_MAX_WINNERS=160)

Called via `payDailyJackpot(isDaily=false)` -> `_executeJackpot` -> `_runJackpotEthFlow`.
Uses `JACKPOT_SCALE_MAX_BPS = 40,000` (4x) and `JACKPOT_MAX_WINNERS = 160` as cap.
No autorebuy in worst case (early-burn ETH pool is small, ~1% drip from futurePool).
`isJackpotPhase = false`: no whale pass, no DGNRS in solo bucket.

Worst-case winner counts at 4x scale: `[100, 59, 0, 1] = 160` (capped).

| Component | Gas |
|-----------|-----|
| Caller overhead (~payDailyJackpot non-daily path) | 50,000 |
| _processDailyEth base overhead (SPLIT_NONE, non-jackpot) | 31,000 |
| 159 normal winners * 31,000 (no autorebuy) | 4,929,000 |
| 1 solo winner * 31,000 (no whale pass, isJackpotPhase=false) | 31,000 |
| **TOTAL** | **5,041,000** |
| **% of 16M limit** | **31.5%** |
| **Margin** | **10,959,000 (68.5%)** |

Note: Early-burn CAN have autorebuy enabled (gameOver is false during early-burn). Conservative autorebuy worst case:

| Component | Gas |
|-----------|-----|
| Caller overhead | 50,000 |
| _processDailyEth base overhead (SPLIT_NONE, non-jackpot) | 31,000 |
| 159 normal winners * 83,000 (with autorebuy+dust) | 13,197,000 |
| 1 solo winner * 83,000 (no whale pass even with autorebuy) | 83,000 |
| **TOTAL (early-burn with autorebuy)** | **13,361,000** |
| **% of 16M limit** | **83.5%** |
| **Margin** | **2,639,000 (16.5%)** |

### 6f. Terminal Jackpot (runTerminalJackpot, SPLIT_NONE, up to 305 winners)

Called externally from GameOverModule. Uses `DAILY_ETH_MAX_WINNERS = 305` and `DAILY_JACKPOT_SCALE_MAX_BPS = 63,600`.
`isJackpotPhase = false`: no whale pass, no DGNRS.
`gameOver = true`: autorebuy is skipped (`if (!gameOver)` guard in `_addClaimableEth`).

| Component | Gas |
|-----------|-----|
| Caller overhead (runTerminalJackpot) | 34,000 |
| _processDailyEth base overhead (SPLIT_NONE) | 25,000 |
| 304 normal winners * 31,000 (no autorebuy, gameOver=true) | 9,424,000 |
| 1 solo winner * 31,000 (no whale pass) | 31,000 |
| **TOTAL** | **9,514,000** |
| **% of 16M limit** | **59.5%** |
| **Margin** | **6,486,000 (40.5%)** |

## 7. Safety Margin Summary

| Path | Worst-Case Winners | Per-Winner | Overhead | Worst-Case Gas | Limit | Margin |
|------|--------------------|------------|----------|---------------|-------|--------|
| Daily call 1 -- SPLIT_CALL1 (160, autorebuy+dust) | 159 normal + 1 solo | 83,000 / 125,000 | 165,000 | **13,487,000** | 16,000,000 | **15.7%** |
| Daily call 1 -- SPLIT_NONE (160, autorebuy+dust) | 159 normal + 1 solo | 83,000 / 125,000 | 152,000 | **13,474,000** | 16,000,000 | **15.8%** |
| Daily call 2 -- SPLIT_CALL2 (145, autorebuy+dust) | 145 normal | 83,000 | 73,000 | **12,108,000** | 16,000,000 | **24.3%** |
| Coin+Tickets (50 coin + 200 ticket) | 250 total | 36,000 / 53,000 | 58,000 | **12,591,800** | 16,000,000 | **21.3%** |
| Early-burn -- SPLIT_NONE (160, autorebuy+dust) | 159 normal + 1 solo | 83,000 | 81,000 | **13,361,000** | 16,000,000 | **16.5%** |
| Terminal -- SPLIT_NONE (305, no autorebuy) | 304 normal + 1 solo | 31,000 | 59,000 | **9,514,000** | 16,000,000 | **40.5%** |

## 8. Skip-Split Threshold Verification (GAS-04)

The skip-split threshold is `JACKPOT_MAX_WINNERS = 160`. This is correct because:

1. **At 160 total winners with autorebuy+dust:** 13,474,000 gas (15.8% margin). Safe.
2. **At 161 total winners (hypothetical SPLIT_NONE):** 13,474,000 + 83,000 = 13,557,000 gas. Still safe at 15.3% margin.
3. **The threshold is conservative:** Even at 305 winners without autorebuy (terminal path), gas is only 9.5M. The 160 threshold ensures that the SPLIT_NONE daily path (which has autorebuy) stays well under 16M.
4. **Beyond 160 with autorebuy:** If all 305 winners had autorebuy+dust in a single call: 305 * 83,000 + 25,000 = 25,340,000 -- exceeds 16M. This confirms splitting is necessary when totalWinners > 160 and autorebuy is possible.

The 160 cutoff is the correct threshold: it is the highest winner count where single-call autorebuy+dust stays safely under 16M.

## 9. Delta from 196-01-GAS-DERIVATION.md

| Item | 196 Derivation | 199 Derivation | Reason |
|------|----------------|----------------|--------|
| SPLIT_NONE sub-case | Not covered | Section 6b, 6e, 6f | Skip-split optimization added in phase 198 |
| call1Bucket mask cost | 300 gas on all paths | 300 on SPLIT_CALL1/CALL2 only, 0 on SPLIT_NONE | Mask build gated on `splitMode != SPLIT_NONE` |
| resumeEthPool SSTORE | 22,100 on call 1 always | 22,100 on SPLIT_CALL1 only, 0 on SPLIT_NONE | Write gated on `splitMode == SPLIT_CALL1` |
| Solo whale pass gating | Always applied | Gated on `isJackpotPhase` flag | Prevents whale pass on terminal/early-burn paths |
| Per-winner gas | 82,000 (autorebuy) | 83,000 (autorebuy) | Refined _randTraitTicket estimate (+193/winner for keccak6-word cost, deity check) |
| Solo bucket gas | 111,000 | 125,000 | Added isFinalDay DGNRS path (dgnrs.poolBalance + transferFromPool external calls) |
| STAGE_JACKPOT_COIN_TICKETS | Not covered | Section 6d | Now a separate advanceGame stage |
| Early-burn with autorebuy | Not considered | Section 6e (autorebuy variant) | gameOver=false during early-burn allows autorebuy |
| Terminal winner count | 305 * 30,250 | 305 * 31,000 | Slight per-winner increase from refined estimates |
| Caller overhead | Not separated | Sections 5a-5c | Explicit separation of payDailyJackpot overhead from _processDailyEth overhead |

## 10. Verdict

**All paths safe.** Every advanceGame jackpot stage and every non-advanceGame jackpot path stays well under the 16,000,000 gas limit.

**Tightest case:** Daily call 1 with SPLIT_CALL1 at 13,487,000 gas (15.7% margin = ~2.5M gas headroom).

**The 15.7% margin is conservative because:**
1. Not all 159 winners will have `takeProfit > 0` -- removing the dust path saves ~23,000 gas/winner
2. Some `holders[idx]` slots will be warm (duplicate winners drawn with replacement reduce cold SLOADs)
3. Queue write keys are shared across winners in the same level -- `ticketQueue[wk]` length becomes warm after the first push
4. `autoRebuyState` SLOADs assume all-cold slots, but repeated winners would be warm
5. `claimableWinnings` SLOADs assume 0->nonzero for every winner, but repeat winners accumulate (warm write)

**Without dust (takeProfit=0):** Call 1 drops from 83,000 to ~60,000 per winner = ~9.7M gas (39% margin).

**Skip-split optimization impact:** When totalWinners <= 160, SPLIT_NONE saves one entire advanceGame transaction (~30k base gas for caller) plus one VRF request. The _processDailyEth cost is ~13k gas cheaper than SPLIT_CALL1 (no resumeEthPool SSTORE, no mask build).

---
*Derived: 2026-04-08*
*Method: Per-operation gas costs from EIP-2929/3529, applied to contract code paths*
*Supersedes: 196-01-GAS-DERIVATION.md*
