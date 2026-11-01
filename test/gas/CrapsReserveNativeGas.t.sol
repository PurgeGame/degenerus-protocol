// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {CrapsHighReserveTest} from "../craps/CrapsHighReserve.t.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CrapsLensReader} from "../../contracts/CrapsLens.sol";

/// @dev The original 96-seat reserve-hook calibration, with native bytecode
/// replacing its engine mock. All eligibility, draw and once-only assertions stay.
contract CrapsReserveNativeGasTest is CrapsHighReserveTest {
    function _reserveCase(bool daySeats) private {
        vm.clearMockedCalls();
        vm.etch(address(0xC6A6), type(CrapsNativeBustEngine).runtimeCode);
        for (uint160 i; i < 96; ++i) _enter(address(0x5000 + i), true, daySeats && i % 2 == 0);
        _lock(50_000);
        _start(_word(true), 0);
        // Settlement is capped at 32 seats per call. Preserve the original
        // 96-seat population and measure the final batch, including the draw.
        for (uint256 i; i < 2; ++i) {
            table.settleSlot(slot, WHOLE_FIELD);
            assertEq(CrapsLensReader.highRollerDrawOf(address(cold), slot).eligible, (i + 1) * 32);
            assertFalse(CrapsLensReader.highRollerDrawOf(address(cold), slot).resolved);
        }
        vm.cool(address(table));
        table.settleSlot{gas: 16_000_000}(slot, WHOLE_FIELD);
        assertTrue(CrapsLensReader.highRollerDrawOf(address(cold), slot).resolved, "reserve draw finalized");
        assertTrue(CrapsLensReader.highRollerDrawOf(address(cold), slot).won, "credit branch exercised");
        assertEq(CrapsLensReader.highRollerDrawOf(address(cold), slot).eligible, 96, "all 96 high seats sampled");
    }

    function test_NativeReserve96OwnSeats() public { _reserveCase(false); }
    function test_NativeReserve96MixedSeats() public { _reserveCase(true); }
}

contract CrapsNativeBustEngine {
    function settleBattle(uint256, uint256, uint256, uint256, uint256, uint48, uint256, uint256)
        external pure returns (Craps.SlipResult memory result) {}
}
