# Phase 310: Implementation — Single Batched USER-APPROVED Contract Diff (IMPL) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-20
**Phase:** 310-implementation-single-batched-user-approved-contract-diff-im
**Areas discussed:** Helper home (pack/unpack placement), EV-logic reach (multiplier fn + constants placement)

> The v45.0 design is fully LOCKED in the 309 SPEC + REQUIREMENTS.md. No locked decision was
> reopened. The discussion resolved one cross-module reachability gap the SPEC did not address:
> the modules are separate delegatecall contracts sharing only `DegenerusGameStorage`, so members
> the SPEC placed in LootboxModule are unreachable from the Mint/Whale deposit-tally sites
> (IMPL-03).

---

## Helper home — pack/unpack placement

| Option | Description | Selected |
|--------|-------------|----------|
| Storage.sol, internal pure | Both `_packLootboxPurchase`/`_unpackLootboxPurchase` in `DegenerusGameStorage.sol` as `internal pure`, inherited by Lootbox/Mint/Whale; matches `_packEthToMilliEth` precedent. Overrides SPEC §1.7 placement. | ✓ |
| Split: pack in Storage, unpack in Lootbox | Relocate only pack; keep unpack Lootbox-private per SPEC §1.7. (Noted: Mint/Whale RMW-accumulate `adjustedPortion` on subsequent deposits → they need unpack too, so the split likely doesn't hold.) | |
| Keep both in Lootbox, inline bit-math in Mint/Whale | Honor SPEC §1.7 literally; hand-roll inline shift/mask in Mint/Whale. Inline-duplicated business logic — drift bug class (Phase 294 BURNIE precedent). | |

**User's choice:** Storage.sol, internal pure (Recommended).
**Notes:** Signatures from SPEC §1.7 unchanged — only the home file moves. Single source of truth;
avoids the inline-duplication drift bug class per `feedback_verify_call_graph_against_source`.

---

## EV-logic reach — multiplier fn + constants placement

| Option | Description | Selected |
|--------|-------------|----------|
| Relocate fn + constants to Storage.sol | Move `_lootboxEvMultiplierFromScore` + EV constants (MIN/NEUTRAL/MAX_BPS, BENEFIT_CAP, ACTIVITY_SCORE_* deps) to `DegenerusGameStorage.sol`; all modules share one score→bps source. `_applyEvMultiplierWithCap` stays in Lootbox (resolvers only). | ✓ |
| Move only what deposit needs | Move just NEUTRAL/CAP + the fn; tends to converge on full relocation because the fn body reads MIN/MAX/ACTIVITY_SCORE_*. | |
| Classify by raw score threshold in Mint/Whale | Re-derive bonus boundary inline (`score > ACTIVITY_SCORE_NEUTRAL_BPS`), move only CAP. Inline-duplicated curve boundary — drift risk. | |

**User's choice:** Relocate fn + constants to Storage.sol (Recommended).
**Notes:** Consistent with the helper decision. The deposit-time tally (SPEC-03 §3.1) must classify
`mult > NEUTRAL` and compute `remaining = CAP - used`; today Mint/Whale have zero EV references
because the cap is drawn entirely at resolution. `_applyEvMultiplierWithCap` is NOT moved — only
the two resolvers call it (`openLootBox` does frozen-apply with no cap fn).

## Claude's Discretion

- Exact bit-mask/shift mechanics inside the relocated pack/unpack helpers (layout fixed by SPEC-01).
- Whether subsequent-deposit `adjustedPortion` accumulation uses unpack→pack or a narrower masked
  RMW, provided `score+1`/`baseLevel+1` are preserved and the layout matches SPEC-01.

## Deferred Ideas

None — discussion stayed within phase scope.
