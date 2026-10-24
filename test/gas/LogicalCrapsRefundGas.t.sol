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

contract LogicalCrapsRefundGasTest is CrapsPins {
    LogicalRefundTable private table;
    uint64 private skipped;
    uint256 private constant SEATS = 32;
    uint256 private constant PRICE = 2_595;

    function setUp() public {
        _installPins();
        _warpToAwardGenesis();
        table = new LogicalRefundTable();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _setIndex(0);
        uint24 next = table.currentDayIndex() + 1;
        skipped = uint64(uint256(next) * 8 + 2); // first routine window
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
        table.seedCursor(skipped);
    }

    function refundOne() external returns (uint256 used, bool progressed) {
        require(msg.sender == address(this));
        vm.prank(ContractAddresses.GAME);
        MineFlipGas.Result memory r = table.runCrapsMaintenance_g10712(
            MineFlipGas.budget(10_000_000, type(uint32).max, true));
        used = vm.lastCallGas().gasTotalUsed;
        progressed = r.progressed;
    }

    function test_LateOpeningRefundsEveryPrepaidSeatWithinExistingBound() public {
        uint256 beforeLane = flip.compLane();
        uint256 peak;
        for (uint256 i; i < SEATS; ++i) {
            uint256 beforeCursor = table.bonusCursorOf(skipped);
            (uint256 used, bool progressed) = this.refundOne();
            assertTrue(progressed);
            assertEq(table.bonusCursorOf(skipped), beforeCursor + 1, "one indivisible refund per call");
            assertLe(used, GasBounds.CRAPS_REFUND_GAS_MAX, "existing per-seat bound covers full call");
            if (used > peak) peak = used;
        }
        assertEq(flip.compLane() - beforeLane, SEATS * PRICE, "all prepaid value returned once");
        assertEq(table.slotIndexOf(skipped), 0, "expired period never commits a battle");
        this.refundOne();
        assertEq(flip.compLane() - beforeLane, SEATS * PRICE, "retry cannot refund twice");
        emit log_named_uint("late_window_refund_peak_cold", peak);
    }
}
