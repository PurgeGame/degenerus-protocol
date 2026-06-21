---
phase: 452-gen-generator-first-no-contract-edit
plan: 03
subsystem: testing
tags: [degenerette, variant-2, ev-equality, option-b, hero-placement, wwxrp-rig, p-s9-invariant, python-generator]

# Dependency graph
requires:
  - phase: 452-02 (Variant-2 constant regen + EVEQ-01 measurement)
    provides: "Averaged Variant-2 honest p_score_distribution + DEC-01 R2 rigged dist + the MEASURED 2.99230 centi-x hero-placement EV drift (hero-common EV-positive at N=1..3) that forced DEC-02 to Option B"
provides:
  - "Option-B honest payout family split per (N, hero-is-gold): 8 honest base tables (N0 + N1g/c + N2g/c + N3g/c + N4) each solved against its OWN Variant-2 hero-placement distribution, every sub-case basePayoutEV in (99,100] and honest +5% ETH bonus EV exactly 5.000% per sub-case"
  - "Honest ETH-bonus factor family split the same way (8 WWXRP_FACTORS_* honest tables)"
  - "WWXRP _RIG_ family kept AVERAGED at 5 tables (drift by-design) — unchanged from 452-02"
  - "EVEQ-01 CONFIRMATION: residual hero-placement EV drift now 0.00007 centi-x (was 2.99230), hard-asserted <= 0.01 centi-x — the player-selectable hero-common edge is CLOSED"
  - "Numeric pre-proof extended: every new honest (N,heroGold) sub-case P(S=9) == averaged == rigged == HEAD all-8-match (Fraction-exact) — the honest split does NOT move P(S=9)"
  - "Printed _getBasePayoutBps(N, isWwxrp, heroIsGold) dispatch shape for the 453 IMPL paste (heroIsGold selector honest-lane only; N0/N4 collapse; WWXRP by N only)"
affects: [453 IMPL (pastes the Option-B honest constant family + the printed dispatch shape — the sole approval gate), 454 TST (byte-reproduce gate re-derives this FINAL block), 455 REAUDIT]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-(N, hero-is-gold) honest sub-case solve: _hero_placement_subcase builds the FIXED-placement Variant-2 distribution; _solve_table (UNCHANGED, shared with the WWXRP _RIG_ family) calibrates each to EV=100 — exact EV-equality across hero placement on the honest lane"
    - "Asymmetric split: HONEST lane split per (N,heroGold) for exact equality; WWXRP _RIG_ lane kept averaged at 5 tables by-design (USER don't-care). The split is the ONLY dispatch change — a heroIsGold selector consulted only when !isWwxrp"
    - "N0 (always hero-common) and N4 (always hero-gold) collapse to one constant each (no HEROGOLD/HEROCOMMON infix); heroIsGold is only consulted for N in {1,2,3}"
    - "Pre-proof strengthened to assert P(S=9) is placement-independent: each new honest sub-case dist[9] == the per-N value (Fraction-exact)"

key-files:
  created:
    - .planning/phases/452-gen-generator-first-no-contract-edit/452-03-SUMMARY.md
  modified:
    - .planning/notes/degenerette-recalibration/derive_5_tables.py

key-decisions:
  - "N0/N4 collapse to one constant name each (no hero-color infix) — they have a single structurally-valid hero placement, so a HEROGOLD/HEROCOMMON suffix would be misleading and would double the constant count needlessly. The printed dispatch shape reproduces the collapse (heroIsGold only consulted for N in {1,2,3})."
  - "S9 pins remain emitted by N only (QUICK_PLAY_PAYOUT_N{N}_S9) — P(S=9) is placement-independent (depends on the gold COUNT N, not which quadrant is the hero), so they are NOT split per hero-color. The pre-proof now asserts this explicitly per sub-case."
  - "Hard-asserted the Option-B residual drift <= 0.01 centi-x (the old 2.99 edge / ~300) so a regression that fails to solve a sub-case against its own dist trips an assert (exit != 0) rather than silently reopening the edge."
  - "Retained the averaged honest p_score_distribution / P_N_TABLE ONLY for the placement-independent invariant checks (S9 pin relabel, rig[9]==honest[9], pre-proof) — the honest PAYOUT tables are solved against the per-sub-case dists, never the averaged one."

patterns-established:
  - "Exact EV-equality on the honest lane closes a player-selectable edge: with heroQuadrant a player-supplied validated param, splitting the honest table per (N,heroGold) removes the +2.24% base-EV hero-common pick measured in 452-02"
  - "S=9 = all-8-axes event is placement-independent AND byte-identical to HEAD across honest (averaged + every sub-case), rigged, and the HEAD-M8 reproduction — proven Fraction-exact before any .sol edit"

requirements-completed: [EVEQ-01, GEN-02, GEN-03]

# Metrics
duration: ~7min
completed: 2026-06-21
---

# Phase 452 Plan 03: DEC-02 Option B — Honest Lane Exact EV-Equality Summary

**`derive_5_tables.py` splits the HONEST Degenerette payout + ETH-bonus family per (N, hero-is-gold) so each pick is exactly EV-equal — the residual hero-placement drift drops from 2.99230 to 0.00007 centi-x (player-selectable hero-common edge CLOSED) — while keeping the WWXRP `_RIG_` family averaged at 5 tables by-design, re-proving P(S=9) unchanged per sub-case, and printing the exact `_getBasePayoutBps` heroIsGold dispatch shape for the 453 IMPL paste.**

## Performance

- **Duration:** ~7 min
- **Started:** 2026-06-21 (PLAN_START captured at execution start)
- **Completed:** 2026-06-21
- **Tasks:** 2
- **Files modified:** 1 (`derive_5_tables.py`)

## Accomplishments

- **Task 1 (EVEQ-01 + GEN-02/GEN-03) — split the honest family per (N, hero-is-gold).**
  Refactored the honest generation path from one averaged table per N into one table per
  structurally-valid `(N, heroGold)` sub-case. Defined `_hero_placement_subcase` and
  `_solve_table` once at the top of the file (the latter shared UNCHANGED with the WWXRP
  `_RIG_` family), enumerated the 8 valid sub-cases (`HONEST_SUBCASES`), and solved each
  against its OWN Variant-2 hero-placement distribution. Split the honest ETH-bonus factor
  solve (`wwxrp_factors_honest(N, heroGold)`) the same way. Updated the FINAL PASTE-READY
  CONSTANTS block to emit greppable per-(N,heroGold) names
  (`QUICK_PLAY_PAYOUTS_N{N}_HEROGOLD_PACKED` / `_HEROCOMMON_PACKED` + matching `_S8` +
  honest `WWXRP_FACTORS_*`), with N0/N4 collapsing to one constant each. The WWXRP `_RIG_`
  family + the m≥7 cap + the SHAPE / S9_PIN / split ratios / ETH_BONUS_BPS / packing are
  untouched. Every honest sub-case asserts `basePayoutEV ∈ (99,100]` and bonus EV = 5.000%.
- **Task 2 (EVEQ-01 + INV-03) — confirm exact equality, per-sub-case pre-proof, dispatch shape.**
  Rewrote the EVEQ-01 report to CONFIRM exact EV-equality (each sub-case vs its OWN table):
  residual drift now **0.00007 centi-x**, hard-asserted `<= 0.01` centi-x, with the explicit
  "Option B: honest lane exactly EV-equal across hero placement (residual <= 0.00007 centi-x)"
  line, the "2.99-edge CLOSED" note, and the WWXRP `_RIG_` averaged-drift by-design note.
  Extended the numeric pre-proof so each NEW honest sub-case `dist[9]` is asserted equal to
  the per-N P(S=9) (Fraction-exact) — proving the honest split does NOT move P(S=9); the
  honest==rigged==HEAD three-way P(S=9) equality still holds for all N. Appended the exact
  `_getBasePayoutBps(N, isWwxrp, heroIsGold)` dispatch shape for the 453 paste (heroIsGold
  selector consulted only when `!isWwxrp`; `_RIG_` indexed by N only; N0/N4 collapse to one
  table each) — printed only, NO `.sol` edited.

## MEASURED RESULTS (surface to USER)

### EVEQ-01 / DEC-02 Option B — residual hero-placement EV drift (centi-x)

Each sub-case evaluated against its OWN solved table (= the EV a player on that pick realizes):

| N | EV(hero gold) | EV(hero common) | \|drift\| |
|---|---------------|-----------------|-----------|
| 0 | n/a | 99.99968 | 0.00000 |
| 1 | 99.99987 | 99.99989 | 0.00002 |
| 2 | 99.99999 | 99.99992 | **0.00007** |
| 3 | 99.99998 | 99.99997 | 0.00001 |
| 4 | 99.99994 | n/a | 0.00000 |

- **MAX residual honest-lane hero-placement EV drift = 0.00007 centi-x (at N=2)** — down
  from the 452-02 **2.99230 centi-x** (a ~43,000× reduction), within `_solve_table` integer
  rounding and hard-asserted `<= 0.01` centi-x.
- **Every honest sub-case basePayoutEV ∈ (99,100]** (all ~99.9999, neutral-or-just-under) —
  no hero-color pick is EV-positive. The 452-02 hero-common EV-positive edge (100.72 /
  101.47 / 102.24 centi-x at N=1/2/3) is **CLOSED**.
- **Honest +5% ETH bonus EV = exactly 5.000000% within EACH sub-case** (all 8).

### Table counts

| Family | Count | Status |
|--------|-------|--------|
| Honest base packed (`QUICK_PLAY_PAYOUTS_N*_PACKED`) | **8** | Option-B split (N0 + N1g/c + N2g/c + N3g/c + N4) |
| Honest base `_S8` | 8 | matching split |
| Honest ETH-bonus factors (`WWXRP_FACTORS_N*_PACKED`) | **8** | matching split |
| WWXRP `_RIG_` packed (`QUICK_PLAY_PAYOUTS_RIG_N{0..4}_PACKED`) | **5** | AVERAGED, unchanged from 452-02 |
| WWXRP `_RIG_` factors (`WWXRP_FACTORS_RIG_N{0..4}_PACKED`) | 5 | unchanged |
| S9 pins (`QUICK_PLAY_PAYOUT_N{0..4}_S9`) | 5 | unchanged = HEAD `[10_756_411, 12_583_037, 14_792_939, 17_512_324, 20_916_435]` |

### Numeric pre-proof — PASSED

P(S=9) is Fraction-exact equal across honest (averaged AND every sub-case), the R2 rig, and
HEAD for all N — the honest split does NOT move P(S=9):

| N | honest P(S=9) | rigged P(S=9) | HEAD all-8-match P |
|---|---------------|---------------|--------------------|
| 0 | 1/12960000 | 1/12960000 | 1/12960000 |
| 1 | 1/25920000 | 1/25920000 | 1/25920000 |
| 2 | 1/51840000 | 1/51840000 | 1/51840000 |
| 3 | 1/103680000 | 1/103680000 | 1/103680000 |
| 4 | 1/207360000 | 1/207360000 | 1/207360000 |

The per-sub-case assert (`dist[9] == averaged P(S=9)` for every honest (N,heroGold)) passes
with no traceback. The `WWXRP_ROI_*` RTP curve (70→115→118→120%) and the S=9 whale-pass
bracket are held fixed in the contract ROI machinery (not recomputed); the R2 rig's m≥7 cap
leaves P(S=9) + its pinned payout intact, so the realized WWXRP RTP curve is byte-identical
to HEAD. `python3 derive_5_tables.py` exits 0 with every assert (existing + new) passing.

### 453 IMPL dispatch shape (printed for the gated diff)

`_getBasePayoutBps(N, isWwxrp, heroIsGold)`: `s9` by N only (pin); if `isWwxrp` -> `_RIG_`
table by N only (heroIsGold ignored, averaged by-design); else honest table by
`(N, heroIsGold)` with N0 always-hero-common and N4 always-hero-gold collapsing to one table
each (heroIsGold consulted only for N in {1,2,3}). The same selector applies to the
ETH-bonus factor dispatch. heroIsGold is a read-only fact from whether the player's hero
quadrant carries a gold color. Printed only — NO `.sol` touched.

## Task Commits

Each task committed atomically (only `derive_5_tables.py` per commit; force-added under
gitignored `.planning/`):

1. **Task 1: Split the honest family per (N, hero-is-gold) and solve each sub-case exactly** — `c72c3247` (feat)
2. **Task 2: Confirm exact EV-equality + per-sub-case P(S=9) pre-proof + 453 dispatch shape** — `f96a39d2` (feat)

_No STATE.md/ROADMAP.md plan-metadata commit — those are orchestrator-owned in this repo and
were intentionally left untouched per execution instructions._

## Files Created/Modified

- `.planning/notes/degenerette-recalibration/derive_5_tables.py`:
  - Module docstring: rewrote the DEC-02 block from Option A (averaged) to Option B (per-(N,
    heroGold) honest split; WWXRP averaged by-design); refreshed the `p_score_distribution`
    docstring to explain the averaged dist is retained only for placement-independent checks.
  - Task 1: moved `_hero_placement_subcase` + `_solve_table` to the top (single definition,
    shared); added `HONEST_SUBCASES` enumeration + the per-sub-case `honest_tables` solve +
    `wwxrp_factors_honest`; rewrote the FINAL honest block (payouts / S8 / factors / EV /
    bonus / RTP) to per-(N,heroGold) naming with `_const_suffix` (N0/N4 collapse); updated the
    `_RIG_` family header + `p_score_distribution_rigged` docstring to state WWXRP stays
    averaged by-design; removed the now-duplicate `_solve_table` definition in the rig section.
  - Task 2: rewrote the EVEQ-01 section to the Option-B exact-equality CONFIRMATION (residual
    line + hard-assert + CLOSED note + WWXRP by-design note); strengthened the pre-proof with
    a per-sub-case P(S=9) placement-independence assert; appended the `_getBasePayoutBps`
    dispatch-shape print for 453.
- `.planning/phases/452-gen-generator-first-no-contract-edit/452-03-SUMMARY.md` — this file.

## Decisions Made

- **N0/N4 collapse to one constant each (no hero-color infix).** They have a single
  structurally-valid hero placement, so a HEROGOLD/HEROCOMMON suffix would be misleading.
  The printed dispatch shape reproduces this (heroIsGold only consulted for N in {1,2,3}).
- **S9 pins stay emitted by N only.** P(S=9) is placement-independent; the pre-proof now
  asserts each honest sub-case's `dist[9]` equals the per-N value, so splitting them would be
  redundant and would risk diverging the byte-reproduce gate from HEAD.
- **Averaged honest dist retained only for invariant checks.** `p_score_distribution` /
  `P_N_TABLE` feed the S9 pin relabel, `rig[9]==honest[9]`, and the pre-proof — never the
  honest PAYOUT solve (which uses the per-sub-case dists).

## Deviations from Plan

None — plan executed exactly as written. Both tasks edited only `derive_5_tables.py`; no
`.sol`, no SHAPE/S9_PIN/split/packing/ETH_BONUS_BPS change; the WWXRP `_RIG_` family is
byte-for-byte the 452-02 averaged 5-table family.

## Issues Encountered

- **Mid-Task-1 intermediate exit=1 (expected, recovered in-task).** After the honest split,
  the legacy EVEQ-01 measurement loop still referenced the now-removed `tables` variable
  (`NameError: name 'tables' is not defined`). This was anticipated — the honest split itself
  passed every per-sub-case assert (the run reached the EVEQ section). Repointed the EVEQ loop
  at `honest_tables` within Task 1 so the script exits 0 before committing; Task 2 then did the
  full Option-B confirmation rewrite. No deviation — the EVEQ rewrite is squarely Task 2's
  scope and the Task-1 commit run exits 0.

## Known Stubs

None — every constant and report line is computed from the per-sub-case / averaged
distributions and asserted on each run. The 453 dispatch shape is intentionally printed-only
(this phase touches NO `.sol`; 453 IMPL is the sole approval gate).

## User Setup Required

None — offline Python generator only; no external service, no `.sol`, no runtime.

## Next Phase Readiness

- **DEC-02 RESOLVED + DELIVERED.** The honest lane is now exactly EV-equal across hero
  placement (residual 0.00007 centi-x, hard-asserted) — the 2.99 centi-x player-selectable
  hero-common edge is closed. 453 IMPL can paste the Option-B honest constant family + the
  printed `_getBasePayoutBps` dispatch shape; the honest-only split is the flagged item for
  USER confirmation at the 453 contract-diff review (per the 452-CONTEXT DEC-02 resolution).
- The full Option-B honest family (8 base + 8 factor tables) + the averaged WWXRP `_RIG_`
  family (5 + 5) + the 5 S9 pins are ready as the 453 IMPL paste source and the 454 TST
  byte-reproduce diff target.
- The P(S=9)/RTP pre-proof passed (honest averaged == every honest sub-case == rigged == HEAD,
  Fraction-exact) — "nothing that matters about WWXRP / the jackpot moved" is re-established
  before the gated diff.
- No blockers on the generator. The only open item is the 453 gated `.sol` diff (sole
  approval gate).

## Self-Check: PASSED

- Commit `c72c3247` (Task 1): FOUND in git log
- Commit `f96a39d2` (Task 2): FOUND in git log
- `derive_5_tables.py`: FOUND (tracked); `python3` run exits 0
- `452-03-SUMMARY.md`: created (this file)
- Verify greps: honest packed (excl RIG) ×8, `_RIG_` packed ×5, honest factors (excl RIG) ×8,
  `_RIG_` factors ×5, S9 pins ×5, `factors<2^64 OK` ×5 (fixed-string); Option-B exact-equality
  line present, residual 0.00007 centi-x, `PRE-PROOF` marker present, `DISPATCH-SHAPE` /
  `heroIsGold` present; only `derive_5_tables.py` in both commits; no `.sol`/STATE/ROADMAP; no
  file deletions.

---
*Phase: 452-gen-generator-first-no-contract-edit*
*Completed: 2026-06-21*
