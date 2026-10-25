// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {LogicalDaysFixture} from "./helpers/LogicalDaysFixture.sol";

contract StallDaysNeverHappened is LogicalDaysFixture {
    function test_StallRetainsRoundAndCreatesOnlyOneNextCommitment() public {
        _nextLogical(777);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        uint256 id = _requestLogical();
        uint24 day = game.currentDayView_g542950();
        uint24 wall = game.currentWallDayView();
        vm.warp(vm.getBlockTimestamp() + 8 days);
        assertEq(game.currentDayView_g542950(), day);
        assertEq(game.currentWallDayView(), wall + 8);
        mockVRF.fulfillRandomWords(id, 0xBEEF0001);
        _nextRequestAfter(id);
        assertEq(game.currentDayView_g542950(), day + 1);
        assertEq(coinflip.requestedDailyIdx(), day + 1);
        assertEq(game.rngWordForDay(day), 0xBEEF0001);
        assertEq(game.rngWordForDay(day + 1), 0);
        for (uint24 d = day + 1; d <= day + 8; ++d) {
            (uint16 result,) = coinflip.getCoinflipDayResult(d);
            assertEq(result, 0, "unrequested calendar dates have no coinflip");
        }
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 0xC0FFEE0002);
        _finishLogical();
        assertEq(game.currentDayView_g542950(), day + 1);
        (,uint24 sent,) = game.dailySessionState();
        assertEq(sent, game.currentWallDayView(), "actual send window owns pacing");
        assertEq(game.currentDayView_g542950(), day + 1);
    }
    function test_LateEntropyCannotRescueExpiredProgressDeadline() public {
        vm.warp(vm.getBlockTimestamp() + 1 days);
        uint256 id = _requestLogical();
        (,,uint48 completed) = game.dailySessionState();
        vm.warp(uint256(completed) + 14 days);
        mockVRF.fulfillRandomWords(id, 777);
        assertTrue(game.livenessTriggered());
        for (uint256 i; i < 100 && !game.gameOver(); ++i) game.mineRun(0);
        assertTrue(game.gameOver());
        assertEq(game.currentDayView_g542950(), 2);
        assertEq(game.rngWordForDay(2), 0, "expired normal result is never applied");
    }
}
