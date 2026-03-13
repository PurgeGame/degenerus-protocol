# Pool Architecture: Storage, Lifecycle, Transitions, and Level Advancement

**Purpose:** Reference for tracing ETH through the pool system -- from deposit to payout eligibility. Every transition is documented with exact trigger conditions, function names, and Solidity expressions.

**Date:** 2026-03-12
**Source contracts:** DegenerusGameStorage.sol, DegenerusGameAdvanceModule.sol, DegenerusGameJackpotModule.sol, DegenerusGame.sol

---

## 1. Storage Layout

Four storage primitives hold the pool state:

### 1a. `prizePoolsPacked` (uint256) -- DegenerusGameStorage slot

Packs two uint128 pools into a single EVM slot:

| Bits | Field | Type | Description |
|------|-------|------|-------------|
| [0:128] | nextPrizePool | uint128 | Accumulates from purchases during current level's purchase phase |
| [128:256] | futurePrizePool | uint128 | Long-term reserve; funds future jackpots via drawdown |

### 1b. `currentPrizePool` (uint256) -- separate full slot

Active jackpot pool during jackpot phase. Receives funds from nextPrizePool (and sometimes futurePrizePool) at consolidation. Pays out to winners during 5-day jackpot.

**Critical:** This is a standalone uint256, NOT packed. It is NOT subject to the freeze mechanism.

### 1c. `prizePoolPendingPacked` (uint256) -- DegenerusGameStorage slot

Pending accumulator during freeze. Same packing as `prizePoolsPacked`:

| Bits | Field | Type | Description |
|------|-------|------|-------------|
| [0:128] | nextPrizePoolPending | uint128 | Next pool contributions during freeze |
| [128:256] | futurePrizePoolPending | uint128 | Future pool contributions during freeze |

Merged into live pools atomically by `_unfreezePool()`.

### 1d. `levelPrizePool` (mapping(uint24 => uint256))

Snapshot of nextPrizePool at each level transition. Serves as the ratchet target for level advancement.

- `levelPrizePool[0]` = `BOOTSTRAP_PRIZE_POOL` = 50 ether (set in constructor, `DegenerusGame.sol:258`)
- `levelPrizePool[N]` = snapshot of `_getNextPrizePool()` at level N transition (`AdvanceModule:281`)
- **x00 levels:** `levelPrizePool[lvl]` = `_getFuturePrizePool() / 3` (set in `_endPhase()`, `AdvanceModule:442`)

### Helper Functions (DegenerusGameStorage)

| Function | Signature | Purpose |
|----------|-----------|---------|
| `_setPrizePools` | `(uint128 next, uint128 future) internal` | Pack and write live pools |
| `_getPrizePools` | `() internal view returns (uint128 next, uint128 future)` | Unpack live pools |
| `_setPendingPools` | `(uint128 next, uint128 future) internal` | Pack and write pending pools |
| `_getPendingPools` | `() internal view returns (uint128 next, uint128 future)` | Unpack pending pools |
| `_getNextPrizePool` | `() internal view returns (uint256)` | Read next component only |
| `_setNextPrizePool` | `(uint256 val) internal` | Write next component only |
| `_getFuturePrizePool` | `() internal view returns (uint256)` | Read future component only |
| `_setFuturePrizePool` | `(uint256 val) internal` | Write future component only |

Packing layout (both packed slots use identical encoding):
```solidity
// Write: prizePoolsPacked = uint256(future) << 128 | uint256(next);
// Read:  next = uint128(packed);  future = uint128(packed >> 128);
```

---

## 2. Pool Lifecycle Diagram

```
                    PURCHASE PHASE                          JACKPOT PHASE
    =====================================       ====================================

                                                  _consolidatePrizePools()
    Purchases -----> nextPrizePool -----------[next -> current]----------> currentPrizePool
        |                 |    ^                                               |
        |                 |    |  _drawDownFuturePrizePool()                   |  payDailyJackpot()
        |                 |    |  [future -> next, 15%]                        |  [days 1-4: 6-14%]
        |                 |    |                                               |  [day 5: 100%]
        +----------> futurePrizePool ---[x00 / rare dump]---> currentPrizePool |
                          ^                                                    v
                          |  _applyTimeBasedFutureTake()              claimableWinnings[player]
                          |  [next -> future skim]
                          |
                    nextPrizePool

    FREEZE LAYER (applies to prizePoolsPacked only):
    ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    During RNG/jackpot: purchases write to prizePoolPendingPacked
    At unfreeze: pending merges into prizePoolsPacked atomically
```

**Flow summary:**
1. Purchases deposit ETH into nextPrizePool and futurePrizePool (split varies by purchase type)
2. When nextPrizePool reaches the level target, `lastPurchaseDay` triggers
3. Time-based skim moves portion of next -> future (pre-consolidation)
4. Consolidation moves next -> current (and optionally future -> current)
5. 5-day jackpot pays current -> claimableWinnings
6. At new level start, drawdown moves 15% of future -> next (except x00 levels)

---

## 3. Transition Triggers

### 3a. future -> next (drawdown at new level start)

**Function:** `_drawDownFuturePrizePool(lvl)` in DegenerusGameAdvanceModule (line 948)
**Called when:** Purchase phase -> jackpot phase transition completes (AdvanceModule:302). The actual causal chain is: `lastPurchaseDay` triggers -> level pre-incremented at RNG request time (`_finalizeRngRequest`, AdvanceModule:1179) -> next `advanceGame()` call processes consolidation -> enters jackpot phase -> `_drawDownFuturePrizePool(lvl)` runs after `levelStartTime` is set (AdvanceModule:301-302). Note: drawdown fires at the START of the jackpot phase (transition into jackpot), not at the end when `_endPhase()` runs.
**Location in flow:** `advanceGame()` line 302: `_drawDownFuturePrizePool(lvl)`

```solidity
function _drawDownFuturePrizePool(uint24 lvl) private {
    uint256 reserved;
    if ((lvl % 100) == 0) {
        reserved = 0;  // x00 levels: NO drawdown (future already drained by consolidation)
    } else {
        reserved = (_getFuturePrizePool() * 15) / 100;  // 15% of future -> next
    }
    if (reserved != 0) {
        _setFuturePrizePool(_getFuturePrizePool() - reserved);
        _setNextPrizePool(_getNextPrizePool() + reserved);
    }
}
```

**Key details:**
- Normal levels: 15% of futurePrizePool moves to nextPrizePool
- x00 levels (100, 200, ...): 0% drawdown -- future pool was already partially consumed during consolidation
- Seeds the next level's purchase phase with ETH

### 3b. next -> future (time-based skim at level completion)

**Function:** `_applyTimeBasedFutureTake(reachedAt, lvl, rngWord)` in DegenerusGameAdvanceModule (line 876)
**Called when:** `lastPurchaseDay` becomes true, before consolidation (line 282)
**Purpose:** Skim portion of nextPrizePool into futurePrizePool to ensure long-term sustainability

**BPS calculation** via `_nextToFutureBps(elapsed, lvl)` (line 846):

| Elapsed (since levelStartTime + 11 days) | Base BPS | Formula |
|------------------------------------------|----------|---------|
| <= 1 day | 3000 + lvlBonus | `NEXT_TO_FUTURE_BPS_FAST + lvlBonus` |
| 1-14 days | (3000 + lvlBonus) -> 1300 (linear decay) | `(3000 + lvlBonus) - ((3000 + lvlBonus - 1300) * elapsedAfterDay) / 13 days` |
| 14-28 days | 1300 -> (3000 + lvlBonus) (ramp up) | `1300 + ((3000 + lvlBonus - 1300) * elapsedAfterMin) / 14 days` |
| > 28 days | 3000 + lvlBonus + weekly step | `3000 + lvlBonus + weeks * 100` |

Where `lvlBonus = (lvl % 100) / 10 * 100` (e.g., level 45 -> +400 BPS)

**Constants:**
- `NEXT_TO_FUTURE_BPS_FAST` = 3000 (30%)
- `NEXT_TO_FUTURE_BPS_MIN` = 1300 (13%)
- `NEXT_TO_FUTURE_BPS_WEEK_STEP` = 100 (+1% per week after day 28)
- `NEXT_TO_FUTURE_BPS_X9_BONUS` = 200 (+2% on x9 levels: 9, 19, 29, ...)
- Cap: 10000 (100% max)

**Adjustments applied after base BPS:**

1. **x9 bonus:** `if (lvl % 10 == 9) bps += 200` (line 885)
2. **Ratio adjustment** (+-200 BPS): Compares `futurePool / nextPool` ratio to 2:1 baseline
   - Below 2:1: `bps += 200 - ratioPct` (skim more to build future)
   - Above 2:1: `bps -= min(penalty, 200)` (skim less, future is healthy)
3. **Growth adjustment** (+-200 BPS): Compares nextPool to `levelPrizePool[lvl-1]`
   - Pool shrank: `bps += 200`
   - Grew < 10%: `bps += 200 - (excessBps / 5)`
   - Grew 10-20%: partial penalty
   - Grew >= 20%: `bps -= 200`
4. **Random variance:** RNG-based perturbation (additional entropy)

**Final operation:**
```solidity
uint256 take = (nextPoolBefore * bps) / 10_000;
// ... variance applied to take ...
uint256 insuranceSkim = (nextPoolBefore * 100) / 10_000; // 1% -> yieldAccumulator
if (take + insuranceSkim > nextPoolBefore) take = nextPoolBefore - insuranceSkim;
_setNextPrizePool(nextPoolBefore - take - insuranceSkim);
_setFuturePrizePool(futurePoolBefore + take);
yieldAccumulator += insuranceSkim;
```

**Insurance skim:** 1% of nextPool (`INSURANCE_SKIM_BPS = 100`) is routed to `yieldAccumulator` at every level transition, giving the terminal insurance fund a second funding source beyond stETH yield surplus. The skim has priority over the future-take if both would exceed nextPool.

### 3c. next -> current (consolidation at jackpot phase start)

**Function:** `consolidatePrizePools(lvl, rngWord)` in DegenerusGameJackpotModule (line 901)
**Called via:** `_consolidatePrizePools()` delegatecall in AdvanceModule (line 504)
**Trigger:** `lastPurchaseDay` was set, time-based skim completed, entering jackpot phase

```solidity
// Step 0 (x00 only): Dump 50% of yieldAccumulator into futurePool BEFORE keep-roll
// JackpotModule:902-908
if ((lvl % 100) == 0) {
    uint256 acc = yieldAccumulator;
    uint256 half = acc >> 1;
    _setFuturePrizePool(_getFuturePrizePool() + half);
    yieldAccumulator = acc - half; // rounds in favor of retention
}

// Step 1: Move ALL of next into current
currentPrizePool += _getNextPrizePool();
_setNextPrizePool(0);

// Step 2a: x00 levels -- variable portion of future moves to current
if ((lvl % 100) == 0) {
    uint256 keepBps = _futureKeepBps(rngWord);  // 5 dice, 0-3 each -> 0-100% keep
    uint256 fp = _getFuturePrizePool();
    if (keepBps < 10_000 && fp != 0) {
        uint256 keepWei = (fp * keepBps) / 10_000;
        uint256 moveWei = fp - keepWei;
        _setFuturePrizePool(keepWei);
        currentPrizePool += moveWei;
    }
}

// Step 2b: Normal levels -- rare random dump (1 in 1e15 chance)
else if (_shouldFutureDump(rngWord)) {
    uint256 fp = _getFuturePrizePool();
    uint256 moveWei = (fp * 9000) / 10_000;  // 90% of future -> current
    _setFuturePrizePool(fp - moveWei);
    currentPrizePool += moveWei;
}
```

**x00 level `_futureKeepBps` mechanic** (line 1315):
- Rolls 5 pseudo-random dice, each 0-3 (max total = 15)
- `keepBps = (total * 10_000) / 15`
- Range: 0% keep (all future to current) to 100% keep (no transfer)
- Average: ~50% of future moves to current on x00 levels

**Rare dump `_shouldFutureDump`** (line 1333):
- `FUTURE_DUMP_ODDS` = 1,000,000,000,000,000 (1e15)
- Probability: 1 in 1 quadrillion per level transition
- Effect: 90% of futurePrizePool dumps into currentPrizePool

### 3d. current -> claimable (daily jackpot payouts)

**Function:** `payDailyJackpot(isDaily, lvl, randWord)` in DegenerusGameJackpotModule (line 332)
**Called from:** `advanceGame()` in AdvanceModule during jackpot phase
**Duration:** 5 logical days (3 physical days if compressed)

**Daily budget calculation:**
```solidity
uint16 dailyBps = _dailyCurrentPoolBps(counter, randWord);
uint256 budget = (currentPrizePool * dailyBps) / 10_000;
```

**`_dailyCurrentPoolBps` logic** (line 2723):

| Counter (jackpotCounter) | BPS Range | Behavior |
|--------------------------|-----------|----------|
| 0-3 (days 1-4) | 600-1400 (6%-14%) | Random via `DAILY_CURRENT_BPS_MIN + (seed % range)` |
| 4 (day 5, final) | 10000 (100%) | Returns `10_000` when `counter >= JACKPOT_LEVEL_CAP - 1` |

Where `JACKPOT_LEVEL_CAP` = 5, `DAILY_CURRENT_BPS_MIN` = 600, `DAILY_CURRENT_BPS_MAX` = 1400.

**Compressed/turbo jackpot:** See Section 6b for the three-value `compressedJackpotFlag` system. When `compressedJackpotFlag = 1` (compressed), counter advances by 2 per physical day and `dailyBps *= 2`. When `compressedJackpotFlag = 2` (turbo), all 5 logical days fire in 1 physical day.

**Budget allocation per day:**
- 80% of budget -> ETH jackpot for trait-matched ticket holders
- 20% of budget -> lootbox ticket budget (converted to ticket units, backed by moving ETH from current to next pool)

**Zero-fallback:** The 20% lootbox portion passes through `_validateTicketBudget()` (JackpotModule:1086), which returns 0 if no trait tickets exist at the current level for the winning traits. When the lootbox budget is zeroed, the full 100% of the daily budget goes to the ETH jackpot instead.

**Winners:** ETH credited to `claimableWinnings[player]`, aggregate tracked in `claimablePool`.

---

## 4. Per-Purchase-Type Pool Splits

| Purchase Type | Condition | Next BPS | Future BPS | Vault BPS | Source Constant | Source File |
|---------------|-----------|----------|------------|-----------|-----------------|-------------|
| Ticket (ETH) | Always | 9000 | 1000 | 0 | `PURCHASE_TO_FUTURE_BPS = 1000` | DegenerusGame.sol:198 |
| Ticket (BURNIE) | Always | -- | -- | -- | N/A (no ETH enters pools) | MintModule |
| Lootbox (ETH) | Post-presale | 1000 | 9000 | 0 | `LOOTBOX_SPLIT_FUTURE_BPS = 9000` / `LOOTBOX_SPLIT_NEXT_BPS = 1000` | MintModule:105-106 |
| Lootbox (ETH) | Presale | 4000 | 4000 | 2000 | `LOOTBOX_PRESALE_SPLIT_FUTURE_BPS = 4000` / `_NEXT_BPS = 4000` / `_VAULT_BPS = 2000` | MintModule:109-111 |
| Lootbox (ETH) | Distress | 10000 | 0 | 0 | Hardcoded in distress branch | MintModule |
| Lootbox (BURNIE) | Always | -- | -- | -- | N/A (no ETH enters pools) | MintModule |
| Whale Bundle | Level 0 | 3000 | 7000 | 0 | Hardcoded: `nextShare = (totalPrice * 3000) / 10_000` | WhaleModule |
| Whale Bundle | Level > 0 | 500 | 9500 | 0 | Hardcoded: `nextShare = (totalPrice * 500) / 10_000` | WhaleModule |
| Lazy Pass | Always | 9000 | 1000 | 0 | `LAZY_PASS_TO_FUTURE_BPS = 1000` | WhaleModule:124 |
| Deity Pass | Level 0 | 3000 | 7000 | 0 | Same as whale bundle level 0 | WhaleModule |
| Deity Pass | Level > 0 | 500 | 9500 | 0 | Same as whale bundle level > 0 | WhaleModule |
| Degenerette (ETH) | Always | 0 | 10000 | 0 | Direct write: `future + uint128(totalBet)` | DegeneretteModule |

**Notes:**
- BURNIE purchases (ticket and lootbox) burn tokens. Zero ETH enters any pool.
- Presale vault share is a real ETH transfer: `payable(ContractAddresses.VAULT).call{value: vaultShare}("")`
- Whale/deity/lazy pass lootbox components are virtual balance awards -- the full purchase price goes to pools, lootbox is tracked separately in `lootboxEth[index][player]`
- Distress mode overrides lootbox splits to 100% next (helps meet purchase target)

---

## 5. Freeze/Unfreeze Mechanics

### 5a. Freeze Activation

**Function:** `_swapAndFreeze(purchaseLevel)` in DegenerusGameStorage (line 742)
**Trigger:** `advanceGame()` requests daily RNG (day boundary crossed)

```solidity
function _swapAndFreeze(uint24 purchaseLevel) internal {
    _swapTicketSlot(purchaseLevel);    // Swap double-buffer ticket queue
    if (!prizePoolFrozen) {
        prizePoolFrozen = true;
        prizePoolPendingPacked = 0;     // Zero pending accumulators (fresh freeze)
    }
    // If ALREADY frozen (jackpot phase multi-day): accumulators keep growing
}
```

**Key behavior:** First freeze zeros pending. Subsequent calls during same jackpot phase (multi-day) do NOT zero pending -- accumulators continue growing.

### 5b. Purchase Behavior During Freeze

All purchase functions check `prizePoolFrozen` before writing:

```solidity
if (prizePoolFrozen) {
    (uint128 pNext, uint128 pFuture) = _getPendingPools();
    _setPendingPools(pNext + uint128(nextShare), pFuture + uint128(futureShare));
} else {
    (uint128 next, uint128 future) = _getPrizePools();
    _setPrizePools(next + uint128(nextShare), future + uint128(futureShare));
}
```

During freeze, all ETH deposits accumulate in `prizePoolPendingPacked` instead of `prizePoolsPacked`. This prevents pool state mutation while RNG/jackpot logic reads the live pools.

### 5c. Unfreeze Triggers

**Function:** `_unfreezePool()` in DegenerusGameStorage (line 752)

```solidity
function _unfreezePool() internal {
    if (!prizePoolFrozen) return;
    (uint128 pNext, uint128 pFuture) = _getPendingPools();
    (uint128 next, uint128 future) = _getPrizePools();
    _setPrizePools(next + pNext, future + pFuture);  // Merge pending into live
    prizePoolPendingPacked = 0;
    prizePoolFrozen = false;
}
```

**Three unfreeze scenarios:**

| Scenario | Where Called | Context |
|----------|-------------|---------|
| Daily RNG resolves (purchase phase, non-jackpot) | `advanceGame()` after `_unlockRng(day)` | Single-day freeze for RNG processing |
| After jackpot phase ends (day 5 complete) | `advanceGame()` at `_endPhase()` -> `_unfreezePool()` (lines 332-333) | Pool frozen for entire 5-day jackpot |
| Phase transition completes (jackpot -> purchase) | In transition path | Restores normal pool operations |

### 5d. During 5-Day Jackpot Phase

- Pool stays frozen for the **entire** jackpot phase (all 5 logical days / 3 physical days if compressed)
- `_swapAndFreeze()` is called each jackpot day but the `if (!prizePoolFrozen)` guard prevents re-zeroing pending
- Pending accumulators grow continuously across all days from ongoing purchases
- Unfreeze happens only when jackpot phase ends (`jackpotCounter >= JACKPOT_LEVEL_CAP`)

### 5e. Critical Detail: Freeze Scope

**Freeze applies to `prizePoolsPacked` (next + future) ONLY.**

`currentPrizePool` is a separate full-width uint256 that is **NOT frozen**. It is freely read and decremented by `payDailyJackpot()` during jackpot phase, while the packed pools remain frozen for accumulation isolation.

---

## 6. Purchase Target and Level Advancement

### 6a. Ratchet System

The purchase target for advancing from level N to level N+1 is `levelPrizePool[N]`:

| Level | Target Source | Value |
|-------|-------------|-------|
| 0 -> 1 | Constructor | `BOOTSTRAP_PRIZE_POOL` = 50 ether |
| N -> N+1 (normal) | Snapshot at level N transition | `levelPrizePool[N]` = `_getNextPrizePool()` at transition (AdvanceModule:281) |
| x00 -> x01 (after century level) | `_endPhase()` | `levelPrizePool[x00]` = `_getFuturePrizePool() / 3` (AdvanceModule:442) |

**Ratchet property:** Each level's target is the pool size achieved at the previous level transition. If the game grows, targets increase. If levels are reached quickly (less ETH accumulated), targets decrease. The x00 override ties targets to the future pool, creating a different growth dynamic at century boundaries.

### 6b. Target Check

In `advanceGame()` during purchase phase (AdvanceModule:253):

```solidity
if (_getNextPrizePool() >= levelPrizePool[purchaseLevel - 1]) {
    lastPurchaseDay = true;
}
```

When `lastPurchaseDay` becomes true:

1. **Compressed jackpot flag** check (AdvanceModule:131-134, 255-257):
   ```solidity
   // Turbo: target met on day 0 or 1 (checked at top of advanceGame)
   compressedJackpotFlag = 2;   // 5 logical days in 1 physical day

   // Compressed: target met on day 2 (checked in purchase phase branch)
   compressedJackpotFlag = 1;   // 5 logical days in 3 physical days
   ```
   Three-value system: `0` = normal (5 physical days), `1` = compressed (5 logical days in 3 physical days, counter advances by 2), `2` = turbo (all 5 logical days in 1 physical day, counter jumps to `JACKPOT_LEVEL_CAP`). Reset to `0` at `_endPhase()` (AdvanceModule:445).

2. **Level prize pool snapshot** (AdvanceModule:281):
   ```solidity
   levelPrizePool[purchaseLevel] = _getNextPrizePool();
   ```

3. **Time-based future take** runs (Section 3b above)
4. **Consolidation** runs (Section 3c above)
5. Jackpot phase begins

### 6c. Time-Based Future Take (Pre-Consolidation)

When `lastPurchaseDay` triggers, `_applyTimeBasedFutureTake()` runs before `_consolidatePrizePools()`:

**Purpose:** Skim portion of nextPrizePool into futurePrizePool before consolidation. This ensures the future pool stays funded even when levels advance quickly.

**Execution order:**
```
lastPurchaseDay = true
  -> levelPrizePool[purchaseLevel] = _getNextPrizePool()  // snapshot
  -> _applyTimeBasedFutureTake(ts, purchaseLevel, rngWord) // skim next -> future
  -> _consolidatePrizePools(purchaseLevel, rngWord)         // next -> current
```

**Net effect:** The nextPrizePool snapshot (target for next level) is taken BEFORE the skim. The skim reduces nextPrizePool, so the amount consolidated into currentPrizePool is `nextPrizePool - skimAmount`.

---

## 7. Distress Mode Pool Behavior

### Condition

**Function:** `_isDistressMode()` in DegenerusGameStorage (line 169)

```solidity
function _isDistressMode() internal view returns (bool) {
    if (gameOver) return false;
    uint48 lst = levelStartTime;
    uint48 ts = uint48(block.timestamp);
    if (level == 0) {
        return uint256(ts) + uint256(DISTRESS_MODE_HOURS) * 1 hours >
            uint256(lst) + uint256(_DEPLOY_IDLE_TIMEOUT_DAYS) * 1 days;
        // Within 6 hours of 365-day deploy timeout
    }
    return uint256(ts) + uint256(DISTRESS_MODE_HOURS) * 1 hours > uint256(lst) + 120 days;
    // Within 6 hours of 120-day liveness guard
}
```

**Constants:**
- `DISTRESS_MODE_HOURS` = 6
- `_DEPLOY_IDLE_TIMEOUT_DAYS` = 365 (level 0 only)
- Liveness guard: 120 days (level > 0)

### Effect on Pool Routing

During distress mode, lootbox ETH splits override to:
- nextBps = 10000 (100% to next pool)
- futureBps = 0
- vaultBps = 0

**Rationale:** Routes all lootbox ETH to nextPrizePool to help meet the purchase target and avoid game-over from liveness guard expiry.

### Activation Windows

| Level | Guard Duration | Distress Activates At |
|-------|---------------|----------------------|
| 0 | 365 days from deploy | 364 days, 18 hours after `levelStartTime` |
| > 0 | 120 days from level start | 119 days, 18 hours after `levelStartTime` |

---

## Appendix: Yield Surplus Distribution

At consolidation time, `_distributeYieldSurplus(rngWord)` (JackpotModule:945) checks for stETH appreciation:

```solidity
uint256 totalBal = address(this).balance + steth.balanceOf(address(this));
uint256 obligations = currentPrizePool + _getNextPrizePool() + claimablePool + _getFuturePrizePool() + yieldAccumulator;
if (totalBal <= obligations) return;
uint256 yieldPool = totalBal - obligations;
// 23% DGNRS claimable, 23% vault claimable, 46% yield accumulator, ~8% buffer
```

This is an additional inflow to the yield accumulator (and indirectly to futurePool via x00 dumps) from stETH yield, separate from purchase-driven pool splits.
