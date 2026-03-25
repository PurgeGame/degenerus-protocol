# Unit 9: Lootbox + Boons -- Final Findings Report

**Unit:** 9 -- Lootbox + Boons
**Contracts:** DegenerusGameLootboxModule.sol (1,864 lines), DegenerusGameBoonModule.sol (327 lines)
**Audit date:** 2026-03-25
**Methodology:** Three-agent adversarial system (ULTIMATE-AUDIT-DESIGN.md)

---

## Executive Summary

Unit 9 covers the lootbox resolution system (ETH, BURNIE, direct, redemption) and the boon system (lootbox-sourced boosts, deity boon issuance, boon consumption by other modules, and boon expiry management). The primary concern was the nested delegatecall pattern where LootboxModule calls BoonModule within the same transaction -- a pattern that could create BAF-class stale-cache bugs if either module cached storage that the other wrote.

**Result:** The nested delegatecall state coherence is SAFE. Both the Mad Genius and Skeptic independently verified that no function caches boonPacked or mintPacked_ before delegatecalling into BoonModule. All reads of these storage variables use fresh SLOADs after the delegatecall completes.

**No CRITICAL, HIGH, or MEDIUM findings.** One informational note regarding deity boon overwrite semantics.

---

## Scope

| Contract | Lines | Functions | Category B | Category C | Category D |
|----------|-------|-----------|-----------|-----------|-----------|
| DegenerusGameLootboxModule.sol | 1,864 | 27 | 5 | 7 | 15 |
| DegenerusGameBoonModule.sol | 327 | 5 | 5 | 0 | 0 |
| **Total** | **2,191** | **32** | **10** | **7** | **15** |

---

## Findings Summary

| ID | Severity | Title | Status |
|----|----------|-------|--------|
| F-01 | INFO | Deity boon overwrite can downgrade existing higher-tier lootbox boon | Confirmed (by design) |

**No CRITICAL, HIGH, MEDIUM, or LOW findings.**

---

## Detailed Findings

### F-01: Deity Boon Overwrite Can Downgrade Existing Higher-Tier Lootbox Boon

**Severity:** INFO
**Location:** `_applyBoon()` L1396-1601, all category handlers
**Mad Genius Verdict:** INVESTIGATE
**Skeptic Verdict:** CONFIRMED -- DOWNGRADE TO INFO

**Description:**
When a deity issues a boon (isDeity=true), the tier is always overwritten regardless of whether the new tier is higher or lower than the existing one. This is implemented via the `if (isDeity || newTier > existingTier)` pattern across all 8 boon category handlers. A deity issuing a low-tier boon to a player with an existing high-tier lootbox boon will downgrade the player's boon.

**Example scenario:**
1. Player has tier-3 (25%) coinflip boon from lootbox, valid for 2 more days
2. Deity issues BOON_COINFLIP_5 (tier-1, 5%) to player
3. Player's boon is overwritten to tier-1 (5%) with same-day deity expiry

**Why INFO (not vulnerability):**
- Deity passes cost 24+ ETH with quadratic pricing, max 32 total
- One boon per recipient per day rate limit
- Deity cannot see recipient's existing boon state on-chain
- Deity boon expires at end of day (shorter than lootbox boon)
- No economic profit for the attacker (pure griefing)
- This is intentional overwrite semantics consistent across all categories

**Recommendation:** No change needed. The deity overwrite semantic is a deliberate design choice that enables deities to "refresh" boons with specific types. The downgrade scenario requires an adversarial deity with knowledge of the recipient's boon state, which is an unlikely and low-impact attack.

---

## Key Security Verifications

### Nested Delegatecall State Coherence: SAFE

The primary investigation target for this unit was the nested delegatecall pattern:
```
LootboxModule._resolveLootboxCommon
  -> _rollLootboxBoons
    -> delegatecall BoonModule.checkAndClearExpiredBoon  [writes boonPacked]
    -> _activeBoonCategory                                [fresh SLOAD of boonPacked]
    -> _applyBoon                                         [fresh SLOAD of boonPacked]
  -> delegatecall BoonModule.consumeActivityBoon          [writes boonPacked.slot1 + mintPacked_]
```

**Verification:** Neither LootboxModule nor any function in the call chain caches boonPacked or mintPacked_ in a local variable before the delegatecalls. All subsequent reads use fresh SLOADs. Both the Mad Genius and Skeptic independently verified this claim by tracing every line of _rollLootboxBoons (L1038-1102) and _resolveLootboxCommon (L872-1026).

### EV Multiplier Cap: CORRECT

The per-account-per-level 10 ETH cap on EV adjustment (`_applyEvMultiplierWithCap`) correctly tracks cumulative benefit across multiple lootbox openings within the same level. The cap is bidirectional (limits both bonuses and penalties). Level transitions naturally reset the cap via new mapping keys.

### Boon Single-Category Constraint: CORRECT

The `_activeBoonCategory` check ensures players can only have one boon category active at a time. New boon rolls in a different category are silently discarded. The category check happens AFTER expired boon cleanup, ensuring the constraint reflects current state.

### RNG Commitment Window: SECURE

All lootbox entropy derives from `keccak256(rngWord, player, day, amount)` where the RNG word is set during VRF fulfillment (after player inputs are committed). Deity boon slots are deterministic per (deity, day, slot) and cannot be manipulated by the deity.

### Bit Packing Correctness: VERIFIED

The BoonPacked struct uses 2 storage slots with explicit bit ranges for 7 boon categories. Each category has a dedicated CLEAR mask that zeroes only its own bits. Cross-category interference is prevented by non-overlapping bit ranges.

---

## Coverage Metrics

| Metric | Value |
|--------|-------|
| Total functions analyzed | 32 |
| Category B (full attack analysis) | 10 |
| Category C (call tree analysis) | 7 |
| Category D (security review) | 15 |
| Multi-parent standalone analyses | 3 (C1, C4, C6) |
| Call trees fully expanded | YES (all Category B + C) |
| Storage writes mapped | YES (all Category B + C) |
| Cached-local-vs-storage checked | YES (all applicable) |
| VULNERABLE findings | 0 |
| INVESTIGATE findings | 1 (downgraded to INFO) |
| CONFIRMED findings | 0 (0 actionable) |
| Taskmaster coverage verdict | PASS (100%) |

---

## Informational Notes

1. **_boonFromRoll default return is unreachable.** The function can theoretically return 0 (default uint8) if no cursor threshold is hit, but this is proven unreachable because the roll is scaled against totalWeight which exactly covers the cursor walk space. No dead code issue -- this is a mathematical invariant of the weighted selection algorithm.

2. **BURNIE lootbox liveness cutoff uses block.timestamp.** The 90-day (335 for level 0) cutoff for shifting BURNIE lootbox tickets to future levels uses `block.timestamp - levelStartTime`. This is resistant to minor timestamp manipulation (seconds of drift don't matter against a 90-day window).

3. **Distress ticket bonus uint32 truncation.** The distress bonus calculation at L992-998 can theoretically overflow uint32 if futureTickets is near type(uint32).max (~4.3B). This requires astronomical ETH amounts and is not practically reachable.

---

*Unit 9 audit complete: 2026-03-25*
*Three-agent system: Taskmaster PASS, Mad Genius complete, Skeptic verified.*
*Result: 0 actionable findings. Nested delegatecall state coherence SAFE.*
