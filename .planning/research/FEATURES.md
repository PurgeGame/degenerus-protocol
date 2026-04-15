# Feature Landscape: Bonus Jackpot Split

**Domain:** Smart contract jackpot system split (ETH main + BURNIE bonus)
**Researched:** 2026-04-11

## Table Stakes

Features that MUST work correctly or the split is broken/unsafe.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Independent bonus trait roll | Core requirement -- bonus drawing needs its own 4-trait set so BURNIE/ticket winners differ from ETH winners | Low | `_rollWinningTraits(randWord)` already exists; call it twice with different entropy derivation |
| Bonus near-future range [lvl+1, lvl+4] | Decision [v26.0] -- remove lvl from BURNIE coin target range so bonus only targets future-level tickets | Low | Change `_selectDailyCoinTargetLevel` from `lvl + entropy%5` to `lvl + 1 + entropy%4` |
| Hero symbol override on bonus traits | Hero override is expected on all trait rolls; omitting it silently changes economics for hero wagerers | Low | `_applyHeroOverride` is already called inside `_rollWinningTraits`; second roll gets it automatically |
| Carryover uses bonus traits | Decision [v26.0] -- carryover ticket distribution draws from future-level tickets, must use bonus traits not main traits | Medium | Carryover in `payDailyJackpotCoinAndTickets` currently reads `winningTraitsPacked` from `dailyJackpotTraitsPacked`; must read bonus traits instead |
| Bonus trait event emission | Decision [v26.0] -- no storage, emit-only for UI consumption | Low | New event `BonusWinningTraits(uint24 indexed level, uint32 traitsPacked)` or similar |
| Main ETH jackpot unchanged | Main drawing (current-level tickets, ETH payouts) must not change behavior | N/A (guard rail) | Verify delta equivalence for all ETH paths |
| Main 20% ticket distribution unchanged | Daily ticket distribution draws from current-level tickets using main traits | N/A (guard rail) | `dailyTicketUnits` distribution in `payDailyJackpotCoinAndTickets` continues using main traits from `dailyJackpotTraitsPacked` |
| ETH pool accounting invariant | Split must not affect ETH conservation (currentPrizePool, futurePrizePool, nextPrizePool, claimablePool) | N/A (guard rail) | Bonus changes only affect BURNIE/ticket paths, not ETH flow |

## Differentiators

Features that add value beyond the minimum split but are not strictly required.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Pack bonus traits into dailyJackpotTraitsPacked | Saves 1 storage slot; 168 bits free in existing packed word (88/256 used). Bonus traits (32 bits) fit at bit offset 88 | Low | Adds DJT_BONUS_TRAITS_SHIFT/MASK constants. Enables carryover Phase 2 to read bonus traits from same SLOAD as main traits |
| Separate entropy domains for main vs bonus | Prevents trait correlation between ETH and BURNIE drawings | Low | Use different tag (e.g., `keccak256("bonus-traits")`) when deriving bonus roll entropy from same randWord |
| Bonus traits available during purchase phase too | Purchase phase currently runs `payDailyCoinJackpot` (standalone) which loads/rolls traits. Having a bonus roll here means purchase-phase BURNIE also uses independent traits | Medium | `payDailyCoinJackpot` currently loads main traits or rolls fresh; needs bonus roll path |

## Anti-Features

Features to explicitly NOT build.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Bonus traits in storage (new slot) | Wastes a storage slot when 168 bits are free in `dailyJackpotTraitsPacked`; adds gas (cold SLOAD for new slot) | Pack into existing `dailyJackpotTraitsPacked` at bits [88:119] |
| Separate VRF request for bonus drawing | Doubles VRF cost, doubles latency, no security benefit (same commitment window) | Derive bonus entropy from same `randWord` with different domain tag |
| Independent bonus jackpot counter | Bonus drawing happens at same cadence as main (5 days). Separate counter adds state and branching for zero benefit | Share `jackpotCounter` -- bonus is a Phase 2 add-on, not independent scheduling |
| Bonus drawing during purchase phase as separate flow | Purchase phase already calls `_payDailyCoinJackpot` which handles BURNIE. Adding a separate "bonus" path during purchase phase overcomplicates the two-phase flow | Modify existing `_payDailyCoinJackpot` and `payDailyJackpotCoinAndTickets` to use bonus traits for BURNIE/coin distribution |
| Far-future coin jackpot changes | Far-future (25% of BURNIE, [lvl+5, lvl+99]) draws from `ticketQueue` which has no trait assignment. Changing its behavior is out of scope and unnecessary | Keep `_awardFarFutureCoinJackpot` unchanged -- it uses ticketQueue (traitless), unaffected by trait split |

## Feature Dependencies

```
Independent bonus trait roll
  |
  +-- Bonus traits packed into dailyJackpotTraitsPacked (or emitted)
  |     |
  |     +-- Carryover uses bonus traits (reads bonus field from packed storage)
  |     |
  |     +-- payDailyJackpotCoinAndTickets uses bonus traits for BURNIE near-future
  |
  +-- Bonus trait event emission (emitted at roll time, before any consumer reads)
  |
  +-- _selectDailyCoinTargetLevel range change [lvl, lvl+4] -> [lvl+1, lvl+4]
       (independent of trait split but same milestone)

Main traits (existing, no change needed):
  +-- ETH jackpot: _processDailyEth reads main traits
  +-- 20% daily ticket distribution: _distributeTicketJackpot reads main traits
  +-- Purchase phase: _executeJackpot reads main traits
```

## Edge Cases: Empty Future-Level Buckets

The bonus drawing targets [lvl+1, lvl+4] via `_selectDailyCoinTargetLevel`. Some of those levels may have zero tickets in `traitBurnTicket[targetLevel]`. This section documents all edge cases and how they are (or should be) handled.

### EC-01: Target level has zero tickets in all 4 winning trait buckets

**Scenario:** `_selectDailyCoinTargetLevel` picks `lvl+3`, but `traitBurnTicket[lvl+3]` has no entries for any of the 4 bonus winning traits.

**Current behavior:** `_awardDailyCoinToTraitWinners` calls `_computeBucketCounts` which checks `traitBurnTicket[lvl][trait].length` for each trait. If all 4 return 0, `activeCount == 0` triggers early return. The BURNIE budget for that day is simply not distributed (no revert, no loss -- `coinflip.creditFlip` is never called).

**Post-split behavior:** Identical. No change needed. The BURNIE budget effectively rolls over because `_calcDailyCoinBudget` is computed fresh each day based on `levelPrizePool` and current price, not from a stored balance that gets depleted.

**Risk:** LOW. BURNIE budget is calculated, not deducted from a pool. Undistributed BURNIE simply means slightly fewer BURNIE minted via coinflip that day.

### EC-02: Target level has tickets in some but not all trait buckets

**Scenario:** `lvl+2` has tickets in traits [0] and [2] but not [1] and [3].

**Current behavior:** `_computeBucketCounts` sets `activeCount=2`, redistributes the winner cap across only the 2 active buckets. `_awardDailyCoinToTraitWinners` only processes active buckets, awarding the full budget to winners in those 2 traits.

**Post-split behavior:** Same mechanism. The bonus traits are independent, so there may be MORE empty buckets (since the bonus roll is uncorrelated with which traits have tickets at that level). This slightly increases the probability of partial or full miss days.

**Risk:** LOW. Partial distribution is by design -- more tickets at a level means more likely to match at least one trait.

### EC-03: Near-future levels have tickets only via deity virtual entries

**Scenario:** No player has purchased tickets for `lvl+2`, but a deity pass holder has a symbol in one of the bonus winning traits.

**Current behavior:** `_computeBucketCounts` checks for deity virtual entries (`deityBySymbol[fullSymId] != address(0)`). If found, the bucket is marked active. `_randTraitTicket` returns the deity address for virtual indices. The deity holder receives BURNIE.

**Post-split behavior:** Same. Deity virtual entries work identically regardless of which traits are rolled.

**Risk:** NONE. Existing mechanism handles this correctly.

### EC-04: [lvl+1, lvl+4] range vs [lvl, lvl+4] -- removing current level from bonus targets

**Scenario:** Current level (`lvl`) always has tickets (from current-level purchases/burns). Removing it from the bonus range means the bonus drawing ONLY targets levels that may have sparse/no tickets.

**Impact:** At early levels (0-3), future levels may have very few tickets. At level 0, `lvl+1` through `lvl+4` (levels 1-4) will have few or no tickets unless early lootbox/carryover has populated them.

**Mitigation:** Early-bird lootbox (day 1 of jackpot phase) distributes tickets to `lvl+1` through `lvl+5`. Carryover tickets (days 2-4) go to `lvl+1` through `lvl+4`. Far-future coin jackpot (25% of BURNIE budget) uses `ticketQueue` which does not depend on trait assignment. So the 75% near-future portion may miss more often at early levels, but this is acceptable because:
1. Early-level prize pools are small, so BURNIE budgets are small
2. The far-future 25% still distributes
3. Ticket population grows rapidly as more players enter

**Risk:** MEDIUM at very early levels (0-2), LOW otherwise.

### EC-05: Carryover source level [lvl+1, lvl+4] has empty trait buckets for bonus traits

**Scenario:** Carryover selects `sourceLevel = lvl + offset` (offset 1-4). It draws winners from `traitBurnTicket[sourceLevel]` using bonus traits. If the bonus-winning trait buckets at `sourceLevel` are empty, no carryover tickets are awarded.

**Current behavior:** Carryover uses MAIN traits. After the split, it uses BONUS traits. Since bonus traits are independent, a different set of trait buckets is queried. This may produce different emptiness patterns.

**Impact:** Carryover ticket distribution may find fewer winners with bonus traits vs main traits at any given source level. This is a probabilistic shift, not a bug.

**Existing safeguard:** `_distributeTicketJackpot` returns gracefully when `activeCount == 0`. Unawarded ticket units are simply not distributed (the ETH backing has already moved to nextPrizePool, so pool accounting is unaffected).

**Risk:** LOW. Unawarded carryover tickets do not leak ETH -- the backing ETH stays in nextPrizePool regardless.

### EC-06: Same player wins both main ETH and bonus BURNIE jackpot

**Scenario:** Player holds current-level tickets matching main traits AND future-level tickets matching bonus traits.

**Current behavior (pre-split):** Already possible since the same traits are used for both ETH and BURNIE. The split makes this LESS likely (independent trait rolls) but still possible.

**Impact:** No issue. ETH credits to `claimableWinnings`, BURNIE credits via `coinflip.creditFlip`. Different accounting paths, no conflict.

**Risk:** NONE. Desirable outcome for players who hold both current and future tickets.

### EC-07: Level transition during jackpot phase -- future tickets get processed

**Scenario:** As the level transitions, `_prepareFutureTickets` processes near-future ticket queues, assigning traits. This populates `traitBurnTicket[lvl+1..lvl+4]`.

**Impact on bonus drawing:** Bonus drawing during jackpot phase occurs AFTER ticket processing (controlled by `dailyJackpotCoinTicketsPending` flag and advance flow ordering). So tickets at future levels should be populated by the time bonus drawing runs.

**Risk:** LOW. The advance flow already ensures ticket processing happens before coin+ticket distribution.

## MVP Recommendation

Prioritize (in implementation order):

1. **Independent bonus trait roll** -- Core of the split. Roll second trait set from same `randWord` with different entropy domain.
2. **Pack bonus traits into `dailyJackpotTraitsPacked`** -- Store at bits [88:119]. Zero incremental gas (same SSTORE as main traits).
3. **Bonus trait event** -- Emit immediately after roll for UI consumption. Single new event.
4. **`_selectDailyCoinTargetLevel` range narrowing** -- Change `% 5` to `% 4` and `+ 0` to `+ 1`. One line.
5. **Wire bonus traits into coin + carryover consumers** -- `payDailyJackpotCoinAndTickets` reads bonus traits instead of main traits for: (a) near-future coin distribution, (b) carryover ticket distribution.
6. **Wire bonus traits into standalone `payDailyCoinJackpot`** -- Purchase-phase BURNIE uses bonus traits.

Defer: None. All 6 items are small and tightly coupled. Splitting across milestones would leave the system in an inconsistent state.

## Detailed Change Map (Function-Level)

### Functions That Change

| Function | Change | Complexity |
|----------|--------|------------|
| `payDailyJackpot` (jackpot phase path) | Roll bonus traits, pack into DJT, emit event | Low |
| `payDailyJackpot` (purchase phase path) | Roll bonus traits, pass to `_payDailyCoinJackpot` | Low |
| `payDailyJackpotCoinAndTickets` | Read bonus traits from DJT; use for coin + carryover distribution | Low-Med |
| `payDailyCoinJackpot` (standalone) | Roll or load bonus traits; use for near-future coin distribution | Low |
| `_selectDailyCoinTargetLevel` | Change range from [lvl, lvl+4] to [lvl+1, lvl+4] | Trivial |
| `_syncDailyWinningTraits` | Also write bonus traits to DJT | Trivial |
| `_loadDailyWinningTraits` | Also read bonus traits from DJT | Trivial |

### Functions That Must NOT Change

| Function | Why Unchanged |
|----------|---------------|
| `_processDailyEth` | ETH distribution uses main traits only |
| `_executeJackpot` | Purchase-phase ETH uses main traits |
| `_runJackpotEthFlow` | ETH bucket distribution unchanged |
| `_distributeTicketJackpot` (daily 20%) | Daily ticket distribution uses main traits, draws from current level |
| `_runEarlyBirdLootboxJackpot` | Own per-winner random trait selection, no dependency on winning traits |
| `_awardFarFutureCoinJackpot` | Uses ticketQueue (traitless), independent of trait roll |
| `runTerminalJackpot` | Rolls its own traits, independent path |
| `runBafJackpot` | Uses external jackpots contract, independent path |
| `distributeYieldSurplus` | No trait dependency |

### Storage Changes

| Storage | Change | Impact |
|---------|--------|--------|
| `dailyJackpotTraitsPacked` | Add bonus traits at bits [88:119] (32 bits) | Same SSTORE, no new slot |
| New constants: `DJT_BONUS_TRAITS_SHIFT = 88`, `DJT_BONUS_TRAITS_MASK = 0xFFFFFFFF` | Constants only | Zero gas impact |

### New Events

| Event | Signature | Emitted Where |
|-------|-----------|---------------|
| `BonusWinningTraits` | `event BonusWinningTraits(uint24 indexed level, uint32 traitsPacked)` | `payDailyJackpot` (both paths), `payDailyCoinJackpot` |

### Interface Changes

| Interface | Change |
|-----------|--------|
| `IDegenerusGameJackpotModule` | No signature changes (bonus traits are internal) |
| `IDegenerusGame` | None |

## Sources

- Contract source: `contracts/modules/DegenerusGameJackpotModule.sol` (2158 lines)
- Storage layout: `contracts/storage/DegenerusGameStorage.sol` (lines 924-952, dailyJackpotTraitsPacked)
- Advance flow: `contracts/modules/DegenerusGameAdvanceModule.sol` (lines 310-441)
- Decision log: `.planning/STATE.md` (v26.0 decisions)
- PROJECT.md milestone target features
