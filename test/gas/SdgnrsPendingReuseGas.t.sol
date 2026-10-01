// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {RedemptionGasTest} from "../fuzz/RedemptionGas.t.sol";
import {Vm} from "forge-std/Vm.sol";

/// @dev Run cold on current source and the original per-day baseline, unchanged.
contract SdgnrsPendingReuseGasTest is RedemptionGasTest {
    function _refund() private view returns (uint256) {
        Vm.Gas memory m = vm.lastCallGas();
        if (m.gasRefunded <= 0) return 0;
        uint256 r = uint256(uint64(m.gasRefunded));
        return r < m.gasTotalUsed / 5 ? r : m.gasTotalUsed / 5;
    }
    function test_ColdPendingAggregateThroughFourRealBurnResolvePeriods() public {
        uint256 burns; uint256 resolutions; uint256 burnRefunds; uint256 resolveRefunds;
        for (uint256 period; period < 4; ++period) {
            _primeCurrentDayRng();
            uint24 day = game.currentDayView();
            vm.prank(player);
            sdgnrs.burn(PLAYER_SDGNRS / 1000);
            burnRefunds += _refund();
            uint256 b = vm.snapshotGasLastCall("pending-pool-burn");
            burns += b;
            assertTrue(sdgnrs.hasPendingRedemptions(day), "paid burn populated this day's pool");
            vm.prank(address(game));
            sdgnrs.resolveRedemptionPeriod(100, day);
            resolveRefunds += _refund();
            uint256 r = vm.snapshotGasLastCall("pending-pool-resolve");
            resolutions += r;
            assertEq(sdgnrs.pendingResolveDay(), 0, "resolved pool invalidated");
            assertFalse(sdgnrs.hasPendingRedemptions(day), "retained payload is logically absent");
            emit log_named_uint("period", period);
            emit log_named_uint("cold burn isolated transaction gas", b);
            emit log_named_uint("cold resolve isolated transaction gas", r);
            vm.warp(vm.getBlockTimestamp() + 1 days);
        }
        emit log_named_uint("four-period burn isolated transaction gas", burns);
        emit log_named_uint("four-period resolve isolated transaction gas", resolutions);
        emit log_named_uint("four-period burn refund proxy", burnRefunds);
        emit log_named_uint("four-period resolve refund proxy", resolveRefunds);
    }
}
