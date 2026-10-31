# Critical properties and evidence

Each row gives a property, the implementation symbols that enforce it, and test assertions that
check it (`file::function`, with the assertion message where one exists). A cited test is a starting
point for review, not proof that the property holds in every state.
[Source hashes](audit/source-sha256.txt) identify inputs, not test outcomes. Run instructions are in
[Testing](TESTING.md).

Paths: contracts under `contracts/`, tests under `test/`. `Storage` is
`contracts/storage/DegenerusGameStorage.sol`.

## RNG

### Commitment before request

The request seals its input cohorts before asking for their word; later purchases join the next
cohort. Some payouts still read live pool balances and prices at settlement.

- **Implementation.** `DegenerusGameRngModule.requestDailyRng_g8190`: `_rngPrepareRequestBoundary`,
  `_swapTicketSlot`, `_swapFoilSlot`, `_sealHeroWagers`, `_freezePool`, `_sealRngWriteBuffer`
  (`Storage._swapRngBuffers`, `_closeRedemptionBatch`), then `_setRngRequest(_requestVrfWord(…))`.
  Mid-day: `_requestLootboxRng` swaps the ticket slot (nonempty, processed queue) and calls
  `_sealRngWriteBuffer` before the coordinator call. A refused request reverts its worker call;
  the miner preserves any earlier progress.
- **Tests.**
  - `test/repro/MiddaySwapJackpotCohort.t.sol::testBuyAfterMiddayRequestIsFrozenOutOfThatWord` ("the
    mid-day drain must never consume the write side: the post-request buy is frozen out of the
    word")
  - `test/fuzz/RngIndexDrainBinding.t.sol::testBindingConsistencyMidDayCrossDay` ("box B leaked onto
    the in-flight index N")
  - `test/fuzz/RngFreezeAndRemovalProofs.t.sol::testPlacementNeverBindsToAWordedIndex` ("the bet
    binds to the unworded write buffer")
  - `test/fuzz/HeroWagerCommitmentIntegration.t.sol::test_LateWagersAcrossSeveralDaysAllEnterNextCommitment`
    ("all four late bets enter next frozen draw")
  - `test/fuzz/FoilGenerationCohort.t.sol::test_NewBuyAfterCommitWaitsForFreshCohort` ("later buy
    cannot use public word"; harness commit, not the full request path)
  - `test/fuzz/invariant/RngWindowFreeze.inv.t.sol::invariant_inWindowSloadsFrozen` ("RNG-FREEZE: a
    player action inside the VRF window mutated an enumerated consumed slot")
  - Degenesis: `test/fuzz/DegenesisWordBinding.t.sol`

### Callback authority

`rawFulfillRandomWords` accepts a word only from the stored coordinator and only for the retained
nonzero low-64-bit request ID; there is no active-flag check.

- **Implementation.** `GameFacade.rawFulfillRandomWords` (`OnlyCoordinator` revert; silent return on
  ID 0 or mismatch; raw words 0 and 1 ignored). `Storage._setRngRequest`, `_endRngSession` (keeps
  the answered ID), `_clearRngRequest` (sets ID 0); `_boundedVrfRequest` refuses a zero low-64 ID.
  Duplicate-delivery trust: [Security](../SECURITY.md#vrf-callback-trust-and-request-ids).
- **Tests.**
  - `test/fuzz/VRFCore.t.sol::test_callbackReverts_unauthorizedSender` (`expectRevert
    OnlyCoordinator()`)
  - `test/fuzz/VRFCore.t.sol::test_callbackNeverReverts_staleId` ("Stale ID should not change
    state")
  - `test/fuzz/VRFCore.t.sol::test_lateSupersededFulfillmentIgnored` ("superseded answer ignored
    while the retry waits", "superseded answer never fills a later request")
  - `test/fuzz/RngTransportCommitmentModel.t.sol::test_InactiveRetainedIdentityCannotAcceptCallback`
    ("retained id alone grants no callback authority"; ID 0 after `_clearRngRequest`, against a test
    mirror of the facade callback)
  - `test/fuzz/VRFCore.t.sol::test_coordinatorAnswersEachRequestOnce` ("the delivered word stands";
    the mock coordinator refuses a second delivery)
  - `test/fuzz/VRFCore.t.sol::test_secondAnswerToConsumedRequestOverwritesOnlyTheSessionWord`
    ("recorded day word unchanged"): documents that the Game itself would accept a second answer to
    a consumed ID, overwriting only the session word
  - `test/fuzz/VrfSwapReissueZeroId.t.sol::test_zeroLow64Id_refusesTheSwap_thenRetrySucceeds`

### Word-to-consumer binding

A daily word is applied once, to the day it was requested for; mid-day words are never recorded as
daily words.

- **Implementation.** `DegenerusGameAdvanceModule.applyDailyWord_g1652` (reverts when
  `_recordedDailyWord(rngRequestDay) != 0`); `DegenerusGameRngUtils._applyDailyRng`;
  `Storage._recordDailyRng` (two-slot ring tagged by `rngDayTags`; copies `degenesisWord` for the
  bound cohort); `GameFacade.rngWordForDay`; mid-day words go only to the session buffer
  (`_finalizeLootboxRng`).
- **Tests.**
  - `test/repro/StaleBufferedDailyWordClamp.t.sol::test_bufferedDailyWord_resolvesRequestDayOnly`
    ("request day resolved with its own raw word", "buffered word NOT reused for day D+1")
  - `test/fuzz/StallDaysNeverHappened.t.sol::test_LateEntropyCannotRescueExpiredProgressDeadline`
    ("expired normal result is never applied")
  - `test/fuzz/DegenesisWordBinding.t.sol` ("word copied at recording")
  - `test/repro/DailyWordAppliedOnce.t.sol::test_SecondApplicationOfARecordedWordReverts` (second
    apply through the Game's own delegatecall reverts `E()`; "recorded word unchanged", "coinflip
    result unchanged"), `::test_RecordedWordStateIsTheApplyFrontier` ("the miner selects DailyPhase,
    never DailyApply, once the word is recorded"), `::test_NoExternalDoorReachesTheApply`,
    `::test_EngineAppliesEachDailyWordOnce` ("day D applied once", "day D coinflip resolved once")

### Nudges affect only the coinflip word

- **Implementation.** `_applyDailyRng` returns `coinWord = word + nudges` for
  `Coinflip.processCoinflipPayouts` and records the raw word; `_clearAppliedNudges`; `RNG_NUDGE_CAP
  = 255`; `reverseFlip` reverts while `rngLockedFlag` is set. The mid-day path applies no nudge.
- **Tests.**
  - `test/fuzz/RngCurrentSentinel.t.sol::testFuzz_FinalWordPreservesEntropyOrRemainsPending` ("coin
    word adds the nudges", "recorded day word stays raw")
  - `test/fuzz/RngCurrentSentinel.t.sol::testFuzz_OnePaidReverseAlwaysFlipsTheDailyCoin` ("every
    other consumer reads the raw word", "one paid reverse always toggles the day's result")
  - `test/fuzz/MiddayRngCredit.t.sol::test_MiddayCallbackStoresSharedWordWithoutApplyingDailyNudges`
    ("midday word is unchanged", "daily nudge remains pending")

### Retry and re-issue keep the cohort

- **Implementation.** `DegenerusGameRngModule.retryRng` (Admin only; `_rngRetryDue`: active,
  waiting, unspent, `RNG_RETRY_TIMEOUT = 20 hours`): `_spendRngRetry` and `_setRngRequest` only; no
  swap or seal; `rngRequestTime` unchanged.
  `DegenerusGameGameOverModule.updateVrfCoordinatorAndSub`: re-issues only an undelivered request
  (`rngWordCurrent == RNG_WORD_WAITING`), spends the retry under the daily lock, leaves
  `rngRequestTime` and nudges; after game over or the dead latch it only repoints the configuration.
- **Tests.**
  - `test/fuzz/RngTransportCommitmentModel.t.sol::testFuzz_RetryPreservesCommitmentAndRejectsStaleResponse`
    ("same original timeout origin", "same day/kind/nudges/cohort"; the module's `retryRng` on
    seeded harness state)
  - `test/fuzz/VRFStallEdgeCases.t.sol::test_CoordinatorSwapPreservesDayCohortAndProgressOrigin`
    (real swap)
  - `test/fuzz/VRFStallEdgeCases.t.sol::testFuzz_CoordinatorSwapPreservesNudges`
  - `test/fuzz/VRFStallEdgeCases.t.sol::test_RetryKeepsCommitmentAndCannotRefreshHardDeadline`
  - `test/fuzz/HeroWagerCommitmentIntegration.t.sol::test_MiddayRequestRetryAndCallbackDoNotRotateHeroPools`
    ("midday retry leaves hero pools intact")
  - `test/fuzz/VRFCore.t.sol::test_sameCoordinatorReissueIgnoresSupersededRequest`

## Mining engine

### Chunking and gas preserve committed draw outcomes

Caller gas and multiplier select how much work a call admits; committed draw outcomes remain the
same. Mining rewards depend on gas spent per call.

- **Implementation.** `GameMiner` (`mineRun`), `MineFlipGas` (`canRun`, `child`, `markProgress`),
  persistent cursors (`boxCursor`, `degeneretteCursor`, `foilCursor`, `jackpotWork`, Degenesis and
  Decimator cursors). Per-consumer seeds use positions, never gas or call counts ([RNG
  domains](audit/RNG-DOMAINS.md)).
- **Tests.**
  - `test/fuzz/DegenesisSettlement.t.sol::test_PartitionInvariance` ("same count"),
    `::test_InterleavedActivityDoesNotChangeRewards`
  - `test/fuzz/JackpotBattleDraw.t.sol::testFuzz_CircularVisitsMatchOracleAcrossChunkSizes`
  - `test/repro/MineFlipWorkerBudget.t.sol::test_ZeroAndExplicitBaselineProduceSameBoxOutcome`
  - `test/fuzz/MinerNoProgress.t.sol::test_LapsedRefundsMatchAcrossGasLimitsIncluding167M`
  - `test/fuzz/BafStagedResume.t.sol::test_MidwayResumeWithAnyAllowancePaysTheSameAwards`,
    `::testFuzz_AllowanceLadderMatchesOneCall`;
    `test/fuzz/BafStagedTranscript.t.sol::test_OneGroupPerCallMatchesOneCall`
  - `test/fuzz/MintModuleDivergenceAcrossSplit.t.sol::testMintDivCrossPathEquality_OwedSplitsAcrossSlices`
  - Whole days:
    `test/repro/WholeDayChunkingIndependence.t.sol::testFuzz_OneDayChunkedEqualsLargeCalls`,
    `::testFuzz_ThreeDaysChunkedEqualLargeCalls` ("the chunked run diverged from the large-call
    run"): from one snapshot of a mature game, an unpaid miner's one-unit minimum-gas calls and 1e9-gas
    minimum-calibration calls end with every written storage slot and touched ETH balance equal,
    except sDGNRS `_settlingReserveLeft`, a between-calls scratch field that is dead once its batch
    completes

### Every mining checkpoint is bounded

- **Implementation.** `contracts/libraries/MineFlipGasBounds.sol` (declared cold-path bounds);
  `MineFlipGas.canRun` admission against remaining allowance and available gas, with the checkpoint
  and return tail.
- **Tests.**
  - `test/gas/RoundDrainChunkGas.t.sol::test_Chunk_AllRounds_Cold` (helper `_oneChunk`: "chunk
    overran its declared reservation" bound and the 10M target)
  - `test/gas/TicketDrainWorstCaseBound.t.sol::test_CanonicalTicketStepsFitSizingTargetIncludingCheckpoint`
  - `test/gas/AdvanceGasCeilingFuzz.t.sol::testFuzz_advanceGame_everyTxUnderCap`
  - `test/gas/DeadVrfEndingGas.t.sol::test_ColdDeadVrfBatchFits11_5M`
  - `test/repro/MineFlipGasAdmission.t.sol::test_ChunkCannotConsumeTheCheckpointTail`,
    `::test_ActualSpendingStopsTheNextChunkAtItsCheckpoint`
  - Jackpot battle: `test/gas/JackpotBattleStageGas.t.sol`, `test/gas/JackpotBattleDrawGas.t.sol`,
    `test/gas/JackpotBattleAwardsGas.t.sol`
  - Gas-admission evidence and its limits: [Testing](TESTING.md#test-selection)

### Mining admission and worker failures

`mineRun` rejects invalid gas multipliers, initial idle/wait states and insufficient initial
execution gas. Request refusals return without reverting earlier work; recognized checkpoint
refusals preserve a completed prefix. Other worker failures propagate. Workers report progress
through `MineFlipGas.Result`.

- **Implementation.** `GameMiner` (dispatch and `MineFlipGas.Result`), `BoundedCall.admitFirst`.
- **Tests.**
  - `test/repro/MineFlipGasSweep.t.sol::test_SweepFromPublish`, `::test_SweepFromDailyPhase`,
    `::test_SweepFromSealingDailyPhase` (helpers `_sweep`: "never WorkGasBound"; `_fullSweep`: "near
    the cap every call succeeds")
  - `test/fuzz/invariant/CrapsRngSeal.inv.t.sol::invariant_keeperNeverReverts` ("CRAPS-KEEPER: a
    mineFlip Craps worker reverted")
  - `test/fuzz/LootboxBudgetResume.t.sol::test_smallBudgetOpensOneEntryPerCallAndDrainsTheIndex`,
    `::test_budgetThatFitsOneEntryRefusesTheSecond`
  - `test/fuzz/invariant/AnyInputSafety.inv.t.sol::invariant_anyInputSafety` (liveness clause under
    a 16.7M per-call cap)
  - Terminal-loan no-revert obligations: [Account loans](ACCOUNT-LOANS.md#settlement-at-game-over)
  - `test/fuzz/BoxOpeningNeverReverts.t.sol::testFuzz_BoxOrdersOpenWithoutRevertAtLaunch`,
    `BoxOpeningNeverRevertsMatureTest::testFuzz_BoxOrdersOpenWithoutRevertAtAMatureLevel` ("box
    opening reverted on its inputs", "every bought box was opened"): one to three real orders of any
    accepted kind, quantity and custom size, with fuzzed score code, boost and distress bit inside
    the writers' domains and a fuzzed word, opened by 16,777,216-gas mineRun calls at level 0 and at
    a mature level

## Ending

### Terminal ordering and deadlines

- **Implementation.** `Storage._endingReason`, `_livenessTriggered`, `_vrfDeadmanFired`
  (`lastDailyCompletedAt + _VRF_DEAD_TIMEOUT`), `_vrfDead` (unpublished request, `rngRequestTime +
  _VRF_DEAD_TIMEOUT`), `_PURCHASE_TIMEOUT_DAYS = 30`, `_VRF_DEAD_TIMEOUT = 14 days`,
  `_nextMinerAction` (sweep at `GO_TIME + 30 days`). `DegenerusGameGameOverModule`: terminal entry
  (latch, loan step), `_handleGameOverDrain`, `_finishTerminalPayout` (stamps `GO_TIME`),
  `_handleFinalSweep` (`goTime + 30 days`, once). The final-sweep delay is the literal `30 days` in
  both places, not a named constant.
- **Tests: 14-day hard stall.**
  - `test/fuzz/DeadVrfEnding.t.sol::test_stallAcrossDeadlineWaitsForTheVrfDeadWindow` ("14 days
    unanswered"; boundary at `sent + 14 days − 1`)
  - `test/fuzz/DeadVrfEnding.t.sol::test_retryBitKeepsTheWindowAndTheDay`,
    `::test_middayRequestUnansweredFourteenDaysIsDeadAndStaysLatched`
  - `test/fuzz/StallDaysNeverHappened.t.sol::test_LateEntropyCannotRescueExpiredProgressDeadline`
  - `test/fuzz/PurchaseDeadline.t.sol::test_FundedPhasesOnlyFaceFourteenDayHardDeadline`
- **Tests: 30-day purchase timeout.**
  - `test/fuzz/PurchaseDeadline.t.sol::test_BothLevelZeroAndLaterLevelsUseThirtyCompletedDays`
    ("completion window stays open for rescue")
  - `test/fuzz/PurchaseDeadline.t.sol::test_day31BlocksPurchaseAndSettlesGameOver` ("unfunded level
    ends after the 30-day deadline")
  - `test/repro/PurchaseTimeoutLateCompletion.t.sol::test_endsWithNextRequestUnanswered`
- **Tests: loan settlement before the terminal request.**
  - `test/fuzz/TerminalLoanSettlement.t.sol::test_ChunkedSettlementResumesAroundManualRepayment`,
    `::test_DeadVrfAtTheDecisionLeavesLoansUntouched`,
    `::test_HardDeadlineInterruptsTerminalLoanBookWithoutReversingPaidPrefix`
- **Tests: `GO_TIME` and the final sweep.**
  - `test/repro/TerminalPayoutCheckpoints.t.sol::test_SetupRunsOncePotIsPinnedAndTimerWaitsForFinalQuadrant`
    (`GO_TIME` zero after setup, set at payout completion)
  - `test/edge/GameOver.test.js` ("mineFlip before 30 days reports NoWork and preserves the
    unexpired claim window", "mineFlip after 30 days triggers final sweep path")
  - `test/fuzz/DeadVrfEnding.t.sol::test_claimsCloseAtTheFinalSweep`
  - `test/repro/FinalSweepBoundary.t.sol::test_OneSecondBeforeTheBoundaryNothingIsSwept` (GO_TIME
    stamped by a real hard-stall ending; at `+ 30 days − 1` the miner is Idle, the terminal phase
    itself does not sweep, a balance is still withdrawable), `::test_AtTheBoundaryTheSweepRunsOnce`,
    `::test_AtTheBoundaryTheTerminalPhaseSweeps`

## Accounting

The equations and per-phase transitions are in [Accounting](ACCOUNTING.md).

### Solvency: custody covers obligations

- **Implementation.** `Storage._untrackedYield` (obligation sum); `GameFacade.yieldPoolView`;
  post-game-over `claimablePool` only.
- **Tests.** `test/fuzz/invariant/EthSolvency.inv.t.sol::invariant_ethSolvency`,
  `::test_reconciliationDetectsMissingWei`;
  `test/fuzz/invariant/AnyInputSafety.inv.t.sol::invariant_anyInputSafety`,
  `::test_conservationDetectsMissingWei`;
  `test/fuzz/invariant/DegenesisSolvency.inv.t.sol::invariant_backingCoversObligations`,
  `::invariant_claimablePoolIdentity`;
  `test/fuzz/invariant/MultiLevel.inv.t.sol::invariant_solvencyAcrossLevels`;
  `test/fuzz/invariant/WhaleSybil.inv.t.sol::invariant_gameOverTerminal`. Full list in
  [Accounting](ACCOUNTING.md#obligation-equation).
- **Tests: the full `claimablePool` identity.** Balance words above their sentinels plus unsplit
  Degenesis volume, Vault budget, redemption reserve, staged BAF reservation and sealed Decimator
  rounds (`test/fuzz/helpers/ClaimablePoolIdentity.sol`):
  `test/repro/ClaimablePoolIdentityComposed.t.sol::test_IdentityHoldsThroughEveryReservation`
  ("claimablePool != balance words + every reservation", at action checkpoints and after every
  successful mining call of a game from the Degenesis deploy day through level 10 that observes
  every reservation live),
  `::test_IdentityIsFalsifiable`;
  `test/fuzz/invariant/AnyInputSafety.inv.t.sol::invariant_anyInputSafety` property (e) ("(e)
  CLAIMABLE IDENTITY"), also run by `AnyInputSafetyDegenesis.inv.t.sol`.

### Exactly-once reserve transfers

| Transfer | Implementation | Tests |
| --- | --- | --- |
| Degenesis cohort split | `DegenerusGameDegenesisModule._splitDegenesisCohorts` (`GD_SPLIT` flag), from `prepareDegenesis_g47` and `splitDegenesis` | `test/fuzz/DegenesisAccounting.t.sol::test_MissedCohorts_FrozenSplit_EmptyAndRepeatedProcessing` ("repeated processing adds nothing"); `test/fuzz/DegenesisBusyWeekIntegration.t.sol::testFuzz_BusyWeekExactlyOnceAndSolvent` (`_onSplit`: "each cohort splits once") |
| Vault budget and sDGNRS AFKing release | `DegenerusGameGameOverModule._handleGameOverDrain` (before `gameOver`; returns early once set) | `test/fuzz/DegenesisTerminal.t.sol::test_HardDeadline_AfterSale_ReleasesOnceIntoFinalPrizes` ("no second release"), `::test_DeadVrfEnding_DuringSale_SplitsThenReleasesOnce` |
| Vault budget spend | `spendDegenesis` (net move equals cost; `DegenesisMaxCostExceeded`) | `test/fuzz/DegenesisVaultSpend.t.sol::testFuzz_SpendLeavesNoCashout`; `test/fuzz/invariant/DegenesisSolvency.inv.t.sol::invariant_degenesisEthConservation` |
| BAF reservation | `runBafJackpot`, `runBafAwards`, `_releaseBafReserve`; game-over latch (`jackpotWork.kind == 7`) | `test/fuzz/BafStagedResume.t.sol::test_EmptyBracketReturnsTheWholeReservation` (`_checkResidue`: "claimablePool releases exactly the residue"); `test/fuzz/BafStagedGameOver.t.sol::test_LatchReleasesTheUncreditedReservationAndTheEndingDistributesIt` ("claimablePool releases exactly work.paid"); `test/fuzz/BafStagedSkip.t.sol::test_X0LosingFlipSkipsWithoutAStage` |
| Redemption reserve | `_closeRedemptionBatch`, `_releaseRedemptionReserve` | `test/repro/RedemptionReserve.t.sol::testSettlingReserveCountsOnceInBackingPreview`; `test/invariant/RedemptionAccounting.t.sol::invariant_INV_02_EthConservationExact` |

### Settled loans retire exactly once

A hard-stall ending leaves unsettled loans open; it does not reverse completed settlements or
settle the remaining loans later.

- **Implementation.** `GamePurchase._borrow`, `_repay` (`LOAN_RETAINED`, swap-pop of the due list);
  `DegenerusGameAdvanceModule._settleLoans`, `_autoRepayLoan`, `_settleTerminalLoans`;
  `DegenerusGameGameOverModule.seizeLoan`. Repayment and borrowing revert after game over.
- **Tests.**
  - `test/fuzz/TerminalLoanConservation.t.sol::testFuzz_SettlementMovesNoEth` ("each loan settles
    exactly once")
  - `test/fuzz/LoanSeizure.t.sol::test_ManyLoansSeizeAcrossBoundedChunks` ("each loan seized exactly
    once")
  - `test/fuzz/TerminalLoanSettlement.t.sol::test_ChunkedSettlementResumesAroundManualRepayment`
    ("manual repayment closes the loan once", "each remaining loan seized exactly once"),
    `::testFuzz_RandomBookSettlesOnceAtTheRepaymentPrice`
  - `test/fuzz/AccountLoans.t.sol::test_RepaidLoanIsNeverSeized`,
    `::test_GameOverClosesRepaymentOfALoanTheEndingLeftOpen`, `::testFuzz_DueListSwapAndPop`
  - `test/fuzz/invariant/LoanAccounting.inv.t.sol::invariant_closedLoansPaidSpecOrSeized`,
    `::invariant_ownershipAndDueLists`

## Player state

### AFKing days are never billed as missed

- **Implementation.** `DegenerusQuests._questSyncState` and `_effectiveBaseStreak` bill misses only
  when `state.afkingSince == 0`; `beginAfking` syncs (billing the pre-run gap) before setting
  `afkingSince`; `finalizeAfking(id, earnedStreak, afkingCoveredDay)` is idempotent, anchors
  `lastActiveDay` at the run's reward endpoint and clears `afkingSince`;
  `GameAfkingModule._finalizeAfking` passes `_afkingEndpoint()`.
- **Tests.**
  - `test/repro/AfkingMidRunShieldBurn.t.sol::test_MidRunManualActionBurnsNoShield` ("a mid-run
    manual action bills no run-covered day")
  - `test/repro/AfkingMidRunShieldBurn.t.sol::test_MidRunManualActionKeepsHighWaterAndGrantsNoCentury`
    ("mid-run high-water untouched by the manual action", "no re-granted century shields")
  - `test/repro/QuestStreakStallForgiveness.t.sol::test_FinalizeDeliveredAheadRetainsPreRequestCoverage`
    ("finalize is idempotent"), `::test_MissedLogicalDaysConsumeShieldsExactlyOnce`
  - `test/fuzz/V56QuestNonPerturb.t.sol::testStreakNeutralDuringAfkingSlot0`,
    `::testStreakNeutralIsGatedByAfkingActiveOnly`
  - Complement (outside a run, misses beyond shields decay against the Game day):
    `test/repro/QuestStreakRequestWindow.t.sol::test_LapsedStreakStaysDecayedInRequestWindow`
    ("window: decayed against the Game day")

### WWXRP claim window

Day `d`'s draw opens when word `d+1` is recorded and closes at the day-`(d+3)` daily request,
before a day-`(d+3)` entry can reuse day `d`'s storage bank.

- **Implementation.** `WWXRP._drawClaimOpen` (Game slot 0 bits 24..47 `dailyIdx <= d + 2`), with
  each caller's `rngWordForDay(d + 1) != 0`; callers `findWinningEntry`, `previewOutcome`, `claim`
  (reverts `WordUnavailable`).
- **Tests.**
  - `test/repro/WwxrpBankReuseTail.t.sol::test_ClaimWindowClosesAtDayPlus3RequestBeforeBankReuse`
    ("control claim paid on day d+2", "finder closed at the d+3 request", "preview closed at the d+3
    request")
  - `test/fuzz/WWXRPRecycling.t.sol::test_ClaimClosesAtDayPlusThreeRequestBeforeBankReuse`
    ("control: open on day d+2", "preview closed at the d+3 request")
  - `test/fuzz/WWXRPRecycling.t.sol::test_VrfStallCannotPayExpiredDrawOrNewDrawWithOldWord`

## Build profiles

### Storage layout identity across profiles

- **Implementation.** Both Game shells (`contracts/profiles/eip170/Eip170Game.sol`,
  `contracts/profiles/glamsterdam/GlamsterdamGame.sol`) inherit `DegenerusGameStorage`.
  `scripts/layout/storage_layout_oracle.sh` compares the Game, standalone state contracts and
  modules with `scripts/layout/golden/`; `scripts/layout/check_recursive_layout.py` compares every
  delegatecall module of the selected profile (from its deployment manifest) and the
  CrapsBattle/JackpotBattle pair with the shared layout, including nested members.
- **Tests.**
  - `test/unit/test_recursive_layout.py` (`test_expected_modules_come_from_deployment_registry` pins
    each profile's module set; checker self-tests for packed and nested member changes)
  - `test/fuzz/StorageSlotPins.t.sol::test_ProductionGameSlotConstants`;
    `test/fuzz/StorageFoundation.t.sol::testSlot0FieldOffsets`
  - Hosted CI, `.github/workflows/ci.yml` job `foundry-build`, step "Glamsterdam profile layout
    identity": selects the `glamsterdam` profile, builds `contracts/`, runs both layout gates on
    that build, and runs `check_recursive_layout.py --baseline forge-out-production`, which fails on
    any layout difference between the two profiles' builds for every contract they share
    (DegenerusGame, every Game and Craps delegate, Coinflip, the standalone state contracts)
