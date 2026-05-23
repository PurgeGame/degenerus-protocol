# Phase 309: SPEC — Locked Layout + Bonus-Only Cap + Shared-Cap Disposition (SPEC) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-20
**Phase:** 309-spec-locked-layout-bonus-only-cap-shared-cap-disposition-spe
**Areas discussed:** adjustedPortion width (conflict), Co-pack scope, Rename, Shared-cap disposition (SPEC-04)

---

## adjustedPortion field width (doc conflict)

| Option | Description | Selected |
|--------|-------------|----------|
| uint64 | Tightest standard width holding the 10 ETH cap (max ≈ 18.44 ETH). Layout bits[0:16]=score+1, bits[16:80]=adjustedPortion. Resolves the REQUIREMENTS-vs-fix-plan conflict toward REQUIREMENTS.md. | ✓ |
| uint96 | What the fix-plan literally wrote (bits[16:112]). Wasteful for a ≤18.44 ETH value; contradicts feedback_frozen_contracts_no_future_proofing. | |

**User's choice:** uint64
**Notes:** REQUIREMENTS.md SPEC-01 said uint64; the v45 fix-plan said uint96 — direct conflict surfaced during analysis. `ceil(log2(1e19)) = 64` and a single box's accumulated adjustedPortion can never exceed the cap, so uint64 is both sufficient and tightest. Matches feedback_maximal_variable_packing + the REQUIREMENTS gas directive. Fix-plan's uint96 treated as superseded.

---

## Co-pack scope

| Option | Description | Selected |
|--------|-------------|----------|
| No co-pack | Lock the word to score+1 + adjustedPortion only (literal SPEC-01 answer; no other cap-bounded field exists). | |
| Investigate candidates first | Scan per-(index, player) state to confirm nothing else folds in / saves a slot. | ✓ |

**User's choice:** Investigate candidates first → then (follow-up) Co-pack baseLevel too
**Notes:** Investigation found two same-key-shape candidates: `lootboxDay` (uint32) and `lootboxBaseLevelPacked` (uint24). `lootboxDay` REJECTED — it feeds the frozen seed keccak(rngWord,player,day,amount) at LootboxModule.sol:545 (INV-04). `lootboxBaseLevelPacked` is viable (same key/lifecycle, all sites in-scope, not a seed input, accumulation already RMWs the word). Follow-up decision below.

### Follow-up: lootboxBaseLevelPacked co-pack

| Option | Description | Selected |
|--------|-------------|----------|
| Keep surgical | Lock word to score+1 + adjustedPortion only; document baseLevel as deferred candidate. Minimizes delta-audit surface; respects security-over-gas. | |
| Co-pack baseLevel too | Fold baseLevel+1 (uint24) into the word → saves one cold slot, honoring the maximal-packing directive; removes lootboxBaseLevelPacked. | ✓ |

**User's choice:** Co-pack baseLevel too
**Notes:** Final word: [0:16] score+1 | [16:80] adjustedPortion(uint64) | [80:104] baseLevel+1(uint24) | [104:256] free. Net −1 storage slot; zero-at-open clears all three in one SSTORE. Expands IMPL-02 + the Phase 313 delta-audit surface, accepted by the user for the packing win.

---

## Rename

| Option | Description | Selected |
|--------|-------------|----------|
| lootboxPurchasePacked | Neutral name for the merged purchase-time word (score + adjustedPortion + baseLevel). Most accurate post-merge. | ✓ |
| lootboxEvPacked | The fix-plan's original suggestion (when EV-only); now slightly misleading. | |
| Keep lootboxEvScorePacked | No rename; narrowest diff but doubly-inaccurate name. | |

**User's choice:** lootboxPurchasePacked
**Notes:** The word now also carries baseLevel, so an EV-only name undersells it. `lootboxPurchasePacked` replaces BOTH `lootboxEvScorePacked` and `lootboxBaseLevelPacked`. Helpers `_packLootboxPurchase(uint16,uint64,uint24)→uint256` / `_unpackLootboxPurchase→(uint16,uint64,uint24)`.

---

## Shared-cap disposition (SPEC-04)

| Option | Description | Selected |
|--------|-------------|----------|
| Accept + document | Word-independence backward-trace: frozen-activityScore multiplier (not rngWord), raw amount→seed, purchased boxes allocate pre-word, order-steering of scarce cap is word-independent → not a freeze violation; accepted self-MEV. Enumerate all in-window SLOADs. | ✓ |
| Fix the shared path too | Add deterministic resolution-time cap allocation. Wider scope on a frozen contract; unnecessary if word-independence holds. | |
| Trace deeper before deciding | Defer the verdict to the SPEC artifact after full SLOAD enumeration. | |

**User's choice:** Accept + document
**Notes:** Verified at LootboxModule.sol:674/710 that evMultiplierBps comes from the frozen activityScore parameter (decimator=bucket-at-burn, degenerette=bet-time, redemption=burn-submission), not rngWord. SPEC must write the rigorous trace + full in-window SLOAD enumeration per feedback_rng_window_storage_read_freshness — "accept" is a claim requiring proof, not a "by construction" assertion.

---

## Claude's Discretion

None — every gray area was decided by the user across four AskUserQuestion turns.

## Deferred Ideas

None — discussion stayed within phase scope. VRF-freeze housekeeping, v44 bookkeeping, and the v43 backlog remain in `.planning/REQUIREMENTS.md` §Future Requirements (out of scope for v45.0).
