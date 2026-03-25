# Unit 9: Lootbox + Boons -- Coverage Checklist

## Contracts Under Audit
- `contracts/modules/DegenerusGameLootboxModule.sol` (1,864 lines, 27 functions)
- `contracts/modules/DegenerusGameBoonModule.sol` (327 lines, 5 functions)
- **Total: 2,191 lines, 32 functions**

## Methodology
- Per D-01: Categories B/C/D only (no Category A -- these are modules, not router)
- Per D-04: Both contracts audited as single unit (BoonModule is EIP-170 split companion to LootboxModule)
- Per D-05: BoonModule consumption functions are Category B (external entry points called by other modules)
- Per D-06: Nested delegatecall pattern is priority investigation area
- Per D-08: Fresh analysis -- do not trust prior audit findings
- Per D-12: Follow ULTIMATE-AUDIT-DESIGN.md format

## Checklist Summary

| Category | Count | Analysis Depth |
|----------|-------|---------------|
| B: External State-Changing | 10 | Full Mad Genius (per D-02) |
| C: Internal Helpers (State-Changing) | 7 | Via caller call tree; standalone for [MULTI-PARENT] (per D-03) |
| D: View/Pure | 15 | Security note review; RNG derivation functions get extra scrutiny |
| **TOTAL** | **32** | |

---

## Category B: External State-Changing Functions

### LootboxModule (B1-B5)

| # | Function | Lines | Access Control | Primary Storage Writes | External Calls | Risk Tier | Subsystem | Analyzed? | Call Tree? | Storage Map? | Cache Check? |
|---|----------|-------|---------------|----------------------|----------------|-----------|-----------|-----------|-----------|-------------|-------------|
| B1 | `openLootBox(address, uint48)` | L547-618 | external (delegatecall from Game) | lootboxEth, lootboxEthBase, lootboxBaseLevelPacked, lootboxEvScorePacked, lootboxDistressEth (all cleared); lootboxEvBenefitUsedByLevel (updated); boonPacked (via nested delegatecall); futureTicketQueue (via _queueTicketsScaled) | coin.creditFlip, dgnrs.transferFromPool, wwxrp.mintPrize, delegatecall BoonModule | Tier 1 | LOOTBOX-ETH | pending | pending | pending | pending |
| B2 | `openBurnieLootBox(address, uint48)` | L627-687 | external (delegatecall from Game) | lootboxBurnie (cleared); boonPacked (via nested delegatecall); futureTicketQueue | coin.creditFlip, dgnrs.transferFromPool, wwxrp.mintPrize, delegatecall BoonModule | Tier 1 | LOOTBOX-BURNIE | pending | pending | pending | pending |
| B3 | `resolveLootboxDirect(address, uint256, uint256)` | L694-720 | external (delegatecall from Game) | lootboxEvBenefitUsedByLevel; futureTicketQueue | coin.creditFlip, dgnrs.transferFromPool, wwxrp.mintPrize | Tier 2 | LOOTBOX-DIRECT | pending | pending | pending | pending |
| B4 | `resolveRedemptionLootbox(address, uint256, uint256, uint16)` | L729-755 | external (delegatecall from Game) | lootboxEvBenefitUsedByLevel; futureTicketQueue | coin.creditFlip, dgnrs.transferFromPool, wwxrp.mintPrize | Tier 2 | LOOTBOX-REDEMPTION | pending | pending | pending | pending |
| B5 | `issueDeityBoon(address, address, uint8)` | L796-822 | external (delegatecall from Game) | deityBoonDay, deityBoonUsedMask, deityBoonRecipientDay, boonPacked (via _applyBoon), potentially futureTicketQueue + mintPacked_ (if whale pass awarded) | none (state-only) | Tier 2 | DEITY-BOON | pending | pending | pending | pending |

### BoonModule (B6-B10)

| # | Function | Lines | Access Control | Primary Storage Writes | External Calls | Risk Tier | Subsystem | Analyzed? | Call Tree? | Storage Map? | Cache Check? |
|---|----------|-------|---------------|----------------------|----------------|-----------|-----------|-----------|-----------|-------------|-------------|
| B6 | `consumeCoinflipBoon(address)` | L41-61 | external (delegatecall from CoinflipModule via Game) | boonPacked[player].slot0 (clear coinflip fields) | none | Tier 3 | BOON-CONSUME | pending | pending | pending | pending |
| B7 | `consumePurchaseBoost(address)` | L66-86 | external (delegatecall from MintModule via Game) | boonPacked[player].slot0 (clear purchase fields) | none | Tier 3 | BOON-CONSUME | pending | pending | pending | pending |
| B8 | `consumeDecimatorBoost(address)` | L91-106 | external (delegatecall from DecimatorModule via Game) | boonPacked[player].slot0 (clear decimator fields) | none | Tier 3 | BOON-CONSUME | pending | pending | pending | pending |
| B9 | `checkAndClearExpiredBoon(address)` | L119-275 | external (nested delegatecall from LootboxModule) | boonPacked[player].slot0, boonPacked[player].slot1 (conditional clear of expired boons across 7 categories) | none | Tier 1 | BOON-MAINTAIN | pending | pending | pending | pending |
| B10 | `consumeActivityBoon(address)` | L280-326 | external (nested delegatecall from LootboxModule) | boonPacked[player].slot1 (clear activity fields), mintPacked_[player] (update levelCount) | quests.awardQuestStreakBonus | Tier 2 | BOON-ACTIVITY | pending | pending | pending | pending |

---

## Category C: Internal/Private State-Changing Helpers

| # | Function | Lines | Contract | Called By | Key Storage Writes | Flags | Analyzed? | Call Tree? | Storage Map? | Cache Check? |
|---|----------|-------|----------|-----------|-------------------|-------|-----------|-----------|-------------|-------------|
| C1 | `_resolveLootboxCommon(...)` | L872-1026 | LootboxModule | B1, B2, B3, B4 | lootboxEvBenefitUsedByLevel (via C6), futureTicketQueue (via _queueTicketsScaled), boonPacked (via delegatecall to B9+B10 and via C4), mintPacked_ (via C5) | [MULTI-PARENT] | pending | pending | pending | pending |
| C2 | `_rollLootboxBoons(...)` | L1038-1102 | LootboxModule | C1 | boonPacked (via delegatecall to B9, then via C4), mintPacked_ (via delegatecall to B10) | | pending | pending | pending | pending |
| C3 | `_resolveLootboxRoll(...)` | L1617-1703 | LootboxModule | C1 | dgnrsClaimable/pool (via C10 -> dgnrs.transferFromPool), WWXRP mint (via wwxrp.mintPrize) | | pending | pending | pending | pending |
| C4 | `_applyBoon(...)` | L1396-1601 | LootboxModule | C2, B5 | boonPacked[player].slot0, boonPacked[player].slot1, futureTicketQueue + mintPacked_ (if whale pass via C5) | [MULTI-PARENT] | pending | pending | pending | pending |
| C5 | `_activateWhalePass(address)` | L1116-1136 | LootboxModule | C4 | futureTicketQueue (via _queueTickets x100 iterations), mintPacked_ (via _applyWhalePassStats) | | pending | pending | pending | pending |
| C6 | `_applyEvMultiplierWithCap(...)` | L505-539 | LootboxModule | B1, B3, B4 | lootboxEvBenefitUsedByLevel[player][lvl] | [MULTI-PARENT] | pending | pending | pending | pending |
| C10 | `_creditDgnrsReward(address, uint256)` | L1793-1799 | LootboxModule | C3 | external: dgnrs.transferFromPool (sDGNRS pool transfer) | | pending | pending | pending | pending |

---

## Category D: View/Pure Functions

| # | Function | Lines | Contract | Reads/Computes | Security Note | Subsystem | Reviewed? |
|---|----------|-------|----------|---------------|--------------|-----------|-----------|
| D1 | `deityBoonSlots(address)` | L768-782 | LootboxModule | deityBoonDay, deityBoonUsedMask, decWindowOpen, deityPassOwners | View -- exposes deity slot info; deterministic per (deity, day) | DEITY-BOON | pending |
| D2 | `_lootboxEvMultiplierBps(address)` | L465-468 | LootboxModule | playerActivityScore (external self-call) | View -- activity score lookup | LOOTBOX-EV | pending |
| D3 | `_lootboxEvMultiplierFromScore(uint256)` | L474-495 | LootboxModule | none (pure) | Linear interpolation 80%-135% EV; verify no division by zero | LOOTBOX-EV | pending |
| D4 | `_burnieToEthValue(uint256, uint256)` | L1105-1111 | LootboxModule | none (pure) | Conversion: zero checks present | UTIL | pending |
| D5 | `_lazyPassPriceForLevel(uint24)` | L1806-1818 | LootboxModule | PriceLookupLib.priceForLevel (pure) | Sum of 10 level prices; 0 if level=0 | BOON-PRICING | pending |
| D6 | `_isDecimatorWindow()` | L1822-1824 | LootboxModule | decWindowOpen (view) | Simple storage read | UTIL | pending |
| D7 | `_deityDailySeed(uint48)` | L1830-1839 | LootboxModule | rngWordByDay, rngWordCurrent (view) | Fallback chain: rngWordByDay -> rngWordCurrent -> keccak(day, this) | DEITY-RNG | pending |
| D8 | `_deityBoonForSlot(...)` | L1848-1862 | LootboxModule | _deityDailySeed, weight constants (view) | Deterministic boon per (deity, day, slot); uses _boonFromRoll | DEITY-BOON | pending |
| D9 | `_rollTargetLevel(uint24, uint256)` | L834-852 | LootboxModule | none (pure) | 90% near (0-4), 10% far (5-50); EntropyLib.entropyStep | LOOTBOX-LEVEL | pending |
| D10 | `_lootboxTicketCount(...)` | L1713-1756 | LootboxModule | none (pure) | 5-tier variance (1%/4%/20%/45%/30%); modulo 10_000; returns scaled count | LOOTBOX-TICKETS | pending |
| D11 | `_lootboxDgnrsReward(uint256, uint256)` | L1763-1787 | LootboxModule | dgnrs.poolBalance (view) | 4-tier probability (79.5%/15%/5%/0.5%); ppm scaling; cap at pool balance | LOOTBOX-DGNRS | pending |
| D12 | `_boonPoolStats(...)` | L1139-1266 | LootboxModule | price, decWindowOpen, deityPassOwners (view) | Weighted average max boon value; complex multi-category calculation | BOON-PRICING | pending |
| D13 | `_boonFromRoll(...)` | L1269-1335 | LootboxModule | none (pure) | Cursor-walk weighted selection; conditional inclusion of decimator/deity/whale/lazy pools | BOON-ROLL | pending |
| D14 | `_activeBoonCategory(address)` | L1339-1363 | LootboxModule | boonPacked (view) | Packed bit extraction; priority order: coinflip > lootbox > purchase > decimator > whale > lazy > activity > deity | BOON-STATE | pending |
| D15 | `_boonCategory(uint8)` | L1366-1390 | LootboxModule | none (pure) | Type-to-category mapping; 12 boon types -> 8 categories | BOON-STATE | pending |

---

## Nested Delegatecall Call Chains (PRIORITY)

LootboxModule and BoonModule interact via nested delegatecall during lootbox resolution. These chains MUST be traced for cached-local-vs-storage bugs:

### Chain 1: Lootbox Resolution -> Boon Cleanup -> Boon Roll -> Activity Consume

```
B1/B2 openLootBox/openBurnieLootBox
  -> C1 _resolveLootboxCommon
    -> C3 _resolveLootboxRoll (x1 or x2 for split lootboxes)
    -> C2 _rollLootboxBoons (if allowBoons=true)
      -> DELEGATECALL to B9 checkAndClearExpiredBoon  [writes boonPacked.slot0, slot1]
      -> D14 _activeBoonCategory                       [reads boonPacked.slot0, slot1]
      -> D12 _boonPoolStats                            [reads price, decWindowOpen, deityPassOwners]
      -> D13 _boonFromRoll                             [pure selection]
      -> D15 _boonCategory                             [pure mapping]
      -> C4 _applyBoon                                 [writes boonPacked.slot0 or slot1]
    -> DELEGATECALL to B10 consumeActivityBoon         [writes boonPacked.slot1, mintPacked_]
```

**Critical question:** Does _rollLootboxBoons cache any boonPacked value before the delegatecall to B9? If yes, the delegatecall write creates a stale cache.

### Chain 2: Deity Boon Issuance

```
B5 issueDeityBoon
  -> D8 _deityBoonForSlot (view, deterministic)
    -> D7 _deityDailySeed
    -> D13 _boonFromRoll
  -> C4 _applyBoon [writes boonPacked.slot0 or slot1]
    -> (if whale pass) C5 _activateWhalePass
      -> _applyWhalePassStats [writes mintPacked_]
      -> _queueTickets x100 [writes futureTicketQueue]
```

### Chain 3: Direct/Redemption Resolution

```
B3/B4 resolveLootboxDirect/resolveRedemptionLootbox
  -> C6 _applyEvMultiplierWithCap [writes lootboxEvBenefitUsedByLevel]
  -> C1 _resolveLootboxCommon (allowBoons=false)
    -> C3 _resolveLootboxRoll (x1 or x2)
    -> NO boon rolling (allowBoons=false)
    -> NO delegatecall to BoonModule
```

### Chain 4: Boon Consumption (by OTHER modules)

```
[CoinflipModule] -> DELEGATECALL to B6 consumeCoinflipBoon
  -> reads boonPacked[player].slot0
  -> clears coinflip fields in slot0
  -> returns boonBps

[MintModule] -> DELEGATECALL to B7 consumePurchaseBoost
  -> reads boonPacked[player].slot0
  -> clears purchase fields in slot0
  -> returns boostBps

[DecimatorModule] -> DELEGATECALL to B8 consumeDecimatorBoost
  -> reads boonPacked[player].slot0
  -> clears decimator fields in slot0
  -> returns boostBps
```

---

## Cross-Module External Calls

| Call | From Functions | Target Contract | State Impact |
|------|---------------|----------------|-------------|
| `coin.creditFlip(player, amount)` | C1 (via _resolveLootboxCommon) | BurnieCoin | Mint BURNIE to player |
| `dgnrs.transferFromPool(Pool.Lootbox, player, amount)` | C10 | StakedDegenerusStonk | Transfer sDGNRS from lootbox pool |
| `dgnrs.poolBalance(Pool.Lootbox)` | D11 | StakedDegenerusStonk | View only (pool balance) |
| `wwxrp.mintPrize(player, amount)` | C3 | WrappedWrappedXRP | Mint WWXRP prize tokens |
| `quests.awardQuestStreakBonus(player, bonus, day)` | B10 | DegenerusQuests | Award quest streak bonus |
| `IDegenerusGame(address(this)).playerActivityScore(player)` | D2 | Self (external self-call) | View only (activity score) |
| `delegatecall BoonModule.checkAndClearExpiredBoon` | C2 | BoonModule (same storage context) | Write boonPacked slots |
| `delegatecall BoonModule.consumeActivityBoon` | C1 | BoonModule (same storage context) | Write boonPacked.slot1 + mintPacked_ |

---

## RNG / Entropy Usage Map

| Entry Point | Initial Entropy Source | Derivation | Downstream Rolls |
|-------------|----------------------|-----------|-----------------|
| B1 openLootBox | `keccak256(rngWord, player, day, amount)` L575 | EntropyLib.entropyStep chain | _rollTargetLevel (% 100, % 5 or % 46), _resolveLootboxRoll (% 20, % 10_000, % 1000, % 20), _rollLootboxBoons (% 1_000_000) |
| B2 openBurnieLootBox | `keccak256(rngWord, player, day, amountEth)` L649 | Same chain | Same as B1 |
| B3 resolveLootboxDirect | `keccak256(rngWord, player, day, amount)` L699 | Same chain | Same minus boon rolls (allowBoons=false) |
| B4 resolveRedemptionLootbox | `keccak256(rngWord, player, day, amount)` L734 | Same chain | Same minus boon rolls |
| B5 issueDeityBoon | `keccak256(_deityDailySeed(day), deity, day, slot)` L1855 | Single step | _boonFromRoll (% totalWeight) |

**RNG commitment window:** lootboxRngWordByIndex[index] is set during VRF fulfillment (after lootbox entry is recorded). Player inputs are committed at purchase time. For deity boons, the seed derives from the day's VRF word -- the deity can see their slots but cannot change them.

---

*Checklist compiled: 2026-03-25*
*Taskmaster: All 32 functions catalogued. Ready for Mad Genius attack phase.*
