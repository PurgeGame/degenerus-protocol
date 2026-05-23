---
phase: 310-implementation-single-batched-user-approved-contract-diff-im
plan: 01
subsystem: contracts
tags: [solidity, storage-packing, lootbox, ev-cap, shared-base, delegatecall]

# Dependency graph
requires:
  - phase: 309-spec-locked-layout-bonus-only-cap-shared-cap-disposition-spe
    provides: SPEC-01 packed layout, §1.7 helper signatures, D-01/D-02 placement override
provides:
  - "lootboxPurchasePacked (uint256) replacing lootboxEvScorePacked + lootboxBaseLevelPacked (net -1 slot)"
  - "_packLootboxPurchase / _unpackLootboxPurchase as internal pure in DegenerusGameStorage (reachable by Lootbox, Mint, Whale)"
  - "_lootboxEvMultiplierFromScore relocated to DegenerusGameStorage as internal pure (shared classifier)"
  - "EV constants relocated to DegenerusGameStorage as internal constant (single source of truth)"
affects: [310-02, 310-03, 311-tests]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Shared-base placement of cross-module pure helpers/constants (matches _packEthToMilliEth precedent)"
    - "Single packed uint256 snapshot word with masked-field encoding (anti-aliasing)"

key-files:
  created: []
  modified:
    - contracts/storage/DegenerusGameStorage.sol
    - contracts/modules/DegenerusGameLootboxModule.sol

key-decisions:
  - "USER-APPROVED rename (deviation): the two relocated lootbox activity-score constants are prefixed LOOTBOX_EV_ACTIVITY_NEUTRAL_BPS / LOOTBOX_EV_ACTIVITY_MAX_BPS to resolve a pre-existing name collision with DegenerusGameDegeneretteModule's ACTIVITY_SCORE_MAX_BPS (30_500). SPEC §0.B used the bare ACTIVITY_SCORE_* names, which were LootboxModule-private at HEAD (no clash); moving them to internal scope surfaced the latent clash."
  - "_applyEvMultiplierWithCap stays private in LootboxModule; only its declarations of NEUTRAL_BPS/BENEFIT_CAP moved — its references now bind the inherited Storage internal constants."

patterns-established:
  - "Lootbox EV constants/classifier live in the shared base; modules consume them as inherited internal members."

requirements-completed: [IMPL-02]

# Metrics
duration: ~9min
completed: 2026-05-20
---

# Phase 310 / Plan 01: Shared-Base Foundation Summary

**Packed `lootboxPurchasePacked` uint256 word + pack/unpack helpers + relocated EV classifier and constants, all in `DegenerusGameStorage` as the single source of truth for the lootbox EV-cap refactor (uncommitted, awaiting the Plan 03 batched USER-APPROVAL gate).**

## Performance

- **Duration:** ~9 min (executor + orchestrator rename)
- **Tasks:** 2 (both grep gates PASS)
- **Files modified:** 2 (uncommitted)

## Accomplishments
- Renamed + widened `lootboxEvScorePacked` (uint16) → `lootboxPurchasePacked` (uint256); removed `lootboxBaseLevelPacked`. Net **−1 storage slot**, no new slot (SPEC §1.8).
- Added `_packLootboxPurchase(uint16 scorePlus1, uint64 adj, uint24 baseLevelPlus1)` and `_unpackLootboxPurchase(uint256)` as `internal pure`, encoding the LOCKED SPEC §1.1 layout: `[0:16]` score+1, `[16:80]` adjustedPortion, `[80:104]` baseLevel+1, `[104:256]` reserved/zero. Each field masked to width before shifting (threat T-310-01). Helper takes an already-encoded `baseLevelPlus1` — no sentinel normalization (DIV-1 preserved).
- Relocated `_lootboxEvMultiplierFromScore` from LootboxModule-`private pure` to Storage-`internal pure`, body byte-identical (only the two activity-constant names changed — see deviation).
- Relocated six EV/activity constants to Storage as `internal constant` (values unchanged: 6_000 / 25_500 / 8_000 / 10_000 / 13_500 / 10 ether). Declarations deleted from LootboxModule.

## Files Created/Modified
- `contracts/storage/DegenerusGameStorage.sol` — packed word mapping + pack/unpack helpers + relocated `_lootboxEvMultiplierFromScore` + 6 relocated EV constants (2 renamed). **UNCOMMITTED.**
- `contracts/modules/DegenerusGameLootboxModule.sol` — deleted the relocated fn + 6 constant declarations. `_applyEvMultiplierWithCap` STAYS (its NEUTRAL_BPS/BENEFIT_CAP references now resolve to inherited Storage constants). **UNCOMMITTED.**

## Final packed-word layout (as implemented)
```solidity
function _packLootboxPurchase(uint16 scorePlus1, uint64 adj, uint24 baseLevelPlus1)
    internal pure returns (uint256) {
    return uint256(scorePlus1) & 0xFFFF
        | (uint256(adj) & 0xFFFFFFFFFFFFFFFF) << 16
        | (uint256(baseLevelPlus1) & 0xFFFFFF) << 80;
}
```

## Decisions Made
- **`_applyEvMultiplierWithCap` retains its `LOOTBOX_EV_NEUTRAL_BPS` (~482) and `LOOTBOX_EV_BENEFIT_CAP` (~488/~490) references** — only the *declarations* moved; the references now bind the inherited Storage `internal constant`. (Plan 02 rewrites the `==`→`<=` rule at ~482.)
- The other four relocated constants (`LOOTBOX_EV_MIN_BPS`, `LOOTBOX_EV_MAX_BPS`, both activity constants) have **zero surviving uses in LootboxModule** because their sole reader, the relocated multiplier fn, was deleted.

## Deviations from Plan

### USER-APPROVED Issue (decision checkpoint)

**1. [Name collision — pre-existing latent clash the SPEC did not anticipate] Renamed the two relocated lootbox activity constants**
- **Found during:** Task 2 (constant relocation) — `forge build` raised Error (9097) "Identifier already declared".
- **Issue:** `ACTIVITY_SCORE_MAX_BPS` was being declared `internal` in `DegenerusGameStorage` (25_500, lootbox EV) while `DegenerusGameDegeneretteModule.sol:170` already declares its own `private constant ACTIVITY_SCORE_MAX_BPS = 30_500` (deity-pass ROI). Both modules `is DegenerusGameStorage`, so the inherited `internal` + derived `private` of the same name collide. SPEC §0.B used the bare `ACTIVITY_SCORE_*` names, which were LootboxModule-private at HEAD (no clash existed there).
- **Decision:** Presented 3 options to the user; user selected **"Prefix lootbox consts"**. Renamed `ACTIVITY_SCORE_NEUTRAL_BPS → LOOTBOX_EV_ACTIVITY_NEUTRAL_BPS` and `ACTIVITY_SCORE_MAX_BPS → LOOTBOX_EV_ACTIVITY_MAX_BPS` in Storage (declarations + all 6 reference sites inside `_lootboxEvMultiplierFromScore`). Degenerette's `ACTIVITY_SCORE_MAX_BPS = 30_500` is untouched.
- **Scope:** Fully self-contained to `DegenerusGameStorage.sol`. No 5th contract touched (phase scope preserved). Plan 02/03 reference `LOOTBOX_EV_NEUTRAL_BPS` / `LOOTBOX_EV_BENEFIT_CAP` / the fn — **not** the activity constants — so their grep gates are unaffected.
- **Verification:** Error (9097) count after rename = **0**; Degenerette constant intact; the only remaining `forge build` errors are the 4 expected not-yet-wired consumer references (`lootboxBaseLevelPacked`/`lootboxEvScorePacked` in Lootbox open + Mint/Whale), which Plans 02/03 rewire.

---

**Total deviations:** 1 (USER-APPROVED naming decision). **Impact:** no scope creep; resolves a compile blocker without touching the locked 4-file scope or any locked SPEC semantics. Only constant *names* changed; values and the classifier body are unchanged.

## Issues Encountered
- Pre-existing `ACTIVITY_SCORE_MAX_BPS` collision (above) — resolved via the user-approved prefix rename.

## Commit Posture
**NO contract commit in this plan** (per the phase CONTRACT-COMMIT POLICY). `DegenerusGameStorage.sol` and `DegenerusGameLootboxModule.sol` are left UNCOMMITTED in the working tree. The single batched 4-file commit happens at the END of Plan 03 after the explicit USER-APPROVAL gate.

## Next Phase Readiness
- Shared symbols (`lootboxPurchasePacked`, `_packLootboxPurchase`, `_unpackLootboxPurchase`, `_lootboxEvMultiplierFromScore`, `LOOTBOX_EV_NEUTRAL_BPS`, `LOOTBOX_EV_BENEFIT_CAP`) are defined and ready for Plan 02 (openLootBox frozen-apply) and Plan 03 (deposit tally).
- `forge build` will not pass until Plan 03 wires Mint/Whale — this is the intended phasing (build gate lives in Plan 03).

---
*Phase: 310-implementation-single-batched-user-approved-contract-diff-im*
*Completed: 2026-05-20*
