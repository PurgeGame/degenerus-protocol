---
phase: 07-jackpot-distribution-mechanics
verified: 2026-03-12T15:10:00Z
status: passed
score: 9/9 must-haves verified
re_verification: false
---

# Phase 7: Jackpot Distribution Mechanics Verification Report

**Phase Goal:** A game theory agent can compute expected payouts across all distribution events — daily purchase-phase drip, jackpot-phase 5-day draws, and transition jackpots (BAF/Decimator)
**Verified:** 2026-03-12T15:10:00Z
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Agent can compute exact daily ETH drip from future pool during purchase phase with formula and all constants | VERIFIED | `v1.1-purchase-phase-distribution.md` section 2 documents `payDailyJackpot(isDaily=false)` lines 613-671 with complete formula, trigger conditions, lootbox split, and worked example |
| 2 | Agent can compute the BURNIE jackpot budget, split, and winner selection for purchase-phase daily draws | VERIFIED | `v1.1-purchase-phase-distribution.md` section 3 documents `payDailyCoinJackpot()` lines 2390-2435 with `_calcDailyCoinBudget()` line 2678, 75/25 near/far split, and coinflip credit payment |
| 3 | Purchase-phase lootbox conversion ratio (75%) and ticket count derivation are documented with exact expressions | VERIFIED | `v1.1-purchase-phase-distribution.md` section 4 consolidates lootbox mechanics, over-collateralization (2x backing), and cross-references jackpot-phase ratios |
| 4 | Agent can compute exact ETH payout per jackpot-phase day given currentPrizePool and a random seed | VERIFIED | `v1.1-jackpot-phase-draws.md` section 2 documents `_dailyCurrentPoolBps()` line 2687 with full Solidity expression, day-by-day BPS table, and agent simulation pseudocode appendix |
| 5 | Agent can determine which trait buckets are eligible each day and their share percentages | VERIFIED | `v1.1-jackpot-phase-draws.md` section 3 documents trait encoding, winning trait derivation, `DAILY_JACKPOT_SHARES_PACKED` and `FINAL_DAY_SHARES_PACKED`, hero override, virtual deity entries, and winner scaling |
| 6 | Carryover mechanics (days 2-4) and early-bird (day 1) are documented as distinct flows with exact formulas | VERIFIED | `v1.1-jackpot-phase-draws.md` sections 4 and 5 separately document each flow with Solidity expressions; section 6 documents compressed jackpot with physical vs logical day mapping table |
| 7 | Compressed jackpot conditions and effects (counterStep=2, BPS doubling) are fully specified | VERIFIED | `v1.1-jackpot-phase-draws.md` section 6 documents trigger condition (AdvanceModule:245), `counterStep=2`, `dailyBps *= 2`, and the 3-physical-day mapping table |
| 8 | Agent can determine exactly which levels trigger BAF and Decimator and the pool percentage for each | VERIFIED | `v1.1-transition-jackpots.md` sections 2 and 5 plus the combined level schedule table (levels 1-110) document all triggers with exact Solidity conditions and pool % per source variable |
| 9 | BAF payout split mechanics, Decimator burn tracking/resolution/claim mechanics are fully specified | VERIFIED | `v1.1-transition-jackpots.md` sections 3-4 (BAF) and 6-8 (Decimator) document all mechanics with `DECIMATOR_MULTIPLIER_CAP`, pro-rata formula, 50/50 ETH/lootbox split, and claim expiry |

**Score:** 9/9 truths verified

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `audit/v1.1-purchase-phase-distribution.md` | Complete purchase-phase distribution reference | VERIFIED | 382 lines, 5 sections, 15-entry constants table, worked examples; contains `PURCHASE_REWARD_JACKPOT_LOOTBOX_BPS` |
| `audit/v1.1-jackpot-phase-draws.md` | Complete 5-day jackpot-phase draw reference | VERIFIED | 645 lines, 9 sections + pseudocode appendix, 26-entry constants table; contains `_dailyCurrentPoolBps` |
| `audit/v1.1-transition-jackpots.md` | Complete BAF and Decimator transition jackpot reference | VERIFIED | 636 lines, 11 sections, combined level schedule table (levels 1-110), 11-entry constants table; contains `DECIMATOR_MULTIPLIER_CAP` |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `v1.1-purchase-phase-distribution.md` | `DegenerusGameJackpotModule.sol` | Formulas with exact line numbers | VERIFIED | 31 occurrences of `JackpotModule:[line]` references |
| `v1.1-purchase-phase-distribution.md` | `audit/v1.1-pool-architecture.md` | futurePool/futurePrizePool references | VERIFIED | 8 occurrences; explicit pool lifecycle cross-reference in section 1 |
| `v1.1-jackpot-phase-draws.md` | `DegenerusGameJackpotModule.sol` | Formulas with exact line numbers | VERIFIED | 41 occurrences of `JackpotModule:[line]` references |
| `v1.1-jackpot-phase-draws.md` | `audit/v1.1-pool-architecture.md` | currentPrizePool/freeze mechanics references | VERIFIED | 18 occurrences of `currentPrizePool`/`freeze` |
| `v1.1-transition-jackpots.md` | `DegenerusGameEndgameModule.sol` | BAF formulas with exact line numbers | VERIFIED | 27 occurrences of `EndgameModule:[line]` references |
| `v1.1-transition-jackpots.md` | `DegenerusGameDecimatorModule.sol` | Decimator formulas with exact line numbers | VERIFIED | 25 occurrences of `DecimatorModule:[line]` references |
| `v1.1-transition-jackpots.md` | `audit/v1.1-pool-architecture.md` | futurePrizePool/baseFuturePool references | VERIFIED | 75 total occurrences of `baseFuturePool`/`futurePoolLocal`/`LOOTBOX_CLAIM_THRESHOLD`/`lastDecClaimRound` combined |

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| JACK-01 | 07-01 | Daily purchase-phase future pool drip with exact formulas and triggers | SATISFIED | Section 2 of `v1.1-purchase-phase-distribution.md`: trigger conditions, 1% pool slice, lootbox conversion, worked example |
| JACK-02 | 07-01 | Daily purchase-phase BURNIE jackpots with winner selection and payout formulas | SATISFIED | Section 3 of `v1.1-purchase-phase-distribution.md`: budget formula, 75/25 near/far split, near/far winner selection, coinflip credit payment |
| JACK-03 | 07-02 | 5-day jackpot-phase draw mechanics with daily pool slice formulas (6-14% random, 100% day 5) | SATISFIED | Section 2 of `v1.1-jackpot-phase-draws.md`: `_dailyCurrentPoolBps()` with exact Solidity, BPS range table, budget 80/20 split |
| JACK-04 | 07-02 | Trait bucket distribution and winner selection per jackpot-phase day | SATISFIED | Section 3 of `v1.1-jackpot-phase-draws.md`: encoding, derivation, share constants, scaling, `_randTraitTicket()`, solo bucket handling |
| JACK-05 | 07-02 | Carryover ETH mechanics and compressed jackpot conditions | SATISFIED | Sections 5 and 6 of `v1.1-jackpot-phase-draws.md`: carryover source selection, lootbox split, winner cap, compressed mode trigger and effect |
| JACK-06 | 07-01, 07-02 | Lootbox conversion ratios (50% daily, 75% reward jackpots) | SATISFIED | Section 4 of `v1.1-purchase-phase-distribution.md` (purchase ratios) and section 7 of `v1.1-jackpot-phase-draws.md` (jackpot-phase cross-reference table) |
| JACK-07 | 07-02 | BURNIE jackpot-phase parallel distribution and far-future allocation | SATISFIED | Section 8 of `v1.1-jackpot-phase-draws.md`: same budget formula as purchase phase, 25%/75% split, far-future loop with `ticketQueue`, near-future `traitBurnTicket` |
| JACK-08 | 07-03 | BAF mechanics (every 10 levels, future pool percentages, lootbox conversion) | SATISFIED | Sections 2-4 of `v1.1-transition-jackpots.md`: exact trigger, pool% formula, large/small winner split, lootbox tiers (0.5/5 ETH thresholds), whale pass mechanics |
| JACK-09 | 07-03 | Decimator mechanics (level triggers, multiplier tiers, BURNIE burn requirements) | SATISFIED | Sections 5-9 of `v1.1-transition-jackpots.md`: window opening/closing, bucket/subbucket system, multiplier cap formula, resolution algorithm, pro-rata claim, expiry semantics |

No orphaned requirements — all 9 JACK IDs in REQUIREMENTS.md are claimed by a plan and documented.

---

## Anti-Patterns Found

No anti-patterns detected. All three audit documents are substantive prose with exact Solidity code blocks, line references, and worked examples. No TODOs, placeholders, or stub sections found.

---

## Human Verification Required

### 1. Contract Source Line Number Accuracy

**Test:** Open `contracts/modules/DegenerusGameJackpotModule.sol` and spot-check 3-5 line number references in the audit documents.
**Expected:** Solidity expressions cited in audit docs match the actual contract source at those line numbers.
**Why human:** Line numbers can shift with edits; automated grep confirms presence of terms but not their accuracy at cited lines.

### 2. Worked Example Arithmetic

**Test:** Manually re-derive the worked examples in section 2g of `v1.1-purchase-phase-distribution.md` and section 3e.
**Expected:** Arithmetic is self-consistent and matches the formula definitions.
**Why human:** Ensures no copy-paste errors in example numbers that would mislead agents.

### 3. Decimator Level Schedule Completeness

**Test:** Verify the combined level schedule table in `v1.1-transition-jackpots.md` section 10 against the AdvanceModule trigger conditions for levels 94-100 (the gap/special-case region).
**Expected:** Level 94 correctly shows "NOT opened", level 95 shows "NOT resolved", level 99 shows "Opens", level 100 shows both BAF and x00 Decimator.
**Why human:** This is the most complex exception region — a subtle off-by-one in the `prevMod100` logic could make the table wrong in ways that mislead agents about the 10-level gap.

---

## Notes

**Plan 02 summary naming discrepancy (informational only):** The `07-02-SUMMARY.md` `key-files.created` field lists `audit/07-jackpot-phase-draws.md` (missing the `v1.1-` prefix). The actual file on disk is `audit/v1.1-jackpot-phase-draws.md`, which is correct and consistent with all other phase 7 audit documents. The summary's `key-files` field is cosmetically wrong but does not affect the audit document itself. No action required.

---

*Verified: 2026-03-12T15:10:00Z*
*Verifier: Claude (gsd-verifier)*
