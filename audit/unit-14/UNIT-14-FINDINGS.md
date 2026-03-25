# Unit 14: Affiliate + Quests + Jackpots -- Final Findings Report

**Phase:** 116
**Contracts:** DegenerusAffiliate.sol, DegenerusQuests.sol, DegenerusJackpots.sol
**Audit Model:** Opus (claude-opus-4-6)
**Date:** 2026-03-25

---

## Executive Summary

Unit 14 audited three standalone peripheral contracts managing the affiliate referral system, daily quest progression, and BAF (Big Ass Flip) jackpot distribution. The audit covered 61 functions across 3 contracts, with 30 state-changing functions receiving full adversarial analysis including call tree expansion, storage write mapping, and cached-local-vs-storage checks.

**Result: ZERO confirmed vulnerabilities.** All contracts follow correct security patterns.

---

## Audit Statistics

| Metric | Value |
|--------|-------|
| Contracts audited | 3 (DegenerusAffiliate, DegenerusQuests, DegenerusJackpots) |
| Total functions | 61 |
| State-changing functions analyzed | 30 (13 Cat B + 17 Cat C) |
| View/pure functions catalogued | 31 |
| Category B (full attack analysis) | 13 |
| Category C (traced via parents) | 17 (8 MULTI-PARENT with standalone sections) |
| CRITICAL-tier functions | 2 (payAffiliate, runBafJackpot) |
| HIGH-tier functions | 3 (referPlayer, rollDailyQuest, recordBafFlip) |
| Cross-contract call sites traced | 10 |
| Storage variables mapped | 16 |
| Priority investigations completed | 7 |
| Findings: CRITICAL | 0 |
| Findings: HIGH | 0 |
| Findings: MEDIUM | 0 |
| Findings: LOW | 0 |
| Findings: INFO | 1 |
| Taskmaster Coverage | PASS (100%) |

---

## Confirmed Findings

**None.** All SAFE verdicts from Mad Genius analysis were independently confirmed by the Skeptic.

---

## INFO-Level Observations

### INFO-01: uint24 Underflow in BAF Scatter Level Targeting at Level 0

**Affected:** DegenerusJackpots::runBafJackpot scatter section (L396)
**Lines:** L396 (`uint24 maxBack = lvl > 99 ? 99 : lvl - 1`)

**Description:** When `lvl == 0` and `isCentury` is true (since `0 % 100 == 0`), the expression `lvl - 1` underflows to `16777215` (uint24 max) at L396. This causes scatter rounds 12-49 to query non-existent game levels via `sampleTraitTicketsAtLevel`, which returns empty ticket arrays. The affected scatter rounds produce no winners, and their prize amounts flow back to the future prize pool via `toReturn`.

**Practical Impact:** At the first-ever BAF resolution (level 0 to level 1 transition), 38 out of 50 scatter rounds would produce no winners. The unawarded ETH is recycled back into the future prize pool by the endgame module (L198-200 of DegenerusGameEndgameModule.sol). No ETH is lost. Given that level 0 has minimal prize pool (game just started), the practical effect is negligible.

**Root Cause:** The century-level scatter targeting code at L391-398 does not account for lvl==0 as a valid input. The code assumes lvl >= 100 for the century path, but `0 % 100 == 0` triggers the century path for lvl==0.

**Recommendation:** Add a guard for lvl==0 in the century scatter targeting:
```solidity
if (isCentury && lvl == 0) {
    targetLvl = lvl; // No historical levels to sample at game start
} else if (isCentury) {
    // existing logic
}
```

Alternatively, the endgame module could skip BAF resolution when `bafPoolWei` is below a minimum threshold, which would naturally skip lvl==0 (minimal pool).

**Severity:** INFO -- no security impact, no fund loss. Cosmetic edge case at first-ever BAF resolution.

---

## Key Audit Observations

### Affiliate System Security Model

The DegenerusAffiliate contract implements a robust multi-tier referral system:
- **Self-referral prevention:** L325 of `referPlayer` reverts on `referrer == msg.sender`. The upline chain is followed via single-hop lookups (not recursive), preventing infinite loops.
- **Referral locking:** Once set, referral codes are permanent (except VAULT referrals during presale). This prevents commission cap bypass via code rotation.
- **Commission cap:** Per-affiliate per-sender per-level cap (0.5 ETH BURNIE) prevents whale domination of any single affiliate's earnings.
- **Deterministic PRNG:** The weighted affiliate winner roll uses deterministic keccak256-based randomness. This is an acknowledged, documented design trade-off (L572) -- the approach is EV-neutral and manipulation can only redistribute between affiliates, not increase any party's expected value.

### Quest System Security Model

The DegenerusQuests contract uses a well-designed progress versioning system:
- **Version gating:** Every quest slot has a version counter. When quests roll for a new day, the version bumps and all stale progress is automatically invalidated. This prevents progress-carrying exploits.
- **Slot ordering:** Slot 1 completion requires slot 0 completion first. This is consistently enforced across all 6 handlers.
- **Double-completion prevention:** The completionMask uses bit flags with monotonic OR operations. Once set, a slot cannot trigger rewards again within the same day.
- **Streak shields:** Shield consumption is correctly ordered -- shields are used before streak is reset, preventing a race condition.

### BAF Jackpot Security Model

The DegenerusJackpots contract uses an epoch-based lazy-reset mechanism:
- **Epoch invalidation:** When a BAF jackpot resolves, the epoch increments. Subsequent `recordBafFlip` calls detect the epoch mismatch and reset the player's total to 0 before adding the new stake. This is gas-efficient and correct.
- **Prize accounting:** All 7 prize slices use the `_creditOrRefund` helper, which returns false for zero-address winners. Unawarded prizes accumulate in `toReturn` and are recycled to the future prize pool.
- **Scatter bounds:** Fixed-size arrays (50 elements) match the BAF_SCATTER_ROUNDS constant. No out-of-bounds risk.

---

## Cross-Contract Integration Assessment

| Integration Path | Assessment |
|-----------------|------------|
| Affiliate -> BurnieCoin (creditFlip, affiliateQuestReward) | SAFE: All affiliate-local state updates complete before external calls |
| BurnieCoin -> Quests (handleMint, handleFlip, etc.) | SAFE: Quest state is independent from caller state |
| BurnieCoin -> Jackpots (recordBafFlip) | SAFE: No reentrancy -- pure storage writes with no callbacks |
| Game Endgame -> Jackpots (runBafJackpot) | SAFE: View calls to game contract (sampleFarFutureTickets, sampleTraitTicketsAtLevel) are point-in-time reads. VRF word is unknown at all input commitment points |
| Game -> Quests (awardQuestStreakBonus) | SAFE: Direct streak increment with clamp, no complex interactions |
| Quest handlers -> Game (mintPrice, level, decWindowOpenFlag) | SAFE: Read-only queries of game state |

---

## Access Control Matrix (Unit 14)

| Function | Access | Guard |
|----------|--------|-------|
| createAffiliateCode | Anyone | None (permissionless) |
| referPlayer | Anyone | None (permissionless, self-referral blocked) |
| payAffiliate | COIN, GAME | `msg.sender != COIN && msg.sender != GAME` revert |
| rollDailyQuest | COIN, COINFLIP | `onlyCoin` modifier |
| awardQuestStreakBonus | GAME | `onlyGame` modifier |
| handleMint | COIN, COINFLIP | `onlyCoin` modifier |
| handleFlip | COIN, COINFLIP | `onlyCoin` modifier |
| handleDecimator | COIN, COINFLIP | `onlyCoin` modifier |
| handleAffiliate | COIN, COINFLIP | `onlyCoin` modifier |
| handleLootBox | COIN, COINFLIP | `onlyCoin` modifier |
| handleDegenerette | COIN, COINFLIP | `onlyCoin` modifier |
| recordBafFlip | COIN, COINFLIP | `onlyCoin` modifier |
| runBafJackpot | GAME | `onlyGame` modifier |

All access control gates use fixed `ContractAddresses.*` constants set at deploy time. No re-pointing, no admin override.

---

## Appendix: Audit Trail

| Stage | Output | Verdict |
|-------|--------|---------|
| Taskmaster Checklist | COVERAGE-CHECKLIST.md | 13 Cat B + 17 Cat C + 31 Cat D identified |
| Mad Genius Attack | ATTACK-REPORT.md | 1 INVESTIGATE finding, all others SAFE |
| Skeptic Review | SKEPTIC-REVIEW.md | Downgraded F-01 to INFO, all SAFE confirmed |
| Taskmaster Coverage | COVERAGE-REVIEW.md | PASS (100% coverage) |
| Final Report | UNIT-14-FINDINGS.md | 0 CRITICAL/HIGH/MEDIUM/LOW, 1 INFO |
