---
phase: 437-tst-prove-the-floor-the-streak-path-the-clamp-the-equivalenc
plan: 03
type: execute
status: complete
requirements: [TST-03]
subject_tree: 2eeed00592bbb0bd0789f0e36530e9330f3e2279
subject_commit: c4b09267
provides: "Point-domain vs bps-domain behaviour-equivalence proofs for the three activity-score consumers (Lootbox EV multiplier, Degenerette ROI + WWXRP high ROI, Decimator multiplier + bucket)"
requires: "v69 byte-frozen subject (contracts/ tree 2eeed005 @ c4b09267); DESIGN-04 TABLE A/B + the per-consumer scale-invariance proofs (435-DESIGN-LOCK §D-04.1/.2/.3)"
affects: []
key-files:
  created:
    - test/fuzz/ConsumerPointEquivalence.t.sol
  modified: []
decisions:
  - "Equivalence proven by an in-test point-domain mirror vs an in-test x100 bps-domain ORACLE per consumer, compared cell-by-cell on a leg-spanning whole-point grid + pinned to the design-locked worked anchors — pure-math mirrors (the consumer formulas are pure functions read directly from source), no live on-chain consumer cross-check needed."
  - "The Decimator multiplier naive-divisor failure (naive points/3 -> 10039 != correct 13900) is asserted explicitly so a dropped x100 re-scale fails the test; this is the ONE non-scale-invariant migration."
  - "Equivalence asserted on the clean whole-point grid ONLY (the floored on-chain score is always a clean whole point); the odd-half-point threshold-tip is documented as the accepted D-09 residual and is NOT asserted as exact at a synthetic odd-half-point input."
metrics:
  tasks_completed: 2
  files_changed: 1
  test_functions: 5
  commits: 2
---

# Phase 437 Plan 03: Prove the Consumer Point-vs-bps Behaviour-Equivalence Summary

**One-liner:** A new forge proof (`ConsumerPointEquivalence.t.sol`, 5 tests, 358 lines) shows the whole-point
activity-score consumer math reproduces the pre-change bps-domain outcomes bit-identically for all three consumers —
the Lootbox EV multiplier, the Degenerette ROI (+ WWXRP high ROI), and the Decimator multiplier + bucket — across the
TABLE-A threshold anchors and a leg-spanning whole-point grid, including the ONE non-scale-invariant migration (the
Decimator multiplier re-scale `(points*100)/3`) proven exact and the naive `points/3` proven ~100x wrong — all against
the v69 byte-frozen subject (`c4b09267`), zero contract change.

## What was proven (TST-03)

Each consumer is mirrored twice in-test: a **point-domain mirror** (the shipped formula with the point anchors) and a
**bps-domain ORACLE** (the identical shape with every score-INPUT anchor x100 and the score fed x100, OUTPUT anchors
unchanged). The oracle re-derives the original pre-change formula, so cell-by-cell agreement IS the equivalence proof;
the design-locked worked anchors pin correctness so a wrong migration (converting an OUTPUT anchor, dropping the
Decimator re-scale, mis-converting a CAP) fails.

### Task 1 — Lootbox EV + Degenerette ROI/WWXRP equivalence (commit `66f73301`)
- `test_LootboxEvEquivalence_Grid` — across the grid `{0,30,59,60,61,120,230,399,400,401,1000}` asserts
  `_evPoint(s) == _evBps(s*100)` (low leg / neutral join / high leg / max clamp), then pins the worked anchors
  **30->9500**, **230->12250**, **>=400->14500** (and 401 still clamps), plus 0->9000 (EV_MIN) and 60->10000 (EV_NEUTRAL,
  the legs meet at NEUTRAL). The two legs are interpolation ratios (`score/NEUTRAL`; `excess/maxExcess`) where the
  factor 100 cancels in numerator and denominator before the integer division.
- `test_DegeneretteRoiEquivalence_Grid` — across `{0,30,74,75,76,150,254,255,256,304,305,306,1000}` asserts both
  `_roiPoint(s) == _roiBps(s*100)` AND `_wwxrpPoint(s) == _wwxrpBps(s*100)` (the QUADRATIC low leg + two linear segments
  + the >MAX clamp; WWXRP single-anchor denominator). Pins the worked **30->9320** (the quadratic `100^2` cancellation),
  0->9000 (ROI_MIN), 75->9500 / 255->9950 / 305->9990 (the segment joins + endpoint), the >305 clamp, and the WWXRP
  endpoints 0->9000 / 305->10990.

### Task 2 — Decimator multiplier re-scale + bucket equivalence (commit `5eea3ebf`)
- `test_DecimatorMultiplierRescaleExact_Grid` — across `{0,1,3,30,117,118,234,235,236,1000}` asserts
  `_decMultPoint(s) == _decMultBps(s*100)`, pins the worked **117->13900** (`10000 + 11700/3`), and — the load-bearing
  guard — proves the **naive `10000 + points/3` is WRONG (117 -> 10039 != 13900, ~100x too small)**. The multiplier is
  `bonusBps/3` in the bps domain; a bare integer `/3` is NOT scale-invariant under `/100`, so the point form must
  re-scale the score back up by 100 BEFORE the `/3`. A regression that drops the x100 re-scale fails this assertion.
- `test_DecimatorClampEquivalence` — over-cap scores 236 and 1000 each behave exactly as the 235-point CAP for BOTH the
  multiplier and the bucket, and the clamp binds identically against the bps oracle. A mis-converted CAP (left at 23500
  in the point domain, or converted in the oracle) would let an over-cap score diverge.
- `test_DecimatorBucketScaleInvariance_Grid` — across the same grid asserts `_bucketPoint(s) == _bucketBps(s*100)`,
  confirms `range == 10` is the dimensionless bucket count fed un-converted to BOTH mirrors, and pins the worked
  **118 -> reduction 5 -> bucket 7** in both domains (`(10*118 + 117)/235 == 5` and `(10*11800 + 11750)/23500 == 5`),
  plus the endpoints 0->bucket 12 and 235(cap)->bucket 2.

## Source-of-truth confirmation (read against the frozen `c4b09267`)

All three shipped point-domain formulas were re-read from source and the mirrors match them exactly:
- **Lootbox EV** `_lootboxEvMultiplierFromScore` (`DegenerusGameStorage.sol:1633-1654`): anchors NEUTRAL_POINTS=60
  (`:1553`), MAX_POINTS=400 (`:1555`); output EV_MIN/NEUTRAL/MAX_BPS=9000/10000/14500 (`:1557/:1559/:1561`).
- **Degenerette ROI** `_roiBpsFromScore` (`:1141-1170`, quadratic low coeffs 1000/500 at `:1152-1153`) + `_wwxrpHighValueRoi`
  (`:1178-1190`): anchors MID/HIGH/MAX_POINTS=75/255/305 (`:188/:191/:194`); output ROI 9000/9500/9950/9990
  (`:197-206`), WWXRP 9000/10990 (`:214/:217`).
- **Decimator** (`DegenerusGameDecimatorModule.sol`): multiplier `bonusPoints == 0 ? 10000 : 10000 + (bonusPoints*100)/3`
  (`:801-803`, keep-alive mirror `:913-921`); CAP `TERMINAL_DEC_ACTIVITY_CAP_POINTS=235` (`:772`); bucket
  `_terminalDecBucket` `range = 12-2 = 10`, `reduction = (range*points + 235/2)/235`, `b = 12 - reduction` floored at 2
  (`:1135-1146`), with the `points == 0 -> BUCKET_BASE(12)` short-circuit mirrored.

## Equivalence method (the cancellation that makes /100 free for clean scores)

- **Comparisons invariant:** `score <op> anchor_in <=> s' <op> a'` (both sides exact multiples of 100), so every
  clamp/branch picks the identical leg.
- **Ratios invariant:** `(score - lo)*K / (hi - lo) = (100s' - 100lo')*K / (100hi' - 100lo') = (s' - lo')*K / (hi' - lo')`
  — the factor 100 cancels top and bottom BEFORE the integer division (`K` is OUTPUT anchors, untouched).
- **Quadratic invariant:** `term2 = 500*score^2/MID^2` carries `100^2` in both numerator and denominator -> cancels.
- **Decimator multiplier is the exception:** a bare `bonusBps/3` is not a ratio of two score-domain quantities, so it is
  re-expressed `(points*100)/3` to keep the `/3` over the bps-equivalent magnitude. This is the one place the migration
  is a x100 re-scale, not a /100 of a constant — exercised + pinned by the naive-divisor guard.

## The accepted residual (D-09, documented, NOT asserted as exact)

The floored on-chain score is always a clean whole point (435 §D-04.0), so every grid input here is a whole point and
the point/bps equivalence is exact. The SOLE accepted divergence is the odd-half-point threshold-tip: a pre-floor score
landing on an odd half-point (an odd quest streak) drops its trailing 0.5 pt, which can shift a consumer outcome by at
most one grid cell at one boundary (435 §D-04.3, threat-register T-435-07 mitigated). Per D-09 this is accepted +
documented; the test deliberately makes **no exact-equivalence assertion at a synthetic odd-half-point input** — the
piecewise consumers are continuous at their join points, so a one-cell input shift produces a sub-grid (<=1 ulp) output
shift, typically zero.

## Constants discipline (TABLE A vs TABLE B)

- **Converted (TABLE A, score inputs):** EV NEUTRAL/MAX 60/400; ROI MID/HIGH/MAX 75/255/305; Decimator CAP 235 — each
  used in both its point form and its x100 oracle form.
- **NOT converted (TABLE B, outputs):** EV_MIN/NEUTRAL/MAX_BPS 9000/10000/14500; ROI 9000/9500/9950/9990; WWXRP
  9000/10990; quadratic coeffs 1000/500; BPS_DENOMINATOR 10000; bucket `range=10` (a dimensionless bucket count). Each
  appears identically in both domain mirrors.

## Verification
- `forge test --match-contract ConsumerPointEquivalenceTest -vv` -> **5 passed, 0 failed, 0 skipped**.
- `git status` shows only the new test file (+ a pre-existing untracked `PLAYER-PURCHASE-REWARDS.html`, unrelated and
  untouched). **No `contracts/*.sol`, `STATE.md`, or `ROADMAP.md` modification** (confirmed via `git status --short`
  on those paths — all clean).

## Deviations from Plan
None — plan executed as written. The plan offered an OPTIONAL live on-chain cross-check of `_decMultPoint` /
`_roiPoint` against the contract; the consumer formulas are pure functions read directly from source and the in-test
mirrors + the x100 bps oracle + the design-locked worked anchors are a complete and self-contained equivalence proof,
so the optional live cross-check was not needed (the choice is named in the contract's `@dev` header comment).

One non-substantive encoding fix during authoring: the Unicode `x`/`/` math signs were replaced with ASCII (`x100`,
`/100`) — Solidity rejects non-ASCII inside string literals (an `assertEq` message). Comments and assertion messages
are ASCII throughout.

## TDD Gate Compliance
This is a test-writing plan against an already-frozen, already-correct subject (`c4b09267`). The tests are proofs that
assert the SHIPPED behaviour, so they pass on first run by construction — the fails-without structure (cell-by-cell
point-vs-bps assertions; the pinned design-locked worked anchors; the explicit naive-divisor rejection for the one
non-scale-invariant Decimator migration) is what guarantees a regression in the contract would be caught. No
`contracts/*.sol` change was made or needed (test-only phase). Both tasks committed individually as `test(...)` commits.

## Self-Check: PASSED
- `test/fuzz/ConsumerPointEquivalence.t.sol` — FOUND (358 lines, 5 test functions).
- Commit `66f73301` (Task 1) — FOUND.
- Commit `5eea3ebf` (Task 2) — FOUND.
