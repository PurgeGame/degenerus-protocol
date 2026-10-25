// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";

/// @notice A real thirty-round purchase phase, including seeded flips and a paid deity,
/// reaches normal terminal settlement at maximum calibration within one transaction's cap.
contract LogicalTerminalMaximumMultiplierTest is DeployProtocol {
    function _mine() private {
        game.mineFlip{gas: 16_777_216}(type(uint32).max);
    }

    function _answer(uint256 word) private {
        uint256 request = mockVRF.lastRequestId();
        if (request == 0) return;
        (,, bool fulfilled) = mockVRF.pendingRequests(request);
        if (!fulfilled) mockVRF.fulfillRandomWords(request, word);
    }

    function test_ThirtyRealRoundsThenNormalEndingAtMaximumMultiplier() public {
        _deployProtocol();
        address deity = address(0xD317A);
        vm.deal(deity, 24 ether);
        vm.prank(deity);
        game.purchaseDeityPass{value: 24 ether}(0, 4, bytes32(0));
        for (uint256 round; round < 30; ++round) {
            uint24 previous = game.currentDayView_g542950();
            vm.warp(vm.getBlockTimestamp() + 1 days);
            for (uint256 call; call < 500 && game.currentDayView_g542950() == previous; ++call) {
                _answer(9000 + round);
                _mine();
            }
            assertEq(game.currentDayView_g542950(), previous + 1, "one accepted round per reset");
            _answer(9000 + round);
            for (uint256 call; call < 500; ++call) {
                (bool complete,,) = game.dailySessionState();
                if (complete) break;
                _mine();
            }
            (bool done,,) = game.dailySessionState();
            assertTrue(done, "every round receives its final completion certificate");
        }
        assertEq(game.currentDayView_g542950(), 39);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        assertTrue(game.livenessTriggered(), "normal timeout after thirty completed rounds");
        for (uint256 call; call < 500 && game.gameOverTimestamp() == 0; ++call) {
            _answer(1234567);
            _mine();
        }
        assertTrue(game.gameOver());
        assertGt(game.gameOverTimestamp(), 0, "the complete terminal path fits its first-unit gas envelope");
    }
}
