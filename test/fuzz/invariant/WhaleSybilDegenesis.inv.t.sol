// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {DegenesisWeekOpening} from "../helpers/DegenesisWeekOpening.sol";
import {SolvencyObligations} from "../helpers/SolvencyObligations.sol";
import {WhaleSybilHandler} from "../handlers/WhaleSybilHandler.sol";
import {WhaleSybilInvariant} from "./WhaleSybil.inv.t.sol";

/// @title WhaleSybilDegenesis -- whale + sybil pressure after a real Degenesis week (turbo launch)
contract WhaleSybilDegenesis is WhaleSybilInvariant, DegenesisWeekOpening {
    function _deployTimestamp() internal pure override(DeployProtocol, DegenesisWeekOpening) returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }

    function _acc(string memory k, uint256 v) internal override returns (uint256) {
        return super._acc(string.concat("DGT_", k), v);
    }

    function setUp() public override {
        _deployProtocol();
        _degenesisWeek(true);
        wsHandler = new WhaleSybilHandler(game, mockVRF, 3, 20);
        _targetWalk();
    }

    function test_degenesisWeekHappened() public view {
        _assertDegenesisWeekHappened();
        assertGt(wsHandler.ghost_initialBacking(), 0, "real opening deposits precede the handler");
        assertEq(wsHandler.ghost_initialBacking(), SolvencyObligations.backing(game));
        assertEq(wsHandler.ghost_whaleDeposited() + wsHandler.ghost_sybilDeposited(), 0);
    }
}
