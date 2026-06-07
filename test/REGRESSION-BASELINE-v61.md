# Regression Baseline — v61.0 (frozen-baseline `2bee6d6f` red set + NON-WIDENING ceiling)

**Subject under test (v61 HEAD):** `b97a7a2e` (the v61.0 batched AFPAY+PACK+CURSE+SMITE diff)
+ `056481ea` (377 GAS Outcome-A) — the milestone working HEAD.
**Frozen baseline (the ceiling):** `2bee6d6f` (the v60.0 closure HEAD — the v61 milestone's
declared baseline per STATE.md / ROADMAP.md). This is the contract subject BEFORE the v61 fold.
**Captured:** 2026-06-07, Plan 378-01 Task 3 (the foundation for the TST-06 non-widening gate
that Plan 378-05 runs against this ceiling).

> **Purpose.** The v61 PACK fold breaks every slot-hardcoded harness at runtime (the −1
> balances-region shift) AND the repo carries a large pre-existing red baseline (v56/v57 ran
> ~134 red-by-name). A large v61-HEAD red count is therefore EXPECTED and does NOT by itself
> indicate a regression. "No v61 regression" is certified ONLY by a NON-WIDENING comparison:
> the v61-HEAD forge red NAME set must be a SUBSET of
> (this baseline union ∪ accepted-slot-shift-staleness ∪ accepted-v61-behavior-changes).
> Any HEAD red NOT in that union is a candidate v61 finding. (The established v55/56/57
> methodology — see `REGRESSION-BASELINE-v56.md` / `-v57.md`.)

---

## 1. Counts

`forge test` (default profile) against the frozen baseline `2bee6d6f`
(full `2bee6d6f` test tree + `2bee6d6f` contracts — the tree as it compiled at that commit):

| | passed | failed | skipped | total |
|---|---|---|---|---|
| **`2bee6d6f` baseline** | **533** | **183** | **103** | **819** |

- 183 total failures collapse to **172 unique failing test NAMES** (the remainder are repeats
  across fuzz seeds / parameterized cases of the same name).
- 94 forge test suites; 38 suites contain ≥1 failure.

**Capture method (non-destructive, tree returned to HEAD):** Tasks 1-2 were committed first
(so they survive). The full `2bee6d6f` test tree + contracts were checked out
(`git checkout 2bee6d6f -- test/ contracts/`); the two untracked 378-02 WIP gas drafts
(`ActivityScoreStreakGas.t.sol`, `AdvanceStageWorstCaseGas.t.sol`) were moved aside.
`forge clean && forge build` (clean), full `forge test`, names captured. Then HARD-restored:
`git checkout HEAD -- test/ contracts/`, untracked WIP moved back, `forge clean && forge build`
(clean) → the v61 HEAD subject is back. **`git diff HEAD -- contracts/` is EMPTY**;
contracts/ fingerprint `fcdd999ce2ddb0cac9e04b49242522b896cf56c67c18e213cd0f6dd5b6aa8aaf`.

> Why the FULL baseline test tree (not just baseline contracts): the v61 test tree calls
> v61-only accessors (`_claimableOf` in `JackpotSingleCallCorrectness.t.sol:36` and
> `YieldSurplusSolvency.t.sol:51`) and the v61 `SettleClaimableShortfallTester.settle(…, bool)`
> 3-arg signature (`StakedStonkRedemption.t.sol:1156/1173`), none of which exist at `2bee6d6f`.
> The faithful baseline red set is therefore the `2bee6d6f` test tree against the `2bee6d6f`
> contracts — exactly what compiled at that commit.

## 2. The non-widening rule (TST-06 gate — applied in 378-05)

Let `BASE` = the 172-name union in §3. A v61-HEAD forge red `r` is a **candidate v61 finding**
iff:

```
r ∉ BASE  ∪  accepted-slot-shift-staleness  ∪  accepted-v61-behavior-change
```

- **accepted-slot-shift-staleness** = harness reds whose `[FAIL: …]` reason is a wrong-slot
  `vm.store`/`vm.load` artifact of the v61 −1 balances-region shift (the §A/§B recalibration
  set in `378-PLAN-TRIAGE.md`; the authoritative slot map in `378-01-RECALIBRATION-KEY.md`).
  These are recalibrated across 378-01 (StorageFoundation + 4 redemption harnesses) and 378-02
  (the 6 gas harnesses); a recalibrated harness turning GREEN is a NARROWING (allowed).
- **accepted-v61-behavior-change** = a test asserting pre-v61 behavior the feature legitimately
  changed (an `AfkingSpent`/`PlayerCredited` emit now present; a curse-penalized activity score;
  an afking-funded shortfall now succeeding where it used to revert; the affiliate fresh/recycled
  split). These are updated in 378-03 and listed there BY NAME.

Set-diff discipline (per v55/56/57): the gate proves `live − (BASE ∪ accepted) == ∅` BY NAME.
`BASE − live` ≠ ∅ is a NARROWING (reds the v61 work fixed/recalibrated), NOT a regression.
A raw red-count change is NOT a regression signal — only a NEW name outside the union is.

## 3. The `2bee6d6f` baseline red union — BY NAME (the ceiling, 172 names)

```
reset
testAdvanceBranchCreditsExactlyOnce
testAdvanceViaMintBurnieRewardedMultiplierHonored
testAffiliateBaseDrainAffiliateOnly
testAffiliateReClaimChurnEqualsHonestContinuous
testAutoOpenNoMaroonedBoxesAfterUnlock
testBatchedPayoutEqualsPerSpinExpectation_Tier1
testBindingConsistencyDailyDrain
testBoundaryLevel5RoutesToWriteKey
testBoundaryLevel6RoutesToFFKey
testBoundaryRoutingAtDeployment
testBoundaryRoutingAtNonZeroLevel
testBountyEarnedZeroSkipCreditsNothing
testBountyEligibleTruthTable
testBurnieClaimLeavesClaimablePoolUnchanged
testCancelledSubFundingWithdrawable
testChurnSameDayAccruesSlot0Once
test_claimedTrackingAccumulates
test_claimWindowMovesWithLevel
testColdMarginalCalibration
testConstructorFFTicketsDrain
testCrankBoxOpenStaysPostUnlock
testCrossingEvictionStillEvictsOutgrownPass
testCrossingPassHolderRefreshedNotEvicted
testD09Gas0104RegressionLocks
testD11DeityHolderBypassesPassGate
testD11DeityHolderSubscribesAtLevelZero
testD11FinitePassCoveringCurrentLevelSubscribes
testD11RealPassSubscribesAtLevelZero
testD12ActiveResubAlreadyGroundedNoRevert
testD12FundedEoaSubscribes
testD13SdgnrsExemptSubscribesNoPassUnfunded
testD13VaultExemptSubscribesNoPassUnfunded
testD13VaultSdgnrsExemptAtLevelZero
testDegeneretteFreezeResolutionEthConserved
testDegeneretteFreezeResolutionZeroPendingReverts
testDegeneretteResolveBelowGateUnpaid
testDegeneretteResolveFlatRewardRoundTripNonPositive
testDegeneretteResolveWwxrpExcludedFromGate
testDegeneretteResolveZeroReverts
testDgnrsAwardStaysPerSpin
testDoubleClaimPaysExactlyOnceCEI
testDrainAffiliateBaseReachableFromAffiliatePath
testDrainAffiliateBaseStubAffiliateOnly
testEdge01NoDoubleCount_FFThenWriteKey
testEdge02RoutingPreventsNewFFDeposits
testEthCapBindsOnIdenticalSpin_Tier2
testEthCreditPathIsDeterministicNoVrfWord
testEthWinningsAlwaysLandInClaimable
testEvictFinalizeMarginal
testFarFutureRoutesToFFKey
testFFDrainOccursDuringPhaseTransition
testFFDrainSequentialByTransition
testFinalizeHookA_ExplicitCancelBeforeTombstone
testFinalizeHookC_PassEvictBeforeRemove
testFinalizeHookD_FundingKillBoundaryKeptAndZeroed
testFreezeUnfreezeRoundTrip
testFrozenSolvencyRevertsOnIdenticalSpin_Tier2
testFuzz_RngLockDeterminism_RetryLootboxRng
testFuzz_RngLockDeterminism_StakedStonkRedemption
testGameoverAdvanceUnrewarded
testGameOverDrainsQueuedTickets
test_gapBackfillSingleDayGap
test_gapDaysSkipResolveRedemptionPeriod
test_gap_gnrus_propose_vote_paths
testGapResetOnResumeRebasesTheRun
testGteThreeNonWwxrpPaysExactlyOneFlat
test_HERO06_WriteBatchByteIdentical_DGAS
test_HERO_DgnrsThresholdsRemapped
test_HERO_S8S9PackingDecodable
test_HERO_S9EqualsOldM8Jackpot
test_HERO_ScoreFormula
testJackpotPhaseTicketsProcessedFromReadSlot
testJackpotPhaseTicketsRouteToCurrentLevel
testLastDayTicketsRouteToNextLevel
testLazyPassHorizonReadDoesNotPerturbFrozenSlots
testLive01AfkingFirstOrdering
testLive01DrainAfkingBoxesSelectorIsolation
testLive01DrainBothCursorsBoundedNoDoubleOpen
testLive01IndividualOpenPathByteUnchanged
test_lootboxBoonAppliedDespiteExistingCoinflipBoon
testLootboxFarRollTicketsRouteToFF
testLootboxNearRollTicketsProcessed
testLootboxSummedPerBetIdNotAcrossBets
testMidDayPartialDrainRewardedViaMintBurnie
testMidDayProcessesReadSlotFirst
test_midDayRequest_doesNotBlockDaily
testMidDayRevertsNotTimeYet
testMidDaySwapAtThreshold
testMidDaySwapJackpotPhase
testMintDivCrossPathEquality_OwedSplitsAcrossSlices
testMixedWwxrpAndNonWwxrpPaysAtGate
testMultiDayAccumulatorPersistence
testMultiLevelAdvancementWithFFTickets
testNearFutureRoutesToWriteKey
testNonCrossingPassHolderProcessedWithoutRefresh
testNoOrphanPendingBoxSubUntouchedByStage
testOneOrTwoNonWwxrpCommittedUnpaidNoRevert
test_orderIndependence
testPackedPoolSlotsUnshifted
test_parametricAutoBuy_crossCategoryBoonFromLootbox
testPerBuyLootboxMarginal
testPerBuyTicketMarginal
testPerOneSpinItemMarginalBelowWorstCase
testPerOpenMarginal
test_PFIX02_RealisticRun_ClosingSweepIsDust
test_PFIX03_EarlyDgnrsRunEmptiesPoolBeforeClose_ClampHolds
test_PFIX03_TierShapePreserved
testPrepareFutureTicketsRange
test_proportionalDistribution
testPurchasePhaseTicketsProcessed
testQueueAfterSwapUsesNewWriteKey
testQueueTicketRangeUsesWriteKey
testQueueTicketsScaledUsesWriteKey
testQueueTicketsUsesWriteKey
testRangeRoutingSplitsCorrectly
testReactivateTombstonedSubNoDoubleAdd
testReResolveResolvedBetRevertsNoSecondReward
testResidualR1StageWeightModelFidelity
testResidualR2HeaviestTicketEntry
testResidualR3MixedStampDayOpenBatch
testResidualR4HeaviestPerIterState
testResolutionDeltasIndependentOfRewardGate
testResolveBetsRevertsPostGameOver_InsolvencyReproClosed
testResultsEqualityValueInvariant
test_retryLootboxRngRescuesStalledMidDay
test_revertBelowMinScore
test_revertDoubleClaim
testRngGuardAllowsWithBypass
testRngGuardIgnoresNearFuture
testRngGuardRangeRevertsOnFirstFFLevel
testRngGuardRevertsOnFFKey
testRngGuardScaledRevertsOnFFKey
testRngLockedBlocksFFLootbox
testRngLockedBlocksFFPurchase
testScaledFarFutureRoutesToFFKey
testScaledNearFutureRoutesToWriteKey
testSlot0FieldOffsets
testSolvencyHoldsBuyThenBurnieClaim
testStageResetGateReopensProcessingPerDay
test_stallSwapResume
testStampedDayOpenAtTwoBlocksByteIdentical
testStandaloneAutoOpenEscapeUnrewarded
testStreakDecaysToZeroAfterOneMissedFundedDay
testSubscribeMinBuyStampsNoInlineResolve
test_SWAP08_BaseFractionBelowFarTicketPresentEv
test_SWAP08_NoArbAtCeiling_SweepAllDistances
test_SWAP09_ArrayBound
test_SWAP09_EthFloorEnforced
test_SWAP09_SolvencyAcrossSwap
test_SWAP09_SwapPopMembershipMaintained
test_SWAP09_TicketFloorEnforced
test_threeAffiliatesProportional
testThreeWwxrpOnlyResolvedUnpaidNoRevert
test_timeoutRetry_12h
test_totalClaimsLeAllocation
test_totalClaimsMatchPoolDelta
testVaultPerpetualTicketsRouteToFF
test_vrfLifecycle_levelAdvancement
test_wallClockDayAdvancesDuringStall
testWhaleBundleTicketsAcrossLevels
testWorstCaseMixedCurrencyBatchGas
testWorstCaseResolveBet10SpinAllMatchFitsBlockGasLimit
testWorstCaseResolveBet25SpinAllMatchFitsBlockGasLimit
testWorstCaseStageChunkUnderBudget
testWriteReadIsolation
testWriteSlotIsolationAcrossBufferStates
testWriteSlotIsolationDuringRngLocked
testWriteSlotSurvivesSwapAndFreeze
testWwxrpKeeperEarnsZeroReward
testZeroResolvedRevertsNoWork
testZeroStrandingAutoBuyAfterTransitions
```

## 4. Bucket characterization (carried from v56/v57 where names overlap)

Failure-reason histogram (the `[FAIL: …]` first token, counted over the 183 raw failures):

| count | reason token | bucket |
|------:|--------------|--------|
| 42 | `panic` | B (wrong-slot `vm.store` storage corruption — underflow/index/enum) |
| 34 | `E()` | B (storage-foundation custom error — stale slot / queue state) |
| 26 | `non-vacuity` | A/B (assertion guards — VRF-window + slot-shift) |
| 26 | `BatchAlreadyTaken()` | B (ticket/jackpot fixture state) |
| 24 | `InvalidBet()` | B (Degenerette — cross-check vs AFPAY `_collectBetFunds` afking tier) |
| 14 | `marginal non-vacuity` | gas-marginal calibration (the 6 slot-hardcoded gas harnesses) |
| 12 | `fixture` | B (harness setup) |
| 8 | `Error != expected error` | A/B (revert-reason flip — RNG-window / behavior) |
| 6 | `VRFPath` | A (VRF/RNG-window) |
| 6 | `LEVEL-0` | B (D-11 level-0 subscribe boundary) |
| 4 | `vm.assume rejected too many inputs` | A (fuzz exhaustion — non-deterministic) |
| 4 | `rngLockedFlag should be true` | B (slot-shift — poked the wrong flag bit) |
| 4 | `_latchGameOver` | B (gameOver flag slot) |
| — | long tail | A/B (Mid/Zero/Write-key/WHALE/TST-03/v55) |

Three coarse buckets (per the v56/v57 precedent):
- **Bucket A — VRF / RNG-window / fuzz-exhaustion (non-deterministic).** Run-variance reds
  (VRFPath, `vm.assume` exhaustion, RNG-window guards). Membership fluctuates run-to-run; these
  are NOT deterministically attributable to a contract change.
- **Bucket B — stale-harness / slot-shift / behavioral.** The dominant class — slot-hardcoded
  `vm.store`/`vm.load` harnesses + fixtures asserting prior behavior. `panic` + `E()` +
  `BatchAlreadyTaken` + the routing/queue family. The v61 −1 shift will MOVE membership within
  this bucket at HEAD (recalibration narrows it), but the NAMES are the ceiling.
- **Bucket F — flaky invariant.** The pre-existing `DegenerusQuests`/`DegeneretteBet` solvency
  invariant flakiness (red at multiple prior baselines; harness stale-slot, not solvency).

**Solvency floor check (decisive, per v57 §2):** grepping every baseline `[FAIL: …]` reason for
`solvenc|conservat|insolven|obligation|underflow(accounting)|claimablePool < ` over the 183
failures returns no accounting-insolvency red outside the known Bucket-F flaky invariant — the
SOLVENCY-01 hard floor is not breached at the baseline (it is re-proven empirically at 378-05).

## 5. NARROWINGS already realized by 378-01 (recalibration → GREEN at HEAD)

Two StorageFoundation names in the §3 union are already turned GREEN at v61 HEAD by the 378-01
recalibration (a NON-WIDENING NARROWING, allowed):
- `testSlot0FieldOffsets` — baseline red ("ticketWriteSlot not at slot 0 offset 28"); the v61
  fold added `presaleOver`+`subsFullyProcessed` bools, shifting the slot-0 flags down 2 byte
  positions. Recalibrated to offsets 26/27/24 (bit 208/216/192) → GREEN at HEAD.
- `testPackedPoolSlotsUnshifted` — baseline red; slot 2 / slot 11 are authoritative-correct at
  v61, so it passes at HEAD with no change. (StorageFoundation 24/24 GREEN at HEAD post-378-01.)

The 4 redemption harnesses (`StakedStonkRedemption`, `RedemptionGas`, `RedemptionStethFallback`,
`RedemptionInvariants`) are GREEN at v61 HEAD post-378-01 (the `balancesPacked` root stayed at
slot 7; the low-128 semantic fix preserves the afking half). None of their names that appear in
§3 (e.g. `testFuzz_RngLockDeterminism_StakedStonkRedemption`) widen at HEAD.

## 6. Hardhat behavioral baseline — DOCUMENTED LIMITATION (corroborating, non-fatal)

The plan calls for capturing the deterministic Hardhat suite (`npm test`, excluding the
probabilistic `npm run test:stat`) at the `2bee6d6f` baseline as a corroborating behavioral
ceiling. **`npm test` could not complete in this autonomous environment** and the limitation is
recorded here (the forge baseline in §1-§5 is the PRIMARY TST-06 ceiling; the Hardhat baseline
is corroborating only and is never a reason to fail the foundation).

Findings during the attempt:
- `npx hardhat compile` at the `2bee6d6f` baseline subject **succeeds** (66 files, evm paris;
  the same compile that regenerates `contracts/ContractAddresses.sol` — repaired by the
  `git checkout HEAD -- contracts/` restore, contracts/ fingerprint re-verified `fcdd999c…`).
- `npm test` **aborts before running any test** with
  `Error: Cannot find module '…/test/adversarial/*.test.js'` (`MODULE_NOT_FOUND`). The npm
  `test` script globs `test/adversarial/*.test.js`, but `test/adversarial/` is **absent from
  the working tree and from git** at both `2bee6d6f` and HEAD (not gitignored — simply not
  present in this checkout). Mocha's glob expansion fails on the missing directory and the whole
  invocation exits non-zero before loading any spec. This is an **environment/repo-state
  limitation, not a baseline-specific or v61-specific defect** — it would affect HEAD identically.
- `npm run test:stat` (chi²/EV distribution tests) is **excluded** from the non-widening ceiling
  by design (probabilistic); it is characterized separately and is not part of this baseline.

**Disposition.** The Hardhat behavioral baseline is deferred to whenever the `test/adversarial/`
specs are restored to the working tree (or the `test` script is invoked with an explicit spec
list that omits the missing glob). Until then, 378-05's TST-06 gate runs against the **forge
baseline ceiling (§3)** as the primary and sufficient non-widening reference, per the plan's
explicit "forge baseline is the PRIMARY ceiling, Hardhat is corroborating" allowance. The v61
behavioral surface (TST-01..06 + SEC-01/02) is PROVEN by the new forge proving tests authored in
378-03/378-04/378-05, independent of the Hardhat behavioral baseline.

---

**Subject restored.** `git diff HEAD -- contracts/` empty; contracts/ fingerprint
`fcdd999ce2ddb0cac9e04b49242522b896cf56c67c18e213cd0f6dd5b6aa8aaf`; `forge build` clean on the
v61 HEAD subject. This baseline is the frozen ceiling for the 378-05 TST-06 non-widening gate.

---

## 7. TST-06 FINAL VERDICT — NON-WIDENING HOLDS (folded from 378-05, 2026-06-07)

The 378-05 TST-06 gate ran the FULL forge suite at the v61 working HEAD against this §3 ceiling.
Full ledger: `.planning/phases/378-tst-proving-tests-rng-freeze-solvency/378-05-NONWIDENING-LEDGER.md`.

- **Live HEAD: 711 passed / 66 unique failing NAMES / 103 skipped** (clean forge cache).
- **`UNION` = 172 (§3 BASE) ∪ 3 (378-03 class-(c) candidates C-1/C-2) ∪ 3 (carried VRFPath
  invariants) = 178 names** (deduped).
- **`live − UNION == ∅` BY NAME → NON-WIDENING HOLDS.** The 66 live reds = 60 carried §3 + 3
  documented class-(c) + 3 carried VRFPath bucket-A invariants. **112 baseline names narrowed to
  GREEN** (the 378-01/02/03 recalibration). **54 new proving tests** (TST-01..05) additive green.
  ZERO new v61 contract regression; NO `## CONTRACT-CHANGE-NEEDED`.

**§3-union scope correction (the only addition this verdict makes):** the §3 enumeration scoped to
`test*` NAMES and omitted the `invariant_*` family. Three VRFPath stateful-fuzz invariants —
`invariant_allGapDaysBackfilled`, `invariant_rngUnlockedAfterSwap`, `invariant_stallRecoveryValid`
(`test/fuzz/invariant/VRFPathInvariants.inv.t.sol`) — appear in the live HEAD set. They were
surfaced out-of-union by the gate, then **PROVEN PRE-EXISTING at `2bee6d6f`**: a non-destructive
checkout of the full `2bee6d6f` test tree + contracts reproduced the SAME 3 invariant failures with
byte-identical messages (`Suite result: FAILED. 4 passed; 3 failed`). They are carried bucket-A
non-deterministic reds (the §4 Bucket-A class; the v61 diff touches no VRF-swap / gap-backfill /
rngLocked logic — that lives in `DegenerusGameAdvanceModule`, untouched). Added to the union as
CARRIED with that evidence, NOT widened-to-hide-a-regression. (A VRFPathHandler slot-stale
hypothesis was investigated — recalibrating the handler's `dailyIdx`/lootbox-word reads to the v61
layout did NOT change the outcome, and the baseline reproduces with its own handler — so the reds
are a genuine pre-existing ghost-counter property; the handler probe was reverted byte-clean.)

**Hardhat:** `npm test` cannot complete (the `test/adversarial/*.test.js` glob is absent at both
baseline and HEAD → `MODULE_NOT_FOUND` before any spec loads — the §6 documented limitation, env-
not-v61). The runnable `test/unit` subset ran at HEAD (930 passing / 67 failing / 3 pending; the 67
are pre-existing affiliate-cap / pool-split / roll / access-control families, NOT the v61 contract
surface, none accounting-insolvency or RNG-freeze). Corroborating only; the forge by-name verdict is
PRIMARY. Comparison is BY NAME, never by count (T-378-05-02).

**Contracts byte-frozen:** tree-hash `87e3b45b46879ec80c4fe6a689b4c17ccae482f1` / fingerprint
`fcdd999ce2ddb0cac9e04b49242522b896cf56c67c18e213cd0f6dd5b6aa8aaf` preserved; `git status
--porcelain contracts/` empty; the non-destructive baseline checkout HARD-restored to HEAD.
