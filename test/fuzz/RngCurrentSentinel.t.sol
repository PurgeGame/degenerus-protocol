// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {OwnerTargetCall} from "../helpers/OwnerTargetCall.sol";

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {DegenerusGameRngUtils} from "../../contracts/modules/DegenerusGameRngUtils.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";

contract CurrentWordApplyHarness is DegenerusGameRngUtils {
    function applyCurrent(uint24 day) external returns (uint256) {
        return _applyDailyRng(day, _currentRngWord());
    }
}

/// @dev Real Game callbacks, then the same shared daily recorder used by both
/// delegate modules. Only the isolated post-callback recorder is overlaid;
/// coordinator authorization and request identity run live.
contract RngCurrentSentinelTest is DeployProtocol {
    function setUp() public { _deployProtocol(); vm.warp(vm.getBlockTimestamp() + 1 days); }

    function _request() private returns (uint256 id) {
        assertEq(uint256(game.extsload_g2807007(bytes32(uint256(3)))), 1, "initialized waiting payload");
        game.mineRun(0);
        id = mockVRF.lastRequestId();
        assertGt(id, 0, "real request sent");
        assertTrue(game.rngLocked());
        assertFalse(game.isRngFulfilled());
    }

    /// @dev The callback stores the raw word for every request; the recorder keeps it as the
    ///      day word and returns raw + nudges as the coinflip's word alone.
    function _check(uint256 input, uint64 nudges) private {
        uint256 id = _request();
        nudges = uint64(bound(nudges, 0, 255));
        RecyclingState.seedNudges(address(game), nudges);
        uint256 coinWord;
        unchecked { coinWord = input + nudges; }
        bytes32 state = game.extsload_g2807007(bytes32(0));
        mockVRF.fulfillRandomWords(id, input);
        assertEq(game.extsload_g2807007(bytes32(0)), state, "callback never writes nudge or lifecycle metadata");
        if (input < 2) {
            assertFalse(game.isRngFulfilled(), "reserved raw words leave the request unanswered");
            assertEq(uint256(game.extsload_g2807007(bytes32(uint256(3)))), 1, "nonzero waiting sentinel retained");
            assertEq(RecyclingState.nudgeCount(address(game)), nudges, "retry keeps paid nudges");
            return;
        }
        assertTrue(game.isRngFulfilled(), "raw word delivered");
        assertEq(RecyclingState.currentWord(address(game)), input, "callback stores the raw session word");
        uint256 stored = uint256(game.extsload_g2807007(bytes32(uint256(3))));
        vm.expectRevert("already fulfilled");
        mockVRF.fulfillRandomWords(id, 777777);
        mockVRF.fulfillRandomWordsRaw(id + 1, address(game), 888888);
        assertEq(uint256(game.extsload_g2807007(bytes32(uint256(3)))), stored, "wrong identity must not replace word");

        uint24 day = game.currentDayView_g542950();
        bytes memory gameCode = address(game).code;
        CurrentWordApplyHarness recorder = new CurrentWordApplyHarness();
        vm.etch(address(game), address(recorder).code);
        assertEq(CurrentWordApplyHarness(address(game)).applyCurrent(day), coinWord, "coin word adds the nudges");
        vm.etch(address(game), gameCode);
        assertEq(game.rngWordForDay(day), input, "recorded day word stays raw");
        assertEq(RecyclingState.nudgeCount(address(game)), 0, "nudge receipt cleared after one recording");
    }

    function _resolvedCoinResult(uint256 word, bool reverse) private returns (bool win) {
        if (reverse) {
            (, uint256 cost) = game.rngNudgeQuote();
            vm.prank(address(game));
            coin.mintForGame_g152734(address(this), cost);
            game.reverseFlip(cost);
        }
        uint256 id = _request();
        uint24 day = game.currentDayView_g542950();
        mockVRF.fulfillRandomWords(id, word);
        assertEq(RecyclingState.currentWord(address(game)), word, "callback stores the raw word");
        for (uint256 i; i < 100 && game.rngLocked(); ++i) game.mineRun(0);
        assertEq(game.rngWordForDay(day), word, "every other consumer reads the raw word");
        (, win) = coinflip.getCoinflipDayResult(day);
    }

    function testFuzz_OnePaidReverseAlwaysFlipsTheDailyCoin(uint256 word) public {
        // The callback deliberately retries raw sentinel values 0 and 1.
        word = bound(word, 2, type(uint256).max - 1);
        uint256 snap = vm.snapshotState();
        bool original = _resolvedCoinResult(word, false);
        assertTrue(vm.revertToState(snap));
        bool reversed = _resolvedCoinResult(word, true);
        assertTrue(original != reversed, "one paid reverse always toggles the day's result");
    }

    function test_ZeroFinalWordRemainsPending() public { _check(0, 0); }
    function test_OneRawWordWithNudgesRemainsPending() public { _check(1, 3); }
    function test_MaxWordWithOneNudgeIsDeliveredRaw() public { _check(type(uint256).max, 1); }
    function test_OneFinalWordRemainsPending() public { _check(1, 0); }
    function test_MaxWordWithTwoNudgesIsDeliveredRaw() public { _check(type(uint256).max, 2); }
    function test_NudgedCoinWordWrapsWithoutTouchingTheRawWord() public { _check(type(uint256).max, 3); }
    function test_ZeroRawWordWithNudgesNeedsNoFallback() public { _check(0, 256); }
    function test_ReservedFinalWordRecoversThroughExistingOwnerRetry() public {
        uint256 id = _request();
        RecyclingState.seedNudges(address(game), 1);
        mockVRF.fulfillRandomWords(id, 1);
        assertFalse(game.isRngFulfilled(), "a reserved raw word is refused despite the nudge");
        vm.warp(vm.getBlockTimestamp() + 20 hours);
        vm.prank(ContractAddresses.CREATOR);
        OwnerTargetCall.call(address(admin), abi.encodeCall(admin.retryGameRng, ()), 0);
        uint256 retry = mockVRF.lastRequestId();
        assertGt(retry, id, "existing owner retry replaces the reserved result");
        mockVRF.fulfillRandomWordsRaw(id, address(game), 42);
        assertEq(RecyclingState.currentWord(address(game)), 0, "retired callback rejected");
        mockVRF.fulfillRandomWords(retry, 42);
        assertEq(RecyclingState.currentWord(address(game)), 42, "replacement stores the raw word");
        assertEq(RecyclingState.nudgeCount(address(game)), 1, "the nudge stays frozen for the coinflip");
    }

    function test_MaxWordWithoutNudgeRemainsMax() public { _check(type(uint256).max, 0); }
    function testFuzz_FinalWordPreservesEntropyOrRemainsPending(uint256 input, uint64 nudges) public { _check(input, nudges); }

    function test_DeliveredWordSurvivesCoordinatorRotationWithoutNewRequest() public {
        uint256 id = _request();
        mockVRF.fulfillRandomWords(id, 42);
        MockVRFCoordinator next = new MockVRFCoordinator();
        uint256 sub = next.createSubscription();
        next.addConsumer(sub, address(game));
        vm.prank(ContractAddresses.ADMIN);
        game.updateVrfCoordinatorAndSub(address(next), sub, bytes32(uint256(1)), 300_000);
        assertEq(next.lastRequestId(), 0, "delivered word is not retried");
        assertTrue(game.isRngFulfilled());
        assertEq(RecyclingState.currentWord(address(game)), 42);
    }

    function test_ConsumedDailyLockRetainsWordUntilTheNextRequest() public {
        uint256 id = _request();
        mockVRF.fulfillRandomWords(id, 42);
        for (uint256 i; i < 100 && game.rngLocked(); ++i) game.mineRun(0);
        assertFalse(game.rngLocked(), "day completed");
        assertEq(uint256(game.extsload_g2807007(bytes32(uint256(3)))), 42, "read consumers retain the final word after daily unlock");
        assertFalse(game.isRngFulfilled());
        assertEq(game.rngWordForDay(game.currentDayView_g542950()), 42, "session word recorded unchanged");
        vm.warp(vm.getBlockTimestamp() + 1 days);
        for (uint256 i; i < 100 && mockVRF.lastRequestId() == id; ++i) game.mineRun(0);
        assertGt(mockVRF.lastRequestId(), id, "next real request remains live");
        assertFalse(game.isRngFulfilled());
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 2);
        assertEq(RecyclingState.currentWord(address(game)), 2);
    }
}
