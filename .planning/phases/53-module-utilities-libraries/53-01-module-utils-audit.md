# Phase 53 Plan 01: Module Utility Contracts Audit

**Contracts:** `DegenerusGameMintStreakUtils.sol` (62 lines), `DegenerusGamePayoutUtils.sol` (94 lines)
**Purpose:** Shared internal helpers inherited by delegatecall modules for mint streak tracking and payout processing.
**Inheritance:** Both extend `DegenerusGameStorage` and are inherited by game modules that execute via `delegatecall`.

---

## Contract: DegenerusGameMintStreakUtils

**File:** `contracts/modules/DegenerusGameMintStreakUtils.sol`
**Pragma:** Solidity 0.8.34
**Type:** Abstract contract (inherited by modules)
**Imports:** `DegenerusGameStorage`, `BitPackingLib`

### Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `MINT_STREAK_LAST_COMPLETED_SHIFT` | 160 | Bit position in `mintPacked_` for last-completed level (24 bits at 160-183) |
| `MINT_STREAK_FIELDS_MASK` | Combined mask | Clears both lastCompleted (bits 160-183) and streak (bits 48-71) in one AND operation |

### `_recordMintStreakForLevel(address player, uint24 mintLevel)` [internal]

| Field | Value |
|-------|-------|
| **Signature** | `function _recordMintStreakForLevel(address player, uint24 mintLevel) internal` |
| **Visibility** | internal |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player address to record streak for; `mintLevel` (uint24): level just completed |
| **Returns** | None |

**State Reads:**
- `mintPacked_[player]` -- packed mint data word (reads lastCompleted from bits 160-183, streak from bits 48-71)

**State Writes:**
- `mintPacked_[player]` -- updates lastCompleted (bits 160-183) and streak (bits 48-71) via mask-and-set

**Callers:**
- `DegenerusGame.recordMintQuestStreak(address player)` (line 447) -- external entry point, access-gated to COIN contract only, passes `_activeTicketLevel()` as mintLevel

**Callees:**
- None (leaf function -- only bitwise operations)

**ETH Flow:** None -- pure storage bookkeeping.

**Invariants:**
1. Idempotent per level: if `lastCompleted == mintLevel`, returns immediately (no double-credit)
2. Streak increments only if `lastCompleted + 1 == mintLevel` (consecutive), otherwise resets to 1
3. Streak saturates at `type(uint24).max` (16,777,215) -- cannot overflow
4. Zero address returns immediately (no storage write for address(0))
5. Non-streak bits of `mintPacked_[player]` are preserved via mask

**NatSpec Accuracy:**
- `@dev` says "idempotent per level" -- CORRECT, verified by `lastCompleted == mintLevel` early return
- `@dev` says "credits on completed 1x price ETH quest" (contract-level) -- ACCURATE, caller in DegenerusGame gates to COIN contract which triggers on quest completion

**Gas Flags:**
- The combined `MINT_STREAK_FIELDS_MASK` clears both fields in one AND -- efficient
- Single SLOAD + single SSTORE per call (optimal)
- `lastCompleted != 0` check before consecutive test: handles first-ever call correctly (resets to streak=1 on first call since lastCompleted starts at 0)

**Verdict:** CORRECT

---

### `_mintStreakEffective(address player, uint24 currentMintLevel)` [internal view]

| Field | Value |
|-------|-------|
| **Signature** | `function _mintStreakEffective(address player, uint24 currentMintLevel) internal view returns (uint24 streak)` |
| **Visibility** | internal |
| **Mutability** | view |
| **Parameters** | `player` (address): player to query; `currentMintLevel` (uint24): current active ticket level |
| **Returns** | `streak` (uint24): effective consecutive mint streak count (0 if broken) |

**State Reads:**
- `mintPacked_[player]` -- reads lastCompleted (bits 160-183) and streak (bits 48-71)

**State Writes:** None (view function)

**Callers:**
- `DegenerusGame.ethMintStreakCount(address)` (line 2353) -- external view, passes `_activeTicketLevel()`
- `DegenerusGame.ethMintStats(address)` (line 2374) -- external view, passes `_activeTicketLevel()`
- `DegenerusGame._playerActivityScore(address)` (line 2416) -- internal view, passes `_activeTicketLevel()`
- `DegenerusGameDegeneretteModule` (line 1030) -- internal call in degenerette activity score, passes `level + 1`

**Callees:**
- None (leaf function -- only bitwise operations and comparisons)

**ETH Flow:** None -- pure read.

**Invariants:**
1. Returns 0 if `lastCompleted == 0` (no mints ever recorded)
2. Returns 0 if `currentMintLevel > lastCompleted + 1` (gap detected -- streak broken)
3. Returns stored streak if `currentMintLevel <= lastCompleted + 1` (streak is current or player is exactly one level ahead)
4. Never modifies state

**NatSpec Accuracy:**
- `@dev` says "Effective mint streak (resets if a level was missed)" -- CORRECT, returns 0 when gap detected

**Gas Flags:**
- Single SLOAD (optimal for view)
- Early returns avoid unnecessary bit extraction when streak is definitely 0

**Verdict:** CORRECT

---

## Contract: DegenerusGamePayoutUtils

**File:** `contracts/modules/DegenerusGamePayoutUtils.sol`
**Pragma:** Solidity 0.8.34
**Type:** Abstract contract (inherited by modules)
**Imports:** `DegenerusGameStorage`, `EntropyLib`, `PriceLookupLib`

### Constants and Types

| Name | Value/Type | Purpose |
|------|-----------|---------|
| `HALF_WHALE_PASS_PRICE` | 2.175 ether | Unit price for one half whale pass (100 tickets across 50 levels) |
| `AutoRebuyCalc` | struct | Return struct for `_calcAutoRebuy` with: `toFuture`, `hasTickets`, `targetLevel`, `ticketCount`, `ethSpent`, `reserved`, `rebuyAmount` |

### Events

| Event | Parameters | Purpose |
|-------|-----------|---------|
| `PlayerCredited` | `player` (indexed), `recipient` (indexed), `amount` | Emitted when ETH credited to claimable balance |

### `_creditClaimable(address beneficiary, uint256 weiAmount)` [internal]

| Field | Value |
|-------|-------|
| **Signature** | `function _creditClaimable(address beneficiary, uint256 weiAmount) internal` |
| **Visibility** | internal |
| **Mutability** | state-changing |
| **Parameters** | `beneficiary` (address): recipient of credited ETH; `weiAmount` (uint256): wei to credit |
| **Returns** | None |

**State Reads:** None (directly writes)

**State Writes:**
- `claimableWinnings[beneficiary]` -- incremented by `weiAmount` (unchecked addition)

**Callers:**
- `DegenerusGameJackpotModule` (lines 982, 1010, 1023) -- jackpot payout, non-auto-rebuy fallback, take-profit reservation
- `DegenerusGameDegeneretteModule` (line 1174) -- degenerette bet payouts
- `DegenerusGameDecimatorModule` (lines 476, 488, 517) -- decimator claim payouts, take-profit, non-rebuy fallback
- `DegenerusGameEndgameModule` (lines 237, 250, 264) -- endgame/BAF payouts, take-profit, non-rebuy fallback
- `_queueWhalePassClaimCore` (line 88, same contract) -- remainder credit after whale pass division

**Callees:**
- None (emits `PlayerCredited` event only)

**ETH Flow:**
- Does NOT transfer ETH -- credits a pull-pattern balance in `claimableWinnings`
- Source: implicit (caller holds the ETH in the game contract's balance)
- Destination: `claimableWinnings[beneficiary]` (accounting entry, not transfer)

**Invariants:**
1. Zero-amount guard: returns immediately if `weiAmount == 0` (no spurious events)
2. Unchecked addition: safe because total protocol ETH supply is bounded (all ETH enters via payable functions with finite block gas limits, and total supply ~ 120M ETH < 2^88 wei, far below uint256 overflow)
3. No reentrancy risk: no external calls, only storage write + event
4. Does NOT update `claimablePool` -- callers are responsible for maintaining the pool aggregate

**NatSpec Accuracy:**
- No NatSpec on the function itself (only the contract-level `@dev Shared payout helpers for jackpot-related modules`)
- Event NatSpec is accurate: `player` and `recipient` are both `beneficiary` in the direct credit path

**Gas Flags:**
- Minimal: single SSTORE + event emit
- `unchecked` block avoids overflow check gas (safe as analyzed above)

**Note on `claimablePool` synchronization:**
This function does NOT increment `claimablePool`. The aggregate pool tracking is handled by callers. This is a deliberate design -- some callers batch-increment `claimablePool` for an entire group of credits (e.g., GameOverModule credits multiple players then adjusts pool once). The invariant `claimablePool >= sum(claimableWinnings[*])` is maintained at the caller level, not here.

**Verdict:** CORRECT

---

### `_calcAutoRebuy(address beneficiary, uint256 weiAmount, uint256 entropy, AutoRebuyState memory state, uint24 currentLevel, uint16 bonusBps, uint16 bonusBpsAfKing)` [internal pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _calcAutoRebuy(address beneficiary, uint256 weiAmount, uint256 entropy, AutoRebuyState memory state, uint24 currentLevel, uint16 bonusBps, uint16 bonusBpsAfKing) internal pure returns (AutoRebuyCalc memory c)` |
| **Visibility** | internal |
| **Mutability** | pure |
| **Parameters** | `beneficiary` (address): player address (used for entropy mixing); `weiAmount` (uint256): total payout to allocate; `entropy` (uint256): VRF-derived entropy seed; `state` (AutoRebuyState memory): player's auto-rebuy configuration; `currentLevel` (uint24): current game level; `bonusBps` (uint16): standard bonus tickets in basis points; `bonusBpsAfKing` (uint16): afKing-mode bonus tickets in basis points |
| **Returns** | `c` (AutoRebuyCalc memory): calculated rebuy parameters |

**State Reads:** None (pure function)

**State Writes:** None (pure function)

**Callers:**
- `DegenerusGameJackpotModule` (line 1000) -- jackpot auto-rebuy processing
- `DegenerusGameDecimatorModule` (line 466) -- decimator auto-rebuy processing
- `DegenerusGameEndgameModule` (line 227) -- endgame/BAF auto-rebuy processing

**Callees:**
- `EntropyLib.entropyStep(uint256)` -- XOR-shift PRNG step for level offset randomization
- `PriceLookupLib.priceForLevel(uint24)` -- retrieves ticket price for target level

**ETH Flow:** None (pure calculation only -- returns allocation breakdown)

**Logic Walkthrough:**
1. If `autoRebuyEnabled` is false, returns empty struct (all zeros/false)
2. **Take-profit reservation:** If `takeProfit != 0`, reserves largest multiple of `takeProfit` from `weiAmount`. Formula: `reserved = (weiAmount / takeProfit) * takeProfit`. This rounds down to nearest multiple.
3. **Rebuy amount:** `rebuyAmount = weiAmount - reserved` (the remainder after take-profit)
4. **Level offset:** Uses `EntropyLib.entropyStep(entropy ^ beneficiary ^ weiAmount)` masked to 2 bits + 1, giving offset 1-4. If offset > 1 then `toFuture = true` (75% chance future, 25% chance next level)
5. **Target level:** `currentLevel + levelOffset`
6. **Ticket price:** `PriceLookupLib.priceForLevel(targetLevel) >> 2` -- divides by 4 (quarter-ticket granularity, matching the purchase system where 400 units = 1 full ticket at priceForLevel)
7. **Base tickets:** `rebuyAmount / ticketPrice` -- integer division, truncates
8. **Bonus tickets:** Applies `bonusBps` or `bonusBpsAfKing` multiplier: `(baseTickets * bps) / 10_000`
9. **Ticket count cap:** Saturates at `type(uint32).max` (4,294,967,295)

**Invariants:**
1. `reserved + rebuyAmount == weiAmount` always holds (no ETH lost in calculation)
2. `ethSpent <= rebuyAmount` always holds (integer division truncates)
3. If `ticketPrice == 0` (should not happen with PriceLookupLib), returns early with no tickets
4. If `baseTickets == 0` (payout too small for even one ticket), returns early with no tickets
5. `ticketCount` cannot overflow uint32 (explicit saturation check)
6. Pure function -- deterministic for same inputs

**NatSpec Accuracy:**
- No NatSpec on the function itself -- MISSING but acceptable for internal pure helper

**Gas Flags:**
- **Take-profit calculation:** `(weiAmount / takeProfit) * takeProfit` -- this is a standard way to compute largest multiple <= weiAmount. If `takeProfit > weiAmount`, `reserved = 0` and full amount goes to rebuy. This is correct behavior.
- **Bonus ticket calculation note:** `bonusTickets` includes the base tickets in the multiplication, so `ticketCount = baseTickets * bonusBps / 10_000`. When `bonusBps = 10_000` (100%), `ticketCount == baseTickets`. When `bonusBps > 10_000`, extra bonus tickets are awarded. The caller uses `ticketCount` as the total ticket count (not base + bonus). This means `bonusBps` acts as a multiplier, not an additive bonus. Callers must account for this.
- Pure function -- no gas concerns beyond computation

**Verdict:** CORRECT

---

### `_queueWhalePassClaimCore(address winner, uint256 amount)` [internal]

| Field | Value |
|-------|-------|
| **Signature** | `function _queueWhalePassClaimCore(address winner, uint256 amount) internal` |
| **Visibility** | internal |
| **Mutability** | state-changing |
| **Parameters** | `winner` (address): player receiving deferred whale pass claims; `amount` (uint256): total ETH payout to convert |
| **Returns** | None |

**State Reads:** None (directly writes -- reads are implicit in `+=`)

**State Writes:**
- `whalePassClaims[winner]` -- incremented by `fullHalfPasses` (number of half-passes)
- `claimableWinnings[winner]` -- incremented by `remainder` (unchecked, via direct write)
- `claimablePool` -- incremented by `remainder` (checked addition)

**Callers:**
- `DegenerusGameEndgameModule` (lines 363, 410) -- lootbox portion and direct payout whale pass queuing
- `DegenerusGameDecimatorModule` (line 729) -- decimator large payout whale pass queuing

**Callees:**
- None (emits `PlayerCredited` event for remainder only)

**ETH Flow:**
- Converts large ETH payouts into deferred whale pass claims
- Division: `amount / HALF_WHALE_PASS_PRICE (2.175 ETH)` = number of half-passes
- Remainder: `amount - (fullHalfPasses * HALF_WHALE_PASS_PRICE)` goes to claimable balance
- `whalePassClaims` is a count, not ETH -- represents tickets/levels to be claimed later
- `claimablePool` is incremented for remainder only (the whale pass portion is handled separately when claims are redeemed)

**Invariants:**
1. Zero guards: returns immediately if `winner == address(0)` or `amount == 0`
2. `fullHalfPasses * HALF_WHALE_PASS_PRICE + remainder == amount` always holds (integer division identity)
3. No ETH is lost: every wei goes to either whale pass claims or claimable remainder
4. `claimablePool` is incremented in sync with `claimableWinnings` for the remainder (unlike `_creditClaimable` which leaves pool tracking to callers)
5. `whalePassClaims` increment is checked (no unchecked) -- safe since half-pass count is bounded by `amount / 2.175 ETH`, and `amount` is bounded by protocol ETH

**NatSpec Accuracy:**
- `@dev` says "Queue deferred whale pass claims for large payouts" -- CORRECT
- `HALF_WHALE_PASS_PRICE` NatSpec says "each half-pass = 1 ticket/level for 100 levels" -- ACCURATE, this is the pricing unit

**Gas Flags:**
- Conditional writes: only writes `whalePassClaims` if `fullHalfPasses != 0`, only writes `claimableWinnings`/`claimablePool` if `remainder != 0` -- saves gas on exact multiples or zero remainders
- `claimableWinnings` remainder addition is unchecked (safe, same analysis as `_creditClaimable`)
- `claimablePool` remainder addition is checked -- slight gas overhead but safer for aggregate tracking

**Design Note:**
Unlike `_creditClaimable`, this function DOES update `claimablePool` for the remainder portion. This is because `_queueWhalePassClaimCore` is a terminal payout function (callers don't batch pool updates), whereas `_creditClaimable` is used in batch contexts where callers manage pool updates.

**Verdict:** CORRECT
