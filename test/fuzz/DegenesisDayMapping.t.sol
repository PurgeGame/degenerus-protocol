// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {DegenesisHarness} from "./helpers/DegenesisHarness.sol";

/// @title DegenesisDayMapping -- cohort sealing, the opening-day request and the catch-up split
/// @notice Spec §6 / §9 and plan §3.3: cohort c (protocol day index c + 1) is sealed exactly from
///         the first daily request after its own day. The opening day's request (index 2) leaves
///         cohort 1 open. A request after a stretch with no requests splits every sealed cohort at
///         once, exact in wei: claimablePool -2q, future pool +2q, Vault budget +q, sDGNRS AFKing +q.
///         Days are driven through mineFlip with mock VRF; credit comes from real lootbox buys.
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

    /// @notice The opening day's request (day index 2) neither splits, prices nor closes cohort 1,
    ///         and cohort 1 keeps taking orders after it.
    function test_OpeningDayRequestLeavesCohortOneOpen() public {
        _warpTo(2, 10);
        _buy(a, 0.1 ether);
        vm.recordLogs();
        _drive(0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(game.currentDayView(), 2, "on day 2");
        assertEq(_closed(), 0, "cohort 1 not closed as empty");
        assertEq(_active(), 0, "cohort 1 not priced");
        assertFalse(_split(1), "cohort 1 not split");
        assertEq(_word(), 0, "no word bound");
        assertEq(_countSig(logs, SIG_SPLIT) + _countSig(logs, SIG_PRICED) + _countSig(logs, SIG_CLOSED), 0, "no cohort events");

        _buy(b, 0.2 ether);
        assertEq(_count(1), 2, "cohort 1 still accepting");
        assertEq(_volumeUnits(1) * UNIT, 0.3 ether, "cohort 1 volume");

        _warpTo(3, 1 hours);
        vm.recordLogs();
        _drive(0);
        logs = vm.getRecordedLogs();
        assertEq(_splitDays(logs), 1 << 1, "day-3 request splits cohort 1");
        (uint256 priced, uint24 bound) = _pricedDays(logs);
        assertEq(priced, 1 << 1, "day-3 request prices cohort 1");
        assertEq(bound, 3, "bound to the day-3 request");
    }

    /// @notice Each cohort is sealed exactly from the request after its own day: an order placed
    ///         on day c + 1 before that day's request is cohort c, the request of day c + 1 leaves
    ///         it open, and the request of day c + 2 splits it.
    function test_EachCohortSealedFromRequestAfterItsDay() public {
        for (uint256 c = 1; c <= 7; ++c) {
            uint24 d = _dayOf(c);
            _warpTo(d, 30 minutes);
            _buy(a, 0.01 ether * c);
            assertEq(_count(c), 1, "order joins today's cohort before the request");
            vm.recordLogs();
            _drive(0);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            uint256 split = _splitDays(logs);
            (uint256 priced, uint24 bound) = _pricedDays(logs);
            assertFalse(_split(c), "own day's request leaves the cohort unsplit");
            if (c == 1) {
                assertEq(split, 0, "nothing sealed at the opening request");
                assertEq(priced, 0, "nothing priced at the opening request");
            } else {
                assertEq(split, uint256(1) << (c - 1), "exactly the previous cohort splits");
                assertEq(priced, uint256(1) << (c - 1), "exactly the previous cohort prices");
                assertEq(bound, d, "bound to this day's request");
                assertEq(_closed(), c - 1, "previous cohort settled and closed");
            }
            _buy(b, 0.02 ether);
            assertEq(_count(c), 2, "cohort keeps accepting after its own day's request");
        }
        _warpTo(9, 1 hours);
        vm.prank(a);
        vm.expectRevert();
        game.buyDegenesisBox{value: 0.01 ether}(0, 0.01 ether);
        vm.recordLogs();
        _drive(0);
        Vm.Log[] memory last = vm.getRecordedLogs();
        assertEq(_splitDays(last), 1 << 7, "day-9 request splits cohort 7");
        (uint256 p7, uint24 b7) = _pricedDays(last);
        assertEq(p7, 1 << 7, "day-9 request prices cohort 7");
        assertEq(b7, 9, "cohort 7 bound to day 9");
        assertEq(_closed(), 7, "sale closed");
    }

    /// @notice Orders map to cohorts by the protocol day boundary (22:57 UTC), not wall midnight:
    ///         the last second of index 2 is cohort 1, the first second of index 3 is cohort 2.
    ///         Buys outside indices 2..8 revert.
    function test_DayBoundaryCohortAssignmentAndSaleWindow() public {
        _warpTo(1, 3600);
        vm.prank(a);
        vm.expectRevert();
        game.buyDegenesisBox{value: 0.01 ether}(0, 0.01 ether);

        vm.warp(_dayStart(2));
        _buy(a, 0.01 ether);
        vm.warp(_dayStart(3) - 1);
        _buy(a, 0.02 ether);
        assertEq(_count(1), 2, "both ends of index 2 are cohort 1");
        vm.warp(_dayStart(3));
        _buy(a, 0.03 ether);
        assertEq(_count(2), 1, "first second of index 3 is cohort 2");

        vm.warp(_dayStart(9) - 1);
        _buy(a, 0.04 ether);
        assertEq(_count(7), 1, "last second of index 8 is cohort 7");
        vm.warp(_dayStart(9));
        vm.prank(a);
        vm.expectRevert();
        game.buyDegenesisBox{value: 0.01 ether}(0, 0.01 ether);
    }

    /// @notice After days with no daily request at all, the next request splits every sealed
    ///         cohort at once, exact in wei, and leaves today's cohort open. Pricing still takes
    ///         only the next cohort in order.
    function test_CatchUpSplitAfterMissedRequests() public {
        _warpTo(2, 1 hours);
        _drive(0);
        _buy(a, 1.0001 ether); // cohort 1
        _warpTo(3, 2 hours); // no request on days 3 and 4
        _buy(b, 2.5 ether); // cohort 2
        _buy(a, 0.0123 ether);
        _warpTo(4, 5 hours);
        _buy(c3, 0.7777 ether); // cohort 3
        _warpTo(5, 10);
        _buy(b, 0.3 ether); // cohort 4, still open at the day-5 request
        assertEq(game.rngWordForDay(3), 0, "no day-3 word: request missed");

        uint256 v = (_volumeUnits(1) + _volumeUnits(2) + _volumeUnits(3)) * UNIT;
        assertEq(v, 1.0001 ether + 2.5 ether + 0.0123 ether + 0.7777 ether, "sealed volume");
        uint256 q = v / 4;
        assertEq(q * 4, v, "quarters exact in wei");

        _stepToRequest();
        uint256 claimable0 = game.claimablePoolView();
        uint256 future0 = _futureTotal();
        uint256 vault0 = _vaultBudget();
        uint256 afk0 = _sdgnrsAfking();
        vm.recordLogs();
        game.mineFlip(0);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(claimable0 - game.claimablePoolView(), 2 * q, "claimablePool -2q");
        assertEq(_futureTotal() - future0, 2 * q, "future pool (live + frozen pending) +2q");
        assertEq(_vaultBudget() - vault0, q, "Vault budget +q");
        assertEq(_sdgnrsAfking() - afk0, q, "sDGNRS AFKing +q");
        assertEq(_splitDays(logs), (1 << 1) | (1 << 2) | (1 << 3), "every sealed cohort split");
        assertFalse(_split(4), "today's cohort open");
        (uint256 priced, uint24 bound) = _pricedDays(logs);
        assertEq(priced, 1 << 1, "only cohort 1 priced");
        assertEq(bound, 5, "bound to the catch-up request");

        // The rest of the sale splits each remaining cohort exactly once.
        _finishSaleAndCheckSplits();
    }

    /// @notice VRF stall: the day-3 request goes unanswered while orders keep arriving on days
    ///         3 and 4. The first request after the late word, on day 5, splits cohorts 2 and 3 at
    ///         once, exact in wei; cohort 2 waits for cohort 1 (still bound to day 3) to settle,
    ///         and cohort 1 settles on the late day-3 word.
    function test_CatchUpSplitAfterVrfStall() public {
        _warpTo(2, 1 hours);
        _drive(0);
        _buy(a, 0.4321 ether); // cohort 1
        _warpTo(3, 1 hours);
        _stepToRequest();
        game.mineFlip(0); // day-3 request: cohort 1 split and priced; the word does not arrive
        uint256 stalled = mockVRF.lastRequestId();
        lastFulfilledReq = stalled; // keep the harness from answering it
        assertTrue(_split(1), "cohort 1 split at day 3");
        assertEq(_activeDay(), 3, "cohort 1 bound to day 3");
        _buy(b, 1.5 ether); // cohort 2
        _warpTo(4, 6 hours);
        _buy(c3, 0.0707 ether); // cohort 3
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        game.mineFlip(0);
        _warpTo(5, 2 hours);
        _buy(a, 0.02 ether); // cohort 4
        uint256 w3 = uint256(keccak256("stalled-word"));
        mockVRF.fulfillRandomWords(stalled, w3);

        // The late word lands for day 3 and binds cohort 1; drive up to the day-5 request, which
        // the engine puts ahead of Degenesis settlement.
        uint256 q1 = _refQ(1, _degPool());
        vm.recordLogs();
        _stepToRequest();
        assertEq(_word(), w3, "late day-3 word copied");
        assertEq(_activeDay(), 3, "cohort 1 still bound to day 3");
        uint256 q = (_volumeUnits(2) + _volumeUnits(3)) * UNIT / 4;
        assertEq(q * 4, 1.5 ether + 0.0707 ether, "quarters exact");
        uint256 claimable0 = game.claimablePoolView();
        uint256 future0 = _futureTotal();
        uint256 vault0 = _vaultBudget();
        uint256 afk0 = _sdgnrsAfking();
        game.mineFlip(0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_splitDays(logs), (1 << 2) | (1 << 3), "cohorts 2 and 3 split together");
        assertEq(claimable0 - game.claimablePoolView(), 2 * q, "claimablePool -2q");
        assertEq(_futureTotal() - future0, 2 * q, "future pool +2q");
        assertEq(_vaultBudget() - vault0, q, "Vault budget +q");
        assertEq(_sdgnrsAfking() - afk0, q, "sDGNRS AFKing +q");
        assertFalse(_split(4), "cohort 4 open");
        (uint256 priced,) = _pricedDays(logs);
        assertEq(priced, 0, "cohort 2 waits for cohort 1 to settle");

        vm.recordLogs();
        _drive(0);
        logs = vm.getRecordedLogs();
        assertEq(_closed(), 1, "cohort 1 settled");
        Res[] memory got = _resolved(logs);
        Res[] memory want = _refCohort(1, w3, q1);
        assertEq(got.length, 1, "cohort 1 order");
        _assertRes(got[0], want[0], "settled on the late day-3 word");
        _warpTo(6, 1 hours);
        vm.recordLogs();
        _drive(0);
        (uint256 p6, uint24 b6) = _pricedDays(vm.getRecordedLogs());
        assertEq(p6, 1 << 2, "cohort 2 priced at the next request");
        assertEq(b6, 6, "bound to day 6");
        _finishSaleAndCheckSplits();
    }

    function _finishSaleAndCheckSplits() internal {
        _drive(0);
        _driveToClose(6);
        uint256 total;
        for (uint256 c = 1; c <= 7; ++c) {
            total += _volumeUnits(c) * UNIT;
            if (_volumeUnits(c) != 0) assertTrue(_split(c), "every nonempty cohort split");
        }
        assertEq(_vaultBudget(), total / 4, "Vault budget = sum of V/4, no double split");
    }
}
