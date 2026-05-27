---
phase: 331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca
plan: 05
subsystem: keeper-router-gas
tags: [gas, keeper-router, contract-gate, split-batch, whale-pass-weighted-budget, GAS-02, GAS-04, GAS-06, user-gated, autonomous-false]

# Dependency graph
requires:
  - phase: 331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca
    plan: 01
    provides: "the gas harness + (corrected) measured marginals — buy ~261,809 (LANDED, not the revert-catch 40,224), typical open ~76-89k, whale-pass open box ~5,346,715"
  - phase: 331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca
    plan: 04
    provides: "the calibration: reward ratios CONFIRMED unchanged; the split-cap recommendation; BOUNTY_ETH_TARGET ceiling"
provides:
  - "the gated contracts/*.sol landing: AfKing DOWORK_BATCH -> BUY_BATCH=50 / OPEN_BATCH=100 split + placeholder-comment strikes; DegenerusGame autoOpen gas-weighted open budget + OPEN_NORMAL_GAS_UNIT; RESOLVE_FLAT_BURNIE comment; batchPurchase rngLock docstring fix"
  - "test mirrors re-pointed to the split constants + the weighted-budget worst-case proofs (clustered whale-pass + structural bound, both <16.7M)"
affects: [332-TST, 333-TERMINAL]
---

# 331-05 — Gated keeper-router gas landing (USER hand-review approved)

## What shipped

The `autonomous: false` contract gate — **ONE batched `contracts/*.sol` diff, USER hand-reviewed and approved** before commit.

**`contracts/AfKing.sol`**
- Split the single `DOWORK_BATCH = 100` into `BUY_BATCH = 50` + `OPEN_BATCH = 100`; routed all 5 references (`_autoBuy` 0-default + docstring, the doWork buy leg, the doWork open leg).
  - `BUY_BATCH = 50`: a LANDED keeper buy is ~262k gas (uniform — buys cannot roll boons), so 50×262k ≈ 13.1M stays under the **16.7M HARD per-tx ceiling**. Buys must never exceed (a reverting full-size batch would brick the daily buy leg).
  - `OPEN_BATCH = 100`: a gas-WEIGHTED budget (see DegenerusGame), ~9M typical.
- Struck the 4 `GAS-331 PLACEHOLDER` comment markers (`ADVANCE_RATIO_NUM`, `BUY_RATIO_NUM/DEN`, `OPEN_KNEE`) — **values byte-identical** (331-04 confirmed the ratios; no behavioral change there).

**`contracts/DegenerusGame.sol`**
- `autoOpen` is now a **gas-weighted budget** (the USER-directed whale-pass-aware cap). Each opened box's measured gas (`gasleft()` delta) is converted to weighted units of the new `OPEN_NORMAL_GAS_UNIT = 90_000` constant (ceil, min 1): a typical box weighs 1, a whale-pass box (~5.4M, the 100-iter `_activateWhalePass` boon) weighs ≈ 60. The walk stops once accumulated weight reaches `maxCount`. The **real `opened` count** (returned, drives the AfKing `OPEN_KNEE` reward pro-rate) is tracked separately from the weighted budget.
  - Bound: a box's weight is only known AFTER it opens, so at most ONE whale-pass box overshoots the budget → worst-case leg gas ≤ `(maxCount−1)×90k + one whale-pass` ≈ 8.9M + 5.4M ≈ **14.3M < 16.7M for ANY whale-pass mix**. Prevents the open-leg gas-revert from whale-pass clustering (the loop has no per-box isolation).
- `RESOLVE_FLAT_BURNIE` placeholder comment struck (value `1e18` unchanged).
- `batchPurchase` docstring corrected: it claimed an rngLock entry-check that does not (and should not) exist — keeper buys are freeze-safe by construction (commit-before-reveal); the orphan hazard is defended on the OPEN side (autoOpen rngLock no-op + word-gate; openLootBox reverts).

**Tests** (`test/fuzz/AfKingSubscription.t.sol`, `test/fuzz/CrankFaucetResistance.t.sol`, `test/gas/CrankOpenBoxWorstCaseGas.t.sol`, `test/gas/RouterWorstCaseGas.t.sol`)
- DOWORK_BATCH → split-constant mirrors; `autoOpen(k)` → `autoOpen(k*64)` weighted-budget headroom in the marginal/round-trip measurements (so all boxes open for those gas brackets).
- New proofs: `testWeightedOpenBudgetCapsClusteredWhalePassBatchUnderCeiling` (clustered whale-pass batch stays ≤16.7M, ≥1 whale-pass fired = non-vacuous) + `testWeightedOpenBudgetStructuralBoundUnderCeiling` (14.26M) + `testBuyBatchFiftyLandsUnderHardCeiling` (12.19M).

## Deviations from the planned 331-05 (major — USER-directed)

The plan's original 331-05 was Seed 1 (affiliate-write coalescing) + Seed 2 (new `batchPurchaseForKeeper` pre-validation) + peg comment-strike. ALL of that was reworked mid-execute on USER direction:
- **Seed 1 DROPPED** — sub-1% win (warm-SSTORE pricing) needing cross-contract plumbing (the abandoned exploratory diff sprawled to 7 files / 308 lines; preserved in `stash@{0}`).
- **Seed 2 DROPPED** — and the lighter "param-not-value" alternative I proposed was **disproven** (delegatecall preserves `msg.value`; the mint module reads it → dropping `{value:}` reverts every buy). **Full try/catch removal = NO-GO** (the `DegenerusGame.sol:1096 storedDay != lbDay` day-rollover revert is not cheaply pre-validatable; one miss bricks the batch). The `try/catch` + `{value:}` both STAY. Security floor preserved.
- **331-01 buy harness was INVALID** — asserted AfKing's `lastAutoBoughtDay` stamp (set even on per-player revert) → measured the revert-catch path (~40k); the real LANDED buy is ~262k. Corrected; the split-cap is therefore a *correctness* fix (100 buys ≈ 26M > 16.7M), not just an optimization.
- **Whale-pass-aware weighted open budget ADDED** (USER idea) — the substantive new mechanism, in place of the dropped Seeds.
- Gas ceiling 30M → **16.7M** (USER); ~9M average target.

## Verification

- `forge build` green (0 errors).
- `RouterWorstCaseGas.t.sol` **11/11 PASS**: buy@50 = 12,192,403; weighted structural worst = 14,256,715; clustered whale-pass (2 fired, capped) = 11,853,000; typical open batch = 6,177,400 — all < the 16,700,000 ceiling.
- Full-suite regression: **identical failing-test set vs baseline** (exact-list `comm` diff: 55 = 55, zero new, zero masked). The 58 raw failures are the documented baseline (v48 reward-rehoming deferred to 332, VRF/stall, slot-drift panics, the flagged `testBatchPurchaseRngLockedRejectsWholeBatchAtEntry`).
- USER hand-review of the full `contracts/` diff: approved.

## Notes / follow-ups for 332-TST
- `testBatchPurchaseRngLockedRejectsWholeBatchAtEntry` asserts a whole-batch rngLock abort that the contract correctly does NOT do (buys-during-lock are intended). Correct/retire the TEST, not the code.
- Buy is now the most expensive leg yet carries the flat 1.5x ratio; a single `BOUNTY_ETH_TARGET` cannot be both faucet-safe (≤8.78e12) and buy-profitable (~170e12) — keeper buys run at a loss by design (protocol-funded). Deploy-param economic choice, surfaced not gated.

## Self-Check: PASSED
