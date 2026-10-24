// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {LogicalDaysFixture} from "../fuzz/helpers/LogicalDaysFixture.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {MineFlipGasBounds as Bounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
contract DailyGapNativeGasTest is LogicalDaysFixture {
    function _delayed(uint256 elapsed, uint256 word) private {
        vm.warp(vm.getBlockTimestamp() + 1 days);
        uint256 id = _requestLogical();
        vm.warp(vm.getBlockTimestamp() + elapsed * 1 days);
        mockVRF.fulfillRandomWords(id, word);
        for (uint256 i; i < 30 && game.rngWordForDay(2) == 0; ++i) {
            game.mineFlip{gas: 3_000_000}(0);
        }
        assertEq(game.rngWordForDay(2), word);
        assertEq(game.currentDayView(), 2);
        assertEq(game.rngWordForDay(3), 0);
        emit log_named_uint("delayed_single_round_last_chunk", vm.lastCallGas().gasTotalUsed);
    }
    function test_OneResetLate() public { _delayed(1, 777); }
    function test_TwelveResetsLateWin() public { _delayed(12, type(uint32).max); }
    function test_TwelveResetsLateLoss() public { _delayed(12, 2); }
}
