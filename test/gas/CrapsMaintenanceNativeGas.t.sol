// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {CrapsScheduledCursorTest} from "../craps/CrapsScheduledCursor.t.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

/// @dev The original scheduled-cursor fixtures: cold arming, fresh pass refunds,
/// partial refund checkpoints and the last refund's cursor/return tail.
contract CrapsMaintenanceNativeGasTest is CrapsScheduledCursorTest {
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
}
