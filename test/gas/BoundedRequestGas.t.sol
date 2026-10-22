// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {MineFlipRequestGasTest} from "./MineFlipRequestGas.t.sol";
import {RequestCostCoordinator} from "../helpers/RequestCostCoordinator.sol";
import {BoundedGasProbe} from "../helpers/BoundedGasProbe.sol";

/// @dev Uses the established complete native request fixtures and production
///      delegate dispatcher, with an independently cross-checked warm replay.
contract BoundedRequestGasTest is MineFlipRequestGasTest, BoundedGasProbe {
    function _configureBounded(Scenario scenario) private {
        this.configure(scenario);
        // Retain the realistic coordinator storage and checks. A gas-burning
        // floor absorbs cold surcharges and cannot measure a warm/cold delta.
        RequestCostCoordinator source = new RequestCostCoordinator(0);
        vm.etch(address(coordinator), address(source).code);
    }
    function test_BoundedDaily() public {
        _configureBounded(Scenario.Daily);
        _measureBounded("request_daily", address(host), address(this), 0,
            abi.encodeCall(host.requestOnly, (true)), false);
    }
    function test_BoundedDailyTransition() public {
        _configureBounded(Scenario.Transition);
        _measureBounded("request_transition", address(host), address(this), 0,
            abi.encodeCall(host.requestOnly, (true)), false);
    }
    function test_BoundedMidday() public {
        _configureBounded(Scenario.Midday);
        _measureBounded("request_midday", address(host), address(this), 0,
            abi.encodeCall(host.requestOnly, (false)), false);
    }
    function test_BoundedDailyRedemption() public {
        _configureBounded(Scenario.DailyRedeem);
        _measureBounded("request_redemption", address(host), address(this), 0,
            abi.encodeCall(host.requestOnly, (true)), false);
    }
}
