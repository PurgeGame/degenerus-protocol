// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {DegenesisWeekOpening} from "../helpers/DegenesisWeekOpening.sol";
import {PoolFlowHandler} from "../handlers/PoolFlowHandler.sol";
import {PoolConservation} from "./PoolConservation.inv.t.sol";

/// @title PoolConservationDegenesis -- pool conservation after a real Degenesis week (turbo launch)
/// @notice The pools start holding the splits' future-pool halves and the turbo jackpot's movements.
contract PoolConservationDegenesis is PoolConservation, DegenesisWeekOpening {
    function _deployTimestamp() internal pure override(DeployProtocol, DegenesisWeekOpening) returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }

    function _acc(string memory k, uint256 v) internal override returns (uint256) {
        return super._acc(string.concat("DGT_", k), v);
    }

    function setUp() public override {
        _deployProtocol();
        _degenesisWeek(true);
        vm.deal(address(game), address(game).balance + 5_000_000 ether);
        mockVRF.fundSubscription(1, 100e18);
        startingBacking = address(game).balance + mockStETH.balanceOf(address(game));
        handler = new PoolFlowHandler(game, mockVRF, 5);
        targetContract(address(handler));
    }

    function test_degenesisWeekHappened() public view {
        _assertDegenesisWeekHappened();
    }
}
