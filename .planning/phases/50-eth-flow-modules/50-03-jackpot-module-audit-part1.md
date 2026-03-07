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

---

### `_distributeYieldSurplus(uint256 rngWord)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _distributeYieldSurplus(uint256 rngWord) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `rngWord` (uint256): VRF entropy for auto-rebuy in `_addClaimableEth` |
| **Returns** | None |

**State Reads:** `steth.balanceOf(address(this))`, `address(this).balance`, `currentPrizePool`, `nextPrizePool`, `claimablePool`, `futurePrizePool`, `autoRebuyState[VAULT]`, `autoRebuyState[DGNRS]`, `gameOver`, `level`

**State Writes:** `claimableWinnings[VAULT]`, `claimableWinnings[DGNRS]`, `claimablePool`, `futurePrizePool`, `nextPrizePool` (via auto-rebuy), `ticketsOwedPacked[]`, `ticketQueue[]`, `whalePassClaims[]`

**Callers:** `consolidatePrizePools`

**Callees:** `steth.balanceOf`, `_addClaimableEth` (x2 for VAULT and DGNRS)

**ETH Flow:**
- Compute yield surplus: `totalBal - obligations` where `totalBal = ETH balance + stETH balance`, `obligations = currentPrizePool + nextPrizePool + claimablePool + futurePrizePool`
- 23% to VAULT claimable: `(yieldPool * 2300) / 10000`
- 23% to DGNRS claimable: `(yieldPool * 2300) / 10000`
- 46% to futurePrizePool: `(yieldPool * 4600) / 10000`
- ~8% unextracted buffer: `10000 - (2300 + 2300 + 4600) = 800 bps`

**Percentage Verification:** 2300 + 2300 + 4600 = 9200 bps. 10000 - 9200 = 800 bps (8%) left unextracted as buffer. This matches the NatSpec comment "~8% buffer left unextracted". VERIFIED.

**Invariants:**
- No-op if `totalBal <= obligations` (no surplus to distribute)
- `claimablePool += claimableDelta` only if `claimableDelta != 0`
- `futurePrizePool += futureShare` only if `futureShare != 0`
- Auto-rebuy may route stakeholder shares to tickets instead of claimable

**NatSpec Accuracy:** CORRECT. Comments state "23% each for DGNRS and Vault" and "46% to future prize pool (~8% buffer left unextracted)".

**Gas Flags:** Two external calls to `_addClaimableEth` (which may trigger auto-rebuy with further external calls). stETH `balanceOf` is an external call. All necessary.

**Verdict:** CORRECT

---

### `_addClaimableEth(address beneficiary, uint256 weiAmount, uint256 entropy)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _addClaimableEth(address beneficiary, uint256 weiAmount, uint256 entropy) private returns (uint256 claimableDelta)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `beneficiary` (address): Recipient; `weiAmount` (uint256): Wei to credit; `entropy` (uint256): RNG for auto-rebuy |
| **Returns** | `uint256`: Amount to add to claimablePool |

**State Reads:** `gameOver`, `autoRebuyState[beneficiary]`

**State Writes:** `claimableWinnings[beneficiary]` (via `_creditClaimable`), or auto-rebuy state changes

**Callers:** `_distributeYieldSurplus`, `_resolveTraitWinners`, `_processDailyEthChunk`, `_creditJackpot`

**Callees:** `_processAutoRebuy` (if auto-rebuy enabled and not gameOver), `_creditClaimable` (otherwise)

**ETH Flow:**
- If `gameOver == true` or auto-rebuy disabled: `weiAmount -> claimableWinnings[beneficiary]`, returns `weiAmount`
- If auto-rebuy enabled and `!gameOver`: delegates to `_processAutoRebuy`, returns reserved amount only

**Invariants:**
- Returns 0 if `weiAmount == 0`
- `gameOver` check prevents post-game auto-rebuy (tickets worthless after game ends)
- Return value represents the amount that should be added to `claimablePool` by the caller

**NatSpec Accuracy:** CORRECT. Describes auto-rebuy branch and gameOver guard.

**Gas Flags:** None. Minimal branching logic.

**Verdict:** CORRECT

---

### `_processAutoRebuy(address player, uint256 newAmount, uint256 entropy, AutoRebuyState memory state)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _processAutoRebuy(address player, uint256 newAmount, uint256 entropy, AutoRebuyState memory state) private returns (uint256 claimableDelta)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): Winning player; `newAmount` (uint256): New winnings in wei; `entropy` (uint256): RNG seed; `state` (AutoRebuyState): Player's auto-rebuy config |
| **Returns** | `uint256`: Amount to add to claimablePool (reserved take-profit only) |

**State Reads:** `level`, `autoRebuyState[player]` (passed in), `price` (via PriceLookupLib)

**State Writes:** `futurePrizePool` (75% chance: +ethSpent), `nextPrizePool` (25% chance: +ethSpent), `claimableWinnings[player]` (reserved amount), `ticketsOwedPacked[]`, `ticketQueue[]`

**Callers:** `_addClaimableEth`

**Callees:** `_calcAutoRebuy` (from PayoutUtils), `_queueTickets`, `_creditClaimable`

**ETH Flow:**
1. Take profit: `reserved = (newAmount / takeProfit) * takeProfit` (truncated to take-profit granularity)
2. Rebuy amount: `newAmount - reserved`
3. Level offset: 1-4 levels ahead (entropy-derived). +1 = nextPrizePool (25%), +2/+3/+4 = futurePrizePool (75%)
4. Ticket price: `PriceLookupLib.priceForLevel(targetLevel) >> 2` (ticket = 1/4 level price)
5. Base tickets: `rebuyAmount / ticketPrice`
6. Bonus: 30% normal (`13000` bps), 45% afKing (`14500` bps)
7. `ethSpent = baseTickets * ticketPrice` (no bonus applied to ETH, only tickets)
8. Fractional dust (rebuyAmount - ethSpent) is dropped

**Auto-Rebuy ETH Accounting:**
- `ethSpent` goes to `futurePrizePool` or `nextPrizePool` (backing the tickets)
- `reserved` goes to `claimableWinnings[player]`
- `newAmount - ethSpent - reserved` = dust, dropped unconditionally
- Return value = `reserved` (only the claimed portion adds to claimablePool liability)

**Note on dust:** The dust amount is `(newAmount - reserved) - ethSpent = (newAmount - reserved) % ticketPrice`. This dust is NOT accounted for -- it is neither credited to the player nor added to any pool. This creates a small ETH leak where `sum(pools) + claimablePool < address(this).balance`. However, this dust is captured by the yield surplus mechanism (`_distributeYieldSurplus`), which measures `totalBal - obligations`. The dust becomes part of the yield surplus. This is an intentional design decision, not a bug.

**Invariants:**
- If `_calcAutoRebuy` returns `hasTickets == false`, full amount goes to claimable (fallback path)
- Bonus BPS are `13000` (130%) and `14500` (145%) -- these are multiplied by baseTickets and divided by 10000, giving 1.3x and 1.45x ticket counts. The naming `bonusBps` is slightly misleading since these are total multipliers, not bonus-only. However, `_calcAutoRebuy` computes `bonusTickets = (baseTickets * bonusBps) / 10000`, so with 13000 bps this gives 1.3x base = 30% bonus. This is correct.
- `ticketCount` capped at `type(uint32).max`

**NatSpec Accuracy:** CORRECT. States "fixed 30% bonus by default, 45% when afKing is active".

**Gas Flags:** `_calcAutoRebuy` is `pure` -- no storage reads. Good gas efficiency.

**Verdict:** CORRECT

---

### `_hasTraitTickets(uint24 lvl, uint32 packedTraits)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _hasTraitTickets(uint24 lvl, uint32 packedTraits) private view returns (bool)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `lvl` (uint24): Level to check; `packedTraits` (uint32): 4 packed trait IDs |
| **Returns** | `bool`: True if any trait has tickets or virtual deity entries |

**State Reads:** `traitBurnTicket[lvl][trait].length`, `deityBySymbol[fullSymId]`

**State Writes:** None

**Callers:** `_validateTicketBudget`, `_selectDailyCoinTargetLevel`, `_selectCarryoverSourceOffset` (via `_hasActualTraitTickets`, `_highestCarryoverSourceOffset`)

**Callees:** `JackpotBucketLib.unpackWinningTraits`

**ETH Flow:** None.

**Invariants:**
- Returns true if ANY of the 4 traits has non-empty ticket array OR a virtual deity entry
- Virtual deity check: `fullSymId = (trait >> 6) * 8 + (trait & 0x07)`. This maps traitId (quadrant 2 bits, color 3 bits, symbol 3 bits) to a flat symbol index (0-31). Deity entries are checked if `fullSymId < 32`.
- Early exit on first found trait (short-circuit)

**NatSpec Accuracy:** Minimal but correct.

**Gas Flags:** Up to 4 SLOAD (array length) + 4 SLOAD (deity mapping) in worst case. Acceptable.

**Verdict:** CORRECT

---

### `_validateTicketBudget(uint256 budget, uint24 lvl, uint32 packedTraits)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _validateTicketBudget(uint256 budget, uint24 lvl, uint32 packedTraits) private view returns (uint256)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `budget` (uint256): Proposed budget; `lvl` (uint24): Level; `packedTraits` (uint32): Winning traits |
| **Returns** | `uint256`: budget if valid, 0 if no trait tickets exist |

**State Reads:** Via `_hasTraitTickets`

**State Writes:** None

**Callers:** `payDailyJackpot` (daily and carryover lootbox budgets)

**Callees:** `_hasTraitTickets`

**ETH Flow:** None.

**Invariants:**
- Returns 0 if `budget != 0 && !_hasTraitTickets(lvl, packedTraits)` (no recipients = zero budget)
- Returns budget unchanged if budget is 0 or trait tickets exist
- Logic: `(budget != 0 && !_hasTraitTickets) ? 0 : budget` -- this correctly handles all cases

**NatSpec Accuracy:** Minimal but correct ("Zeros budget if no trait tickets exist").

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_budgetToTicketUnits(uint256 budget, uint24 lvl)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _budgetToTicketUnits(uint256 budget, uint24 lvl) private pure returns (uint256)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `budget` (uint256): ETH budget; `lvl` (uint24): Level for price lookup |
| **Returns** | `uint256`: Number of ticket units the budget can buy |

**State Reads:** None (pure)

**State Writes:** None

**Callers:** `payDailyJackpot`, `_distributeLootboxAndTickets`

**Callees:** `PriceLookupLib.priceForLevel`

**ETH Flow:** None.

**Invariants:**
- Returns 0 if budget is 0 or ticketPrice is 0
- Formula: `(budget << 2) / ticketPrice` = `(budget * 4) / ticketPrice`
- This gives the number of tickets at `ticketPrice / 4` each (ticket cost = 1/4 of level price)
- Consistent with `PriceLookupLib.priceForLevel(lvl) >> 2` used elsewhere for ticket pricing

**NatSpec Accuracy:** CORRECT. "Tickets cost ticketPrice/4".

**Gas Flags:** Pure function, no storage access.

**Verdict:** CORRECT

---

### `_distributeLootboxAndTickets(uint24 lvl, uint32 winningTraitsPacked, uint256 lootboxBudget, uint256 randWord)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _distributeLootboxAndTickets(uint24 lvl, uint32 winningTraitsPacked, uint256 lootboxBudget, uint256 randWord) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Current level; `winningTraitsPacked` (uint32): Packed trait IDs; `lootboxBudget` (uint256): ETH to convert to tickets; `randWord` (uint256): Entropy |
| **Returns** | None |

**State Reads:** Via `_distributeTicketJackpot`

**State Writes:** `nextPrizePool`, `ticketsOwedPacked[]`, `ticketQueue[]`

**Callers:** `payDailyJackpot` (early-burn path, isEthDay)

**Callees:** `_budgetToTicketUnits`, `_distributeTicketJackpot`

**ETH Flow:**
- `nextPrizePool += lootboxBudget` (ETH backing for tickets)
- Ticket units calculated for `lvl + 1` price
- Tickets distributed to trait winners at current level

**Invariants:**
- Lootbox budget adds to nextPrizePool (tickets are for future levels)
- Ticket units at `lvl + 1` price but winners drawn from `lvl` ticket pool
- Uses salt 242 for entropy differentiation

**NatSpec Accuracy:** Minimal but correct.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_distributeTicketJackpot(uint24 lvl, uint32 winningTraitsPacked, uint256 ticketUnits, uint256 entropy, uint16 maxWinners, uint8 saltBase)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _distributeTicketJackpot(uint24 lvl, uint32 winningTraitsPacked, uint256 ticketUnits, uint256 entropy, uint16 maxWinners, uint8 saltBase) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Level for winner selection; `winningTraitsPacked` (uint32): Traits; `ticketUnits` (uint256): Total tickets to distribute; `entropy` (uint256): RNG; `maxWinners` (uint16): Winner cap; `saltBase` (uint8): Entropy salt |
| **Returns** | None |

**State Reads:** `traitBurnTicket[lvl][]`, `deityBySymbol[]`

**State Writes:** `ticketsOwedPacked[]`, `ticketQueue[]`

**Callers:** `_distributeLootboxAndTickets`, `payDailyJackpotCoinAndTickets`

**Callees:** `JackpotBucketLib.unpackWinningTraits`, `_computeBucketCounts`, `_distributeTicketsToBuckets`

**ETH Flow:** None (ticket distribution only).

**Invariants:**
- No-op if `ticketUnits == 0`
- Cap: `min(maxWinners, ticketUnits)` to avoid allocating more winners than tickets
- Uses `_computeBucketCounts` which divides winners evenly across active trait buckets
- No-op if `activeCount == 0`

**NatSpec Accuracy:** Minimal but correct.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_distributeTicketsToBuckets(uint24 lvl, uint8[4] traitIds, uint16[4] counts, uint256 ticketUnits, uint256 entropy, uint16 cap, uint8 saltBase)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _distributeTicketsToBuckets(uint24 lvl, uint8[4] memory traitIds, uint16[4] memory counts, uint256 ticketUnits, uint256 entropy, uint16 cap, uint8 saltBase) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Level; `traitIds` (uint8[4]): Trait IDs; `counts` (uint16[4]): Winners per bucket; `ticketUnits` (uint256): Total tickets; `entropy` (uint256): RNG; `cap` (uint16): Total winner cap; `saltBase` (uint8): Salt |
| **Returns** | None |

**State Reads:** Via `_distributeTicketsToBucket`

**State Writes:** Via `_distributeTicketsToBucket`

**Callers:** `_distributeTicketJackpot`

**Callees:** `EntropyLib.entropyStep`, `_distributeTicketsToBucket`

**ETH Flow:** None.

**Invariants:**
- `baseUnits = ticketUnits / cap` (even distribution)
- `distParams` packs `extra = ticketUnits % cap` (first `extra` winners get +1 unit) and `offset = entropy % cap` (randomized starting position for +1 distribution)
- `globalIdx` tracks position across all buckets for fair +1 distribution
- Skips buckets with 0 counts

**NatSpec Accuracy:** Minimal but correct.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_distributeTicketsToBucket(uint24 lvl, uint8 traitId, uint16 count, uint256 entropy, uint8 salt, uint256 baseUnits, uint256 distParams, uint16 cap, uint256 startIdx)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _distributeTicketsToBucket(uint24 lvl, uint8 traitId, uint16 count, uint256 entropy, uint8 salt, uint256 baseUnits, uint256 distParams, uint16 cap, uint256 startIdx) private returns (uint256 endIdx)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Level; `traitId` (uint8): Trait; `count` (uint16): Winners; `entropy` (uint256): RNG; `salt` (uint8): Salt; `baseUnits` (uint256): Tickets per winner; `distParams` (uint256): Packed extra/offset; `cap` (uint16): Total cap; `startIdx` (uint256): Global index |
| **Returns** | `uint256`: Updated global index (endIdx) |

**State Reads:** `traitBurnTicket[lvl][traitId]`, `deityBySymbol[]`

**State Writes:** `ticketsOwedPacked[]`, `ticketQueue[]`

**Callers:** `_distributeTicketsToBuckets`

**Callees:** `_randTraitTicket`, `_queueTickets`

**ETH Flow:** None.

**Invariants:**
- Count capped at `MAX_BUCKET_WINNERS` (250)
- Winners selected from trait pool (duplicates allowed)
- Each winner gets `baseUnits + (1 if cursor < extra)` tickets
- Cursor wraps at `cap` to ensure fair +1 distribution
- Tickets queued at `lvl + 1` (next level)
- Units capped at `type(uint32).max`
- No-op for address(0) winners or zero units

**NatSpec Accuracy:** Minimal but correct.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_computeBucketCounts(uint24 lvl, uint8[4] traitIds, uint16 maxWinners, uint256 entropy)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _computeBucketCounts(uint24 lvl, uint8[4] memory traitIds, uint16 maxWinners, uint256 entropy) private view returns (uint16[4] memory counts, uint8 activeCount)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `lvl` (uint24): Level; `traitIds` (uint8[4]): Trait IDs; `maxWinners` (uint16): Total winner cap; `entropy` (uint256): RNG |
| **Returns** | `counts` (uint16[4]): Winners per bucket; `activeCount` (uint8): Number of active buckets |

**State Reads:** `traitBurnTicket[lvl][trait].length`, `deityBySymbol[]`

**State Writes:** None

**Callers:** `_distributeTicketJackpot`, `_awardDailyCoinToTraitWinners`

**Callees:** None (self-contained logic)

**ETH Flow:** None.

**Invariants:**
- Active buckets: traits with ticket entries OR virtual deity entries
- Winners split evenly: `baseCount = maxWinners / activeCount`
- Remainder distributed starting from `entropy & 3` position
- `sum(counts) == maxWinners` (exact allocation, no waste)
- Returns (all zeros, 0) if no active buckets

**NatSpec Accuracy:** Minimal but correct.

**Gas Flags:** Up to 8 SLOADs (4 array lengths + 4 deity lookups). Acceptable.

**Verdict:** CORRECT

---

### `_runEarlyBirdLootboxJackpot(uint24 lvl, uint256 rngWord)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _runEarlyBirdLootboxJackpot(uint24 lvl, uint256 rngWord) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Target level (typically current + 1); `rngWord` (uint256): VRF entropy |
| **Returns** | None |

**State Reads:** `futurePrizePool`, `traitBurnTicket[lvl][]`, `deityBySymbol[]`

**State Writes:** `futurePrizePool` (deducted 3%), `nextPrizePool` (receives full budget), `ticketsOwedPacked[]`, `ticketQueue[]`

**Callers:** `payDailyJackpot` (day 1 only, replaces carryover)

**Callees:** `PriceLookupLib.priceForLevel`, `EntropyLib.entropyStep`, `_randTraitTicket`, `_queueTickets`

**ETH Flow:**
1. `reserveContribution = (futurePrizePool * 300) / 10000` = 3% from unified reserve
2. `futurePrizePool -= reserveContribution`
3. For each of 100 winners: select random trait ticket holder at current level, roll level offset 0-4, convert `perWinnerEth` to tickets at that level's price
4. `nextPrizePool += totalBudget` (full 3% budget backs tickets in next pool)

**Invariants:**
- Fixed 100 winners max
- Even split: `perWinnerEth = totalBudget / 100`
- Random trait selection (uniform, not burn-weighted -- `uint8(entropy)` gives uniform trait ID)
- Level offset: `entropy % 5` gives 0-4 offset from base level
- No-op if `totalBudget == 0`
- Budget goes to `nextPrizePool` AFTER ticket distribution (backing the tickets)
- Winners drawn from `traitBurnTicket[lvl]` (the parameter `lvl`, which is `currentLevel + 1`)

**NatSpec Accuracy:** CORRECT.

**Gas Flags:** Fixed 100 iterations with 2 entropy steps + 1 winner selection each. This is bounded and safe for gas. PriceLookupLib prices cached in `levelPrices[5]` memory array -- good optimization.

**Verdict:** CORRECT

---

### `_futureKeepBps(uint256 rngWord)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _futureKeepBps(uint256 rngWord) private pure returns (uint256)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `rngWord` (uint256): VRF entropy |
| **Returns** | `uint256`: Keep percentage in basis points (0-10000) |

**State Reads:** None (pure)

**State Writes:** None

**Callers:** `consolidatePrizePools`

**Callees:** `keccak256`

**ETH Flow:** None (calculation only).

**Dice Math Verification:**
- 5 dice, each `seed >> (k*16) % 4` gives values 0-3
- Total range: 0 to 15 (5 dice x max 3)
- `keepBps = (total * 10000) / 15`
- Minimum: `(0 * 10000) / 15 = 0` (0% keep = 100% moved)
- Maximum: `(15 * 10000) / 15 = 10000` (100% keep = 0% moved)
- Average: `(7.5 * 10000) / 15 = 5000` (50% keep = 50% moved)
- Distribution: Each die averages 1.5, so 5 dice average 7.5. The distribution is roughly normal (sum of uniforms). VERIFIED.

**Invariants:**
- Returns 0-10000 (0-100%)
- Seed is domain-separated by `FUTURE_KEEP_TAG`
- 16-bit shifts between dice values provide independent draws from different parts of the hash

**NatSpec Accuracy:** CORRECT. "5 dice with zeros (0-3), mapped to 0-100% keep (avg 50%)".

**Gas Flags:** Single keccak256 + 5 modulo operations. Minimal.

**Verdict:** CORRECT

---

### `_shouldFutureDump(uint256 rngWord)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _shouldFutureDump(uint256 rngWord) private pure returns (bool)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `rngWord` (uint256): VRF entropy |
| **Returns** | `bool`: True if the dump should occur |

**State Reads:** None (pure)

**State Writes:** None

**Callers:** `consolidatePrizePools`

**Callees:** `keccak256`

**ETH Flow:** None (calculation only).

**Modulo Verification:**
- `seed % FUTURE_DUMP_ODDS == 0` where `FUTURE_DUMP_ODDS = 1_000_000_000_000_000` (1e15)
- Probability: 1 in 1 quadrillion
- keccak256 output is uniformly distributed over uint256, so `seed % 1e15 == 0` has exactly 1/1e15 probability. VERIFIED.
- Domain-separated by `FUTURE_DUMP_TAG`

**NatSpec Accuracy:** CORRECT. "1 in 1e15 chance to dump 90% of future into current on normal levels".

**Gas Flags:** Single keccak256 + 1 modulo. Minimal.

**Verdict:** CORRECT

---

## ETH Mutation Path Map (Part 1)

### Pool Consolidation Flow

| Step | Source | Destination | Trigger | Function | Amount |
|------|--------|-------------|---------|----------|--------|
| 1 | nextPrizePool | currentPrizePool | Level transition (always) | `consolidatePrizePools` | 100% of nextPrizePool |
| 2a | futurePrizePool | currentPrizePool | x00 levels | `consolidatePrizePools` | (1 - keepBps/10000) x futurePrizePool |
| 2b | futurePrizePool | currentPrizePool | Non-x00 (1e-15 odds) | `consolidatePrizePools` | 90% of futurePrizePool |
| 3 | Yield surplus | claimablePool (VAULT) | Surplus exists | `_distributeYieldSurplus` | 23% of surplus |
| 4 | Yield surplus | claimablePool (DGNRS) | Surplus exists | `_distributeYieldSurplus` | 23% of surplus |
| 5 | Yield surplus | futurePrizePool | Surplus exists | `_distributeYieldSurplus` | 46% of surplus |
| 6 | (8% surplus) | Unextracted buffer | Surplus exists | `_distributeYieldSurplus` | 8% of surplus |

### Daily Jackpot ETH Flow

| Step | Source | Destination | Trigger | Function | Amount |
|------|--------|-------------|---------|----------|--------|
| 1 | currentPrizePool | dailyLootboxBudget -> nextPrizePool | Fresh daily start | `payDailyJackpot` | 20% of daily BPS slice |
| 2 | futurePrizePool | reserveSlice (carryover pool) | Days 2-4 (not day 1) | `payDailyJackpot` | 1% of futurePrizePool |
| 3 | reserveSlice | carryoverLootboxBudget -> nextPrizePool | Carryover has tickets | `payDailyJackpot` | 50% of reserveSlice |
| 4 | currentPrizePool | claimablePool (winners) | Phase 0 chunk | `_processDailyEthChunk` | Per-winner share |
| 5 | dailyCarryoverEthPool | claimablePool (winners) | Phase 1 chunk | `_processDailyEthChunk` | Per-winner share |
| 6 | (Phase 0/1 winners) | futurePrizePool/nextPrizePool | Auto-rebuy active | `_processAutoRebuy` | ethSpent portion |
| 7 | (Solo bucket winner) | futurePrizePool (whale pass) | Solo bucket >= 1 half-pass | `_processSoloBucketWinner` | 25% of solo share |

**Daily BPS Slice (days 1-4):** Random 6%-14% of `currentPrizePool` (avg 10%). Day 5: 100%.

**Compressed Jackpot:** BPS doubled on compressed days (counterStep=2), combining two days' payouts.

### Early-Burn Jackpot ETH Flow

| Step | Source | Destination | Trigger | Function | Amount |
|------|--------|-------------|---------|----------|--------|
| 1 | futurePrizePool | ethDaySlice | Every 3rd purchase day | `payDailyJackpot` | 1% of futurePrizePool |
| 2 | ethDaySlice | lootboxBudget -> nextPrizePool | Trait tickets exist | `_distributeLootboxAndTickets` | 75% of ethDaySlice |
| 3 | ethDaySlice | claimablePool (winners) | Via _executeJackpot | `_executeJackpot` | Remaining 25% |

### Early-Bird Lootbox Flow (Day 1 Only)

| Step | Source | Destination | Trigger | Function | Amount |
|------|--------|-------------|---------|----------|--------|
| 1 | futurePrizePool | totalBudget | Day 1 jackpot | `_runEarlyBirdLootboxJackpot` | 3% of futurePrizePool |
| 2 | totalBudget | nextPrizePool (ticket backing) | Always | `_runEarlyBirdLootboxJackpot` | 100% of totalBudget |
| 3 | (tickets) | ticketQueue[lvl+0..4] | Per winner | `_runEarlyBirdLootboxJackpot` | perWinnerEth / ticketPrice |

### Yield Surplus Flow

| Step | Source | Destination | Trigger | Function | Amount |
|------|--------|-------------|---------|----------|--------|
| 1 | stETH appreciation | yieldPool (calculated) | totalBal > obligations | `_distributeYieldSurplus` | totalBal - obligations |
| 2 | yieldPool | claimableWinnings[VAULT] | stakeholderShare != 0 | `_addClaimableEth` | 23% |
| 3 | yieldPool | claimableWinnings[DGNRS] | stakeholderShare != 0 | `_addClaimableEth` | 23% |
| 4 | yieldPool | futurePrizePool | futureShare != 0 | `_distributeYieldSurplus` | 46% |
| 5 | yieldPool | (unextracted buffer) | Always | (implicit) | 8% |

### Auto-Rebuy Flow

| Step | Source | Destination | Trigger | Function | Amount |
|------|--------|-------------|---------|----------|--------|
| 1 | Jackpot winnings | reserved (take-profit) | takeProfit != 0 | `_processAutoRebuy` | Truncated to takeProfit granularity |
| 2 | reserved | claimableWinnings[player] | reserved != 0 | `_creditClaimable` | Full reserved amount |
| 3 | rebuyAmount | ticketCount tickets | hasTickets == true | `_queueTickets` | baseTickets x ticketPrice |
| 4 | ethSpent | nextPrizePool | targetLevel = currentLevel + 1 (25%) | `_processAutoRebuy` | ethSpent |
| 5 | ethSpent | futurePrizePool | targetLevel = currentLevel + 2..4 (75%) | `_processAutoRebuy` | ethSpent |
| 6 | dust | (dropped) | rebuyAmount % ticketPrice | (implicit) | rebuyAmount - ethSpent |

**Bonus Tickets:** 30% bonus (13000 bps) normally, 45% bonus (14500 bps) with afKing. Bonus applied to ticket count only, NOT to ethSpent.

---

## Findings Summary (Part 1)

| Severity | Count | Details |
|----------|-------|---------|
| BUG | 0 | None found |
| CONCERN | 1 | `_raritySymbolBatch` assembly storage slot calculation is correct but relies on EVM fixed-array-within-mapping layout -- any Solidity version change to storage layout would break this |
| GAS | 0 | No unnecessary computation found. Gas optimizations (budget/5, pool/100, LCG batch generation, creditFlipBatch) are all sound |
| CORRECT | 21 | All 21 functions in Part 1 scope verified correct |

### Concern Details

**CONCERN-1: Assembly storage slot calculation in `processTicketBatch` -> `_raritySymbolBatch`**
- **Function:** `_raritySymbolBatch` (line 2143)
- **Issue:** Uses raw assembly to compute storage slots for `traitBurnTicket[lvl][traitId]`. The calculation `levelSlot = keccak256(lvl, traitBurnTicket.slot)` then `elem = add(levelSlot, traitId)` assumes the 256-element fixed-size array within the mapping is stored contiguously at the mapping value slot. This is correct for Solidity 0.8.34 but is an implicit coupling to EVM storage layout.
- **Risk:** Low. Solidity storage layout has been stable since 0.5.x and is part of the ABI specification. The contract is not upgradeable, so a Solidity version change would require a full redeploy regardless.
- **Impact:** None at current version. Informational only.

### Positive Observations

1. **Comprehensive resumability:** The daily jackpot's two-phase chunking with 6 cursor/state variables provides reliable mid-execution resume. Each advanceGame call picks up exactly where the last left off.

2. **Sound ETH accounting:** All ETH flows are traceable. Dust from auto-rebuy is captured by the yield surplus mechanism. No ETH is permanently lost.

3. **Consistent entropy derivation:** All random selections use domain-separated entropy via tags and XOR mixing. No entropy reuse across different selection contexts.

4. **Gas-bounded operations:** processTicketBatch uses writes-budget accounting, daily jackpot uses units-budget accounting, and winner counts are hard-capped. All operations are bounded.

5. **gameOver guard on auto-rebuy:** `_addClaimableEth` correctly prevents auto-rebuy when `gameOver == true`, ensuring post-game winnings are claimable as ETH.

6. **Solo bucket whale pass conversion:** `_processSoloBucketWinner` correctly applies 75/25 split only when 25% covers at least one half-pass, falling back to 100% ETH otherwise.
