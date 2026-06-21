---
phase: 453-impl-the-sole-approval-gate
plan: 01
subsystem: contracts
tags: [solidity, degenerette, variant-2, wwxrp-rig, payout-tables, eip-170]

# Dependency graph
requires:
  - phase: 452-gen-generator-first-no-contract-edit
    provides: "derive_5_tables.py (Variant-2 honest + R2 rigged byte-source) + the locked DEC-01 R2 / DEC-02 Option B / DEC-03 rulings + the printed 453 IMPL DISPATCH SHAPE"
provides:
  - "Variant-2 (color-gated-by-symbol) _score in the core Degenerette betting engine"
  - "DEC-01 R2 score-bearing WWXRP rig (_rigWwxrpResult) with the +2 unlock, empty-pool no-op, m>=7 cap (never S=9)"
  - "DEC-02 Option-B per-(N, heroIsGold) honest payout family (8 base + 8 S8 + 8 factor tables) threaded through _getBasePayoutBps / _wwxrpFactor / _fullTicketPayout + 4 call sites"
  - "Recalibrated 5 by-N WWXRP _RIG_ base/S8/factor tables under the R2 rigged distribution"
affects: [454-tst, 455-aud, 456-close]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Honest lane indexed by (N, heroIsGold); rigged lane + S9 pin by N only — heroIsGold consulted only when !isWwxrp"
    - "Color-gated-by-symbol scoring (Variant-2) — ported from the foil-match precedent into the core engine"
    - "Score-bearing rig pool (non-hero symbols + colors on symbol-matched quads); empty-pool guard before the uniform % u pick"

key-files:
  created: []
  modified:
    - contracts/modules/DegenerusGameDegeneretteModule.sol

key-decisions:
  - "Constants pasted VERBATIM from derive_5_tables.py (S9 pins kept HEAD underscore form, numerically byte-identical; honest S8 pasted in the generator's no-underscore form)"
  - "heroIsGold computed once per bet at the regular-bet site (alongside goldCount); inline at the 3 box sites; hero quadrant hoisted to a named local at the two inline-MASK_2 box paths"
  - "Pass-1 count order (color-branch then symbol-branch) made identical to the pass-2 walk so the uniform pick index lines up"

patterns-established:
  - "Variant-2 color increment is reachable ONLY inside the symMatch branch (gated, never an independent axis)"
  - "EIP-170 headroom recorded at the sole approval gate before presenting the diff"

requirements-completed: [SCORE-01, SCORE-02, SCORE-03, RIG-01, RIG-02, RIG-03, IMPL-01]

# Metrics
duration: 33min
completed: 2026-06-21
---

# Phase 453 Plan 01: IMPL (the sole approval gate) Summary

**Variant-2 color-gated-by-symbol _score + DEC-01 R2 score-bearing WWXRP rig + DEC-02 Option-B per-(N, heroIsGold) honest payout family applied to the single file DegenerusGameDegeneretteModule.sol — forge build clean (15,873 B, 8,703 B EIP-170 headroom), S9 pins + WWXRP RTP curve byte-identical to HEAD, byte-reproduce smoke 44/44 — UNCOMMITTED pending USER approval.**

## Performance

- **Duration:** 33 min
- **Started:** 2026-06-21T20:33:38Z
- **Completed:** 2026-06-21T21:07:20Z
- **Tasks:** 5 (Task 5 is the blocking-human approval gate — verifications run, diff presented, NOT committed)
- **Files modified:** 1 (`contracts/modules/DegenerusGameDegeneretteModule.sol`)

## Accomplishments

- **Task 1 — Constants (Option B family):** Replaced the 5 honest `QUICK_PLAY_PAYOUTS_N{0..4}_PACKED` with the 8 per-(N,heroGold) base tables; the 5 honest `_S8` with the 8 per-(N,heroGold) S8 tiers; the 5 honest `WWXRP_FACTORS_N{0..4}_PACKED` with the 8 per-(N,heroGold) honest factor tables; and recalibrated the 5 by-N rigged `QUICK_PLAY_PAYOUTS_RIG_N{0..4}_PACKED` / `_RIG_N{0..4}_S8` / `WWXRP_FACTORS_RIG_N{0..4}_PACKED` (still 5 by-N, NOT split). All pasted verbatim from `derive_5_tables.py`. The 5 `QUICK_PLAY_PAYOUT_N{0..4}_S9` pins, `WWXRP_BONUS_FACTOR_SCALE`, `WWXRP_RIG_SALT`, and the entire `WWXRP_ROI_*` / `WWXRP_FLOOR_BPS` curve left untouched (confirmed by git diff).
- **Task 2 — `_score` Variant-2:** Per quadrant a symbol match scores +1 (hero +2); the quadrant's color scores +1 ONLY inside the `symMatch` branch (gated). Dropped the independent color +1. Max 9; floor S>=2 left to the payout SHAPE (S=0,1 pay 0). Doc-comment refreshed.
- **Task 3 — `_rigWwxrpResult` R2:** Replaced the blanket `if (!colorMatch) ++u;` with a gated color count (`symMatch && !colorMatch`, incl. the hero color) plus the non-hero unmatched-symbol count (`q != heroQuadrant && !symMatch`). Pass-2 walks the SAME predicates in the SAME order. Added an explicit `u == 0` empty-pool no-op guard before the `% u` pick. Kept the `m >= 7` cap and the `rigSeed % 5 >= 3` gate verbatim. +2 unlock allowed; never S=9. Doc-comment refreshed.
- **Task 4 — heroIsGold threading:** Added `bool heroIsGold` to `_getBasePayoutBps`, `_wwxrpFactor`, and `_fullTicketPayout`; the honest lane dispatches per (N, heroIsGold) (N0/N4 collapse, N∈{1,2,3} pick HEROGOLD/HEROCOMMON) while the rigged lane + S9 pin stay by N only. Derived `heroIsGold = ((playerTicket >> (heroQuadrant*8+3)) & 7) == 7` at all 4 call sites (once per bet at the regular-bet site; inline at the 3 box sites; hero quadrant hoisted to a named local at the two `uint8(... & MASK_2)` box paths). `forge build` exit 0.
- **Task 5 — Verify + present:** `forge build` exit 0; EIP-170 size + headroom recorded; single-file diff confirmed; invariant lines byte-identical to HEAD; byte-reproduce smoke 44/44; SUMMARY written. NOT committed.

## Task Commits

**NONE — nothing committed this run (by design).** Per the plan's CRITICAL_OVERRIDE and the milestone rule, this plan is the SOLE contract-commit approval gate: all edits are applied to the working tree and LEFT UNCOMMITTED for USER hand-review. A commit-guard hook blocks `.sol` commits; the orchestrator commits the `.sol` only after explicit USER approval (`CONTRACTS_COMMIT_APPROVED=1` + hook move-aside). STATE.md / ROADMAP.md were not touched (orchestrator owns them).

## Files Created/Modified

- `contracts/modules/DegenerusGameDegeneretteModule.sol` — Variant-2 `_score`; R2 `_rigWwxrpResult`; heroIsGold-threaded `_getBasePayoutBps` / `_wwxrpFactor` / `_fullTicketPayout` + 4 call sites; regenerated Option-B constant family (8 honest base + 8 S8 + 8 factor) + recalibrated 5 by-N rigged tables; refreshed doc-comments and the constant-block banners. **352 lines changed (231 insertions / 121 deletions) — UNCOMMITTED.**

## Verification Results (recorded at the gate)

- **`forge build`:** exit 0, 0 compile-error lines. Only a pre-existing, unrelated `unsafe-typecast` lint warning in `DegenerusGameFoilPackModule.sol:767` (out of scope — not this file).
- **EIP-170:** `DegenerusGameDegeneretteModule` runtime size = **15,873 bytes**; **headroom = 8,703 bytes** under the 24,576-byte limit. No optimization needed; no tables dropped.
- **`git diff --stat`:** exactly **1 file changed** — `contracts/modules/DegenerusGameDegeneretteModule.sol` (+231 / −121). No other file touched.
- **S9 pins:** `git diff` shows NO added/removed `QUICK_PLAY_PAYOUT_N{0..4}_S9` line — byte-identical to HEAD.
- **WWXRP RTP curve:** `git diff` shows NO added/removed `WWXRP_ROI_*` / `WWXRP_FLOOR_BPS` line — byte-identical to HEAD. `WWXRP_BONUS_FACTOR_SCALE` + `WWXRP_RIG_SALT` also unchanged.
- **Byte-reproduce smoke:** all **44/44** generator `private constant` values present in the contract (8 honest PACKED + 8 honest S8 + 5 S9 pins + 8 honest factors + 5 rigged PACKED + 5 rigged S8 + 5 rigged factors). The S9 pins matched after normalizing Solidity underscore separators (the contract keeps HEAD's `10_756_411` form; the generator prints `10756411` — numerically identical, and correctly NOT in the diff).
- **Structural greps:** `_score` color-gated (no `S = A + 2`); `_rigWwxrpResult` has `m >= 7` cap + `u == 0` empty-pool guard + NO blanket `if (!colorMatch) ++u;`; `heroIsGold` appears 24× across 3 dispatcher signatures + 4 call-site derivations + dispatch uses; `heroQuadrant * 8 + 3` appears exactly 4× (the 4 call sites); rigged branches reference only `_RIG_N{n}` (no HEROGOLD/HEROCOMMON under `if (isWwxrp)`).

## Decisions Made

- **Constant formatting:** Honest S8 tiers pasted in the generator's no-underscore integer form (`5124517`), while the S9 pins keep HEAD's underscore form (`10_756_411`) since they were not regenerated. Both are numerically byte-identical; the Phase 454 byte-reproduce gate normalizes separators.
- **heroIsGold placement:** Computed once at the regular-bet site (constant per bet, alongside `goldCount`) and inline at the 3 box-spin sites. The hero quadrant was hoisted to a named local at the two box paths that previously passed `uint8(ss & MASK_2)` / `uint8(seed & MASK_2)` inline so `_score` and the heroIsGold derivation read the identical value.
- **Pass-1/pass-2 ordering:** Both passes order the color-branch (`symMatch && !colorMatch`) before the symbol-branch (`q != heroQuadrant && !symMatch`) so the uniform pick index lines up. (Intra-quadrant order does not change the modeled score distribution because the pick is uniform over the eligible pool, but matching the order keeps display==score honest per cell.)

## Deviations from Plan

None - plan executed exactly as written. (The doc-comment / constant-block-banner refreshes on `_score`, `_rigWwxrpResult`, the RIG-family banner, the per-N base-table banner, the `FullTicketResult.matches` @param, and the two inline call-site comments were explicitly required by Tasks 2/3/4 and the CONTEXT doc-comment-refresh directive — not deviations.)

## Issues Encountered

- The initial byte-reproduce smoke flagged the 5 S9 pins as "missing" purely because the generator prints them without underscores while the contract keeps HEAD's underscore separators. Re-ran the smoke with underscores normalized on both sides → 44/44 match. The S9 pins are correctly NOT in the diff (byte-identical to HEAD).
- `forge build` with `via_ir` over 237 files is slow (~7 min cold); ran the long build in the background and waited for completion rather than blocking. Incremental rebuilds after comment-only edits were fast.

## Known Stubs

None — no stubs, placeholders, or hardcoded empty values introduced. The change is a complete payout-engine recalibration; the constants are real solved tables from the generator.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- **AWAITING USER APPROVAL (the sole contract-commit gate).** The single-file diff is applied and UNCOMMITTED. The orchestrator must present `git diff contracts/modules/DegenerusGameDegeneretteModule.sol` to the USER; on "approved" it commits the `.sol` under `CONTRACTS_COMMIT_APPROVED=1` + hook move-aside.
- **Phase 454 (TST)** is then unblocked: the byte-reproduce stat gate (`test/stat/DegenerettePerNEvExactness.test.js`), the rig-parity behavioral test (run the contract `_rigWwxrpResult` over many seeds vs `p_score_distribution_rigged`), the bonus-EV oracle, and full-suite (forge + Hardhat) parity.
- **Phase 455 (AUD)** carries the deep solvency / RNG-freeze / liveness re-audit on the new scoring (threat T-453-08, transferred).

## Self-Check: PASSED

- `453-01-SUMMARY.md` exists at `.planning/phases/453-impl-the-sole-approval-gate/`.
- `contracts/modules/DegenerusGameDegeneretteModule.sol` is modified + UNCOMMITTED in the working tree (`git status` shows ` M`).
- HEAD unchanged at `88f19119` — nothing committed this run (the `.sol` awaits USER approval; STATE/ROADMAP untouched).

---
*Phase: 453-impl-the-sole-approval-gate*
*Completed: 2026-06-21*
