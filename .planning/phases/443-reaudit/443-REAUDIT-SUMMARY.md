---
phase: 443
phase_name: "REAUDIT — Re-Run the v68/v69 Detection Nets on the Reset Subject"
milestone: v70.0
status: complete
date: 2026-06-19
requirements: [REAUDIT-01, REAUDIT-02, REAUDIT-03]
subject: contracts/ tree 99f2e53f @ ffbd7796 (byte-frozen)
---

# Phase 443 REAUDIT — Summary

**The v68/v69 detection nets re-run on the new v70 subject — all green. No `contracts/*.sol` change.**

## REAUDIT-01 — storage-layout golden ✅ (NO slot move)

`scripts/layout/storage_layout_oracle.sh --check` → **"STORAGE LAYOUT ORACLE: all goldens match ✓"** +
**"delegatecall shared-slot consistency (modules vs Game): OK"**.

All 24 contract goldens (DegenerusGame + the 13 delegatecall modules + the standalone state contracts) match the
v69 baseline with ZERO slot movement — exactly the expected result: the reshape is read-side (it changes pure
reward-curve formulas, not storage), and the new `ActivityCurveLib` is storageless (`internal pure` + `internal
constant` only, 57-byte inlined stub). No layout delta to investigate; the slot-hardcoded harnesses
(`RngFreezeAndRemovalProofs` slots 34/35/38/39, the V56 cluster) remain valid and pass unchanged.

## REAUDIT-02 — RNG-freeze proof re-attested ✅

Every freeze/determinism proof suite ran green on the new subject (inside the 0-failed full-suite total):
`RngFreezeAndRemovalProofs` (15), `RngLockDeterminism` (22), `V55FreezeDeterminism` (7), `PrizePoolFreeze` (9),
`DegeneretteFreezeResolution` (10), `V61RngFreezeIntact` (6), plus the `RngWindowFreeze` / `VRFPathInvariants` /
`RngIndexDrainOrdering` invariant suites.

**Attestation:** every activity-score-reading RNG/VRF consumer is still frozen-at-commitment under the new curves.
The reshape changes only the *pure function* applied to the activity score; it introduces NO new live re-read inside
any RNG window:
- **Lootbox EV** reads the score frozen into the packed box word (`LB_SCORE`, uint16) at deposit time, then applies
  `_lootboxEvMultiplierFromScore` — formula change only; the snapshot-at-deposit freeze is unchanged.
- **Degenerette ROI / WWXRP** read the score packed into the bet at placement time, then apply
  `_roiBpsFromScore` / `_wwxrpHighValueRoi` at settlement — same frozen input, new formula.
- **Decimator** reads the score at burn time and, at claim, re-derives the sealed score via
  `minScoreForBucket(bucket)` (the exact band-floor inverse) — the seal point is unchanged.

No freeze-proof ledger anchor moved (the storage layout is identical), so no anchor update was needed.

## REAUDIT-03 — regression + invariant nets green; mutation/Halmos carried ✅

- **Full forge suite: 935 passed / 0 failed / 108 skipped** across 134 suites (the 108 skips are the pre-existing
  v56 vm.skip set, unchanged from the v69 close's 108). +1 vs the v69 close's 934 = the new century-parity test.
- **18 invariant suites green** — solvency (`EthSolvency`, `PoolConservation`, `V61SolvencyAfpay`, `VaultShareMath`),
  freeze-window (`RngWindowFreeze`), VRF-path (`VRFPathInvariants`), FSM/composition/multi-level, redemption
  accounting, degenerette-bet, whale-sybil — all pass on the new subject.
- **EIP-170** re-confirmed on the frozen subject: DegenerusGame 20,388 / 4,188 headroom (= v69 baseline), FLIP
  7,668 / 16,908; every changed module under the ceiling.
- **Mutation + Halmos symbolic: documented CARRY** (consistent with the v63/v64/v67/v68/v69 closes). The full
  gambit mutation campaign and a Halmos symbolic pass on the new `ActivityCurveLib` are the milestone's long-pole
  (each mutant requires a fresh via_ir recompile — impractical inline; CI/detached). **Triage rationale for the
  carry:** the reshaped surface is pure integer arithmetic with near-complete concrete oracle coverage — every
  curve waypoint is pinned to an exact golden, every knee's continuity is asserted, monotonicity is scanned densely,
  and the bucket inverse is round-tripped against the forward ladder. A constant or operator mutation anywhere in
  `ActivityCurveLib` or the inline curves breaks a golden waypoint, so the expected kill-rate on the changed surface
  is high; the carry is the formal campaign, not a coverage gap in behavior.

## Verdict

The reset subject passes every re-run detection net with zero unexpected drift. Layout unchanged, RNG-freeze intact,
full regression + invariant nets green. Ready for TERMINAL (444) closure. Test/tooling work commits autonomously;
UNPUSHED.
