// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @notice The eight-reset interruption that formerly made purchaseStartDay outrun
///         the processed day must preserve one commitment and never compensate the baseline.
contract AdvanceGapBackfillBrick is DeployProtocol {
    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 1_000 ether);
    }

    function _request() private returns (uint256) {
        for (uint256 i; i < 200 && !game.rngLocked(); ++i) game.mineRun(0);
        assertTrue(game.rngLocked());
        return mockVRF.lastRequestId();
    }

    function test_C2_purchasePhaseStall_advanceGameSurvives() public {
        address buyer = makeAddr("buyer");
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        game.purchaseOrderFor{value: 0.05 ether}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        uint24 baseline = uint24(uint256(vm.load(address(game), bytes32(0))));
        vm.warp(block.timestamp + 1 days);
        uint256 request = _request();
        uint24 committed = game.currentDayView_g542950();
        uint256 pool = coinflip.recordPool();
        vm.warp(block.timestamp + 8 days);
        assertEq(game.currentDayView_g542950(), committed, "calendar gaps create no rounds");
        mockVRF.fulfillRandomWords(request, 0xCAFEBABE);
        for (uint256 i; i < 500; ++i) {
            if (mockVRF.lastRequestId() != request) break;
            game.mineRun(0);
        }
        assertEq(uint24(uint256(vm.load(address(game), bytes32(0)))), baseline,
            "no purchase-clock compensation or underflow");
        assertEq(game.currentDayView_g542950(), committed + 1, "one next request, no backfill");
        assertEq(coinflip.requestedDailyIdx(), committed + 1);
        assertEq(coinflip.recordPool(), pool + 2_000, "only the real result funds rewards");
        (uint16 reward, bool win) = coinflip.getCoinflipDayResult(committed);
        assertEq(reward, 1);
        assertFalse(win);
        (reward,) = coinflip.getCoinflipDayResult(committed + 1);
        assertEq(reward, 0, "following round still needs its own word");
        assertFalse(game.gameOver());
    }
}
