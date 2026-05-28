---
phase: 336-tst-equivalence-freeze-safety-divergence-repro-non-widening-
verified: 2026-05-28
status: passed
score: 4/4
overrides_applied: 0
---

# Phase 336: TST — Equivalence + Freeze-Safety + Divergence-Repro + Non-Widening Regression Verification Report

**Phase Goal:** The three contract items are proven behaviorally correct empirically — the whale-pass refactor materializes the same tickets/traits/whale-pass stats with uniform-O(1) opens + a freeze fuzz that the deferred record+claim perturb no current-window entropy; the pass-gated subscription sweeps/evicts/refreshes correctly with NO external pass read on the non-crossing path + OPEN-E re-attest + cancel-tombstone/swap-pop held; the MINTDIV same-traits regression lands; and the full suite is NON-WIDENING vs the v49.0 baseline.
**Verified:** 2026-05-28
**Status:** PASSED
**Verifier:** Claude (orchestrator, inline — Phase 336 executed inline on main per D-CC-02; the D-CC-03 binding gate was USER hand-reviewed + approved).

---

## Goal Achievement

### Observable Truths (the 4 ROADMAP Success Criteria)

| # | Truth (SC) | Status | Evidence |
|---|------------|--------|----------|
| 1 | **TST-01** — whale-pass refactor proven equivalent + uniform-O(1) + freeze-safe | VERIFIED | `336-01` `testFuzz_RngLockDeterminism_ClaimWhalePassDuringLockSafe` GREEN — re-attests `334-WHALE04-FREEZE-PROOF.md` (the deferred record + `claimWhalePass` perturb no current-window entropy) under default + `FOUNDRY_PROFILE=deep`. `336-02` `testClaimWhalePassMaterializesFutureWindowAndAppliesStats` GREEN — box-open + `claimWhalePass()` yields the same materialized tickets/traits/stats as the old inline mint (WHALE-01/02 roundtrip, D-TST01-03). `336-03` `testWhaleOpenerEqualsNonWhaleOpenerGas` GREEN — whale vs non-whale `autoOpen(1)` gas delta 4_636 ≤ 25_000 tolerance → the 331 whale-pass-weighted carve-out RETIRED (WHALE-03, uniform-O(1)). All 3 in the live pass set (§Requirements). |
| 2 | **TST-02** — AfKing pass-gated subs proven (sweep/evict/refresh, no-SLOAD non-crossing, OPEN-E, cancel-tombstone/swap-pop) | VERIFIED | `336-04` `testNonCrossingPathPerformsZeroLazyPassHorizonSloads` GREEN — first-in-tree `vm.expectCall(IGame.lazyPassHorizon.selector, count:0)` oracle proving the non-crossing autoBuy iteration performs ZERO external pass-horizon reads (AFSUB-02, GASOPT-05-class no-regression). The crossing eviction/refresh + OPEN-E + swap-pop behaviors are proven by the 335-migrated AfKing suites (`AfKingSubscription`, `AfKingFundingWaterfall`, `AfKingConcurrency`, `KeeperNonBrick` — the 9 fixture-migration artifacts closed at 335-06) which are GREEN in the TST-HEAD run (none appears in the 40-name live failing set). |
| 3 | **TST-03** — MINTDIV same-traits regression lands | VERIFIED | `336-05` `testMintDivCrossPathEquality_OwedSplitsAcrossSlices` (deterministic anchor at the verbatim `334-MINTDIV01-REACHABILITY-VERDICT.md` scenario owed=300/maxT=292) + `testFuzz_MintDiv_BoundaryOwedCrossPath` (1000-run boundary fuzz, owed∈[293,492]) BOTH GREEN — byte-identical per-player trait derivation across budget-slice trajectories, codifying the MINTDIV-02 `processed += take` fix at `DegenerusGameMintModule.sol:719`. Storage-digest oracle (immune to event-sig drift); non-vacuity guard (`totalTraits == owed`) present. |
| 4 | **TST-04** — full suite NON-WIDENING vs the v49.0 baseline; clean v50.0 baseline ledger recorded | VERIFIED | `336-06` `test/REGRESSION-BASELINE-v50.md` (301 lines). Whole-tree `forge test --json` at the TST HEAD = **674 passed / 40 failed / 17 skipped**. Binding gate (USER-approved ⊆ form): `live failing set − the 42-name §2 union == ∅` — ZERO new regression. `union − live = {invariant_solvencyUnderDegenerette, invariant_ghostAccountingNetPositive}`, both in the UNSEEDED `DegeneretteBet.inv` flaky cluster (documented §4; proven flake not fix — frozen subject + frozen test file). Deltas vs v49 §2: B9/B10 OUT, B14/B15 IN (`42 − 2 + 2 = 42`). |

**Score:** 4/4 truths verified.

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `test/REGRESSION-BASELINE-v50.md` | TST-04 NON-WIDENING ledger (≥200 lines, ⊆ gate, 42-name union, deltas) | VERIFIED | Exists, 301 lines. `live − union == ∅` proven; "BY NAME" ×6; B14/B15 + B9/B10 documented; `42 − 2 + 2 = 42`; `e756a6f3` ×15; 6-arg `TraitsGenerated` absent. |
| `test/fuzz/MintModuleDivergenceAcrossSplit.t.sol` | TST-03 (NEW) | VERIFIED | Exists (509 lines), 2/2 GREEN at TST HEAD. Committed `57a61c68` (wave-5 reconcile) + present in suite. |
| `336-01..06-SUMMARY.md` | one per plan | VERIFIED | All 6 present + committed (`f9400d56`/`1f0ce97a`/`84f65d8f`/`c4a0d3c6`/`57a61c68`/`c876cbc7`). |
| 6 new green proof functions | 336-01..05 | VERIFIED | All 6 present and `Success` in the TST-HEAD `--json` (§Goal Achievement rows 1–3). |

---

### Requirements Coverage

| Requirement | Source Plan | Status | Evidence |
|-------------|-------------|--------|----------|
| TST-01 | 336-01, 336-02, 336-03 | SATISFIED | Freeze-fuzz + claim-equivalence + uniform-O(1) gas all GREEN; the 331 carve-out empirically retired. |
| TST-02 | 336-04 (+ 335-migrated AfKing suites) | SATISFIED | No-SLOAD non-crossing oracle GREEN (`vm.expectCall count:0`); crossing evict/refresh + OPEN-E + swap-pop GREEN in-suite. |
| TST-03 | 336-05 | SATISFIED | Cross-path trait equality (deterministic anchor + 1000-run fuzz) GREEN; MINTDIV-02 codified. |
| TST-04 | 336-06 | SATISFIED | NON-WIDENING ⊆ gate PROVEN (`live − union == ∅`); v50.0 baseline ledger recorded; flaky cluster documented. |

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | — | — | No anti-patterns. |

Debt-marker scan: no TBD/FIXME/XXX in the 336 artifacts. Zero `contracts/*.sol` touched this phase — `git diff e756a6f3 HEAD -- contracts/` is EMPTY (D-TST04-04 holds).

---

### Human Verification

The Phase-336 `autonomous: false` D-CC-03 gate (the binding v50.0 NON-WIDENING headline) was hand-reviewed and APPROVED by the USER (2026-05-28), including the deliberate methodology decision to relax the v49-precedent strict-equality gate to the non-widening ⊆ gate for the unseeded `DegeneretteBet.inv` invariant cluster.

---

### Gaps Summary

No gaps. All 4 ROADMAP Success Criteria VERIFIED; all 4 TST requirements SATISFIED; zero `contracts/*.sol` mutation confirmed.

**One documented finding (not a gap, USER-adjudicated):** the `[invariant]` block in `foundry.toml` has no `seed`, so the `DegeneretteBet.inv` cluster (B12/B14/B15) is non-deterministic (0–3 reds/run). The TST-04 ledger handles this with the ⊆ gate + a documented cross-run table. A candidate test-infra follow-up (add `[invariant] seed` for reproducibility) is recorded in the ledger §4 + the 336-06 SUMMARY, OUT of this phase's markdown-only scope. The load-bearing regression-detection property (no new red outside the baseline) is unaffected.

**Process note (resolved during this run):** wave-5 (336-05) had been executed but its commit never landed (interrupted execution — the test file was untracked, the SUMMARY un-committed). Reconciled at the start of this execute-phase run: the test was re-verified GREEN (2/2, 1000 fuzz runs) and committed atomically (`57a61c68` + tracking `94af7f46`), restoring the clean per-plan history before 336-06 ran.

---

_Verified: 2026-05-28_
_Verifier: Claude (orchestrator, inline)_
