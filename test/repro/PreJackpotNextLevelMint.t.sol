// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {TicketQueueStorage as RingStorage} from "../fuzz/helpers/TicketQueueStorage.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {TicketQueueStorage} from "../fuzz/helpers/TicketQueueStorage.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @dev Seed only the starting state; requests, callbacks, advances and claims use production code.
contract PreJackpotMintSeeder is DegenerusGame, WalletSeed {
    function seed(address currentBuyer, address nextBuyer, uint32 nextEntries, bool parity, bool turbo) external {
        uint24 day = _simulatedDayIndex();
        TicketQueueStorage.retireCompleted(address(this), 129);
        level = 129; // Outside constructor allocations; next level is an x0 turbo latch.
        purchaseStartDay = day - (turbo ? 1 : 5);
        dailyIdx = day;
        lastVrfProcessedTimestamp = uint48(block.timestamp);
        _recordDailyRng(day, 0xDA11);
        rngWordCurrent = RNG_WORD_WAITING;
        rngRequestTime = 0;
        vrfRequestId = 0;
        rngLockedFlag = false;
        jackpotPhaseFlag = false;
        lastPurchaseDay = false;
        jackpotFlags = 0;
        phaseTransitionActive = false;
        dailyJackpotCoinTicketsPending = false;
        ticketsFullyProcessed = true;
        subsFullyProcessed = true;
        prizePoolFrozen = false;
        ticketWriteSlot = parity;
        _afkingResetDay = day;
        levelPrizePool[129] = 50 ether;
        _setPrizePools(51 ether, 20 ether);
        currentPrizePool = 0;
        rngFlagsAndNudges = (rngFlagsAndNudges & ~(uint16(1) << 12)) | (uint16((42) & 1) << 12);
        _lrWrite(LR_PENDING_ETH_SHIFT, LR_PENDING_ETH_MASK, 0);
        _lrWrite(LR_PENDING_FLIP_SHIFT, LR_PENDING_FLIP_MASK, 0);
        _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0);
        rngFlagsAndNudges = (rngFlagsAndNudges & ~(uint16(1) << 12)) | (uint16((uint48(41) + 1) & 1) << 12);
        rngWordCurrent = 0x01D; _setRngSessionPublished(true); _setRngComplete(true);
        // Synthetic empty prior cohort: delivered word, no boxes/bets/fields.
        humanReadComplete = true;
        if (currentBuyer != address(0)) _queueEntries(_seedWallet(currentBuyer), 130, 4, false);
        if (nextEntries != 0) _queueEntries(_seedWallet(nextBuyer), 131, nextEntries, false);
        // The turbo latch freezes the same FF cohort; set it after queueing that cohort.
        lastPurchaseDay = turbo;
        jackpotFlags = turbo ? JACKPOT_TURBO : 0;
    }

    function queueNext(address player, uint32 entries) external {
        _queueEntries(_seedWallet(player), 131, entries, false);
    }

    function setTargetMet(bool met) external {
        _setPrizePools(met ? 51 ether : 49 ether, uint128(_getFuturePrizePool()));
    }

    function ceiling() external view returns (uint24) {
        return _mintCeiling();
    }

    function generationBound(uint24 lvl) external view returns (uint256) {
        return ticketGenerationStartBlock[lvl];
    }

    function activatedLevel() external view returns (uint24) {
        return earlyTicketLevel;
    }
}

/// @notice A target-met purchase phase may mint the next level without committing the current
///         jackpot cohort. The FF snapshot needs its own new word, while subsequent purchases
///         remain in the ordinary write queue. A missing word still permits the deterministic exit.
contract PreJackpotNextLevelMintTest is DeployProtocol {
    uint24 private constant CURRENT = 130;
    uint24 private constant NEXT = 131;
    uint24 private constant SLOT_BIT = uint24(1) << 23;
    uint24 private constant FF_BIT = uint24(1) << 22;
    uint48 private constant INDEX = 0;
    bytes32 private constant PAYOUT_FIXED = keccak256("DeadVrfPayoutFixed(uint24,uint256,uint256,uint256,uint256)");
    bytes32 private constant ADVANCE = keccak256("Advance(uint8,uint24)");
    bytes32 private constant TRAITS_GENERATED = keccak256("TraitsGenerated(uint32,uint256,uint32)");

    address private alice = address(0xA11CE);
    address private bob = address(0xB0B);
    address private carol = address(0xCA401);
    address private keeper = address(0xBEEF);
    bytes private productionCode;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 200 days + 12 hours);
        vm.deal(address(game), 100 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(carol, 100 ether);
        mockVRF.fundSubscription(1, 1000 ether);
        productionCode = address(game).code;
    }

    function test_targetMetBeforeLastPurchaseDayMintsOnlyNextLevel() public {
        _assertIsolatedMint(false, false);
    }

    function test_isolationAlsoHoldsWithOppositeBufferParity() public {
        _assertIsolatedMint(false, true);
    }

    function test_turboLatchUsesIsolatedMintWithoutSwappingCurrentTickets() public {
        _assertIsolatedMint(true, false);
    }

    function _assertIsolatedMint(bool turbo, bool parity) private {
        _seed(8, parity, turbo, true);
        uint24 currentKey = _writeKey(CURRENT);
        uint256 currentOwed = _owed(currentKey, alice);
        uint256 oldDayWord = game.rngWordForDay(game.currentDayView());
        assertEq(_queueLen(NEXT | FF_BIT), 1, "fixture: next-level entries are unminted FF entries");

        // The early cohort piggybacks on an otherwise eligible, funded mid-day request.
        _requestPaidMidday();
        uint256 reqId = mockVRF.lastRequestId();
        assertGt(reqId, 0, "a fresh request was sent");
        assertEq(_parity(), parity, "isolated mint must not commit current-level writes");
        assertEq(_midday(), 2, "the FF-only drain is distinguished from a normal swap");
        assertFalse(_fullyProcessed(), "the isolated cohort is pending");
        assertEq(_ceiling(), NEXT, "later next-level awards route away from the frozen FF pool");
        assertFalse(game.rngLocked(), "mid-day request does not take the daily lock");
        assertEq(_boxWord(INDEX), 0, "previous mid-day and daily words cannot resolve this cohort");
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        game.mineFlip();
        assertEq(_minted(NEXT, bob), 0, "no next-level traits before the fresh callback");

        // Exercise the production queue sink with an award arriving AFTER the snapshot.
        _overlay().queueNext(carol, 4);
        _restore();
        assertEq(_owed(_writeKey(NEXT), carol), 4, "post-request award takes the normal write lane");
        _buyCurrent(carol);
        uint256 afterRequestCurrent = _owed(currentKey, carol);
        assertEq(afterRequestCurrent, 4, "current-level purchase remains eligible for the upcoming draw");

        mockVRF.fulfillRandomWords(reqId, 0xF12345);
        _drainIsolated();
        assertEq(_minted(NEXT, bob), 8, "the committed next-level entries materialized");
        assertEq(_minted(NEXT, carol), 0, "later entries did not inherit the revealed word");
        assertEq(_owed(_writeKey(NEXT), carol), 4, "later entries are still queued");
        assertEq(_owed(currentKey, alice), currentOwed, "original current tickets were untouched");
        assertEq(_owed(currentKey, carol), afterRequestCurrent, "current tickets bought during the request survive");
        assertEq(_minted(CURRENT, alice) + _minted(CURRENT, carol), 0, "no current-level ticket used the early word");
        assertEq(_parity(), parity, "drain completion does not flip current parity");
        assertEq(_queueLen(NEXT | FF_BIT), 0, "committed FF queue emptied");
        assertEq(game.rngWordForDay(game.currentDayView()), oldDayWord, "mid-day callback leaves daily entropy alone");
        assertEq(_ceiling(), NEXT, "the generation ceiling remains raised after the latch clears");

        // Early generation does not grant another request without ordinary request funding.
        _finishReadConsumers();
        _mineRefused();
        assertEq(mockVRF.lastRequestId(), reqId, "ticket work grants no extra request");
    }

    function test_ffWorkDoesNotWaivePendingValueOrThresholdGates() public {
        _seed(8, false, false, true);
        _mineRefused();
        assertEq(_midday(), 0);
        assertEq(_ceiling(), CURRENT, "an unfunded request cannot activate generation");

        _buyBox(0.01 ether);
        _mineRefused();
        assertEq(_midday(), 0);
        assertEq(_ceiling(), CURRENT, "below-threshold work must wait for an eligible request");
        assertEq(_queueLen(NEXT | FF_BIT), 1, "rejected requests preserve the uncreated cohort");
    }

    function test_ffWorkDoesNotWaiveBasefeeGate() public {
        _seed(8, false, false, true);
        _buyBox(2 ether);
        vm.prank(ContractAddresses.CREATOR);
        game.setMiddayMaxBasefee(5);
        vm.fee(6 gwei);
        _mineRefused();
        assertEq(_midday(), 0, "rejected request commits no early cohort");
        assertEq(_ceiling(), CURRENT, "rejected request does not raise the mint ceiling");
    }

    function test_firstEligibleRequestRaisesCeilingEvenWithAnEmptyFfPool() public {
        _seed(0, false, false, true);
        vm.roll(100);
        _requestPaidMidday();
        assertEq(_ceiling(), NEXT, "the first fresh request starts generation for the next level");
        assertEq(_generationBound(), 100);
        assertTrue(_midday() != 2, "an empty future pool needs no isolated work latch");
        _overlay().queueNext(carol, 4);
        _restore();
        assertEq(_owed(_writeKey(NEXT), carol), 4, "later next-level entries use the ordinary queue");
        assertEq(_queueLen(NEXT | FF_BIT), 0, "the future pool is never reopened");
    }

    function test_requestBeforeTargetDoesNotStartNextLevelGeneration() public {
        _seed(8, false, false, true);
        _buyBox(2 ether);
        _overlay().setTargetMet(false);
        _restore();
        _mineRequest(address(this));
        assertEq(_ceiling(), CURRENT, "the target has not been met at commitment");
        assertEq(_generationBound(), 0);
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 0xF12345);
        _drainIsolated();
        assertEq(_minted(CURRENT, alice), 4, "ordinary current-level ticket processing still runs");
        assertEq(_minted(NEXT, bob), 0, "unqualified FF entries do not use this word");
        assertEq(_queueLen(NEXT | FF_BIT), 1);
    }

    function test_existingInflightWordCannotBeAdoptedForEarlyMint() public {
        _seed(8, false, false, false);
        _buyBox(2 ether);
        _overlay().setTargetMet(false);
        _restore();
        uint256 existingId = _mineRequest(address(this));

        _overlay().setTargetMet(true);
        _restore();
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        game.mineFlip();
        assertEq(_ceiling(), CURRENT, "an already requested word cannot open the generation window");
        assertEq(_midday(), 0, "no isolated cohort was bound retroactively");
        mockVRF.fulfillRandomWords(existingId, 0xF12345);
        assertEq(_minted(NEXT, bob), 0, "old in-flight request created no next-level traits");

        _requestPaidMidday();
        assertGt(mockVRF.lastRequestId(), existingId, "the early cohort requires another request");
        assertEq(_midday(), 2);
    }

    function test_ordinaryDailyLeavesFuturePoolQueuedUntilFollowingMiddayRequest() public {
        _seed(8, false, false, true);
        uint24 currentKey = _writeKey(CURRENT);
        vm.roll(100);
        uint256 reqId = _requestNextDaily();
        assertGt(reqId, 0, "daily advance requests its ordinary fresh word");
        assertEq(game.level(), CURRENT - 1, "the request does not advance the purchase level");
        (, bool jackpot, bool lastPurchase, bool locked,) = game.purchaseInfo();
        assertFalse(jackpot);
        assertFalse(lastPurchase, "the ordinary purchase day is not yet sealed");
        assertTrue(locked, "the daily request keeps its ordinary lock");
        assertEq(_ceiling(), CURRENT, "ordinary daily RNG does not raise the generation ceiling");
        assertEq(_activatedLevel(), 0, "ordinary daily RNG does not activate the future pool");
        assertEq(_generationBound(), 0);
        assertEq(_midday(), 0);
        assertEq(_readKey(CURRENT), currentKey, "daily commitment includes current-level tickets");
        assertEq(_boxWord(INDEX), 0);
        assertEq(_minted(NEXT, bob), 0, "previous recorded words cannot create the FF cohort");
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        game.mineFlip();

        mockVRF.fulfillRandomWords(reqId, 0xDA113);
        _finishOrdinaryPurchaseDaily();
        assertEq(_minted(NEXT, bob), 0, "the ordinary daily jackpot finishes before FF generation");
        assertEq(_owed(NEXT | FF_BIT, bob), 8, "Bob's future entries remain available through the daily jackpot");
        assertGt(_queueLen(NEXT | FF_BIT), 0, "the future pool still waits at the last-purchase seal");
        assertEq(_activatedLevel(), 0, "the ordinary seal uses its natural freeze rather than early activation");
        assertEq(_ceiling(), NEXT, "the completed last-purchase seal opens its normal ceiling");
        assertGe(_minted(CURRENT, alice), 4, "ordinary daily current-level drain remains intact");
        assertEq(_owed(currentKey, alice), 0);

        _requestPaidMidday();
        uint256 middayId = mockVRF.lastRequestId();
        assertGt(middayId, reqId, "the future pool receives a separate fresh mid-day word");
        assertEq(_midday(), 2);
        assertEq(_minted(NEXT, bob), 0, "the earlier daily word cannot resolve this cohort");
        mockVRF.fulfillRandomWords(middayId, 0xF12345);
        _drainIsolated();
        assertEq(_minted(NEXT, bob), 8, "the following mid-day word creates the waiting entries");
        assertEq(_queueLen(NEXT | FF_BIT), 0);
    }

    function test_freshTurboDailyRequestMintsFuturePoolBeforeJackpot() public {
        _assertTransitionDrainsFutureBeforeJackpot(true);
    }

    function test_normalLastPurchaseTransitionStillDrainsFuturePoolBeforeJackpot() public {
        _assertTransitionDrainsFutureBeforeJackpot(false);
    }

    function _assertTransitionDrainsFutureBeforeJackpot(bool turbo) private {
        _seed(8, false, turbo, true);
        if (!turbo) {
            mockVRF.fulfillRandomWords(_requestNextDaily(), 0xDA113);
            _finishOrdinaryPurchaseDaily();
            assertEq(_minted(NEXT, bob), 0, "the preceding ordinary daily left the pool unminted");
        }
        _buyCurrent(carol);
        uint24 currentKey = _writeKey(CURRENT);
        assertEq(_owed(currentKey, carol), 4, "the last purchase window includes a fresh current-level buy");
        assertEq(_owed(NEXT | FF_BIT, bob), 8, "the transition still has a real frozen cohort to drain");

        uint256 reqId = _requestNextDaily();
        assertEq(game.level(), CURRENT, "last-purchase request promotes the level exactly once");
        assertTrue(game.rngLocked());
        assertFalse(game.jackpotPhase());
        assertEq(_ceiling(), NEXT);
        assertEq(_activatedLevel(), turbo ? NEXT : 0,
            "turbo activates early generation; the ordinary transition retains its natural freeze");
        assertEq(_readKey(CURRENT), currentKey, "the transition commits last-purchase tickets");
        assertEq(_minted(NEXT, bob), 0, "FF entries wait for this transition's fresh callback");

        mockVRF.fulfillRandomWords(reqId, 0xDA114);
        // The engine composes admitted checkpoints, so a turbo collapse can enter and leave its
        // jackpot phase inside one realistic call. Read the order from the call's logs: every
        // materialization the transition owes must precede the jackpot-entry marker (stage 7),
        // which itself precedes the early-bird draw (stage 14).
        bool entered;
        uint256 bobBefore;
        uint256 carolBefore;
        for (uint256 i; i < 100 && !entered; ++i) {
            vm.recordLogs();
            game.mineFlip{gas: 16_777_216}();
            Vm.Log[] memory logs = vm.getRecordedLogs();
            for (uint256 j; j < logs.length && !entered; ++j) {
                if (logs[j].emitter != address(game)) continue;
                if (logs[j].topics.length == 1 && logs[j].topics[0] == ADVANCE) {
                    (uint8 stage,) = abi.decode(logs[j].data, (uint8, uint24));
                    assertTrue(stage != 14, "no early-bird draw before jackpot entry");
                    if (stage == 7) entered = true;
                    continue;
                }
                bobBefore += _materializedIn(logs[j], bob, NEXT);
                carolBefore += _materializedIn(logs[j], carol, CURRENT);
            }
        }
        assertTrue(entered, "the funded transition reaches jackpot entry");
        assertEq(bobBefore, 8, "all frozen FF entries materialize before jackpot entry and the early-bird draw");
        assertEq(carolBefore, 4, "the last-purchase current cohort materializes before its jackpot");
        assertEq(_minted(NEXT, bob), 8, "all frozen FF entries materialize before the early-bird draw");
        assertEq(_queueLen(NEXT | FF_BIT), 0, "jackpot entry cannot leave part of the frozen cohort behind");
        assertEq(_minted(CURRENT, carol), 4, "the last-purchase current cohort materializes before its jackpot");
        assertEq(_owed(currentKey, carol), 0);
        assertGe(_minted(CURRENT, alice), 4);
    }

    function test_partialBatchesKeepTheirLatchAndCurrentCohortUntouched() public {
        _seed(8000, true, false, true);
        uint24 currentKey = _writeKey(CURRENT);
        _requestPaidMidday();
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 0xABCD);
        // Publication precedes the bounded ticket worker; with a realistic allowance the same
        // call admits ticket chunks only while their bounds fit, leaving a partial batch.
        game.mineFlip{gas: 16_777_216}();
        assertEq(_midday(), 2, "a partial first batch retains its word binding");
        assertFalse(_fullyProcessed(), "partial first batch cannot report completion");
        game.mineFlip{gas: 16_777_216}();
        assertEq(_midday(), 2, "a partial batch retains its word binding");
        assertFalse(_fullyProcessed(), "partial FF batch cannot report completion");
        assertGt(_minted(NEXT, bob), 0, "the first batch made progress");
        assertLt(_minted(NEXT, bob), 8000, "fixture: more than one batch was required");
        assertEq(_owed(currentKey, alice), 4, "partial drain did not touch current tickets");
        _drainIsolated();
        assertEq(_minted(NEXT, bob), 8000, "all entries eventually materialize exactly once");
        assertEq(_owed(currentKey, alice), 4);
        assertTrue(_parity(), "all isolated batches retain global parity");
    }

    function test_twentyHourRetryPreservesMiddayThenDailyCommitsCurrentWrites() public {
        _assertDailyRetry(false);
    }

    function test_turboRetryPreservesMiddayThenDailyCommitsCurrentWrites() public {
        _assertDailyRetry(true);
    }

    function _assertDailyRetry(bool turbo) private {
        _seed(8, false, turbo, true);
        // The synthetic 200-day jump leaves scheduled empty Craps days to retire.
        // Finish that real maintenance before buying boxes so it cannot send the
        // intended explicit midday request on our behalf.
        for (uint256 i; i < 256 && crapsBattle.minerMaintenancePending(); ++i) {
            game.mineFlip{gas: 16_777_216}();
        }
        assertFalse(crapsBattle.minerMaintenancePending(), "fixture scheduled maintenance completed");
        _requestPaidMidday();
        uint256 oldId = mockVRF.lastRequestId();
        uint256 sent = vm.getBlockTimestamp();
        bool committedParity = _parity();
        uint24 oldKey = _writeKey(CURRENT);
        _buyCurrent(carol);

        vm.warp(sent + 20 hours - 1);
        vm.prank(ContractAddresses.CREATOR);
        (bool early,) = address(admin).call(abi.encodeWithSignature("retryGameRng()"));
        assertFalse(early, "retry is unavailable before twenty hours");
        assertEq(mockVRF.lastRequestId(), oldId);
        assertEq(_owed(oldKey, alice), 4);
        assertEq(_owed(oldKey, carol), 4);

        vm.warp(sent + 20 hours + 1);
        vm.prank(keeper);
        (bool outsider,) = address(admin).call(abi.encodeWithSignature("retryGameRng()"));
        assertFalse(outsider, "only the vault owner may spend the retry");
        vm.prank(ContractAddresses.CREATOR);
        admin.retryGameRng();
        uint256 retryId = mockVRF.lastRequestId();
        assertGt(retryId, oldId, "owner sent a replacement request");
        assertFalse(game.rngLocked(), "transport retry retains the midday mode");
        assertEq(_parity(), committedParity, "retry does not commit a new ticket cohort");
        assertEq(_writeKey(CURRENT), oldKey, "current buys remain in their original write queue");
        assertEq(_owed(oldKey, alice), 4);
        assertEq(_owed(oldKey, carol), 4);
        assertEq(game.level(), CURRENT - 1, "transport retry cannot promote the level");
        assertFalse(game.jackpotPhase(), "midday retry cannot enter a jackpot");

        mockVRF.fulfillRandomWords(oldId, 0xBAD);
        assertEq(_boxWord(INDEX), 0, "obsolete callback cannot settle the isolated cohort");
        mockVRF.fulfillRandomWords(retryId, 0x600D);
        // The old midday word finishes its frozen FF cohort before a fresh daily request
        // commits the current-level purchases, including those bought during the stall.
        for (uint256 i; i < 100 && mockVRF.lastRequestId() == retryId; ++i) {
            game.mineFlip{gas: 16_777_216}();
        }
        uint256 dailyId = mockVRF.lastRequestId();
        assertGt(dailyId, retryId, "daily settlement requires a separate fresh request");
        assertTrue(game.rngLocked(), "the fresh daily request takes the daily lock");
        assertEq(_readKey(CURRENT), oldKey, "fresh daily request commits current-level purchases");
        assertEq(game.level(), turbo ? CURRENT : CURRENT - 1, "only the fresh request may promote the level");
        assertEq(_minted(NEXT, bob), 8, "midday retry resolved only its frozen FF cohort");
        assertEq(_minted(CURRENT, carol), 0, "stall-window current tickets await the daily word");
        mockVRF.fulfillRandomWords(dailyId, 0xDA11);
        for (uint256 i; i < 100; ++i) {
            if (_minted(CURRENT, alice) == 4 && _minted(CURRENT, carol) == 4) break;
            assertFalse(game.jackpotPhase(), "current tickets precede jackpot entry");
            game.mineFlip{gas: 16_777_216}();
        }
        assertEq(_minted(CURRENT, alice), 4, "original current tickets materialized before their draw");
        assertEq(_minted(CURRENT, carol), 4, "stall-window tickets joined the same daily cohort");
        assertEq(_minted(NEXT, bob), 8, "midday retry resolves the isolated FF snapshot");
        assertEq(_owed(oldKey, alice) + _owed(oldKey, carol), 0, "no current tickets were left behind");
    }

    function test_laterLastPurchaseLatchPreservesTheEarlyGenerationBound() public {
        _seed(8, false, false, true);
        vm.roll(100);
        _requestPaidMidday();
        assertEq(_generationBound(), 100, "the fresh early request opens the generation window");
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 0xA11CE);
        _drainIsolated();

        vm.roll(200);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        bool latched;
        for (uint256 i; i < 100; ++i) {
            (, bool jackpot, bool lastPurchase, bool locked,) = game.purchaseInfo();
            if (lastPurchase && !locked) {
                assertFalse(jackpot, "the next daily seal just opened the last purchase window");
                latched = true;
                break;
            }
            game.mineFlip();
            uint256 reqId = mockVRF.lastRequestId();
            (,, bool fulfilled) = mockVRF.pendingRequests(reqId);
            if (!fulfilled) mockVRF.fulfillRandomWords(reqId, 0xDA112);
        }
        assertTrue(latched, "production advance reached the ordinary last purchase latch");
        assertEq(_generationBound(), 100, "later latch cannot hide previously generated tickets");
    }

    function test_actualTraitsDependOnTheFreshWordRatherThanTheRecordedWords() public {
        _seed(8, false, false, true);
        _requestPaidMidday();
        uint256 reqId = mockVRF.lastRequestId();
        uint256 snapshot = vm.snapshotState();
        mockVRF.fulfillRandomWords(reqId, 0xA11CE);
        _drainIsolated();
        bytes32 first = _traitDigest();

        assertTrue(vm.revertToState(snapshot));
        mockVRF.fulfillRandomWords(reqId, 0xB0B);
        _drainIsolated();
        assertTrue(_traitDigest() != first, "changing only the fresh word must change the generated traits");
    }

    function test_unansweredEarlyRequestStillEndsDeterministicallyAfterFourteenDays() public {
        _seed(8, false, false, true);
        _requestPaidMidday();
        uint256 sent = vm.getBlockTimestamp();
        _buyCurrent(carol);

        vm.warp(sent + 14 days - 1);
        assertFalse(game.livenessTriggered(), "target-met purchase phase remains live inside the timeout");
        assertFalse(game.gameOver());
        assertEq(_minted(NEXT, bob), 0, "stalled next-level traits remain uncreated");

        vm.warp(sent + 14 days);
        assertTrue(game.livenessTriggered(), "fourteen unanswered days enable deterministic exit");
        vm.recordLogs();
        for (uint256 i; i < 30 && !game.gameOver(); ++i) {
            game.mineFlip();
        }
        assertTrue(game.gameOver(), "the isolated snapshot cannot prevent fund release");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool saw;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length == 0 || logs[i].topics[0] != PAYOUT_FIXED) {
                continue;
            }
            assertEq(uint256(logs[i].topics[1]), CURRENT, "the ending pays the current ticket cohort");
            (, uint256 created, uint256 uncreated,) = abi.decode(logs[i].data, (uint256, uint256, uint256, uint256));
            assertEq(created, 0, "early request never created current-level tickets");
            assertEq(uncreated, 8 * 100, "both current purchases count; speculative next-level entries do not");
            saw = true;
        }
        assertTrue(saw, "ending fixed its deterministic pot");
        // A queued claim names the owner's wallet ID and carries the queue key holding the
        // entries in bits 32..55 (GameOverModule.claimDeadVrf).
        uint256 pos = game.walletIdOf(alice);
        uint24 aliceKey = _owed(_writeKey(CURRENT), alice) != 0 ? _writeKey(CURRENT) : _readKey(CURRENT);
        assertEq(_owed(aliceKey, alice), 4, "alice's current entries are still queued at the ending");
        uint256[] memory refs = new uint256[](1);
        refs[0] = (uint256(1) << 248) | (uint256(aliceKey) << 32) | pos;
        uint256 before = game.claimableWinningsOf(alice);
        game.claimDeadVrf(alice, refs);
        assertGt(game.claimableWinningsOf(alice), before, "current ticket holder can claim the ending pot");
    }

    function _seed(uint32 nextEntries, bool parity, bool turbo, bool withCurrent) private {
        _overlay().seed(withCurrent ? alice : address(0), bob, nextEntries, parity, turbo);
        _restore();
        // The synthetic 200-day jump leaves expired Craps days for real miner maintenance,
        // which refuses every RNG request until it completes (RngModule request gates).
        _finishMaintenance();
    }

    function _finishMaintenance() private {
        for (uint256 i; i < 512 && crapsBattle.minerMaintenancePending(); ++i) {
            game.mineFlip{gas: 16_777_216}();
        }
        assertFalse(crapsBattle.minerMaintenancePending(), "fixture scheduled maintenance completed");
    }

    function _overlay() private returns (PreJackpotMintSeeder) {
        vm.etch(address(game), type(PreJackpotMintSeeder).runtimeCode);
        return PreJackpotMintSeeder(payable(address(game)));
    }

    function _restore() private {
        vm.etch(address(game), productionCode);
    }

    function _ceiling() private returns (uint24 result) {
        result = _overlay().ceiling();
        _restore();
    }

    function _generationBound() private returns (uint256 result) {
        result = _overlay().generationBound(NEXT);
        _restore();
    }

    function _activatedLevel() private returns (uint24 result) {
        result = _overlay().activatedLevel();
        _restore();
    }

    function _requestNextDaily() private returns (uint256 reqId) {
        uint256 oldId = mockVRF.lastRequestId();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        // A new day may first retire its own expired Craps maintenance checkpoints.
        for (uint256 i; i < 64 && mockVRF.lastRequestId() == oldId; ++i) {
            game.mineFlip{gas: 16_777_216}();
        }
        reqId = mockVRF.lastRequestId();
        assertGt(reqId, oldId, "the new day requests a fresh word");
    }

    /// @dev Each call gets the smallest rung of a realistic allowance ladder that admits work, so
    ///      the sealing call cannot also compose the miner's own mid-day request (2.5M bound):
    ///      the seal is observed before any later request.
    function _finishOrdinaryPurchaseDaily() private {
        uint256[9] memory ladder = [uint256(1_500_000), 2_000_000, 2_500_000, 3_000_000, 3_500_000, 4_000_000,
            6_000_000, 10_000_000, 16_777_216];
        // Drive the day seal, then the committed session's read consumers (they follow the seal),
        // stopping before any new request.
        uint256 requestId = mockVRF.lastRequestId();
        for (uint256 i; i < 400 && (game.rngLocked() || !game.rngComplete()); ++i) {
            assertEq(mockVRF.lastRequestId(), requestId, "no request composes into the daily chain");
            for (uint256 r; r < ladder.length; ++r) {
                try game.mineFlip{gas: ladder[r]}() {
                    break;
                } catch (bytes memory err) {
                    assertEq(bytes4(err), MineFlipGas.InsufficientExecutionGas.selector, "only an allowance refusal retries");
                    assertTrue(r + 1 < ladder.length, "a realistic allowance must make progress");
                }
            }
        }
        (, bool jackpot, bool lastPurchase, bool locked,) = game.purchaseInfo();
        assertFalse(locked, "the whole daily jackpot and ticket leg reached their day seal");
        assertTrue(lastPurchase, "the target-met ordinary day opened its last-purchase window");
        assertFalse(jackpot, "the last-purchase window precedes the jackpot phase");
        // No daily work remains. A shut Craps window bound to the write buffer is mid-day request
        // work for any caller (craps windows ride the normal RNG round), not daily work.
        uint8 next = game.nextMinerAction();
        assertTrue(
            next == uint8(DegenerusGameStorage.MinerAction.Idle) || next == uint8(DegenerusGameStorage.MinerAction.RequestMidday),
            "no daily work remains before the next request"
        );
    }

    function _buyCurrent(address player) private {
        (,,,, uint256 price) = game.purchaseInfo();
        vm.prank(player);
        game.purchase{value: price}(player, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
    }

    function _buyBox(uint256 amount) private {
        vm.prank(alice);
        game.purchase{value: amount}(
            alice, 0, BoxOrderLib.boCustom(amount), bytes32(0), MintPaymentKind.DirectEth, false
        );
    }

    function _requestPaidMidday() private {
        _finishReadConsumers();
        _buyBox(2 ether);
        _mineRequest(keeper);
    }

    /// @dev `caller`'s mineFlip, the only door to the mid-day request, issues it as the engine's
    ///      next action.
    function _mineRequest(address caller) private returns (uint256 id) {
        uint256 prior = mockVRF.lastRequestId();
        vm.prank(caller);
        game.mineFlip();
        id = mockVRF.lastRequestId();
        assertGt(id, prior, "mineFlip issued the mid-day request");
        assertFalse(game.rngLocked(), "a mid-day request, not the daily one");
    }

    /// @dev The mid-day request is refused before it is ever selected, so a mineFlip with nothing
    ///      else to do finds no work and requests nothing.
    function _mineRefused() private {
        uint256 prior = mockVRF.lastRequestId();
        assertEq(game.nextMinerAction(), 0, "the refused request is not selected (Idle)");
        vm.expectRevert(bytes4(keccak256("NoWork()")));
        game.mineFlip();
        assertEq(mockVRF.lastRequestId(), prior, "a refused request asked for no word");
    }

    function _drainIsolated() private {
        // The drain ends when this cohort completes. A completed cohort can be followed by the
        // engine's next mid-day request in the same call (e.g. a write-side Craps window with
        // freshly queued tickets); that request's own latch is not this cohort's work.
        uint256 startId = mockVRF.lastRequestId();
        for (uint256 i; i < 100 && _midday() != 0 && mockVRF.lastRequestId() == startId; ++i) {
            game.mineFlip{gas: 16_777_216}();
        }
        if (mockVRF.lastRequestId() != startId) return; // a new request needs the cohort complete
        assertEq(_midday(), 0, "isolated drain completes in bounded calls");
        assertTrue(_fullyProcessed(), "completion releases the ticket work latch");
    }

    function _parity() private view returns (bool) {
        return (uint256(vm.load(address(game), bytes32(uint256(0)))) >> 200) & 1 != 0;
    }

    function _fullyProcessed() private view returns (bool) {
        return (uint256(vm.load(address(game), bytes32(uint256(0)))) >> 192) & 1 != 0;
    }

    function _midday() private view returns (uint256) {
        return (uint256(vm.load(address(game), bytes32(GameSlots.LOOTBOX_RNG_PACKED))) >> 224) & 0xFF;
    }

    function _writeKey(uint24 lvl) private view returns (uint24) {
        return _parity() ? lvl | SLOT_BIT : lvl;
    }

    function _readKey(uint24 lvl) private view returns (uint24) {
        return _parity() ? lvl : lvl | SLOT_BIT;
    }

    function _queueLen(uint24 key) private view returns (uint256) {
        return TicketQueueStorage.length(address(game), key);
    }

    function _boxWord(uint48 index) private view returns (uint256) {
        return RecyclingState.word(address(game), index);
    }

    function _owed(uint24 key, address player) private view returns (uint256) {
        return uint32(TicketQueueStorage.owed(address(game), key, player) >> 8);
    }

    function _minted(uint24 lvl, address player) private view returns (uint256 total) {
        for (uint16 trait; trait < 256; ++trait) {
            (uint24 count,,) = game.getEntries(uint8(trait), lvl, 0, type(uint32).max, player);
            total += count;
        }
    }

    /// @dev Entries for (player, lvl) materialized by one log: a solo TraitsGenerated run (level in
    ///      the stream identity, bits 224..247) or an anonymous EntryTraitsRevealed round (topic j is
    ///      (level << 160) | walletId; presence bit 128 + 4j + q per quadrant).
    function _materializedIn(Vm.Log memory l, address player, uint24 lvl) private view returns (uint256 n) {
        uint32 playerId = game.walletIdOf(player);
        if (l.topics.length == 2 && l.topics[0] == TRAITS_GENERATED) {
            if (uint32(uint256(l.topics[1])) != playerId) return 0;
            (uint256 baseKey, uint32 take) = abi.decode(l.data, (uint256, uint32));
            if (uint24(baseKey >> 224) == lvl) n = take;
            return n;
        }
        if (l.topics.length != 4 || l.data.length != 32) return 0;
        uint256 entries = abi.decode(l.data, (uint256));
        uint256 tag = (uint256(lvl) << 160) | playerId;
        for (uint256 j; j < 4; ++j) {
            if (uint256(l.topics[j]) != tag) continue;
            for (uint256 q; q < 4; ++q) if ((entries >> (128 + 4 * j + q)) & 1 != 0) ++n;
        }
    }

    function _traitDigest() private view returns (bytes32) {
        uint24[256] memory counts;
        for (uint16 trait; trait < 256; ++trait) {
            (counts[trait],,) = game.getEntries(uint8(trait), NEXT, 0, type(uint32).max, bob);
        }
        return keccak256(abi.encode(counts));
    }
}
