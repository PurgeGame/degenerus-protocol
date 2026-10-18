// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DegenesisHarness} from "./helpers/DegenesisHarness.sol";

/// @title DegenesisClosingBurn -- empty cohorts, the closing burn and strict cohort ordering
/// @notice Spec §4 / §10 checks 6, 13, 21: one closing step handles settled and empty cohorts,
///         so the leftover inventory burns exactly once after the seventh closes, also when the
///         last day or every day is empty. A cohort is priced only after the previous one fully
///         settles; a settlement backlog only delays the next cohort's binding and never lowers
///         its rate.
contract DegenesisClosingBurn is DegenesisHarness {
    address internal a;
    address internal b;
    address[4] internal many;

    function setUp() public override {
        super.setUp();
        a = _player("cb-a");
        b = _player("cb-b");
        _drive(0);
        _earnCredit(a, 20 ether);
        _earnCredit(b, 20 ether);
        _driveDay(2, 0);
    }

    struct SaleLog {
        uint256 burns;
        uint256 burned;
        uint256 closes;
        uint256 closedMask;
    }

    function _scan(Vm.Log[] memory logs, SaleLog memory s) internal view {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length == 0) continue;
            bytes32 t = logs[i].topics[0];
            if (t == SIG_BURNED) {
                ++s.burns;
                s.burned += abi.decode(logs[i].data, (uint256));
            } else if (t == SIG_CLOSED) {
                ++s.closes;
                uint256 c = uint256(logs[i].topics[1]);
                assertEq(s.closedMask & (uint256(1) << c), 0, "each cohort closes once");
                assertEq(s.closedMask, (uint256(1) << c) - 2, "cohorts close in order");
                s.closedMask |= uint256(1) << c;
            }
        }
    }

    /// @dev Drive the sale with orders on the Degenesis days flagged in `orderMask` (bit c),
    ///      recording the cohort events; then drive several more days to show nothing repeats.
    function _runSale(uint256 orderMask) internal returns (SaleLog memory s, uint256 poolBeforeBurn) {
        for (uint256 c = 1; c <= 7; ++c) {
            uint24 d = _dayOf(c);
            if (c > 1) _driveAndScan(d, s);
            _warpTo(d, 3 hours);
            if (orderMask & (uint256(1) << c) != 0) {
                _buy(a, 0.25 ether * c);
                _buy(b, 0.0137 ether);
            }
        }
        poolBeforeBurn = _degPool();
        for (uint24 d = 9; d <= 14; ++d) _driveAndScan(d, s);
    }

    /// @dev Drive day `d`, scanning its cohort events; a drive that burns lowers sDGNRS supply
    ///      by exactly the burned amount.
    function _driveAndScan(uint24 d, SaleLog memory s) internal {
        uint256 supply0 = sdgnrs.totalSupply();
        uint256 burned0 = s.burned;
        vm.recordLogs();
        _driveDay(d, 0);
        _scan(vm.getRecordedLogs(), s);
        if (s.burned != burned0) assertEq(supply0 - sdgnrs.totalSupply(), s.burned - burned0, "burn lowers supply");
    }

    function _assertBurnedOnce(SaleLog memory s, uint256 poolBeforeBurn, bool lastDaySettles) internal view {
        assertEq(s.burns, 1, "inventory burned exactly once");
        assertEq(s.closes, 7, "seven cohorts closed");
        assertEq(s.closedMask, 0xFE, "cohorts 1..7 closed");
        assertEq(_closed(), 7, "degenesisClosed == 7");
        assertEq(_degPool(), 0, "Degenesis pool empty after the burn");
        assertEq(_active(), 0, "no reservation outstanding");
        assertEq(_word(), 0, "no bound word");
        if (!lastDaySettles) assertEq(s.burned, poolBeforeBurn, "burn takes the whole inventory");
        else assertLe(s.burned, poolBeforeBurn, "burn takes what cohort 7 left");
    }

    /// @notice Last day settled: cohort 7 settles after the sale ends and its close burns.
    function test_BurnOnceWhenLastDaySettled() public {
        (SaleLog memory s, uint256 pool9) = _runSale(0xFE);
        _assertBurnedOnce(s, pool9, true);
    }

    /// @notice Last day empty: cohort 7 closes through the empty path, which burns.
    function test_BurnOnceWhenLastDayEmpty() public {
        (SaleLog memory s, uint256 pool9) = _runSale(0x7E);
        _assertBurnedOnce(s, pool9, false);
    }

    /// @notice No orders at all: every cohort closes empty, one per request, and the seventh
    ///         burns the whole 100B inventory.
    function test_BurnOnceWhenAllDaysEmpty() public {
        uint256 r0 = _degPool();
        (SaleLog memory s, uint256 pool9) = _runSale(0);
        _assertBurnedOnce(s, pool9, false);
        assertEq(s.burned, r0, "whole inventory burned");
        assertEq(r0, 100_000_000_000 * 1e12, "100B tokens");
    }

    /// @notice Empty cohorts between nonempty ones close in order without pricing, and their
    ///         tokens roll forward as inventory for the next priced cohort.
    function test_EmptyCohortRollsInventoryForward() public {
        _buy(a, 1 ether); // cohort 1
        _warpTo(3, 1 hours);
        _drive(0); // cohort 1 settles
        uint256 r = _degPool();
        // cohorts 2 and 3 empty; order on day index 5 (cohort 4)
        _warpTo(4, 1 hours);
        _drive(0);
        assertEq(_closed(), 2, "cohort 2 closed empty at day 4");
        _warpTo(5, 2 hours);
        _drive(0);
        assertEq(_closed(), 3, "cohort 3 closed empty at day 5");
        assertEq(_degPool(), r, "empty closes pay nothing");
        _buy(b, 0.5 ether); // cohort 4
        _warpTo(6, 1 hours);
        _requestOnly(uint256(keccak256("cb-roll")));
        assertEq(_activeQ(), _refQ(4, r), "cohort 4 priced on the rolled-forward inventory");
    }

    /// @notice Strict ordering and backlog: while cohort 1 still has orders to settle, the next
    ///         request splits cohort 2 but does not price it; cohort 2 is priced at the first
    ///         request after cohort 1 closes, on the same Q a prompt settlement would give.
    function test_BacklogDelaysBindingNeverLowersRate() public {
        for (uint256 i; i < 4; ++i) {
            many[i] = _player(string.concat("cb-many-", vm.toString(i)));
            _earnCredit(many[i], 10 ether);
        }
        for (uint256 i; i < 420; ++i) _buy(many[i % 4], 0.01 ether + (i % 9) * 0.0011 ether);
        _warpTo(3, 2 hours);
        uint256 w3 = uint256(keccak256("cb-backlog"));
        _requestOnly(w3);
        _buy(a, 0.8 ether); // cohort 2
        _buy(b, 0.0505 ether);
        uint256 snap = vm.snapshotState();

        // Prompt: cohort 1 settles on day 3, cohort 2 prices at the day-4 request.
        _drive(w3);
        assertEq(_closed(), 1, "prompt: cohort 1 closed on day 3");
        uint256 rPrompt = _degPool();
        _warpTo(4, 1 hours);
        _requestOnly(uint256(keccak256("cb-day4")));
        uint256 qPrompt = _activeQ();
        assertEq(_activeDay(), 4, "prompt: bound to day 4");
        assertEq(qPrompt, _refQ(2, rPrompt), "prompt Q");

        // Backlog: one chunk of cohort 1 on day 3, the day-4 request runs with orders left.
        vm.revertToState(snap);
        _driveToSettle();
        game.mineFlip(0);
        assertLt(_activeCursor(), 420, "backlog");
        _warpTo(4, 1 hours);
        vm.recordLogs();
        _driveToSettle();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_countSig(logs, SIG_PRICED), 0, "no pricing while the previous cohort settles");
        assertTrue(_split(2), "cohort 2 still splits on schedule");
        assertEq(_activeDay(), 3, "cohort 1 still active");
        assertEq(_closed(), 0, "cohort 1 not closed");

        _drive(0); // finish cohort 1 on day 4
        assertEq(_closed(), 1, "cohort 1 closed late");
        assertEq(_active(), 0, "no cohort priced at close");
        assertEq(_degPool(), rPrompt, "same inventory left as the prompt run");

        _warpTo(5, 1 hours);
        _requestOnly(uint256(keccak256("cb-day5")));
        assertEq(_activeDay(), 5, "backlog: bound to day 5, one request later");
        assertEq(_activeQ(), qPrompt, "backlog never lowers the rate");
    }
}
