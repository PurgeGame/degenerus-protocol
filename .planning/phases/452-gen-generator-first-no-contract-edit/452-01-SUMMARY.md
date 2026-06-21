---
phase: 452-gen-generator-first-no-contract-edit
plan: 01
subsystem: testing
tags: [degenerette, variant-2, color-gated, wwxrp-rig, ev-calibration, python-generator]

# Dependency graph
requires:
  - phase: 451 (v72.0 close)
    provides: "frozen v72.0 subject; foil precedent (16225de6) of the color-gated-by-symbol rule being ported"
provides:
  - "Variant-2 honest p_score_distribution (color +1 only on a symbol-matched quadrant; hero symbol +2)"
  - "DEC-01 R2 score-bearing p_score_distribution_rigged (forces only cells that raise S; explicit empty-pool no-lift case)"
  - "Regenerated honest + rigged constant family with honest P(S=9) byte-identical to HEAD"
affects: [452-02 (regen/EV-drift/pre-proof), 453 IMPL (_score + _rigWwxrpResult + constant blocks), 454 TST (byte-reproduce gate)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-quadrant joint (symbol,color) enumeration replaces independent-axis convolution (Variant-2 couples color to symbol)"
    - "DEC-02 Option A: per-N distribution averaged over hero placement (hero gold n/4, common (4-n)/4)"
    - "Rig modeled as a fold over (S, M, e) partial states; e = score-bearing eligible-cell count"

key-files:
  created:
    - .planning/phases/452-gen-generator-first-no-contract-edit/452-01-SUMMARY.md
  modified:
    - .planning/notes/degenerette-recalibration/derive_5_tables.py

key-decisions:
  - "Modeled rig lift as exactly +1 per the plan spec, even where forcing a non-hero symbol would unlock an already-matched color (the +2 path); the color-unlock is accounted separately as the (b) eligible-cell pathway."
  - "Included the hero quadrant's COLOR in the R2 (b) pool — the hero color is an ordinary axis (only the hero SYMBOL is excluded); confirmed against the contract comment 'color axis is ordinary for every quadrant'."
  - "Implemented DEC-02 Option A in BOTH distributions (honest + rigged) by averaging over hero placement; S=9 stays placement-independent so the invariant holds."

patterns-established:
  - "S=9 = all-8-axes product, byte-identical to HEAD across honest + rigged + all hero placements (S9_PIN loop + rig[9]==honest[9] both green)"
  - "Explicit empty-eligible-pool (e==0) no-lift branch — a reachable case (small nonzero mass at N=0..3), not dead code"

requirements-completed: [GEN-01]

# Metrics
duration: ~35min
completed: 2026-06-21
---

# Phase 452 Plan 01: Variant-2 Generator Rewrite Summary

**`derive_5_tables.py` now models Variant-2 (color-gated-by-symbol) honest scoring and the DEC-01 R2 score-bearing WWXRP rig, with honest P(S=9) byte-identical to HEAD and all self-asserts green.**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-06-21 (PLAN_START captured at execution start)
- **Completed:** 2026-06-21
- **Tasks:** 2
- **Files modified:** 1 (`derive_5_tables.py`)

## Accomplishments

- **Task 1 — Variant-2 honest distribution.** Rewrote `p_score_distribution` from the
  independent `S = A + 2H` model to the per-quadrant joint (symbol, color) model: a symbol
  match scores +1 (hero +2), and that quadrant's color scores +1 ONLY IF its symbol also
  matched. Convolves three ordinary-quadrant dists {0,+1,+2} with the hero-quadrant dist
  {0,+2,+3}; max S=9. Effect: P(any payout, S≥2) drops from HEAD's ~32.4% (1-in-3) to
  **19.6% (1-in-5) at N=0** — the documented "~1-in-5 at ~2× multipliers at identical EV"
  intent. E[S] N=0 fell 1.158 → 0.692.
- **Task 2 — R2 score-bearing rigged distribution.** Re-derived `p_score_distribution_rigged`
  to force ONLY score-bearing cells under Variant-2: (a) an unmatched non-hero symbol (+1) or
  (b) an unmatched color on a quadrant whose symbol already matched (+1, incl. the hero color);
  hero symbol and no-op colors excluded. Added the explicit empty-eligible-pool (e==0) no-lift
  case. The m≥7 cap is preserved so the rig never manufactures S=9.
- **S=9 invariant held end-to-end.** Honest P_N(S=9) is exactly the all-8-axes product
  (1/12,960,000 → 1/207,360,000 for N=0..4), byte-identical to HEAD; both the `S9_PIN`
  reproduction loop and the rigged `rig[9] == P_N_TABLE[N][9]` assert pass for all N.

## Task Commits

Each task was committed atomically (only `derive_5_tables.py` per commit):

1. **Task 1: Rewrite p_score_distribution for Variant-2 (color-gated-by-symbol)** — `15457fa0` (feat)
2. **Task 2: Re-derive p_score_distribution_rigged for DEC-01 R2 (score-bearing pool)** — `6a29234d` (feat)

_No plan-metadata commit for STATE.md/ROADMAP.md — those are orchestrator-owned in this repo and were intentionally left untouched (per execution instructions)._

## Files Created/Modified

- `.planning/notes/degenerette-recalibration/derive_5_tables.py` — rewrote `p_score_distribution`
  (+ new `_ordinary_quadrant_dist` / `_hero_quadrant_dist` helpers) and `p_score_distribution_rigged`
  (+ new `_quad_states` helper); only the two distribution functions and their docstrings changed.
  `SHAPE` / `S9_PIN` / `_solve_table` / `wwxrp_factors*` / all print blocks are byte-unchanged.
- `.planning/phases/452-gen-generator-first-no-contract-edit/452-01-SUMMARY.md` — this file.

## Verify Outputs

Task 1 (`python3 derive_5_tables.py`):
```
exit=0
"S=9 relabel pin reproduced from the old M=8 scaling for all N (consistent)."  (printed)
honest P_N(S=9) byte-identical to HEAD (1/12960000 … 1/207360000)
P(any payout, S>=2): N=0 19.6094% (1 in 5.10) … N=4 17.9346% (1 in 5.58)
```

Task 2 (`python3 derive_5_tables.py`):
```
exit=0
5 rigged-verification lines, each: rigged EV in (99,100] | bonus EV=5.00000% | factors<2^64 OK
  N=0 99.99913 | N=1 99.99865 | N=2 99.99982 | N=3 99.99940 | N=4 99.99945
assert rig[9] == P_N_TABLE[N][9] passes for all 5 N (m>=7 cap held)
empty-eligible-pool case reachable (nonzero mass at N=0..3)
```

Note on the plan's literal verify command `grep -c "factors<2^64 OK"`: it returns **0** because
`^` is a BRE anchor metacharacter in `grep`, so the pattern never matches literally. The five
lines ARE present — confirmed with `grep -cF "factors<2^64 OK"` → **5**. This is a grep-regex
artifact in the verify string, not a missing-output failure (the script exits 0 with all asserts
passing).

## Decisions Made

- **Rig lift modeled as exactly +1** (per the plan `<action>` spec), even in the (sm=0, cm=1)
  case where forcing the symbol would honestly unlock the already-matched color for +2. The
  color-unlock is instead captured as the separate (b) eligible-cell pathway, keeping the model
  faithful to "force ONE cell, +1" and consistent with the contract forcing exactly one cell.
- **Hero quadrant's color is in the R2 (b) pool.** The hero color is an ordinary axis (contract:
  "color axis is ordinary for every quadrant"); only the hero SYMBOL is excluded from the rig.
- **DEC-02 Option A applied to both distributions** by averaging over hero placement within a
  fixed N. S=9 depends only on the gold/common COUNT (not which quadrant is hero), so the
  averaging leaves the S=9 invariant untouched.

## Deviations from Plan

None — plan executed exactly as written. Both distribution functions were rewritten in place;
no other sections touched; all existing self-asserts pass.

## Issues Encountered

- **Spurious commit during Task 1 (recovered).** The first `git commit` for Task 1 picked up an
  orchestrator-pre-staged STATE.md change (committed under the wrong message) because `git add`
  on the gitignored-but-tracked `derive_5_tables.py` did not stage on the first attempt. Recovered
  with `git reset --soft` to the pre-commit point, unstaged STATE.md (orchestrator-owned), and
  re-committed ONLY the generator with `git add -f`. Final history is clean: `15457fa0` (Task 1)
  and `6a29234d` (Task 2) each contain only `derive_5_tables.py`; STATE.md was left as an
  untouched working-tree change for the orchestrator. Lesson reinforced: always `git add -f` the
  tracked file under gitignored `.planning/` and verify the staged set before committing.

## User Setup Required

None — offline Python generator only; no external service configuration, no `.sol`, no runtime.

## Next Phase Readiness

- The two Variant-2 distributions are in place and trustworthy (self-assert harness green).
- **Plan 02** can now consume them for constant regen, the DEC-02 Option-A EV-drift measurement
  (hero-gold vs hero-common worst-case), and the new pre-proof printing — none of which were
  added here (correctly out of scope for Plan 01).
- No blockers. No contract surface touched; the sole approval gate remains Phase 453 IMPL.

## Self-Check: PASSED

- Commit `15457fa0` (Task 1): FOUND in git log
- Commit `6a29234d` (Task 2): FOUND in git log
- `derive_5_tables.py`: FOUND (tracked)
- `452-01-SUMMARY.md`: created (this file)

---
*Phase: 452-gen-generator-first-no-contract-edit*
*Completed: 2026-06-21*
