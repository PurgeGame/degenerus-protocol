# Phase 11: Parameter Reference - Research

**Researched:** 2026-03-12
**Domain:** Solidity constant extraction and documentation consolidation
**Confidence:** HIGH

## Summary

Phase 11 consolidates every numeric constant, BPS value, ETH threshold, and timing parameter from the Degenerus protocol into a single master reference document. The contracts contain approximately 200+ named constants spread across 15+ Solidity files. Research has identified and catalogued every `private constant` and `internal constant` declaration across all contract files, categorized them by type (BPS splits, ETH thresholds/pricing, timing/duration, and operational/structural), and mapped each to its source file and line number.

The key challenge is organization: constants are scattered across DegenerusGame.sol, BurnieCoinflip.sol, DegenerusAffiliate.sol, DegenerusStonk.sol, DegenerusGameStorage.sol, PriceLookupLib.sol, and 10+ module files. Many constants are duplicated across modules (e.g., LOOTBOX_BOOST_EXPIRY_DAYS appears in MintModule, WhaleModule, and BoonModule; DEITY_PASS_BASE appears in WhaleModule and LootboxModule). The reference document must deduplicate while noting all locations.

**Primary recommendation:** Produce a single audit/v1.1-parameter-reference.md with four master tables (BPS constants, ETH thresholds/pricing, timing constants, operational constants), each row containing: constant name, exact value, human-readable interpretation, purpose description, and contract file:line. Cross-reference prior audit documents for purpose descriptions already written.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PARM-01 | Master table of all BPS constants with values, purposes, and contract locations | All BPS constants identified across 15 contract files -- ~60 unique BPS constants found. Source locations, exact values, and categorization by subsystem documented below. |
| PARM-02 | Master table of all ETH thresholds, caps, and pricing constants | All ETH-denominated constants identified -- ~30 unique values including pricing tiers, thresholds, caps, and minimum bets. PriceLookupLib tier table fully documented. |
| PARM-03 | Master table of all timing constants (timeouts, windows, durations) | All timing constants identified -- ~15 unique values covering expiry days, timeout periods, claim windows, and operational timing. |
</phase_requirements>

## Standard Stack

This phase produces documentation only -- no libraries or tooling needed. The "stack" is the contract source files themselves.

### Source Contract Files (containing constants)

| File | Constant Count | Primary Domain |
|------|---------------|----------------|
| `contracts/DegenerusGame.sol` | ~15 | Core game BPS splits, afKing thresholds |
| `contracts/BurnieCoinflip.sol` | ~16 | Coinflip mechanics, recycling bonuses |
| `contracts/DegenerusAffiliate.sol` | ~10 | Affiliate reward scaling, taper system |
| `contracts/DegenerusStonk.sol` | ~8 | DGNRS token supply distribution |
| `contracts/BurnieCoin.sol` | ~7 | Decimator mechanics |
| `contracts/DegenerusQuests.sol` | ~12 | Quest rewards and targets |
| `contracts/DegenerusJackpots.sol` | ~4 | BAF scatter parameters |
| `contracts/DeityBoonViewer.sol` | ~30 | Deity boon types and weights |
| `contracts/storage/DegenerusGameStorage.sol` | ~10 | Core thresholds, bootstrap values |
| `contracts/libraries/PriceLookupLib.sol` | ~7 (inline) | Level pricing tiers |
| `contracts/libraries/JackpotBucketLib.sol` | ~5 | Jackpot scaling thresholds |
| `contracts/libraries/GameTimeLib.sol` | ~1 | Day boundary timing |
| `contracts/modules/DegenerusGameMintModule.sol` | ~15 | Lootbox splits, purchase limits |
| `contracts/modules/DegenerusGameWhaleModule.sol` | ~25 | Whale/deity/lazy pass pricing and splits |
| `contracts/modules/DegenerusGameJackpotModule.sol` | ~25 | Jackpot distribution, daily slices |
| `contracts/modules/DegenerusGameAdvanceModule.sol` | ~15 | Future pool drip, VRF, level transitions |
| `contracts/modules/DegenerusGameLootboxModule.sol` | ~70 | Lootbox EV, boon system, ticket variance |
| `contracts/modules/DegenerusGameDecimatorModule.sol` | ~5 | Auto-rebuy bonuses, multiplier cap |
| `contracts/modules/DegenerusGameEndgameModule.sol` | ~3 | Endgame affiliate reward, small lootbox |
| `contracts/modules/DegenerusGameBoonModule.sol` | ~4 | Boon expiry durations |
| `contracts/modules/DegenerusGameDegeneretteModule.sol` | ~30 | Degenerette ROI tiers, min bets, activity |
| `contracts/modules/DegenerusGameGameOverModule.sol` | ~1 | Deity pass refund on early gameover |

## Architecture Patterns

### Document Structure for Parameter Reference

```
audit/v1.1-parameter-reference.md
  1. Overview (what this document is, how to use it)
  2. BPS Constants (PARM-01)
     - Pool Split BPS
     - Reward Scaling BPS
     - Coinflip Mechanics BPS
     - Lootbox EV/Variance BPS
     - Deity Boon Weight Table
     - Degenerette ROI BPS
     - Jackpot Distribution BPS
  3. ETH Thresholds & Pricing (PARM-02)
     - Level Pricing Tiers (PriceLookupLib)
     - Whale/Deity/Lazy Pass Pricing
     - Minimum Bets & Thresholds
     - Bootstrap & Cap Values
  4. Timing Constants (PARM-03)
     - Expiry Windows (boons, claims)
     - Timeout Periods (death clock, deploy idle)
     - Operational Timing (VRF, day boundaries)
  5. Cross-Reference Index (alphabetical by constant name)
```

### Table Format (agent-consumable)

Each table row should contain:
```
| Constant Name | Value | Human | Purpose | File:Line |
```

Where:
- **Value** = exact Solidity literal (e.g., `1000`, `0.01 ether`, `90`)
- **Human** = readable interpretation (e.g., "10%", "0.01 ETH", "90 days")
- **Purpose** = one-line description
- **File:Line** = contract path and line number (multiple if duplicated)

### Deduplication Strategy

Many constants are duplicated across modules (same name, same value, used via delegatecall storage or redeclared). The reference should:
1. List each unique constant ONCE with all locations
2. Note where constants are redeclared (not inherited) -- e.g., `LOOTBOX_BOOST_EXPIRY_DAYS` in MintModule:102, WhaleModule:85, BoonModule:24
3. Flag any value discrepancies (none found in this codebase -- all duplicates match)

## Complete Constant Inventory

### BPS Constants (~60 unique)

**Pool & Distribution Splits:**
| Constant | Value | Human | File:Line |
|----------|-------|-------|-----------|
| PURCHASE_TO_FUTURE_BPS | 1000 | 10% | DegenerusGame.sol:198 |
| LOOTBOX_SPLIT_FUTURE_BPS | 9000 | 90% | MintModule.sol:105 |
| LOOTBOX_SPLIT_NEXT_BPS | 1000 | 10% | MintModule.sol:106 |
| LOOTBOX_PRESALE_SPLIT_FUTURE_BPS | 4000 | 40% | MintModule.sol:109 |
| LOOTBOX_PRESALE_SPLIT_NEXT_BPS | 4000 | 40% | MintModule.sol:110 |
| LOOTBOX_PRESALE_SPLIT_VAULT_BPS | 2000 | 20% | MintModule.sol:111 |
| LAZY_PASS_TO_FUTURE_BPS | 1000 | 10% | WhaleModule.sol:124 |
| LAZY_PASS_LOOTBOX_PRESALE_BPS | 2000 | 20% | WhaleModule.sol:115 |
| LAZY_PASS_LOOTBOX_POST_BPS | 1000 | 10% | WhaleModule.sol:118 |
| WHALE_LOOTBOX_PRESALE_BPS | 2000 | 20% | WhaleModule.sol:142 |
| WHALE_LOOTBOX_POST_BPS | 1000 | 10% | WhaleModule.sol:145 |
| DEITY_LOOTBOX_PRESALE_BPS | 2000 | 20% | WhaleModule.sol:148 |
| DEITY_LOOTBOX_POST_BPS | 1000 | 10% | WhaleModule.sol:151 |
| DEITY_WHALE_POOL_BPS | 500 | 5% | WhaleModule.sol:106 |
| FAR_FUTURE_COIN_BPS | 2500 | 25% | JackpotModule.sol:209 |
| FINAL_DAY_DGNRS_BPS | 100 | 1% | JackpotModule.sol:176 |
| DAILY_REWARD_JACKPOT_LOOTBOX_BPS | 5000 | 50% | JackpotModule.sol:179 |
| PURCHASE_REWARD_JACKPOT_LOOTBOX_BPS | 7500 | 75% | JackpotModule.sol:182 |
| LOOTBOX_BOON_BUDGET_BPS | 1000 | 10% | LootboxModule.sol:192 |
| LOOTBOX_BOON_UTILIZATION_BPS | 5000 | 50% | LootboxModule.sol:197 |
| AFFILIATE_POOL_REWARD_BPS | 100 | 1% | EndgameModule.sol:96 |

**DGNRS Token Distribution:**
| Constant | Value | Human | File:Line |
|----------|-------|-------|-----------|
| CREATOR_BPS | 2000 | 20% | DegenerusStonk.sol:157 |
| WHALE_POOL_BPS | 1143 | 11.43% | DegenerusStonk.sol:160 |
| AFFILIATE_POOL_BPS | 3428 | 34.28% | DegenerusStonk.sol:161 |
| LOOTBOX_POOL_BPS | 1143 | 11.43% | DegenerusStonk.sol:162 |
| REWARD_POOL_BPS | 1143 | 11.43% | DegenerusStonk.sol:163 |
| EARLYBIRD_POOL_BPS | 1143 | 11.43% | DegenerusStonk.sol:164 |
| AFFILIATE_DGNRS_LEVEL_BPS | 500 | 5% | DegenerusGame.sol:201 |
| COINFLIP_BOUNTY_DGNRS_BPS | 50 | 0.5% | DegenerusGame.sol:204 |
| AFFILIATE_DGNRS_DEITY_BONUS_BPS | 2000 | 20% | DegenerusGame.sol:207 |

**Affiliate System:**
| Constant | Value | Human | File:Line |
|----------|-------|-------|-----------|
| REWARD_SCALE_FRESH_L1_3_BPS | 2500 | 25% | DegenerusAffiliate.sol:198 |
| REWARD_SCALE_FRESH_L4P_BPS | 2000 | 20% | DegenerusAffiliate.sol:199 |
| REWARD_SCALE_RECYCLED_BPS | 500 | 5% | DegenerusAffiliate.sol:200 |
| LOOTBOX_TAPER_MIN_BPS | 5000 | 50% floor | DegenerusAffiliate.sol:204 |

**Coinflip Mechanics:**
| Constant | Value | Human | File:Line |
|----------|-------|-------|-----------|
| COINFLIP_REWARD_MEAN_BPS | 9685 | 96.85% mean payout | BurnieCoinflip.sol:128 |
| COINFLIP_RATIO_BPS_SCALE | 10000 | 1x scale | BurnieCoinflip.sol:123 |
| COINFLIP_RATIO_BPS_EQUAL | 10000 | 1x ratio | BurnieCoinflip.sol:124 |
| COINFLIP_RATIO_BPS_TRIPLE | 30000 | 3x ratio | BurnieCoinflip.sol:125 |
| COINFLIP_EV_EQUAL_BPS | 0 | 0% EV adjustment | BurnieCoinflip.sol:126 |
| COINFLIP_EV_TRIPLE_BPS | 300 | 3% EV adjustment | BurnieCoinflip.sol:127 |
| AFKING_RECYCLE_BONUS_BPS | 160 | 1.6% | BurnieCoinflip.sol:130 |
| AFKING_DEITY_BONUS_PER_LEVEL_HALF_BPS | 2 | 0.01%/level | BurnieCoinflip.sol:131 |
| AFKING_DEITY_BONUS_MAX_HALF_BPS | 300 | 1.5% max | BurnieCoinflip.sol:132 |

**Future Pool Drip (AdvanceModule):**
| Constant | Value | Human | File:Line |
|----------|-------|-------|-----------|
| NEXT_TO_FUTURE_BPS_FAST | 3000 | 30% | AdvanceModule.sol:101 |
| NEXT_TO_FUTURE_BPS_MIN | 1300 | 13% | AdvanceModule.sol:102 |
| NEXT_TO_FUTURE_BPS_WEEK_STEP | 100 | 1%/week | AdvanceModule.sol:103 |
| NEXT_TO_FUTURE_BPS_X9_BONUS | 200 | 2% bonus | AdvanceModule.sol:104 |
| NEXT_SKIM_VARIANCE_BPS | 1000 | 10% variance | AdvanceModule.sol:105 |
| NEXT_SKIM_VARIANCE_MIN_BPS | 1000 | 10% min variance | AdvanceModule.sol:106 |

**Jackpot Distribution:**
| Constant | Value | Human | File:Line |
|----------|-------|-------|-----------|
| DAILY_CURRENT_BPS_MIN | 600 | 6% | JackpotModule.sol:143 |
| DAILY_CURRENT_BPS_MAX | 1400 | 14% | JackpotModule.sol:144 |
| JACKPOT_SCALE_BASE_BPS | 10000 | 1x | JackpotBucketLib.sol:25 |
| JACKPOT_SCALE_FIRST_BPS | 20000 | 2x | JackpotBucketLib.sol:26 |
| JACKPOT_SCALE_MAX_BPS | 40000 | 4x | JackpotModule.sol:225 |
| DAILY_JACKPOT_SCALE_MAX_BPS | 66667 | 6.67x | JackpotModule.sol:228 |

**Decimator & Auto-Rebuy:**
| Constant | Value | Human | File:Line |
|----------|-------|-------|-----------|
| AUTO_REBUY_BONUS_BPS | 13000 | 130% (30% bonus) | DecimatorModule.sol:91 |
| AFKING_AUTO_REBUY_BONUS_BPS | 14500 | 145% (45% bonus) | DecimatorModule.sol:94 |
| DECIMATOR_ACTIVITY_CAP_BPS | 23500 | 235% activity cap | BurnieCoin.sol:183 |

**Activity & Deity:**
| Constant | Value | Human | File:Line |
|----------|-------|-------|-----------|
| DEITY_PASS_ACTIVITY_BONUS_BPS | 8000 | 80% bonus | DegenerusGame.sol:217, DegeneretteModule.sol:226 |
| ACTIVITY_SCORE_MID_BPS | 7500 | 75% | DegeneretteModule.sol:191 |
| ACTIVITY_SCORE_HIGH_BPS | 25500 | 255% | DegeneretteModule.sol:194 |
| ACTIVITY_SCORE_MAX_BPS | 30500 | 305% | DegeneretteModule.sol:197 |
| ACTIVITY_SCORE_NEUTRAL_BPS | 6000 | 60% (lootbox) | LootboxModule.sol:321 |
| ACTIVITY_SCORE_MAX_BPS (lootbox) | 25500 | 255% (lootbox) | LootboxModule.sol:323 |

**Degenerette ROI:**
| Constant | Value | Human | File:Line |
|----------|-------|-------|-----------|
| ROI_MIN_BPS | 9000 | 90% | DegeneretteModule.sol:200 |
| ROI_MID_BPS | 9500 | 95% | DegeneretteModule.sol:203 |
| ROI_HIGH_BPS | 9950 | 99.5% | DegeneretteModule.sol:206 |
| ROI_MAX_BPS | 9990 | 99.9% | DegeneretteModule.sol:209 |
| ETH_ROI_BONUS_BPS | 500 | 5% ETH bonus | DegeneretteModule.sol:212 |
| WWXRP_HIGH_ROI_BASE_BPS | 9000 | 90% base | DegeneretteModule.sol:217 |
| WWXRP_HIGH_ROI_MAX_BPS | 10990 | 109.9% max | DegeneretteModule.sol:220 |
| ETH_WIN_CAP_BPS | 1000 | 10% pool cap | DegeneretteModule.sol:223 |

**Lootbox Ticket Variance:**
| Constant | Value | Human | File:Line |
|----------|-------|-------|-----------|
| LOOTBOX_TICKET_ROLL_BPS | 16100 | 161% base | LootboxModule.sol:267 |
| LOOTBOX_TICKET_VARIANCE_TIER1_CHANCE_BPS | 100 | 1% | LootboxModule.sol:269 |
| LOOTBOX_TICKET_VARIANCE_TIER2_CHANCE_BPS | 400 | 4% | LootboxModule.sol:271 |
| LOOTBOX_TICKET_VARIANCE_TIER3_CHANCE_BPS | 2000 | 20% | LootboxModule.sol:273 |
| LOOTBOX_TICKET_VARIANCE_TIER4_CHANCE_BPS | 4500 | 45% | LootboxModule.sol:275 |
| LOOTBOX_TICKET_VARIANCE_TIER1_BPS | 46000 | 460% | LootboxModule.sol:277 |
| LOOTBOX_TICKET_VARIANCE_TIER2_BPS | 23000 | 230% | LootboxModule.sol:279 |
| LOOTBOX_TICKET_VARIANCE_TIER3_BPS | 11000 | 110% | LootboxModule.sol:281 |
| LOOTBOX_TICKET_VARIANCE_TIER4_BPS | 6510 | 65.1% | LootboxModule.sol:283 |
| LOOTBOX_TICKET_VARIANCE_TIER5_BPS | 4500 | 45% | LootboxModule.sol:285 |
| DISTRESS_TICKET_BONUS_BPS | 2500 | 25% | LootboxModule.sol:317 |

**Lootbox EV:**
| Constant | Value | Human | File:Line |
|----------|-------|-------|-----------|
| LOOTBOX_EV_MIN_BPS | 8000 | 80% | LootboxModule.sol:325 |
| LOOTBOX_EV_NEUTRAL_BPS | 10000 | 100% | LootboxModule.sol:327 |
| LOOTBOX_EV_MAX_BPS | 13500 | 135% | LootboxModule.sol:329 |

**Lootbox Boon Bonus BPS (boost tiers applied from deity boons):**
| Constant | Value | Human | File:Line |
|----------|-------|-------|-----------|
| LOOTBOX_BOOST_5_BONUS_BPS | 500 | 5% | MintModule.sol:97, WhaleModule.sol:73, LootboxModule.sol:241 |
| LOOTBOX_BOOST_15_BONUS_BPS | 1500 | 15% | MintModule.sol:98, WhaleModule.sol:76, LootboxModule.sol:243 |
| LOOTBOX_BOOST_25_BONUS_BPS | 2500 | 25% | MintModule.sol:99, WhaleModule.sol:79, LootboxModule.sol:245 |
| LOOTBOX_COINFLIP_10_BONUS_BPS | 1000 | 10% | LootboxModule.sol:237 |
| LOOTBOX_COINFLIP_25_BONUS_BPS | 2500 | 25% | LootboxModule.sol:239 |
| LOOTBOX_PURCHASE_BOOST_5_BONUS_BPS | 500 | 5% | LootboxModule.sol:247 |
| LOOTBOX_PURCHASE_BOOST_15_BONUS_BPS | 1500 | 15% | LootboxModule.sol:249 |
| LOOTBOX_PURCHASE_BOOST_25_BONUS_BPS | 2500 | 25% | LootboxModule.sol:251 |
| LOOTBOX_DECIMATOR_10_BONUS_BPS | 1000 | 10% | LootboxModule.sol:253 |
| LOOTBOX_DECIMATOR_25_BONUS_BPS | 2500 | 25% | LootboxModule.sol:255 |
| LOOTBOX_DECIMATOR_50_BONUS_BPS | 5000 | 50% | LootboxModule.sol:257 |
| LOOTBOX_WHALE_BOON_DISCOUNT_10_BPS | 1000 | 10% | LootboxModule.sol:200 |
| LOOTBOX_WHALE_BOON_DISCOUNT_25_BPS | 2500 | 25% | LootboxModule.sol:201 |
| LOOTBOX_WHALE_BOON_DISCOUNT_50_BPS | 5000 | 50% | LootboxModule.sol:202 |
| LOOTBOX_LAZY_PASS_DISCOUNT_10_BPS | 1000 | 10% | LootboxModule.sol:204 |
| LOOTBOX_LAZY_PASS_DISCOUNT_25_BPS | 2500 | 25% | LootboxModule.sol:205 |
| LOOTBOX_LAZY_PASS_DISCOUNT_50_BPS | 5000 | 50% | LootboxModule.sol:206 |
| LOOTBOX_BOON_BONUS_BPS | 500 | 5% | LootboxModule.sol:218 |
| LAZY_PASS_BOON_DEFAULT_DISCOUNT_BPS | 1000 | 10% | WhaleModule.sol:121 |
| LOOTBOX_PRESALE_BURNIE_BONUS_BPS | 6200 | 62% | LootboxModule.sol:305 |

**Lootbox DGNRS PPM (parts per million):**
| Constant | Value | Human | File:Line |
|----------|-------|-------|-----------|
| LOOTBOX_DGNRS_POOL_SMALL_PPM | 10 | 0.001% | LootboxModule.sol:287 |
| LOOTBOX_DGNRS_POOL_MEDIUM_PPM | 390 | 0.039% | LootboxModule.sol:289 |
| LOOTBOX_DGNRS_POOL_LARGE_PPM | 800 | 0.08% | LootboxModule.sol:291 |
| LOOTBOX_DGNRS_POOL_MEGA_PPM | 8000 | 0.8% | LootboxModule.sol:293 |

**Whale DGNRS PPM:**
| Constant | Value | Human | File:Line |
|----------|-------|-------|-----------|
| DGNRS_WHALE_MINTER_PPM | 10000 | 1% | WhaleModule.sol:91 |
| DGNRS_AFFILIATE_DIRECT_WHALE_PPM | 1000 | 0.1% | WhaleModule.sol:94 |
| DGNRS_AFFILIATE_UPLINE_WHALE_PPM | 200 | 0.02% | WhaleModule.sol:97 |
| DGNRS_AFFILIATE_DIRECT_DEITY_PPM | 5000 | 0.5% | WhaleModule.sol:100 |
| DGNRS_AFFILIATE_UPLINE_DEITY_PPM | 1000 | 0.1% | WhaleModule.sol:103 |

**Lootbox BURNIE payout BPS:**
| Constant | Value | Human | File:Line |
|----------|-------|-------|-----------|
| LOOTBOX_LARGE_BURNIE_LOW_BASE_BPS | 5808 | 58.08% | LootboxModule.sol:297 |
| LOOTBOX_LARGE_BURNIE_LOW_STEP_BPS | 477 | 4.77%/step | LootboxModule.sol:299 |
| LOOTBOX_LARGE_BURNIE_HIGH_BASE_BPS | 30705 | 307.05% | LootboxModule.sol:301 |
| LOOTBOX_LARGE_BURNIE_HIGH_STEP_BPS | 9430 | 94.3%/step | LootboxModule.sol:303 |

### ETH Thresholds, Caps & Pricing (~30 unique)

**Level Pricing (PriceLookupLib -- inline values):**
| Level Range | Price | File:Line |
|-------------|-------|-----------|
| 0-4 | 0.01 ETH | PriceLookupLib.sol:23 |
| 5-9 | 0.02 ETH | PriceLookupLib.sol:24 |
| 10-29 | 0.04 ETH | PriceLookupLib.sol:27 |
| 30-59 | 0.08 ETH | PriceLookupLib.sol:28 |
| 60-89 | 0.12 ETH | PriceLookupLib.sol:29 |
| 90-99 | 0.16 ETH | PriceLookupLib.sol:30 |
| x00 (100+) | 0.24 ETH (milestone) | PriceLookupLib.sol:36 |
| x01-x29 (100+) | 0.04 ETH | PriceLookupLib.sol:38 |
| x30-x59 (100+) | 0.08 ETH | PriceLookupLib.sol:39 |
| x60-x89 (100+) | 0.12 ETH | PriceLookupLib.sol:40 |
| x90-x99 (100+) | 0.16 ETH | PriceLookupLib.sol:43 |

**Named ETH Constants:**
| Constant | Value | Human | Purpose | File:Line |
|----------|-------|-------|---------|-----------|
| AFKING_KEEP_MIN_ETH | 5 ether | 5 ETH | Min afKing ETH keep amount | DegenerusGame.sol:188 |
| AFKING_KEEP_MIN_COIN | 20000 ether | 20,000 BURNIE | Min afKing BURNIE keep | DegenerusGame.sol:192, BurnieCoinflip.sol:140 |
| AFFILIATE_DGNRS_DEITY_BONUS_CAP_ETH | 5 ether | 5 ETH | Max deity affiliate bonus | DegenerusGame.sol:210 |
| AFFILIATE_DGNRS_MIN_SCORE | 10 ether | 10 (raw score) | Min score for DGNRS affiliate claim | DegenerusGame.sol:213 |
| MAX_COMMISSION_PER_REFERRER_PER_LEVEL | 0.5 ether | 0.5 ETH | Per-referrer per-level affiliate cap | DegenerusAffiliate.sol:207 |
| BOOTSTRAP_PRIZE_POOL | 50 ether | 50 ETH | Initial prize pool at level 0 | DegenerusGameStorage.sol:137 |
| LOOTBOX_CLAIM_THRESHOLD | 5 ether | 5 ETH | Whale pass claim eligibility threshold | DegenerusGameStorage.sol:132 |
| EARLYBIRD_TARGET_ETH | 1000 ether | 1,000 ETH | Earlybird DGNRS emission curve target | DegenerusGameStorage.sol:144 |
| WHALE_BUNDLE_EARLY_PRICE | 2.4 ether | 2.4 ETH | Whale bundle price (level < 10) | WhaleModule.sol:127 |
| WHALE_BUNDLE_STANDARD_PRICE | 4 ether | 4 ETH | Whale bundle price (level >= 10) | WhaleModule.sol:130, LootboxModule.sol:226 |
| DEITY_PASS_BASE | 24 ether | 24 ETH | Base deity pass price | WhaleModule.sol:154, LootboxModule.sol:235 |
| DEITY_TRANSFER_ETH_COST | 5 ether | 5 ETH | Cost to transfer deity pass | WhaleModule.sol:157 |
| DEITY_PASS_EARLY_GAMEOVER_REFUND | 20 ether | 20 ETH | Deity pass refund on early gameover | GameOverModule.sol:38 |
| LOOTBOX_WHALE_PASS_PRICE | 4.35 ether | 4.35 ETH | Whale pass price via lootbox | LootboxModule.sol:307 |
| HALF_WHALE_PASS_PRICE | 2.175 ether | 2.175 ETH | Half whale pass price (jackpot payouts) | PayoutUtils.sol:17, LootboxModule.sol:310 |
| LOOTBOX_SPLIT_THRESHOLD | 0.5 ether | 0.5 ETH | Threshold to split lootbox into halves | LootboxModule.sol:313 |
| LOOTBOX_EV_BENEFIT_CAP | 10 ether | 10 ETH | Max EV benefit accumulation per player | LootboxModule.sol:331 |
| LOOTBOX_BOON_MAX_BUDGET | 1 ether | 1 ETH | Max boon budget per lootbox | LootboxModule.sol:194 |
| LOOTBOX_BOON_MAX_BONUS | 5000 ether | 5,000 BURNIE | Max BURNIE bonus from lootbox boon | LootboxModule.sol:220 |
| LOOTBOX_MIN | 0.01 ether | 0.01 ETH | Minimum ETH lootbox purchase | MintModule.sol:90 |
| BURNIE_LOOTBOX_MIN | 1000 ether | 1,000 BURNIE | Minimum BURNIE lootbox purchase | MintModule.sol:92 |
| TICKET_MIN_BUYIN_WEI | 0.0025 ether | 0.0025 ETH | Minimum ETH ticket buy-in | MintModule.sol:94 |
| LOOTBOX_BOOST_MAX_VALUE | 10 ether | 10 ETH | Max ETH value for lootbox boost | WhaleModule.sol:82 (also MintModule.sol:100) |
| LOOTBOX_PRESALE_ETH_CAP | 200 ether | 200 ETH | Presale ETH cap before presale ends | AdvanceModule.sol:110 |
| RNG_NUDGE_BASE_COST | 100 ether | 100 BURNIE | Base cost to nudge RNG | AdvanceModule.sol:97 |
| BURNIE_RNG_TRIGGER | 40000 ether | 40,000 BURNIE | BURNIE threshold for RNG trigger | AdvanceModule.sol:98 |
| MIN_LINK_FOR_LOOTBOX_RNG | 40 ether | 40 LINK | Min LINK for lootbox RNG | AdvanceModule.sol:107 |
| SMALL_LOOTBOX_THRESHOLD | 0.5 ether | 0.5 ETH | Small lootbox ETH threshold (endgame) | EndgameModule.sol:97 |
| MIN (coinflip) | 100 ether | 100 BURNIE | Min coinflip stake | BurnieCoinflip.sol:119 |
| COINFLIP_LOSS_WWXRP_REWARD | 1 ether | 1 WWXRP | WWXRP consolation on coinflip loss | BurnieCoinflip.sol:120 |
| PRICE_COIN_UNIT | 1000 ether | 1,000 BURNIE | Conversion factor for BURNIE | DegenerusGameStorage.sol:125, BurnieCoinflip.sol:135, DegenerusQuests.sol:125, DegenerusAdmin.sol:344 |
| DEITY_RECYCLE_CAP | 1000000 ether | 1M BURNIE | Max BURNIE recycle from deity | BurnieCoinflip.sol:133 |
| DECIMATOR_MIN | 1000 ether | 1,000 BURNIE | Min BURNIE for decimator entry | BurnieCoin.sol:173 |
| DECIMATOR_BOON_CAP | 50000 ether | 50,000 BURNIE | Max BURNIE from decimator boon | BurnieCoin.sol:186, LootboxModule.sol:224 |
| DECIMATOR_MULTIPLIER_CAP | 200000 ether | 200,000 BURNIE | Decimator multiplier burn cap | DecimatorModule.sol:100 |
| COINFLIP_BOON_MAX_DEPOSIT | 100000 ether | 100,000 BURNIE | Max BURNIE deposit from coinflip boon | LootboxModule.sol:222 |
| INITIAL_SUPPLY | 1e30 | 1T DGNRS | Total DGNRS supply | DegenerusStonk.sol:151 |
| REFILL_SUPPLY | 1e30 | 1T BURNIE | Vault refill supply | DegenerusVault.sol:352 |
| LOOTBOX_WWXRP_PRIZE | 1 ether | 1 WWXRP | WWXRP prize per lootbox | LootboxModule.sol:295 |
| QUEST_ETH_TARGET_CAP | 0.5 ether | 0.5 ETH | Quest ETH target cap | DegenerusQuests.sol:194 |

**Degenerette Min Bets:**
| Constant | Value | Human | File:Line |
|----------|-------|-------|-----------|
| MIN_BET_ETH | 0.005 ether | 0.005 ETH | DegeneretteModule.sol:242 |
| MIN_BET_BURNIE | 100 ether | 100 BURNIE | DegeneretteModule.sol:245 |
| MIN_BET_WWXRP | 1 ether | 1 WWXRP | DegeneretteModule.sol:248 |
| CONSOLATION_MIN_ETH | 0.01 ether | 0.01 ETH | DegeneretteModule.sol:254 |
| CONSOLATION_MIN_BURNIE | 500 ether | 500 BURNIE | DegeneretteModule.sol:255 |
| CONSOLATION_MIN_WWXRP | 20 ether | 20 WWXRP | DegeneretteModule.sol:256 |
| CONSOLATION_PRIZE_WWXRP | 1 ether | 1 WWXRP | DegeneretteModule.sol:259 |

### Timing Constants (~15 unique)

| Constant | Value | Human | Purpose | File:Line |
|----------|-------|-------|---------|-----------|
| DEPLOY_IDLE_TIMEOUT_DAYS | 365 | 1 year | Death clock timeout at level 0 | DegenerusGame.sol:185, AdvanceModule.sol:91, Storage.sol:164 |
| (implicit level timeout) | 120 days | 120 days | Death clock timeout at level 1+ | AdvanceModule.sol:382, Storage.sol:177 |
| DISTRESS_MODE_HOURS | 6 | 6 hours | Hours before gameover when distress activates | Storage.sol:161 |
| GAMEOVER_RNG_FALLBACK_DELAY | 3 days | 3 days | Fallback delay for VRF on gameover | AdvanceModule.sol:92 |
| COIN_CLAIM_DAYS | 90 | 90 days | Coinflip claim window (non-first) | BurnieCoinflip.sol:136 |
| COIN_CLAIM_FIRST_DAYS | 30 | 30 days | Coinflip first claim window | BurnieCoinflip.sol:137 |
| AUTO_REBUY_OFF_CLAIM_DAYS_MAX | 1095 | ~3 years | Max auto-rebuy off claim days | BurnieCoinflip.sol:138 |
| COIN_PURCHASE_CUTOFF | 90 days | 90 days | BURNIE purchase cutoff (120-30) | MintModule.sol:115 |
| COIN_PURCHASE_CUTOFF_LVL0 | 335 days | 335 days | BURNIE purchase cutoff level 0 (365-30) | MintModule.sol:116 |
| COINFLIP_BOON_EXPIRY_DAYS | 2 | 2 days | Coinflip boon expires after | BoonModule.sol:23 |
| LOOTBOX_BOOST_EXPIRY_DAYS | 2 | 2 days | Lootbox boost expires after | BoonModule.sol:24, MintModule.sol:102, WhaleModule.sol:85 |
| PURCHASE_BOOST_EXPIRY_DAYS | 4 | 4 days | Purchase boost expires after | BoonModule.sol:25 |
| DEITY_PASS_BOON_EXPIRY_DAYS | 4 | 4 days | Deity pass boon expires after | BoonModule.sol:26, WhaleModule.sol:160 |
| JACKPOT_RESET_TIME | 82620 | 22:57:00 UTC | Daily jackpot reset time (seconds after midnight) | JackpotModule.sol:102, GameTimeLib.sol:14, BurnieCoinflip.sol:134 |
| LINK_ETH_MAX_STALE | 1 days | 1 day | Max staleness for LINK/ETH oracle | DegenerusAdmin.sol:350 |

### Operational/Structural Constants

| Constant | Value | Purpose | File:Line |
|----------|-------|---------|-----------|
| TICKET_SCALE | 100 | Fractional ticket scale (2 dp) | Storage.sol:129 |
| AFKING_LOCK_LEVELS | 5 | Levels locked for afKing | DegenerusGame.sol:195 |
| PASS_STREAK_FLOOR_POINTS | 50 | Min streak points for pass activity | DegenerusGame.sol:219, DegeneretteModule.sol:228 |
| PASS_MINT_COUNT_FLOOR_POINTS | 25 | Min mint count floor points | DegenerusGame.sol:221, DegeneretteModule.sol:230 |
| EARLYBIRD_END_LEVEL | 3 | Level where earlybird ends | Storage.sol:141 |
| MID_DAY_SWAP_THRESHOLD | 440 | Ticket queue swap trigger | Storage.sol:158 |
| JACKPOT_LEVEL_CAP | 5 | Max jackpot phase days | JackpotModule.sol:105, MintModule.sol:119, AdvanceModule.sol:93 |
| LAZY_PASS_LEVELS | 10 | Levels covered by lazy pass | WhaleModule.sol:109 |
| LAZY_PASS_TICKETS_PER_LEVEL | 4 | Tickets per level from lazy pass | WhaleModule.sol:112 |
| WHALE_BONUS_TICKETS_PER_LEVEL | 40 | Bonus tickets per level (whale) | WhaleModule.sol:133 |
| WHALE_STANDARD_TICKETS_PER_LEVEL | 2 | Standard tickets per level (whale) | WhaleModule.sol:136 |
| WHALE_BONUS_END_LEVEL | 10 | Level where whale bonus ends | WhaleModule.sol:139 |
| VAULT_PERPETUAL_TICKETS | 16 | Perpetual vault tickets per advance | AdvanceModule.sol:99 |
| ETH_PERK_ODDS | 100 | 1-in-100 ETH perk chance | AdvanceModule.sol:100 |
| VRF_CALLBACK_GAS_LIMIT | 300000 | VRF callback gas | AdvanceModule.sol:94 |
| VRF_REQUEST_CONFIRMATIONS | 10 | VRF confirmations (normal) | AdvanceModule.sol:95 |
| VRF_MIDDAY_CONFIRMATIONS | 3 | VRF confirmations (midday) | AdvanceModule.sol:96 |
| AFFILIATE_BONUS_MAX | 50 | Max affiliate bonus tier | DegenerusAffiliate.sol:196 |
| MAX_KICKBACK_PCT | 25 | Max kickback percentage | DegenerusAffiliate.sol:197 |
| LOOTBOX_TAPER_START_SCORE | 15000 | Activity score where taper begins | DegenerusAffiliate.sol:202 |
| LOOTBOX_TAPER_END_SCORE | 25500 | Activity score where taper maxes | DegenerusAffiliate.sol:203 |
| DECIMATOR_BUCKET_BASE | 12 | Base bucket for decimator | BurnieCoin.sol:176 |
| DECIMATOR_MIN_BUCKET_NORMAL | 5 | Min bucket (normal levels) | BurnieCoin.sol:179 |
| DECIMATOR_MIN_BUCKET_100 | 2 | Min bucket (level 100+) | BurnieCoin.sol:180 |
| DECIMATOR_MAX_DENOM | 12 | Max denominator for decimator | DecimatorModule.sol:103 |
| COINFLIP_EXTRA_MIN_PERCENT | 78 | Min extra payout percent | BurnieCoinflip.sol:121 |
| COINFLIP_EXTRA_RANGE | 38 | Extra payout range | BurnieCoinflip.sol:122 |
| MAX_SPINS_PER_BET | 10 | Max degenerette spins per bet | DegeneretteModule.sol:251 |
| DEITY_PASS_MAX_TOTAL | 32 | Max deity passes per player | LootboxModule.sol:214 |
| DEITY_DAILY_BOON_COUNT | 3 | Deity boons per day | LootboxModule.sol:351, DeityBoonViewer.sol:20 |
| MAX_BUCKET_WINNERS | 250 | Max winners per jackpot bucket | JackpotModule.sol:186 |
| JACKPOT_MAX_WINNERS | 300 | Max total jackpot winners | JackpotModule.sol:193 |
| DAILY_ETH_MAX_WINNERS | 321 | Max daily ETH winners | JackpotModule.sol:196 |
| DAILY_CARRYOVER_MIN_WINNERS | 20 | Min carryover winners | JackpotModule.sol:200 |
| DAILY_COIN_MAX_WINNERS | 50 | Max daily BURNIE winners | JackpotModule.sol:203 |
| FAR_FUTURE_COIN_SAMPLES | 10 | Samples for far-future coin | JackpotModule.sol:212 |
| LOOTBOX_MAX_WINNERS | 100 | Max lootbox winners | JackpotModule.sol:222 |
| DAILY_JACKPOT_UNITS_SAFE | 1000 | Safe jackpot units | JackpotModule.sol:167 |
| DAILY_JACKPOT_UNITS_AUTOREBUY | 3 | Auto-rebuy jackpot units | JackpotModule.sol:170 |
| DAILY_CARRYOVER_MAX_OFFSET | 5 | Max carryover source offset | JackpotModule.sol:140 |
| BAF_SCATTER_TICKET_WINNERS | 40 | BAF scatter ticket winners | DegenerusJackpots.sol:114 |
| BAF_SCATTER_ROUNDS | 50 | BAF scatter rounds | DegenerusJackpots.sol:117 |
| DECIMATOR_SPECIAL_LEVEL | 100 | Special decimator quest level | DegenerusQuests.sol:197 |
| QUEST_SLOT_COUNT | 2 | Quest slots per player | DegenerusQuests.sol:132 |
| QUEST_SLOT0_REWARD | 100 ether | 100 BURNIE per slot 0 quest | DegenerusQuests.sol:135 |
| QUEST_RANDOM_REWARD | 200 ether | 200 BURNIE random quest reward | DegenerusQuests.sol:138 |
| QUEST_MINT_TARGET | 1 | 1 mint to complete quest | DegenerusQuests.sol:182 |
| QUEST_BURNIE_TARGET | 2000 ether | 2,000 BURNIE | DegenerusQuests.sol:185 |
| QUEST_LOOTBOX_TARGET_MULTIPLIER | 2 | 2x lootbox target | DegenerusQuests.sol:188 |
| QUEST_DEPOSIT_ETH_TARGET_MULTIPLIER | 1 | 1x ETH deposit target | DegenerusQuests.sol:191 |
| WRITES_BUDGET_SAFE | 550 | Gas-safe write budget | JackpotModule.sol:160, MintModule.sol:80 |

### Deity Boon Weights (complete table)

| Boon | ID | Weight | P(all) | File:Line |
|------|-----|--------|--------|-----------|
| Coinflip +5% | 1 | 200 | 15.41% | DeityBoonViewer.sol:50 |
| Coinflip +10% | 2 | 40 | 3.08% | DeityBoonViewer.sol:51 |
| Coinflip +25% | 3 | 8 | 0.62% | DeityBoonViewer.sol:52 |
| Lootbox +5% | 5 | 200 | 15.41% | DeityBoonViewer.sol:53 |
| Lootbox +15% | 6 | 30 | 2.31% | DeityBoonViewer.sol:54 |
| Lootbox +25% | 22 | 8 | 0.62% | DeityBoonViewer.sol:38 |
| Purchase +5% | 7 | 400 | 30.82% | DeityBoonViewer.sol:56 |
| Purchase +15% | 8 | 80 | 6.16% | DeityBoonViewer.sol:57 |
| Purchase +25% | 9 | 16 | 1.23% | DeityBoonViewer.sol:58 |
| Decimator +10% | 13 | 40 | 3.08% | DeityBoonViewer.sol:59 |
| Decimator +25% | 14 | 8 | 0.62% | DeityBoonViewer.sol:60 |
| Decimator +50% | 15 | 2 | 0.15% | DeityBoonViewer.sol:61 |
| Whale -10% | 16 | 28 | 2.16% | DeityBoonViewer.sol:62 |
| Whale -25% | 23 | 10 | 0.77% | DeityBoonViewer.sol:63 |
| Whale -50% | 24 | 2 | 0.15% | DeityBoonViewer.sol:64 |
| Deity Pass -10% | 25 | 28 | 2.16% | DeityBoonViewer.sol:65 |
| Deity Pass -25% | 26 | 10 | 0.77% | DeityBoonViewer.sol:66 |
| Deity Pass -50% | 27 | 2 | 0.15% | DeityBoonViewer.sol:67 |
| Activity +10 | 17 | 100 | 7.70% | DeityBoonViewer.sol:68 |
| Activity +25 | 18 | 30 | 2.31% | DeityBoonViewer.sol:69 |
| Activity +50 | 19 | 8 | 0.62% | DeityBoonViewer.sol:70 |
| Whale Pass | 28 | 8 | 0.62% | DeityBoonViewer.sol:71 |
| Lazy Pass -10% | 29 | 30 | 2.31% | DeityBoonViewer.sol:72 |
| Lazy Pass -25% | 30 | 8 | 0.62% | DeityBoonViewer.sol:73 |
| Lazy Pass -50% | 31 | 2 | 0.15% | DeityBoonViewer.sol:74 |
| Deity Pass (all) | - | 40 | 3.08% | DeityBoonViewer.sol:75 |
| **TOTAL** | - | **1298** | 100% | DeityBoonViewer.sol:76 |
| *Total (no decimator)* | - | *1248* | - | DeityBoonViewer.sol:77 |

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Constant extraction | Manual reading | grep for `constant` declarations | 500+ lines of constants -- manual extraction would miss entries |
| Value interpretation | Mental arithmetic | Document exact Solidity literal + human-readable conversion side by side | Prevent ETH vs wei vs BURNIE unit confusion |
| Deduplication | Assume unique | Track all locations for each constant | Same constant redeclared in 2-3 modules |
| Prior audit cross-ref | Re-derive purposes | Pull descriptions from audit/v1.1-*.md files | Phases 6-10 already documented constant purposes |

## Common Pitfalls

### Pitfall 1: Unit Confusion
**What goes wrong:** Constants declared as `X ether` mean different things for different tokens -- BURNIE uses 18 decimals, so `100 ether` means 100 BURNIE, not 100 ETH.
**Why it happens:** Solidity `ether` keyword is just `* 10^18`, used for any 18-decimal token.
**How to avoid:** Always include the token unit in the human-readable column (e.g., "100 BURNIE" not "100 ether").
**Warning signs:** Any constant with `ether` suffix in BurnieCoin.sol, BurnieCoinflip.sol, or quest contracts.

### Pitfall 2: Half-BPS Units
**What goes wrong:** Two constants (`AFKING_DEITY_BONUS_PER_LEVEL_HALF_BPS`, `AFKING_DEITY_BONUS_MAX_HALF_BPS`) use half-BPS scale (divide by 20,000 not 10,000).
**Why it happens:** Precision optimization in the coinflip recycling math.
**How to avoid:** Flag half-BPS constants explicitly in the table with a note.

### Pitfall 3: Missing Inline Constants
**What goes wrong:** Some critical values are inline literals, not named constants -- e.g., `120 days` level timeout in AdvanceModule.sol:382, `5 days` final purchase window in DegenerusGame.sol:2237.
**Why it happens:** Developer chose not to extract to named constant.
**How to avoid:** Include a section for "implicit/inline constants" noting key values that are hardcoded but not named.

### Pitfall 4: Duplicate Constants Across Modules
**What goes wrong:** Assuming a constant appears in only one file when it's actually redeclared in 2-3 modules.
**Why it happens:** Modules can't share private constants via inheritance (delegatecall pattern).
**How to avoid:** List ALL locations for each constant; verified no value discrepancies in this codebase.

### Pitfall 5: PPM vs BPS Scales
**What goes wrong:** Some constants use parts-per-million (PPM) scale while most use BPS (parts per 10,000).
**Why it happens:** Whale DGNRS rewards and lootbox DGNRS rewards need finer precision.
**How to avoid:** Separate PPM constants into their own subsection with explicit scale notation.

## Architecture Patterns

### Recommended Document Organization

The output document should follow this pattern for agent consumption:

1. **Section per constant category** (BPS, ETH, Timing, Operational)
2. **Sub-section per subsystem** within each category (Pool Splits, Coinflip, Lootbox, etc.)
3. **Consistent table format** across all sections
4. **Alphabetical cross-reference index** at the end for quick lookup
5. **Inline constants section** for hardcoded values without named constants

### Cross-Reference Pattern

Each table entry should include which prior audit document discusses this constant in context, enabling agents to look up the full explanation:

```
| Constant | ... | Audit Ref |
|----------|-----|-----------|
| PURCHASE_TO_FUTURE_BPS | ... | 06-pool-architecture.md |
```

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Manual verification against contract source |
| Config file | N/A (documentation phase) |
| Quick run command | `grep -c "private constant\|internal constant" contracts/**/*.sol` |
| Full suite command | N/A |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PARM-01 | BPS constants table completeness | manual | Verify count against grep output | N/A |
| PARM-02 | ETH thresholds table completeness | manual | Verify all ether-valued constants included | N/A |
| PARM-03 | Timing constants table completeness | manual | Verify all DAYS/HOURS constants included | N/A |

### Sampling Rate
- **Per task commit:** Verify constant count matches grep baseline
- **Per wave merge:** N/A (single-plan phase)
- **Phase gate:** All constants from research inventory appear in output document

### Wave 0 Gaps
None -- this is a documentation-only phase requiring no test infrastructure.

## Open Questions

1. **Packed constants (FINAL_DAY_SHARES_PACKED, DAILY_JACKPOT_SHARES_PACKED, HERO_BOOST_PACKED, QUICK_PLAY_BASE_PAYOUTS_PACKED)**
   - What we know: These are uint64/uint256 values encoding multiple sub-values via bit packing
   - What's unclear: Whether to unpack and document individual sub-values or just reference the packed value
   - Recommendation: Document the packed constant with a note pointing to the prior audit doc that explains the unpacked values (e.g., FINAL_DAY_SHARES_PACKED = [6000, 1333, 1333, 1334] per JackpotModule.sol:111 comment)

2. **FUTURE_DUMP_ODDS precision**
   - What we know: `FUTURE_DUMP_ODDS = 1_000_000_000_000_000` (1e15) -- this is 1-in-1e15 odds
   - What's unclear: Whether this should be categorized as operational or as a probability constant
   - Recommendation: Include in operational section with note "effectively zero probability -- easter egg"

## Sources

### Primary (HIGH confidence)
- Direct grep of all `private constant` and `internal constant` declarations across contracts/ directory
- Line-by-line verification of values against Solidity source
- PriceLookupLib.sol full source review for inline pricing tiers

### Confidence Assessment
All findings are HIGH confidence -- derived directly from contract source code with exact file:line references. No external sources needed for this documentation consolidation phase.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - direct source extraction
- Architecture: HIGH - follows established audit document patterns from phases 6-10
- Pitfalls: HIGH - based on observed patterns in codebase (unit confusion, half-BPS, duplicates)

**Research date:** 2026-03-12
**Valid until:** Indefinite (constants are immutable in deployed contracts)
