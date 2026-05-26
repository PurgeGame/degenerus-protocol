---
status: partial
phase: 327-tst-repro-same-results-no-arb-ev-regression-proofs
source: [327-VERIFICATION.md]
started: 2026-05-26T00:00:00Z
updated: 2026-05-26T00:00:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Full forge test tree — net-zero new regression
expected: `forge test` (whole tree, NOT --match-path) yields 632 passed / 42 failed; every red is named in `test/REGRESSION-BASELINE-v48.md` Bucket A (VRF/RNG, 8) + Bucket B (stale-harness / v48-behavioral, 34) + Bucket C (FOUNDRY HERO-deferred, 0). Reconciles to the 326-08 baseline: 632 = 594 + 38 new-passing; 42 = 42 + 0 net-new.
result: [pending]

### 2. HERO byte-reproduce gate state (Hardhat)
expected: `npx hardhat test test/stat/DegenerettePerNEvExactness.test.js test/stat/DegeneretteBonusEv.test.js` yields 15 passing / 1 failing — the PASS_ALL gate is RED (15/20 placeholder constants diverge; the 5 S9 relabel constants match), per-N EV and ETH-bonus EV checks green. Confirms the gate is genuine (regenerated from `derive_5_tables.py`, not hand-typed) and the HERO-04 contract-constant landing is still PENDING.
result: [pending]

### 3. Per-plan forge spot-checks
expected: each wave-1 `--match-path` target passes — PresaleBoxDrain 3/0, RedemptionStethFallback 10/0, BurnieTombstone 8/0, DegeneretteHeroScore 6/0, FarFutureSalvageSwap 9/0; and `FOUNDRY_PROFILE=deep` RedemptionAccounting invariants 18/0.
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
