---
phase: 327-tst-repro-same-results-no-arb-ev-regression-proofs
verified: 2026-05-26T12:00:00Z
status: human_needed
score: 5/5
overrides_applied: 0
human_verification:
  - test: "Run the full forge test tree and confirm 632 passed / 42 failed"
    expected: "forge test exits 0 with 632 passing and 42 failing (all 42 named in test/REGRESSION-BASELINE-v48.md buckets A+B+C)"
    why_human: "The verifier cannot execute forge; this is the net-zero-new-regression arithmetic proof that underpins SC-5"
  - test: "Confirm HERO byte-reproduce RED state: run `npx hardhat test test/stat/DegenerettePerNEvExactness.test.js test/stat/DegeneretteBonusEv.test.js`"
    expected: "15 passing / 1 failing — the 1 failure is HERO-04 PASS_ALL with 15/20 constants diverging from the canonical generator (the expected, in-scope pre-landing state)"
    why_human: "The verifier cannot execute hardhat; this is the documented EXPECTED-RED conditional gate whose current state must be confirmed before Phase 328 TERMINAL proceeds"
  - test: "Confirm all five wave-1 forge targets pass independently: run `forge test --match-path test/fuzz/PresaleBoxDrain.t.sol`, `--match-path test/fuzz/RedemptionStethFallback.t.sol`, `--match-path test/fuzz/BurnieTombstone.t.sol`, `--match-path test/fuzz/DegeneretteHeroScore.t.sol`, `--match-path test/fuzz/FarFutureSalvageSwap.t.sol`"
    expected: "3/0, 10/0, 8/0, 6/0, 9/0 (pass/fail) respectively; the FOUNDRY HERO-deferred count is 0 (DegeneretteHeroScore.t.sol green regardless of placeholder values)"
    why_human: "The verifier cannot execute forge; these are the SC-level proofs for PFIX-02/03, RFALL-05+POOL-04, BTOMB-03, HERO-04/06, SWAP-08/09"
---

# Phase 327: TST Verification Report

**Phase Goal:** The IMPL diff is proven correct empirically — the presale-box drain now mops up only variance dust (not ~60% of the pool), the redemption fallback preserves the v47 REDEEM-08 invariants under stETH coverage, the sDGNRS `receive()` relaxation is accounting-safe, the BURNIE tombstone signals only in uncirculated supply, the Degenerette recalibration is byte-identical from `derive_5_tables.py`, and the load-bearing salvage-swap no-arb holds at the jitter band CEILING with solvency preserved — restoring a clean v48.0 regression baseline.
**Verified:** 2026-05-26T12:00:00Z
**Status:** human_needed (automated artifact and wiring verification PASSED 5/5; execution confirmation needs human)
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Presale-drain dust bound proven (PFIX-02/03): over a realistic 50-ETH run the closing sweep is 0 wei, pool ends empty, tier-1==3x-tier-5, clamp holds | VERIFIED | `test/fuzz/PresaleBoxDrain.t.sol` — 396 lines, 3 test functions (`test_PFIX03_TierShapePreserved`, `test_PFIX03_EarlyDgnrsRunEmptiesPoolBeforeClose_ClampHolds`, `test_PFIX02_RealisticRun_ClosingSweepIsDust`); asserts transferFromPool, poolStart/100 dust bound, 43.2% realized branch rate; SUMMARY records measured swept=0, 100% pool drawn through boxes; commits d59790c3 + 837890a4 verified in git log |
| 2 | Redemption-fallback regression holds (RFALL-05) and sDGNRS receive() AF_KING relaxation is accounting-safe (POOL-04) | VERIFIED | `test/fuzz/RedemptionStethFallback.t.sol` — 619 lines, 10 test functions (6 RFALL05 branch-drivers + 4 POOL04); `test/fuzz/handlers/RedemptionHandler.sol` contains `action_toggleStethFallback` + `ghost_stethLegBurns`; `test/invariant/RedemptionAccounting.t.sol` contains `invariant_RFALL05_SolvencyUnderFallback`; each stETH-leg test asserts game ETH < maxIncrement BEFORE and claimable/pool UNCHANGED AFTER; commits 141244c3 + a83b5ca4 verified |
| 3 | BURNIE tombstone is non-circulating, one-shot, GAME-gated, overflow-safe, DGVB-claim-safe (BTOMB-03) | VERIFIED | `test/fuzz/BurnieTombstone.t.sol` — 326 lines, 8 test functions; asserts tombstoneAtGameOver, supplyIncUncirculated, totalSupply; SUMMARY records totalSupply delta=0, vaultMintAllowance+=1e36, one-shot latch, boundary controls at U128_MAX-1e36; commit f0c98063 verified |
| 4 | Degenerette recalibration is byte-identical from derive_5_tables.py (HERO-04 gate + HERO-06 DGAS + no-leak) | VERIFIED (gate is EXPECTED-RED against placeholders per critical_verification_context) | `test/fuzz/DegeneretteHeroScore.t.sol` — 871 lines, 6 test functions (scoring shape, S9 relabel, S8/S9 packing dispatch, DGNRS thresholds, write-batch DGAS, dailyHeroWagers no-leak); `test/stat/DegenerettePerNEvExactness.test.js` contains spawnSync derive_5_tables.py + PASS_ALL gate; `derive_5_tables.py` extended to S∈{0..9}; 15/20 constants produce RED-with-diff against Phase-326 placeholders (EXPECTED); ready-to-apply finals documented in 327-04-SUMMARY; commits 39a706ca + c8e1fcf5 + d4ec2e62 verified |
| 5 | Salvage-swap no-arb holds at the 110% jitter CEILING for all d∈[6,100], solvency preserved, floors/bound/swap-pop enforced (SWAP-08/09) | VERIFIED | `test/fuzz/FarFutureSalvageSwap.t.sol` — 593 lines, 9 test functions (no-arb ceiling sweep, ceiling reachability, base fraction margin, BURNIE-can't-mint-far, solvency, ticket floor, ETH floor, array bound, swap-pop membership); ceiling sweep asserts fractionBps(d)*1.1 < 2100 bps at every d; d6 binding margin +4.50pp; BURNIE purchaseCoin grows zero far queues; commit 1a19fdbf verified |

**Score:** 5/5 truths verified (all automated artifact/wiring levels passed)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `test/fuzz/PresaleBoxDrain.t.sol` | PFIX-02/03 dust bound + tier shape + clamp proofs | VERIFIED | 396 lines; contains `transferFromPool`, `PFIX02`, `PFIX03` patterns; 3 test functions; not a stub |
| `test/fuzz/RedemptionStethFallback.t.sol` | RFALL-05 + POOL-04 scenario proofs | VERIFIED | 619 lines; contains `pullRedemptionReserve`, `steth`, all 6 RFALL05 + 4 POOL04 tests |
| `test/fuzz/handlers/RedemptionHandler.sol` | stETH-fallback lever + leg-attribution ghosts | VERIFIED | Contains `action_toggleStethFallback` + `ghost_stethLegBurns` |
| `test/invariant/RedemptionAccounting.t.sol` | Extended with `invariant_RFALL05_SolvencyUnderFallback` | VERIFIED | Contains `invariant_RFALL05_SolvencyUnderFallback` at line 553 |
| `test/fuzz/BurnieTombstone.t.sol` | BTOMB-03 non-circulating + one-shot + DGVB-claim-safe | VERIFIED | 326 lines; contains `tombstoneAtGameOver`, `supplyIncUncirculated`, `totalSupply`; 8 test functions |
| `test/fuzz/DegeneretteHeroScore.t.sol` | HERO-04/06 scoring + DGAS + no-leak proofs | VERIFIED | 871 lines; contains `dailyHeroWagers`, `S9`, scoring shape tests; 6 test functions |
| `.planning/notes/degenerette-recalibration/derive_5_tables.py` | Canonical 10-bucket S∈{0..9} generator | VERIFIED | Contains `S9_PIN`, `basePayoutEV`, PASS_ALL comment; extended beyond old M=0..8 |
| `test/stat/DegenerettePerNEvExactness.test.js` | PASS_ALL byte-reproduce gate (spawnSync, not hand-typed) | VERIFIED | Contains `spawnSync`, `derive_5_tables`, PASS_ALL gate diff logic |
| `test/stat/DegeneretteBonusEv.test.js` | WWXRP/ETH-bonus EV on regenerated B=6..9 factors | VERIFIED | File exists; modified by plan |
| `test/fuzz/FarFutureSalvageSwap.t.sol` | SWAP-08/09 no-arb ceiling + solvency + floors + swap-pop | VERIFIED | 593 lines; contains `sellFarFutureTickets`, `fractionBps`, `claimablePool`, 9 test functions |
| `test/REGRESSION-BASELINE-v48.md` | Named expected-red enumeration + 326-08 arithmetic + HERO conditional delta | VERIFIED | 254 lines; contains 326-08, 594/42/632, Bucket A/B/C enumeration, HERO conditional delta |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `test/fuzz/PresaleBoxDrain.t.sol` | `contracts/modules/DegenerusGameLootboxModule.sol` | `_presaleBoxDgnrsReward` + closing-sweep `transferFromPool` | VERIFIED | `transferFromPool` pattern present; exercises real on-chain path via `game.buyPresaleBox` → `game.openPresaleBox` |
| `test/fuzz/RedemptionStethFallback.t.sol` | `contracts/DegenerusGame.sol` | `pullRedemptionReserve` ETH-or-stETH branch | VERIFIED | `pullRedemptionReserve` pattern confirmed in file |
| `test/invariant/RedemptionAccounting.t.sol` | `contracts/StakedDegenerusStonk.sol` | solvency invariant `balance+stETH >= claimablePool >= pendingRedemptionEthValue` | VERIFIED | `invariant_RFALL05_SolvencyUnderFallback` wired; `claimablePool` pattern present |
| `test/fuzz/BurnieTombstone.t.sol` | `contracts/BurnieCoin.sol` | `tombstoneAtGameOver()` GAME-gated one-shot flood | VERIFIED | `tombstoneAtGameOver` + `supplyIncUncirculated` + `totalSupply` patterns present |
| `test/stat/DegenerettePerNEvExactness.test.js` | `.planning/notes/degenerette-recalibration/derive_5_tables.py` | `spawnSync` regenerate + diff vs contract source | VERIFIED | `spawnSync` + PASS_ALL gate + `derive_5_tables` pattern confirmed |
| `test/fuzz/DegeneretteHeroScore.t.sol` | `contracts/modules/DegenerusGameDegeneretteModule.sol` | `_score(...)` dispatch + `resolveBets` write-batch + `dailyHeroWagers` | VERIFIED | `dailyHeroWagers`, scoring shape, S9 relabel patterns confirmed in 871-line file |
| `test/fuzz/FarFutureSalvageSwap.t.sol` | `contracts/modules/DegenerusGameMintModule.sol` | `sellFarFutureTickets` + `_quoteFarFutureSwap` jitter ceiling | VERIFIED | `sellFarFutureTickets` + `FarFutureSwap` patterns confirmed in 593-line file |
| `test/REGRESSION-BASELINE-v48.md` | `.planning/phases/326-impl-the-one-batched-contract-diff-all-7-items/326-08-SUMMARY.md` | 594/42 baseline arithmetic | VERIFIED | `326-08` + `594` + `42` patterns confirmed in ledger |

### Data-Flow Trace (Level 4)

These are test files, not UI/data-rendering components. The relevant data-flow question is whether the tests invoke the REAL contract paths (not mocks or replicas).

| Artifact | Key Test Path | Real Contract Invoked | Status |
|----------|---------------|----------------------|--------|
| `PresaleBoxDrain.t.sol` | `game.buyPresaleBox` → `game.openPresaleBox` | VERIFIED — exercises real `_presaleBoxDgnrsReward` + closing-sweep; slot seeding via `vm.store` for state, not logic |
| `RedemptionStethFallback.t.sol` | `sdgnrs.burn` → `game.pullRedemptionReserve` | VERIFIED — real pullRedemptionReserve path; MockStETH for stETH balance control only |
| `BurnieTombstone.t.sol` | `coin.tombstoneAtGameOver()` → `DegenerusVault.burnCoin` | VERIFIED — real contract paths via DeployProtocol harness; not a mock-based test |
| `DegeneretteHeroScore.t.sol` | `game.resolveBets` → `FullTicketResult.matches` | VERIFIED — reaches private `_score` through public resolve path; scoring formula not mocked |
| `FarFutureSalvageSwap.t.sol` | `previewSellFarFutureTickets` / `sellFarFutureTickets` | VERIFIED — shares `_quoteFarFutureSwap` with executing path; valuation cannot drift from actual paid value |

### Behavioral Spot-Checks

Forge is not available for execution in this context. The SUMMARY documents for each plan record passing test results. The human verification section captures execution confirmation as a required human check.

| Behavior | Expected Result | Evidence Source | Status |
|----------|-----------------|-----------------|--------|
| `forge test --match-path test/fuzz/PresaleBoxDrain.t.sol` | 3 passed / 0 failed | 327-01-SUMMARY + self-check | HUMAN NEEDED |
| `forge test --match-path test/fuzz/RedemptionStethFallback.t.sol` | 10 passed / 0 failed | 327-02-SUMMARY + self-check | HUMAN NEEDED |
| `FOUNDRY_PROFILE=deep forge test --match-path test/invariant/RedemptionAccounting.t.sol` | 18 passed / 0 failed | 327-02-SUMMARY + self-check | HUMAN NEEDED |
| `forge test --match-path test/fuzz/BurnieTombstone.t.sol` | 8 passed / 0 failed | 327-03-SUMMARY + self-check | HUMAN NEEDED |
| `forge test --match-path test/fuzz/DegeneretteHeroScore.t.sol` | 6 passed / 0 failed | 327-04-SUMMARY + self-check | HUMAN NEEDED |
| `forge test --match-path test/fuzz/FarFutureSalvageSwap.t.sol` | 9 passed / 0 failed | 327-05-SUMMARY + self-check | HUMAN NEEDED |
| `forge test` (full tree) | 632 passed / 42 failed | 327-06-SUMMARY + test/REGRESSION-BASELINE-v48.md | HUMAN NEEDED |
| HERO byte-reproduce gate (hardhat) | 15 passing / 1 failing (EXPECTED-RED) | 327-04/06-SUMMARY | HUMAN NEEDED |

### Probe Execution

No explicit probe scripts (`scripts/*/tests/probe-*.sh`) were declared in any plan. The behavioral spot-check rows above cover the equivalent verification.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| PFIX-02 | 327-01 | Closing-box sweep is variance dust (≤ poolStart/100) over a realistic 50-ETH run; pool ends ~empty | SATISFIED | `test_PFIX02_RealisticRun_ClosingSweepIsDust` in PresaleBoxDrain.t.sol; SUMMARY records swept=0, 100% pool through boxes |
| PFIX-03 | 327-01 | Tier shape preserved (3×); transferFromPool clamp holds | SATISFIED | `test_PFIX03_TierShapePreserved` + `test_PFIX03_EarlyDgnrsRunEmptiesPoolBeforeClose_ClampHolds`; exact ratio asserted |
| RFALL-05 | 327-02 | v47 REDEEM-08 invariants hold under stETH fallback | SATISFIED | 6 RFALL05 branch-driver tests + `invariant_RFALL05_SolvencyUnderFallback`; each branch explicitly proven |
| POOL-04 | 327-02 | sDGNRS receive() accounting-safe; reserves via address(this).balance, no double-count | SATISFIED | 4 POOL04 tests in RedemptionStethFallback.t.sol; previewBurn delta exactly-once proof documented |
| BTOMB-03 | 327-03 | Tombstone does NOT touch totalSupply(); signal only in uncirculated leg; DGVB claim safe | SATISFIED | 8 tests in BurnieTombstone.t.sol; totalSupply delta=0 asserted; DGVB burnCoin reachability proven |
| HERO-04 | 327-04 | Byte-identical constants from derive_5_tables.py; PASS_ALL gate regenerates not hand-types | SATISFIED (with documented EXPECTED-RED gate) | derive_5_tables.py extended; PASS_ALL gate via spawnSync; RED=15/20 placeholders is expected in-scope outcome per critical_verification_context; finals ready-to-apply in 327-04-SUMMARY |
| HERO-06 | 327-04 | Write-batch DGAS equivalence; dailyHeroWagers no-leak | SATISFIED | `test_HERO06_WriteBatchByteIdentical_DGAS` + `test_HERO06_DailyHeroJackpotUnaffected_NoLeak`; byte-identity and non-vacuity confirmed |
| SWAP-08 | 327-05 | No-arb at jitter band CEILING: 16.5%@d6 < 21% acquisition floor; margin +4.50pp; BURNIE can't mint far | SATISFIED | `test_SWAP08_NoArbAtCeiling_SweepAllDistances` + reachability + BURNIE behavioral probe; d6 binding margin +4.50pp confirmed |
| SWAP-09 | 327-05 | Solvency claimablePool <= balance+stETH; ticket/ETH floors; array bound ≤32; swap-pop membership | SATISFIED | 5 SWAP09 tests; solvency before/after documented (49.828 <= 5000 ETH); all floors + swap-pop enforced |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `test/fuzz/PresaleBoxDrain.t.sol` | ~260 | Tautological clamp assertion (`drew <= poolBefore` by construction of subtraction) | WARNING (WR-01 from 327-REVIEW) | Does not weaken the load-bearing assertions (no-revert + swept <= 1 wei); the no-draw-exceeds-balance property is still proven by pool-balance delta |
| `test/fuzz/FarFutureSalvageSwap.t.sol` | ~424,455,485,495,589 | Bare `vm.expectRevert()` without typed selector | WARNING (WR-02 from 327-REVIEW) | ETH/ticket-floor revert tests could pass on a wrong earlier gate; the specific gate is partially disambiguated by fixture pre-assertions |
| `test/fuzz/RedemptionStethFallback.t.sol` | ~362-364 | Bare `vm.expectRevert()` for fail-closed proof | WARNING (WR-03 from 327-REVIEW) | Fail-closed is the load-bearing proof; a wrong-gate revert would pass without reaching the coverage gate; advisory (reviewer confirmed no blocker) |
| `test/fuzz/handlers/RedemptionHandler.sol` | ~574-579 | `try sdgnrs.burn()` success branch unreachability not directly asserted | WARNING (WR-07 from 327-REVIEW) | Relies on downstream invariant catch; not a direct proof of unreachability |

No `TBD`, `FIXME`, or `XXX` debt markers found in any wave-1 test file. No stub patterns (`return null`, `return []`, empty implementations) found. Zero mainnet `contracts/*.sol` edits across all 10 wave-1 commits — confirmed by `git diff-tree` on each commit.

### Human Verification Required

#### 1. Full forge test tree execution (SC-5 net-zero regression baseline)

**Test:** Run `forge test` (the FULL tree, no `--match-path`) from the repository root.
**Expected:** 632 passed / 42 failed (674 total). Arithmetic: 594 + 38 NEW_PASSING = 632; 42 + 0 net-new = 42. Every failing test name should appear in one of the three named buckets in `test/REGRESSION-BASELINE-v48.md` (Bucket A: VRF/RNG, Bucket B: stale-harness/v48-behavioral, Bucket C: FOUNDRY HERO-deferred = 0).
**Why human:** Forge cannot be executed in the verification environment; this is the single composite proof that the five wave-1 test files introduced zero net-new regression.

#### 2. HERO byte-reproduce gate state (expected-RED confirmation)

**Test:** Run `npx hardhat test test/stat/DegenerettePerNEvExactness.test.js test/stat/DegeneretteBonusEv.test.js`
**Expected:** 15 passing / 1 failing. The 1 failure is `HERO-04 PASS_ALL: 15/20 constants diverge from the canonical generator` — the expected in-scope pre-landing state. The trailing `Cannot find module` line is the known cosmetic mocha teardown quirk, not a test failure.
**Why human:** The HERO byte-reproduce RED state is the critical PENDING USER DECISION documented in project memory — the PASS_ALL gate author (327-04) confirmed the gate is genuine (not weakened) and the REVIEW confirms the same. A human must verify the gate is RED (not accidentally green from a prior landing attempt) before Phase 328 TERMINAL proceeds.

#### 3. Per-plan forge spot checks

**Test:** Run each plan's own forge target: `forge test --match-path test/fuzz/PresaleBoxDrain.t.sol`, `test/fuzz/RedemptionStethFallback.t.sol`, `test/fuzz/BurnieTombstone.t.sol`, `test/fuzz/DegeneretteHeroScore.t.sol`, `test/fuzz/FarFutureSalvageSwap.t.sol`. Also `FOUNDRY_PROFILE=deep forge test --match-path test/invariant/RedemptionAccounting.t.sol`.
**Expected:** 3/0, 10/0, 8/0, 6/0, 9/0, 18/0 (pass/fail) respectively. No wave-1 file should contribute any failing tests.
**Why human:** The verifier confirms files are substantive and wired, but cannot run forge. Each plan's SUMMARY records these pass counts; spot-checking confirms no post-commit regression.

### Gaps Summary

No gaps found. All 5 Success Criteria for Phase 327 are satisfied by substantive, wired test artifacts with 10 verified commits and zero mainnet contract edits. The HERO-04 byte-reproduce gate is in its documented EXPECTED-RED state (the planned, in-scope outcome of a no-contract phase) per the critical_verification_context — this is not a gap.

The 7 WARNINGs in the code review (327-REVIEW) are advisory test-quality items (tautological assertion, bare vm.expectRevert, unreachability not directly asserted) that do not affect correctness of the current subject. The reviewer confirmed 0 BLOCKER-class defects.

---

_Verified: 2026-05-26T12:00:00Z_
_Verifier: Claude (gsd-verifier)_
