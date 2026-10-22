// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {MineFlipRequestGasTest} from "./MineFlipRequestGas.t.sol";
import {RequestCostCoordinator} from "../helpers/RequestCostCoordinator.sol";
import {BoundedGasProbe} from "../helpers/BoundedGasProbe.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

contract BoundedHeroRequestSeeder is DegenerusGameStorage {
    function seedHeroWeights() external {
        for (uint8 q; q < 3; ++q) {
            lootboxRngPacked = _recordHeroWager(q, 7, 100, lootboxRngPacked);
        }
    }
}
contract BoundedHeroRequestGasTest is MineFlipRequestGasTest, BoundedGasProbe {
    function _runHeroRequest(string memory label, Scenario scenario, bool daily) private {
        this.configure(scenario);
        RequestCostCoordinator source = new RequestCostCoordinator(0);
        vm.etch(address(coordinator), address(source).code);
        bytes memory original = address(host).code;
        vm.etch(address(host), vm.getDeployedCode("BoundedHeroRequestGas.t.sol:BoundedHeroRequestSeeder"));
        BoundedHeroRequestSeeder(address(host)).seedHeroWeights();
        vm.etch(address(host), original);
        _measureBounded(label, address(host), address(this), 0, abi.encodeCall(host.requestOnly, (daily)), false);
    }
    function test_BoundedPopulatedDailyHeroSeal() public { _runHeroRequest("G6_request_full", Scenario.Daily, true); }
    function test_BoundedPopulatedMiddayHeroPreserved() public { _runHeroRequest("G6_request_midday_full", Scenario.Midday, false); }
}
