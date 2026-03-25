# Unit 1: Storage Layout Verification

## Methodology
- Tool: forge inspect (Foundry, solc 0.8.34)
- Authoritative source: `forge inspect DegenerusGame storage-layout`
- Cross-reference: Manual slot comments in DegenerusGameStorage.sol (lines 34-65)
- Module alignment: All 10 delegatecall modules inspected and compared
- Comparison method: JSON output with programmatic field-by-field comparison (label, slot, offset, normalized type)

## DegenerusGame Authoritative Layout

102 storage variables across slots 0-78.

### Slot 0 (32 bytes -- Timing, FSM, Counters, Flags, ETH Phase)

| Variable | Type | Slot | Offset | Bytes |
|----------|------|------|--------|-------|
| levelStartTime | uint48 | 0 | 0 | 6 |
| dailyIdx | uint48 | 0 | 6 | 6 |
| rngRequestTime | uint48 | 0 | 12 | 6 |
| level | uint24 | 0 | 18 | 3 |
| jackpotPhaseFlag | bool | 0 | 21 | 1 |
| jackpotCounter | uint8 | 0 | 22 | 1 |
| poolConsolidationDone | bool | 0 | 23 | 1 |
| lastPurchaseDay | bool | 0 | 24 | 1 |
| decWindowOpen | bool | 0 | 25 | 1 |
| rngLockedFlag | bool | 0 | 26 | 1 |
| phaseTransitionActive | bool | 0 | 27 | 1 |
| gameOver | bool | 0 | 28 | 1 |
| dailyJackpotCoinTicketsPending | bool | 0 | 29 | 1 |
| dailyEthPhase | uint8 | 0 | 30 | 1 |
| compressedJackpotFlag | uint8 | 0 | 31 | 1 |

**Total: 32 bytes used, 0 bytes padding. Fully packed.**

### Slot 1 (25 bytes used -- Price and Double-Buffer Fields)

| Variable | Type | Slot | Offset | Bytes |
|----------|------|------|--------|-------|
| purchaseStartDay | uint48 | 1 | 0 | 6 |
| price | uint128 | 1 | 6 | 16 |
| ticketWriteSlot | uint8 | 1 | 22 | 1 |
| ticketsFullyProcessed | bool | 1 | 23 | 1 |
| prizePoolFrozen | bool | 1 | 24 | 1 |

**Total: 25 bytes used, 7 bytes padding.**

### Slots 2-78 (Full-Width Variables, Mappings, Arrays)

| Variable | Type | Slot | Offset | Bytes |
|----------|------|------|--------|-------|
| currentPrizePool | uint256 | 2 | 0 | 32 |
| prizePoolsPacked | uint256 | 3 | 0 | 32 |
| rngWordCurrent | uint256 | 4 | 0 | 32 |
| vrfRequestId | uint256 | 5 | 0 | 32 |
| totalFlipReversals | uint256 | 6 | 0 | 32 |
| dailyTicketBudgetsPacked | uint256 | 7 | 0 | 32 |
| dailyEthPoolBudget | uint256 | 8 | 0 | 32 |
| claimableWinnings | mapping(address => uint256) | 9 | 0 | 32 |
| claimablePool | uint256 | 10 | 0 | 32 |
| traitBurnTicket | mapping(uint24 => address[][256]) | 11 | 0 | 32 |
| mintPacked_ | mapping(address => uint256) | 12 | 0 | 32 |
| rngWordByDay | mapping(uint48 => uint256) | 13 | 0 | 32 |
| prizePoolPendingPacked | uint256 | 14 | 0 | 32 |
| ticketQueue | mapping(uint24 => address[]) | 15 | 0 | 32 |
| ticketsOwedPacked | mapping(uint24 => mapping(address => uint40)) | 16 | 0 | 32 |
| ticketCursor | uint32 | 17 | 0 | 4 |
| ticketLevel | uint24 | 17 | 4 | 3 |
| dailyCarryoverEthPool | uint256 | 18 | 0 | 32 |
| dailyCarryoverWinnerCap | uint16 | 19 | 0 | 2 |
| lootboxEth | mapping(uint48 => mapping(address => uint256)) | 20 | 0 | 32 |
| lootboxPresaleActive | bool | 21 | 0 | 1 |
| lootboxPresaleMintEth | uint256 | 22 | 0 | 32 |
| gameOverTime | uint48 | 23 | 0 | 6 |
| gameOverFinalJackpotPaid | bool | 23 | 6 | 1 |
| finalSwept | bool | 23 | 7 | 1 |
| whalePassClaims | mapping(address => uint256) | 24 | 0 | 32 |
| autoRebuyState | mapping(address => AutoRebuyState) | 25 | 0 | 32 |
| decimatorAutoRebuyDisabled | mapping(address => bool) | 26 | 0 | 32 |
| lastDailyJackpotWinningTraits | uint32 | 27 | 0 | 4 |
| lastDailyJackpotLevel | uint24 | 27 | 4 | 3 |
| lastDailyJackpotDay | uint48 | 27 | 7 | 6 |
| lootboxEthBase | mapping(uint48 => mapping(address => uint256)) | 28 | 0 | 32 |
| operatorApprovals | mapping(address => mapping(address => bool)) | 29 | 0 | 32 |
| levelPrizePool | mapping(uint24 => uint256) | 30 | 0 | 32 |
| affiliateDgnrsClaimedBy | mapping(uint24 => mapping(address => bool)) | 31 | 0 | 32 |
| levelDgnrsAllocation | mapping(uint24 => uint256) | 32 | 0 | 32 |
| levelDgnrsClaimed | mapping(uint24 => uint256) | 33 | 0 | 32 |
| deityPassCount | mapping(address => uint16) | 34 | 0 | 32 |
| deityPassPurchasedCount | mapping(address => uint16) | 35 | 0 | 32 |
| deityPassPaidTotal | mapping(address => uint256) | 36 | 0 | 32 |
| deityPassOwners | address[] | 37 | 0 | 32 |
| deityPassSymbol | mapping(address => uint8) | 38 | 0 | 32 |
| deityBySymbol | mapping(uint8 => address) | 39 | 0 | 32 |
| earlybirdDgnrsPoolStart | uint256 | 40 | 0 | 32 |
| earlybirdEthIn | uint256 | 41 | 0 | 32 |
| vrfCoordinator | IVRFCoordinator | 42 | 0 | 20 |
| vrfKeyHash | bytes32 | 43 | 0 | 32 |
| vrfSubscriptionId | uint256 | 44 | 0 | 32 |
| lootboxRngIndex | uint48 | 45 | 0 | 6 |
| lootboxRngPendingEth | uint256 | 46 | 0 | 32 |
| lootboxRngThreshold | uint256 | 47 | 0 | 32 |
| lootboxRngMinLinkBalance | uint256 | 48 | 0 | 32 |
| lootboxRngWordByIndex | mapping(uint48 => uint256) | 49 | 0 | 32 |
| lootboxDay | mapping(uint48 => mapping(address => uint48)) | 50 | 0 | 32 |
| lootboxBaseLevelPacked | mapping(uint48 => mapping(address => uint24)) | 51 | 0 | 32 |
| lootboxEvScorePacked | mapping(uint48 => mapping(address => uint16)) | 52 | 0 | 32 |
| lootboxBurnie | mapping(uint48 => mapping(address => uint256)) | 53 | 0 | 32 |
| lootboxRngPendingBurnie | uint256 | 54 | 0 | 32 |
| lastLootboxRngWord | uint256 | 55 | 0 | 32 |
| midDayTicketRngPending | bool | 56 | 0 | 1 |
| deityBoonDay | mapping(address => uint48) | 57 | 0 | 32 |
| deityBoonUsedMask | mapping(address => uint8) | 58 | 0 | 32 |
| deityBoonRecipientDay | mapping(address => uint48) | 59 | 0 | 32 |
| degeneretteBets | mapping(address => mapping(uint64 => uint256)) | 60 | 0 | 32 |
| degeneretteBetNonce | mapping(address => uint64) | 61 | 0 | 32 |
| lootboxEvBenefitUsedByLevel | mapping(address => mapping(uint24 => uint256)) | 62 | 0 | 32 |
| decBurn | mapping(uint24 => mapping(address => DecEntry)) | 63 | 0 | 32 |
| decBucketBurnTotal | mapping(uint24 => uint256[13][13]) | 64 | 0 | 32 |
| decClaimRounds | mapping(uint24 => DecClaimRound) | 65 | 0 | 32 |
| decBucketOffsetPacked | mapping(uint24 => uint64) | 66 | 0 | 32 |
| dailyHeroWagers | mapping(uint48 => uint256[4]) | 67 | 0 | 32 |
| playerDegeneretteEthWagered | mapping(address => mapping(uint24 => uint256)) | 68 | 0 | 32 |
| topDegeneretteByLevel | mapping(uint24 => uint256) | 69 | 0 | 32 |
| lootboxDistressEth | mapping(uint48 => mapping(address => uint256)) | 70 | 0 | 32 |
| yieldAccumulator | uint256 | 71 | 0 | 32 |
| centuryBonusLevel | uint24 | 72 | 0 | 3 |
| centuryBonusUsed | mapping(address => uint256) | 73 | 0 | 32 |
| lastVrfProcessedTimestamp | uint48 | 74 | 0 | 6 |
| terminalDecEntries | mapping(address => TerminalDecEntry) | 75 | 0 | 32 |
| terminalDecBucketBurnTotal | mapping(bytes32 => uint256) | 76 | 0 | 32 |
| lastTerminalDecClaimRound | TerminalDecClaimRound | 77 | 0 | 32 |
| boonPacked | mapping(address => BoonPacked) | 78 | 0 | 32 |

## Manual Comment Cross-Reference

Cross-referencing forge output against manual slot comments in DegenerusGameStorage.sol (lines 34-65).

### Slot 0 Cross-Reference

| Offset | Variable | Forge Says | Source Comment Says | Status |
|--------|----------|------------|---------------------|--------|
| [0:6] | levelStartTime | slot 0, offset 0, 6 bytes, uint48 | slot 0, [0:6], uint48 | MATCH |
| [6:12] | dailyIdx | slot 0, offset 6, 6 bytes, uint48 | slot 0, [6:12], uint48 | MATCH |
| [12:18] | rngRequestTime | slot 0, offset 12, 6 bytes, uint48 | slot 0, [12:18], uint48 | MATCH |
| [18:21] | level | slot 0, offset 18, 3 bytes, uint24 | slot 0, [18:21], uint24 | MATCH |
| [21:22] | jackpotPhaseFlag | slot 0, offset 21, 1 byte, bool | slot 0, [21:22], bool | MATCH |
| [22:23] | jackpotCounter | slot 0, offset 22, 1 byte, uint8 | slot 0, [22:23], uint8 | MATCH |
| [23:24] | poolConsolidationDone | slot 0, offset 23, 1 byte, bool | slot 0, [23:24], bool | MATCH |
| [24:25] | lastPurchaseDay | slot 0, offset 24, 1 byte, bool | slot 0, [24:25], bool | MATCH |
| [25:26] | decWindowOpen | slot 0, offset 25, 1 byte, bool | slot 0, [25:26], bool | MATCH |
| [26:27] | rngLockedFlag | slot 0, offset 26, 1 byte, bool | slot 0, [26:27], bool | MATCH |
| [27:28] | phaseTransitionActive | slot 0, offset 27, 1 byte, bool | slot 0, [27:28], bool | MATCH |
| [28:29] | gameOver | slot 0, offset 28, 1 byte, bool | slot 0, [28:29], bool | MATCH |
| [29:30] | dailyJackpotCoinTicketsPending | slot 0, offset 29, 1 byte, bool | slot 0, [29:30], bool | MATCH |
| [30:31] | dailyEthPhase | slot 0, offset 30, 1 byte, uint8 | slot 0, [30:31], uint8 | MATCH |
| [31:32] | compressedJackpotFlag | slot 0, offset 31, 1 byte, uint8 | slot 0, [31:32], uint8 | MATCH |

**Slot 0: 15/15 fields MATCH. 32/32 bytes accounted for. Zero padding.**

### Slot 1 Cross-Reference

| Offset | Variable | Forge Says | Source Comment Says | Status |
|--------|----------|------------|---------------------|--------|
| [0:6] | purchaseStartDay | slot 1, offset 0, 6 bytes, uint48 | slot 1, [0:6], uint48 | MATCH |
| [6:22] | price | slot 1, offset 6, 16 bytes, uint128 | slot 1, [6:22], uint128 | MATCH |
| [22:23] | ticketWriteSlot | slot 1, offset 22, 1 byte, uint8 | slot 1, [22:23], uint8 | MATCH |
| [23:24] | ticketsFullyProcessed | slot 1, offset 23, 1 byte, bool | slot 1, [23:24], bool | MATCH |
| [24:25] | prizePoolFrozen | slot 1, offset 24, 1 byte, bool | slot 1, [24:25], bool | MATCH |
| [25:32] | (padding) | -- | [25:32], 7 bytes unused | MATCH |

**Slot 1: 5/5 fields MATCH. 25/32 bytes used, 7 bytes padding confirmed.**

### Slots 2-8 Cross-Reference

| Slot | Variable | Forge Says | Source Comment Says | Status |
|------|----------|------------|---------------------|--------|
| 2 | currentPrizePool | uint256, slot 2 | "EVM SLOT 2 -- Current Prize Pool", uint256 | MATCH |
| 3 | prizePoolsPacked | uint256, slot 3 | "SLOTS 3+ -- Full-width variables" (slot 3 documented as nextPrizePool[128] + futurePrizePool[128]) | MATCH |
| 4 | rngWordCurrent | uint256, slot 4 | slot 4 (sequential after slot 3) | MATCH |
| 5 | vrfRequestId | uint256, slot 5 | slot 5 | MATCH |
| 6 | totalFlipReversals | uint256, slot 6 | slot 6 | MATCH |
| 7 | dailyTicketBudgetsPacked | uint256, slot 7 | slot 7 | MATCH |
| 8 | dailyEthPoolBudget | uint256, slot 8 | slot 8 | MATCH |

**Slots 2-8: All MATCH.**

### Slots 9+

Source comments state "Slots 9+ -- Mappings and dynamic arrays" without individual slot numbers for each variable. The forge output provides the authoritative mapping. No manual comments to cross-reference for slots 9-78 -- the source documentation defers to sequential declaration order, which forge confirms.

## Module Alignment Matrix

All comparisons performed using forge inspect JSON output with programmatic field-by-field comparison. Type strings normalized to strip compiler-internal AST node IDs (which differ per compilation unit but do not affect storage layout).

| Module | Inherits Via | Var Count | Slot Range | Layout Match | Notes |
|--------|-------------|-----------|------------|--------------|-------|
| DegenerusGameAdvanceModule | Direct (DegenerusGameStorage) | 102 | 0-78 | EXACT MATCH | -- |
| DegenerusGameMintModule | Direct (DegenerusGameStorage) | 102 | 0-78 | EXACT MATCH | -- |
| DegenerusGameWhaleModule | Via MintStreakUtils | 102 | 0-78 | EXACT MATCH | -- |
| DegenerusGameJackpotModule | Via PayoutUtils | 102 | 0-78 | EXACT MATCH | -- |
| DegenerusGameDecimatorModule | Via PayoutUtils | 102 | 0-78 | EXACT MATCH | -- |
| DegenerusGameEndgameModule | Via PayoutUtils | 102 | 0-78 | EXACT MATCH | -- |
| DegenerusGameGameOverModule | Direct (DegenerusGameStorage) | 102 | 0-78 | EXACT MATCH | -- |
| DegenerusGameLootboxModule | Direct (DegenerusGameStorage) | 102 | 0-78 | EXACT MATCH | -- |
| DegenerusGameBoonModule | Direct (DegenerusGameStorage) | 102 | 0-78 | EXACT MATCH | -- |
| DegenerusGameDegeneretteModule | Diamond (PayoutUtils + MintStreakUtils) | 102 | 0-78 | EXACT MATCH | Diamond inheritance verified safe |

**10/10 modules: EXACT MATCH with DegenerusGame.**

## Diamond Inheritance Check (DegeneretteModule)

`DegenerusGameDegeneretteModule is DegenerusGamePayoutUtils, DegenerusGameMintStreakUtils`

Both `DegenerusGamePayoutUtils` and `DegenerusGameMintStreakUtils` inherit from `DegenerusGameStorage`. Solidity C3 linearization resolves this diamond:

```
DegeneretteModule
  -> PayoutUtils -> DegenerusGameStorage
  -> MintStreakUtils -> DegenerusGameStorage
```

C3 linearization: `DegeneretteModule, PayoutUtils, MintStreakUtils, DegenerusGameStorage`

DegenerusGameStorage appears exactly once in the linearization. Neither PayoutUtils nor MintStreakUtils declares any storage variables -- they only add internal functions. Therefore no duplicate slots can result.

**Verification:** `forge inspect DegenerusGameDegeneretteModule storage-layout --json` produces 102 variables across slots 0-78, identical to DegenerusGame.

**Diamond inheritance: SAFE. No duplicate slots.**

## Rogue Variable Check

**Method 1: forge inspect comparison (authoritative)**
Every module has exactly 102 variables, matching DegenerusGame's 102 variables. Variable names, slot numbers, offsets, and types all match. No module has additional variables beyond what DegenerusGameStorage defines.

**Method 2: grep verification (secondary)**
The research phase verified via grep that all module-level declarations are `private constant` or `internal constant` -- neither occupies storage slots (constants are compiled into bytecode, not stored in storage).

**Result: No module adds non-constant state variables. Zero rogue variables detected.**

## Verdict

**PASS -- All storage layouts are aligned.**

Evidence:
1. Forge inspect confirms DegenerusGame has 102 storage variables across slots 0-78
2. Manual slot comments for slots 0-1 match forge output exactly (20/20 fields verified)
3. All 10 delegatecall modules have identical storage layout (102 vars, slots 0-78, EXACT MATCH on label/slot/offset/type)
4. DegeneretteModule diamond inheritance resolves safely via C3 linearization
5. No module adds non-constant state variables (zero rogue variables)

The delegatecall module system shares a coherent, verified storage layout. All subsequent module audits (Phases 104-117) can rely on this foundation.
