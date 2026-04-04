# Phase 180 Plan 01: Storage Layout & ContractAddresses Verification

## Part 1: Storage Layout Verification (DELTA-02)

### Method

Ran `forge inspect <Contract> storage-layout --json` on all 13 DegenerusGameStorage inheritors. Extracted (slot, offset, label, type) tuples for each contract, normalized Solidity AST node IDs (compiler-internal identifiers that differ per compilation unit but do not affect storage layout), then computed SHA-256 hash of the canonical representation for comparison.

### Results

| # | Contract | Slots | Max Slot | Layout Hash | Match |
|---|----------|-------|----------|-------------|-------|
| 1 | DegenerusGameStorage (baseline) | 95 | 72 | 98c1613443f7bf53 | IDENTICAL |
| 2 | DegenerusGamePayoutUtils | 95 | 72 | 98c1613443f7bf53 | IDENTICAL |
| 3 | DegenerusGameMintStreakUtils | 95 | 72 | 98c1613443f7bf53 | IDENTICAL |
| 4 | DegenerusGameAdvanceModule | 95 | 72 | 98c1613443f7bf53 | IDENTICAL |
| 5 | DegenerusGameBoonModule | 95 | 72 | 98c1613443f7bf53 | IDENTICAL |
| 6 | DegenerusGameGameOverModule | 95 | 72 | 98c1613443f7bf53 | IDENTICAL |
| 7 | DegenerusGameLootboxModule | 95 | 72 | 98c1613443f7bf53 | IDENTICAL |
| 8 | DegenerusGameJackpotModule | 95 | 72 | 98c1613443f7bf53 | IDENTICAL |
| 9 | DegenerusGameDecimatorModule | 95 | 72 | 98c1613443f7bf53 | IDENTICAL |
| 10 | DegenerusGameWhaleModule | 95 | 72 | 98c1613443f7bf53 | IDENTICAL |
| 11 | DegenerusGameMintModule | 95 | 72 | 98c1613443f7bf53 | IDENTICAL |
| 12 | DegenerusGame | 95 | 72 | 98c1613443f7bf53 | IDENTICAL |
| 13 | DegenerusGameDegeneretteModule | 95 | 72 | 98c1613443f7bf53 | IDENTICAL |

### Inheritance Tree Covered

```
DegenerusGameStorage (base)
  +-- DegenerusGamePayoutUtils (abstract)
  |     +-- DegenerusGameJackpotModule
  |     +-- DegenerusGameDecimatorModule
  +-- DegenerusGameMintStreakUtils (abstract)
  |     +-- DegenerusGameWhaleModule
  |     +-- DegenerusGameMintModule
  |     +-- DegenerusGame
  +-- DegenerusGameAdvanceModule
  +-- DegenerusGameBoonModule
  +-- DegenerusGameGameOverModule
  +-- DegenerusGameLootboxModule
  +-- DegenerusGameDegeneretteModule (inherits both PayoutUtils + MintStreakUtils)
```

### Notes on AST ID Differences

Raw `forge inspect` output shows differing AST node IDs in type strings (e.g., `t_struct(AutoRebuyState)2326_storage` vs `t_struct(AutoRebuyState)2746_storage`). These are Solidity compiler internal identifiers that vary per compilation unit. They do NOT affect storage layout -- the actual struct definition, field order, slot assignment, and byte offset are identical across all 13 contracts. Normalization strips these IDs before comparison, confirming byte-identical layout.

### DELTA-02: VERIFIED -- all 13 inheritors byte-identical

All 13 DegenerusGameStorage inheritors share identical storage layout: 95 storage entries across slots 0-72. No drift detected after v16.0 repack, v17.0 affiliate bonus cache, and v17.1 comment correctness changes. This re-confirms the Phase 172 verification still holds.

---

## Part 2: ContractAddresses Alignment Audit (DELTA-04)

### Method

For each of the 31 labels in ContractAddresses.sol (lines 7-38), ran `grep -rn` across contracts/ (excluding ContractAddresses.sol itself and .bak files) to find all consumer files. Multi-line references (where ContractAddresses and .LABEL appear on separate lines due to line wrapping) were captured by searching for `.LABEL` patterns.

### Non-Address Constants

| Label | Type | Consumer Files | Refs | Key Consumers |
|-------|------|----------------|------|---------------|
| DEPLOY_DAY_BOUNDARY | uint48 | 3 | 4 | GameTimeLib, AdvanceModule, JackpotModule |
| VRF_KEY_HASH | bytes32 | 1 | 2 | DegenerusAdmin |

### Module Address Labels

| Label | Consumer Files | Refs | Key Consumers |
|-------|----------------|------|---------------|
| GAME_MINT_MODULE | 2 | 6 | DegenerusGame, AdvanceModule |
| GAME_ADVANCE_MODULE | 1 | 6 | DegenerusGame |
| GAME_WHALE_MODULE | 2 | 5 | DegenerusGame, AdvanceModule |
| GAME_JACKPOT_MODULE | 2 | 10 | DegenerusGame, AdvanceModule |
| GAME_DECIMATOR_MODULE | 2 | 7 | DegenerusGame, AdvanceModule |
| **GAME_ENDGAME_MODULE** | **0** | **0** | **NONE (dead label, EndgameModule deleted in v16.0)** |
| GAME_GAMEOVER_MODULE | 1 | 2 | AdvanceModule |
| GAME_LOOTBOX_MODULE | 3 | 6 | DegenerusGame, DecimatorModule, DegeneretteModule |
| GAME_BOON_MODULE | 2 | 5 | DegenerusGame, LootboxModule |
| GAME_DEGENERETTE_MODULE | 1 | 2 | DegenerusGame |
| ICONS_32 | 1 | 1 | DegenerusDeityPass |

### Infrastructure Address Labels

| Label | Consumer Files | Refs | Key Consumers |
|-------|----------------|------|---------------|
| COIN | 11 | 20 | BurnieCoinflip, DegenerusAffiliate, DegenerusGame, DegenerusJackpots, DegenerusQuests (+6 more) |
| COINFLIP | 10 | 25 | BurnieCoin, DegenerusAdmin, DegenerusAffiliate, DegenerusGame, DegenerusJackpots (+5 more) |
| VAULT | 15 | 48 | BurnieCoin, DegenerusAdmin, DegenerusAffiliate, DegenerusDeityPass, DegenerusGame (+10 more) |
| AFFILIATE | 3 | 3 | BurnieCoinflip, DegenerusQuests, DegenerusGameStorage |
| JACKPOTS | 3 | 4 | BurnieCoinflip, DegenerusGame, JackpotModule |
| QUESTS | 4 | 6 | BurnieCoin, BurnieCoinflip, DegenerusAffiliate, DegenerusGameStorage |
| GAME | 15 | 38 | BurnieCoin, BurnieCoinflip, DegenerusAdmin, DegenerusAffiliate, DegenerusDeityPass (+10 more) |
| SDGNRS | 14 | 37 | BurnieCoin, BurnieCoinflip, DegenerusAdmin, DegenerusAffiliate, DegenerusGame (+9 more) |
| DGNRS | 2 | 10 | DegenerusAffiliate, StakedDegenerusStonk |
| ADMIN | 4 | 8 | BurnieCoinflip, DegenerusGame, AdvanceModule, GameOverModule |
| DEITY_PASS | 1 | 1 | WhaleModule |
| WWXRP | 4 | 4 | BurnieCoinflip, DegenerusVault, DegeneretteModule, LootboxModule |
| STETH_TOKEN | 8 | 8 | DegenerusGame, DegenerusStonk, DegenerusVault, GNRUS, StakedDegenerusStonk (+3 more) |
| LINK_TOKEN | 1 | 2 | DegenerusAdmin |
| GNRUS | 4 | 6 | DegenerusStonk, AdvanceModule, GameOverModule, JackpotModule |
| CREATOR | 3 | 13 | DegenerusStonk, DegenerusVault, Icons32Data |
| VRF_COORDINATOR | 1 | 4 | DegenerusAdmin |
| WXRP | 1 | 1 | WrappedWrappedXRP |

### GAME_ENDGAME_MODULE Analysis

GAME_ENDGAME_MODULE (ContractAddresses.sol line 16) was confirmed to have **zero live consumers**. An exhaustive search for "ENDGAME_MODULE", "EndgameModule", and "ENDGAME" across all .sol files in contracts/ (excluding ContractAddresses.sol) returned no results.

The EndgameModule was deleted in v16.0 (Phase 171). The label persists in ContractAddresses.sol as a dead constant. Since ContractAddresses is a library of compile-time constants, unused constants are eliminated by the compiler and incur zero gas cost at runtime. The label is harmless but could be cleaned up as a housekeeping matter.

### Summary

- 31 total labels in ContractAddresses.sol (2 non-address constants + 29 address labels)
- 30 labels have at least one live consumer
- 1 label (GAME_ENDGAME_MODULE) has zero consumers -- expected dead, confirmed harmless

### DELTA-04: VERIFIED -- GAME_ENDGAME_MODULE has 0 live consumers (dead label, no runtime impact); all other 30 labels have active consumers
