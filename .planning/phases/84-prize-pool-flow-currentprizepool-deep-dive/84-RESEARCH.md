# Phase 84: Prize Pool Flow & currentPrizePool Deep Dive - Research

**Researched:** 2026-03-23
**Domain:** Solidity smart contract audit -- prize pool storage, freeze lifecycle, consolidation mechanics, and VRF-dependent readers
**Confidence:** HIGH

## Summary

Phase 84 requires exhaustive tracing of every function that reads or writes `currentPrizePool`, the packed `prizePoolsPacked` storage layout, the `prizePoolFrozen` freeze/unfreeze lifecycle, prize pool consolidation mechanics, and all VRF-dependent readers of `currentPrizePool`. This is a re-audit phase: all prior audit prose (v3.5, v3.8) is treated as unverified, and every claim must be confirmed with file:line citations against actual Solidity code, with discrepancies flagged.

The prize pool system uses a four-pool architecture: `futurePrizePool` (long-term reserve, packed upper 128 bits of `prizePoolsPacked`), `nextPrizePool` (accumulator for current purchase phase, packed lower 128 bits), `currentPrizePool` (active jackpot budget, own full uint256 slot), and `claimablePool` (player-owed ETH). During the jackpot phase, `prizePoolFrozen` redirects all incoming purchase revenue to a pending accumulator (`prizePoolPendingPacked`) so that the live pool snapshot used for daily jackpot budgeting is not corrupted by concurrent purchases. The freeze is set by `_swapAndFreeze` (GS:719) at daily RNG request time and cleared by `_unfreezePool` (GS:729) at phase transition end or after jackpot phase completion.

The consolidation function (`consolidatePrizePools` at JM:879) is the critical level-transition entry point that merges `nextPrizePool` into `currentPrizePool`, optionally moves funds from `futurePrizePool` to `currentPrizePool` on x00 milestone levels, credits the DGNRS coinflip pool, and distributes yield surplus. This function is called exclusively via delegatecall from `AdvanceModule._consolidatePrizePools` (AM:541) during the purchase-to-jackpot phase transition. There are exactly 6 locations where `currentPrizePool` is written (2 additions in consolidation, 2 subtractions in daily jackpot distribution, 2 zero-assignments in GameOver).

**Primary recommendation:** Systematically enumerate every reader and writer of `currentPrizePool` with file:line citations, document the packed `prizePoolsPacked` layout and accessor pattern, trace the full freeze/unfreeze lifecycle including all 13+ `prizePoolFrozen` check sites, document the consolidation flow step by step, identify all VRF-dependent readers of `currentPrizePool`, and flag discrepancies between current code and prior audit documentation (v3.5, v3.8).

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PPF-01 | currentPrizePool storage slot confirmed, all writers enumerated with file:line | Storage slot 2 confirmed from DegenerusGameStorage layout comment (GS:70-73) and variable declaration (GS:348). 6 write sites identified across JackpotModule (4 sites: JM:403, JM:522, JM:889, JM:900) and GameOverModule (2 sites: GM:118, GM:130). Readers include JM:365, JM:905, JM:915, DG:2141, DG:2168, and view functions. |
| PPF-02 | prizePoolsPacked storage layout documented (packed fields, bit positions, BPS allocations) | Slot 3: lower 128 bits = nextPrizePool (uint128), upper 128 bits = futurePrizePool (uint128). Accessors: `_setPrizePools` (GS:660), `_getPrizePools` (GS:664), `_setPendingPools` (GS:670), `_getPendingPools` (GS:674). Single-component accessors: `_getNextPrizePool` (GS:743), `_setNextPrizePool` (GS:749), `_getFuturePrizePool` (GS:755), `_setFuturePrizePool` (implicit). BPS allocations: PURCHASE_TO_FUTURE_BPS=1000 (10% future), remainder to next. Whale/deity: level 0 = 30/70 next/future, level 1+ = 5/95 next/future. |
| PPF-03 | prizePoolFrozen freeze/unfreeze lifecycle traced with all trigger conditions | Freeze set at GS:722 via `_swapAndFreeze` (called at AM:233 on daily RNG request). Unfreeze at GS:735 via `_unfreezePool` (called at AM:246 phase transition complete, AM:293 purchase phase daily, AM:369 jackpot phase ended). 13+ check sites: DG:396 (purchase), DG:1750 (sDGNRS lootbox), DG:2840 (receive), MM:779 (mint lootbox), WM:298/434/551 (whale/lazy/deity), DegeneretteModule:558/685 (bet/payout), DM:321/834 (decimator claim). |
| PPF-04 | Prize pool consolidation mechanics documented with file:line | `consolidatePrizePools` at JM:879-908 via delegatecall from AM:541-551. Steps: (1) x00 yield dump: 50% of yieldAccumulator to futurePrizePool (JM:881-886). (2) Merge: currentPrizePool += nextPrizePool, zero next (JM:889-890). (3) x00 keep roll: 30-65% kept in future, rest to current (JM:892-902, via `_futureKeepBps` JM:1281). (4) Credit coinflip (JM:905). (5) Distribute yield surplus (JM:907). Pre-consolidation: `_applyTimeBasedFutureTake` at AM:1029 skims next->future, `levelPrizePool[purchaseLevel]` recorded at AM:314. |
| PPF-05 | All VRF-dependent readers of currentPrizePool documented | Primary VRF-dependent reader: `payDailyJackpot` reads `currentPrizePool` at JM:365 (pool snapshot for daily budget), writes at JM:403 (lootbox deduction) and JM:522 (ETH payout deduction). `consolidatePrizePools` at JM:889/900 reads/writes but runs post-VRF-fulfillment during advanceGame flow. `_distributeYieldSurplus` at JM:915 reads as part of obligations calculation. `_creditDgnrsCoinflip` at JM:905/2346 reads currentPrizePool for coinflip credit sizing. v3.8 verdict: SAFE (freeze-gated during daily window, not read by rawFulfillRandomWords). |
| PPF-06 | Every discrepancy and new finding tagged | Research identified v3.8 claims to cross-reference: Section 1.10 consolidation inventory (JM:879-908), Section 4 currentPrizePool SAFE verdict, prizePoolsPacked SAFE verdict, prizePoolPendingPacked SAFE verdict. v3.5 confirmed consolidatePrizePools NatSpec accurate (v3.5-comment-findings-54-05 line 181). Potential line drift: v3.8 references AM lines that may have shifted by 3 lines (consistent with Phase 81 findings). |
</phase_requirements>

## Architecture Patterns

### Contract Architecture (Delegatecall)

DegenerusGame holds all state. Modules execute via delegatecall, sharing the storage layout from `DegenerusGameStorage.sol`. Key modules for prize pool flow:

| Module | File | Prize Pool Functions |
|--------|------|---------------------|
| JackpotModule | `contracts/modules/DegenerusGameJackpotModule.sol` (2794 lines) | `consolidatePrizePools`, `payDailyJackpot`, `_creditDgnrsCoinflip`, `_distributeYieldSurplus`, `_dailyCurrentPoolBps`, `_futureKeepBps` |
| AdvanceModule | `contracts/modules/DegenerusGameAdvanceModule.sol` (1558 lines) | `_consolidatePrizePools` (delegatecall wrapper), `_applyTimeBasedFutureTake`, `_drawDownFuturePrizePool`, `_swapAndFreeze`, `_unfreezePool` |
| GameOverModule | `contracts/modules/DegenerusGameGameOverModule.sol` | Terminal zeroing of all pools |
| MintModule | `contracts/modules/DegenerusGameMintModule.sol` | Lootbox ETH split to pools |
| WhaleModule | `contracts/modules/DegenerusGameWhaleModule.sol` | Whale/lazy/deity pass ETH split to pools |
| DegeneretteModule | `contracts/modules/DegenerusGameDegeneretteModule.sol` | Bet ETH to future pool; payout freeze guard |
| DecimatorModule | `contracts/modules/DegenerusGameDecimatorModule.sol` | Claim freeze guard; lootbox portion to future pool |
| DegenerusGame | `contracts/DegenerusGame.sol` | `_processMintPayment` pool routing, `receive()` pool routing, view functions |

### Four-Pool Architecture

```
                    Purchase Revenue
                         |
                  10% / 90% split
                 (PURCHASE_TO_FUTURE_BPS = 1000)
                  /             \
          futurePrizePool    nextPrizePool
          (long-term          (current level
           reserve)            accumulator)
               |                    |
               |     consolidatePrizePools (at level transition)
               |     - merge next into current
               |     - x00: roll 30-65% keep, move rest
               |                    |
               +------>  currentPrizePool  <------+
                     (active jackpot budget)
                              |
                    payDailyJackpot
                    (6-14% days 1-4, 100% day 5)
                              |
                       claimablePool
                    (player-owed ETH)
```

### Storage Slot Layout (Prize Pool Variables)

```
EVM Slot 1, byte [26:27]:  prizePoolFrozen (bool)       -- GS:339
EVM Slot 2 (full word):    currentPrizePool (uint256)    -- GS:348
EVM Slot 3 (full word):    prizePoolsPacked (uint256)    -- GS:356
                           [0:128]   nextPrizePool    (uint128)
                           [128:256] futurePrizePool  (uint128)
Variable slot (after mappings): prizePoolPendingPacked (uint256) -- GS:449
                           [0:128]   nextPrizePoolPending    (uint128)
                           [128:256] futurePrizePoolPending  (uint128)
```

### currentPrizePool Write Sites (Complete Enumeration)

| # | Location | Operation | Context |
|---|----------|-----------|---------|
| 1 | JM:889 | `currentPrizePool += _getNextPrizePool()` | consolidatePrizePools: merge next into current |
| 2 | JM:900 | `currentPrizePool += moveWei` | consolidatePrizePools: x00 future->current transfer |
| 3 | JM:403 | `currentPrizePool -= dailyLootboxBudget` | payDailyJackpot: deduct lootbox ticket budget |
| 4 | JM:522 | `currentPrizePool -= paidDailyEth` | payDailyJackpot: deduct daily ETH paid to winners |
| 5 | GM:118 | `currentPrizePool = 0` | gameOver: zero when no available funds |
| 6 | GM:130 | `currentPrizePool = 0` | gameOver: zero after final jackpot paid |

### currentPrizePool Read Sites (Complete Enumeration)

| # | Location | Context | VRF-Dependent? |
|---|----------|---------|----------------|
| 1 | JM:365 | `poolSnapshot = currentPrizePool` (daily budget calculation) | YES -- read during payDailyJackpot, budget is VRF-BPS-derived |
| 2 | JM:905 | `_creditDgnrsCoinflip(currentPrizePool)` | YES -- during consolidation, uses pool value for coinflip credit |
| 3 | JM:915 | `obligations = currentPrizePool + ...` (yield surplus check) | YES -- during consolidation's yield surplus distribution |
| 4 | DG:2141 | `currentPrizePoolView()` external view | NO -- view function only |
| 5 | DG:2168 | `obligations = currentPrizePool + ...` (yieldPoolView) | NO -- view function only |

### prizePoolFrozen Lifecycle

```
                 advanceGame (daily)
                       |
            _swapAndFreeze(purchaseLevel) -- AM:233
                       |
           +-----------+-----------+
           |                       |
    !prizePoolFrozen         prizePoolFrozen
           |                  (already frozen,
    prizePoolFrozen = true     multi-day jackpot)
    prizePoolPendingPacked = 0    |
           |                   no-op
           +------- FROZEN ----+
                       |
        [purchase revenue -> pending accumulators]
        [daily jackpot budget computed from frozen snapshot]
        [1-5 jackpot days elapse]
                       |
                 _unfreezePool() -- GS:729
                       |
        (uint128 pNext, pFuture) = _getPendingPools()
        (uint128 next, future) = _getPrizePools()
        _setPrizePools(next + pNext, future + pFuture)
        prizePoolPendingPacked = 0
        prizePoolFrozen = false
                       |
                   UNFROZEN
```

### prizePoolFrozen Check Sites (13 identified)

| # | File | Line | Action on Frozen |
|---|------|------|-----------------|
| 1 | DG | 396 | Purchase: redirect prize contribution to pending accumulators |
| 2 | DG | 1750 | sDGNRS lootbox: redirect amount to pending future pool |
| 3 | DG | 2840 | receive(): redirect ETH to pending future pool |
| 4 | MM | 779 | Mint lootbox: redirect split to pending pools |
| 5 | WM | 298 | Whale bundle: redirect split to pending pools |
| 6 | WM | 434 | Lazy pass: redirect split to pending pools |
| 7 | WM | 551 | Deity pass: redirect split to pending pools |
| 8 | DegeneretteM | 558 | Place bet: redirect bet ETH to pending future pool |
| 9 | DegeneretteM | 685 | Distribute payout: REVERT if frozen (would corrupt snapshot) |
| 10 | DM | 321 | Claim decimator jackpot: REVERT if frozen |
| 11 | DM | 834 | Claim terminal decimator: REVERT if frozen |
| 12 | GS | 721 | _swapAndFreeze: sets frozen if not already |
| 13 | GS | 730 | _unfreezePool: clears frozen and merges pending |

**Two patterns of frozen handling:**
- **Redirect (7 sites):** Routes ETH to pending accumulators instead of live pools. Purchases, bets, and receive() all use this pattern.
- **Revert (3 sites):** Blocks the operation entirely. Degenerette ETH payout and decimator claims revert because they read from `futurePrizePool` directly, which must be immutable during jackpot processing.

### _unfreezePool Call Sites

| # | Location | Context |
|---|----------|---------|
| 1 | AM:246 | Phase transition complete (purchase phase starts) |
| 2 | AM:293 | Purchase phase daily jackpot complete |
| 3 | AM:369 | Jackpot phase ended (all 5 days done, after _runRewardJackpots) |

### Consolidation Flow (Step by Step)

Pre-consolidation (AM:313-316):
1. `levelPrizePool[purchaseLevel] = _getNextPrizePool()` -- record level target (AM:314)
2. `_applyTimeBasedFutureTake(ts, purchaseLevel, rngWord)` -- skim next->future based on time elapsed (AM:1029-1101)
3. `_consolidatePrizePools(purchaseLevel, rngWord)` -- delegatecall to JM:879

Within `consolidatePrizePools` (JM:879-908):
1. **x00 yield dump** (JM:881-886): If `lvl % 100 == 0`, move 50% of `yieldAccumulator` into `futurePrizePool`
2. **Merge** (JM:889-890): `currentPrizePool += _getNextPrizePool()` then zero next
3. **x00 keep roll** (JM:892-902): If `lvl % 100 == 0`, roll `_futureKeepBps(rngWord)` (30-65%, 5-dice), move remainder from future to current
4. **Credit coinflip** (JM:905): `_creditDgnrsCoinflip(currentPrizePool)` -- mints BURNIE to sDGNRS coinflip based on pool value
5. **Yield surplus** (JM:907): `_distributeYieldSurplus(rngWord)` -- 23% each to DGNRS/Vault claimable, 46% to yield accumulator

Post-consolidation (AM:327-338):
1. Enter jackpot phase: `jackpotPhaseFlag = true`
2. `_drawDownFuturePrizePool(lvl)` -- 15% of future -> next on non-x00 levels (AM:1106-1118)

### BPS Allocation Constants

| Constant | Value | Location | Purpose |
|----------|-------|----------|---------|
| PURCHASE_TO_FUTURE_BPS | 1000 (10%) | DG:186 | Purchase revenue future share |
| DAILY_CURRENT_BPS_MIN | 600 (6%) | JM:146 | Min daily pool budget |
| DAILY_CURRENT_BPS_MAX | 1400 (14%) | JM:147 | Max daily pool budget |
| DAILY_REWARD_JACKPOT_LOOTBOX_BPS | 5000 (50%) | JM:176 | Carryover lootbox share |
| NEXT_TO_FUTURE_BPS_FAST | 3000 (30%) | AM:99 | Fast-target skim |
| NEXT_TO_FUTURE_BPS_MIN | 1300 (13%) | AM:100 | Minimum skim |
| NEXT_TO_FUTURE_BPS_X9_BONUS | 200 (2%) | AM:102 | x9 level bonus skim |
| NEXT_TO_FUTURE_BPS_MAX | 8000 (80%) | AM:109 | Hard cap on total skim |

### Whale/Deity Pass Pool Split

| Level | Next Share | Future Share | Source |
|-------|-----------|--------------|--------|
| Level 0 | 30% (3000 BPS) | 70% | WM:293, WM:547 |
| Level 1+ | 5% (500 BPS) | 95% | WM:295, WM:549 |

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Prize pool tracing | Custom static analysis | Systematic grep + manual code reading with file:line | Delegatecall patterns confuse automated analyzers |
| Storage slot verification | Manual counting | `forge inspect DegenerusGame storage-layout` | Compiler-authoritative slot assignments |
| Discrepancy detection | Trusting prior audit docs | Independent code reading, then cross-reference v3.5/v3.8 | v3.8 has confirmed line drift (Phase 81 findings) |
| Packed field layout | Manual bit arithmetic | Read helper functions `_getPrizePools`/`_setPrizePools` source | Helpers are the single access point -- analyzing them is sufficient |

## Common Pitfalls

### Pitfall 1: Missing the Pending Accumulator Pattern
**What goes wrong:** Reporting that purchase revenue writes to `currentPrizePool` during jackpot phase
**Why it happens:** The freeze redirect is not in the same file as the pool variable declaration
**How to avoid:** Trace both paths at every check site: frozen -> pending accumulators, unfrozen -> live pools. The pending pattern is consistent across all 7 redirect sites.
**Warning signs:** Any claim that `currentPrizePool` is written during jackpot phase by purchase functions.

### Pitfall 2: Confusing consolidatePrizePools with _consolidatePrizePools
**What goes wrong:** Searching for `consolidatePrizePools` callers and missing that the actual entry point is the private wrapper
**Why it happens:** `consolidatePrizePools` (JM:879) is external, but only called via delegatecall from `_consolidatePrizePools` (AM:541). The underscore-prefixed private wrapper is the actual call site.
**How to avoid:** Always follow the delegatecall chain: AM:316 calls AM:541 which delegatecalls JM:879.

### Pitfall 3: Missing the x00 Special Path in Consolidation
**What goes wrong:** Documenting consolidation as "merge next into current" and missing the x00 yield dump and keep roll
**Why it happens:** The x00 blocks are conditional (`if (lvl % 100) == 0`) and easy to skip during reading
**How to avoid:** Note that consolidation has FIVE steps, not one. Steps 1, 3 are x00-only. The keep roll uses VRF entropy (RNG-dependent).

### Pitfall 4: Treating _applyTimeBasedFutureTake as Part of Consolidation
**What goes wrong:** Including the time-based future take inside the consolidation documentation
**Why it happens:** It runs immediately before consolidation in the advanceGame flow
**How to avoid:** `_applyTimeBasedFutureTake` is at AM:1029, called from AM:315. It modifies `prizePoolsPacked` (next/future) but NOT `currentPrizePool`. It is a pre-consolidation step, not part of `consolidatePrizePools`.

### Pitfall 5: Assuming currentPrizePool Is VRF-Safe Because of Freeze
**What goes wrong:** Concluding SAFE without verifying that rawFulfillRandomWords does not read it
**Why it happens:** Freeze protects against purchase-time mutation but the real safety question is whether the VRF callback reads the variable
**How to avoid:** The v3.8 verdict is correct (SAFE), but the REASON is important: rawFulfillRandomWords does NOT read `currentPrizePool`. The freeze protects the pool snapshot for payDailyJackpot (which runs AFTER VRF fulfillment), not for the VRF callback itself. This distinction matters.

### Pitfall 6: Missing the Two Revert Sites
**What goes wrong:** Documenting all prizePoolFrozen check sites as "redirect to pending"
**Why it happens:** Most sites (7/10) use the redirect pattern, so it is easy to assume all do
**How to avoid:** DegeneretteModule:685 and DecimatorModule:321/834 REVERT when frozen. These are fundamentally different from the redirect pattern -- they block the operation entirely because they would read from the live futurePrizePool.

### Pitfall 7: Stale Line References from v3.8
**What goes wrong:** Citing v3.8 commitment window inventory line numbers as current
**Why it happens:** Phase 81 documented 3-line drift in AdvanceModule from code additions
**How to avoid:** Always verify v3.8 references against current code. Known drift: AM:230->AM:233 (_swapAndFreeze), AM:717->AM:720 (_swapTicketSlot).

## Code Examples

### Packed Prize Pool Helpers (GS:660-678)
```solidity
// Source: contracts/storage/DegenerusGameStorage.sol:660-678
function _setPrizePools(uint128 next, uint128 future) internal {
    prizePoolsPacked = uint256(future) << 128 | uint256(next);
}

function _getPrizePools() internal view returns (uint128 next, uint128 future) {
    uint256 packed = prizePoolsPacked;
    next = uint128(packed);
    future = uint128(packed >> 128);
}

function _setPendingPools(uint128 next, uint128 future) internal {
    prizePoolPendingPacked = uint256(future) << 128 | uint256(next);
}

function _getPendingPools() internal view returns (uint128 next, uint128 future) {
    uint256 packed = prizePoolPendingPacked;
    next = uint128(packed);
    future = uint128(packed >> 128);
}
```

### Freeze and Unfreeze (GS:719-736)
```solidity
// Source: contracts/storage/DegenerusGameStorage.sol:719-736
function _swapAndFreeze(uint24 purchaseLevel) internal {
    _swapTicketSlot(purchaseLevel);
    if (!prizePoolFrozen) {
        prizePoolFrozen = true;
        prizePoolPendingPacked = 0;
    }
}

function _unfreezePool() internal {
    if (!prizePoolFrozen) return;
    (uint128 pNext, uint128 pFuture) = _getPendingPools();
    (uint128 next, uint128 future) = _getPrizePools();
    _setPrizePools(next + pNext, future + pFuture);
    prizePoolPendingPacked = 0;
    prizePoolFrozen = false;
}
```

### consolidatePrizePools (JM:879-908)
```solidity
// Source: contracts/modules/DegenerusGameJackpotModule.sol:879-908
function consolidatePrizePools(uint24 lvl, uint256 rngWord) external {
    // Step 1: x00 yield dump (50% of yieldAccumulator -> futurePrizePool)
    if ((lvl % 100) == 0) {
        uint256 acc = yieldAccumulator;
        uint256 half = acc >> 1;
        _setFuturePrizePool(_getFuturePrizePool() + half);
        yieldAccumulator = acc - half;
    }

    // Step 2: Merge next into current
    currentPrizePool += _getNextPrizePool();
    _setNextPrizePool(0);

    // Step 3: x00 keep roll (30-65% kept in future, rest to current)
    if ((lvl % 100) == 0) {
        uint256 keepBps = _futureKeepBps(rngWord);
        uint256 fp = _getFuturePrizePool();
        if (keepBps < 10_000 && fp != 0) {
            uint256 keepWei = (fp * keepBps) / 10_000;
            uint256 moveWei = fp - keepWei;
            if (moveWei != 0) {
                _setFuturePrizePool(keepWei);
                currentPrizePool += moveWei;
            }
        }
    }

    // Step 4: Credit coinflip
    _creditDgnrsCoinflip(currentPrizePool);

    // Step 5: Distribute yield surplus
    _distributeYieldSurplus(rngWord);
}
```

### Purchase Revenue Pool Routing (DG:392-408)
```solidity
// Source: contracts/DegenerusGame.sol:392-408
if (prizeContribution != 0) {
    uint256 futureShare = (prizeContribution * PURCHASE_TO_FUTURE_BPS) / 10_000;
    uint256 nextShare = prizeContribution - futureShare;
    if (prizePoolFrozen) {
        (uint128 pNext, uint128 pFuture) = _getPendingPools();
        _setPendingPools(pNext + uint128(nextShare), pFuture + uint128(futureShare));
    } else {
        (uint128 next, uint128 future) = _getPrizePools();
        _setPrizePools(next + uint128(nextShare), future + uint128(futureShare));
    }
}
```

### Daily Pool Budget Calculation (JM:362-376)
```solidity
// Source: contracts/modules/DegenerusGameJackpotModule.sol:362-376
bool isFinalPhysicalDay = (counter + counterStep >= JACKPOT_LEVEL_CAP);
bool isEarlyBirdDay = (counter == 0);
uint256 poolSnapshot = currentPrizePool;  // <-- VRF-dependent READ
uint16 dailyBps;
if (isFinalPhysicalDay) {
    dailyBps = 10_000; // 100% of remaining pool
} else {
    dailyBps = _dailyCurrentPoolBps(counter, randWord); // VRF-derived 6-14%
    if (counterStep == 2) {
        dailyBps *= 2; // Double for compressed days
    }
}
uint256 budget = (poolSnapshot * dailyBps) / 10_000;
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No freeze mechanism | prizePoolFrozen + pending accumulators | Pre-v3.0 era | Prevents pool corruption during jackpot phase |
| Separate next/future storage slots | Packed prizePoolsPacked (1 SSTORE) | Pre-v3.0 era | Gas optimization: single SSTORE for both fields |
| consolidatePrizePools had different step 3 | 30-65% keep roll via 5-dice (_futureKeepBps) | Updated pre-v3.2 | NatSpec confirmed correct in v3.5 audit (CMT-V35 line 181) |

**Prior audits on prize pool:**
- v3.5 (comment findings): Confirmed consolidatePrizePools NatSpec accurate (30-65% keep range)
- v3.5 (comment findings): Confirmed FUND ACCOUNTING description (futurePrizePool, currentPrizePool, nextPrizePool, claimablePool) matches code
- v3.8 (commitment window inventory): Section 1.10 documents consolidation reads/writes. Section 4 currentPrizePool verdict: SAFE (freeze-gated).
- v3.8: Known line drift in AdvanceModule (3-line shift from code additions, confirmed in Phase 81)

## Open Questions

1. **prizePoolPendingPacked slot number**
   - What we know: Declared at GS:449, after several mappings. The v3.8 inventory does not give its exact slot number in the Section 4 entry.
   - What's unclear: Exact compiler-assigned slot number. Need `forge inspect` to confirm.
   - Recommendation: Run `forge inspect DegenerusGame storage-layout` during plan execution and confirm the slot numbers for `currentPrizePool` (should be 2), `prizePoolsPacked` (should be 3), and `prizePoolPendingPacked`.

2. **_drawDownFuturePrizePool timing relative to consolidation**
   - What we know: Called at AM:338, AFTER consolidation (AM:316) and after jackpotPhaseFlag=true (AM:327). It moves 15% of future to next on non-x00 levels.
   - What's unclear: Whether this 15% drawdown runs on the SAME advanceGame call as consolidation. It appears to -- both are in the "entered jackpot" block of the purchase-to-jackpot transition.
   - Recommendation: Verify during audit that drawdown runs in the same transaction as consolidation and does not affect `currentPrizePool`.

3. **yieldAccumulator slot number from v3.8**
   - What we know: v3.8 says slot 100. Memory file says slot numbering may be stale.
   - Recommendation: Verify with `forge inspect`.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge) + Hardhat |
| Config file | `foundry.toml` |
| Quick run command | `forge test --match-contract PrizePoolFreeze -vvv` |
| Full suite command | `forge test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PPF-01 | currentPrizePool writers enumerated | manual audit | N/A (code trace) | N/A |
| PPF-02 | prizePoolsPacked layout documented | manual audit + storage inspect | `forge inspect DegenerusGame storage-layout` | N/A |
| PPF-03 | prizePoolFrozen lifecycle traced | manual audit + existing test | `forge test --match-contract PrizePoolFreeze -vvv` | Yes (test/fuzz/PrizePoolFreeze.t.sol) |
| PPF-04 | Consolidation mechanics documented | manual audit | N/A (code trace) | N/A |
| PPF-05 | VRF-dependent readers documented | manual audit | N/A (code trace + v3.8 cross-ref) | N/A |
| PPF-06 | Discrepancies flagged | manual audit | N/A (doc review) | N/A |

### Sampling Rate
- **Per task commit:** `forge test --match-contract PrizePoolFreeze -vvv` (verify no regression)
- **Per wave merge:** `forge test` (full suite)
- **Phase gate:** All existing Foundry tests pass before /gsd:verify-work

### Wave 0 Gaps
None -- this is an audit-only phase (no code changes). Existing test infrastructure covers prize pool freeze mechanics. The deliverable is an audit document, not code.

## Known Prior Audit Claims to Cross-Reference

These claims from v3.5 and v3.8 must be independently verified during plan execution:

### From v3.8 Commitment Window Inventory

1. **Section 1.10**: consolidatePrizePools reads/writes -- `yieldAccumulator` (slot 100 R/W), `currentPrizePool` (slot 2 R/W), `prizePoolsPacked` (slot 3 R/W), `claimableWinnings` (W), `claimablePool` (R/W), `autoRebuyState` (R). Lines JM:879-908.
2. **Section 4 currentPrizePool verdict**: SAFE -- "prizePoolFrozen = true. All purchase revenue is redirected to prizePoolPendingPacked. currentPrizePool is immutable during daily window."
3. **Section 4 prizePoolsPacked verdict**: SAFE -- "Freeze-gated. During daily window, permissionless writes go to prizePoolPendingPacked instead."
4. **Section 4 prizePoolPendingPacked verdict**: SAFE -- "Freeze accumulator; not read by any VRF-dependent outcome computation during commitment windows."
5. **Section 1.11**: _applyTimeBasedFutureTake reads `levelStartTime` (slot 0 offset 0), `prizePoolsPacked` (slot 3 R/W), `levelPrizePool[lvl-1]`, `yieldAccumulator`.

### From v3.5 Comment Findings

6. **CMT-V35 line 181**: "consolidatePrizePools NatSpec (lines 866-878) accurately describes pool merge and x00 keep roll."
7. **CMT-V35 line 176**: "FUND ACCOUNTING description (lines 33-37) matches actual pool flow: futurePrizePool, currentPrizePool, nextPrizePool, claimablePool."

### Known Line Drift (from Phase 81)

- `_swapAndFreeze` call: v3.8 says AM:230, current code AM:233 (3-line shift)
- Same 3-line shift expected for all AdvanceModule references in v3.8

## Sources

### Primary (HIGH confidence)
- `contracts/storage/DegenerusGameStorage.sol` -- storage layout, packed pool helpers, freeze/unfreeze mechanics (GS:50-100 layout comment, GS:339 prizePoolFrozen, GS:348 currentPrizePool, GS:356 prizePoolsPacked, GS:449 prizePoolPendingPacked, GS:660-758 helpers, GS:709-736 swap/freeze)
- `contracts/modules/DegenerusGameJackpotModule.sol` -- consolidatePrizePools (JM:879-908), payDailyJackpot pool reads/writes (JM:365-522), _creditDgnrsCoinflip (JM:2346), _distributeYieldSurplus (JM:910-944), _futureKeepBps (JM:1281-1296), _dailyCurrentPoolBps (JM:2656-2669), BPS constants (JM:146-176)
- `contracts/modules/DegenerusGameAdvanceModule.sol` -- _consolidatePrizePools wrapper (AM:541-551), _applyTimeBasedFutureTake (AM:1029-1101), _drawDownFuturePrizePool (AM:1106-1118), _swapAndFreeze call (AM:233), _unfreezePool calls (AM:246, AM:293, AM:369), BPS constants (AM:99-109)
- `contracts/modules/DegenerusGameGameOverModule.sol` -- terminal zeroing (GM:118, GM:130)
- `contracts/DegenerusGame.sol` -- _processMintPayment pool routing (DG:392-408), receive() pool routing (DG:2838-2847), view functions (DG:2140-2175), PURCHASE_TO_FUTURE_BPS constant (DG:186)
- All freeze-check modules: MM:779, WM:298/434/551, DegeneretteM:558/685, DM:321/834

### Secondary (MEDIUM confidence)
- `audit/v3.8-commitment-window-inventory.md` -- Sections 1.10, 1.11, and Section 4 prize pool verdicts (to be cross-referenced)
- `audit/v3.5-comment-findings-54-05-game-modules.md` -- consolidatePrizePools NatSpec confirmation
- `.planning/phases/81-ticket-creation-queue-mechanics/81-RESEARCH.md` -- Phase 81 research (line drift documentation, audit methodology pattern)

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- currentPrizePool writers: HIGH -- complete grep enumeration across all contracts, 6 write sites confirmed
- prizePoolsPacked layout: HIGH -- storage comment, variable declaration, and accessor functions all consistent
- prizePoolFrozen lifecycle: HIGH -- freeze set/clear sites and all 13 check sites identified from grep
- Consolidation mechanics: HIGH -- single function, 5 well-defined steps, NatSpec confirmed correct in v3.5
- VRF-dependent readers: HIGH -- traced from v3.8 backward trace categories, consistent with current code structure

**Research date:** 2026-03-23
**Valid until:** Indefinite (audit of immutable contract code)

## Project Constraints (from CLAUDE.md)

From global CLAUDE.md:
- **Self-check before delivering results** -- after completing any substantial task, internally review for gaps, stale references, cascading changes

From project memory:
- **Only read contracts from `contracts/` directory** -- stale copies exist elsewhere
- **Present fix and wait for explicit approval before editing code** -- audit-only phase, no code changes
- **NEVER commit contracts/ or test/ changes without explicit user approval** -- N/A for audit-only phase
- **Every RNG audit must trace BACKWARD from each consumer** -- applicable to verifying VRF-dependent readers of currentPrizePool
- **Every RNG audit must check what player-controllable state can change between VRF request and fulfillment** -- applicable to verifying freeze guard protects currentPrizePool during commitment window

From STATE.md:
- **v3.8 commitment window inventory has line drift** -- all v3.8 references must be verified against current code (3-line shift in AdvanceModule confirmed in Phase 81)
- **DSC-01/DSC-02 (PPF-06) are cross-cutting** -- apply to all v4.0 phases
