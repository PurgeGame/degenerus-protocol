# Phase 453: IMPL (the sole approval gate) - Context

**Gathered:** 2026-06-21
**Status:** Ready for planning
**Source:** Locked by Phase 452 GEN output (the generator IS the spec) + USER DEC rulings.

<domain>
## Phase Boundary

Implement v73.0 Variant-2 in `contracts/modules/DegenerusGameDegeneretteModule.sol` as ONE
batched, USER-approved `.sol` diff. This is the **sole contract-commit approval gate** of the
milestone. The byte-source for every constant is the committed generator
`.planning/notes/degenerette-recalibration/derive_5_tables.py` (run it; paste its FINAL
PASTE-READY CONSTANTS verbatim). Everything the generator produced in 452 (Variant-2 honest
distribution, the DEC-01-R2 "+2-unlock" rig, the DEC-02 Option-B per-(N,hero-gold) honest family,
the held-fixed S9 pins + WWXRP RTP curve) is locked — do NOT re-decide it here.

**HARD RULE:** apply all edits, `forge build`, verify, then STOP and present ONE diff for USER
hand-review. Do NOT `git commit` any `contracts/*.sol` without explicit approval
(`CONTRACTS_COMMIT_APPROVED=1` + hook move-aside). Commit all planning docs BEFORE touching `.sol`.
</domain>

<decisions>
## Implementation Decisions (all locked upstream)

### The five edits to DegenerusGameDegeneretteModule.sol

1. **`_score` ~L1053-1080 → Variant-2 (color-gated-by-symbol).** Today: per quadrant, color +1
   (independent) and symbol +1 (hero +2) — `S = A + 2H`. Variant-2: per quadrant a symbol match
   scores +1 (hero symbol +2), and that quadrant's COLOR scores +1 **only if that quadrant's
   symbol also matched**. Max stays 9 (hero quad 3 + three ordinary quads ×2). S=9 stays exactly
   the all-8-axes event (P(S=9) byte-identical to HEAD).

2. **`_rigWwxrpResult` ~L1299-1358 → DEC-01 R2 score-bearing rig (USER "allow +2, never S=9").**
   Narrow the eligible pool to SCORE-BEARING cells only:
   - an unmatched **non-hero symbol** (any color state) — force the symbol; AND
   - an unmatched **color on a quadrant whose symbol ALREADY matched** (`!colorMatch && symMatch`).
   EXCLUDE: the hero symbol, and **no-op colors** (an unmatched color on a quadrant whose symbol is
   still unmatched — i.e. drop the HEAD `if (!colorMatch) ++u;` blanket and gate it on `symMatch`).
   Keep: the **m≥7 cap** (`if (m >= 7) return rigged;`), the **3/5 gate**, the uniform pick, and the
   two-pass force walk. The +2 unlock (forcing a symbol onto an already-color-matched quad lifts the
   score +2 under Variant-2) is ALLOWED and happens naturally from forcing the symbol; the m≥7 cap
   guarantees a fired roll (M≤6) → post-force M≤7 → S≤8, so the rig can NEVER make S=9. This matches
   the generator's `p_score_distribution_rigged` per-pick +1/+2 model (452-04).

3. **`_getBasePayoutBps` ~L1175-1213 → add a `heroIsGold` selector (honest lane only).** New
   signature `_getBasePayoutBps(uint8 N, uint8 s, bool isWwxrp, bool heroIsGold)`. S=9 pin: by N only
   (unchanged). `isWwxrp` (rigged) lane: by N only (the `_RIG_` family stays averaged — unchanged
   shape, recalibrated values). Honest lane (`!isWwxrp`, s≤8): index by **(N, heroIsGold)** —
   N0 always-hero-common and N4 always-hero-gold collapse to one table each; N∈{1,2,3} pick
   `_HEROGOLD` vs `_HEROCOMMON`. (Exact dispatch printed by the generator's
   "453 IMPL DISPATCH SHAPE" block.)

4. **`_wwxrpFactor` ~L1101 → same `heroIsGold` split on the honest ETH-bonus factors.** Honest
   `WWXRP_FACTORS_N*` become per-(N,hero-gold); the rigged `WWXRP_FACTORS_RIG_N*` stay by-N
   (recalibrated). Add `bool heroIsGold` param, consulted only when `!isWwxrp`.

5. **Thread `heroIsGold` through `_fullTicketPayout` ~L1132 and its 4 call sites** (~L753, L1489,
   L1551, L1604). At each call site the player ticket + heroQuadrant are in scope; compute
   `heroIsGold = ((playerTicket >> (heroQuadrant*8 + 3)) & 7) == 7` and pass it. `_fullTicketPayout`
   forwards it to `_getBasePayoutBps` and `_wwxrpFactor`.

### Constant blocks (~L300-360) — paste from the generator verbatim
- Honest base: replace `QUICK_PLAY_PAYOUTS_N{0..4}_PACKED` / `_S8` with the **8** per-(N,hero-gold)
  constants (`QUICK_PLAY_PAYOUTS_N0_PACKED`, `..._N{1,2,3}_HEROGOLD/_HEROCOMMON_PACKED`,
  `..._N4_PACKED`, and the matching `_S8`).
- Honest factors: `WWXRP_FACTORS_N{0..4}_PACKED` → the per-(N,hero-gold) honest factor set.
- Rigged family: `QUICK_PLAY_PAYOUTS_RIG_N{0..4}_PACKED` / `_S8` + `WWXRP_FACTORS_RIG_N{0..4}_PACKED`
  → the recalibrated +2-rig values (still 5 by-N tables).
- **UNTOUCHED:** `QUICK_PLAY_PAYOUT_N{0..4}_S9` (S9 pins) and the `WWXRP_ROI_*` / `WWXRP_FLOOR_BPS`
  curve. Confirm by diff they are byte-identical to HEAD.

### Doc-comment refresh
- `_score`, `_rigWwxrpResult`, `_getBasePayoutBps`, `_wwxrpFactor`, and the constant-block banners
  describe Variant-2 + the R2 "+2-unlock, never-9" rig + the Option-B honest split.

### Claude's Discretion
- Exact branch layout / helper extraction in the dispatchers, provided behavior matches the
  generator's printed dispatch shape and `forge build` stays under EIP-170.
- Whether to compute `heroIsGold` inline at each call site or via a tiny private helper.
</decisions>

<canonical_refs>
## Canonical References (MUST read before planning/implementing)
- `.planning/notes/degenerette-recalibration/derive_5_tables.py` — the byte-source. Run
  `python3 …/derive_5_tables.py`; the FINAL PASTE-READY CONSTANTS + "453 IMPL DISPATCH SHAPE"
  blocks are the exact paste + dispatch spec.
- `.planning/phases/452-gen-generator-first-no-contract-edit/452-CONTEXT.md` — DEC-01 (R2 + the
  refined "+2 unlock, never 9"), DEC-02 (Option B honest-only split), DEC-03 (floor S≥2).
- `contracts/modules/DegenerusGameDegeneretteModule.sol` — the only file edited. Anchors: `_score`
  ~L1053, `_rigWwxrpResult` ~L1299, `_getBasePayoutBps` ~L1175, `_wwxrpFactor` ~L1101,
  `_fullTicketPayout` ~L1132 + call sites ~L753/L1489/L1551/L1604, constants ~L300-360.
- `.planning/REQUIREMENTS.md` — SCORE-01/02/03, RIG-01/02/03, IMPL-01.

## Phase requirement IDs
SCORE-01, SCORE-02, SCORE-03, RIG-01, RIG-02, RIG-03, IMPL-01
</canonical_refs>

<verification>
## Success criteria
1. `_score` is Variant-2 (color gated by symbol; hero symbol +2; floor S≥2; max 9).
2. `_rigWwxrpResult` is R2 (pool = non-hero symbols + colors on symbol-matched quads; uniform pick;
   m≥7 cap; +2 unlock allowed; never S=9) — matching the 452-04 generator model.
3. The regenerated constants are pasted verbatim (8 honest base + honest factors + recalibrated
   `_RIG_` family); S9 pins + `WWXRP_ROI_*` confirmed byte-identical to HEAD.
4. `_getBasePayoutBps` / `_wwxrpFactor` / `_fullTicketPayout` thread `heroIsGold`; honest lane
   indexed by (N, heroIsGold), rigged by N only.
5. `forge build` clean; **EIP-170 fits** (8 tables + threading add bytecode — verify headroom;
   if it overflows, flag for optimization, do NOT silently drop tables).
6. Diff is `contracts/modules/DegenerusGameDegeneretteModule.sol` ONLY; presented for USER approval;
   NOT committed without `CONTRACTS_COMMIT_APPROVED=1`.

## Key risks
- **EIP-170 / bytecode growth** from 5→8 honest base tables + 5→8 honest factor tables + the
  dispatch branches. Must `forge build` and check the module's deployed size.
- **Generator↔contract rig parity:** the contract `_rigWwxrpResult` must produce the score
  distribution the generator models. A 454 behavioral test (run the actual rig over many seeds,
  compare to `p_score_distribution_rigged`) is the proof — named here for traceability.
</verification>

<deferred>
None — 453 is pure IMPL of the locked 452 spec. Tests (byte-reproduce + rig-parity), invariants,
re-audit, and closure are 454/455/456.
</deferred>

---
*Phase: 453-impl-the-sole-approval-gate*
*Context: locked by 452 GEN output; 2026-06-21*
