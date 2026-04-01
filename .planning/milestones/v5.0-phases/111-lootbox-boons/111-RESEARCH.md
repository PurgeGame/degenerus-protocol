# Phase 111: Lootbox + Boons - Research

**Compiled:** 2026-03-25
**Contracts:**
- `contracts/modules/DegenerusGameLootboxModule.sol` (1,864 lines, 35 functions)
- `contracts/modules/DegenerusGameBoonModule.sol` (327 lines, 6 functions)
- **Total: ~2,191 lines, 41 functions**

---

## 1. Complete Function Inventory

### 1.1 DegenerusGameLootboxModule.sol

#### Category B: External State-Changing (4 functions)

| # | Function | Lines | Access | Risk Tier | Subsystem |
|---|----------|-------|--------|-----------|-----------|
| B1 | `openLootBox(address, uint48)` | L547-618 | external (delegatecall only) | Tier 1 | LOOTBOX-ETH |
| B2 | `openBurnieLootBox(address, uint48)` | L627-687 | external (delegatecall only) | Tier 1 | LOOTBOX-BURNIE |
| B3 | `resolveLootboxDirect(address, uint256, uint256)` | L694-720 | external (delegatecall only) | Tier 2 | LOOTBOX-DIRECT |
| B4 | `resolveRedemptionLootbox(address, uint256, uint256, uint16)` | L729-755 | external (delegatecall only) | Tier 2 | LOOTBOX-REDEMPTION |
| B5 | `issueDeityBoon(address, address, uint8)` | L796-822 | external (delegatecall only) | Tier 2 | DEITY-BOON |

**Notes:**
- B1 is Tier 1: complex multi-path resolution with EV multiplier, distress bonus, presale logic, grace period, boon rolling, nested delegatecall
- B2 is Tier 1: BURNIE-to-ETH conversion, liveness cutoff, complex resolution chain
- B3/B4 are Tier 2: simplified resolution paths but still chain into _resolveLootboxCommon
- B5 is Tier 2: deity boon issuance with access control, deterministic slot generation, one-per-recipient-per-day constraint

#### Category C: Internal/Private State-Changing (14 functions)

| # | Function | Lines | Called By | Key Storage Writes | Flags |
|---|----------|-------|-----------|-------------------|-------|
| C1 | `_resolveLootboxCommon(...)` | L872-1026 | B1, B2, B3, B4 | lootboxEvBenefitUsedByLevel, futureTicketQueue, boonPacked (via delegatecall) | [MULTI-PARENT] |
| C2 | `_rollLootboxBoons(...)` | L1038-1102 | C1 | boonPacked (via delegatecall + _applyBoon) | |
| C3 | `_resolveLootboxRoll(...)` | L1617-1703 | C1 | dgnrsClaimable (via _creditDgnrsReward) | |
| C4 | `_applyBoon(...)` | L1396-1601 | C2, B5 | boonPacked[player].slot0, boonPacked[player].slot1, whale pass tickets (via _activateWhalePass) | [MULTI-PARENT] |
| C5 | `_activateWhalePass(address)` | L1116-1136 | C4 | futureTicketQueue, mintPacked_ (via _applyWhalePassStats) | |
| C6 | `_applyEvMultiplierWithCap(...)` | L505-539 | B1, B3, B4 | lootboxEvBenefitUsedByLevel[player][lvl] | [MULTI-PARENT] |
| C7 | `_rollTargetLevel(uint24, uint256)` | L834-852 | B1, B2, B3, B4 | none (pure) | reclassify to D |
| C8 | `_lootboxTicketCount(...)` | L1713-1756 | C3 | none (pure) | reclassify to D |
| C9 | `_lootboxDgnrsReward(uint256, uint256)` | L1763-1787 | C3 | none (view) | reclassify to D |
| C10 | `_creditDgnrsReward(address, uint256)` | L1793-1799 | C3 | external call to dgnrs.transferFromPool | |
| C11 | `_boonPoolStats(...)` | L1139-1266 | C2 | none (view) | reclassify to D |
| C12 | `_boonFromRoll(...)` | L1269-1335 | C2, B5 (via _deityBoonForSlot) | none (pure) | reclassify to D |
| C13 | `_activeBoonCategory(address)` | L1339-1363 | C2 | none (view) | reclassify to D |
| C14 | `_boonCategory(uint8)` | L1366-1390 | C2 | none (pure) | reclassify to D |

**Reclassification notes:** C7, C8, C9, C11, C12, C13, C14 are pure/view functions. They should be reclassified to Category D during the Taskmaster phase. Listed here as C because they are critical links in state-changing call chains.

#### Category D: View/Pure Functions (7 functions + 7 reclassified = 14 total)

| # | Function | Lines | Reads/Computes | Security Note |
|---|----------|-------|---------------|---------------|
| D1 | `deityBoonSlots(address)` | L768-782 | deityBoonDay, deityBoonUsedMask, decWindowOpen, deityPassOwners | View -- no state changes |
| D2 | `_lootboxEvMultiplierBps(address)` | L465-468 | playerActivityScore (external call) | View -- EV calculation |
| D3 | `_lootboxEvMultiplierFromScore(uint256)` | L474-495 | none (pure) | Linear interpolation |
| D4 | `_burnieToEthValue(uint256, uint256)` | L1105-1111 | none (pure) | Conversion helper |
| D5 | `_lazyPassPriceForLevel(uint24)` | L1806-1818 | PriceLookupLib (pure) | Sum of 10 level prices |
| D6 | `_isDecimatorWindow()` | L1822-1824 | decWindowOpen (view) | Simple storage read |
| D7 | `_deityDailySeed(uint48)` | L1830-1839 | rngWordByDay, rngWordCurrent (view) | Fallback to keccak if no VRF word |
| D8 | `_deityBoonForSlot(...)` | L1848-1862 | _deityDailySeed, weights (view) | Deterministic boon generation |
| D9 | `_rollTargetLevel(uint24, uint256)` | L834-852 | none (pure) | 90/10 near/far split, EntropyLib |
| D10 | `_lootboxTicketCount(...)` | L1713-1756 | none (pure) | 5-tier variance, modulo bias check |
| D11 | `_lootboxDgnrsReward(uint256, uint256)` | L1763-1787 | dgnrs.poolBalance (view) | 4-tier probability |
| D12 | `_boonPoolStats(...)` | L1139-1266 | price, decWindowOpen, deityPassOwners (view) | Weighted avg value |
| D13 | `_boonFromRoll(...)` | L1269-1335 | none (pure) | Weighted selection, cursor walk |
| D14 | `_activeBoonCategory(address)` | L1339-1363 | boonPacked (view) | Packed bit extraction |
| D15 | `_boonCategory(uint8)` | L1366-1390 | none (pure) | Type-to-category mapping |

### 1.2 DegenerusGameBoonModule.sol

#### Category B: External State-Changing (5 functions)

| # | Function | Lines | Access | Risk Tier | Subsystem |
|---|----------|-------|--------|-----------|-----------|
| B6 | `consumeCoinflipBoon(address)` | L41-61 | external (delegatecall only) | Tier 3 | BOON-CONSUME |
| B7 | `consumePurchaseBoost(address)` | L66-86 | external (delegatecall only) | Tier 3 | BOON-CONSUME |
| B8 | `consumeDecimatorBoost(address)` | L91-106 | external (delegatecall only) | Tier 3 | BOON-CONSUME |
| B9 | `checkAndClearExpiredBoon(address)` | L119-275 | external (delegatecall only) | Tier 1 | BOON-MAINTAIN |
| B10 | `consumeActivityBoon(address)` | L280-326 | external (delegatecall only) | Tier 2 | BOON-ACTIVITY |

**Notes:**
- B6/B7/B8 are Tier 3: simple consume-and-clear pattern with expiry check
- B9 is Tier 1: 156 lines, reads/writes both packed slots, 7 boon categories with deity+time expiry, complex conditional logic
- B10 is Tier 2: writes to mintPacked_ (levelCount) + external call to quests.awardQuestStreakBonus

### Summary Counts

| Category | LootboxModule | BoonModule | Total |
|----------|--------------|------------|-------|
| B (External State-Changing) | 5 | 5 | 10 |
| C (Internal State-Changing) | 7* | 0 | 7 |
| D (View/Pure) | 15 | 0 | 15 |
| **Total** | **27** | **5** | **32** |

*After reclassification of 7 view/pure functions from C to D.

---

## 2. Risk Tiers

### Tier 1 (Critical -- Full BAF-pattern scrutiny required)
- **B1: openLootBox** -- Most complex entry point. 72 lines of setup + chains into _resolveLootboxCommon (155 lines). EV multiplier, grace period, distress bonus, presale, nested delegatecall to BoonModule. Multiple storage mappings cleared. RNG-dependent multi-path resolution.
- **B2: openBurnieLootBox** -- BURNIE-to-ETH conversion at 80% rate. Liveness cutoff logic shifts tickets to future. Chains into same _resolveLootboxCommon.
- **B9: checkAndClearExpiredBoon** -- 156 lines of packed bit manipulation across 2 slots, 7 boon categories. Called via nested delegatecall from LootboxModule during resolution. Any bit-packing error here silently corrupts all boon state.
- **C1: _resolveLootboxCommon** -- Central resolution hub. Called by all 4 lootbox entry points. Manages boon budget split, two-roll resolution, boon rolling, ticket queuing, BURNIE minting, distress bonus. The nested delegatecall to BoonModule happens here.

### Tier 2 (Significant -- Important state changes, cross-contract calls)
- **B3: resolveLootboxDirect** -- Decimator claim path. No RNG wait but still uses EV multiplier.
- **B4: resolveRedemptionLootbox** -- Redemption path with snapshotted activity score.
- **B5: issueDeityBoon** -- Deity boon issuance. Access control, one-per-recipient-per-day, deterministic slot generation.
- **B10: consumeActivityBoon** -- Writes to mintPacked_ (levelCount) and calls external quests contract.
- **C4: _applyBoon** -- 206 lines, 12 boon type handlers. Writes boonPacked slots. Both lootbox (upgrade) and deity (overwrite) semantics. Called from C2 and B5.
- **C6: _applyEvMultiplierWithCap** -- Tracking storage for EV cap. Called by B1, B3, B4.

### Tier 3 (Standard -- Simpler patterns, lower risk)
- **B6: consumeCoinflipBoon** -- Read-check-clear pattern. 21 lines.
- **B7: consumePurchaseBoost** -- Read-check-clear pattern. 21 lines.
- **B8: consumeDecimatorBoost** -- Read-check-clear pattern. 16 lines.
- **C5: _activateWhalePass** -- Whale pass ticket queue. Straightforward loop.
- **C10: _creditDgnrsReward** -- Single external call wrapper.

---

## 3. Storage Write Map

### LootboxModule Storage Writes

| Storage Variable | Written By | Type |
|-----------------|-----------|------|
| `lootboxEth[index][player]` | B1 (clear to 0) | mapping(uint48 => mapping(address => uint256)) |
| `lootboxEthBase[index][player]` | B1 (clear to 0) | mapping(uint48 => mapping(address => uint256)) |
| `lootboxBaseLevelPacked[index][player]` | B1 (clear to 0) | mapping(uint48 => mapping(address => uint24)) |
| `lootboxEvScorePacked[index][player]` | B1 (clear to 0) | mapping(uint48 => mapping(address => uint16)) |
| `lootboxDistressEth[index][player]` | B1 (clear to 0) | mapping(uint48 => mapping(address => uint256)) |
| `lootboxBurnie[index][player]` | B2 (clear to 0) | mapping(uint48 => mapping(address => uint256)) |
| `lootboxEvBenefitUsedByLevel[player][lvl]` | C6 (increment) | mapping(address => mapping(uint24 => uint256)) |
| `boonPacked[player].slot0` | C4, B6, B7, B8, B9 | BoonPacked struct |
| `boonPacked[player].slot1` | C4, B9, B10 | BoonPacked struct |
| `mintPacked_[player]` | C5 (via _applyWhalePassStats), B10 | mapping(address => uint256) |
| `deityBoonDay[deity]` | B5 | mapping(address => uint48) |
| `deityBoonUsedMask[deity]` | B5 | mapping(address => uint8) |
| `deityBoonRecipientDay[recipient]` | B5 | mapping(address => uint48) |

### External Calls (State Changes in Other Contracts)

| External Call | From | Target | Effect |
|--------------|------|--------|--------|
| `coin.creditFlip(player, amount)` | C1 | BurnieCoin | Mint BURNIE |
| `dgnrs.transferFromPool(Pool.Lootbox, player, amount)` | C10 | StakedDegenerusStonk | Transfer sDGNRS from pool |
| `wwxrp.mintPrize(player, amount)` | C3 | WrappedWrappedXRP | Mint WWXRP prize token |
| `quests.awardQuestStreakBonus(player, bonus, day)` | B10 | DegenerusQuests | Award quest streak bonus |
| `IDegenerusGame(address(this)).playerActivityScore(player)` | D2 | Self (via external call) | View only |
| `_queueTickets(player, lvl, count)` | C5 | Storage (inherited) | Write futureTicketQueue |
| `_queueTicketsScaled(player, lvl, count)` | C1 | Storage (inherited) | Write futureTicketQueue |

---

## 4. RNG Usage Patterns

### Entropy Derivation Chain

```
openLootBox:
  entropy = keccak256(rngWord, player, day, amount)          [L575]
  -> _rollTargetLevel(baseLevel, entropy)                     [L576] uses EntropyLib.entropyStep
  -> _resolveLootboxCommon(..., nextEntropy, ...)             [L604]
    -> _resolveLootboxRoll(..., entropy)                      [L923] uses EntropyLib.entropyStep
      -> roll = nextEntropy % 20                              [L1638] -- 4 outcome paths
      -> _lootboxTicketCount(..., nextEntropy)                [L1643] uses entropyStep, % 10_000
      -> _lootboxDgnrsReward(..., nextEntropy)                [L1657] % 1000
      -> BURNIE variance: nextEntropy % 20                    [L1687]
    -> (second roll if split) same chain
    -> _rollLootboxBoons(..., entropy)                        [L974]
      -> roll = entropy % BOON_PPM_SCALE (1_000_000)          [L1085]
      -> _boonFromRoll((roll * totalWeight) / totalChance)    [L1089]

openBurnieLootBox:
  entropy = keccak256(rngWord, player, day, amountEth)        [L649]
  -> same chain as above

resolveLootboxDirect:
  entropy = keccak256(rngWord, player, day, amount)           [L699]
  -> same chain, but allowBoons=false

resolveRedemptionLootbox:
  entropy = keccak256(rngWord, player, day, amount)           [L734]
  -> same chain, but allowBoons=false

issueDeityBoon:
  -> _deityBoonForSlot(deity, day, slot, ...)                 [L818]
    -> seed = keccak256(_deityDailySeed(day), deity, day, slot) [L1855]
    -> roll = seed % total_weight                              [L1860]
    -> _boonFromRoll(roll, ...)                                [L1861]
```

### Modulo Bias Assessment

| Operation | Modulus | Domain Size (256-bit) | Bias |
|-----------|---------|----------------------|------|
| `% 20` | 20 | 2^256 / 20 | Negligible (~10^-76) |
| `% 100` | 100 | 2^256 / 100 | Negligible |
| `% 1000` | 1000 | 2^256 / 1000 | Negligible |
| `% 10_000` | 10,000 | 2^256 / 10,000 | Negligible |
| `% 1_000_000` | 1,000,000 | 2^256 / 1,000,000 | Negligible |
| `% 5` | 5 | 2^256 / 5 | Negligible |
| `% 46` | 46 | 2^256 / 46 | Negligible |
| `% total_weight` | 1248-1298 | 2^256 / ~1300 | Negligible |

All moduli are negligibly small relative to the 256-bit entropy domain. No actionable modulo bias.

### RNG Commitment Window

For openLootBox/openBurnieLootBox: The RNG word (`lootboxRngWordByIndex[index]`) is set during VRF fulfillment, which occurs after the lootbox entry is recorded. Player inputs (player address, day, amount) are committed at purchase time. The keccak256 derivation prevents the VRF fulfiller from targeting specific outcomes.

For resolveLootboxDirect/resolveRedemptionLootbox: The `rngWord` parameter is passed directly. The caller (DecimatorModule, sDGNRS) is responsible for providing an appropriate RNG word. This is a cross-module trust boundary.

For issueDeityBoon: The deity boon slots are deterministic for a given (deity, day, slot) tuple. The deity can see their slots before deciding to issue. This is intentional -- the randomness prevents deities from choosing WHICH boon types to make available, but they can choose which of their 3 slots to issue and to whom.

---

## 5. Critical Attack Surfaces

### 5.1 Nested Delegatecall State Coherence (PRIORITY)

**Flow:** `_resolveLootboxCommon` (C1) -> `_rollLootboxBoons` (C2) -> delegatecall to `checkAndClearExpiredBoon` (B9) -> then reads `_activeBoonCategory` (D14) -> then calls `_applyBoon` (C4). After boon roll, C1 calls delegatecall to `consumeActivityBoon` (B10).

**Concern:** If any function in LootboxModule caches boonPacked[player] in a local variable before the delegatecall to BoonModule, the BoonModule write would create a stale-cache bug.

**Initial analysis:** _rollLootboxBoons does NOT cache boonPacked directly. It calls checkAndClearExpiredBoon via delegatecall first, then reads _activeBoonCategory (which does a fresh SLOAD), then calls _applyBoon. The sequence appears correct but needs full verification.

### 5.2 EV Multiplier Cap Bypass

**Flow:** `_applyEvMultiplierWithCap` tracks `lootboxEvBenefitUsedByLevel[player][lvl]`. The cap is 10 ETH per account per level.

**Concern:** The cap uses `currentLevel` (current game level), not `targetLevel`. A player could open multiple lootboxes in the same level, each getting the EV boost up to 10 ETH total. But if the EV is below 100% (penalty), the cap also limits the penalty -- which means the tracking is bidirectional.

**Attack surface:** If the player can manipulate which level is "current" at resolution time (e.g., by timing resolution around level transitions), they might get more EV benefit than intended. The cap tracks per-level, so level transitions reset the cap.

### 5.3 Boon Single-Category Constraint

**Flow:** `_rollLootboxBoons` checks `_activeBoonCategory(player)`. If a boon is already active, only the same category can be refreshed/upgraded. If a different category is rolled, the boon is silently discarded.

**Concern:** The category check happens AFTER checkAndClearExpiredBoon. If clearing expired boons changes the active category (e.g., the old boon expires and a different slot was also set), the new roll might target a now-empty category. This is correct behavior but worth verifying.

### 5.4 Deity Boon Access Control

**Flow:** `issueDeityBoon` checks: deity != address(0), recipient != address(0), deity != recipient, slot < 3, deityPassPurchasedCount[deity] > 0, RNG available, recipient hasn't received boon today, slot not already used.

**Concern:** No explicit `msg.sender` check. This function is called via delegatecall from DegenerusGame, so `msg.sender` is the original caller. The function checks `deityPassPurchasedCount[deity]` but does NOT check that `deity == msg.sender` or that msg.sender is authorized to issue on behalf of deity. The Game router presumably passes the correct deity address, but if any external path can call with arbitrary deity address, a non-deity could issue boons.

### 5.5 BURNIE Lootbox Liveness Cutoff

**Flow:** `openBurnieLootBox` checks `elapsed > cutoff` where elapsed = `block.timestamp - levelStartTime` and cutoff = 90 days (or 335 days for level 0). If true, `targetLevel` is bumped to `currentLevel + 2`.

**Concern:** This uses `block.timestamp`, not day-based calculation. The cutoff is relative to `levelStartTime`, which is set at level transition. If the game runs slowly (levels last longer than expected), this cutoff might trigger earlier or later than intended.

### 5.6 Grace Period Level Lock

**Flow:** `openLootBox` calculates `graceLevel = baseLevelPacked == 0 ? currentLevel : baseLevelPacked - 1`. The grace period is 7 days from lootbox day. Within grace period, the base level is from purchase time. After grace period, base level falls to `purchaseLevel` (stored in upper 24 bits of packed lootboxEth).

**Concern:** The `baseLevelPacked - 1` offset suggests 1-indexed storage. If `baseLevelPacked` was set to 0 by mistake, the fallback to `currentLevel` could give a higher base level than intended.

---

## 6. Subsystem Map

```
LOOTBOX RESOLUTION
  openLootBox ---------> _resolveLootboxCommon -> _resolveLootboxRoll (x1 or x2)
  openBurnieLootBox ---> _resolveLootboxCommon    |-> ticket path -> _queueTicketsScaled
  resolveLootboxDirect > _resolveLootboxCommon    |-> DGNRS path -> _creditDgnrsReward -> dgnrs.transferFromPool
  resolveRedemptionLb -> _resolveLootboxCommon    |-> WWXRP path -> wwxrp.mintPrize
                                                   |-> BURNIE path -> coin.creditFlip

BOON SYSTEM (from _resolveLootboxCommon)
  _rollLootboxBoons -> delegatecall checkAndClearExpiredBoon
                    -> _activeBoonCategory (read)
                    -> _boonPoolStats (calc)
                    -> _boonFromRoll (select)
                    -> _applyBoon (write boonPacked)
  then: delegatecall consumeActivityBoon -> mintPacked_ + quests

DEITY BOON SYSTEM
  issueDeityBoon -> _deityBoonForSlot -> _deityDailySeed -> _boonFromRoll
                 -> _applyBoon (write boonPacked, isDeity=true)

BOON CONSUMPTION (called by OTHER modules)
  consumeCoinflipBoon   -> read/clear boonPacked.slot0
  consumePurchaseBoost  -> read/clear boonPacked.slot0
  consumeDecimatorBoost -> read/clear boonPacked.slot0
```

---

## 7. Inherited Functions Used

Functions from DegenerusGameStorage.sol that LootboxModule/BoonModule call:

| Function | Lines in Storage.sol | Used By | Effect |
|----------|---------------------|---------|--------|
| `_simulatedDayIndex()` | L1134-1137 | B1, B2, B3, B4, B5, B6, B7, B8, B9, B10, C2 | Current day calculation |
| `_queueTickets(player, lvl, count)` | L528-554 | C5 | Write futureTicketQueue |
| `_queueTicketsScaled(player, lvl, count)` | L556-580 | C1 | Write futureTicketQueue (scaled) |
| `_applyWhalePassStats(player, level)` | L1067-1130 | C5 | Write mintPacked_ (stats) |
| `_coinflipTierToBps(tier)` | L1519-1525 | B6 | Pure tier-to-BPS conversion |
| `_coinflipBpsToTier(bps)` | L1567-1581 | C4 | Pure BPS-to-tier conversion |
| `_lootboxTierToBps(tier)` | L1527-1533 | C4 | Pure tier-to-BPS conversion |
| `_purchaseTierToBps(tier)` | L1535-1541 | B7 | Pure tier-to-BPS conversion |
| `_purchaseBpsToTier(bps)` | L1583-1589 | C4 | Pure BPS-to-tier conversion |
| `_decimatorTierToBps(tier)` | L1543-1565 | B8 | Pure tier-to-BPS conversion |
| `_decimatorBpsToTier(bps)` | L1591-1597 | C4 | Pure BPS-to-tier conversion |
| `_whaleBpsToTier(bps)` | L1599-1605 | C4 | Pure BPS-to-tier conversion |
| `_lazyPassBpsToTier(bps)` | L1607-1613 | C4 | Pure BPS-to-tier conversion |

---

*Research compiled: 2026-03-25*
*Ready for planning phase.*
