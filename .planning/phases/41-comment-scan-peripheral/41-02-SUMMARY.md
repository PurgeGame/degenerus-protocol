# Phase 41 Plan 02: Light-Change Peripheral + Interfaces -- Comment Audit

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
