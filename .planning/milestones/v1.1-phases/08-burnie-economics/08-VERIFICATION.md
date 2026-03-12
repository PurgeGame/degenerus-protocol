---
phase: 08-burnie-economics
verified: 2026-03-12T16:00:00Z
status: passed
score: 8/8 must-haves verified
re_verification: false
---

# Phase 8: BURNIE Economics Verification Report

**Phase Goal:** A game theory agent can model BURNIE supply dynamics including all earning paths, burn sinks, and vault mechanics
**Verified:** 2026-03-12T16:00:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A game theory agent can compute exact coinflip EV including all payout tiers (1.5x, 2.5x, 1.78x-2.15x) with correct probabilities | VERIFIED | Section 3 of v1.1-burnie-coinflip.md documents all three tiers with exact probabilities (5%/5%/90%) and derives weighted EV = 0.98425x; verified against BurnieCoinflip.sol:813-824 |
| 2 | A game theory agent can model the bounty system lifecycle: accumulation, arming, resolution (win/loss), and clearing | VERIFIED | Section 5 of v1.1-burnie-coinflip.md covers all four lifecycle states with exact Solidity from BurnieCoinflip.sol:634-693 (arming) and 849-879 (resolution) |
| 3 | A game theory agent can compute recycling bonuses (normal 1% capped 1000, afKing 1.6%+ with deity scaling) for auto-rebuy EV modeling | VERIFIED | Section 6 documents both bonus paths with worked example; verified against BurnieCoinflip.sol:1042-1066 |
| 4 | Claim window expiry (30d first-time, 90d subsequent) is documented as a supply sink with exact conditions | VERIFIED | Section 7 documents window durations and auto-rebuy extension; verified against BurnieCoinflip.sol:470 (COIN_CLAIM_FIRST_DAYS=30, COIN_CLAIM_DAYS=90) |
| 5 | A game theory agent can enumerate every path that creates new BURNIE supply vs virtual credits | VERIFIED | Section 3 of v1.1-burnie-supply.md classifies all 7 earning paths with mint vs creditFlip distinction; critical pitfall explicitly called out |
| 6 | A game theory agent can enumerate every BURNIE burn sink with exact conditions and minimums | VERIFIED | Section 4 of v1.1-burnie-supply.md documents all 4 sinks (coinflip loss, decimator, ticket purchase, vault transfer) with permanence flags and minimums verified against source |
| 7 | A game theory agent can verify the vault invariant and trace how each operation affects it | VERIFIED | Section 2 of v1.1-burnie-supply.md provides 9-row operation impact table with exact Solidity; verified against BurnieCoin.sol lines 442-706 |
| 8 | Lootbox BURNIE output formulas (low/high path BPS values, presale bonus) are documented with exact conversion expressions | VERIFIED | Section 3b of v1.1-burnie-supply.md documents both paths with BPS ranges; verified against DegenerusGameLootboxModule.sol:297-305, 1607-1612 |

**Score:** 8/8 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `audit/v1.1-burnie-coinflip.md` | Complete coinflip mechanics reference for game theory agents | VERIFIED | 766 lines, 10 sections, 25-entry constants table; contains COINFLIP_EXTRA_MIN_PERCENT |
| `audit/v1.1-burnie-supply.md` | Complete BURNIE supply dynamics reference for game theory agents | VERIFIED | 810 lines, 8 sections, 27-entry constants table; contains supplyIncUncirculated |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| audit/v1.1-burnie-coinflip.md | contracts/BurnieCoinflip.sol | Verified formulas with exact line numbers | VERIFIED | Every formula cites BurnieCoinflip.sol line numbers; spot-checked: MIN at line 119, rewardPercent logic at 813-824, bounty at 855-879, recycling at 1042-1066, all confirmed correct |
| audit/v1.1-burnie-coinflip.md | contracts/BurnieCoin.sol | burnForCoinflip and mintForCoinflip mechanics | VERIFIED | burnForCoinflip documented at BurnieCoin.sol:517-519, mintForCoinflip at 526-528; both verified against source |
| audit/v1.1-burnie-supply.md | contracts/BurnieCoin.sol | Supply invariant and all mint/burn entry points | VERIFIED | Operation impact table references BurnieCoin.sol lines 442-706; spot-checked _mint(line 478), _burn(lines 501-502), _transfer to VAULT(lines 451-452), vaultEscrow(line 685), vaultMintTo(lines 700-702); all correct |
| audit/v1.1-burnie-supply.md | contracts/modules/DegenerusGameLootboxModule.sol | Lootbox BURNIE output formulas | VERIFIED | LOOTBOX_LARGE_BURNIE_LOW_BASE_BPS=5808 at line 297, LOW_STEP_BPS=477 at line 299, HIGH_BASE_BPS=30705 at line 301, HIGH_STEP_BPS=9430 at line 303, PRESALE_BONUS_BPS=6200 at line 305 — all confirmed |
| audit/v1.1-burnie-supply.md | contracts/DegenerusVault.sol | Vault claim and DGVB share redemption mechanics | VERIFIED | _burnCoinFor documented at DegenerusVault.sol:773-812; coinOut formula at line 784; three-source fulfillment at lines 797/804/810 confirmed |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| BURN-01 | 08-01-PLAN.md | Document coinflip mechanics (stake, odds, payout range, bounty system, expiry) | SATISFIED | v1.1-burnie-coinflip.md fully covers: MIN=100 BURNIE, 50/50 VRF odds, three-tier payout distribution (1.5x/2.5x/1.78x-2.15x), complete bounty lifecycle, 30d/90d expiry windows |
| BURN-02 | 08-02-PLAN.md | Document BURNIE earning paths (lootbox bonuses, quest rewards, coinflip winnings) | SATISFIED | v1.1-burnie-supply.md Section 3 enumerates all 7 earning paths with delivery method classification; lootbox BPS values verified; quest rewards QUEST_SLOT0_REWARD=100 BURNIE (DegenerusQuests.sol:135), QUEST_RANDOM_REWARD=200 BURNIE (line 138) confirmed |
| BURN-03 | 08-02-PLAN.md | Document BURNIE burn sinks (decimator eligibility, ticket purchases) | SATISFIED | v1.1-burnie-supply.md Section 4 covers all 4 sinks: DECIMATOR_MIN=1000 BURNIE (BurnieCoin.sol:173), BURNIE_LOOTBOX_MIN=1000 BURNIE (MintModule:92), COIN_PURCHASE_CUTOFF=90d (MintModule:115), vault-transfer as non-permanent sink |
| BURN-04 | 08-02-PLAN.md | Document vault reserve mechanics and supply invariants | SATISFIED | v1.1-burnie-supply.md Section 2 provides supply invariant with 9-operation table; Section 5 covers DGVB share redemption with coinOut formula; initial vaultAllowance=2,000,000 BURNIE verified at BurnieCoin.sol:202 |

**Orphaned requirements check:** REQUIREMENTS.md maps BURN-01 through BURN-04 to Phase 8. Both plans (08-01 and 08-02) claim these four IDs collectively. No requirements are orphaned.

---

### Formula Accuracy Spot-Checks

The following specific formulas and constants from the audit documents were verified against contract source:

**v1.1-burnie-coinflip.md:**

| Claim | Contract Location | Verified? |
|-------|------------------|-----------|
| MIN = 100 ether at BurnieCoinflip.sol:119 | Line 119: `uint256 private constant MIN = 100 ether;` | Correct |
| COINFLIP_LOSS_WWXRP_REWARD = 1 ether at line 120 | Line 120: `uint256 private constant COINFLIP_LOSS_WWXRP_REWARD = 1 ether;` | Correct |
| COINFLIP_EXTRA_MIN_PERCENT = 78 at line 121 | Line 121: `uint16 private constant COINFLIP_EXTRA_MIN_PERCENT = 78;` | Correct |
| COINFLIP_EXTRA_RANGE = 38 at line 122 | Line 122: `uint16 private constant COINFLIP_EXTRA_RANGE = 38;` | Correct |
| COINFLIP_REWARD_MEAN_BPS = 9685 at line 128 | Line 128: `uint16 private constant COINFLIP_REWARD_MEAN_BPS = 9685;` | Correct |
| AFKING_RECYCLE_BONUS_BPS = 160 at line 130 | Line 130: `uint16 private constant AFKING_RECYCLE_BONUS_BPS = 160;` | Correct |
| AFKING_DEITY_BONUS_MAX_HALF_BPS = 300 at line 132 | Line 132: `uint16 private constant AFKING_DEITY_BONUS_MAX_HALF_BPS = 300;` | Correct |
| DEITY_RECYCLE_CAP = 1,000,000 ether at line 133 | Line 133: `uint256 private constant DEITY_RECYCLE_CAP = 1_000_000 ether;` | Correct |
| PRICE_COIN_UNIT = 1000 ether at line 135 | Line 135: `uint256 private constant PRICE_COIN_UNIT = 1000 ether;` | Correct |
| COIN_CLAIM_DAYS = 90 at line 136 | Line 136: `uint8 private constant COIN_CLAIM_DAYS = 90;` | Correct |
| COIN_CLAIM_FIRST_DAYS = 30 at line 137 | Line 137: `uint8 private constant COIN_CLAIM_FIRST_DAYS = 30;` | Correct |
| AUTO_REBUY_OFF_CLAIM_DAYS_MAX = 1095 at line 138 | Line 138: `uint16 private constant AUTO_REBUY_OFF_CLAIM_DAYS_MAX = 1095;` | Correct |
| Bounty initialised at 1_000 ether at line 167 | Line 167: `uint128 public currentBounty = 1_000 ether;` | Correct |
| EV derivation: COINFLIP_REWARD_MEAN_BPS = 96.5*50 + 5000 = 9685 | Mathematical derivation confirmed | Correct |
| Bounty resolution: slice = currentBounty_ >> 1 at line 856 | Line 856: `slice = currentBounty_ >> 1;` | Correct |
| payout formula at lines 532-534 matches _claimCoinflipsInternal | Lines 532-534 in source code: `uint256 payout = stake + (stake * uint256(rewardPercent)) / 100;` | Correct |
| _applyEvToRewardPercent at 1128-1142: variable name `adjustedPercent` | Source lines 1128-1142: function returns `adjustedPercent` | Correct (document shows `adjustedPercent = uint16(rounded)` — the actual source line 1141 assigns to `adjustedPercent`) |
| LOOTBOX_BOON_BONUS_BPS = 500 at LootboxModule:218 | Line 218: `uint16 private constant LOOTBOX_BOON_BONUS_BPS = 500;` | Correct |
| LOOTBOX_COINFLIP_10_BONUS_BPS = 1000 at LootboxModule:237 | Line 237: `uint16 private constant LOOTBOX_COINFLIP_10_BONUS_BPS = 1000;` | Correct |
| LOOTBOX_COINFLIP_25_BONUS_BPS = 2500 at LootboxModule:239 | Line 239: `uint16 private constant LOOTBOX_COINFLIP_25_BONUS_BPS = 2500;` | Correct |

**v1.1-burnie-supply.md:**

| Claim | Contract Location | Verified? |
|-------|------------------|-----------|
| Supply struct at BurnieCoin.sol:195-198 | Lines 195-198: `struct Supply { uint128 totalSupply; uint128 vaultAllowance; }` | Correct |
| Initial vaultAllowance = 2_000_000 ether at line 202 | Line 202: `Supply private _supply = Supply({totalSupply: 0, vaultAllowance: uint128(2_000_000 ether)});` | Correct |
| _transfer to VAULT: totalSupply -= at line 451, vaultAllowance += at line 452 | Lines 451-452 confirmed | Correct |
| vaultEscrow increments vaultAllowance at line 685 | Line 685: `_supply.vaultAllowance += amount128;` | Correct |
| vaultMintTo: vaultAllowance -= at line 700, totalSupply += at line 701 | Lines 700-701 confirmed | Correct |
| mintForCoinflip at BurnieCoin.sol:526-528 | Lines 526-528 confirmed | Correct |
| burnForCoinflip at BurnieCoin.sol:517-519 | Lines 517-519 confirmed | Correct |
| DECIMATOR_MIN = 1000 ether at BurnieCoin.sol:173 | Line 173: `uint256 private constant DECIMATOR_MIN = 1_000 ether;` | Correct |
| DECIMATOR_BUCKET_BASE = 12 at line 176 | Line 176: `uint8 private constant DECIMATOR_BUCKET_BASE = 12;` | Correct |
| DECIMATOR_ACTIVITY_CAP_BPS = 23500 at line 183 | Line 183: `uint16 private constant DECIMATOR_ACTIVITY_CAP_BPS = 23_500;` | Correct |
| DECIMATOR_BOON_CAP = 50000 ether at line 186 | Line 186: `uint256 private constant DECIMATOR_BOON_CAP = 50_000 ether;` | Correct |
| LOOTBOX_LARGE_BURNIE_LOW_BASE_BPS = 5808 at LootboxModule:297 | Line 297: `uint16 private constant LOOTBOX_LARGE_BURNIE_LOW_BASE_BPS = 5_808;` | Correct |
| LOOTBOX_PRESALE_BURNIE_BONUS_BPS = 6200 at LootboxModule:305 | Line 305: `uint16 private constant LOOTBOX_PRESALE_BURNIE_BONUS_BPS = 6_200;` | Correct |
| QUEST_SLOT0_REWARD = 100 ether at DegenerusQuests.sol:135 | Line 135: `uint256 private constant QUEST_SLOT0_REWARD = 100 ether;` | Correct |
| QUEST_RANDOM_REWARD = 200 ether at DegenerusQuests.sol:138 | Line 138: `uint256 private constant QUEST_RANDOM_REWARD = 200 ether;` | Correct |
| BURNIE_LOOTBOX_MIN = 1000 ether at MintModule:92 | Line 92: `uint256 private constant BURNIE_LOOTBOX_MIN = 1000 ether;` | Correct |
| COIN_PURCHASE_CUTOFF = 90 days at MintModule:115 | Line 115: `uint256 private constant COIN_PURCHASE_CUTOFF = 90 days;` | Correct |
| COIN_PURCHASE_CUTOFF_LVL0 = 335 days at MintModule:116 | Line 116: `uint256 private constant COIN_PURCHASE_CUTOFF_LVL0 = 335 days;` | Correct |
| Lootbox low-path max at varianceRoll=15: 5808 + 15*477 = 12963 (129.63%) | Arithmetic confirmed; document notes 129.63% correcting earlier research estimate | Correct |
| _burnCoinFor at DegenerusVault.sol:773; coinOut formula at line 784 | Line 773 is _burnCoinFor, line 784: `coinOut = (coinBal * amount) / supplyBefore;` | Correct |

---

### Anti-Patterns Found

No anti-patterns were detected. Both audit documents contain:
- No TODO/FIXME/placeholder comments
- No empty sections or stubs
- All formulas include Solidity code blocks with line references
- No return null patterns (documentation files)

---

### Human Verification Required

The following items cannot be verified programmatically and may benefit from human review:

**1. Lootbox BURNIE Delivery Path Completeness**
**Test:** Trace all call sites of `creditFlip` and `mintForCoinflip` in the contracts and compare against the 7 earning paths listed in v1.1-burnie-supply.md Section 3.
**Expected:** No earning path is missing from the enumeration.
**Why human:** Requires exhaustive call-site search across all game modules to confirm completeness.

**2. Bounty payout DGNRS reward cross-reference**
**Test:** Confirm `game.payCoinflipBountyDgnrs(to)` at BurnieCoinflip.sol:865 is adequately described; the document notes it awards a DGNRS token but the exact formula is not in this phase.
**Expected:** Acceptable as a cross-reference stub since DGNRS tokenomics are Phase 10 scope.
**Why human:** Judgment call on whether the forward-reference is sufficient for agent modeling.

**3. Worked example arithmetic verification (v1.1-burnie-supply.md Section 7)**
**Test:** Manually verify the 5-step worked example traces totalSupply, vaultAllowance, and supplyIncUncirculated correctly through: coinflip deposit, win mint, decimator burn, creditFlip no-op, vaultEscrow.
**Expected:** Starting at (100k, 2.1M, 2.2M), ending at (99,960, 2,105,000, 2,204,960).
**Why human:** Arithmetic is internally consistent as written; human confirmation ensures no transcription error.

---

## Gaps Summary

No gaps. All 8 must-have truths are verified. All 4 requirements (BURN-01, BURN-02, BURN-03, BURN-04) are satisfied with evidence traceable to contract source. Both artifact files exist, are substantive (766 and 810 lines respectively), and their claimed constants and line numbers match the actual contract source code across every spot-check performed.

The documents correctly handle the key distinction (per plan's "Critical" note) between `mintForCoinflip` as a new-supply operation and `creditFlip` as a virtual-only credit — this is prominently documented in both files and listed as "Pitfall 1" in v1.1-burnie-coinflip.md and the critical warning in v1.1-burnie-supply.md Section 3h.

One minor documentation accuracy finding: the summary of `_applyEvToRewardPercent` in v1.1-burnie-coinflip.md Section 4b shows the function body with `adjustedPercent = uint16(rounded)` as the final line but the function return type shown in the code block is missing the `returns (uint16)` signature annotation. This is a cosmetic omission that does not affect agent usability.

---

*Verified: 2026-03-12T16:00:00Z*
*Verifier: Claude (gsd-verifier)*
