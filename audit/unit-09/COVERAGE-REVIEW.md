# Unit 9: Lootbox + Boons -- Coverage Review

**Reviewer:** Taskmaster (coverage verification)
**Date:** 2026-03-25

---

## Function Checklist Verification

| # | Function | Analyzed? | Call Tree Complete? | Storage Writes Complete? | Cache Check Done? |
|---|----------|-----------|--------------------|-----------------------|------------------|
| B1 | openLootBox | YES | YES | YES | YES |
| B2 | openBurnieLootBox | YES | YES | YES | YES |
| B3 | resolveLootboxDirect | YES | YES | YES | YES |
| B4 | resolveRedemptionLootbox | YES | YES | YES | YES |
| B5 | issueDeityBoon | YES | YES | YES | YES |
| B6 | consumeCoinflipBoon | YES | YES | YES | YES |
| B7 | consumePurchaseBoost | YES | YES | YES | YES |
| B8 | consumeDecimatorBoost | YES | YES | YES | YES |
| B9 | checkAndClearExpiredBoon | YES | YES | YES | YES |
| B10 | consumeActivityBoon | YES | YES | YES | YES |
| C1 | _resolveLootboxCommon | YES | YES | YES | YES |
| C2 | _rollLootboxBoons | YES (within C1 tree) | YES | YES | YES |
| C3 | _resolveLootboxRoll | YES (within C1 tree) | YES | YES | N/A (called within C1) |
| C4 | _applyBoon | YES (standalone - MULTI-PARENT) | YES | YES | YES |
| C5 | _activateWhalePass | YES (within C4 tree) | YES | YES | N/A (called within C4) |
| C6 | _applyEvMultiplierWithCap | YES (standalone - MULTI-PARENT) | YES | YES | YES |
| C10 | _creditDgnrsReward | YES (within C3 tree) | YES | YES | N/A (single call) |
| D1-D15 | View/Pure functions | All reviewed | N/A | N/A | N/A |

## Coverage Gaps Found

**None.** All 32 functions have corresponding analysis sections in the attack report.

## Interrogation Log

### Q1: _boonFromRoll default return path
**Question:** The Mad Genius did not explicitly analyze what happens if _boonFromRoll returns 0 (default). Can boonType=0 reach _applyBoon?
**Answer (from Skeptic review):** The Skeptic independently verified this is unreachable. The roll is scaled against totalWeight which exactly matches the cursor walk in _boonFromRoll (both skip the same disabled pools). The default return of 0 is dead code. SATISFIED.

### Q2: BP_COINFLIP_CLEAR mask correctness
**Question:** The Mad Genius flagged "INVESTIGATE -- need to verify BP_COINFLIP_CLEAR preserves lootbox, purchase, decimator, and whale fields." Was this verified?
**Answer:** The clear masks are defined in DegenerusGameStorage.sol. Each BP_*_CLEAR mask zeroes only the bits belonging to that boon category and preserves all others. The Skeptic's bit packing review confirms no cross-category bit corruption. SATISFIED.

### Q3: Nested delegatecall to consumeActivityBoon after _rollLootboxBoons
**Question:** After _rollLootboxBoons applies a boon (writing boonPacked), does the subsequent consumeActivityBoon (which also writes boonPacked.slot1) interfere?
**Answer:** No. _applyBoon writes to the CATEGORY-specific fields of boonPacked. consumeActivityBoon writes to the ACTIVITY-specific fields using BP_ACTIVITY_CLEAR. These are non-overlapping bit ranges within slot1. The BP_ACTIVITY_CLEAR mask preserves all non-activity fields. SATISFIED.

### Q4: EV cap tracking when evMultiplierBps < NEUTRAL
**Question:** Does the EV cap limit penalties as well as bonuses?
**Answer:** Yes. The Mad Genius explicitly documents: "When EV < 100% (penalty), the cap LIMITS the penalty -- only the first 10 ETH of a level gets penalized." This is intentional bidirectional capping. SATISFIED.

## Verdict: PASS

All 32 functions covered. All call trees fully expanded. All storage writes mapped. All cached-local-vs-storage checks present for applicable functions. Multi-parent helpers (C1, C4, C6) received standalone analysis. The nested delegatecall state coherence has been independently verified by both the Mad Genius and the Skeptic.

**Coverage: 100%** (10 B + 7 C + 15 D = 32 functions)

---

*Coverage review completed: 2026-03-25*
*Verdict: PASS -- 100% coverage achieved.*
