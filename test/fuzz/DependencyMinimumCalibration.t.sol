// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {GameIsolationHost} from "./GameExternalIsolation.t.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {BoundedCall} from "../../contracts/libraries/BoundedCall.sol";
import {IDegenerusGameAdvanceModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";

contract CountingDependency {
    uint256 public calls;

    function ping() external {
        ++calls;
    }
}

/// @dev A continuation meter (no first-unit permission, no floor) carrying a caller calibration.
contract CalibratedBoundedCaller {
    function attempt(uint32 multiplierBps, address target, uint256 minimum, uint256 reserve)
        external returns (bool ok)
    {
        MineFlipGas.Meter memory meter;
        meter.multiplierBps = multiplierBps;
        (ok,) = BoundedCall.callRemaining(meter, target, minimum, reserve, abi.encodeWithSignature("ping()"), 0);
    }
}

/// @title Caller calibration scales the protocol's own tail, never a dependency call's minimum
contract DependencyMinimumCalibrationTest is DeployProtocol {
    CountingDependency internal dep;
    CalibratedBoundedCaller internal caller;

    function setUp() public {
        _deployProtocol();
        dep = new CountingDependency();
        caller = new CalibratedBoundedCaller();
    }

    function test_CalibrationNeverLowersTheDependencyMinimum() public {
        // 200k cannot admit a 300k minimum at the lowest or the default calibration.
        uint32[2] memory low = [MineFlipGas.MIN_MULTIPLIER, MineFlipGas.DEFAULT_MULTIPLIER];
        for (uint256 i; i < 2; ++i) {
            vm.expectRevert(MineFlipGas.InsufficientExecutionGas.selector);
            caller.attempt{gas: 200_000}(low[i], address(dep), 300_000, 30_000);
        }
        // 400k admits it at the lowest calibration, exactly as at the default.
        assertTrue(caller.attempt{gas: 400_000}(MineFlipGas.MIN_MULTIPLIER, address(dep), 300_000, 30_000));
        assertEq(dep.calls(), 1);
        // A 4x calibration raises both the minimum (1.2M) and the tail (160k).
        vm.expectRevert(MineFlipGas.InsufficientExecutionGas.selector);
        caller.attempt{gas: 1_000_000}(40_000, address(dep), 300_000, 30_000);
        assertTrue(caller.attempt{gas: 1_600_000}(40_000, address(dep), 300_000, 30_000));
        assertEq(dep.calls(), 2);
    }

    function test_LowCalibrationCannotUnderfundTheStake() public {
        vm.etch(address(game), type(GameIsolationHost).runtimeCode);
        GameIsolationHost host = GameIsolationHost(payable(address(game)));
        vm.deal(address(game), 1 ether);
        bytes memory input = abi.encodePacked(
            abi.encodeCall(IDegenerusGameAdvanceModule.stakeExcessEth, (uint256(1 ether))),
            MineFlipGas.budget(type(uint192).max, MineFlipGas.MIN_MULTIPLIER, false)
        );
        vm.expectRevert(MineFlipGas.InsufficientExecutionGas.selector);
        host.invoke{gas: 250_000}(ContractAddresses.GAME_ADVANCE_MODULE, input);
        assertEq(address(game).balance, 1 ether, "no submit below the fixed minimum");
        host.invoke{gas: 1_000_000}(ContractAddresses.GAME_ADVANCE_MODULE, input);
        assertEq(address(game).balance, 0, "an admitted stake still submits");
    }
}
