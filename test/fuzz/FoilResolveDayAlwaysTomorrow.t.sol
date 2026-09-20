// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";

/// @notice A foil pack always resolves against the day after the buy, like a coinflip
///         deposit, so no state of the advance walk can hand it a resolving word that
///         already exists on chain.
contract FoilResolveDayAlwaysTomorrow is DeployProtocol {
    uint256 private constant WORD_NORMAL = 0xA11CE;
    uint256 private constant WORD_LATE = 0xBEEF_0001;
    uint256 private constant WORD_FRESH = 0xC0FFEE_0002;

    DegenerusGameLens private lens;
    uint256 private _t;
    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        lens = new DegenerusGameLens();
        mockVRF.fundSubscription(1, 100e18);
        _t = block.timestamp + 1 days;
        vm.warp(_t);
        vm.deal(address(game), 5_000_000 ether);
    }

    /// @dev Multi-day VRF stall: the fulfil crank records every gap day's word and the wall
    ///      day's and skips the gap. A buy before or after the wall day seals resolves
    ///      against a day whose word is still unset.
    function test_BuyDuringRewalkResolvesAgainstUnsetWord() public {
        _runStageNewDay(WORD_NORMAL);
        _runStageNewDay(WORD_NORMAL ^ 1);

        _t += 1 days;
        vm.warp(_t);
        game.advanceGame();
        uint24 R = game.currentDayView();
        uint256 reqR = mockVRF.lastRequestId();

        _t += 3 days;
        vm.warp(_t);
        uint24 W = game.currentDayView();
        assertEq(W, R + 3, "wall day is R+3");
        mockVRF.fulfillRandomWords(reqR, WORD_LATE);
        _advanceUntilUnlocked();
        assertEq(_dailyIdx(), R, "sealed R");

        game.advanceGame();
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), WORD_FRESH);
        game.advanceGame();
        assertTrue(game.rngWordForDay(W) != 0, "W's word recorded by the fulfil crank");
        assertEq(_dailyIdx(), W - 1, "gap days skipped");
        assertTrue(game.rngLocked(), "W's jackpot still owed under the lock");

        // Every word through W is public and the lock is up: a buy resolves against W+1.
        address early = makeAddr("foil_early");
        _buy(early);
        _assertResolvesTomorrow(early, W);

        // W seals; caught up and unlocked, a buy still resolves against W+1.
        _advanceUntilUnlocked();
        assertEq(_dailyIdx(), W, "sealed W");
        address late = makeAddr("foil_late");
        _buy(late);
        _assertResolvesTomorrow(late, W);
        _t += 1 days;
        vm.warp(_t);
        assertEq(game.rngWordForDay(W + 1), 0, "W+1 unrequested before its own day");
        game.advanceGame();
        assertTrue(game.rngLocked(), "W+1 requested on its own day");
    }

    /// @dev The pre-request slice on a normal day (wall day rolled, request not yet fired)
    ///      also resolves against tomorrow, not today.
    function test_PreRequestSliceResolvesAgainstTomorrow() public {
        _runStageNewDay(WORD_NORMAL);
        _runStageNewDay(WORD_NORMAL ^ 1);
        _t += 1 days;
        vm.warp(_t);
        uint24 today = game.currentDayView();
        assertEq(_dailyIdx(), today - 1, "wall day rolled, not yet advanced");
        assertFalse(game.rngLocked(), "no request yet");
        address buyer = makeAddr("foil_slice");
        _buy(buyer);
        _assertResolvesTomorrow(buyer, today);
    }

    function _buy(address buyer) private {
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        game.purchase{value: 50 ether}(buyer, 0, 0, bytes32(0), MintPaymentKind.DirectEth, true);
    }

    function _assertResolvesTomorrow(address buyer, uint24 wallDay) private view {
        uint24 lvl = game.level();
        DegenerusGameLens.FoilRecordEntry memory f = lens.foilRecordOf(address(game), lvl, buyer);
        if (!f.present) f = lens.foilRecordOf(address(game), lvl + 1, buyer);
        assertTrue(f.present, "foil record written");
        assertEq(f.resolveDay, wallDay + 1, "resolves against tomorrow");
        assertEq(game.rngWordForDay(f.resolveDay), 0, "resolving word unset at buy");
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
