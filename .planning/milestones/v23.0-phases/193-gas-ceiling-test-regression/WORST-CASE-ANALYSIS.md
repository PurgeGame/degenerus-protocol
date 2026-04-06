# Worst-Case advanceGame Gas Analysis

## Theoretical Worst Case: payDailyJackpot (Final Day, Max Winners, Full Autorebuy)

### Scenario Construction

| Parameter | Value | Source |
|-----------|-------|--------|
| Path | `payDailyJackpot(isDaily=true)` | Final physical day of jackpot phase |
| Pool size | ≥ 200 ETH in currentPrizePool | Triggers max scaling |
| dailyBps | 10,000 (100%) | `isFinalPhysicalDay = true` |
| Scale factor | 6.667x (`DAILY_JACKPOT_SCALE_MAX_BPS = 66,667`) | At ≥200 ETH |
| Base winners | [25, 15, 8, 1] = 49 | `traitBucketCounts()` |
| Scaled winners | [166, 100, 53, 1] = 320 | Capped by `DAILY_ETH_MAX_WINNERS = 321` |
| All unique players | 321 different addresses | Every SLOAD/SSTORE is cold |
| All autorebuy enabled | 321 `_processAutoRebuy` calls | Maximum write path |

### Per-Winner Storage Costs (Cold, New Player)

| # | Operation | Gas | Notes |
|---|-----------|-----|-------|
| 1 | `autoRebuyState[player]` SLOAD | 2,100 | Cold mapping read |
| 2 | `ticketsOwedPacked[wk][player]` SLOAD | 2,100 | Cold mapping read |
| 3 | `ticketsOwedPacked[wk][player]` SSTORE 0→non-zero | 20,000 | Create new entry |
| 4 | `ticketQueue[wk]` new element SSTORE | 22,100 | Cold slot + create |
| 5 | `ticketQueue[wk]` length SSTORE | 2,900 | Warm modify (increment) |
| 6 | `prizePoolsPacked` SLOAD + SSTORE | 3,000 | Warm (shared across winners) |
| 7 | `claimableWinnings[player]` SLOAD | 2,100 | Cold mapping read |
| 8 | `claimableWinnings[player]` SSTORE 0→non-zero | 20,000 | Create new entry |
| 9 | `claimablePool` SSTORE | 100 | Warm modify (shared) |
| 10 | JackpotEthWin event (3 indexed) | 1,525 | 3×375 topic + data |
| 11 | PlayerCredited event (2 indexed) | 575 | 2×375 topic + data |
| 12 | Computation + memory | ~3,000 | _calcAutoRebuy, entropy, etc. |
| | **Per-winner total** | **~79,500** | |

### Total Estimate

| Component | Gas |
|-----------|-----|
| 321 winners × ~79,500 per winner | ~25,520,000 |
| `_randTraitTicket` × 4 buckets | ~40,000 |
| `bucketCountsForPoolCap` + share math | ~5,000 |
| Pool arithmetic + slot 0 reads | ~10,000 |
| Base tx overhead | ~21,000 |
| **Total estimate** | **~25,596,000** |

### Risk Assessment

| Threshold | Value | Status |
|-----------|-------|--------|
| Hard limit (block gas) | 30,000,000 | Exceeds 85% |
| User limit | 16,000,000 | **EXCEEDS BY 60%** |
| 1.5x margin target | 20,000,000 | **EXCEEDS BY 28%** |

### What Needs Testing

Build a Hardhat test that constructs:
1. 321 unique signers with autorebuy enabled
2. All signers buy tickets with trait distribution covering all 4 buckets
3. Drive game to jackpot phase with ≥200 ETH in currentPrizePool
4. Advance to final physical day
5. Call `advanceGame()` and measure gasUsed

This will give the REAL number to compare against the theoretical estimate.

### Potential Mitigations (For Discussion)

1. **Lower `DAILY_ETH_MAX_WINNERS`** — e.g., from 321 to ~150 (fits under 16M)
2. **Batch winner processing across multiple advanceGame calls** — like ticket processing
3. **Skip autorebuy during jackpot distribution** — process rebuys in a separate call
4. **Pack more winner data per SSTORE** — reduce cold writes
5. **Gas circuit breaker** — `gasleft()` check in the winner loop, pause and resume

### Note on Existing Benchmark

The existing AdvanceGameGas.test.js peak of 6,275,799 gas (Phase Transition, stage=2) measures a DIFFERENT code path (`_consolidatePoolsAndRewardJackpots` → `runBafJackpot`). That path processes BAF winners (far fewer than 321). The daily jackpot path with max winners was never benchmarked.
