// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {DegenesisWeekOpening} from "../helpers/DegenesisWeekOpening.sol";
import {VRFPathHandler} from "../handlers/VRFPathHandler.sol";
import {VRFPathInvariants} from "./VRFPathInvariants.inv.t.sol";

/// @title VRFPathDegenesis -- lootbox RNG index lifecycle, stalls and gap backfill after a real
///        Degenesis week (turbo launch)
contract VRFPathDegenesis is VRFPathInvariants, DegenesisWeekOpening {
    function _deployTimestamp() internal pure override(DeployProtocol, DegenesisWeekOpening) returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }

    function _acc(string memory k, uint256 v) internal override returns (uint256) {
        return super._acc(string.concat("DGT_", k), v);
    }

    function setUp() public override {
        _deployProtocol();
        _degenesisWeek(true);
        handler = new VRFPathHandler(game, mockVRF, admin, 5);
        targetContract(address(handler));
    }

    function test_degenesisWeekHappened() public view {
        _assertDegenesisWeekHappened();
    }
}

/// @title VRFPathDegenesisBacklog -- the same, handed off with the Degenesis settlement backlog open
/// @notice Stalls, coordinator swaps, gap-day backfills and recoveries hit a game whose active cohort
///         still settles on its bound word and whose seventh cohort still waits for a later request.
contract VRFPathDegenesisBacklog is VRFPathInvariants, DegenesisWeekOpening {
    function _deployTimestamp() internal pure override(DeployProtocol, DegenesisWeekOpening) returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }

    function _dgwBacklog() internal pure override returns (bool) {
        return true;
    }

    function _acc(string memory k, uint256 v) internal override returns (uint256) {
        return super._acc(string.concat("DGB_", k), v);
    }

    function setUp() public override {
        _deployProtocol();
        _degenesisWeek(true);
        handler = new VRFPathHandler(game, mockVRF, admin, 5);
        targetContract(address(handler));
    }

    function invariant_degenesisBacklogSettlesForward() public view {
        _assertBacklogSettlesForward();
    }

    function test_degenesisWeekHappened() public view {
        _assertDegenesisWeekHappened();
    }
}
