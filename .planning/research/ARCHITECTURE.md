# Architecture Research

**Domain:** Degenerus Protocol — Always-Open Purchases (v1.0)
**Researched:** 2026-03-11
**Confidence:** HIGH (sourced directly from contracts and implementation plan)

## System Overview

The Degenerus game uses a delegatecall module pattern. `DegenerusGame.sol` holds all state (ETH, storage) and dispatches complex logic to stateless module contracts via `delegatecall`. Every module inherits `DegenerusGameStorage`, which defines the canonical slot layout — modules operate on the main contract's storage via that shared layout.

```
┌──────────────────────────────────────────────────────────────────────┐
│                        DegenerusGame.sol                              │
│  (state owner: holds ETH, all storage slots, external entry points)   │
│                                                                        │
│  recordMint()  receive()  advanceGame()  claimWinnings()  etc.        │
└────────────────────────────┬─────────────────────────────────────────┘
                             │  delegatecall (module code, game storage)
        ┌────────────────────┼────────────────────────────┐
        │                    │                            │
┌───────▼───────┐  ┌─────────▼────────┐  ┌──────────────▼──────┐
│AdvanceModule  │  │  JackpotModule   │  │    MintModule        │
│               │  │                  │  │                      │
│ advanceGame() │  │processTicketBatch│  │_callTicketPurchase() │
│ rngGate()     │  │payDailyJackpot() │  │processFutureTicket.. │
│ _swapTicket.. │  │consolidatePools()│  │_queueLootboxTickets()│
│ _swapAndFreeze│  │                  │  │                      │
└───────────────┘  └──────────────────┘  └──────────────────────┘
        │                    │                            │
        └────────────────────┼────────────────────────────┘
                             │  all read/write via:
┌────────────────────────────▼─────────────────────────────────────────┐
│                   DegenerusGameStorage.sol                             │
│  (abstract — single source of truth for storage slot layout)          │
│                                                                        │
│  Slot 0: levelStartTime, dailyIdx, rngRequestTime, level, jackpot..  │
│  Slot 1: jackpotCounter, rngLockedFlag, purchaseStartDay, ...         │
│  Slot 2: price (uint128)                                               │
│  Slot 3+: currentPrizePool, nextPrizePool, futurePrizePool, ...       │
│  Mappings: ticketQueue, ticketsOwedPacked, claimableWinnings, ...     │
│  Helpers: _queueTickets*(), (new) _tqWriteKey/_tqReadKey, ...        │
└──────────────────────────────────────────────────────────────────────┘
```

Additional modules (WhaleModule, DegeneretteModule, EndgameModule, DecimatorModule, LootboxModule, BoonModule, GameOverModule) follow the same pattern.

## Component Responsibilities

| Component | Responsibility | What Changes |
|-----------|----------------|--------------|
| DegenerusGameStorage | Canonical slot layout, queue helpers, pool helpers | PRIMARY: Add 3 new flags to Slot 1, replace `nextPrizePool`+`futurePrizePool` with `prizePoolsPacked`, add `prizePoolPendingPacked`, add `_tqWriteKey`/`_tqReadKey`, add `_swapTicketSlot`/`_swapAndFreeze`/`_unfreezePool`, update all `_queueTickets*` to write-key |
| DegenerusGameAdvanceModule | Game state machine, daily/mid-day cadence, RNG lifecycle | PRIMARY: Full rewrite of `advanceGame` flow — add mid-day path, gate RNG on drain, call `_swapAndFreeze` at daily RNG, call `_unfreezePool` at unlock points |
| DegenerusGameMintModule | Ticket purchase dispatch, lootbox purchase, future ticket processing | MODIFIED: Remove 2 `rngLockedFlag` reverts; add freeze branch to lootbox pool split; update `processFutureTicketBatch` to use read-key |
| DegenerusGameJackpotModule | Ticket processing, daily jackpot payout, pool consolidation | MODIFIED: `processTicketBatch`+`_processOneTicketEntry` use read-key; migrate all `nextPrizePool`/`futurePrizePool` accesses to `_getPrizePools`/`_setPrizePools` |
| DegenerusGame | Entry points, `recordMint`, ETH receive, public getters | MODIFIED: Add freeze branch to `recordMint` pool split and ETH receive fallback; all pool writes via packed helpers |
| DegenerusGameWhaleModule | Whale bundle / lazy pass purchase paths | MODIFIED: Freeze branch on pool splits at lines 296-297, 419-426, 537-538 |
| DegenerusGameDegeneretteModule | Degenerette bet pool contributions | MODIFIED: Freeze branch on pool split at line 589 |
| DegenerusGameEndgameModule | Endgame settlement | MODIFIED: Migrate `nextPrizePool`/`futurePrizePool` to packed helpers only (game logic — no freeze branch) |
| DegenerusGameDecimatorModule | Decimator lootbox payouts | MODIFIED: Migrate pool reads/writes to packed helpers only |

## New vs Modified — Explicit Classification

### New (does not exist today)

| Item | Location | Type |
|------|----------|------|
| `ticketWriteSlot` (uint8) | DegenerusGameStorage Slot 1 [18:19] | New state variable |
| `ticketsFullyProcessed` (bool) | DegenerusGameStorage Slot 1 [19:20] | New state variable |
| `prizePoolFrozen` (bool) | DegenerusGameStorage Slot 1 [20:21] | New state variable |
| `prizePoolsPacked` (uint256) | DegenerusGameStorage, replaces 2 slots | New packed variable |
| `prizePoolPendingPacked` (uint256) | DegenerusGameStorage, new slot | New packed variable |
| `TICKET_SLOT_BIT` (uint24 constant) | DegenerusGameStorage | New constant |
| `_tqWriteKey(uint24)` | DegenerusGameStorage | New internal function |
| `_tqReadKey(uint24)` | DegenerusGameStorage | New internal function |
| `_swapTicketSlot(uint24)` | DegenerusGameStorage | New internal function (hard gate) |
| `_swapAndFreeze(uint24)` | DegenerusGameStorage | New internal function |
| `_unfreezePool()` | DegenerusGameStorage | New internal function |
| `_getPrizePools()` | DegenerusGameStorage | New view helper |
| `_setPrizePools(uint128, uint128)` | DegenerusGameStorage | New internal helper |
| `_getPendingPools()` | DegenerusGameStorage | New view helper |
| `_setPendingPools(uint128, uint128)` | DegenerusGameStorage | New internal helper |
| `ReadSlotNotDrained` error | DegenerusGameStorage or AdvanceModule | New custom error |
| Mid-day path in `advanceGame` | DegenerusGameAdvanceModule | New code branch |

### Modified (exists today, behavior changes)

| Item | Location | Change |
|------|----------|--------|
| `nextPrizePool` (uint256) | DegenerusGameStorage line 308 | Removed — replaced by `prizePoolsPacked` lower 128 bits |
| `futurePrizePool` (uint256) | DegenerusGameStorage line 409 | Removed — replaced by `prizePoolsPacked` upper 128 bits |
| `_queueTickets()` | DegenerusGameStorage line 497 | Uses `_tqWriteKey(targetLevel)` instead of raw `targetLevel` |
| `_queueTicketsScaled()` | DegenerusGameStorage line 529 | Uses `_tqWriteKey(targetLevel)` instead of raw `targetLevel` |
| `_queueTicketRange()` | DegenerusGameStorage line 585 | Uses `_tqWriteKey(lvl)` per iteration instead of raw `lvl` |
| `_queueLootboxTickets()` | DegenerusGameStorage line 624 | Inherits write-key via `_queueTicketsScaled` |
| `advanceGame()` | DegenerusGameAdvanceModule | Major rewrite — mid-day path, drain gates, `_swapAndFreeze`, `_unfreezePool` call sites |
| `_callTicketPurchase()` | DegenerusGameMintModule line 839 | Remove `rngLockedFlag` revert |
| `_purchaseFor()` | DegenerusGameMintModule line 627 | Remove lootbox+rngLocked compound revert |
| `processFutureTicketBatch()` | DegenerusGameMintModule line 295 | Read-key for queue access |
| `processTicketBatch()` | DegenerusGameJackpotModule line 1914 | Read-key for queue access |
| `_processOneTicketEntry()` | DegenerusGameJackpotModule line 2008 | Read-key for queue access |
| `consolidatePrizePools()` | DegenerusGameJackpotModule | Migrate to `_getPrizePools`/`_setPrizePools` (load-once, store-once) |
| `payDailyJackpot()` | DegenerusGameJackpotModule | Migrate to packed helpers |
| `recordMint()` | DegenerusGame.sol lines 411, 415 | Freeze branch on pool split |
| ETH receive fallback | DegenerusGame.sol line 2820 | Freeze branch on pool split |
| `_applyTimeBasedFutureTake()` | DegenerusGameAdvanceModule | Migrate to packed helpers (game logic, no freeze branch) |
| `_drawDownFuturePrizePool()` | DegenerusGameAdvanceModule | Migrate to packed helpers |
| All whale bundle pool splits | DegenerusGameWhaleModule lines 296-297, 419-426, 537-538 | Add freeze branch |
| Degenerette bet pool split | DegenerusGameDegeneretteModule line 589 | Add freeze branch |
| Endgame pool reads/writes | DegenerusGameEndgameModule | Migrate to packed helpers |
| Decimator pool reads/writes | DegenerusGameDecimatorModule | Migrate to packed helpers |

## Data Flow Changes

### Purchase Flow (before vs after)

**Before:**
```
Player → recordMint/delegatecall _callTicketPurchase
  → if (rngLockedFlag) revert        ← blocks purchase
  → _queueTicketsScaled(level, ...)  ← writes to raw level key
  → nextPrizePool += nextShare       ← direct SSTORE
  → futurePrizePool += futureShare   ← direct SSTORE
```

**After:**
```
Player → recordMint/delegatecall _callTicketPurchase
  → (no rngLockedFlag gate)          ← always allowed
  → wk = _tqWriteKey(level)          ← bit-23 encoded key
  → _queueTicketsScaled(wk, ...)     ← writes to write slot
  → if (prizePoolFrozen):
      _setPendingPools(pNext+share, pFuture+share)  ← pending
    else:
      _setPrizePools(next+share, future+share)      ← live
```

### advanceGame Flow (daily path, simplified)

```
advanceGame() called
  │
  ├─ [day == dailyIdx] ─── MID-DAY PATH ──────────────────────────────┐
  │                                                                     │
  │   1. Read slot has tickets? → process batch, return                 │
  │   2. Read slot empty, write queue >= 440 or jackpotPhase?           │
  │      → _swapTicketSlot()   (queue swap ONLY, no freeze)             │
  │      → return                                                        │
  │   3. Neither → revert NotTimeYet()                                  │
  │                                                                     │
  └─ [day > dailyIdx] ─── DAILY PATH ─────────────────────────────────┘

  GATE: !ticketsFullyProcessed?
    → read slot has tickets? → process batch, return
    → else set ticketsFullyProcessed = true

  rngGate(day):
    → word == 1 (request fired)?
        _swapAndFreeze(purchaseLevel)   ← swap + freeze
        return STAGE_RNG_REQUESTED

    → word ready (processing):
        process tickets (read slot), set ticketsFullyProcessed
        purchase phase daily:
          payDailyJackpot → _unlockRng → _unfreezePool   ← unfreeze
        jackpot phase daily (not last day):
          payDailyJackpot → _unlockRng   (no unfreeze)   ← freeze persists
        jackpot phase last day (day 5):
          _endPhase → _unfreezePool                       ← unfreeze
        phase transition complete:
          _processPhaseTransition → _unlockRng → _unfreezePool ← unfreeze
```

### Prize Pool Freeze State Machine

```
                    ┌─────────────────────┐
                    │   prizePoolFrozen=F  │
                    │  (live pools active) │
                    └────────┬────────────┘
                             │  daily RNG request fires
                             │  _swapAndFreeze()
                             ▼
                    ┌─────────────────────┐
                    │   prizePoolFrozen=T  │◄── jackpot days 2-5
                    │  purchases → pending │    (freeze persists)
                    │  jackpots use live  │
                    └────────┬────────────┘
                             │  one of 3 unfreeze points:
                             │  (a) purchase daily unlock
                             │  (b) jackpot day 5 _endPhase
                             │  (c) phase transition complete
                             │  _unfreezePool()
                             ▼
                    ┌─────────────────────┐
                    │   prizePoolFrozen=F  │
                    │ pending merged→live  │
                    └─────────────────────┘
```

### Queue Double-Buffer Key Encoding

```
ticketWriteSlot = 0:
  write key = level           (bit 23 clear)
  read  key = level | 0x800000 (bit 23 set)

ticketWriteSlot = 1:
  write key = level | 0x800000 (bit 23 set)
  read  key = level            (bit 23 clear)

_swapTicketSlot():
  1. ASSERT ticketQueue[_tqReadKey(purchaseLevel)].length == 0  (hard gate)
  2. ticketWriteSlot ^= 1
  3. ticketsFullyProcessed = false
```

## Integration Points

### New Feature — Existing Architecture Touchpoints

| New Feature | Integrates With | Integration Point | Concern |
|-------------|-----------------|-------------------|---------|
| Write-key encoding | All `_queueTickets*` helpers | DegenerusGameStorage — queue helpers | Every call site that queues tickets must produce the write-key. `_queueTicketRange` iterates per level — the write-key computation must be inside the loop but `ticketWriteSlot` is constant per call, so hoisting the slot bit is safe. |
| Read-key encoding | `processTicketBatch`, `_processOneTicketEntry`, `processFutureTicketBatch` | JackpotModule, MintModule | These functions accept a `lvl` param. The `_tqReadKey(lvl)` call must gate ALL array and mapping accesses for that level. The `ticketCursor` and `ticketLevel` state are slot-agnostic — they track position within the currently active read queue. |
| `_swapAndFreeze` | Daily RNG request path | AdvanceModule `rngGate` return path | Called once, exactly when VRF request is submitted. Not re-entrant. The freeze idempotency guard (`if (!prizePoolFrozen)`) prevents double-freeze during jackpot phase continuation. |
| `_swapTicketSlot` (mid-day) | Mid-day advanceGame path | AdvanceModule mid-day branch | Hard gate in `_swapTicketSlot` itself provides a second defense layer beyond flow-control in `advanceGame`. If the read slot is non-empty, the swap reverts with `ReadSlotNotDrained`. |
| `_unfreezePool` | Three unlock points in AdvanceModule | `_unlockRng` + `_endPhase` + `_processPhaseTransition` | Order matters: pending must be applied before `prizePoolFrozen = false`. The single function enforces this. Callers must not split the operation. |
| Freeze branch in purchase paths | `recordMint`, ETH receive, lootbox, whale, degenerette | DegenerusGame + 3 modules | Every purchase-driven pool addition needs the freeze branch. Missing one is a correctness bug (purchases inflate live pools during jackpot payout). The plan identifies all 9 call sites explicitly. |
| `prizePoolsPacked` helpers | All current `nextPrizePool`/`futurePrizePool` reads/writes | 11 files, 101 occurrences | Migration is mechanical but high surface area. The packed helpers enforce load-once/store-once discipline. Functions that today do multiple intermediate SSTOREs (e.g., `consolidatePrizePools`) must convert to local uint128 variables. |
| `ticketsFullyProcessed` flag | advanceGame daily path gate, mid-day path | AdvanceModule | Set to `false` by `_swapTicketSlot`. Set to `true` after the read slot drains. The flag controls whether advanceGame attempts ticket processing vs proceeds to jackpot logic. Cleared on every swap — including mid-day swaps. |
| `purchaseLevel` key for swap | `_swapTicketSlot`, `_swapAndFreeze` | AdvanceModule computes `purchaseLevel` from `lastPurchase && rngLockedFlag` condition | After this change, `rngLockedFlag` is still set/cleared by AdvanceModule for other non-purchase gates (DegenerusGame.sol lines 1536, 1557, 1572, 1637). `purchaseLevel` computation at line 129 still uses `rngLockedFlag`. The swap functions use `purchaseLevel` only to check/clear the queue — this remains correct. |

### Unchanged Integration Points (no changes required)

| Feature | Modules | Reason |
|---------|---------|--------|
| `rngLockedFlag` (non-purchase uses) | DegenerusGame lines 1536-1637, LootboxModule lines 558, 641, DegeneretteModule line 504, AdvanceModule lines 599, 1195, 1232 | These gates protect burn/open operations and VRF coordinator update, not ticket purchases. They remain as-is. |
| `ticketCursor`, `ticketLevel` | JackpotModule, MintModule, AdvanceModule | Track position within read slot. Double-buffering doesn't affect cursor semantics. |
| Lootbox RNG path | DegenerusGameLootboxModule | Separate lootbox RNG index system is independent of daily queue. |
| VRF callback (`fulfillRandomWords`) | AdvanceModule | Writes `rngWordCurrent`, clears `rngRequestTime`. Unaffected. |
| `claimableWinnings`, `claimablePool` | JackpotModule, DegenerusGame | Pull-pattern payouts unchanged. |
| `traitBurnTicket` | JackpotModule | Trait tickets use a separate mapping. Not part of double-buffer scope. |

## Architectural Patterns

### Pattern 1: Freeze Branch at Purchase-Driven Pool Additions

**What:** Every location that adds ETH to `nextPrizePool` or `futurePrizePool` as a result of a purchase checks `prizePoolFrozen` and redirects to pending accumulators when true.

**When to use:** All 9 purchase-path pool addition sites. Not applicable to game-logic pool mutations (jackpot payout, consolidation, drawdown).

**Trade-offs:** Adding 9 freeze branches increases code surface; all resolve to a single SLOAD + single SSTORE on either path (packed helpers), so gas cost is identical to current behavior.

```solidity
// Pattern applied uniformly at all purchase-path addition sites
if (prizePoolFrozen) {
    (uint128 pNext, uint128 pFuture) = _getPendingPools();
    _setPendingPools(pNext + uint128(nextShare), pFuture + uint128(futureShare));
} else {
    (uint128 next, uint128 future) = _getPrizePools();
    _setPrizePools(next + uint128(nextShare), future + uint128(futureShare));
}
```

### Pattern 2: Load-Once / Store-Once for Pool Mutations

**What:** Functions that perform multiple mutations to prize pools load both values once at entry, work with local uint128 variables, and store once at exit.

**When to use:** All game-logic functions that previously did multiple `nextPrizePool +=` / `futurePrizePool -=` operations. Critical for `consolidatePrizePools`, `payDailyJackpot`, `_drawDownFuturePrizePool`.

**Trade-offs:** Requires restructuring functions with early returns or multiple exit paths. Each exit point must store the locals back. Nets a significant SSTORE reduction on hot paths.

```solidity
// Entry
(uint128 next, uint128 future) = _getPrizePools();
// ... work with locals ...
next += uint128(someAddition);
future -= uint128(someDrawdown);
// Single exit
_setPrizePools(next, future);
```

### Pattern 3: Hard Gate at Swap Function Level

**What:** `_swapTicketSlot` itself enforces the drain invariant rather than relying solely on advanceGame flow-control.

**When to use:** Applied once, in `_swapTicketSlot`.

**Trade-offs:** Dual-layer protection (flow control in advanceGame + revert in swap) means a bug in advanceGame sequencing still can't corrupt the queue state. The check is cheap — one SLOAD of `ticketQueue[rk].length`, zero cost when the read slot is drained (array length at storage is 0).

## Anti-Patterns

### Anti-Pattern 1: Applying Freeze Branch to Game-Logic Pool Mutations

**What people might do:** Add freeze branch to `consolidatePrizePools`, `payDailyJackpot`, `_drawDownFuturePrizePool`.

**Why it's wrong:** These functions run during advanceGame processing, after the swap but before unfreeze. They should operate on live pool values — that's the whole point of freezing (payouts use committed pre-freeze amounts). Redirecting game logic to pending accumulators would starve the jackpot payouts.

**Do this instead:** Migrate these functions to `_getPrizePools`/`_setPrizePools` packed helpers only — no freeze branch.

### Anti-Pattern 2: Mid-Day Swap Triggering Freeze

**What people might do:** Call `_swapAndFreeze` from the mid-day path for symmetry.

**Why it's wrong:** Mid-day processing handles only ticket queue processing — no jackpot payouts, no threshold checks, no pool drawdowns occur. Freezing here would redirect purchase revenue to pending for no reason and would delay the pending merge until the next formal unlock, creating an off-by-one in pool accounting.

**Do this instead:** Mid-day path calls `_swapTicketSlot` only (queue swap, no freeze). The freeze is exclusively the responsibility of the daily RNG request path.

### Anti-Pattern 3: Calling `_unfreezePool` Before Read Slot is Drained

**What people might do:** Unfreeze at `_unlockRng` unconditionally.

**Why it's wrong:** During jackpot phase, `_unlockRng` is called between jackpot days. Unfreezing then would apply accumulated purchase-phase pending amounts to live pools mid-jackpot, inflating pool values used by subsequent jackpot-day payouts.

**Do this instead:** Unfreeze only at the three designated points: (1) purchase phase daily unlock when `!jackpotPhaseFlag`, (2) `_endPhase()` at jackpot phase completion, (3) `_processPhaseTransition()` completion. The advanceGame flow pseudocode in the plan makes these sites explicit.

### Anti-Pattern 4: Skipping Read-Key on Any Queue Access in Processing

**What people might do:** Convert `processTicketBatch` to use `_tqReadKey` at the top, but leave inner function `_processOneTicketEntry` using a raw level key.

**Why it's wrong:** `_processOneTicketEntry` reads from `ticketsOwedPacked[level][buyer]` and writes the drained entry. If it uses a raw key while the outer function uses the read-key, it reads from the wrong slot and silently processes zero tickets.

**Do this instead:** Thread `rk = _tqReadKey(level)` into `_processOneTicketEntry` as a parameter, or compute it inside. All array and mapping accesses for a given queue operation must use the same key.

## Suggested Build Order

Dependencies flow from storage outward to modules. Storage changes must land before any module touches the new API. The freeze branch in purchase paths must be in place before `rngLockedFlag` reverts are removed (otherwise a brief window during testing exists where purchases are open but pools are unprotected).

| Step | Task | Dependency | Rationale |
|------|------|------------|-----------|
| 1 | Storage: Add 3 new flags to Slot 1 | None | Foundation — everything else reads these |
| 2 | Storage: Replace `nextPrizePool`+`futurePrizePool` with `prizePoolsPacked` | Step 1 (fresh deploy assumed) | Pool helpers must exist before any module migration |
| 3 | Storage: Add `prizePoolPendingPacked` and pending helpers | Step 2 | Required by freeze branch |
| 4 | Storage: Add `TICKET_SLOT_BIT`, `_tqWriteKey`, `_tqReadKey` | Step 1 | Required by queue helper updates and all module changes |
| 5 | Storage: Update all `_queueTickets*` to use `_tqWriteKey` | Step 4 | Write path must be correct before any swap can safely occur |
| 6 | Storage: Add `_swapTicketSlot`, `_swapAndFreeze`, `_unfreezePool` | Steps 3, 4, 5 | Swap/freeze/unfreeze compose the helpers from steps 3-5 |
| 7 | JackpotModule: Migrate pool reads/writes to packed helpers | Step 2 | Mechanical — no behavior change, just API swap |
| 8 | JackpotModule: Update `processTicketBatch` + `_processOneTicketEntry` to use `_tqReadKey` | Step 4 | Read path must match write path |
| 9 | MintModule: Update `processFutureTicketBatch` to use `_tqReadKey` | Step 4 | Same as step 8 for future ticket processing |
| 10 | MintModule: Add freeze branch to lootbox pool split | Step 3 | Purchase-path freeze coverage |
| 11 | DegenerusGame: Add freeze branches to `recordMint` and ETH receive | Step 3 | Purchase-path freeze coverage |
| 12 | WhaleModule: Add freeze branches to all bundle/lazy-pass pool splits | Step 3 | Purchase-path freeze coverage |
| 13 | DegeneretteModule: Add freeze branch to bet pool split | Step 3 | Purchase-path freeze coverage |
| 14 | EndgameModule, DecimatorModule, AdvanceModule internals: Migrate pool reads/writes to packed helpers | Step 2 | Game-logic paths — packed helpers only, no freeze branch |
| 15 | MintModule: Remove `rngLockedFlag` reverts from `_callTicketPurchase` and `_purchaseFor` | Steps 10-13 must be complete | All purchase-path freeze branches must exist before removing the lock gate |
| 16 | AdvanceModule: Rewrite `advanceGame` — add mid-day path, drain gates, `_swapAndFreeze`, `_unfreezePool` call sites | Steps 6, 7, 8, 9 | The new flow depends on all storage/module pieces |
| 17 | Test: Foundry unit tests for `_swapTicketSlot` hard gate, freeze/unfreeze cycle, packed pool math | Steps 1-16 | Validate invariants before integration tests |
| 18 | Test: Integration — full purchase-during-RNG-lock scenario, mid-day threshold trigger, jackpot-phase multi-day freeze persistence | Step 16 | Full flow validation |

## Confidence Notes

All findings are sourced directly from `contracts/storage/DegenerusGameStorage.sol`, `contracts/modules/DegenerusGameAdvanceModule.sol`, `contracts/modules/DegenerusGameJackpotModule.sol`, `contracts/modules/DegenerusGameMintModule.sol`, `contracts/DegenerusGame.sol`, and `audit/PLAN-ALWAYS-OPEN-PURCHASES.md`. No external research required — this is a closed codebase with a comprehensive implementation plan already written.

The 101 occurrences of `nextPrizePool`/`futurePrizePool` across 11 files (per grep count) represent the full migration surface for the packed helpers. The plan lists affected files explicitly; the grep confirms nothing is omitted.

The `rngLockedFlag` grep identifies all sites (15 total). Only 2 are targeted for removal (MintModule purchase gates). The remaining 13 sites (burn/open gates, VRF coordinator update, decimator window logic, advanceGame internal flow) are unchanged and must not be touched.

## Sources

- `contracts/storage/DegenerusGameStorage.sol` — slot layout, queue helpers, current `nextPrizePool`/`futurePrizePool` positions
- `contracts/modules/DegenerusGameAdvanceModule.sol` — current `advanceGame` flow, `rngLockedFlag` set/clear points, `purchaseLevel` computation
- `contracts/modules/DegenerusGameJackpotModule.sol` — `processTicketBatch` and `_processOneTicketEntry` signatures, pool mutation patterns
- `contracts/modules/DegenerusGameMintModule.sol` — purchase lock reverts, `processFutureTicketBatch`
- `contracts/DegenerusGame.sol` — `recordMint`, ETH receive, delegatecall dispatch, non-purchase `rngLockedFlag` gates
- `audit/PLAN-ALWAYS-OPEN-PURCHASES.md` — comprehensive implementation plan, pseudocode, invariants, edge cases

---
*Architecture research for: Degenerus Protocol — Always-Open Purchases v1.0*
*Researched: 2026-03-11*
