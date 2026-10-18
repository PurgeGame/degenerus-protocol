// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DegenesisDeployProtocol} from "../helpers/DeployProtocol.sol";
import {DegenesisRngFreezeHandler} from "../handlers/DegenesisRngFreezeHandler.sol";
import {BoxOrderLib} from "../../helpers/BoxOrderLib.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";
import {GameTimeLib} from "../../../contracts/libraries/GameTimeLib.sol";

/// @title DegenesisRngFreeze -- the RNG-freeze invariant on the Degenesis timeline
/// @notice Deploys on day index 1 with the sale ahead. The fuzzer interleaves Degenesis buys,
///         ordinary lootbox buys, Craps day entries, nudge attempts, miner calls on fuzzed gas,
///         VRF fulfilments, delays, admin retries and day changes. At each request the handler
///         snapshots what every pending outcome will read (the priced cohort's lanes, V, Q and
///         bound day; the sealed lootbox buffer; the locked jackpot battle's field), and the
///         properties below assert those inputs never change before resolution and that every
///         Degenesis order resolves exactly as the reference computes from the snapshot and the
///         word recorded for its bound day. See DegenesisRngFreezeHandler for the replay.
///
///         Non-vacuity: setUp places cohort-1 orders on Degenesis day 1, so the campaign's first
///         daily request prices a real cohort. afterInvariant drains each run's pending work on
///         the same clock (answering every request, every call replayed through the checks),
///         re-asserts the properties, and requires a cohort priced at a mid-sale request and settled with every cohort-1
///         order matched, a delivered word, a locked battle, re-checks of the frozen inputs and
///         sealed boxes, and a player action or delay while a request was open. test_handlerSequenceExercisesTheProperty
///         pins the same on a deterministic action sequence, and the two falsifiability tests
///         show the detectors fire.
contract DegenesisRngFreeze is DegenesisDeployProtocol {
    DegenesisRngFreezeHandler public handler;
    address[] internal actors;

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 100e18);
        for (uint256 i; i < 5; ++i) {
            address a = makeAddr(string.concat("deg-rng-actor-", vm.toString(i)));
            vm.deal(a, 1_000 ether);
            actors.push(a);
            // 40 ETH of boxes: 10 ETH of Degenesis credit each.
            vm.prank(a);
            game.purchase{value: 40 ether}(0, 0, BoxOrderLib.boCustom(40 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        }
        _driveAll();
        vm.warp(_dayStartOf(GameTimeLib.DEGENESIS_START_DAY) + 1 hours);
        _driveAll();
        // Cohort-1 orders, so the campaign's first daily request prices a real cohort.
        for (uint256 i; i < 10; ++i) {
            vm.warp(block.timestamp + 11 minutes);
            vm.prank(actors[i % 5]);
            game.buyDegenesisBox{value: 0.0137 ether + i * 0.0011 ether}(0, 0.0137 ether + i * 0.0011 ether);
        }

        handler = new DegenesisRngFreezeHandler(game, mockVRF, coin, crapsBattle, actors);
        targetContract(address(handler));
        bytes4[] memory excluded = new bytes4[](3);
        excluded[0] = DegenesisRngFreezeHandler.debugSeedLaneMutationAndCheck.selector;
        excluded[1] = DegenesisRngFreezeHandler.debugSeedOutcomeMismatchAndCheck.selector;
        excluded[2] = DegenesisRngFreezeHandler.drainAll.selector;
        excludeSelector(StdInvariant.FuzzSelector({addr: address(handler), selectors: excluded}));
    }

    function _dayStartOf(uint24 d) internal pure returns (uint256) {
        return uint256(d - 1) * 1 days + GameTimeLib.JACKPOT_RESET_TIME;
    }

    /// @dev Mine until idle, answering every request with a derived word.
    function _driveAll() internal {
        for (uint256 i; i < 300; ++i) {
            uint256 req = mockVRF.lastRequestId();
            if (req != 0) {
                (,, bool done) = mockVRF.pendingRequests(req);
                if (!done) mockVRF.fulfillRandomWords(req, uint256(keccak256(abi.encode("deg-rng-setup", req))));
            }
            try game.mineFlip(0) {} catch {
                req = mockVRF.lastRequestId();
                (,, bool done) = mockVRF.pendingRequests(req);
                if (done) return;
            }
        }
    }

    // =====================================================================
    // Properties
    // =====================================================================

    /// @notice Every Degenesis order resolves once, after its bound word, exactly as the reference
    ///         computes from the inputs snapshotted at its cohort's request; a cohort closes only
    ///         when every order resolved.
    function invariant_degenesisOutcomesBindToTheirRequest() public view {
        assertEq(handler.ghost_outcomeMismatches(), 0, "a Degenesis order resolved off its request-time inputs");
        assertEq(handler.ghost_strayResolutions(), 0, "an order resolved outside the priced cohort");
        assertEq(handler.ghost_doubleResolutions(), 0, "an order resolved twice");
        assertEq(handler.ghost_resolvedBeforeWord(), 0, "an order resolved before its bound word was recorded");
        assertEq(handler.ghost_closedIncomplete(), 0, "a cohort closed with orders unresolved");
    }

    /// @notice A cohort is priced only inside the call that sends its VRF request, bound to that
    ///         request's day while the day's word is unknown, and never while another is pending.
    function invariant_pricingRidesItsRequest() public view {
        assertEq(handler.ghost_pricedWithoutRequest(), 0, "a cohort priced outside its request");
        assertEq(handler.ghost_boundToKnownWord(), 0, "a cohort bound to a word already recorded");
        assertEq(handler.ghost_overlappingPricing(), 0, "a cohort priced while another was pending");
    }

    /// @notice Between its request and its close, nothing changes a priced cohort's lanes, V,
    ///         count, Q or bound day, the copied word equals its bound day's recorded word, and no
    ///         order joins a cohort other than today's.
    function invariant_pendingInputsFrozen() public view {
        assertEq(handler.ghost_frozenInputMutations(), 0, "a priced cohort's input changed before its close");
        assertEq(handler.ghost_wordCopyMismatches(), 0, "degenesisWord differs from its bound day's word");
        assertEq(handler.ghost_windowOrdersIntoSealedCohort(), 0, "an order joined a sealed cohort");
    }

    /// @notice The lootbox buffer sealed by a request keeps every entry word until the next request.
    function invariant_sealedBoxesFrozen() public view {
        assertEq(handler.ghost_sealedBoxMutations(), 0, "a sealed lootbox entry changed before the next request");
    }

    /// @notice A locked jackpot battle's field, price and award target are frozen until it
    ///         starts, and a Degenesis window day draws no awarded seats.
    function invariant_jackpotBattleFrozen() public view {
        assertEq(handler.ghost_battleFieldMutations(), 0, "a locked battle's field changed before its word");
        assertEq(handler.ghost_battleAwardsDuringSale(), 0, "a Degenesis window battle drew awarded seats");
    }

    /// @notice No nudge is accepted while a daily word is in flight.
    function invariant_noNudgeInDailyWindow() public view {
        assertEq(handler.ghost_nudgesInDailyWindow(), 0, "a nudge was accepted inside the daily window");
    }

    // =====================================================================
    // Non-vacuity
    // =====================================================================

    function afterInvariant() public {
        // Drain the run's pending work on the same clock (every call replayed through the
        // checks), so the cohort a run priced settles and its orders are graded.
        handler.drainAll();
        invariant_degenesisOutcomesBindToTheirRequest();
        invariant_pricingRidesItsRequest();
        invariant_pendingInputsFrozen();
        invariant_sealedBoxesFrozen();
        invariant_jackpotBattleFrozen();

        emit log_named_uint("cohorts priced", handler.ghost_cohortsPriced());
        emit log_named_uint("cohorts settled", handler.ghost_cohortsSettled());
        emit log_named_uint("orders matched", handler.ghost_ordersMatched());
        emit log_named_uint("requests", handler.ghost_requests());
        emit log_named_uint("requests mid-sale (pricing)", handler.ghost_requestsMidSale());
        emit log_named_uint("fulfilments", handler.ghost_fulfilments());
        emit log_named_uint("buys", handler.ghost_buys());
        emit log_named_uint("buys while request open", handler.ghost_buysWhileRequestOpen());
        emit log_named_uint("box buys while request open", handler.ghost_boxBuysWhileRequestOpen());
        emit log_named_uint("delays while request open", handler.ghost_delaysWhileRequestOpen());
        emit log_named_uint("retries", handler.ghost_retries());
        emit log_named_uint("craps attempts", handler.ghost_crapsAttempts());
        emit log_named_uint("craps entries", handler.ghost_crapsEntries());
        emit log_named_uint("battle locks", handler.ghost_battleLocks());
        emit log_named_uint("nudge attempts in window", handler.ghost_nudgeAttemptsInDailyWindow());
        emit log_named_uint("frozen checks", handler.ghost_frozenChecks());
        emit log_named_uint("box epoch checks", handler.ghost_boxEpochChecks());
        assertGe(handler.ghost_cohortsPriced(), 1, "vacuous: no cohort priced");
        assertGe(handler.ghost_requestsMidSale(), 1, "vacuous: no pricing request landed mid-sale");
        assertGe(handler.ghost_pricingRequestsWithOrdersPending(), 1, "vacuous: no priced cohort held orders");
        assertGe(handler.ghost_cohortsSettled(), 1, string.concat(
            "vacuous: no cohort settled; live=", vm.toString(handler.snapLive()),
            " wordSeen=", vm.toString(handler.snapWordSeen()),
            " resolved=", vm.toString(handler.snapResolvedCount()),
            " fulfil=", vm.toString(handler.ghost_fulfilments()),
            " req=", vm.toString(handler.ghost_requests()),
            " day=", vm.toString(game.currentDayView()),
            " action=", vm.toString(game.nextMinerAction()),
            " locked=", vm.toString(game.rngLocked())
        ));
        assertGe(handler.ghost_ordersMatched(), 10, "vacuous: cohort 1's orders were not all matched");
        assertGe(handler.ghost_fulfilments(), 1, "vacuous: no word delivered");
        assertGe(handler.ghost_frozenChecks(), 1, "vacuous: frozen inputs never re-checked");
        assertGe(handler.ghost_boxEpochChecks(), 1, "vacuous: sealed boxes never re-checked");
        assertGe(handler.ghost_battleLocks(), 1, "vacuous: no jackpot battle locked");
        assertGe(
            handler.ghost_buysWhileRequestOpen() + handler.ghost_boxBuysWhileRequestOpen()
                + handler.ghost_delaysWhileRequestOpen() + handler.ghost_nudgeAttemptsInDailyWindow(),
            1,
            "vacuous: no player action or delay while a request was open"
        );
    }

    /// @notice Campaign-wide minima are asserted on one deterministic sequence of the same
    ///         handler actions: a cohort priced at a mid-sale request, orders and boxes bought
    ///         while its word is out, a delay and a retry, then settled with every order matched.
    function test_handlerSequenceExercisesTheProperty() public {
        handler.nextDay(3600);
        handler.crank(11);
        handler.crank(11);
        assertTrue(handler.snapLive(), "cohort 1 priced and pending");
        assertEq(handler.snapCohort(), 1, "cohort 1");
        assertEq(handler.snapBoundDay(), 3, "bound to day 3");
        handler.buyDegenesis(1, 77);
        handler.buyBox(2, 300);
        handler.tryNudge(3);
        handler.crapsEnter(4, 9);
        handler.delay(0);
        handler.stallAndRetry();
        handler.fulfil(5);
        for (uint256 i; i < 6 && handler.snapLive(); ++i) handler.crank(11);
        assertFalse(handler.snapLive(), "cohort 1 closed");
        assertEq(handler.ghost_cohortsSettled(), 1, "cohort 1 settled");
        assertEq(handler.ghost_ordersMatched(), 10, "all ten orders matched the reference");
        assertGe(handler.ghost_buysWhileRequestOpen(), 1, "a Degenesis buy inside the window");
        assertGe(handler.ghost_boxBuysWhileRequestOpen(), 1, "a box buy inside the window");
        assertGe(handler.ghost_nudgeAttemptsInDailyWindow(), 1, "a refused nudge");
        assertEq(handler.ghost_retries(), 1, "the retry re-issued");
        invariant_degenesisOutcomesBindToTheirRequest();
        invariant_pricingRidesItsRequest();
        invariant_pendingInputsFrozen();
        invariant_sealedBoxesFrozen();
        invariant_jackpotBattleFrozen();
        invariant_noNudgeInDailyWindow();
    }

    /// @notice Falsifiability: a mutated lane of the pending cohort trips the frozen-input check.
    function test_detectorCatchesLaneMutation() public {
        handler.nextDay(3600);
        handler.crank(11);
        handler.crank(11);
        assertTrue(handler.snapLive(), "cohort pending");
        assertTrue(handler.debugSeedLaneMutationAndCheck(), "lane mutation detected");
        assertEq(handler.ghost_frozenInputMutations(), 0, "seam is counter-neutral");
    }

    /// @notice Falsifiability: a resolution off the reference by one FLIP trips the outcome check.
    function test_detectorCatchesOutcomeMismatch() public {
        // A long cohort, so it is still settling when its word is recorded.
        for (uint256 i; i < 300; ++i) {
            vm.prank(actors[i % 5]);
            game.buyDegenesisBox{value: 0.01 ether}(0, 0.01 ether);
        }
        handler.nextDay(3600);
        handler.crank(11);
        handler.crank(11);
        handler.fulfil(9);
        for (uint256 i; i < 40 && !handler.snapWordSeen(); ++i) handler.mine(9, i);
        assertTrue(handler.snapLive(), "still settling");
        assertTrue(handler.snapWordSeen(), "bound word recorded");
        assertTrue(handler.debugSeedOutcomeMismatchAndCheck(), "outcome mismatch detected");
        assertEq(handler.ghost_outcomeMismatches(), 0, "seam is counter-neutral");
    }
}
