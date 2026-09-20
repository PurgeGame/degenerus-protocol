// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";

/// @notice Arming coinflip auto-rebuy is frozen while two or more days are unresolved, so a
///         delivered word whose derived results are already readable cannot be compounded
///         through by a position that arms after seeing them.
contract AutoRebuyArmFrozen is DeployProtocol {
    uint256 private constant WORD_NORMAL = 0xA11CE;
    uint256 private constant WORD_LATE = 0xBEEF_0001;
    uint256 private constant WORD_FRESH = 0xC0FFEE_0002;

    error RngLocked();

    address private player = makeAddr("rebuy_player");
    address private armed = makeAddr("rebuy_armed");
    uint256 private _t;
    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 100e18);
        _t = block.timestamp + 1 days;
        vm.warp(_t);
        vm.deal(address(game), 5_000_000 ether);
    }

    function test_ArmingFrozenFromFulfilUntilTheDaySeals() public {
        _runStageNewDay(WORD_NORMAL);
        _runStageNewDay(WORD_NORMAL ^ 1);

        // Caught up: arming is open. One position stays armed into the stall.
        vm.prank(player);
        coinflip.setCoinflipAutoRebuy(address(0), true, 0);
        vm.prank(player);
        coinflip.setCoinflipAutoRebuy(address(0), false, 0);
        vm.prank(armed);
        coinflip.setCoinflipAutoRebuy(address(0), true, 0);

        _t += 1 days;
        vm.warp(_t);
        game.advanceGame();
        uint256 reqR = mockVRF.lastRequestId();
        _t += 3 days;
        vm.warp(_t);
        uint24 W = game.currentDayView();

        // Stalled with the word outstanding: arming frozen, and the armed position frozen.
        vm.prank(player);
        vm.expectRevert(RngLocked.selector);
        coinflip.setCoinflipAutoRebuy(address(0), true, 0);
        vm.prank(armed);
        vm.expectRevert(RngLocked.selector);
        coinflip.setCoinflipAutoRebuy(address(0), false, 0);

        // Word delivered but not yet applied: still frozen (results are readable now).
        mockVRF.fulfillRandomWords(reqR, WORD_LATE);
        vm.prank(player);
        vm.expectRevert(RngLocked.selector);
        coinflip.setCoinflipAutoRebuy(address(0), true, 0);

        _advanceUntilUnlocked();
        game.advanceGame();
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), WORD_FRESH);
        game.advanceGame(); // backfill: every day through W resolved, lock still held
        // Nothing unresolved remains, so arming is open even under the lock: a known run can
        // only be claimed plainly, never compounded.
        vm.prank(player);
        coinflip.setCoinflipAutoRebuy(address(0), true, 0);
        vm.prank(armed);
        coinflip.setCoinflipAutoRebuy(address(0), false, 0);

        _advanceUntilUnlocked();
        assertEq(_dailyIdx(), W, "sealed W");
    }

    function _runStageNewDay(uint256 vrfWord) internal {
        _settleClean(vrfWord ^ 0xF00D);
        _t += 1 days;
        vm.warp(_t);
        _settleClean(vrfWord);
    }

    function _settleClean(uint256 vrfWord) internal {
        for (uint256 d; d < 240; d++) {
            if (!game.advanceDue() && !game.rngLocked()) return;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.advanceGame();
            _fulfillPending(vrfWord);
        }
    }

    function _fulfillPending(uint256 vrfWord) internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            (,, bool fulfilled) = mockVRF.pendingRequests(reqId);
            if (!fulfilled) {
                mockVRF.fulfillRandomWords(reqId, vrfWord);
                _lastFulfilledReqId = reqId;
            }
        }
    }

    function _advanceUntilUnlocked() internal {
        for (uint256 i; i < 64; i++) {
            if (!game.rngLocked()) return;
            game.advanceGame();
        }
        revert("harness: lock never released");
    }

    function _dailyIdx() internal view returns (uint24) {
        return uint24(uint256(vm.load(address(game), bytes32(uint256(0)))) >> 24);
    }
}
