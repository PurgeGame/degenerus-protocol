# Jackpot Payout Reference (Post-Split)

This document describes every jackpot type in the Degenerus Protocol after the two-call gas safety split (v24.0 milestone). A reader can look up any jackpot type and understand who wins, how much, and how payout flows from pool to recipient without reading contract source.

**Last verified against:** commit `f0dc4c99`

---

## 1. Overview

The Degenerus jackpot system distributes ETH, BURNIE coin, DGNRS tokens, whale passes, and lootbox tickets to players who hold burn tickets for winning traits. The system has 7 distinct jackpot types spanning normal gameplay, endgame, and external reward pools.

**Core mechanics:**

- **4-bucket trait-based distribution.** Each jackpot selects 4 winning traits (one per quadrant). Winners are drawn from burn ticket pools for those traits. Bucket sizes vary: base counts are [25, 15, 8, 1] (large, mid, small, solo), rotated by entropy for fairness.
- **Two-call split pattern.** Daily ETH jackpots use Call 1 (`payDailyJackpot`) for ETH distribution and Call 2 (`payDailyJackpotCoinAndTickets`) for BURNIE coin and ticket distribution. This keeps each `advanceGame` invocation under the 15M gas block limit.
- **Stage machine.** The AdvanceModule drives jackpot flow through sequential stages: `STAGE_ENTERED_JACKPOT` (7) -> `STAGE_JACKPOT_DAILY_STARTED` (11) -> `STAGE_JACKPOT_COIN_TICKETS` (9) -> `STAGE_JACKPOT_PHASE_ENDED` (10).

---

## 2. Key Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `JACKPOT_LEVEL_CAP` | 5 | Maximum daily jackpots per level (5 jackpot days) |
| `DAILY_JACKPOT_SHARES_PACKED` | 2000 bps x 4 | Equal 20% per bucket on days 1-4; solo bucket gets ETH remainder |
| `FINAL_DAY_SHARES_PACKED` | [6000, 1333, 1333, 1334] bps | Day-5 shares: 60% rotates to solo bucket via entropy |
| `DAILY_ETH_MAX_WINNERS` | 321 | Maximum total ETH winners across daily + carryover jackpots |
| `JACKPOT_MAX_WINNERS` | 300 | Maximum total winners for early-burn/lootbox path |
| `DAILY_COIN_MAX_WINNERS` | 50 | Maximum near-future BURNIE coin winners |
| `DAILY_JACKPOT_SCALE_MAX_BPS` | 66,667 | 6.667x scaling at 200+ ETH for daily path |
| `JACKPOT_SCALE_MAX_BPS` | 40,000 | 4x scaling at 200+ ETH for early-burn path |
| `MAX_BUCKET_WINNERS` | 250 | Per-bucket hard cap (safety net, fits in uint8) |
| `FAR_FUTURE_COIN_BPS` | 2500 | 25% of BURNIE coin budget to far-future winners |
| `FAR_FUTURE_COIN_SAMPLES` | 10 | Number of far-future levels sampled |
| `DAILY_CURRENT_BPS_MIN` | 600 | Minimum daily pool slice (6%) |
| `DAILY_CURRENT_BPS_MAX` | 1400 | Maximum daily pool slice (14%) |
| `PURCHASE_REWARD_JACKPOT_LOOTBOX_BPS` | 7500 | 75% of early-burn ETH to lootbox tickets |
| `FINAL_DAY_DGNRS_BPS` | 100 | 1% of DGNRS reward pool to day-5 solo winner |
| `HALF_WHALE_PASS_PRICE` | 2.25 ether | Price per half-whale-pass unit |
| `LOOTBOX_CLAIM_THRESHOLD` | 5 ether | ETH threshold for whale pass claim vs immediate tickets |
| `SMALL_LOOTBOX_THRESHOLD` | 0.5 ether | Below this: single lootbox roll; above: 2 rolls |
| `LOOTBOX_MAX_WINNERS` | 100 | Maximum winners for lootbox/ticket distributions |
| Base bucket counts | [25, 15, 8, 1] | From `JackpotBucketLib.traitBucketCounts`, rotated by entropy |

**Scaling curve:** 1x under 10 ETH, linearly to 2x by 50 ETH, linearly to max scale by 200 ETH, then capped. Solo bucket (count=1) is never scaled.

---

## 3. Daily Normal Jackpot (Days 1-4)

### Trigger

`advanceGame` -> `STAGE_JACKPOT_DAILY_STARTED` -> `payDailyJackpot(isDaily=true)`.

### Pool Source

`currentPrizePool`. Daily slice = `pool * randomBps(6-14%) / 10000`, where BPS is derived from `_dailyCurrentPoolBps(counter, randWord)`. 20% of the slice (budget / 5) is reserved for lootbox tickets and moved from `currentPrizePool` to `nextPrizePool`.

On days 2-4, an additional 0.5% of `futurePrizePool` is reserved for carryover tickets: moved to `nextPrizePool` and distributed as tickets to winners from a random source level in [lvl+1, lvl+4].

### Winner Selection

4 winning traits rolled via `_rollWinningTraits(randWord, true)` (burn-weighted, with hero override). Winners drawn from `traitBurnTicket[level][traitId]` pools. Bucket counts scaled by pool size using `JackpotBucketLib.bucketCountsForPoolCap` with base [25, 15, 8, 1], up to 6.667x at 200+ ETH, capped at `DAILY_ETH_MAX_WINNERS` (321 total).

### Share Allocation

Equal 20% per bucket (`DAILY_JACKPOT_SHARES_PACKED` = 2000 bps each). Solo bucket (1-winner bucket) gets the ETH remainder after other buckets are rounded to unit boundaries. Per-winner payout = `share / bucketCount`.

### Two-Call Split

- **Call 1** (`payDailyJackpot`): Processes all 4 buckets via `_processDailyEth`. Iterates buckets in largest-first order. Each bucket's winners receive ETH credits. Sets `dailyJackpotCoinTicketsPending = true` and stores state for Call 2.
- **Call 2** (`payDailyJackpotCoinAndTickets`, triggered on next `advanceGame`): Distributes BURNIE coin jackpot (near-future + far-future) and lootbox tickets to trait winners. Increments `jackpotCounter`.

Each call uses the same VRF word (`rngWordCurrent`), but derives independent entropy through domain-specific XOR mixing.

### Solo Bucket Payout

75% ETH + 25% whale passes (if 25% covers at least one half-pass at 2.25 ETH; else 100% ETH). Whale pass count = `(perWinner / 4) / HALF_WHALE_PASS_PRICE`. Whale pass cost is added to `futurePrizePool`. No DGNRS on non-final days.

### Normal Bucket Payout

Each winner gets `perWinner` ETH credited to `claimableWinnings`. If the winner has auto-rebuy enabled, ETH is converted to tickets via `_processAutoRebuy` instead.

### Events Emitted

- `JackpotTicketWinner` (every winner, from `_processDailyEth` at lines 1244 and 1458)
- `AutoRebuyProcessed` (winners with auto-rebuy enabled, from `_processAutoRebuy` at line 839)

---

## 4. Daily x10 / x100 Multiplied Jackpots

Controlled by `compressedJackpotFlag`:

- **x10 (flag=1):** 5 logical jackpot days compressed into 3 physical days. Days 2-3 get `counterStep=2`, doubling the BPS for that physical day (combining two logical days' payouts).
- **x100 / turbo (flag=2):** All 5 logical jackpot days in 1 physical day. Counter jumps by `JACKPOT_LEVEL_CAP` (5) on the first call.

The payout mechanics are identical to normal daily jackpots (Section 3). Only the BPS multiplier and the speed of level progression change. When `counterStep=2`, the daily BPS is doubled (`dailyBps *= 2`). When turbo, the counter immediately reaches `JACKPOT_LEVEL_CAP`, making the single call a "final day" with `dailyBps = 10000`.

---

## 5. Daily Final Day (Day 5)

### Pool Source

100% of remaining `currentPrizePool` (`dailyBps = 10000`).

### Share Allocation

`FINAL_DAY_SHARES_PACKED` = [6000, 1333, 1333, 1334] bps. The 60% share rotates to the solo bucket via entropy (`soloBucketIndex`).

### Solo Bucket Bonus

Same 75/25 ETH/whale pass split as days 1-4, PLUS the DGNRS reward. After Call 2 completes coin+ticket distribution, `awardFinalDayDgnrsReward` is called: 1% of the DGNRS reward pool (`FINAL_DAY_DGNRS_BPS=100`) is transferred to the solo bucket winner via `dgnrs.transferFromPool`.

### Pool Accounting

Full budget deducted from `currentPrizePool`. Unpaid remainder (from empty buckets) moved to `futurePrizePool`.

### Two-Call Split

Same pattern as days 1-4: Call 1 for ETH, Call 2 for coin+tickets. After Call 2, `_awardFinalDayDgnrsReward` runs, then `_endPhase()` transitions the level.

### Events Emitted

- `JackpotTicketWinner` (all ETH winners, same paths as Section 3)
- `AutoRebuyProcessed` (auto-rebuy winners)
- `dgnrs.transferFromPool` triggers a Transfer event on the DGNRS token (solo winner DGNRS reward -- no custom jackpot event)

---

## 6. Trait Jackpot (Early-Burn Path)

### Trigger

`payDailyJackpot(isDaily=false)` during purchase phase when early burns occur.

### Pool Source

1% of `futurePrizePool` (`ethDaySlice`), only on non-day-1 levels (requires `questDay > startDay` and `lvl > 1`). 75% of slice to lootbox tickets (`PURCHASE_REWARD_JACKPOT_LOOTBOX_BPS = 7500`), remaining 25% as ETH jackpot.

On day 1 of a level: `ethDaySlice = 0`, so `_executeJackpot` no-ops on empty pool.

### Winner Selection

Non-burn-weighted trait roll (`_rollWinningTraits(randWord, false)`). Bucket counts scaled up to 4x (`JACKPOT_SCALE_MAX_BPS = 40,000`) via `_runJackpotEthFlow`, with `JACKPOT_MAX_WINNERS = 300` total cap.

### Payout

Standard `_distributeJackpotEth` (single call, no two-call split). All 4 buckets processed sequentially via `_processOneBucket`. Solo bucket gets 75/25 ETH/whale pass split. Normal buckets get straight ETH.

After ETH distribution, lootbox budget is distributed via `_distributeLootboxAndTickets` with 50% ticket conversion.

### Events

- `JackpotTicketWinner` (from `_resolveTraitWinners` at lines 1406, 1439, 1458)
- `AutoRebuyProcessed` (auto-rebuy winners)

---

## 7. Early-Bird Lootbox Jackpot (Day 1 Only)

### Trigger

`_runEarlyBirdLootboxJackpot` called on jackpot day 1 (when `counter == 0`).

### Pool Source

3% of `futurePrizePool` (`reserveContribution = futurePoolLocal * 300 / 10000`).

### Winners

Up to 100 winners (`maxWinners = 100`). Uniform trait selection (not burn-weighted): each iteration picks a random `traitId` from entropy, then draws 1 winner from `traitBurnTicket[lvl]`. Each winner gets `perWinnerEth = totalBudget / 100` worth of tickets at a random level offset (0-4 from `lvl+1`).

Tickets are queued via `_queueTickets`. All budget goes to `nextPrizePool`.

### Events

No explicit jackpot event is emitted. Ticket queuing is silent (no `JackpotTicketWinner` in `_runEarlyBirdLootboxJackpot`).

---

## 8. Terminal Jackpot (Game Over, x00 Levels)

### Trigger

`runTerminalJackpot` called from GameOverModule at x00 levels.

### Pool Source

Entire pool passed in by caller (`poolWei`).

### Winner Selection

Burn-weighted traits (`_rollWinningTraits(rngWord, true)`). Bucket counts scaled with `DAILY_JACKPOT_SCALE_MAX_BPS` (66,667 = 6.667x) and `DAILY_ETH_MAX_WINNERS` (321). Single call -- no auto-rebuy at game over so gas cost per winner is lower.

### Share Allocation

`FINAL_DAY_SHARES_PACKED` (60/13/13/13 bps), same as daily final day. The 60% share rotates to solo bucket.

### Payout

`_distributeJackpotEth` (single call). All 4 buckets processed sequentially. Standard per-winner payout. Solo bucket gets 75/25 ETH/whale pass split.

### Events

- `JackpotTicketWinner` (from `_resolveTraitWinners`)
- `AutoRebuyProcessed` (auto-rebuy winners, though game is over so auto-rebuy is skipped by the `!gameOver` guard in `_addClaimableEth`)

---

## 9. Decimator Jackpot

### Trigger

`runDecimatorJackpot` called from AdvanceModule during reward jackpot settlement at level end.

### Winner Selection

Players who burned into winning subbuckets. Each denominator (2-12) has one winning subbucket selected deterministically from VRF. A player wins if their `DecEntry.subBucket` matches the winning subbucket for their denominator. Winners are not drawn at resolution time -- resolution snapshots the winning subbuckets and pool, then players claim individually.

### Payout

ETH from decimator pool. Amount = player's proportional burn share of the winning subbucket's total burn, scaled against the full pool. Formula: `amountWei = (poolWei * playerBurn) / totalBurn` (where `totalBurn` is the sum of all winning subbucket burns across all denominators). Claims processed via `_consumeDecClaim`.

If the claimer has auto-rebuy enabled, ETH is converted to tickets via the DecimatorModule's own `_processAutoRebuy`.

### Events

- `DecBurnRecorded` (at burn time, line 177)
- `TerminalDecBurnRecorded` (terminal decimator burns, line 767)
- `AutoRebuyProcessed` (decimator claim with auto-rebuy, line 400)

Note: There is no `DecimatorResolved` event at snapshot time. The snapshot is silent -- players discover results by attempting to claim.

---

## 10. BAF Jackpot

### Trigger

`runBafJackpot` called from AdvanceModule's `_consolidatePoolsAndRewardJackpots` during reward jackpot settlement.

### Pool Source

BAF pool from `DegenerusJackpots` external contract (accessed via `jackpots.runBafJackpot(poolWei, lvl, rngWord)`). The external contract determines winners and amounts; JackpotModule processes the payouts.

### Payout Structure

**Large winners** (amount >= 5% of pool):
- 50% credited as claimable ETH (via `_addClaimableEth`)
- 50% as lootbox: if lootbox portion <= `LOOTBOX_CLAIM_THRESHOLD` (5 ETH), awarded as immediate ticket rolls; if > 5 ETH, deferred to whale pass claim (via `_queueWhalePassClaimCore`)

**Small winners** (amount < 5% of pool):
- Even index (i % 2 == 0): 100% claimable ETH
- Odd index: 100% lootbox tickets (via `_awardJackpotTickets`)

All lootbox ETH stays in `futurePrizePool` (source pool). Refund amount returned by external contract is subtracted from `netSpend`.

### Events

- `AutoRebuyProcessed` (ETH winners with auto-rebuy, indirectly via `_addClaimableEth` -> `_processAutoRebuy`)
- `PlayerCredited` (remainder from whale pass rounding, via `_queueWhalePassClaimCore`)
- `RewardJackpotsSettled` (emitted by AdvanceModule after BAF + pool accounting, line 808)

Note: No dedicated BAF jackpot winner event. The BAF payout flow uses internal crediting functions without emitting `JackpotTicketWinner`.

---

## 11. Daily BURNIE Coin Jackpot

### Trigger

`payDailyCoinJackpot` called during `STAGE_JACKPOT_COIN_TICKETS` (via `payDailyJackpotCoinAndTickets`, Call 2 of the daily split).

### Pool Source

`_calcDailyCoinBudget(lvl)` -- BURNIE coin budget for this level.

### Split

- 25% to far-future (`FAR_FUTURE_COIN_BPS = 2500`)
- 75% to near-future

### Near-Future

Up to `DAILY_COIN_MAX_WINNERS` (50) trait-matched winners at a random level in [lvl, lvl+4] (selected by `_selectDailyCoinTargetLevel`). Each gets `baseAmount = coinBudget / cap`, with remainder distributed round-robin. Winners credited via `coinflip.creditFlipBatch` (batched in groups of 3).

### Far-Future

Up to `FAR_FUTURE_COIN_SAMPLES` (10) winners drawn from `ticketQueue` for random levels in [lvl+5, lvl+99]. Each gets `farBudget / foundWinners`. Credited via `coinflip.creditFlipBatch`.

### Events

- `JackpotTicketWinner` (near-future coin winners, from `_awardDailyCoinToTraitWinners` line 2213)
- `FarFutureCoinJackpotWinner` (far-future winners, from `_awardFarFutureCoinJackpot` line 2314)

---

## 12. Pool Flow Summary

| Jackpot Type | Source Pool | Payout Path | Unpaid Remainder | Pool Variables Changed |
|---|---|---|---|---|
| Daily Normal (1-4) | `currentPrizePool` | `_processDailyEth` -> `_addClaimableEth` | Stays in `currentPrizePool` (only paidEth deducted) | `currentPrizePool` -= paidEth; `nextPrizePool` += lootbox budget |
| Daily Final (5) | `currentPrizePool` (100%) | Same as days 1-4 | Unpaid -> `futurePrizePool` | `currentPrizePool` -= full budget; `futurePrizePool` += unpaid |
| Daily x10/x100 | `currentPrizePool` | Same mechanics, doubled/full BPS | Same as corresponding day type | Same as corresponding day type |
| Trait (Early-Burn) | `futurePrizePool` (1%) | `_executeJackpot` -> `_distributeJackpotEth` | Stays in `futurePrizePool` (only paid deducted) | `futurePrizePool` -= (lootboxBudget + paidEth) |
| Early-Bird Lootbox | `futurePrizePool` (3%) | Ticket queuing via `_queueTickets` | All budget -> `nextPrizePool` | `futurePrizePool` -= 3%; `nextPrizePool` += budget |
| Terminal | Caller-provided `poolWei` | `_distributeJackpotEth` | Caller handles remainder | `claimablePool` += liability delta |
| Decimator | Caller-provided `poolWei` | Deferred claims via `_consumeDecClaim` | Returned if no qualifying burns | Snapshot stored in `decClaimRounds` |
| BAF | `futurePrizePool` (via external) | Mixed ETH + lootbox | Refund returned to caller | `claimablePool` += delta; `futurePrizePool` retains lootbox portion |
| BURNIE Coin | BURNIE budget (off-chain) | `coinflip.creditFlip` / `creditFlipBatch` | None (BURNIE tokens, not ETH) | No ETH pool changes |

---

## 13. Two-Call Split Details

### Why the Split Exists

The daily jackpot distributes ETH, BURNIE coin, and lootbox tickets to potentially hundreds of winners. Processing all three in a single `advanceGame` call can exceed the 15M gas block limit, especially when auto-rebuy is active (~82K gas per auto-rebuy winner).

### Split Architecture

**Call 1: `payDailyJackpot(isDaily=true)`** (stage `STAGE_JACKPOT_DAILY_STARTED`)

- Rolls winning traits, calculates daily budget
- On day 1: runs early-bird lootbox jackpot (from `futurePrizePool`)
- Distributes all ETH via `_processDailyEth` (all 4 buckets, largest-first order)
- Calculates and packs ticket/carryover budgets into `dailyTicketBudgetsPacked`
- Sets `dailyJackpotCoinTicketsPending = true`
- Stores level and winning traits for Call 2

**Call 2: `payDailyJackpotCoinAndTickets(randWord)`** (stage `STAGE_JACKPOT_COIN_TICKETS`)

- Distributes BURNIE coin jackpot (near-future trait-matched + far-future ticketQueue)
- Distributes daily lootbox tickets to current-level trait winners
- Distributes carryover tickets (winners from source level, tickets at current level)
- Increments `jackpotCounter`
- Clears `dailyJackpotCoinTicketsPending`

### Inter-Call State

| Storage Variable | Purpose |
|---|---|
| `dailyJackpotCoinTicketsPending` | Boolean flag: true after Call 1, cleared after Call 2 |
| `lastDailyJackpotLevel` | Level when jackpot was triggered |
| `lastDailyJackpotWinningTraits` | Packed 4 winning trait IDs |
| `dailyTicketBudgetsPacked` | Packed: counterStep (8 bits), dailyTicketUnits (64 bits), carryoverTicketUnits (64 bits), carryoverSourceOffset (8 bits) |

### Stage Machine Flow

```
advanceGame:
  STAGE_ENTERED_JACKPOT (7)
    |-- if dailyJackpotCoinTicketsPending:
    |     payDailyJackpotCoinAndTickets(rngWord)
    |     if counter >= JACKPOT_LEVEL_CAP:
    |       awardFinalDayDgnrsReward -> STAGE_JACKPOT_PHASE_ENDED (10)
    |     else:
    |       -> STAGE_JACKPOT_COIN_TICKETS (9)
    |-- else:
          payDailyJackpot(isDaily=true)
          -> STAGE_JACKPOT_DAILY_STARTED (11)
```

Each call uses the same VRF word, but derives independent entropy through domain-specific XOR mixing (`randWord ^ (uint256(lvl) << 192)`, `randWord ^ (uint256(lvl) << 192) ^ COIN_JACKPOT_TAG`, etc.). This ensures deterministic but non-correlated winner selection across ETH and coin distributions.

### Economic Guarantee

Pool conservation is maintained across the split. Call 1 deducts paidEth from `currentPrizePool` and stores remaining state. Call 2 does not modify ETH pools (coin distributions use BURNIE, ticket queuing is pool-neutral). The two-call pattern is economically equivalent to a single-call execution.
