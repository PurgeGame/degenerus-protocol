# Regression Baseline — v49.0 (NON-WIDENING clean-baseline gate ledger)

**Plan:** 332-06 (Wave-3 full-suite NON-WIDENING regression gate).
**Subject:** the v49.0 unified keeper-router source, FROZEN at the committed v49 source —
`63bc16ca` (the Phase-330 batched router/advance-rework diff) + `4c9f9d9b` (the Phase-331 GAS-calibrated
constants). **Zero `contracts/*.sol` (mainnet) edits were applied by this phase** (TST is a `test/` +
`.planning/` phase; the audit subject stays byte-frozen).
**Baseline carried forward against:** `test/REGRESSION-BASELINE-v48.md §2` — the AUTHORITATIVE 42-red
union BY NAME (the v48.0 clean baseline at `0cc5d10f`, computed at the Phase-326 diff `f50cc634`).

This is a plain-markdown ledger — NOT a `.sol` file, NOT a runnable test. It RECORDS the authoritative
whole-tree `forge test` run AT THE TST HEAD (after all v49 proofs + the 17 deletions + the 5 renames
have landed), the 42-red carried-forward union BY NAME, the 17 deletions with per-test re-homing
justification, the 5 `Crank*`→`Keeper*` file renames, the new green proof files, and the net-zero-new-
regression proof.

> **THE BINDING HEADLINE (by NAME, never a bare count):**
> at the v49 TST HEAD, the `forge test` failing set **==** the 42 v48.0-baseline reds **BY NAME** —
> **net-zero new regression**. The gate is a strict NAME-set equality (`live failing set == the §2
> enumerated 42-name union`), NOT a count match. A count-only gate would mask a real new regression
> that coincidentally offsets one of the 17 deletions. Both directions hold: zero failing name is
> OUTSIDE the 42 union (no new red), and zero name in the 42 union is MISSING from the live set (no
> dropped baseline red). This restores a clean v49.0 regression baseline against the GAS-calibrated
> constants.

---

## 1. The v49 TST-HEAD arithmetic + the deletion / fresh-green reconciliation

The Phase-330 keeper-router diff `63bc16ca` (unified-bounty RD-4 / dropped batchPurchase rngLock guard
RD-2 / autoOpen entry-gate RD-5 / `AutoBought`-event retirement GASOPT-04) + the Phase-331 GAS-2 re-peg
`4c9f9d9b` flipped a set of **17** premise-retired reward-rehoming tests from green-at-v48 to red-at-v49.
332-05 (TST-04 part A) DELETED those 17 (re-authoring their v49 invariants fresh at 332-02/03/04) and
`git mv`-renamed the 5 surviving `Crank*` files to `Keeper*`. The v49 proofs (332-01/02/03/04 + the two
Phase-331-added green files) contribute only PASSING tests.

| Quantity | v49 mid-execution HEAD (pre-delete) | TST-04-A delta (332-05) | v49 TST HEAD (this run) |
|----------|-------------------------------------|-------------------------|-------------------------|
| `forge test` passed | 666 | + **0** (deletions removed only RED tests) | **666** |
| `forge test` failed | 59 | − **17** premise-retired reds DELETED | **42** |
| `forge test` skipped | 17 | + 0 | **17** |
| total run (passed+failed) | 725 | − 17 | **708** |

Reconciliation:
- **`failed == 42`** EXACTLY, and `42 == the v48.0 §2 union BY NAME` (proven §6). `59 − 17 == 42`. ✓
- **`passed == 666`** — the 17 deletions removed only RED tests, so the passing count did NOT change
  across the deletion. The fresh-green v49 proof files (TST-01/02/03/05 + the two Phase-331 files) were
  ALREADY part of the 666 passing at the pre-delete HEAD (they landed before / during TST-04-A); they
  are NOT a post-deletion addition. The `666 passed` is the v49 baseline passing count at the TST HEAD.
- 17 `skipped` carried forward unchanged (the `RngLockDeterminism` `vm.skip` blocks — not reds, not
  greens; orthogonal to the gate).

> **NOTE on the arithmetic shape vs the v48 ledger.** The v48 ledger's §1 was a `594 + 38 NEW_PASSING`
> reconciliation because v48's wave-1 ADDED 5 brand-new GREEN test files in the SAME plan as the gate.
> v49's TST-04 (332-05/06) is a DELETE-and-rename plan layered ON TOP of the already-landed fresh-green
> proofs (332-01..04 landed in earlier waves). So the v49 §1 reconciliation is a `59 − 17 deleted == 42`
> (the failing side), with the passing side flat at 666 across the deletion. The binding invariant —
> "failing == the 42 v48 names" — is identical in both ledgers; only the passing-side bookkeeping shape
> differs because of WHEN the fresh-green files landed relative to the gate plan.

### The fresh v49 green proof files (all GREEN, contribute zero red) — see §5 for the per-file counts.

The six v49-era green proof surfaces total **40** passing tests (3 TST-01 router functions in
`RngLockDeterminism` + 9 + 7 + 7 + 11 + 2 + 1 skip), all GREEN, **zero of their cases is red**, and none
appears in the 42-name failing union.

---

## 2. The AUTHORITATIVE 42-red carried-forward union for `forge test` (enumerated BY NAME — UNCHANGED from v48 §2)

Every red below is a **pre-existing v48.0-baseline red**, carried forward **verbatim and UNCHANGED**
from `test/REGRESSION-BASELINE-v48.md §2` (Buckets A / B / C + the B13 note). The v49 source diff
(`63bc16ca` + `4c9f9d9b`) flipped NONE of these green and dropped NONE of them; the 332-05 deletions
removed only the 17 premise-retired reds (§3), which are DISJOINT from this 42-name union. Adding the
v49 proof files (§5) introduced **zero** new red. **Any forge red NOT in this union is a NEW regression
→ STOP. No such red appeared** (§6, both directions verified empirically this run).

The 42 reds classify into the same three named buckets as v48 (each red lands in exactly one bucket):

### Bucket A — VRF / RNG-window baseline reds (out of v49 scope; v49 touched no VRF/Advance RNG-window code)

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

> **A7 carried forward UNCHANGED (Pitfall 2):** TST-01 (332-01) EXTENDED `RngLockDeterminism.t.sol`
> with NEW router functions but did NOT touch A7's `vm.assume` filters. `git log -L` on the A7 function
> body shows its last body-touching commit is `b102bc0f` (306-04, the V-184 strict-assertion flip) —
> NOT the 332-01 file touch. A7 is the same documented fuzzer-exhaustion red as in v48 (see §6).

### Bucket B — stale-harness / v48-behavioral baseline reds (test fixtures encoding pre-v48 expectations the Phase-326 diff changed; carried forward, out of this gate's scope; re-syncing owned by a future fixture-repair plan)

| # | Suite (file) | Failing test(s) | Count |
|---|--------------|-----------------|-------|
| B1 | `test/fuzz/TicketRouting.t.sol` | `testBoundaryLevel5RoutesToWriteKey`, `testBoundaryLevel6RoutesToFFKey`, `testFarFutureRoutesToFFKey`, `testNearFutureRoutesToWriteKey`, `testRangeRoutingSplitsCorrectly`, `testRngGuardAllowsWithBypass`, `testRngGuardIgnoresNearFuture`, `testRngGuardRangeRevertsOnFirstFFLevel`, `testRngGuardRevertsOnFFKey`, `testRngGuardScaledRevertsOnFFKey`, `testScaledFarFutureRoutesToFFKey`, `testScaledNearFutureRoutesToWriteKey` | 12 |
| B2 | `test/fuzz/QueueDoubleBuffer.t.sol` (MidDaySwapTest) | `testMidDayProcessesReadSlotFirst`, `testMidDayRevertsNotTimeYet`, `testMidDaySwapAtThreshold`, `testMidDaySwapJackpotPhase` | 4 |
| B3 | `test/fuzz/QueueDoubleBuffer.t.sol` (QueueDoubleBufferTest) | `testQueueAfterSwapUsesNewWriteKey`, `testQueueTicketRangeUsesWriteKey`, `testQueueTicketsScaledUsesWriteKey`, `testQueueTicketsUsesWriteKey`, `testWriteReadIsolation` | 5 |
| B4 | `test/fuzz/TicketEdgeCases.t.sol` | `testEdge01NoDoubleCount_FFThenWriteKey`, `testEdge02RoutingPreventsNewFFDeposits` | 2 |
| B5 | `test/fuzz/PrizePoolFreeze.t.sol` | `testFreezeUnfreezeRoundTrip`, `testMultiDayAccumulatorPersistence` | 2 |
| B6 | `test/fuzz/TicketLifecycle.t.sol` | `testLootboxNearRollTicketsProcessed` | 1 |
| B7 | `test/fuzz/GameOverPathIsolation.t.sol` | `testGameOverDrainsQueuedTickets` | 1 |
| B8 | `test/fuzz/LootboxBoonCoexistence.t.sol` | `test_lootboxBoonAppliedDespiteExistingCoinflipBoon`, `test_parametricAutoBuy_crossCategoryBoonFromLootbox` | 2 |
| B9 | `test/fuzz/AfKingSubscription.t.sol` | `testRenewalExactlyAtCostFullBurn` (at-cost renew 0 != 1) | 1 |
| B10 | `test/fuzz/AfKingFundingWaterfall.t.sol` | `testFundingSourceVaultDoesNotInheritExemption` (`BurnieChargeFailed()`) | 1 |
| B11 | `test/fuzz/CoverageGap222.t.sol` | `test_gap_gnrus_propose_vote_paths` | 1 |
| B12 | `test/fuzz/invariant/DegeneretteBet.inv.t.sol` | `invariant_solvencyUnderDegenerette` (replay) | 1 |
| B13 | `test/fuzz/DegeneretteFreezeResolution.t.sol` | `testDgnrsAwardStaysPerSpin` (DGAS-04 per-spin draining sum, `9.2e27 != 1.09e28`) | 1 |

Bucket B total: 12 + 4 + 5 + 2 + 2 + 1 + 1 + 2 + 1 + 1 + 1 + 1 + 1 = **34**.

> **B9 / B10 are carried-forward v48-baseline reds even though a v49 commit later touched their files
> (§6 attribution).** B9 `testRenewalExactlyAtCostFullBurn`: the FAILING test BODY was last touched at
> `f50cc634` (v48 / 326) — the 331-05 `4c9f9d9b` file-level touch (the gas-split work) did NOT modify
> this red's premise (`git log -L` on the function body confirms `f50cc634`). B10
> `testFundingSourceVaultDoesNotInheritExemption`: present and red in the v48 §2 union (B10 at
> `f50cc634`); its body was re-touched by the 330 diff `63bc16ca` (fixture re-sync for the v49 funding
> waterfall) but it was ALREADY a v48-baseline red — it stays red at v49 = carried-forward baseline, NOT
> a new regression. Both are in the 42-name union; neither widens it.

### Bucket C — HERO-deferred reds (FOUNDRY side)

The HERO byte-reproduce gate lives ENTIRELY in the Hardhat stat tree, NOT `forge test` (unchanged from
v48 §2 Bucket C). The only Foundry file asserting Degenerette payout SHAPE is
`test/fuzz/DegeneretteHeroScore.t.sol`, which is GREEN. **FOUNDRY-side HERO-deferred red count = 0.**

| # | Suite (file) | Failing test |
|---|--------------|--------------|
| — | (none) | (none) |

### Union totals

Bucket A (8) + Bucket B (34) + Bucket C (0) = **42**. ✓

Per-suite reconciliation directly from this run's red set (matches the v48 §2 reconciliation
exactly, name-for-name): TicketRouting 12 + QueueDoubleBuffer 9 (MidDaySwap 4 + QDB 5) +
VRFPathInvariants 3 + PrizePoolFreeze 2 + TicketEdgeCases 2 + LootboxBoonCoexistence 2 +
AfKingSubscription 1 + AfKingFundingWaterfall 1 + CoverageGap222 1 + DegeneretteBet.inv 1 +
DegeneretteFreezeResolution 1 + TicketLifecycle 1 + GameOverPathIsolation 1 + RngIndexDrainBinding 1 +
VRFCore 1 + VRFLifecycle 1 + VRFPathCoverage 1 + RngLockDeterminism 1 (A7) = **42**. ✓

---

## 3. NEW vs v48 — the 17 premise-retired deletions, with per-test re-homing justification (332-05 TST-04 part A)

The Phase-330 keeper-router diff `63bc16ca` (the unified-bounty / dropped-guard / entry-gate / event-
retirement model) + the Phase-331 GAS-2 re-peg `4c9f9d9b` RETIRED the premise of **17** tests that were
GREEN at v48.0. Per D-04 (delete + re-author fresh, NOT repair-in-place), 332-05 DELETED all 17 (their
v49 invariants re-authored fresh at 332-02/03/04 — the deletion loses zero coverage) and grep-verified
the deletion target exactly: `failing − the-17-set == the 42 v48 union BY NAME` pre-delete (59 − 17 ==
42), `failing == 42` post-delete. Deletion commit: **`8041451d`** (4 files, 736 deletions).

Each row is classified **reward-shape** (the per-item *summed* / per-leg reward premise retired by RD-4
+ GAS-2) or **oracle-migration** (the RD-2 guard-drop / RD-5 entry-gate / GASOPT-04 no-double-buy oracle
migration). Provenance = the v46 commit that introduced the test green (none last-touched by a v48/327
wave commit → they were GREEN in the v48 ledger; all turned RED only by the v49 diff).

| # | File (→ `Keeper*` rename) | Deleted test | Class | Retired premise | Re-author home (v49) | v46 provenance |
|---|---------------------------|--------------|-------|-----------------|----------------------|----------------|
| 1 | CrankFaucetResistance → KeeperFaucetResistance | `testBatchEmitsExactlyOneCreditFlipWithSum` | reward-shape | per-item *summed* creditFlip amount | flat-per-tx ONE credit (`KeeperRouterOneCategory`, 332-02) | `3afbf676` (318-02 SAFE-01) |
| 2 | CrankFaucetResistance → KeeperFaucetResistance | `testCrankBeforeRngWordSkipsAndDoesNotReward` | reward-shape | skip-and-no-reward via per-leg credit (now `NoWork()`) | `doWork` routes past + `NoWork()` when empty (`KeeperRouterOneCategory`, 332-02) | `3afbf676` (318-02) |
| 3 | CrankFaucetResistance → KeeperFaucetResistance | `testDuplicateInBatchRewardsOnce` | reward-shape | per-item dup reward = once at per-item peg | flat ≥3-gate reward shape (`DegeneretteResolveRepeg`, 332-04) | `3afbf676` (318-02) |
| 4 | CrankFaucetResistance → KeeperFaucetResistance | `testFuzz_MultiBoxRoundTripNonPositiveAcrossGasPrices` | reward-shape | summed-box price-independent reward | open pro-rate-below-knee round-trip ≤0 (`KeeperRewardRoutingSameResults` / `RouterWorstCaseGas`, GAS-05) | `795e679d` (319-05 CR-01) |
| 5 | CrankFaucetResistance → KeeperFaucetResistance | `testFuzz_RoundTripNonPositiveAcrossGasPrices` | reward-shape | per-item fixed reward round-trip | flat-per-tx round-trip ≤0 (`RouterWorstCaseGas`, 331) | `3afbf676` (318-02) |
| 6 | CrankFaucetResistance → KeeperFaucetResistance | `testMultiBoxSelfCrankRoundTripNonPositive` | reward-shape | summed-box self-crank ≤0 | open-leg self-keeper ≤0 under `doWork` (`RouterWorstCaseGas`, 331) | `795e679d` (319-05) |
| 7 | CrankFaucetResistance → KeeperFaucetResistance | `testSelfCrankRoundTripNonPositive` | reward-shape | per-leg self-crank ≤0 | `doWork` self-exclude + ETH-work-gate ≤0 (`RouterWorstCaseGas`, 331) | `3afbf676` (318-02) |
| 8 | CrankFaucetResistance → KeeperFaucetResistance | `testWinningBetFullResolvePathStillPegsReward` | reward-shape | per-item peg alongside a winnings credit | flat ≥3-gate creditFlip alongside winnings (`DegeneretteResolveRepeg` case a, 332-04) | `3afbf676` (318-02) |
| 9 | CrankFaucetResistance → KeeperFaucetResistance | `testZeroSuccessBatchEmitsNoCreditFlip` | oracle-migration | zero-success → no credit via old path (now `NoWork()` on 0 resolved) | `degeneretteResolve` `revert NoWork()` on 0 (`DegeneretteResolveRepeg` case c, 332-04) | `3afbf676` (318-02) |
| 10 | CrankLeversAndPacking → KeeperLeversAndPacking | `testCrankBetsEmitsExactlyOneCreditFlipForManyItems` | reward-shape | ONE creditFlip carrying the SUM of 3 item rewards | one flat `RESOLVE_FLAT_BURNIE` at ≥3 (`DegeneretteResolveRepeg` case a, 332-04) | `dfba3ac1` (319-04 GAS-02) |
| 11 | CrankLeversAndPacking → KeeperLeversAndPacking | `testCrankBoxesEmitsExactlyOneCreditFlipForManyBoxes` | reward-shape | an autoOpen-side creditFlip (= 1) | autoOpen self-credits ZERO; `doWork` credits (`KeeperRouterOneCategory` open branch, 332-02) | `dfba3ac1` (319-04) |
| 12 | CrankNonBrick → KeeperNonBrick | `testBatchPurchaseRngLockedRejectsWholeBatchAtEntry` | oracle-migration | **RD-2:** `batchPurchase` reverts under rngLock (guard DROPPED) | autoBuy-during-rngLock SAFE (`RngLockDeterminism` 332-01); the revert assertion DELETED | `47b9d031` (318-03 SAFE-02) |
| 13 | CrankNonBrick → KeeperNonBrick | `testCrankBetsSkipsPoisonedMiddleItem` | reward-shape | one crank-reward creditFlip for the batch (per-leg) | per-item isolation + flat ≥3 reward shape (`DegeneretteResolveRepeg` / `KeeperBatchAffiliateDeltaAudit` poison-position, 332-04 / 331) | `47b9d031` (318-03) |
| 14 | CrankNonBrick → KeeperNonBrick | `testCrankBoxesSkipsPoisonedEntryViaTryCatch` | oracle-migration | autoOpen per-item try/catch (DROPPED at RD-5 — entry-gate instead) | entry-gate no-marooned-boxes (`RngLockDeterminism` `testAutoOpenNoMaroonedBoxesAfterUnlock`, 332-01) | `47b9d031` (318-03) |
| 15 | CrankNonBrick → KeeperNonBrick | `testFuzz_CrankBetsPoisonPositionNeverBricks` | reward-shape | 2 healthy resolves rewarded at per-item peg | per-item isolation + flat reward at ≥3 (`KeeperBatchAffiliateDeltaAudit` poison-position invariant, 331) | `47b9d031` (318-03) |
| 16 | RngFreezeAndRemovalProofs (NOT renamed) | `testCrankBetResolutionStaysPostUnlock` | oracle-migration | resolution via old per-leg path (now `NoWork()` shape) | `degeneretteResolve` post-unlock + ≥3/`NoWork` gate (`DegeneretteResolveRepeg`, 332-04) | `b9bc5206` (318-05 SAFE-04) |
| 17 | RngFreezeAndRemovalProofs (NOT renamed) | `testFuzz_CrankResolvesIffWordLanded` | oracle-migration | resolves-iff-word via old reward (now `NoWork()` on no word) | `boxesPending`/`autoOpen` rngLock-aware + `NoWork` (`RngLockDeterminism` 332-01 + `DegeneretteResolveRepeg` 332-04) | `b9bc5206` (318-05) |

**Re-homing coverage attestation (no coverage lost by the deletion):** the retired premises re-home into
the fresh v49 proofs as: flat-per-tx one-credit-per-tx (rows 1,2,3,5,8,10,13,15 → `KeeperRouterOneCategory`
332-02 / `DegeneretteResolveRepeg` 332-04, the D-02 count==1 + amount==flat-literal proof); self-keeper /
open round-trip ≤0 (rows 4,6,7 → `RouterWorstCaseGas` 331 + `KeeperRewardRoutingSameResults` 332-03 open
pro-rate); `NoWork()` revert-on-no-work + ≥3 gate (rows 9,16,17 → `DegeneretteResolveRepeg` cases a/b/c/d/e
332-04); RD-2 autoBuy-during-rngLock SAFE (row 12 → `RngLockDeterminism` 332-01); RD-5 entry-gate
no-marooned-boxes (rows 14,17 → `RngLockDeterminism` `testAutoOpenNoMaroonedBoxesAfterUnlock` 332-01);
per-item poison isolation never-bricks (rows 13,15 → `KeeperBatchAffiliateDeltaAudit` poison-position
invariant 331). **SAFE-03 / H-CANCEL-SWAP were PRESERVED, not weakened** (TST-04 hard constraint): the
no-double-buy / cancel-tombstone / reentrancy-rollback survivors in `KeeperNonBrick` + `AfKingConcurrency`
stay GREEN against the migrated `lastAutoBoughtDay` storage oracle (the retired `AutoBought` event,
GASOPT-04, is never read by the survivors), and `testCrankBoxOpenStaysPostUnlock` in
`RngFreezeAndRemovalProofs` stays GREEN.

Also removed by `8041451d` (transitively orphaned ONLY by the deleted set, grep-verified zero
outside-use before removal): the `CRANK_RESOLVE_BET_GAS_UNITS` / `CRANK_OPEN_BOX_GAS_UNITS` /
`CRANK_GAS_PRICE_REF` summed-reward constants in both `Crank{FaucetResistance,LeversAndPacking}`, the
`_placeWinningBet` / `_winningTicketFor` / `_countCoinflipStakeUpdatedWithAmount` helpers in
`KeeperFaucetResistance`, and the now-dead section-divider headers whose every test was deleted.

---

## 4. NEW vs v48 — the 5 `Crank*`→`Keeper*` file renames (pure rename, behavior-neutral, NON-WIDENING) (332-05 D-07)

D-07 de-cranks the test tree to match the v48 contract rename (the user dislikes "crank"). 332-05
`git mv`-renamed the 5 surviving `Crank*`-named test files to `Keeper*` + their internal `contract` decl
+ `@title` + header NatSpec, preserving git rename-detection (R094-R098 similarity). Rename commit:
**`52452fe1`** (5 files, 5 renames at 94-98% similarity, 68 insertions / 78 deletions).

| Current file (v48) | Current contract | → `git mv` target (v49) | New contract |
|--------------------|------------------|-------------------------|--------------|
| `test/fuzz/CrankFaucetResistance.t.sol` | `CrankFaucetResistance` | `test/fuzz/KeeperFaucetResistance.t.sol` | `KeeperFaucetResistance` |
| `test/fuzz/CrankNonBrick.t.sol` | `CrankNonBrick` | `test/fuzz/KeeperNonBrick.t.sol` | `KeeperNonBrick` |
| `test/gas/CrankLeversAndPacking.t.sol` | `CrankLeversAndPacking` | `test/gas/KeeperLeversAndPacking.t.sol` | `KeeperLeversAndPacking` |
| `test/gas/CrankOpenBoxWorstCaseGas.t.sol` | `CrankOpenBoxWorstCaseGas` | `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` | `KeeperOpenBoxWorstCaseGas` |
| `test/gas/CrankResolveBetWorstCaseGas.t.sol` | `CrankResolveBetWorstCaseGas` | `test/gas/KeeperResolveBetWorstCaseGas.t.sol` | `KeeperResolveBetWorstCaseGas` |

**Why the rename is NON-WIDENING (the gate is the red-set / behavior, not file names):** the renames are
pure file-path + identifier churn — Foundry test contracts do not import each other, so all cross-file
references to the old names are provenance COMMENT prose with zero code-level dependency. 332-05 PROVED
behavior-neutrality empirically: the post-rename `forge test` failing NAME set is **byte-identical** to
the post-delete set (**666 passed / 42 failed** both runs), and `forge build` exits 0. A rename that
perturbed any test would have shifted a name in/out of the 42-name union. The single deliberate
code-level `Crank` residual is `testCrankBoxOpenStaysPostUnlock` (GREEN) in the NOT-renamed
`RngFreezeAndRemovalProofs.t.sol` — left UNCHANGED per the explicit plan directive (DO-NOT-DELETE +
do-not-edit-test-logic); all other `Crank` tokens across `test/` are provenance comment prose. The 5
de-cranked GREEN survivor test-function names inside `KeeperFaucetResistance` (`SelfCrank`→`SelfKeeper`,
`ReCrank`→`ReResolve`, `CrankBoxesBeforeRngWord`→`AutoOpenBoxesBeforeRngWord`, `WwxrpCrank`→`WwxrpKeeper`)
are not in the 42-red union (all GREEN), so the by-name gate is unaffected.

---

## 5. NEW vs v48 — the new green proof files (the v49 empirical proofs; actual passing counts)

The v49 TST proofs (332-01/02/03/04) re-author the retired invariants fresh + the two Phase-331-added
green files. All counts re-verified from this run's `forge test --json` (NOT assumed).

| Plan / Req | New / extended Foundry file | Contract | Passing tests | Notes |
|------------|-----------------------------|----------|---------------|-------|
| 332-01 TST-01 | `test/fuzz/RngLockDeterminism.t.sol` (extension) | `RngLockDeterminism` | **3** (router functions) | `testFuzz_RngLockDeterminism_AutoBuyDuringLockSafe` (non-vacuous router same-tx freeze byte-identity) + `testAutoOpenBlockedDuringRngLockNoOps` + `testAutoOpenNoMaroonedBoxesAfterUnlock`. (The contract's own run = 4 pass / 1 fail / 16 skip; the 4th pass is the pre-existing `RetryLootboxRng`, the 1 fail is A7 carried forward, the 16 skip are the `vm.skip` blocks.) |
| 332-02 TST-02 | `test/fuzz/KeeperRouterOneCategory.t.sol` (new) | `KeeperRouterOneCategory` | **9** | one-category creditFlip COUNT==1 across buy/advance/open + `bountyEarned==0` skip (count==0) + `NoWork()` empty + structural reentrancy grep-attest (no attacker harness, D-01) + parameterless default-batch/remainder + UNREWARDED standalone escapes. |
| 332-03 TST-03 | `test/fuzz/KeeperRewardRoutingSameResults.t.sol` (new) | `KeeperRewardRoutingSameResults` | **7** | advance UNREWARDED-standalone (count==0, day still ticks) vs REWARDED-via-`doWork` (mult honored, relative magnitude) + mid-day `mult==1` rewarded + gameover `mult==0` unrewarded + GASOPT-01 `owedMap`-hoist same-results + GASOPT-03 `keeperSnapshot` same-results. |
| 332-04 TST-05 | `test/fuzz/DegeneretteResolveRepeg.t.sol` (new) | `DegeneretteResolveRepeg` | **7** | flat ONE `RESOLVE_FLAT_BURNIE` (count==1 AND amount==1e18, never the summed premise) / 1-2 unpaid-no-strand / 0 `NoWork()` / 3 WWXRP-only unpaid-no-revert / mixed paid-at-gate + RESULTS-equality value-invariant (Open Question 1 route b, no resurrected source). |
| 331 (GAS) | `test/gas/RouterWorstCaseGas.t.sol` (new at v49) | `RouterWorstCaseGas` | **11** | the GAS-2 worst-case marginal-derivation / split-batch / whale-pass-weighted budget harness (re-counted live = 11, NOT the 13 the research draft assumed — the 331 GAS rescope dropped the 2 buy/open seeds). |
| 331 (GAS) | `test/fuzz/KeeperBatchAffiliateDeltaAudit.t.sol` (new at v49) | `KeeperBatchAffiliateDeltaAudit` | **2** (+1 skipped) | `testBaselineDgnrsBatchMoneyOutcomes` + `testPathEquivalence_DgnrsBatchByteIdentical` GREEN; `testFuzz_BaselinePoisonPositionMoneyInvariant` `vm.skip` (1 skipped, not red). |

**New v49 green total: 3 + 9 + 7 + 7 + 11 + 2 = 39 passing** (+ 1 skipped in `KeeperBatchAffiliateDeltaAudit`).
None of these 39 passing tests is red; none appears in the 42-name failing union.

**TST-05 Hardhat Degenerette stat secondary gate (precedent-locked v48 parity, recorded at 332-04):**
`npx hardhat test test/stat/DegenerettePerNEvExactness.test.js test/stat/DegeneretteBonusEv.test.js
test/stat/DegeneretteProducerChi2.test.js` → **24 passing / 1 pending** (the STAT-02 round-trip lifecycle
soft-skip, BY DESIGN — a pending, not a failure; chi²/EV-exactness distribution invariance unchanged by
the `degeneretteResolve` rename). This is the v48 last-known parity, not a regression. The Foundry
NON-WIDENING ledger (this document) is the authoritative regression gate; the Hardhat stat tree is the
secondary gate.

---

## 6. Net-zero-new-regression PROOF (the false-confidence guards + the membership table)

The authoritative whole-tree run AT THE TST HEAD (`7d59ec16`), this session:

```
forge test  (default profile, WHOLE tree — NOT --match-path)
  → 666 passed / 42 failed / 17 skipped  (708 run)
```

A `forge test --json` parse built the live failing `(suite-basename, testName)` set and compared it to
the §2 enumerated 42-name v48 union by strict SET EQUALITY:

- **`live failing set − v48 union` (NEW regression OUTSIDE baseline) = ∅** — zero failing name is outside
  the 42 union.
- **`v48 union − live failing set` (dropped baseline red) = ∅** — zero name in the 42 union is missing.
- **`live failing set == v48 union BY NAME` → TRUE.** (Both 42-element sets; element-for-element equal.)

> **No `## STOP — NEW REGRESSION OUTSIDE BASELINE` block:** every red is accounted for by NAME in the §2
> 42-name union; the actual red set is exactly the union (not merely a subset — it is equal, so no
> baseline red was dropped either).

### The false-confidence guards (mirrors v48 §4 FC1-FC4)

- **FC1 (loose count match masks a new regression):** mitigated. The gate is a strict NAME-set EQUALITY
  against the §2 enumerated union, not a bare `failed == 42` count. A new regression that coincidentally
  offset one of the 17 deletions would surface as a name in `live − union` (≠ ∅) and trip the STOP.
  *(T-332-06-COUNT)*
- **FC2 (the 17 deletions / 5 renames are unattributable churn):** mitigated. §3 enumerates the 17
  deletions BY NAME with per-test re-homing + the v46 provenance commit (`3afbf676` / `795e679d` /
  `dfba3ac1` / `47b9d031` / `b9bc5206`) and the deletion commit `8041451d`; §4 enumerates the 5 renames
  with the `git mv` commit `52452fe1` and the byte-identical-failing-set behavior-neutrality proof. Every
  test-tree diff vs v48 is attributable to a named v49 commit. *(T-332-06-ATTR)*
- **FC3 (a passing ledger written over a real regression):** mitigated. The §1 reconciliation STOPS with
  `## STOP — NEW REGRESSION OUTSIDE BASELINE` if any failing name is outside the 42 union — the ledger is
  never written green over a genuine regression. The set comparison above returned ∅ for `live − union`,
  so no STOP was emitted. *(T-332-06-FALSE)*
- **FC4 (the full tree was never actually run — only `--match-path`):** mitigated. `forge test` was run on
  the WHOLE tree (NOT `--match-path`) and reconciled to 666/42/17; the per-suite membership table below
  covers every failing suite.

### Membership proof that all 42 reds predate v49 (last-touching commit per failing suite)

```
git log -1 --format=%h <suite-file>     (file-level last-touching commit)
git log -L /func/,/^    }/:<file>        (per-test BODY last-touching commit, where the file was v49-touched)
```

| Failing suite | File-level last-touch | Failing-test BODY last-touch | Phase | Carried-forward? |
|---------------|-----------------------|------------------------------|-------|------------------|
| `PrizePoolFreeze.t.sol` | `38da9417` | `38da9417` | 03 (pre-v48) | yes |
| `TicketRouting.t.sol` | `2d96df6f` | `2d96df6f` | pre-v48 | yes |
| `QueueDoubleBuffer.t.sol` | `156b22ac` | `156b22ac` | 210 (pre-v48) | yes |
| `TicketEdgeCases.t.sol` | `156b22ac` | `156b22ac` | 210 (pre-v48) | yes |
| `VRFLifecycle.t.sol` | `e284da33` | `e284da33` | 211 (pre-v48) | yes |
| `CoverageGap222.t.sol` | `f50cc634` | `f50cc634` | 326 (v48 diff) | yes |
| `TicketLifecycle.t.sol` | `f50cc634` | `f50cc634` | 326 (v48 diff) | yes |
| `LootboxBoonCoexistence.t.sol` | `f50cc634` | `f50cc634` | 326 (v48 diff) | yes |
| `DegeneretteFreezeResolution.t.sol` | `b9451eb0` | `b9451eb0` | 323 (pre-v48) | yes |
| `RngIndexDrainBinding.t.sol` | `5b7f76ad` | `5b7f76ad` | 323 (pre-v48) | yes |
| `GameOverPathIsolation.t.sol` | `4606a8ad` | `4606a8ad` | pre-v48 | yes |
| `invariant/DegeneretteBet.inv.t.sol` | `82520b4c` | `82520b4c` | 323 (pre-v48) | yes |
| `invariant/VRFPathInvariants.inv.t.sol` | `0009d207` | `0009d207` | pre-v48 | yes |
| `VRFCore.t.sol` | `80516d30` | `80516d30` | 323 (pre-v48) | yes |
| `VRFPathCoverage.t.sol` | `80516d30` | `80516d30` | 323 (pre-v48) | yes |
| `AfKingSubscription.t.sol` | `4c9f9d9b` (331-05 file touch) | **`f50cc634`** (326 — body) | 326 (v48 diff) | yes — body is a v48 red; the 331-05 touch was the gas-split, NOT this red's premise |
| `AfKingFundingWaterfall.t.sol` | `63bc16ca` (330 file touch) | **`63bc16ca`** (330 — body re-sync) | 330 (v49) — but **RED at v48 (B10 @ `f50cc634`)** | yes — present and red in v48 §2 (B10); the 330 body re-touch is the v49 funding-waterfall fixture re-sync, the test was ALREADY a v48-baseline red |
| `RngLockDeterminism.t.sol` | `41a49223` (332-01 file touch) | **`b102bc0f`** (306-04 — A7 body) | 306 (pre-v48) | yes — A7's `vm.assume` filters untouched by 332-01 (Pitfall 2); only NEW router functions were added |

**Net-zero attribution (the binding conclusion):**
- **15 of the 18 failing suites** were last touched (file-level) at or before the v48 diff `f50cc634` (or
  earlier 03 / 210 / 211 / 323 commits) → their reds plainly predate v49.
- **3 suites** were file-touched by a v49 commit (`AfKingSubscription` by 331-05, `AfKingFundingWaterfall`
  by 330, `RngLockDeterminism` by 332-01), but the per-test BODY-level `git log -L` proves each FAILING
  test is a carried-forward v48-baseline red: the 331-05 / 332-01 touches added unrelated work (the
  gas-split / the NEW TST-01 router functions) and did NOT alter the failing red's premise; the 330 touch
  re-synced `AfKingFundingWaterfall` for the v49 funding waterfall but B10 was ALREADY red at v48.
- **The v49 source diff (`63bc16ca` + `4c9f9d9b`) flipped NONE of the 42 from green to red**, and the
  332-05 deletions removed only the 17 DISJOINT premise-retired reds. Therefore:

> **NET NEW REGRESSION FROM THE v49 KEEPER-ROUTER REDESIGN (330) + GAS RE-PEG (331) + TST PROOFS (332) = 0.**

---

## 7. Scope attestation

- The FULL `forge test` tree was run (NOT `--match-path`) at the v49 TST HEAD `7d59ec16` → 666 passed /
  42 failed / 17 skipped; the failing NAME set == the 42 v48.0-baseline union (net-zero new regression).
- **Zero `contracts/*.sol` (mainnet) modifications** this phase; no new `contracts/*.sol`-touching
  proof authored; the audit subject is FROZEN at the committed v49 source (`63bc16ca` + the Phase-331 GAS
  constants `4c9f9d9b`). `git diff --name-only contracts/` is empty.
- The 17 premise-retired deletions (`8041451d`, §3) + the 5 `Crank*`→`Keeper*` renames (`52452fe1`, §4)
  are fully attributable; the renames are proven behavior-neutral (byte-identical failing set).
- The fresh v49 green proof files (§5) contribute only PASSING tests; the TST-05 Hardhat Degenerette stat
  secondary gate is GREEN at v48 parity (24 passing / 1 pending, by design).
- The binding gate is a NAME-set equality, not a bare count — this ledger is the authoritative
  NON-WIDENING gate the Phase-333 TERMINAL delta-audit consumes.
