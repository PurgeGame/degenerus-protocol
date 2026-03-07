# DegenerusGameJackpotModule.sol -- Function-Level Audit (Part 1: Entry Points and Pool Management)

**Contract:** DegenerusGameJackpotModule
**File:** contracts/modules/DegenerusGameJackpotModule.sol
**Lines:** 2794
**Solidity:** 0.8.34
**Inherits:** DegenerusGamePayoutUtils (which inherits DegenerusGameStorage)
**Called via:** delegatecall from DegenerusGame (most functions), direct external call (runTerminalJackpot)
**Audit date:** 2026-03-07
**Scope:** Part 1 -- External entry points, pool management, auto-rebuy, ticket helpers (lines 1-1076)

---

## Constants Inventory

### Timing and Thresholds

| Constant | Value | Purpose |
|----------|-------|---------|
| `JACKPOT_RESET_TIME` | 82620 (uint48) | Seconds offset from midnight UTC for daily jackpot reset boundary (22:57 UTC) |
| `JACKPOT_LEVEL_CAP` | 5 (uint8) | Maximum daily jackpots per level before forcing level transition |

### Share Distribution (Basis Points)

| Constant | Value | Purpose |
|----------|-------|---------|
| `FINAL_DAY_SHARES_PACKED` | Packed [6000, 1333, 1333, 1334] = 10000 bps | Day-5 trait bucket shares; 60% share rotates to solo bucket |
| `DAILY_JACKPOT_SHARES_PACKED` | 2000 bps each x4 = 8000 bps | Days 1-4 equal shares; remaining 20% to entropy-selected solo bucket |
| `FINAL_DAY_DGNRS_BPS` | 100 (uint16) | 1% of DGNRS reward pool paid to day-5 solo bucket winner |
| `DAILY_REWARD_JACKPOT_LOOTBOX_BPS` | 5000 (uint16) | 50% of reward-pool-funded daily jackpot ETH converted to loot boxes |
| `PURCHASE_REWARD_JACKPOT_LOOTBOX_BPS` | 7500 (uint16) | 75% of purchase-phase reward-pool jackpots converted to loot boxes |
| `FAR_FUTURE_COIN_BPS` | 2500 (uint16) | 25% of daily BURNIE budget awarded to far-future ticket holders |

### Entropy Salt Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `COIN_JACKPOT_TAG` | keccak256("coin-jackpot") | Domain separator for coin jackpot entropy derivation |
| `DAILY_CURRENT_BPS_TAG` | keccak256("daily-current-bps") | Domain separator for rolling current-pool daily jackpot percentage |
| `DAILY_CARRYOVER_SOURCE_TAG` | keccak256("daily-carryover-source") | Domain separator for selecting daily carryover source level |
| `FUTURE_DUMP_TAG` | keccak256("future-dump") | Domain separator for rare future-pool dump roll |
| `FUTURE_KEEP_TAG` | keccak256("future-keep") | Domain separator for level-100 future pool keep roll |
| `FAR_FUTURE_COIN_TAG` | keccak256("far-future-coin") | Domain separator for far-future coin jackpot entropy |
| `DAILY_CARRYOVER_MAX_OFFSET` | 5 (uint8) | Max forward offset for carryover source selection |

### Daily Jackpot Percentage Bounds

| Constant | Value | Purpose |
|----------|-------|---------|
| `DAILY_CURRENT_BPS_MIN` | 600 (uint16) | 6% minimum daily current pool jackpot share (days 1-4) |
| `DAILY_CURRENT_BPS_MAX` | 1400 (uint16) | 14% maximum daily current pool jackpot share (days 1-4) |

### Gas Budgeting Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `WRITES_BUDGET_SAFE` | 550 (uint32) | Default SSTORE budget for processTicketBatch (~15M gas safe) |
| `DAILY_JACKPOT_UNITS_SAFE` | 1000 (uint16) | Default unit budget for daily jackpot ETH distribution |
| `DAILY_JACKPOT_UNITS_AUTOREBUY` | 3 (uint8) | Winner unit cost when auto-rebuy is enabled (3x normal) |

### Winner Cap Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `JACKPOT_MAX_WINNERS` | 300 (uint16) | Maximum total winners per jackpot payout (including solo bucket) |
| `DAILY_ETH_MAX_WINNERS` | 321 (uint16) | Maximum total ETH winners across daily + carryover jackpots |
| `DAILY_CARRYOVER_MIN_WINNERS` | 20 (uint16) | Minimum carryover winners when carryover is active |
| `DAILY_COIN_MAX_WINNERS` | 50 (uint16) | Maximum winners for daily coin jackpot |
| `LOOTBOX_MAX_WINNERS` | 100 (uint16) | Maximum winners for lootbox jackpot distributions |
| `MAX_BUCKET_WINNERS` | 250 (uint8) | Max winners per single trait bucket |
| `FAR_FUTURE_COIN_SAMPLES` | 10 (uint8) | Number of far-future levels to sample for BURNIE jackpot |

### Scaling Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `JACKPOT_SCALE_MAX_BPS` | 40000 (uint16) | Maximum scale for bucket sizing (4x at 200+ ETH) |
| `DAILY_JACKPOT_SCALE_MAX_BPS` | 66667 (uint32) | Daily jackpot max scale (6.6667x) |

### Miscellaneous Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `FUTURE_DUMP_ODDS` | 1e15 (uint256) | 1-in-quadrillion odds for future->current dump |
| `TICKET_LCG_MULT` | 0x5851F42D4C957F2D (uint64) | LCG multiplier for deterministic trait generation (Knuth's MMIX) |
| `DAILY_COIN_SALT_BASE` | 252 (uint8) | Salt base for daily coin jackpot winner selection |
| `FAR_FUTURE_COIN_SALT_BASE` | 248 (uint8) | Salt base for far-future coin jackpot winner selection |

---

## Structs

### `JackpotEthCtx`

Mutable context passed through ETH distribution loops to track cumulative state. Avoids stack-too-deep.

| Field | Type | Description |
|-------|------|-------------|
| `entropyState` | uint256 | Rolling entropy for winner selection |
| `liabilityDelta` | uint256 | Cumulative claimable liability added this run |
| `totalPaidEth` | uint256 | Total ETH paid out (including ticket conversions) |
| `lvl` | uint24 | Current level |

### `JackpotParams`

Packed parameters for a single jackpot execution. Avoids passing 6+ parameters through call chain.

| Field | Type | Description |
|-------|------|-------------|
| `lvl` | uint24 | Current game level (1-indexed) |
| `ethPool` | uint256 | ETH available for this jackpot |
| `entropy` | uint256 | VRF-derived entropy for winner selection |
| `winningTraitsPacked` | uint32 | 4 trait IDs packed into 32 bits (8 bits each) |
| `traitShareBpsPacked` | uint64 | 4 share percentages packed (16 bits each) |

### `AutoRebuyCalc` (from PayoutUtils)

| Field | Type | Description |
|-------|------|-------------|
| `toFuture` | bool | True if tickets target 2-4 levels ahead (75%), false for +1 (25%) |
| `hasTickets` | bool | True if ticket calculation produced at least 1 ticket |
| `targetLevel` | uint24 | Level tickets are queued for |
| `ticketCount` | uint32 | Number of tickets after bonus |
| `ethSpent` | uint256 | ETH consumed by ticket purchase |
| `reserved` | uint256 | ETH reserved for take-profit claim |
| `rebuyAmount` | uint256 | ETH available for auto-rebuy after take-profit |

---

## Function Audit

### `runTerminalJackpot(uint256 poolWei, uint24 targetLvl, uint256 rngWord)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function runTerminalJackpot(uint256 poolWei, uint24 targetLvl, uint256 rngWord) external returns (uint256 paidWei)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `poolWei` (uint256): Total ETH to distribute; `targetLvl` (uint24): Level to sample winners from; `rngWord` (uint256): VRF entropy seed |
| **Returns** | `uint256`: Total ETH distributed (callers deduct from source pool) |

**State Reads:** `traitBurnTicket[targetLvl]`, `deityBySymbol[]`, `claimableWinnings[]`, `autoRebuyState[]`, `gameOver`, `level`, `futurePrizePool`, `nextPrizePool`, `whalePassClaims[]`

**State Writes:** `claimableWinnings[]`, `claimablePool`, `autoRebuyState[]` (via auto-rebuy), `futurePrizePool` (via solo bucket whale pass conversion), `nextPrizePool` (via auto-rebuy), `whalePassClaims[]`, `ticketsOwedPacked[]`, `ticketQueue[]`

**Callers:** EndgameModule, GameOverModule (via `IDegenerusGame(address(this)).runTerminalJackpot(...)`)

**Callees:** `_rollWinningTraits`, `JackpotBucketLib.unpackWinningTraits`, `JackpotBucketLib.bucketCountsForPoolCap`, `JackpotBucketLib.shareBpsByBucket`, `_distributeJackpotEth`

**ETH Flow:** `poolWei` (caller-provided budget) -> distributed to winners via `_distributeJackpotEth`. Uses FINAL_DAY_SHARES_PACKED (60/13/13/13). Solo bucket winners may receive whale passes (ETH -> `futurePrizePool`). Non-solo winners: ETH -> `claimableWinnings[]` / `claimablePool`. Auto-rebuy paths: ETH -> `nextPrizePool` or `futurePrizePool` + tickets.

**Invariants:**
- `msg.sender` must be `ContractAddresses.GAME` (OnlyGame check)
- `paidWei <= poolWei` (can be less due to rounding dust)
- Callers must deduct `paidWei` from their source pool
- `claimablePool` incremented matches sum of individual `claimableWinnings` credits

**NatSpec Accuracy:** CORRECT. NatSpec accurately describes this as a terminal jackpot for x00 levels using Day-5-style shares. It correctly warns callers must NOT double-count pool debits.

**Gas Flags:** Uses `DAILY_ETH_MAX_WINNERS` (321) and `DAILY_JACKPOT_SCALE_MAX_BPS` (66667) for terminal jackpot -- these are the daily limits, not the regular jackpot limits. This is intentional to allow wider distribution for terminal pots. No unnecessary computation.

**Access Control:** This function is called via a normal `external` call (not delegatecall). The `OnlyGame()` check verifies `msg.sender == ContractAddresses.GAME`. This means EndgameModule/GameOverModule call `IDegenerusGame(address(this)).runTerminalJackpot(...)` during delegatecall execution. In that context, `address(this)` is the Game contract, and `msg.sender` becomes the Game contract address -- so the access check passes.

**Verdict:** CORRECT

---

### `payDailyJackpot(bool isDaily, uint24 lvl, uint256 randWord)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function payDailyJackpot(bool isDaily, uint24 lvl, uint256 randWord) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `isDaily` (bool): true for scheduled daily, false for early-burn; `lvl` (uint24): Current game level; `randWord` (uint256): VRF entropy |
| **Returns** | None |

**State Reads:** `dailyEthPoolBudget`, `dailyEthPhase`, `dailyEthBucketCursor`, `dailyEthWinnerCursor`, `lastDailyJackpotWinningTraits`, `lastDailyJackpotLevel`, `jackpotCounter`, `compressedJackpotFlag`, `currentPrizePool`, `futurePrizePool`, `nextPrizePool`, `dailyCarryoverEthPool`, `dailyCarryoverWinnerCap`, `dailyTicketBudgetsPacked`, `traitBurnTicket[]`, `dailyHeroWagers[]`, `price`, `levelStartTime`, `autoRebuyState[]`, `gameOver`, `level`

**State Writes:** `lastDailyJackpotWinningTraits`, `lastDailyJackpotLevel`, `lastDailyJackpotDay`, `dailyEthPoolBudget`, `dailyEthPhase`, `dailyEthBucketCursor`, `dailyEthWinnerCursor`, `currentPrizePool`, `futurePrizePool`, `nextPrizePool`, `dailyCarryoverEthPool`, `dailyCarryoverWinnerCap`, `dailyTicketBudgetsPacked`, `dailyJackpotCoinTicketsPending`, `claimableWinnings[]`, `claimablePool`, `ticketsOwedPacked[]`, `ticketQueue[]`, `whalePassClaims[]`

**Callers:** DegenerusGame via delegatecall (advanceGame flow)

**Callees:** `_calculateDayIndex`, `_rollWinningTraits`, `_syncDailyWinningTraits`, `_dailyCurrentPoolBps`, `_runEarlyBirdLootboxJackpot`, `_validateTicketBudget`, `_budgetToTicketUnits`, `_selectCarryoverSourceOffset`, `_packDailyTicketBudgets`, `_unpackDailyTicketBudgets`, `_processDailyEthChunk`, `_executeJackpot`, `_distributeLootboxAndTickets`, `JackpotBucketLib.unpackWinningTraits`, `JackpotBucketLib.bucketCountsForPoolCap`, `JackpotBucketLib.shareBpsByBucket`, `JackpotBucketLib.sumBucketCounts`, `coin.rollDailyQuest`

#### Two-Phase Chunking Mechanism (Daily Path)

The daily jackpot is split into multiple advanceGame calls to stay under 15M gas:

**Phase 0: Current level ETH distribution**
1. On first call (`isResuming == false`): compute winning traits, calculate daily BPS (6-14% or 100% on day 5), compute daily lootbox budget (20% of daily ETH), compute carryover pool (1% from `futurePrizePool`), store all state for resumability.
2. Execute `_processDailyEthChunk()` with a units budget (DAILY_JACKPOT_UNITS_SAFE = 1000). If chunk completes, calculate carryover winner cap. If chunk does NOT complete, store cursor state and `return` (next call resumes).
3. On completion: set `dailyEthPhase = 1` if carryover has work; otherwise finalize immediately.

**Phase 1: Carryover ETH distribution**
1. Distribute carryover ETH to winners from a randomly selected future level (offset 1-5).
2. Uses same chunking mechanism via `_processDailyEthChunk()`.
3. On completion: clear all daily state, set `dailyJackpotCoinTicketsPending = true`.

**Early-Burn Path (isDaily == false):**
- Rolls random winning traits (non-burn-weighted).
- Every 3rd purchase day: adds 1% `futurePrizePool` slice with 75% converted to lootbox tickets.
- Calls `_executeJackpot()` (not chunked -- early-burn pots are smaller).
- Rolls daily quest at the end.

**Resumability Protocol:**
| State Variable | Purpose |
|----------------|---------|
| `dailyEthPoolBudget` | Current level ETH budget (prevents re-calculation) |
| `dailyEthPhase` | 0 = current level, 1 = carryover |
| `dailyEthBucketCursor` | Which bucket (in order array) to resume at |
| `dailyEthWinnerCursor` | Which winner within bucket to resume at |
| `dailyCarryoverEthPool` | Carryover ETH reserved after Phase 0 |
| `dailyCarryoverWinnerCap` | Remaining winner cap for Phase 1 |
| `dailyTicketBudgetsPacked` | Packed ticket units, counter step, carryover offset |
| `lastDailyJackpotWinningTraits` | Saved winning traits for resuming |
| `lastDailyJackpotLevel` | Saved level for resuming |

**Pool Mutation Trace (Daily Path, Fresh Start):**
1. `currentPrizePool -= dailyLootboxBudget` (20% of daily slice, for ticket backing)
2. `nextPrizePool += dailyLootboxBudget` (tickets backed by next pool)
3. `futurePrizePool -= reserveSlice` (1% for carryover, days 2-4 only)
4. `nextPrizePool += carryoverLootboxBudget` (50% of carryover for ticket backing)
5. `currentPrizePool -= paidDailyEth` (Phase 0 ETH paid to winners)
6. `claimablePool += liabilityDelta` (Phase 0 claimable liability)
7. (Phase 1: carryover paid from `dailyCarryoverEthPool` -- already deducted from `futurePrizePool`)

**Pool Mutation Trace (Early-Burn Path, isEthDay):**
1. `futurePrizePool -= ethDaySlice` (1% of future pool)
2. `nextPrizePool += lootboxBudget` (via `_distributeLootboxAndTickets`)
3. `claimablePool += liabilityDelta` (via `_executeJackpot` -> `_distributeJackpotEth`)

**Compressed Jackpot Handling:** When `compressedJackpotFlag` is true and counter < 4, `counterStep = 2` and `dailyBps *= 2`. This combines two days' payouts into one physical day, allowing 5 logical days to complete in 3 physical days.

**ETH Flow:** Multiple paths documented above. Core invariant: all ETH deducted from `currentPrizePool`/`futurePrizePool` is either credited to `claimablePool` (for winners) or moved to `nextPrizePool`/`futurePrizePool` (for ticket backing/auto-rebuy).

**Invariants:**
- `dailyEthPoolBudget`, `dailyEthPhase`, `dailyEthBucketCursor`, `dailyEthWinnerCursor` are zeroed when all phases complete
- `dailyJackpotCoinTicketsPending = true` only set after both Phase 0 and Phase 1 complete
- `jackpotCounter` is NOT incremented here -- deferred to `payDailyJackpotCoinAndTickets`
- On day 1 (`counter == 0`): early-bird lootbox replaces carryover; `reserveSlice = 0`

**NatSpec Accuracy:** CORRECT. Extensive NatSpec accurately describes both daily and early-burn paths, including day-1 early-bird replacement of carryover, compressed jackpot, and chunking.

**Gas Flags:**
- `budget / 5` used instead of `* 2000 / 10000` -- correct optimization (20% = 1/5)
- `futurePrizePool / 100` used instead of `* 100 / 10000` -- correct optimization (1% = 1/100)
- Phase 0 lootbox budget uses `_validateTicketBudget` which zeros budget if no trait tickets exist, preventing wasted computation

**Verdict:** CORRECT

---

### `payDailyJackpotCoinAndTickets(uint256 randWord)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function payDailyJackpotCoinAndTickets(uint256 randWord) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `randWord` (uint256): VRF entropy (must match rngWordCurrent from Phase 1) |
| **Returns** | None |

**State Reads:** `dailyJackpotCoinTicketsPending`, `dailyTicketBudgetsPacked`, `lastDailyJackpotLevel`, `lastDailyJackpotWinningTraits`, `traitBurnTicket[]`, `deityBySymbol[]`, `price`, `levelPrizePool[]`

**State Writes:** `jackpotCounter` (incremented by counterStep), `dailyJackpotCoinTicketsPending` (cleared to false), `dailyTicketBudgetsPacked` (cleared to 0), `ticketsOwedPacked[]`, `ticketQueue[]`

**Callers:** DegenerusGame via delegatecall (advanceGame flow, when `dailyJackpotCoinTicketsPending` is true)

**Callees:** `_unpackDailyTicketBudgets`, `_calcDailyCoinBudget`, `_awardFarFutureCoinJackpot`, `_selectDailyCoinTargetLevel`, `_awardDailyCoinToTraitWinners`, `_distributeTicketJackpot`, `_calculateDayIndex`, `coin.rollDailyQuest`

**ETH Flow:** No direct ETH mutation. This function distributes BURNIE coin and tickets only. Coin distribution via `coin.creditFlip()` / `coin.creditFlipBatch()`. Ticket distribution via `_queueTickets()`.

**Invariants:**
- Early-exit if `dailyJackpotCoinTicketsPending == false` (idempotent guard)
- `jackpotCounter += counterStep` (1 or 2 for compressed)
- Coin budget: 0.5% of `levelPrizePool[lvl-1]` converted to BURNIE units
- Coin split: 25% far-future (ticketQueue-based), 75% near-future (trait-matched)
- Daily tickets distributed to current level; carryover tickets to carryover source level
- `dailyJackpotCoinTicketsPending` and `dailyTicketBudgetsPacked` cleared on completion

**NatSpec Accuracy:** CORRECT. NatSpec accurately describes this as Phase 2 of daily jackpot, gas optimization rationale, and stored value usage.

**Gas Flags:** Separating coin+ticket distribution from ETH distribution is a sound gas optimization. Each advanceGame call stays under 15M gas. No redundant reads.

**Verdict:** CORRECT

---

### `awardFinalDayDgnrsReward(uint24 lvl, uint256 rngWord)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function awardFinalDayDgnrsReward(uint24 lvl, uint256 rngWord) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Current level; `rngWord` (uint256): VRF random word |
| **Returns** | None |

**State Reads:** `lastDailyJackpotWinningTraits`, `traitBurnTicket[lvl]`, `deityBySymbol[]`

**State Writes:** None directly (DGNRS token transfer is an external call)

**Callers:** DegenerusGame via delegatecall (after Day 5 coin+tickets)

**Callees:** `dgnrs.poolBalance(Pool.Reward)`, `JackpotBucketLib.soloBucketIndex`, `JackpotBucketLib.unpackWinningTraits`, `_randTraitTicket`, `dgnrs.transferFromPool`

**ETH Flow:** No ETH movement. Transfers DGNRS tokens from the Reward pool to the solo bucket winner.

**Invariants:**
- Reward = 1% of DGNRS reward pool (`FINAL_DAY_DGNRS_BPS = 100`)
- Uses stored `lastDailyJackpotWinningTraits` (from the Day-5 jackpot)
- Solo bucket index derived from entropy rotation
- Only 1 winner selected (the solo bucket winner)
- No-op if reward is 0 or no winner found

**NatSpec Accuracy:** CORRECT. Accurately describes re-derivation of solo bucket from stored traits.

**Gas Flags:** Minimal computation. Single winner selection + single external call.

**Verdict:** CORRECT

---

### `consolidatePrizePools(uint24 lvl, uint256 rngWord)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function consolidatePrizePools(uint24 lvl, uint256 rngWord) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Current game level; `rngWord` (uint256): VRF entropy |
| **Returns** | None |

**State Reads:** `nextPrizePool`, `currentPrizePool`, `futurePrizePool`, `claimablePool`, `price`, `lastPurchaseDayFlipTotal`, `lastPurchaseDayFlipTotalPrev`, `autoRebuyState[]`, `gameOver`

**State Writes:** `currentPrizePool`, `nextPrizePool` (set to 0), `futurePrizePool`, `lastPurchaseDayFlipTotal` (set to 0), `lastPurchaseDayFlipTotalPrev`, `claimablePool`, `claimableWinnings[]`, `whalePassClaims[]`, `ticketsOwedPacked[]`, `ticketQueue[]`

**Callers:** DegenerusGame via delegatecall (at level transition, start of jackpot phase)

**Callees:** `_futureKeepBps`, `_shouldFutureDump`, `_creditDgnrsCoinflip`, `_distributeYieldSurplus`

**ETH Flow:**
1. `currentPrizePool += nextPrizePool; nextPrizePool = 0` (always)
2. x00 levels: `futurePrizePool -> currentPrizePool` by 5-dice keep roll (0-100% stays in future, remainder moves to current)
3. Non-x00 levels: 1-in-1e15 chance to move 90% of `futurePrizePool -> currentPrizePool`
4. `_creditDgnrsCoinflip`: credits BURNIE coin proportional to prize pool (no ETH movement)
5. `_distributeYieldSurplus`: distributes stETH yield surplus (23% DGNRS, 23% vault, 46% future)

**Pool Consolidation Flow:**

| Step | Source | Destination | Trigger | Amount |
|------|--------|-------------|---------|--------|
| 1 | nextPrizePool | currentPrizePool | Always | 100% of nextPrizePool |
| 2a | futurePrizePool | currentPrizePool | x00 levels | (1 - keepBps/10000) * futurePrizePool |
| 2b | futurePrizePool | currentPrizePool | Non-x00 (1e-15 odds) | 90% of futurePrizePool |
| 3 | Yield surplus | claimablePool (VAULT) | Always (if surplus exists) | 23% of yield |
| 4 | Yield surplus | claimablePool (DGNRS) | Always (if surplus exists) | 23% of yield |
| 5 | Yield surplus | futurePrizePool | Always (if surplus exists) | 46% of yield |

**Invariants:**
- `nextPrizePool` is always zeroed
- `futurePrizePool` only reduced on x00 levels or rare dump
- keepBps range: 0-10000 (0-100%), from 5 dice each 0-3, sum 0-15, scaled to 10000
- `lastPurchaseDayFlipTotalPrev = lastPurchaseDayFlipTotal; lastPurchaseDayFlipTotal = 0`
- Yield surplus distribution preserves ~8% as buffer (2300+2300+4600 = 9200 out of 10000)

**NatSpec Accuracy:** CORRECT. NatSpec accurately describes the consolidation flow, x00 keep roll, and 1-in-1e15 dump.

**Gas Flags:** `_distributeYieldSurplus` reads `steth.balanceOf(address(this))` and `address(this).balance` -- external call and balance check. These are necessary and unavoidable. No redundant reads.

**Verdict:** CORRECT

---

### `payDailyCoinJackpot(uint24 lvl, uint256 randWord)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function payDailyCoinJackpot(uint24 lvl, uint256 randWord) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Current level; `randWord` (uint256): VRF entropy |
| **Returns** | None |

**State Reads:** `price`, `levelPrizePool[lvl-1]`, `lastDailyJackpotWinningTraits`, `lastDailyJackpotLevel`, `lastDailyJackpotDay`, `jackpotPhaseFlag`, `traitBurnTicket[]`, `deityBySymbol[]`, `dailyHeroWagers[]`, `ticketQueue[]`

**State Writes:** `lastDailyJackpotWinningTraits`, `lastDailyJackpotLevel`, `lastDailyJackpotDay` (via `_syncDailyWinningTraits`, only if traits not already cached for today)

**Callers:** DegenerusGame via delegatecall (during purchase/jackpot phase daily cycle)

**Callees:** `_calcDailyCoinBudget`, `_awardFarFutureCoinJackpot`, `_calculateDayIndex`, `_loadDailyWinningTraits`, `_rollWinningTraits`, `_syncDailyWinningTraits`, `_selectDailyCoinTargetLevel`, `_awardDailyCoinToTraitWinners`

**ETH Flow:** No ETH mutation. This distributes BURNIE coin only via `coin.creditFlip()` and `coin.creditFlipBatch()`.

**Invariants:**
- Coin budget: `(levelPrizePool[lvl-1] * PRICE_COIN_UNIT) / (price * 200)` = 0.5% of prize pool target in BURNIE
- Split: 25% far-future (ticketQueue holders, lvl+5 to lvl+99), 75% near-future (trait-matched, lvl to lvl+4)
- Near-future target level randomly selected from [lvl, lvl+4] with trait ticket existence check
- Uses `coin.creditFlipBatch()` in batches of 3 for gas efficiency
- Daily winning traits cached and reused if same day

**NatSpec Accuracy:** CORRECT. NatSpec describes daily BURNIE jackpot with 75/25 split accurately.

**Gas Flags:** Batching `creditFlipBatch` in groups of 3 is a sound optimization to reduce external call overhead. `_loadDailyWinningTraits` caches traits to avoid re-rolling.

**Verdict:** CORRECT

---

### `processTicketBatch(uint24 lvl)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function processTicketBatch(uint24 lvl) external returns (bool finished)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Level whose tickets should be processed |
| **Returns** | `bool`: True if all tickets for this level have been fully processed |

**State Reads:** `ticketQueue[lvl]`, `ticketLevel`, `ticketCursor`, `rngWordCurrent`, `ticketsOwedPacked[lvl][]`

**State Writes:** `ticketLevel`, `ticketCursor`, `ticketQueue[lvl]` (delete on completion), `ticketsOwedPacked[lvl][]`, `traitBurnTicket[lvl][]` (via assembly bulk writes)

**Callers:** DegenerusGame via delegatecall (advanceGame flow, iterative processing)

**Callees:** `_processOneTicketEntry`, `_generateTicketBatch` -> `_raritySymbolBatch`, `_finalizeTicketEntry`, `_resolveZeroOwedRemainder`, `_rollRemainder`

**ETH Flow:** No ETH mutation. This function processes ticket queues into trait burn tickets.

**Invariants:**
- Level switching: if `ticketLevel != lvl`, resets cursor and sets new level
- Writes budget: 550 SSTOREs per call (reduced by 35% for first batch due to cold storage)
- Each entry processes `take` tickets out of `owed`, resuming on next call if budget exhausted
- Fractional tickets (remainder) are rolled for probabilistic inclusion
- `ticketQueue[lvl]` deleted when all entries processed
- `finished == true` when `idx >= total` or queue is empty

**NatSpec Accuracy:** CORRECT. NatSpec describes gas budgeting, cold storage scaling, and iterative processing accurately.

**Gas Flags:**
- First-batch 35% scaling (`writesBudget *= 65%`) accounts for cold SLOAD costs
- `_raritySymbolBatch` uses inline assembly for bulk storage writes -- critical for gas efficiency when writing many trait tickets
- LCG-based trait generation in groups of 16 is highly efficient
- `_processOneTicketEntry` tracks base overhead (4 for first entry with small owed, 2 otherwise)
- The writes budget formula `((take <= 256) ? (take << 1) : (take + 256))` accounts for array growth costs

**Concern:** The `_raritySymbolBatch` function uses raw assembly to compute storage slots via `keccak256`. The slot calculation uses `add(levelSlot, traitId)` for the array length slot -- this relies on the EVM's nested mapping layout being `keccak256(traitId, keccak256(level, slot))`. However, the code computes `levelSlot = keccak256(lvl, traitBurnTicket.slot)` and then accesses `add(levelSlot, traitId)`. For a `mapping(uint24 => address[][256])`, the 256-element fixed array's slot for element `traitId` is `keccak256(lvl, slot) + traitId`. This is correct for a fixed-size array within a mapping -- Solidity stores fixed arrays contiguously starting at the mapping value slot.

**Verdict:** CORRECT
