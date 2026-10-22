// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {ProtocolBoonAdvanceGasTest, ProtocolDailyGasHost} from "./ProtocolBoonAdvanceGas.t.sol";
import {BoundedGasProbe} from "../helpers/BoundedGasProbe.sol";

contract BoundedDailyGasTest is ProtocolBoonAdvanceGasTest, BoundedGasProbe {
    function test_G1_PublishDailyWord() public {
        vm.etch(address(game), type(ProtocolDailyGasHost).runtimeCode);
        _measureBounded("G1_publish", address(game), address(this), 0,
            abi.encodeCall(ProtocolDailyGasHost.publishOnly, ()), false);
    }
    function test_G8_G9_ApplySixDeepBoonDraws() public {
        vm.etch(address(game), type(ProtocolDailyGasHost).runtimeCode);
        ProtocolDailyGasHost(payable(address(game))).publishOnly();
        _measureBounded("G8_G9_six_deep_draws", address(game), address(this), 0,
            abi.encodeCall(ProtocolDailyGasHost.applyOnly, ()), false);
    }
}
