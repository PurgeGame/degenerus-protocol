# Accounting

The ETH/stETH accounting map by phase: who holds custody, the obligation equation, what is
reserved inside `claimablePool`, which functions move value, how the ending treats each item,
and which test asserts it. FLIP, WWXRP, sDGNRS supply and the comp allowance are not ETH obligations; units are in [Token units](TOKEN-UNITS.md) and
the separate ledgers in [Economic disclosures](../ECONOMIC_DISCLOSURES.md#accounting-and-value).

Test references are `file::function`; the quoted text is the assertion message.

## Custody

| Holder | Assets | Owed against it |
| --- | --- | --- |
| Game (`DegenerusGame`) | ETH balance plus stETH balance | The obligation sum below. Staking (`adminStakeEthForStEth`, `adminSwapEthForStEth`, `stakeExcessEth`) changes the asset mix, not the obligations |
| sDGNRS | Its own ETH and stETH, plus its Game claimable (above the sentinel) and the Game-held redemption reserve | Redemption claims. Live pricing uses Game backing only; token custody counts after game over (`sDGNRS._redemptionBacking`, `_liveMoney`) |
| Vault | Its own ETH/stETH, plus its Game claimable and prepaid AFKing | DGVE/DGVF share redemptions |
| GNRUS | Its own balances | Charity rules |
| Admin | A retired-subscription cancellation refund | Funds the replacement subscription |
| VRF coordinator subscription | Native ETH sent by `donateVrf` and `_refillVrfNative` | Fulfillment billing; not Game custody |

## Obligation equation

The Game sums its ETH obligations in one place, `_untrackedYield`
(`contracts/storage/DegenerusGameStorage.sol`):

```text
obligations = currentPrizePool + nextPrizePool + futurePrizePool
            + claimablePool + yieldAccumulator
            + pendingNext + pendingFuture          // frozen purchase buffer, prizePoolPendingPacked
custody     = address(game).balance + stETH.balanceOf(game)
yield       = max(custody - obligations, 0)
```

`GameFacade.yieldPoolView` reports the same set. The test helper
`test/fuzz/helpers/SolvencyObligations.sol` mirrors it: `backing(game)` is Game ETH plus stETH,
and `obligations(game)` is the sum above while live and `claimablePoolView()` alone once
`gameOver` is set. The pending buffer has no external view; the helper reads its slot (bit 255 is
the slot's nonzero sentinel, not value).

`claimablePool` is the aggregate of three kinds of item:

```text
claimablePool = Σ_id (claimable_id − 1 + afking_id)       // player and protocol balance words
              + unsplit Degenesis volume
              + degenesisVaultBudget
              + redemption reserve                         // _redemptionReserveStored − 1
              + staged BAF reservation                     // jackpotWork.paid while kind == 7
              + sealed Decimator round pool                // round.poolWei until paid or released
```

Every allocated wallet ID starts with a 1-wei claimable sentinel (`_registerWallet`,
`balancesPacked[id] = 1`) outside `claimablePool`. No path pays it; claims, repayment, sweeps, VRF
funding and AFKing top-ups all leave it. Only the final sweep takes it, at most 3 wei for the
protocol sinks. The low 128 bits of `balancesPacked[id]` are claimable; the high 128 bits are
prepaid AFKing funding.

| Assertion | Test |
| --- | --- |
| Custody covers obligations, live and post-game-over | `test/fuzz/invariant/EthSolvency.inv.t.sol::invariant_ethSolvency` ("ETH solvency violated: balance < obligations"); `test/fuzz/invariant/AnyInputSafety.inv.t.sol::invariant_anyInputSafety` via `_checkSolvency` ("(a) SOLVENCY: game ETH+stETH < obligations"); `test/fuzz/invariant/MultiLevel.inv.t.sol::invariant_solvencyAcrossLevels`; `test/fuzz/invariant/WhaleSybil.inv.t.sol::invariant_solvencyUnderPressure`; `test/fuzz/invariant/DegeneretteBet.inv.t.sol::invariant_solvencyUnderDegenerette`; `test/fuzz/invariant/VaultShareMath.inv.t.sol::invariant_gameSolvencyUnderVaultOps` |
| The custody oracle detects one missing wei | `test/fuzz/invariant/EthSolvency.inv.t.sol::test_reconciliationDetectsMissingWei` ("the oracle must see the missing wei"); `test/fuzz/invariant/AnyInputSafety.inv.t.sol::test_conservationDetectsMissingWei` ("oracle must see the wei") |
| ETH conservation across Game, Vault, sDGNRS, GNRUS and players | `test/fuzz/invariant/EthSolvency.inv.t.sol::invariant_balanceReconciliation` |
| A freeze-window purchase adds exactly its price to obligations | `test/economics/FoilClaimBatch.t.sol::test_freezeWindowObligationsAreExact` ("obligation of exactly the buy") |
| A stETH rebase changes custody, not obligations | `test/fork/ForkSteth.t.sol::test_positiveRebaseAccruesToTheGameAsYield` ("obligations unchanged", "a positive rebase restores strict solvency") |

The full `claimablePool` identity is asserted for the Degenesis terms (balance words, Vault
budget and unsplit volume) by `test/fuzz/invariant/DegenesisSolvency.inv.t.sol::invariant_claimablePoolIdentity`
("claimablePool != balance words + Vault budget + unsplit volume"), with a falsifiability check in
`::test_IdentityIsFalsifiable`. The identity with every reservation (balance words above their
sentinels, unsplit Degenesis volume, the Vault budget, the redemption reserve, the staged BAF
reservation and sealed Decimator rounds) is asserted after every action of a real game from the
Degenesis days to level 10 by `test/repro/ClaimablePoolIdentityComposed.t.sol::test_IdentityHoldsThroughEveryReservation`
(falsifiability: `::test_IdentityIsFalsifiable`), and as property (e) of
`test/fuzz/invariant/AnyInputSafety.inv.t.sol::invariant_anyInputSafety` ("(e) CLAIMABLE IDENTITY:
claimablePool != balance words + reservations"), whose Degenesis variant inherits it. A Decimator
round reserves its `poolWei` while sealed and, after ranking, `poolWei` less the part released to
the future pool and the ETH already paid to places.

## Pre-game and Degenesis (day indices 1–8)

Custody and the obligation equation are as above; the prize pools start empty. Degenesis adds
two reservations inside `claimablePool`.

| Transition | Function | Effect |
| --- | --- | --- |
| Box purchase | `DegenerusGameDegenesisModule.buyDegenesisBox_g1442` (`purchaseDegenesisBox`) | Pays from `msg.value`, then claimable, then AFKing; `claimablePool += amount` (unsplit volume). Overpay is credited to the payer's AFKing |
| Cohort split (once per cohort) | `_splitDegenesisCohorts`, from `prepareDegenesis_g47` at the daily request | Skips cohorts with `GD_SPLIT` set, then sets it. For quarters `q = V/4`: `claimablePool −= 2q`; future pool `+= q` (`_addPrizeContribution`); `yieldAccumulator += q`; `degenesisVaultBudget += q`; sDGNRS AFKing `+= q` |
| Vault budget spend | `spendDegenesis(recipientId, …)` (Vault owner, via `Vault.spendDegenesis`) | Moves `maxCost` from the budget into Vault claimable, runs the ordinary claimable-funded purchase for any allocated recipient (0 = Vault), returns the unspent part; the actual cost leaves the budget and `claimablePool` for the ordinary purchase pools. The Vault ledger returns to its prior balance |
| sDGNRS AFKing top-up | `topUpSdgnrsAfking_g318` | Reclassifies sDGNRS claimable (above its sentinel) into AFKing up to 10 ETH; `claimablePool` unchanged |
| Seventh close | `_closeDegenesisCohort` | sDGNRS AFKing above 10 ETH returns to its claimable (`DegenesisAfkingExcessClaimable`); remaining `Pool.Degenesis` sDGNRS is burned once |
| Credit accrual | Mint, Whale, foil and purchase spend sites | Degenesis credit is permission to spend, not an ETH obligation |

| Assertion | Test |
| --- | --- |
| Split is exact in wei at the first request after the cohort's day | `test/fuzz/DegenesisAccounting.t.sol::test_Split_ExactInWei_AtFirstRequestAfterItsDay`, `::testFuzz_Split_ExactInWei` |
| Repeated processing splits nothing twice | `test/fuzz/DegenesisAccounting.t.sol::test_MissedCohorts_FrozenSplit_EmptyAndRepeatedProcessing` ("repeated processing adds nothing"); `test/fuzz/DegenesisBusyWeekIntegration.t.sol::testFuzz_BusyWeekExactlyOnceAndSolvent` ("each cohort split once") |
| Unsplit volume stays reserved until its own split | `test/fuzz/DegenesisAccounting.t.sol::test_UnsplitVolumeStaysReservedUntilItsOwnSplit` |
| Budget conservation | `test/fuzz/invariant/DegenesisSolvency.inv.t.sol::invariant_degenesisEthConservation` ("Vault budget + spends + release != split volume / 4") |
| Solvency through the sale | `test/fuzz/invariant/DegenesisSolvency.inv.t.sol::invariant_backingCoversObligations` ("ETH + stETH < obligations") |
| Budget spend leaves no cashout; arbitrary recipients | `test/fuzz/DegenesisVaultSpend.t.sol::testFuzz_SpendLeavesNoCashout`, `::test_SpendTickets_ExactCost_SentinelMaxCostEqualsCost` |

## Live game

| Transition | Function | Effect |
| --- | --- | --- |
| Ticket, lootbox, pass purchase | Purchase, Mint, Whale modules (`_addPrizeContribution`) | Payment enters next/future pools, or the pending buffer while frozen; claimable-funded parts debit `claimablePool` |
| Daily freeze | `_freezePool` at the daily request; `_unfreezePool` at unlock | New pool contributions accumulate in `prizePoolPendingPacked` and fold back at unlock; the sum is unchanged |
| Jackpot and prize credit | Jackpot, JackpotDraw, Lootbox modules | Pool debit and `claimablePool` credit of the same amount |
| Claim | `GameActions._claimWinningsInternal` (`claimWinnings`, `claimClaimable`) | `claimablePool −= payout` before the transfer; stETH-first option |
| AFKing funding | `_creditAfkingValue`; `_withdrawAfkingFunding`; AFKing delivery (`GameAfkingModule`) | Prepaid funding enters `claimablePool`; delivery moves it into the pools |
| VRF funding | `_refillVrfNative` → `_topUpVrfNative` | Untracked yield first, then sDGNRS claimable (above the sentinel), then sDGNRS AFKing; each non-yield wei sent removes one wei of `claimablePool` |
| Yield distribution | `DegenerusGameJackpotModule._distributeYieldSurplus` | Distributes only `custody − obligations` |
| Redemption batch close | `DegenerusGameRngUtils._closeRedemptionBatch` at each request | Releases the previous reserve to sDGNRS claimable, then moves the batch's priced pull from sDGNRS claimable into the redemption reserve; `claimablePool` unchanged |
| Redemption settlement | `DegenerusGameLootboxModule.resolveRedemptionLootbox`, `creditRedemptionDirect` | Spend only from the reserve |
| Loan borrow | `GamePurchase._borrow` | Lender claimable `−principal` (`claimablePool −= principal`); ETH to borrower, ticket part (late purchase phase) to pools |
| Loan repayment | `GamePurchase._repay` (`clearDebtNow`), `DegenerusGameAdvanceModule._autoRepayLoan` | Lender credited; fresh ETH enters `claimablePool`; auto-repayment is an internal move |
| BAF reservation | `DegenerusGameJackpotDrawModule.runBafJackpot` (arm), `runBafAwards` (pay), `_releaseBafReserve` (residue) | The x0 consolidation moves the schedule's ETH term from `futurePool` into `claimablePool` and `jackpotWork.paid`; each group's credits reduce `paid`; the residue returns to the pending future pool |
| Decimator reservation | Advance Decimator block; `DegenerusGameDecimatorModule` (`claimablePool += funding`, `_releaseToFuture`) | The sealed pool `P` moves from `futurePool` into `claimablePool`; generated funding `F` moves from `currentPrizePool`; winners consume the reservation; unused parts return to `futurePool` |
| Account sweep | `GamePurchase._sweepAccounts` | Moves a subaccount's claimable into its owner's main balance; `claimablePool` unchanged |

| Assertion | Test |
| --- | --- |
| Repayment from claimable keeps the sentinel and the pool | `test/fuzz/AccountLoans.t.sol::test_RepayFromClaimableKeepsSentinelAndConservesPool` ("internal move") |
| Loan accounting | `test/fuzz/invariant/LoanAccounting.inv.t.sol::invariant_lenderLedger`, `::invariant_borrowPayout`, `::invariant_closedLoansPaidSpecOrSeized`, `::invariant_solvency` |
| BAF credits plus residue equal the reservation | `test/fuzz/BafStagedResume.t.sol::test_RealConsolidationArmsTheScheduleReserve` ("credits plus residue equal the reservation", "claimablePool releases exactly the residue"); `::test_EmptyBafSlotForfeitsToResidue` |
| Redemption reserve counted once | `test/repro/RedemptionReserve.t.sol::testSettlingReserveCountsOnceInBackingPreview`; `test/invariant/RedemptionAccounting.t.sol::invariant_INV_02_EthConservationExact` |

### sDGNRS redemption properties

Fixtures: `test/fuzz/helpers/RedemptionFixture.sol` and `test/fuzz/helpers/RedemptionCloseTools.sol`
(the latter exposes the production close/funding hook `_closeRedemptionBatch` without a whole VRF
session; real request integration is covered by `RedemptionForwardBatches` and the session suites).

| Property | Tests |
| --- | --- |
| A burn leaves supply at once and records raw token weight and the first activity score; escrow keeps the holder's share of the base until a daily or mid-day request closes and prices the batch | `test/fuzz/RedemptionForwardBatches.t.sol::test_BurnLeavesSupplyAtOnceAndCloseEmitsNoTransfer`, `::test_ClosePricesOverTheHolderBaseWithEqualPerTokenBases`; `test/fuzz/StakedStonkRedemption.t.sol::testFuzz_BurnRecordsTokensAndAggregates`, `::test_PriceIsFixedAtCloseNotBurn`; `test/fuzz/RedemptionEdgeCases.t.sol::test_ActivityScoreFrozenOnFirstBurn` |
| Exact batch token conservation; no daily or supply cap (burns accumulate across days and a batch can exceed half the supply); exact reserves including cursor rounding dust and parked claims | `test/invariant/RedemptionAccounting.t.sol::invariant_INV_04_TokenConservation`, `::invariant_INV_02_EthConservationExact`, `::invariant_balanceCoversPendingRedemptionEth`; `test/fuzz/RedemptionEdgeCases.t.sol::test_NoDailyCapAcrossBatches`, `::test_UncappedBurnsAccumulateAcrossDays`, `::test_BatchCanExceedHalfSupply` |
| The batch's FLIP leg pays on a tagged synthetic flip, independent of the daily coinflip bit | `test/fuzz/RedemptionForwardBatches.t.sol::test_SyntheticFlipBitIsIndependentOfDailyCoinflipBit`; `test/fuzz/StakedStonkRedemption.t.sol::testFuzz_FlipWinOrLossUsesBatchSyntheticResult`; `test/fuzz/RedemptionBatching.t.sol::test_EscrowUsesBatchSyntheticResultWithoutDailyResultRead` |
| The lootbox leg resolves as one box order of at most 20 boxes, with cold gas bounds | `test/fuzz/RedemptionForwardBatches.t.sol::test_RedemptionLootboxLegResolvesAsOneBoundedOrder`; `test/gas/RedemptionBatchGas.t.sol::test_ColdTwentyBoxBeneficiaryThroughRouter`, `::testFuzz_ColdLargeLootboxFitsOrderBound`; `test/fuzz/RandomnessSeedInputs.t.sol::testFuzz_BoxAmountDoesNotRerollIdentity` |
| The close moves the batch's maximum (175%) payout, capped at free backing, from sDGNRS's Game claimable into the redemption reserve; live legs pay only from that reserve, a stETH transfer failure cannot block the close or settlement, and token donations wait for the ending | `test/fuzz/RedemptionStethFallback.t.sol::test_StethTransferFailureCannotBlockReserveCloseOrSettlement`, `::test_TokenDonationWaitsForTheEndingAndGameReserveFundsClaim`, `::test_LargeTokenDonationCannotDropALiveClaim`, `::testFuzz_CloseAndClaimFundingMix`; `test/repro/RedemptionReserve.t.sol::testLargeGameBackingCapsBatchWithoutTruncating` |
| Open escrow stays in the holder base until its batch closes; pending and resolved claims survive century refills | `test/economics/SdgnrsCenturyRecycle.t.sol::testPendingAndResolvedClaimsSurviveRefillsAndSettle`, `::testOpenBatchRemainsUnpricedAcrossRefill` |
| Both endings resolve an unrolled settling batch at 100; a batch resolved live keeps its roll; the open batch unwinds at the terminal burn price | `test/fuzz/RedemptionForwardBatches.t.sol::test_TerminalWordResolvesTheSettlingBatchAndOpenBatchUnwinds`, `::test_DeadEndingResolvesTheSettlingBatchAtExpectedValue`, `::test_OpenBatchUnwindsAtTheGameOverBurnPrice`; `test/fuzz/DeadVrfEnding.t.sol::test_pendingRedemptionResolvesAtExpectedValue` |
| Terminal claims pay exactly once, with no expiry; operators claim for the owner only | `test/fuzz/RedemptionEdgeCases.t.sol::testFuzz_TerminalClaimPaysExactlyOnce`, `::test_OperatorCanClaimTerminalForOwnerOnly` |

The redemption suites also cover real payable forwarding, stETH-before-ETH reentrancy,
protection of other claims' reserves, settlement order, parked retries and operator
authorization.

## Liveness triggered and terminal processing

Once `_endingReason()` is not `None`, purchases, borrowing and AFKing changes close. The
obligation equation still holds until `gameOver` is set.

| Step | Function | Effect |
| --- | --- | --- |
| Decision (purchase timeout, VRF alive) | `DegenerusGameGameOverModule` terminal entry | Latches the terminal level; a staged BAF reservation releases its uncredited part (`if (jackpotWork.kind == 7) claimablePool −= jackpotWork.paid`) into the distributable total |
| Terminal loan settlement | `DegenerusGameAdvanceModule._settleTerminalLoans` (stage 20) | Each loan repays at the current price (internal move) or is seized; no Game ETH moves |
| Drain | `_handleGameOverDrain` | Splits all Degenesis cohorts (`splitDegenesis`); `available = custody − claimablePool`; credits deity refunds (levels below 10, `claimablePool += refunded`); releases `degenesisVaultBudget` and sDGNRS AFKing (`claimablePool −= both`, `DegenesisFundsReleased`); sets `gameOver`; burns unallocated GNRUS/DGNRS inventory and clears `degenesisActive`; zeroes current/next/future, `yieldAccumulator` and the pending buffer |
| Payout | `_startJackpotWork` / `_resumeTerminalPayout` (VRF alive) or `deadPot` + `claimDeadVrf` (hard stall) | `available = custody − claimablePool` goes to the terminal ticket jackpot, or is fixed as `deadPot` and credited to `claimablePool` claim by claim. Empty-bucket leftovers stay in custody for the final sweep |
| Completion | `_finishTerminalPayout` | Sets `GO_JACKPOT_PAID` and `GO_TIME` |

The Game-held redemption reserve stays inside `claimablePool` through the drain; a hard stall
calls `sDGNRS.resolveTerminalRedemptions()`.

| Assertion | Test |
| --- | --- |
| Each loan settles exactly once and settlement moves no Game ETH | `test/fuzz/TerminalLoanConservation.t.sol::testFuzz_SettlementMovesNoEth` ("each loan settles exactly once", "settlement never moves Game ETH") |
| The BAF latch releases exactly the uncredited reservation | `test/fuzz/BafStagedGameOver.t.sol::test_LatchReleasesTheUncreditedReservationAndTheEndingDistributesIt` ("claimablePool releases exactly work.paid", "the released ETH is part of the distributable total") |
| Degenesis budget and sDGNRS AFKing released once | `test/fuzz/DegenesisTerminal.t.sol::test_HardDeadline_AfterSale_ReleasesOnceIntoFinalPrizes` ("no second release"), `::test_HardDeadline_DuringSale_SplitsAllAndForfeitsUnresolved`, `::test_DeadVrfEnding_DuringSale_SplitsThenReleasesOnce` ("the release follows the split in the same call") |
| `GO_TIME` waits for the final quadrant | `test/repro/TerminalPayoutCheckpoints.t.sol::test_SetupRunsOncePotIsPinnedAndTimerWaitsForFinalQuadrant` |
| Hard-stall pot split | `test/fuzz/DeadVrfEnding.t.sol::test_deadEndingSplitsThePotDeterministically` |
| Composed mature ending (loans, redemption, terminal claims, sweep recipients) | `test/repro/MatureComposition.t.sol` (`_solvent`: "composed solvency") |

## Terminal and post-game-over

After `gameOver`, the obligation is `claimablePool` alone: deity refunds, earned claims, credited
terminal awards, the redemption reserve and the protocol sinks' balances. The live pools are zero.
The uncredited part of the terminal pot (an unfinished terminal jackpot or unclaimed `deadPot`) is
custody above `claimablePool`, not a separate obligation.

Final sweep (`_handleFinalSweep`, at `GO_TIME + 30 days`, once):

1. Sets `GO_SWEPT`; stamps GNRUS (`onFinalSweep`).
2. Releases the redemption reserve to sDGNRS claimable.
3. Takes the Vault, sDGNRS and GNRUS balance words (claimable plus AFKing) as `owed`; sets
   `claimablePool = 0`. Every other player balance is forfeited.
4. Reads custody with a one-shot stETH read (`BoundedCall.admitFirst` at `STETH_READ_MIN_GAS`,
   then `_boundedStethBalance`). A read that starts short of gas reverts the sweep; a failed or
   malformed read counts as zero and can leave stETH at the Game after closure
   ([Security](../SECURITY.md#external-dependencies-and-settlement)). Vault, sDGNRS and GNRUS
   holder exits read stETH through `BoundedCall.stethBalanceOrZero` with the same
   `STETH_READ_MIN_GAS` floor ([details](ARCHITECTURE-DETAILS.md#miner-bounty-admission-bounds-and-stage-events)).
5. Pays each sink its `owed` plus a third of the remainder (GNRUS takes the rounding wei); if
   custody is short of `owed` (the three unbacked sentinels, or an stETH loss), the legs are pro
   rata and sum to custody. stETH is sent first.
6. Shuts down the VRF subscription through Admin; a failed shutdown reverts the whole sweep.

After the sweep, `claimWinnings`/`claimClaimable` revert `AlreadySwept`, AFKing withdrawal and
`sweepAccounts` revert, `claimDeadVrf` reverts, and `claimablePoolView()` returns 0. sDGNRS
terminal redemption claims are held by sDGNRS and have no expiry.

| Assertion | Test |
| --- | --- |
| Post-game claimable within backing | `test/fuzz/invariant/WhaleSybil.inv.t.sol::invariant_gameOverTerminal` ("WhaleSybil: post-game claimable exceeds backing") |
| Sweep pays all three receivers, stETH first, pro rata when short | `test/fuzz/FinalSweepPayoutLegs.t.sol::test_ethOnlySweepPaysAllThreeReceiversThroughTheRawCall` ("every wei reached the three receivers"), `::test_mixedSweepPaysStethFirstThenEth`, `::test_aShortfallSplitsWhatExistsProRata`, `::test_emptySweepCompletes` |
| Sweep shuts down the subscription | `test/fuzz/FinalSweepPayoutLegs.t.sol::test_sweepShutsDownTheSubscription`, `::test_sweepSurvivesACoordinatorThatRefusesTheCancel` |
| Claims close at the sweep | `test/fuzz/DeadVrfEnding.t.sol::test_claimsCloseAtTheFinalSweep` |
| Failed stETH read leaves stETH in place | `test/repro/V08StethDeadSweep.t.sol::test_revertingSteth_sweepCompletesAndLeavesStethInPlace` |
| Sweep not reachable before 30 days | `test/edge/GameOver.test.js` ("mineFlip before 30 days reports NoWork and preserves the unexpired claim window") |
