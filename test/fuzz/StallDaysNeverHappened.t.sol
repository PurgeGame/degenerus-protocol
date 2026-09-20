// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";

/// @notice A multi-day VRF stall resolves the day that requested the word with that word,
///         settles the skipped days' coinflips from derived words, and then resumes at the
///         wall day under the lock. The skipped days get no daily draw and no seal, so the
///         engine is never unlocked while a recorded word sits ahead of the sealed day.
contract StallDaysNeverHappened is DeployProtocol {
    uint256 private constant WORD_NORMAL = 0xA11CE;
    uint256 private constant WORD_LATE = 0xBEEF_0001;
    uint256 private constant WORD_FRESH = 0xC0FFEE_0002;
    uint256 private constant FOIL_DRAW_SLOT = 60;

    uint256 private _t;
    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 100e18);
        _t = block.timestamp + 1 days;
        vm.warp(_t);
        vm.deal(address(game), 5_000_000 ether);
    }

    function test_StallSkipsGapDaysAndResumesAtWallDayUnderLock() public {
        _runStageNewDay(WORD_NORMAL);
        _runStageNewDay(WORD_NORMAL ^ 1);

        _t += 1 days;
        vm.warp(_t);
        game.advanceGame();
        uint24 R = game.currentDayView();
        uint256 reqR = mockVRF.lastRequestId();
        assertTrue(game.rngLocked(), "day R: request outstanding");

        // Three days pass with the word outstanding, then it lands.
        _t += 3 days;
        vm.warp(_t);
        uint24 W = game.currentDayView();
        assertEq(W, R + 3, "wall day is R+3");
        mockVRF.fulfillRandomWords(reqR, WORD_LATE);

        // R resolves with its own word (buffered clamp), seals, unlocks.
        _advanceUntilUnlocked();
        _assertNoWordAheadWhenUnlocked();
        assertEq(_dailyIdx(), R, "sealed R with the word it requested");
        assertEq(game.rngWordForDay(R + 1), 0, "R+1 untouched by R's word");

        // W requests fresh; on delivery the gap R+1..W-1 is backfilled and skipped.
        game.advanceGame();
        assertTrue(game.rngLocked(), "W requested fresh");
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), WORD_FRESH);
        game.advanceGame(); // backfill tx
        assertTrue(game.rngLocked(), "lock still held after the backfill");
        assertTrue(game.rngWordForDay(R + 1) != 0, "R+1 has a derived word");
        assertTrue(game.rngWordForDay(R + 2) != 0, "R+2 has a derived word");
        assertTrue(game.rngWordForDay(W) != 0, "W recorded");
        assertEq(_dailyIdx(), W - 1, "gap days skipped: index parked at W-1");
        assertEq(_foilDraw(R + 1), 0, "no daily draw for R+1");
        assertEq(_foilDraw(R + 2), 0, "no daily draw for R+2");

        // The next advances pay W's jackpot under the lock and seal W.
        _advanceUntilUnlocked();
        assertEq(_dailyIdx(), W, "sealed W");
        assertEq(_foilDraw(R + 1), 0, "still no draw for R+1");
        assertEq(_foilDraw(R + 2), 0, "still no draw for R+2");
        assertTrue(_foilDraw(W) != 0, "W got its draw");
        _assertNoWordAheadWhenUnlocked();

        // The following day is an ordinary fresh-request day.
        _t += 1 days;
        vm.warp(_t);
        assertEq(game.rngWordForDay(W + 1), 0, "W+1 unrequested before its day");
        game.advanceGame();
        assertTrue(game.rngLocked(), "W+1 requested on its own day");
    }

    /// @dev A stall past the VRF deadman is terminal in every phase: the game goes over and
    ///      pays out instead of walking or skipping the gap.
    function test_StallPastDeadmanEndsTheGame() public {
        _runStageNewDay(WORD_NORMAL);
        _runStageNewDay(WORD_NORMAL ^ 1);
        _t += 1 days;
        vm.warp(_t);
        game.advanceGame();
        uint256 reqR = mockVRF.lastRequestId();

        _t += 130 days;
        vm.warp(_t);
        assertTrue(game.livenessTriggered(), "no sealed day for 130 days: liveness fired");
        mockVRF.fulfillRandomWords(reqR, WORD_LATE);
        for (uint256 i; i < 40 && !game.gameOver(); ++i) {
            game.advanceGame();
            uint256 reqId = mockVRF.lastRequestId();
            (,, bool fulfilled) = mockVRF.pendingRequests(reqId);
            if (reqId != 0 && !fulfilled) mockVRF.fulfillRandomWords(reqId, WORD_FRESH + i);
        }
        assertTrue(game.gameOver(), "terminal payout reached");
    }

    /// @dev The invariant the freeze rests on: whenever the lock is down, no word is
    ///      recorded for the day the next seal will draw. (Game over is the one exception:
    ///      the terminal seal keeps dailyIdx stale on purpose, and no live draw remains.)
    function _assertNoWordAheadWhenUnlocked() private view {
        if (!game.rngLocked()) {
            assertEq(game.rngWordForDay(_dailyIdx() + 1), 0, "unlocked with a word ahead");
        }
    }

    function _foilDraw(uint24 day) private view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(day), FOIL_DRAW_SLOT))));
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
