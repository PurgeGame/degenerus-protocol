---
phase: 452-gen-generator-first-no-contract-edit
plan: 02
subsystem: testing
tags: [degenerette, variant-2, ev-equality, ev-drift, wwxrp-rig, p-s9-invariant, python-generator]

# Dependency graph
requires:
  - phase: 452-01 (Variant-2 generator rewrite)
    provides: "Variant-2 honest p_score_distribution + DEC-01 R2 score-bearing p_score_distribution_rigged (both averaged over hero placement); honest P(S=9) byte-identical to HEAD"
provides:
  - "Full Variant-2 constant family regenerated off the Plan-01 distributions (honest QUICK_PLAY_PAYOUTS_N{0..4}_PACKED/_S8 + WWXRP_FACTORS_N{0..4} + the full _RIG_ family) with all GEN-02 self-asserts green"
  - "EVEQ-01 / DEC-02 hero-placement EV-drift measurement (hero-gold vs hero-common per N, max across N) with a conditional DEC-02 verdict"
  - "Numeric pre-proof (INV-03): honest == rigged == HEAD P(S=9) Fraction-exact for all N + WWXRP RTP curve confirmed held fixed, with a grep-able PRE-PROOF marker"
  - "MEASURED FINDING: hero-placement EV drift = 2.9923 centi-x (N=3), grossly outside the ~0.5 centi-x tolerance → DEC-02 verdict = ESCALATE to Option B (USER + 453 IMPL decision required)"
affects: [453 IMPL (must resolve DEC-02 Option-A-vs-B before pasting the constant family + _getBasePayoutBps dispatch), 454 TST (byte-reproduce gate re-derives this FINAL block), 455 REAUDIT]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Hero-placement sub-case isolation (_hero_placement_subcase) reuses the exact per-quadrant Variant-2 convolution but for ONE fixed hero placement, to expose the EV split the averaged per-N table hides"
    - "Conditional DEC-02 verdict: 'Option A kept' if max drift <= ~0.5 centi-x else 'ESCALATE to Option B' — the verdict is data-driven, not pre-baked"
    - "Numeric pre-proof prints honest/rigged/HEAD P(S=9) side-by-side as Fractions and asserts exact equality (no float tolerance) for all N"

key-files:
  created:
    - .planning/phases/452-gen-generator-first-no-contract-edit/452-02-SUMMARY.md
  modified:
    - .planning/notes/degenerette-recalibration/derive_5_tables.py

key-decisions:
  - "Did NOT hard-assert per-sub-case EV <= 100 — the plan asks to REFERENCE the existing averaged-table EV<=100 assert, not add a new per-sub-case one. The per-sub-case EV split IS the EV drift being measured; a hard assert there would mask the EVEQ-01 finding."
  - "Surfaced the EV>100 hero-common sub-case as a measured FINDING (not a code deviation): the 452 CONTEXT's DEC-02 solvency note assumed BOTH sub-cases stay <=100 (a hair of drift); the Variant-2 measurement shows ~2.9 centi-x and the hero-common EV exceeds 100 at N=1..3, which is exactly the EVEQ-01 'grossly outside tolerance' trigger to revisit Option B."
  - "Used _p_old(N)[8] (the existing HEAD M=8 reproduction) as the HEAD all-8-match probability in the pre-proof — it is the same physical event as Variant-2 S=9, so the three-way equality is the right invariant."

patterns-established:
  - "S=9 = all-8-axes event is byte-identical to HEAD across honest, rigged, AND the explicit HEAD-M8 reproduction (1/12,960,000 → 1/207,360,000 for N=0..4) — proven Fraction-exact before any .sol edit"
  - "EVEQ-01 measurement is free (no contract cost) and is the gate that converts DEC-02 from an assumption into a measured decision"

requirements-completed: [GEN-02, GEN-03, EVEQ-01]

# Metrics
duration: ~25min
completed: 2026-06-21
---

# Phase 452 Plan 02: Variant-2 Constant Regen + EV-Drift + P(S=9) Pre-Proof Summary

**`derive_5_tables.py` regenerates the full Variant-2 constant family (honest + `_RIG_`) off the Plan-01 distributions, measures the DEC-02 hero-placement EV drift (max 2.9923 centi-x at N=3 — grossly outside tolerance → verdict ESCALATE to Option B), and proves Fraction-exact that P(S=9) and the WWXRP RTP curve are unchanged vs HEAD.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-06-21 (PLAN_START captured at execution start)
- **Completed:** 2026-06-21
- **Tasks:** 2
- **Files modified:** 1 (`derive_5_tables.py`)

## Accomplishments

- **Task 1 (GEN-03 + GEN-02) — full constant family regenerated + doc refresh.** With the
  Plan-01 Variant-2 distributions in place, the existing solve/pack/print machinery
  (`_solve_table`, `wwxrp_factors`, `wwxrp_factors_rig`, the packing loops) regenerates the
  complete FINAL PASTE-READY CONSTANTS block off them with zero structural change: 5 honest
  `QUICK_PLAY_PAYOUTS_N{0..4}_PACKED` + 5 `_S8` + 5 `WWXRP_FACTORS_N{0..4}_PACKED`, plus the full
  `_RIG_` family (5 `QUICK_PLAY_PAYOUTS_RIG_N{0..4}_PACKED` + 5 `_S8` + 5
  `WWXRP_FACTORS_RIG_N{0..4}_PACKED`). All GEN-02 self-asserts pass (per-N honest+rigged
  basePayoutEV ∈ (99,100]; bonus-EV = 5.00000%; all WWXRP factors < 2^64; rigged P(S=9) == honest
  P(S=9)). The 5 `QUICK_PLAY_PAYOUT_N{0..4}_S9` pins print equal to the HEAD values
  `[10_756_411, 12_583_037, 14_792_939, 17_512_324, 20_916_435]` and are never recomputed; the
  `WWXRP_ROI_*` / RTP curve is not regenerated. The deferred-from-wave-1 doc refresh landed: the
  module docstring, the FINAL-block header, and the RIG-FAMILY header now describe Variant-2
  (color-gated-by-symbol) and the DEC-01 R2 score-bearing rig (replacing the old `S = A + 2H` and
  "variant-B ordinary-only" descriptions).
- **Task 2 (EVEQ-01 + pre-proof) — drift measurement + numeric pre-proof.** Added two new
  print/verify sections after the FINAL blocks (existing asserts untouched):
  1. **EVEQ-01 / DEC-02 Option-A EV-drift.** Built the hero-gold and hero-common sub-case
     distributions per N (reusing the exact Variant-2 per-quadrant convolution, no averaging),
     evaluated the SAME solved per-N honest table against each, and reported the worst-case
     `|EV_gold − EV_common|` per N plus the max across N with a data-driven DEC-02 verdict.
  2. **Numeric pre-proof (INV-03).** Prints honest `P_N(S=9)`, rigged `P_N(S=9)`, and the HEAD
     all-8-match probability side-by-side as Fractions and asserts all three EQUAL for every N;
     states the `WWXRP_ROI_*` curve (70→115→118→120%) + the S=9 whale-pass bracket are held fixed
     in the contract (INV-02/INV-04), not recomputed; prints the grep-able marker
     `PRE-PROOF: P(S=9) and WWXRP RTP curve unchanged vs HEAD under Variant-2 + R2 rig`.

## MEASURED RESULTS (surface to USER)

### EVEQ-01 / DEC-02 hero-placement EV drift (centi-x)

| N | EV(hero gold) | EV(hero common) | \|drift\| |
|---|---------------|-----------------|-----------|
| 0 | n/a (no gold hero possible) | 99.99968 | 0.00000 |
| 1 | 97.84837 | **100.71705** | 2.86868 |
| 2 | 98.52780 | **101.47210** | 2.94430 |
| 3 | 99.25183 | **102.24413** | **2.99230** |
| 4 | 99.99994 | n/a (no common hero possible) | 0.00000 |

- **MAX hero-placement EV drift across N = 2.9923 centi-x (at N=3).**
- **DEC-02 verdict: ESCALATE to Option B.** The drift grossly exceeds the ~0.5 centi-x tolerance,
  and the hero-COMMON sub-case EV exceeds 100 centi-x at N=1..3 (EV-positive to the player on
  those picks). The 452 CONTEXT's DEC-02 solvency note assumed BOTH sub-cases stay ≤100 (a hair of
  drift); under the measured Variant-2 drift that assumption does NOT hold. Per EVEQ-01 / DEC-02
  this is exactly the documented "grossly outside tolerance" trigger to revisit Option B (index by
  `(N, hero-is-gold)`, ~8–9 tables + a small `_getBasePayoutBps` dispatch tweak). **Option A is NOT
  silently kept** — a USER + 453 IMPL decision is required.

### Numeric pre-proof — PASSED

P(S=9) is Fraction-exact equal across honest Variant-2, the R2 rig, and HEAD for all N:

| N | honest P(S=9) | rigged P(S=9) | HEAD all-8-match P |
|---|---------------|---------------|--------------------|
| 0 | 1/12960000 | 1/12960000 | 1/12960000 |
| 1 | 1/25920000 | 1/25920000 | 1/25920000 |
| 2 | 1/51840000 | 1/51840000 | 1/51840000 |
| 3 | 1/103680000 | 1/103680000 | 1/103680000 |
| 4 | 1/207360000 | 1/207360000 | 1/207360000 |

The `WWXRP_ROI_*` RTP curve (70→115→118→120%) and the S=9 whale-pass bracket are confirmed held
fixed in the contract ROI machinery (not recomputed here); the R2 rig's m≥7 cap leaves P(S=9) and
its pinned payout intact, so the realized WWXRP RTP curve is byte-identical to HEAD. `python3
derive_5_tables.py` exits 0 with every assert (existing + new) passing.

## Task Commits

Each task was committed atomically (only `derive_5_tables.py` per commit; force-added under
gitignored `.planning/`):

1. **Task 1: Regenerate full Variant-2 constant family + doc refresh (GEN-03 + GEN-02)** — `67d3b3d8` (docs)
2. **Task 2: EVEQ-01 hero-placement EV-drift measurement + P(S=9)/RTP pre-proof** — `483a5ea4` (feat)

_No STATE.md/ROADMAP.md plan-metadata commit — those are orchestrator-owned in this repo and were
intentionally left untouched per execution instructions._

## Files Created/Modified

- `.planning/notes/degenerette-recalibration/derive_5_tables.py`:
  - Task 1: refreshed the module docstring (Variant-2 color-gated-by-symbol model + DEC-02
    Option-A averaging + DEC-03 S≥2 floor), the FINAL-block header, and the RIG-FAMILY header
    (DEC-01 R2 score-bearing rig). No SHAPE / S9_PIN / split / packing change.
  - Task 2: appended two new sections after the FINAL blocks — `_hero_placement_subcase` + the
    EVEQ-01 drift report/verdict, and the numeric P(S=9) pre-proof with the grep marker.
- `.planning/phases/452-gen-generator-first-no-contract-edit/452-02-SUMMARY.md` — this file.

## Decisions Made

- **Per-sub-case EV<=100 is NOT hard-asserted.** The plan asks to *reference* the existing
  averaged-table EV<=100 assert (the priced-across-picks house-edge guarantee, still green), not to
  add a new per-sub-case assert. My first draft hard-asserted per-sub-case <=100 and it correctly
  tripped at N=1 — that assert was wrong (it would mask the EVEQ-01 finding), so I removed it and
  surfaced the EV>100 hero-common sub-case as the measured drift instead.
- **The ESCALATE verdict is a valid Task-2 outcome.** The plan's acceptance criteria explicitly
  allow the verdict line to read "ESCALATE to Option B" when drift is grossly outside tolerance.
  The measurement did its job; the script exits 0; the decision is now front-loaded for 453 IMPL.

## Deviations from Plan

None — plan executed exactly as written. The "ESCALATE to Option B" verdict is an expected,
plan-sanctioned measurement outcome (not a deviation): EVEQ-01 explicitly defines both the
"Option A kept" and "ESCALATE to Option B" branches, and the generator took the latter because the
measured drift (2.9923 centi-x) is grossly outside the ~0.5 centi-x tolerance the CONTEXT
anticipated. No contract surface touched; no SHAPE/S9_PIN/split/packing change.

## Issues Encountered

- **First-draft per-sub-case solvency assert tripped (recovered).** My initial Task-2 code added a
  hard `assert total_ev(table, sub) <= 100` per hero-placement sub-case, which failed at N=1
  (hero-common EV = 100.71705). On review this was MY over-assertion, not a generator bug: the
  plan asks to reference the existing averaged-table assert, not add a per-sub-case one, and the
  EV>100 split is precisely the EVEQ-01 drift to be reported. Replaced the hard assert with a
  finite-drift assert + an informational EV>100 note, and let the conditional verdict report
  "ESCALATE to Option B". Script then exits 0.

## Known Stubs

None — the generator is fully wired; every constant and every report line is computed from the
Plan-01 distributions and asserted on each run.

## User Setup Required

None — offline Python generator only; no external service configuration, no `.sol`, no runtime.

## Next Phase Readiness

- **DECISION GATE for 453 IMPL:** the EVEQ-01 measurement says the residual hero-placement EV drift
  (max 2.9923 centi-x, hero-common EV-positive at N=1..3) is grossly outside the ~0.5 centi-x
  tolerance — the DEC-02 verdict is **ESCALATE to Option B**. 453 IMPL cannot simply paste the 5
  averaged per-N tables without a USER decision on Option A vs Option B (per-`(N, hero-is-gold)`
  tables + a `_getBasePayoutBps` dispatch tweak). This is front-loaded here, before any `.sol` edit,
  exactly as the generator-first posture intends.
  - NOTE: the USER ruling in the 452 CONTEXT ("WWXRP gold-payout drift is don't-care") applies to
    the WWXRP rigged lane specifically; the drift measured here is on the **honest** (ETH/FLIP)
    averaged table where the hero-common sub-case goes EV-positive, so the don't-care ruling does
    not automatically dispose of it — the orchestrator should put this in front of the USER.
- The full Variant-2 constant family + the pre-proof are ready as the 453 IMPL paste source and the
  454 TST byte-reproduce diff target.
- The P(S=9)/RTP pre-proof passed (honest == rigged == HEAD, Fraction-exact) — the "nothing that
  matters about WWXRP / the jackpot moved" guarantee is established before the gated diff.
- No blockers on the generator itself; the only open item is the DEC-02 Option-A-vs-B decision.

## Self-Check: PASSED

- Commit `67d3b3d8` (Task 1): FOUND in git log
- Commit `483a5ea4` (Task 2): FOUND in git log
- `derive_5_tables.py`: FOUND (tracked); `python3` run exits 0
- `452-02-SUMMARY.md`: created (this file)
- Verify greps: FINAL blocks ×2, honest packed ×5, rig packed ×5, WWXRP factors ×10, S9 pins ×5,
  `factors<2^64 OK` ×5 (fixed-string); drift report present, `PRE-PROOF` marker present, `P(S=9)`
  lines present

---
*Phase: 452-gen-generator-first-no-contract-edit*
*Completed: 2026-06-21*
