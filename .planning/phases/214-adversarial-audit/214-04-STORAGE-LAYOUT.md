# Adversarial Audit: Storage Layout Verification (ADV-02)

**Method:** forge inspect storageLayout comparison across all DegenerusGameStorage inheritors
**Date:** 2026-04-10
**Contracts inspected:** 13 (1 base + 12 inheritors)
**Storage variables per contract:** 84

## Inheritance Tree

```
DegenerusGameStorage (abstract)
  +-- DegenerusGamePayoutUtils (abstract)
  |     +-- DegenerusGameDecimatorModule
  |     +-- DegenerusGameJackpotModule
  |     +-- DegenerusGameDegeneretteModule (also inherits MintStreakUtils)
  +-- DegenerusGameMintStreakUtils (abstract)
  |     +-- DegenerusGameMintModule
  |     +-- DegenerusGameWhaleModule
  |     +-- DegenerusGameDegeneretteModule (also inherits PayoutUtils)
  |     +-- DegenerusGame (main dispatcher)
  +-- DegenerusGameAdvanceModule
  +-- DegenerusGameLootboxModule
  +-- DegenerusGameBoonModule
  +-- DegenerusGameGameOverModule
```

Note: DegenerusGameDegeneretteModule uses dual inheritance (`is DegenerusGamePayoutUtils, DegenerusGameMintStreakUtils`). Both intermediate parents inherit DegenerusGameStorage, creating a diamond. Solidity's C3 linearization resolves this correctly -- DegenerusGameStorage appears once in the linearized chain, so no slot duplication occurs.

## DegenerusGameStorage Base Layout

84 storage variables across 66 EVM slots (slots 0-65). Produced via `forge inspect DegenerusGameStorage storageLayout --json`.

### Slot 0: Timing, FSM, Counters, Flags, Buffer, Freeze (30/32 bytes)

| Byte Range | Bit Range | Type | Variable | Bytes |
|------------|-----------|------|----------|-------|
| [0:4] | 0-31 | uint32 | purchaseStartDay | 4 |
| [4:8] | 32-63 | uint32 | dailyIdx | 4 |
| [8:14] | 64-111 | uint48 | rngRequestTime | 6 |
| [14:17] | 112-135 | uint24 | level | 3 |
| [17:18] | 136-143 | bool | jackpotPhaseFlag | 1 |
| [18:19] | 144-151 | uint8 | jackpotCounter | 1 |
| [19:20] | 152-159 | bool | lastPurchaseDay | 1 |
| [20:21] | 160-167 | bool | decWindowOpen | 1 |
| [21:22] | 168-175 | bool | rngLockedFlag | 1 |
| [22:23] | 176-183 | bool | phaseTransitionActive | 1 |
| [23:24] | 184-191 | bool | gameOver | 1 |
| [24:25] | 192-199 | bool | dailyJackpotCoinTicketsPending | 1 |
| [25:26] | 200-207 | uint8 | compressedJackpotFlag | 1 |
| [26:27] | 208-215 | bool | ticketsFullyProcessed | 1 |
| [27:28] | 216-223 | bool | gameOverPossible | 1 |
| [28:29] | 224-231 | bool | ticketWriteSlot | 1 |
| [29:30] | 232-239 | bool | prizePoolFrozen | 1 |
| [30:32] | 240-255 | -- | (padding) | 2 |

**Total: 30 bytes used, 2 bytes padding, 240/256 bits occupied.**

### Slot 1: Prize Pools (32/32 bytes -- FULL)

| Byte Range | Bit Range | Type | Variable | Bytes |
|------------|-----------|------|----------|-------|
| [0:16] | 0-127 | uint128 | currentPrizePool | 16 |
| [16:32] | 128-255 | uint128 | claimablePool | 16 |

**Total: 32 bytes used, 0 bytes padding, 256/256 bits occupied.**

### Slots 2-65: Full-Width Variables, Mappings, Arrays

| Slot | Type | Variable |
|------|------|----------|
| 2 | uint256 | prizePoolsPacked |
| 3 | uint256 | rngWordCurrent |
| 4 | uint256 | vrfRequestId |
| 5 | uint256 | totalFlipReversals |
| 6 | uint256 | dailyTicketBudgetsPacked |
| 7 | mapping(address => uint256) | claimableWinnings |
| 8 | mapping(uint24 => address[][256]) | traitBurnTicket |
| 9 | mapping(address => uint256) | mintPacked_ |
| 10 | mapping(uint32 => uint256) | rngWordByDay |
| 11 | uint256 | prizePoolPendingPacked |
| 12 | mapping(uint24 => address[]) | ticketQueue |
| 13 | mapping(uint24 => mapping(address => uint40)) | ticketsOwedPacked |
| 14 | uint32 + uint24 (packed) | ticketCursor, ticketLevel |
| 15 | mapping(uint48 => mapping(address => uint256)) | lootboxEth |
| 16 | uint256 | presaleStatePacked |
| 17 | uint256 | gameOverStatePacked |
| 18 | mapping(address => uint256) | whalePassClaims |
| 19 | mapping(address => AutoRebuyState) | autoRebuyState |
| 20 | uint256 | dailyJackpotTraitsPacked |
| 21 | mapping(uint48 => mapping(address => uint256)) | lootboxEthBase |
| 22 | mapping(address => mapping(address => bool)) | operatorApprovals |
| 23 | mapping(uint24 => uint256) | levelPrizePool |
| 24 | mapping(uint24 => mapping(address => bool)) | affiliateDgnrsClaimedBy |
| 25 | mapping(uint24 => uint256) | levelDgnrsAllocation |
| 26 | mapping(uint24 => uint256) | levelDgnrsClaimed |
| 27 | mapping(address => uint16) | deityPassPurchasedCount |
| 28 | mapping(address => uint256) | deityPassPaidTotal |
| 29 | address[] | deityPassOwners |
| 30 | mapping(address => uint8) | deityPassSymbol |
| 31 | mapping(uint8 => address) | deityBySymbol |
| 32 | uint256 | earlybirdDgnrsPoolStart |
| 33 | uint256 | earlybirdEthIn |
| 34 | uint128 | resumeEthPool |
| 35 | IVRFCoordinator (address) | vrfCoordinator |
| 36 | bytes32 | vrfKeyHash |
| 37 | uint256 | vrfSubscriptionId |
| 38 | uint256 | lootboxRngPacked |
| 39 | mapping(uint48 => uint256) | lootboxRngWordByIndex |
| 40 | mapping(uint48 => mapping(address => uint32)) | lootboxDay |
| 41 | mapping(uint48 => mapping(address => uint24)) | lootboxBaseLevelPacked |
| 42 | mapping(uint48 => mapping(address => uint16)) | lootboxEvScorePacked |
| 43 | mapping(uint48 => mapping(address => uint256)) | lootboxBurnie |
| 44 | mapping(address => uint32) | deityBoonDay |
| 45 | mapping(address => uint8) | deityBoonUsedMask |
| 46 | mapping(address => uint32) | deityBoonRecipientDay |
| 47 | mapping(address => mapping(uint64 => uint256)) | degeneretteBets |
| 48 | mapping(address => uint64) | degeneretteBetNonce |
| 49 | mapping(address => mapping(uint24 => uint256)) | lootboxEvBenefitUsedByLevel |
| 50 | mapping(uint24 => mapping(address => DecEntry)) | decBurn |
| 51 | mapping(uint24 => uint256[13][13]) | decBucketBurnTotal |
| 52 | mapping(uint24 => DecClaimRound) | decClaimRounds |
| 53 | mapping(uint24 => uint64) | decBucketOffsetPacked |
| 54 | mapping(uint32 => uint256[4]) | dailyHeroWagers |
| 55 | mapping(address => mapping(uint24 => uint256)) | playerDegeneretteEthWagered |
| 56 | mapping(uint24 => uint256) | topDegeneretteByLevel |
| 57 | mapping(uint48 => mapping(address => uint256)) | lootboxDistressEth |
| 58 | uint256 | yieldAccumulator |
| 59 | uint24 | centuryBonusLevel |
| 60 | mapping(address => uint256) | centuryBonusUsed |
| 61 | uint48 | lastVrfProcessedTimestamp |
| 62 | mapping(address => TerminalDecEntry) | terminalDecEntries |
| 63 | mapping(bytes32 => uint256) | terminalDecBucketBurnTotal |
| 64 | TerminalDecClaimRound | lastTerminalDecClaimRound |
| 65 | mapping(address => BoonPacked) | boonPacked |

## Layout Comparison

### Methodology

For each inheritor, `forge inspect <Contract> storageLayout --json` was executed and the output parsed. Each entry's slot number, byte offset within slot, semantic type (with compiler-internal AST IDs normalized away), and variable label were compared against the DegenerusGameStorage base layout.

Criteria for IDENTICAL verdict:
- Same number of storage entries (84)
- Every entry matches on: slot, offset, normalized type, label
- No extra storage variables appended by the inheritor

The Solidity compiler assigns different internal struct/interface AST IDs per compilation unit (e.g., `AutoRebuyState)2394` vs `AutoRebuyState)9976`). These IDs are metadata artifacts -- the underlying storage slot, offset, and semantic type are identical. All comparisons normalize these IDs before matching.

### Results

| Contract | Entries | Base Match | Extra Slots | Verdict |
|----------|--------:|:----------:|-------------|---------|
| DegenerusGameStorage (base) | 84 | -- | -- | REFERENCE |
| DegenerusGamePayoutUtils | 84 | Yes | None | IDENTICAL |
| DegenerusGameMintStreakUtils | 84 | Yes | None | IDENTICAL |
| DegenerusGameAdvanceModule | 84 | Yes | None | IDENTICAL |
| DegenerusGameJackpotModule | 84 | Yes | None | IDENTICAL |
| DegenerusGameMintModule | 84 | Yes | None | IDENTICAL |
| DegenerusGameWhaleModule | 84 | Yes | None | IDENTICAL |
| DegenerusGameDecimatorModule | 84 | Yes | None | IDENTICAL |
| DegenerusGameDegeneretteModule | 84 | Yes | None | IDENTICAL |
| DegenerusGameLootboxModule | 84 | Yes | None | IDENTICAL |
| DegenerusGameBoonModule | 84 | Yes | None | IDENTICAL |
| DegenerusGameGameOverModule | 84 | Yes | None | IDENTICAL |
| DegenerusGame | 84 | Yes | None | IDENTICAL |

All 12 inheritors match the base layout exactly. No inheritor adds, removes, or reorders any storage variable.

## Findings

No MISMATCH entries. Zero findings raised.

## Slot 0 Repack Verification

Slot 0 packs 17 variables into 30 of 32 available bytes (240 of 256 bits used).

| Field | Byte Offset | Bit Range | Type | Size |
|-------|-------------|-----------|------|------|
| purchaseStartDay | 0 | 0-31 | uint32 | 4 B |
| dailyIdx | 4 | 32-63 | uint32 | 4 B |
| rngRequestTime | 8 | 64-111 | uint48 | 6 B |
| level | 14 | 112-135 | uint24 | 3 B |
| jackpotPhaseFlag | 17 | 136-143 | bool | 1 B |
| jackpotCounter | 18 | 144-151 | uint8 | 1 B |
| lastPurchaseDay | 19 | 152-159 | bool | 1 B |
| decWindowOpen | 20 | 160-167 | bool | 1 B |
| rngLockedFlag | 21 | 168-175 | bool | 1 B |
| phaseTransitionActive | 22 | 176-183 | bool | 1 B |
| gameOver | 23 | 184-191 | bool | 1 B |
| dailyJackpotCoinTicketsPending | 24 | 192-199 | bool | 1 B |
| compressedJackpotFlag | 25 | 200-207 | uint8 | 1 B |
| ticketsFullyProcessed | 26 | 208-215 | bool | 1 B |
| gameOverPossible | 27 | 216-223 | bool | 1 B |
| ticketWriteSlot | 28 | 224-231 | bool | 1 B |
| prizePoolFrozen | 29 | 232-239 | bool | 1 B |
| (padding) | 30-31 | 240-255 | -- | 2 B |

**Verification:** All forge inspect outputs show identical slot 0 layout across all 13 contracts. Field boundaries are contiguous with no overlaps. The 2-byte padding at bytes 30-31 is unused and does not conflict with any variable.

No field straddles a byte boundary incorrectly. All bool fields occupy exactly 1 byte. The uint48 rngRequestTime correctly occupies 6 bytes at offset 8. The uint24 level correctly occupies 3 bytes at offset 14.

## Slot 1 Repack Verification

Slot 1 packs two uint128 variables into the full 32-byte slot.

| Field | Byte Offset | Bit Range | Type | Size |
|-------|-------------|-----------|------|------|
| currentPrizePool | 0 | 0-127 | uint128 | 16 B |
| claimablePool | 16 | 128-255 | uint128 | 16 B |

**Verification:** All forge inspect outputs show identical slot 1 layout across all 13 contracts. The two uint128 values are packed back-to-back with zero padding. The slot is fully utilized (32/32 bytes).

The uint128 maximum value (~3.4e38 wei, or ~3.4e20 ETH) far exceeds total ETH supply, providing adequate headroom for both prize pool and claimable pool accounting.

## Slot 14 Packing Note

Slot 14 contains two co-packed variables:
- `ticketCursor` (uint32, offset 0, 4 bytes)
- `ticketLevel` (uint24, offset 4, 3 bytes)

This packing is consistent across all 13 contracts. Total: 7 bytes used, 25 bytes padding.

## Diamond Inheritance Safety

DegenerusGameDegeneretteModule inherits from both DegenerusGamePayoutUtils and DegenerusGameMintStreakUtils, both of which independently inherit DegenerusGameStorage. Solidity's C3 linearization deduplicates DegenerusGameStorage in the inheritance chain, resulting in a single set of storage variables. The forge inspect output confirms 84 entries (not 168), proving no slot duplication from the diamond.

DegenerusGame also inherits DegenerusGameMintStreakUtils (which inherits DegenerusGameStorage), following the same pattern. 84 entries confirmed.

## Conclusion

Storage layout is **IDENTICAL** across all DegenerusGameStorage inheritors. All 13 contracts (1 base + 2 abstract utilities + 9 concrete modules + 1 main dispatcher) produce the same 84-entry storage layout with matching slots, offsets, types, and labels.

**Delegatecall safety is CONFIRMED.** When DegenerusGame delegates to any module, the module's code operates on the same storage slot mapping as the main contract. No slot collision, reordering, or type mismatch exists.

### Threat Mitigations

| Threat ID | Status | Evidence |
|-----------|--------|----------|
| T-214-14 (Storage layout mismatch) | MITIGATED | forge inspect comparison: 12/12 inheritors IDENTICAL to base |
| T-214-15 (Slot 0/1 repack correctness) | MITIGATED | Bit-level field boundary verification: slot 0 (240/256 bits, 17 fields, no overlap), slot 1 (256/256 bits, 2x uint128) |
