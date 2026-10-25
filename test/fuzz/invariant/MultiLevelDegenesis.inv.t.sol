// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {DegenesisWeekOpening} from "../helpers/DegenesisWeekOpening.sol";
import {MultiLevelHandler} from "../handlers/MultiLevelHandler.sol";
import {MultiLevelInvariant} from "./MultiLevel.inv.t.sol";

/// @title MultiLevelDegenesisTurbo -- solvency and level history after a real Degenesis week (turbo)
/// @notice Deploys on day index 1, plays a busy Degenesis week into the turbo level-1 jackpot, then the
///         base suite's opening to level 10 and its campaign.
contract MultiLevelDegenesisTurbo is MultiLevelInvariant, DegenesisWeekOpening {
    uint24 internal levelAtHandoff;

    function _deployTimestamp() internal pure virtual override(DeployProtocol, DegenesisWeekOpening) returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }

    function _turbo() internal pure virtual returns (bool) {
        return true;
    }

    function setUp() public override {
        _deployProtocol();
        _degenesisWeek(_turbo());
        levelAtHandoff = game.currentLvl();
        mlHandler = new MultiLevelHandler(game, mockVRF, 15);
        mlHandler.scriptedOpening();
        assertGe(game.currentLvl(), mlHandler.OPENING_LEVEL(), "MultiLevel: the scripted opening must reach its level");
        targetContract(address(mlHandler));
    }

    /// @notice The opening counts only the levels it raised: from the level the Degenesis week left.
    function test_openingReachesLevelTen() public view override {
        assertGe(uint256(game.currentLvl()), mlHandler.OPENING_LEVEL(), "opening level");
        assertGe(mlHandler.ghost_levelTransitions(), mlHandler.OPENING_LEVEL() - levelAtHandoff, "each level was a recorded transition");
        assertLe(mlHandler.openingDays(), mlHandler.OPENING_MAX_DAYS(), "opening bound");
    }

    function invariant_degenesisSaleStaysClosed() public view {
        _assertSaleStaysClosed();
    }

    function test_degenesisWeekHappened() public view {
        _assertDegenesisWeekHappened();
    }
}

/// @title MultiLevelDegenesisNoTurbo -- the same after a week that closes below 50 ETH
contract MultiLevelDegenesisNoTurbo is MultiLevelDegenesisTurbo {
    function _turbo() internal pure override returns (bool) {
        return false;
    }
}
