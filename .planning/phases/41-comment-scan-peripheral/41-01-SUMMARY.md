# Phase 41 Plan 01: Heavy-Change Peripheral Contracts -- Comment Audit

## BurnieCoinflip.sol

**Scope:** 1,114 lines | 62 NatSpec tags | ~125 comment lines | 14 external/public functions
**Changes since v3.1:** 68 lines changed (rngLocked removal from top-level claim guards, takeProfit function removal, NatSpec additions)
**v3.1 findings status:** CMT-072 through CMT-076 -- all 5 verified FIXED

### v3.1 Fix Verification

| v3.1 ID | Description | Status | Verification |
|---------|-------------|--------|-------------|
| CMT-072 | Unused JACKPOT_RESET_TIME constant | FIXED | Constant fully removed; no remaining references in comments or code |
| CMT-073 | depositCoinflip missing NatSpec for operator pattern | FIXED | Lines 223-227: @dev/@param now document operator-approved deposits with isOperatorApproved check |
| CMT-074 | _viewClaimableCoin vestigial "staking removed" comment | FIXED | Line 930: Comment now reads "Pending flip winnings within the claim window." -- vestigial phrase removed |
| CMT-075 | "RNG state" section comment for flipsClaimableDay | FIXED | Line 164: Now reads "Last resolved day -- claims can process up to this day" -- accurately describes the claim cursor |
| CMT-076 | _resolvePlayer reusing OnlyBurnieCoin() error | FIXED | Lines 1098-1106: _resolvePlayer now reverts with NotApproved(), consistent with _requireApproved |

### Findings

#### CMT-101: Unused TakeProfitZero error -- orphan from removed claimCoinflipsTakeProfit function

- **What:** The error `TakeProfitZero()` is declared at line 103 but is never referenced anywhere in the contract. It was previously used by the `claimCoinflipsTakeProfit` function which has been removed. The error declaration was left behind.
- **Where:** `BurnieCoinflip.sol:103`
- **Why:** A warden seeing an unused custom error would investigate whether validation logic was accidentally removed. The error name implies a zero-check on take-profit that no longer exists in any code path, inflating the perceived revert surface.
- **Suggestion:** Remove `error TakeProfitZero();` from the error declarations.
- **Category:** CMT
- **Severity:** INFO

#### CMT-102: claimCoinflips @dev says "claims from takeprofit (claimableStored)" but claimableStored accumulates from multiple sources

- **What:** The @dev for `claimCoinflips` at line 326 states "Processes resolved days and claims from takeprofit (claimableStored)." The parenthetical equating claimableStored with takeprofit is inaccurate. `claimableStored` accumulates from: (a) all winnings in non-auto-rebuy mode, (b) take-profit reserved amounts in auto-rebuy mode, and (c) carry flush when auto-rebuy is disabled. It is not exclusively takeprofit skimming. The same misleading language appears in `claimCoinflipsFromBurnie` at line 336 and `consumeCoinflipsForBurn` at line 348.
- **Where:** `BurnieCoinflip.sol:326`, `BurnieCoinflip.sol:336`, `BurnieCoinflip.sol:348`
- **Why:** A warden reading "claims from takeprofit (claimableStored)" would conclude that claimableStored only holds take-profit skimming amounts, and that non-auto-rebuy players have nothing in claimableStored. In reality, `settleFlipModeChange` (line 219) and `_depositCoinflip` (line 260) both accumulate ALL mintable amounts into claimableStored regardless of auto-rebuy status.
- **Suggestion:** Line 326: Change to "Processes resolved days and claims from accumulated balance (claimableStored)." Line 336: Same fix. Line 348: Change "only takeprofit is consumable" to "only accumulated balance (claimableStored) is consumable."
- **Category:** CMT
- **Severity:** INFO

#### CMT-103: IBurnieCoinflip.sol still annotates @custom:reverts RngLocked on 3 claim functions -- accurate but potentially misleading

- **What:** The interface IBurnieCoinflip.sol annotates `@custom:reverts RngLocked If VRF randomness is currently being resolved` on `claimCoinflips` (line 33), `claimCoinflipsFromBurnie` (line 42), and `consumeCoinflipsForBurn` (line 51). These annotations are technically correct -- the claim path CAN revert with RngLocked via the BAF leaderboard guard deep in `_claimCoinflipsInternal` (lines 555-562). However, the implementation no longer has a top-level rngLocked gate on claims. The revert only triggers when ALL of these conditions are simultaneously true: not in jackpot phase, game not over, last purchase day, rngLocked, and level divisible by 10. The interface annotation's unqualified "If VRF randomness is currently being resolved" overstates the revert surface.
- **Where:** `IBurnieCoinflip.sol:33`, `IBurnieCoinflip.sol:42`, `IBurnieCoinflip.sol:51`
- **Why:** A warden reading the interface would believe claims are blanket-blocked during any RNG resolution. The actual behavior is much narrower: only BAF-eligible claims at specific level boundaries during RNG lock. This is noted here for completeness but is an interface-side finding (will be formally audited in Plan 02).
- **Suggestion:** Qualify the annotation: `@custom:reverts RngLocked If BAF leaderboard credit would occur during VRF resolution at a BAF boundary level.` Or defer to Plan 02's interface audit.
- **Category:** CMT
- **Severity:** INFO

### Notes

- **rngLocked removal from claim entry:** Verified. The three claim functions (`claimCoinflips`, `claimCoinflipsFromBurnie`, `consumeCoinflipsForBurn`) no longer have a top-level `rngLocked()` check. The RngLocked revert still exists but only fires from the BAF section of `_claimCoinflipsInternal` under specific multi-condition circumstances.
- **claimCoinflipsTakeProfit removal:** Verified complete. Neither `claimCoinflipsTakeProfit` nor `_claimCoinflipsTakeProfit` exist in the contract. The only orphan is the unused `TakeProfitZero` error (CMT-101).
- **New NatSpec additions (depositCoinflip):** Lines 223-227 accurately document the operator pattern, parameter semantics, and deposit target resolution. @dev and @param tags match function behavior.
- **All other function NatSpec verified accurate:** settleFlipModeChange, processCoinflipPayouts, creditFlip, creditFlipBatch, previewClaimCoinflips, coinflipAmount, coinflipAutoRebuyInfo, coinflipTopLastDay, setCoinflipAutoRebuy, setCoinflipAutoRebuyTakeProfit -- all @notice/@dev/@param/@return/@custom:reverts tags match actual behavior.
- **Event NatSpec verified accurate:** CoinflipStakeUpdated, CoinflipDayResolved, CoinflipTopUpdated, BiggestFlipUpdated -- all @notice/@param tags match emitted values.
- **Internal function comments verified:** _claimCoinflipsInternal, _addDailyFlip, _setCoinflipAutoRebuy, _setCoinflipAutoRebuyTakeProfit, _coinflipLockedDuringTransition, _recyclingBonus, _afKingRecyclingBonus, _afKingDeityBonusHalfBpsWithLevel, _targetFlipDay, _questApplyReward, _score96, _updateTopDayBettor, _bafBracketLevel, _resolvePlayer, _requireApproved -- all @dev comments and inline comments accurately describe code behavior.
- **Section headers verified:** EVENTS, CUSTOM ERRORS, STORAGE VARIABLES, CONSTRUCTOR, MODIFIERS, CORE COINFLIP FUNCTIONS, CLAIM FUNCTIONS, STAKE MANAGEMENT, AUTO-REBUY FUNCTIONS, RNG PROCESSING, FLIP CREDITING, VIEW FUNCTIONS, INTERNAL HELPER FUNCTIONS -- all accurately reflect their contents.

---

## DegenerusQuests.sol

**Scope:** 1,588 lines | 248 NatSpec tags | ~143 comment lines | 11 external functions
**Changes since v3.1:** 28 lines changed (QUEST_TYPE_RESERVED removal, ID renumbering, NatSpec fixes)
**v3.1 findings status:** CMT-059 through CMT-064, DRIFT-004 -- all 7 verified FIXED

### v3.1 Fix Verification

| v3.1 ID | Description | Status | Verification |
|---------|-------------|--------|-------------|
| CMT-059 | Contract header says "COIN contract" only | FIXED | Line 16: Header now says "called by the Degenerus ContractAddresses.COIN and COINFLIP contracts" |
| CMT-060 | Security Model references nonexistent onlyCoinOrGame modifier | FIXED | Line 23: Security Model rewritten; no reference to onlyCoinOrGame; now says "COIN/COINFLIP-gated via `onlyCoin` modifier" |
| CMT-061 | Security Model says "COIN-gated" without clarifying COINFLIP | FIXED | Line 23: Now says "COIN/COINFLIP-gated via `onlyCoin` modifier" -- both callers documented |
| CMT-062 | rollDailyQuest @dev says "Slot 0 uses entropy" | FIXED | Line 299: Now says "Slot 0 is fixed to MINT_ETH (no entropy used)" -- accurately reflects the hardcoded slot 0 type |
| CMT-063 | OnlyCoin error/modifier name implies COIN-only | FIXED | Line 53: Error @notice says "COIN or COINFLIP"; Line 279: Modifier @dev says "COIN or COINFLIP contract" |
| CMT-064 | _questComplete NatSpec says "all slots finish" | FIXED | Line 1360: Now says "credits streak on slot 0 completion" -- accurate because slot 1 requires slot 0 first (guards at lines 570, 623, 674, 728, 1081) |
| DRIFT-004 | QUEST_TYPE_RESERVED vestigial constant | FIXED | Constant fully removed; no remaining references to "QUEST_TYPE_RESERVED" or "reserved" in comments or code; _bonusQuestType no longer has a skip guard for it |

### Quest Type ID Renumbering Audit

QUEST_TYPE_RESERVED (old ID 4) was removed, causing all subsequent IDs to shift down by 1:
- DECIMATOR: 5 -> 4
- LOOTBOX: 6 -> 5
- DEGENERETTE_ETH: 7 -> 6
- DEGENERETTE_BURNIE: 8 -> 7
- QUEST_TYPE_COUNT: 9 -> 8

**Renumbering audit result:** No stale hardcoded quest type ID numbers found in any comments or NatSpec. All references use constant names (QUEST_TYPE_MINT_BURNIE, QUEST_TYPE_FLIP, etc.) rather than numeric IDs. No references to "9 quest types" or "nine quest" remain. The `_bonusQuestType` function correctly iterates 0 to QUEST_TYPE_COUNT (8) with no RESERVED skip. Clean renumbering.

### Findings

No new findings identified.

All 248 NatSpec tags verified accurate. All handler functions (handleMint, handleFlip, handleDecimator, handleAffiliate, handleLootBox, handleDegenerette) have complete and accurate @notice/@dev/@param/@return/@custom:reverts annotations. The contract header's Architecture Overview, Security Model, Quest Lifecycle, Progress Versioning, and Streak System sections all accurately describe current behavior. Struct documentation (DailyQuest, PlayerQuestState) accurately reflects field semantics including completion mask layout. Internal helper NatSpec (_questSyncState, _questSyncProgress, _questComplete, _questCompleteWithPair, _bonusQuestType, _canRollDecimatorQuest, _questTargetValue, _questRequirements, _questViewData, _questHandleProgressSlot, _questProgressValid, _questProgressValidStorage, _questCompleted, _questReady, _maybeCompleteOther, _seedQuestType, _currentQuestDay, _clampedAdd128, _nextQuestVersion, _materializeActiveQuestsForView) all verified. Section headers accurately reflect their contents. Event NatSpec verified. Error NatSpec verified (OnlyCoin now correctly says "COIN or COINFLIP", OnlyGame accurate).

---

## DegenerusJackpots.sol

**Scope:** 689 lines | 76 NatSpec tags | ~115 comment lines | 3 external functions
**Changes since v3.1:** 14 lines changed (BurnieCoin->BurnieCoinflip reference fixes)
**v3.1 findings status:** CMT-065 through CMT-069 -- 4 verified FIXED, 1 over-corrected (CMT-068)

### v3.1 Fix Verification

| v3.1 ID | Description | Status | Verification |
|---------|-------------|--------|-------------|
| CMT-065 | Contract-level @dev says "BurnieCoin forwards flips" | FIXED | Line 35: Now says "BurnieCoinflip forwards flips into this contract" -- accurate |
| CMT-066 | Section header says "Called by BurnieCoin" | FIXED | Line 164: Now says "Called by BurnieCoinflip to record coinflip activity" -- accurate |
| CMT-067 | recordBafFlip @dev/@custom:access say "coin contract" | FIXED | Line 169: @dev says "coinflip contract"; Line 173: @custom:access says "coinflip contract" -- both accurate for the actual caller |
| CMT-068 | OnlyCoin error says "restricted to the coin contract" | OVER-CORRECTED | Line 47: Now says "restricted to the coinflip contract" (singular) -- but the `onlyCoin` modifier (line 150) accepts BOTH ContractAddresses.COIN and ContractAddresses.COINFLIP. Fix swung from one inaccuracy to the opposite (see CMT-104 below) |
| CMT-069 | IDegenerusCoinJackpotView @notice says "coin contract" | FIXED | Line 19: Now says "coinflip contract jackpot-related queries" -- accurate since the interface targets ContractAddresses.COINFLIP |

### Findings

#### CMT-104: OnlyCoin error @notice says "restricted to the coinflip contract" but modifier accepts both COIN and COINFLIP

- **What:** The `OnlyCoin` error @notice at line 47 states "Thrown when a function restricted to the coinflip contract is called by another address." The `onlyCoin` modifier (lines 149-151) checks `msg.sender != ContractAddresses.COIN && msg.sender != ContractAddresses.COINFLIP`, accepting both contracts. Saying "restricted to the coinflip contract" (singular) omits COIN. The v3.1 fix for CMT-068 changed this from "coin contract" to "coinflip contract" but swung to the opposite inaccuracy. The modifier's own @dev at line 147 correctly says "Restricts function to coin or coinflip contract."
- **Where:** `DegenerusJackpots.sol:47`
- **Why:** A warden reading the error description would believe only BurnieCoinflip is authorized. If BurnieCoin.sol were to call a function gated by `onlyCoin`, the error message would mislead debugging (the error says "coinflip" when the check allows both). The modifier @dev is correct, but the error @notice is the user-facing documentation most tools and wardens parse first.
- **Suggestion:** Change to "Thrown when a function restricted to the coin or coinflip contract is called by another address." This matches the modifier @dev at line 147 and the actual implementation.
- **Category:** CMT
- **Severity:** INFO

### Notes

- **BurnieCoin->BurnieCoinflip fixes verified complete:** Grep for `BurnieCoin[^f]` (BurnieCoin not followed by "flip") returns zero matches. All references correctly use "BurnieCoinflip" or "coinflip contract."
- **Prize distribution percentages verified:** 10% (top BAF) + 5% (top flip) + 5% (random 3rd/4th) + 5% (far-future draw 1) + 5% (far-future draw 2) + 45% (scatter 1st) + 25% (scatter 2nd) = 100%. Block comment at lines 196-214 accurate.
- **PlayerScore struct packing verified:** address (160 bits) + uint96 score = 256 bits per slot. Line 78 @dev is accurate.
- **All function NatSpec verified accurate:** recordBafFlip, runBafJackpot, getLastBafResolvedDay -- all @notice/@dev/@param/@return/@custom:access tags match actual behavior. runBafJackpot @dev correctly documents winner array sizing (107 max), entropy chaining, and level targeting.
- **Internal helper NatSpec verified:** _creditOrRefund, _bafScore, _score96, _updateBafTop, _bafTop, _clearBafTop -- all @dev/@param/@return tags accurate.
- **Event NatSpec verified:** BafFlipRecorded -- all @param tags match emitted values.
- **Section headers verified:** ERRORS, EVENTS, STRUCTS, CONSTANT STATE, CONSTANTS, BAF STATE STORAGE, MODIFIERS & ACCESS CONTROL, COINFLIP CONTRACT HOOKS, BAF JACKPOT RESOLUTION, INTERNAL HELPER FUNCTIONS, BAF LEADERBOARD HELPERS, VIEW FUNCTIONS -- all accurately reflect their contents.
- **Scatter level targeting comments verified:** Lines 399-416 inline comments accurately describe both non-century and century BAF targeting patterns.

---

## Plan 01 Summary

| Contract | Lines | v3.1 Findings Verified | New Findings | Total |
|----------|-------|----------------------|--------------|-------|
| BurnieCoinflip.sol | 1,114 | 5 fixed, 0 partial | 3 (CMT-101, CMT-102, CMT-103) | 3 |
| DegenerusQuests.sol | 1,588 | 7 fixed, 0 partial | 0 | 0 |
| DegenerusJackpots.sol | 689 | 4 fixed, 1 over-corrected | 1 (CMT-104) | 1 |
| **Total** | **3,391** | **16 fixed, 1 over-corrected** | **4** | **4** |

**Notes:**
- CMT-103 is an interface-side finding on IBurnieCoinflip.sol (will be formally audited in Plan 02); included here because it was discovered during implementation-side review.
- CMT-104 is the over-correction of v3.1 CMT-068: the fix changed "coin contract" to "coinflip contract" instead of "coin or coinflip contract."
- No .sol files were modified during this audit.

## Self-Check: PASSED

- 41-01-SUMMARY.md: FOUND
- Task 1 commit ad02a609: FOUND
- Task 2 commit 6b808721: FOUND
