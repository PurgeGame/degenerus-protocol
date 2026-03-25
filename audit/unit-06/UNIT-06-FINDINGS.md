# Unit 6: Whale Purchases -- Final Findings

## Audit Scope
- **Contract:** DegenerusGameWhaleModule.sol (817 lines)
- **Inherits:** DegenerusGameMintStreakUtils (62 lines) -> DegenerusGameStorage (1,613 lines)
- **Audit type:** Three-agent adversarial (Taskmaster + Mad Genius + Skeptic)
- **Coverage verdict:** PASS (16/16 functions, 100%)
- **Functions analyzed:**
  - External state-changing (B): 3 (full analysis per D-02)
  - Internal helpers (C): 9 (via caller call trees; standalone for [MULTI-PARENT] per D-03)
  - View/Pure (D): 4 (minimal review)
- **Inherited helpers traced:** 12 (from DegenerusGameStorage and DegenerusGameMintStreakUtils)

## Findings Summary

| Severity | Count |
|----------|-------|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 0 |
| LOW | 0 |
| INFO | 1 |
| **Total** | **1** |

## Confirmed Findings

### [INFO] F-02: DGNRS Whale Pool Diminishing Returns in Multi-Quantity Purchase

**Location:** `DegenerusGameWhaleModule.sol` lines 284-287 (loop), lines 587-603 (pool read + transfer)
**Found by:** Mad Genius (Attack Report)
**Confirmed by:** Skeptic (Review, downgraded from LOW to INFO)
**Severity:** INFO -- by-design economic mechanics, no correctness issue

**Description:**
The DGNRS reward loop at line 284 calls `_rewardWhaleBundleDgnrs` once per `quantity` (up to 100). Each iteration reads a FRESH `dgnrs.poolBalance(IStakedDegenerusStonk.Pool.Whale)` at line 593. After each transfer, the pool balance decreases. This creates diminishing returns: the cumulative minter reward for quantity=100 is approximately 63.4% of the initial whale pool (using 1 - 0.99^100), not 100% x 1%.

**Impact:**
- Players purchasing multiple whale bundles in a single transaction receive less total DGNRS per ETH spent than if they purchased individually across separate transactions (assuming pool doesn't change between txs).
- The affiliate pool has an additional `reserved` guard (line 610-612) that prevents drain below the level claim allocation.
- No funds at risk. No state corruption. No exploitable attack vector.

**Root Cause:**
Per-iteration fresh pool balance reads cause geometric diminishment. This is standard economic design for token pool distributions -- it prevents complete pool drain.

**Recommendation:**
Consider documenting this behavior in player-facing documentation so multi-bundle buyers understand the per-unit DGNRS yield decreases with quantity. Alternatively, compute total reward as a single batch calculation for consistent per-unit rates. However, the current behavior may be intentionally anti-whale (discouraging single-tx bulk purchases).

**Evidence:**
- Mad Genius call tree: ATTACK-REPORT.md, B1 section, lines 284-287 / C4 analysis
- Skeptic verification: SKEPTIC-REVIEW.md, F-02 section (downgraded from LOW to INFO)

---

## Dismissed Findings (False Positives)

| ID | Title | Mad Genius Verdict | Skeptic Verdict | Reason |
|----|-------|--------------------|-----------------|--------|
| F-01 | Boon discount based on standard price at early levels | INVESTIGATE (INFO) | FALSE POSITIVE | Intentional pricing: boon discounts the standard 4 ETH price, not the early 2.4 ETH price. Player can choose not to use boon at early levels. |
| F-03 | Lazy pass cachedPacked in _recordLootboxMintDay | INVESTIGATE (INFO) | FALSE POSITIVE | Fresh read at L449 ensures cachedPacked reflects _activate10LevelPass write. Day matches, no write occurs. |
| F-04 | ERC721 mint callback re-entry | INVESTIGATE (INFO) | FALSE POSITIVE | Checks-effects-interactions pattern followed. All deity state written before external mint call. Re-entry blocked by deityPassCount guard. |
| F-05 | Deity pass ticket start level formula | INVESTIGATE (INFO) | FALSE POSITIVE | Intentional design: deity pass uses 50-level-aligned ticket ranges for phase coverage, different from whale bundle's rolling ranges. |
| F-06 | Lootbox EV score reflects post-purchase state | INVESTIGATE (INFO) | FALSE POSITIVE | Score differential from single purchase is negligible. Consistent across all callers. Not exploitable. |

---

## Cache-Overwrite (BAF Pattern) Verification

### Context
The BAF cache-overwrite bug pattern (ancestor caches storage variable, descendant writes to same variable, ancestor writes stale cache back) was the highest-priority concern for this audit. DegenerusGameWhaleModule has specific risks due to:
1. Lazy pass reads `mintPacked_[buyer]` then calls `_activate10LevelPass` which reads/writes `mintPacked_[buyer]`
2. All three purchase functions pass `cachedPacked` to `_recordLootboxMintDay` which conditionally writes `mintPacked_[buyer]`

### Verification Results

| Function | Cache Concern | Mad Genius Verdict | Skeptic Verification | Final |
|----------|-------------|-------------------|--------------------|-------|
| purchaseWhaleBundle | `data` passed to _recordLootboxMintDay | SAFE: data has current day, _recordLootboxMintDay returns without write | Verified: day set by _setMintDay matches _simulatedDayIndex | SAFE |
| purchaseLazyPass | `prevData` cached before _activate10LevelPass | SAFE: prevData used read-only for validation; fresh read at L449 for lootbox | Verified: fresh SLOAD at L449 reflects _activate10LevelPass write at Storage L1059 | SAFE |
| purchaseDeityPass | `s1Deity` cached before boon clear | SAFE: s1Deity used only for tier/expiry check; write uses s1Deity & CLEAR mask | Verified: no stale writeback; fresh read at L563 for lootbox | SAFE |

### Conclusion
All three purchase functions are SAFE for the BAF cache-overwrite pattern. Both agents independently verified: no ancestor caches a value that a descendant overwrites with different data.

---

## Coverage Statistics

| Metric | Value |
|--------|-------|
| Functions on checklist | 16 |
| Category B analyzed | 3/3 |
| Category C analyzed | 9/9 |
| [MULTI-PARENT] standalone | 2/2 |
| Category D reviewed | 4/4 |
| Inherited helpers traced | 12/12 |
| Coverage percentage | 100% |
| Taskmaster verdict | PASS |
| Skeptic checklist verification | PASS |

## Audit Trail

| Deliverable | Status | File |
|-------------|--------|------|
| Coverage Checklist | Complete (all YES) | audit/unit-06/COVERAGE-CHECKLIST.md |
| Attack Report | Complete | audit/unit-06/ATTACK-REPORT.md |
| Coverage Review | PASS | audit/unit-06/COVERAGE-REVIEW.md |
| Skeptic Review | Complete | audit/unit-06/SKEPTIC-REVIEW.md |
| Final Findings | This document | audit/unit-06/UNIT-06-FINDINGS.md |

---

*Unit 6 audit complete: 2026-03-25*
*Result: 0 CRITICAL, 0 HIGH, 0 MEDIUM, 0 LOW, 1 INFO. No BAF-class vulnerabilities found. DegenerusGameWhaleModule is assessed as secure for its intended purpose.*
