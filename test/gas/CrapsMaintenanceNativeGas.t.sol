// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {CrapsScheduledCursorTest} from "../craps/CrapsScheduledCursor.t.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {GlamsterdamReprice} from "../helpers/GlamsterdamReprice.sol";
import {ColdFirstReprice} from "../helpers/ColdFirstReprice.sol";

/// @dev The original scheduled-cursor fixtures: cold arming, fresh pass refunds,
/// partial refund checkpoints and the last refund's cursor/return tail.
contract CrapsMaintenanceNativeGasTest is CrapsScheduledCursorTest, ColdFirstReprice {
    uint256 private constant ALLOWANCE = 900_000;

    function _measureMaintenance() private returns (MineFlipGas.Result memory result) {
        vm.cool(address(craps));
        vm.prank(ContractAddresses.GAME);
        result = craps.runCrapsMaintenance_g10712{gas: ALLOWANCE}(ALLOWANCE);
        assertTrue(result.progressed, "cold maintenance commits work");
    }

    function test_NativeColdScheduledArm() public {
        // Admit the opener before it expires, then measure arming its closed field.
        vm.warp(vm.getBlockTimestamp() - ((vm.getBlockTimestamp() - 82_620) % 1 days) + 1);
        _openDay();
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        _measureMaintenance();
        assertGt(craps.slotIndexOf(craps.minerSlot()), 0, "closed field registered");
    }

    function _refundCase(uint256 count, bool high) private {
        _openDay();
        uint24 day = craps.currentDayIndex();
        _settleWholeDay(day);
        address[] memory owners = new address[](count);
        for (uint256 i; i < count; ++i) {
            owners[i] = address(uint160(0xC17000 + i));
            uint32 id = _idFor(owners[i]);
            vm.prank(ContractAddresses.GAME);
            craps.creditPasses(id, high ? 0 : 1, high ? 1 : 0);
            vm.prank(owners[i]);
            craps.applyCrapsPasses(day + 1, 1, high);
        }
        vm.warp(block.timestamp + 2 days);
        _setDailyWord(craps.currentDayIndex(), PLAIN_WORD);
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        _measureMaintenance();
        uint256 refunded;
        for (uint256 i; i < count; ++i) {
            (uint256 normal, uint256 higher) = craps.passCreditsOf(owners[i]);
            assertEq(high ? normal : higher, 0, "refund preserves pass lane");
            refunded += high ? higher : normal;
        }
        assertGt(refunded, 0, "refund checkpoint is nonempty");
        assertLe(refunded, count, "refund cannot duplicate credits");
        if (count == 1) assertEq(refunded, count, "last refund completes");
        else assertLt(refunded, count, "cold backlog crosses a checkpoint");
        emit log_named_uint("refunded_passes", refunded);
    }

    function test_NativeColdNormalRefundBatch() public { _refundCase(100, false); }
    function test_NativeColdHighRefundBatch() public { _refundCase(100, true); }
    function test_NativeColdNormalLastRefund() public { _refundCase(1, false); }
    function test_NativeColdHighLastRefund() public { _refundCase(1, true); }

    /// @dev Day + 1 lapses holding `credited` pass-funded day seats, then `fresh` vault-comped day
    ///      seats whose owners have no credit word, and optionally one vault window-ahead seat in
    ///      the day's last window. The comp lane word is left empty, so a comp credit writes it fresh.
    function _lapsedDay(uint256 credited, uint256 fresh, bool lastWindow) private {
        _openDay();
        uint24 day = craps.currentDayIndex();
        _settleWholeDay(day);
        flip.setCompLane(100_000_000);
        for (uint256 i; i < credited + fresh; ++i) {
            address owner = address(uint160(0xC18000 + i));
            uint32 id = _idFor(owner);
            if (i < credited) {
                vm.prank(ContractAddresses.GAME);
                craps.creditPasses(id, 1, 0);
                vm.prank(owner);
                craps.applyCrapsPasses(day + 1, 1, false);
            } else {
                vm.prank(ContractAddresses.VAULT);
                craps.vaultComp(uint256(id) | (uint256(2) << 160) | (uint256(day + 1) << 176) | (uint256(1) << 200));
                (uint256 normal, uint256 higher) = craps.passCreditsOf(owner);
                assertEq(normal + higher, 0, "comped owner holds no credit");
            }
        }
        if (lastWindow) {
            uint32 id = _idFor(address(0xC19000));
            vm.prank(ContractAddresses.VAULT);
            craps.vaultComp(uint256(id) | (uint256(5) << 160) | (uint256(day + 1) << 176)
                | (uint256(1) << 200) | (uint256(5) << 208));
        }
        assertEq(uint128(uint256(vm.load(ContractAddresses.COIN, bytes32(uint256(7))))), flip.compLane(), "comp lane slot");
        vm.store(ContractAddresses.COIN, bytes32(uint256(7)), bytes32(0));
        assertEq(craps.dayTicketsOf(day + 1), credited + fresh, "day seats reserved");
        vm.warp(block.timestamp + 2 days);
        _setDailyWord(craps.currentDayIndex(), PLAIN_WORD);
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
    }

    /// @dev Two lapsed-day shapes, `shape` = fresh comped day seats, plus 100 for the last-window
    ///      seat. Both are measured cold before either is recorded.
    function _lapsedPair(uint256 loShape, uint256 hiShape)
        private returns (GlamsterdamReprice.Result memory lo, GlamsterdamReprice.Result memory hi)
    {
        bytes memory data = abi.encodeCall(craps.runCrapsMaintenance_g10712, (ALLOWANCE));
        uint256[2] memory shapes = [loShape, hiShape];
        uint256[2] memory cold;
        bytes32[2] memory results;
        uint256 base = vm.snapshotState();
        for (uint256 k; k < 2; ++k) {
            _lapsedDay(0, shapes[k] % 100, shapes[k] >= 100);
            uint64 head = craps.minerSlot();
            bytes memory result;
            (cold[k], result) = _coldFrame(address(craps), ContractAddresses.GAME, data, ALLOWANCE);
            results[k] = keccak256(result);
            assertTrue(abi.decode(result, (MineFlipGas.Result)).progressed, "cold maintenance commits work");
            assertEq(craps.minerSlot(), head + 8, "the lapsed day is swept whole");
            assertTrue(vm.revertToState(base));
        }
        GlamsterdamReprice.Result[2] memory r;
        for (uint256 k; k < 2; ++k) {
            _lapsedDay(0, shapes[k] % 100, shapes[k] >= 100);
            r[k] = this.coldFirstReplay(address(craps), ContractAddresses.GAME, data, ALLOWANCE, cold[k], results[k]);
            assertTrue(vm.revertToState(base));
        }
        vm.deleteStateSnapshot(base);
        (lo, hi) = (r[0], r[1]);
    }

    function _reportDelta(string memory label, GlamsterdamReprice.Result memory hi,
        GlamsterdamReprice.Result memory lo, uint256 bound) private returns (uint256 total)
    {
        total = hi.glamsterdamExec + hi.stateGas - lo.glamsterdamExec - lo.stateGas;
        emit log_named_string("unit", label);
        emit log_named_int("osaka", int256(hi.osakaExec) - int256(lo.osakaExec));
        emit log_named_int("glamsterdam_exec", int256(hi.glamsterdamExec) - int256(lo.glamsterdamExec));
        emit log_named_int("glamsterdam_state", int256(hi.stateGas) - int256(lo.stateGas));
        emit log_named_uint("glamsterdam_total", total);
        emit log_named_int("new_slots", int256(hi.newSlots) - int256(lo.newSlots));
        emit log_named_uint("bound", bound);
    }

    /// @dev One refund: the fourth seat opens a cold bet word and its owner's credit word is new.
    function test_GlamsterdamFreshCreditRefundUnit() public {
        (GlamsterdamReprice.Result memory three, GlamsterdamReprice.Result memory four) = _lapsedPair(3, 4);
        _report("lapsed_day_three_fresh_refunds", three, GasBounds.CRAPS_REFUND_GAS_MAX + GasBounds.CRAPS_SWEEP_TAIL_GAS);
        _report("lapsed_day_four_fresh_refunds", four, GasBounds.CRAPS_REFUND_GAS_MAX + GasBounds.CRAPS_SWEEP_TAIL_GAS);
        assertEq(four.newSlots, three.newSlots + 1, "the fourth refund creates its credit word");
        uint256 total = _reportDelta("fourth_fresh_credit_refund", four, three, GasBounds.CRAPS_REFUND_GAS_MAX);
        assertLe(total, GasBounds.CRAPS_REFUND_GAS_MAX, "CRAPS_REFUND_GAS_MAX");
    }

    /// @dev A whole one-refund checkpoint: fresh credit word and fresh day cursor word.
    function test_GlamsterdamFreshCreditRefundCheckpoint() public {
        (GlamsterdamReprice.Result memory empty, GlamsterdamReprice.Result memory one) = _lapsedPair(0, 1);
        assertEq(one.newSlots, empty.newSlots + 2, "credit and cursor words are new");
        uint256 bound = GasBounds.CRAPS_REFUND_GAS_MAX + GasBounds.CRAPS_SWEEP_TAIL_GAS;
        _report("lapsed_day_one_fresh_refund_whole_call", one, bound);
        assertLe(one.glamsterdamExec + one.stateGas, bound, "CRAPS_REFUND_GAS_MAX + CRAPS_SWEEP_TAIL_GAS (whole call)");
        uint256 total = _reportDelta("refund_and_its_cursor_over_empty_sweep", one, empty, bound);
        assertLe(total, bound, "CRAPS_REFUND_GAS_MAX + CRAPS_SWEEP_TAIL_GAS");
    }

    /// @dev The sweep tail: the last window's refund leaves a fresh cursor word and a comp credit
    ///      into an empty lane word. Measured over the empty sweep, so the window refund is included.
    function test_GlamsterdamSweepTailFreshCursorAndComps() public {
        (GlamsterdamReprice.Result memory empty, GlamsterdamReprice.Result memory last) = _lapsedPair(0, 100);
        assertEq(last.newSlots, empty.newSlots + 2, "cursor and comp lane words are new");
        uint256 bound = GasBounds.CRAPS_REFUND_GAS_MAX + GasBounds.CRAPS_SWEEP_TAIL_GAS;
        _report("lapsed_day_last_window_refund_whole_call", last, bound);
        assertLe(last.glamsterdamExec + last.stateGas, bound, "CRAPS_REFUND_GAS_MAX + CRAPS_SWEEP_TAIL_GAS (whole call)");
        uint256 total = _reportDelta("window_refund_cursor_and_comps_over_empty_sweep", last, empty,
            GasBounds.CRAPS_SWEEP_TAIL_GAS);
        assertLe(total, GasBounds.CRAPS_SWEEP_TAIL_GAS, "CRAPS_SWEEP_TAIL_GAS");
    }
}
