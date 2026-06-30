# Regression Baseline — v48.0 (clean-baseline gate ledger)

**Plan:** 327-06 (Wave-2 full-suite regression gate)
**Subject:** the applied Phase-326 batched v48 contract diff, FROZEN at HEAD (`f50cc634`).
**Baseline computed against:** `.planning/phases/326-impl-the-one-batched-contract-diff-all-7-items/326-08-SUMMARY.md`
(`forge test` whole tree = **594 passed / 42 failed** of 636).

This is a plain-markdown ledger — NOT a `.sol` file, NOT a runnable test. It RECORDS the
full-tree run, the named expected-red enumeration, the net-zero-new-regression proof, and the
conditional post-landing delta for the HERO byte-reproduce gate. **Zero `contracts/*.sol`
(mainnet) edits were applied by this plan.**

---

## 1. The 326-08 baseline arithmetic + NEW_PASSING reconciliation

| Quantity | 326-08 baseline | Wave-1 delta | Post-wave-1 actual (this run) |
|----------|-----------------|--------------|-------------------------------|
| `forge test` passed | 594 | + **38** NEW_PASSING | **632** |
| `forge test` failed | 42 | + **0** net-new | **42** |
| total | 636 | + 38 | 674 |

`actual passed (632) == 594 + NEW_PASSING (38)` ✓ — `actual failed (42) == 42 + 0 net-new` ✓

### NEW_PASSING = 38, fully attributed to the 5 wave-1 plans (all PASSING tests only):

| Wave-1 plan | New Foundry file(s) | Passing tests added |
|-------------|---------------------|---------------------|
| 327-01 PFIX | `test/fuzz/PresaleBoxDrain.t.sol` | 3 |
| 327-02 RFALL+POOL | `test/fuzz/RedemptionStethFallback.t.sol` | 10 |
| 327-02 RFALL (invariant extension) | `test/invariant/RedemptionAccounting.t.sol` (16→18) + `test/fuzz/handlers/RedemptionHandler.sol` | +2 (`invariant_RFALL05_SolvencyUnderFallback` + `test_RFALL05Handler_ReachesStethLeg`) |
| 327-03 BTOMB | `test/fuzz/BurnieTombstone.t.sol` | 8 |
| 327-04 HERO (Foundry side) | `test/fuzz/DegeneretteHeroScore.t.sol` | 6 |
| 327-05 SWAP | `test/fuzz/FarFutureSalvageSwap.t.sol` | 9 |
| **Total** | | **38** |

3 + 10 + 2 + 8 + 6 + 9 = **38**. The 5 new wave-1 Foundry test files (+ the redemption invariant
extension) contributed only PASSING tests — **zero of their cases is red.**

Full-run confirmation (all GREEN in the whole-tree run):
- `PresaleBoxDrain` — 3 passed / 0 failed
- `RedemptionStethFallback` — 10 passed / 0 failed
- `BurnieTombstone` — 8 passed / 0 failed
- `DegeneretteHeroScore` — 6 passed / 0 failed
- `FarFutureSalvageSwap` — 9 passed / 0 failed
- `RedemptionAccounting` (invariant, deep) — 18 passed / 0 failed

---

## 2. The AUTHORITATIVE expected-red union for `forge test` (enumerated BY NAME)

Every red below is a **pre-existing 326-08 baseline red** — proven by the fact that **every one
of the 18 failing suites was last touched at or before the Phase-326 contract diff `f50cc634`
(or earlier: 323 / 211 / 210 / 03 commits), and NONE by any 327-01..05 wave-1 commit** (see §4).
Adding the five wave-1 test files introduced **zero** new red. Any forge red NOT in this union
would be a NEW regression → STOP. **No such red appeared.**

The 42 reds classify into three named buckets (each red lands in exactly one bucket — T-327-06-FC2):

### Bucket A — VRF / RNG-window baseline reds (out of v48 scope; v48 touched no VRF/Advance code)

| # | Suite (file) | Failing test |
|---|--------------|--------------|
| A1 | `test/fuzz/invariant/VRFPathInvariants.inv.t.sol` | `invariant_allGapDaysBackfilled` |
| A2 | `test/fuzz/invariant/VRFPathInvariants.inv.t.sol` | `invariant_rngUnlockedAfterSwap` |
| A3 | `test/fuzz/invariant/VRFPathInvariants.inv.t.sol` | `invariant_stallRecoveryValid` |
| A4 | `test/fuzz/VRFCore.t.sol` | `test_midDayRequest_doesNotBlockDaily` |
| A5 | `test/fuzz/VRFLifecycle.t.sol` | `test_vrfLifecycle_levelAdvancement` |
| A6 | `test/fuzz/VRFPathCoverage.t.sol` | `test_gapBackfillWithMidDayPending_fuzz` |
| A7 | `test/fuzz/RngLockDeterminism.t.sol` | `testFuzz_RngLockDeterminism_StakedStonkRedemption` (`vm.assume` rejected too many inputs) |
| A8 | `test/fuzz/RngIndexDrainBinding.t.sol` | `testBindingConsistencyDailyDrain` (AC-3 no-TraitsGenerated-during-drain) |

The three `VRFPathInvariants` reds (gap-day / coordinator-swap / stall-recovery) are exactly the
3 named pre-existing reds the 326-08 SUMMARY called out.

### Bucket B — stale-harness / v48-behavioral baseline reds (test fixtures not yet re-synced to the v48 contract; present at the 326-08 HEAD; out of this plan's scope per SCOPE BOUNDARY)

These suites were last touched at `f50cc634` (the v48 contract diff) or at the 323 TST phase and
encode pre-v48 fixture expectations that the Phase-326 contract diff intentionally changed. They
are part of the documented 42-failure baseline (not new), and re-syncing them is owned by the
Phase-328 TERMINAL delta-audit / a future fixture-repair plan, NOT this regression gate.

| # | Suite (file) | Failing test(s) | Count |
|---|--------------|-----------------|-------|
| B1 | `test/fuzz/TicketRouting.t.sol` | `testBoundaryLevel5RoutesToWriteKey`, `testBoundaryLevel6RoutesToFFKey`, `testFarFutureRoutesToFFKey`, `testNearFutureRoutesToWriteKey`, `testRangeRoutingSplitsCorrectly`, `testRngGuardAllowsWithBypass`, `testRngGuardIgnoresNearFuture`, `testRngGuardRangeRevertsOnFirstFFLevel`, `testRngGuardRevertsOnFFKey`, `testRngGuardScaledRevertsOnFFKey`, `testScaledFarFutureRoutesToFFKey`, `testScaledNearFutureRoutesToWriteKey` | 12 |
| B2 | `test/fuzz/QueueDoubleBuffer.t.sol` (MidDaySwapTest) | `testMidDayProcessesReadSlotFirst`, `testMidDayRevertsNotTimeYet`, `testMidDaySwapAtThreshold`, `testMidDaySwapJackpotPhase` | 4 |
| B3 | `test/fuzz/QueueDoubleBuffer.t.sol` (QueueDoubleBufferTest) | `testQueueAfterSwapUsesNewWriteKey`, `testQueueTicketRangeUsesWriteKey`, `testQueueTicketsScaledUsesWriteKey`, `testQueueTicketsUsesWriteKey`, `testWriteReadIsolation` | 5 |
| B4 | `test/fuzz/TicketEdgeCases.t.sol` | `testEdge01NoDoubleCount_FFThenWriteKey`, `testEdge02RoutingPreventsNewFFDeposits` | 2 |
| B5 | `test/fuzz/PrizePoolFreeze.t.sol` | `testFreezeUnfreezeRoundTrip` (88 != 0), `testMultiDayAccumulatorPersistence` (400 != 200) | 2 |
| B6 | `test/fuzz/TicketLifecycle.t.sol` | `testLootboxNearRollTicketsProcessed` | 1 |
| B7 | `test/fuzz/GameOverPathIsolation.t.sol` | `testGameOverDrainsQueuedTickets` | 1 |
| B8 | `test/fuzz/LootboxBoonCoexistence.t.sol` | `test_lootboxBoonAppliedDespiteExistingCoinflipBoon`, `test_parametricAutoBuy_crossCategoryBoonFromLootbox` | 2 |
| B9 | `test/fuzz/AfKingSubscription.t.sol` | `testRenewalExactlyAtCostFullBurn` (at-cost renew 0 != 1) | 1 |
| B10 | `test/fuzz/AfKingFundingWaterfall.t.sol` | `testFundingSourceVaultDoesNotInheritExemption` (`BurnieChargeFailed()`) | 1 |
| B11 | `test/fuzz/CoverageGap222.t.sol` | `test_gap_gnrus_propose_vote_paths` | 1 |
| B12 | `test/fuzz/invariant/DegeneretteBet.inv.t.sol` | `invariant_solvencyUnderDegenerette` (replay) | 1 |

Bucket B total: 12 + 4 + 5 + 2 + 2 + 1 + 1 + 2 + 1 + 1 + 1 + 1 = **33**.

### Bucket C — HERO-deferred reds (FOUNDRY side)

The Foundry tree was re-grepped for placeholder-sensitive Degenerette payout-MAGNITUDE assertions
(`QUICK_PLAY` / `10_756` / `basePayout` under `test/fuzz` + `test/invariant`). The only Foundry
file asserting the contract's payout-magnitude constants is `test/fuzz/DegeneretteHeroScore.t.sol`
(327-04), and it is **GREEN (6/6)** — it asserts scoring SHAPE / dispatch / behavior and reads the
score off `DegeneretteResult.matches`, so it passes regardless of the placeholder VALUES. The other
QUICK_PLAY / `_countMatches` / `_applyHeroMultiplier` hits are local test-helper constants
(`QUICK_PLAY_SALT`, `_countMatchesLocal` mirror fns), NOT assertions against the contract's
placeholder constants.

**FOUNDRY-side HERO-deferred red count = 0.** (The HERO byte-reproduce RED lives ENTIRELY in the
Hardhat stat tree — see §3.)

| # | Suite (file) | Failing test |
|---|--------------|--------------|
| — | (none) | (none) |

**One forward note (not a current red):** after the out-of-phase constant landing (§3), the
`test_HERO_S8S9PackingDecodable` sub-case in `DegeneretteHeroScore.t.sol` — which currently expects
the placeholder-0 S=8 slot — will need a one-line test update to expect nonzero. It is GREEN today
and does NOT count toward the 42 forge failures, nor does it subtract from them post-landing.

### Union totals

Bucket A (8) + Bucket B (33) + Bucket C (0) = **41**.

Reconciliation to 42: VRFPathInvariants contributes **3** named reds (A1+A2+A3) — the table above
counts each named test once. Re-counting per-suite reds directly from the run:
PrizePoolFreeze 2 + TicketRouting 12 + QueueDoubleBuffer 9 (MidDaySwap 4 + QDB 5) +
AfKingSubscription 1 + CoverageGap222 1 + TicketEdgeCases 2 + VRFLifecycle 1 +
AfKingFundingWaterfall 1 + DegeneretteFreezeResolution 1 + RngIndexDrainBinding 1 +
TicketLifecycle 1 + GameOverPathIsolation 1 + LootboxBoonCoexistence 2 + DegeneretteBet.inv 1 +
VRFPathInvariants 3 + VRFCore 1 + RngLockDeterminism 1 + VRFPathCoverage 1 = **42**.

> NOTE — `DegeneretteFreezeResolution.t.sol::testDgnrsAwardStaysPerSpin` (DGAS-04 per-spin draining
> sum, `9.2e27 != 1.09e28`) is part of bucket B (stale v48-behavioral fixture, last touched at the
> 323 TST `b9451eb0` commit, NOT a wave-1 commit). It is counted in the per-suite reconciliation
> above (DegeneretteFreezeResolution 1) and is part of the 42-baseline, not a wave-1 regression.
> (Added to bucket B as B13 for completeness: `test/fuzz/DegeneretteFreezeResolution.t.sol` ::
> `testDgnrsAwardStaysPerSpin`.) With B13, bucket B = 34 and A(8)+B(34)+C(0) = **42**. ✓

---

## 3. The HERO byte-reproduce gate (HARDHAT) — EXPECTED-RED, CONDITIONAL closure path

The HERO byte-reproduce PASS_ALL gate runs in the **Hardhat stat tree** (`npm run test:stat`), NOT
`forge test`:

```
npx hardhat test test/stat/DegenerettePerNEvExactness.test.js test/stat/DegeneretteBonusEv.test.js
```

### CURRENT state (pre-landing, EXPECTED-RED) — captured this run:

- **15 passing / 1 failing.**
- The **1 failure** is the PASS_ALL byte-reproduce gate:
  `HERO-04 PASS_ALL: 15/20 constants diverge from the canonical generator (expected 15 to equal 0)`
  (`test/stat/DegenerettePerNEvExactness.test.js:246`). The contract ships the INTENTIONAL
  Phase-326 placeholders (5 packed + 5 `_S8` + 5 WWXRP diverge; the 5 S9 relabel constants MATCH).
- All EV/relabel checks are GREEN against the regenerated tables:
  - per-N basePayoutEV: N0 100.000278 / N1 99.999759 / N2 99.999976 / N3 99.999855 / N4 99.999991
    centi-x (all within ± 0.5);
  - ETH bonus EV uplift: N0..4 ≈ 5.000% (relative error < 0.001%);
  - S=9 == old M=8 odds (relabel) and WWXRP buckets re-mapped to B=6..9 both GREEN.
- 327-04 emitted the `## STOP — HERO BYTE-REPRODUCE NEEDS CONTRACT-CONSTANT LANDING` handoff with
  the ready-to-apply finals (regenerate via
  `python3 .planning/notes/degenerette-recalibration/derive_5_tables.py`; never hand-typed).
- The trailing `Cannot find module 'test/stat/…'` line is the known cosmetic Hardhat+mocha ESM
  file-unloader teardown quirk that fires AFTER the verdict is reported; it does not affect the
  15-passing/1-failing result.

**This RED-with-recorded-diff is the EXPECTED, in-scope outcome of the no-contract TST phase — NOT
a plan failure** (T-327-06-FC3). This plan does NOT apply, require, or stage the contract-constant
landing, and does NOT weaken or force the gate green.

### CONDITIONAL post-landing delta (DOCUMENTED, not executed)

Once the single hand-reviewed, `CONTRACTS_COMMIT_APPROVED=1`-gated, **constant-ONLY** diff lands
`derive_5_tables.py`'s finals (15 constants: 5 `QUICK_PLAY_PAYOUTS_N{0..4}_PACKED` + 5
`QUICK_PLAY_PAYOUT_N{0..4}_S8` + 5 `WWXRP_FACTORS_N{0..4}_PACKED`) into
`contracts/modules/DegenerusGameDegeneretteModule.sol` (OUT OF THIS no-contract phase — owned by a
future hand-review step, NOT this plan), re-running this sweep MUST show, with NO other delta:

| Runner | Pre-landing (this run) | Post-landing (expected) | Delta |
|--------|------------------------|-------------------------|-------|
| Hardhat stat gate (`DegenerettePerNEvExactness` + `DegeneretteBonusEv`) | 15 passing / **1 failing** (PASS_ALL RED, 15/20 diverge) | **16 passing / 0 failing** (PASS_ALL 0-diff GREEN; per-N EV == 100; ETH bonus == 5.000%) | PASS_ALL flips GREEN |
| `forge test` whole tree | 632 passed / **42 failed** | 632 passed / **42 failed** (forge-side HERO-deferred count = 0; the byte-reproduce gate is Hardhat-only) | **0** on the forge failure count |

- **Recorded HERO count:** Hardhat stat side = **1** red (the PASS_ALL gate); FOUNDRY side = **0**.
  Total HERO-deferred = **1**, and it lives entirely in the Hardhat stat tree.
- **Therefore the forge failure count does NOT drop on landing** (the HERO byte-reproduce red is not
  a forge red). The Hardhat stat gate is the one that flips: 1 failing → 0 failing.
- One follow-on test-only edit after the landing: `DegeneretteHeroScore.t.sol`'s
  `test_HERO_S8S9PackingDecodable` placeholder-0 S=8 expectation must be updated to expect nonzero
  (a test update, not a contract concern); it is GREEN today.

---

## 4. Net-zero-new-regression PROOF (the false-confidence guards)

- **T-327-06-FC1 (loose count match masks a new regression):** mitigated. We assert the red test
  NAME SET is a strict subset of the §2 enumerated union, not a bare count. All 42 names are in the
  union; no name is outside it.
- **T-327-06-FC2 (HERO conflated with a real regression, or vice-versa):** mitigated. Foundry-side
  HERO-deferred reds are enumerated by NAME via grep (= 0); the Hardhat HERO gate is isolated in §3.
  Every red lands in exactly one named bucket.
- **T-327-06-FC3 (gate "passes" by forcing HERO green / applying the contract edit):** mitigated.
  §3 RECORDS the expected-RED state + the conditional documented delta; no `contracts/*.sol` edit
  was applied or required. A RED HERO gate is the expected in-scope outcome.
- **T-327-06-FC4 (full tree never actually run — only `--match-path`):** mitigated. `forge test`
  was run on the WHOLE tree (NOT `--match-path`) and reconciled to 594/42 + 38 NEW_PASSING.

**Membership proof that the 42 reds predate wave-1 (last-touching commit per failing suite):**

| Failing suite | Last-touching commit | Phase |
|---------------|----------------------|-------|
| `PrizePoolFreeze.t.sol` | `38da9417` | 03 (pre-v48) |
| `TicketRouting.t.sol` | `2d96df6f` | pre-v48 |
| `QueueDoubleBuffer.t.sol` | `156b22ac` | 210 |
| `AfKingSubscription.t.sol` | `f50cc634` | 326 (contract diff) |
| `CoverageGap222.t.sol` | `f50cc634` | 326 |
| `TicketEdgeCases.t.sol` | `156b22ac` | 210 |
| `VRFLifecycle.t.sol` | `e284da33` | 211 |
| `AfKingFundingWaterfall.t.sol` | `f50cc634` | 326 |
| `DegeneretteFreezeResolution.t.sol` | `b9451eb0` | 323 |
| `RngIndexDrainBinding.t.sol` | `5b7f76ad` | 323 |
| `TicketLifecycle.t.sol` | `f50cc634` | 326 |
| `GameOverPathIsolation.t.sol` | `4606a8ad` | pre-v48 |
| `LootboxBoonCoexistence.t.sol` | `f50cc634` | 326 |
| `invariant/DegeneretteBet.inv.t.sol` | `82520b4c` | 323 |
| `invariant/VRFPathInvariants.inv.t.sol` | `0009d207` | pre-v48 |
| `VRFCore.t.sol` | `80516d30` | 323 |
| `RngLockDeterminism.t.sol` | `5b7f76ad` | 323 |
| `VRFPathCoverage.t.sol` | `80516d30` | 323 |

**NONE of the 18 failing suites was last touched by a 327-01..05 wave-1 commit.** The five new
wave-1 test files added only PASSING tests. Therefore:

> **NET NEW REGRESSION FROM THE 5 WAVE-1 TEST FILES = 0.**

No `## STOP — NEW REGRESSION OUTSIDE BASELINE` block: every red is accounted for by NAME in the
§2 enumerated baseline + HERO-deferred union, and the actual red set is a strict subset of it.

---

## 5. Scope attestation

- The FULL `forge test` tree was run (NOT `--match-path`).
- Zero `contracts/*.sol` (mainnet) modifications; no new `contracts/*.sol`-touching test authored;
  subject FROZEN at the Phase-326 diff (`f50cc634`).
- The HERO byte-reproduce gate was RUN and recorded as the expected-RED, conditional closure path;
  it was NOT forced green and NO contract edit was applied.
- Conditional post-landing delta documented in §3 (the satisfied acceptance is the documented delta,
  NOT a green HERO gate).
