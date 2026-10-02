// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

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
/// coordinator authorization, request identity and duplicate protection run live.
contract RngCurrentSentinelTest is DeployProtocol {
    function setUp() public { _deployProtocol(); vm.warp(vm.getBlockTimestamp() + 1 days); }

    function _request() private returns (uint256 id) {
        assertEq(uint256(game.extsload(bytes32(uint256(3)))), 1, "initialized waiting payload");
        game.mineFlip();
        id = mockVRF.lastRequestId();
        assertGt(id, 0, "real request sent");
        assertTrue(game.rngLocked());
        assertFalse(game.isRngFulfilled());
    }

    function _check(uint256 input, uint64 nudges) private {
        uint256 id = _request();
        nudges = uint64(bound(nudges, 0, 256));
        RecyclingState.seedNudges(address(game), nudges);
        uint256 expected;
        unchecked { expected = input + nudges; }
        bytes32 state = game.extsload(bytes32(0));
        mockVRF.fulfillRandomWords(id, input);
        assertEq(game.extsload(bytes32(0)), state, "callback never writes nudge or lifecycle metadata");
        if (expected < 2) {
            assertFalse(game.isRngFulfilled(), "reserved final words leave the request unanswered");
            assertEq(uint256(game.extsload(bytes32(uint256(3)))), 1, "nonzero waiting sentinel retained");
            assertEq(RecyclingState.nudgeCount(address(game)), nudges, "retry keeps paid nudges");
            return;
        }
        assertTrue(game.isRngFulfilled(), "final word delivered");
        assertEq(RecyclingState.currentWord(address(game)), expected, "callback stores the final session word");
        uint256 stored = uint256(game.extsload(bytes32(uint256(3))));
        assertEq(stored, expected);
        mockVRF.fulfillRandomWordsRaw(id, address(game), 777777);
        assertEq(uint256(game.extsload(bytes32(uint256(3)))), stored, "duplicate must not replace delivered word");
        mockVRF.fulfillRandomWordsRaw(id + 1, address(game), 888888);
        assertEq(uint256(game.extsload(bytes32(uint256(3)))), stored, "wrong identity must not replace word");

        uint24 day = game.currentDayView();
        bytes memory gameCode = address(game).code;
        CurrentWordApplyHarness recorder = new CurrentWordApplyHarness();
        vm.etch(address(game), address(recorder).code);
        assertEq(CurrentWordApplyHarness(address(game)).applyCurrent(day), expected);
        vm.etch(address(game), gameCode);
        assertEq(game.rngWordForDay(day), expected, "entropy unchanged by encoding");
        assertEq(RecyclingState.nudgeCount(address(game)), 0, "nudge receipt cleared after one recording");
    }

    function test_ZeroFinalWordRemainsPending() public { _check(0, 0); }
    function test_OneRawWordWithNudgesIsStoredWithoutNormalization() public { _check(1, 3); }
    function test_NudgedZeroRemainsPending() public { _check(type(uint256).max, 1); }
    function test_OneFinalWordRemainsPending() public { _check(1, 0); }
    function test_NudgedOneRemainsPending() public { _check(type(uint256).max, 2); }
    function test_NudgedWrapToTwoIsDeliveredUnchanged() public { _check(type(uint256).max, 3); }
    function test_ZeroRawWordWithNudgesNeedsNoFallback() public { _check(0, 256); }
    function test_ReservedFinalWordRecoversThroughExistingOwnerRetry() public {
        uint256 id = _request();
        RecyclingState.seedNudges(address(game), 1);
        mockVRF.fulfillRandomWords(id, type(uint256).max);
        assertFalse(game.isRngFulfilled());
        vm.warp(vm.getBlockTimestamp() + 20 hours);
        vm.prank(ContractAddresses.CREATOR);
        admin.retryGameRng();
        uint256 retry = mockVRF.lastRequestId();
        assertGt(retry, id, "existing owner retry replaces the reserved result");
        mockVRF.fulfillRandomWordsRaw(id, address(game), 42);
        assertEq(RecyclingState.currentWord(address(game)), 0, "retired callback rejected");
        mockVRF.fulfillRandomWords(retry, 42);
        assertEq(RecyclingState.currentWord(address(game)), 43, "replacement applies the preserved nudge exactly once");
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
        game.updateVrfCoordinatorAndSub(address(next), sub, bytes32(uint256(1)));
        assertEq(next.lastRequestId(), 0, "delivered word is not retried");
        assertTrue(game.isRngFulfilled());
        assertEq(RecyclingState.currentWord(address(game)), 42);
    }

    function test_ConsumedDailyLockRetainsWordUntilTheNextRequest() public {
        uint256 id = _request();
        mockVRF.fulfillRandomWords(id, 42);
        for (uint256 i; i < 100 && game.rngLocked(); ++i) game.mineFlip();
        assertFalse(game.rngLocked(), "day completed");
        assertEq(uint256(game.extsload(bytes32(uint256(3)))), 42, "read consumers retain the final word after daily unlock");
        assertFalse(game.isRngFulfilled());
        assertEq(game.rngWordForDay(game.currentDayView()), 42, "session word recorded unchanged");
        vm.warp(vm.getBlockTimestamp() + 1 days);
        for (uint256 i; i < 100 && mockVRF.lastRequestId() == id; ++i) game.mineFlip();
        assertGt(mockVRF.lastRequestId(), id, "next real request remains live");
        assertFalse(game.isRngFulfilled());
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 2);
        assertEq(RecyclingState.currentWord(address(game)), 2);
    }
}
