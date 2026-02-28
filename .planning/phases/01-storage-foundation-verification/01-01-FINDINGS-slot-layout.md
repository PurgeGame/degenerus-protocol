# Phase 1 Plan 01: Storage Slot Layout Verification Findings

**Date:** 2026-02-28
**Auditor tool:** `forge inspect --via-ir` (Foundry 1.3.5-stable)
**Scope:** All 10 delegatecall modules + DegenerusGame
**Method:** Compiler-verified storage layout extraction and slot-by-slot diff

---

## Section 1: Module Storage Layout Comparison Table

Each module's storage layout was extracted using `forge inspect --via-ir` and diffed against the DegenerusGame baseline. The diff compares Name, Slot, Offset, and Bytes columns for all 135 storage variables.

| # | Module | Inherits | Total Vars | Max Slot | Diff vs DegenerusGame | Verdict |
|---|--------|----------|-----------|----------|----------------------|---------|
| 1 | DegenerusGameMintModule | DegenerusGameStorage (direct) | 135 | 108 | Zero diff | **PASS** |
| 2 | DegenerusGameAdvanceModule | DegenerusGameStorage (direct) | 135 | 108 | Zero diff | **PASS** |
| 3 | DegenerusGameJackpotModule | DegenerusGamePayoutUtils | 135 | 108 | Zero diff | **PASS** |
| 4 | DegenerusGameEndgameModule | DegenerusGamePayoutUtils | 135 | 108 | Zero diff | **PASS** |
| 5 | DegenerusGameWhaleModule | DegenerusGameStorage (direct) | 135 | 108 | Zero diff | **PASS** |
| 6 | DegenerusGameLootboxModule | DegenerusGameStorage (direct) | 135 | 108 | Zero diff | **PASS** |
| 7 | DegenerusGameBoonModule | DegenerusGameStorage (direct) | 135 | 108 | Zero diff | **PASS** |
| 8 | DegenerusGameDecimatorModule | DegenerusGamePayoutUtils | 135 | 108 | Zero diff | **PASS** |
| 9 | DegenerusGameDegeneretteModule | DegenerusGamePayoutUtils + DegenerusGameMintStreakUtils | 135 | 108 | Zero diff | **PASS** |
| 10 | DegenerusGameGameOverModule | DegenerusGameStorage (direct) | 135 | 108 | Zero diff | **PASS** |

**Baseline:** DegenerusGame = 135 variables, max slot 108.

**Diamond inheritance note:** DegenerusGameDegeneretteModule inherits from both DegenerusGamePayoutUtils and DegenerusGameMintStreakUtils, each of which inherits DegenerusGameStorage. Solidity's C3 linearization correctly deduplicates the base -- `forge inspect` confirms 135 variables (not 270), identical to all other modules.

**Conclusion:** All 10 modules have identical storage layouts to DegenerusGame. No delegatecall storage corruption risk exists from layout divergence.

---

## Section 2: Canonical Slot Map

The following is the authoritative slot map for DegenerusGame and all 10 delegatecall modules, produced by `forge inspect --via-ir`. This is the single source of truth for all downstream phases.

### Slot 0 (32 bytes, fully packed -- no padding)

| Offset | Bytes | Name | Type |
|--------|-------|------|------|
| 0 | 6 | levelStartTime | uint48 |
| 6 | 6 | dailyIdx | uint48 |
| 12 | 6 | rngRequestTime | uint48 |
| 18 | 3 | level | uint24 |
| 21 | 2 | lastExterminatedTrait | uint16 |
| 23 | 1 | jackpotPhaseFlag | bool |
| 24 | 1 | jackpotCounter | uint8 |
| 25 | 1 | earlyBurnPercent | uint8 |
| 26 | 1 | levelJackpotPaid | bool |
| 27 | 1 | levelJackpotLootboxPaid | bool |
| 28 | 1 | lastPurchaseDay | bool |
| 29 | 1 | decWindowOpen | bool |
| 30 | 1 | rngLockedFlag | bool |
| 31 | 1 | exterminationInvertFlag | bool |

Total: 6+6+6+3+2+1+1+1+1+1+1+1+1+1 = 32 bytes (perfectly packed, zero padding)

### Slot 1 (21 bytes used, 11 bytes padding)

| Offset | Bytes | Name | Type |
|--------|-------|------|------|
| 0 | 1 | phaseTransitionActive | bool |
| 1 | 1 | gameOver | bool |
| 2 | 1 | dailyJackpotCoinTicketsPending | bool |
| 3 | 1 | dailyEthBucketCursor | uint8 |
| 4 | 1 | dailyEthPhase | uint8 |
| 5 | 16 | price | uint128 |

Total: 1+1+1+1+1+16 = 21 bytes used, 11 bytes padding

### Slots 2-108 (full-width and mappings)

| Slot | Name | Type | Bytes |
|------|------|------|-------|
| 2 | currentPrizePool | uint256 | 32 |
| 3 | nextPrizePool | uint256 | 32 |
| 4 | rngWordCurrent | uint256 | 32 |
| 5 | vrfRequestId | uint256 | 32 |
| 6 | totalFlipReversals | uint256 | 32 |
| 7 | dailyTicketBudgetsPacked | uint256 | 32 |
| 8 | dailyEthPoolBudget | uint256 | 32 |
| 9 | claimableWinnings | mapping(address => uint256) | 32 |
| 10 | claimablePool | uint256 | 32 |
| 11 | traitBurnTicket | mapping(uint24 => address[][256]) | 32 |
| 12 | mintPacked_ | mapping(address => uint256) | 32 |
| 13 | rngWordByDay | mapping(uint48 => uint256) | 32 |
| 14 | lastPurchaseDayFlipTotal | uint256 | 32 |
| 15 | lastPurchaseDayFlipTotalPrev | uint256 | 32 |
| 16 | levelJackpotWinningTraits | uint32 | 4 |
| 17 | levelJackpotEthPool | uint256 | 32 |
| 18 | futurePrizePool | uint256 | 32 |
| 19 | ticketQueue | mapping(uint24 => address[]) | 32 |
| 20 | ticketsOwedPacked | mapping(uint24 => mapping(address => uint40)) | 32 |
| 21 | ticketCursor (offset 0, 4B) + ticketLevel (offset 4, 3B) + dailyEthWinnerCursor (offset 7, 2B) | packed: uint32 + uint24 + uint16 | 9 |
| 22 | dailyCarryoverEthPool | uint256 | 32 |
| 23 | dailyCarryoverWinnerCap | uint16 | 2 |
| 24 | lootboxEth | mapping(uint48 => mapping(address => uint256)) | 32 |
| 25 | lootboxPresaleActive | bool | 1 |
| 26 | lootboxEthTotal | uint256 | 32 |
| 27 | lootboxPresaleMintEth | uint256 | 32 |
| 28 | gameOverTime (offset 0, 6B) + gameOverFinalJackpotPaid (offset 6, 1B) | packed: uint48 + bool | 7 |
| 29 | whalePassClaims | mapping(address => uint256) | 32 |
| 30 | coinflipBoonTimestamp | mapping(address => uint48) | 32 |
| 31 | lootboxBoon5Active | mapping(address => bool) | 32 |
| 32 | lootboxBoon5Timestamp | mapping(address => uint48) | 32 |
| 33 | lootboxBoon15Active | mapping(address => bool) | 32 |
| 34 | lootboxBoon15Timestamp | mapping(address => uint48) | 32 |
| 35 | lootboxBoon25Active | mapping(address => bool) | 32 |
| 36 | lootboxBoon25Timestamp | mapping(address => uint48) | 32 |
| 37 | whaleBoonDay | mapping(address => uint48) | 32 |
| 38 | whaleBoonDiscountBps | mapping(address => uint16) | 32 |
| 39 | activityBoonPending | mapping(address => uint24) | 32 |
| 40 | activityBoonTimestamp | mapping(address => uint48) | 32 |
| 41 | autoRebuyState | mapping(address => struct AutoRebuyState) | 32 |
| 42 | decimatorAutoRebuyDisabled | mapping(address => bool) | 32 |
| 43 | purchaseBoostBps | mapping(address => uint16) | 32 |
| 44 | purchaseBoostTimestamp | mapping(address => uint48) | 32 |
| 45 | _deprecated_ticketBoostBps | mapping(address => uint16) | 32 |
| 46 | _deprecated_ticketBoostTimestamp | mapping(address => uint48) | 32 |
| 47 | decimatorBoostBps | mapping(address => uint16) | 32 |
| 48 | coinflipBoonBps | mapping(address => uint16) | 32 |
| 49 | lastDailyJackpotWinningTraits (offset 0, 4B) + lastDailyJackpotLevel (offset 4, 3B) + lastDailyJackpotDay (offset 7, 6B) | packed: uint32 + uint24 + uint48 | 13 |
| 50 | lootboxEthBase | mapping(uint48 => mapping(address => uint256)) | 32 |
| 51 | operatorApprovals | mapping(address => mapping(address => bool)) | 32 |
| 52 | ethPerkLevel (offset 0, 3B) + ethPerkBurnCount (offset 3, 2B) + burniePerkLevel (offset 5, 3B) + burniePerkBurnCount (offset 8, 2B) + dgnrsPerkLevel (offset 10, 3B) + dgnrsPerkBurnCount (offset 13, 2B) | packed: uint24+uint16+uint24+uint16+uint24+uint16 | 15 |
| 53 | levelPrizePool | mapping(uint24 => uint256) | 32 |
| 54 | affiliateDgnrsClaimedBy | mapping(uint24 => mapping(address => bool)) | 32 |
| 55 | perkExpectedCount | uint24 | 3 |
| 56 | deityPassCount | mapping(address => uint16) | 32 |
| 57 | deityPassPurchasedCount | mapping(address => uint16) | 32 |
| 58 | deityPassPaidTotal | mapping(address => uint256) | 32 |
| 59 | deityPassOwners | address[] | 32 |
| 60 | deityPassSymbol | mapping(address => uint8) | 32 |
| 61 | deityBySymbol | mapping(uint8 => address) | 32 |
| 62 | earlybirdDgnrsPoolStart | uint256 | 32 |
| 63 | earlybirdEthIn | uint256 | 32 |
| 64 | vrfCoordinator | contract IVRFCoordinator | 20 |
| 65 | vrfKeyHash | bytes32 | 32 |
| 66 | vrfSubscriptionId | uint256 | 32 |
| 67 | lootboxRngIndex | uint48 | 6 |
| 68 | lootboxRngPendingEth | uint256 | 32 |
| 69 | lootboxRngThreshold | uint256 | 32 |
| 70 | lootboxRngMinLinkBalance | uint256 | 32 |
| 71 | lootboxRngWordByIndex | mapping(uint48 => uint256) | 32 |
| 72 | lootboxRngRequestIndexById | mapping(uint256 => uint48) | 32 |
| 73 | lootboxDay | mapping(uint48 => mapping(address => uint48)) | 32 |
| 74 | lootboxBaseLevelPacked | mapping(uint48 => mapping(address => uint24)) | 32 |
| 75 | lootboxEvScorePacked | mapping(uint48 => mapping(address => uint16)) | 32 |
| 76 | lootboxIndexQueue | mapping(address => uint48[]) | 32 |
| 77 | lootboxBurnie | mapping(uint48 => mapping(address => uint256)) | 32 |
| 78 | deityPassRefundable | mapping(address => uint256) | 32 |
| 79 | lootboxRngPendingBurnie | uint256 | 32 |
| 80 | deityBoonDay | mapping(address => uint48) | 32 |
| 81 | deityBoonUsedMask | mapping(address => uint8) | 32 |
| 82 | deityBoonRecipientDay | mapping(address => uint48) | 32 |
| 83 | deityCoinflipBoonDay | mapping(address => uint48) | 32 |
| 84 | deityLootboxBoon5Day | mapping(address => uint48) | 32 |
| 85 | deityLootboxBoon15Day | mapping(address => uint48) | 32 |
| 86 | deityLootboxBoon25Day | mapping(address => uint48) | 32 |
| 87 | deityPurchaseBoostDay | mapping(address => uint48) | 32 |
| 88 | _deprecated_deityTicketBoostDay | mapping(address => uint48) | 32 |
| 89 | deityDecimatorBoostDay | mapping(address => uint48) | 32 |
| 90 | deityWhaleBoonDay | mapping(address => uint48) | 32 |
| 91 | deityActivityBoonDay | mapping(address => uint48) | 32 |
| 92 | degeneretteBets | mapping(address => mapping(uint64 => uint256)) | 32 |
| 93 | degeneretteBetNonce | mapping(address => uint64) | 32 |
| 94 | deityPassBoonTier | mapping(address => uint8) | 32 |
| 95 | deityPassBoonTimestamp | mapping(address => uint48) | 32 |
| 96 | deityDeityPassBoonDay | mapping(address => uint48) | 32 |
| 97 | lootboxEvBenefitUsedByLevel | mapping(address => mapping(uint24 => uint256)) | 32 |
| 98 | decBurn | mapping(uint24 => mapping(address => struct DecEntry)) | 32 |
| 99 | decBucketBurnTotal | mapping(uint24 => uint256[13][13]) | 32 |
| 100-102 | lastDecClaimRound | struct LastDecClaimRound | 96 (3 slots) |
| 103 | decBucketOffsetPacked | mapping(uint24 => uint64) | 32 |
| 104 | lazyPassBoonDay | mapping(address => uint48) | 32 |
| 105 | lazyPassBoonDiscountBps | mapping(address => uint16) | 32 |
| 106 | dailyHeroWagers | mapping(uint48 => uint256[4]) | 32 |
| 107 | playerDegeneretteEthWagered | mapping(address => mapping(uint24 => uint256)) | 32 |
| 108 | topDegeneretteByLevel | mapping(uint24 => uint256) | 32 |

**Total: 135 storage variables, spanning slots 0 through 108.**

Note: Slot 100-102 is a single struct `LastDecClaimRound` occupying 3 consecutive slots (96 bytes). This is why 135 variables map to slot range 0-108 rather than 0-134 -- mappings and structs use hashed or multi-slot storage.

---

## Section 3: Requirement Verdicts

### STOR-01: No Module Instance Storage Variables -- **PASS**

**Requirement:** All 10 delegatecall modules must have identical storage layout to DegenerusGame. No module may declare instance storage variables outside the DegenerusGameStorage inheritance chain.

**Evidence:**
- `forge inspect --via-ir` reports exactly 135 storage variables for all 10 modules, identical to DegenerusGame
- All module-level declarations are `constant` or `private constant` (compile-time bytecode constants, not storage variables)
- JackpotModule defines `struct JackpotEthCtx` and `struct JackpotParams` at contract level -- these are type definitions only and occupy no storage slots
- Diamond inheritance in DegenerusGameDegeneretteModule (DegenerusGamePayoutUtils + DegenerusGameMintStreakUtils) is correctly deduplicated by C3 linearization -- no duplicate slots

**Verdict: PASS** -- No module declares instance storage variables. All storage comes exclusively from the DegenerusGameStorage inheritance chain.

### STOR-02: Storage Slot Ordering Matches forge inspect -- **PASS**

**Requirement:** Storage slot ordering in DegenerusGameStorage must match `forge inspect` output for all module contracts.

**Evidence:**
- `diff` of Name|Slot|Offset|Bytes columns between DegenerusGame and each of the 10 modules produces zero output for all 10 comparisons
- The canonical slot map (Section 2 above) is the compiler-verified authoritative reference
- Variable ordering in DegenerusGameStorage.sol source matches the forge inspect output exactly (variables are declared in slot order)

**Verdict: PASS** -- Slot ordering is identical across all 11 contracts. The delegatecall storage safety foundation is verified.

---

## Section 4: Documentation Findings

### F1 -- INFORMATIONAL: Stale NatSpec Slot Boundary Comments in DegenerusGameStorage.sol

**Severity:** Informational (documentation debt -- no runtime impact)
**Location:** `contracts/storage/DegenerusGameStorage.sol` lines 34-73

**Issue:** The NatSpec boundary table at the top of DegenerusGameStorage.sol describes an outdated storage layout that includes two removed `uint32` fields. Specifically:

| What NatSpec says | What forge inspect shows |
|-------------------|--------------------------|
| Slot 0 [18:22] = `(unused) uint32` (previously airdropTicketsProcessedCount) | Field does not exist -- `level` is at offset 18 |
| Slot 0 [22:26] = `(unused) uint32` (previously airdropIndex) | Field does not exist -- `lastExterminatedTrait` is at offset 21 |
| Slot 0 [26:29] = `level uint24` | Actual: `level` is at slot 0 offset 18 |
| Slot 0 [29:31] = `lastExterminatedTrait uint16` | Actual: offset 21 |
| Slot 0 [31:32] = `jackpotPhaseFlag bool` | Actual: offset 23 |
| Slot 1 starts with `jackpotCounter` | Actual: `jackpotCounter` is in slot 0 at offset 24 |
| Slot 1 occupies 13 bytes (19 padding) | Actual slot 1: 21 bytes used (11 padding), starts with `phaseTransitionActive` |
| Slot 2 = `price uint128` | Actual: `price` is in slot 1 at offset 5; slot 2 = `currentPrizePool uint256` |

**Root cause:** Two `uint32` fields (`airdropTicketsProcessedCount` and `airdropIndex`) were removed from the variable declarations at some point, but the NatSpec boundary table was not updated. Since the fields were removed (not just reordered), the EVM packs the remaining variables tighter. The variable declarations in source code are correct; only the comment prose is wrong.

**Impact:** None at runtime. The compiler uses variable declarations, not comments, to determine slot assignments. All 10 modules and DegenerusGame have identical correct layouts regardless of the stale comments.

**Recommendation:** Update the NatSpec boundary table in lines 34-73 to match the canonical slot map from `forge inspect` (Section 2 of this document). This eliminates a maintenance risk where future developers might rely on the stale comments and make incorrect assumptions about slot packing.

### F3 -- INFORMATIONAL: Misleading Comment on BURNIE_LOOTBOX_MIN

**Severity:** Informational (documentation confusion -- no runtime impact)
**Location:** `contracts/modules/DegenerusGameMintModule.sol` line 90

**Issue:** The NatSpec comment reads:
```
/// @dev BURNIE loot box minimum purchase amount (scaled for testnet).
uint256 private constant BURNIE_LOOTBOX_MIN = 1000 ether;
```

The comment says "scaled for testnet" but this is the **mainnet** contract file (under `contracts/`, not `contracts-testnet/`). The value `1000 ether` is denominated in BURNIE ERC-20 units (not ETH), and is the correct mainnet value. The testnet version in `contracts-testnet/` has the same value.

**Impact:** None at runtime. The constant value is correctly set. The comment creates documentation confusion by implying testnet-specific scaling in the mainnet codebase.

**Recommendation:** Remove "scaled for testnet" from the comment. Replace with: `/// @dev BURNIE loot box minimum purchase amount (in BURNIE ERC-20 units).`

---

## Section 5: Phase 2 Handoff Note -- rngLockedFlag Comment

**Variable:** `rngLockedFlag` (bool, slot 0 offset 30)
**Location:** `contracts/storage/DegenerusGameStorage.sol` line 241

**Comment in source:**
> "Set when daily VRF is requested, cleared when daily processing completes. Mid-day lootbox RNG does NOT set this flag. Used to block burns/opens during jackpot resolution window."

**Additionally (line 177-178):** The `rngRequestTime` comment states it "also serves as the RNG lock flag (replaces deprecated rngLockedFlag)."

**Observation:** The comment explicitly states that mid-day lootbox RNG does NOT set `rngLockedFlag`. This is relevant to Phase 2 requirement RNG-01 (VRF manipulation resistance), which must investigate whether the window between VRF fulfillment and `advanceGame` word consumption creates an exploitable nudge opportunity -- specifically whether lootbox VRF requests can be used to probe randomness timing without triggering the lock.

**Phase 1 verdict:** No finding raised. This is a Phase 2 investigation item. The storage layout itself is correct and consistent; the question is about the game logic that reads/writes this flag, which is outside Phase 1 scope.

**Action for Phase 2:** Investigate the full rngLockedFlag lifecycle: when it is set, when it is cleared, what operations it blocks, and whether the lootbox RNG exemption creates a timing window that a validator-level attacker could exploit. Also investigate the relationship with `rngRequestTime` which appears to have replaced some of rngLockedFlag's original purpose.

---

## Appendix: Verification Commands

All commands executed from `/home/zak/Dev/PurgeGame/degenerus-contracts/`.

**Baseline extraction:**
```bash
/home/zak/.foundry/bin/forge inspect --via-ir \
  contracts/DegenerusGame.sol:DegenerusGame storageLayout
```

**Per-module diff (example for MintModule; identical pattern for all 10):**
```bash
diff \
  <(/home/zak/.foundry/bin/forge inspect --via-ir \
      contracts/DegenerusGame.sol:DegenerusGame storageLayout 2>&1 \
      | grep "^|" | grep -v "^| Name\|^|--\|^+=" \
      | awk -F'|' '{print $2, $4, $5, $6}') \
  <(/home/zak/.foundry/bin/forge inspect --via-ir \
      contracts/modules/DegenerusGameMintModule.sol:DegenerusGameMintModule storageLayout 2>&1 \
      | grep "^|" | grep -v "^| Name\|^|--\|^+=" \
      | awk -F'|' '{print $2, $4, $5, $6}')
# Expected: no output (zero diff = PASS)
```

**Variable count per contract:**
```bash
/home/zak/.foundry/bin/forge inspect --via-ir \
  contracts/DegenerusGame.sol:DegenerusGame storageLayout 2>&1 \
  | grep "^|" | grep -v "^| Name\|^|--\|^+=" | wc -l
# Output: 135
```
