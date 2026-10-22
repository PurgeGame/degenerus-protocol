// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {DegenesisWeekOpening} from "../helpers/DegenesisWeekOpening.sol";
import {VRFHandler} from "../helpers/VRFHandler.sol";
import {TicketTrackingHandler} from "../handlers/TicketTrackingHandler.sol";
import {TicketQueueInvariant} from "./TicketQueue.inv.t.sol";

/// @title TicketQueueDegenesis -- ticket queue consistency after a real Degenesis week (turbo launch)
/// @notice The queues start holding the week's lootbox-born and turbo-jackpot entries.
contract TicketQueueDegenesis is TicketQueueInvariant, DegenesisWeekOpening {
    function _deployTimestamp() internal pure override(DeployProtocol, DegenesisWeekOpening) returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }

    function _acc(string memory k, uint256 v) internal override returns (uint256) {
        return super._acc(string.concat("DGT_", k), v);
    }

    function setUp() public override {
        _deployProtocol();
        _degenesisWeek(true);
        ticketHandler = new TicketTrackingHandler(game, 10);
        vrfHandler = new VRFHandler(mockVRF, game);
        targetContract(address(ticketHandler));
        targetContract(address(vrfHandler));
    }

    function test_degenesisWeekHappened() public view {
        _assertDegenesisWeekHappened();
    }
}
