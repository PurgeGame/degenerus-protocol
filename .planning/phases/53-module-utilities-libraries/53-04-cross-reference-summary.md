# Phase 53: Module Utilities & Libraries -- Cross-Reference Summary

**Date:** 2026-03-07
**Scope:** 7 contracts across 3 audit plans (53-01, 53-02, 53-03)
**Purpose:** Comprehensive call site index, dependency matrix, consolidated findings, and phase statistics.

---

## Call Site Index

### 1. DegenerusGameMintStreakUtils (53-01)

**File:** `contracts/modules/DegenerusGameMintStreakUtils.sol`
**Functions:** `_recordMintStreakForLevel`, `_mintStreakEffective`
**Access Pattern:** Abstract contract inherited via delegatecall module chain

| File | Line | Function Called | Context |
|------|------|-----------------|---------|
| `DegenerusGame.sol` | 47 | import | Imports DegenerusGameMintStreakUtils |
| `DegenerusGame.sol` | 447 | `_recordMintStreakForLevel` | External entry point, COIN-gated, passes `_activeTicketLevel()` |
| `DegenerusGame.sol` | 2353 | `_mintStreakEffective` | `ethMintStreakCount()` view, passes `_activeTicketLevel()` |
| `DegenerusGame.sol` | 2374 | `_mintStreakEffective` | `ethMintStats()` view, passes `_activeTicketLevel()` |
| `DegenerusGame.sol` | 2416 | `_mintStreakEffective` | `_playerActivityScore()` internal view |
| `DegenerusGameDegeneretteModule.sol` | 11 | import | Imports DegenerusGameMintStreakUtils |
| `DegenerusGameDegeneretteModule.sol` | 1030 | `_mintStreakEffective` | Degenerette activity score, passes `level + 1` |
| `DegenerusGameWhaleModule.sol` | 12 | import | Imports DegenerusGameMintStreakUtils |

**Total call sites:** 5 (1 write, 4 read)
**Importing contracts:** 3 (DegenerusGame, DegeneretteModule, WhaleModule)

---

### 2. DegenerusGamePayoutUtils (53-01)

**File:** `contracts/modules/DegenerusGamePayoutUtils.sol`
**Functions:** `_creditClaimable`, `_calcAutoRebuy`, `_queueWhalePassClaimCore`
**Access Pattern:** Abstract contract inherited via delegatecall module chain

#### `_creditClaimable(address, uint256)`

| File | Line | Context |
|------|------|---------|
| `DegenerusGameJackpotModule.sol` | 982 | Direct jackpot credit |
| `DegenerusGameJackpotModule.sol` | 1010 | Non-auto-rebuy fallback |
| `DegenerusGameJackpotModule.sol` | 1023 | Take-profit reservation |
| `DegenerusGameDegeneretteModule.sol` | 1174 | Degenerette bet winnings |
| `DegenerusGameDecimatorModule.sol` | 476 | Decimator claim, no auto-rebuy |
| `DegenerusGameDecimatorModule.sol` | 488 | Decimator take-profit |
| `DegenerusGameDecimatorModule.sol` | 517 | Decimator non-rebuy fallback |
| `DegenerusGameEndgameModule.sol` | 237 | Endgame/BAF auto-rebuy credit |
| `DegenerusGameEndgameModule.sol` | 250 | Endgame take-profit reservation |
| `DegenerusGameEndgameModule.sol` | 264 | Endgame non-rebuy fallback |
| `DegenerusGamePayoutUtils.sol` | 88 | Internal: `_queueWhalePassClaimCore` remainder |

**Total call sites:** 11

#### `_calcAutoRebuy(...)`

| File | Line | Context |
|------|------|---------|
| `DegenerusGameJackpotModule.sol` | 1000 | Jackpot prize auto-rebuy |
| `DegenerusGameDecimatorModule.sol` | 466 | Decimator prize auto-rebuy |
| `DegenerusGameEndgameModule.sol` | 227 | Endgame/BAF prize auto-rebuy |

**Total call sites:** 3

#### `_queueWhalePassClaimCore(address, uint256)`

| File | Line | Context |
|------|------|---------|
| `DegenerusGameEndgameModule.sol` | 363 | Lootbox portion whale pass queuing |
| `DegenerusGameEndgameModule.sol` | 410 | Direct payout whale pass queuing |
| `DegenerusGameDecimatorModule.sol` | 729 | Decimator large payout conversion |

**Total call sites:** 3

**Importing contracts:** 4 (JackpotModule, DecimatorModule, DegeneretteModule, EndgameModule)
**Combined PayoutUtils call sites:** 17

---

### 3. BitPackingLib (53-02)

**File:** `contracts/libraries/BitPackingLib.sol`
**Functions:** `setPacked`
**Constants:** 10 (3 masks + 7 shifts)
**Access Pattern:** Internal library, inlined at call sites

| File | Line(s) | Usage | Fields Accessed |
|------|---------|-------|-----------------|
| `DegenerusGame.sol` | 49 | import | -- |
| `DegenerusGame.sol` | 1668-1669, 1680-1681 | Read (shift+mask) | FROZEN_UNTIL_LEVEL |
| `DegenerusGame.sol` | 2327-2328 | Read | LAST_LEVEL |
| `DegenerusGame.sol` | 2341-2342, 2372, 2414 | Read | LEVEL_COUNT |
| `DegenerusGame.sol` | 2419-2420 | Read | FROZEN_UNTIL_LEVEL |
| `DegenerusGame.sol` | 2423 | Read | WHALE_BUNDLE_TYPE |
| `DegenerusGameStorage.sol` | 7 | import | -- |
| `DegenerusGameStorage.sol` | 969-977, 996 | Read (shift+mask) | FROZEN_UNTIL_LEVEL, LAST_LEVEL, LEVEL_COUNT, WHALE_BUNDLE_TYPE |
| `DegenerusGameStorage.sol` | 1003-1035 | Write (setPacked x6) | LEVEL_COUNT, FROZEN_UNTIL_LEVEL, WHALE_BUNDLE_TYPE, LAST_LEVEL, DAY |
| `DegenerusGameStorage.sol` | 1053-1058 | Read | FROZEN_UNTIL_LEVEL, LEVEL_COUNT |
| `DegenerusGameStorage.sol` | 1077-1107 | Write (setPacked x5) | LEVEL_COUNT, FROZEN_UNTIL_LEVEL, WHALE_BUNDLE_TYPE, LAST_LEVEL, DAY |
| `DegenerusGameMintModule.sol` | 10 | import | -- |
| `DegenerusGameMintModule.sol` | 193-210 | Read | LAST_LEVEL, LEVEL_COUNT, LEVEL_UNITS_LEVEL, LEVEL_UNITS, MASK_16 |
| `DegenerusGameMintModule.sol` | 219-278 | Write (setPacked x8) | LEVEL_UNITS, LEVEL_UNITS_LEVEL, FROZEN_UNTIL_LEVEL, WHALE_BUNDLE_TYPE, LAST_LEVEL, LEVEL_COUNT |
| `DegenerusGameWhaleModule.sol` | 10 | import | -- |
| `DegenerusGameWhaleModule.sol` | 209-210 | Read | FROZEN_UNTIL_LEVEL, LEVEL_COUNT |
| `DegenerusGameWhaleModule.sol` | 251-258 | Write (setPacked x4 + direct) | LEVEL_COUNT, FROZEN_UNTIL_LEVEL, WHALE_BUNDLE_TYPE, LAST_LEVEL, DAY |
| `DegenerusGameWhaleModule.sol` | 351-352 | Read | FROZEN_UNTIL_LEVEL |
| `DegenerusGameWhaleModule.sol` | 859, 863-864 | Read + direct write | DAY |
| `DegenerusGameWhaleModule.sol` | 871-874 | Write (setPacked x4) | LEVEL_COUNT, LEVEL_STREAK, LAST_LEVEL, MINT_STREAK_LAST_COMPLETED |
| `DegenerusGameAdvanceModule.sol` | 20 | import | -- |
| `DegenerusGameAdvanceModule.sol` | 555 | Read | DAY |
| `DegenerusGameAdvanceModule.sol` | 572-573 | Read | FROZEN_UNTIL_LEVEL |
| `DegenerusGameBoonModule.sol` | 7 | import | -- |
| `DegenerusGameBoonModule.sol` | 336 | Read | LEVEL_COUNT |
| `DegenerusGameBoonModule.sol` | 344-347 | Write (setPacked x1) | LEVEL_COUNT |
| `DegenerusGameMintStreakUtils.sol` | 5 | import | -- |
| `DegenerusGameMintStreakUtils.sol` | 13-14, 21, 28-29, 44, 55, 59 | Read + direct bit ops | LEVEL_STREAK, MINT_STREAK_LAST_COMPLETED, MASK_24 |
| `DegenerusGameDegeneretteModule.sol` | 9 | import | -- |
| `DegenerusGameDegeneretteModule.sol` | 1028, 1033-1034, 1037 | Read | LEVEL_COUNT, FROZEN_UNTIL_LEVEL, WHALE_BUNDLE_TYPE |

**Total importing contracts:** 8 (DegenerusGame, DegenerusGameStorage, MintModule, WhaleModule, AdvanceModule, BoonModule, MintStreakUtils, DegeneretteModule)
**Total `setPacked` call sites:** 28 (6 Storage + 8 MintModule + 4 WhaleModule-write + 1 BoonModule + 4 WhaleModule-reset + 5 Storage-whale)
**Total constant read sites:** 50+

---

### 4. EntropyLib (53-02)

**File:** `contracts/libraries/EntropyLib.sol`
**Functions:** `entropyStep`
**Access Pattern:** Internal library, inlined at call sites

| File | Line(s) | Call Count | Context |
|------|---------|------------|---------|
| `DegenerusGamePayoutUtils.sol` | 5 | import | -- |
| `DegenerusGamePayoutUtils.sol` | 54 | 1 | Level offset randomization for auto-rebuy |
| `DegenerusGameMintModule.sol` | 11 | import | -- |
| `DegenerusGameMintModule.sol` | 527 | 1 | Lootbox roll entropy derivation |
| `DegenerusGameEndgameModule.sol` | 10 | import | -- |
| `DegenerusGameEndgameModule.sol` | 458 | 1 | BAF/decimator entropy derivation |
| `DegenerusGameLootboxModule.sol` | 11 | import | -- |
| `DegenerusGameLootboxModule.sol` | 795, 799, 1540, 1561, 1577, 1591, 1627 | 7 | Level entropy, far entropy, boon generation, deity boon rolls |
| `DegenerusGameJackpotModule.sol` | 12 | import | -- |
| `DegenerusGameJackpotModule.sol` | 833, 845, 1158, 1393, 1449, 1653, 2122, 2475, 2563 | 9 | Ticket processing, winner selection, BURNIE coin jackpots, LCG step, chunk entropy |

**Total importing contracts:** 5 (PayoutUtils, MintModule, EndgameModule, LootboxModule, JackpotModule)
**Total `entropyStep` call sites:** 19

---

### 5. GameTimeLib (53-02)

**File:** `contracts/libraries/GameTimeLib.sol`
**Functions:** `currentDayIndex`, `currentDayIndexAt`
**Access Pattern:** Internal library, inlined at call sites

| File | Line(s) | Function | Context |
|------|---------|----------|---------|
| `DegenerusGameStorage.sol` | 8 | import | -- |
| `DegenerusGameStorage.sol` | 1114 | `currentDayIndex` | `_currentDay()` wrapper |
| `DegenerusGameStorage.sol` | 1119 | `currentDayIndexAt` | `_currentDayAt()` wrapper |
| `DegenerusAffiliate.sol` | 6 | import | -- |
| `DegenerusAffiliate.sol` | 906 | `currentDayIndex` | Affiliate day tracking |

**Total importing contracts:** 2 (DegenerusGameStorage, DegenerusAffiliate)
**Total call sites:** 3 (2 `currentDayIndex`, 1 `currentDayIndexAt`)

Note: All module access to day index goes through DegenerusGameStorage helper functions (`_currentDay()`, `_currentDayAt()`), not direct GameTimeLib calls.

---

### 6. PriceLookupLib (53-02)

**File:** `contracts/libraries/PriceLookupLib.sol`
**Functions:** `priceForLevel`
**Access Pattern:** Internal library, inlined at call sites

| File | Line(s) | Call Count | Context |
|------|---------|------------|---------|
| `DegenerusGamePayoutUtils.sol` | 6 | import | -- |
| `DegenerusGamePayoutUtils.sol` | 60 | 1 | Ticket price (`>> 2` for quarter-ticket unit) |
| `DegenerusGameWhaleModule.sol` | 11 | import | -- |
| `DegenerusGameWhaleModule.sol` | 372 | 1 | Whale bundle level pricing |
| `DegenerusGameWhaleModule.sol` | 604 | 1 | Lazy pass cost (sum-of-level-prices loop) |
| `DegenerusGameEndgameModule.sol` | 11 | import | -- |
| `DegenerusGameEndgameModule.sol` | 479 | 1 | BAF target price |
| `DegenerusGameJackpotModule.sol` | 13 | import | -- |
| `DegenerusGameJackpotModule.sol` | 823 | 1 | Level prices array population |
| `DegenerusGameJackpotModule.sol` | 1074 | 1 | Ticket price for jackpot processing |
| `DegenerusGameJackpotModule.sol` | 1413 | 1 | Unit price for bucket share rounding |
| `DegenerusGameJackpotModule.sol` | 1535 | 1 | Unit price for normal jackpot share rounding |
| `DegenerusGameLootboxModule.sol` | 12 | import | -- |
| `DegenerusGameLootboxModule.sol` | 854 | 1 | Lootbox target price |
| `DegenerusGameLootboxModule.sol` | 1719 | 1 | Deity pass level-sum pricing |

**Total importing contracts:** 5 (PayoutUtils, WhaleModule, EndgameModule, JackpotModule, LootboxModule)
**Total `priceForLevel` call sites:** 10

---

### 7. JackpotBucketLib (53-03)

**File:** `contracts/libraries/JackpotBucketLib.sol`
**Functions:** 13 (traitBucketCounts, scaleTraitBucketCountsWithCap, bucketCountsForPoolCap, sumBucketCounts, capBucketCounts, bucketShares, soloBucketIndex, rotatedShareBps, shareBpsByBucket, packWinningTraits, unpackWinningTraits, getRandomTraits, bucketOrderLargestFirst)
**Access Pattern:** Internal library, inlined at call sites; exclusively used by JackpotModule

| File | Line(s) | Function | Context |
|------|---------|----------|---------|
| `DegenerusGameJackpotModule.sol` | 14 | import | -- |
| `DegenerusGameJackpotModule.sol` | 296 | `unpackWinningTraits` | Final-day jackpot distribution |
| `DegenerusGameJackpotModule.sol` | 300 | `bucketCountsForPoolCap` | Final-day scaled bucket counts |
| `DegenerusGameJackpotModule.sol` | 306 | `shareBpsByBucket` | Final-day share BPS |
| `DegenerusGameJackpotModule.sol` | 783 | `soloBucketIndex` | DGNRS final-day solo targeting |
| `DegenerusGameJackpotModule.sol` | 785 | `unpackWinningTraits` | DGNRS final-day trait unpacking |
| `DegenerusGameJackpotModule.sol` | 1041 | `unpackWinningTraits` | Trait ticket check |
| `DegenerusGameJackpotModule.sol` | 1117 | `unpackWinningTraits` | Winner selection trait unpacking |
| `DegenerusGameJackpotModule.sol` | 1322 | `unpackWinningTraits` | Standard jackpot execution |
| `DegenerusGameJackpotModule.sol` | 1325 | `shareBpsByBucket` | Standard jackpot share BPS |
| `DegenerusGameJackpotModule.sol` | 1341 | `traitBucketCounts` | Standard jackpot base counts |
| `DegenerusGameJackpotModule.sol` | 1345 | `scaleTraitBucketCountsWithCap` | Standard jackpot scaling |
| `DegenerusGameJackpotModule.sol` | 1414 | `soloBucketIndex` | Chunked distribution remainder bucket |
| `DegenerusGameJackpotModule.sol` | 1415 | `bucketShares` | Chunked ETH share computation |
| `DegenerusGameJackpotModule.sol` | 1423 | `bucketOrderLargestFirst` | Chunked distribution ordering |
| `DegenerusGameJackpotModule.sol` | 1536 | `soloBucketIndex` | Normal jackpot remainder bucket |
| `DegenerusGameJackpotModule.sol` | 1538 | `soloBucketIndex` | Normal jackpot solo bucket |
| `DegenerusGameJackpotModule.sol` | 1540 | `bucketShares` | Normal ETH share computation |
| `DegenerusGameJackpotModule.sol` | 2453 | `unpackWinningTraits` | BURNIE coin jackpot |
| `DegenerusGameJackpotModule.sol` | 2632 | `packWinningTraits` | Burn-count-weighted trait packing |
| `DegenerusGameJackpotModule.sol` | 2636 | `packWinningTraits` | Random trait packing |
| `DegenerusGameJackpotModule.sol` | 2637 | `getRandomTraits` | Random trait derivation |
| `DegenerusGameJackpotModule.sol` | 2689 | `unpackWinningTraits` | Actual trait ticket check |

**Total importing contracts:** 1 (JackpotModule only)
**Total call sites:** 22 across 11 distinct caller functions

---

## Dependency Matrix

Consumer contracts vs. utility/library dependencies:

| Consumer | MintStreakUtils | PayoutUtils | BitPackingLib | EntropyLib | GameTimeLib | PriceLookupLib | JackpotBucketLib |
|----------|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| **DegenerusGame** | x | | x | | | | |
| **DegenerusGameStorage** | | | x | | x | | |
| **DegenerusAffiliate** | | | | | x | | |
| **MintModule** | | | x | x | | | |
| **WhaleModule** | x | | x | | | x | |
| **AdvanceModule** | | | x | | | | |
| **BoonModule** | | | x | | | | |
| **MintStreakUtils** | -- | | x | | | | |
| **PayoutUtils** | | -- | | x | | x | |
| **DegeneretteModule** | x | x | x | | | | |
| **DecimatorModule** | | x | | | | | |
| **EndgameModule** | | x | | x | | x | |
| **LootboxModule** | | | | x | | x | |
| **JackpotModule** | | x | | x | | x | x |

**Legend:** `x` = imports/uses; `--` = self (definition site)

### Dependency Counts

| Library/Utility | Importing Contracts | Total Call Sites |
|-----------------|:---:|:---:|
| MintStreakUtils | 3 | 5 |
| PayoutUtils | 4 | 17 |
| BitPackingLib | 8 | 28+ setPacked, 50+ constant reads |
| EntropyLib | 5 | 19 |
| GameTimeLib | 2 | 3 |
| PriceLookupLib | 5 | 10 |
| JackpotBucketLib | 1 | 22 |

### Cross-Library Dependencies

```
BitPackingLib      <-- no dependencies (standalone)
EntropyLib         <-- no dependencies (standalone)
GameTimeLib        <-- ContractAddresses (compile-time constant DEPLOY_DAY_BOUNDARY)
PriceLookupLib     <-- no dependencies (standalone)
JackpotBucketLib   <-- no dependencies (standalone)
MintStreakUtils     <-- BitPackingLib (constants + direct bit ops)
PayoutUtils        <-- EntropyLib (entropy step), PriceLookupLib (price lookup)
```

No circular dependencies exist. All 4 pure libraries are leaf nodes. The 2 utility contracts (MintStreakUtils, PayoutUtils) depend on libraries but not on each other.
