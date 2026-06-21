---
phase: 454-tst
subsystem: tests
tags: [degenerette, variant-2, byte-reproduce, invariants, rig-parity, stat, foundry]
requires:
  - phase: 453-impl-the-sole-approval-gate
    provides: "v73 byte-frozen subject (contracts/ tree d6615306) + derive_5_tables.py byte-source"
provides:
  - "v73 byte-reproduce gate (44 Variant-2 constants) — TST-01"
  - "Variant-2 per-(N,heroIsGold) EV exactness + exact EV-equality (Option B) proof"
  - "R2 rigged-distribution neutral baseline + bonus-EV=5% + P(S=9) invariance proofs (INV-03)"
  - "INV-01/02/04 byte-unchanged-vs-pre-v73 proofs (ROI curve, WWXRP RTP curve, S9 pins, whale-pass bracket)"
  - "On-chain Variant-2 score + R2 rig (+2 unlock, never-9) behaviour + 3000-spin rig DISTRIBUTION parity"
  - "full-suite parity (forge + Hardhat stat) — no v73 regression"
affects: [455-reaudit, 456-terminal]
requirements-completed: [TST-01, TST-02, INV-01, INV-02, INV-03, INV-04]
completed: 2026-06-21
---

# Phase 454 — TST Summary

**The v73 Variant-2 recalibration is proven byte-reproducible, exactly EV-equal across hero
placement, neutral-or-just-under per (N,heroIsGold), with the R2 rig matching its analytical
distribution and every held-fixed invariant byte-identical to the pre-v73 source. All Degenerette
unit/stat/invariant gates green; full-suite parity confirms zero v73 regression.**

## What was built (test-only; no `contracts/*.sol` touched)

The shipped 453 stat/Foundry oracles were **v72-era** — they encoded the old `S = A + 2H`
independent-axes model, the old 5-table naming, and "the rig lifts by exactly 0 or 1". They were
RED against v73. Phase 454 rewrote them to Variant-2 + the DEC-01 R2 rig + the DEC-02 Option-B
8-table honest family, and added the held-fixed-invariant proofs.

### 1. `test/stat/DegenerettePerNEvExactness.test.js` — rewritten (23 passing)
- **TST-01 byte-reproduce gate (44 constants):** spawns `derive_5_tables.py`, parses the FINAL
  PASTE-READY block, diffs every one of the 44 v73 constants (8 honest base + 8 honest S8 + 8
  honest factors + 5 S9 pins + 5 rigged base + 5 rigged S8 + 5 rigged factors) against the contract
  source; diff == 0 for all. (The old gate vacuously passed the split tables — its regex missed the
  `_HEROGOLD`/`_HEROCOMMON` infix names; the new gate covers them explicitly.)
- **Honest EV exactness:** an INDEPENDENT exact-BigInt Variant-2 P(S | N, heroIsGold) (numerators
  over 120^4) integrated against the CONTRACT's landed tables — every sub-case basePayoutEV ≤ 100
  and ≥ 99.95 centi-x (matches the generator's printed EVs to 6 dp).
- **EVEQ-01 / Option B:** EV(hero gold) vs EV(hero common) within 0.01 centi-x per N∈{1,2,3}
  (measured max drift 0.000065) — the player-selectable hero-placement edge is closed.
- **R2 rigged EV + P(S=9) invariance (INV-03):** an analytical R2 rigged P_N(S) (the same
  (S,M,e1,e2) +1/+2 fold as the generator) → rigged base-table EV ≤ 100 / ≥ 99.9; rig P(S=9) ==
  honest P(S=9) exactly; honest P(S=9) placement-independent and == the all-8-axes event.

### 2. `test/stat/DegeneretteBonusEv.test.js` — rewritten (14 passing)
- Honest +5% ETH bonus EV == 5.000% ± 1% per (N,heroIsGold) sub-case (split factors); WWXRP R2
  rigged bonus EV == 5.000% ± 1% per N (rigged factors). Measured uplift 5.0000xx% everywhere.

### 3. `test/stat/DegeneretteV73Invariants.test.js` — NEW (7 passing), registered in `test:stat`
- **INV-01:** `_roiBpsFromScore` body + `ROI_*` constants byte-identical to the pre-v73 source
  (`64ec993e^`); anchor 90%→99.9% (9000→9990).
- **INV-02:** `_wwxrpRoi` body + `WWXRP_ROI_*` + `WWXRP_FLOOR_BPS` byte-identical; anchor
  70→115→118→120% (floor 70%).
- **INV-03:** S=9 jackpot pins byte-identical to pre-v73 (and == the known M=8 relabel pins).
- **INV-04:** the S=9 WWXRP whale-pass bracket-award block + `WwxrpJackpotWhalePass` event
  byte-identical. (+ `WWXRP_BONUS_FACTOR_SCALE`/`WWXRP_RIG_SALT` unchanged — rig seed + factor decode
  byte-stable.)

### 4. `test/fuzz/DegeneretteHeroScore.t.sol` — rewritten (8 passing, Foundry)
- Variant-2 score behaviour via a new `_ticketV2(symMask,colMask)` constructor: hero-symbol-alone
  → S=2; full doubles; **a lone color (symbol unmatched) → S=0** (the Variant-2 gating change vs
  v72's 1); lone ordinary symbol → S=1 (below floor); all-symbols-no-colors → S=5; all → S=9.
- S8/S9 packing dispatch + DGNRS S≥7 thresholds re-engineered to Variant-2 scores.
- **R2 rig behaviour:** lift ∈ {0,+1,+2} (the +2 color-unlock is non-vacuously exercised), never
  below honest, never fires at M≥7, and can NEVER lift to S=9 (a rigged S=9 only coincides with an
  honest S=9). ~60% gate among eligible reels.
- **Rig DISTRIBUTION parity (the named 454 deliverable):** runs the REAL `_rigWwxrpResult` over
  3000 live WWXRP spins for a fixed N=0/hero-common ticket and confirms the empirical rigged-score
  histogram matches the generator's analytical `riggedPScore(N=0)` (per-bin ~4σ tolerance + mean
  parity E[S]=1.36088 + zero S=9). A wrong pool / no-+2 / wrong gate would blow the tolerances.

### 5. `test/gas/KeeperResolveBetWorstCaseGas.t.sol` — fixed (4 passing)
- The worst-case-word search used the OLD `_countMatches ≥ 2` win predicate (color-only "matches"
  no longer pay under Variant-2), so the pinned word no longer won every spin (10-spin 6≠10,
  25-spin 12≠21). Replaced the predicate with the Variant-2 score `_scoreV2` (S≥2 = win, heroQuad 0)
  and made the 10-spin assertion data-driven (lootboxFlips == predicted wins, like the 25-spin).
- Collapsed the doomed all-win-then-fallback double pass into a SINGLE combined max-win pass and
  capped the search budget (4000→2000) — the v72 double pass MemoryOOG'd in setUp under Variant-2
  (all-win never breaks early; Solidity never frees per-iteration loop memory). 4/4 green, stable.

## Verification

- **Stat (my rewrites):** DegenerettePerNEvExactness 23/23, DegeneretteBonusEv 14/14,
  DegeneretteV73Invariants 7/7. DegeneretteProducerChi2 3/3 (untouched trait producer, unchanged).
- **Foundry:** DegeneretteHeroScore 8/8 (3×), KeeperResolveBetWorstCaseGas 4/4 (3×),
  DegeneretteFreezeResolution 9/9 (1 skip).
- **Full `forge test`:** 941 passed / 108 skipped after the worst-case fix (the only 2 failures in
  the pre-fix run were those v72-era worst-case oracles, now green).
- **Full `npm run test:stat`:** my 44 Degenerette/invariant assertions green. 6 remaining failures
  are **pre-existing, not v73 regressions** — 5 `SurfaceRegression` stale historical byte-anchors
  (DegenerusGameJackpotModule / DegenerusTraitUtils / EntropyLib `hash1` addition / LootboxModule,
  all from earlier-milestone refactors against v33–v40 baselines) + 1 `PerPullEmptyBucketSkip`
  lootbox MC. NONE reads `DegenerusGameDegeneretteModule.sol` (the only file v73 changed), so their
  result is identical at the v72 baseline. Carried, routed to 455/456.

## Known carries / flake
- **Pre-existing `_deployProtocol` real-clock flake:** with no `block_timestamp` pin in foundry.toml,
  a protocol constructor's day-arithmetic intermittently panics (0x11) at certain wall-clock seconds
  in setUp (harness-wide, NOT v73; e.g. `test_HERO_ScoreFormula` passed 3/3 on retry). Noted for 455.
- The 6 pre-existing stat reds (SurfaceRegression stale anchors + STAT-03) are carried — re-anchoring
  them is out of v73 scope (they predate this milestone).

## Self-Check: PASSED
- 44 byte-reproduce + EV/EVEQ/rig/invariant assertions green; Foundry Variant-2 + rig parity green;
  worst-case gas green; full forge suite green except the documented pre-existing flake.
- No `contracts/*.sol` modified (test-only phase).
