// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {LogicalDaysFixture} from "./helpers/LogicalDaysFixture.sol";

/// @notice Fuzz delayed commitments across reset windows without synthetic gap outcomes.
contract VRFPathCoverage is LogicalDaysFixture {
    function testFuzz_DelayedWordStaysWithItsSingleRound(uint256 word, uint8 elapsed) public {
        word = bound(word, 2, type(uint256).max);
        uint256 gap = bound(elapsed, 1, 12);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        uint256 id = _requestLogical();
        uint256 pool = coinflip.recordPool();
        vm.warp(vm.getBlockTimestamp() + gap * 1 days);
        mockVRF.fulfillRandomWords(id, word);
        _nextRequestAfter(id);
        assertEq(game.currentDayView_g542950(), 3);
        assertEq(game.rngWordForDay(2), word);
        assertEq(coinflip.recordPool(), pool + 2_000);
        (uint16 reward, bool win) = coinflip.getCoinflipDayResult(2);
        assertGt(reward, 0);
        assertEq(win, word & 1 == 1);
        for (uint24 d = 3; d <= 14; ++d) {
            (reward,) = coinflip.getCoinflipDayResult(d);
            assertEq(reward, 0);
        }
    }
    function test_SentinelWordDoesNotCreateAResult() public {
        vm.warp(vm.getBlockTimestamp() + 1 days);
        mockVRF.fulfillRandomWords(_requestLogical(), 0);
        assertTrue(game.rngLocked());
        assertEq(game.currentDayView_g542950(), 2);
        assertEq(game.rngWordForDay(2), 0);
        assertEq(coinflip.requestedDailyIdx(), 2);
    }
    function testFuzz_RequestPacingUsesActualSendWindow(uint8 elapsed) public {
        vm.warp(vm.getBlockTimestamp() + bound(elapsed, 1, 12) * 1 days);
        uint256 id = _requestLogical();
        (,uint24 sent,) = game.dailySessionState();
        assertEq(sent, game.currentWallDayView());
        mockVRF.fulfillRandomWords(id, 777);
        _finishLogical();
        assertFalse(game.advanceDue());
        assertEq(mockVRF.lastRequestId(), id);
    }
}
