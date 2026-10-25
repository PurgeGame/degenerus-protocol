// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";

/// @title PurchaseTimeoutLateCompletion
/// @notice With no purchases and every daily session finished on the wall day after its request,
///         the purchase timeout still ends the game: it keys on the last completed day, so it
///         fires at the first wall-day rollover after the deadline day completes, including
///         while the next day's request is outstanding (unanswered or answered, unprocessed).
contract PurchaseTimeoutLateCompletion is DeployProtocol {
    /// @dev The first purchase day is 9; day 39 is the last completed day that counts.
    uint24 private constant DEADLINE_DAY = 39;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        mockVRF.fundSubscription(1, 100e18);
    }

    function _answer() private {
        uint256 id = mockVRF.lastRequestId();
        if (id == 0) return;
        (,, bool done) = mockVRF.pendingRequests(id);
        if (!done) mockVRF.fulfillRandomWords(id, uint256(keccak256(abi.encode(id, "late"))));
    }

    function _mine() private returns (bool ok) {
        try game.mineRun(0) { ok = true; } catch {}
    }

    /// @dev Each wall day: finish yesterday's session, send the next request, answer it (unless
    ///      `holdNext` keeps the request after the deadline day unanswered), then stop mining
    ///      until the next wall day. Returns at the first wall day the ending is reported.
    function _lateCadenceToEnding(bool holdNext) private {
        uint256 t = vm.getBlockTimestamp();
        for (uint256 d; d < 80; ++d) {
            if (game.livenessTriggered()) return;
            uint24 before = game.currentDayView_g542950();
            for (uint256 i; i < 400; ++i) {
                if (!_mine()) {
                    _answer();
                    if (!_mine()) break;
                }
                if (game.currentDayView_g542950() != before) break;
            }
            uint24 day = game.currentDayView_g542950();
            require(day != before, "no request this wall day");
            if (!(holdNext && day == DEADLINE_DAY + 1)) _answer();
            t += 1 days;
            vm.warp(t);
        }
        revert("no ending within 80 wall days");
    }

    function _endsAtFirstRolloverAfterTheDeadlineDay(bool holdNext) private {
        _lateCadenceToEnding(holdNext);
        assertEq(game.currentDayView_g542950(), DEADLINE_DAY + 1, "day 40's request is outstanding");
        (bool complete,,) = game.dailySessionState();
        assertFalse(complete, "day 40 is not complete");

        for (uint256 i; i < 400 && !game.gameOver(); ++i) {
            _answer();
            _mine();
        }
        assertTrue(game.gameOver(), "the purchase timeout reached game over");
    }

    function test_endsWithNextRequestUnanswered() public {
        _endsAtFirstRolloverAfterTheDeadlineDay(true);
    }

    function test_endsWithNextRequestAnsweredUnprocessed() public {
        _endsAtFirstRolloverAfterTheDeadlineDay(false);
    }
}
