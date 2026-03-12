# Phase 7: Jackpot & Distribution Mechanics - Research

**Researched:** 2026-03-12
**Domain:** Solidity smart contract analysis -- jackpot distribution, ETH/BURNIE payouts, BAF/Decimator transition mechanics
**Confidence:** HIGH

## Summary

Phase 7 documents all distribution flows in the Degenerus protocol: purchase-phase daily drips, jackpot-phase 5-day draws, and transition jackpots (BAF/Decimator). The core logic lives in three contract modules: `DegenerusGameJackpotModule.sol` (2810 lines -- daily jackpots, trait bucket distribution, coin jackpots, ticket batch processing), `DegenerusGameEndgameModule.sol` (522 lines -- BAF execution, reward jackpot dispatch), and `DegenerusGameDecimatorModule.sol` (754 lines -- decimator burn tracking, jackpot resolution, claim mechanics).

The distribution system operates in two distinct phases that alternate per level: a **purchase phase** (daily early-burn ETH drip from future pool + BURNIE jackpots) and a **jackpot phase** (5-day draw sequence distributing currentPrizePool). Transition jackpots (BAF and Decimator) fire at specific level milestones during the jackpot-to-purchase transition, funded by the future pool. All nine JACK requirements map cleanly to specific contract functions with exact constants identified.

**Primary recommendation:** Structure the phase into 3 plans: (1) purchase-phase daily drip + BURNIE jackpots, (2) jackpot-phase 5-day draw mechanics including trait buckets and carryover, (3) BAF and Decimator transition mechanics.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| JACK-01 | Daily purchase-phase future pool drip (ETH and tickets) | `payDailyJackpot(isDaily=false)` in JackpotModule lines 613-671. 1% future pool daily drip, 75% lootbox conversion (PURCHASE_REWARD_JACKPOT_LOOTBOX_BPS=7500) |
| JACK-02 | Daily purchase-phase BURNIE jackpots | `payDailyCoinJackpot()` in JackpotModule lines 2390-2435 and `_calcDailyCoinBudget()` line 2678. Budget = 0.5% of prize pool target in BURNIE equivalent |
| JACK-03 | 5-day jackpot-phase draw mechanics | `payDailyJackpot(isDaily=true)` in JackpotModule lines 333-611. `_dailyCurrentPoolBps()` line 2687. Days 1-4: 6-14% random, Day 5: 100% |
| JACK-04 | Trait bucket distribution and winner selection | `_distributeJackpotEth()` line 1530, `_randTraitTicket()` line 2264, `JackpotBucketLib`, DAILY_JACKPOT_SHARES_PACKED (equal 20% x4), FINAL_DAY_SHARES_PACKED (60/13/13/13) |
| JACK-05 | Carryover ETH and compressed jackpot | Carryover: Phase 1 of daily jackpot (lines 554-610), 1% future pool. Compressed: `compressedJackpotFlag` when level reached in <=2 days, counterStep=2, dailyBps*=2 |
| JACK-06 | Lootbox-to-jackpot conversion ratios | DAILY_REWARD_JACKPOT_LOOTBOX_BPS=5000 (50% for jackpot-phase daily), PURCHASE_REWARD_JACKPOT_LOOTBOX_BPS=7500 (75% for purchase-phase) |
| JACK-07 | BURNIE jackpot-phase parallel distribution and far-future | `payDailyJackpotCoinAndTickets()` line 685. 75% near-future (trait-matched, lvl to lvl+4), 25% far-future (ticketQueue, lvl+5 to lvl+99). Budget from `_calcDailyCoinBudget` |
| JACK-08 | BAF mechanics | `runRewardJackpots()` in EndgameModule line 138. Every 10 levels: 10% future pool; level 50: 25%; x00: 20%. Lootbox split: large winners 50/50 ETH/lootbox, small alternating |
| JACK-09 | Decimator mechanics | `runDecimatorJackpot()` in DecimatorModule line 297. Levels x5 (not x95): 10% future; x00: 30% future. Bucket system 2-12 denominators, subbucket-based winner selection, 50/50 claim split |
</phase_requirements>

## Contract Architecture for Phase 7

### Source Files and Line References

| Module | File | Lines | Purpose |
|--------|------|-------|---------|
| JackpotModule | `contracts/modules/DegenerusGameJackpotModule.sol` | 2810 | Daily jackpots (purchase + jackpot phase), trait bucket distribution, coin jackpots, ticket batch processing, pool consolidation |
| AdvanceModule | `contracts/modules/DegenerusGameAdvanceModule.sol` | 1331 | Orchestrates advanceGame flow, calls jackpot/endgame delegates, manages phase transitions |
| EndgameModule | `contracts/modules/DegenerusGameEndgameModule.sol` | 522 | BAF jackpot execution, decimator dispatch, reward jackpot routing |
| DecimatorModule | `contracts/modules/DegenerusGameDecimatorModule.sol` | 754 | Decimator burn tracking, jackpot resolution, claim mechanics |
| PayoutUtils | `contracts/modules/DegenerusGamePayoutUtils.sol` | ~100 | Base class with HALF_WHALE_PASS_PRICE, LOOTBOX_CLAIM_THRESHOLD, whale pass queueing |
| JackpotBucketLib | `contracts/libraries/JackpotBucketLib.sol` | -- | Trait bucket sizing, share calculations, winner count scaling |

### Key Constants (Verified Against Source)

| Constant | Value | Location | Purpose |
|----------|-------|----------|---------|
| JACKPOT_LEVEL_CAP | 5 | JackpotModule:105 | Maximum daily jackpots per level |
| DAILY_CURRENT_BPS_MIN | 600 (6%) | JackpotModule:143 | Min daily pool slice |
| DAILY_CURRENT_BPS_MAX | 1400 (14%) | JackpotModule:144 | Max daily pool slice |
| FINAL_DAY_SHARES_PACKED | 6000/1333/1333/1334 | JackpotModule:113-117 | Day-5 trait bucket shares (60/13/13/13) |
| DAILY_JACKPOT_SHARES_PACKED | 2000/2000/2000/2000 | JackpotModule:121-122 | Days 1-4 trait bucket shares (20% each, remaining 20% to solo bucket via remainder) |
| DAILY_REWARD_JACKPOT_LOOTBOX_BPS | 5000 (50%) | JackpotModule:179 | Jackpot-phase daily: 50% of carryover budget to lootbox |
| PURCHASE_REWARD_JACKPOT_LOOTBOX_BPS | 7500 (75%) | JackpotModule:182 | Purchase-phase daily: 75% of ETH drip to lootbox tickets |
| FAR_FUTURE_COIN_BPS | 2500 (25%) | JackpotModule:209 | BURNIE budget share for far-future holders |
| FAR_FUTURE_COIN_SAMPLES | 10 | JackpotModule:212 | Max levels sampled for far-future BURNIE |
| DAILY_COIN_MAX_WINNERS | 50 | JackpotModule:203 | Max winners per coin jackpot draw |
| DAILY_ETH_MAX_WINNERS | 321 | JackpotModule:196 | Max total ETH winners across daily + carryover |
| DAILY_CARRYOVER_MIN_WINNERS | 20 | JackpotModule:200 | Min carryover winners when carryover is active |
| DAILY_CARRYOVER_MAX_OFFSET | 5 | JackpotModule:140 | Max forward offset for carryover source |
| JACKPOT_MAX_WINNERS | 300 | JackpotModule:193 | Max winners per non-daily jackpot payout |
| MAX_BUCKET_WINNERS | 250 | JackpotModule:186 | Max winners per single trait bucket |
| LOOTBOX_MAX_WINNERS | 100 | JackpotModule:222 | Max winners for lootbox distributions |
| FINAL_DAY_DGNRS_BPS | 100 (1%) | JackpotModule:176 | DGNRS reward pool paid to day-5 solo winner |
| HALF_WHALE_PASS_PRICE | 2.175 ether | PayoutUtils:17-18 | Half-pass unit price for whale pass conversion |
| LOOTBOX_CLAIM_THRESHOLD | 5 ether | DegenerusGameStorage:132-133 | Threshold for deferred whale pass claims |
| DECIMATOR_MULTIPLIER_CAP | 200 * 1000 ether | DecimatorModule:100 | 200,000 BURNIE multiplier cap |
| DECIMATOR_MAX_DENOM | 12 | DecimatorModule:103 | Maximum bucket denominator (2-12) |
| AFFILIATE_POOL_REWARD_BPS | 100 (1%) | EndgameModule:96 | DGNRS reward for top affiliate per level |

## Distribution Flow Architecture

### Overall Flow Diagram

```
PURCHASE PHASE (each day):
  advanceGame()
    -> payDailyJackpot(isDaily=false)    [ETH drip from future pool]
    -> _payDailyCoinJackpot()             [BURNIE jackpot]
    -> check nextPrizePool >= target      [level advancement trigger]

JACKPOT PHASE (5 days):
  Day 1:
    -> payDailyJackpot(isDaily=true)      [6-14% of currentPrizePool]
       -> _runEarlyBirdLootboxJackpot()   [3% of future pool -> tickets]
    -> payDailyJackpotCoinAndTickets()    [BURNIE + ticket distribution]

  Days 2-4:
    -> payDailyJackpot(isDaily=true)      [6-14% of currentPrizePool]
       -> Carryover: 1% future pool to next-level winners
    -> payDailyJackpotCoinAndTickets()    [BURNIE + ticket distribution]

  Day 5:
    -> payDailyJackpot(isDaily=true)      [100% of remaining currentPrizePool]
    -> payDailyJackpotCoinAndTickets()    [BURNIE + ticket distribution]
    -> _awardFinalDayDgnrsReward()        [1% DGNRS reward pool to solo bucket winner]
    -> _runRewardJackpots()               [BAF + Decimator transition jackpots]
    -> _endPhase()                        [reset counters, begin new level]
```

### JACK-01: Purchase-Phase Daily ETH Drip

**Function:** `payDailyJackpot(isDaily=false)` -- JackpotModule lines 613-671

**Trigger conditions:**
- Fires every day during purchase phase (not day 1 of level, not level 0-1)
- `isEthDay = daysSince > 0 && lvl > 1` (JackpotModule:628)

**ETH drip formula:**
```solidity
uint256 poolBps = 100;  // 1% daily drip from futurePool
ethDaySlice = (_getFuturePrizePool() * poolBps) / 10_000;
_setFuturePrizePool(_getFuturePrizePool() - ethDaySlice);  // upfront deduction
```

**Lootbox conversion (75%):**
```solidity
lootboxBudget = (ethPool * PURCHASE_REWARD_JACKPOT_LOOTBOX_BPS) / 10_000;
// PURCHASE_REWARD_JACKPOT_LOOTBOX_BPS = 7500 (75%)
// Remaining 25% distributed as ETH to trait-matched winners
```

**Ticket conversion flow:**
```solidity
_distributeLootboxAndTickets(lvl, winningTraitsPacked, lootboxBudget, randWord, 5_000);
// ticketConversionBps = 5000 (50% of lootbox budget determines ticket count)
// Full lootbox budget goes to nextPrizePool
// Ticket units = (lootboxBudget * 5000 / 10000 * 4) / ticketPrice
```

### JACK-02: Purchase-Phase BURNIE Jackpots

**Functions:**
- `payDailyCoinJackpot(lvl, randWord)` -- JackpotModule:2390
- `_payDailyCoinJackpot()` (wrapper) -- AdvanceModule:569

**Budget formula:**
```solidity
function _calcDailyCoinBudget(uint24 lvl) private view returns (uint256) {
    return (levelPrizePool[lvl - 1] * PRICE_COIN_UNIT) / (priceWei * 200);
    // = 0.5% of prize pool target, denominated in BURNIE
    // PRICE_COIN_UNIT = 1000 ether
}
```

**Split:**
- 25% far-future (FAR_FUTURE_COIN_BPS = 2500) -> `_awardFarFutureCoinJackpot()`
- 75% near-future -> `_awardDailyCoinToTraitWinners()`

**Near-future (75%):**
- Target level selected randomly from [lvl, lvl+4] that has winning-trait tickets
- Up to DAILY_COIN_MAX_WINNERS (50) winners from trait buckets
- Paid as coinflip credits via `coin.creditFlipBatch()`

**Far-future (25%):**
- Samples up to FAR_FUTURE_COIN_SAMPLES (10) random levels in [lvl+5, lvl+99]
- 1 winner per level from `ticketQueue` (traits not yet assigned)
- Even split among found winners

### JACK-03: 5-Day Jackpot-Phase Draw Mechanics

**Function:** `payDailyJackpot(isDaily=true)` -- JackpotModule:333-611

**Daily pool slice formula:**
```solidity
function _dailyCurrentPoolBps(uint8 counter, uint256 randWord) private pure returns (uint16) {
    if (counter >= JACKPOT_LEVEL_CAP - 1) return 10_000;  // Day 5: 100%
    uint16 range = DAILY_CURRENT_BPS_MAX - DAILY_CURRENT_BPS_MIN + 1;  // 801
    uint256 seed = keccak256(abi.encodePacked(randWord, DAILY_CURRENT_BPS_TAG, counter));
    return DAILY_CURRENT_BPS_MIN + (seed % range);  // 600-1400 (6%-14%)
}
```

**Compressed jackpot (when level reached target in <=2 days):**
```solidity
if (compressedJackpotFlag && counter < JACKPOT_LEVEL_CAP - 1) {
    counterStep = 2;  // advance counter by 2
}
if (counterStep == 2) {
    dailyBps *= 2;  // double the BPS to combine two days
}
// Result: 5 logical days in 3 physical days
```

**Budget split per day:**
```solidity
uint256 budget = (currentPrizePool * dailyBps) / 10_000;
uint256 dailyLootboxBudget = budget / 5;  // 20% to lootbox tickets
budget -= dailyLootboxBudget;              // 80% to ETH distribution
```

**Day 1 special:** Runs `_runEarlyBirdLootboxJackpot()` instead of carryover:
```solidity
uint256 reserveContribution = (_getFuturePrizePool() * 300) / 10_000;  // 3%
// 100 winners max, per-winner = totalBudget / 100
// Each winner: random level offset 0-4, tickets at that level's price
// Full budget added to nextPrizePool
```

**Days 2-4 carryover:**
```solidity
uint256 reserveSlice = _getFuturePrizePool() / 100;  // 1% of future pool
// carryoverLootboxBps = DAILY_REWARD_JACKPOT_LOOTBOX_BPS = 5000 (50%)
uint256 carryoverLootboxBudget = (futureEthPool * 5000) / 10_000;
// Remaining 50% distributed as ETH to carryover source level winners
```

**Carryover source level selection:**
- Selects from [lvl+1, lvl+DAILY_CARRYOVER_MAX_OFFSET] (up to lvl+5)
- Only levels with actual winning-trait tickets are eligible
- Random selection among eligible offsets

### JACK-04: Trait Bucket Distribution and Winner Selection

**Trait ID encoding:** `(quadrant << 6) | (color << 3) | symbol`
- 4 quadrants (Q0-Q3), 8 colors, 8 symbols = 256 possible traits
- Q0/Q1/Q2: fixed symbol-0, random color; Q3: fully random
- Hero override: top daily hero symbol auto-wins its quadrant

**Days 1-4 shares:** DAILY_JACKPOT_SHARES_PACKED = 2000 each (20% x 4)
- Solo bucket (entropy-selected) receives any remainder

**Day 5 shares:** FINAL_DAY_SHARES_PACKED = 6000/1333/1333/1334
- Solo bucket (1 winner) gets 60%, other 3 buckets split remaining 40%
- Rotation: solo bucket index = `entropy & 3`

**Winner selection:** `_randTraitTicket()` -- JackpotModule:2264
```solidity
// Duplicates allowed (more tickets = more chances)
// Virtual deity entries: floor(2% of bucket tickets), min 2
uint8 fullSymId = (trait >> 6) * 8 + (trait & 0x07);
if (deityBySymbol[fullSymId] != address(0)) {
    virtualCount = len / 50;  // 2% of real tickets
    if (virtualCount < 2) virtualCount = 2;
}
// Winner selected: idx = slice % effectiveLen (real + virtual)
```

**Bucket winner count scaling:**
- JackpotBucketLib scales bucket counts based on pool size and entropy
- JACKPOT_SCALE_MAX_BPS = 40,000 (4x at 200 ETH+)
- DAILY_JACKPOT_SCALE_MAX_BPS = 66,667 (6.67x for daily draws)

### JACK-05: Carryover ETH and Compressed Jackpot

**Carryover mechanics:**
- Days 2-4 only (day 1 uses early-bird lootbox instead)
- 1% of futurePrizePool deducted upfront
- 50% of slice -> lootbox tickets (to carryover source level)
- 50% -> ETH distributed to carryover source level trait winners
- Source level: random eligible offset in [lvl+1, lvl+5]
- Winner cap: remaining after daily distribution (min DAILY_CARRYOVER_MIN_WINNERS=20)

**Compressed jackpot trigger:**
```solidity
// In advanceGame() when lastPurchaseDay becomes true:
compressedJackpotFlag = (day - purchaseStartDay <= 2);
// Effect: counterStep=2, dailyBps*=2
// 5 logical days complete in 3 physical days
```

### JACK-06: Lootbox-to-Jackpot Conversion Ratios

| Context | Constant | Value | Meaning |
|---------|----------|-------|---------|
| Jackpot-phase daily carryover | DAILY_REWARD_JACKPOT_LOOTBOX_BPS | 5000 | 50% of carryover ETH -> lootbox tickets |
| Purchase-phase daily drip | PURCHASE_REWARD_JACKPOT_LOOTBOX_BPS | 7500 | 75% of drip ETH -> lootbox tickets |
| Jackpot-phase daily budget | `budget / 5` | 20% | 20% of daily budget to lootbox tickets |
| Early-bird (day 1) | 100% | 3% of future -> all tickets | Full budget becomes tickets via nextPrizePool |
| Purchase-phase drip ticket conversion | `ticketConversionBps = 5000` | 50% | Only 50% of lootbox budget determines ticket count (but full budget goes to nextPrizePool) |

### JACK-07: BURNIE Jackpot-Phase Parallel Distribution

**During jackpot phase** -- `payDailyJackpotCoinAndTickets()` (JackpotModule:685)

**BURNIE budget:** Same formula as purchase phase: 0.5% of prize pool target in BURNIE
```solidity
coinBudget = (levelPrizePool[lvl - 1] * PRICE_COIN_UNIT) / (priceWei * 200);
```

**Split identical to purchase phase:**
- 25% far-future (lvl+5 to lvl+99, ticketQueue-based, up to 10 winners)
- 75% near-future (lvl to lvl+4, trait-matched, up to 50 winners)

**Far-future allocation details:**
```solidity
// Samples FAR_FUTURE_COIN_SAMPLES (10) random levels in [lvl+5, lvl+99]
uint24 candidate = lvl + 5 + uint24(entropy % 95);
// Picks 1 winner per level from ticketQueue[_tqWriteKey(candidate)]
// Even split among found winners
// Paid via coin.creditFlipBatch()
```

### JACK-08: BAF (Big-Ass Flip) Mechanics

**Trigger:** Every 10 levels (lvl % 10 == 0) during `runRewardJackpots()` (EndgameModule:138)

**Pool percentages:**
```solidity
uint256 bafPct = prevMod100 == 0 ? 20 : (lvl == 50 ? 25 : 10);
uint256 bafPoolWei = (baseFuturePool * bafPct) / 100;
```

| Level | Pool % | Source |
|-------|--------|--------|
| 10, 20, 30, 40, 60, 70, 80, 90 | 10% of future pool | EndgameModule:150 |
| 50 | 25% of future pool | EndgameModule:150 |
| 100, 200, 300... | 20% of future pool | EndgameModule:150 |

**Distribution flow:**
1. External call to `jackpots.runBafJackpot(poolWei, lvl, rngWord)` returns winners and amounts
2. Large winners (>=5% of BAF pool):
   - 50% as claimable ETH
   - 50% as lootbox (<=5 ETH: immediate tickets, >5 ETH: deferred whale pass)
3. Small winners (<5% of pool): alternating
   - Even index: 100% ETH
   - Odd index: 100% lootbox tickets

**Lootbox ticket award tiers (EndgameModule:405-488):**
- Very small (<=0.5 ETH): single probabilistic roll
- Medium (0.5-5 ETH): split in half, 2 probabilistic rolls
- Large (>5 ETH): deferred whale pass claim
- Each roll: 30% current level, 65% +1-4 levels, 5% +5-50 levels

**Refund mechanics:** Any unused BAF pool returns to futurePrizePool. Lootbox ETH stays in futurePrizePool (source pool).

### JACK-09: Decimator Mechanics

**Trigger levels:**
```solidity
// In advanceGame() when entering jackpot phase:
uint24 mod100 = lvl % 100;
if ((lvl % 10 == 4 && mod100 != 94) || mod100 == 99) {
    decWindowOpen = true;
}
// Window opens at: 4, 14, 24, 34, 44, 54, 64, 74, 84, 99, 104, ...
// NOT at: 94

// Resolution during runRewardJackpots():
// Levels ending in 5 (not 95): 10% of future pool
// x00 levels: 30% of future pool (based on baseFuturePool before BAF deduction)
```

**Pool percentages:**
```solidity
// Normal decimator (levels 5, 15, 25, ... 85):
decPoolWei = (futurePoolLocal * 10) / 100;  // 10% of remaining future pool

// x00 decimator (100, 200, ...):
decPoolWei = (baseFuturePool * 30) / 100;   // 30% of original future pool
```

**Burn tracking** (`recordDecBurn()` -- DecimatorModule:221):
- Players choose bucket denominator 2-12 (lower = fewer winners, higher payout)
- Subbucket deterministically assigned: `keccak256(player, lvl, bucket) % bucket`
- Burns accumulate with multiplier (capped at DECIMATOR_MULTIPLIER_CAP = 200,000 BURNIE)
- Can migrate to lower bucket (removes from old, adds to new)

**Effective amount with multiplier cap:**
```solidity
function _decEffectiveAmount(uint256 prevBurn, uint256 baseAmount, uint256 multBps) {
    // If multBps <= 10000 or prevBurn >= cap: return baseAmount (no multiplier)
    // Otherwise: apply multiplier up to cap, then 1x for remainder
    // Cap = DECIMATOR_MULTIPLIER_CAP = 200 * PRICE_COIN_UNIT = 200,000 BURNIE
}
```

**Jackpot resolution** (`runDecimatorJackpot()` -- DecimatorModule:297):
1. For each denominator 2-12: deterministically select winning subbucket from VRF
2. Sum burn totals from all winning subbuckets
3. Snapshot results in `lastDecClaimRound` (overwrites previous -- old claims expire)
4. Return 0 if winners found (pool held for claims), return poolWei if no qualifying burns

**Claim mechanics:**
- Pro-rata: `amountWei = (poolWei * playerBurn) / totalBurn`
- Normal play: 50% ETH / 50% lootbox (via `_creditDecJackpotClaimCore`)
- Game over: 100% ETH
- Claims blocked during pool freeze (jackpot phase days 1-4)
- Lootbox portion: <=LOOTBOX_CLAIM_THRESHOLD (5 ETH): immediate resolve; >5 ETH: deferred whale pass

**Decimator window open/close timing:**
- Opens: at jackpot phase start for eligible levels (AdvanceModule:282-285)
- Burns can occur during jackpot phase while window is open
- Resolution: during `_runRewardJackpots()` after day 5 completes

## Common Pitfalls

### Pitfall 1: Compressed Jackpot Counter vs Physical Days
**What goes wrong:** Confusing logical vs physical days in compressed mode.
**Root cause:** `counterStep=2` means counter increments by 2 per physical day, and `dailyBps *= 2` doubles the payout per physical day.
**Prevention:** Always specify "logical days" vs "physical days" in documentation. 5 logical days = 3 physical days when compressed.

### Pitfall 2: Day 1 vs Days 2-4 Carryover Distinction
**What goes wrong:** Assuming carryover runs on all jackpot days.
**Root cause:** Day 1 (`counter == 0`) runs `_runEarlyBirdLootboxJackpot()` instead. Days 2-4 run the 1% future pool carryover. Day 5 has no separate carryover.
**Prevention:** Document early-bird vs carryover as explicitly different day-1 vs day-2-4 mechanics.

### Pitfall 3: BAF Pool Percentage Basis
**What goes wrong:** Assuming BAF and Decimator use the same pool base.
**Root cause:** BAF uses `baseFuturePool` (snapshot before any deductions). Normal decimator uses `futurePoolLocal` (after BAF deduction). x00 decimator uses `baseFuturePool`.
**Prevention:** Document the exact variable used for each percentage calculation.

### Pitfall 4: Solo Bucket 75/25 Split
**What goes wrong:** Assuming all jackpot winners get pure ETH.
**Root cause:** Solo bucket winners (1 winner per bucket) get 75% ETH / 25% whale passes if the 25% covers at least one HALF_WHALE_PASS_PRICE (2.175 ETH). Otherwise 100% ETH.
**Prevention:** Document the solo bucket special handling separately from multi-winner buckets.

### Pitfall 5: Lootbox Budget vs Ticket Count Disconnect
**What goes wrong:** Assuming lootbox budget equals ticket value.
**Root cause:** In purchase-phase drip, `ticketConversionBps=5000` means only 50% of the lootbox budget determines ticket count, but the FULL budget goes to nextPrizePool. This creates an over-collateralization of ticket backing.
**Prevention:** Document both the pool flow and the ticket count independently.

### Pitfall 6: Decimator Claims Expire
**What goes wrong:** Modeling decimator payouts as immediate.
**Root cause:** `runDecimatorJackpot()` only snapshots. Claims are deferred. `lastDecClaimRound` overwrites -- only the most recent decimator is claimable. Old claims expire.
**Prevention:** Document the claim window explicitly (between resolution and next decimator run).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge test) |
| Config file | foundry.toml |
| Quick run command | `forge test --match-contract JackpotTest -x` |
| Full suite command | `forge test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| JACK-01 | Purchase-phase future pool drip | manual-only | N/A -- documentation phase, verify against source | N/A |
| JACK-02 | Purchase-phase BURNIE jackpots | manual-only | N/A -- documentation phase, verify against source | N/A |
| JACK-03 | 5-day jackpot draw mechanics | manual-only | N/A -- documentation phase, verify against source | N/A |
| JACK-04 | Trait bucket distribution | manual-only | N/A -- documentation phase, verify against source | N/A |
| JACK-05 | Carryover ETH and compressed | manual-only | N/A -- documentation phase, verify against source | N/A |
| JACK-06 | Lootbox conversion ratios | manual-only | N/A -- documentation phase, verify against source | N/A |
| JACK-07 | BURNIE jackpot-phase distribution | manual-only | N/A -- documentation phase, verify against source | N/A |
| JACK-08 | BAF mechanics | manual-only | N/A -- documentation phase, verify against source | N/A |
| JACK-09 | Decimator mechanics | manual-only | N/A -- documentation phase, verify against source | N/A |

**Justification for manual-only:** This is a documentation/analysis phase. No code changes are made. Validation is verifying that documented formulas match contract source -- done by the planner/executor reading source alongside output.

### Sampling Rate
- **Per task commit:** Visual diff of documented constants against contract source
- **Per wave merge:** Cross-reference all BPS values with constant table
- **Phase gate:** All 9 JACK requirements addressed with source-verified formulas

### Wave 0 Gaps
None -- existing test infrastructure is not relevant to documentation-only phases.

## Recommended Plan Structure

### Plan 07-01: Purchase-Phase Distribution (JACK-01, JACK-02, JACK-06 partial)
- Daily ETH drip from future pool (1%, 75% lootbox conversion)
- Daily BURNIE jackpots (0.5% of target, 75/25 near/far split)
- Purchase-phase lootbox conversion ratio (PURCHASE_REWARD_JACKPOT_LOOTBOX_BPS=7500)
- Winning trait derivation for purchase phase (non-burn-weighted)

### Plan 07-02: Jackpot-Phase 5-Day Draws (JACK-03, JACK-04, JACK-05, JACK-06 partial, JACK-07)
- Daily pool slice formula (6-14% random, 100% day 5)
- Trait bucket distribution (equal 20% days 1-4, 60/13/13/13 day 5)
- Day 1 early-bird lootbox jackpot (3% future pool)
- Days 2-4 carryover (1% future pool, 50% lootbox)
- Compressed jackpot mechanics (counterStep=2, BPS doubling)
- BURNIE parallel distribution during jackpot phase
- DGNRS day-5 solo bucket reward (1% of reward pool)
- Winner selection mechanics (trait tickets, virtual deity entries)

### Plan 07-03: Transition Jackpots -- BAF and Decimator (JACK-08, JACK-09)
- BAF trigger schedule and pool percentages (10/25/20%)
- BAF payout split (large: 50/50, small: alternating)
- BAF lootbox ticket tiers (small/medium/large)
- Decimator trigger schedule (x5 not x95: 10%, x00: 30%)
- Decimator burn tracking (bucket 2-12, subbucket, multiplier cap)
- Decimator resolution and claim mechanics
- Decimator lootbox conversion (50/50 ETH/lootbox)
- Decimator window open/close timing

## Sources

### Primary (HIGH confidence)
- `contracts/modules/DegenerusGameJackpotModule.sol` -- All daily jackpot mechanics, trait bucket distribution, coin jackpots, pool consolidation, winner selection
- `contracts/modules/DegenerusGameAdvanceModule.sol` -- Phase orchestration, compressed jackpot trigger, decimator window opening
- `contracts/modules/DegenerusGameEndgameModule.sol` -- BAF jackpot execution, decimator dispatch, reward routing
- `contracts/modules/DegenerusGameDecimatorModule.sol` -- Decimator burn tracking, resolution, claim mechanics
- `contracts/modules/DegenerusGamePayoutUtils.sol` -- HALF_WHALE_PASS_PRICE, LOOTBOX_CLAIM_THRESHOLD
- `audit/06-pool-architecture.md` -- Pool lifecycle context (Phase 6 dependency)
- `audit/06-eth-inflows.md` -- Pool split ratios context (Phase 6 dependency)

## Metadata

**Confidence breakdown:**
- Distribution flow architecture: HIGH -- all functions traced through source code with exact line references
- Constants and formulas: HIGH -- every constant verified against contract source with file and line
- Pitfalls: HIGH -- identified from code structure analysis, cross-referencing multiple modules
- Plan structure: HIGH -- clean mapping from 9 requirements to 3 logical groupings

**Research date:** 2026-03-12
**Valid until:** Indefinite (contracts are immutable, analysis-only milestone)
