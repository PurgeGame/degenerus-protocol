// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {DegenesisWeekOpening} from "../helpers/DegenesisWeekOpening.sol";
import {FSMHandler} from "../handlers/FSMHandler.sol";
import {GameFSMInvariant} from "./GameFSM.inv.t.sol";

/// @title GameFSMDegenesisTurbo -- the game FSM invariants after a real Degenesis week (turbo launch)
/// @notice Deploys on day index 1, plays a busy Degenesis week whose next pool closes above 50 ETH, so
///         the index-9 request latches the turbo and level 1 plays its one-day jackpot; then the base
///         suite's scripted opening and campaign run on that game. Adds: nothing reopens the sale.
contract GameFSMDegenesisTurbo is GameFSMInvariant, DegenesisWeekOpening {
    function _deployTimestamp() internal pure virtual override(DeployProtocol, DegenesisWeekOpening) returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }

    function _turbo() internal pure virtual returns (bool) {
        return true;
    }

    function _acc(string memory k, uint256 v) internal virtual override returns (uint256) {
        return super._acc(string.concat(_turbo() ? "DGT_" : "DGN_", k), v);
    }

    function setUp() public override {
        _deployProtocol();
        _degenesisWeek(_turbo());

        fsmHandler = new FSMHandler(game, mockVRF, 10);
        fsmHandler.scriptedOpening(OPENING_LEVEL);
        assertGe(game.level(), OPENING_LEVEL, "GameFSM: the scripted opening must reach its level");
        openingPurchases = fsmHandler.ghost_purchases();
        openingAdvances = fsmHandler.ghost_advances();
        openingVrf = fsmHandler.ghost_vrfFulfillments();

        bytes4[] memory sels = new bytes4[](7);
        sels[0] = FSMHandler.purchase.selector;
        sels[1] = FSMHandler.mineFlip.selector;
        sels[2] = FSMHandler.fulfillVrf.selector;
        sels[3] = FSMHandler.recoverAndDrain.selector;
        sels[4] = FSMHandler.warpPastVrfTimeout.selector;
        sels[5] = FSMHandler.warpTime.selector;
        sels[6] = FSMHandler.driveLevelUp.selector;
        targetContract(address(fsmHandler));
        targetSelector(FuzzSelector({addr: address(fsmHandler), selectors: sels}));
    }

    /// @notice After the period nothing reopens or appends to the sale, whatever the FSM does.
    function invariant_degenesisSaleStaysClosed() public view {
        _assertSaleStaysClosed();
    }

    /// @notice The opening is the real sale: every cohort sold, sealed, split, priced, settled and
    ///         closed, inventory burned once, and the launch matches the variant.
    function test_degenesisWeekHappened() public view {
        _assertDegenesisWeekHappened();
    }
}

/// @title GameFSMDegenesisNoTurbo -- the same, after a week whose next pool closes below 50 ETH
/// @notice No turbo at the index-9 request: level 0 continues and the scripted opening raises the level
///         through ordinary play.
contract GameFSMDegenesisNoTurbo is GameFSMDegenesisTurbo {
    function _turbo() internal pure override returns (bool) {
        return false;
    }
}
