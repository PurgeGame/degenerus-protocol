# Level System Reference

Complete reference for how `level` flows through the Degenerus Protocol. Each section traces the level variable from its storage location through every subsystem that consumes it.

**Contracts referenced:**
- `contracts/storage/DegenerusGameStorage.sol` (storage layout)
- `contracts/modules/DegenerusGameAdvanceModule.sol` (level advancement, phase transitions)
- `contracts/modules/DegenerusGameMintModule.sol` (purchaseLevel, ticket routing, lootbox packing)
- `contracts/libraries/PriceLookupLib.sol` (price derivation)
- `contracts/DegenerusQuests.sol` (quest target calculation)
- `contracts/modules/DegenerusGameJackpotModule.sol` (jackpot ticket routing, carryover)

---

## Section 1: Level Advancement

### Storage

`level` is stored in EVM Slot 0 as a `uint24` occupying bytes 18-21 (bits 144-167).

```
DegenerusGameStorage.sol line 256:
    uint24 public level = 0;
```

Slot 0 also holds `jackpotPhaseFlag` (bool at byte 21), which determines whether the game is in purchase phase (`false`) or jackpot phase (`true`).

```
DegenerusGameStorage.sol line 263:
    bool internal jackpotPhaseFlag;
```

### Trigger

`level` is written exactly once per level cycle, inside `_finalizeRngRequest` in `DegenerusGameAdvanceModule.sol` at line 1374:

```solidity
// Line 1373-1374 (DegenerusGameAdvanceModule.sol):
if (isTicketJackpotDay && !isRetry) {
    level = lvl;
```

The increment happens at VRF request time, not at VRF fulfillment. The variable `lvl` at this point is `purchaseLevel` (which equals `level + 1`), so `level = lvl` performs the increment. The `!isRetry` guard prevents double-increment on VRF retry.

### Who Can Call

`advanceGame()` is `external` with no access modifier -- any address can call it.

```
DegenerusGameAdvanceModule.sol line 136:
    function advanceGame() external {
```

Callers are incentivized by a BURNIE flip credit bounty (~0.01 ETH worth).

### When It Triggers

The level increment is triggered specifically when `isTicketJackpotDay == true`, which is the condition `lastPurchaseDay == true` at the time of RNG request. `lastPurchaseDay` is set to `true` when the next prize pool meets or exceeds the level prize target:

```
DegenerusGameAdvanceModule.sol lines 146-148:
    if (purchaseDays <= 1 && _getNextPrizePool() >= levelPrizePool[lvl]) {
        lastPurchaseDay = true;
```

### State Transitions at Level Change

When `level` increments, the following state changes occur across the level cycle:

1. **Level set** -- `level = lvl` (line 1374, AdvanceModule)
2. **Charity resolved** -- `charityResolve.pickCharity(lvl - 1)` (line 1381, AdvanceModule)
3. **RNG locked** -- `rngLockedFlag = true` (line 1362, AdvanceModule)
4. **VRF request recorded** -- `vrfRequestId`, `rngRequestTime`, `rngWordCurrent` updated (lines 1359-1361, AdvanceModule)
5. **Jackpot phase entered** (after VRF fulfillment): `jackpotPhaseFlag = true` (line 368, AdvanceModule)
6. **Decimator window managed** -- opened/closed based on level modular arithmetic (lines 371-373, 1365-1368, AdvanceModule)
7. **Prize pools consolidated** -- `levelPrizePool[purchaseLevel]` set, pools consolidated (lines 355-358, AdvanceModule)
8. **Level start time** -- `levelStartTime = ts` (line 378, AdvanceModule)
9. **Level quest rolled** -- `quests.rollLevelQuest(questEntropy)` (line 383, AdvanceModule)

When jackpot phase ends (via `_endPhase` at line 510):
- `phaseTransitionActive = true`
- `jackpotCounter = 0`
- `compressedJackpotFlag = 0`
- At milestone levels (x00): `levelPrizePool[lvl] = _getFuturePrizePool() / 3` (line 514)

After phase transition completes (lines 285-292):
- `phaseTransitionActive = false`
- `purchaseStartDay = day`
- `jackpotPhaseFlag = false`
- Endgame flag evaluated: `_evaluateGameOverPossible(lvl, purchaseLevel)` (line 290)

---

## Section 2: Price Derivation

All ticket pricing is computed by a single pure function:

```
PriceLookupLib.sol lines 21-46:
    function priceForLevel(uint24 targetLevel) internal pure returns (uint256)
```

This replaced the former `price` storage variable, which was removed in Phase 160.1. Pricing is now fully deterministic from level alone -- no storage reads required.

### Full Tier Table

| Level Range | Price (ETH) | Category |
|---|---|---|
| 0-4 | 0.01 | Intro tier 1 |
| 5-9 | 0.02 | Intro tier 2 |
| 10-29 | 0.04 | First cycle, early |
| 30-59 | 0.08 | First cycle, mid |
| 60-89 | 0.12 | First cycle, late |
| 90-99 | 0.16 | First cycle, final |
| x00 (100, 200, ...) | 0.24 | Milestone |
| x01-x29 | 0.04 | Cycle early |
| x30-x59 | 0.08 | Cycle mid |
| x60-x89 | 0.12 | Cycle late |
| x90-x99 | 0.16 | Cycle final |

The function uses a short-circuit design: levels 0-99 match explicit comparisons (lines 23-30). Levels 100+ compute `cycleOffset = targetLevel % 100` and branch on the offset (lines 32-45).

**Key properties:**
- Pure function -- no state reads, deterministic, zero gas overhead beyond computation
- 7 distinct price tiers: 0.01, 0.02, 0.04, 0.08, 0.12, 0.16, 0.24 ETH
- Levels 0-9 override the standard x01-x29 tier with intro pricing
- Milestone levels (multiples of 100, starting at 100) use the highest price tier (0.24 ETH)
- The 100-level cycle repeats indefinitely (uint24 supports ~16M levels)

---

## Section 3: purchaseLevel Semantics

### The Ternary

The variable `purchaseLevel` determines which level tickets are priced and routed to. It is computed as:

```
DegenerusGameMintModule.sol line 627:
    uint24 purchaseLevel = cachedJpFlag ? cachedLevel : cachedLevel + 1;
```

| Phase | `jackpotPhaseFlag` | `purchaseLevel` | Meaning |
|---|---|---|---|
| Purchase phase | `false` | `level + 1` | Tickets target the upcoming level |
| Jackpot phase | `true` | `level` | Tickets target the current level |

### Why

During **purchase phase**, the current level's jackpots are complete. Players purchasing tickets are building toward the next level's prize pool, so tickets route to `level + 1` and are priced at `priceForLevel(level + 1)`.

During **jackpot phase**, daily jackpot draws are still running for the current level. Tickets purchased during this phase participate in the remaining draws at the current level, so they route to `level` and are priced at `priceForLevel(level)`.

### Where Computed

The ternary appears in two locations:

1. **_purchaseFor** (player-facing purchase): `DegenerusGameMintModule.sol` line 627
2. **_callTicketPurchase** (internal ticket routing): `DegenerusGameMintModule.sol` line 875

Both compute the same result: `cachedJpFlag ? cachedLevel : cachedLevel + 1`.

### How purchaseLevel Feeds Into Pricing

```
DegenerusGameMintModule.sol line 628:
    uint256 priceWei = PriceLookupLib.priceForLevel(purchaseLevel);
```

This price determines ticket cost via:
```
    ticketCost = (priceWei * ticketQuantity) / (4 * TICKET_SCALE);
```

See **Section 2** for the full price tier table.

### How purchaseLevel Affects Ticket Key Space

Tickets are queued at the `purchaseLevel` key. The routing logic in `_callTicketPurchase` (line 875) also handles a final-day override:

```
DegenerusGameMintModule.sol lines 878-881:
    if (cachedJpFlag && rngLockedFlag) {
        uint8 step = cachedComp == 2 ? JACKPOT_LEVEL_CAP
            : (cachedComp == 1 && cachedCnt > 0 && cachedCnt < JACKPOT_LEVEL_CAP - 1) ? 2 : 1;
        if (cachedCnt + step >= JACKPOT_LEVEL_CAP) targetLevel = cachedLevel + 1;
    }
```

On the final jackpot day (when `jackpotCounter + step >= JACKPOT_LEVEL_CAP`), tickets route to `level + 1` instead of `level`. This prevents stranded tickets -- `_endPhase` breaks before `_unlockRng`, so no future daily draw would process tickets at the current level. See **Section 6** for full jackpot routing details.

### advanceGame purchaseLevel

The `advanceGame` function also computes `purchaseLevel` at line 156, but with a different formula for the mid-VRF case:

```
DegenerusGameAdvanceModule.sol line 156:
    uint24 purchaseLevel = (lastPurchase && rngLockedFlag) ? lvl : lvl + 1;
```

When `lastPurchaseDay` is true and VRF is pending (`rngLockedFlag`), level has already been incremented at VRF request time, so `lvl` (which is `level`) already equals the old `level + 1`. The ternary avoids double-incrementing.

---

## Section 4: Quest Target Calculation

The quest system uses two separate price inputs for target calculation: `mintPrice` for daily quest targets and `levelQuestPrice` for level quest targets.

### The Split in handlePurchase

The call site in `_purchaseFor` passes both prices:

```
DegenerusGameMintModule.sol line 771:
    quests.handlePurchase(buyer, ethMintUnits, burnieMintUnits, lootBoxAmount,
        priceWei,                                      // mintPrice = priceForLevel(purchaseLevel)
        PriceLookupLib.priceForLevel(cachedLevel + 1)  // levelQuestPrice = priceForLevel(level + 1)
    );
```

- `mintPrice` = `priceForLevel(purchaseLevel)` -- varies by phase (see **Section 3**)
- `levelQuestPrice` = `priceForLevel(level + 1)` -- always `level + 1`, regardless of phase

This split exists because daily quests should reflect the current ticket price players are paying (which depends on phase), while level quests use a fixed `level + 1` price as a stable target throughout the entire level.

### Daily Quest Targets

Computed by `_questTargetValue` at `DegenerusQuests.sol` line 1412:

| Quest Type | Constant | Target Formula | Notes |
|---|---|---|---|
| MINT_ETH (slot 0) | `QUEST_DEPOSIT_ETH_TARGET_MULTIPLIER = 1` | `mintPrice * 1` | Capped at 0.5 ETH |
| MINT_ETH (slot 1) | `QUEST_LOOTBOX_TARGET_MULTIPLIER = 2` | `mintPrice * 2` | Capped at 0.5 ETH |
| LOOTBOX (6) | `QUEST_LOOTBOX_TARGET_MULTIPLIER = 2` | `mintPrice * 2` | Capped at 0.5 ETH |
| DEGENERETTE_ETH (7) | `QUEST_LOOTBOX_TARGET_MULTIPLIER = 2` | `mintPrice * 2` | Capped at 0.5 ETH |
| MINT_BURNIE (9) | `QUEST_MINT_TARGET = 1` | `1` (ticket) | Fixed, price-independent |
| FLIP (2) | `QUEST_BURNIE_TARGET = 2000 BURNIE` | `2000 ether` | Fixed, price-independent |
| AFFILIATE (3) | `QUEST_BURNIE_TARGET = 2000 BURNIE` | `2000 ether` | Fixed, price-independent |
| DECIMATOR (5) | `QUEST_BURNIE_TARGET = 2000 BURNIE` | `2000 ether` | Fixed, price-independent |
| DEGENERETTE_BURNIE (8) | `QUEST_BURNIE_TARGET = 2000 BURNIE` | `2000 ether` | Fixed, price-independent |

Constants defined at `DegenerusQuests.sol` lines 193-205:
- `QUEST_MINT_TARGET = 1` (line 193)
- `QUEST_BURNIE_TARGET = 2 * PRICE_COIN_UNIT` = 2000 BURNIE (line 196, `PRICE_COIN_UNIT = 1000 ether` at line 135)
- `QUEST_LOOTBOX_TARGET_MULTIPLIER = 2` (line 199)
- `QUEST_DEPOSIT_ETH_TARGET_MULTIPLIER = 1` (line 202)
- `QUEST_ETH_TARGET_CAP = 0.5 ether` (line 205)

ETH-based targets use `mintPrice` (which is `priceForLevel(purchaseLevel)`). The slot index determines the multiplier: slot 0 uses 1x, slot 1 uses 2x (line 1419-1421). All ETH targets are capped at 0.5 ETH (line 1423). BURNIE-denominated quests have fixed targets independent of level.

### Level Quest Targets (10x Multipliers)

Computed by `_levelQuestTargetValue` at `DegenerusQuests.sol` line 1822:

| Quest Type | Target Formula | Example at L5 (price = 0.02 ETH) |
|---|---|---|
| MINT_BURNIE (9) | `10` (tickets) | 10 tickets |
| MINT_ETH (1) | `mintPrice * 10` | 0.2 ETH |
| LOOTBOX (6) | `mintPrice * 20` | 0.4 ETH |
| DEGENERETTE_ETH (7) | `mintPrice * 20` | 0.4 ETH |
| FLIP (2) | `20,000 BURNIE` | 20,000 BURNIE |
| DECIMATOR (5) | `20,000 BURNIE` | 20,000 BURNIE |
| AFFILIATE (3) | `20,000 BURNIE` | 20,000 BURNIE |
| DEGENERETTE_BURNIE (8) | `20,000 BURNIE` | 20,000 BURNIE |

The `mintPrice` parameter in `_levelQuestTargetValue` receives `levelQuestPrice` (= `priceForLevel(level + 1)`), not the daily `mintPrice`. This value is constant for the entire level regardless of jackpot/purchase phase.

Level quest targets have no ETH cap (unlike daily quests) as noted in the NatSpec at line 1818: "No ETH cap applied (unlike daily quests)."

### How Level Quest Progress Flows

Level quest progress is handled by `_handleLevelQuestProgress` at line 1848. It is called from `_questHandleProgressSlot` (line 1253) with the `levelQuestPrice` parameter:

```
DegenerusQuests.sol line 1253:
    _handleLevelQuestProgress(player, handlerQuestType, levelDelta, levelQuestPrice);
```

The function reads `levelQuestType` and `levelQuestVersion` from storage, short-circuits on type mismatch, then accumulates progress until target is reached. At completion, eligibility is checked (line 1877: `_isLevelQuestEligible(player)`).

---

## Section 5: Lootbox Baseline

### Always level + 1

Lootbox base level is always `level + 1`, regardless of whether the game is in jackpot or purchase phase. This is because lootboxes resolve later (at VRF fulfillment), and must target the upcoming level to produce valid tickets.

### lootboxBaseLevelPacked

On first lootbox deposit within an RNG index, the base level is stored:

```
DegenerusGameMintModule.sol line 697:
    lootboxBaseLevelPacked[lbIndex][buyer] = uint24(cachedLevel + 1);
```

This is a `mapping(uint48 => mapping(address => uint24))` keyed by `lootboxRngIndex` and player address. The value is `cachedLevel + 1` where `cachedLevel = level` (cached at line 626).

### lootboxEth Packing

The lootbox ETH deposit amount is packed with the target level in a single `uint256`:

```
DegenerusGameMintModule.sol line 712:
    lootboxEth[lbIndex][buyer] = (uint256(cachedLevel + 1) << 232) | newAmount;
```

The upper 24 bits (bits 232-255) store `cachedLevel + 1`. The lower 232 bits store the accumulated ETH amount (with boost applied).

### Why level + 1

Both `lootboxBaseLevelPacked` and the packed level in `lootboxEth` use `cachedLevel + 1` unconditionally (not `purchaseLevel`). The `cachedLevel` value is read at line 626 as `level`, so the packed level is always `level + 1`.

During purchase phase, `purchaseLevel` already equals `level + 1`, so this matches. During jackpot phase, `purchaseLevel` equals `level`, but the lootbox still uses `level + 1`. This ensures that when the lootbox resolves (which happens after VRF fulfillment, potentially across a level boundary), the tickets it produces target the correct upcoming level rather than the current level whose jackpot draws have already begun.

---

## Section 6: Jackpot Ticket Routing

### Normal Routing

During purchase phase, tickets route to `purchaseLevel` = `level + 1`. During jackpot phase, tickets route to `purchaseLevel` = `level` (the current level). See **Section 3** for the ternary.

Tickets are queued via `_queueTickets` or `_queueTicketsBatched` in `DegenerusGameStorage.sol` (lines 559-589). The target level determines the key space:

- **Near-future** (targetLevel <= level + 5): Uses double-buffered key space via `_tqWriteKey(targetLevel)` (bit 23 toggles between slots)
- **Far-future** (targetLevel > level + 5): Uses `_tqFarFutureKey(targetLevel)` which sets bit 22 (line 191: `TICKET_FAR_FUTURE_BIT = 1 << 22`)

```
DegenerusGameStorage.sol lines 559-561:
    bool isFarFuture = targetLevel > level + 5;
    if (isFarFuture && rngLockedFlag && !phaseTransitionActive) revert RngLocked();
    uint24 wk = isFarFuture ? _tqFarFutureKey(targetLevel) : _tqWriteKey(targetLevel);
```

### Carryover Tickets

Daily carryover distributes tickets to future-level ticket holders as a reward. The mechanism is in `DegenerusGameJackpotModule.sol` lines 357-407.

**Source range:** Carryover source levels range from `lvl + 1` to `lvl + DAILY_CARRYOVER_MAX_OFFSET` (= `lvl + 4`). The offset constant is defined at line 132:

```
DegenerusGameJackpotModule.sol line 132:
    uint8 private constant DAILY_CARRYOVER_MAX_OFFSET = 4;
```

**Source selection:** `_selectCarryoverSourceOffset` (line 2513) picks a random eligible offset in `[1..highestEligible]` where "eligible" means the level has actual winning-trait ticket holders. `_highestCarryoverSourceOffset` (line 2495) scans downward from offset 4 to find the highest populated level.

**Budget:** 0.5% of the future prize pool:

```
DegenerusGameJackpotModule.sol line 376:
    reserveSlice = _getFuturePrizePool() / 200;
```

This is deducted upfront and flows to `nextPool` as ETH backing for the carryover tickets (line 384).

**Distribution chain:**
1. `_distributeTicketJackpot` (line 958) -- entry point, unpacks traits, computes bucket counts
2. `_distributeTicketsToBuckets` (line 996) -- distributes across all 4 trait buckets
3. `_distributeTicketsToBucket` (line 1035) -- distributes within a single bucket to individual winners

Carryover tickets are queued at the current level (`lvl`), drawn from trait holders at the source level (`carryoverSourceLevel`):

```
DegenerusGameJackpotModule.sol lines 393-396:
    carryoverTicketUnits = _budgetToTicketUnits(
        reserveSlice,
        lvl       // tickets queue at current level
    );
```

**Skipped on early-bird day:** Day 1 of each level runs the early-bird lootbox jackpot instead of carryover (lines 332-334).

### Final-Day Override

On the final jackpot day (`jackpotCounter + step >= JACKPOT_LEVEL_CAP`), ticket purchases route to `level + 1` instead of `level`:

```
DegenerusGameMintModule.sol lines 878-881:
    if (cachedJpFlag && rngLockedFlag) {
        uint8 step = cachedComp == 2 ? JACKPOT_LEVEL_CAP
            : (cachedComp == 1 && cachedCnt > 0 && cachedCnt < JACKPOT_LEVEL_CAP - 1) ? 2 : 1;
        if (cachedCnt + step >= JACKPOT_LEVEL_CAP) targetLevel = cachedLevel + 1;
    }
```

This override prevents stranded tickets: `_endPhase` (line 510) sets `phaseTransitionActive = true` and resets counters, then the phase transition flow in `advanceGame` clears `jackpotPhaseFlag` and exits the jackpot phase. No further daily draws occur at the old level, so any tickets queued there would never be processed.

### Far-Future Key Space (Bit 22)

Tickets targeting levels beyond `level + 5` use a third key space with bit 22 set:

```
DegenerusGameStorage.sol line 191:
    uint24 internal constant TICKET_FAR_FUTURE_BIT = 1 << 22;

DegenerusGameStorage.sol line 714:
    function _tqFarFutureKey(uint24 lvl) internal pure returns (uint24) {
        return lvl | TICKET_FAR_FUTURE_BIT;
    }
```

This key space is disjoint from both double-buffer slots (which use bit 23). Far-future tickets are not double-buffered; they persist until their level becomes current and are drained during phase transition via `_processFutureTicketBatch` in `advanceGame` (lines 278-284 of AdvanceModule).

Far-future tickets are also guarded by `rngLockedFlag` -- permissionless far-future writes revert with `RngLocked()` during the VRF commitment window unless `phaseTransitionActive` is true (line 560 of DegenerusGameStorage.sol).

### Jackpot-Phase BURNIE Distribution

During jackpot phase, the daily BURNIE coin budget is split between near-future and far-future holders:

- 75% to near-future (trait-based draws at current level)
- 25% to far-future ticket holders via `_awardFarFutureCoinJackpot` (line 2328, JackpotModule)

The far-future portion samples up to `FAR_FUTURE_COIN_SAMPLES = 10` levels from `ticketQueue[_tqFarFutureKey(candidate)]` in the range `[lvl+5, lvl+99]` (line 2344-2350).

---

## Cross-Reference Summary

| Subsystem | Input | Source |
|---|---|---|
| Price derivation | `purchaseLevel` | Section 3 defines, Section 2 maps to price |
| Daily quest targets | `mintPrice` = `priceForLevel(purchaseLevel)` | Section 3 for purchaseLevel, Section 2 for price lookup |
| Level quest targets | `levelQuestPrice` = `priceForLevel(level + 1)` | Section 1 for level, Section 2 for price lookup |
| Lootbox baseline | `cachedLevel + 1` (always) | Section 1 for level storage |
| Ticket routing | `purchaseLevel` (with final-day override) | Section 3 for base routing, Section 6 for overrides |
| Carryover source | `lvl + offset` where offset in `[1, 4]` | Section 6 for mechanism, Section 2 for pricing at source level |

### Worked Example: Level 5, Purchase Phase

- `level = 5`, `jackpotPhaseFlag = false`
- `purchaseLevel = 5 + 1 = 6`
- Ticket price: `priceForLevel(6) = 0.02 ETH` (intro tier 2, see Section 2)
- Daily MINT_ETH target (slot 0): `0.02 * 1 = 0.02 ETH`
- Daily MINT_ETH target (slot 1): `0.02 * 2 = 0.04 ETH`
- Level quest MINT_ETH target: `priceForLevel(6) * 10 = 0.2 ETH`
- Lootbox base level: `5 + 1 = 6`
- Tickets queue to level 6 (near-future key space)

### Worked Example: Level 5, Jackpot Phase

- `level = 5`, `jackpotPhaseFlag = true`
- `purchaseLevel = 5` (current level)
- Ticket price: `priceForLevel(5) = 0.02 ETH` (intro tier 2, see Section 2)
- Daily MINT_ETH target (slot 0): `0.02 * 1 = 0.02 ETH`
- Level quest MINT_ETH target: `priceForLevel(6) * 10 = 0.2 ETH` (still level + 1)
- Lootbox base level: `5 + 1 = 6` (always level + 1, see Section 5)
- Tickets queue to level 5 (unless final jackpot day, then level 6)

### Worked Example: Level 100 (Milestone)

- `level = 100`, `jackpotPhaseFlag = false`
- `purchaseLevel = 101`
- Ticket price: `priceForLevel(101) = 0.04 ETH` (cycle early, x01, see Section 2)
- Level quest MINT_ETH target: `priceForLevel(101) * 10 = 0.4 ETH`
- Note: Level 100 itself has milestone pricing (0.24 ETH) but during purchase phase, pricing is for level 101

---

*Generated from contract source as of 2026-04-02. All line references verified against current codebase.*
