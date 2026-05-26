---
phase: 327-tst-repro-same-results-no-arb-ev-regression-proofs
plan: 01
subsystem: testing
tags: [foundry, forge, presale-box, dgnrs, f-47-01, dust-bound, tier-shape, transferFromPool-clamp]

# Dependency graph
requires:
  - phase: 326-impl-the-one-batched-contract-diff-all-7-items
    provides: "The applied PFIX diff (divisor 1_000->400, base poolStart/100->poolStart/40) in DegenerusGameLootboxModule.sol _presaleBoxDgnrsReward + the closing-box transferFromPool sweep"
  - phase: 325-spec-design-lock-call-graph-attestation-shared-surface-recon
    provides: "325-ATTEST-PFIX-RFALL.md verified anchors for the PFIX site"
provides:
  - "test/fuzz/PresaleBoxDrain.t.sol — 3 Foundry tests proving the F-47-01 fix empirically (PFIX-02 dust bound + PFIX-03 tier shape + clamp)"
  - "Empirical dust bound: over a realistic 50-ETH run the closing sweep is 0 (vs ~60% of pool under the old /1_000 curve)"
affects: [327-06-regression-gate, terminal-delta-audit, FINDINGS-v48]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Hybrid e2e+seed harness: real game.buyPresaleBox -> game.openPresaleBox drives the private _resolvePresaleBox + closing-sweep, with credit / per-index VRF word / small-pool scenario seeded via vm.store (test scaffolding, zero contract edits)"
    - "Branch forcing without weakening: brute-force a rngWord so keccak(rngWord,'PRESALE_BOX',player,amount)%100 lands a chosen outcome band — controls the distribution while running the REAL on-chain roll"
    - "Pool seeding via the game-only transferFromPool to a sink (no direct array poke) keeps poolBalance() internally consistent"

key-files:
  created:
    - "test/fuzz/PresaleBoxDrain.t.sol"
  modified: []

key-decisions:
  - "Dust bound chosen = poolStart/100 (1%): the v47 /1_000 curve left ~60% of poolStart for the closer, so 1% fails the OLD behavior by ~60x while comfortably covering the FIXED curve's integer-division variance dust (measured swept == 0)"
  - "Realized DGNRS branch-rate tolerance band = 30%..50% of boxes (target ~40%); measured 43.2% (108/250) — a degenerate all-BURNIE run fails the test, not silently passes (T-327-01-FC1)"
  - "Curve-exercised guard = cumulative per-box DGNRS draw >= 90% of poolStart (measured 100% — boxes drained the whole pool, clamped); the OLD /1_000 curve (~2.5x smaller per-box draw) fails this, proving the FIXED curve is genuinely exercised (T-327-01-FC2)"
  - "Tier-shape ratio asserted EXACTLY: tier-1 reward == 3 * tier-5 reward at equal amount + frozen poolStart, plus each absolute reward cross-checked against the (poolStart*tierTenths*amount)/(400*1e18) formula"
  - "Clamp scenario uses 5-ETH boxes so tier-1 per-box draw = 0.375*poolStart, letting a handful of DGNRS opens overshoot a small seeded pool and engage the transferFromPool clamp before the closer"

patterns-established:
  - "F-47-01 dust-bound proof shape: prove BOTH the closing sweep is dust AND the pool was drained through the boxes (two-directional false-confidence guard)"

requirements-completed: [PFIX-02, PFIX-03]

# Metrics
duration: ~10min
completed: 2026-05-26
---

# Phase 327 Plan 01: PresaleBox Drain (F-47-01) Empirical Proof Summary

**Foundry proof that the applied PFIX fix turns the v47 ~60% closing-box DGNRS windfall into 0-wei variance dust: over a realistic 50-ETH presale run (43.2% realized DGNRS branch rate) the boxes drain the entire pool (100% of poolStart) and the closing sweep transfers nothing, while the tier-1==3x-tier-5 ladder and the transferFromPool empty-before-close clamp both hold exactly.**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-05-26T08:29:35Z
- **Completed:** 2026-05-26T08:38:42Z
- **Tasks:** 2
- **Files modified:** 1 (created)

## Accomplishments

- **PFIX-02 dust bound proven empirically.** A 250-box × 0.2-ETH run (exactly the 50-ETH cap) with a PRNG-seeded ~50/40/10 BURNIE/DGNRS/WWXRP mix drives the REAL `_presaleBoxDgnrsReward` curve. Measured: closing-box sweep = **0 wei** (bound: ≤ poolStart/100 = 1e27); residual pool = **0** (ends empty); cumulative per-box DGNRS draw = **100% of poolStart** (≥90% guard). The v47 `/1_000` curve would have left ~60% of poolStart (≈6e28) for the closer — failing both the dust bound and the curve-exercised guard by orders of magnitude.
- **Realized-mix guard against false confidence.** The test asserts the realized DGNRS branch rate is 30%..50% (measured **43.2%**, 108/250). A degenerate all-BURNIE run that never exercises the pool-draining branch fails the test rather than passing it (mitigates T-327-01-FC1).
- **PFIX-03 tier shape preserved exactly.** A tier-1 box (soldBefore < 10 ETH, 3.0×) earns EXACTLY 3× the DGNRS-per-ETH of a tier-5 box (soldBefore ≥ 40 ETH, 1.0×) at equal `amount` + frozen `poolStart`; both absolute rewards cross-checked against the FIXED `(poolStart*tierTenths*amount)/(400*1e18)` formula.
- **PFIX-03 clamp holds.** A run of 5-ETH DGNRS-branch opens drains a small seeded pool to ~0 BEFORE the closing box; the closing open does not revert, sweeps ≤ 1 wei dust, and no per-box draw ever exceeds the live pool balance (transferFromPool returns the clamped amount).
- All three properties run against the applied Phase-326 diff with **zero `contracts/*.sol` (mainnet) modifications**.

## Task Commits

Each task was committed atomically:

1. **Task 1: PFIX-03 tier-shape parity + clamp/empty-before-close proofs** — `d59790c3` (test)
2. **Task 2: PFIX-02 realistic 50-ETH run, closing sweep is variance dust** — `837890a4` (test)

## Files Created/Modified

- `test/fuzz/PresaleBoxDrain.t.sol` — Foundry test suite (3 tests) exercising the real presale-box queue→open path against the applied PFIX diff. Helpers: storage-slot constants (verified via `forge inspect`), `_buyBox` (real `game.buyPresaleBox`, ETH-funded + vm.store credit grant), `_setRngWord` / `_setPoolBalanceTo` seeding, `_wordForDgnrs` / `_wordForBand` band-forcing PRNG, `_expectedReward` formula cross-check.

## Measured Results (recorded for the audit record)

| Property | Bound | Measured |
|----------|-------|----------|
| Closing-box sweep (PFIX-02) | ≤ poolStart/100 (1e27) | **0 wei** |
| Residual pool after close (PFIX-02) | ≤ poolStart/100 | **0** |
| Cumulative per-box DGNRS draw (PFIX-02 guard) | ≥ 90% of poolStart | **100%** (1e29 / 1e29) |
| Realized DGNRS branch rate (PFIX-02 anti-false-confidence) | 30%..50% | **43.2%** (108/250) |
| Tier-1 / tier-5 DGNRS-per-ETH ratio (PFIX-03) | == 3 exactly | **3** |
| Closing draw when pool emptied early (PFIX-03 clamp) | ≤ 1 wei, no revert | **passes** |

poolStart = 1e29 wei (100,000,000,000 DGNRS = 10% of INITIAL_SUPPLY, `PRESALE_BOX_POOL_BPS = 1000`).

## Decisions Made

See `key-decisions` frontmatter. Headline: the dust bound (poolStart/100) and the curve-exercised guard (≥90% of poolStart) form a two-directional false-confidence filter — the OLD `/1_000` curve fails BOTH (too much survives to the closer; too little drawn through the boxes), so a regression to the pre-fix divisor cannot pass this test.

## Deviations from Plan

None — plan executed exactly as written. The plan explicitly authorized the slot-seed helper pattern ("if direct state seeding is needed mirror the slot-seed helper pattern used in the existing redemption/degenerette Foundry tests"); credit / per-index VRF word / the small-pool clamp scenario are seeded via `vm.store` + the game-only `transferFromPool`, while the audit-subject math (`_presaleBoxDgnrsReward` + the closing sweep) runs entirely on-chain via `game.buyPresaleBox` → `game.openPresaleBox`.

## Issues Encountered

- **Clamp test initial failure (resolved during Task 1):** with 1-ETH boxes the tier-1 per-box draw is only 7.5% of poolStart, so 6 opens could not empty a small pool before the closer (pool sat at 55% remaining). Switched the clamp scenario to 5-ETH boxes (per-box draw = 0.375 × poolStart) so a handful of DGNRS opens overshoot and engage the `transferFromPool` clamp before the closing box. Not a contract defect — purely a test-sizing fix. Final run: all 3 tests pass.
- **Enum import:** `sdgnrs` is the concrete `StakedDegenerusStonk` type, which uses its own `Pool` enum (not the interface enum) — imported the concrete contract for the enum reference. Compile-only fix.
- Pre-existing compiler warnings in `DegenerusGameJackpotModule.sol` (variable shadowing + unused parameter) are out of scope (not introduced by this plan); left untouched per the SCOPE BOUNDARY.

## No Contract Defect Surfaced

All asserted properties hold against the applied diff. No property that SHOULD hold failed, so no contract-defect STOP/handoff was required.

## Next Phase Readiness

- PFIX-02 + PFIX-03 are proven; `forge test --match-path test/fuzz/PresaleBoxDrain.t.sol` exits 0 (3 passed).
- Feeds the 327-06 full-suite regression gate (Wave 2) and the v48 TERMINAL delta-audit / FINDINGS attestation for F-47-01.
- No blockers.

## Self-Check: PASSED

- FOUND: `test/fuzz/PresaleBoxDrain.t.sol`
- FOUND: `.planning/phases/327-tst-repro-same-results-no-arb-ev-regression-proofs/327-01-SUMMARY.md`
- FOUND commit: `d59790c3` (Task 1)
- FOUND commit: `837890a4` (Task 2)
- `forge test --match-path test/fuzz/PresaleBoxDrain.t.sol` → 3 passed, 0 failed
- Zero `contracts/*.sol` (mainnet) modifications

---
*Phase: 327-tst-repro-same-results-no-arb-ev-regression-proofs*
*Completed: 2026-05-26*
