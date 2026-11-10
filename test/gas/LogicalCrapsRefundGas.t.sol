// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {CrapsPins} from "../craps/CrapsPins.sol";
import {CrapsViews} from "../craps/CrapsViews.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";

contract LogicalRefundTable is CrapsViews {
    function seedCursor(uint64 slot) external { _minerSlot = slot; }
}

/// @dev A late daily opening still opens its elapsed periods. Their prepaid seats are armed into
///      an ordinary battle, one window per maintenance call, inside the existing maintenance bound,
///      and nothing is refunded to the comp lane.
contract LogicalCrapsRefundGasTest is CrapsPins {
    LogicalRefundTable private table;
    uint64 private elapsed;
    uint256 private constant SEATS = 32;

    function setUp() public {
        _installPins();
        _warpToAwardGenesis();
        table = new LogicalRefundTable();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _setIndex(0);
        uint24 next = table.currentDayIndex() + 1;
        elapsed = uint64(uint256(next) * 8 + 2); // first routine window
        flip.setCompLane(100_000_000);
        for (uint256 i; i < SEATS; ++i) {
            uint32 id = _idFor(address(uint160(0xAA000 + i)));
            uint256 code = uint256(id) | (uint256(5) << 160) | (uint256(next) << 176)
                | (uint256(1) << 200) | (uint256(1) << 208);
            vm.prank(ContractAddresses.VAULT);
            table.vaultComp(code);
        }
        vm.warp(vm.getBlockTimestamp() + 1 days + 8 hours);
        _setDailyWord(next, 40 << 8);
        vm.prank(ContractAddresses.GAME);
        table.openBonusDay();
        table.seedCursor(elapsed);
    }

    function keepOne() external returns (uint256 used, bool progressed) {
        require(msg.sender == address(this));
        vm.prank(ContractAddresses.GAME);
        MineFlipGas.Result memory r = table.runCrapsMaintenance_g10712(
            MineFlipGas.budget(10_000_000, type(uint32).max, true));
        used = vm.lastCallGas().gasTotalUsed;
        progressed = r.progressed;
    }

    function test_LateOpeningArmsElapsedWindowWithItsPrepaidSeats() public {
        uint256 beforeLane = flip.compLane();
        assertEq(table.slotIndexOf(elapsed), 0, "fixture: elapsed window not yet armed");
        (uint256 used, bool progressed) = this.keepOne();
        assertTrue(progressed);
        assertGt(table.slotIndexOf(elapsed), 0, "the elapsed window is armed, not skipped");
        assertGe(table.battleOf(bytes32(uint256(elapsed))).entrants, SEATS, "every prepaid seat plays the window");
        assertEq(flip.compLane(), beforeLane, "nothing is refunded to the comp lane");
        assertLe(used, GasBounds.CRAPS_MAINTENANCE_GAS_MAX, "arming stays inside the maintenance bound");
        emit log_named_uint("late_window_arm_cold", used);
    }
}
