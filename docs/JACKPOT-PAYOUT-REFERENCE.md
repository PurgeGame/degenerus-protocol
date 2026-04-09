# Jackpot Payout Reference (Post-Skip-Split)

Reflects the unified `_processDailyEth` with conditional skip-split architecture.

Last verified against: `fa2b9c39` (2026-04-08)

---

## 1. Overview

The Degenerus jackpot system distributes ETH, BURNIE coin, DGNRS tokens, whale passes, and tickets across seven distinct jackpot types. All jackpots use trait-based 4-bucket distribution: four winning traits are rolled from VRF entropy, and winners are drawn from burn-ticket pools for each trait.

Key architectural patterns:

- **4-bucket trait distribution.** Every jackpot divides winners into 4 buckets based on winning traits (one per quadrant 0-63, 64-127, 128-191, 192-255). Base counts [25, 15, 8, 1] are rotated by entropy for fairness. The solo bucket (count=1) always receives the remainder share.
- **Conditional two-call split for daily ETH.** When `totalWinners <= 160` (`JACKPOT_MAX_WINNERS`), all 4 buckets process in a single call via `SPLIT_NONE`. When `totalWinners > 160`, the largest + solo buckets process in Call 1 (`SPLIT_CALL1`), mid buckets in Call 2 (`SPLIT_CALL2`).
- **Stage machine.** The AdvanceModule drives the flow via sequential stage constants: `STAGE_JACKPOT_DAILY_STARTED` (11) triggers Call 1 or single-call, `STAGE_JACKPOT_ETH_RESUME` (8) triggers Call 2 (only when `resumeEthPool != 0`), `STAGE_JACKPOT_COIN_TICKETS` (9) triggers Call 3 (coin + tickets).

---

## 2. Key Constants

| Constant | Value | Source |
|----------|-------|--------|
| `JACKPOT_LEVEL_CAP` | 5 | 5 jackpot days per level |
| `SPLIT_NONE` | 0 | All 4 buckets in one call (JackpotModule line 167) |
| `SPLIT_CALL1` | 1 | Largest + solo buckets only (JackpotModule line 169) |
| `SPLIT_CALL2` | 2 | Mid buckets only (JackpotModule line 171) |
| `DAILY_JACKPOT_SHARES_PACKED` | 2000 bps each (20/20/20/20) | Solo bucket gets the ETH remainder (effectively ~20% + rounding surplus) |
| `FINAL_DAY_SHARES_PACKED` | [6000, 1333, 1333, 1334] bps | 60% rotates to solo bucket on day 5 |
| `DAILY_ETH_MAX_WINNERS` | 305 | Max total across all buckets at max daily scale |
| `JACKPOT_MAX_WINNERS` | 160 | Skip-split threshold / purchase phase path cap |
| `DAILY_JACKPOT_SCALE_MAX_BPS` | 63,600 (6.36x) | Max scaling at 200+ ETH pool |
| `JACKPOT_SCALE_MAX_BPS` | 40,000 (4x) | Max scaling for purchase phase path |
| `MAX_BUCKET_WINNERS` | 250 | Per-bucket hard cap (safety net) |
| `DAILY_COIN_MAX_WINNERS` | 50 | Max winners per BURNIE coin jackpot |
| `FAR_FUTURE_COIN_BPS` | 2500 (25%) | Far-future share of coin budget |
| `FAR_FUTURE_COIN_SAMPLES` | 10 | Max far-future levels sampled |
| `DAILY_CURRENT_BPS_MIN` | 600 (6%) | Min daily pool slice |
| `DAILY_CURRENT_BPS_MAX` | 1400 (14%) | Max daily pool slice |
| `PURCHASE_REWARD_JACKPOT_LOOTBOX_BPS` | 7500 (75%) | Early-burn ETH to lootbox tickets |
| `FINAL_DAY_DGNRS_BPS` | 100 (1%) | DGNRS reward pool to solo winner on day 5 |
| `HALF_WHALE_PASS_PRICE` | 2.25 ether | Unit price per half-whale-pass |
| `LOOTBOX_CLAIM_THRESHOLD` | 5 ether | Above this: deferred whale pass claim |
| `LOOTBOX_MAX_WINNERS` | 100 | Max winners per lootbox/ticket distribution |
| Base bucket counts | [25, 15, 8, 1] | `JackpotBucketLib.traitBucketCounts` |
| Max scaled counts (daily, 6.36x) | [159, 95, 50, 1] = 305 | At 200+ ETH pool |
| Max scaled counts (purchase phase, 4x) | [100, 60, 32, 1] -> capped to 160 | `capBucketCounts` proportionally reduces non-solo to fit 159 |

---

## 3. Daily Normal Jackpot (Days 1-4)

### Trigger

`advanceGame` -> `STAGE_JACKPOT_DAILY_STARTED` (11) -> `payDailyJackpot(isJackpotPhase=true)`.

### Pool Source

`currentPrizePool`. Daily slice = pool * randomBps(6%-14%) / 10,000. 20% of the slice (1/5) is reserved for lootbox tickets and moved to `nextPrizePool`.

### Winner Selection

4 winning traits rolled via `_rollWinningTraits` (burn-weighted). Winners drawn from `traitBurnTicket` pools at the current level. Bucket counts scaled by pool size:

- Base: [25, 15, 8, 1] (rotated by entropy)
- Scaling: 1x under 10 ETH, linearly to 2x at 50 ETH, linearly to 6.36x at 200+ ETH
- Capped at `DAILY_ETH_MAX_WINNERS` = 305 total

### Share Allocation

Equal 20% per bucket (`DAILY_JACKPOT_SHARES_PACKED` = 2000 bps each). The solo bucket (count=1) receives the ETH remainder after other buckets are rounded to unit boundaries. Per-winner payout = share / bucketCount.

### Split Behavior

The split mode depends on total scaled winners after bucket count computation:

**SPLIT_NONE path** (`totalWinners <= 160`):

`splitMode = SPLIT_NONE` -> `_processDailyEth` processes all 4 buckets in a single call. No `resumeEthPool` write. Call 3 (coin + tickets) follows immediately on the next `advanceGame`.

**SPLIT_CALL1 + SPLIT_CALL2 path** (`totalWinners > 160`):

| Call | Stage | splitMode | Buckets Processed | Max Winners |
|------|-------|-----------|-------------------|-------------|
| 1 | `STAGE_JACKPOT_DAILY_STARTED` (11) | `SPLIT_CALL1` | Largest + Solo | 160 |
| 2 | `STAGE_JACKPOT_ETH_RESUME` (8) | `SPLIT_CALL2` | Two mid buckets | 145 |
| 3 | `STAGE_JACKPOT_COIN_TICKETS` (9) | N/A | Coin + Tickets | N/A (separate) |

Call 1 stores `ethPool` as `uint128` in `resumeEthPool`. Call 2 reads `resumeEthPool`, processes the two mid buckets, and clears `resumeEthPool` to zero. Both paths use `bucketOrderLargestFirst` iteration. Each call uses its own VRF word (entropy independence).

### Solo Bucket Payout

75% ETH + 25% whale passes (if the 25% covers at least one half-pass at 2.25 ETH; otherwise 100% ETH). No DGNRS on non-final days.

### Normal Bucket Payout

Each winner gets `perWinner` ETH. Auto-rebuy fires if enabled (ETH converted to tickets via `_addClaimableEth` -> `_processAutoRebuy`).

### Events Emitted

- `JackpotEthWin` -- every winner (normal and solo)
- `JackpotWhalePassWin` -- solo bucket winner when whale passes are awarded

---

## 4. Daily x10 / x100 Multiplied Jackpots

The `compressedJackpotFlag` controls jackpot compression:

| Flag | Mode | Physical Days | Behavior |
|------|------|---------------|----------|
| 0 | Normal | 5 | 1 logical day per physical day |
| 1 | x10 (compressed) | 3 | Days 2-3 get `counterStep=2`, doubling the BPS |
| 2 | x100 (turbo) | 1 | Counter jumps by `JACKPOT_LEVEL_CAP` (5) on first call |

The payout mechanics are identical to daily normal -- only the BPS multiplier and progression speed change. Same split behavior applies (SPLIT_NONE or SPLIT_CALL1+SPLIT_CALL2 depending on totalWinners). Turbo mode fires when the prize target is met within the first day or two of purchase phase (`lastPurchaseDay` set early).

---

## 5. Daily Final Day (Day 5)

### Pool Source

100% of remaining `currentPrizePool` (`dailyBps = 10,000`).

### Share Allocation

`FINAL_DAY_SHARES_PACKED` = [6000, 1333, 1333, 1334] bps. The 60% share rotates to the solo bucket via entropy. The remaining three buckets each receive ~13.3%.

### Solo Bucket Bonus

Same 75/25 ETH/whale-pass split as normal days, plus 1% of the DGNRS reward pool (`FINAL_DAY_DGNRS_BPS` = 100) paid via `dgnrs.transferFromPool(Pool.Reward, ...)`.

### Pool Accounting

Full budget is deducted from `currentPrizePool`. Unpaid remainder (from empty buckets with no eligible ticket holders) is moved to `futurePrizePool`.

### Split Behavior

Same conditional split as days 1-4 (SPLIT_NONE when `totalWinners <= 160`, two-call split otherwise). The `isFinalDay` flag is set based on `jackpotCounter + counterStep >= JACKPOT_LEVEL_CAP`.

### Events Emitted

- `JackpotEthWin` -- every winner
- `JackpotWhalePassWin` -- solo winner (if whale passes awarded)
- `JackpotDgnrsWin` -- solo winner (DGNRS reward, final day only)

---

## 6. Trait Jackpot (Early-Burn Path)

### Trigger

`payDailyJackpot(isJackpotPhase=false)` during purchase phase when burns occur.

### Pool Source

1% of `futurePrizePool` (`ethDaySlice`), only on non-day-1 levels (requires `questDay > purchaseStartDay && lvl > 1`). 75% of the slice goes to lootbox tickets (`PURCHASE_REWARD_JACKPOT_LOOTBOX_BPS` = 7500), remaining 25% distributed as ETH.

### Winner Selection

Non-burn-weighted trait roll (`_rollWinningTraits(randWord, false)` uses `JackpotBucketLib.getRandomTraits`). Bucket counts scaled up to 4x (`JACKPOT_SCALE_MAX_BPS` = 40,000) with `JACKPOT_MAX_WINNERS` = 160 total cap via `scaleTraitBucketCountsWithCap`.

### Payout

`_runJackpotEthFlow` -> `_processDailyEth(splitMode=SPLIT_NONE, isJackpotPhase=false)`. All 4 buckets processed in a single call. Winner counts capped at `JACKPOT_MAX_WINNERS` = 160 via `scaleTraitBucketCountsWithCap`. No whale pass, no DGNRS.

### Events Emitted

- `JackpotEthWin` -- every winner

---

## 7. Early-Bird Lootbox Jackpot (Day 1 Only)

### Trigger

`_runEarlyBirdLootboxJackpot` called on jackpot day 1 (`isEarlyBirdDay = counter == 0`).

### Pool Source

3% of `futurePrizePool`.

### Winners

100 winners (`maxWinners = 100`), uniform trait selection (not burn-weighted). Each winner gets `perWinnerEth = totalBudget / 100` worth of tickets at a random level offset (0-4 from current, based on `levelPrices`).

### Events Emitted

- `JackpotTicketWin` -- each winner

---

## 8. Terminal Jackpot (Game Over, x00 Levels)

### Trigger

`runTerminalJackpot` called from GameOverModule at x00 levels.

### Pool Source

Entire pool passed in by caller (`poolWei`).

### Winner Selection

Burn-weighted traits (`_rollWinningTraits(rngWord, true)`). Bucket counts scaled with `DAILY_JACKPOT_SCALE_MAX_BPS` (6.36x) and `DAILY_ETH_MAX_WINNERS` = 305 via `bucketCountsForPoolCap` (not `scaleTraitBucketCountsWithCap`).

### Share Allocation

`FINAL_DAY_SHARES_PACKED` (60/13/13/13).

### Payout

`runTerminalJackpot` -> `_processDailyEth(splitMode=SPLIT_NONE, isJackpotPhase=false)`. All 4 buckets processed in a single call. Uses `DAILY_ETH_MAX_WINNERS` = 305 cap and `bucketCountsForPoolCap`. No whale pass, no DGNRS. No autorebuy (`gameOver=true` prevents it).

### Events Emitted

- `JackpotEthWin` -- every winner

---

## 9. Decimator Jackpot

### Trigger

`DecimatorModule.resolveDecimator` called at level end to snapshot winning subbuckets.

### Winner Selection

Players who burned into winning subbuckets (bucket denominators 2-12). One winning subbucket per denominator, selected deterministically from VRF. Each player's burn amount determines their pro-rata share of the pool.

### Payout

Deferred claim model. The pool (`poolWei`) is locked at resolution time. Players call `claimDecJackpot` to collect their pro-rata ETH based on `burn / totalBurn * poolWei`. Auto-rebuy is available during claim (via `_processAutoRebuy` in DecimatorModule).

### Events Emitted

- `DecimatorResolved` -- resolution (winning subbuckets snapshotted)
- `DecBurnRecorded` -- burn recording (every decimator burn)
- `TerminalDecBurnRecorded` -- terminal burns (time-weighted at game over)
- `AutoRebuyProcessed` -- when a claimer's ETH is auto-converted to tickets

---

## 10. BAF Jackpot

### Trigger

`runBafJackpot` called from AdvanceModule during reward jackpot settlement (`_settleRewardJackpots`).

### Pool Source

BAF pool from external `DegenerusJackpots` contract. Up to 107 winners (1 top BAF + 1 top flip + 1 pick + 4 far-future x2 + 50 + 50 scatter).

### Payout Structure

| Winner Size | Condition | Reward |
|-------------|-----------|--------|
| Large | >= 5% of pool | 50% ETH (claimable) + 50% lootbox |
| Small (even index) | < 5% of pool | 100% ETH (claimable) |
| Small (odd index) | < 5% of pool | 100% lootbox (tickets) |

**Lootbox tiering for large winners:**
- Lootbox portion <= 5 ETH (`LOOTBOX_CLAIM_THRESHOLD`): immediate 2-roll tickets via `_awardJackpotTickets`
- Lootbox portion > 5 ETH: deferred whale pass claim via `_queueWhalePassClaimCore`

### Events Emitted

- `JackpotEthWin` -- ETH portions (large winners 50% + small even-index 100%)
- `JackpotTicketWin` -- immediate ticket awards (large small-lootbox + small odd-index)
- `JackpotWhalePassWin` -- large winners with deferred lootbox (> 5 ETH)

---

## 11. Daily BURNIE Coin Jackpot

### Trigger

`payDailyCoinJackpot` called during `STAGE_JACKPOT_COIN_TICKETS` (9), or inline from `payDailyJackpotCoinAndTickets` during the daily flow.

### Pool Source

`_calcDailyCoinBudget(lvl)` -- BURNIE coin budget for this level (0.5% of prize pool target in BURNIE).

### Split

25% to far-future (`FAR_FUTURE_COIN_BPS` = 2500), 75% to near-future.

### Near-Future Distribution

Up to `DAILY_COIN_MAX_WINNERS` = 50 trait-matched winners at a random level in [lvl, lvl+4]. Each gets `baseAmount = coinBudget / cap` (with modular extra distribution for remainder). Payout via `coinflip.creditFlip`.

### Far-Future Distribution

Up to `FAR_FUTURE_COIN_SAMPLES` = 10 winners drawn from `ticketQueue` for levels 5-99 ahead of current. One winner per sampled level. Payout split evenly via `coinflip.creditFlipBatch`.

### Events Emitted

- `JackpotBurnieWin` -- near-future winners
- `FarFutureCoinJackpotWinner` -- far-future winners

---

## 12. Pool Flow Summary

| Jackpot Type | Source Pool | Payout Path | Unpaid Remainder | Pool Variables Changed |
|--------------|------------|-------------|------------------|----------------------|
| Daily Normal (1-4) | `currentPrizePool` | `claimableWinnings` (ETH), `whalePassClaims` (solo) | stays in `currentPrizePool` | `currentPrizePool` -=, `claimablePool` +=, `nextPrizePool` += (lootbox), `futurePrizePool` += (whale pass cost) |
| Daily Final (5) | `currentPrizePool` (100%) | same as above + DGNRS transfer | -> `futurePrizePool` | `currentPrizePool` -=, `futurePrizePool` += (unpaid + whale pass) |
| Trait / Early-Burn | `futurePrizePool` (1%) | `claimableWinnings` | stays in `futurePrizePool` (deferred deduction) | `futurePrizePool` -= (paidEth + lootbox) |
| Early-Bird Lootbox | `futurePrizePool` (3%) | tickets via `_queueTickets` | stays in `nextPrizePool` | `futurePrizePool` -=, `nextPrizePool` += |
| Terminal | caller-provided `poolWei` | `claimableWinnings` | returned to caller | `claimablePool` += |
| Decimator | decimator pool | deferred claim (`claimDecJackpot`) | held in `decClaimRounds` | `claimablePool` += (at claim time) |
| BAF | `futurePrizePool` (via DegenerusJackpots) | `claimableWinnings` + tickets/whale pass | stays in `futurePrizePool` | `futurePrizePool` -= claimableDelta only |
| BURNIE Coin | BURNIE budget | `coinflip.creditFlip` | not applicable (coin, not ETH) | none (external BURNIE contract) |

---

## 13. Conditional Split Details

### Why the Split Exists

At maximum pool scale (200+ ETH), daily jackpots produce up to 305 ETH winners. With autorebuy enabled, each winner costs ~83,000 gas. Processing all 305 in one transaction would require ~25.3M gas, exceeding the 16M block gas limit.

### Skip-Split Optimization

When `totalWinners <= JACKPOT_MAX_WINNERS` (160), all 4 buckets fit in a single `_processDailyEth` call using `SPLIT_NONE`. This avoids a second VRF request and `advanceGame` call. The split-mode decision is made in `payDailyJackpot` after bucket count scaling:

```
totalWinners = sum(bucketCounts[0..3])
splitMode = (totalWinners <= 160) ? SPLIT_NONE : SPLIT_CALL1
```

Non-daily callers (purchase phase via `_runJackpotEthFlow`, terminal via `runTerminalJackpot`) always use `SPLIT_NONE` because their winner counts are capped at single-call-safe levels.

### Two-Call Split Architecture

When `totalWinners > 160`, `SPLIT_CALL1` processes the largest + solo buckets in Call 1, and `SPLIT_CALL2` processes the two mid buckets in Call 2:

```
advanceGame call 1 (STAGE_JACKPOT_DAILY_STARTED = 11)
  -> payDailyJackpot(isJackpotPhase=true)
     -> _processDailyEth(splitMode=SPLIT_CALL1)
        -> processes largest bucket + solo bucket
        -> stores ethPool as uint128 in resumeEthPool
        -> sets dailyJackpotCoinTicketsPending = true

advanceGame call 2 (STAGE_JACKPOT_ETH_RESUME = 8)
  -> payDailyJackpot(isJackpotPhase=true)
     -> detects resumeEthPool != 0
     -> _resumeDailyEth
        -> _processDailyEth(splitMode=SPLIT_CALL2)
           -> reads ethPool from resumeEthPool
           -> processes 2 mid buckets
           -> clears resumeEthPool to 0

advanceGame call 3 (STAGE_JACKPOT_COIN_TICKETS = 9)
  -> payDailyJackpotCoinAndTickets
     -> coin jackpot (BURNIE)
     -> ticket distribution
     -> increments jackpotCounter
     -> clears dailyJackpotCoinTicketsPending
```

### Bucket Assignment

The `call1Bucket` mask determines which buckets go to Call 1 vs Call 2:

- `bucketOrderLargestFirst` sorts buckets by winner count (descending)
- Call 1: `order[0]` (largest) + `soloBucketIndex` (remainder recipient)
- Edge case: if the largest bucket IS the solo bucket, Call 1 takes `order[0]` + `order[1]` instead
- Call 2: the two remaining buckets

At max scale [159, 95, 50, 1]:
- Call 1: 159 (largest) + 1 (solo) = **160 winners**
- Call 2: 95 + 50 = **145 winners**

### Inter-Call State

`resumeEthPool` (`uint128` in storage) stores the original `ethPool` value between calls:
- Non-zero value = resume pending (Call 2 needed)
- Zero = no pending resume (Call 1 complete or no daily jackpot)
- Call 2 reconstructs bucket counts, shares, and traits from stored state (`lastDailyJackpotWinningTraits`, `dailyTicketBudgetsPacked`)
- `SPLIT_NONE` never reads or writes `resumeEthPool`

### Entropy Independence

Each call uses a fresh VRF word (new `advanceGame` call = new `rngWordCurrent`). This means Call 1 and Call 2 have different entropy, producing different winner selections within the same bucket structure. Economic guarantees (pool conservation) are maintained because bucket sizes and share allocations are deterministic from the stored pool value.

### isJackpotPhase Gating

The `isJackpotPhase` parameter controls whale pass and DGNRS awards:

- `isJackpotPhase=true` (daily jackpot path): Solo bucket winner receives 75% ETH + 25% whale passes. On final day, also receives 1% DGNRS reward pool.
- `isJackpotPhase=false` (purchase phase, terminal): Solo bucket winner receives 100% ETH via `_payNormalBucket`. No whale pass, no DGNRS.

The parameter is a compile-time literal at every call site: `true` in `payDailyJackpot` and `_resumeDailyEth`, `false` in `_runJackpotEthFlow` and `runTerminalJackpot`.

### Gas Safety Margins

| Path | Max Winners | Worst-Case Gas | Block Limit | Margin |
|------|-------------|----------------|-------------|--------|
| Skip-split daily (SPLIT_NONE, autorebuy) | 160 (159+1) | 13,474,000 | 16,000,000 | 15.8% |
| Call 1 (SPLIT_CALL1, autorebuy) | 160 (159+1) | 13,487,000 | 16,000,000 | 15.7% |
| Call 2 (SPLIT_CALL2, autorebuy) | 145 | 12,108,000 | 16,000,000 | 24.3% |
| Early-burn (SPLIT_NONE, autorebuy) | 160 (159+1) | 13,361,000 | 16,000,000 | 16.5% |
| Terminal (SPLIT_NONE, no autorebuy) | 305 (304+1) | 9,514,000 | 16,000,000 | 40.5% |

Terminal has no autorebuy (`gameOver=true`), so per-winner cost is ~31,000 not ~83,000.

Non-daily callers (purchase phase, terminal) always use `SPLIT_NONE` because their winner counts are capped at single-call-safe levels.
