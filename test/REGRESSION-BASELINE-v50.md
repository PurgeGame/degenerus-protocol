# Regression Baseline — v50.0 (NON-WIDENING clean-baseline gate ledger)

**Plan:** 336-06 (Wave-6 full-suite NON-WIDENING regression gate).
**Subject:** the v50.0 audit subject — the BATCH-02 USER-approved diff
`e756a6f3677f3142aafba7f044e106cd416d0d3b` (5 contracts + 8 tests, 1239 ins / 1311 del, net −72
lines), landing **WHALE-01..03** (O(1) box-open whale-pass claim + `claimWhalePass` materialization +
the 331 gas-weighted `autoOpen` carve-out retired) + **AFSUB-01..05** (pass-gated subs,
`validThroughLevel` + refresh-or-evict at the crossing, OPEN-E preserved, SUB-07 cancel-tombstone +
the v49 swap-pop invariant) + **MINTDIV-02** (`processed += take` one-liner advance alignment).
**Zero `contracts/*.sol` edits were applied by this phase** (TST is a `test/` + `.planning/` phase;
the audit subject stays byte-frozen at `e756a6f3` — `git diff e756a6f3 HEAD -- contracts/` is EMPTY).
**Baseline carried forward against:** `test/REGRESSION-BASELINE-v49.md §2` — the authoritative 42-red
union BY NAME (the v49.0 clean baseline at the closure HEAD `b0511ca2` /
`MILESTONE_V49_AT_HEAD_b0511ca29130c36cbe9bfb44e282c7379f9778c9`).

This is a plain-markdown ledger — NOT a `.sol` file, NOT a runnable test. It RECORDS the authoritative
whole-tree `forge test` run AT THE TST HEAD (after all six 336 proof waves landed), the 42-name
carried-forward union BY NAME, the v50 deltas vs the v49 §2 union (B9 + B10 OUT, B14 + B15 IN), the new
green proof files, and the net-zero-new-regression proof.

> **THE BINDING HEADLINE (by NAME, never a bare count):**
> at the v50 TST HEAD, every `forge test` failing test **∈** the 42-name v50.0 §2 enumerated union
> **BY NAME** — `live failing set − the §2 union == ∅` — **net-zero new regression**. **40 of the 42
> union names were observed red this run**; the 2 union names NOT red this run
> (`invariant_solvencyUnderDegenerette`, `invariant_ghostAccountingNetPositive`) are both members of
> the **UNSEEDED `DegeneretteBet.inv` invariant cluster** that fails a fuzz-campaign-dependent 0–3
> subset per run (v49: 1, 335-IMPL: 3, this TST run: 1 — see §4). Because that cluster is
> non-deterministic, the v49-precedent strict-equality gate
> (`live failing set == the 42 v50.0 §2 enumerated union`) is **RELAXED to the non-widening SUBSET gate**
> (`live failing set ⊆ the §2 union`, i.e. `live − union == ∅`), which is the load-bearing property: it
> proves the v50 changes introduced **no failing test outside the known baseline**. The opposite
> direction (`union − live`) is non-empty ONLY by the documented flaky-cluster narrowing, never by a new
> red. This restores a clean v50.0 regression baseline against the FROZEN IMPL subject `e756a6f3`.

---

## 1. The v50 TST-HEAD arithmetic + the reconciliation

The six 336 proof waves (336-01..05 green proofs + 336-06 this ledger) ADD only PASSING tests; they
mutate **no** `contracts/*.sol` (the subject is frozen at `e756a6f3`). The IMPL HEAD `e756a6f3` ran
666 passed / 42 failed / 17 skipped (335-LOCAL-VERIFICATION §2). The v50 TST HEAD adds the 6 new green
proofs; the failing side moved from 42 → 40 ONLY because the unseeded `DegeneretteBet.inv` cluster
caught 1 (not 3) of its counterexample family this run (§4).

| Quantity | v50 IMPL HEAD `e756a6f3` | TST-HEAD delta (336-01..05) | v50 TST HEAD (this run) |
|----------|--------------------------|------------------------------|-------------------------|
| `forge test` passed | 666 | **+6** new green proofs **+2** flaky-cluster green-this-run (B12, B15) | **674** |
| `forge test` failed | 42 | **−2** flaky-cluster green-this-run (B12, B15) | **40** |
| `forge test` skipped | 17 | +0 | **17** |
| total run (passed+failed+skipped) | 725 | **+6** (new test functions) | **731** |

Reconciliation:
- **`failed == 40`**, and every one of the 40 ∈ the §2 42-name union BY NAME (`live − union == ∅`,
  proven §6). The 2 union names not red this run are `invariant_solvencyUnderDegenerette` (B12) and
  `invariant_ghostAccountingNetPositive` (B15) — both in the unseeded `DegeneretteBet.inv` flaky cluster
  (§4); `invariant_noEthCreation` (B14) was caught this run. No name outside the union failed.
- **`passed == 674` == 666 + 6 + 2.** The +6 are the new green proofs from 336-01..05 (§5); the +2 are
  B12 + B15 passing this run (the same cluster flake that drops the failing side to 40). The +6 and +2
  are arithmetically independent — the 6 new proofs are deterministic (the `[fuzz]` profile is seeded,
  §4), the 2 flaky-flips are the unseeded-invariant variance.
- **17 `skipped`** carried forward unchanged (the `RngLockDeterminism` `vm.skip` blocks — not reds, not
  greens; orthogonal to the gate).

> **NOTE on the gate shape vs the v49 ledger.** The v49 §1 asserted strict equality
> (`live failing set == the 42 v48 names`) because that run observed exactly its enumerated union. v50's
> `DegeneretteBet.inv` cluster is **unseeded** (§4) and so its red-subset is non-deterministic — strict
> equality is the wrong gate for a non-deterministic family. The binding v50 invariant is the
> non-widening SUBSET direction (`live − union == ∅`: no NEW red), which is identical in spirit to v49's
> "failing == the baseline names" — only the flaky-cluster's `union − live` slack is documented rather
> than asserted away. Per the USER hand-review at the 336-06 gate (D-CC-03), this ⊆-gate baseline was
> approved over (a) seeding `[invariant]` + re-running, and (b) cherry-picking a re-run that hit 42 — the
> latter explicitly rejected as a passing-ledger-over-reality anti-pattern.

---

## 2. The carried-forward 42-name union for `forge test` (enumerated BY NAME — the v50.0 ceiling)

Every red below is the v50.0 baseline ceiling: the v49 §2 union with the v50 deltas applied (§3). The
v50 source diff (`e756a6f3`) flipped NONE of these green as a *regression*; the only membership changes
vs v49 §2 are the attributable deltas in §3. **Any forge red NOT in this union is a NEW regression →
STOP. No such red appeared** (§6, `live − union == ∅` verified empirically this run). The **This-run**
column records the observed status of each name in the authoritative whole-tree run (40 RED / 2
flaky-GREEN).

The 42 names classify into the same three named buckets as v49 (each red lands in exactly one bucket):

### Bucket A — VRF / RNG-window baseline reds (out of v50 scope; v50 touched no VRF/Advance RNG-window code)

| # | Suite (file) | Failing test | This-run |
|---|--------------|--------------|----------|
| A1 | `test/fuzz/invariant/VRFPathInvariants.inv.t.sol` | `invariant_allGapDaysBackfilled` | RED |
| A2 | `test/fuzz/invariant/VRFPathInvariants.inv.t.sol` | `invariant_rngUnlockedAfterSwap` | RED |
| A3 | `test/fuzz/invariant/VRFPathInvariants.inv.t.sol` | `invariant_stallRecoveryValid` | RED |
| A4 | `test/fuzz/VRFCore.t.sol` | `test_midDayRequest_doesNotBlockDaily` | RED |
| A5 | `test/fuzz/VRFLifecycle.t.sol` | `test_vrfLifecycle_levelAdvancement` | RED |
| A6 | `test/fuzz/VRFPathCoverage.t.sol` | `test_gapBackfillWithMidDayPending_fuzz` | RED |
| A7 | `test/fuzz/RngLockDeterminism.t.sol` | `testFuzz_RngLockDeterminism_StakedStonkRedemption` (`vm.assume` rejected too many inputs) | RED |
| A8 | `test/fuzz/RngIndexDrainBinding.t.sol` | `testBindingConsistencyDailyDrain` | RED |

> **A7 carried forward UNCHANGED (Pitfall 2):** 336-01 EXTENDED `RngLockDeterminism.t.sol` with the NEW
> `testFuzz_RngLockDeterminism_ClaimWhalePassDuringLockSafe` proof but did NOT touch A7's `vm.assume`
> filters. A7 is the same documented fuzzer-exhaustion red as in v49.

### Bucket B — stale-harness / v48-behavioral baseline reds (34; B9 + B10 OUT vs v49, NEW B14 + B15 IN — see §3)

| # | Suite (file) | Failing test(s) | Count | This-run |
|---|--------------|-----------------|-------|----------|
| B1 | `test/fuzz/TicketRouting.t.sol` | `testBoundaryLevel5RoutesToWriteKey`, `testBoundaryLevel6RoutesToFFKey`, `testFarFutureRoutesToFFKey`, `testNearFutureRoutesToWriteKey`, `testRangeRoutingSplitsCorrectly`, `testRngGuardAllowsWithBypass`, `testRngGuardIgnoresNearFuture`, `testRngGuardRangeRevertsOnFirstFFLevel`, `testRngGuardRevertsOnFFKey`, `testRngGuardScaledRevertsOnFFKey`, `testScaledFarFutureRoutesToFFKey`, `testScaledNearFutureRoutesToWriteKey` | 12 | RED |
| B2 | `test/fuzz/QueueDoubleBuffer.t.sol` (MidDaySwapTest) | `testMidDayProcessesReadSlotFirst`, `testMidDayRevertsNotTimeYet`, `testMidDaySwapAtThreshold`, `testMidDaySwapJackpotPhase` | 4 | RED |
| B3 | `test/fuzz/QueueDoubleBuffer.t.sol` (QueueDoubleBufferTest) | `testQueueAfterSwapUsesNewWriteKey`, `testQueueTicketRangeUsesWriteKey`, `testQueueTicketsScaledUsesWriteKey`, `testQueueTicketsUsesWriteKey`, `testWriteReadIsolation` | 5 | RED |
| B4 | `test/fuzz/TicketEdgeCases.t.sol` | `testEdge01NoDoubleCount_FFThenWriteKey`, `testEdge02RoutingPreventsNewFFDeposits` | 2 | RED |
| B5 | `test/fuzz/PrizePoolFreeze.t.sol` | `testFreezeUnfreezeRoundTrip`, `testMultiDayAccumulatorPersistence` | 2 | RED |
| B6 | `test/fuzz/TicketLifecycle.t.sol` | `testLootboxNearRollTicketsProcessed` | 1 | RED |
| B7 | `test/fuzz/GameOverPathIsolation.t.sol` | `testGameOverDrainsQueuedTickets` | 1 | RED |
| B8 | `test/fuzz/LootboxBoonCoexistence.t.sol` | `test_lootboxBoonAppliedDespiteExistingCoinflipBoon`, `test_parametricAutoBuy_crossCategoryBoonFromLootbox` | 2 | RED |
| ~~B9~~ | ~~`test/fuzz/AfKingSubscription.t.sol`~~ | ~~`testRenewalExactlyAtCostFullBurn`~~ | ~~1~~ | **OUT — DELETED at 335-05 (premise retired by AFSUB-01); see §3** |
| ~~B10~~ | ~~`test/fuzz/AfKingFundingWaterfall.t.sol`~~ | ~~`testFundingSourceVaultDoesNotInheritExemption`~~ | ~~1~~ | **OUT — flipped GREEN at v50 IMPL (BurnieChargeFailed path structurally gone under AFSUB-01); see §3** |
| B11 | `test/fuzz/CoverageGap222.t.sol` | `test_gap_gnrus_propose_vote_paths` | 1 | RED |
| B12 | `test/fuzz/invariant/DegeneretteBet.inv.t.sol` | `invariant_solvencyUnderDegenerette` | 1 | **flaky-GREEN this run** (unseeded cluster, §4) |
| B13 | `test/fuzz/DegeneretteFreezeResolution.t.sol` | `testDgnrsAwardStaysPerSpin` | 1 | RED |
| **B14** | `test/fuzz/invariant/DegeneretteBet.inv.t.sol` | `invariant_noEthCreation` | 1 | **RED** (NEW vs v49 — §3) |
| **B15** | `test/fuzz/invariant/DegeneretteBet.inv.t.sol` | `invariant_ghostAccountingNetPositive` | 1 | **flaky-GREEN this run** (NEW vs v49 — §3) |

Bucket B total (union ceiling): 12 + 4 + 5 + 2 + 2 + 1 + 1 + 2 + 0 (~~B9~~) + 0 (~~B10~~) + 1 + 1 + 1 +
1 (B14) + 1 (B15) = **34**.

### Bucket C — HERO-deferred reds (FOUNDRY side)

Unchanged from v49 §2 Bucket C — the HERO byte-reproduce gate lives entirely in the Hardhat stat tree.
**FOUNDRY-side HERO-deferred red count = 0.**

| # | Suite (file) | Failing test |
|---|--------------|--------------|
| — | (none) | (none) |

### Union totals

Bucket A (8) + Bucket B (34) + Bucket C (0) = **42** (the v50.0 ceiling). ✓
**This-run observed RED = 40** (42 − B12 − B15, both flaky-GREEN this run); **`live − union == ∅`** (§6).

---

## 3. NEW vs v49 §2 — the v50 deltas (B9 + B10 OUT, B14 + B15 IN), with provenance

The v50 union differs from the v49 §2 union by exactly four attributable membership changes — net zero:

```
v50 §2 = {v49 §2 42-name union}
        − {B9  testRenewalExactlyAtCostFullBurn}               [DELETED at 335-05]
        − {B10 testFundingSourceVaultDoesNotInheritExemption}  [GREEN at v50 IMPL]
        + {B14 invariant_noEthCreation}                         [NEW co-failure, WHALE-01 widening]
        + {B15 invariant_ghostAccountingNetPositive}            [NEW co-failure, WHALE-01 widening]
= 42 − 2 + 2 = 42 ✓   (Pitfall 4 mitigation — explicit delta math)
```

| Delta | Disposition | Provenance |
|-------|-------------|------------|
| **B9 OUT** — `AfKingSubscription.testRenewalExactlyAtCostFullBurn` | DELETED in Plan 335-05; the v49 pass-OR-pay day-31 PAID-renewal premise was structurally retired by AFSUB-01 (the BURNIE subscription window removal). The replacement test asserts the new pass-eviction-OR-refresh shape. Deletion-with-re-author per D-IMPL-02. | 335-LOCAL-VERIFICATION §2 + 335-07 BATCH-02 (`e756a6f3`) |
| **B10 OUT** — `AfKingFundingWaterfall.testFundingSourceVaultDoesNotInheritExemption` | The test is still present (the LANDMINE-A exemption-spoof assertion preserved) but now GREEN at v50 IMPL: under AFSUB-01 the `BurnieChargeFailed` error and the BURNIE-shortfall path are deleted entirely, so the test reaches the LANDMINE-A assertion cleanly. Incidental contract-side cleanup. | 335-LOCAL-VERIFICATION §2 ("Incidental fixes") |
| **B14 IN** — `DegeneretteBet.inv.t.sol::invariant_noEthCreation` | NEW co-failure of the B12 family (`assertGe(totalIn, totalOut)`, weaker solvency form). The WHALE-01 box-open `whalePassClaims += grant` deferred-claim accounting shifts the ETH-tracking ghost variables relative to v49's immediate-apply path, surfacing the same ~22 wei drift B12 already enumerates. LEGITIMATE-v50-change widening per D-IMPL-03 row 3 (NOT a fixture-migration artifact — the test file is byte-identical to `b0511ca2`). | 335-LOCAL-VERIFICATION §2 ("Incidental NEW reds") |
| **B15 IN** — `DegeneretteBet.inv.t.sol::invariant_ghostAccountingNetPositive` | Sibling of B14 (same `totalIn vs totalOut` check, no `betsResolved == 0` skip). Same WHALE-01 deferred-claim widening source, same shrunken counterexample, same ~22 wei delta. | 335-LOCAL-VERIFICATION §2 ("Incidental NEW reds") |

The three `DegeneretteBet.inv` rows (B12 + B14 + B15) are one tightly-coupled counterexample family
(`totalIn (ghost_totalDeposited + ghost_totalEthWagered) vs totalOut (ghost_totalClaimed +
ghost_totalEthPayout)`, ~22 wei drift, e.g. `12_135_689_514_005_900_853 vs 12_157_781_233_599_270_312`).
They share a root sequence — which is precisely why their red-membership co-varies run-to-run (§4).

---

## 4. The unseeded `DegeneretteBet.inv` invariant cluster — non-determinism analysis (the ⊆-gate rationale)

**Root cause (proven, not assumed).** `foundry.toml` seeds the `[fuzz]` profile (`seed = "0xdeadbeef"`,
`runs = 1000`) — so all unit-fuzz proofs are deterministic — but the **`[invariant]` block has NO
`seed`** (`runs = 256`, `depth = 128`, `fail_on_revert = false`). Invariant campaigns therefore explore
a different random call-sequence space each run, and a rare counterexample (here the ~22 wei
`DegeneretteBet` drift) is caught only when the campaign happens to reach it.

**Evidence the membership is fuzz-variance, not a regression or a fix:**
- `test/fuzz/invariant/DegeneretteBet.inv.t.sol` is **byte-frozen since the IMPL HEAD**
  (`git diff e756a6f3 HEAD -- test/fuzz/invariant/DegeneretteBet.inv.t.sol` is EMPTY).
- The v50 contract subject is **frozen** (`git diff e756a6f3 HEAD -- contracts/` is EMPTY).
- The five test files 336 touched (`AfKingSubscription`, `MintModuleDivergenceAcrossSplit`,
  `RngFreezeAndRemovalProofs`, `RngLockDeterminism`, `KeeperOpenBoxWorstCaseGas`) do **not** include any
  invariant suite.
- Identical contracts + identical invariant test file + a different red-subset = non-determinism by
  definition.

**Observed red-subset of the {B12, B14, B15} cluster across runs:**

| Run | Context | Cluster reds caught | Which |
|-----|---------|---------------------|-------|
| v49 closure | `b0511ca2` | 1 | `invariant_solvencyUnderDegenerette` (B12 only; B14/B15 green pre-WHALE-01) |
| v50 IMPL HEAD | `e756a6f3` (335-LOCAL-VERIFICATION) | 3 | B12 + B14 + B15 |
| **v50 TST HEAD** | **this run** | **1** | **`invariant_noEthCreation` (B14)** |

The cluster's deterministic floor is 0 and ceiling is 3; the rest of the suite (Bucket A's
`VRFPathInvariants` invariants A1–A3 and all 31 seeded/non-invariant Bucket-B reds) was stable RED this
run. Because the cluster is non-deterministic, the v50.0 gate uses the **non-widening SUBSET direction**
(`live − union == ∅`) as binding, and records the cluster's full 3-name membership in the §2 union as
the ceiling. This is honest: it never asserts a red that did not fire, and it never lets a NEW red
escape.

> **Disposition (USER-approved at the 336-06 gate, D-CC-03):** keep `foundry.toml` UNCHANGED (no
> `[invariant] seed`); baseline the full 42-name union as the ceiling with the ⊆ gate; document the
> cluster here. Seeding `[invariant]` for reproducibility (which would also pin the Bucket-A VRF
> invariants) is recorded as a candidate test-infra follow-up, OUT of the 336-06 markdown-only scope.

---

## 5. NEW vs v49 — the new green proof files (the v50 empirical proofs; all GREEN, contribute zero red)

All six 336 proof functions are GREEN at the TST HEAD (re-verified from this run's `forge test --json`);
none appears in the 42-name failing union.

| Plan / Req | Foundry file (extension / new) | Test function | This-run |
|------------|--------------------------------|---------------|----------|
| 336-01 TST-01 (freeze) | `test/fuzz/RngLockDeterminism.t.sol` (ext) | `testFuzz_RngLockDeterminism_ClaimWhalePassDuringLockSafe` | Success |
| 336-02 TST-01 (equiv) | `test/fuzz/RngFreezeAndRemovalProofs.t.sol` (ext) | `testClaimWhalePassMaterializesFutureWindowAndAppliesStats` | Success |
| 336-03 TST-01 (uniform-O(1)) | `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` (ext) | `testWhaleOpenerEqualsNonWhaleOpenerGas` | Success |
| 336-04 TST-02 (no-SLOAD oracle) | `test/fuzz/AfKingSubscription.t.sol` (ext) | `testNonCrossingPathPerformsZeroLazyPassHorizonSloads` | Success |
| 336-05 TST-03 (MINTDIV anchor) | `test/fuzz/MintModuleDivergenceAcrossSplit.t.sol` (new) | `testMintDivCrossPathEquality_OwedSplitsAcrossSlices` | Success |
| 336-05 TST-03 (MINTDIV fuzz) | `test/fuzz/MintModuleDivergenceAcrossSplit.t.sol` (new) | `testFuzz_MintDiv_BoundaryOwedCrossPath` (1000 runs) | Success |

**New v50 green total: 6 passing** (all deterministic — the `[fuzz]` profile is seeded). None is red;
none appears in the 42-name failing union.

> The v50 test-tree migrations (the 8 test files in the BATCH-02 diff `e756a6f3` — the AfKing
> pass-gated fixture migration + the `hasAnyLazyPass`→`lazyPassHorizon` re-wire + the `validThroughLevel`
> oracle rename) landed at the IMPL HEAD and are part of the FROZEN subject, NOT a 336 delta. This phase
> added only the 6 green proofs above; `git diff e756a6f3 HEAD -- test/` is bounded to those additions
> (336-01..05) + this ledger.

---

## 6. Net-zero-new-regression PROOF (the ⊆ gate + the false-confidence guards)

The authoritative whole-tree run AT THE TST HEAD, this session:

```
forge test --json   (default profile, WHOLE tree — NOT --match-path)
  → 674 passed / 40 failed / 17 skipped   (731 run)   [FORGE_EXIT=1, expected with reds]
```

A `forge test --json` parse built the live failing `(suite-basename, testName)` set and compared it to
the §2 enumerated 42-name v50 union by set operations (both directions):

- **`live failing set − v50 §2 union` (NEW regression OUTSIDE baseline) = ∅** — zero failing name is
  outside the 42 union. **This is the binding, load-bearing gate, and it HOLDS.**
- **`v50 §2 union − live failing set` = { `invariant_solvencyUnderDegenerette`,
  `invariant_ghostAccountingNetPositive` }** — exactly the 2 members of the unseeded `DegeneretteBet.inv`
  cluster that flaked GREEN this run (§4). This is a documented non-deterministic *narrowing*, NOT a
  dropped baseline red in the regression sense.
- **`live failing set ⊆ v50 §2 union BY NAME` → TRUE** (40 ⊆ 42; the 2-name slack is the flaky cluster).

> **No `## STOP — NEW REGRESSION OUTSIDE BASELINE` block:** every live red is accounted for by NAME in
> the §2 42-name union (`live − union == ∅`). The v49-precedent strict equality
> (`live failing set == the 42 v50.0 §2 enumerated union`) is intentionally RELAXED to the ⊆ gate for the
> unseeded invariant cluster per the USER hand-review (D-CC-03); the relaxation weakens nothing on the
> regression-detection side (a new red would still appear in `live − union` and trip the STOP).

### The false-confidence guards (mirrors v49 §6 FC1-FC4)

- **FC1 (loose count match masks a new regression):** mitigated. The gate is a NAME-set membership test
  (`live − union == ∅`), not a bare `failed == 40` count. A new regression would surface as a name in
  `live − union` (≠ ∅) and trip the STOP, regardless of how many flaky-cluster reds offset it. *(this is
  the precise trap a count-only gate would hide: a real new red coinciding with a flaky-cluster green.)*
- **FC2 (the v50 deltas are unattributable churn):** mitigated. §3 enumerates the 4 membership deltas BY
  NAME (B9 deleted at 335-05, B10 green at IMPL, B14 + B15 NEW WHALE-01 widenings) with provenance, and
  the delta math `42 − 2 + 2 = 42`. Every union change vs v49 §2 is attributable to a named v50 commit.
- **FC3 (a passing ledger written over a real regression):** mitigated. The §6 comparison emits
  `## STOP — NEW REGRESSION OUTSIDE BASELINE` if `live − union ≠ ∅`; it returned ∅, so no STOP. The
  cluster narrowing was NOT papered over — it is fully documented in §4, and a re-run cherry-picked to
  hit 42 was explicitly rejected.
- **FC4 (the full tree was never actually run — only `--match-path`):** mitigated. `forge test` was run
  on the WHOLE tree (NOT `--match-path`) and reconciled to 674/40/17; the live `(suite, test)` set was
  parsed from the full-run `--json`.
- **FC5 (v50-specific — flaky cluster masquerading as a fix):** mitigated. §4 proves the
  `DegeneretteBet.inv` cluster's 2 greens are unseeded-invariant variance (frozen contract + frozen test
  file + different result), not a v50 fix; the cluster's full 3-name membership is kept in the §2 ceiling
  so a future run catching all 3 still satisfies `live ⊆ union`.

---

## 7. Scope attestation

- The FULL `forge test` tree was run (NOT `--match-path`) at the v50 TST HEAD → **674 passed / 40 failed
  / 17 skipped**; the live failing NAME set ⊆ the 42 v50.0 §2 union (`live − union == ∅`, net-zero new
  regression).
- **Zero `contracts/*.sol` modifications** this phase (D-TST04-04); no new `contracts/*.sol`-touching
  proof authored; the audit subject is FROZEN at the v50 IMPL BATCH-02 commit `e756a6f3`
  (`e756a6f3677f3142aafba7f044e106cd416d0d3b`). `git diff e756a6f3 HEAD -- contracts/` is EMPTY.
- The v50 deltas vs v49 §2 (B9 deleted at 335-05, B10 green at IMPL, NEW B14 `invariant_noEthCreation` +
  B15 `invariant_ghostAccountingNetPositive` added) are fully attributable to 335 D-IMPL-02 / IMPL HEAD
  `e756a6f3`; the delta math is `42 − 2 + 2 = 42`.
- The six new green proof files (§5) contribute only PASSING tests (all deterministic under the seeded
  `[fuzz]` profile).
- The binding gate is a NAME-set SUBSET (`live − union == ∅`), not a bare count and not strict equality
  — the strict-equality form was relaxed for the unseeded `DegeneretteBet.inv` cluster (§4) per the USER
  hand-review (D-CC-03). This ledger is the authoritative NON-WIDENING gate the Phase-338 TERMINAL
  delta-audit consumes; the documented cluster non-determinism is carried forward as a known property of
  the unseeded `[invariant]` profile.
