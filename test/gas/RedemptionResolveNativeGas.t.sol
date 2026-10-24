// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {RedemptionFixture} from "../fuzz/helpers/RedemptionFixture.sol";
import {RedemptionTerminalSeeder} from "../fuzz/AutomaticRedemptionSettlement.t.sol";
import {NativeGasExport} from "../helpers/NativeGasExport.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as Bounds} from "../../contracts/libraries/MineFlipGasBounds.sol";

/// @dev The original resolution-only calibration: close a funded batch, publish
/// its real-shaped word, then measure before the first beneficiary is admitted.
contract RedemptionResolveNativeGasTest is RedemptionFixture, NativeGasExport {
    function _resolution(uint16 roll, bool winningFlip) private {
        uint32 batch = _openBatchId();
        _seedFlipBacking(1_000_000);
        _burn(alice, sdgnrs.totalSupply() / 1000);
        _closeAsGame();
        uint256 word = _wordForRollFrom(roll, 2);
        while ((_synthReward(word, batch) != 0) != winningFlip) word = _wordForRollFrom(roll, word + 1);
        bytes memory original = address(game).code;
        vm.etch(address(game), type(RedemptionTerminalSeeder).runtimeCode);
        RedemptionTerminalSeeder(payable(address(game))).seedLiveRedemptionWord(word);
        vm.etch(address(game), original);
        uint256 snapshot = vm.snapshotState();
        vm.cool(address(sdgnrs));
        vm.cool(address(game));
        (uint256 used, MineFlipGas.Result memory result) = this.coldResolution(word);
        assertTrue(result.progressed, "resolution commits");
        assertFalse(result.done, "beneficiary remains queued");
        assertEq(_rollOf(batch), roll);
        assertEq(_cursor(), 0, "resolution admits no beneficiary");
        assertLe(used, Bounds.REDEMPTION_RESOLVE_GAS, "full cold resolution frame fits");
        emit log_named_uint("redemption_resolution_cold_frame", used);
        if (bytes(vm.envOr("STORAGE_REUSE_EXPORT", string(""))).length != 0) {
            assertTrue(vm.revertToState(snapshot));
            this.exportNativeFixture(string.concat("redemption-resolve-", vm.toString(roll), "-", vm.toString(winningFlip)),
                address(game), address(sdgnrs), abi.encodeCall(sdgnrs.runRedemptionWork, (word, uint256(300_000))));
        }
        vm.deleteStateSnapshot(snapshot);
    }

    function coldResolution(uint256 word) external returns (uint256 used, MineFlipGas.Result memory result) {
        require(msg.sender == address(this), "measurement self-call");
        vm.prank(address(game));
        result = sdgnrs.runRedemptionWork(word, 300_000);
        used = vm.lastCallGas().gasTotalUsed;
    }

    function test_NativeResolveMinimumWin() public { _resolution(21, true); }
    function test_NativeResolveMinimumLoss() public { _resolution(21, false); }
    function test_NativeResolveMaximumWin() public { _resolution(175, true); }
    function test_NativeResolveMaximumLoss() public { _resolution(175, false); }
}
