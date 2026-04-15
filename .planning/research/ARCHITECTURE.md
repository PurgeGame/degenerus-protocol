# Architecture: Bonus Jackpot Trait Split Integration

**Domain:** Smart contract jackpot system modification
**Researched:** 2026-04-11
**Confidence:** HIGH (derived entirely from current contract source code)

## Current Architecture Summary

The jackpot system uses a two-call gas split during jackpot phase:

**Call 1 -- `payDailyJackpot(isJackpotPhase=true)`:**
1. Rolls 4 winning traits via `_rollWinningTraits(randWord)` (VRF-derived, hero override applied)
2. Persists traits to `dailyJackpotTraitsPacked` via `_syncDailyWinningTraits`
3. Computes ETH budget (6-14% of currentPrizePool, or 100% on final day)
4. Computes ticket budgets (daily + carryover), packs into `dailyTicketBudgetsPacked`
5. Distributes ETH to trait-matched winners at current level
6. Sets `dailyJackpotCoinTicketsPending = true`

**Call 2 -- `payDailyJackpotCoinAndTickets(randWord)`:**
1. Reads stored traits from `dailyJackpotTraitsPacked` (line 562)
2. Reads ticket budgets from `dailyTicketBudgetsPacked` (line 558)
3. Distributes BURNIE coin to near-future trait-matched winners (using stored main traits)
4. Distributes daily tickets to current-level trait winners (using stored main traits)
5. Distributes carryover tickets to source-level winners (using stored main traits)
6. Increments `jackpotCounter`, clears pending flag

**Key insight:** Currently, coin distribution AND carryover ticket distribution both use the same `winningTraitsPacked` that was rolled and stored in Call 1. The bonus split requires carryover and coin to use independently-rolled bonus traits instead.

## Recommended Architecture

### Strategy: Store Bonus Traits in `dailyTicketBudgetsPacked`

Do NOT add a new storage variable. The `dailyTicketBudgetsPacked` word currently uses 144 of 256 bits. Bonus traits are 32 bits. Pack bonus traits into the existing word at bits 144-175.

**Rationale:**
- Zero new SSTORE/SLOAD cost -- bonus traits piggyback on the existing `dailyTicketBudgetsPacked` write in Call 1 and read in Call 2
- `dailyJackpotTraitsPacked` is the wrong home -- it serves as a cross-call cache for the main traits, and is read by `_resumeDailyEth` (the ETH resume path) which must continue to use main traits
- A third storage variable would cost an extra cold SLOAD (2100 gas) in Call 2 for no reason

### Modified Layout: `dailyTicketBudgetsPacked`

```
Current:
  [bits   0:7]   counterStep              uint8
  [bits   8:71]  dailyTicketUnits          uint64
  [bits  72:135] carryoverTicketUnits      uint64
  [bits 136:143] carryoverSourceOffset     uint8
  [bits 144:255] <unused>                  112 bits free

Proposed:
  [bits   0:7]   counterStep              uint8    (unchanged)
  [bits   8:71]  dailyTicketUnits          uint64   (unchanged)
  [bits  72:135] carryoverTicketUnits      uint64   (unchanged)
  [bits 136:143] carryoverSourceOffset     uint8    (unchanged)
  [bits 144:175] bonusTraitsPacked         uint32   (NEW -- 4x8-bit trait IDs)
  [bits 176:255] <unused>                  80 bits remain
```

### Component Boundaries

| Component | Responsibility | Modification |
|-----------|---------------|--------------|
| `_rollWinningTraits` | Roll 4 traits from VRF, apply hero override | **NONE** -- called twice with different entropy derivations |
| `_packDailyTicketBudgets` | Pack Call 1 outputs for Call 2 | **MODIFY** -- add `bonusTraitsPacked` parameter at bits 144-175 |
| `_unpackDailyTicketBudgets` | Unpack in Call 2 | **MODIFY** -- return `bonusTraitsPacked` as 5th return value |
| `payDailyJackpot` (jackpot phase) | Call 1: roll traits, distribute ETH | **MODIFY** -- roll bonus traits with separate entropy, pack into budgets word |
| `payDailyJackpotCoinAndTickets` | Call 2: distribute coin + tickets | **MODIFY** -- unpack bonus traits, use for coin and carryover tickets |
| `_syncDailyWinningTraits` | Store main traits in `dailyJackpotTraitsPacked` | **NONE** -- continues storing main traits only |
| `_resumeDailyEth` | Resume ETH distribution on call 2 of gas split | **NONE** -- reads main traits from `dailyJackpotTraitsPacked`, unaffected |
| `_selectDailyCoinTargetLevel` | Pick random level in [lvl, lvl+4] | **MODIFY** -- narrow to [lvl+1, lvl+4] for bonus |
| `payDailyCoinJackpot` | Purchase-phase BURNIE distribution | **EVALUATE** -- may need bonus traits (see Purchase Phase Impact section) |
| `dailyJackpotTraitsPacked` | Cross-call trait cache | **NONE** -- stores main traits only, read by ETH resume path |
| `dailyTicketBudgetsPacked` | Cross-call budget + metadata cache | **MODIFY** -- gains bonus traits field |

### Data Flow

```
Call 1: payDailyJackpot(isJackpotPhase=true)
  |
  |-- mainTraits = _rollWinningTraits(randWord)            // existing
  |-- _syncDailyWinningTraits(lvl, mainTraits, questDay)   // existing, unchanged
  |-- [ETH distribution using mainTraits]                   // existing, unchanged
  |
  |-- bonusTraits = _rollWinningTraits(bonusEntropy)        // NEW: second roll
  |-- emit BonusWinningTraits(lvl, bonusTraits)             // NEW: event only, no storage
  |
  |-- dailyTicketBudgetsPacked = _packDailyTicketBudgets(   // MODIFIED
  |       counterStep, dailyTicketUnits,
  |       carryoverTicketUnits, sourceOffset,
  |       bonusTraits)                                      // NEW param
  |
  |-- dailyJackpotCoinTicketsPending = true

Call 2: payDailyJackpotCoinAndTickets(randWord)
  |
  |-- (counterStep, dailyTicketUnits, carryoverTicketUnits,
  |    sourceOffset, bonusTraits) = _unpackDailyTicketBudgets(...)  // MODIFIED
  |
  |-- mainTraits = _djtRead(...)                            // existing, for daily tickets
  |
  |-- Coin Jackpot: uses bonusTraits + narrowed target      // CHANGED from mainTraits
  |      targetLevel = _selectDailyCoinTargetLevel(lvl, entropy)  // narrowed [lvl+1, lvl+4]
  |      _awardDailyCoinToTraitWinners(targetLevel, bonusTraits, ...)
  |
  |-- Daily Tickets: uses mainTraits, current level         // UNCHANGED
  |      _distributeTicketJackpot(lvl, lvl+1, mainTraits, dailyTicketUnits, ...)
  |
  |-- Carryover Tickets: uses bonusTraits, source level     // CHANGED from mainTraits
  |      _distributeTicketJackpot(sourceLevel, ..., bonusTraits, carryoverTicketUnits, ...)
```

### Bonus Entropy Derivation

The bonus trait roll must use deterministically different entropy from the main roll to produce independent traits while maintaining VRF security properties.

```solidity
// In payDailyJackpot, after rolling main traits:
bytes32 constant BONUS_TRAIT_TAG = keccak256("bonus-traits");
uint256 bonusEntropy = uint256(keccak256(abi.encodePacked(randWord, BONUS_TRAIT_TAG)));
uint32 bonusTraitsPacked = _rollWinningTraits(bonusEntropy);
```

This follows the existing pattern used by `COIN_JACKPOT_TAG`, `DAILY_CARRYOVER_SOURCE_TAG`, etc. The `_applyHeroOverride` inside `_rollWinningTraits` will apply hero override to both main and bonus rolls, preserving the hero symbol guarantee.

### Bonus Event Emission

Per requirements, bonus winning traits are emitted as an event (no separate storage). Add a new event in `payDailyJackpot` Call 1, immediately after rolling bonus traits:

```solidity
event BonusWinningTraits(uint24 indexed level, uint32 traitsPacked);
```

Emitted once per jackpot-phase day, alongside the main traits stored in `dailyJackpotTraitsPacked`.

### `_selectDailyCoinTargetLevel` Narrowing

Current: `lvl + uint24(entropy % 5)` produces [lvl, lvl+4].
Bonus: `lvl + 1 + uint24(entropy % 4)` produces [lvl+1, lvl+4].

This function is also called from `payDailyCoinJackpot` (purchase phase). Two options:

1. **Add a parameter** `bool excludeCurrentLevel` to the function. Jackpot-phase callers pass `true`, purchase-phase path passes `false`.
2. **Inline the narrowed logic** at the bonus call site and leave the existing function unchanged.

Recommendation: Option 1 (parameter). Cleaner, single source of truth, minimal diff in each caller.

### Purchase Phase Impact

`payDailyCoinJackpot` (purchase-phase BURNIE) currently uses main traits loaded from `dailyJackpotTraitsPacked`. This function runs during purchase phase (not jackpot phase), so it does NOT participate in the two-call split.

**Decision needed from owner:** Should purchase-phase BURNIE also use independent bonus traits, or does the bonus split only apply to jackpot-phase?

If purchase-phase also needs bonus traits: the function already loads-or-rolls its traits inline (`_loadDailyWinningTraits` with fallback to `_rollWinningTraits`). Adding a second inline roll for bonus is straightforward with zero storage cost since there is no two-call split to bridge.

If purchase-phase keeps main traits: no change needed to `payDailyCoinJackpot`.

## Patterns to Follow

### Pattern 1: Piggyback on Existing Packed Storage

**What:** Add new cross-call data to an existing packed word that is already written in Call 1 and read in Call 2, rather than adding new storage variables.

**Why:** Zero marginal gas cost. The SSTORE/SLOAD for `dailyTicketBudgetsPacked` already happens. Adding 32 bits to a 144-bit word in a 256-bit slot costs nothing extra.

**Apply to:** `bonusTraitsPacked` in `dailyTicketBudgetsPacked`.

### Pattern 2: Entropy Domain Separation via keccak Tag

**What:** Derive sub-entropy from the VRF word using `keccak256(abi.encodePacked(randWord, DOMAIN_TAG))`.

**Why:** Produces independent, deterministic, non-correlating sub-streams from a single VRF word. Already used throughout the codebase (`COIN_JACKPOT_TAG`, `DAILY_CARRYOVER_SOURCE_TAG`, `DAILY_CURRENT_BPS_TAG`).

**Apply to:** Bonus trait roll entropy derivation.

### Pattern 3: Hero Override Preservation

**What:** Both main and bonus trait rolls go through `_rollWinningTraits`, which calls `_applyHeroOverride`. This means both rolls will replace the winning quadrant's trait with the hero symbol if one exists.

**Why:** Hero symbol guarantee is a game mechanic that should apply to both drawings. Since `_rollWinningTraits` already handles this, no special-casing needed.

## Anti-Patterns to Avoid

### Anti-Pattern 1: Storing Bonus Traits in `dailyJackpotTraitsPacked`

**What:** Overwriting or adding bonus traits to the existing trait packed tracker.

**Why bad:** `_resumeDailyEth` reads main traits from `dailyJackpotTraitsPacked` at line 1137. If bonus traits are written there, the ETH resume path (call 2 of the ETH gas split) would use wrong traits. The ETH distribution must always use main traits.

**Instead:** Store bonus traits in `dailyTicketBudgetsPacked` which is only consumed by `payDailyJackpotCoinAndTickets`.

### Anti-Pattern 2: Adding a New Storage Variable for Bonus Traits

**What:** Declaring `uint32 bonusTraitsPacked` as a separate storage slot.

**Why bad:** Costs 2100 gas (cold SLOAD) in Call 2 for data that fits in 32 bits of an existing 256-bit word with 112 bits free. Pure waste.

**Instead:** Pack into `dailyTicketBudgetsPacked` at bits 144-175.

### Anti-Pattern 3: Rolling Bonus Traits in Call 2

**What:** Calling `_rollWinningTraits` during `payDailyJackpotCoinAndTickets` instead of storing the roll from Call 1.

**Why bad:** `_rollWinningTraits` calls `_applyHeroOverride` which calls `_topHeroSymbol(_simulatedDayIndex())`. If Call 1 and Call 2 happen on different simulated days (unlikely but possible in edge cases), the hero override could differ. Rolling in Call 1 and storing ensures consistency between the bonus trait selection announcement (event) and the actual distribution.

**Instead:** Roll in Call 1 (alongside main traits), store in packed budgets, consume in Call 2.

## Suggested Modification Order (Minimizing Risk)

### Step 1: Pack/Unpack Infrastructure

Modify `_packDailyTicketBudgets` and `_unpackDailyTicketBudgets` to include the 5th field (bonusTraitsPacked at bits 144-175). All existing callers pass 0 for the new field initially. This is a pure additive change with zero behavioral impact.

**Files:** `DegenerusGameJackpotModule.sol` (2 functions)
**Risk:** MINIMAL -- new bits are in unused space, existing callers pass 0

### Step 2: Bonus Trait Roll in Call 1

In `payDailyJackpot` (jackpot phase path), add the bonus trait roll after the main roll. Pack bonus traits into `dailyTicketBudgetsPacked`. Emit `BonusWinningTraits` event. Add `BONUS_TRAIT_TAG` constant.

**Files:** `DegenerusGameJackpotModule.sol` (1 function + 1 constant + 1 event)
**Risk:** LOW -- additive; main ETH distribution path untouched

### Step 3: Bonus Traits in Call 2 -- Coin Distribution

In `payDailyJackpotCoinAndTickets`, unpack bonus traits. Change coin jackpot section to use bonus traits instead of main traits. Narrow `_selectDailyCoinTargetLevel` to [lvl+1, lvl+4].

**Files:** `DegenerusGameJackpotModule.sol` (2 functions)
**Risk:** MEDIUM -- changes coin winner selection (different traits = different winners)
**Verification:** Coin winners are bonus-trait-matched at bonus target level

### Step 4: Bonus Traits in Call 2 -- Carryover Tickets

In `payDailyJackpotCoinAndTickets`, change carryover ticket distribution to use bonus traits instead of main traits.

**Files:** `DegenerusGameJackpotModule.sol` (1 call site, ~1 line change)
**Risk:** MEDIUM -- changes carryover ticket winner selection
**Verification:** Carryover winners matched against bonus traits at source level

### Step 5: Purchase Phase Decision

If purchase-phase BURNIE also needs bonus traits: modify `payDailyCoinJackpot` to roll bonus traits inline and use them for coin distribution. No storage needed (single-call path).

**Files:** `DegenerusGameJackpotModule.sol` (1 function)
**Risk:** LOW -- isolated function, no cross-call state

### Step 6: Interface and Event Updates

Add `BonusWinningTraits` event to `IDegenerusGameJackpotModule` interface. Update any off-chain indexers or test expectations.

**Files:** `IDegenerusGameJackpotModule.sol`, test files
**Risk:** MINIMAL -- interface-only

## Gas Analysis

| Operation | Current Gas | After Change | Delta |
|-----------|------------|--------------|-------|
| Call 1 SSTORE (`dailyTicketBudgetsPacked`) | Same slot | Same slot | 0 |
| Call 1 bonus roll (`_rollWinningTraits`) | N/A | ~800 (keccak + pack + hero check) | +800 |
| Call 1 bonus event emission | N/A | ~375 (LOG2 base + 56 bytes) | +375 |
| Call 2 SLOAD (`dailyTicketBudgetsPacked`) | Same slot | Same slot | 0 |
| Call 2 coin distribution | Same | Same (different traits, same logic) | 0 |
| Call 2 carryover distribution | Same | Same (different traits, same logic) | 0 |
| **Total marginal cost** | | | **~1175 gas** |

The gas overhead is negligible (one keccak256, one trait roll, one event). No new storage slots, no new SLOADs or SSTOREs.

## Invariants to Preserve

1. **Main ETH distribution uses main traits** -- `_resumeDailyEth` reads from `dailyJackpotTraitsPacked`, which must continue to store main traits only
2. **Daily ticket distribution (20% lootbox) uses main traits at current level** -- this is the "main drawing" for tickets
3. **`jackpotCounter` increment and `dailyJackpotCoinTicketsPending` clear remain in Call 2** -- lifecycle unchanged
4. **Both trait rolls share the same VRF word** -- independence comes from domain-separated keccak, not separate VRF requests
5. **Hero override applies to both rolls** -- `_rollWinningTraits` handles this automatically
6. **`dailyTicketBudgetsPacked` is zeroed after consumption** (line 630) -- bonus traits cleared with it

## Sources

- `contracts/modules/DegenerusGameJackpotModule.sol` -- lines 310-631 (two-call split), 1861-1942 (trait roll + pack/unpack)
- `contracts/storage/DegenerusGameStorage.sol` -- lines 925-952 (dailyJackpotTraitsPacked layout), 380-385 (dailyTicketBudgetsPacked layout)
- `contracts/modules/DegenerusGameAdvanceModule.sol` -- lines 300-433 (call flow orchestration)
