---
phase: 41-comment-scan-peripheral
plan: 02
subsystem: audit
tags: [solidity, natspec, comment-audit, interface-parity, rngLocked, decimator-expiry]

requires:
  - phase: 41-comment-scan-peripheral
    provides: "41-RESEARCH.md with v3.1 findings status table and pre-identified findings"
provides:
  - "Comment audit findings for DegenerusVault, DegenerusAffiliate, IBurnieCoinflip, IDegenerusGame"
  - "9 new findings (CMT-201 through CMT-209) including 3 HIGH-probability stale RngLocked annotations"
  - "v3.1 fix verification: 3 fully fixed, 1 partially fixed (CMT-078)"
affects: [41-comment-scan-peripheral, consolidated-findings]

tech-stack:
  added: []
  patterns: [interface-implementation-cross-reference-table, per-contract-scope-header]

key-files:
  created:
    - ".planning/phases/41-comment-scan-peripheral/41-02-SUMMARY.md"
  modified: []

key-decisions:
  - "CMT-201: Classified _transfer plural 'checks' as INFO since from==address(0) is unreachable in normal operation"
  - "CMT-202/203/204: Classified stale RngLocked as LOW since wardens would file false findings based on interface docs"
  - "CMT-207: Classified purchaseDeityPass phantom useBoon parameter as LOW due to API surface confusion"
  - "PRNG design note on DegenerusAffiliate verified accurate -- no finding needed"

patterns-established:
  - "Interface-implementation NatSpec cross-reference table format for systematic verification"

requirements-completed: [CMT-04, CMT-05]

duration: 7min
completed: 2026-03-19
---

# Phase 41 Plan 02: Light-Change Peripheral + Interfaces -- Comment Audit

**9 findings across 4 contracts (2,514 lines): 3 stale RngLocked on IBurnieCoinflip claim functions, 5 IDegenerusGame NatSpec gaps/staleness, 1 DegenerusVault plural zero-address check from v3.1 partial fix**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-19T13:24:11Z
- **Completed:** 2026-03-19T13:31:13Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Verified 4 v3.1 findings: 3 fully fixed (CMT-070, CMT-071, CMT-077), 1 partially fixed (CMT-078)
- Identified 3 stale @custom:reverts RngLocked annotations on IBurnieCoinflip claim functions (highest-value findings)
- Completed full interface-implementation NatSpec cross-reference for all 14 IBurnieCoinflip functions and 72 IDegenerusGame functions
- Verified DegenerusAffiliate PRNG design note accurately characterizes the EV-neutral weighted random mechanism
- Confirmed clean removal of claimCoinflipsTakeProfit and futurePrizePoolTotalView across all contracts

## Task Commits

Each task was committed atomically:

1. **Task 1: Audit DegenerusVault.sol and DegenerusAffiliate.sol comments** - `7906efd4` (docs)
2. **Task 2: Audit IBurnieCoinflip.sol and IDegenerusGame.sol interface comments** - `10b83db2` (docs)

## Files Created/Modified
- `.planning/phases/41-comment-scan-peripheral/41-02-SUMMARY.md` - Comment audit findings for 4 contracts

## Decisions Made
- Classified DegenerusAffiliate PRNG design note as accurate (no finding) after verifying EV-neutrality and redistributive-only manipulation property
- Used CMT-201 through CMT-209 numbering (Plan 02 series) to avoid collision with Plan 01 numbering

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Plan 03 (remaining/utility contracts) can proceed immediately
- CMT numbering should continue from CMT-210 in Plan 03

## DegenerusVault.sol

**Scope:** 1,050 lines | 281 NatSpec tags | 363 comment lines | 30 external/public functions (5 DegenerusVaultShare + 25 DegenerusVault)
**Changes since v3.1:** 17 lines changed (AFK->afKing, takeProfit removal, transferFrom @custom:reverts fix)
**v3.1 findings status:** CMT-077 FIXED, CMT-078 PARTIALLY FIXED

### v3.1 Fix Verification

**CMT-077 (line 662):** FIXED. `@notice` now says "afKing mode" instead of "AFK king mode". The `@param` descriptions correctly reference afKing mode settings. No remaining "AFK" references in the file.

**CMT-078 (line 236):** PARTIALLY FIXED. The `transferFrom` `@custom:reverts` tag was corrected to say `ZeroAddress If to is address(0)` (removing the false `from` claim). However, the `_transfer` `@dev` at line 286 still says "zero-address checks" (plural), implying both `from` and `to` are validated. The implementation only checks `to` (line 291). See CMT-201 below.

### Code Change Verification

**AFK->afKing rename:** No remaining "AFK" references anywhere in DegenerusVault.sol. Clean rename.

**claimCoinflipsTakeProfit removal:** The `coinClaimCoinflipsTakeProfit` function and the `claimCoinflipsTakeProfit` declaration in the inner `ICoinflipPlayerActions` interface are both cleanly removed. No remaining references to `claimCoinflipsTakeProfit` in comments or code. The remaining `takeProfit` references (lines 37, 41, 42, 58, 59, 648, 650, 663, 664, 668, 669, 706, 708, 713, 715) are all legitimate -- they relate to `setAutoRebuyTakeProfit`, `setCoinflipAutoRebuyTakeProfit`, and `setAfKingMode` parameters which still exist.

**ICoinflipPlayerActions parity:** The inner interface defined at lines 54-60 declares 5 functions: `depositCoinflip`, `claimCoinflips`, `previewClaimCoinflips`, `setCoinflipAutoRebuy`, `setCoinflipAutoRebuyTakeProfit`. All 5 match the actual IBurnieCoinflip.sol function signatures (parameter names, types, return values).

### Full NatSpec Audit

All 30 external/public functions were reviewed. @notice descriptions match function behavior. @param tags match parameter names and types. @return tags match return values. @custom:reverts tags accurately list revert conditions for all functions.

The contract header block comment (lines 72-129) accurately describes the architecture: two asset types, two independent share classes (DGVE for ETH+stETH, DGVB for BURNIE), deposit flow, claim flow, and refill mechanism. All invariants documented in the header hold true in the implementation.

### Findings

#### CMT-201: _transfer @dev says "zero-address checks" (plural) but only `to` is checked

- **What:** The `_transfer` function's `@dev` at line 286 says "Internal transfer logic with balance and zero-address checks" -- the plural "checks" implies both `from` and `to` addresses are validated against `address(0)`. The implementation only checks `to` (line 291: `if (to == address(0)) revert ZeroAddress()`). No check exists for `from == address(0)`.
- **Where:** `DegenerusVault.sol:286`
- **Why:** A warden verifying the revert surface would expect `_transfer(address(0), validAddr, amount)` to revert with `ZeroAddress`, but it would instead succeed (deducting from address(0)'s balance, which is typically zero, so it would revert with `Insufficient` instead). The plural phrasing overstates the validation. This is the remaining half of v3.1 finding CMT-078 that was not addressed.
- **Suggestion:** Change "zero-address checks" to "zero-address check" (singular) or "destination zero-address check" to accurately reflect that only `to` is validated.
- **Category:** CMT
- **Severity:** INFO

---

## DegenerusAffiliate.sol

**Scope:** 848 lines | 128 NatSpec tags | 166 comment lines | 11 external/public functions
**Changes since v3.1:** 5 lines changed (taper values fix, batch comment fix, PRNG design note)
**v3.1 findings status:** CMT-070 FIXED, CMT-071 FIXED

### v3.1 Fix Verification

**CMT-070 (line 383):** FIXED. The `@param lootboxActivityScore` now correctly says "10000+ triggers linear taper to 25% floor at 25500". This matches the code constants: `LOOTBOX_TAPER_START_SCORE = 10_000`, `LOOTBOX_TAPER_END_SCORE = 25_500`, `LOOTBOX_TAPER_MIN_BPS = 2_500` (25% floor). The block comment in the REWARD FLOW section (lines 374-376) also correctly documents these values. No internal contradiction remains.

**CMT-071 (line 546):** FIXED. The inline comment now says "Collect recipients for weighted random winner selection (gas efficient vs 3 separate credits)." This accurately describes the mechanism: recipients and amounts are collected, then `_rollWeightedAffiliateWinner` picks a single winner with probability proportional to their share.

### Code Change Verification

**PRNG design note (line 547):** The new inline comment reads: "PRNG is known -- accepted design tradeoff (EV-neutral, manipulation only redistributive between affiliates)."

Verification:
- **(a) Is the PRNG known/deterministic?** YES. The function `_rollWeightedAffiliateWinner` (line 815) uses `keccak256(abi.encodePacked(AFFILIATE_ROLL_TAG, currentDay, sender, storedCode))`. All inputs are on-chain and predictable: the tag is a constant, `currentDay` is derived from `block.timestamp`, `sender` and `storedCode` are known to the caller. A sophisticated actor could predict the outcome.
- **(b) Is it EV-neutral?** YES. The winner receives `totalAmount` (the sum of all recipients' shares). Each recipient's probability equals `amount_i / totalAmount`, so their expected value is `amount_i` -- identical to what they would receive if each were credited separately.
- **(c) Is manipulation only redistributive between affiliates?** SUBSTANTIALLY YES. A manipulator who knows the PRNG output could time their transactions to bias which affiliate tier (direct, upline1, upline2) wins the roll. However, the total payout amount is fixed (determined by the purchase amount and reward scaling), so manipulation cannot extract additional value from the system. It can only shift winnings between the 3 affiliate tiers. The comment is accurate.

No finding needed for the PRNG design note -- it accurately characterizes the mechanism.

### Full NatSpec Audit

All 11 external/public functions and 9 private/internal functions were reviewed. @notice descriptions match function behavior. @param tags match parameter names and types. @return tags match return values. Event NatSpec (5 events) accurately describes emission context and parameter semantics. Error NatSpec (4 errors) accurately describes trigger conditions.

The contract header block comment (lines 8-25) accurately describes the architecture: 3-tier referral, kickback, reward rates, leaderboard tracking. The REWARD FLOW block comment within `payAffiliate` (lines 355-365) accurately documents the full payout pipeline. All reward rate constants match the documented percentages.

### Findings

No new findings identified. All v3.1 findings verified fixed. New PRNG design note is accurate.

---

## IBurnieCoinflip.sol

**Scope:** 173 lines | 82 NatSpec tags | 14 function declarations
**Changes since v3.1:** 14 lines removed (claimCoinflipsTakeProfit removal)
**Known issue:** 3 stale @custom:reverts RngLocked annotations (pre-identified in research)

### Code Change Verification

**claimCoinflipsTakeProfit removal:** Cleanly removed from the interface. No remaining references to `claimCoinflipsTakeProfit` or `TakeProfit` as a standalone function concept. The `takeProfit` parameter references on `setCoinflipAutoRebuy` (line 60) and `setCoinflipAutoRebuyTakeProfit` (line 73) are legitimate and still exist in the implementation.

### Interface-Implementation Cross-Reference

Every function declaration in IBurnieCoinflip.sol was cross-referenced against BurnieCoinflip.sol:

| Function | @param match | @return match | @custom:reverts accurate | @notice accurate |
|----------|:---:|:---:|:---:|:---:|
| `depositCoinflip` | YES | N/A | YES (AmountLTMin, CoinflipLocked, NotApproved) | YES |
| `claimCoinflips` | YES | YES | **NO** (stale RngLocked) | YES |
| `claimCoinflipsFromBurnie` | YES | YES | **NO** (stale RngLocked) | YES |
| `consumeCoinflipsForBurn` | YES | YES | **NO** (stale RngLocked) | YES |
| `setCoinflipAutoRebuy` | YES | N/A | YES (RngLocked, AutoRebuyAlreadyEnabled, NotApproved) | YES |
| `setCoinflipAutoRebuyTakeProfit` | YES | N/A | YES (RngLocked, AutoRebuyNotEnabled, NotApproved) | YES |
| `settleFlipModeChange` | YES | N/A | YES (OnlyDegenerusGame) | YES |
| `processCoinflipPayouts` | YES | N/A | YES (OnlyDegenerusGame) | YES |
| `creditFlip` | YES | N/A | YES (OnlyFlipCreditors) | YES |
| `creditFlipBatch` | YES | N/A | YES (OnlyFlipCreditors) | YES |
| `previewClaimCoinflips` | YES | YES | N/A | YES |
| `coinflipAmount` | YES | YES | N/A | YES |
| `coinflipAutoRebuyInfo` | YES | YES | N/A | YES |
| `coinflipTopLastDay` | N/A | YES | N/A | YES |

**Result:** 3 functions have stale `@custom:reverts` annotations. All other NatSpec is accurate.

### Findings

#### CMT-202: Stale @custom:reverts RngLocked on claimCoinflips

- **What:** Interface declares `@custom:reverts RngLocked If VRF randomness is currently being resolved` but the implementation (BurnieCoinflip.sol `claimCoinflips` at line 328) no longer checks `rngLocked()` on this function. The `rngLocked()` check was removed as part of the rngLocked removal refactor. The claim function now uses BAF epoch-based protection exclusively.
- **Where:** `IBurnieCoinflip.sol:33`
- **Why:** A warden reading the interface would expect `RngLocked` to be a valid revert condition and might file a false finding based on it, or miss that the actual claim protection is now BAF epoch-based only.
- **Suggestion:** Remove `@custom:reverts RngLocked If VRF randomness is currently being resolved` from the NatSpec.
- **Category:** CMT
- **Severity:** LOW

#### CMT-203: Stale @custom:reverts RngLocked on claimCoinflipsFromBurnie

- **What:** Interface declares `@custom:reverts RngLocked If VRF randomness is currently being resolved` but the implementation (BurnieCoinflip.sol `claimCoinflipsFromBurnie` at line 339) no longer checks `rngLocked()` on this function. The `rngLocked()` check was removed as part of the rngLocked removal refactor.
- **Where:** `IBurnieCoinflip.sol:42`
- **Why:** A warden reading the interface would expect `RngLocked` to be a valid revert condition and might file a false finding based on it, or miss that the actual claim protection is now BAF epoch-based only.
- **Suggestion:** Remove `@custom:reverts RngLocked If VRF randomness is currently being resolved` from the NatSpec.
- **Category:** CMT
- **Severity:** LOW

#### CMT-204: Stale @custom:reverts RngLocked on consumeCoinflipsForBurn

- **What:** Interface declares `@custom:reverts RngLocked If VRF randomness is currently being resolved` but the implementation (BurnieCoinflip.sol `consumeCoinflipsForBurn` at line 349) no longer checks `rngLocked()` on this function. The `rngLocked()` check was removed as part of the rngLocked removal refactor.
- **Where:** `IBurnieCoinflip.sol:51`
- **Why:** A warden reading the interface would expect `RngLocked` to be a valid revert condition and might file a false finding based on it, or miss that the actual claim protection is now BAF epoch-based only.
- **Suggestion:** Remove `@custom:reverts RngLocked If VRF randomness is currently being resolved` from the NatSpec.
- **Category:** CMT
- **Severity:** LOW

---

## IDegenerusGame.sol

**Scope:** 443 lines | 221 NatSpec tags | 72 function declarations
**Changes since v3.1:** 4 lines removed (futurePrizePoolTotalView removal)

### Code Change Verification

**futurePrizePoolTotalView removal:** Cleanly removed from the interface. Grep across all contracts confirms zero remaining references to `futurePrizePoolTotalView` or `futurePrizePoolTotal`. The single-pool `futurePrizePoolView` (line 150) remains and is correctly documented.

### Interface-Implementation Cross-Reference

All 72 function declarations in IDegenerusGame.sol were reviewed against DegenerusGame.sol. Parameter names, types, and return values match across all functions. The following specific issues were identified:

### Findings

#### CMT-205: Stale "or expired" in decClaimable @return after decimator claim expiry removal

- **What:** The `decClaimable` function's `@return amountWei` at line 244 says "Claimable amount (0 if not winner, already claimed, or expired)." The "or expired" condition is stale -- decimator claim expiry was removed in commit `19f5bc60` ("feat: remove decimator claim expiry -- claims persist across rounds"). The implementation at DegenerusGame.sol:1310 says "(0 if not winner or already claimed)" without "expired".
- **Where:** `IDegenerusGame.sol:244`
- **Why:** A warden reading the interface would believe there is a time-based expiry on decimator claims and might investigate the expiry logic. Since claims now persist indefinitely, the "expired" qualifier is misleading.
- **Suggestion:** Change to `Claimable amount (0 if not winner or already claimed).` to match the implementation NatSpec.
- **Category:** CMT
- **Severity:** INFO

#### CMT-206: Duplicate @notice on resolveDegeneretteBets -- stale "Place" notice from copy-paste

- **What:** The `resolveDegeneretteBets` function at lines 324-325 has two consecutive `@notice` tags. The first (`@notice Place Full Ticket Degenerette bets using pending affiliate Degenerette credit.`) appears to be a leftover from the `placeFullTicketBets` function above it. The second (`@notice Resolve Degenerette bets once RNG is available.`) is correct.
- **Where:** `IDegenerusGame.sol:324`
- **Why:** The stale @notice is confusing -- `resolveDegeneretteBets` resolves existing bets, it does not place new ones. A warden or developer would see contradictory descriptions of the same function.
- **Suggestion:** Remove line 324 (`/// @notice Place Full Ticket Degenerette bets using pending affiliate Degenerette credit.`), keeping only the correct `@notice Resolve Degenerette bets once RNG is available.`
- **Category:** CMT
- **Severity:** INFO

#### CMT-207: purchaseDeityPass @dev says "Two modes" but only documents one

- **What:** The `purchaseDeityPass` function's `@dev` at line 384 says "Two modes:" but only lists one mode ("Presale (useBoon=false): During presale only, level 1, fixed 25 ETH price."). The second mode (boon-based purchase outside presale with escalating pricing) is not documented. Additionally, the `useBoon` parameter referenced in the text does not exist in the function signature -- the function signature is `purchaseDeityPass(address buyer, uint8 symbolId)`.
- **Where:** `IDegenerusGame.sol:384-385`
- **Why:** Incomplete NatSpec with a phantom parameter reference (`useBoon`) misleads wardens about the function's behavior and API surface.
- **Suggestion:** Either complete the second mode description and remove the `useBoon` reference (since mode is determined by game state, not a parameter), or simplify to a single accurate description of the purchase flow.
- **Category:** CMT
- **Severity:** LOW

#### CMT-208: Three terminal decimator functions lack NatSpec in the interface

- **What:** Three functions in the "Terminal Decimator (Death Bet)" section (lines 206-218) have no NatSpec at all in the interface: `recordTerminalDecBurn`, `runTerminalDecimatorJackpot`, and `terminalDecWindow`. The implementations in DegenerusGame.sol (lines 1188, 1208, 1231) all have `@notice` and `@dev` annotations.
- **Where:** `IDegenerusGame.sol:206-218`
- **Why:** Interface files are the primary documentation surface for external integrators. Missing NatSpec on 3 functions means tooling that generates documentation from the interface will have gaps. The section header comment ("Terminal Decimator (Death Bet)") provides some context, but no per-function documentation exists.
- **Suggestion:** Copy the NatSpec from the implementation to the interface declarations, adding `@param` and `@return` tags as appropriate.
- **Category:** CMT
- **Severity:** INFO

#### CMT-209: Four Degenerette tracking view functions lack NatSpec in the interface

- **What:** Four functions in the "Degenerette Tracking Views" section (lines 439-442) have no NatSpec: `getDailyHeroWager`, `getDailyHeroWinner`, `getPlayerDegeneretteWager`, and `getTopDegenerette`. The implementations in DegenerusGame.sol (lines 2749-2803) have full `@param` and `@return` annotations.
- **Where:** `IDegenerusGame.sol:439-442`
- **Why:** These view functions are the primary API for UI/tooling integration. Missing NatSpec means integrators must read the implementation to understand parameter semantics and return value formats (e.g., `wagerUnits` is in 1e12 wei units, not raw wei).
- **Suggestion:** Copy the NatSpec from the implementation to the interface declarations.
- **Category:** CMT
- **Severity:** INFO

---

## Plan 02 Summary

| Contract | Lines | v3.1 Findings Verified | New Findings | Total |
|----------|-------|----------------------|--------------|-------|
| DegenerusVault.sol | 1,050 | 1 fixed, 1 partial | 1 (CMT-201) | 1 |
| DegenerusAffiliate.sol | 848 | 2 fixed | 0 | 0 |
| IBurnieCoinflip.sol | 173 | N/A (no v3.1 findings) | 3 (CMT-202/203/204) | 3 |
| IDegenerusGame.sol | 443 | N/A (no v3.1 findings) | 5 (CMT-205/206/207/208/209) | 5 |
| **Total** | **2,514** | **3 fixed, 1 partial** | **9** | **9** |

---

## Self-Check: PASSED

- SUMMARY file exists: FOUND
- Task 1 commit (7906efd4): FOUND
- Task 2 commit (10b83db2): FOUND
- All 4 contract sections present: FOUND
- Summary table present: FOUND
- Finding count: 9 (CMT-201 through CMT-209)
- No .sol files modified by this plan

---
*Phase: 41-comment-scan-peripheral*
*Completed: 2026-03-19*
