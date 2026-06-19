---
phase: 435-design-design-lock-the-point-unit-streak-path-packing-equiva
plan: 03
subsystem: audit
tags: [design-lock, behaviour-equivalence, scale-invariance, activity-score, points, lootbox-ev, degenerette-roi, decimator, edit-surface, rng-freeze, v69]

# Dependency graph
requires:
  - phase: 435-01 (DESIGN-01 + DESIGN-02 sections of 435-DESIGN-LOCK.md)
    provides: point unit (1 pt = 100 bps), floor(questStreak/2), 655 cap, subStreakLatch widening + per-symbol edits to fold into the consolidated 436 surface
  - phase: 435-02 (DESIGN-03 section of 435-DESIGN-LOCK.md)
    provides: pendingFlip uint32->uint24, the 72-bit accumulator repack, the layout-golden recapture flag + lootboxRngPendingFlip out-of-scope confirmation
  - phase: v68.0 baseline (contracts/ tree e9a5fc24)
    provides: byte-frozen _lootboxEvMultiplierFromScore, _roiBpsFromScore/_wwxrpHighRoiFromScore, decimator multiplier+bucket, the four uint16-activityScore lootbox entrypoints, the external playerActivityScore boundary
provides:
  - DESIGN-04 design-lock — per-consumer scale-invariance proof (Lootbox EV, Degenerette ROI incl. the QUADRATIC low leg, Decimator), the input-vs-output constant inventory (TABLE A convert / TABLE B do-not-convert), the bounded odd-half-point de-minimis divergence (D-09)
  - The consolidated per-file/per-symbol 436 edit surface (union of DESIGN-01..04 + threshold migrations + the 7 anchor-correction comment fixes) with a DO-NOT-TOUCH list
  - The 438 RNG-freeze re-audit executor checklist (external boundary, frozen-at-deposit anti-gaming knob, layout-golden recapture, mutation+invariant re-run)
affects: [436-IMPL (POINTS-02 threshold migration + the decimator multiplier re-scale + the consolidated diff), 437-TST, 438-REAUDIT (REAUDIT-01 layout golden + REAUDIT-02 freeze/boundary re-attest)]

# Tech tracking
tech-stack:
  added: []
  patterns: [scale-invariance proof of integer threshold/interpolation math under /100; input-vs-output constant classification tables; consolidated mechanical per-symbol edit surface; source-anchored re-audit handoff checklist]

key-files:
  created:
    - .planning/phases/435-design-design-lock-the-point-unit-streak-path-packing-equiva/435-03-SUMMARY.md
  modified:
    - .planning/phases/435-design-design-lock-the-point-unit-streak-path-packing-equiva/435-DESIGN-LOCK.md

key-decisions:
  - "Equivalence (D-10) proved by scale-invariance: comparisons (score vs anchor) and ratios (score*K/range) are invariant under /100 because the score AND the TABLE-A input anchors both divide by 100 while the OUTPUT anchors (K) are untouched; for clean whole-point scores every consumer result is bit-identical"
  - "Input-vs-output inventory: TABLE A converts /100 (Degenerette MID/HIGH/MAX 7500/25500/30500->75/255/305, Lootbox NEUTRAL/MAX 6000/40000->60/400, Decimator CAP 23500->235); TABLE B must NOT convert (ROI 9000-9990 + WWXRP 9000/10990, EV-mult 9000/10000/14500, quad coeffs 1000/500, DGNRS reward bps, BPS_DENOMINATOR 10000)"
  - "Sole divergence (D-09) = the odd-half-point threshold-tip: floor(questStreak/2) drops a trailing 0.5 pt that can shift a consumer outcome by at most one grid cell at one boundary, and only for odd-quest-streak players landing on a boundary; piecewise legs are continuous at their joins so the shift is typically 0; ACCEPTED + DOCUMENTED, no threshold nudging"
  - "Consolidated 436 edit surface authored as a single per-file/per-symbol mechanical diff (union of DESIGN-01..04 edits + the point-domain threshold migrations + the 7 anchor-correction comment fixes), with an explicit DO-NOT-TOUCH list"
  - "438 RNG-freeze re-audit checklist: external playerActivityScore bps->points boundary (sDGNRS uint16(score)+1 re-verified point-correct, 656 fits uint16, 0=unset sentinel holds; indexer/off-chain parity flagged), the uint16 frozen-at-deposit anti-gaming knob across the 4 lootbox entrypoints (655 fits uint16), the layout-golden recapture (expected new golden, not drift), mutation+invariant re-run on the changed modules"

patterns-established:
  - "Behaviour-equivalence of an integer-domain rescale is proven by scale-invariance of the comparisons + ratios, not by hand-checking every grid point; the residual divergence is bounded and accepted explicitly"

requirements-completed: [DESIGN-04]

# Metrics
duration: ~6min
completed: 2026-06-19
---

# Phase 435 Plan 03: Design-Lock Consumer-Threshold Equivalence + Consolidated Edit Surface + Re-Audit Checklist Summary

**Appended the load-bearing DESIGN-04 section to the v69 design-lock: the per-consumer scale-invariance proof (Lootbox EV multiplier, Degenerette ROI — including the QUADRATIC low leg the plan mislabelled as linear — and the Decimator bucket/multiplier), the input-vs-output constant inventory (TABLE A converts ÷100 / TABLE B must not), and the bounded odd-half-point de-minimis divergence (D-09); then consolidated the union of all DESIGN-01..04 edits into a single per-file/per-symbol 436 edit surface with a DO-NOT-TOUCH list, and authored the 438 RNG-freeze re-audit executor checklist — read-only against the byte-frozen v68 baseline `e9a5fc24`, NO `.sol` change.**

## Performance

- **Duration:** ~6 min
- **Completed:** 2026-06-19
- **Tasks:** 2
- **Files modified:** 1 (435-DESIGN-LOCK.md, +199 lines appended → now 496 lines, DESIGN-01..04 + 436 surface + 438 checklist complete), 1 summary created

## Accomplishments

- **DESIGN-04 equivalence proof (Task 1):**
  - Established the two pre-conditions from DESIGN-01: the score is always a multiple of 50 bps and every contributor except the quest-streak leg is a multiple of 100, so the *floored* score (D-02) is always a clean whole point — the point domain is exact for it by construction.
  - **TABLE A** (6 score-INPUT thresholds that convert ÷100) and **TABLE B** (10+ output/out-of-domain bps that must NOT convert) with file:line and per-constant role/rationale. Explicitly disambiguated the "40000" collision: the EV-cap = `LOOTBOX_EV_ACTIVITY_MAX_BPS` (`Storage:1555` → 400), while the coincidentally-equal `LootboxModule:304` "40000" is the derived presale-box FLIP-band EV mean (ignore).
  - **Per-consumer scale-invariance proof (D-10)** with the general comparison + ratio cancellation argument, then applied with worked numeric checks to each consumer: Lootbox EV (`_lootboxEvMultiplierFromScore:1633-1654`, all three branches), Degenerette ROI (`_roiBpsFromScore:1141-1170` + `_wwxrpHighRoiFromScore:1179-1190`), and the Decimator (clamp + `_terminalDecBucket:1133-1144` + the multiplier).
  - **Bounded odd-half-point divergence (D-09)** enumerated as the sole divergence, with a worked Lootbox-EV boundary example showing the piecewise legs are continuous at their joins (shift ≤ 1 grid cell, typically 0); confirmed the ACCEPTED + DOCUMENTED disposition, no threshold nudging.
- **Consolidated 436 edit surface + 438 checklist (Task 2):**
  - A single per-file/per-symbol 436 change list spanning MintStreakUtils (floor + point cap + ×100-leg collapse), DegenerusGameStorage (cap 655, subStreakLatch uint8→uint16 + mask, pendingFlip uint32→uint24 + clamp re-pin, EV input anchors 60/400, the accumulator repack + all comment fixes), GameAfkingModule (accrue casts/clamps + latch follow-through), DegenerusQuests (DELETE the floor-hack), Degenerette (MID/HIGH/MAX), Decimator (CAP + the multiplier re-scale + the bucket) — folding in all 7 prior anchor-correction comment fixes — plus an explicit **DO-NOT-TOUCH list**.
  - The **438 RNG-freeze re-audit checklist**: REAUDIT-02 external `playerActivityScore` bps→points boundary (IDegenerusGame:65 → DegenerusGame:2210-2218 → sDGNRS:47/:1140 + decimator self-call, with the `uint16(score)+1` point-correctness re-verified — 656 fits uint16, 0=unset sentinel holds — and indexer/off-chain parity flagged); REAUDIT-02 the `uint16` frozen-at-deposit anti-gaming knob across the four lootbox entrypoints (`:873/:928/:967/:1076`, 655 fits uint16); REAUDIT-01 the layout-golden recapture (expected new golden, not a drift) + EIP-170 re-attest; the mutation + invariant re-run on the changed modules; and the `lootboxRngPendingFlip` out-of-scope confirmation.

## Task Commits

Each task was committed atomically with `git add -f` (`.planning/` is gitignored in this repo):

1. **Task 1: Author the DESIGN-04 equivalence proof + input-vs-output inventory** — `745dc8d0` (docs, +118 lines)
2. **Task 2: Consolidate the 436 edit surface + author the 438 RNG-freeze re-audit checklist** — `7f2718c7` (docs, +81 lines)

## Files Created/Modified

- `.planning/phases/435-design-design-lock-the-point-unit-streak-path-packing-equiva/435-DESIGN-LOCK.md` — appended `## DESIGN-04`, `## 436 Edit Surface (consolidated)`, `## 438 RNG-Freeze Re-Audit Checklist` (+199 lines; the doc now holds DESIGN-01..04 + the consolidated surface + the re-audit checklist, 496 lines total — the load-bearing design-lock is complete).
- `.planning/phases/435-design-design-lock-the-point-unit-streak-path-packing-equiva/435-03-SUMMARY.md` — this summary.

## Decisions Made

None beyond recording the USER-locked D-09/D-10 (LOCKED in CONTEXT.md; this plan records them with the source-anchored proof, the inventory tables, and the bounded divergence). Claude's-discretion items (constant naming/placement) stay deferred to 436 IMPL as the plan specified.

## Deviations from Plan

None — plan executed exactly as written (Rules 1-4 not triggered). No `contracts/*.sol`, STATE.md, or ROADMAP.md touched. The proof was built per D-10 (scale-invariance) and D-09 (accept + document the bounded divergence); the source-discovered nuances below were captured as `[ANCHOR NOTE]`s inside the design-lock (source is ground truth) rather than as deviations, since they refine — not change — the locked decisions.

## Anchor Corrections (source is ground truth)

Two NEW `[ANCHOR NOTE]` corrections were surfaced in DESIGN-04 by reading the consumer math at the frozen `e9a5fc24` tree (both are recorded inline in the design-lock and both *strengthen* rather than weaken the equivalence argument):

1. **Degenerette ROI low segment is QUADRATIC, not linear** (`DegeneretteModule:1148-1154`): the plan/CONTEXT interfaces described all ROI legs as "linear interpolation." The live `score <= MID` leg is a quadratic ease (`term1 = 1000·x/MID`, `term2 = 500·x²/MID²`). Scale-invariance still holds and is the stronger claim — `term1` cancels one factor of 100, `term2` cancels 100² in numerator and denominator — and the coefficients `1000`/`500` are output-domain shape constants that must NOT convert (added to TABLE B).
2. **Decimator multiplier is `bonusBps/3`, NOT a CAP ratio** (`DecimatorModule:799-801`, `:913-919`): the plan's interface block said the decimator "uses CAP in the (CAP/2)/CAP ratio." That `(CAP/2)/CAP` ratio is the *bucket* leg (`_terminalDecBucket:1135-1141`, which IS scale-invariant). The *multiplier* leg is the bare integer division `BPS_DENOMINATOR + (bonusBps/3)`, which is NOT scale-invariant under a naive ÷100. The design-lock records the mandatory 436 fix: re-express it as `BPS_DENOMINATOR + (points·100)/3` (a `×100` re-scale, not a ÷100 of a constant) — a naive `points/3` would be ~100× wrong. This is the one consumer leg whose migration is non-trivial; it is flagged in both the 436 edit surface and the 438 re-attest list.

(Also confirmed an additional in-family consumer the plan did not enumerate: `_wwxrpHighRoiFromScore` (`:1179-1190`) uses `ACTIVITY_SCORE_MAX_BPS` as its input range anchor and `WWXRP_HIGH_ROI_BASE/MAX_BPS` as output anchors — scale-invariant, folded into the Degenerette TABLE A/B classification and the 436 surface.)

The 7 prior anchor corrections from plans 01/02 (the stale `Storage:2144` bits-0-6 comment, the three Sub-struct sub-total comments `config 40b→48b` / `per-sub stamp 48→40b` / `markers 72→96b`, the sDGNRS sentinel `:1138-1141`, the `lootboxRngPendingFlip :1525`) are all rolled into the consolidated 436 edit surface as `[comment]` fixes.

## Threat Model Coverage

- **T-435-07 (Tampering — EV/ROI/decimator behaviour-equivalence):** mitigated — per-consumer scale-invariance proof (÷100 of score AND input anchors preserves the ratio; output anchors untouched → integer result identical for clean scores) with worked checks; the sole divergence (odd-half-point tip) bounded to ≤1 grid cell at one boundary and accepted (D-09).
- **T-435-08 (Tampering — input-vs-output constant misclassification):** mitigated — TABLE A (convert) vs TABLE B (do-not-convert) with file:line; the `:304` "40000" EV-mean comment flagged a non-anchor; the consolidated 436 surface carries an explicit DO-NOT-TOUCH list.
- **T-435-09 (Information disclosure — external playerActivityScore bps→points boundary):** mitigated — handed to 438 REAUDIT-02 (sDGNRS `uint16(score)+1` re-verified point-correct, 656 fits uint16, 0=unset sentinel holds; indexer/off-chain parity flagged).
- **T-435-10 (Elevation of privilege — RNG-freeze under the point domain):** mitigated — re-confirm the `uint16 activityScore` snapshot-at-deposit freeze across the four lootbox entrypoints (655 fits uint16, no in-window score-bump bias); re-attested in 438 REAUDIT-02.
- **T-435-SC (npm/pip/cargo installs):** N/A — read-only docs-only phase, no install task exists.

## Threat Flags

None — DESIGN-04 introduces no new security surface; it documents a behaviour-equivalence proof and hands the existing external boundary + freeze surfaces to 438 for re-attestation.

## Known Stubs

None — this is a docs-only design-lock; no code, components, or data sources were stubbed. The 436 edit surface and 438 checklist are complete handoffs, not placeholders.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration. Documentation-only design-lock phase.

## Next Phase Readiness

- The v69 design-lock document `435-DESIGN-LOCK.md` is **complete** (DESIGN-01..04 + the consolidated 436 edit surface + the 438 re-audit checklist, 496 lines). DESIGN-04 is the load-bearing correctness argument: equivalence is proven by scale-invariance, the input/output inventory is unambiguous, and the sole divergence is bounded + accepted.
- **436 IMPL** (POINTS-01/02 + STREAK-01/02 + PACK-01) can now be implemented as a single mechanical batched diff from the consolidated edit surface — with the one non-trivial item flagged loudly: the **Decimator multiplier `×100` re-scale** (not a ÷100 of a constant). The DO-NOT-TOUCH list prevents the common error (converting output bps).
- **437 TST** owns the clamp-saturation property (TST-02) + the new-domain consumer tests. **438 REAUDIT** owns REAUDIT-01 (layout golden recapture, expected new golden) + REAUDIT-02 (external boundary + frozen-at-deposit freeze re-attest) + the mutation/invariant re-run, all per the checklist.
- No blockers. NO `contracts/*.sol`, STATE.md, or ROADMAP.md modified (orchestrator owns those writes).

## Self-Check: PASSED

- `435-DESIGN-LOCK.md` has `## DESIGN-04`, `## 436 Edit Surface (consolidated)`, `## 438 RNG-Freeze Re-Audit Checklist` sections (appended after DESIGN-01..03; +199 lines, 496 total) ✓
- Task 1 verify PASS: `DESIGN-04`, `scale-invarianc`, `_lootboxEvMultiplierFromScore`, `→75`, `odd-half-point`/`de-minimis` all present ✓
- Task 2 verify PASS: `436 Edit Surface`, `438 RNG-Freeze Re-Audit`/`REAUDIT-02`, `sDGNRS`, `anti-gaming`/`FROZEN at deposit`, `DO-NOT-TOUCH`/`do not convert` all present ✓
- Commits `745dc8d0` + `7f2718c7` exist in git log, each with the `.planning/` file in the commit (git show --stat: 118 + 81 insertions) ✓
- No `contracts/*.sol` modified (`git status --porcelain contracts/` empty); STATE.md / ROADMAP.md untouched ✓
- `435-03-SUMMARY.md` created ✓

---
*Phase: 435-design-design-lock-the-point-unit-streak-path-packing-equiva*
*Completed: 2026-06-19*
