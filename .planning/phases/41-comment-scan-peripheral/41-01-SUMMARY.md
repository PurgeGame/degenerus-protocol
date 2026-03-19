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
