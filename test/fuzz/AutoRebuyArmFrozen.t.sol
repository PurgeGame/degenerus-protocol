// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";

/// @notice A position already on auto-rebuy is frozen from the daily request until that day's flip
///         is applied: it holds a carry the pending word prices, so toggling off would extract it
///         before a known loss. Arming stays open: it first settles every published outcome and
///         can only affect the following unknown round. Wall time creates no extra unresolved day.
contract AutoRebuyArmFrozen is DeployProtocol {
    uint256 private constant WORD_NORMAL = 0xA11CE;
    uint256 private constant WORD_LATE = 0xBEEF_0001;
    uint256 private constant WORD_FRESH = 0xC0FFEE_0002;

    error RngLocked();

    address private player = makeAddr("rebuy_player");
    address private armed = makeAddr("rebuy_armed");
    address private late = makeAddr("rebuy_late");
    uint256 private _t;
    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 100e18);
        _t = block.timestamp + 1 days;
        vm.warp(_t);
        vm.deal(address(game), 5_000_000 ether);
    }

    function test_ArmedPositionFrozenFromRequestUntilItsDayResolves() public {
        _runStageNewDay(WORD_NORMAL);
        _runStageNewDay(WORD_NORMAL ^ 1);

        // Caught up: arming and disarming are open. One position stays armed into the request.
        vm.prank(player);
        coinflip.setCoinflipAutoRebuy(0, true, 0);
        vm.prank(player);
        coinflip.setCoinflipAutoRebuy(0, false, 0);
        vm.prank(armed);
        coinflip.setCoinflipAutoRebuy(0, true, 0);

        _t += 1 days;
        vm.warp(_t);
        uint256 reqR = _requestFreshDaily();
        uint24 R = game.currentDayView_g542950();
        _t += 3 days;
        vm.warp(_t);
        assertEq(game.currentDayView_g542950(), R, "a stall creates no further game day");

        // Word outstanding: the armed position is frozen. A new position may still arm (its
        // arming settles only published outcomes), and once armed it is frozen like the rest.
        vm.prank(armed);
        vm.expectRevert(RngLocked.selector);
        coinflip.setCoinflipAutoRebuy(0, false, 0);
        vm.prank(late);
        coinflip.setCoinflipAutoRebuy(0, true, 0);
        vm.prank(late);
        vm.expectRevert(RngLocked.selector);
        coinflip.setCoinflipAutoRebuy(0, false, 0);

        // Word delivered but not yet applied: still frozen (the result is readable now).
        mockVRF.fulfillRandomWords(reqR, WORD_LATE);
        vm.prank(armed);
        vm.expectRevert(RngLocked.selector);
        coinflip.setCoinflipAutoRebuy(0, false, 0);

        // R seals on its late word. Once R's read cohort drains, the same crank chain issues the
        // next day's request under the lock: there is no unlocked window between them.
        uint256 fresh = _requestFreshDaily();
        assertEq(game.currentDayView_g542950(), R + 1, "the next request advances exactly one logical day");
        vm.prank(armed);
        vm.expectRevert(RngLocked.selector);
        coinflip.setCoinflipAutoRebuy(0, false, 0);
        mockVRF.fulfillRandomWords(fresh, WORD_FRESH);
        game.mineFlip(0); // apply the word: the requested day is resolved, the lock still held
        // Nothing unresolved remains, so the armed positions are free even under the lock.
        vm.prank(armed);
        coinflip.setCoinflipAutoRebuy(0, false, 0);
        vm.prank(late);
        coinflip.setCoinflipAutoRebuy(0, false, 0);

        _advanceUntilUnlocked();
        assertEq(_dailyIdx(), R + 1, "sealed the requested day");
    }

    function _runStageNewDay(uint256 vrfWord) internal {
        _settleClean(vrfWord ^ 0xF00D);
        _t += 1 days;
        vm.warp(_t);
        _settleClean(vrfWord);
    }

    /// @dev Settle the current day: deliver every outstanding request (the daily one and any
    ///      mid-day request the crank issues for pending value or a shut Craps window) and
    ///      drain its consumers, returning once today is sealed, unlocked and idle.
    function _settleClean(uint256 vrfWord) internal {
        for (uint256 d; d < 240; d++) {
            _fulfillPending(vrfWord);
            if (_daySealed()) return;
            if (game.advanceDue()) game.mineFlip(0);
        }
        revert("harness: day never settled");
    }

    /// @dev A false advance hint can mean the read cohort must drain first, or that a
    ///      delivered mid-day request still waits for its word.
    function _daySealed() internal view returns (bool) {
        uint24 sealedDay = uint24(uint256(vm.load(address(game), bytes32(uint256(0)))) >> 24);
        return game.currentDayView_g542950() == sealedDay && !game.advanceDue() && !game.rngLocked()
            && !_requestOutstanding();
    }

    function _requestOutstanding() internal view returns (bool) {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return false;
        (,, bool fulfilled) = mockVRF.pendingRequests(reqId);
        return !fulfilled;
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

    /// @dev Finish the previous cohort at a fixed clock before expecting a new request.
    function _requestFreshDaily() internal returns (uint256 id) {
        uint256 previous = mockVRF.lastRequestId();
        for (uint256 i; i < 80; ++i) {
            game.mineFlip(0);
            id = mockVRF.lastRequestId();
            if (id != previous) {
                assertTrue(game.rngLocked(), "the new daily request holds the lock");
                return id;
            }
        }
        revert("harness: no fresh daily request");
    }

    function _advanceUntilUnlocked() internal {
        for (uint256 i; i < 64; i++) {
            if (!game.rngLocked()) return;
            game.mineFlip(0);
        }
        revert("harness: lock never released");
    }

    function _dailyIdx() internal view returns (uint24) {
        return uint24(uint256(vm.load(address(game), bytes32(uint256(0)))) >> 24);
    }
}
