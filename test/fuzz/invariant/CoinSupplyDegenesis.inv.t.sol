// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {DegenesisWeekOpening} from "../helpers/DegenesisWeekOpening.sol";
import {VRFHandler} from "../helpers/VRFHandler.sol";
import {GameHandler} from "../handlers/GameHandler.sol";
import {WhaleHandler} from "../handlers/WhaleHandler.sol";
import {FlipSupplyProbe} from "../handlers/FlipSupplyProbe.sol";
import {CoinSupplyInvariant} from "./CoinSupply.inv.t.sol";

/// @title CoinSupplyDegenesis -- FLIP supply conservation after a real Degenesis week (turbo launch)
/// @notice The campaign starts with the week's batched Degenesis coinflip credits outstanding.
contract CoinSupplyDegenesis is CoinSupplyInvariant, DegenesisWeekOpening {
    function _deployTimestamp() internal pure override(DeployProtocol, DegenesisWeekOpening) returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }

    function _acc(string memory k, uint256 v) internal override returns (uint256) {
        return super._acc(string.concat("DGT_", k), v);
    }

    function setUp() public override {
        _deployProtocol();
        _degenesisWeek(true);
        gameHandler = new GameHandler(game, 10);
        vrfHandler = new VRFHandler(mockVRF, game);
        whaleHandler = new WhaleHandler(game, 5);
        probe = new FlipSupplyProbe(coin, gameHandler, vrfHandler, whaleHandler);
        targetContract(address(probe));
    }

    function test_degenesisWeekHappened() public view {
        _assertDegenesisWeekHappened();
    }
}
