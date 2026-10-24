// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {DegenesisHarness} from "./helpers/DegenesisHarness.sol";

/// @title DegenesisDayMapping -- logical cohort sealing and calendar stalls
/// @notice Each accepted request opens one cohort. Calendar delays preserve the current cohort;
///         a sealed backlog may wait for the next request to bind its own word.
contract DegenesisDayMapping is DegenesisHarness {
    address internal a;
    address internal b;
    address internal c3;

    function setUp() public override {
        super.setUp();
        a = _player("dm-a");
        b = _player("dm-b");
        c3 = _player("dm-c");
        _drive(0);
        _earnCredit(a, 10 ether);
        _earnCredit(b, 10 ether);
        _earnCredit(c3, 10 ether);
    }

    function _splitDays(Vm.Log[] memory logs) internal view returns (uint256 mask) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length > 1 && logs[i].topics[0] == SIG_SPLIT) {
                mask |= uint256(1) << uint256(logs[i].topics[1]);
            }
        }
    }

    function _pricedDays(Vm.Log[] memory logs) internal view returns (uint256 mask, uint24 boundDay) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length > 1 && logs[i].topics[0] == SIG_PRICED) {
                mask |= uint256(1) << uint256(logs[i].topics[1]);
                (,, boundDay) = abi.decode(logs[i].data, (uint256, uint256, uint24));
            }
        }
    }

    function _open(uint24 day) internal {
        _warpTo(day, 1 hours);
        _drive(0);
        assertEq(game.currentDayView(), day, "one accepted request per logical day");
    }

    function test_BonusMeasuresExactLateRequestAndNeverWraps() public {
        _warpTo(2, 23 hours + 17);
        _drive(0);
        uint256 opened = vm.getBlockTimestamp();
        _buy(a, 0.01 ether);
        assertEq(_lane(1, 0) >> 70, 0, "late opening receives the full bonus");
        vm.warp(opened + 1 hours + 3);
        _buy(a, 0.01 ether);
        assertEq(_lane(1, 1) >> 70, 1 hours + 3, "cross-reset age stays exact");
        vm.warp(opened + 6 hours - 1);
        _buy(a, 0.01 ether);
        assertEq(_lane(1, 2) >> 70, 6 hours - 1);
        vm.warp(opened + 6 hours);
        _buy(a, 0.01 ether);
        assertEq(_lane(1, 3) >> 70, 6 hours);
        vm.warp(opened + 3 days);
        _buy(a, 0.01 ether);
        assertEq(_lane(1, 4) >> 70, 6 hours, "stalled cohort never reopens bonus");
        _drive(0);
        assertEq(game.currentDayView(), 3);
        _buy(a, 0.01 ether);
        assertEq(_lane(2, 0) >> 70, 0, "only a new daily request opens a new bonus");
    }

    function test_OpeningDayRequestLeavesCohortOneOpen() public {
        _warpTo(2, 10);
        vm.recordLogs();
        _drive(0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(game.currentDayView(), 2);
        assertEq(_closed(), 0);
        assertEq(_active(), 0);
        assertFalse(_split(1));
        assertEq(_countSig(logs, SIG_SPLIT) + _countSig(logs, SIG_PRICED), 0);
        _buy(a, 0.1 ether);
        _buy(b, 0.2 ether);
        assertEq(_count(1), 2);
        assertEq(_volumeUnits(1) * UNIT, 0.3 ether);
        _warpTo(3, 1 hours);
        vm.recordLogs();
        _drive(0);
        logs = vm.getRecordedLogs();
        assertEq(_splitDays(logs), 1 << 1);
        (uint256 priced, uint24 bound) = _pricedDays(logs);
        assertEq(priced, 1 << 1);
        assertEq(bound, 3);
    }

    function test_EachCohortSealedByTheNextAcceptedRequest() public {
        for (uint256 c = 1; c <= 7; ++c) {
            _warpTo(_dayOf(c), 30 minutes);
            vm.recordLogs();
            _drive(0);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            assertEq(game.currentDayView(), _dayOf(c));
            assertFalse(_split(c));
            if (c > 1) {
                assertEq(_splitDays(logs), uint256(1) << (c - 1));
                (uint256 priced, uint24 bound) = _pricedDays(logs);
                assertEq(priced, uint256(1) << (c - 1));
                assertEq(bound, _dayOf(c));
                assertEq(_closed(), c - 1);
            }
            _buy(a, 0.01 ether * c);
            _buy(b, 0.02 ether);
            assertEq(_count(c), 2);
        }
        _warpTo(9, 1 hours);
        // The reset alone leaves the seventh cohort open until its request is accepted.
        _buy(a, 0.01 ether);
        vm.recordLogs();
        _drive(0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_splitDays(logs), 1 << 7);
        (uint256 priced, uint24 bound) = _pricedDays(logs);
        assertEq(priced, 1 << 7);
        assertEq(bound, 9);
        assertEq(_closed(), 7);
        vm.prank(a);
        vm.expectRevert();
        game.buyDegenesisBox{value: 0.01 ether}(0, 0.01 ether);
    }

    function test_CalendarBoundaryDoesNotAssignANewCohort() public {
        _warpTo(2, 0);
        vm.prank(a);
        vm.expectRevert();
        game.buyDegenesisBox{value: 0.01 ether}(0, 0.01 ether);
        _drive(0);
        _buy(a, 0.01 ether);
        vm.warp(_dayStart(3) - 1);
        _buy(a, 0.02 ether);
        vm.warp(_dayStart(3));
        _buy(a, 0.03 ether);
        assertEq(game.currentDayView(), 2);
        assertEq(_count(1), 3);
        assertEq(_count(2), 0);
        _drive(0);
        _buy(a, 0.04 ether);
        assertEq(_count(2), 1);
    }

    function test_MissedCalendarRequestsSplitOnlyOneLogicalCohort() public {
        _open(2);
        _buy(a, 1.0001 ether);
        _warpTo(3, 2 hours);
        _buy(b, 2.5 ether);
        _buy(a, 0.0123 ether);
        _warpTo(4, 5 hours);
        _buy(c3, 0.7777 ether);
        _warpTo(5, 10);
        _buy(b, 0.3 ether);
        assertEq(game.currentDayView(), 2);
        assertEq(_count(1), 5);
        uint256 v = 4.5901 ether;
        assertEq(_volumeUnits(1) * UNIT, v);
        uint256 q = v / 4;
        _stepToRequest();
        uint256 claimable0 = game.claimablePoolView();
        uint256 future0 = _futureTotal();
        uint256 insurance0 = game.yieldAccumulatorView();
        uint256 vault0 = _vaultBudget();
        uint256 afk0 = _sdgnrsAfking();
        vm.recordLogs();
        game.mineFlip(0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(game.currentDayView(), 3);
        assertEq(claimable0 - game.claimablePoolView(), 2 * q);
        assertEq(_futureTotal() - future0, q);
        assertEq(game.yieldAccumulatorView() - insurance0, q);
        assertEq(_vaultBudget() - vault0, q);
        assertEq(_sdgnrsAfking() - afk0, q);
        assertEq(_splitDays(logs), 1 << 1);
        (uint256 priced, uint24 bound) = _pricedDays(logs);
        assertEq(priced, 1 << 1);
        assertEq(bound, 3);
        _drive(0);
        assertEq(game.currentDayView(), 3, "no calendar catch-up");
        assertEq(_closed(), 1);
    }

    function test_VrfStallKeepsOrdersInTheOutstandingLogicalCohort() public {
        _open(2);
        _buy(a, 0.4321 ether);
        _warpTo(3, 1 hours);
        _stepToRequest();
        game.mineFlip(0);
        uint256 stalled = mockVRF.lastRequestId();
        lastFulfilledReq = stalled;
        assertEq(game.currentDayView(), 3);
        assertTrue(_split(1));
        assertEq(_activeDay(), 3);
        _buy(b, 1.5 ether);
        _warpTo(4, 6 hours);
        _buy(c3, 0.0707 ether);
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        game.mineFlip(0);
        _warpTo(5, 2 hours);
        _buy(a, 0.02 ether);
        assertEq(_volumeUnits(2) * UNIT, 1.5907 ether);
        assertEq(_volumeUnits(3), 0);
        uint256 w3 = uint256(keccak256("stalled-word"));
        mockVRF.fulfillRandomWords(stalled, w3);
        vm.recordLogs();
        _drive(0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // Completion admits at most one fresh request in this later window.
        assertEq(game.currentDayView(), 4);
        assertEq(_splitDays(logs), 1 << 2);
        assertEq(game.rngWordForDay(3), w3);
        assertEq(game.rngWordForDay(5), 0);
        assertEq(_closed(), 1, "the old active cohort settles after the new request");
        _warpTo(6, 2 hours);
        _drive(0);
        assertEq(game.currentDayView(), 5);
        assertEq(_closed(), 2, "next request prices and settles the backlog");
    }
}
