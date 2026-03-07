# DegenerusGameStorage.sol -- Storage & Delegatecall Dispatch Audit

**Contract:** DegenerusGameStorage
**File:** contracts/storage/DegenerusGameStorage.sol
**Lines:** 1383
**Solidity:** 0.8.34
**Inherited by:** DegenerusGame (via DegenerusGameMintStreakUtils), all 10 delegatecall modules
**Audit date:** 2026-03-07

## Summary

Shared storage layout for DegenerusGame and all 10 delegatecall modules. Contains ~130+ storage variables (including packed slot fields), 7 constants, 7 events, 2 structs, and 11 internal functions. All modules inherit this contract to share the same storage layout, enabling delegatecall from DegenerusGame. Storage slots are assigned sequentially by the EVM; Slots 0-1 are manually packed for gas efficiency.

---

## Constants

### `PRICE_COIN_UNIT`

| Field | Value |
|-------|-------|
| **Type** | uint256 |
| **Value** | 1000 ether (1e21) |
| **Purpose** | Conversion factor for BURNIE token amounts. price / PRICE_COIN_UNIT = BURNIE per mint |

### `TICKET_SCALE`

| Field | Value |
|-------|-------|
| **Type** | uint256 |
| **Value** | 100 |
| **Purpose** | Scale factor for fractional ticket calculations (2 decimal places). 1 ticket = 100 scaled units |

### `LOOTBOX_CLAIM_THRESHOLD`

| Field | Value |
|-------|-------|
| **Type** | uint256 |
| **Value** | 5 ether |
| **Purpose** | ETH threshold for whale pass claim eligibility from lootbox wins |

### `BOOTSTRAP_PRIZE_POOL`

| Field | Value |
|-------|-------|
| **Type** | uint256 |
| **Value** | 50 ether |
| **Purpose** | Bootstrap prize pool target at level 1 (fallback for levelPrizePool[0]) |

### `EARLYBIRD_END_LEVEL`

| Field | Value |
|-------|-------|
| **Type** | uint24 |
| **Value** | 3 |
| **Purpose** | Level at which earlybird DGNRS rewards end (exclusive) |

### `EARLYBIRD_TARGET_ETH`

| Field | Value |
|-------|-------|
| **Type** | uint256 |
| **Value** | 1,000 ether |
| **Purpose** | Total ETH target for earlybird DGNRS emission curve |

### Note: Additional Constants in DegenerusGame.sol

DegenerusGame.sol defines additional private constants not in Storage: `DEPLOY_IDLE_TIMEOUT_DAYS` (912), `AFKING_KEEP_MIN_ETH` (5 ether), `AFKING_KEEP_MIN_COIN` (20,000 ether), `AFKING_LOCK_LEVELS` (5), `PURCHASE_TO_FUTURE_BPS` (1000), `AFFILIATE_DGNRS_LEVEL_BPS` (500), `COINFLIP_BOUNTY_DGNRS_BPS` (50), `AFFILIATE_DGNRS_DEITY_BONUS_BPS` (2000), `AFFILIATE_DGNRS_MIN_SCORE` (10 ether), `DEITY_PASS_ACTIVITY_BONUS_BPS` (8000), `PASS_STREAK_FLOOR_POINTS` (50), `PASS_MINT_COUNT_FLOOR_POINTS` (25). These do not occupy storage slots.

---

## Storage Variables

### SLOT 0: Level Timing, Batching, and FSM (Packed -- 32 bytes)

### `levelStartTime`

| Field | Value |
|-------|-------|
| **Type** | uint48 |
| **Visibility** | internal |
| **Slot** | 0, bytes [0:6] |
| **Initial Value** | block.timestamp (set in constructor) |
| **Purpose** | Timestamp when current level opened for purchase phase. Used for inactivity guard timing and purchase-phase daily jackpots |

**Read by:** AdvanceModule (R), JackpotModule (R), DegenerusGame (R)
**Written by:** AdvanceModule (W), DegenerusGame constructor (W)
**Packed with:** dailyIdx, rngRequestTime, level, jackpotPhaseFlag (Slot 0)
**Invariants:** Always non-zero after deployment. uint48 overflow: year 8.9M

### `dailyIdx`

| Field | Value |
|-------|-------|
| **Type** | uint48 |
| **Visibility** | internal |
| **Slot** | 0, bytes [6:12] |
| **Initial Value** | 0 |
| **Purpose** | Monotonically increasing game-relative day counter. Keys RNG words and tracks daily jackpot eligibility |

**Read by:** AdvanceModule (R), JackpotModule (R), MintModule (R), LootboxModule (R), DegenerusGame (R), DecimatorModule (R), BoonModule (R)
**Written by:** AdvanceModule (W)
**Packed with:** levelStartTime, rngRequestTime, level, jackpotPhaseFlag (Slot 0)
**Invariants:** Monotonically increasing, never decremented

### `rngRequestTime`

| Field | Value |
|-------|-------|
| **Type** | uint48 |
| **Visibility** | internal |
| **Slot** | 0, bytes [12:18] |
| **Initial Value** | 0 |
| **Purpose** | Timestamp of last VRF request. Non-zero = request in-flight or awaiting processing. Used for 18h timeout detection |

**Read by:** AdvanceModule (R)
**Written by:** AdvanceModule (W)
**Packed with:** levelStartTime, dailyIdx, level, jackpotPhaseFlag (Slot 0)
**Invariants:** 0 when no request pending, non-zero when VRF in-flight

### `level`

| Field | Value |
|-------|-------|
| **Type** | uint24 |
| **Visibility** | public |
| **Slot** | 0, bytes [26:29] |
| **Initial Value** | 0 |
| **Purpose** | Current jackpot level (starts at 0). Purchase phase targets level + 1 |

**Read by:** All modules (R), DegenerusGame (R)
**Written by:** AdvanceModule (W)
**Packed with:** levelStartTime, dailyIdx, rngRequestTime, jackpotPhaseFlag (Slot 0)
**Invariants:** Monotonically increasing, uint24 supports ~16M levels

### `jackpotPhaseFlag`

| Field | Value |
|-------|-------|
| **Type** | bool |
| **Visibility** | internal |
| **Slot** | 0, bytes [29:30] |
| **Initial Value** | false (purchase phase) |
| **Purpose** | Game phase: false = PURCHASE, true = JACKPOT |

**Read by:** AdvanceModule (R), JackpotModule (R), MintModule (R), DegenerusGame (R), EndgameModule (R), WhaleModule (R), DecimatorModule (R)
**Written by:** AdvanceModule (W)
**Packed with:** levelStartTime, dailyIdx, rngRequestTime, level (Slot 0)
**Invariants:** Only transitions via advanceGame flow. Once gameOver=true, this becomes irrelevant

---

### SLOT 1: Cursors, Counters, and Boolean Flags (Packed -- 18 bytes used, 14 padding)

### `jackpotCounter`

| Field | Value |
|-------|-------|
| **Type** | uint8 |
| **Visibility** | internal |
| **Slot** | 1, bytes [0:1] |
| **Initial Value** | 0 |
| **Purpose** | Count of jackpots processed this level. Capped at 5 (JACKPOT_LEVEL_CAP); triggers level advancement |

**Read by:** AdvanceModule (R), JackpotModule (R)
**Written by:** AdvanceModule (W), JackpotModule (W)
**Packed with:** earlyBurnPercent, poolConsolidationDone, etc. (Slot 1)
**Invariants:** 0-5 range, reset at level start

### `earlyBurnPercent`

| Field | Value |
|-------|-------|
| **Type** | uint8 |
| **Visibility** | internal |
| **Slot** | 1, bytes [1:2] |
| **Initial Value** | 0 |
| **Purpose** | Previous pool percentage for early burn reward calculation in jackpot module |

**Read by:** JackpotModule (R)
**Written by:** JackpotModule (W)
**Packed with:** jackpotCounter, poolConsolidationDone, etc. (Slot 1)
**Invariants:** 0-100 range (practically)

### `poolConsolidationDone`

| Field | Value |
|-------|-------|
| **Type** | bool |
| **Visibility** | internal |
| **Slot** | 1, bytes [2:3] |
| **Initial Value** | false |
| **Purpose** | Prevents double-execution of prize pool consolidation. Reset at level transition |

**Read by:** AdvanceModule (R)
**Written by:** AdvanceModule (W)
**Packed with:** jackpotCounter, earlyBurnPercent, etc. (Slot 1)
**Invariants:** Set true once per level, reset at transition

### `lastPurchaseDay`

| Field | Value |
|-------|-------|
| **Type** | bool |
| **Visibility** | internal |
| **Slot** | 1, bytes [3:4] |
| **Initial Value** | false |
| **Purpose** | True when prize target is met for current level. Triggers fast-track to jackpot window |

**Read by:** AdvanceModule (R), DegenerusGame (R)
**Written by:** AdvanceModule (W)
**Packed with:** Slot 1 booleans
**Invariants:** Set when target met, cleared at level transition

### `decWindowOpen`

| Field | Value |
|-------|-------|
| **Type** | bool |
| **Visibility** | internal |
| **Slot** | 1, bytes [4:5] |
| **Initial Value** | false |
| **Purpose** | Decimator window latch. Opens at jackpot phase start for resolution levels (4, 14, 24... or 99, 199...) |

**Read by:** DecimatorModule (R), BoonModule (R), DegenerusGame (R), AdvanceModule (R)
**Written by:** AdvanceModule (W)
**Packed with:** Slot 1 booleans
**Invariants:** Only opens at specific level patterns, closes when RNG requested

### `rngLockedFlag`

| Field | Value |
|-------|-------|
| **Type** | bool |
| **Visibility** | internal |
| **Slot** | 1, bytes [5:6] |
| **Initial Value** | false |
| **Purpose** | True when daily RNG is locked (jackpot resolution in progress). Blocks burns/opens |

**Read by:** DegenerusGame (R), MintModule (R), LootboxModule (R), AdvanceModule (R), BoonModule (R)
**Written by:** AdvanceModule (W)
**Packed with:** Slot 1 booleans
**Invariants:** Set when VRF requested for daily jackpot, cleared when daily processing completes

### `phaseTransitionActive`

| Field | Value |
|-------|-------|
| **Type** | bool |
| **Visibility** | internal |
| **Slot** | 1, bytes [6:7] |
| **Initial Value** | false |
| **Purpose** | True while jackpot-to-purchase transition housekeeping is in progress |

**Read by:** AdvanceModule (R)
**Written by:** AdvanceModule (W)
**Packed with:** Slot 1 booleans
**Invariants:** Transient during transition, set/cleared within advanceGame

### `gameOver`

| Field | Value |
|-------|-------|
| **Type** | bool |
| **Visibility** | public |
| **Slot** | 1, bytes [7:8] |
| **Initial Value** | false |
| **Purpose** | Terminal state flag. Once set, game enters game-over drain mode |

**Read by:** All modules (R), DegenerusGame (R)
**Written by:** AdvanceModule (W), GameOverModule (W)
**Packed with:** Slot 1 booleans
**Invariants:** One-way: false -> true only, never reverts

### `dailyJackpotCoinTicketsPending`

| Field | Value |
|-------|-------|
| **Type** | bool |
| **Visibility** | internal |
| **Slot** | 1, bytes [8:9] |
| **Initial Value** | false |
| **Purpose** | True when daily jackpot ETH phase completed but coin+tickets phase pending. Gas optimization for splitting work |

**Read by:** AdvanceModule (R)
**Written by:** AdvanceModule (W), JackpotModule (W)
**Packed with:** Slot 1 booleans
**Invariants:** Transient, cleared after coin+ticket distribution completes

### `dailyEthBucketCursor`

| Field | Value |
|-------|-------|
| **Type** | uint8 |
| **Visibility** | internal |
| **Slot** | 1, bytes [9:10] |
| **Initial Value** | 0 |
| **Purpose** | Cursor for daily jackpot ETH distribution (bucket order index, 0..3) |

**Read by:** JackpotModule (R)
**Written by:** JackpotModule (W)
**Packed with:** Slot 1 fields
**Invariants:** 0-3 range, reset after daily jackpot completes

### `dailyEthPhase`

| Field | Value |
|-------|-------|
| **Type** | uint8 |
| **Visibility** | internal |
| **Slot** | 1, bytes [10:11] |
| **Initial Value** | 0 |
| **Purpose** | Daily jackpot ETH phase: 0 = current level, 1 = carryover |

**Read by:** JackpotModule (R)
**Written by:** JackpotModule (W)
**Packed with:** Slot 1 fields
**Invariants:** 0 or 1 only

### `compressedJackpotFlag`

| Field | Value |
|-------|-------|
| **Type** | bool |
| **Visibility** | internal |
| **Slot** | 1, bytes [11:12] |
| **Initial Value** | false |
| **Purpose** | True when jackpot phase is compressed (3 days instead of 5). Set when purchase target met quickly |

**Read by:** AdvanceModule (R), JackpotModule (R)
**Written by:** AdvanceModule (W)
**Packed with:** Slot 1 fields
**Invariants:** Cleared at phase end

### `purchaseStartDay`

| Field | Value |
|-------|-------|
| **Type** | uint48 |
| **Visibility** | internal |
| **Slot** | 1, bytes [12:18] |
| **Initial Value** | 0 |
| **Purpose** | Game day index when current purchase phase opened. Used for compressed jackpot detection |

**Read by:** AdvanceModule (R)
**Written by:** AdvanceModule (W)
**Packed with:** Slot 1 fields
**Invariants:** Updated at each purchase phase start

---

### SLOT 2: Mint Price

### `price`

| Field | Value |
|-------|-------|
| **Type** | uint128 |
| **Visibility** | internal |
| **Slot** | 2, bytes [0:16] |
| **Initial Value** | 0.01 ether |
| **Purpose** | Base price unit in wei. One unit covers 4 scaled ticket entries |

**Read by:** MintModule (R), WhaleModule (R), DegenerusGame (R), LootboxModule (R)
**Written by:** AdvanceModule (W)
**Packed with:** 16 bytes padding (Slot 2)
**Invariants:** uint128 supports up to ~3.4e20 ETH. Updated via PriceLookupLib at level transitions

---

### SLOTS 3+: Full-Width Variables

### `currentPrizePool`

| Field | Value |
|-------|-------|
| **Type** | uint256 |
| **Visibility** | internal |
| **Slot** | 3 |
| **Initial Value** | 0 |
| **Purpose** | Active prize pool for current level. Accumulated from mint fees, distributed via jackpots |

**Read by:** JackpotModule (R), AdvanceModule (R), EndgameModule (R), GameOverModule (R)
**Written by:** JackpotModule (W), AdvanceModule (W), GameOverModule (W)
**Invariants:** Non-negative, decremented by jackpot payouts

### `nextPrizePool`

| Field | Value |
|-------|-------|
| **Type** | uint256 |
| **Visibility** | internal |
| **Slot** | 4 |
| **Initial Value** | 0 |
| **Purpose** | Pre-funded prize pool for the next level. 90% of mint prize contribution goes here |

**Read by:** JackpotModule (R), AdvanceModule (R), DegenerusGame (R)
**Written by:** DegenerusGame (W), JackpotModule (W), MintModule (W), WhaleModule (W)
**Invariants:** Non-negative, transferred to currentPrizePool at consolidation

### `rngWordCurrent`

| Field | Value |
|-------|-------|
| **Type** | uint256 |
| **Visibility** | internal |
| **Slot** | 5 |
| **Initial Value** | 0 |
| **Purpose** | Latest VRF random word. 0 indicates pending state |

**Read by:** AdvanceModule (R), DegenerusGame (R)
**Written by:** AdvanceModule (W)
**Invariants:** 0 = pending, non-zero = valid randomness

### `vrfRequestId`

| Field | Value |
|-------|-------|
| **Type** | uint256 |
| **Visibility** | internal |
| **Slot** | 6 |
| **Initial Value** | 0 |
| **Purpose** | Last VRF request ID. Prevents processing stale/mismatched VRF responses |

**Read by:** AdvanceModule (R)
**Written by:** AdvanceModule (W)
**Invariants:** Matched against fulfillment callback requestId

### `totalFlipReversals`

| Field | Value |
|-------|-------|
| **Type** | uint256 |
| **Visibility** | internal |
| **Slot** | 7 |
| **Initial Value** | 0 |
| **Purpose** | Count of reverse flips purchased against current RNG word |

**Read by:** AdvanceModule (R), JackpotModule (R)
**Written by:** AdvanceModule (W)
**Invariants:** Reset at each new RNG word

### `dailyTicketBudgetsPacked`

| Field | Value |
|-------|-------|
| **Type** | uint256 |
| **Visibility** | internal |
| **Slot** | 8 |
| **Initial Value** | 0 |
| **Purpose** | Packed daily jackpot ticket data for two-phase execution. Layout: counterStep(8b), dailyTicketUnits(64b), carryoverTicketUnits(64b), carryoverSourceOffset(8b) |

**Read by:** JackpotModule (R)
**Written by:** JackpotModule (W)
**Packed with:** Internal bit packing (not EVM slot packing)
**Invariants:** Set during ETH phase, consumed during coin+ticket phase

### `dailyEthPoolBudget`

| Field | Value |
|-------|-------|
| **Type** | uint256 |
| **Visibility** | internal |
| **Slot** | 9 |
| **Initial Value** | 0 |
| **Purpose** | Daily jackpot ETH pool budget for current-level distribution. Deterministic across split calls |

**Read by:** JackpotModule (R)
**Written by:** JackpotModule (W)
**Invariants:** Set once per daily jackpot, consumed during bucket distribution

---

### Token State and Jackpot Mechanics

### `claimableWinnings`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint256) |
| **Visibility** | internal |
| **Purpose** | ETH claimable by players from jackpot winnings. Pull pattern for security |

**Read by:** DegenerusGame (R), JackpotModule (R), MintModule (R), DecimatorModule (R), WhaleModule (R), GameOverModule (R)
**Written by:** JackpotModule (W), DegenerusGame (W), DecimatorModule (W), GameOverModule (W), EndgameModule (W), WhaleModule (W)
**Invariants:** Always >= 1 wei sentinel after first credit (gas optimization)

### `claimablePool`

| Field | Value |
|-------|-------|
| **Type** | uint256 |
| **Visibility** | internal |
| **Purpose** | Aggregate ETH liability across all claimableWinnings entries |

**Read by:** DegenerusGame (R), JackpotModule (R), GameOverModule (R)
**Written by:** DegenerusGame (W), JackpotModule (W), DecimatorModule (W), GameOverModule (W), EndgameModule (W), WhaleModule (W)
**Invariants:** claimablePool >= sum(claimableWinnings[*]). Temporarily breaks during decimator settlement (full pool reserved before individual credits)

### `traitBurnTicket`

| Field | Value |
|-------|-------|
| **Type** | mapping(uint24 => address[][256]) |
| **Visibility** | internal |
| **Purpose** | Nested mapping: level -> trait ID (0-255) -> array of ticket holders for jackpot winner selection |

**Read by:** JackpotModule (R), EndgameModule (R)
**Written by:** JackpotModule (W)
**Invariants:** Array growth bounded by total ticket supply per level

### `mintPacked_`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint256) |
| **Visibility** | internal |
| **Purpose** | Bit-packed mint history per player. Layout: lastEthLevel(24b), ethLevelCount(24b), ethLevelStreak(24b), lastEthDay(32b), unitsLevel(24b), frozenUntilLevel(24b), whaleBundleType(2b), mintStreakLast(24b), unitsAtLevel(16b) |

**Read by:** DegenerusGame (R), MintModule (R), WhaleModule (R), AdvanceModule (R), MintStreakUtils (R), JackpotModule (R)
**Written by:** MintModule (W), WhaleModule (W), DegenerusGameStorage._activate10LevelPass (W), DegenerusGameStorage._applyWhalePassStats (W), MintStreakUtils (W), EndgameModule (W)
**Invariants:** Bit fields must not overlap (verified by BitPackingLib constants)

---

### RNG History

### `rngWordByDay`

| Field | Value |
|-------|-------|
| **Type** | mapping(uint48 => uint256) |
| **Visibility** | internal |
| **Purpose** | VRF random words keyed by dailyIdx. 0 = not yet recorded. Immutable audit trail |

**Read by:** AdvanceModule (R), DegenerusGame (R), LootboxModule (R), BoonModule (R)
**Written by:** AdvanceModule (W)
**Invariants:** Write-once per day index; provides replay audit trail

---

### Coinflip Statistics

### `lastPurchaseDayFlipTotal`

| Field | Value |
|-------|-------|
| **Type** | uint256 |
| **Visibility** | internal |
| **Purpose** | Total coinflip deposits during lastPurchaseDay (current level). Used for payout tuning |

**Read by:** DegenerusGame (R), AdvanceModule (R)
**Written by:** DegenerusGame (W), AdvanceModule (W)
**Invariants:** Reset at level transition

### `lastPurchaseDayFlipTotalPrev`

| Field | Value |
|-------|-------|
| **Type** | uint256 |
| **Visibility** | internal |
| **Purpose** | Previous level's lastPurchaseDay coinflip deposits. Trend detection for payout tuning |

**Read by:** DegenerusGame (R), AdvanceModule (R)
**Written by:** AdvanceModule (W)
**Invariants:** Set from lastPurchaseDayFlipTotal at level transition

---

### Future/Reserve Pool

### `futurePrizePool`

| Field | Value |
|-------|-------|
| **Type** | uint256 |
| **Visibility** | internal |
| **Purpose** | Unified reserve pool (formerly future + reward). Funds jackpots, carryover, and time-based level splits |

**Read by:** JackpotModule (R), AdvanceModule (R), GameOverModule (R), DegenerusGame (R)
**Written by:** DegenerusGame (W), JackpotModule (W), MintModule (W), WhaleModule (W), GameOverModule (W)
**Invariants:** Non-negative; 10% of mint prize contribution routed here

---

### Ticket Queues

### `ticketQueue`

| Field | Value |
|-------|-------|
| **Type** | mapping(uint24 => address[]) |
| **Visibility** | internal |
| **Purpose** | Queue of players with tickets per level. All ticket sources (purchases, lootbox rewards, etc.) queue here |

**Read by:** JackpotModule (R), MintModule (R)
**Written by:** DegenerusGameStorage._queueTickets (W), DegenerusGameStorage._queueTicketsScaled (W), DegenerusGameStorage._queueTicketRange (W)
**Invariants:** Append-only per level during active play

### `ticketsOwedPacked`

| Field | Value |
|-------|-------|
| **Type** | mapping(uint24 => mapping(address => uint40)) |
| **Visibility** | internal |
| **Purpose** | Packed owed tickets per level per player. Layout: [32 bits owed][8 bits remainder] |

**Read by:** JackpotModule (R), MintModule (R)
**Written by:** DegenerusGameStorage._queueTickets (W), DegenerusGameStorage._queueTicketsScaled (W), DegenerusGameStorage._queueTicketRange (W)
**Invariants:** owed capped at uint32.max, remainder < TICKET_SCALE (100)

### `ticketCursor`

| Field | Value |
|-------|-------|
| **Type** | uint32 |
| **Visibility** | internal |
| **Purpose** | Cursor for ticket queue processing (dual-purpose: setup/purchase/jackpot phases) |

**Read by:** JackpotModule (R), MintModule (R), AdvanceModule (R)
**Written by:** JackpotModule (W), MintModule (W), AdvanceModule (W)
**Invariants:** Reset between phase transitions. Phases are mutually exclusive

### `ticketLevel`

| Field | Value |
|-------|-------|
| **Type** | uint24 |
| **Visibility** | internal |
| **Purpose** | Current level being processed in ticket queue operations |

**Read by:** JackpotModule (R), MintModule (R), AdvanceModule (R)
**Written by:** AdvanceModule (W), MintModule (W)
**Invariants:** Tracks which level's ticket queue is being iterated

---

### Daily Jackpot Resume State

### `dailyEthWinnerCursor`

| Field | Value |
|-------|-------|
| **Type** | uint16 |
| **Visibility** | internal |
| **Purpose** | Resume cursor within current daily jackpot bucket (winner index). 0 = start of bucket |

**Read by:** JackpotModule (R)
**Written by:** JackpotModule (W)
**Invariants:** Reset after bucket completes

### `dailyCarryoverEthPool`

| Field | Value |
|-------|-------|
| **Type** | uint256 |
| **Visibility** | internal |
| **Purpose** | Carryover ETH pool reserved after daily phase 0 completes. Avoids re-deducting futurePrizePool |

**Read by:** JackpotModule (R)
**Written by:** JackpotModule (W)
**Invariants:** Set once per daily cycle, consumed during carryover phase

### `dailyCarryoverWinnerCap`

| Field | Value |
|-------|-------|
| **Type** | uint16 |
| **Visibility** | internal |
| **Purpose** | Remaining winner cap for carryover buckets |

**Read by:** JackpotModule (R)
**Written by:** JackpotModule (W)
**Invariants:** DAILY_ETH_MAX_WINNERS minus daily winners

---

### Loot Box State

### `lootboxEth`

| Field | Value |
|-------|-------|
| **Type** | mapping(uint48 => mapping(address => uint256)) |
| **Visibility** | internal |
| **Purpose** | Loot box ETH per RNG index per player. Packed: [232 bits: amount] [24 bits: purchase level]. Purchase level locked at buy time |

**Read by:** LootboxModule (R), MintModule (R)
**Written by:** MintModule (W), LootboxModule (W)
**Invariants:** Amount accumulates within index; level set at first purchase

### `lootboxPresaleActive`

| Field | Value |
|-------|-------|
| **Type** | bool |
| **Visibility** | internal |
| **Initial Value** | true |
| **Purpose** | Presale mode toggle. One-way: can only be turned off. Presale gives 2x BURNIE |

**Read by:** MintModule (R), LootboxModule (R), AdvanceModule (R), DegenerusGame (R)
**Written by:** AdvanceModule (W), DegenerusGame (W)
**Invariants:** Monotonic: true -> false only (one-way toggle)

### `lootboxEthTotal`

| Field | Value |
|-------|-------|
| **Type** | uint256 |
| **Visibility** | internal |
| **Purpose** | Total ETH spent on lootboxes across all players and indices |

**Read by:** LootboxModule (R), MintModule (R)
**Written by:** MintModule (W)
**Invariants:** Monotonically increasing

### `lootboxPresaleMintEth`

| Field | Value |
|-------|-------|
| **Type** | uint256 |
| **Visibility** | internal |
| **Purpose** | Total ETH allocated to lootboxes from regular mints (excludes pass lootboxes). Triggers presale auto-end at 200 ETH cap |

**Read by:** MintModule (R), AdvanceModule (R)
**Written by:** MintModule (W)
**Invariants:** Monotonically increasing, caps at 200 ETH trigger

---

### Game Over State

### `gameOverTime`

| Field | Value |
|-------|-------|
| **Type** | uint48 |
| **Visibility** | internal |
| **Initial Value** | 0 |
| **Purpose** | Timestamp when game over triggered. 0 = game still active. Enforces 1-month delay before final vault sweep |

**Read by:** GameOverModule (R), AdvanceModule (R)
**Written by:** AdvanceModule (W)
**Invariants:** 0 until gameOver set true, then immutable

### `gameOverFinalJackpotPaid`

| Field | Value |
|-------|-------|
| **Type** | bool |
| **Visibility** | internal |
| **Initial Value** | false |
| **Purpose** | Prevents duplicate payouts of the gameover prize pool |

**Read by:** GameOverModule (R)
**Written by:** GameOverModule (W)
**Invariants:** One-way: false -> true

---

### Whale Pass Claims

### `whalePassClaims`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint256) |
| **Visibility** | internal |
| **Purpose** | Pending whale pass claims from large lootbox wins (>5 ETH). Stores half whale pass count (100 tickets = 50 levels x 2) |

**Read by:** EndgameModule (R), LootboxModule (R), DecimatorModule (R)
**Written by:** LootboxModule (W), DecimatorModule (W), JackpotModule (W), EndgameModule (W)
**Invariants:** Decremented on claim, never negative

---

### Coinflip Boon

### `coinflipBoonDay`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint48) |
| **Visibility** | internal |
| **Purpose** | Day index when coinflip boon was awarded. 2-day expiration window |

**Read by:** BoonModule (R)
**Written by:** LootboxModule (W), BoonModule (W)
**Invariants:** Set on boon award, checked for expiry

---

### Lootbox Boost Boons

### `lootboxBoon5Active`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => bool) |
| **Visibility** | internal |
| **Purpose** | 5% lootbox boost boon active flag. Single-use, 2-day expiry |

**Read by:** LootboxModule (R), BoonModule (R)
**Written by:** LootboxModule (W), BoonModule (W)
**Invariants:** Consumed on next lootbox open

### `lootboxBoon5Day`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint48) |
| **Visibility** | internal |
| **Purpose** | Day index when 5% lootbox boost was awarded |

**Read by:** LootboxModule (R), BoonModule (R)
**Written by:** LootboxModule (W), BoonModule (W)

### `lootboxBoon15Active`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => bool) |
| **Visibility** | internal |
| **Purpose** | 15% lootbox boost boon active flag. Single-use, 2-day expiry |

**Read by:** LootboxModule (R), BoonModule (R)
**Written by:** LootboxModule (W), BoonModule (W)
**Invariants:** Consumed on next lootbox open

### `lootboxBoon15Day`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint48) |
| **Visibility** | internal |
| **Purpose** | Day index when 15% lootbox boost was awarded |

**Read by:** LootboxModule (R), BoonModule (R)
**Written by:** LootboxModule (W), BoonModule (W)

### `lootboxBoon25Active`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => bool) |
| **Visibility** | internal |
| **Purpose** | 25% lootbox boost boon active flag. Single-use, 2-day expiry |

**Read by:** LootboxModule (R), BoonModule (R)
**Written by:** LootboxModule (W), BoonModule (W)
**Invariants:** Consumed on next lootbox open

### `lootboxBoon25Day`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint48) |
| **Visibility** | internal |
| **Purpose** | Day index when 25% lootbox boost was awarded |

**Read by:** LootboxModule (R), BoonModule (R)
**Written by:** LootboxModule (W), BoonModule (W)

---

### Whale Bundle Boon

### `whaleBoonDay`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint48) |
| **Visibility** | internal |
| **Purpose** | Day when whale bundle boon was awarded. 4-day expiry with tiered discount |

**Read by:** WhaleModule (R), BoonModule (R)
**Written by:** LootboxModule (W), BoonModule (W)

### `whaleBoonDiscountBps`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint16) |
| **Visibility** | internal |
| **Purpose** | Whale bundle boon discount tier (1000=10%, 2500=25%, 5000=50%) |

**Read by:** WhaleModule (R), BoonModule (R)
**Written by:** LootboxModule (W), BoonModule (W)

---

### Activity Boons

### `activityBoonPending`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint24) |
| **Visibility** | internal |
| **Purpose** | Pending activity boon bonus levels per player. Applied on lootbox open |

**Read by:** BoonModule (R), LootboxModule (R)
**Written by:** BoonModule (W), LootboxModule (W)

### `activityBoonDay`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint48) |
| **Visibility** | internal |
| **Purpose** | Day when activity boon was last assigned. 2-day expiry window |

**Read by:** BoonModule (R), LootboxModule (R)
**Written by:** BoonModule (W), LootboxModule (W)

---

### Auto-Rebuy & afKing Mode

### `autoRebuyState`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => AutoRebuyState) |
| **Visibility** | internal |
| **Purpose** | Packed auto-rebuy/afKing state: takeProfit(uint128), afKingActivatedLevel(uint24), autoRebuyEnabled(bool), afKingMode(bool) |

**Read by:** DegenerusGame (R), JackpotModule (R), AdvanceModule (R)
**Written by:** DegenerusGame (W)
**Invariants:** afKing lock: cannot disable for AFKING_LOCK_LEVELS after activation

### `decimatorAutoRebuyDisabled`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => bool) |
| **Visibility** | internal |
| **Purpose** | Decimator auto-rebuy toggle. true = disabled. Default enabled (false) |

**Read by:** DecimatorModule (R), DegenerusGame (R)
**Written by:** DegenerusGame (W)
**Invariants:** DGNRS address cannot toggle this

---

### Purchase/Burn Boosts

### `purchaseBoostBps`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint16) |
| **Visibility** | internal |
| **Purpose** | One-time purchase boost (5%/15%/25%), time-limited |

**Read by:** BoonModule (R), MintModule (R)
**Written by:** BoonModule (W), LootboxModule (W)

### `purchaseBoostDay`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint48) |
| **Visibility** | internal |
| **Purpose** | Day index when purchase boost was awarded (jackpot reset expiry) |

**Read by:** BoonModule (R)
**Written by:** BoonModule (W), LootboxModule (W)

### `decimatorBoostBps`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint16) |
| **Visibility** | internal |
| **Purpose** | Decimator burn boost (10%/25%/50%), one-time, no expiry |

**Read by:** BoonModule (R), DecimatorModule (R)
**Written by:** BoonModule (W), LootboxModule (W)

### `coinflipBoonBps`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint16) |
| **Visibility** | internal |
| **Purpose** | Coinflip boon boost (5%/10%/25%), one-time, time-limited |

**Read by:** BoonModule (R)
**Written by:** BoonModule (W), LootboxModule (W)

---

### Daily Jackpot Trait Tracking

### `lastDailyJackpotWinningTraits`

| Field | Value |
|-------|-------|
| **Type** | uint32 |
| **Visibility** | internal |
| **Purpose** | Winning traits for last daily/early jackpot (packed uint32, 8 bits per trait) |

**Read by:** JackpotModule (R)
**Written by:** JackpotModule (W)

### `lastDailyJackpotLevel`

| Field | Value |
|-------|-------|
| **Type** | uint24 |
| **Visibility** | internal |
| **Purpose** | Level for which lastDailyJackpotWinningTraits was computed |

**Read by:** JackpotModule (R)
**Written by:** JackpotModule (W)

### `lastDailyJackpotDay`

| Field | Value |
|-------|-------|
| **Type** | uint48 |
| **Visibility** | internal |
| **Purpose** | Day index for lastDailyJackpotWinningTraits |

**Read by:** JackpotModule (R)
**Written by:** JackpotModule (W)

### `lootboxEthBase`

| Field | Value |
|-------|-------|
| **Type** | mapping(uint48 => mapping(address => uint256)) |
| **Visibility** | internal |
| **Purpose** | Base (pre-boost) lootbox ETH per RNG index per player. Boosts apply at purchase time |

**Read by:** LootboxModule (R), MintModule (R)
**Written by:** MintModule (W)

---

### Operator Approvals

### `operatorApprovals`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => mapping(address => bool)) |
| **Visibility** | internal |
| **Purpose** | owner => operator => approved (game-wide delegated control) |

**Read by:** DegenerusGame (R)
**Written by:** DegenerusGame (W)
**Invariants:** Zero address operator not allowed

---

### ETH Perk Burn Tracking

### `ethPerkLevel`

| Field | Value |
|-------|-------|
| **Type** | uint24 |
| **Visibility** | internal |
| **Purpose** | Level associated with current ETH perk burn counter |

**Read by:** MintModule (R)
**Written by:** MintModule (W)

### `ethPerkBurnCount`

| Field | Value |
|-------|-------|
| **Type** | uint16 |
| **Visibility** | internal |
| **Purpose** | Count of ETH perk tokens burned this level |

**Read by:** MintModule (R)
**Written by:** MintModule (W)

### `burniePerkLevel`

| Field | Value |
|-------|-------|
| **Type** | uint24 |
| **Visibility** | internal |
| **Purpose** | Level associated with current BURNIE perk burn counter |

**Read by:** MintModule (R)
**Written by:** MintModule (W)

### `burniePerkBurnCount`

| Field | Value |
|-------|-------|
| **Type** | uint16 |
| **Visibility** | internal |
| **Purpose** | Count of BURNIE perk tokens burned this level |

**Read by:** MintModule (R)
**Written by:** MintModule (W)

### `dgnrsPerkLevel`

| Field | Value |
|-------|-------|
| **Type** | uint24 |
| **Visibility** | internal |
| **Purpose** | Level associated with current DGNRS perk burn counter |

**Read by:** MintModule (R)
**Written by:** MintModule (W)

### `dgnrsPerkBurnCount`

| Field | Value |
|-------|-------|
| **Type** | uint16 |
| **Visibility** | internal |
| **Purpose** | Count of DGNRS perk tokens burned this level |

**Read by:** MintModule (R)
**Written by:** MintModule (W)

---

### Affiliate DGNRS Claims

### `levelPrizePool`

| Field | Value |
|-------|-------|
| **Type** | mapping(uint24 => uint256) |
| **Visibility** | internal |
| **Purpose** | Per-level prize pool snapshot for affiliate DGNRS weighting |

**Read by:** DegenerusGame (R), AdvanceModule (R)
**Written by:** AdvanceModule (W), DegenerusGame constructor (W)
**Invariants:** levelPrizePool[0] = BOOTSTRAP_PRIZE_POOL (set in constructor)

### `affiliateDgnrsClaimedBy`

| Field | Value |
|-------|-------|
| **Type** | mapping(uint24 => mapping(address => bool)) |
| **Visibility** | internal |
| **Purpose** | Per-level per-affiliate claim tracking (prevents double claims) |

**Read by:** DegenerusGame (R)
**Written by:** DegenerusGame (W)
**Invariants:** One claim per level per affiliate

---

### Special Perk Expected Count

### `perkExpectedCount`

| Field | Value |
|-------|-------|
| **Type** | uint24 |
| **Visibility** | internal |
| **Purpose** | Expected special perk burn count for current level (1% of purchase count) |

**Read by:** MintModule (R), AdvanceModule (R)
**Written by:** MintModule (W)

---

### Deity Pass

### `deityPassCount`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint16) |
| **Visibility** | internal |
| **Purpose** | Count of deity passes per player (0 or 1). Vault/DGNRS get 1 in constructor for score boost |

**Read by:** DegenerusGame (R), WhaleModule (R), MintModule (R), LootboxModule (R), AdvanceModule (R), BoonModule (R), EndgameModule (R)
**Written by:** WhaleModule (W), DegenerusGame constructor (W)
**Invariants:** 0 or 1 per player (grants are single-count)

### `deityPassPurchasedCount`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint16) |
| **Visibility** | internal |
| **Purpose** | Count of deity passes purchased (excludes grants) |

**Read by:** WhaleModule (R), GameOverModule (R)
**Written by:** WhaleModule (W)

### `deityPassPaidTotal`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint256) |
| **Visibility** | internal |
| **Purpose** | Total ETH paid per buyer for deity passes |

**Read by:** GameOverModule (R), WhaleModule (R)
**Written by:** WhaleModule (W)

### `deityPassOwners`

| Field | Value |
|-------|-------|
| **Type** | address[] |
| **Visibility** | internal |
| **Purpose** | List of deity pass owners for iteration |

**Read by:** DegenerusGame (R), EndgameModule (R), GameOverModule (R), WhaleModule (R)
**Written by:** WhaleModule (W)
**Invariants:** Max 32 entries (32 symbols available, 24 purchasable + 8 reserved)

### `deityPassSymbol`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint8) |
| **Visibility** | internal |
| **Purpose** | Symbol assigned to each deity pass holder (0-31). 0 is valid (Bitcoin) |

**Read by:** WhaleModule (R), LootboxModule (R), DegenerusGame (R)
**Written by:** WhaleModule (W)

### `deityBySymbol`

| Field | Value |
|-------|-------|
| **Type** | mapping(uint8 => address) |
| **Visibility** | internal |
| **Purpose** | Reverse lookup: symbol ID (0-31) -> current owner address |

**Read by:** WhaleModule (R), EndgameModule (R)
**Written by:** WhaleModule (W)

---

### DGNRS Earlybird Rewards

### `earlybirdDgnrsPoolStart`

| Field | Value |
|-------|-------|
| **Type** | uint256 |
| **Visibility** | internal |
| **Initial Value** | 0 |
| **Purpose** | Initial earlybird pool balance snapshot (set on first payout) |

**Read by:** DegenerusGameStorage._awardEarlybirdDgnrs (R)
**Written by:** DegenerusGameStorage._awardEarlybirdDgnrs (W)
**Invariants:** Set once to pool balance, then set to type(uint256).max when earlybird ends

### `earlybirdEthIn`

| Field | Value |
|-------|-------|
| **Type** | uint256 |
| **Visibility** | internal |
| **Initial Value** | 0 |
| **Purpose** | Total purchase ETH counted toward earlybird emission |

**Read by:** DegenerusGameStorage._awardEarlybirdDgnrs (R)
**Written by:** DegenerusGameStorage._awardEarlybirdDgnrs (W)
**Invariants:** Monotonically increasing, capped at EARLYBIRD_TARGET_ETH (1000 ETH)

---

### VRF Configuration

### `vrfCoordinator`

| Field | Value |
|-------|-------|
| **Type** | IVRFCoordinator |
| **Visibility** | internal |
| **Purpose** | Chainlink VRF V2.5 coordinator contract. Mutable for emergency rotation |

**Read by:** AdvanceModule (R)
**Written by:** AdvanceModule (W) (via wireVrf / updateVrfCoordinatorAndSub)

### `vrfKeyHash`

| Field | Value |
|-------|-------|
| **Type** | bytes32 |
| **Visibility** | internal |
| **Purpose** | VRF key hash identifying oracle and gas lane |

**Read by:** AdvanceModule (R)
**Written by:** AdvanceModule (W)

### `vrfSubscriptionId`

| Field | Value |
|-------|-------|
| **Type** | uint256 |
| **Visibility** | internal |
| **Purpose** | VRF subscription ID for LINK billing |

**Read by:** AdvanceModule (R)
**Written by:** AdvanceModule (W)

---

### Lootbox RNG Indexing

### `lootboxRngIndex`

| Field | Value |
|-------|-------|
| **Type** | uint48 |
| **Visibility** | internal |
| **Initial Value** | 1 |
| **Purpose** | Current lootbox RNG index for new purchases (1-based) |

**Read by:** MintModule (R), LootboxModule (R), AdvanceModule (R)
**Written by:** AdvanceModule (W)
**Invariants:** Monotonically increasing, 1-based

### `lootboxRngPendingEth`

| Field | Value |
|-------|-------|
| **Type** | uint256 |
| **Visibility** | internal |
| **Purpose** | Accumulated lootbox ETH toward the RNG request threshold |

**Read by:** AdvanceModule (R), MintModule (R)
**Written by:** MintModule (W), AdvanceModule (W)

### `lootboxRngThreshold`

| Field | Value |
|-------|-------|
| **Type** | uint256 |
| **Visibility** | internal |
| **Initial Value** | 1 ether |
| **Purpose** | ETH threshold that triggers a lootbox RNG request |

**Read by:** AdvanceModule (R), DegenerusGame (R)
**Written by:** DegenerusGame (W)

### `lootboxRngMinLinkBalance`

| Field | Value |
|-------|-------|
| **Type** | uint256 |
| **Visibility** | internal |
| **Initial Value** | 14 ether |
| **Purpose** | Minimum LINK balance for manual lootbox RNG rolls (~2 weeks of daily VRF) |

**Read by:** AdvanceModule (R), DegenerusGame (R)
**Written by:** DegenerusGame (W)

### `lootboxRngWordByIndex`

| Field | Value |
|-------|-------|
| **Type** | mapping(uint48 => uint256) |
| **Visibility** | internal |
| **Purpose** | RNG words keyed by lootbox RNG index |

**Read by:** LootboxModule (R), AdvanceModule (R), DegeneretteModule (R)
**Written by:** AdvanceModule (W)

### `lootboxRngRequestIndexById`

| Field | Value |
|-------|-------|
| **Type** | mapping(uint256 => uint48) |
| **Visibility** | internal |
| **Purpose** | VRF requestId -> lootbox RNG index mapping. 0 = not a lootbox request |

**Read by:** AdvanceModule (R)
**Written by:** AdvanceModule (W)

### `lootboxDay`

| Field | Value |
|-------|-------|
| **Type** | mapping(uint48 => mapping(address => uint48)) |
| **Visibility** | internal |
| **Purpose** | Lootbox purchase day per RNG index and player |

**Read by:** LootboxModule (R)
**Written by:** MintModule (W)

### `lootboxBaseLevelPacked`

| Field | Value |
|-------|-------|
| **Type** | mapping(uint48 => mapping(address => uint24)) |
| **Visibility** | internal |
| **Purpose** | Lootbox base level at purchase time, packed as (level + 1). 0 = no lootbox |

**Read by:** LootboxModule (R)
**Written by:** MintModule (W)

### `lootboxEvScorePacked`

| Field | Value |
|-------|-------|
| **Type** | mapping(uint48 => mapping(address => uint16)) |
| **Visibility** | internal |
| **Purpose** | Lootbox activity score at purchase time, packed as (score + 1). 0 = no score |

**Read by:** LootboxModule (R)
**Written by:** MintModule (W)

### `lootboxIndexQueue`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint48[]) |
| **Visibility** | internal |
| **Purpose** | Per-player queue of lootbox RNG indices for auto-open processing |

**Read by:** LootboxModule (R), MintModule (R)
**Written by:** MintModule (W), LootboxModule (W)

---

### Lootbox BURNIE & Deity Refunds

### `lootboxBurnie`

| Field | Value |
|-------|-------|
| **Type** | mapping(uint48 => mapping(address => uint256)) |
| **Visibility** | internal |
| **Purpose** | BURNIE lootbox amounts keyed by lootbox RNG index and player |

**Read by:** LootboxModule (R)
**Written by:** MintModule (W), LootboxModule (W)

### `deityPassRefundable`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint256) |
| **Visibility** | internal |
| **Purpose** | Refundable deity pass ETH per buyer before level 1 starts |

**Read by:** WhaleModule (R), GameOverModule (R)
**Written by:** WhaleModule (W)

### `lootboxRngPendingBurnie`

| Field | Value |
|-------|-------|
| **Type** | uint256 |
| **Visibility** | internal |
| **Purpose** | Total pending BURNIE lootbox amount for manual RNG trigger threshold |

**Read by:** AdvanceModule (R), MintModule (R)
**Written by:** MintModule (W), AdvanceModule (W)

---

### Deity Boon Tracking

### `deityBoonDay`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint48) |
| **Visibility** | internal |
| **Purpose** | Day when deity's boon slots were assigned |

**Read by:** LootboxModule (R), DegenerusGame (R), BoonModule (R)
**Written by:** LootboxModule (W)

### `deityBoonUsedMask`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint8) |
| **Visibility** | internal |
| **Purpose** | Bitmask of used slots for current day (bit i = slot i used) |

**Read by:** LootboxModule (R), DegenerusGame (R)
**Written by:** LootboxModule (W)

### `deityBoonRecipientDay`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint48) |
| **Visibility** | internal |
| **Purpose** | Day when recipient last received a deity boon (prevents double-receipt) |

**Read by:** LootboxModule (R)
**Written by:** LootboxModule (W)

### `deityCoinflipBoonDay`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint48) |
| **Visibility** | internal |
| **Purpose** | Day when deity-granted coinflip boon was issued |

**Read by:** LootboxModule (R), BoonModule (R)
**Written by:** LootboxModule (W)

### `deityLootboxBoon5Day`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint48) |
| **Visibility** | internal |
| **Purpose** | Day when deity-granted 5% lootbox boost was issued |

**Read by:** LootboxModule (R), BoonModule (R)
**Written by:** LootboxModule (W)

### `deityLootboxBoon15Day`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint48) |
| **Visibility** | internal |
| **Purpose** | Day when deity-granted 15% lootbox boost was issued |

**Read by:** LootboxModule (R), BoonModule (R)
**Written by:** LootboxModule (W)

### `deityLootboxBoon25Day`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint48) |
| **Visibility** | internal |
| **Purpose** | Day when deity-granted 25% lootbox boost was issued |

**Read by:** LootboxModule (R), BoonModule (R)
**Written by:** LootboxModule (W)

### `deityPurchaseBoostDay`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint48) |
| **Visibility** | internal |
| **Purpose** | Day when deity-granted purchase boost was issued |

**Read by:** LootboxModule (R), BoonModule (R)
**Written by:** LootboxModule (W)

### `_deprecated_deityTicketBoostDay`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint48) |
| **Visibility** | internal |
| **Purpose** | DEPRECATED. Replaced by deityPurchaseBoostDay. Occupies slot to preserve layout |

**Read by:** None
**Written by:** None
**Invariants:** Dead storage -- preserved for slot alignment only

### `deityDecimatorBoostDay`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint48) |
| **Visibility** | internal |
| **Purpose** | Day when deity-granted decimator boost was issued |

**Read by:** LootboxModule (R), BoonModule (R)
**Written by:** LootboxModule (W)

### `deityWhaleBoonDay`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint48) |
| **Visibility** | internal |
| **Purpose** | Day when deity-granted whale boon was issued |

**Read by:** LootboxModule (R), BoonModule (R)
**Written by:** LootboxModule (W)

### `deityActivityBoonDay`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint48) |
| **Visibility** | internal |
| **Purpose** | Day when deity-granted activity boon was issued |

**Read by:** LootboxModule (R), BoonModule (R)
**Written by:** LootboxModule (W)

---

### Degenerette Bets

### `degeneretteBets`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => mapping(uint64 => uint256)) |
| **Visibility** | internal |
| **Purpose** | Packed bet data: mode(1b), isRandom(1b), customTicket(32b), ticketCount(8b), currency(2b), amountPerTicket(128b), RNG index(48b), activity score(16b), hasCustom(1b) |

**Read by:** DegeneretteModule (R)
**Written by:** DegeneretteModule (W)

### `degeneretteBetNonce`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint64) |
| **Visibility** | internal |
| **Purpose** | Per-player bet counter for Degenerette bet ID generation |

**Read by:** DegeneretteModule (R)
**Written by:** DegeneretteModule (W)
**Invariants:** Monotonically increasing per player

---

### Deity Pass Purchase Boon

### `deityPassBoonTier`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint8) |
| **Visibility** | internal |
| **Purpose** | Deity pass purchase boon tier (0=none, 1=10%, 2=25%, 3=50% discount) |

**Read by:** WhaleModule (R), LootboxModule (R), BoonModule (R)
**Written by:** LootboxModule (W), BoonModule (W)

### `deityPassBoonDay`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint48) |
| **Visibility** | internal |
| **Purpose** | Day when deity pass boon was awarded (4-day expiry for lootbox-rolled) |

**Read by:** WhaleModule (R), BoonModule (R)
**Written by:** LootboxModule (W), BoonModule (W)

### `deityDeityPassBoonDay`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint48) |
| **Visibility** | internal |
| **Purpose** | Day when deity-granted deity pass boon was issued (1-day expiry) |

**Read by:** LootboxModule (R), BoonModule (R)
**Written by:** LootboxModule (W)

---

### Lootbox EV Multiplier Cap

### `lootboxEvBenefitUsedByLevel`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => mapping(uint24 => uint256)) |
| **Visibility** | internal |
| **Purpose** | Lootbox ETH that has received EV multiplier benefit per player per level. Capped at 10 ETH |

**Read by:** LootboxModule (R), MintModule (R)
**Written by:** MintModule (W)

---

### Decimator Jackpot State

### `decBurn`

| Field | Value |
|-------|-------|
| **Type** | mapping(uint24 => mapping(address => DecEntry)) |
| **Visibility** | internal |
| **Purpose** | Player decimator burn entry per level. DecEntry: burn(uint192), bucket(uint8), subBucket(uint8), claimed(uint8) |

**Read by:** DecimatorModule (R), DegenerusGame (R)
**Written by:** DecimatorModule (W)

### `decBucketBurnTotal`

| Field | Value |
|-------|-------|
| **Type** | mapping(uint24 => uint256[13][13]) |
| **Visibility** | internal |
| **Purpose** | Aggregated burn totals per level/denom/subbucket. Array [13][13] for direct indexing (denom 0-12, sub 0-12) |

**Read by:** DecimatorModule (R)
**Written by:** DecimatorModule (W)

### `lastDecClaimRound`

| Field | Value |
|-------|-------|
| **Type** | LastDecClaimRound (struct) |
| **Visibility** | internal |
| **Purpose** | Last Decimator claim round snapshot. Fields: poolWei(uint256), rngWord(uint256), totalBurn(uint232), lvl(uint24) |

**Read by:** DecimatorModule (R), DegenerusGame (R)
**Written by:** DecimatorModule (W)
**Invariants:** Claims expire when next decimator runs

### `decBucketOffsetPacked`

| Field | Value |
|-------|-------|
| **Type** | mapping(uint24 => uint64) |
| **Visibility** | internal |
| **Purpose** | Packed winning subbucket per denominator for a level. 4 bits each for denom 2..12 (44 bits, fits uint64) |

**Read by:** DecimatorModule (R), DegenerusGame (R)
**Written by:** DecimatorModule (W)

---

### Lazy Pass Boon

### `lazyPassBoonDay`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint48) |
| **Visibility** | internal |
| **Purpose** | Day when lazy pass boon was awarded. 4-day expiry |

**Read by:** WhaleModule (R), BoonModule (R)
**Written by:** LootboxModule (W), BoonModule (W)

### `lazyPassBoonDiscountBps`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint16) |
| **Visibility** | internal |
| **Purpose** | Lazy pass boon discount in BPS (1000/2500/5000) |

**Read by:** WhaleModule (R), BoonModule (R)
**Written by:** LootboxModule (W), BoonModule (W)

### `deityLazyPassBoonDay`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => uint48) |
| **Visibility** | internal |
| **Purpose** | Deity-sourced lazy pass boon day (1-day expiry). 0 for lootbox-sourced boons |

**Read by:** LootboxModule (R), BoonModule (R)
**Written by:** LootboxModule (W)

---

### Degenerette Hero Wager Tracking

### `dailyHeroWagers`

| Field | Value |
|-------|-------|
| **Type** | mapping(uint48 => uint256[4]) |
| **Visibility** | internal |
| **Purpose** | Daily hero symbol wagers (ETH only), indexed by day. 4 packed uint256s = 8 symbols x 32-bit amounts per quadrant. Stored in 1e12 wei units (~4,295 ETH max per symbol per day) |

**Read by:** DegeneretteModule (R)
**Written by:** DegeneretteModule (W)

### `playerDegeneretteEthWagered`

| Field | Value |
|-------|-------|
| **Type** | mapping(address => mapping(uint24 => uint256)) |
| **Visibility** | internal |
| **Purpose** | Total ETH wagered on degenerette per player per level (in wei) |

**Read by:** DegeneretteModule (R), AdvanceModule (R)
**Written by:** DegeneretteModule (W)

### `topDegeneretteByLevel`

| Field | Value |
|-------|-------|
| **Type** | mapping(uint24 => uint256) |
| **Visibility** | internal |
| **Purpose** | Top degenerette player per level. Packed: [96 bits: amount in 1e12 units] [160 bits: address] |

**Read by:** DegeneretteModule (R), EndgameModule (R)
**Written by:** DegeneretteModule (W)
