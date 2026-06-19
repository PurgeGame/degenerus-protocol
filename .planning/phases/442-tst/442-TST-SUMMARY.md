---
phase: 442
phase_name: "TST — Prove the Curves, the Ladder, the Inverse & the Reachable Tail"
milestone: v70.0
status: complete
date: 2026-06-19
requirements: [TST-01, TST-02, TST-03]
subject: contracts/ tree 99f2e53f @ ffbd7796 (byte-frozen; ZERO contracts/*.sol change)
---

# Phase 442 TST — Summary

**Test-only. 17/17 targeted green on the frozen subject. No `contracts/*.sol` change.**

The three consumer-curve oracle files were rewritten from the OLD formulas to the new 3-segment curves, and a
Mint↔Afking century-parity test was added to close the one remaining TST-03 gap.

## Coverage vs criteria

### TST-01 — value-curve endpoints + shape ✅
`ConsumerPointEquivalence.t.sol` (10 tests):
- Golden waypoints for all five curves at 12 anchors each (0/60/75/155/235/305/400/500/1000/2000/10000/30000) —
  the multiplier + century assert **directly** against `ActivityCurveLib`; ROI/WWXRP/lootbox-EV against byte-faithful
  local mirrors (the module bodies are `private`, so a pure mirror is the correct test surface).
- `test_CurveInvariants` — MIN at 0, MAX (== old named ceiling) exactly at the cap, flat beyond, dense monotonic
  non-decreasing 0..1200 + tail, ROI strictly < 10000, lootbox 0..60 neutral anchor preserved.
- `test_Continuity_AtKnees` — every knee for every curve (mult 235/500; roi/wwxrp 305/500; century 305/500;
  lootbox 60/400/500) joins exactly (no cliff).
- The decimator `s==0 → 1.0x` no-op is pinned (`decMultBps(0)=10000`).

### TST-02 — bucket ladder + inverse ✅
- `test_BucketLadder_AndFloors` — all 11 threshold crossings (0/10/30/55/85/120/180/250/300/500/1000), just-below
  edges (no off-by-one), the normal floor-5 and century/terminal floor-2 paths, and monotonic non-increasing.
- `test_BucketInverse_RoundTrip` — `minScoreForBucket` returns the exact threshold for every bucket 2..12 and
  round-trips through the forward `decBucket` ladder.

### TST-03 — reachable tail + century parity ✅
- Reachable tail (the pre-clamp-removal fix): `decBucket(1000,2)=2` and each value curve reaches its MAX exactly at
  score 30000 (`test_CurveInvariants` / `test_BucketLadder_AndFloors`).
- **`test_CenturyBonus_MintAfkingParity`** (new) — the century purchase bonus (Mint) and afking bonus (Afking) draw
  from the SAME `ActivityCurveLib.centuryBps` helper, so for identical (baseQty, score) they yield an identical
  bonus; pinned at the anchors (0%/90%/98%/100% of base qty at 0/305/500/30000) and across a dense grid.

## Other oracle files

- `DegeneretteHeroScore.t.sol` (6/6) — the in-test ROI mirror updated to the new 3-segment curve (old MID/HIGH
  9500/9950 knees removed); exercises ROI through the HERO score path.
- `V69ConsumerMigrationFixes.t.sol` (1/1) — pins the v69 affiliate-lootbox-taper migration (100/255 points). The
  affiliate taper is OUT of the reshape scope (unchanged); the suite correctly **dropped its 4 old-shape oracle
  tests** that asserted the pre-reshape curves and would now be false.

## Carry

- Direct module-body call coverage for ROI/WWXRP (currently byte-faithful local mirrors) is blocked without a
  contract change — both are `private`. The mirrors were independently re-derived and confirmed byte-faithful in
  440. A future option is an integration test through the public Degenerette bet-settlement path. Non-blocking.

## Commit

`test(442): reshape oracle rewrites + century Mint/Afking parity (17/17 green)` — test-only, autonomous (no contract
gate). UNPUSHED.
